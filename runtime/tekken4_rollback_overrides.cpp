// Tekken 4 (SLUS-20328, NTSC-U v1.00): rollback netcode phases 0-2 (docs/ROLLBACK_PLAN.md, docs/ROLLBACK_PHASE01.md,
// docs/ROLLBACK_PHASE2.md). Nothing here runs unless TEKKEN4_RB_MODE is set: normal play keeps the default runtime
// path (no hook, no cut, no IOP gate installed).
//
// TEKKEN4_RB_MODE=measure  per frame boundary: frame number, vsync tick, EE cycle, full state hash (RDRAM with masks,
//                          scratchpad, VU memories, scheduler, device registers), per-1-MB region hashes, EE time.
//                          Written to rb_frames.log in the working directory (the run dir).
// TEKKEN4_RB_MODE=test     measure + rollback self-test (T5DR's T5_RB_MODE=test): every N frames save the machine,
//                          run K frames, restore, check the restored hash, run the same K frames again with the same
//                          scripted input and compare every boundary's hash with the first pass (K = 1..maxdepth).
//                          TEKKEN4_RB_TEST="start=<frame>,every=<N>,depth=<maxK>[,words=1][,mispredict=1]"
//                          (defaults 600,30,8). mispredict=1: like a real rollback, a second pass runs the K frames
//                          with WRONG input (pad 1 replaced), is rolled back again, and the third pass with the
//                          true input must match the first pass frame by frame.
// TEKKEN4_RB_MODE=selfnet  one-process netcode harness: pad 2 is the "remote" player. Its scripted input is revealed
//                          to the simulation late (TEKKEN4_RB_NET="start=<frame>,delay=<D>,jitter=<J>,max=<M>",
//                          defaults 2100,4,0,8); until then the input of the last revealed frame is used (prediction
//                          = repeat), and a misprediction rolls back to the mispredicted frame and re-simulates up to
//                          the live frame (snapshot every boundary, ring of M+2). Compare the LAST line of each frame
//                          (rb_compare.py --last) with a measure run fed the true input on time (TEKKEN4_RB_PAD2=1).
// Re-simulated frames (W/R passes of the test, rollbacks of selfnet) run with the cuts of TEKKEN4_RB_CUT
//                          ("none" or a list of draw, upload, iop, present, vu1; default draw,iop,present,vu1):
//                          draw = no GS primitive submission, upload = no host->local image data, iop = IOP frozen
//                          (sound RPCs answered from the live frames' log, async IOP->EE writes replayed by EE cycle),
//                          present = the presenter keeps the last live frame, vu1 = no VU1 microprogram runs (VU1
//                          data memory is then output state and left out of the hash unless TEKKEN4_RB_HASHVU1=1).
//                          TEKKEN4_RB_CUT_TAIL=<n> (default 1, in netplay 0):
//                          the last n re-simulated frames draw again (the picture the next vblank shows).
// TEKKEN4_RB_SND           what a frozen-IOP RPC does when the re-simulated call differs from the logged one:
//                          "replay" (default: the logged reply is written, nothing reaches the IOP) or "forward"
//                          (the call goes to the IOP: a sound of the corrected timeline starts late).
// TEKKEN4_RB_IDLE=0       the vsync wait loop (0x22a150) iterates as the game does (default: its iterations up to the
//                          next event are accounted in one step; same EE cycles and events, much less host time).
// TEKKEN4_RB_SNDTRACE=1    rb_sound.log: every IOP RPC (frame, sid, function, send/reply bytes) and every replay.
// TEKKEN4_RB_INPUT         frame-exact scripted pad 1 input instead of the keyboard (both runs see the same input):
//                          "<frame>:<Btn>[+<Btn>...][:<hold frames>],..." e.g. "500:Start,800:Cross:4"
//                          (Up Down Left Right Start Select Cross Circle Square Triangle L1 R1 L2 R2; hold 6).
// TEKKEN4_RB_FUZZ          "<from>[:<to>]": from that frame on, pad 1 plays a pseudo-random fight input (directions,
//                          punches, kicks; never Start/Select) that is a pure function of the frame number.
// TEKKEN4_RB_PAD2=1        pad 2 connected (always on in selfnet), driven by TEKKEN4_RB_INPUT2 / TEKKEN4_RB_FUZZ2
//                          (same syntax; pad 2's fuzz is another sequence than pad 1's).
// TEKKEN4_RB_BOUNDARY      the frame boundary: "vblank" (default: every VBlankStart, at the next dispatcher
//                          checkpoint), or a main-thread wake: "vsync", "sema:<id>", "evf:<id>", "any".
// TEKKEN4_RB_MASK          extra hash masks "<addr>:<size>,..." (physical RDRAM, hex ok) on top of the built-in list.
// TEKKEN4_RB_DUMP          "<frame>,..." writes rb_dump_f<frame>.bin (RDRAM 32 MB) and rb_sched_f<frame>.bin.
// TEKKEN4_RB_PAGES         "<from>:<to>": also log the per-4-KB page hashes of RDRAM for those frames (rb_pages.log).
// TEKKEN4_RB_IOPSTATE=1    (phase 3) the IOP is part of every snapshot: re-simulated frames run the IOP like live ones
//                          (no IOP cut, no gate), the SPU2 output of re-simulated frames is not played. Default in
//                          netplay; available to test/selfnet/measure (measure: NETHASH lines comparable with netplay).
// TEKKEN4_RB_AUDIO_TIMELINE=1  mute host SPU2 output by logical resim state, including no-cut frames (default off).
// TEKKEN4_RB_FRAMEHASH=0   no full-state hash per boundary in rb_frames.log (h=0; default 0 in netplay: 3 ms a frame).
//
// Netplay (phase 3, docs/ROLLBACK_PHASE3.md): two game instances over UDP (transport: tekken4_net.cpp), GGPO-style.
// TEKKEN4_NET=host:<port> | join:<ip>:<port>  (sets TEKKEN4_RB_MODE=net). The host is P1 (pad port 1), the joiner P2.
// TEKKEN4_NET_PORT         join: local UDP port (default 0 = any); TEKKEN4_NET_BIND local address
// TEKKEN4_NET_DELAY        input delay frames, "auto" (default: 1 up to 60 ms round trip, 2 above, 3 above 150, 4 above
//                          250) or a number; the host's setting decides, the joiner adopts it
// TEKKEN4_NET_MAXPRED      frames of remote input predicted at most before the frame waits (default 8)
// TEKKEN4_NET_RBSTART      frames before this run in lockstep (every input confirmed: boot, intro movie); default 600
// TEKKEN4_NET_HASH_EVERY   desync check: every N-th frame's final state hash (RDRAM, scratchpad, IOP, EE cycle) is
//                          exchanged (default 30); NETHASH lines in rb_frames.log
// TEKKEN4_NET_DESYNC_DUMP=1  on a mismatch, net_desync_f<frame>.bin (RDRAM + scratchpad of that frame), both sides
// TEKKEN4_NET_SIM          in-process network simulator for this side's sends: "lat=<ms>,jitter=<ms>,loss=<%>"
//                          (one-way; give each side half the round trip)
// TEKKEN4_NET_LOCALPAD=0   the local player is the script only (TEKKEN4_RB_INPUT/FUZZ on the host, TEKKEN4_RB_INPUT2/
//                          FUZZ2 on the joiner; frame = the frame the input takes effect in); otherwise script | device
// TEKKEN4_NET_AUTO_VS=1   bounded shared boot script on both pads through normal net input; devices held neutral.
//                          TEKKEN4_RB_INPUT supplies finite presses (else the pair-test VS menu prefix); no fuzz.
// TEKKEN4_NET_AUTO_VS_END  logical timeout/release frame, default 1200, range 1..3600; normal input from END+1.
//                          Select is not detected: timeout logs an unverified handoff. Settings must match peers.
// TEKKEN4_NET_PAD          the local device: 0 keyboard + first gamepad (default), -1 keyboard, n n-th gamepad
// TEKKEN4_NET_BUILD        build id (16 hex digits, tools/t4_buildid.py); else t4net_build.txt next to the exe;
//                          a peer with another id is refused at HELLO
// TEKKEN4_NET_SEED         the host's session seed (default its session id); mixed into the game's srand unless
//                          TEKKEN4_RAND_SEED pins it. TEKKEN4_NET_KEY: packet authentication secret
// TEKKEN4_NET_TIMESYNC=0   no frame-advantage balancing; TEKKEN4_NET_SHOTS="<frame>,...": net_shot_f<frame>.bmp
// TEKKEN4_NET_END=<frame>  at that frame write the final NETSUMMARY and "NETEND" (the harness closes the games)
// Phase 3b (docs/ROLLBACK_PHASE3B.md):
// TEKKEN4_NET_LOCKDELAY    the lockstep's own input delay ("auto" default: one way + 12 ms in frames, + 1; at least
//                          the session delay): the boot no longer waits for the peer every frame
// TEKKEN4_NET_EARLY=0      no early rollback (default on: the boundary comes up to TEKKEN4_NET_EARLY_MS (4) before
//                          its vblank time; a misprediction already known, or found while waiting for that time, is
//                          rolled back in the wait; the local input is still sampled at the vblank time)
// TEKKEN4_NET_LAZY=0       capture every re-simulated boundary (default: not the ones no rollback can reach again)
// The desync hash (and its dump copy) runs on a worker thread. RDRAM snapshots are incremental where the runtime
// keeps RDRAM under a write watch (PS2X_RDRAM_WRITE_WATCH, PS2X_RB_INCREMENTAL, PS2X_RB_WW_VERIFY=1 checks it).
// TEKKEN4_NET_HASH_PROFILE=1  host-only hash queue/collection age and snapshot reader-wait diagnostics (default off).
// TEKKEN4_NET_COST_PROFILE=1  bounded host-only live/cut/tail and snapshot/restore/rollback cost histograms (default off).
// TEKKEN4_NET_DIAG=1      one-second host timing/lead/deadline samples (default off).
// TEKKEN4_NET_DEFER_RESIM_FLUSH=1  defer ordinary boundary log flushes until replay returns live (default off).
// TEKKEN4_NET_BOOT_RENDEZVOUS=1  wait once for the peer's same-frame publication after boot prefill (default off).
// TEKKEN4_NET_FAST_SYNC=1  use eight fresh lead samples instead of twenty; keep the RTT settling hold (default off).
// TEKKEN4_NET_SYNC_SPREAD=<n>  a time-sync correction is spread over the next n live frames (default 8: ~2 ms
//                              longer each, no frame shown twice); 0 or 1 = the old single pause of the whole give.
// TEKKEN4_NET_SUBFRAME_SYNC=1  correct filtered leads of 0.25..<1 frame with fractional waits (default off).
// TEKKEN4_NET_FULL_SYNC=1  give up the measured lead from 1 frame, capped at four, without whole-frame rounding (default off).
// TEKKEN4_NET_SYNC_CAP_ONE=1  cap each correction pause at one vblank; retain its original settling hold (default off).
// TEKKEN4_NET_SYNC_GAP_RESET=1  refill lead samples after a >50 ms gap between live sync visits (default off).
// TEKKEN4_NET_SYNC_WALL_HOLD=1  cap the frame-count settling hold with its nominal wall duration (default off).
// TEKKEN4_NET_ATOMIC_INPUT=1  recheck a missing remote input and select its prediction under one lock (default off).
// TEKKEN4_NET_REFRESH_RC=1  refresh confirmed remote input after time sync, before the wait/late scan (default off).
// TEKKEN4_NET_REBASE_CATCHUP=1  retain two vblank periods of deadline debt at live pacing rebases (default off).
// TEKKEN4_STATE_PROBE=1    read-only live-boundary discovery log (requires a rollback mode; docs/DIRECTFIGHT_T4.md).
// TEKKEN4_NET_RESULT=<path>  diagnostic session result JSON, default off; winner/score remain unproved TODOs.
#include "game_overrides.h"
#include "ps2_log.h"
#include "ps2_runtime.h"
#include "ps2_runtime_macros.h"
#include "runtime/ee_scheduler.h"
#include "runtime/gs/gs_frontend.h"
#include "runtime/ps2_memory.h"
#include "runtime/ps2_rollback.h"
#include "runtime/ps2_rollback_cuts.h"
#include "Stubs/Pad.h"
#include "Stubs/SIF.h"
#include "tekken4_state_probe.h"
#if __has_include("tekken4_net.h") && defined(PS2X_ROLLBACK_IOP_STATE)
#include "tekken4_net.h"
#include "tekken4_online_result.h"
#define TEKKEN4_NETPLAY 1
#include <cmath>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>
#endif

#include <algorithm>
#include <chrono>
#include <cerrno>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

namespace tekken4
{
    extern uint64_t g_frames; // tekken4_overrides.cpp: passes of the main loop (per-frame sound RPC 0x100)
}

namespace tekken4_rollback
{
    // Host timing samples (ms) for the p50/p90/max lines of NETSUMMARY / COST. It used to be a vector sorted on
    // every summary: the summary frame every 600 frames cost 9 ms after 3 minutes and 31 ms after 16 (owner's
    // 2-PC test 2026-11-03: a visible 21-44 ms hitch every 10 s, growing with the session). Now a fixed histogram:
    // 0.01 ms bins up to 100 ms (inside a bin the value is the bin's centre, so the printed %.2f can differ by 0.01),
    // exact values outside that range and an exact maximum. O(1) per sample, ~10 us per percentile, whole session.
    class TimeSamples
    {
    public:
        void push_back(double v)
        {
            if (m_n == 0 || v > m_max)
                m_max = v;
            ++m_n;
            if (v >= 0.0 && v < kRangeMs)
            {
                if (m_bins.empty())
                    m_bins.assign(kBins, 0u);
                ++m_bins[static_cast<size_t>(v / kBinMs)];
            }
            else
                (v < 0.0 ? m_low : m_high).push_back(v);
        }
        [[nodiscard]] size_t size() const { return static_cast<size_t>(m_n); }
        [[nodiscard]] bool empty() const { return m_n == 0; }
        // As the old sorted-vector percentile: the value at index round(p * (n - 1)).
        [[nodiscard]] double percentile(double p) const
        {
            if (m_n == 0)
                return 0.0;
            if (p >= 1.0)
                return m_max;
            uint64_t at = std::min<uint64_t>(m_n - 1u, static_cast<uint64_t>(p * static_cast<double>(m_n - 1u) + 0.5));
            if (at < m_low.size())
            {
                std::vector<double> low = m_low;
                std::nth_element(low.begin(), low.begin() + static_cast<std::ptrdiff_t>(at), low.end());
                return low[at];
            }
            at -= m_low.size();
            for (size_t b = 0; b < m_bins.size(); ++b)
            {
                if (at < m_bins[b])
                    return std::min(m_max, (static_cast<double>(b) + 0.5) * kBinMs);
                at -= m_bins[b];
            }
            std::vector<double> high = m_high;
            if (high.empty())
                return m_max;
            at = std::min<uint64_t>(at, high.size() - 1u);
            std::nth_element(high.begin(), high.begin() + static_cast<std::ptrdiff_t>(at), high.end());
            return high[at];
        }

    private:
        static constexpr double kBinMs = 0.01, kRangeMs = 100.0;
        static constexpr size_t kBins = 10000u;
        std::vector<uint32_t> m_bins;
        std::vector<double> m_low, m_high;
        uint64_t m_n = 0;
        double m_max = 0.0;
    };

    enum class Mode
    {
        Off,
        Measure,
        Test,
        SelfNet,
        Net,
    };

    // Hash masks: words that differ between two runs with the same input for reasons outside the simulation, or
    // that the restore cannot reproduce. Each entry needs its evidence in docs/ROLLBACK_PHASE01.md.
    const std::vector<ps2_rollback::MaskRange> kBuiltinMasks = {
    };

    constexpr uint16_t kBtnSelect = 1u << 0, kBtnStart = 1u << 3, kBtnUp = 1u << 4, kBtnRight = 1u << 5,
                       kBtnDown = 1u << 6, kBtnLeft = 1u << 7, kBtnL2 = 1u << 8, kBtnR2 = 1u << 9, kBtnL1 = 1u << 10,
                       kBtnR1 = 1u << 11, kBtnTriangle = 1u << 12, kBtnCircle = 1u << 13, kBtnCross = 1u << 14,
                       kBtnSquare = 1u << 15;

    struct ScriptPress
    {
        uint64_t frame = 0;
        uint64_t hold = 6;
        uint16_t buttons = 0; // active-high here
    };

    struct PadScript
    {
        std::vector<ScriptPress> presses;
        uint64_t fuzzFrom = ~0ull, fuzzTo = ~0ull;
        uint64_t salt = 0;
    };

    struct Config
    {
        Mode mode = Mode::Off;
        bool scripted = false;
        bool pad2 = false;
        PadScript pads[2];
        EeWaitReason boundaryReason = EeWaitReason::VSync;
        int boundaryId = -1; // -1: any id
        bool boundaryAny = false;
        bool boundaryVblank = true;
        std::vector<ps2_rollback::MaskRange> masks;
        std::vector<uint64_t> dumpFrames;
        std::vector<uint64_t> shotFrames; // TEKKEN4_RB_SHOTS
        uint64_t pagesFrom = ~0ull, pagesTo = 0;
        uint64_t testStart = 600, testEvery = 30, testDepth = 8;
        bool testWords = false;
        bool testMispredict = false;
        uint32_t cuts = ps2_rollback::CutDraw | ps2_rollback::CutIop | ps2_rollback::CutPresent | ps2_rollback::CutVu1;
        uint64_t cutTail = 1;
        bool sndForward = false;
        bool sndTrace = false;
        uint64_t netStart = 2100, netDelay = 4, netJitter = 0, netMax = 8;
        bool iopState = false;   // TEKKEN4_RB_IOPSTATE / netplay: the IOP is in every snapshot
        bool audioTimeline = false; // TEKKEN4_RB_AUDIO_TIMELINE: host output only, independent of render cuts
        bool frameHash = true;   // TEKKEN4_RB_FRAMEHASH
        uint64_t hashEvery = 0;  // NETHASH every N frames (netplay; measure with TEKKEN4_NET_HASH_EVERY)
    };

    struct TestState
    {
        bool active = false; // a save exists and the first pass is running
        bool resim = false;  // second pass running
        bool wrong = false;  // mispredict=1: the wrong-input pass is running
        uint64_t wrongDiverged = 0, wrongPasses = 0;
        bool wrongSawDiff = false;
        uint64_t saveFrame = 0;
        uint64_t targetFrame = 0;
        uint64_t depth = 0;
        uint64_t cycle = 0;
        std::map<uint64_t, ps2_rollback::StateHash> firstPass;
        std::map<uint64_t, std::vector<uint64_t>> firstPages;
        std::map<uint64_t, std::vector<uint8_t>> firstRam; // words=1 only
        // totals
        uint64_t rollbacks = 0, restoredOk = 0, restoredBad = 0, compared = 0, mismatches = 0;
        double saveMs = 0, restoreMs = 0, maxSaveMs = 0, maxRestoreMs = 0;
        // cost of the current re-simulation pass (R): restore + EE time of its frames
        double passRestoreMs = 0, passEeMs = 0;
        uint64_t passFrames = 0;
    };

    struct NetState
    {
        std::vector<ps2_rollback::Snapshot> ring; // snapshot of boundary b in ring[b % size]
        std::vector<uint64_t> ringFrame;
        std::map<uint64_t, uint16_t> usedRemote; // pad 2 buttons (active-high) the latest run of frame k used
        uint64_t revealed = 0;                   // remote input known for frames <= revealed
        bool resim = false;
        uint64_t liveFrame = 0;                  // the boundary a running re-simulation returns to
        uint64_t rollbacks = 0, resimFrames = 0, maxDepth = 0, mispredicted = 0, revealedFrames = 0;
        double restoreMs = 0, captureMs = 0, passEeMs = 0;
        uint64_t captures = 0;
        uint64_t depthHist[17]{};
        TimeSamples passCost; // restore + EE time of each rollback's re-simulated frames
    };

    // The IOP outside the rollback state: per frame, what the IOP did to the EE on the live run, replayed while
    // re-simulating (CutIop). Frame = the logical frame executing (g_frame after its boundary).
    struct IopEffect
    {
        uint8_t kind = 0; // 0 write, 1 zero, 2 SIF command
        uint32_t address = 0;
        uint8_t *host = nullptr; // RDRAM/scratchpad pointer of address (writes)
        uint64_t cycle = 0;
        std::vector<uint8_t> data;
        size_t size = 0;
    };

    struct RpcRecord
    {
        uint32_t sid = 0, function = 0;
        std::vector<uint8_t> send;
        ps2x::iop::RpcResult result{};
        std::vector<IopEffect> effects;
    };

    struct FrameIop
    {
        std::vector<RpcRecord> rpcs;
        std::vector<IopEffect> async;
        size_t asyncCursor = 0;
        size_t rpcCursor = 0;
    };

    struct IopStats
    {
        uint64_t liveRpcs = 0, liveAsync = 0, liveSifCmds = 0;
        uint64_t replayedSame = 0, replayedDiff = 0, forwardedDiff = 0, forwardedUnlogged = 0, unloggedReplayEmpty = 0;
        uint64_t asyncReplayed = 0, asyncLeft = 0, eeToIopSuppressed = 0, frozenWritesIgnored = 0;
    };

    Config g_cfg;
    PS2Runtime *g_runtime = nullptr;
    uint64_t g_frame = 0;  // logical frame = boundary count since boot; restored with the snapshot
    uint64_t g_wallFrames = 0;
    FILE *g_log = nullptr;
    FILE *g_pagesLog = nullptr;
    FILE *g_sndLog = nullptr;
    ps2_rollback::Snapshot g_snapshot;
    uint64_t g_snapshotFrame = 0;
    TestState g_test;
    NetState g_net;
    std::map<uint64_t, FrameIop> g_iop;
    FrameIop *g_iopFrame = nullptr;
    RpcRecord *g_iopRpc = nullptr; // live RPC being recorded
    IopStats g_iopStats;
    uint32_t g_frameCuts = 0;       // cuts active while the current frame executes
    std::chrono::steady_clock::time_point g_lastBoundary{};
    uint64_t g_lastWaitNs = 0;
    uint64_t g_lastCycle = 0;
    uint64_t g_lastTick = 0;
    uint64_t g_lastLoops = 0;
    uint64_t g_lastIdle = 0;
    double g_hookMs = 0;
    std::map<std::string, uint64_t> g_wakeCounts;
    std::vector<uint64_t> g_prevPages; // previous boundary's page hashes: dirty-page count per frame
    uint64_t g_gsNs = 0, g_lastGsNs = 0; // host time in GS packet processing on the EE thread
    std::chrono::steady_clock::time_point g_start{};
    std::map<std::string, TimeSamples> g_eeByKind; // EE ms per executed frame, by pass kind
    ps2_rollback::HostProfile g_lastProfile;               // host profile counters at the previous boundary

    uint64_t parseNumber(const std::string &text)
    {
        return std::strtoull(text.c_str(), nullptr, 0);
    }

    std::vector<std::string> split(const std::string &text, char by)
    {
        std::vector<std::string> out;
        std::stringstream stream(text);
        for (std::string item; std::getline(stream, item, by);)
            if (!item.empty())
                out.push_back(item);
        return out;
    }

    uint16_t buttonByName(const std::string &name)
    {
        static const std::pair<const char *, uint16_t> kNames[] = {
            {"Up", kBtnUp}, {"Down", kBtnDown}, {"Left", kBtnLeft}, {"Right", kBtnRight}, {"Start", kBtnStart},
            {"Select", kBtnSelect}, {"Cross", kBtnCross}, {"Circle", kBtnCircle}, {"Square", kBtnSquare},
            {"Triangle", kBtnTriangle}, {"L1", kBtnL1}, {"R1", kBtnR1}, {"L2", kBtnL2}, {"R2", kBtnR2}};
        for (const auto &[text, bit] : kNames)
            if (name == text)
                return bit;
        RUNTIME_LOG("[rollback] unknown button " << name << "\n");
        return 0;
    }

