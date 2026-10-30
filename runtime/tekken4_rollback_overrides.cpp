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
#if __has_include("tekken4_net.h") && defined(PS2X_ROLLBACK_IOP_STATE)
#include "tekken4_net.h"
#define TEKKEN4_NETPLAY 1
#include <cmath>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <thread>
#endif

#include <algorithm>
#include <chrono>
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
        std::vector<double> passCost; // restore + EE time of each rollback's re-simulated frames
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
    std::map<std::string, std::vector<double>> g_eeByKind; // EE ms per executed frame, by pass kind
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

    double percentile(std::vector<double> values, double p)
    {
        if (values.empty())
            return 0.0;
        std::sort(values.begin(), values.end());
        const size_t at = std::min(values.size() - 1u, static_cast<size_t>(p * static_cast<double>(values.size() - 1u) + 0.5));
        return values[at];
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
        // phase 3b: early rollback (T5 sec. 27): the boundary may come up to earlyMs before its vblank time; what is
        // already known to be mispredicted is rolled back in that wait, and inputs that arrive during it too
        bool early = true;
        double earlyMs = 4.0;
        bool lazy = true; // re-simulated boundaries no rollback can reach again are not captured (T5 sec. 33.4)
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
        int leadMine[kLeadWin]{}, leadTheirs[kLeadWin]{};
        int leadN = 0;
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
        std::vector<double> rbCost, frameTimes;
        std::chrono::steady_clock::time_point lastLive{}, winT0{}, runT0{};
        uint64_t winFrames = 0, runFrames = 0;
        double winFps = 0;
        uint32_t sessionSeed = 0;
        uint64_t lastSummary = ~0ull;
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
        g_hw.todo.push_back(std::move(job));
        g_hw.cv.notify_one();
    }

    // Before a ring slot is written again: no hash job may still read it.
    void hashWaitSlot(size_t slot)
    {
        std::unique_lock<std::mutex> lk(g_hw.mu);
        g_hw.doneCv.wait(lk, [slot]
                         {
                             if (g_hw.busySlot == static_cast<long>(slot))
                                 return false;
                             for (const HashJob &j : g_hw.todo)
                                 if (j.slot == slot)
                                     return false;
                             return true; });
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
            g_np.hashMs += job.ms;
            ++g_np.hashes;
            t4net::pushHash(static_cast<uint32_t>(job.frame), job.h.total);
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

    // The inputs frame g runs with: this side's (decided delay frames ago), the peer's (confirmed, or the last
    // confirmed one repeated = predicted).
    void npDecideInputs(uint64_t g)
    {
        t4net::PadInput local{}, remote{};
        (void)t4net::local(static_cast<uint32_t>(g), &local);
        bool predicted = false;
        if (!t4net::remote(static_cast<uint32_t>(g), &remote))
        {
            predicted = true;
            const uint32_t rc = t4net::remoteContig();
            if (rc == 0 || !t4net::remote(rc - 1u, &remote))
                remote = t4net::PadInput{};
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
    uint64_t npScan(uint64_t f, uint64_t rc)
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
                ++g_np.mispredicted;
                break;
            }
        }
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
        g_np.captureMs += msSince(t0);
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
        g_np.liveVblank = g_runtime->eeScheduler().nextVblankHostDeadline();
        g_np.rbT0 = std::chrono::steady_clock::now();
        ps2_rollback::restore(*g_runtime, g_np.ring[slot]);
        g_np.restoreMs += msSince(g_np.rbT0);
        const uint64_t depth = f - g;
        ++g_np.rollbacks;
        if (early)
            ++g_np.earlyRollbacks;
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
        g_np.rbCost.push_back(msSince(g_np.rbT0));
        // the restored scheduler carries the host times of the snapshot's day: put the live schedule back
        const auto now = g_runtime->eeScheduler().nextVblankHostDeadline();
        if (now.time_since_epoch().count() != 0 && g_np.liveVblank.time_since_epoch().count() != 0)
            npShift(g_np.liveVblank - now);
        ps2_rollback::setIopOutputMuted(false);
    }

    void npTimeSync(uint64_t f, uint64_t rc)
    {
        const int peerFrame = static_cast<int>(rc) - 1 - g_np.delay;
        const int mine = static_cast<int>(f) - peerFrame;
        t4net::setLead(mine);
        // (after the lockstep both sides' inputs run up to lockDelay - delay frames further ahead for a few frames:
        // no samples before tsFrom)
        if (f < g_np.tsFrom)
            return;
        if (f >= g_np.tsHold)
        {
            g_np.leadMine[g_np.leadN % NetplayState::kLeadWin] = mine;
            g_np.leadTheirs[g_np.leadN % NetplayState::kLeadWin] = t4net::peerLead();
            ++g_np.leadN;
        }
        if (!g_np.timeSync || g_np.leadN < NetplayState::kLeadWin || t4net::peerLost())
            return;
        int d[NetplayState::kLeadWin];
        for (int i = 0; i < NetplayState::kLeadWin; ++i)
            d[i] = g_np.leadMine[i] - g_np.leadTheirs[i];
        std::sort(d, d + NetplayState::kLeadWin);
        const int cut = NetplayState::kLeadWin / 5;
        double sum = 0;
        for (int i = cut; i < NetplayState::kLeadWin - cut; ++i)
            sum += d[i];
        const double adv = sum / (2.0 * (NetplayState::kLeadWin - 2 * cut)); // frames this side is ahead
        if (adv < 1.0 || f - g_np.lastCorrection < 10u)
            return;
        const int frames = adv >= 2.5 ? std::min(4, static_cast<int>(adv + 0.5)) : 1;
        // give the frames up as whole vblank periods: this frame's live part starts that much later and the
        // schedule moves with it (the picture on screen stays exactly that many periods longer)
        const auto give = kVblank * frames;
        npSleepUntil(std::max(std::chrono::steady_clock::now(), g_np.liveT) + give);
        npShift(give);
        const double ms = std::chrono::duration<double, std::milli>(give).count();
        const int rtt = t4net::rttMs();
        g_np.tsHold = f + static_cast<uint64_t>(frames) + (rtt > 0 ? static_cast<uint64_t>(rtt / 16.667 + 0.999) : 0u) + 2u;
        g_np.leadN = 0;
        g_np.lastCorrection = f;
        ++g_np.corrections;
        g_np.correctionMs += ms;
        std::fprintf(g_log, "NETTS f=%" PRIu64 " ahead %.2f frames: gave up %d frame(s)\n", f, adv, frames);
    }

    // Never more than ~3 frames behind the host schedule: a slow stretch (a rollback, the stage that runs at 33 fps)
    // is not caught up later in a burst.
    void npPacingGuard()
    {
        const auto next = g_runtime->eeScheduler().nextVblankHostDeadline();
        if (next.time_since_epoch().count() == 0)
            return;
        const auto late = std::chrono::steady_clock::now() - next;
        if (late > std::chrono::milliseconds(50))
        {
            npShift(late);
            ++g_np.rebases;
            g_np.rebaseMs += std::chrono::duration<double, std::milli>(late).count();
        }
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
                     " resends %" PRIu64 "; capture avg %.2f restore avg %.2f hash avg %.2f ms; peer %s"
                     "; lockstep waits %" PRIu64 " (%.0f ms) lock delay %d; early rollbacks %" PRIu64 " (wait for the vblank %.0f ms)"
                     "; lazy captures skipped %" PRIu64 "; frames > 20 ms %" PRIu64 " > 34 ms %" PRIu64 " of %" PRIu64
                     "; rdram pages per capture %.0f per restore %.0f%s\n",
                     tag, g_np.liveFrames, g_frame, g_np.winFps, runS > 0 ? static_cast<double>(g_np.runFrames) / runS : 0.0,
                     g_np.rollbacks, g_np.resimFrames, g_np.maxDepth, hist.c_str(), g_np.predicted, g_np.mispredicted,
                     percentile(g_np.rbCost, 0.5), percentile(g_np.rbCost, 0.9), percentile(g_np.rbCost, 1.0), g_np.stalls,
                     g_np.stallMs, g_np.corrections, g_np.correctionMs, g_np.rebases, g_np.rebaseMs,
                     percentile(g_np.frameTimes, 0.5), percentile(g_np.frameTimes, 0.9), percentile(g_np.frameTimes, 0.99), rtt,
                     samples, g_np.delay, t4net::hashesCompared(), t4net::hashMismatches(), st.packetsOut, st.packetsIn,
                     st.simDropped, st.resends, g_np.captures ? g_np.captureMs / static_cast<double>(g_np.captures) : 0.0,
                     g_np.rollbacks ? g_np.restoreMs / static_cast<double>(g_np.rollbacks) : 0.0,
                     g_np.hashes ? g_np.hashMs / static_cast<double>(g_np.hashes) : 0.0,
                     t4net::peerLost() ? (t4net::lostReason() ? t4net::lostReason() : "lost") : "ok",
                     g_np.lockWaits, g_np.lockWaitMs, g_np.lockDelay, g_np.earlyRollbacks, g_np.earlyWaitMs, g_np.lazySkips,
                     g_np.over20, g_np.over34, g_np.timedFrames,
                     cs.captures ? static_cast<double>(cs.capturePages) / static_cast<double>(cs.captures) : 0.0,
                     cs.restores ? static_cast<double>(cs.restorePages) / static_cast<double>(cs.restores) : 0.0,
                     cs.verifyMismatchPages ? (" VERIFY MISMATCH PAGES " + std::to_string(cs.verifyMismatchPages)).c_str() : "");
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
        // the boot waited: pace from now; with early rollback the schedule runs earlyMs ahead of the vblank times
        // the frames' live parts keep (liveT)
        npShift(std::chrono::steady_clock::now() - t0 -
                std::chrono::microseconds(g_np.early ? static_cast<int64_t>(g_np.earlyMs * 1000.0) : 0));
        std::fprintf(g_log, "NET connected: slot %d, delay %d (lockstep %d), frames < %" PRIu64 " neutral, lockstep until %" PRIu64
                            ", max prediction %" PRIu64 ", session seed %08x, handshake %.0f ms, early rollback %s (%.1f ms), lazy %d\n",
                     g_np.slot, g_np.delay, g_np.lockDelay, base, g_np.rbStart, g_np.maxPred, g_np.sessionSeed, msSince(t0),
                     g_np.early ? "on" : "off", g_np.earlyMs, g_np.lazy ? 1 : 0);
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
            if (g_frame >= g_np.rbStart)
            {
                ++g_np.timedFrames;
                g_np.over20 += ms > 20.0 ? 1u : 0u;
                g_np.over34 += ms > 34.0 ? 1u : 0u;
            }
        }
        if (g_np.frameTimes.size() > 20000u)
            g_np.frameTimes.erase(g_np.frameTimes.begin(), g_np.frameTimes.begin() + 10000);
        g_np.lastLive = now;
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
        }
        else
            npCapture(cycle);

        hashCollect();
        const bool lockstep = f < g_np.rbStart;
        if (g_np.liveTFrame != f)
        {
            // first visit of this live boundary: its vblank time (the schedule runs earlyMs ahead of it)
            g_np.liveTFrame = f;
            const auto next = g_runtime->eeScheduler().nextVblankHostDeadline();
            g_np.liveT = next.time_since_epoch().count() == 0
                             ? std::chrono::steady_clock::now()
                             : next - kVblank + std::chrono::microseconds(g_np.early ? static_cast<int64_t>(g_np.earlyMs * 1000.0) : 0);
            // this side's input for f + delay, sent at once (before any rollback: the peer must not wait for it)
            const uint64_t ahead = static_cast<uint64_t>(lockstep ? g_np.lockDelay : g_np.delay);
            for (uint64_t u = t4net::localMax(); u <= f + ahead; ++u)
                t4net::setLocal(static_cast<uint32_t>(u), npSampleLocal(u));
            t4net::sendNow();
        }

        uint64_t rc = t4net::remoteContig();
        if (g_np.liveDone != f)
        {
            // ---- early part: until the frame's vblank time, roll back what is already known to be wrong
            const auto waitT0 = std::chrono::steady_clock::now();
            for (;;)
            {
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
            npFrameTiming();
            npShots(f);
            t4net::sendNow();
            rc = t4net::remoteContig();
            if (f > g_np.lastLiveFrame)
                npTimeSync(f, rc);
            g_np.lastLiveFrame = std::max(g_np.lastLiveFrame, f);
        }
        else
        {
            t4net::sendNow();
            rc = t4net::remoteContig();
        }

        const uint64_t need = lockstep ? f + 1u : (f > g_np.maxPred ? f - g_np.maxPred : 0u);
        if (rc < need && !t4net::peerLost())
        {
            const auto t0 = std::chrono::steady_clock::now();
            rc = t4net::waitRemote(static_cast<uint32_t>(need - 1u), UINT32_MAX);
            const double ms = msSince(t0);
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
            if (ms > 200.0)
                std::fprintf(g_log, "NET frame %" PRIu64 " waited %.0f ms for the peer's input up to %" PRIu64 " (%s)\n", f, ms,
                             need - 1u, lockstep ? "lockstep" : "prediction window");
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
        }

        npDecideInputs(f);
        npPacingGuard();
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

    bool npConfigure(PS2Runtime &runtime)
    {
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
        if (const char *v = std::getenv("TEKKEN4_NET_RBSTART"))
            g_np.rbStart = parseNumber(v);
        if (const char *v = std::getenv("TEKKEN4_NET_END"))
            g_np.endFrame = parseNumber(v);
        if (const char *v = std::getenv("TEKKEN4_NET_TIMESYNC"))
            g_np.timeSync = parseNumber(v) != 0;
        if (const char *v = std::getenv("TEKKEN4_NET_LOCKDELAY"); v && *v && std::strcmp(v, "auto") != 0)
            g_np.lockDelaySetting = std::max(0, std::min(kMaxLockDelay, std::atoi(v)));
        if (const char *v = std::getenv("TEKKEN4_NET_EARLY"))
            g_np.early = parseNumber(v) != 0;
        if (const char *v = std::getenv("TEKKEN4_NET_EARLY_MS"))
            g_np.earlyMs = std::max(0.0, std::min(12.0, std::atof(v)));
        if (const char *v = std::getenv("TEKKEN4_NET_LAZY"))
            g_np.lazy = parseNumber(v) != 0;
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
        // IOP in the state: a re-simulated frame (any cut) runs the IOP, its SPU2 output was already heard live
        if (g_cfg.iopState)
            ps2_rollback::setIopOutputMuted(g_frameCuts != 0u);
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
        std::fflush(g_log);
        if (g_pagesLog)
            std::fflush(g_pagesLog);
        if (g_sndLog)
            std::fflush(g_sndLog);

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

        g_log = std::fopen("rb_frames.log", "w");
        if (!g_log)
        {
            RUNTIME_LOG("[rollback] cannot open rb_frames.log, rollback off\n");
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
        }
#endif
        std::fprintf(g_log, "CONFIG mode=%s cuts=%x tail=%" PRIu64 " snd=%s pad2=%d net=start:%" PRIu64 ",delay:%" PRIu64
                            ",jitter:%" PRIu64 ",max:%" PRIu64 " iopstate=%d framehash=%d hashevery=%" PRIu64 "\n",
                     mode, g_cfg.cuts, g_cfg.cutTail, g_cfg.sndForward ? "forward" : "replay", g_cfg.pad2 ? 1 : 0,
                     g_cfg.netStart, g_cfg.netDelay, g_cfg.netJitter, g_cfg.netMax, g_cfg.iopState ? 1 : 0,
                     g_cfg.frameHash ? 1 : 0, g_cfg.hashEvery);
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
