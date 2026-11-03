# Rollback phase 3: real two-process netplay over UDP

Status 2026-10-29. Plan: `docs/ROLLBACK_PLAN.md`, phases 0-2: `docs/ROLLBACK_PHASE01.md`, `docs/ROLLBACK_PHASE2.md`.
T5DR reference: `docs/ROLLBACK.md` / `docs/NETPLAY.md` of T5DR Online ("T5 §n"), `src/netplay/netplay_core.cpp`,
`src/rollback/rb_net.cpp`, `lobby/t5lobby/buildid.py`.

Summary: two game instances on this PC, each its own process, run dir, memory card and window, over loopback UDP
with an in-process network simulator (each side's sends delayed by RTT/2 +- jitter, 3 % dropped), sound on, both
pads driven frame-exactly from scripts (host = pad 1, joiner = pad 2: VS BATTLE, Kazuya vs Paul on the cage stage,
both rounds with KOs, win poses/replays, then the next match on Underground), boot to logical frame 12 000:

| run | RTT (measured) | input delay | rollbacks host / join | re-simulated frames | max depth | rollback ms p50 / p90 / max (host; join) | stalls host / join | time-sync corrections | fps whole run / fights (f 2400-12000) | displayed frame p50 / p99 ms | final-state hashes compared | desyncs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `n0b` | 0 (0) | 1 | 11 / 356 | 12 / 394 | 2 / 9 | 13.9 / 15.0 / 22.1; 26.2 / 28.5 / 104.9 | 0 / 4 (0.2 s) | 3 / 57 | 40.6 / 38.2 | 22.0 / 42.5; 21.5 / 51.7 | 418 (+ vs ref: 418) | **0** |
| `n50b` | 50 (48) | 1 | 727 / 1327 | 927 / 1655 | 3 / 4 | 16.9 / 26.4 / 41.3; 22.2 / 28.3 / 43.6 | 409 / 417 (2.4 s, the lockstep boot) | 3 / 4 | 39.0 / 36.8 | 26.0 / 45.7; 26.2 / 53.3 | 416 (+ ref 416) | **0** |
| `n150b` | 150 (148-151) | 3 (auto) | 808 / 1148 | 1416 / 1955 | 5 / 6 | 19.7 / 30.6 / 48.0; 21.2 / 31.2 / 56.9 | 423 / 410 (3.7 s) | 1 / 26 | 38.9 / 36.9 | 27.1 / 46.0; 27.2 / 52.8 | 402 (+ ref 402) | **0** |

- **0 sampled hash mismatches**: host and joiner agree on the final-state hash (RDRAM + scratchpad + VU0, IOP RAM + SPU2 RAM + IOP
  threads, EE cycle) of every 30th frame from frame 30 to 12 000+, and both agree with `nref`, a single-process
  measure run fed the same inputs on time (`docs/rollback/net_compare.py`). This establishes agreement of the
  covered state at those sampled frames. It does not check every frame or prove identical presented pictures,
  heard audio or smooth play; the separate picture, sound and timing observations below have their own limits.
- **Pictures** (`net_shot_f*.bmp` at frames 2400 ... 12000, `logs/net/n*b/contact.png`, host row over joiner row):
  the same scene on both at every shot (fight start, rounds, "PAUL WINS", "KAZUYA WINS", the next match's intro and
  fight); about half of the pairs are pixel-identical, the others one presented frame apart (the shot takes the
  presenter's latest picture, which runs asynchronously to the EE).
- **Frame rate**: ~37-38 fps per side in the fights (both sides at the same rate: time sync), ~40 fps over the whole
  run; one instance alone (`nref`, no netplay) runs the same frames at 40.8 fps on this machine -- the VS stages are
  slower than 60 fps in this port without any rollback (phase 2: ~33 fps on Underground). Netplay itself costs the
  snapshot (1.8 ms per frame), the hash (3.8 ms every 30 frames) and the rollbacks.
- **Re-simulation** (`COST` lines): a cut re-simulated frame 6.2-6.5 ms p50, the drawn tail frame 10.5-12.4 ms p50;
  restore 1.7-1.9 ms; a whole rollback (restore + all its frames) 14-22 ms p50, 26-31 ms p90.
- **Sound** (`n50w` + `nrefw`, `TEKKEN4_SOUND_WAV` on each side, 6000 frames): of the 4557 non-silent 20 ms windows of
  the offline reference's WAV, 4538 are bit-identical in the host's WAV at the same position and 4541 in the
  joiner's (shifted by a constant < 100 ms: its WAV writer started later); the ~19 others are the windows around
  mispredicted frames (host 88, joiner 391 one-to-two-frame rollbacks). No doubled audio: each WAV holds one
  frame's samples per live frame (104.8 s for 6000 frames + boot). This PC has no playback device ("Failed to
  initialize playback device" in every run, also phase 2's), so the WAV is the evidence, not listening.
- **Build id / failure paths**: `nbuild` (host given another build id): both sides `build_mismatch` within 0.5 s,
  both games go on offline. `ndesync` (joiner with another srand pin, forced desync): `NETDESYNC` from frame 150 on
  both sides, dumps written, `net_desync_diff.py` names the one differing word: 0x304900 (newlib's rand state,
  `_impure_ptr` + 88) 1 vs 2.
- The first pairs (`n0`, `n50`, `n150`, before the EcoQoS opt-out, section 3) were also 0 desyncs (399 hashes each,
  equal to `nref`), but the background host ran its fight frames at 27 ms against the joiner's 19 ms: the joiner
  took 2213-2730 rollbacks against the host's 5-376 and gave up 350-390 frames' worth of time-sync corrections.
- `iopsnet` (one process, section 1): sound on, 3115 rollbacks, 0 of 13 453 frames differ from offline.

## 1. Sound on: the IOP is part of the rollback state

Phase 2 kept the IOP (R3000, IOP RAM, zsiopdrv, SPU2) outside the state and froze it in re-simulated frames,
replaying what it had done to the EE. Across two peers that cannot work: the IOP of the peer whose live frames ran on
a predicted input heard that timeline's sound commands, its replies (RPC 0x100 reply page 0x1cca000) and therefore
the EE's sound-library path (+8 EE cycles, which reach timer 0 and the srand seed at the next scene start) differ from
the other peer's (`vssnet` in phase 2). Of the fixes the plan listed, the one that removes the cause is to roll the
IOP back with the EE:

- `IopSubsystem::saveState/loadState` (patch 41) copy the emulated IOP by value at the frame boundary (the IOP never
  runs there: it is advanced from the EE thread's `accountCycles` and synchronous RPCs only): IOP RAM 2 MB, the
  kernel (threads with their CPU states, semaphores, event flags, ready/delay queues relinked by thread id), SPU2
  (sample RAM 2 MB, 48 voices, reverb, input streams, IRQ, its clock), timers, interrupt handlers, cdvd/ioman
  positions, RPC servers, the EE->IOP SIF command queue, SIF software registers, the EE-cycle carry. Host resources
  (disc image handle, ISO index, the host audio queue) stay. The EE side of IOP->EE traffic (SIF command
  invocations, guest heap) was already in the EE snapshot.
- A re-simulated frame runs the IOP like a live one (`TEKKEN4_RB_IOPSTATE=1`, default in netplay: no IOP cut, no
  gate); `SoundEngine::setOutputMuted` keeps its SPU2 samples from the speakers -- they were heard as the live frame's.
  So the IOP only ever keeps the timeline that sticks; what a player hears is the live timeline (a sound only the
  corrected timeline has starts late by the rollback depth or is cut, a mispredicted one is cut at the rollback),
  never a doubled sound (each live frame's samples reach the device once).
- Cost: the snapshot grows by ~6 MB; capture 1.4-1.8 ms per frame (was 1.2), restore 1.5-2.0 ms.

Evidence (sound on everywhere):
- `iopsnet` (selfnet, the phase-2 `vssnet` setup: pad 2 remote, delay 4 + jitter 0..2, both pads fuzzed, Kazuya vs
  Paul and the following matches) against `nref` (measure, same inputs on time): **0 differing frames of 13 453**
  confirmed frames (`rb_compare.py --last`: full hash incl. the sound page 0x1cca000 and the EE cycle; the 3 last
  frames of the run were still unrevealed predictions), 3115 rollbacks, 15 152 re-simulated frames. Phase 2's
  `vssnet` differed in every frame from 2665 on.
- Every netplay pair below: host, joiner and the single-process reference `nref` have the same final-state hash
  (RDRAM + scratchpad + VU0, the **IOP** (RAM, SPU2 RAM, threads), the **EE cycle**) at every 30th frame.

## 2. Protocol (`runtime/tekken4_net.cpp`, "T4NP" v1)

T5DR's wire design (its `netplay_core.cpp`), trimmed to what a two-pad PS2 game needs:

| packet | content |
|---|---|
| header (all) | magic "T4NP", type, version (1), delay, slot, session id, sender nonce (per process) |
| HELLO | build id (u64), session seed, flags (bits 8-15 the sender's input-delay setting, 0xFF auto). Joiner sends every 100 ms until it hears the host; the host answers, the joiner adopts session id + seed, its echo completes the host's side. Different build id: REJECT(build) both ways, `build_mismatch`. Other protocol version: refused the same way |
| INPUT | ack (peer inputs known below), first frame, count, the sender's inputs from the peer's ack (at least the last 8, max 64) = redundancy against loss; the latest 8 final state hashes; the sender's frame-advantage estimate; the host's input-delay pick |
| PING | the sender's clock, the echo of the last PING it received and how long it held it (round trip = now - echo - hold, median of 32), the host's input-delay pick; every 50 ms for the first 3 s after the handshake, then every 200 ms while nothing else goes out |
| BYE | leaving (x3 at exit); REJECT: other build / other session |

Optional `TEKKEN4_NET_KEY`: SipHash-2-4 tag on every packet. The peer is lost after `TEKKEN4_NET_TIMEOUT` s
(20) of silence; unacknowledged inputs are resent every 15 ms. Pad payload: 16-bit buttons + 4 axes (quantized to
3 levels, so stick noise is no new input).

**Build id** (`tools/t4_buildid.py`, run by `net_build.cmd`, written to `out\net\ps2xRuntime\t4net_build.txt`):
`sha1("t4dr-build:<SLUS_203.28 sha1>:<code_id>:<net version>")[:16]`, code_id = SHA-1 over the PS2Recomp tree's id
(not the commit, which differs per PC) and uncommitted diff, `patches/*.patch`, `config/*.toml|*.csv`, the staged game
modules (`*_overrides.cpp`, `tekken4_net*`; line endings normalised) and the toolchain of the CMake build (compiler id and
exact version, build type, flags, PS2X_* options, native VU1 or interpreter; no paths). The games take it from `TEKKEN4_NET_BUILD` (the scripts set it from the stamp) or
`t4net_build.txt` in the run dir; unset = no check (tests only).

**Session seed**: the host's (`TEKKEN4_NET_SEED`, else its session id) is mixed into the game's srand
(`seed ^ session seed`) unless `TEKKEN4_RAND_SEED` pins srand (the tests do, to compare with a reference run).

## 3. The loop (`Mode::Net` in `runtime/tekken4_rollback_overrides.cpp`)

Both peers boot the game from cold (empty memory card per run dir) and the netplay loop runs from the first frame
boundary; menus, character select (each player with his own pad: host = pad 1, joiner = pad 2), fights, KO, replay,
results and the next match are all frames like any other. This works because the port is cycle-deterministic from
boot (phase 0/1) and the IOP is now in the state.

- **Frame 1**: handshake (blocks), the host collects 16 round-trip samples and picks the input delay: its own
  `TEKKEN4_NET_DELAY`, or auto as T5DR = **1 frame up to 60 ms, 2 above, 3 above 150, 4 above 250**; the joiner waits
  for the pick. Frames below 1 + delay are neutral on both sides.
- **Per live boundary f**: snapshot (EE + IOP, ring of maxpred + 3); this side's input for f + delay sampled (script
  and/or device) and sent at once; the peer's inputs that arrived are compared with the predictions the frames ran
  with (prediction = the last confirmed input repeats). First wrong frame g -> restore g, re-simulate g..f-1 with the
  cuts (draw, present, VU1; the last frame drawn), SPU2 muted, each re-simulated boundary re-snapshotted; then frame
  f runs live. More than `TEKKEN4_NET_MAXPRED` (8) frames unconfirmed -> wait.
- **Lockstep until `TEKKEN4_NET_RBSTART`** (600): boot and the intro movie (MPEG/IPU never rolled back) wait for
  every input.
- **Time sync** (T5 §28): each packet carries the sender's lead (f minus the peer's frame implied by its latest
  input); per 20-sample window the trimmed mean of (mine - theirs) / 2; ahead by >= 1 frame -> give up 1 frame (up to
  4 from 2.5): sleep that long and shift the host schedule, then hold the estimate for frames + round trip.
- **Pacing**: the vblank host deadlines are absolute; after a wait for the peer the schedule is shifted by the wait,
  after a rollback the restored deadlines are moved back to the live schedule, and the schedule never lags more than
  50 ms (no catch-up bursts after a slow stretch).
- **Desync check**: every `TEKKEN4_NET_HASH_EVERY` (30) frames, once that frame is final (every input before it
  confirmed, no rollback pending), the hash of its snapshot (RDRAM 32 MB + scratchpad + VU0, IOP, EE cycle; ~3.8 ms)
  goes into the next packets; the transport compares. Mismatch: `NETDESYNC` line, and with `TEKKEN4_NET_DESYNC_DUMP=1`
  both sides write `net_desync_f<frame>.bin` (`docs/rollback/net_desync_diff.py` diffs them).
- **Windows power throttling**: a game whose window is not in the foreground runs with EcoQoS on Windows 11 (the
  efficiency cores of this 32-thread CPU): in the first pairs (`n0/n50/n150`) the background host's fight frames
  took 27 ms against the joiner's 19 ms, so the joiner was always ahead (time sync gave up 350-390 corrections) and
  took 90 % of the rollbacks. The transport now opts the process out (`SetProcessInformation(ProcessPowerThrottling)`)
  and asks for 1 ms timers.

Logs per run dir: `rb_frames.log` (one line per boundary, `p=L` lockstep / `N` live / `R` re-simulated, `in/in2` the
pads the frame ran with; `NETHASH`, `NETTS` (time sync), `NETSUMMARY` every 600 live frames, `NETDESYNC`, `NETEND`),
`net.log` (transport: handshake, delay pick, peer lost).

## 4. Reproduce

Build (stages generated code, the HEAD versions of the shared overrides, the working rollback/netplay driver and
`runtime/tekken4_net*`; builds `<TEKKEN4_SRC>\out\<TEKKEN4_BUILD_DIR>`; writes `ps2xRuntime\t4net_build.txt` there):
```
docs\rollback\net_build.cmd
```
The project root is resolved from the script location, independent of the current directory. Defaults:
the sibling `..\tekken4-fork-net` worktree and build directory `net` (still `D:\tekken4-fork-net\out\net`
when this project is at `D:\tekken4-us`). To override them in cmd.exe before calling the script:
```
set "TEKKEN4_SRC=C:\work\tekken4-fork-net"
set "TEKKEN4_BUILD_DIR=net"
docs\rollback\net_build.cmd
```
Paths with spaces are supported. The same source and build directory are used for staging, building and the build id stamp.

Pairs (PowerShell; `net_pair.ps1` holds `logs\run.lock` for both games, closes them when both logged `NETEND`):
```
$v = 'TEKKEN4_RAND_SEED=1;TEKKEN4_RB_INPUT=500:Start,800:Start,960:Down,1020:Down,1080:Cross,1320:Cross,1560:Cross,1800:Cross;TEKKEN4_RB_INPUT2=1320:Cross,1560:Cross,1800:Cross;TEKKEN4_RB_FUZZ=2400;TEKKEN4_RB_FUZZ2=2400;TEKKEN4_SOUND=1;TEKKEN4_NET_LOCALPAD=0;TEKKEN4_NET_DESYNC_DUMP=1'
$shots = '2400,3000,4500,6000,7500,9000,10500,12000'
powershell -ExecutionPolicy Bypass -File tools\net_pair.ps1 -Name n150b -Rtt 150 -Jitter 5 -Loss 3 -End 12000 -Env $v -Shots $shots
# the offline reference (same inputs on time, NETHASH every 30 frames):
#   TEKKEN4_SRC=D:\tekken4-fork-net TEKKEN4_BUILD_DIR=net TEKKEN4_RB_MODE=measure TEKKEN4_RB_PAD2=1 TEKKEN4_RB_IOPSTATE=1
#   TEKKEN4_NET_HASH_EVERY=30 + $v, then tools\run_capture.ps1 -RunDir logs\net\nref -Shots 60,120,180,240,300,360
python -I docs\rollback\net_compare.py logs\net\n150b\host\rb_frames.log logs\net\n150b\join\rb_frames.log --ref logs\net\nref\rb_frames.log
python -I docs\rollback\net_contact.py logs\net\n150b
Select-String logs\net\n150b\*\rb_frames.log -Pattern 'NETSUMMARY final'
```
The script was the phase-2 one: in netplay the host plays `TEKKEN4_RB_INPUT/FUZZ`, the joiner `TEKKEN4_RB_INPUT2/FUZZ2`,
each at the frame the input takes effect in (independent of the delay), so the run equals the offline reference.

## 5. Playing by hand (two people)

Build first (`docs\rollback\net_build.cmd`). Each player starts one game; both must run the same build (the
script passes the build id of `out\net\ps2xRuntime\t4net_build.txt`; another build is refused at the handshake).

Two PCs (host's UDP port reachable, e.g. LAN; allow `ps2EntryRunner.exe` in the Windows firewall when asked):
```
# PC 1 (host, Player 1), from D:\tekken4-us:
powershell -ExecutionPolicy Bypass -File tools\net_play.ps1 -Host -Port 7400
# PC 2 (join, Player 2), the host's address:
powershell -ExecutionPolicy Bypass -File tools\net_play.ps1 -Join 192.168.1.20 -Port 7400
```
One PC, two players (keyboard for P1, the first gamepad for P2; the keyboard only reaches the focused window, a
gamepad works without focus):
```
powershell -ExecutionPolicy Bypass -File tools\net_play.ps1 -Host -Port 7400 -Pad -1
powershell -ExecutionPolicy Bypass -File tools\net_play.ps1 -Join 127.0.0.1 -Port 7400 -Pad 1
```
Options: `-Delay auto|0..4` (the host's decides), `-Sound 0`, `-Sim "lat=75,jitter=5,loss=3"` (try a far
opponent on one PC: give both sides half the round trip), `-RunDir`. The same by hand, without the script:
```
$env:TEKKEN4_NET='host:7400'          # joiner: $env:TEKKEN4_NET='join:192.168.1.20:7400'
$env:TEKKEN4_SOUND='1'; $env:TEKKEN4_NET_PAD='0'
$env:TEKKEN4_NET_BUILD=(Get-Content D:\tekken4-fork-net\out\net\ps2xRuntime\t4net_build.txt).Split(' ')[0]
mkdir D:\t4play\host; cd D:\t4play\host     # its own run dir = its own memory card
& D:\tekken4-fork-net\out\net\ps2xRuntime\ps2EntryRunner.exe D:\tekken4-us\game\disc\SLUS_203.28
```
Both games boot in step (the first 600 frames in lockstep: logo, intro movie), then play with rollback: Player 1
picks VS BATTLE in the main menu, each player picks his character with his own controls (keyboard WASD + Z/X/C/V =
Square/Cross/Circle/Triangle, Enter = Start; or the gamepad). START pauses for both (it is just an input). The
session's state is in each run dir's `rb_frames.log` (`NETSUMMARY` every 600 frames: fps, rollbacks, round trip,
delay, hashes compared, mismatches) and `net.log` (handshake, delay pick, peer lost).

## 6. What is left (phase 4 and later)

- **Lobby integration with the T5DR server**: the launcher/match driver passes `TEKKEN4_NET` (host/join + the
  punched or relayed address), `TEKKEN4_NET_KEY` (match secret: SipHash tags are implemented), `TEKKEN4_NET_SEED`,
  `TEKKEN4_NET_BUILD` (`tools/t4_buildid.py` = T5DR's `buildid.py` scheme with "t4dr-build") and the delay
  (ranked / far-match rules as T5DR's `T5L_PING_DELAYS`). Missing on the game side: a result file (winner, final
  hash of the deciding frame, fps, lost reason) like T5DR's, a NAT-rebinding test through a relay (the transport
  follows a peer whose packets come from a new address), lobby-driven sessions without a reboot per opponent.
- **Direct fight** (T5DR's way: skip the menus to a chosen stage and characters, rollback from the fight on) instead
  of booting both games in step through the menus: needs the game's mode/character/stage variables found and set.
  Then also T5DR's match rules (no pause online, KO/result actions only on confirmed frames).
- **Online save**: each run dir starts with an empty memory card; a player's own card changes the boot path, so
  lobby matches need the fixed online save of the plan (unlocks).
- **Speed**: the VS stages run 37-41 fps on this machine (one or two instances); 60 fps needs the live frame
  cheaper (GS back-pressure, VU1: the perf work in `D:\tekken4-fork-perf`). On the rollback side: undo-log
  snapshots instead of the 38 MB copy per frame (1.8 ms), a cheaper desync hash (3.8 ms every 30 frames),
  T5DR's early rollback (re-simulate in the vsync wait), the joiner still takes ~1.4-1.8x the host's rollbacks.
- **Sound polish**: sounds of the corrected timeline that start inside re-simulated frames are heard late/cut (the
  usual GGPO behaviour, ~0.4 % of the 20 ms windows in `n50w`); T5DR's dedupe of re-simulated starts would need
  zsiopdrv's command queue decoded.
- Not tested: two real PCs / a real WAN, more than ~12 000 frames per session (several matches + rematch menus are in;
  hours are not), human play.

## What changed

PS2Recomp worktree `D:\tekken4-fork-net`, branch `t4-net` (on top of t4-us = patches 01-40):

| commit | patch | content |
|---|---|---|
| `090a662` | `41-*` | the IOP in the rollback snapshot (CPU, kernel, IOP RAM, SPU2, timers, SIF/RPC bookkeeping), SPU2 output muted in re-simulated frames |
| `79de57a` | `42-*` | `EeScheduler::shiftHostDeadlines` / `nextVblankHostDeadline` (pacing), `ps2_stubs::sampleHostPad` (this PC's controls), runner `*_net*.cpp` outside unity/PCH + ws2_32 |

Exported as `docs/rollback/patches/41..42-*.patch` (format-patch against t4-us); move them to `patches/` to make them
part of the normal build.

This repo (not committed by me):
- `runtime/tekken4_net.h`, `runtime/tekken4_net.cpp` (new): the UDP transport (game-agnostic).
- `runtime/tekken4_rollback_overrides.cpp`: `Mode::Net` (the GGPO loop), `TEKKEN4_RB_IOPSTATE`, `TEKKEN4_RB_FRAMEHASH`,
  NETHASH lines (also in measure mode), session seed in srand. Header lists every switch.
  The netplay code is guarded by `__has_include("tekken4_net.h") && PS2X_ROLLBACK_IOP_STATE`: the file still builds in
  trees without patches 41/42 (stage_generated copies it everywhere), netplay is then simply absent.
- `docs/rollback/net_build.cmd` (build the sibling `tekken4-fork-net\out\net` by default + build id stamp), `tools/net_pair.ps1` (two
  instances, network simulator, run lock), `tools/t4_buildid.py`, `docs/rollback/net_compare.py`,
  `docs/rollback/net_desync_diff.py`, `docs/rollback/net_contact.py`, `tools/net_play.ps1` (one game by hand).