    // Pseudo-random fight input as a pure function of the frame: a new choice every 6 frames.
    uint16_t fuzzButtons(uint64_t frame, uint64_t salt = 0)
    {
        uint64_t x = (frame / 6u) * 0x9E3779B97F4A7C15ull + 0x1234567u + salt * 0xD1B54A32D192ED03ull;
        x ^= x >> 31;
        x *= 0xBF58476D1CE4E5B9ull;
        x ^= x >> 29;
        static const uint16_t kDirs[] = {0, 0, kBtnLeft, kBtnRight, kBtnDown, kBtnUp, kBtnRight | kBtnDown,
                                         kBtnLeft | kBtnDown, kBtnRight, kBtnRight};
        static const uint16_t kAttacks[] = {0, kBtnSquare, kBtnTriangle, kBtnCross, kBtnCircle, kBtnSquare | kBtnTriangle,
                                            kBtnCross | kBtnCircle, 0, kBtnSquare, kBtnCross};
        const uint16_t dir = kDirs[x % 10u];
        const uint16_t attack = ((frame % 6u) < 3u) ? kAttacks[(x >> 8) % 10u] : 0u; // press then release
        return static_cast<uint16_t>(dir | attack);
    }

    uint16_t scriptedButtons(int pad, uint64_t frame)
    {
        const PadScript &script = g_cfg.pads[pad];
        uint16_t buttons = 0;
        for (const ScriptPress &press : script.presses)
            if (frame >= press.frame && frame < press.frame + press.hold)
                buttons |= press.buttons;
        if (frame >= script.fuzzFrom && frame < script.fuzzTo)
            buttons |= fuzzButtons(frame, script.salt);
        return buttons;
    }

    // selfnet: the remote (pad 2) input a run of frame k uses: the true one once revealed, else the last revealed.
    uint16_t remoteInputFor(uint64_t k)
    {
        if (k < g_cfg.netStart || k <= g_net.revealed)
            return scriptedButtons(1, k);
        return scriptedButtons(1, g_net.revealed);
    }

#ifdef TEKKEN4_NETPLAY
    bool npPadInput(int port, uint16_t &buttons, uint8_t (&axes)[4]); // netplay section below
    bool npResimulating(uint64_t *liveFrame);
#endif

    bool padProvider(int port, uint16_t &buttons, uint8_t (&axes)[4])
    {
#ifdef TEKKEN4_NETPLAY
        if (g_cfg.mode == Mode::Net)
            return npPadInput(port, buttons, axes);
#endif
        (void)axes;
        uint16_t pressed = 0;
        if (port == 0)
        {
            pressed = scriptedButtons(0, g_frame);
            if (g_test.wrong)
                pressed = static_cast<uint16_t>((fuzzButtons(g_frame * 7u + 3u) | kBtnLeft) & ~(kBtnStart | kBtnSelect));
        }
        else if (port == 1 && g_cfg.pad2)
        {
            if (g_cfg.mode == Mode::SelfNet)
            {
                const auto it = g_net.usedRemote.find(g_frame);
                pressed = it != g_net.usedRemote.end() ? it->second : remoteInputFor(g_frame);
            }
            else
                pressed = scriptedButtons(1, g_frame);
        }
        else
            return false; // not connected (as with no host gamepad)
        buttons = static_cast<uint16_t>(~pressed);
        return true;
    }

    // ---------------------------------------------------------------- IOP gate
    std::string hexBytes(const uint8_t *data, size_t size, size_t limit = 0x80)
    {
        std::string text;
        char buffer[4];
        for (size_t i = 0; i < size && i < limit; ++i)
        {
            std::snprintf(buffer, sizeof(buffer), "%02x", data[i]);
            text += buffer;
            if ((i & 3u) == 3u)
                text += ' ';
        }
        return text;
    }

    std::vector<uint8_t> guestBytes(uint32_t address, uint32_t size)
    {
        std::vector<uint8_t> out;
        if (size == 0 || size > 0x10000u)
            return out;
        uint8_t *rdram = g_runtime->memory().getRDRAM();
        if (const uint8_t *src = getMemPtr(rdram, address))
            out.assign(src, src + size);
        return out;
    }

    void applyEffect(const IopEffect &effect)
    {
        if (effect.kind == 2)
        {
            ps2_stubs::dispatchSifCommand(g_runtime->memory().getRDRAM(), g_runtime, effect.address,
                                          effect.data.data(), effect.data.size());
            return;
        }
        if (!effect.host)
            return;
        if (effect.kind == 1)
            std::memset(effect.host, 0, effect.size);
        else
            std::memcpy(effect.host, effect.data.data(), effect.data.size());
    }

    class Gate final : public ps2_rollback::IopGate
    {
    public:
        void guestWrite(uint32_t address, const uint8_t *data, size_t size) override
        {
            if (ps2_rollback::cutActive(ps2_rollback::CutIop))
            {
                ++g_iopStats.frozenWritesIgnored; // a forwarded call while frozen: not part of the log
                return;
            }
            IopEffect effect;
            effect.kind = data ? 0 : 1;
            effect.address = address;
            effect.host = getMemPtr(g_runtime->memory().getRDRAM(), address);
            effect.cycle = g_runtime->eeScheduler().eeCycle();
            effect.size = size;
            if (data)
                effect.data.assign(data, data + size);
            record(std::move(effect));
        }

        void sifCommand(uint32_t commandId, const uint8_t *packet, size_t size) override
        {
            if (ps2_rollback::cutActive(ps2_rollback::CutIop))
            {
                ++g_iopStats.frozenWritesIgnored;
                return;
            }
            IopEffect effect;
            effect.kind = 2;
            effect.address = commandId;
            effect.cycle = g_runtime->eeScheduler().eeCycle();
            effect.size = size;
            if (packet)
                effect.data.assign(packet, packet + size);
            ++g_iopStats.liveSifCmds;
            record(std::move(effect));
        }

        void rpcBegin(const ps2x::iop::RpcRequest &request) override
        {
            FrameIop &frame = currentFrame();
            frame.rpcs.emplace_back();
            RpcRecord &rec = frame.rpcs.back();
            rec.sid = request.sid;
            rec.function = request.function;
            rec.send = guestBytes(request.send.address, request.send.size);
            g_iopRpc = &rec;
            ++g_iopStats.liveRpcs;
        }

        void rpcEnd(const ps2x::iop::RpcRequest &request, const ps2x::iop::RpcResult &result) override
        {
            if (g_iopRpc)
            {
                g_iopRpc->result = result;
                if (g_sndLog)
                {
                    const std::vector<uint8_t> reply = guestBytes(request.receive.address, request.receive.size);
                    std::fprintf(g_sndLog, "L f=%" PRIu64 " cyc=%" PRIu64 " sid=%x fn=%x send=%u recv=%x/%u eff=%zu\n  S %s\n  Q %s\n",
                                 g_frame, g_runtime->eeScheduler().eeCycle(), request.sid, request.function,
                                 request.send.size, request.receive.address, request.receive.size,
                                 g_iopRpc->effects.size(), hexBytes(g_iopRpc->send.data(), g_iopRpc->send.size()).c_str(),
                                 hexBytes(reply.data(), reply.size(), 0x40).c_str());
                }
            }
            g_iopRpc = nullptr;
        }

        void frozenAdvance(uint64_t eeCycle) override
        {
            FrameIop *frame = g_iopFrame;
            if (!frame)
                return;
            while (frame->asyncCursor < frame->async.size() && frame->async[frame->asyncCursor].cycle <= eeCycle)
            {
                applyEffect(frame->async[frame->asyncCursor++]);
                ++g_iopStats.asyncReplayed;
            }
        }

        ps2x::iop::RpcResult frozenRpc(const ps2x::iop::RpcRequest &request,
                                       const std::function<ps2x::iop::RpcResult()> &forward) override
        {
            FrameIop &frame = currentFrame();
            const size_t index = frame.rpcCursor++;
            RpcRecord *rec = index < frame.rpcs.size() ? &frame.rpcs[index] : nullptr;
            if (rec && (rec->sid != request.sid || rec->function != request.function))
                rec = nullptr;
            if (!rec)
            {
                ++g_iopStats.forwardedUnlogged;
                if (g_sndLog)
                    std::fprintf(g_sndLog, "F f=%" PRIu64 " sid=%x fn=%x idx=%zu: no log, forwarded\n", g_frame,
                                 request.sid, request.function, index);
                return forward();
            }
            const std::vector<uint8_t> send = guestBytes(request.send.address, request.send.size);
            const bool same = send == rec->send;
            if (!same && g_cfg.sndForward)
            {
                ++g_iopStats.forwardedDiff;
                if (g_sndLog)
                    std::fprintf(g_sndLog, "F f=%" PRIu64 " sid=%x fn=%x idx=%zu: differs, forwarded\n  S %s\n", g_frame,
                                 request.sid, request.function, index, hexBytes(send.data(), send.size()).c_str());
                return forward();
            }
            ++(same ? g_iopStats.replayedSame : g_iopStats.replayedDiff);
            for (const IopEffect &effect : rec->effects)
                applyEffect(effect);
            if (g_sndLog && !same)
                std::fprintf(g_sndLog, "D f=%" PRIu64 " sid=%x fn=%x idx=%zu: differs, logged reply written\n  S %s\n",
                             g_frame, request.sid, request.function, index, hexBytes(send.data(), send.size()).c_str());
            return rec->result;
        }

        bool frozenIopWrite(uint32_t address, size_t size) override
        {
            (void)address;
            (void)size;
            ++g_iopStats.eeToIopSuppressed;
            return false;
        }

    private:
        static FrameIop &currentFrame()
        {
            if (!g_iopFrame)
                g_iopFrame = &g_iop[g_frame];
            return *g_iopFrame;
        }

        static void record(IopEffect &&effect)
        {
            if (g_iopRpc)
            {
                g_iopRpc->effects.push_back(std::move(effect));
                return;
            }
            ++g_iopStats.liveAsync;
            if (g_sndLog)
                std::fprintf(g_sndLog, "A f=%" PRIu64 " cyc=%" PRIu64 " kind=%u addr=%x size=%zu\n", g_frame, effect.cycle,
                             effect.kind, effect.address, effect.size);
            currentFrame().async.push_back(std::move(effect));
        }
    };

    Gate g_gate;

    // A frame starts executing: live frames get a fresh IOP log, re-simulated ones replay theirs from the start.
    void startFrameIop(bool live)
    {
        if (g_iopFrame && !live && g_iopFrame->asyncCursor < g_iopFrame->async.size())
            g_iopStats.asyncLeft += g_iopFrame->async.size() - g_iopFrame->asyncCursor;
        FrameIop &frame = g_iop[g_frame];
        if (live)
            frame = FrameIop{};
        frame.asyncCursor = 0;
        frame.rpcCursor = 0;
        g_iopFrame = &frame;
        g_iopRpc = nullptr;
        while (!g_iop.empty() && g_iop.begin()->first + 256u < g_frame)
            g_iop.erase(g_iop.begin());
    }

    // ---------------------------------------------------------------- logging helpers
    const char *reasonName(EeWaitReason reason)
    {
        switch (reason)
        {
        case EeWaitReason::None: return "none";
        case EeWaitReason::Sleep: return "sleep";
        case EeWaitReason::Semaphore: return "sema";
        case EeWaitReason::EventFlag: return "evf";
        case EeWaitReason::VSync: return "vsync";
        case EeWaitReason::External: return "ext";
        case EeWaitReason::Mpeg: return "mpeg";
        }
        return "?";
    }

    bool isBoundary(const EeBoundaryInfo &info)
    {
        if (g_cfg.boundaryVblank)
            return info.vblank;
        if (g_cfg.boundaryAny)
            return true;
        if (info.reason != g_cfg.boundaryReason)
            return false;
        return g_cfg.boundaryId < 0 || info.waitId == g_cfg.boundaryId;
    }

    void dumpFrame(uint64_t frame)
    {
        PS2Memory &memory = g_runtime->memory();
        {
            std::ofstream out("rb_dump_f" + std::to_string(frame) + ".bin", std::ios::binary);
            out.write(reinterpret_cast<const char *>(memory.getRDRAM()), PS2_RAM_SIZE);
            out.write(reinterpret_cast<const char *>(memory.getScratchpad()), PS2_SCRATCHPAD_SIZE);
        }
        std::vector<uint8_t> digest;
        g_runtime->eeScheduler().appendStateDigest(digest);
        std::ofstream out("rb_sched_f" + std::to_string(frame) + ".bin", std::ios::binary);
        out.write(reinterpret_cast<const char *>(digest.data()), static_cast<std::streamsize>(digest.size()));
        g_runtime->eeScheduler().publishSnapshot();
        const EeKernelSnapshot kernel = g_runtime->eeScheduler().snapshot();
        for (const EeThreadSnapshot &thread : kernel.threads)
            std::fprintf(g_log, "THREAD f=%" PRIu64 " id=%d status=%d wait=%s:%d prio=%d pc=0x%08x entry=0x%08x"
                                " invocations=%u\n",
                         frame, thread.id, static_cast<int>(thread.status), reasonName(thread.waitReason), thread.waitId,
                         thread.currentPriority, thread.pc, thread.entry, thread.invocationDepth);
        RUNTIME_LOG("[rollback] dumped frame " << frame << "\n");
    }

    std::string regionsText(const ps2_rollback::StateHash &hash)
    {
        std::string text;
        char buffer[16];
        for (int r = 0; r < 32; ++r)
        {
            std::snprintf(buffer, sizeof(buffer), "%04x", static_cast<unsigned>(hash.regions[r] & 0xFFFFu));
            text += buffer;
        }
        return text;
    }

    void logPageDiff(uint64_t frame, const std::vector<uint64_t> &now)
    {
        const auto it = g_test.firstPages.find(frame);
        if (it == g_test.firstPages.end())
            return;
        int shown = 0;
        size_t total = 0;
        std::string pages;
        for (size_t p = 0; p < now.size(); ++p)
        {
            if (now[p] == it->second[p])
                continue;
            ++total;
            if (shown++ < 24)
            {
                char buffer[24];
                std::snprintf(buffer, sizeof(buffer), " %07zx", p * 4096u);
                pages += buffer;
            }
        }
        std::fprintf(g_log, "  pages differing: %zu:%s\n", total, pages.c_str());
        const auto ram = g_test.firstRam.find(frame);
        if (ram == g_test.firstRam.end())
            return;
        const uint8_t *current = g_runtime->memory().getRDRAM();
        int words = 0;
        for (uint32_t a = 0; a < PS2_RAM_SIZE && words < 64; a += 4)
        {
            uint32_t before = 0, after = 0;
            std::memcpy(&before, ram->second.data() + a, 4);
            std::memcpy(&after, current + a, 4);
            if (before != after)
            {
                std::fprintf(g_log, "  word %07x: first %08x resim %08x\n", a, before, after);
                ++words;
            }
        }
    }

    double percentile(const TimeSamples &values, double p)
    {
        return values.percentile(p);
    }

    std::string costText()
    {
        std::string text;
        char buffer[160];
        for (const auto &[kind, values] : g_eeByKind)
        {
            std::snprintf(buffer, sizeof(buffer), " %s:n=%zu,p50=%.2f,p90=%.2f,max=%.2f", kind.c_str(), values.size(),
                          percentile(values, 0.5), percentile(values, 0.9), percentile(values, 1.0));
            text += buffer;
        }
        return text;
    }

    std::string iopText()
    {
        char buffer[400];
        std::snprintf(buffer, sizeof(buffer),
                      "live rpcs %" PRIu64 " async %" PRIu64 " sifcmds %" PRIu64 "; frozen: replayed same %" PRIu64
                      " diff %" PRIu64 ", forwarded diff %" PRIu64 " unlogged %" PRIu64 ", async replayed %" PRIu64
                      " left %" PRIu64 ", EE->IOP writes suppressed %" PRIu64 ", writes of forwarded calls %" PRIu64,
                      g_iopStats.liveRpcs, g_iopStats.liveAsync, g_iopStats.liveSifCmds, g_iopStats.replayedSame,
                      g_iopStats.replayedDiff, g_iopStats.forwardedDiff, g_iopStats.forwardedUnlogged,
                      g_iopStats.asyncReplayed, g_iopStats.asyncLeft, g_iopStats.eeToIopSuppressed,
                      g_iopStats.frozenWritesIgnored);
        return buffer;
    }

