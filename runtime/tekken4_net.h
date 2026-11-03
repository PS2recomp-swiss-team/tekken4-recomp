// Tekken 4 netplay transport (rollback phase 3, docs/ROLLBACK_PHASE3.md): UDP session between two game instances.
// Game-agnostic: it knows frames, pad inputs and state hashes, nothing about the game. The rollback loop that uses
// it is Mode::Net of runtime/tekken4_rollback_overrides.cpp. Wire design from T5DR Online's src/netplay/netplay_core.cpp
// (the user's own code): HELLO / INPUT / PING / BYE / REJECT, a per-process nonce, optional SipHash-2-4 tags,
// redundant unacknowledged inputs in every INPUT packet, the latest state hashes riding along, the sender's
// frame-advantage estimate for time sync, round trip by PING echo, the host's input-delay pick carried in PING/INPUT.
// Magic "T4NP", protocol version kNetVersion (raise it with any wire change; it is part of the build id).
#pragma once

#include <cstdint>
#include <string>

namespace t4net
{
    constexpr uint8_t kNetVersion = 1;

    // One player's pad for one frame: buttons active-HIGH in libpad bit order (bit 3 Start, 4 Up, ... 14 Cross,
    // 15 Square), axes rx ry lx ly (0x80 centre).
    struct PadInput
    {
        uint16_t buttons = 0;
        uint8_t axes[4] = {0x80, 0x80, 0x80, 0x80};
        bool operator==(const PadInput &o) const
        {
            return buttons == o.buttons && axes[0] == o.axes[0] && axes[1] == o.axes[1] && axes[2] == o.axes[2] &&
                   axes[3] == o.axes[3];
        }
        bool operator!=(const PadInput &o) const { return !(*this == o); }
    };

    enum class Role
    {
        Off,
        Host,
        Join,
    };

    struct Config
    {
        Role role = Role::Off;
        uint16_t port = 7400;          // host: listen port; join: local port (0 = any)
        std::string peer;              // join: host ip:port (host: optional, it then calls it too)
        std::string bind;              // local address ("" = 127.0.0.1 for a loopback peer, else any)
        int delaySetting = -1;         // -1 = auto (by round trip), else frames
        uint64_t buildId = 0;          // a peer with another build id is refused at HELLO
        uint32_t seed = 0;             // host: the session seed (0 = the session id)
        std::string key;               // optional match secret: SipHash-2-4 tag on every packet
        int timeoutS = 20;             // peer silent this long = lost
        int connectTimeoutS = 120;     // no handshake within this = failed
        // in-process network simulator (outgoing packets of this side): one-way latency, +- jitter, loss
        double simLatencyMs = 0, simJitterMs = 0, simLossPercent = 0;
        uint32_t simSeed = 1;
        std::string logPath = "net.log";
    };

    // Socket + receive/tick threads; the handshake starts at once in the background.
    bool start(const Config &config);
    bool enabled();
    int slot(); // 0 = host (P1, pad port 1), 1 = join (P2)

    // Blocks until the handshake is done (or failed / timed out): true when connected.
    bool waitConnected();
    const char *failure();    // non-null once connecting failed for good
    bool peerLost();
    const char *lostReason();
    uint32_t sessionSeed();   // the host's seed (after the handshake)
    uint64_t peerBuildId();

    // Round trip (median of the PING echo samples), -1 without samples.
    int rttMs(int *samples = nullptr);
    // Input delay: the host decides (auto: 1 frame up to 60 ms round trip, 2 above, 3 above 150, 4 above 250, or
    // its own setting), the joiner waits for the host's pick. Collects round-trip samples first (up to waitMs).
    int agreeDelay(uint32_t waitMs);

    // Frames < base are neutral for both players (before the first sampled frame + delay).
    void setInputBase(uint32_t base);
    // This side's input for a frame (frames in order, each once): kept and sent with the next packet (now).
    void setLocal(uint32_t frame, const PadInput &input);
    bool local(uint32_t frame, PadInput *out);
    uint32_t localMax();      // local inputs known for frames < this
    bool remote(uint32_t frame, PadInput *out);
    uint32_t remoteContig();  // the peer's inputs are known for every frame < this
    uint32_t peerAck();       // the peer has our inputs for frames < this
    // Waits until the peer's input for `frame` is here, the session is lost, or ms passed (UINT32_MAX = no limit
    // but the session's timeout). Returns remoteContig().
    uint32_t waitRemote(uint32_t frame, uint32_t ms);
    // The same with a microsecond limit (the early-rollback wait before a frame's vblank time; never resends).
    uint32_t waitRemoteUs(uint32_t frame, uint32_t us);
    void sendNow();           // send the inputs + hashes now (also done by setLocal and every 15 ms while stalled)

    // Time sync: this side's lead estimate rides in every packet; the peer's latest.
    void setLead(int lead);
    int peerLead();

    // Desync check: the hash of a FINAL frame (every input before it confirmed). Both sides push the same frames;
    // compared when both are known.
    void pushHash(uint32_t frame, uint64_t hash);
    bool takeMismatch(uint32_t *frame, uint64_t *local, uint64_t *remote);
    uint32_t hashesCompared();
    uint32_t hashMismatches();

    struct Stats
    {
        uint64_t packetsOut = 0, packetsIn = 0, simDropped = 0, bytesOut = 0, resends = 0;
    };
    Stats stats();

    void bye(); // BYE x3 (also at process exit)
    void note(const char *fmt, ...);
}
