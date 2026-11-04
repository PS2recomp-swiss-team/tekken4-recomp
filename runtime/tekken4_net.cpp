/*
 * Adapted from T5DR Online's src/netplay/netplay_core.cpp.
 * MIT License
 * Copyright (c) 2026 TheWishin and the T5DR Online contributors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
// Tekken 4 netplay transport -- see tekken4_net.h. Ported from T5DR Online's src/netplay/netplay_core.cpp (the
// user's own code): the same packet types and redundancy rules, without the lobby/persistent-session/costume/pick
// parts (character select is played in the game, both pads exchanged like any other frame).
//
// Threads: "t4net-rx" (recvfrom, packet handling), "t4net-tick" (handshake HELLOs, PINGs, the stalled resend, the
// silence check), "t4net-sim" (the in-process network simulator's delayed sends). The EE thread calls the rest.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <timeapi.h>

#include "tekken4_net.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <vector>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "winmm.lib")

namespace t4net
{
    namespace
    {
        constexpr uint32_t kMagic = 0x504E3454u; // "T4NP" little-endian
        constexpr uint32_t kRing = 1024;         // frames of input / hash history
        constexpr uint32_t kMaxBatch = 64;       // inputs per packet
        constexpr uint32_t kHashes = 8;          // latest hashes per packet
        constexpr int kTag = 8;                  // SipHash-2-4 tag when keyed
        constexpr int kMaxDelay = 15;

        enum : uint8_t
        {
            PKT_HELLO = 1,
            PKT_INPUT = 2,
            PKT_BYE = 3,
            PKT_PING = 4,
            PKT_REJECT = 5,
        };
        enum : uint8_t
        {
            REJ_BUILD = 1,
            REJ_SESSION = 2,
            REJ_AUTO_VS = 3,
        };
        constexpr uint8_t kNoDelay = 0xFF;

#pragma pack(push, 1)
        struct Hdr
        {
            uint32_t magic;
            uint8_t type, ver, delay, slot;
            uint32_t session;
            uint32_t nonce; // the sender's per-process id
        };
        struct HelloExt
        {
            uint64_t build;
            uint32_t seed;
            uint32_t flags; // bits 8-15: the sender's input delay setting (0xFF auto)
        };
        struct AutoVsHelloExt
        {
            HelloExt hello;
            uint64_t fingerprint;
        };
        struct InputHdr
        {
            uint32_t ack;   // the sender has our inputs for frames < ack
            uint32_t first; // first frame of the inputs that follow
            uint8_t count, nhash;
            int8_t lead;    // the sender's frame advantage estimate
            uint8_t delay;  // the host's input delay pick (0xFF: none yet)
        };
        struct WireIn
        {
            uint16_t buttons;
            uint8_t axes[4];
        };
        struct WireHash
        {
            uint32_t frame;
            uint64_t hash;
        };
        // t_us: the sender's clock; echo_us/hold_us: the t_us of the last PING it got and how long it held it.
        struct PingExt
        {
            uint32_t frame; // the sender's local inputs known for frames < this
            uint32_t t_us, echo_us, hold_us;
            uint8_t delay;  // the host's input delay pick (0xFF: none yet)
        };
#pragma pack(pop)

        uint64_t qpcUs()
        {
            static const double inv = []
            {
                LARGE_INTEGER f;
                QueryPerformanceFrequency(&f);
                return 1e6 / static_cast<double>(f.QuadPart);
            }();
            LARGE_INTEGER t;
            QueryPerformanceCounter(&t);
            return static_cast<uint64_t>(static_cast<double>(t.QuadPart) * inv);
        }
        uint64_t nowMs() { return qpcUs() / 1000u; }

        inline uint64_t rotl64(uint64_t x, int b) { return (x << b) | (x >> (64 - b)); }
        uint64_t siphash24(const uint8_t key[16], const uint8_t *in, size_t len)
        {
            uint64_t k0, k1;
            std::memcpy(&k0, key, 8);
            std::memcpy(&k1, key + 8, 8);
            uint64_t v0 = 0x736f6d6570736575ull ^ k0, v1 = 0x646f72616e646f6dull ^ k1;
            uint64_t v2 = 0x6c7967656e657261ull ^ k0, v3 = 0x7465646279746573ull ^ k1;
            auto round = [&]()
            {
                v0 += v1; v1 = rotl64(v1, 13); v1 ^= v0; v0 = rotl64(v0, 32);
                v2 += v3; v3 = rotl64(v3, 16); v3 ^= v2;
                v0 += v3; v3 = rotl64(v3, 21); v3 ^= v0;
                v2 += v1; v1 = rotl64(v1, 17); v1 ^= v2; v2 = rotl64(v2, 32);
            };
            const size_t end = len - (len % 8);
            for (size_t i = 0; i < end; i += 8)
            {
                uint64_t m;
                std::memcpy(&m, in + i, 8);
                v3 ^= m; round(); round(); v0 ^= m;
            }
            uint64_t b = static_cast<uint64_t>(len) << 56;
            for (size_t i = 0; i < len % 8; i++)
                b |= static_cast<uint64_t>(in[end + i]) << (8 * i);
            v3 ^= b; round(); round(); v0 ^= b;
            v2 ^= 0xff;
            round(); round(); round(); round();
            return v0 ^ v1 ^ v2 ^ v3;
        }

        struct Ring
        {
            PadInput in[kRing];
            uint32_t inTag[kRing]{}; // frame + 1 when in[] holds that frame
            uint64_t hash[kRing]{};
            uint32_t hashTag[kRing]{};
        };

        struct SimPacket
        {
            uint64_t dueUs = 0;
            std::vector<uint8_t> bytes;
            sockaddr_in to{};
        };

        struct State
        {
            std::mutex mu;
            std::condition_variable rx; // something arrived (inputs, hashes, handshake)
            Config cfg;
            bool on = false;
            SOCKET sock = INVALID_SOCKET;
            sockaddr_in peer{};
            bool peerKnown = false, envPeer = false;
            bool keyed = false;
            bool strictHello = false;
            bool matchDelay = false;
            uint8_t netVersion = kNetVersion;
            in_addr expectedPeerIp{}; // original configured peer, unaffected by address rebinding
            uint8_t key[16]{};
            uint32_t session = 0, nonce = 0, peerNonce = 0;
            uint32_t seed = 0;
            uint64_t peerBuild = 0;
            int delay = 0;             // agreed input delay (-1 until agreed)
            int decided = -1;          // host: its pick; join: the host's pick once received
            int peerDelaySetting = -1; // from its HELLO
            bool connected = false, lost = false, sentInputs = false, peerSentInputs = false;
            std::string failReason, lostReason;
            uint64_t startMs = 0, lastRxMs = 0, lastSendMs = 0, lastHelloMs = 0, lastPingMs = 0, connectMs = 0;
            // TEKKEN4_NET_COALESCE=1: only redundant sendNow calls may be skipped. Protected by mu.
            bool coalesce = false;
            std::array<uint8_t, sizeof(Hdr) + sizeof(InputHdr) + kMaxBatch * sizeof(WireIn) + kHashes * sizeof(WireHash)> lastInput{};
            size_t lastInputBytes = 0;
            sockaddr_in lastInputPeer{};
            uint32_t lastInputPeerNonce = 0;
            uint64_t lastInputMs = 0;
            uint32_t base = 0;         // frames < base are neutral (both sides)
            Ring local, remote;
            uint32_t localMax = 0, remoteContig = 0, peerAck = 0;
            int8_t localLead = 0, peerLeadV = 0;
            // TEKKEN4_NET_LIVE_LEAD=1: sample pacing feedback with the outgoing input frontiers.
            bool liveLead = false, leadReady = false;
            int8_t leadSendCached = 0, leadSendFresh = 0;
            uint64_t leadSendDiff = 0, leadSendChanged = 0;
            int leadSendDeltaMax = 0;
            // TEKKEN4_NET_ORDERED_LEAD=1: ignore regressing pacing metadata, not inputs.
            bool orderedLead = false;
            uint32_t peerLeadAck = 0, peerLeadEnd = 0;
            uint64_t leadStale = 0, leadStaleDiff = 0, leadRejected = 0;
            uint32_t localHashMax = 0, remoteHashMax = 0, checked = 0, compared = 0, mismatches = 0;
            std::deque<std::array<uint64_t, 3>> mismatchQueue;
            // per hashed frame: 1 = both hashes known and equal, -1 = different (tag = frame + 1)
            int8_t verdict[kRing]{};
            uint32_t verdictTag[kRing]{};
            // round trip
            float rtt[32]{};
            uint32_t nrtt = 0;
            uint32_t peerPingUs = 0;
            uint64_t peerPingRxUs = 0;
            Stats st;
            uint32_t strangers = 0;
            // TEKKEN4_NET_DIAG=1: wall-clock transport diagnostics, no wire/simulation changes.
            bool diag = false, simSafeWait = false;
            // Only the simulator worker's relative thread priority changes; packet scheduling stays the same.
            bool simNormalPriority = false;
            std::atomic<bool> simPriorityReady{false}, simPriorityOk{false};
            std::atomic<int> simThreadPriority{0};
            std::atomic<uint64_t> simSpinCalls{0}, simSpinUs{0}, simSpinMaxUs{0}, simSendCalls{0},
                                  simLateMaxUs{0}, simLateOver2ms{0};
            uint64_t diagLastUs = 0, diagTickUs = 0, diagTickGapUs = 0, diagRxWaitUs = 0;
            uint64_t diagInputUs = 0, diagInputGapUs = 0, diagProgressUs = 0;
            uint64_t diagLocalUs = 0, diagLocalGapUs = 0;
            uint32_t diagLeadEnd = 0, diagLeadEndMax = 0;
            uint64_t diagLeadBack = 0, diagLeadEndUs = 0;
            std::atomic<uint64_t> diagSimLateUs{0}, diagSimLateCount{0}, diagSimDepth{0};
            FILE *log = nullptr;
            std::mutex logMu;
            // simulator
            std::mutex simMu;
            std::condition_variable simCv;
            std::deque<SimPacket> simQueue;
            std::mt19937_64 simRng;
            bool sim = false;
            bool stop = false;
        };

        State &S()
        {
            static State *s = new State(); // never destroyed: threads may still run at exit
            return *s;
        }

        std::string addrText(const sockaddr_in &a)
        {
            char ip[64] = "?";
            inet_ntop(AF_INET, &a.sin_addr, ip, sizeof ip);
            return std::string(ip) + ":" + std::to_string(ntohs(a.sin_port));
        }

        bool sameAddr(const sockaddr_in &a, const sockaddr_in &b)
        {
            return a.sin_addr.s_addr == b.sin_addr.s_addr && a.sin_port == b.sin_port;
        }

        void vnote(const char *fmt, va_list ap)
        {
            State &s = S();
            char buf[1024];
            std::vsnprintf(buf, sizeof buf, fmt, ap);
            std::lock_guard<std::mutex> lk(s.logMu);
            const double t = static_cast<double>(nowMs() - s.startMs) / 1000.0;
            if (s.log)
            {
                std::fprintf(s.log, "[%8.3f] %s\n", t, buf);
                std::fflush(s.log);
            }
            std::fprintf(stderr, "[t4net] %s\n", buf);
        }

        // Raw send (the simulator's thread, or at once).
        void sendWire(const uint8_t *p, int n, const sockaddr_in &to)
        {
            State &s = S();
            if (s.sock == INVALID_SOCKET)
                return;
            sendto(s.sock, reinterpret_cast<const char *>(p), n, 0, reinterpret_cast<const sockaddr *>(&to), sizeof to);
        }

        // Caller holds mu. Appends the tag when keyed; through the simulator when on.
        void sendTo(const void *p, int n, const sockaddr_in *to = nullptr)
        {
            State &s = S();
            if (s.sock == INVALID_SOCKET)
                return;
            if (!to)
            {
                if (!s.peerKnown)
                    return;
                to = &s.peer;
            }
            uint8_t buf[2048];
            if (n + kTag > static_cast<int>(sizeof buf))
                return;
            std::memcpy(buf, p, static_cast<size_t>(n));
            if (s.keyed)
            {
                const uint64_t t = siphash24(s.key, buf, static_cast<size_t>(n));
                std::memcpy(buf + n, &t, kTag);
                n += kTag;
            }
            s.st.packetsOut++;
            s.st.bytesOut += static_cast<uint64_t>(n);
            if (!s.sim)
            {
                sendWire(buf, n, *to);
                return;
            }
            std::lock_guard<std::mutex> lk(s.simMu);
            std::uniform_real_distribution<double> uni(0.0, 1.0);
            if (uni(s.simRng) * 100.0 < s.cfg.simLossPercent)
            {
                s.st.simDropped++;
                return;
            }
            double ms = s.cfg.simLatencyMs;
            if (s.cfg.simJitterMs > 0)
                ms += (uni(s.simRng) * 2.0 - 1.0) * s.cfg.simJitterMs;
            SimPacket packet;
            packet.dueUs = qpcUs() + static_cast<uint64_t>(std::max(0.0, ms) * 1000.0);
            packet.bytes.assign(buf, buf + n);
            packet.to = *to;
            // keep the queue ordered by due time (jitter may reorder packets, as a real path can)
            auto it = s.simQueue.end();
            while (it != s.simQueue.begin() && std::prev(it)->dueUs > packet.dueUs)
                --it;
            s.simQueue.insert(it, std::move(packet));
            if (s.diag && s.simQueue.size() > s.diagSimDepth.load(std::memory_order_relaxed))
                s.diagSimDepth.store(s.simQueue.size(), std::memory_order_relaxed);
            s.simCv.notify_one();
        }

        Hdr makeHdr(uint8_t type)
        {
            State &s = S();
            return {kMagic, type, s.netVersion, static_cast<uint8_t>(std::max(0, s.delay)),
                    static_cast<uint8_t>(s.cfg.role == Role::Host ? 0 : 1), s.session, s.nonce};
        }

        uint8_t delayWire()
        {
            const State &s = S();
            return s.cfg.role == Role::Host && s.decided >= 0 ? static_cast<uint8_t>(s.decided) : kNoDelay;
        }

        void sendHelloLocked(const sockaddr_in *to = nullptr)
        {
            State &s = S();
            const HelloExt hello = {
                s.cfg.buildId, s.seed,
                static_cast<uint32_t>((s.cfg.delaySetting < 0 ? 0xFFu : static_cast<uint32_t>(s.cfg.delaySetting)) << 8)};
            if (s.cfg.autoVsFingerprint)
            {
                struct
                {
                    Hdr h;
                    AutoVsHelloExt x;
                } p = {makeHdr(PKT_HELLO), {hello, s.cfg.autoVsFingerprint}};
                sendTo(&p, sizeof p, to);
                s.lastHelloMs = nowMs();
                return;
            }
            struct
            {
                Hdr h;
                HelloExt x;
            } p = {makeHdr(PKT_HELLO), hello};
            sendTo(&p, sizeof p, to);
            s.lastHelloMs = nowMs();
        }

        void sendPingLocked()
        {
            State &s = S();
            const uint64_t now = qpcUs();
            struct
            {
                Hdr h;
                PingExt x;
            } p = {makeHdr(PKT_PING),
                   {s.localMax, static_cast<uint32_t>(now), s.peerPingUs,
                    s.peerPingUs ? static_cast<uint32_t>(now - s.peerPingRxUs) : 0u, delayWire()}};
            sendTo(&p, sizeof p);
            s.lastPingMs = s.lastSendMs = nowMs();
        }

        void sendRejectLocked(const sockaddr_in &to, uint8_t why)
        {
            struct
            {
                Hdr h;
                uint8_t why;
            } p = {makeHdr(PKT_REJECT), why};
            sendTo(&p, sizeof p, &to);
        }

        // Every input the peer may still need (from its ack, at least the last 8), plus our latest hashes.
        void sendInputsLocked(bool allowCoalesce = false)
        {
            State &s = S();
            if (!s.connected || s.lost)
                return;
            uint8_t buf[sizeof(Hdr) + sizeof(InputHdr) + kMaxBatch * sizeof(WireIn) + kHashes * sizeof(WireHash)];
            Hdr *h = reinterpret_cast<Hdr *>(buf);
            *h = makeHdr(PKT_INPUT);
            InputHdr *ih = reinterpret_cast<InputHdr *>(h + 1);
            uint32_t first = s.peerAck;
            if (s.localMax >= 8 && first > s.localMax - 8)
                first = s.localMax - 8;
            if (first < s.base)
                first = s.base;
            uint32_t count = s.localMax > first ? s.localMax - first : 0;
            if (count > kMaxBatch)
                count = kMaxBatch;
            ih->ack = s.remoteContig;
            ih->first = first;
            ih->count = static_cast<uint8_t>(count);
            // setLead runs once per live frame, after its first sends. Resends during rollback or waits
            // can otherwise keep advertising that old value while received input advances.
            const int64_t gap = static_cast<int64_t>(s.localMax) - static_cast<int64_t>(s.remoteContig);
            const int8_t freshLead = s.leadReady
                                         ? static_cast<int8_t>(std::max<int64_t>(-100, std::min<int64_t>(100, gap)))
                                         : s.localLead; // keep startup metadata until the first live estimate
            ih->lead = s.liveLead ? freshLead : s.localLead;
            ih->delay = delayWire();
            WireIn *wi = reinterpret_cast<WireIn *>(ih + 1);
            for (uint32_t i = 0; i < count; i++)
            {
                const PadInput &in = s.local.in[(first + i) % kRing];
                wi[i].buttons = in.buttons;
                std::memcpy(wi[i].axes, in.axes, 4);
            }
            WireHash *wh = reinterpret_cast<WireHash *>(wi + count);
            uint32_t nh = 0;
            // the latest kHashes pushed hashes (they are sparse: every N frames)
            for (uint32_t back = 0, f = s.localHashMax; f > 0 && back < kRing && nh < kHashes; --f, ++back)
                if (s.local.hashTag[(f - 1) % kRing] == f)
                {
                    wh[nh].frame = f - 1;
                    wh[nh].hash = s.local.hash[(f - 1) % kRing];
                    ++nh;
                }
            ih->nhash = static_cast<uint8_t>(nh);
            const size_t bytes = static_cast<size_t>(reinterpret_cast<uint8_t *>(wh + nh) - buf);
            if (s.coalesce && allowCoalesce && s.lastInputBytes == bytes &&
                s.lastInputPeerNonce == s.peerNonce && sameAddr(s.lastInputPeer, s.peer) &&
                std::memcmp(s.lastInput.data(), buf, bytes) == 0 && nowMs() - s.lastInputMs < 15)
            {
                ++s.st.coalesced;
                return; // keep the resend deadline: a skipped call is not a send attempt
            }
            if (s.diag)
            {
                s.leadSendCached = s.localLead;
                s.leadSendFresh = freshLead;
                const int delta = std::abs(static_cast<int>(freshLead) - static_cast<int>(s.localLead));
                if (delta)
                {
                    ++s.leadSendDiff;
                    if (s.liveLead)
                        ++s.leadSendChanged;
                    s.leadSendDeltaMax = std::max(s.leadSendDeltaMax, delta);
                }
            }
            sendTo(buf, static_cast<int>(bytes));
            s.lastSendMs = nowMs();
            if (s.coalesce)
            {
                std::memcpy(s.lastInput.data(), buf, bytes);
                s.lastInputBytes = bytes;
                s.lastInputPeer = s.peer;
                s.lastInputPeerNonce = s.peerNonce;
                s.lastInputMs = s.lastSendMs;
            }
            s.sentInputs = s.sentInputs || count > 0;
        }

        void compareHashesLocked()
        {
            State &s = S();
            for (;;)
            {
                const uint32_t f = s.checked, i = f % kRing;
                if (f >= s.localHashMax)
                    break;
                if (s.local.hashTag[i] != f + 1)
                {
                    s.checked++;
                    continue;
                }
                if (s.remote.hashTag[i] != f + 1)
                {
                    // not here yet -- or never (packets carry the latest few): give up once far past it
                    if (s.localHashMax - f > kRing / 2 || s.remoteHashMax > f + 1 + 512)
                    {
                        s.checked++;
                        continue;
                    }
                    break;
                }
                s.compared++;
                s.verdictTag[i] = f + 1;
                s.verdict[i] = s.local.hash[i] == s.remote.hash[i] ? 1 : -1;
                if (s.local.hash[i] != s.remote.hash[i])
                {
                    if (s.mismatches < 10)
                    {
                        // (vnote takes logMu, not mu)
                        char text[160];
                        std::snprintf(text, sizeof text, "DESYNC at frame %u: local state hash %016llx, peer %016llx", f,
                                      static_cast<unsigned long long>(s.local.hash[i]),
                                      static_cast<unsigned long long>(s.remote.hash[i]));
                        note("%s", text);
                    }
                    s.mismatches++;
                    if (s.mismatchQueue.size() < 64)
                        s.mismatchQueue.push_back({f, s.local.hash[i], s.remote.hash[i]});
                }
                s.checked++;
            }
        }

        void failLocked(const char *reason, const std::string &text)
        {
            State &s = S();
            if (!s.failReason.empty())
                return;
            s.failReason = reason;
            s.lost = true;
            note("cannot connect (%s): %s", reason, text.c_str());
            s.rx.notify_all();
        }

        void loseLocked(const char *reason, const std::string &text)
        {
            State &s = S();
            if (s.lost)
                return;
            s.lostReason = reason;
            s.lost = true;
            note("peer lost (%s): %s", reason, text.c_str());
            s.rx.notify_all();
        }

        void connectLocked()
        {
            State &s = S();
            if (s.connected)
                return;
            s.connected = true;
            s.connectMs = s.lastRxMs = nowMs();
            note("connected (%s), peer %s, session %08x, seed %08x%s", s.cfg.role == Role::Host ? "host, P1" : "join, P2",
                 addrText(s.peer).c_str(), s.session, s.seed, s.keyed ? ", packets authenticated" : "");
            s.rx.notify_all();
        }

        void handlePacket(const uint8_t *p, int n, const sockaddr_in &from)
        {
            State &s = S();
            if (n < static_cast<int>(sizeof(Hdr)))
                return;
            Hdr h;
            std::memcpy(&h, p, sizeof h);
            if (h.magic != kMagic)
                return;
            const int payloadBytes = n; // keep the authentication tag in the byte count
            const uint64_t lockUs = s.diag ? qpcUs() : 0;
            std::lock_guard<std::mutex> lk(s.mu);
            if (s.diag)
                s.diagRxWaitUs = std::max(s.diagRxWaitUs, qpcUs() - lockUs);
            if (h.ver != s.netVersion)
            {
                // A foreign HELLO must prove it belongs to this match before it can cancel it.
                // T5DR Online fixed the same pre-authentication failure (NETPLAY.md, Connection problems).
                const bool checkedHello = s.strictHello || s.cfg.autoVsFingerprint;
                bool trusted = !checkedHello;
                if (checkedHello && s.keyed && n >= static_cast<int>(sizeof(Hdr)) + kTag)
                {
                    uint64_t tag;
                    std::memcpy(&tag, p + n - kTag, kTag);
                    trusted = tag == siphash24(s.key, p, static_cast<size_t>(n - kTag));
                }
                else if (checkedHello && !s.keyed)
                    trusted = s.envPeer ? from.sin_addr.s_addr == s.expectedPeerIp.s_addr
                                        : s.peerKnown && sameAddr(from, s.peer);
                if (!s.connected && h.type == PKT_HELLO && trusted)
                    failLocked("build_mismatch", addrText(from) + " speaks netplay protocol v" + std::to_string(h.ver) +
                                                     ", this game v" + std::to_string(s.netVersion) +
                                                     "; check AUTO_VS, STRICT_HELLO and DELAY_MATCH on both PCs");
                return;
            }
            if (s.keyed)
            {
                if (n < static_cast<int>(sizeof(Hdr)) + kTag)
                    return;
                n -= kTag;
                uint64_t t;
                std::memcpy(&t, p + n, kTag);
                if (t != siphash24(s.key, p, static_cast<size_t>(n)))
                {
                    if (s.strangers++ < 5)
                        note("packet from %s with a wrong authentication tag dropped", addrText(from).c_str());
                    return;
                }
            }
            const bool fromPeer = s.peerKnown && sameAddr(from, s.peer);
            const bool trustedSource = s.keyed || !s.envPeer || from.sin_addr.s_addr == s.expectedPeerIp.s_addr;
            if (h.type == PKT_HELLO)
            {
                if (n < static_cast<int>(sizeof(Hdr) + sizeof(HelloExt)))
                    return;
                if ((s.strictHello || s.cfg.autoVsFingerprint) && ((!s.connected && !trustedSource) ||
                                      (s.connected && !s.keyed && !fromPeer)))
                    return;
                HelloExt x;
                std::memcpy(&x, p + sizeof(Hdr), sizeof x);
                if (s.cfg.autoVsFingerprint)
                {
                    if (n < static_cast<int>(sizeof(Hdr) + sizeof(AutoVsHelloExt)))
                        return;
                    AutoVsHelloExt boot;
                    std::memcpy(&boot, p + sizeof(Hdr), sizeof boot);
                    if (boot.fingerprint != s.cfg.autoVsFingerprint)
                    {
                        if (!s.connected)
                        {
                            sendRejectLocked(from, REJ_AUTO_VS);
                            failLocked("auto_vs_mismatch", addrText(from) +
                                       " has different boot/native-name settings; use the same settings on both PCs");
                        }
                        return;
                    }
                }
                const uint32_t ds = (x.flags >> 8) & 0xFFu;
                if ((s.strictHello || s.matchDelay || s.cfg.autoVsFingerprint) && (h.slot != (s.cfg.role == Role::Host ? 1 : 0) || !h.nonce ||
                                                        (s.cfg.role == Role::Join && !h.session) ||
                                                        (ds != 0xFFu && ds > static_cast<uint32_t>(kMaxDelay))))
                    return; // malformed HELLO cannot establish or restart a session
                if ((x.build && s.cfg.buildId && x.build != s.cfg.buildId) ||
                    (s.strictHello && (!x.build || !s.cfg.buildId)))
                {
                    if (!s.connected)
                    {
                        sendRejectLocked(from, REJ_BUILD);
                        char text[200];
                        std::snprintf(text, sizeof text, "%s runs a different build (build id %016llx, ours %016llx)",
                                      addrText(from).c_str(), static_cast<unsigned long long>(x.build),
                                      static_cast<unsigned long long>(s.cfg.buildId));
                        failLocked("build_mismatch", text);
                    }
                    return;
                }
                if (s.connected && h.nonce != s.peerNonce)
                {
                    if (!s.peerSentInputs && !s.sentInputs)
                    {
                        note("the opponent's game was restarted before the match began (%s); connecting to the new one",
                             addrText(from).c_str());
                        s.connected = false;
                        s.peerNonce = 0;
                    }
                    else
                    {
                        sendRejectLocked(from, REJ_SESSION);
                        loseLocked("peer_restarted", "the opponent's game restarted in the middle of the match");
                        return;
                    }
                }
                if (s.connected)
                {
                    s.lastRxMs = nowMs();
                    if (s.cfg.role == Role::Host)
                        sendHelloLocked();
                    return;
                }
                s.peerBuild = x.build;
                s.peerDelaySetting = ds == 0xFFu ? -1 : static_cast<int>(ds);
                if (s.cfg.role == Role::Host)
                {
                    if (!s.peerKnown || !fromPeer || s.peerNonce != h.nonce)
                        note("peer %s says hello", addrText(from).c_str());
                    s.peer = from;
                    s.peerKnown = true;
                    s.peerNonce = h.nonce;
                    sendHelloLocked();
                    if (h.session == s.session)
                        connectLocked();
                }
                else
                {
                    s.session = h.session;
                    s.seed = x.seed;
                    s.peer = from;
                    s.peerKnown = true;
                    s.peerNonce = h.nonce;
                    connectLocked();
                    sendHelloLocked(); // echoes the session: completes the host's handshake
                }
                return;
            }
            if (h.type == PKT_REJECT)
            {
                if ((s.strictHello || s.cfg.autoVsFingerprint) && !s.keyed &&
                    !(s.envPeer ? from.sin_addr.s_addr == s.expectedPeerIp.s_addr : fromPeer))
                    return;
                if (s.connected && h.nonce != s.peerNonce)
                    return;
                const uint8_t why = n >= static_cast<int>(sizeof(Hdr) + 1) ? p[sizeof(Hdr)] : 0;
                if (why == REJ_BUILD)
                {
                    if (!s.connected)
                        failLocked("build_mismatch", addrText(from) + " refused us: it runs a different build");
                }
                else if (why == REJ_AUTO_VS)
                {
                    if (!s.connected)
                        failLocked("auto_vs_mismatch", addrText(from) + " refused us: boot/native-name settings differ");
                }
                else if (!s.connected)
                    failLocked("rejected", addrText(from) + " is playing another session");
                else
                    loseLocked("peer_restarted", "the opponent's game no longer knows this session");
                return;
            }
            if (h.session != s.session)
                return;
            if (!s.connected)
            {
                // the joiner's session echo was lost, but its packets carry our session id
                if (s.cfg.role != Role::Host || h.type == PKT_BYE)
                    return;
                // New policies need a checked HELLO first: its build in strict mode, its setting in match mode.
                if ((s.strictHello || s.matchDelay || s.cfg.autoVsFingerprint) &&
                    (!s.peerNonce || h.nonce != s.peerNonce || (!s.keyed && !fromPeer)))
                    return;
                if (s.peerNonce && h.nonce != s.peerNonce)
                    return;
                s.peer = from;
                s.peerKnown = true;
                s.peerNonce = h.nonce;
                connectLocked();
            }
            if (h.nonce != s.peerNonce)
                return;
            if (!fromPeer)
            {
                if (s.strangers++ < 5)
                    note("the peer's address changed from %s to %s -- following it", addrText(s.peer).c_str(),
                         addrText(from).c_str());
                s.peer = from;
            }
            s.st.packetsIn++;
            s.st.bytesIn += static_cast<uint64_t>(payloadBytes);
            s.lastRxMs = nowMs();
            if (h.type == PKT_BYE)
            {
                loseLocked("peer_quit", "the opponent left (its game was closed)");
                return;
            }
            if (h.type == PKT_PING)
            {
                if (n >= static_cast<int>(sizeof(Hdr) + sizeof(PingExt)))
                {
                    PingExt x;
                    std::memcpy(&x, p + sizeof(Hdr), sizeof x);
                    const uint64_t now = qpcUs();
                    if (x.echo_us)
                    {
                        const uint32_t rttUs = static_cast<uint32_t>(now) - x.echo_us - x.hold_us;
                        if (rttUs < 2000000u)
                            s.rtt[s.nrtt++ % 32] = static_cast<float>(rttUs) / 1000.0f;
                    }
                    s.peerPingUs = x.t_us;
                    s.peerPingRxUs = now;
                    if (x.delay != kNoDelay && s.cfg.role == Role::Join && s.decided < 0)
                        s.decided = x.delay;
                }
                s.rx.notify_all();
                return;
            }
            if (h.type != PKT_INPUT || n < static_cast<int>(sizeof(Hdr) + sizeof(InputHdr)))
                return;
            InputHdr ih;
            std::memcpy(&ih, p + sizeof(Hdr), sizeof ih);
            if (n < static_cast<int>(sizeof(Hdr) + sizeof(InputHdr) + ih.count * sizeof(WireIn) + ih.nhash * sizeof(WireHash)))
                return;
            if (ih.count)
                s.peerSentInputs = true;
            if (s.diag)
            {
                const uint64_t now = qpcUs();
                if (s.diagInputUs)
                    s.diagInputGapUs = std::max(s.diagInputGapUs, now - s.diagInputUs);
                s.diagInputUs = now;
                s.diagLeadEnd = ih.first + ih.count; // sender frontier; may be batch-limited if >64 inputs unacked
                if (s.diagLeadEnd < s.diagLeadEndMax)
                    ++s.diagLeadBack;
                if (s.diagLeadEnd > s.diagLeadEndMax)
                    s.diagLeadEndUs = now;
                s.diagLeadEndMax = std::max(s.diagLeadEndMax, s.diagLeadEnd);
            }
            if (ih.ack > s.peerAck)
                s.peerAck = ih.ack;
            // Both fields are nondecreasing at the sender. Jitter can deliver an older
            // packet after a newer one; its inputs/hashes still matter, its lead may not.
            // Equal-frontier packets cannot be ordered without a wire sequence number.
            const uint32_t leadEnd = ih.first + ih.count;
            const bool staleLead = ih.ack < s.peerLeadAck || leadEnd < s.peerLeadEnd;
            if (staleLead)
            {
                ++s.leadStale;
                if (ih.lead != s.peerLeadV)
                    ++s.leadStaleDiff;
            }
            if (s.orderedLead && staleLead)
                ++s.leadRejected;
            else
                s.peerLeadV = ih.lead;
            s.peerLeadAck = std::max(s.peerLeadAck, ih.ack);
            s.peerLeadEnd = std::max(s.peerLeadEnd, leadEnd);
            if (ih.delay != kNoDelay && s.cfg.role == Role::Join && s.decided < 0)
                s.decided = ih.delay;
            const uint8_t *at = p + sizeof(Hdr) + sizeof(InputHdr);
            for (uint32_t k = 0; k < ih.count; k++, at += sizeof(WireIn))
            {
                const uint32_t f = ih.first + k;
                if (f < s.remoteContig || f >= s.remoteContig + kRing / 2)
                    continue;
                WireIn w;
                std::memcpy(&w, at, sizeof w);
                const uint32_t i = f % kRing;
                s.remote.in[i].buttons = w.buttons;
                std::memcpy(s.remote.in[i].axes, w.axes, 4);
                s.remote.inTag[i] = f + 1;
            }
            const uint32_t beforeContig = s.remoteContig;
            while (s.remote.inTag[s.remoteContig % kRing] == s.remoteContig + 1)
                s.remoteContig++;
            if (s.diag && s.remoteContig != beforeContig)
                s.diagProgressUs = qpcUs();
            for (uint32_t k = 0; k < ih.nhash; k++, at += sizeof(WireHash))
            {
                WireHash w;
                std::memcpy(&w, at, sizeof w);
                const uint32_t i = w.frame % kRing;
                s.remote.hash[i] = w.hash;
                s.remote.hashTag[i] = w.frame + 1;
                if (w.frame + 1 > s.remoteHashMax)
                    s.remoteHashMax = w.frame + 1;
            }
            compareHashesLocked();
            s.rx.notify_all();
        }

        void rxThread()
        {
            State &s = S();
            const BOOL priorityOk = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
            if (s.diag)
                note("NETDIAG thread=rx priority=%d set_ok=%d", GetThreadPriority(GetCurrentThread()), priorityOk);
            uint8_t buf[2048];
            for (;;)
            {
                sockaddr_in from{};
                int fl = sizeof from;
                const int n = recvfrom(s.sock, reinterpret_cast<char *>(buf), sizeof buf, 0,
                                       reinterpret_cast<sockaddr *>(&from), &fl);
                if (n > 0)
                {
                    handlePacket(buf, n, from);
                    continue;
                }
                if (n == SOCKET_ERROR)
                {
                    const int e = WSAGetLastError();
                    if (e == WSAECONNRESET || e == WSAEMSGSIZE || e == WSAEINTR)
                        continue; // (ICMP port unreachable before the peer is up)
                    note("recvfrom failed (%d); receive thread stops", e);
                    return;
                }
            }
        }

        void simThread()
        {
            State &s = S();
            const int requested = s.simNormalPriority ? THREAD_PRIORITY_NORMAL : THREAD_PRIORITY_HIGHEST;
            const BOOL priorityOk = SetThreadPriority(GetCurrentThread(), requested);
            const int reported = GetThreadPriority(GetCurrentThread());
            s.simPriorityOk.store(priorityOk != FALSE, std::memory_order_relaxed);
            s.simThreadPriority.store(reported, std::memory_order_relaxed);
            s.simPriorityReady.store(true, std::memory_order_release);
            note("NETSIMPRIO_START normal_priority=%d requested_priority=%d thread_priority=%d set_ok=%d",
                 s.simNormalPriority, requested, reported, priorityOk);
            if (s.diag)
                note("NETDIAG thread=sim priority=%d set_ok=%d", reported, priorityOk);
            std::unique_lock<std::mutex> lk(s.simMu);
            for (;;)
            {
                if (s.simQueue.empty())
                {
                    s.simCv.wait(lk);
                    continue;
                }
                const uint64_t now = qpcUs();
                SimPacket &front = s.simQueue.front();
                if (front.dueUs > now)
                {
                    const uint64_t wait = front.dueUs - now;
                    if (wait > 1500)
                        s.simCv.wait_for(lk, std::chrono::microseconds(wait - 1000));
                    else
                    {
                        // A sorted middle insertion by sendTo invalidates deque references. The opt-in fix
                        // holds only a value while unlocked, then rechecks the queue under simMu.
                        const uint64_t dueUs = front.dueUs;
                        lk.unlock();
                        const uint64_t spinStart = qpcUs();
                        while (qpcUs() < (s.simSafeWait ? dueUs : front.dueUs))
                            std::this_thread::yield();
                        const uint64_t spinUs = qpcUs() - spinStart;
                        s.simSpinCalls.fetch_add(1, std::memory_order_relaxed);
                        s.simSpinUs.fetch_add(spinUs, std::memory_order_relaxed);
                        if (spinUs > s.simSpinMaxUs.load(std::memory_order_relaxed))
                            s.simSpinMaxUs.store(spinUs, std::memory_order_relaxed);
                        lk.lock();
                    }
                    continue;
                }
                SimPacket packet = std::move(front);
                s.simQueue.pop_front();
                lk.unlock();
                const uint64_t late = qpcUs() - packet.dueUs;
                if (late > s.simLateMaxUs.load(std::memory_order_relaxed))
                    s.simLateMaxUs.store(late, std::memory_order_relaxed);
                if (late >= 2000)
                    s.simLateOver2ms.fetch_add(1, std::memory_order_relaxed);
                if (s.diag)
                {
                    if (late > s.diagSimLateUs.load(std::memory_order_relaxed))
                        s.diagSimLateUs.store(late, std::memory_order_relaxed);
                    if (late >= 2000)
                        s.diagSimLateCount.fetch_add(1, std::memory_order_relaxed);
                }
                s.simSendCalls.fetch_add(1, std::memory_order_relaxed);
                sendWire(packet.bytes.data(), static_cast<int>(packet.bytes.size()), packet.to);
                lk.lock();
            }
        }

        void tickThread()
        {
            State &s = S();
            const BOOL priorityOk = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_ABOVE_NORMAL);
            if (s.diag)
                note("NETDIAG thread=tick priority=%d set_ok=%d process_class=%lu", GetThreadPriority(GetCurrentThread()),
                     priorityOk, static_cast<unsigned long>(GetPriorityClass(GetCurrentProcess())));
            uint64_t lastWaitNote = 0;
            for (;;)
            {
                Sleep(5);
                std::lock_guard<std::mutex> lk(s.mu);
                const uint64_t now = nowMs();
                if (s.diag)
                {
                    const uint64_t us = qpcUs();
                    if (s.diagTickUs)
                        s.diagTickGapUs = std::max(s.diagTickGapUs, us - s.diagTickUs);
                    s.diagTickUs = us;
                    if (us - s.diagLastUs >= 1000000)
                    {
                        s.diagLastUs = us;
                        note("NETDIAG local=%u remote=%u ack=%u lead=%d peer_lead=%d lead_end=%u lead_end_max=%u lead_back=%llu lead_end_age_ms=%.1f input_age_ms=%.1f progress_age_ms=%.1f "
                             "local_age_ms=%.1f local_gap_ms=%.1f input_gap_ms=%.1f rx_lock_ms=%.1f tick_gap_ms=%.1f sim_late_ms=%.1f sim_late_n=%llu sim_depth=%llu "
                             "lead_ordered=%d lead_ack_max=%u lead_end_high=%u lead_stale=%llu lead_stale_diff=%llu lead_rejected=%llu",
                             s.localMax, s.remoteContig, s.peerAck, s.localLead, s.peerLeadV,
                             s.diagLeadEnd, s.diagLeadEndMax, static_cast<unsigned long long>(s.diagLeadBack),
                             s.diagLeadEndUs ? (us - s.diagLeadEndUs) / 1000.0 : -1.0,
                             s.diagInputUs ? (us - s.diagInputUs) / 1000.0 : -1.0,
                             s.diagProgressUs ? (us - s.diagProgressUs) / 1000.0 : -1.0,
                             s.diagLocalUs ? (us - s.diagLocalUs) / 1000.0 : -1.0,
                             s.diagLocalGapUs / 1000.0, s.diagInputGapUs / 1000.0, s.diagRxWaitUs / 1000.0,
                             s.diagTickGapUs / 1000.0, s.diagSimLateUs.exchange(0, std::memory_order_relaxed) / 1000.0,
                             static_cast<unsigned long long>(s.diagSimLateCount.exchange(0, std::memory_order_relaxed)),
                             static_cast<unsigned long long>(s.diagSimDepth.exchange(0, std::memory_order_relaxed)),
                             s.orderedLead, s.peerLeadAck, s.peerLeadEnd,
                             static_cast<unsigned long long>(s.leadStale), static_cast<unsigned long long>(s.leadStaleDiff),
                             static_cast<unsigned long long>(s.leadRejected));
                        note("NETDIAG lead_live=%d lead_send_cached=%d lead_send_fresh=%d lead_send_diff=%llu lead_send_changed=%llu lead_send_delta_max=%d",
                             s.liveLead, s.leadSendCached, s.leadSendFresh,
                             static_cast<unsigned long long>(s.leadSendDiff), static_cast<unsigned long long>(s.leadSendChanged),
                             s.leadSendDeltaMax);
                        s.diagTickGapUs = s.diagRxWaitUs = s.diagLocalGapUs = s.diagInputGapUs = 0;
                        s.diagLeadBack = 0;
                    }
                }
                if (!s.failReason.empty() || s.lost)
                    continue;
                if (!s.connected)
                {
                    if ((s.cfg.role == Role::Join || s.peerKnown) && now - s.lastHelloMs >= 100)
                        sendHelloLocked();
                    if (now - lastWaitNote >= 5000)
                    {
                        lastWaitNote = now;
                        if (now - s.startMs >= 4000)
                            note("waiting for the opponent's game to answer (%llus)...",
                                 static_cast<unsigned long long>((now - s.startMs) / 1000));
                    }
                    if (s.cfg.connectTimeoutS > 0 && now - s.startMs >= static_cast<uint64_t>(s.cfg.connectTimeoutS) * 1000)
                        failLocked("no_peer", "no answer from the opponent's game within " +
                                                  std::to_string(s.cfg.connectTimeoutS) + " s");
                    continue;
                }
                // PINGs: every 50 ms for the first 3 s (round-trip samples for the delay pick), then every 200 ms
                // while nothing else goes out
                const uint64_t pingEvery = now - s.connectMs < 3000 ? 50 : 200;
                if (now - s.lastPingMs >= pingEvery && (pingEvery == 50 || now - s.lastSendMs >= 200))
                    sendPingLocked();
                // inputs again while the peer has not acknowledged everything (lost packets)
                if (s.peerAck < s.localMax && now - s.lastSendMs >= 15)
                {
                    sendInputsLocked();
                    s.st.resends++;
                }
                if (s.cfg.timeoutS > 0 && now - s.lastRxMs >= static_cast<uint64_t>(s.cfg.timeoutS) * 1000)
                    loseLocked("peer_timeout", "nothing from the opponent's game for " + std::to_string(s.cfg.timeoutS) + " s");
            }
        }

        bool parseAddr(const std::string &spec, sockaddr_in *out)
        {
            const size_t c = spec.rfind(':');
            if (c == std::string::npos)
                return false;
            const std::string host = spec.substr(0, c);
            const int port = std::atoi(spec.c_str() + c + 1);
            std::memset(out, 0, sizeof *out);
            out->sin_family = AF_INET;
            out->sin_port = htons(static_cast<u_short>(port));
            if (inet_pton(AF_INET, host.c_str(), &out->sin_addr) == 1)
                return true;
            addrinfo hints{};
            hints.ai_family = AF_INET;
            hints.ai_socktype = SOCK_DGRAM;
            addrinfo *res = nullptr;
            if (getaddrinfo(host.c_str(), nullptr, &hints, &res) != 0 || !res)
                return false;
            out->sin_addr = reinterpret_cast<sockaddr_in *>(res->ai_addr)->sin_addr;
            freeaddrinfo(res);
            return true;
        }

        void deriveKey(const std::string &secret, uint8_t out[16])
        {
            static const uint8_t k1[16] = {'T', '4', 'N', 'P', '-', 'k', 'e', 'y', '-', 'd', 'e', 'r', 'i', 'v', 'e', '1'};
            static const uint8_t k2[16] = {'T', '4', 'N', 'P', '-', 'k', 'e', 'y', '-', 'd', 'e', 'r', 'i', 'v', 'e', '2'};
            const uint64_t a = siphash24(k1, reinterpret_cast<const uint8_t *>(secret.data()), secret.size());
            const uint64_t b = siphash24(k2, reinterpret_cast<const uint8_t *>(secret.data()), secret.size());
            std::memcpy(out, &a, 8);
            std::memcpy(out + 8, &b, 8);
        }
    }

    void note(const char *fmt, ...)
    {
        va_list ap;
        va_start(ap, fmt);
        vnote(fmt, ap);
        va_end(ap);
    }

    bool start(const Config &config)
    {
        State &s = S();
        if (s.on || config.role == Role::Off)
            return s.on;
        s.cfg = config;
        const char *strictHello = std::getenv("TEKKEN4_NET_STRICT_HELLO");
        s.strictHello = strictHello && std::strcmp(strictHello, "1") == 0;
        const char *matchDelay = std::getenv("TEKKEN4_NET_DELAY_MATCH");
        s.matchDelay = matchDelay && std::strcmp(matchDelay, "1") == 0;
        s.netVersion = s.matchDelay ? (s.strictHello ? kNetVersionStrictDelayMatch : kNetVersionDelayMatch)
                                   : (s.strictHello ? kNetVersionStrict : kNetVersion);
        if (s.cfg.autoVsFingerprint)
            s.netVersion += kNetVersionAutoVsOffset;
        // Normalize before HELLO so the setting compared by both players is the setting sent on the wire.
        if (s.matchDelay)
            s.cfg.delaySetting = s.cfg.delaySetting < 0 ? -1 : std::min(s.cfg.delaySetting, kMaxDelay);
        const char *coalesce = std::getenv("TEKKEN4_NET_COALESCE");
        s.coalesce = coalesce && std::strcmp(coalesce, "1") == 0;
        const char *diag = std::getenv("TEKKEN4_NET_DIAG");
        s.diag = diag && std::strcmp(diag, "1") == 0;
        const char *simSafeWait = std::getenv("TEKKEN4_NET_SIM_SAFE_WAIT");
        s.simSafeWait = simSafeWait && std::strcmp(simSafeWait, "1") == 0;
        const char *simNormalPriority = std::getenv("TEKKEN4_NET_SIM_NORMAL_PRIORITY");
        s.simNormalPriority = simNormalPriority && std::strcmp(simNormalPriority, "1") == 0;
        const char *orderedLead = std::getenv("TEKKEN4_NET_ORDERED_LEAD");
        s.orderedLead = orderedLead && std::strcmp(orderedLead, "1") == 0;
        const char *liveLead = std::getenv("TEKKEN4_NET_LIVE_LEAD");
        s.liveLead = liveLead && std::strcmp(liveLead, "1") == 0;
        s.lastInputBytes = 0;
        s.startMs = nowMs();
        s.log = std::fopen(config.logPath.c_str(), "w");
        // Two games on one PC (tests, a local session): Windows 11 runs a process without the foreground window with
        // EcoQoS (efficiency cores, coarse timers). The first pair ran the background game's frames at 27 ms against
        // 19 ms for the foreground one -- one side always behind, the other predicting and rolling back all match.
        // A netplay game must keep its speed whether its window has the focus or not.
        {
            PROCESS_POWER_THROTTLING_STATE throttling{};
            throttling.Version = PROCESS_POWER_THROTTLING_CURRENT_VERSION;
            throttling.ControlMask = PROCESS_POWER_THROTTLING_EXECUTION_SPEED | PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION;
            throttling.StateMask = 0; // off for both
            const BOOL ok = SetProcessInformation(GetCurrentProcess(), ProcessPowerThrottling, &throttling, sizeof throttling);
            const DWORD powerError = ok ? ERROR_SUCCESS : GetLastError();
            const MMRESULT timerResult = timeBeginPeriod(1);
            note("power throttling (EcoQoS) %s for this process; timer resolution 1 ms", ok ? "off" : "could not be turned off");
            if (s.diag)
                note("NETDIAG thread=start tid=%lu priority=%d power_ok=%d power_error=%lu timer_result=%u",
                     static_cast<unsigned long>(GetCurrentThreadId()), GetThreadPriority(GetCurrentThread()), ok, static_cast<unsigned long>(powerError),
                     static_cast<unsigned>(timerResult));
            // The same for the GPU (phase 3b): the game without the foreground window had its GPU work scheduled
            // behind, its GS worker then waited 65-200 ms every ~6 frames for the vertex ring's fences (the GPU
            // tens of ms behind) -- a picture held 4-12 refreshes. The process GPU scheduling priority class
            // (gdi32 D3DKMTSetProcessSchedulingPriorityClass, what OBS uses for the same reason): HIGH, else
            // ABOVE_NORMAL (HIGH may need elevation). TEKKEN4_NET_GPU_PRIORITY=0 leaves it.
            const char *gp = std::getenv("TEKKEN4_NET_GPU_PRIORITY");
            if (!gp || *gp != '0')
            {
                using SetGpuPriority = LONG(WINAPI *)(HANDLE, int);
                HMODULE gdi = GetModuleHandleA("gdi32.dll");
                if (!gdi)
                    gdi = LoadLibraryA("gdi32.dll");
                const auto fn = gdi ? reinterpret_cast<SetGpuPriority>(
                                          reinterpret_cast<void *>(GetProcAddress(gdi, "D3DKMTSetProcessSchedulingPriorityClass")))
                                    : nullptr;
                LONG r = -1;
                int cls = 4; // D3DKMT_SCHEDULINGPRIORITYCLASS_HIGH
                if (fn)
                {
                    r = fn(GetCurrentProcess(), cls);
                    if (r != 0)
                    {
                        cls = 3; // ABOVE_NORMAL
                        r = fn(GetCurrentProcess(), cls);
                    }
                }
                note("GPU scheduling priority %s (%s)", r == 0 ? (cls == 4 ? "high" : "above normal") : "unchanged",
                     fn ? (r == 0 ? "D3DKMTSetProcessSchedulingPriorityClass" : "refused") : "no D3DKMT entry point");
            }
        }
        WSADATA wsa;
        if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
        {
            note("WSAStartup failed");
            return false;
        }
        LARGE_INTEGER t;
        QueryPerformanceCounter(&t);
        uint64_t x = static_cast<uint64_t>(t.QuadPart) ^ (static_cast<uint64_t>(GetCurrentProcessId()) << 32);
        x ^= x >> 33;
        x *= 0xff51afd7ed558ccdull;
        x ^= x >> 33;
        s.nonce = static_cast<uint32_t>(x) | 1u;
        s.session = config.role == Role::Host ? (static_cast<uint32_t>(x >> 32) | 1u) : 0u;
        s.seed = config.role == Role::Host ? (config.seed ? config.seed : s.session) : 0u;
        s.decided = -1;
        if (!config.key.empty())
        {
            deriveKey(config.key, s.key);
            s.keyed = true;
        }
        s.envPeer = !config.peer.empty() && parseAddr(config.peer, &s.peer);
        if (s.envPeer)
            s.expectedPeerIp = s.peer.sin_addr;
        if (!config.peer.empty() && !s.envPeer)
            note("cannot parse the peer address '%s'", config.peer.c_str());
        s.peerKnown = s.envPeer;
        s.sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (s.sock == INVALID_SOCKET)
        {
            note("socket() failed (%d)", WSAGetLastError());
            return false;
        }
        int rcvbuf = 1 << 20;
        setsockopt(s.sock, SOL_SOCKET, SO_RCVBUF, reinterpret_cast<const char *>(&rcvbuf), sizeof rcvbuf);
        // no WSAECONNRESET storms from ICMP port unreachable (the peer not up yet)
        BOOL noReset = FALSE;
        DWORD ret = 0;
        WSAIoctl(s.sock, _WSAIOW(IOC_VENDOR, 12), &noReset, sizeof noReset, nullptr, 0, &ret, nullptr, nullptr);
        sockaddr_in me{};
        me.sin_family = AF_INET;
        me.sin_port = htons(config.port);
        std::string bind = config.bind;
        if (bind.empty())
            bind = s.envPeer && s.peer.sin_addr.s_addr == htonl(INADDR_LOOPBACK) ? "127.0.0.1" : "0.0.0.0";
        inet_pton(AF_INET, bind.c_str(), &me.sin_addr);
        if (::bind(s.sock, reinterpret_cast<sockaddr *>(&me), sizeof me) != 0)
        {
            note("bind %s:%u failed (%d)", bind.c_str(), config.port, WSAGetLastError());
            closesocket(s.sock);
            s.sock = INVALID_SOCKET;
            return false;
        }
        s.sim = config.simLatencyMs > 0 || config.simJitterMs > 0 || config.simLossPercent > 0;
        s.simRng.seed(config.simSeed * 0x9E3779B97F4A7C15ull + (config.role == Role::Host ? 1 : 2));
        s.on = true;
        note("netplay %s on %s:%u%s%s, build %016llx, protocol v%u, input delay setting %s%s", config.role == Role::Host ? "host" : "join",
             bind.c_str(), config.port, s.envPeer ? ", peer " : "", s.envPeer ? addrText(s.peer).c_str() : "",
             static_cast<unsigned long long>(config.buildId), s.netVersion,
             s.cfg.delaySetting < 0 ? "auto" : std::to_string(s.cfg.delaySetting).c_str(), s.keyed ? ", keyed" : "");
        if (s.coalesce)
            note("TEKKEN4_NET_COALESCE=1: duplicate boundary INPUT sends coalesced for up to 15 ms; sampled inputs and stalled resends unchanged");
        if (s.strictHello)
            note("TEKKEN4_NET_STRICT_HELLO=1: protocol v%u requires nonzero matching build ids and validates HELLO/REJECT identity", s.netVersion);
        if (s.matchDelay)
            note("TEKKEN4_NET_DELAY_MATCH=1: protocol v%u uses equal explicit settings or measured-RTT auto, fixed for this session", s.netVersion);
        if (s.cfg.autoVsFingerprint)
            note("protocol v%u requires matching boot/native-name fingerprint %016llx",
                 s.netVersion, static_cast<unsigned long long>(s.cfg.autoVsFingerprint));
        if (s.sim)
            note("network simulator on this side's sends: one-way %.1f ms +- %.1f ms, %.1f %% loss", config.simLatencyMs,
                 config.simJitterMs, config.simLossPercent);
        if (s.diag)
            note("NETDIAG enabled (one-second interval maxima, ages at sample); sim_seed=%u role_stream=%d sim_safe_wait=%d",
                 config.simSeed, config.role == Role::Host ? 1 : 2, s.simSafeWait);
        if (s.simSafeWait)
            note("TEKKEN4_NET_SIM_SAFE_WAIT=1: simulator wait uses a copied deadline while its queue is unlocked");
        if (s.simNormalPriority)
            note("TEKKEN4_NET_SIM_NORMAL_PRIORITY=1: only the simulator worker uses NORMAL instead of HIGHEST thread priority; sim_active=%d", s.sim);
        if (s.orderedLead)
            note("TEKKEN4_NET_ORDERED_LEAD=1: ignore peer lead when INPUT ack or end regresses; inputs and hashes unchanged");
        if (s.liveLead)
            note("TEKKEN4_NET_LIVE_LEAD=1: INPUT lead uses current signed localMax - remoteContig, clamped to +/-100");
        std::thread(rxThread).detach();
        std::thread(tickThread).detach();
        if (s.sim)
            std::thread(simThread).detach();
        if (config.role == Role::Join || s.envPeer)
        {
            std::lock_guard<std::mutex> lk(s.mu);
            sendHelloLocked();
        }
        std::atexit([] { bye(); });
        return true;
    }

    bool enabled() { return S().on; }
    int slot() { return S().cfg.role == Role::Host ? 0 : 1; }

    bool waitConnected()
    {
        State &s = S();
        std::unique_lock<std::mutex> lk(s.mu);
        s.rx.wait(lk, [&s] { return s.connected || !s.failReason.empty(); });
        return s.connected && s.failReason.empty();
    }

    const char *failure()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.failReason.empty() ? nullptr : s.failReason.c_str();
    }

    bool peerLost()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.lost;
    }

    const char *lostReason()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.lostReason.empty() ? (s.failReason.empty() ? nullptr : s.failReason.c_str()) : s.lostReason.c_str();
    }

    uint32_t sessionSeed()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.seed ? s.seed : s.session;
    }

    uint64_t peerBuildId()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.peerBuild;
    }

    int rttMs(int *samples)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        const uint32_t n = std::min<uint32_t>(s.nrtt, 32);
        if (samples)
            *samples = static_cast<int>(n);
        if (!n)
            return -1;
        float v[32];
        std::memcpy(v, s.rtt, sizeof(float) * n);
        std::sort(v, v + n);
        return static_cast<int>(v[n / 2] + 0.5f);
    }

    int agreeDelay(uint32_t waitMs)
    {
        State &s = S();
        if (s.matchDelay && s.cfg.role == Role::Host)
        {
            std::lock_guard<std::mutex> lk(s.mu);
            if (s.decided >= 0)
            {
                s.delay = s.decided;
                return s.delay;
            }
        }
        const uint64_t t0 = nowMs();
        if (s.cfg.role == Role::Host)
        {
            // round-trip samples first (PINGs every 50 ms after the connect)
            for (;;)
            {
                int n = 0;
                rttMs(&n);
                if (n >= 16 || nowMs() - t0 >= waitMs || peerLost())
                    break;
                Sleep(10);
            }
            int samples = 0;
            const int rtt = rttMs(&samples);
            int peerSetting;
            {
                std::lock_guard<std::mutex> lk(s.mu);
                peerSetting = s.peerDelaySetting;
            }
            int pick;
            std::string why;
            if (s.cfg.delaySetting >= 0 && (!s.matchDelay || s.cfg.delaySetting == peerSetting))
            {
                pick = std::min(s.cfg.delaySetting, kMaxDelay);
                why = s.matchDelay ? "both players set " + std::to_string(pick) : "the host's setting";
            }
            else
            {
                pick = rtt < 0 ? 2 : rtt <= 60 ? 1 : rtt <= 150 ? 2 : rtt <= 250 ? 3 : 4;
                why = "auto: round trip " + std::to_string(rtt) + " ms (" + std::to_string(samples) +
                      " samples; 1 frame up to 60 ms, 2 above, 3 above 150, 4 above 250)";
                if (s.matchDelay)
                    why += "; settings " + (s.cfg.delaySetting < 0 ? std::string("auto") : std::to_string(s.cfg.delaySetting)) +
                           " / " + (peerSetting < 0 ? std::string("auto") : std::to_string(peerSetting));
            }
            {
                std::lock_guard<std::mutex> lk(s.mu);
                s.decided = pick;
                s.delay = pick;
                sendPingLocked();
            }
            note("input delay for this session: %d frame(s) (%s; the peer's setting %s)", pick, why.c_str(),
                 peerSetting < 0 ? "auto" : std::to_string(peerSetting).c_str());
            return pick;
        }
        std::unique_lock<std::mutex> lk(s.mu);
        s.rx.wait(lk, [&s] { return s.decided >= 0 || s.lost; });
        s.delay = std::max(0, s.decided);
        const int delay = s.delay;
        lk.unlock();
        int samples = 0;
        const int rtt = rttMs(&samples);
        note("input delay for this session: %d frame(s) (the host's pick; round trip here %d ms, %d samples)", delay, rtt, samples);
        return delay;
    }

    void setInputBase(uint32_t base)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        s.base = base;
        for (uint32_t f = 0; f < base; ++f)
        {
            s.local.in[f % kRing] = PadInput{};
            s.local.inTag[f % kRing] = f + 1;
            if (s.remote.inTag[f % kRing] != f + 1)
            {
                s.remote.in[f % kRing] = PadInput{};
                s.remote.inTag[f % kRing] = f + 1;
            }
        }
        s.localMax = std::max(s.localMax, base);
        while (s.remote.inTag[s.remoteContig % kRing] == s.remoteContig + 1)
            s.remoteContig++;
    }

    void setLocal(uint32_t frame, const PadInput &input)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        if (s.diag)
        {
            const uint64_t us = qpcUs();
            if (s.diagLocalUs)
                s.diagLocalGapUs = std::max(s.diagLocalGapUs, us - s.diagLocalUs);
            else
                note("NETDIAG thread=setLocal tid=%lu priority=%d", static_cast<unsigned long>(GetCurrentThreadId()),
                     GetThreadPriority(GetCurrentThread()));
            s.diagLocalUs = us;
        }
        for (uint32_t g = s.localMax; g <= frame; ++g) // a gap (never expected) holds this input
        {
            s.local.in[g % kRing] = input;
            s.local.inTag[g % kRing] = g + 1;
        }
        if (frame + 1 > s.localMax)
            s.localMax = frame + 1;
        sendInputsLocked();
    }

    bool local(uint32_t frame, PadInput *out)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        if (s.local.inTag[frame % kRing] != frame + 1)
            return false;
        *out = s.local.in[frame % kRing];
        return true;
    }

    uint32_t localMax()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.localMax;
    }

    bool remote(uint32_t frame, PadInput *out)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        if (frame >= s.remoteContig || s.remote.inTag[frame % kRing] != frame + 1)
            return false;
        *out = s.remote.in[frame % kRing];
        return true;
    }

    bool remoteOrPredict(uint32_t frame, PadInput *out, uint32_t *contig)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        *contig = s.remoteContig;
        *out = PadInput{};
        if (frame < s.remoteContig && s.remote.inTag[frame % kRing] == frame + 1)
        {
            *out = s.remote.in[frame % kRing];
            return true;
        }
        // Reception cannot advance between the exact lookup and this fallback. Never borrow a future input.
        if (s.remoteContig > 0 && s.remoteContig <= frame)
        {
            const uint32_t last = s.remoteContig - 1u;
            if (s.remote.inTag[last % kRing] == last + 1)
                *out = s.remote.in[last % kRing];
        }
        return false;
    }

    uint32_t remoteContig()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.remoteContig;
    }

    uint32_t peerAck()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.peerAck;
    }

    uint32_t waitRemote(uint32_t frame, uint32_t ms)
    {
        State &s = S();
        const uint64_t t0 = nowMs();
        std::unique_lock<std::mutex> lk(s.mu);
        for (;;)
        {
            if (s.remoteContig > frame || s.lost)
                return s.remoteContig;
            const uint64_t now = nowMs();
            if (ms != UINT32_MAX && now - t0 >= ms)
                return s.remoteContig;
            if (now - s.lastSendMs >= 15)
                sendInputsLocked();
            s.rx.wait_for(lk, std::chrono::milliseconds(2));
        }
    }

    uint32_t waitRemoteUs(uint32_t frame, uint32_t us)
    {
        State &s = S();
        const uint64_t end = qpcUs() + us;
        std::unique_lock<std::mutex> lk(s.mu);
        for (;;)
        {
            if (s.remoteContig > frame || s.lost)
                return s.remoteContig;
            const uint64_t now = qpcUs();
            if (now >= end)
                return s.remoteContig;
            s.rx.wait_for(lk, std::chrono::microseconds(std::min<uint64_t>(end - now, 1000u)));
        }
    }

    void sendNow()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        sendInputsLocked(true);
        compareHashesLocked();
    }

    void setLead(int lead)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        s.localLead = static_cast<int8_t>(std::max(-100, std::min(100, lead)));
        s.leadReady = true;
    }

    int peerLead()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.peerLeadV;
    }

    void pushHash(uint32_t frame, uint64_t hash)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        const uint32_t i = frame % kRing;
        s.local.hash[i] = hash;
        s.local.hashTag[i] = frame + 1;
        if (frame + 1 > s.localHashMax)
            s.localHashMax = frame + 1;
        compareHashesLocked();
    }

    bool takeMismatch(uint32_t *frame, uint64_t *localHash, uint64_t *remoteHash)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        if (s.mismatchQueue.empty())
            return false;
        *frame = static_cast<uint32_t>(s.mismatchQueue.front()[0]);
        *localHash = s.mismatchQueue.front()[1];
        *remoteHash = s.mismatchQueue.front()[2];
        s.mismatchQueue.pop_front();
        return true;
    }

    uint32_t hashesCompared()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.compared;
    }

    int hashAgreement(uint32_t frame)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        const uint32_t i = frame % kRing;
        if (s.verdictTag[i] == frame + 1)
            return s.verdict[i];
        return frame < s.checked ? 2 : 0;
    }

    uint32_t hashMismatches()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        return s.mismatches;
    }

    Stats stats()
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        Stats out = s.st;
        out.simActive = s.sim;
        out.simNormalPriority = s.simNormalPriority;
        out.simPriorityReady = s.simPriorityReady.load(std::memory_order_acquire);
        out.simPriorityOk = s.simPriorityOk.load(std::memory_order_relaxed);
        out.simThreadPriority = s.simThreadPriority.load(std::memory_order_relaxed);
        out.simSpinCalls = s.simSpinCalls.load(std::memory_order_relaxed);
        out.simSpinUs = s.simSpinUs.load(std::memory_order_relaxed);
        out.simSpinMaxUs = s.simSpinMaxUs.load(std::memory_order_relaxed);
        out.simSendCalls = s.simSendCalls.load(std::memory_order_relaxed);
        out.simLateMaxUs = s.simLateMaxUs.load(std::memory_order_relaxed);
        out.simLateOver2ms = s.simLateOver2ms.load(std::memory_order_relaxed);
        return out;
    }

    void bye()
    {
        State &s = S();
        if (!s.on)
            return;
        std::lock_guard<std::mutex> lk(s.mu);
        if (!s.connected || s.sock == INVALID_SOCKET)
            return;
        const Hdr h = makeHdr(PKT_BYE);
        // straight out (not through the simulator: the process is ending)
        for (int i = 0; i < 3; ++i)
            sendWire(reinterpret_cast<const uint8_t *>(&h), sizeof h, s.peer);
    }
}