    // ---------------------------------------------------------------- test mode
    // Restores the snapshot and checks the restored state against the first pass's hash of that frame.
    void rollBack(const char *from)
    {
        const auto restoreStart = std::chrono::steady_clock::now();
        const uint64_t fromFrame = g_frame;
        ps2_rollback::restore(*g_runtime, g_snapshot);
        g_frame = g_snapshotFrame;
        const double ms =
            std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - restoreStart).count();
        g_test.restoreMs += ms;
        g_test.maxRestoreMs = std::max(g_test.maxRestoreMs, ms);
        g_test.passRestoreMs = ms;
        g_test.passEeMs = 0;
        g_test.passFrames = 0;
        ++g_test.rollbacks;
        std::vector<uint64_t> restoredPages;
        const ps2_rollback::StateHash restored = ps2_rollback::hashState(*g_runtime, g_cfg.masks, &restoredPages);
        const auto saved = g_test.firstPass.find(g_frame);
        const bool ok = saved != g_test.firstPass.end() && saved->second.total == restored.total;
        if (ok)
            ++g_test.restoredOk;
        else
        {
            ++g_test.restoredBad;
            std::fprintf(g_log, "RESTORE MISMATCH at frame %" PRIu64 ": saved h=%016" PRIx64 " restored h=%016" PRIx64
                                " ram %016" PRIx64 "/%016" PRIx64 " oth %016" PRIx64 "/%016" PRIx64 " sch %016" PRIx64
                                "/%016" PRIx64 "\n",
                         g_frame, saved != g_test.firstPass.end() ? saved->second.total : 0, restored.total,
                         saved != g_test.firstPass.end() ? saved->second.rdram : 0, restored.rdram,
                         saved != g_test.firstPass.end() ? saved->second.other : 0, restored.other,
                         saved != g_test.firstPass.end() ? saved->second.scheduler : 0, restored.scheduler);
            logPageDiff(g_frame, restoredPages);
        }
        std::fprintf(g_log, "ROLLBACK cycle %" PRIu64 " depth %" PRIu64 " after %s: %" PRIu64 " -> %" PRIu64
                            " restore %.2f ms, restored state %s\n",
                     g_test.cycle, g_test.depth, from, fromFrame, g_frame, ms, ok ? "OK" : "BAD");
    }

    bool frameIsResimulating()
    {
        if (g_cfg.mode == Mode::Test)
            return g_test.resim || g_test.wrong;
        if (g_cfg.mode == Mode::SelfNet)
            return g_net.resim;
#ifdef TEKKEN4_NETPLAY
        if (g_cfg.mode == Mode::Net)
        {
            uint64_t target = 0;
            return npResimulating(&target);
        }
#endif
        return false;
    }

    // Which cuts the frame about to execute (g_frame) runs with.
    uint32_t cutsForNextFrame()
    {
        bool resim = false;
        uint64_t target = 0;
        bool tailAllowed = false;
        if (g_cfg.mode == Mode::Test)
        {
            resim = g_test.resim || g_test.wrong;
            target = g_test.targetFrame;
            tailAllowed = g_test.resim;
        }
        else if (g_cfg.mode == Mode::SelfNet)
        {
            resim = g_net.resim;
            target = g_net.liveFrame;
            tailAllowed = true;
        }
#ifdef TEKKEN4_NETPLAY
        else if (g_cfg.mode == Mode::Net)
        {
            resim = npResimulating(&target);
            tailAllowed = true;
        }
#endif
        if (!resim)
            return 0;
        uint32_t cuts = g_cfg.cuts;
        // frame g_frame ends at boundary g_frame+1; the last cutTail frames before the target draw again
        if (tailAllowed && g_frame + g_cfg.cutTail >= target)
            cuts &= ~static_cast<uint32_t>(ps2_rollback::CutDraw | ps2_rollback::CutUpload | ps2_rollback::CutVu1);
        return cuts;
    }

    void testBoundary(const ps2_rollback::StateHash &hash, const std::vector<uint64_t> &pages, double eeMs)
    {
        if (g_test.resim)
        {
            g_test.passEeMs += eeMs;
            ++g_test.passFrames;
            const auto it = g_test.firstPass.find(g_frame);
            ++g_test.compared;
            const bool same = it != g_test.firstPass.end() && it->second.total == hash.total;
            if (!same)
            {
                ++g_test.mismatches;
                std::fprintf(g_log, "MISMATCH resim frame %" PRIu64 " (cycle %" PRIu64 ", depth %" PRIu64
                                    "): first h=%016" PRIx64 " ram=%016" PRIx64 " oth=%016" PRIx64 " sch=%016" PRIx64
                                    " reg=%s\n",
                             g_frame, g_test.cycle, g_test.depth, it != g_test.firstPass.end() ? it->second.total : 0,
                             it != g_test.firstPass.end() ? it->second.rdram : 0,
                             it != g_test.firstPass.end() ? it->second.other : 0,
                             it != g_test.firstPass.end() ? it->second.scheduler : 0,
                             it != g_test.firstPass.end() ? regionsText(it->second).c_str() : "");
                logPageDiff(g_frame, pages);
            }
            if (g_frame >= g_test.targetFrame)
            {
                g_test.resim = false;
                g_test.firstPass.clear();
                g_test.firstPages.clear();
                g_test.firstRam.clear();
                std::fprintf(g_log, "PASSCOST cycle %" PRIu64 " depth %" PRIu64 " restore %.2f resim %.2f ms (%.2f per frame)\n",
                             g_test.cycle, g_test.depth, g_test.passRestoreMs, g_test.passEeMs,
                             g_test.passFrames ? g_test.passEeMs / static_cast<double>(g_test.passFrames) : 0.0);
                g_eeByKind["pass" + std::to_string(g_test.depth)].push_back(g_test.passRestoreMs + g_test.passEeMs);
            }
        }
        else if (g_test.active)
        {
            g_test.firstPass[g_frame] = hash;
            g_test.firstPages[g_frame] = pages;
            if (g_cfg.testWords)
            {
                const uint8_t *ram = g_runtime->memory().getRDRAM();
                g_test.firstRam[g_frame].assign(ram, ram + PS2_RAM_SIZE);
            }
            if (g_frame >= g_test.targetFrame)
            {
                rollBack("first pass");
                g_test.active = false;
                if (g_cfg.testMispredict)
                {
                    g_test.wrong = true;
                    g_test.wrongSawDiff = false;
                    ++g_test.wrongPasses;
                }
                else
                    g_test.resim = true;
                // The re-run starts here: the next boundaries are frames saveFrame+1 .. targetFrame again.
            }
        }
        else if (g_test.wrong)
        {
            // Wrong-input pass (a mispredicted timeline): only check that it really diverged.
            const auto it = g_test.firstPass.find(g_frame);
            if (it != g_test.firstPass.end() && it->second.total != hash.total)
                g_test.wrongSawDiff = true;
            if (g_frame >= g_test.targetFrame)
            {
                if (g_test.wrongSawDiff)
                    ++g_test.wrongDiverged;
                g_test.wrong = false;
                rollBack("wrong-input pass");
                g_test.resim = true;
            }
        }
        else if (g_frame >= g_cfg.testStart && (g_frame - g_cfg.testStart) % g_cfg.testEvery == 0)
        {
            const auto saveStart = std::chrono::steady_clock::now();
            ps2_rollback::capture(*g_runtime, g_snapshot);
            g_snapshotFrame = g_frame;
            const double ms =
                std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - saveStart).count();
            g_test.saveMs += ms;
            g_test.maxSaveMs = std::max(g_test.maxSaveMs, ms);
            ++g_test.cycle;
            g_test.depth = 1u + (g_test.cycle - 1u) % g_cfg.testDepth;
            g_test.saveFrame = g_frame;
            g_test.targetFrame = g_frame + g_test.depth;
            g_test.active = true;
            g_test.firstPass.clear();
            g_test.firstPages.clear();
            g_test.firstRam.clear();
            g_test.firstPass[g_frame] = hash;
            g_test.firstPages[g_frame] = pages;
        }
        if (g_wallFrames % 600u == 0u)
        {
            std::fprintf(g_log,
                         "SUMMARY wall frames %" PRIu64 " logical %" PRIu64 ": rollbacks %" PRIu64 " restore ok %" PRIu64
                         " bad %" PRIu64 ", resim frames compared %" PRIu64 " mismatches %" PRIu64
                         ", wrong-input passes %" PRIu64 " diverged %" PRIu64
                         ", save avg %.2f max %.2f ms, restore avg %.2f max %.2f ms\n",
                         g_wallFrames, g_frame, g_test.rollbacks, g_test.restoredOk, g_test.restoredBad,
                         g_test.compared, g_test.mismatches, g_test.wrongPasses, g_test.wrongDiverged,
                         g_test.cycle ? g_test.saveMs / g_test.cycle : 0.0,
                         g_test.maxSaveMs, g_test.rollbacks ? g_test.restoreMs / g_test.rollbacks : 0.0,
                         g_test.maxRestoreMs);
        }
    }

    // ---------------------------------------------------------------- selfnet mode
    void netCapture()
    {
        const size_t slot = g_frame % g_net.ring.size();
        const auto t0 = std::chrono::steady_clock::now();
        ps2_rollback::capture(*g_runtime, g_net.ring[slot]);
        g_net.ringFrame[slot] = g_frame;
        g_net.captureMs += std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        ++g_net.captures;
    }

    uint64_t jitterFor(uint64_t frame)
    {
        if (g_cfg.netJitter == 0)
            return 0;
        uint64_t x = frame * 0x9E3779B97F4A7C15ull + 0x51u;
        x ^= x >> 29;
        x *= 0xBF58476D1CE4E5B9ull;
        x ^= x >> 32;
        return x % (g_cfg.netJitter + 1u);
    }

    void netBoundary(double eeMs)
    {
        if (g_frame < g_cfg.netStart)
        {
            g_net.revealed = g_frame; // before the start everything is known (menus, lockstep-like)
            return;
        }
        if (g_net.resim)
        {
            g_net.passEeMs += eeMs;
            ++g_net.resimFrames;
            netCapture(); // the corrected state of this boundary replaces the mispredicted one
            if (g_frame >= g_net.liveFrame)
            {
                g_net.resim = false;
                g_net.passCost.push_back(g_net.passEeMs);
            }
            else
            {
                g_net.usedRemote[g_frame] = remoteInputFor(g_frame);
                return;
            }
        }
        else
        {
            netCapture();
            // Reveal the remote input that "arrives" now: frames up to f - delay - jitter, never more than max behind.
            const uint64_t lag = g_cfg.netDelay + jitterFor(g_frame);
            uint64_t newRevealed = g_frame > lag ? g_frame - lag : 0;
            newRevealed = std::max(newRevealed, g_net.revealed);
            if (g_frame > g_cfg.netMax)
                newRevealed = std::max(newRevealed, g_frame - g_cfg.netMax);
            newRevealed = std::min(newRevealed, g_frame - 1u);
            uint64_t firstWrong = ~0ull;
            for (uint64_t k = g_net.revealed + 1u; k <= newRevealed; ++k)
            {
                ++g_net.revealedFrames;
                const auto used = g_net.usedRemote.find(k);
                if (k >= g_cfg.netStart && used != g_net.usedRemote.end() && used->second != scriptedButtons(1, k))
                {
                    firstWrong = std::min(firstWrong, k);
                    ++g_net.mispredicted;
                }
            }
            g_net.revealed = newRevealed;
            if (firstWrong != ~0ull)
            {
                const size_t slot = firstWrong % g_net.ring.size();
                if (g_net.ringFrame[slot] != firstWrong)
                    std::fprintf(g_log, "NET no snapshot for frame %" PRIu64 " (have %" PRIu64 ")\n", firstWrong,
                                 g_net.ringFrame[slot]);
                else
                {
                    const uint64_t depth = g_frame - firstWrong;
                    const auto t0 = std::chrono::steady_clock::now();
                    ps2_rollback::restore(*g_runtime, g_net.ring[slot]);
                    const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
                    g_net.restoreMs += ms;
                    g_net.passEeMs = ms;
                    ++g_net.rollbacks;
                    g_net.maxDepth = std::max(g_net.maxDepth, depth);
                    ++g_net.depthHist[std::min<uint64_t>(depth, 16u)];
                    g_net.liveFrame = g_frame;
                    g_net.resim = true;
                    g_frame = firstWrong;
                }
            }
        }
        g_net.usedRemote[g_frame] = remoteInputFor(g_frame);
        while (!g_net.usedRemote.empty() && g_net.usedRemote.begin()->first + 64u < g_frame)
            g_net.usedRemote.erase(g_net.usedRemote.begin());
        if (g_wallFrames % 600u == 0u)
        {
            std::string hist;
            for (int d = 0; d <= 16; ++d)
                if (g_net.depthHist[d])
                    hist += " " + std::to_string(d) + ":" + std::to_string(g_net.depthHist[d]);
            std::fprintf(g_log,
                         "NETSUMMARY wall frames %" PRIu64 " logical %" PRIu64 ": rollbacks %" PRIu64 " resim frames %" PRIu64
                         " mispredicted %" PRIu64 " of %" PRIu64 " revealed, max depth %" PRIu64 " depths%s; restore avg %.2f,"
                         " capture avg %.2f ms, rollback cost p50 %.2f p90 %.2f max %.2f ms\n",
                         g_wallFrames, g_frame, g_net.rollbacks, g_net.resimFrames, g_net.mispredicted,
                         g_net.revealedFrames, g_net.maxDepth, hist.c_str(),
                         g_net.rollbacks ? g_net.restoreMs / static_cast<double>(g_net.rollbacks) : 0.0,
                         g_net.captures ? g_net.captureMs / static_cast<double>(g_net.captures) : 0.0,
                         percentile(g_net.passCost, 0.5), percentile(g_net.passCost, 0.9), percentile(g_net.passCost, 1.0));
        }
    }

    // ---------------------------------------------------------------- final-state hash (netplay desync check)
    // What both peers compare: RDRAM, scratchpad, VU0 data, the IOP (RAM, SPU2 RAM, CPU/kernel) and the EE cycle
    // of a boundary's snapshot. VU1 data memory and GS state are output (phase 2) and left out.
    struct NetHash
    {
        uint64_t total = 0, ram = 0, iop = 0, cycle = 0;
    };

    uint64_t mix64(uint64_t h)
    {
        h ^= h >> 33;
        h *= 0xff51afd7ed558ccdull;
        h ^= h >> 33;
        h *= 0xc4ceb9fe1a85ec53ull;
        h ^= h >> 33;
        return h;
    }

    NetHash netHashOf(const ps2_rollback::Snapshot &snap, uint64_t cycle)
    {
        NetHash h;
        h.ram = ps2_rollback::hashBytes(snap.rdram.data(), snap.rdram.size(), 11);
        h.ram = mix64(h.ram ^ ps2_rollback::hashBytes(snap.scratchpad.data(), snap.scratchpad.size(), 12));
        h.ram = mix64(h.ram ^ ps2_rollback::hashBytes(snap.vu0Data.data(), snap.vu0Data.size(), 13));
#ifdef PS2X_ROLLBACK_IOP_STATE
        h.iop = ps2_rollback::hashIop(snap);
#endif
        h.cycle = cycle;
        h.total = mix64(h.ram ^ mix64(h.iop + 0x9E3779B97F4A7C15ull) ^ mix64(cycle * 0xD1B54A32D192ED03ull));
        return h;
    }

    // measure mode with TEKKEN4_NET_HASH_EVERY: the same NETHASH lines as netplay (a reference run to compare with)
    void measureNetHash(uint64_t cycle)
    {
        if (!g_cfg.hashEvery || g_frame % g_cfg.hashEvery != 0u)
            return;
        ps2_rollback::capture(*g_runtime, g_snapshot);
        const NetHash h = netHashOf(g_snapshot, cycle);
        std::fprintf(g_log, "NETHASH f=%" PRIu64 " h=%016" PRIx64 " ram=%016" PRIx64 " iop=%016" PRIx64 " cyc=%" PRIu64 "\n",
                     g_frame, h.total, h.ram, h.iop, h.cycle);
    }

