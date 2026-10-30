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
            uint32_t base = 0;         // frames < base are neutral (both sides)
            Ring local, remote;
            uint32_t localMax = 0, remoteContig = 0, peerAck = 0;
            int8_t localLead = 0, peerLeadV = 0;
            uint32_t localHashMax = 0, remoteHashMax = 0, checked = 0, compared = 0, mismatches = 0;
            std::deque<std::array<uint64_t, 3>> mismatchQueue;
            // round trip
            float rtt[32]{};
            uint32_t nrtt = 0;
            uint32_t peerPingUs = 0;
            uint64_t peerPingRxUs = 0;
            Stats st;
            uint32_t strangers = 0;
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
            s.simCv.notify_one();
        }

        Hdr makeHdr(uint8_t type)
        {
            State &s = S();
            return {kMagic, type, kNetVersion, static_cast<uint8_t>(std::max(0, s.delay)),
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
            struct
            {
                Hdr h;
                HelloExt x;
            } p = {makeHdr(PKT_HELLO),
                   {s.cfg.buildId, s.seed,
                    static_cast<uint32_t>((s.cfg.delaySetting < 0 ? 0xFFu : static_cast<uint32_t>(s.cfg.delaySetting)) << 8)}};
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
        void sendInputsLocked()
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
            ih->lead = s.localLead;
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
            sendTo(buf, static_cast<int>(reinterpret_cast<uint8_t *>(wh + nh) - buf));
            s.lastSendMs = nowMs();
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
            std::lock_guard<std::mutex> lk(s.mu);
            if (h.ver != kNetVersion)
            {
                if (!s.connected && h.type == PKT_HELLO)
                    failLocked("build_mismatch", addrText(from) + " speaks netplay protocol v" + std::to_string(h.ver) +
                                                     ", this game v" + std::to_string(kNetVersion));
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
            if (h.type == PKT_HELLO)
            {
                if (n < static_cast<int>(sizeof(Hdr) + sizeof(HelloExt)))
                    return;
                HelloExt x;
                std::memcpy(&x, p + sizeof(Hdr), sizeof x);
                if (x.build && s.cfg.buildId && x.build != s.cfg.buildId)
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
                const uint32_t ds = (x.flags >> 8) & 0xFFu;
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
                if (s.connected && h.nonce != s.peerNonce)
                    return;
                const uint8_t why = n >= static_cast<int>(sizeof(Hdr) + 1) ? p[sizeof(Hdr)] : 0;
                if (why == REJ_BUILD)
                {
                    if (!s.connected)
                        failLocked("build_mismatch", addrText(from) + " refused us: it runs a different build");
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
            if (ih.ack > s.peerAck)
                s.peerAck = ih.ack;
            s.peerLeadV = ih.lead;
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
            while (s.remote.inTag[s.remoteContig % kRing] == s.remoteContig + 1)
                s.remoteContig++;
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
            SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
            State &s = S();
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
            SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
            State &s = S();
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
                        lk.unlock();
                        while (qpcUs() < front.dueUs) // (front stays: only this thread pops)
                            std::this_thread::yield();
                        lk.lock();
                    }
                    continue;
                }
                SimPacket packet = std::move(front);
                s.simQueue.pop_front();
                lk.unlock();
                sendWire(packet.bytes.data(), static_cast<int>(packet.bytes.size()), packet.to);
                lk.lock();
            }
        }

        void tickThread()
        {
            SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_ABOVE_NORMAL);
            State &s = S();
            uint64_t lastWaitNote = 0;
            for (;;)
            {
                Sleep(5);
                std::lock_guard<std::mutex> lk(s.mu);
                const uint64_t now = nowMs();
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
            timeBeginPeriod(1);
            note("power throttling (EcoQoS) %s for this process; timer resolution 1 ms", ok ? "off" : "could not be turned off");
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
             static_cast<unsigned long long>(config.buildId), kNetVersion,
             config.delaySetting < 0 ? "auto" : std::to_string(config.delaySetting).c_str(), s.keyed ? ", keyed" : "");
        if (s.sim)
            note("network simulator on this side's sends: one-way %.1f ms +- %.1f ms, %.1f %% loss", config.simLatencyMs,
                 config.simJitterMs, config.simLossPercent);
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
            int pick;
            std::string why;
            if (s.cfg.delaySetting >= 0)
            {
                pick = std::min(s.cfg.delaySetting, kMaxDelay);
                why = "the host's setting";
            }
            else
            {
                pick = rtt < 0 ? 2 : rtt <= 60 ? 1 : rtt <= 150 ? 2 : rtt <= 250 ? 3 : 4;
                why = "auto: round trip " + std::to_string(rtt) + " ms (" + std::to_string(samples) +
                      " samples; 1 frame up to 60 ms, 2 above, 3 above 150, 4 above 250)";
            }
            {
                std::lock_guard<std::mutex> lk(s.mu);
                s.decided = pick;
                s.delay = pick;
                sendPingLocked();
            }
            note("input delay for this session: %d frame(s) (%s; the peer's setting %s)", pick, why.c_str(),
                 s.peerDelaySetting < 0 ? "auto" : std::to_string(s.peerDelaySetting).c_str());
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
        sendInputsLocked();
        compareHashesLocked();
    }

    void setLead(int lead)
    {
        State &s = S();
        std::lock_guard<std::mutex> lk(s.mu);
        s.localLead = static_cast<int8_t>(std::max(-100, std::min(100, lead)));
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
        return s.st;
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