#ifdef TEKKEN4_NETPLAY
    // ---------------------------------------------------------------- netplay (phase 3)
    // GGPO-style loop over the UDP transport (tekken4_net.cpp), T5DR's rb_net.cpp adapted to this driver: per live
    // boundary f a snapshot, this side's input for f + delay sampled and sent, the peer's inputs that came in checked
    // against the predictions the frames ran with (prediction = the last confirmed input repeats); the first wrong
    // frame g -> restore g's snapshot (IOP included), re-simulate g..f-1 with the cuts (draw, present, vu1; last frame
    // drawn), SPU2 output muted, then the live frame f. Frames before TEKKEN4_NET_RBSTART run in lockstep.
    constexpr uint32_t kHist = 4096;
    constexpr int kMaxLockDelay = 12;
    constexpr auto kVblank = std::chrono::microseconds(16667);

    // Quarter-ms upper-bound buckets through 64 ms, then one overflow bucket. These are host diagnostics only:
    // never serialized, hashed, used to choose inputs/cuts or used to advance the emulated machine.
    struct NetCostHistogram
    {
        uint64_t bins[258]{}, count = 0;
        double sum = 0, maximum = 0;

        void add(double ms)
        {
            if (!std::isfinite(ms) || ms < 0.0)
                return;
            const size_t bin = ms > 64.0 ? 257u : static_cast<size_t>(std::ceil(ms * 4.0));
            ++bins[bin];
            ++count;
            sum += ms;
            maximum = std::max(maximum, ms);
        }

        double upper(double fraction) const
        {
            if (!count)
                return 0.0;
            const uint64_t rank = static_cast<uint64_t>(std::ceil(fraction * static_cast<double>(count)));
            uint64_t seen = 0;
            for (size_t bin = 0; bin < 258u; ++bin)
            {
                seen += bins[bin];
                if (seen >= rank)
                    return bin == 257u ? maximum : static_cast<double>(bin) * 0.25;
            }
            return maximum;
        }
    };

    struct NetplayState
    {
        bool on = false, started = false, failed = false;
        int slot = 0;
        int delay = 0;
        // phase 3b: the lockstep's own input delay (boot: every input confirmed; each side samples its pad far
        // enough ahead that the peer's input is there when the frame comes, -1 = by round trip)
        int lockDelaySetting = -1, lockDelay = 0;
        uint64_t maxPred = 8, rbStart = 600, endFrame = ~0ull, tsFrom = 0;
        bool timeSync = true, localPad = true, dump = false, ended = false;
        bool fastSync = false;
        bool subframeSync = false;
        int syncSpread = 8;                                              // TEKKEN4_NET_SYNC_SPREAD
        std::chrono::steady_clock::duration spreadLeft{}, spreadSlice{}; // time-sync give still to hand out
        uint64_t spreadSlices = 0;
        bool fullSync = false;
        bool syncCapOne = false;
        bool syncGapReset = false;
        bool syncWallHold = false;
        bool syncProgressOnly = false;
        // Host-only sample watermark; retained across corrections and guest restores.
        bool syncProgressSeen = false;
        uint64_t syncProgressRc = 0, syncProgressCandidates = 0, syncProgressRepeated = 0,
                 syncProgressSkipped = 0, syncProgressSamples = 0, syncProgressEvals = 0,
                 syncProgressCorrections = 0;
        // Host-only settling deadline, measured from correction end; never restored with guest state.
        std::chrono::steady_clock::time_point syncHoldEnd{};
        bool syncHoldReleased = false;
        uint64_t syncHoldEligible = 0, syncHoldReleases = 0, syncHoldSamples = 0;
        uint64_t syncHoldEvals = 0, syncHoldCorrections = 0;
        // Host-only sample lifetime experiment, observed in both arms; never restored with guest state.
        std::chrono::steady_clock::time_point syncVisit{};
        uint64_t syncGapEvents = 0, syncGapEligible = 0, syncGapResets = 0, syncGapDiscarded = 0;
        double syncGapMaxMs = 0;
        // Applied corrections in both arms; pre-cap durations also define the unchanged settling hold.
        uint64_t syncCapActions = 0, syncCapEligible = 0, syncCapChanged = 0;
        double syncCapBaseMs = 0, syncCapRequestedMs = 0, syncCapActualMs = 0, syncCapMaxMs = 0;
        bool atomicInput = false;
        bool replayBatch = false;
        bool replayBeforeSync = false;
        // Host-only selected correction; survives guest restore and is applied once at live catch-up.
        struct SyncCorrection
        {
            bool active = false, subframe = false;
            int wallSamples = 0;
            uint64_t frame = 0, rc = 0;
            double adv = 0;
            int frames = 0;
            std::chrono::microseconds give{}, baseGive{}, legacyGive{}, fullGive{};
            std::chrono::steady_clock::time_point selected{};
        } pendingSync;
        uint64_t replaySyncEligible = 0, replaySyncMismatch = 0, replaySyncDeferred = 0, replaySyncApplied = 0,
                 replaySyncFrame = 0, replaySyncFrom = 0;
        int64_t replaySyncDeferredUs = 0, replaySyncAppliedUs = 0;
        double replaySyncDelayMs = 0, replaySyncMaxDelayMs = 0;
        // Host-only bounded confirmation batching; one opportunity/wait per live frame, never restored.
        uint64_t batchSeenFrame = ~0ull, batchRollbackFrame = ~0ull;
        uint64_t batchOpportunities = 0, batchWaits = 0, batchEarlyWaits = 0, batchAdvanced = 0,
                 batchCompleted = 0, batchRevisits = 0, batchFrame = 0, batchBefore = 0, batchAfter = 0;
        double batchWaitMs = 0, batchMaxMs = 0;
        // Input-selection race observations; host-only, split by live/replay execution, never restored.
        uint64_t inputMisses[2]{}, inputRecovered[2]{}, inputAdvanced[2]{}, inputAheadFrontier[2]{},
                 inputFutureFallbacks[2]{};
        // Whole-lead duration experiment; host-only opportunities/actions in both arms, never restored.
        uint64_t fullSyncEvals = 0, fullSyncActions = 0, fullSyncChanged = 0, fullSyncLastFrame = 0;
        double fullSyncRequestedMs = 0, fullSyncLegacyMs = 0, fullSyncActualMs = 0, fullSyncLastAdv = 0;
        // Eligible filtered evaluations in both arms; actual fractional waits only with the switch on.
        uint64_t subframeEvals = 0, subframeCorrections = 0, subframeLastFrame = 0;
        double subframeMs = 0, subframeActualMs = 0, subframeLastAdv = 0;
        bool predHeadroom = false;
        bool sendFirst = false;
        bool deferResimFlush = false;
        bool bootRendezvous = false, rendezvousObserved = false;
        // Host-only phase experiment; never repeat the observation/wait during replay.
        uint64_t rendezvousFrame = 0, rendezvousTarget = 0, rendezvousLocalMax = 0,
                 rendezvousBefore = 0, rendezvousAfter = 0, rendezvousCalls = 0;
        bool rendezvousReady = false;
        double rendezvousMs = 0;
        // Host-only ordinary hook-end flush measurements, in both switch arms; explicit flushes are excluded.
        uint64_t deferredFlushes = 0, boundaryFlushes[2]{}; // live / replay about to execute
        double boundaryFlushMs[2]{}, boundaryFlushMaxMs[2]{};
        // Host-only timing of first-live capture + hash collection, before (OFF) or after (ON) input publication.
        uint64_t sendFirstFrames = 0, sendFirstInputs = 0, sendPrepFrames = 0, sendPrepFrame = 0;
        double sendPrepMs = 0, sendPrepMaxMs = 0, sendPrepLastMs = 0;
        // Prediction-wait experiment and host-only cumulative diagnostics; never restored with a snapshot.
        uint64_t headroomOpportunities = 0, headroomWaits = 0, headroomCompleted = 0, headroomRequested = 0;
        uint64_t headroomFrame = 0, headroomBefore = 0, headroomAfter = 0, headroomNeed = 0, headroomTarget = 0;
        double headroomWaitMs = 0;
        bool autoVs = false, autoVsReleased = false;
        uint64_t autoVsEnd = 1200;
        PadScript autoVsScript;
        // phase 3b: early rollback (T5 sec. 27): the boundary may come up to earlyMs before its vblank time; what is
        // already known to be mispredicted is rolled back in that wait, and inputs that arrive during it too
        bool early = true;
        bool earlyDeadline = false;
        uint64_t earlyDeadlineSkips = 0, earlyDeadlineRevisits = 0, earlyOverdueRollbacks = 0,
                 earlyOverdueRevisits = 0, earlyDeferredLate = 0;
        uint64_t earlyRollbackFrame = ~0ull, earlyDeferredFrame = ~0ull;
        double earlyMs = 4.0;
        bool lazy = true; // re-simulated boundaries no rollback can reach again are not captured (T5 sec. 33.4)
        bool hashProfile = false;
        bool costProfile = false;
        bool diag = false;
        bool refreshRc = false;
        bool rebaseCatchup = false;
        uint64_t catchupRebases = 0;
        double catchupDebtMs = 0;
        // Host diagnostics only. Totals are cumulative; maxima cover the last diagnostic interval.
        std::chrono::steady_clock::time_point diagLast{};
        double diagDebtMaxMs = 0, diagGapMaxMs = 0, diagRollbackMaxMs = 0,
               diagSyncActualMs = 0, diagSyncOverMaxMs = 0, diagWaitMaxMs = 0, diagAdv = 0;
        uint64_t diagWaitBefore = 0, diagWaitAfter = 0, diagWaitNeed = 0;
        NetCostHistogram frameCost[4][5]; // boot / live / cut resim / drawn resim tail; EE busy / GS / VIF / VU / IOP
        NetCostHistogram captureCost[2], restoreCost, rollbackCost;
        int padDevice = 0;
        std::vector<uint64_t> shots;
        size_t shotNext = 0;
        t4net::PadInput used[kHist];
        uint64_t usedTag[kHist]{};
        bool pred[kHist]{};
        t4net::PadInput inputs[2];
        uint64_t checked = 0, hashNext = 0, lastLiveFrame = 0;
        std::vector<ps2_rollback::Snapshot> ring;
        std::vector<uint64_t> ringFrame, ringCycle;
        bool resim = false, resimEarly = false;
        uint64_t liveFrame = 0, resimFrom = 0;
        uint64_t liveDone = ~0ull;                         // the live frame whose live part (input, time sync) ran
        uint64_t liveTFrame = ~0ull;                       // the frame liveT belongs to
        std::chrono::steady_clock::time_point liveT{};     // its vblank time (the schedule's, without the early margin)
        std::chrono::steady_clock::time_point liveVblank{}, rbT0{};
        // time sync (T5DR rb_net.cpp ts_correct: trimmed mean of the two lead estimates)
        static constexpr int kLeadWin = 20;
        int leadWindow = kLeadWin;
        int leadMine[kLeadWin]{}, leadTheirs[kLeadWin]{};
        bool leadWallSample[kLeadWin]{};
        int leadN = 0;
        uint64_t syncEvals = 0, syncEarlyEvals = 0, syncEvalFrame = 0, syncEarlyCorrections = 0;
        uint64_t lastCorrection = 0, tsHold = 0;
        // desync dump: RDRAM + scratchpad of the last hashed frames
        struct Kept
        {
            uint64_t frame = ~0ull;
            std::vector<uint8_t> ram;
        };
        Kept kept[3];
        int keptNext = 0;
        // statistics
        uint64_t liveFrames = 0, rollbacks = 0, resimFrames = 0, maxDepth = 0, depthHist[17]{}, predicted = 0,
                 mispredicted = 0, stalls = 0, lockWaits = 0, corrections = 0, rebases = 0, captures = 0, hashes = 0,
                 earlyRollbacks = 0, lazySkips = 0, over20 = 0, over34 = 0, timedFrames = 0;
        double stallMs = 0, lockWaitMs = 0, correctionMs = 0, rebaseMs = 0, restoreMs = 0, captureMs = 0, hashMs = 0,
               earlyWaitMs = 0;
        // Host-only diagnostics, written/read by the EE thread; never part of a snapshot or hash.
        size_t hashQueuePeak = 0;
        uint64_t hashWaitCalls = 0, hashReaderWaits = 0;
        double hashWaitMs = 0, hashWaitMaxMs = 0, hashQueueMs = 0, hashQueueMaxMs = 0,
               hashAgeMs = 0, hashAgeMaxMs = 0;
        TimeSamples rbCost, frameTimes;
        std::chrono::steady_clock::time_point lastLive{}, winT0{}, runT0{};
        uint64_t winFrames = 0, runFrames = 0;
        double winFps = 0;
        uint32_t sessionSeed = 0;
        uint64_t lastSummary = ~0ull;
        bool resultFinished = false; // host-only; never restore or write a report from a repeated frame
    };
    NetplayState g_np;

    // ---- the desync hash off the game thread (phase 3b): ~4 ms per hashed frame (+ the 32 MB dump copy) made one
    // frame in 30 late. A hashed frame is final, so no rollback writes its ring slot again; a capture into that slot
    // (maxpred + 3 frames later) waits for the job.
    struct HashJob
    {
        uint64_t frame = 0, cycle = 0;
        size_t slot = 0;
        NetHash h;
        double ms = 0;
        std::chrono::steady_clock::time_point submitted{}; // profiling only, passed with the job under g_hw.mu
        double queueMs = 0;
        std::vector<uint8_t> ram; // desync dump copy
    };
    struct HashWorker
    {
        std::mutex mu;
        std::condition_variable cv, doneCv;
        std::deque<HashJob> todo, done;
        long busySlot = -1;
        bool started = false;
        std::thread thread;
    };
    HashWorker g_hw;

    NetHash netHashOf(const ps2_rollback::Snapshot &snap, uint64_t cycle);

    void hashWorkerLoop()
    {
        for (;;)
        {
            HashJob job;
            {
                std::unique_lock<std::mutex> lk(g_hw.mu);
                g_hw.cv.wait(lk, [] { return !g_hw.todo.empty(); });
                job = std::move(g_hw.todo.front());
                g_hw.todo.pop_front();
                g_hw.busySlot = static_cast<long>(job.slot);
            }
            const auto t0 = std::chrono::steady_clock::now();
            if (g_np.hashProfile)
                job.queueMs = std::chrono::duration<double, std::milli>(t0 - job.submitted).count();
            const ps2_rollback::Snapshot &snap = g_np.ring[job.slot];
            job.h = netHashOf(snap, job.cycle);
            if (g_np.dump)
            {
                job.ram.assign(snap.rdram.begin(), snap.rdram.end());
                job.ram.insert(job.ram.end(), snap.scratchpad.begin(), snap.scratchpad.end());
            }
            job.ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
            {
                std::lock_guard<std::mutex> lk(g_hw.mu);
                g_hw.busySlot = -1;
                g_hw.done.push_back(std::move(job));
            }
            g_hw.doneCv.notify_all();
        }
    }

    void hashSubmit(uint64_t frame, size_t slot, uint64_t cycle)
    {
        std::lock_guard<std::mutex> lk(g_hw.mu);
        if (!g_hw.started)
        {
            g_hw.started = true;
            g_hw.thread = std::thread(hashWorkerLoop);
            g_hw.thread.detach();
        }
        HashJob job;
        job.frame = frame;
        job.slot = slot;
        job.cycle = cycle;
        if (g_np.hashProfile)
            job.submitted = std::chrono::steady_clock::now();
        g_hw.todo.push_back(std::move(job));
        if (g_np.hashProfile)
            g_np.hashQueuePeak = std::max(g_np.hashQueuePeak, g_hw.todo.size() + (g_hw.busySlot >= 0 ? 1u : 0u));
        g_hw.cv.notify_one();
    }

    // Before a ring slot is written again: no hash job may still read it.
    void hashWaitSlot(size_t slot)
    {
        const auto t0 = g_np.hashProfile ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point{};
        std::unique_lock<std::mutex> lk(g_hw.mu);
        const auto ready = [slot]
        {
            if (g_hw.busySlot == static_cast<long>(slot))
                return false;
            for (const HashJob &j : g_hw.todo)
                if (j.slot == slot)
                    return false;
            return true;
        };
        if (g_np.hashProfile)
        {
            ++g_np.hashWaitCalls;
            if (!ready())
                ++g_np.hashReaderWaits;
        }
        g_hw.doneCv.wait(lk, ready);
        if (g_np.hashProfile)
        {
            const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
            g_np.hashWaitMs += ms;
            g_np.hashWaitMaxMs = std::max(g_np.hashWaitMaxMs, ms);
        }
    }

    // Finished hashes: to the transport (compared with the peer's) and the log.
    void hashCollect()
    {
        std::deque<HashJob> done;
        {
            std::lock_guard<std::mutex> lk(g_hw.mu);
            done.swap(g_hw.done);
        }
        for (HashJob &job : done)
        {
            if (g_np.hashProfile)
            {
                const double age = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - job.submitted).count();
                g_np.hashQueueMs += job.queueMs;
                g_np.hashQueueMaxMs = std::max(g_np.hashQueueMaxMs, job.queueMs);
                g_np.hashAgeMs += age;
                g_np.hashAgeMaxMs = std::max(g_np.hashAgeMaxMs, age);
            }
            g_np.hashMs += job.ms;
            ++g_np.hashes;
            t4net::pushHash(static_cast<uint32_t>(job.frame), job.h.total);
            tekken4_online_result::confirmedHash(job.frame, job.h.total, g_cfg.iopState);
            std::fprintf(g_log, "NETHASH f=%" PRIu64 " h=%016" PRIx64 " ram=%016" PRIx64 " iop=%016" PRIx64 " cyc=%" PRIu64 "\n",
                         job.frame, job.h.total, job.h.ram, job.h.iop, job.h.cycle);
            if (g_np.dump)
            {
                NetplayState::Kept &k = g_np.kept[g_np.keptNext++ % 3];
                k.frame = job.frame;
                k.ram = std::move(job.ram);
            }
        }
    }

    bool npResimulating(uint64_t *liveFrame)
    {
        *liveFrame = g_np.liveFrame;
        return g_np.resim;
    }

    void npFinishResult(const char *reason, uint64_t frame, const char *detail = nullptr)
    {
        if (!tekken4_online_result::enabled() || g_np.resultFinished)
            return;
        g_np.resultFinished = true;
        // Only already-submitted, input-confirmed jobs. Do not hash a speculative live state or wait for the
        // peer here. A timeout leaves the latest completed sample, with its own frame, in the report.
        {
            std::unique_lock<std::mutex> lk(g_hw.mu);
            g_hw.doneCv.wait_for(lk, std::chrono::milliseconds(250), []
                                { return g_hw.todo.empty() && g_hw.busySlot < 0; });
        }
        hashCollect();
        if (g_np.started)
        {
            const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - g_np.runT0).count();
            tekken4_online_result::liveFrame(frame, seconds > 0.0 ? static_cast<double>(g_np.runFrames) / seconds : 0.0);
        }
        tekken4_online_result::finish(reason, frame, detail);
    }

    // Both ports during a netplay frame: the inputs decided at its boundary (npDecideInputs).
    bool npPadInput(int port, uint16_t &buttons, uint8_t (&axes)[4])
    {
        if (port < 0 || port > 1)
            return false;
        const t4net::PadInput &in = g_np.inputs[port];
        buttons = static_cast<uint16_t>(~in.buttons);
        for (int i = 0; i < 4; ++i)
            axes[i] = in.axes[i];
        return true;
    }

    void npShift(std::chrono::steady_clock::duration d)
    {
        if (d.count() != 0)
            g_runtime->eeScheduler().shiftHostDeadlines(d);
    }

    double msSince(std::chrono::steady_clock::time_point t0)
    {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    }

    void npSleepUntil(std::chrono::steady_clock::time_point end)
    {
        while (std::chrono::steady_clock::now() + std::chrono::milliseconds(2) < end)
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        while (std::chrono::steady_clock::now() < end)
            std::this_thread::yield();
    }

    uint8_t quantizeAxis(uint8_t v)
    {
        // three levels: stick noise must not look like a new input (every change would be a misprediction)
        return v < 0x40u ? 0x00u : v > 0xC0u ? 0xFFu : 0x80u;
    }

    t4net::PadInput npSampleLocal(uint64_t frame)
    {
        t4net::PadInput in;
        if (g_np.autoVs && frame <= g_np.autoVsEnd)
        {
            // Use the EFFECTIVE target frame, including ahead-of-time priming. Repeated boundaries and
            // rollback read the normal input history; host clocks and live expiry logging cannot alter it.
            if (frame < g_np.autoVsEnd)
                for (const ScriptPress &press : g_np.autoVsScript.presses)
                    if (frame >= press.frame && frame - press.frame < press.hold)
                        in.buttons |= press.buttons;
            return in; // END is one neutral release frame, including all axes; no real device or fuzz here.
        }
        if (g_np.autoVs)
        {
            // A long boot press cannot leak past the bounded window. Later per-slot test presses and fuzz
            // remain available (the pair harness can continue from select into a fight).
            const PadScript &script = g_cfg.pads[g_np.slot];
            for (const ScriptPress &press : script.presses)
                if (press.frame > g_np.autoVsEnd && frame >= press.frame && frame - press.frame < press.hold)
                    in.buttons |= press.buttons;
            if (frame >= script.fuzzFrom && frame < script.fuzzTo)
                in.buttons |= fuzzButtons(frame, script.salt);
        }
        else
            in.buttons = scriptedButtons(g_np.slot, frame);
        if (g_np.localPad)
        {
            uint16_t buttons = 0xFFFFu;
            uint8_t axes[4]{0x80, 0x80, 0x80, 0x80};
            if (ps2_stubs::sampleHostPad(g_runtime, g_np.padDevice, buttons, axes))
            {
                in.buttons |= static_cast<uint16_t>(~buttons);
                for (int i = 0; i < 4; ++i)
                    in.axes[i] = quantizeAxis(axes[i]);
            }
        }
        return in;
    }

    uint64_t npSendLocal(uint64_t f)
    {
        uint64_t sampled = 0;
        const uint64_t ahead = static_cast<uint64_t>(f < g_np.rbStart ? g_np.lockDelay : g_np.delay);
        for (uint64_t u = t4net::localMax(); u <= f + ahead; ++u)
        {
            t4net::setLocal(static_cast<uint32_t>(u), npSampleLocal(u));
            ++sampled;
        }
        t4net::sendNow();
        return sampled;
    }

    // The inputs frame g runs with: this side's (decided delay frames ago), the peer's (confirmed, or the last
    // confirmed one repeated = predicted).
    void npDecideInputs(uint64_t g)
    {
        t4net::PadInput local{}, remote{};
        (void)t4net::local(static_cast<uint32_t>(g), &local);
        bool predicted = false;
        if (!t4net::remote(static_cast<uint32_t>(g), &remote))
        {
            const size_t pass = g_np.resim ? 1u : 0u;
            ++g_np.inputMisses[pass];
            uint32_t rc = 0;
            if (g_np.atomicInput)
            {
                predicted = !t4net::remoteOrPredict(static_cast<uint32_t>(g), &remote, &rc);
                if (!predicted)
                    ++g_np.inputRecovered[pass];
            }
            else
            {
                predicted = true;
                rc = t4net::remoteContig();
                if (rc == 0 || !t4net::remote(rc - 1u, &remote))
                    remote = t4net::PadInput{};
                else if (static_cast<uint64_t>(rc - 1u) > g)
                    ++g_np.inputFutureFallbacks[pass];
            }
            if (static_cast<uint64_t>(rc) > g)
            {
                ++g_np.inputAdvanced[pass];
                if (static_cast<uint64_t>(rc - 1u) > g)
                    ++g_np.inputAheadFrontier[pass];
                // Both transport calls have released their locks. This is decision time, not first arrival.
                if (g_np.diag)
                    std::fprintf(g_log, "NETATOMICINPUT_EVENT steady_ms=%.3f slot=%d g=%" PRIu64
                                        " replay=%d atomic_input=%d rc=%u confirmed=%d\n",
                                 std::chrono::duration<double, std::milli>(
                                     std::chrono::steady_clock::now().time_since_epoch()).count(),
                                 g_np.slot, g, g_np.resim ? 1 : 0, g_np.atomicInput ? 1 : 0, rc, predicted ? 0 : 1);
            }
        }
        const uint32_t i = static_cast<uint32_t>(g % kHist);
        g_np.used[i] = remote;
        g_np.usedTag[i] = g + 1u;
        g_np.pred[i] = predicted;
        if (predicted)
            ++g_np.predicted;
        g_np.inputs[g_np.slot] = local;
        g_np.inputs[1 - g_np.slot] = remote;
    }

    // First frame g < min(f, rc) whose confirmed remote input differs from the prediction it ran with.
    // A nonconsuming observation leaves checked and mispredicted unchanged.
    uint64_t npScan(uint64_t f, uint64_t rc, bool consume = true)
    {
        const uint64_t upto = std::min(rc, f);
        uint64_t firstWrong = ~0ull;
        for (uint64_t g = g_np.checked; g < upto; ++g)
        {
            const uint32_t i = static_cast<uint32_t>(g % kHist);
            if (g_np.usedTag[i] != g + 1u || !g_np.pred[i])
                continue;
            t4net::PadInput real;
            if (!t4net::remote(static_cast<uint32_t>(g), &real))
                break;
            if (real != g_np.used[i])
            {
                firstWrong = g;
                if (consume)
                    ++g_np.mispredicted;
                break;
            }
        }
        if (consume)
            g_np.checked = std::max(g_np.checked, upto);
        return firstWrong;
    }

    void npCapture(uint64_t cycle)
    {
        const size_t slot = g_frame % g_np.ring.size();
        hashWaitSlot(slot);
        const auto t0 = std::chrono::steady_clock::now();
        ps2_rollback::capture(*g_runtime, g_np.ring[slot]);
        g_np.ringFrame[slot] = g_frame;
        g_np.ringCycle[slot] = cycle;
        const double ms = msSince(t0);
        g_np.captureMs += ms;
        if (g_np.costProfile)
            g_np.captureCost[g_frame < g_np.rbStart ? 0u : 1u].add(ms);
        ++g_np.captures;
    }

    bool npStartRollback(uint64_t f, uint64_t g, bool early)
    {
        const size_t slot = g % g_np.ring.size();
        if (g_np.ringFrame[slot] != g)
        {
            std::fprintf(g_log, "NET frame %" PRIu64 ": misprediction at %" PRIu64 " out of the snapshot ring (have %" PRIu64
                                ") -- DESYNC likely\n", f, g, g_np.ringFrame[slot]);
            return false;
        }
        const bool overdueEarly = early && std::chrono::steady_clock::now() >= g_np.liveT;
        if (g_np.batchRollbackFrame == f)
            ++g_np.batchRevisits;
        g_np.batchRollbackFrame = f;
        const uint64_t batchBefore = t4net::remoteContig();
        if (g_np.batchSeenFrame != f && batchBefore < f && !t4net::peerLost())
        {
            g_np.batchSeenFrame = f;
            ++g_np.batchOpportunities;
            const auto begin = std::chrono::steady_clock::now();
            auto end = begin;
            uint64_t after = batchBefore;
            double ms = 0;
            if (g_np.replayBatch)
            {
                // Wait only for replay inputs through f-1. A lagging peer may still need to sample them;
                // the finite budget avoids waiting indefinitely for its progress. Never scan again here:
                // npScan advanced checked, but g still needs its pending restore.
                // Leave the live deadline unchanged. This spends wall time, it does not hide a pacing shift.
                after = t4net::waitRemoteUs(static_cast<uint32_t>(f - 1u), static_cast<uint32_t>(kVblank.count()));
                end = std::chrono::steady_clock::now();
                ms = std::chrono::duration<double, std::milli>(end - begin).count();
                ++g_np.batchWaits;
                if (early)
                    ++g_np.batchEarlyWaits;
                if (after > batchBefore)
                    ++g_np.batchAdvanced;
                if (after >= f)
                    ++g_np.batchCompleted;
                g_np.batchWaitMs += ms;
                g_np.batchMaxMs = std::max(g_np.batchMaxMs, ms);
                g_np.batchFrame = f;
                g_np.batchBefore = batchBefore;
                g_np.batchAfter = after;
            }
            if (g_np.diag)
                std::fprintf(g_log, "NETREPLAYBATCH_EVENT steady_ms=%.3f end_steady_ms=%.3f slot=%d replay_batch=%d"
                                    " f=%" PRIu64 " from=%" PRIu64 " early=%d rc_before=%" PRIu64
                                    " rc_after=%" PRIu64 " target=%" PRIu64 " budget_us=%" PRId64
                                    " wait_ms=%.3f peer_lost=%d\n",
                             std::chrono::duration<double, std::milli>(begin.time_since_epoch()).count(),
                             std::chrono::duration<double, std::milli>(end.time_since_epoch()).count(),
                             g_np.slot, g_np.replayBatch ? 1 : 0, f, g, early ? 1 : 0, batchBefore, after, f,
                             static_cast<int64_t>(kVblank.count()), ms, t4net::peerLost() ? 1 : 0);
        }
        g_np.liveVblank = g_runtime->eeScheduler().nextVblankHostDeadline();
        g_np.rbT0 = std::chrono::steady_clock::now();
        ps2_rollback::restore(*g_runtime, g_np.ring[slot]);
        const double ms = msSince(g_np.rbT0);
        g_np.restoreMs += ms;
        if (g_np.costProfile)
            g_np.restoreCost.add(ms);
        const uint64_t depth = f - g;
        ++g_np.rollbacks;
        if (early)
        {
            ++g_np.earlyRollbacks;
            if (overdueEarly)
            {
                ++g_np.earlyOverdueRollbacks;
                if (g_np.earlyRollbackFrame == f)
                    ++g_np.earlyOverdueRevisits;
            }
            g_np.earlyRollbackFrame = f;
        }
        else if (g_np.earlyDeferredFrame == f)
            ++g_np.earlyDeferredLate;
        g_np.maxDepth = std::max(g_np.maxDepth, depth);
        ++g_np.depthHist[std::min<uint64_t>(depth, 16u)];
        g_np.resim = true;
        g_np.resimEarly = early;
        g_np.liveFrame = f;
        g_np.resimFrom = g;
        g_frame = g;
        ps2_rollback::setIopOutputMuted(true);
        npDecideInputs(g);
        return true;
    }

    void npEndResim()
    {
        g_np.resim = false;
        const double ms = msSince(g_np.rbT0);
        g_np.rbCost.push_back(ms);
        if (g_np.diag)
            g_np.diagRollbackMaxMs = std::max(g_np.diagRollbackMaxMs, ms);
        if (g_np.costProfile)
            g_np.rollbackCost.add(ms);
        // the restored scheduler carries the host times of the snapshot's day: put the live schedule back
        const auto now = g_runtime->eeScheduler().nextVblankHostDeadline();
        if (now.time_since_epoch().count() != 0 && g_np.liveVblank.time_since_epoch().count() != 0)
            npShift(g_np.liveVblank - now);
        ps2_rollback::setIopOutputMuted(false);
    }

    // First visit of a live boundary, before its vblank time is read: hand out one slice of a pending time-sync give.
    void npSpreadSlice()
    {
        if (g_np.spreadLeft.count() <= 0)
            return;
        const auto slice = std::min(g_np.spreadLeft, std::max(g_np.spreadSlice, std::chrono::steady_clock::duration(1)));
        npShift(slice);
        g_np.spreadLeft -= slice;
        ++g_np.spreadSlices;
    }

    void npApplyTimeSync(const NetplayState::SyncCorrection &selected)
    {
        const uint64_t f = selected.frame, rc = selected.rc;
        const double adv = selected.adv;
        const bool subframe = selected.subframe;
        const int frames = selected.frames;
        const auto give = selected.give, baseGive = selected.baseGive;
        const auto legacyGive = selected.legacyGive, fullGive = selected.fullGive;
        const auto sleepStart = std::chrono::steady_clock::now();
        // Spread (default): no pause now; the next syncSpread live frames each start give/syncSpread later
        // (npSpreadSlice). One pause of a whole frame showed the same picture twice: a 31-34 ms hitch per
        // correction in the owner's 2-PC test. Wall-clock pacing only: inputs and the simulation do not change.
        const bool spread = g_np.syncSpread > 1;
        if (spread)
        {
            g_np.spreadLeft += give;
            g_np.spreadSlice = g_np.spreadLeft / g_np.syncSpread;
        }
        else
        {
            npSleepUntil(std::max(std::chrono::steady_clock::now(), g_np.liveT) + give);
            npShift(give);
        }
        const auto sleepEnd = std::chrono::steady_clock::now();
        const double ms = std::chrono::duration<double, std::milli>(give).count();
        const double actual = spread ? ms : std::chrono::duration<double, std::milli>(sleepEnd - sleepStart).count();
        ++g_np.syncCapActions;
        if (baseGive > kVblank)
            ++g_np.syncCapEligible;
        if (give != baseGive)
            ++g_np.syncCapChanged;
        g_np.syncCapBaseMs += std::chrono::duration<double, std::milli>(baseGive).count();
        g_np.syncCapRequestedMs += ms;
        g_np.syncCapActualMs += actual;
        g_np.syncCapMaxMs = std::max(g_np.syncCapMaxMs, ms);
        if (!subframe)
        {
            ++g_np.fullSyncActions; // All >= 1-frame corrections in BOTH arms; changed only counts ON differences.
            if (baseGive != legacyGive) // Keep FULL_SYNC's policy changes separate from the pause cap.
                ++g_np.fullSyncChanged;
            g_np.fullSyncRequestedMs += ms;
            g_np.fullSyncLegacyMs += std::chrono::duration<double, std::milli>(legacyGive).count();
            g_np.fullSyncActualMs += actual;
        }
        if (subframe)
        {
            ++g_np.subframeCorrections;
            g_np.subframeMs += ms;
            g_np.subframeActualMs += actual;
        }
        if (g_np.diag)
        {
            g_np.diagSyncActualMs += actual;
            g_np.diagSyncOverMaxMs = std::max(g_np.diagSyncOverMaxMs, actual - ms);
        }
        const int rtt = t4net::rttMs();
        g_np.tsHold = f + static_cast<uint64_t>(frames) + (rtt > 0 ? static_cast<uint64_t>(rtt / 16.667 + 0.999) : 0u) + 2u +
                      static_cast<uint64_t>(spread ? g_np.syncSpread : 0);
        // Keep the original nominal post-sleep hold. Wall expiry may only admit samples EARLIER.
        g_np.syncHoldEnd = sleepEnd + kVblank * static_cast<int64_t>(g_np.tsHold - f);
        g_np.syncHoldReleased = false;
        if (selected.wallSamples > 0)
            ++g_np.syncHoldCorrections;
        if (g_np.diag)
            std::fprintf(g_log, "NETSYNCHOLD_SET end_steady_ms=%.3f slot=%d f=%" PRIu64
                                " sync_wall_hold=%d hold_until=%" PRIu64 " deadline_ms=%.3f"
                                " window_wall_samples=%d\n",
                         std::chrono::duration<double, std::milli>(sleepEnd.time_since_epoch()).count(),
                         g_np.slot, f, g_np.syncWallHold ? 1 : 0, g_np.tsHold,
                         std::chrono::duration<double, std::milli>(g_np.syncHoldEnd.time_since_epoch()).count(),
                         selected.wallSamples);
        if (g_np.diag)
            std::fprintf(g_log, "NETSYNCCAP_EVENT steady_ms=%.3f end_steady_ms=%.3f slot=%d f=%" PRIu64
                                " sync_cap_one=%d adv=%.6f base_us=%" PRId64 " give_us=%" PRId64
                                " actual_ms=%.3f hold_frames=%d rtt_ms=%d hold_until=%" PRIu64
                                " rc_before=%" PRIu64 " rc_after=%u\n",
                         std::chrono::duration<double, std::milli>(sleepStart.time_since_epoch()).count(),
                         std::chrono::duration<double, std::milli>(sleepEnd.time_since_epoch()).count(),
                         g_np.slot, f, g_np.syncCapOne ? 1 : 0, adv, static_cast<int64_t>(baseGive.count()),
                         static_cast<int64_t>(give.count()), actual, frames, rtt, g_np.tsHold, rc, t4net::remoteContig());
        if (!subframe)
        {
            std::fprintf(g_log, "NETTS f=%" PRIu64 " ahead %.2f frames: gave up %.3f frame(s) window=%d samples=%d gap=%" PRIu64 "\n",
                         f, adv, static_cast<double>(give.count()) / kVblank.count(), g_np.leadWindow, g_np.leadN,
                         g_np.corrections ? f - g_np.lastCorrection : 0u);
            std::fprintf(g_log, "NETFULLSYNC_EVENT steady_ms=%.3f end_steady_ms=%.3f slot=%d f=%" PRIu64
                                " full_sync=%d adv=%.6f give_us=%" PRId64 " legacy_us=%" PRId64
                                " candidate_us=%" PRId64 " hold_frames=%d window=%d samples=%d"
                                " rc_before=%" PRIu64 " rc_after=%u\n",
                         std::chrono::duration<double, std::milli>(sleepStart.time_since_epoch()).count(),
                         std::chrono::duration<double, std::milli>(sleepEnd.time_since_epoch()).count(),
                         g_np.slot, f, g_np.fullSync ? 1 : 0, adv, static_cast<int64_t>(give.count()),
                         static_cast<int64_t>(legacyGive.count()), static_cast<int64_t>(fullGive.count()), frames,
                         g_np.leadWindow, g_np.leadN, rc, t4net::remoteContig());
        }
        if (subframe)
            std::fprintf(g_log, "NETSUBFRAME_EVENT steady_ms=%.3f end_steady_ms=%.3f slot=%d f=%" PRIu64
                                " adv=%.3f give_us=%" PRId64 " hold_frames=%d window=%d samples=%d"
                                " rc_before=%" PRIu64 " rc_after=%u\n",
                         std::chrono::duration<double, std::milli>(sleepStart.time_since_epoch()).count(),
                         std::chrono::duration<double, std::milli>(sleepEnd.time_since_epoch()).count(),
                         g_np.slot, f, adv, static_cast<int64_t>(give.count()), frames, g_np.leadWindow, g_np.leadN,
                         rc, t4net::remoteContig());
        if (g_np.leadN < NetplayState::kLeadWin)
            ++g_np.syncEarlyCorrections;
        g_np.leadN = 0;
        g_np.lastCorrection = f;
        ++g_np.corrections;
        ++g_np.syncProgressCorrections;
        g_np.correctionMs += ms;
    }

    // True only when replay started and the selected correction is pending until live catch-up.
    bool npTimeSync(uint64_t f, uint64_t rc)
    {
        const int peerFrame = static_cast<int>(rc) - 1 - g_np.delay;
        const int mine = static_cast<int>(f) - peerFrame;
        t4net::setLead(mine);
        // Called once per new live frame. A long wall gap can leave the window spanning a producer hitch.
        // Expire it BEFORE this evaluation, including after early replay, rather than at the later pacing guard.
        const auto now = std::chrono::steady_clock::now();
        const bool hadVisit = g_np.syncVisit.time_since_epoch().count() != 0;
        const auto gap = hadVisit ? now - g_np.syncVisit : std::chrono::steady_clock::duration::zero();
        const double gapMs = std::chrono::duration<double, std::milli>(gap).count();
        g_np.syncVisit = now;
        if (g_np.timeSync && f >= g_np.tsFrom && hadVisit && gap > std::chrono::milliseconds(50))
        {
            ++g_np.syncGapEvents;
            g_np.syncGapMaxMs = std::max(g_np.syncGapMaxMs, gapMs);
            const int samples = std::min(g_np.leadN, g_np.leadWindow);
            if (samples > 0)
                ++g_np.syncGapEligible;
            const bool reset = g_np.syncGapReset && samples > 0;
            if (reset)
            {
                g_np.leadN = 0;
                ++g_np.syncGapResets;
                g_np.syncGapDiscarded += static_cast<uint64_t>(samples);
            }
            if (g_np.diag)
                std::fprintf(g_log, "NETSYNCGAP_EVENT steady_ms=%.3f slot=%d f=%" PRIu64
                                    " sync_gap_reset=%d gap_ms=%.3f samples_before=%d reset=%d"
                                    " mine=%d peer_lead=%d rc=%" PRIu64 " hold_until=%" PRIu64 "\n",
                             std::chrono::duration<double, std::milli>(now.time_since_epoch()).count(),
                             g_np.slot, f, g_np.syncGapReset ? 1 : 0, gapMs, samples, reset ? 1 : 0,
                             mine, t4net::peerLead(), rc, g_np.tsHold);
        }
        // (after the lockstep both sides' inputs run up to lockDelay - delay frames further ahead for a few frames:
        // no samples before tsFrom)
        if (f < g_np.tsFrom)
            return false;
        const bool wallEligible = g_np.timeSync && f < g_np.tsHold &&
                                  g_np.syncHoldEnd.time_since_epoch().count() != 0 && now >= g_np.syncHoldEnd;
        const bool wallSample = g_np.syncWallHold && wallEligible;
        const bool repeated = g_np.syncProgressSeen && rc <= g_np.syncProgressRc;
        const bool admit = !g_np.syncProgressOnly || !repeated;
        if (wallEligible)
            ++g_np.syncHoldEligible;
        if (wallSample && admit)
        {
            ++g_np.syncHoldSamples;
            if (!g_np.syncHoldReleased)
            {
                g_np.syncHoldReleased = true;
                ++g_np.syncHoldReleases;
            }
        }
        if (wallEligible && g_np.diag)
            std::fprintf(g_log, "NETSYNCHOLD_SAMPLE steady_ms=%.3f slot=%d f=%" PRIu64
                                " sync_wall_hold=%d hold_until=%" PRIu64 " deadline_ms=%.3f"
                                " admitted=%d mine=%d peer_lead=%d rc=%" PRIu64 "\n",
                         std::chrono::duration<double, std::milli>(now.time_since_epoch()).count(),
                         g_np.slot, f, g_np.syncWallHold ? 1 : 0, g_np.tsHold,
                         std::chrono::duration<double, std::milli>(g_np.syncHoldEnd.time_since_epoch()).count(),
                         wallSample && admit ? 1 : 0, mine, t4net::peerLead(), rc);
        if (f >= g_np.tsHold || wallSample)
        {
            // Observe the SAME rc used for mine. Input progress does not guarantee fresh peer-lead metadata:
            // peerLead remains the existing separately locked cached observation in both arms.
            const int theirs = t4net::peerLead();
            ++g_np.syncProgressCandidates;
            if (repeated)
                ++g_np.syncProgressRepeated;
            if (!admit)
                ++g_np.syncProgressSkipped;
            if (g_np.diag)
                std::fprintf(g_log, "NETSYNCPROGRESS_SAMPLE steady_ms=%.3f slot=%d f=%" PRIu64
                                    " sync_progress_only=%d rc=%" PRIu64 " last_rc=%" PRIu64
                                    " seen=%d repeated=%d admitted=%d mine=%d peer_lead=%d samples_before=%d\n",
                             std::chrono::duration<double, std::milli>(now.time_since_epoch()).count(),
                             g_np.slot, f, g_np.syncProgressOnly ? 1 : 0, rc, g_np.syncProgressRc,
                             g_np.syncProgressSeen ? 1 : 0, repeated ? 1 : 0, admit ? 1 : 0, mine, theirs,
                             std::min(g_np.leadN, g_np.leadWindow));
            // Do not evaluate the unchanged full window on a skipped visit either.
            if (!admit)
                return false;
            g_np.leadMine[g_np.leadN % g_np.leadWindow] = mine;
            g_np.leadTheirs[g_np.leadN % g_np.leadWindow] = theirs;
            g_np.leadWallSample[g_np.leadN % g_np.leadWindow] = wallSample;
            ++g_np.leadN;
            g_np.syncProgressSeen = true;
            g_np.syncProgressRc = rc;
            ++g_np.syncProgressSamples;
        }
        if (!g_np.timeSync || g_np.leadN < g_np.leadWindow || t4net::peerLost())
            return false;
        ++g_np.syncEvals;
        g_np.syncEvalFrame = f;
        if (g_np.leadN < NetplayState::kLeadWin)
            ++g_np.syncEarlyEvals;
        int d[NetplayState::kLeadWin];
        int wallSamples = 0;
        for (int i = 0; i < g_np.leadWindow; ++i)
        {
            d[i] = g_np.leadMine[i] - g_np.leadTheirs[i];
            if (g_np.leadWallSample[i])
                ++wallSamples;
        }
        std::sort(d, d + g_np.leadWindow);
        const int cut = g_np.leadWindow / 5;
        double sum = 0;
        for (int i = cut; i < g_np.leadWindow - cut; ++i)
            sum += d[i];
        const double adv = sum / (2.0 * (g_np.leadWindow - 2 * cut)); // frames this side is ahead
        ++g_np.syncProgressEvals;
        if (g_np.diag)
            std::fprintf(g_log, "NETSYNCPROGRESS_EVAL steady_ms=%.3f slot=%d f=%" PRIu64
                                " sync_progress_only=%d rc=%" PRIu64 " adv=%.6f samples=%d\n",
                         std::chrono::duration<double, std::milli>(now.time_since_epoch()).count(),
                         g_np.slot, f, g_np.syncProgressOnly ? 1 : 0, rc, adv,
                         std::min(g_np.leadN, g_np.leadWindow));
        if (wallSamples > 0)
        {
            ++g_np.syncHoldEvals;
            if (g_np.diag)
                std::fprintf(g_log, "NETSYNCHOLD_EVAL steady_ms=%.3f slot=%d f=%" PRIu64
                                    " window_wall_samples=%d adv=%.6f rc=%" PRIu64 "\n",
                             std::chrono::duration<double, std::milli>(now.time_since_epoch()).count(),
                             g_np.slot, f, wallSamples, adv, rc);
        }
        if (g_np.diag)
            g_np.diagAdv = adv;
        const bool subframe = adv >= 0.25 && adv < 1.0;
        if (subframe && f - g_np.lastCorrection >= 10u)
        {
            ++g_np.subframeEvals; // Overlapping filtered evaluations, not distinct producer phase episodes.
            g_np.subframeLastFrame = f;
            g_np.subframeLastAdv = adv;
        }
        if (adv < (g_np.subframeSync ? 0.25 : 1.0) || f - g_np.lastCorrection < 10u)
            return false;
        const int legacyFrames = adv >= 2.5 ? std::min(4, static_cast<int>(adv + 0.5)) : 1;
        const auto legacyGive = kVblank * legacyFrames;
        const auto fullGive = std::chrono::microseconds(static_cast<int64_t>(kVblank.count() * std::min(4.0, adv)));
        // FULL_SYNC changes only adv >= 1. SUBFRAME_SYNC independently controls the formerly ignored band.
        const auto baseGive = subframe
                              ? std::chrono::microseconds(static_cast<int64_t>(kVblank.count() * adv))
                              : (g_np.fullSync ? fullGive : legacyGive);
        // Isolate pause size: the cap must not shorten the original RTT settling hold or refill sooner.
        const int frames = static_cast<int>((baseGive.count() + kVblank.count() - 1) / kVblank.count());
        const auto give = g_np.syncCapOne ? std::min(baseGive, kVblank) : baseGive;
        if (!subframe && fullGive != legacyGive)
        {
            ++g_np.fullSyncEvals; // Eligible correction opportunities, after every existing controller guard.
            g_np.fullSyncLastFrame = f;
            g_np.fullSyncLastAdv = adv;
        }
        NetplayState::SyncCorrection selected;
        selected.wallSamples = wallSamples;
        selected.frame = f;
        selected.rc = rc;
        selected.adv = adv;
        selected.subframe = subframe;
        selected.frames = frames;
        selected.give = give;
        selected.baseGive = baseGive;
        selected.legacyGive = legacyGive;
        selected.fullGive = fullGive;
        selected.selected = std::chrono::steady_clock::now();
        ++g_np.replaySyncEligible;
        // Observe the same confirmed interval in both arms without consuming a pending mismatch.
        const uint64_t wrong = npScan(f, rc, false);
        const bool mismatch = wrong != ~0ull;
        const bool snapshotOk = mismatch && g_np.ringFrame[wrong % g_np.ring.size()] == wrong;
        if (mismatch)
            ++g_np.replaySyncMismatch;
        bool deferred = false;
        if (g_np.replayBeforeSync && snapshotOk && !t4net::peerLost())
        {
            // Inputs below rc are immutable. Consume this exact interval only after validating its snapshot.
            const uint64_t from = npScan(f, rc);
            if (from != ~0ull)
            {
                g_np.pendingSync = selected;
                g_np.pendingSync.active = true;
                deferred = npStartRollback(f, from, false);
                if (deferred)
                {
                    ++g_np.replaySyncDeferred;
                    g_np.replaySyncDeferredUs += give.count();
                    g_np.replaySyncFrame = f;
                    g_np.replaySyncFrom = from;
                }
                else
                    g_np.pendingSync.active = false;
            }
        }
        if (g_np.diag)
            std::fprintf(g_log, "NETREPLAYSYNC_EVENT steady_ms=%.3f slot=%d f=%" PRIu64
                                " replay_before_sync=%d rc=%" PRIu64 " mismatch=%d from=%" PRIu64
                                " snapshot_ok=%d deferred=%d adv=%.6f give_us=%" PRId64 "\n",
                         std::chrono::duration<double, std::milli>(selected.selected.time_since_epoch()).count(),
                         g_np.slot, f, g_np.replayBeforeSync ? 1 : 0, rc, mismatch ? 1 : 0, wrong,
                         snapshotOk ? 1 : 0, deferred ? 1 : 0, adv, static_cast<int64_t>(give.count()));
        if (deferred)
            return true;
        npApplyTimeSync(selected);
        return false;
    }

    // Normally discard all debt beyond ~3 frames. The opt-in experiment keeps two vblank periods of live debt
    // so a slow sender can recover some headroom; excess debt is still discarded after a long hitch.
    void npPacingGuard()
    {
        const auto next = g_runtime->eeScheduler().nextVblankHostDeadline();
        if (next.time_since_epoch().count() == 0)
            return;
        const auto late = std::chrono::steady_clock::now() - next;
        if (g_np.diag)
            g_np.diagDebtMaxMs = std::max(g_np.diagDebtMaxMs, std::chrono::duration<double, std::milli>(late).count());
        if (late > std::chrono::milliseconds(50))
        {
            auto shift = late;
            if (g_np.rebaseCatchup && g_frame >= g_np.rbStart)
            {
                const auto keep = std::chrono::duration_cast<std::chrono::steady_clock::duration>(kVblank * 2);
                shift -= keep; // late > 50 ms, keep ~= 33 ms: the shift remains positive.
                ++g_np.catchupRebases;
                g_np.catchupDebtMs += std::chrono::duration<double, std::milli>(keep).count();
            }
            npShift(shift);
            ++g_np.rebases;
            g_np.rebaseMs += std::chrono::duration<double, std::milli>(shift).count();
        }
    }

    void npDiag()
    {
        if (!g_np.diag)
            return;
        const auto now = std::chrono::steady_clock::now();
        if (now - g_np.diagLast < std::chrono::seconds(1))
            return;
        g_np.diagLast = now;
        const uint64_t rc = t4net::remoteContig();
        const int64_t mine = static_cast<int64_t>(g_frame) - static_cast<int64_t>(rc) + 1 + g_np.delay;
        const double steadyMs = std::chrono::duration<double, std::milli>(now.time_since_epoch()).count();
        std::fprintf(g_log, "NETDIAG steady_ms=%.3f f=%" PRIu64 " slot=%d rc=%" PRIu64
                            " mine=%" PRId64 " peer=%d adv=%.2f samples=%d hold=%" PRIu64
                            " gap_max_ms=%.3f debt_max_ms=%.3f rebase=%" PRIu64 " rebase_ms=%.3f"
                            " sync=%" PRIu64 " sync_req_ms=%.3f sync_actual_ms=%.3f sync_over_max_ms=%.3f"
                            " stalls=%" PRIu64 " stall_ms=%.3f wait_max_ms=%.3f wait_rc=%" PRIu64 "->%" PRIu64
                            " wait_need=%" PRIu64 " rb=%" PRIu64 " rb_max_ms=%.3f"
                            " sync_fast=%d sync_window=%d sync_eval=%" PRIu64 " sync_eval_f=%" PRIu64
                            " sync_early_eval=%" PRIu64 " sync_early_corrections=%" PRIu64 "\n",
                     steadyMs, g_frame, g_np.slot, rc, mine, t4net::peerLead(), g_np.diagAdv, g_np.leadN, g_np.tsHold,
                     g_np.diagGapMaxMs, g_np.diagDebtMaxMs, g_np.rebases, g_np.rebaseMs,
                     g_np.corrections, g_np.correctionMs, g_np.diagSyncActualMs, g_np.diagSyncOverMaxMs,
                     g_np.stalls, g_np.stallMs, g_np.diagWaitMaxMs, g_np.diagWaitBefore, g_np.diagWaitAfter,
                     g_np.diagWaitNeed, g_np.rollbacks, g_np.diagRollbackMaxMs,
                     g_np.fastSync ? 1 : 0, g_np.leadWindow, g_np.syncEvals, g_np.syncEvalFrame,
                     g_np.syncEarlyEvals, g_np.syncEarlyCorrections);
        std::fprintf(g_log, "NETDIAG steady_ms=%.3f f=%" PRIu64 " slot=%d early_deadline=%d"
                            " early_due_skips=%" PRIu64 " early_due_revisits=%" PRIu64
                            " early_overdue_rb=%" PRIu64 " early_overdue_revisits=%" PRIu64
                            " early_deferred_late=%" PRIu64 "\n",
                     steadyMs, g_frame, g_np.slot, g_np.earlyDeadline ? 1 : 0,
                     g_np.earlyDeadlineSkips, g_np.earlyDeadlineRevisits,
                     g_np.earlyOverdueRollbacks, g_np.earlyOverdueRevisits, g_np.earlyDeferredLate);
        std::fprintf(g_log, "NETDIAG steady_ms=%.3f f=%" PRIu64 " slot=%d pred_headroom=%d"
                            " headroom_opportunities=%" PRIu64 " headroom_waits=%" PRIu64
                            " headroom_completed=%" PRIu64 " headroom_requested=%" PRIu64 " headroom_wait_ms=%.3f"
                            " headroom_f=%" PRIu64 " headroom_rc=%" PRIu64 "->%" PRIu64
                            " headroom_need=%" PRIu64 " headroom_target=%" PRIu64 "\n",
                     steadyMs, g_frame, g_np.slot, g_np.predHeadroom ? 1 : 0,
                     g_np.headroomOpportunities, g_np.headroomWaits, g_np.headroomCompleted,
                     g_np.headroomRequested, g_np.headroomWaitMs, g_np.headroomFrame,
                     g_np.headroomBefore, g_np.headroomAfter, g_np.headroomNeed, g_np.headroomTarget);
        std::fprintf(g_log, "NETDIAG steady_ms=%.3f f=%" PRIu64 " slot=%d send_first=%d"
                            " send_first_frames=%" PRIu64 " send_first_inputs=%" PRIu64 " send_prep_frames=%" PRIu64
                            " send_prep_ms=%.3f send_prep_max_ms=%.3f send_prep_f=%" PRIu64
                            " send_prep_last_ms=%.3f\n",
                     steadyMs, g_frame, g_np.slot, g_np.sendFirst ? 1 : 0,
                     g_np.sendFirstFrames, g_np.sendFirstInputs, g_np.sendPrepFrames, g_np.sendPrepMs, g_np.sendPrepMaxMs,
                     g_np.sendPrepFrame, g_np.sendPrepLastMs);
        g_np.diagGapMaxMs = g_np.diagDebtMaxMs = g_np.diagSyncOverMaxMs = g_np.diagWaitMaxMs = g_np.diagRollbackMaxMs = 0;
    }

    bool writeBmp(const std::string &path, const std::vector<uint8_t> &rgba, uint32_t width, uint32_t height)
    {
        std::ofstream f(path, std::ios::binary);
        if (!f)
            return false;
        auto put16 = [&f](uint16_t v) { f.write(reinterpret_cast<const char *>(&v), 2); };
        auto put32 = [&f](uint32_t v) { f.write(reinterpret_cast<const char *>(&v), 4); };
        const uint32_t imageBytes = width * height * 4u;
        f.write("BM", 2);
        put32(54u + imageBytes);
        put32(0u);
        put32(54u);
        put32(40u);
        put32(width);
        put32(static_cast<uint32_t>(-static_cast<int32_t>(height)));
        put16(1u);
        put16(32u);
        put32(0u);
        put32(imageBytes);
        put32(2835u);
        put32(2835u);
        put32(0u);
        put32(0u);
        std::vector<uint8_t> bgra(imageBytes);
        for (uint32_t i = 0; i < width * height; ++i)
        {
            bgra[i * 4u + 0u] = rgba[i * 4u + 2u];
            bgra[i * 4u + 1u] = rgba[i * 4u + 1u];
            bgra[i * 4u + 2u] = rgba[i * 4u + 0u];
            bgra[i * 4u + 3u] = 0xFFu;
        }
        f.write(reinterpret_cast<const char *>(bgra.data()), static_cast<std::streamsize>(bgra.size()));
        return static_cast<bool>(f);
    }

    void npSummary(const char *tag)
    {
        std::string hist;
        for (int d = 0; d <= 16; ++d)
            if (g_np.depthHist[d])
                hist += " " + std::to_string(d) + ":" + std::to_string(g_np.depthHist[d]);
        const t4net::Stats st = t4net::stats();
        int samples = 0;
        const int rtt = t4net::rttMs(&samples);
        const double runS = msSince(g_np.runT0) / 1000.0;
#ifdef PS2X_ROLLBACK_RDRAM_INCREMENTAL
        const ps2_rollback::RdramCopyStats cs = ps2_rollback::rdramCopyStats();
#else
        struct
        {
            uint64_t captures = 0, capturePages = 0, restores = 0, restorePages = 0, verifyMismatchPages = 0;
        } cs;
#endif
        std::fprintf(g_log,
                     "%s live %" PRIu64 " logical %" PRIu64 ": fps window %.1f run %.1f; rollbacks %" PRIu64 " resim frames %" PRIu64
                     " max depth %" PRIu64 " depths%s; frames on predicted input %" PRIu64 " mispredicted %" PRIu64
                     "; rollback ms (restore+resim) p50 %.2f p90 %.2f max %.2f; stalls %" PRIu64 " (%.0f ms); time sync %" PRIu64
                     " (%.0f ms); rebases %" PRIu64 " (%.0f ms); displayed frame ms p50 %.1f p90 %.1f p99 %.1f; rtt %d ms (%d)"
                     " delay %d; hashes compared %u mismatches %u; packets out %" PRIu64 " in %" PRIu64 " sim-dropped %" PRIu64
                     " resends %" PRIu64 " coalesced %" PRIu64 "; payload bytes out %" PRIu64 " in %" PRIu64
                     "; capture avg %.2f restore avg %.2f hash avg %.2f ms; peer %s"
                     "; lockstep waits %" PRIu64 " (%.0f ms) lock delay %d; early rollbacks %" PRIu64 " (wait for the vblank %.0f ms)"
                     "; lazy captures skipped %" PRIu64 "; frames > 20 ms %" PRIu64 " > 34 ms %" PRIu64 " of %" PRIu64
                     "; rdram pages per capture %.0f per restore %.0f%s",
                     tag, g_np.liveFrames, g_frame, g_np.winFps, runS > 0 ? static_cast<double>(g_np.runFrames) / runS : 0.0,
                     g_np.rollbacks, g_np.resimFrames, g_np.maxDepth, hist.c_str(), g_np.predicted, g_np.mispredicted,
                     percentile(g_np.rbCost, 0.5), percentile(g_np.rbCost, 0.9), percentile(g_np.rbCost, 1.0), g_np.stalls,
                     g_np.stallMs, g_np.corrections, g_np.correctionMs, g_np.rebases, g_np.rebaseMs,
                     percentile(g_np.frameTimes, 0.5), percentile(g_np.frameTimes, 0.9), percentile(g_np.frameTimes, 0.99), rtt,
                     samples, g_np.delay, t4net::hashesCompared(), t4net::hashMismatches(), st.packetsOut, st.packetsIn,
                     st.simDropped, st.resends, st.coalesced, st.bytesOut, st.bytesIn,
                     g_np.captures ? g_np.captureMs / static_cast<double>(g_np.captures) : 0.0,
                     g_np.rollbacks ? g_np.restoreMs / static_cast<double>(g_np.rollbacks) : 0.0,
                     g_np.hashes ? g_np.hashMs / static_cast<double>(g_np.hashes) : 0.0,
                     t4net::peerLost() ? (t4net::lostReason() ? t4net::lostReason() : "lost") : "ok",
                     g_np.lockWaits, g_np.lockWaitMs, g_np.lockDelay, g_np.earlyRollbacks, g_np.earlyWaitMs, g_np.lazySkips,
                     g_np.over20, g_np.over34, g_np.timedFrames,
                     cs.captures ? static_cast<double>(cs.capturePages) / static_cast<double>(cs.captures) : 0.0,
                     cs.restores ? static_cast<double>(cs.restorePages) / static_cast<double>(cs.restores) : 0.0,
                     cs.verifyMismatchPages ? (" VERIFY MISMATCH PAGES " + std::to_string(cs.verifyMismatchPages)).c_str() : "");
        std::fprintf(g_log, "; NETFLUSH f=%" PRIu64 " defer_resim_flush=%d deferred_boundaries=%" PRIu64
                            " live_flushes=%" PRIu64 " live_ms=%.3f live_max_ms=%.3f"
                            " replay_flushes=%" PRIu64 " replay_ms=%.3f replay_max_ms=%.3f",
                     g_frame, g_np.deferResimFlush ? 1 : 0, g_np.deferredFlushes,
                     g_np.boundaryFlushes[0], g_np.boundaryFlushMs[0], g_np.boundaryFlushMaxMs[0],
                     g_np.boundaryFlushes[1], g_np.boundaryFlushMs[1], g_np.boundaryFlushMaxMs[1]);
        std::fprintf(g_log, "; NETBOOT rendezvous=%d observed=%d calls=%" PRIu64 " f=%" PRIu64
                            " target=%" PRIu64 " local_max=%" PRIu64 " rc_before=%" PRIu64 " rc_after=%" PRIu64
                            " ready=%d wait_ms=%.3f",
                     g_np.bootRendezvous ? 1 : 0, g_np.rendezvousObserved ? 1 : 0, g_np.rendezvousCalls,
                     g_np.rendezvousFrame, g_np.rendezvousTarget, g_np.rendezvousLocalMax,
                     g_np.rendezvousBefore, g_np.rendezvousAfter, g_np.rendezvousReady ? 1 : 0, g_np.rendezvousMs);
        std::fprintf(g_log, "; NETSUBFRAME subframe_sync=%d time_sync=%d eligible_evals=%" PRIu64
                            " corrections=%" PRIu64 " requested_ms=%.3f actual_ms=%.3f last_f=%" PRIu64
                            " last_adv=%.3f",
                     g_np.subframeSync ? 1 : 0, g_np.timeSync ? 1 : 0, g_np.subframeEvals,
                     g_np.subframeCorrections, g_np.subframeMs, g_np.subframeActualMs,
                     g_np.subframeLastFrame, g_np.subframeLastAdv);
        std::fprintf(g_log, "; NETFULLSYNC full_sync=%d time_sync=%d eligible_actions=%" PRIu64
                            " actions=%" PRIu64 " changed_actions=%" PRIu64 " requested_ms=%.3f legacy_ms=%.3f"
                            " actual_ms=%.3f last_eligible_f=%" PRIu64 " last_eligible_adv=%.6f",
                     g_np.fullSync ? 1 : 0, g_np.timeSync ? 1 : 0, g_np.fullSyncEvals, g_np.fullSyncActions,
                     g_np.fullSyncChanged, g_np.fullSyncRequestedMs, g_np.fullSyncLegacyMs, g_np.fullSyncActualMs,
                     g_np.fullSyncLastFrame, g_np.fullSyncLastAdv);
        std::fprintf(g_log, "; NETSYNCCAP sync_cap_one=%d time_sync=%d actions=%" PRIu64
                            " eligible_actions=%" PRIu64 " changed_actions=%" PRIu64
                            " base_ms=%.3f requested_ms=%.3f actual_ms=%.3f max_request_ms=%.3f",
                     g_np.syncCapOne ? 1 : 0, g_np.timeSync ? 1 : 0, g_np.syncCapActions,
                     g_np.syncCapEligible, g_np.syncCapChanged, g_np.syncCapBaseMs,
                     g_np.syncCapRequestedMs, g_np.syncCapActualMs, g_np.syncCapMaxMs);
        std::fprintf(g_log, "; NETSYNCGAP sync_gap_reset=%d time_sync=%d gap_events=%" PRIu64
                            " eligible_resets=%" PRIu64 " resets=%" PRIu64 " discarded_samples=%" PRIu64
                            " max_gap_ms=%.3f threshold_ms=50",
                     g_np.syncGapReset ? 1 : 0, g_np.timeSync ? 1 : 0, g_np.syncGapEvents,
                     g_np.syncGapEligible, g_np.syncGapResets, g_np.syncGapDiscarded, g_np.syncGapMaxMs);
        std::fprintf(g_log, "; NETSYNCHOLD sync_wall_hold=%d time_sync=%d eligible_visits=%" PRIu64
                            " released_holds=%" PRIu64 " early_samples=%" PRIu64
                            " window_evals=%" PRIu64 " window_corrections=%" PRIu64,
                     g_np.syncWallHold ? 1 : 0, g_np.timeSync ? 1 : 0, g_np.syncHoldEligible,
                     g_np.syncHoldReleases, g_np.syncHoldSamples, g_np.syncHoldEvals, g_np.syncHoldCorrections);
        std::fprintf(g_log, "; NETSYNCPROGRESS sync_progress_only=%d time_sync=%d candidates=%" PRIu64
                            " repeated=%" PRIu64 " skipped=%" PRIu64 " samples=%" PRIu64
                            " evals=%" PRIu64 " corrections=%" PRIu64 " last_rc=%" PRIu64,
                     g_np.syncProgressOnly ? 1 : 0, g_np.timeSync ? 1 : 0, g_np.syncProgressCandidates,
                     g_np.syncProgressRepeated, g_np.syncProgressSkipped, g_np.syncProgressSamples,
                     g_np.syncProgressEvals, g_np.syncProgressCorrections, g_np.syncProgressRc);
        std::fprintf(g_log, "; NETATOMICINPUT atomic_input=%d misses_live=%" PRIu64 " misses_replay=%" PRIu64
                            " recovered_live=%" PRIu64 " recovered_replay=%" PRIu64
                            " advanced_live=%" PRIu64 " advanced_replay=%" PRIu64
                            " ahead_frontier_live=%" PRIu64 " ahead_frontier_replay=%" PRIu64
                            " future_fallbacks_live=%" PRIu64 " future_fallbacks_replay=%" PRIu64,
                     g_np.atomicInput ? 1 : 0, g_np.inputMisses[0], g_np.inputMisses[1],
                     g_np.inputRecovered[0], g_np.inputRecovered[1], g_np.inputAdvanced[0], g_np.inputAdvanced[1],
                     g_np.inputAheadFrontier[0], g_np.inputAheadFrontier[1],
                     g_np.inputFutureFallbacks[0], g_np.inputFutureFallbacks[1]);
        std::fprintf(g_log, "; NETREPLAYBATCH replay_batch=%d opportunities=%" PRIu64 " waits=%" PRIu64
                            " early_waits=%" PRIu64 " advanced=%" PRIu64 " completed=%" PRIu64
                            " revisits=%" PRIu64 " wait_ms=%.3f max_ms=%.3f last_f=%" PRIu64
                            " rc_before=%" PRIu64 " rc_after=%" PRIu64 " budget_us=%" PRId64,
                     g_np.replayBatch ? 1 : 0, g_np.batchOpportunities, g_np.batchWaits, g_np.batchEarlyWaits,
                     g_np.batchAdvanced, g_np.batchCompleted, g_np.batchRevisits, g_np.batchWaitMs,
                     g_np.batchMaxMs, g_np.batchFrame, g_np.batchBefore, g_np.batchAfter,
                     static_cast<int64_t>(kVblank.count()));
        std::fprintf(g_log, "; NETREPLAYSYNC replay_before_sync=%d time_sync=%d eligible=%" PRIu64
                            " mismatch=%" PRIu64 " deferred=%" PRIu64 " applied=%" PRIu64 " pending=%d"
                            " deferred_us=%" PRId64 " applied_us=%" PRId64
                            " delay_ms=%.3f max_delay_ms=%.3f last_f=%" PRIu64 " last_from=%" PRIu64,
                     g_np.replayBeforeSync ? 1 : 0, g_np.timeSync ? 1 : 0, g_np.replaySyncEligible,
                     g_np.replaySyncMismatch, g_np.replaySyncDeferred, g_np.replaySyncApplied,
                     g_np.pendingSync.active ? 1 : 0, g_np.replaySyncDeferredUs, g_np.replaySyncAppliedUs,
                     g_np.replaySyncDelayMs, g_np.replaySyncMaxDelayMs, g_np.replaySyncFrame, g_np.replaySyncFrom);
        std::fprintf(g_log, "; NETSIMPRIO normal_priority=%d sim_active=%d started=%d set_ok=%d thread_priority=%d"
                            " spin_calls=%" PRIu64 " spin_ms=%.3f spin_max_ms=%.3f send_calls=%" PRIu64
                            " late_max_ms=%.3f late_ge2ms=%" PRIu64 "\n",
                     st.simNormalPriority ? 1 : 0, st.simActive ? 1 : 0, st.simPriorityReady ? 1 : 0,
                     st.simPriorityOk ? 1 : 0, st.simThreadPriority, st.simSpinCalls,
                     st.simSpinUs / 1000.0, st.simSpinMaxUs / 1000.0, st.simSendCalls,
                     st.simLateMaxUs / 1000.0, st.simLateOver2ms);
        if (g_np.rebaseCatchup)
            std::fprintf(g_log, "NETREBASE_CATCHUP f=%" PRIu64 " rebases=%" PRIu64 " retained_debt_ms=%.3f\n",
                         g_frame, g_np.catchupRebases, g_np.catchupDebtMs);
        if (g_np.hashProfile)
            std::fprintf(g_log,
                         "NETHASH_PROFILE f=%" PRIu64 " collected=%" PRIu64 " pending peak=%zu; queue avg %.3f max %.3f ms;"
                         " submit-to-collect avg %.3f max %.3f ms; slot checks=%" PRIu64 " reader waits=%" PRIu64
                         " slot call total %.3f max %.3f ms\n",
                         g_frame, g_np.hashes, g_np.hashQueuePeak,
                         g_np.hashes ? g_np.hashQueueMs / static_cast<double>(g_np.hashes) : 0.0, g_np.hashQueueMaxMs,
                         g_np.hashes ? g_np.hashAgeMs / static_cast<double>(g_np.hashes) : 0.0, g_np.hashAgeMaxMs,
                         g_np.hashWaitCalls, g_np.hashReaderWaits, g_np.hashWaitMs, g_np.hashWaitMaxMs);
        if (g_np.costProfile)
        {
            const auto report = [](const char *pass, const char *part, const NetCostHistogram &cost)
            {
                if (!cost.count)
                    return;
                std::fprintf(g_log, "NETCOST f=%" PRIu64 " pass=%s part=%s n=%" PRIu64
                                    " avg=%.3f p50_upper=%.3f p90_upper=%.3f p99_upper=%.3f max=%.3f ms\n",
                             g_frame, pass, part, cost.count, cost.sum / static_cast<double>(cost.count),
                             cost.upper(0.5), cost.upper(0.9), cost.upper(0.99), cost.maximum);
            };
            const char *passes[] = {"boot", "live", "cut", "tail"};
            const char *parts[] = {"ee_busy", "gs", "vif", "vu", "iop"};
            for (size_t p = 0; p < 4u; ++p)
                for (size_t part = 0; part < 5u; ++part)
                    report(passes[p], parts[part], g_np.frameCost[p][part]);
            report("boot", "capture", g_np.captureCost[0]);
            report("boundary", "capture", g_np.captureCost[1]);
            report("rollback", "restore", g_np.restoreCost);
            report("rollback", "whole", g_np.rollbackCost);
        }
    }

    void npHandshake()
    {
        const auto t0 = std::chrono::steady_clock::now();
        std::fprintf(g_log, "NET waiting for the peer (handshake)\n");
        std::fflush(g_log);
        if (!t4net::waitConnected())
        {
            std::fprintf(g_log, "NET no session (%s): the game runs offline\n", t4net::failure() ? t4net::failure() : "?");
            g_np.failed = true;
            if (g_np.autoVs)
            {
                ps2_stubs::setPadInputProvider(nullptr);
                std::fprintf(g_log, "NETAUTO_VS aborted: handshake failed; normal offline input restored\n");
                std::fflush(g_log);
            }
            npFinishResult("handshake_failed", g_frame, t4net::failure());
            return;
        }
        g_np.delay = t4net::agreeDelay(1500);
        g_np.sessionSeed = t4net::sessionSeed();
        // the lockstep's input delay: this side's input for frame f leaves at boundary f - lockDelay and must be at
        // the peer by its boundary f: one way + jitter margin, plus one frame. Each side picks its own (frames before
        // base are neutral on both sides; the inputs between base and f + lockDelay are sampled now).
        const int rtt = t4net::rttMs();
        g_np.lockDelay = g_np.lockDelaySetting >= 0
                             ? g_np.lockDelaySetting
                             : (rtt < 0 ? g_np.delay : static_cast<int>(std::ceil((rtt / 2.0 + 12.0) / 16.667)) + 1);
        g_np.lockDelay = std::max(g_np.delay, std::min(kMaxLockDelay, g_np.lockDelay));
        if (g_frame >= g_np.rbStart)
            g_np.lockDelay = g_np.delay;
        g_np.tsFrom = g_np.rbStart + static_cast<uint64_t>(kMaxLockDelay) + 4u;
        const uint64_t base = g_frame + static_cast<uint64_t>(g_np.delay);
        t4net::setInputBase(static_cast<uint32_t>(base));
        for (uint64_t t = base; t < g_frame + static_cast<uint64_t>(g_np.lockDelay); ++t)
            t4net::setLocal(static_cast<uint32_t>(t), npSampleLocal(t));
        g_np.checked = g_frame;
        g_np.hashNext = g_frame;
        g_np.started = true;
        g_np.runT0 = g_np.winT0 = std::chrono::steady_clock::now();
        if (g_np.diag)
            g_np.diagLast = g_np.runT0;
        tekken4_online_result::started(g_np.slot);
        // the boot waited: pace from now; with early rollback the schedule runs earlyMs ahead of the vblank times
        // the frames' live parts keep (liveT)
        npShift(std::chrono::steady_clock::now() - t0 -
                std::chrono::microseconds(g_np.early ? static_cast<int64_t>(g_np.earlyMs * 1000.0) : 0));
        std::fprintf(g_log, "NET connected: slot %d, delay %d (lockstep %d), frames < %" PRIu64 " neutral, lockstep until %" PRIu64
                            ", max prediction %" PRIu64 ", session seed %08x, handshake %.0f ms, early rollback %s (%.1f ms), lazy %d\n",
                     g_np.slot, g_np.delay, g_np.lockDelay, base, g_np.rbStart, g_np.maxPred, g_np.sessionSeed, msSince(t0),
                     g_np.early ? "on" : "off", g_np.earlyMs, g_np.lazy ? 1 : 0);
        if (g_np.refreshRc)
            std::fprintf(g_log, "NET remote input refresh before prediction wait/late scan enabled\n");
        if (g_np.rebaseCatchup)
            std::fprintf(g_log, "NET TEKKEN4_NET_REBASE_CATCHUP=1: live rebases retain two vblank periods of deadline debt\n");
        if (g_np.earlyDeadline)
            std::fprintf(g_log, "NET TEKKEN4_NET_EARLY_DEADLINE=1: overdue early scans defer to sync/wait and late rollback\n");
        if (g_np.predHeadroom)
            std::fprintf(g_log, "NET TEKKEN4_NET_PRED_HEADROOM=1: prediction waits request up to two more confirmed inputs, at most through the current frame\n");
        if (g_np.sendFirst)
            std::fprintf(g_log, "NET TEKKEN4_NET_SEND_FIRST=1: first-live input sampled and sent before capture/hash collection\n");
        if (g_np.deferResimFlush)
            std::fprintf(g_log, "NET TEKKEN4_NET_DEFER_RESIM_FLUSH=1: ordinary log flushes deferred while replay remains active\n");
        if (g_np.bootRendezvous)
            std::fprintf(g_log, "NET TEKKEN4_NET_BOOT_RENDEZVOUS=1: one same-frame input wait after boot prefill; phase experiment, not a shared release clock\n");
        std::fprintf(g_log, "NET time-sync corrections spread over %d live frame(s) (TEKKEN4_NET_SYNC_SPREAD)\n",
                     g_np.syncSpread > 1 ? g_np.syncSpread : 1);
        if (g_np.subframeSync)
            std::fprintf(g_log, "NET TEKKEN4_NET_SUBFRAME_SYNC=1: fractional waits for filtered leads 0.25..<1 frame\n");
        if (g_np.fullSync)
            std::fprintf(g_log, "NET TEKKEN4_NET_FULL_SYNC=1: continuous measured lead from 1 frame, cap 4; settling hold rounds up\n");
        if (g_np.syncCapOne)
            std::fprintf(g_log, "NET TEKKEN4_NET_SYNC_CAP_ONE=1: correction pauses capped at one vblank; pre-cap settling hold retained\n");
        if (g_np.syncGapReset)
            std::fprintf(g_log, "NET TEKKEN4_NET_SYNC_GAP_RESET=1: discard lead samples after >50 ms between live sync visits; refill normal window\n");
        if (g_np.syncWallHold)
            std::fprintf(g_log, "NET TEKKEN4_NET_SYNC_WALL_HOLD=1: release settling hold at original frame or nominal wall deadline from correction end\n");
        if (g_np.syncProgressOnly)
            std::fprintf(g_log, "NET TEKKEN4_NET_SYNC_PROGRESS_ONLY=1: sample/evaluate time sync only on advancing confirmed remote input frontier\n");
        if (g_np.atomicInput)
            std::fprintf(g_log, "NET TEKKEN4_NET_ATOMIC_INPUT=1: locked exact-input recheck and held prediction\n");
        if (g_np.replayBatch)
            std::fprintf(g_log, "NET TEKKEN4_NET_REPLAY_BATCH=1: wait up to one vblank for replay inputs, once per live frame\n");
        if (g_np.replayBeforeSync)
            std::fprintf(g_log, "NET TEKKEN4_NET_REPLAY_BEFORE_SYNC=1: replay confirmed mismatch before applying the same selected time-sync correction\n");
    }

    void npBootRendezvous(uint64_t f)
    {
        const uint64_t prefill = static_cast<uint64_t>(g_np.lockDelay - g_np.delay);
        if (g_np.rendezvousObserved || f <= g_np.rbStart || f - g_np.rbStart <= prefill)
            return;
        // Last boot sample: rbStart - 1 + lockDelay. Here f + delay is newly produced on both peers.
        // Current publication has already happened. The lagging peer can reach f using our sent history;
        // neither side asks for a future sample before it can publish its own. This can reverse phase,
        // rather than align it: each peer releases when the other's packet arrives, not at a common clock.
        g_np.rendezvousObserved = true;
        g_np.rendezvousFrame = f;
        g_np.rendezvousTarget = f + static_cast<uint64_t>(g_np.delay);
        g_np.rendezvousLocalMax = t4net::localMax();
        g_np.rendezvousBefore = t4net::remoteContig();
        g_np.rendezvousAfter = g_np.rendezvousBefore;
        const auto begin = std::chrono::steady_clock::now();
        auto end = begin;
        if (g_np.bootRendezvous && !t4net::peerLost())
        {
            ++g_np.rendezvousCalls;
            g_np.rendezvousAfter = t4net::waitRemote(static_cast<uint32_t>(g_np.rendezvousTarget), UINT32_MAX);
            end = std::chrono::steady_clock::now();
            const auto elapsed = end - begin;
            g_np.rendezvousMs = std::chrono::duration<double, std::milli>(elapsed).count();
            npShift(elapsed);
            g_np.liveT += elapsed; // npShift moves scheduler deadlines only; retain the current early margin too.
        }
        g_np.rendezvousReady = g_np.rendezvousAfter > g_np.rendezvousTarget && !t4net::peerLost();
        std::fprintf(g_log, "NETBOOT_EVENT steady_ms=%.3f end_steady_ms=%.3f slot=%d rendezvous=%d f=%" PRIu64
                            " target=%" PRIu64 " local_max=%" PRIu64 " rc_before=%" PRIu64 " rc_after=%" PRIu64
                            " ready=%d wait_ms=%.3f\n",
                     std::chrono::duration<double, std::milli>(begin.time_since_epoch()).count(),
                     std::chrono::duration<double, std::milli>(end.time_since_epoch()).count(), g_np.slot,
                     g_np.bootRendezvous ? 1 : 0, f, g_np.rendezvousTarget, g_np.rendezvousLocalMax,
                     g_np.rendezvousBefore, g_np.rendezvousAfter, g_np.rendezvousReady ? 1 : 0, g_np.rendezvousMs);
    }

    // A re-simulated boundary b < live frame: its snapshot is needed only if a later rollback can go back to it
    // (b >= every confirmed frame: rollbacks start at the first unconfirmed frame or later) or its hash is still to
    // be taken. Otherwise its ring slot is marked empty.
    bool npNeedResimCapture(uint64_t b)
    {
        if (!g_np.lazy)
            return true;
        if (b >= t4net::remoteContig())
            return true;
        if (g_cfg.hashEvery && b % g_cfg.hashEvery == 0u && b >= g_np.hashNext)
            return true;
        return false;
    }

    void npFrameTiming()
    {
        ++g_np.liveFrames;
        ++g_np.runFrames;
        ++g_np.winFrames;
        const auto now = std::chrono::steady_clock::now();
        if (g_np.lastLive.time_since_epoch().count() != 0)
        {
            const double ms = std::chrono::duration<double, std::milli>(now - g_np.lastLive).count();
            g_np.frameTimes.push_back(ms);
            if (g_np.diag)
                g_np.diagGapMaxMs = std::max(g_np.diagGapMaxMs, ms);
            if (g_frame >= g_np.rbStart)
            {
                ++g_np.timedFrames;
                g_np.over20 += ms > 20.0 ? 1u : 0u;
                g_np.over34 += ms > 34.0 ? 1u : 0u;
            }
        }
        g_np.lastLive = now;
        if (tekken4_online_result::enabled())
        {
            const double seconds = msSince(g_np.runT0) / 1000.0;
            tekken4_online_result::liveFrame(g_frame, seconds > 0.0 ? static_cast<double>(g_np.runFrames) / seconds : 0.0);
        }
        if (g_np.winFrames >= 300u)
        {
            g_np.winFps = static_cast<double>(g_np.winFrames) * 1000.0 / std::max(1.0, msSince(g_np.winT0));
            g_np.winFrames = 0;
            g_np.winT0 = now;
        }
    }

    void npShots(uint64_t f)
    {
        while (g_np.shotNext < g_np.shots.size() && g_np.shots[g_np.shotNext] <= f)
        {
            if (g_np.shots[g_np.shotNext] == f)
            {
                std::vector<uint8_t> pixels;
                uint32_t width = 0u, height = 0u;
                const std::string name = "net_shot_f" + std::to_string(f) + ".bmp";
                if (g_runtime->gs().copyLatchedHostPresentationFrame(pixels, width, height) && width && height &&
                    pixels.size() >= static_cast<size_t>(width) * height * 4u)
                    writeBmp(name, pixels, width, height);
            }
            ++g_np.shotNext;
        }
    }

    void npBoundary(uint64_t cycle)
    {
        if (g_np.failed)
            return;
        if (!g_np.started)
        {
            npHandshake();
            if (g_np.failed)
                return;
        }
        const uint64_t f = g_frame;
        uint64_t deferredSyncRc = ~0ull;
        // Replay must reuse recorded input. Only a first live visit may publish before capture; leave liveT
        // assignment below, after npEndResim has restored the live scheduler on a replay's return.
        const bool firstLive = !g_np.resim && g_np.liveTFrame != f;
        const bool sentFirst = firstLive && g_np.sendFirst;
        if (sentFirst)
        {
            g_np.sendFirstInputs += npSendLocal(f);
            ++g_np.sendFirstFrames;
        }
        const auto prepT0 = firstLive && g_np.diag ? std::chrono::steady_clock::now()
                                                 : std::chrono::steady_clock::time_point{};
        if (g_np.resim)
        {
            ++g_np.resimFrames;
            if (f < g_np.liveFrame)
            {
                if (npNeedResimCapture(f))
                    npCapture(cycle); // the corrected state of this boundary replaces the mispredicted one
                else
                {
                    g_np.ringFrame[f % g_np.ring.size()] = ~0ull;
                    ++g_np.lazySkips;
                }
                npDecideInputs(f);
                return;
            }
            npCapture(cycle);
            npEndResim();
            if (g_np.pendingSync.active && g_np.pendingSync.frame == f)
            {
                const auto selected = g_np.pendingSync;
                g_np.pendingSync.active = false; // never repeat the correction on another replay of f
                deferredSyncRc = selected.rc;
                const double delayMs = msSince(selected.selected);
                ++g_np.replaySyncApplied;
                g_np.replaySyncAppliedUs += selected.give.count();
                g_np.replaySyncDelayMs += delayMs;
                g_np.replaySyncMaxDelayMs = std::max(g_np.replaySyncMaxDelayMs, delayMs);
                if (g_np.diag)
                    std::fprintf(g_log, "NETREPLAYSYNC_APPLY steady_ms=%.3f slot=%d f=%" PRIu64
                                        " delay_ms=%.3f give_us=%" PRId64 "\n",
                                 std::chrono::duration<double, std::milli>(
                                     std::chrono::steady_clock::now().time_since_epoch()).count(),
                                 g_np.slot, f, delayMs, static_cast<int64_t>(selected.give.count()));
                // npEndResim has restored the live scheduler. Apply the saved duration and decision once.
                npApplyTimeSync(selected);
            }
        }
        else
            npCapture(cycle);

        hashCollect();
        if (firstLive && g_np.diag)
        {
            const double ms = msSince(prepT0);
            ++g_np.sendPrepFrames;
            g_np.sendPrepMs += ms;
            g_np.sendPrepMaxMs = std::max(g_np.sendPrepMaxMs, ms);
            g_np.sendPrepFrame = f;
            g_np.sendPrepLastMs = ms;
        }
        const bool lockstep = f < g_np.rbStart;
        if (g_np.liveTFrame != f)
        {
            // first visit of this live boundary: its vblank time (the schedule runs earlyMs ahead of it)
            g_np.liveTFrame = f;
            npSpreadSlice();
            const auto next = g_runtime->eeScheduler().nextVblankHostDeadline();
            g_np.liveT = next.time_since_epoch().count() == 0
                             ? std::chrono::steady_clock::now()
                             : next - kVblank + std::chrono::microseconds(g_np.early ? static_cast<int64_t>(g_np.earlyMs * 1000.0) : 0);
            // this side's input for f + delay, sent at once (before any rollback: the peer must not wait for it)
            if (!sentFirst)
                npSendLocal(f);
        }

        if (firstLive)
            npBootRendezvous(f);
        uint64_t rc = t4net::remoteContig();
        if (g_np.liveDone != f)
        {
            // ---- early part: until the frame's vblank time, roll back what is already known to be wrong
            const auto waitT0 = std::chrono::steady_clock::now();
            for (;;)
            {
                // Once overdue, reach sync and the prediction wait before replaying again. Do not scan here:
                // npScan advances checked; the late scan below must still see every pending mismatch.
                if (!lockstep && g_np.early && g_np.earlyDeadline && std::chrono::steady_clock::now() >= g_np.liveT)
                {
                    ++g_np.earlyDeadlineSkips;
                    if (g_np.earlyRollbackFrame == f)
                        ++g_np.earlyDeadlineRevisits;
                    g_np.earlyDeferredFrame = f;
                    break;
                }
                if (!lockstep && g_np.early)
                {
                    const uint64_t g = npScan(f, rc);
                    if (g != ~0ull && npStartRollback(f, g, true))
                        return;
                }
                const auto now = std::chrono::steady_clock::now();
                if (now >= g_np.liveT)
                    break;
                const auto left = std::chrono::duration_cast<std::chrono::microseconds>(g_np.liveT - now).count();
                if (!g_np.early || lockstep || left <= 1500)
                {
                    npSleepUntil(g_np.liveT);
                    break;
                }
                rc = t4net::waitRemoteUs(static_cast<uint32_t>(rc), static_cast<uint32_t>(left - 1000));
            }
            g_np.earlyWaitMs += msSince(waitT0);

            // ---- live part (at the vblank time): time sync, the prediction window, the late rollback
            g_np.liveDone = f;
            if (g_np.autoVs && !g_np.autoVsReleased && f >= g_np.autoVsEnd)
            {
                g_np.autoVsReleased = true; // logging only: never used to decide target-frame input.
                std::fprintf(g_log, "NETAUTO_VS timeout f=%" PRIu64 ": select unverified; neutral release at %" PRIu64
                                    "; normal input restored from %" PRIu64 " (check language/save dialogs)\n",
                             f, g_np.autoVsEnd, g_np.autoVsEnd + 1u);
                std::fflush(g_log);
            }
            npFrameTiming();
            npShots(f);
            t4net::sendNow();
            rc = t4net::remoteContig();
            bool syncReplay = false;
            if (f > g_np.lastLiveFrame)
                syncReplay = npTimeSync(f, rc);
            g_np.lastLiveFrame = std::max(g_np.lastLiveFrame, f);
            if (syncReplay)
                return; // the selected correction remains pending until this live frame's catch-up
        }
        else
        {
            t4net::sendNow();
            rc = t4net::remoteContig();
        }

        // Preserve the pre-sleep frontier in either ordering unless the explicit refresh experiment is enabled.
        if (deferredSyncRc != ~0ull)
            rc = deferredSyncRc;
        // Time sync may have slept while remote input advanced. Use that progress for the wait and late scan.
        if (g_np.refreshRc)
            rc = t4net::remoteContig();
        const uint64_t need = lockstep ? f + 1u : (f > g_np.maxPred ? f - g_np.maxPred : 0u);
        if (rc < need && !t4net::peerLost())
        {
            const auto t0 = std::chrono::steady_clock::now();
            const uint64_t rcBefore = rc;
            uint64_t waitNeed = need;
            rc = t4net::waitRemote(static_cast<uint32_t>(need - 1u), UINT32_MAX);
            if (!lockstep && rc >= need && !t4net::peerLost())
            {
                // Releasing at the limit leaves no spare prediction budget. Only after an existing prediction
                // wait, request up to two frames of headroom. Never require an input beyond f: both peers have already
                // sampled and sent their current input before waiting. Do not scan until this wait is finished.
                const uint64_t target = std::min(f + 1u, need + 2u);
                if (rc < target)
                {
                    ++g_np.headroomOpportunities;
                    if (g_np.predHeadroom)
                    {
                        const auto extraT0 = std::chrono::steady_clock::now();
                        ++g_np.headroomWaits;
                        g_np.headroomRequested += target - rc;
                        g_np.headroomFrame = f;
                        g_np.headroomBefore = rc;
                        g_np.headroomNeed = need;
                        g_np.headroomTarget = target;
                        waitNeed = target;
                        rc = t4net::waitRemote(static_cast<uint32_t>(target - 1u), UINT32_MAX);
                        g_np.headroomWaitMs += msSince(extraT0);
                        g_np.headroomAfter = rc;
                        if (rc >= target)
                            ++g_np.headroomCompleted;
                    }
                }
            }
            const double ms = msSince(t0);
            if (g_np.diag)
            {
                g_np.diagWaitBefore = rcBefore;
                g_np.diagWaitAfter = rc;
                g_np.diagWaitNeed = waitNeed;
                g_np.diagWaitMaxMs = std::max(g_np.diagWaitMaxMs, ms);
            }
            if (lockstep)
            {
                ++g_np.lockWaits;
                g_np.lockWaitMs += ms;
            }
            else
            {
                ++g_np.stalls;
                g_np.stallMs += ms;
            }
            npShift(std::chrono::microseconds(static_cast<int64_t>(ms * 1000.0)));
            if (g_np.diag)
                std::fprintf(g_log, "NETWAIT_EVENT steady_ms=%.3f end_steady_ms=%.3f slot=%d f=%" PRIu64
                                    " lockstep=%d rc_before=%" PRIu64 " rc_after=%" PRIu64 " need=%" PRIu64
                                    " wait_ms=%.3f peer_lost=%d\n",
                             std::chrono::duration<double, std::milli>(t0.time_since_epoch()).count(),
                             std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count(),
                             g_np.slot, f, lockstep ? 1 : 0, rcBefore, rc, waitNeed, ms, t4net::peerLost() ? 1 : 0);
            if (ms > 200.0)
                std::fprintf(g_log, "NET frame %" PRIu64 " waited %.0f ms for the peer's input up to %" PRIu64 " (%s)\n", f, ms,
                             waitNeed - 1u, lockstep ? "lockstep" : "prediction window");
        }

        if (g_np.autoVs && t4net::peerLost())
        {
            // A lost peer may have last sent a held boot press. End the session instead of predicting that
            // press forever; offline recovery uses the native pad path, never an unsynchronized script.
            g_np.failed = true;
            ps2_stubs::setPadInputProvider(nullptr);
            std::fprintf(g_log, "NETAUTO_VS aborted: peer lost at f=%" PRIu64 "; normal offline input restored\n", f);
            std::fflush(g_log);
            npFinishResult("peer_lost", f, t4net::lostReason());
            return;
        }
        const uint64_t firstWrong = npScan(f, rc);
        if (firstWrong != ~0ull && npStartRollback(f, firstWrong, false))
            return;

        // final hashes: boundaries g <= min(rc, f) (every input before g confirmed, no rollback pending), on the
        // hash worker
        const uint64_t upto = std::min(rc, f);
        for (uint64_t g = g_np.hashNext; g <= upto; ++g)
        {
            if (!g_cfg.hashEvery || g % g_cfg.hashEvery != 0u)
                continue;
            const size_t slot = g % g_np.ring.size();
            if (g_np.ringFrame[slot] != g)
                continue;
            hashSubmit(g, slot, g_np.ringCycle[slot]);
        }
        g_np.hashNext = std::max(g_np.hashNext, upto + 1u);
        uint32_t badFrame = 0;
        uint64_t mine = 0, theirs = 0;
        while (t4net::takeMismatch(&badFrame, &mine, &theirs))
        {
            std::fprintf(g_log, "NETDESYNC f=%u local=%016" PRIx64 " peer=%016" PRIx64 "\n", badFrame, mine, theirs);
            for (const NetplayState::Kept &k : g_np.kept)
                if (k.frame == badFrame)
                {
                    std::ofstream out("net_desync_f" + std::to_string(badFrame) + ".bin", std::ios::binary);
                    out.write(reinterpret_cast<const char *>(k.ram.data()), static_cast<std::streamsize>(k.ram.size()));
                }
            npFinishResult("desync", f);
        }

        npDecideInputs(f);
        npPacingGuard();
        npDiag();
        if (t4net::peerLost())
            npFinishResult("peer_lost", f, t4net::lostReason());
        if (g_np.liveFrames % 600u == 0u && g_np.liveDone == f && f == g_np.lastLiveFrame && g_np.lastSummary != f)
        {
            g_np.lastSummary = f;
            npSummary("NETSUMMARY");
        }
        if (!g_np.ended && f >= g_np.endFrame)
        {
            g_np.ended = true;
            npSummary("NETSUMMARY final");
            std::fprintf(g_log, "NETEND f=%" PRIu64 "\n", f);
            t4net::note("NETEND at frame %llu", static_cast<unsigned long long>(f));
            npFinishResult("frame_limit", f);
        }
    }

    // TEKKEN4_NET_BUILD (16 hex digits of tools/t4_buildid.py), else the first word of t4net_build.txt in the working
    // directory; 0 = unknown (then no peer is refused for its build: tests only).
    uint64_t parseBuildId()
    {
        if (const char *id = std::getenv("TEKKEN4_NET_BUILD"); id && *id)
            return std::strtoull(id, nullptr, 16);
        std::ifstream in("t4net_build.txt");
        std::string text;
        if (in >> text)
            return std::strtoull(text.c_str(), nullptr, 16);
        return 0;
    }

    bool autoVsNumber(const std::string &text, uint64_t &value)
    {
        if (text.empty() || text[0] < '0' || text[0] > '9')
            return false;
        char *end = nullptr;
        errno = 0;
        value = std::strtoull(text.c_str(), &end, 0);
        return errno != ERANGE && end && *end == '\0';
    }

    bool npConfigureAutoVs(t4net::Config &c)
    {
        if (!g_np.autoVs)
            return true;
        if (const char *end = std::getenv("TEKKEN4_NET_AUTO_VS_END"))
            if (!autoVsNumber(end, g_np.autoVsEnd) || !g_np.autoVsEnd || g_np.autoVsEnd > 3600u)
            {
                std::fprintf(g_log, "NETAUTO_VS aborted: AUTO_VS_END must be 1..3600; normal offline input restored\n");
                return false;
            }
        const char *input = std::getenv("TEKKEN4_RB_INPUT");
        if (input)
        {
            // The old script parser is permissive. Do not silently negotiate malformed automation as neutral
            // input: validate the finite presses here while leaving ordinary RB_INPUT behavior unchanged.
            const std::string text = input;
            bool valid = text.empty() || (text.front() != ',' && text.back() != ',' && text.find(",,") == std::string::npos);
            for (const std::string &item : split(text, ','))
            {
                const auto parts = split(item, ':');
                uint64_t frame = 0, hold = 6;
                if (parts.size() < 2u || parts.size() > 3u || item.front() == ':' ||
                    item.find("::") != std::string::npos || item.back() == ':' ||
                    !autoVsNumber(parts[0], frame) || (parts.size() == 3u && !autoVsNumber(parts[2], hold)) ||
                    !hold || hold > ~0ull - frame)
                {
                    valid = false;
                    break;
                }
                const std::string &buttons = parts[1];
                if (buttons.front() == '+' || buttons.back() == '+' || buttons.find("++") != std::string::npos)
                    valid = false;
                for (const std::string &name : split(buttons, '+'))
                    if (!buttonByName(name))
                        valid = false;
            }
            if (!valid)
            {
                std::fprintf(g_log, "NETAUTO_VS aborted: invalid TEKKEN4_RB_INPUT; normal offline input restored\n");
                return false;
            }
            g_np.autoVsScript.presses = g_cfg.pads[0].presses;
        }
        else
        {
            // Only the VS-menu prefix of the documented pair script. Later Cross presses select fighters/stage.
            g_np.autoVsScript.presses = {{500, 6, kBtnStart}, {800, 6, kBtnStart}, {960, 6, kBtnDown},
                                         {1020, 6, kBtnDown}, {1080, 6, kBtnCross}};
        }
        g_np.rbStart = std::max(g_np.rbStart, g_np.autoVsEnd + 1u);
        // Hash the effective buttons, not spelling/order of the input list. The transport checks the nonzero
        // fingerprint even with an unknown build ID, before any input is primed. No host time enters this hash.
        uint64_t fingerprint = 14695981039346656037ull;
        const auto mix = [&fingerprint](uint64_t value)
        {
            for (unsigned i = 0; i < 8u; ++i)
            {
                fingerprint ^= static_cast<uint8_t>(value >> (i * 8u));
                fingerprint *= 1099511628211ull;
            }
        };
        mix(1u); // automation contract version
        mix(g_np.autoVsEnd);
        mix(g_np.rbStart);
        mix(g_cfg.boundaryVblank ? 1u : 0u);
        mix(g_cfg.boundaryAny ? 1u : 0u);
        mix(static_cast<uint32_t>(g_cfg.boundaryReason));
        mix(static_cast<uint32_t>(g_cfg.boundaryId));
        for (uint64_t frame = 0; frame <= g_np.autoVsEnd; ++frame)
            mix(npSampleLocal(frame).buttons);
        c.autoVsFingerprint = fingerprint ? fingerprint : 1u;
        std::fprintf(g_log, "NETAUTO_VS enabled: source=%s end=%" PRIu64 " normal_from=%" PRIu64
                            " lockstep_until=%" PRIu64 " fingerprint=%016" PRIx64
                            "; both pads shared, devices neutral, select unverified\n",
                     input ? "TEKKEN4_RB_INPUT" : "pair_prefix", g_np.autoVsEnd, g_np.autoVsEnd + 1u,
                     g_np.rbStart, c.autoVsFingerprint);
        return true;
    }

    bool npConfigure(PS2Runtime &runtime)
    {
        const char *autoVs = std::getenv("TEKKEN4_NET_AUTO_VS");
        g_np.autoVs = autoVs && std::strcmp(autoVs, "1") == 0;
        const char *spec = std::getenv("TEKKEN4_NET");
        if (!spec || !*spec)
            return false;
        t4net::Config c;
        const std::string s = spec;
        if (s.rfind("host:", 0) == 0)
        {
            c.role = t4net::Role::Host;
            c.port = static_cast<uint16_t>(std::atoi(s.c_str() + 5));
            if (const char *peer = std::getenv("TEKKEN4_NET_PEER"))
                c.peer = peer;
        }
        else if (s.rfind("join:", 0) == 0)
        {
            c.role = t4net::Role::Join;
            c.peer = s.substr(5);
            c.port = 0;
            if (const char *port = std::getenv("TEKKEN4_NET_PORT"))
                c.port = static_cast<uint16_t>(std::atoi(port));
        }
        else
        {
            RUNTIME_LOG("[rollback] TEKKEN4_NET=" << spec << ": expected host:<port> or join:<ip>:<port>\n");
            return false;
        }
        if (const char *bind = std::getenv("TEKKEN4_NET_BIND"))
            c.bind = bind;
        if (const char *delay = std::getenv("TEKKEN4_NET_DELAY"); delay && *delay && std::strcmp(delay, "auto") != 0)
            c.delaySetting = std::max(0, std::atoi(delay));
        if (const char *seed = std::getenv("TEKKEN4_NET_SEED"))
            c.seed = static_cast<uint32_t>(std::strtoul(seed, nullptr, 0));
        if (const char *key = std::getenv("TEKKEN4_NET_KEY"))
            c.key = key;
        if (const char *timeout = std::getenv("TEKKEN4_NET_TIMEOUT"))
            c.timeoutS = std::atoi(timeout);
        c.buildId = parseBuildId();
        if (const char *sim = std::getenv("TEKKEN4_NET_SIM"))
            for (const std::string &item : split(sim, ','))
            {
                const auto kv = split(item, '=');
                if (kv.size() != 2)
                    continue;
                if (kv[0] == "lat")
                    c.simLatencyMs = std::atof(kv[1].c_str());
                else if (kv[0] == "jitter")
                    c.simJitterMs = std::atof(kv[1].c_str());
                else if (kv[0] == "loss")
                    c.simLossPercent = std::atof(kv[1].c_str());
                else if (kv[0] == "seed")
                    c.simSeed = static_cast<uint32_t>(parseNumber(kv[1]));
            }
        g_np.slot = c.role == t4net::Role::Host ? 0 : 1;
        if (const char *v = std::getenv("TEKKEN4_NET_MAXPRED"))
            g_np.maxPred = std::max<uint64_t>(1u, std::min<uint64_t>(12u, parseNumber(v)));
        if (const char *v = std::getenv("TEKKEN4_NET_PRED_HEADROOM"))
            g_np.predHeadroom = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_SEND_FIRST"))
            g_np.sendFirst = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_DEFER_RESIM_FLUSH"))
            g_np.deferResimFlush = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_BOOT_RENDEZVOUS"))
            g_np.bootRendezvous = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_RBSTART"))
            g_np.rbStart = parseNumber(v);
        if (const char *v = std::getenv("TEKKEN4_NET_END"))
            g_np.endFrame = parseNumber(v);
        if (const char *v = std::getenv("TEKKEN4_NET_TIMESYNC"))
            g_np.timeSync = parseNumber(v) != 0;
        if (const char *v = std::getenv("TEKKEN4_NET_FAST_SYNC"))
            g_np.fastSync = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_SUBFRAME_SYNC"))
            g_np.subframeSync = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_SYNC_SPREAD"))
            g_np.syncSpread = std::max(0, std::min(60, static_cast<int>(parseNumber(v))));
        if (const char *v = std::getenv("TEKKEN4_NET_FULL_SYNC"))
            g_np.fullSync = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_SYNC_CAP_ONE"))
            g_np.syncCapOne = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_SYNC_GAP_RESET"))
            g_np.syncGapReset = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_SYNC_WALL_HOLD"))
            g_np.syncWallHold = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_SYNC_PROGRESS_ONLY"))
            g_np.syncProgressOnly = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_ATOMIC_INPUT"))
            g_np.atomicInput = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_REPLAY_BATCH"))
            g_np.replayBatch = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_REPLAY_BEFORE_SYNC"))
            g_np.replayBeforeSync = std::strcmp(v, "1") == 0;
        g_np.leadWindow = g_np.fastSync ? 8 : NetplayState::kLeadWin;
        if (const char *v = std::getenv("TEKKEN4_NET_LOCKDELAY"); v && *v && std::strcmp(v, "auto") != 0)
            g_np.lockDelaySetting = std::max(0, std::min(kMaxLockDelay, std::atoi(v)));
        if (const char *v = std::getenv("TEKKEN4_NET_EARLY"))
            g_np.early = parseNumber(v) != 0;
        if (const char *v = std::getenv("TEKKEN4_NET_EARLY_DEADLINE"))
            g_np.earlyDeadline = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_EARLY_MS"))
            g_np.earlyMs = std::max(0.0, std::min(12.0, std::atof(v)));
        if (const char *v = std::getenv("TEKKEN4_NET_LAZY"))
            g_np.lazy = parseNumber(v) != 0;
        if (const char *v = std::getenv("TEKKEN4_NET_HASH_PROFILE"))
            g_np.hashProfile = parseNumber(v) != 0;
        if (const char *v = std::getenv("TEKKEN4_NET_COST_PROFILE"))
            g_np.costProfile = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_DIAG"))
            g_np.diag = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_REFRESH_RC"))
            g_np.refreshRc = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_REBASE_CATCHUP"))
            g_np.rebaseCatchup = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_NET_LOCALPAD"))
            g_np.localPad = parseNumber(v) != 0;
        if (const char *v = std::getenv("TEKKEN4_NET_PAD"))
            g_np.padDevice = std::atoi(v);
        if (const char *v = std::getenv("TEKKEN4_NET_DESYNC_DUMP"))
            g_np.dump = parseNumber(v) != 0;
        if (const char *v = std::getenv("TEKKEN4_NET_SHOTS"))
        {
            for (const std::string &item : split(v, ','))
                g_np.shots.push_back(parseNumber(item));
            std::sort(g_np.shots.begin(), g_np.shots.end());
        }
        if (!npConfigureAutoVs(c))
            return false;
        const size_t ring = static_cast<size_t>(g_np.maxPred + 3u);
        g_np.ring.resize(ring);
        g_np.ringFrame.assign(ring, ~0ull);
        g_np.ringCycle.assign(ring, 0u);
        (void)runtime;
        if (!t4net::start(c))
        {
            RUNTIME_LOG("[rollback] netplay transport did not start (see net.log)\n");
            return false;
        }
        g_np.on = true;
        if (g_np.fastSync)
            RUNTIME_LOG("[rollback] TEKKEN4_NET_FAST_SYNC=1: lead window 8, RTT settling hold unchanged\n");
        return true;
    }
#endif

    // ---------------------------------------------------------------- the boundary
    const char *passLabel()
    {
        if (g_cfg.mode == Mode::SelfNet)
            return g_net.resim ? "R" : (g_frame >= g_cfg.netStart ? "S" : "-");
#ifdef TEKKEN4_NETPLAY
        if (g_cfg.mode == Mode::Net)
            return g_np.resim ? "R" : (g_frame < g_np.rbStart ? "L" : "N");
#endif
        return g_test.resim ? "R" : (g_test.wrong ? "W" : (g_test.active ? "1" : "-"));
    }

    void boundary(const EeBoundaryInfo &info)
    {
        if (info.reason != EeWaitReason::None)
        {
            std::string key = std::string(reasonName(info.reason)) + ":" + std::to_string(info.waitId);
            ++g_wakeCounts[key];
        }
        if (!isBoundary(info))
            return;

        const auto hookStart = std::chrono::steady_clock::now();
        const uint32_t executedCuts = g_frameCuts; // cuts the frame that just ended ran with
        ++g_frame;
        ++g_wallFrames;
        // Inspect the state of the pass that just ended BEFORE a handler restores the timeline or clears
        // its resim flag. Drawn tails and frames without render cuts are still repeated simulation.
        if (!frameIsResimulating() && tekken4_state_probe::enabled())
            tekken4_state_probe::sample(g_frame, g_runtime->memory().getRDRAM(), false);
        std::vector<uint64_t> pages;
        const ps2_rollback::StateHash hash =
            g_cfg.frameHash ? ps2_rollback::hashState(*g_runtime, g_cfg.masks, &pages) : ps2_rollback::StateHash{};
        size_t dirty = 0;
        if (g_prevPages.size() == pages.size())
            for (size_t p = 0; p < pages.size(); ++p)
                dirty += pages[p] != g_prevPages[p] ? 1u : 0u;
        g_prevPages = pages;

        // EE time of the frame: wall time between boundaries minus host pacing waits minus this hook's own time.
        const uint64_t waitNs = g_runtime->eeScheduler().hostWaitNanoseconds();
        const double wallMs = g_lastBoundary.time_since_epoch().count() == 0
                                  ? 0.0
                                  : std::chrono::duration<double, std::milli>(hookStart - g_lastBoundary).count();
        const double eeMs = wallMs - static_cast<double>(waitNs - g_lastWaitNs) / 1e6 - g_hookMs;
        const double gsMs = static_cast<double>(g_gsNs - g_lastGsNs) / 1e6;
        g_lastGsNs = g_gsNs;
        const ps2_rollback::HostProfile &prof = ps2_rollback::g_hostProfile;
        const double vuMs = static_cast<double>(prof.vu1Ns - g_lastProfile.vu1Ns) / 1e6;
        const double vifMs = static_cast<double>(prof.vif1Ns - g_lastProfile.vif1Ns) / 1e6;
        const double iopMs = static_cast<double>(prof.iopNs - g_lastProfile.iopNs) / 1e6;
        const uint64_t vuRuns = prof.vu1Runs - g_lastProfile.vu1Runs;
        g_lastProfile = prof;

        const char *pass = passLabel();
#ifdef TEKKEN4_NETPLAY
        if (g_cfg.mode == Mode::Net && g_np.costProfile && wallMs > 0.0 && g_frame > 2u)
        {
            const size_t kind = pass[0] == 'R' ? ((executedCuts & ps2_rollback::CutDraw) ? 2u : 3u)
                                             : (g_frame - 1u < g_np.rbStart ? 0u : 1u);
            const double costs[] = {eeMs, gsMs, vifMs, vuMs, iopMs};
            for (size_t part = 0; part < 5u; ++part)
                g_np.frameCost[kind][part].add(costs[part]);
        }
#endif
        uint32_t in1 = scriptedButtons(0, g_frame), in2 = g_cfg.pad2 ? scriptedButtons(1, g_frame) : 0u;
#ifdef TEKKEN4_NETPLAY
        if (g_cfg.mode == Mode::Net) // the inputs the frame that just ended ran with
        {
            in1 = g_np.inputs[0].buttons;
            in2 = g_np.inputs[1].buttons;
        }
#endif
        std::fprintf(g_log, "f=%" PRIu64 " tick=%" PRIu64 " dt=%" PRIu64 " cyc=%" PRIu64 " dcyc=%" PRIu64
                            " h=%016" PRIx64 " ram=%016" PRIx64 " oth=%016" PRIx64 " sch=%016" PRIx64
                            " idle=%" PRIu64 " in=%04x in2=%04x ee=%.2f gs=%.2f vif=%.2f vu=%.2f/%" PRIu64 " iop=%.2f wall=%.2f hk=%.2f dirty=%zu t=%.2f p=%s cut=%x run=%d loop=%" PRIu64
                            " wake=%s:%d reg=%s\n",
                     g_frame, info.vsyncTick, info.vsyncTick - g_lastTick, info.eeCycle, info.eeCycle - g_lastCycle,
                     hash.total, hash.rdram, hash.other, hash.scheduler,
                     g_runtime->eeScheduler().idleSkippedCycles() - g_lastIdle, in1, in2, eeMs, gsMs, vifMs, vuMs, vuRuns, iopMs, wallMs, g_hookMs, dirty,
                     std::chrono::duration<double>(hookStart - g_start).count(), pass, executedCuts, info.runningThreadId,
                     tekken4::g_frames - g_lastLoops, reasonName(info.reason), info.waitId, regionsText(hash).c_str());
        g_lastLoops = tekken4::g_frames;
        g_lastIdle = g_runtime->eeScheduler().idleSkippedCycles();
        g_lastTick = info.vsyncTick;
        g_lastCycle = info.eeCycle;
        if (wallMs > 0.0 && g_frame > 2u)
        {
            const std::string kind = pass[0] == 'R' ? ((executedCuts & ps2_rollback::CutDraw) ? "R" : "Rtail") : pass;
            g_eeByKind[kind].push_back(eeMs);
            g_eeByKind[kind + ".gs"].push_back(gsMs);
            g_eeByKind[kind + ".vif"].push_back(vifMs);
            g_eeByKind[kind + ".vu"].push_back(vuMs);
            g_eeByKind[kind + ".iop"].push_back(iopMs);
        }

        if (g_pagesLog && g_frame >= g_cfg.pagesFrom && g_frame <= g_cfg.pagesTo)
        {
            std::fprintf(g_pagesLog, "f=%" PRIu64, g_frame);
            for (const uint64_t page : pages)
                std::fprintf(g_pagesLog, " %016" PRIx64, page);
            std::fprintf(g_pagesLog, "\n");
        }
        if (std::find(g_cfg.dumpFrames.begin(), g_cfg.dumpFrames.end(), g_frame) != g_cfg.dumpFrames.end())
            dumpFrame(g_frame);
#ifdef TEKKEN4_NETPLAY
        if (std::find(g_cfg.shotFrames.begin(), g_cfg.shotFrames.end(), g_frame) != g_cfg.shotFrames.end())
        {
            std::vector<uint8_t> pixels;
            uint32_t width = 0u, height = 0u;
            if (g_runtime->gs().copyLatchedHostPresentationFrame(pixels, width, height) && width && height &&
                pixels.size() >= static_cast<size_t>(width) * height * 4u)
            {
                uint64_t ph = 1469598103934665603ull;
                for (size_t i = 0; i < static_cast<size_t>(width) * height * 4u; ++i)
                    ph = (ph ^ pixels[i]) * 1099511628211ull;
                writeBmp("rb_shot_f" + std::to_string(g_frame) + ".bmp", pixels, width, height);
                std::fprintf(g_log, "SHOT f=%" PRIu64 " %ux%u pix=%016" PRIx64 "\n", g_frame, width, height, ph);
            }
        }
#endif

        if (g_cfg.mode == Mode::Test)
            testBoundary(hash, pages, eeMs);
        else if (g_cfg.mode == Mode::SelfNet)
            netBoundary(eeMs);
        else if (g_cfg.mode == Mode::Measure)
            measureNetHash(info.eeCycle);
#ifdef TEKKEN4_NETPLAY
        else if (g_cfg.mode == Mode::Net)
            npBoundary(info.eeCycle);
#endif

        g_frameCuts = cutsForNextFrame();
        ps2_rollback::setActiveCuts(g_frameCuts);
        startFrameIop((g_frameCuts & ps2_rollback::CutIop) == 0u);
#ifdef PS2X_ROLLBACK_IOP_STATE
        // IOP in the state: keep its bookkeeping running. Host samples from a repeated frame must not be queued
        // again, even with no render cuts or a drawn tail. The opt-in policy uses the timeline, not the cut mask.
        if (g_cfg.iopState)
            ps2_rollback::setIopOutputMuted(g_cfg.audioTimeline ? frameIsResimulating() : g_frameCuts != 0u);
#endif

        if (g_wallFrames % 600u == 0u)
        {
            std::string wakes;
            for (const auto &[key, count] : g_wakeCounts)
                wakes += " " + key + "=" + std::to_string(count);
            std::fprintf(g_log, "WAKES after %" PRIu64 " wall frames:%s\n", g_wallFrames, wakes.c_str());
            std::fprintf(g_log, "COST ee ms per executed frame by pass:%s\n", costText().c_str());
            std::fprintf(g_log, "IOP %s\n", iopText().c_str());
        }
#ifdef TEKKEN4_NETPLAY
        // Use the state AFTER npBoundary: the restore boundary may start replay, and the catch-up boundary
        // may end it. Keep every record, and flush buffered records on live return or a failed/ended session.
        const bool netFlush = g_cfg.mode == Mode::Net;
        const size_t flushKind = netFlush && g_np.resim ? 1u : 0u;
        const bool deferFlush = netFlush && g_np.deferResimFlush && g_np.started &&
                                !g_np.failed && !g_np.ended && g_np.resim;
        if (deferFlush)
            ++g_np.deferredFlushes;
        else
#endif
        {
#ifdef TEKKEN4_NETPLAY
            const auto flushT0 = netFlush ? std::chrono::steady_clock::now()
                                         : std::chrono::steady_clock::time_point{};
#endif
            std::fflush(g_log);
            if (g_pagesLog)
                std::fflush(g_pagesLog);
            if (g_sndLog)
                std::fflush(g_sndLog);
#ifdef TEKKEN4_NETPLAY
            if (netFlush)
            {
                const double ms = msSince(flushT0);
                ++g_np.boundaryFlushes[flushKind];
                g_np.boundaryFlushMs[flushKind] += ms;
                g_np.boundaryFlushMaxMs[flushKind] = std::max(g_np.boundaryFlushMaxMs[flushKind], ms);
            }
#endif
        }

        g_lastWaitNs = g_runtime->eeScheduler().hostWaitNanoseconds();
        const auto hookEnd = std::chrono::steady_clock::now();
        g_hookMs = std::chrono::duration<double, std::milli>(hookEnd - hookStart).count();
        g_lastBoundary = hookStart;
    }

    // The game's srand (0x2a2528: *(_impure_ptr) + 88 = seed), logged with its caller so the seed source is known
    // (phase 0 question 7). Same effect as the original; only installed in rollback mode without TEKKEN4_RAND_SEED.
    void loggedSrand(uint8_t *rdram, R5900Context *ctx, PS2Runtime *runtime)
    {
        (void)runtime;
        const uint32_t seed = getRegU32(ctx, 4);
        const uint32_t ra = getRegU32(ctx, 31);
        uint32_t reent = 0u;
        std::memcpy(&reent, rdram + 0x304b94u, 4);
        SET_GPR_U32(ctx, 2, 0x300000u);
        SET_GPR_U32(ctx, 3, reent);
        uint32_t stored = seed;
#ifdef TEKKEN4_NETPLAY
        if (g_cfg.mode == Mode::Net && g_np.started) // the session's seed: other matches, the same on both peers
            stored = seed ^ g_np.sessionSeed;
#endif
        if (uint8_t *state = getMemPtr(rdram, reent + 88u))
            std::memcpy(state, &stored, 4);
        if (g_log)
            std::fprintf(g_log, "SRAND seed=0x%08x stored=0x%08x ra=0x%08x frame=%" PRIu64 " cycle=%" PRIu64 "\n", seed,
                         stored, ra, g_frame, g_runtime ? g_runtime->eeScheduler().eeCycle() : 0u);
        ctx->pc = ra;
    }

    void parseScript(PadScript &script, const char *input, const char *fuzz)
    {
        if (input)
        {
            g_cfg.scripted = true;
            for (const std::string &item : split(input, ','))
            {
                const auto parts = split(item, ':');
                if (parts.size() < 2)
                    continue;
                ScriptPress press;
                press.frame = parseNumber(parts[0]);
                for (const std::string &name : split(parts[1], '+'))
                    press.buttons |= buttonByName(name);
                if (parts.size() >= 3)
                    press.hold = parseNumber(parts[2]);
                script.presses.push_back(press);
            }
        }
        if (fuzz)
        {
            g_cfg.scripted = true;
            const auto parts = split(fuzz, ':');
            if (!parts.empty())
                script.fuzzFrom = parseNumber(parts[0]);
            script.fuzzTo = parts.size() >= 2 ? parseNumber(parts[1]) : ~0ull;
        }
    }

    void apply(PS2Runtime &runtime)
    {
        const char *mode = std::getenv("TEKKEN4_RB_MODE");
        const char *netSpec = std::getenv("TEKKEN4_NET");
        if ((!mode || !*mode) && netSpec && *netSpec)
            mode = "net";
        if (!mode || !*mode)
            return;
        if (std::strcmp(mode, "measure") == 0)
            g_cfg.mode = Mode::Measure;
        else if (std::strcmp(mode, "test") == 0)
            g_cfg.mode = Mode::Test;
        else if (std::strcmp(mode, "selfnet") == 0)
            g_cfg.mode = Mode::SelfNet;
#ifdef TEKKEN4_NETPLAY
        else if (std::strcmp(mode, "net") == 0)
            g_cfg.mode = Mode::Net;
#endif
        else
        {
            RUNTIME_LOG("[rollback] unknown TEKKEN4_RB_MODE=" << mode << " (measure|test|selfnet|net), rollback off\n");
            return;
        }
        g_runtime = &runtime;
        g_start = std::chrono::steady_clock::now();
        g_cfg.masks = kBuiltinMasks;
        if (const char *masks = std::getenv("TEKKEN4_RB_MASK"))
            for (const std::string &item : split(masks, ','))
            {
                const auto parts = split(item, ':');
                if (parts.size() == 2)
                    g_cfg.masks.push_back({static_cast<uint32_t>(parseNumber(parts[0])) & 0x1FFFFFFFu,
                                           static_cast<uint32_t>(parseNumber(parts[1]))});
            }
        g_cfg.pads[1].salt = 0x5EC0u;
        parseScript(g_cfg.pads[0], std::getenv("TEKKEN4_RB_INPUT"), std::getenv("TEKKEN4_RB_FUZZ"));
        parseScript(g_cfg.pads[1], std::getenv("TEKKEN4_RB_INPUT2"), std::getenv("TEKKEN4_RB_FUZZ2"));
        if (const char *pad2 = std::getenv("TEKKEN4_RB_PAD2"); pad2 && parseNumber(pad2) != 0)
            g_cfg.pad2 = true;
        if (g_cfg.mode == Mode::SelfNet)
        {
            g_cfg.pad2 = true;
            g_cfg.scripted = true;
        }
        if (g_cfg.mode == Mode::Net)
        {
            g_cfg.pad2 = true;
            g_cfg.scripted = true; // the provider answers for both ports
            g_cfg.iopState = true;
            g_cfg.frameHash = false;
            g_cfg.hashEvery = 30;
        }
        if (const char *v = std::getenv("TEKKEN4_RB_IOPSTATE"))
            g_cfg.iopState = parseNumber(v) != 0;
        if (const char *v = std::getenv("TEKKEN4_RB_AUDIO_TIMELINE"))
            g_cfg.audioTimeline = std::strcmp(v, "1") == 0;
        if (const char *v = std::getenv("TEKKEN4_RB_FRAMEHASH"))
            g_cfg.frameHash = parseNumber(v) != 0;
        if (const char *v = std::getenv("TEKKEN4_NET_HASH_EVERY"))
            g_cfg.hashEvery = parseNumber(v);
#ifndef PS2X_ROLLBACK_IOP_STATE
        g_cfg.iopState = false;
#endif
        if (const char *which = std::getenv("TEKKEN4_RB_BOUNDARY"))
        {
            const auto parts = split(which, ':');
            const std::string kind = parts.empty() ? "" : parts[0];
            g_cfg.boundaryVblank = kind == "vblank";
            if (kind == "any")
                g_cfg.boundaryAny = true;
            else if (kind == "sema")
                g_cfg.boundaryReason = EeWaitReason::Semaphore;
            else if (kind == "evf")
                g_cfg.boundaryReason = EeWaitReason::EventFlag;
            else if (kind == "sleep")
                g_cfg.boundaryReason = EeWaitReason::Sleep;
            else
                g_cfg.boundaryReason = EeWaitReason::VSync;
            if (parts.size() >= 2)
                g_cfg.boundaryId = static_cast<int>(parseNumber(parts[1]));
        }
        if (const char *dump = std::getenv("TEKKEN4_RB_DUMP"))
            for (const std::string &item : split(dump, ','))
                g_cfg.dumpFrames.push_back(parseNumber(item));
        // TEKKEN4_RB_SHOTS="<frame>,...": rb_shot_f<frame>.bmp = the presented picture at that frame boundary, and a
        // SHOT line with its pixel hash in rb_frames.log (frame-exact picture comparisons between builds; t4vurecomp)
        if (const char *shots = std::getenv("TEKKEN4_RB_SHOTS"))
            for (const std::string &item : split(shots, ','))
                g_cfg.shotFrames.push_back(parseNumber(item));
        if (const char *pagesSpec = std::getenv("TEKKEN4_RB_PAGES"))
        {
            const auto parts = split(pagesSpec, ':');
            if (parts.size() == 2)
            {
                g_cfg.pagesFrom = parseNumber(parts[0]);
                g_cfg.pagesTo = parseNumber(parts[1]);
                g_pagesLog = std::fopen("rb_pages.log", "w");
            }
        }
        if (const char *test = std::getenv("TEKKEN4_RB_TEST"))
            for (const std::string &item : split(test, ','))
            {
                const auto parts = split(item, '=');
                if (parts.size() != 2)
                    continue;
                if (parts[0] == "start")
                    g_cfg.testStart = parseNumber(parts[1]);
                else if (parts[0] == "every")
                    g_cfg.testEvery = std::max<uint64_t>(2u, parseNumber(parts[1]));
                else if (parts[0] == "depth")
                    g_cfg.testDepth = std::max<uint64_t>(1u, parseNumber(parts[1]));
                else if (parts[0] == "words")
                    g_cfg.testWords = parseNumber(parts[1]) != 0;
                else if (parts[0] == "mispredict")
                    g_cfg.testMispredict = parseNumber(parts[1]) != 0;
            }
        if (g_cfg.mode == Mode::Test && g_cfg.testDepth >= g_cfg.testEvery)
            g_cfg.testDepth = g_cfg.testEvery - 1u;
        if (const char *net = std::getenv("TEKKEN4_RB_NET"))
            for (const std::string &item : split(net, ','))
            {
                const auto parts = split(item, '=');
                if (parts.size() != 2)
                    continue;
                if (parts[0] == "start")
                    g_cfg.netStart = parseNumber(parts[1]);
                else if (parts[0] == "delay")
                    g_cfg.netDelay = std::max<uint64_t>(1u, parseNumber(parts[1]));
                else if (parts[0] == "jitter")
                    g_cfg.netJitter = parseNumber(parts[1]);
                else if (parts[0] == "max")
                    g_cfg.netMax = std::max<uint64_t>(1u, parseNumber(parts[1]));
            }
        if (g_cfg.netMax < g_cfg.netDelay)
            g_cfg.netMax = g_cfg.netDelay;
        if (const char *cut = std::getenv("TEKKEN4_RB_CUT"))
        {
            g_cfg.cuts = 0;
            for (const std::string &item : split(cut, ','))
            {
                if (item == "draw")
                    g_cfg.cuts |= ps2_rollback::CutDraw;
                else if (item == "upload")
                    g_cfg.cuts |= ps2_rollback::CutUpload;
                else if (item == "iop")
                    g_cfg.cuts |= ps2_rollback::CutIop;
                else if (item == "present")
                    g_cfg.cuts |= ps2_rollback::CutPresent;
                else if (item == "vu1")
                    g_cfg.cuts |= ps2_rollback::CutVu1;
            }
        }
        // IOP in the state: re-simulated frames run it, so no IOP cut (and no gate, below)
        if (g_cfg.iopState)
            g_cfg.cuts &= ~static_cast<uint32_t>(ps2_rollback::CutIop);
        // VU1 data memory is output state once VU1 runs are cut (docs/ROLLBACK_PHASE2.md): not hashed then.
        ps2_rollback::g_hostProfile.hashVu1Data = (g_cfg.cuts & ps2_rollback::CutVu1) == 0u;
        if (const char *hashVu1 = std::getenv("TEKKEN4_RB_HASHVU1"))
            ps2_rollback::g_hostProfile.hashVu1Data = parseNumber(hashVu1) != 0;
        ps2_rollback::g_hostProfile.on = true;
        // netplay (phase 3b): no drawn tail by default. The tail frame (~11 ms with VU1 and GS, against ~6 ms cut, plus
        // its GPU work) made every rollback a picture shown twice; without it the first live frame after a rollback
        // still shows the picture of the mispredicted pass and the corrected one comes a frame later. Pair at RTT
        // 100: fight 48 -> 55 fps, displayed p99 ~115 -> ~75 ms (docs/ROLLBACK_PHASE3B.md). TEKKEN4_RB_CUT_TAIL=1: as before.
        if (g_cfg.mode == Mode::Net)
            g_cfg.cutTail = 0;
        if (const char *tail = std::getenv("TEKKEN4_RB_CUT_TAIL"))
            g_cfg.cutTail = parseNumber(tail);
        if (const char *snd = std::getenv("TEKKEN4_RB_SND"))
            g_cfg.sndForward = std::strcmp(snd, "forward") == 0;
        if (const char *trace = std::getenv("TEKKEN4_RB_SNDTRACE"))
            g_cfg.sndTrace = parseNumber(trace) != 0;

#ifdef TEKKEN4_NETPLAY
        if (g_cfg.mode == Mode::Net)
            tekken4_online_result::configure(-1);
#endif
        g_log = std::fopen("rb_frames.log", "w");
        if (!g_log)
        {
            RUNTIME_LOG("[rollback] cannot open rb_frames.log, rollback off\n");
#ifdef TEKKEN4_NETPLAY
            if (g_cfg.mode == Mode::Net)
                tekken4_online_result::finish("rollback_log_failed", g_frame);
#endif
            return;
        }
        if (g_cfg.sndTrace)
            g_sndLog = std::fopen("rb_sound.log", "w");
        if (g_cfg.mode == Mode::SelfNet)
        {
            const size_t size = static_cast<size_t>(g_cfg.netMax + g_cfg.netJitter + 2u);
            g_net.ring.resize(size);
            g_net.ringFrame.assign(size, ~0ull);
        }
#ifdef PS2X_ROLLBACK_IOP_STATE
        ps2_rollback::setIncludeIop(g_cfg.iopState);
#endif
#ifdef TEKKEN4_NETPLAY
        if (g_cfg.mode == Mode::Net && !npConfigure(runtime))
        {
            std::fprintf(g_log, "NET not started (TEKKEN4_NET missing or invalid, or the socket failed): netplay off\n");
            g_np.failed = true;
            if (g_np.autoVs)
            {
                g_cfg.scripted = false; // no provider installed yet: retain the normal offline pad path.
                std::fprintf(g_log, "NETAUTO_VS aborted: netplay configuration failed; normal offline input restored\n");
                std::fflush(g_log);
            }
            npFinishResult("configure_failed", g_frame);
        }
#endif
        std::fprintf(g_log, "CONFIG mode=%s cuts=%x tail=%" PRIu64 " snd=%s pad2=%d net=start:%" PRIu64 ",delay:%" PRIu64
                            ",jitter:%" PRIu64 ",max:%" PRIu64 " iopstate=%d framehash=%d hashevery=%" PRIu64 "\n",
                     mode, g_cfg.cuts, g_cfg.cutTail, g_cfg.sndForward ? "forward" : "replay", g_cfg.pad2 ? 1 : 0,
                     g_cfg.netStart, g_cfg.netDelay, g_cfg.netJitter, g_cfg.netMax, g_cfg.iopState ? 1 : 0,
                     g_cfg.frameHash ? 1 : 0, g_cfg.hashEvery);
        if (g_cfg.audioTimeline)
            std::fprintf(g_log, "AUDIO_TIMELINE logical-resim mute; iopstate=%d\n", g_cfg.iopState ? 1 : 0);
        if (g_cfg.scripted)
            ps2_stubs::setPadInputProvider(padProvider);
        if (const char *perf = std::getenv("TEKKEN4_PERF_LOG"); !perf || !*perf)
        {
            // GS packet processing runs on the EE thread: time it so EE-only cost = ee - gs (TEKKEN4_PERF_LOG
            // installs its own wrapper; then gs= stays 0).
            PS2Runtime *rt = &runtime;
            runtime.gifArbiter().setProcessPacketFn([rt](const uint8_t *data, uint32_t size)
                                                    {
                                                        const auto t0 = std::chrono::steady_clock::now();
                                                        rt->gs().processGIFPacket(data, size);
                                                        g_gsNs += static_cast<uint64_t>(
                                                            std::chrono::duration_cast<std::chrono::nanoseconds>(
                                                                std::chrono::steady_clock::now() - t0).count());
                                                    });
        }
        if (const char *seed = std::getenv("TEKKEN4_RAND_SEED"); !seed || !*seed)
            runtime.registerFunction(0x002a2528u, loggedSrand);
        // The IOP gate logs what the IOP does to the EE on every live frame (only needed when frames are
        // re-simulated with the IOP frozen, but cheap, and measure runs then show the same counters).
        if (!g_cfg.iopState)
            ps2_rollback::setIopGate(&g_gate);
        // The main loop's vsync wait FUN_0022a140 polls 0x1ccafb7 at 0x22a150 until the vblank handler clears it:
        // pure cycle burning, skipped in bulk up to the next event (TEKKEN4_RB_IDLE=0: iterate as the game does).
        if (const char *idle = std::getenv("TEKKEN4_RB_IDLE"); !idle || parseNumber(idle) != 0)
            runtime.eeScheduler().setIdleLoopPcs({0x0022a150u});
        runtime.eeScheduler().setBoundaryHook(boundary);
        RUNTIME_LOG("[rollback] TEKKEN4_RB_MODE=" << mode << ": boundary hook installed, "
                                                  << g_cfg.masks.size() << " hash masks, scripted input "
                                                  << (g_cfg.scripted ? "on" : "off") << ", resim cuts 0x" << std::hex
                                                  << g_cfg.cuts << std::dec << "\n");
    }
}

PS2_REGISTER_GAME_OVERRIDE("Tekken 4 rollback (SLUS-20328 v1.00)", "SLUS_203.28", 0x00180088u, 0xB975F704u,
                           tekken4_rollback::apply)
