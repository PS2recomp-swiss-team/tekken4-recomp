# Rollback phases 0 and 1: measurements, save/restore, self-test

Status 2026-10-29: phase 0 (measure) and phase 1 (save/restore + offline self-test) are done for the
SOUND-OFF configuration (`TEKKEN4_SOUND` unset or `0`). With `TEKKEN4_SOUND=1` the sound RPC reply page differs
in re-simulated frames (expected, see "Sound"). Plan: `docs/ROLLBACK_PLAN.md`. Sister project: T5DR Online
`docs/ROLLBACK.md` ("T5 §n").

## Where the code is

- PS2Recomp fork worktree `D:\tekken4-fork-rb`, branch `t4-rollback` (from `t4-us` = eb8688b + patches 01-32),
  commit `0dc98d9` "Rollback hooks" (958 lines). Not yet turned into `patches/33-*.patch` (see "Next steps").
  - `EeScheduler`: `setBoundaryHook` (called at the top of the dispatcher loop: on every VBlankStart, and on every
    wake of the main thread), `SavedState` + `saveState/loadState` (threads with contexts and invocations, ready
    queues, semaphores, event flags, alarms, IRQ handlers, id counters, cycle counters, events, deadlines, pending
    invocations, vsync state, invocation stacks), `appendStateDigest` (deterministic bytes for the hash),
    `hostWaitNanoseconds`. With a hook installed (only then) cycle-due events fire in EE-cycle order and the
    timer-vs-vblank idle wait compares cycles, not host times: host pacing can then never reorder guest events.
  - `PS2Memory::saveDeviceState/loadDeviceState` (`PS2DeviceState`): I/O register map, GS privileged registers
    (CSR, vsync tick), VIF0/VIF1, DMA x10, PATH2 cut state, VIF1 carry, masked PATH3 FIFO, pending GIF/VIF
    transfers, completed DMAC causes, EE timers + batching debt, MFIFO state.
  - `ps2_rollback.{h,cpp}`: `capture/restore` (RDRAM 32 MB, scratchpad, VU0/VU1 code+data, scheduler, devices,
    VU0/VU1 interpreter objects, R5900 main context copy, guest heap bookkeeping, async callback stacks, pad
    ports), `hashState` (per-4-KB-page RDRAM hash with masks, 32 x 1-MB region digests, scratchpad + VU + scheduler
    digest + device registers).
  - Pad stub: `setPadInputProvider` (frame-exact input for every port), `savePadState/loadPadState`;
    `scePadGetFrameCount`'s counter moved from a function static into that state.
- `runtime/tekken4_rollback_overrides.cpp` (this repo, new): the driver. Returns at once unless
  `TEKKEN4_RB_MODE` is set (normal play installs no hook; checked: `logs/rb/plain`, key path, fight at 60 fps,
  "perf second 61..68: 60 frames").
- `docs/rollback/rb_compare.py`: frame-by-frame diff of two `rb_frames.log`.

Environment of the driver (all in the file header): `TEKKEN4_RB_MODE=measure|test`, `TEKKEN4_RB_INPUT`
(scripted pad 1 per logical frame), `TEKKEN4_RB_FUZZ` (pseudo-random fight input as a function of the frame),
`TEKKEN4_RB_TEST=start=,every=,depth=,words=,mispredict=`, `TEKKEN4_RB_BOUNDARY`, `TEKKEN4_RB_MASK`,
`TEKKEN4_RB_DUMP`, `TEKKEN4_RB_PAGES`. Output: `rb_frames.log` in the run dir, one line per boundary
(`f` logical frame, `tick`, `cyc` EE cycle, `h/ram/oth/sch` hashes, `in` pad 1, `ee/gs/wall/hk` ms, `dirty` pages,
`p` pass: `-` normal, `1` first pass, `W` wrong-input pass, `R` re-simulation, `loop` main-loop passes, `reg`).

## Phase 0 answers

1. **What the main loop waits on; the boundary.** Thread 1 blocks in the scheduler only during boot and the intro
   movie (62 wakes in total, all `VSync`, the movie runs at 30 fps). From the main menu on it never blocks:
   at every boundary of `logs/rb/m2` after the movie `run=1` (thread 1 is the running thread) and the wake counter
   stays at 62. The main loop body `FUN_00196940` (loop at `FUN_001969f8`) is paced by the vblank interrupt, so
   the frame boundary is **the first dispatcher checkpoint after a VBlankStart** (`EeBoundaryInfo::vblank`). There
   the host stack is empty (the running thread stopped at a generated-code checkpoint, its resume pc is in its
   context), every guest-visible thing is plain data, and the point is a fixed EE cycle (the first checkpoint
   with `m_eeCycle >= deadline`). Save AND restore are done there.
2. **Logic steps per vsync.** Exactly one main-loop pass (per-frame sound RPC 0x100) per vblank: `loop=1` on
   3240 of 3393 boundaries of `m2`; `loop=0` only in the first 15 boot frames and on every other vblank of the
   30-fps movie. In fights always 1, also when a frame takes longer than 16.7 ms of host time: vblanks are
   EE-cycle events, so the game runs slower in real time instead of skipping. **Logical frame = vsync tick.**
3. **Dirty pages per frame** (fight, page hash differs from the previous boundary, `final`): avg 179, p50 185,
   p90 192, max 211 pages of 4 KB (~0.75 MB; T5DR: 700-880).
4. **EE cost per frame** (fight, sound off, `perf`: 804 frames): EE thread 19.7 ms of which GS packet processing
   on the EE thread 7.2 ms, **EE-only 12.5 ms** (p50 12.7, p90 13.3, p99 13.9) - this still includes VU1 (native),
   VIF/DMA and the IOP interpreter advanced from `accountCycles`. A re-simulated frame in phase 1 costs the same as
   a live one (`final`: wall 20.8 ms for `-`, 20.8 `R`, 20.9 `W`; host pacing is skipped automatically because the
   restored deadlines are in the past). Hash 3.3 ms per frame (32 MB), full save 1.23 ms avg (max 4.1),
   restore 1.23 ms avg (max 2.2).
5. **Host threads writing RDRAM.** No write-fault trace was built. Evidence instead: run `nB` with the software GS
   (`PS2X_GS_BACKEND=cpu`, multi-threaded raster, 3578 frames in 100 s) against `nA` with the GL GS (6410 frames
   in 100 s), unseeded: **0 of 3578 frames differ** (full hash: RDRAM, scratchpad, VU, scheduler, devices).
   Any timing-dependent host write into guest state would show there.
6. **Baseline double run.** `dA`/`dB` (seed 1, same script, 3610 frames boot -> menus -> Story fight with fuzz
   input): RDRAM, EE cycle, vsync tick and input identical at every frame; the only difference was the scheduler
   digest, which hashed the padding bytes of a `std::pair` (fixed before the commit). `nA`/`nB` above after the
   fix: 0 differing frames. **No masked words were needed with sound off; the built-in mask list is empty.**
7. **srand.** Called from `FUN_0020e090` (return 0x20e0cc) at each scene start (frames 137, 1836, 2045, 2194,
   4187, ...). Seed = products/sums of `FUN_00197c90()` twice and the EE timer 0 count (0x10000000) read twice.
   Timer 0 advances from EE cycles, so the seed is deterministic in this runtime (same in `nA`/`nB` without
   `TEKKEN4_RAND_SEED`). No wall clock reaches guest state on the boot -> fight path: runs made minutes apart are
   identical. (Each run dir starts with an empty memory card; a player's own card changes the boot path, so
   net play needs the fixed online save of the plan.)
8. **EE threads in a fight:** one. `THREAD f=3000 id=1 status=Running pc=0x0022a150` is the only thread record
   (`final`, `TEKKEN4_RB_DUMP=3000`); interrupt handlers run as invocations on it.
9. **GS readback in a fight:** not examined (phase 2: the hash would show it once the GS submit is cut).
10. **RPC 0x100 queue layout:** not decoded (phase 2/5, sound).

## Phase 1: save/restore self-test

Method (T5 `T5_RB_MODE=test`, made stricter): from frame 2100 (fight start) every 30 frames save the machine,
run K frames (K = 1..8 in turn) and record each boundary's full hash; restore; check the restored hash equals the
saved frame's hash; with `mispredict=1` run the same K frames again with WRONG pad 1 input (what a misprediction
does), restore again and check again; then run the K frames with the true input and compare every boundary with
the first pass.

Result `logs/rb/final` (sound off, seed 1, GL GS, 200 s wall, logical frames 1..8943: fight 1 vs Yoshimitsu
frames ~2000-6100 = 68 s of fight incl. round ends, KO and replay, then the next Story stage load and fight 2 vs
Lei): **447 rollbacks (depth 1-8, every 30 frames), restored state OK 447/447, 1000 re-simulated frames compared,
0 mismatches**; the wrong-input pass diverged from the first pass in 222 of 224 cycles (the 2 others fall in
frames that ignore input), so the hash does see input. Frame shots during rollbacks are correct (`final`
frame_180s: Kazuya vs Lei KO replay; `t2` frame_100s: round 2 HUD). Earlier runs: `t1` (44 rollbacks, 0
mismatches), `t2` (386 rollbacks, 865 frames, 0 mismatches).

## Sound (TEKKEN4_SOUND=1): kept outside the state, as T5DR does

Decision for phase 1: the IOP (R3000, IOP RAM, zsiopdrv, SPU2/SoundEngine) is NOT in the snapshot; it keeps
running through re-simulated frames. Evidence of what that costs (`snd`, `snd2`, same test with sound on):
restores still 100 % OK (202/202, 61/61), but 64 of 447 and 16 of 267 re-simulated frames mismatch, every time in
**one page, 0x1cca000** (91 of 91 page reports in `snd`): the sound library's reply/state block. Words
(`snd2`, `words=1`): 0x1cca004 and 0x1cca008 (reply words 1-2 of RPC 0x100, the reply buffer is 0x1cca000,
8 words) most often, then 0x1cca6c4/70c/778/788/78c/844/8b8. Once (`snd2` frames 4082-4083) the difference
reached game memory outside that page: word 0x357f98 (first pass 0x00873806, re-sim 0x0087197c). So the reply
bytes do feed back, as in T5 §20 ("skipping is not enough"): phase 2 must log the reply of each frame's RPC 0x100
(and other sound calls) on the first pass and replay it in re-simulation (plan M12 option A), or roll the IOP back
(option B). Masking 0x1cca000 would only hide it.

## Remaining non-determinism / not covered

- Sound on: above. Sound off: none found (0 differing frames across GL/CPU GS, seeded/unseeded, minutes apart).
- Not tested yet: 2-player VS (pad 2 is reported "not connected" by the provider), other stages/modes, a
  memory card with a save, MPEG/IPU movies inside a rollback window, different CPU vendors / builds (MXCSR, FMA).
- GS state (VRAM, frontend registers) is not rolled back: re-simulated frames draw again (GS is a sink; the RDRAM
  hash matching shows no feedback in these runs). Phase 2 cuts the GS submit in re-simulation.
- `m_debugPublishCountdown`, debug snapshots, host override counters (`tekken4::g_frames`, movie state) are
  outside the state on purpose (not guest-visible).

## Reproduce

Build (stages generated code, the COMMITTED `runtime/*_overrides.cpp` of HEAD plus the new rollback override):
```
set TEKKEN4_SRC=D:\tekken4-fork-rb
set TEKKEN4_BUILD_DIR=rb
call tools\stage_generated.cmd
rem or in one step: docs\rollback\rb_build.cmd (stages the HEAD versions of the shared overrides because another
rem agent had uncommitted edits in runtime\tekken4_overrides.cpp that did not build against t4-us); runs: docs\rollback\rb_run.ps1
call tools\build_runtime.cmd
```
Run (PowerShell; `tools\run_capture.ps1` honours TEKKEN4_SRC / TEKKEN4_BUILD_DIR and the run lock):
```
$env:TEKKEN4_SRC='D:\tekken4-fork-rb'; $env:TEKKEN4_BUILD_DIR='rb'; $env:TEKKEN4_SOUND='0'
$env:TEKKEN4_RAND_SEED='1'
$env:TEKKEN4_RB_INPUT='500:Start,800:Start,1040:Start,1280:Cross,1580:Start'   # Story Battle, Kazuya
$env:TEKKEN4_RB_FUZZ='2100'
# phase 0 measure / determinism (run twice, then compare):
$env:TEKKEN4_RB_MODE='measure'
powershell -File tools\run_capture.ps1 -RunDir logs\rb\dA -Shots 34,50,70
python -I docs\rollback\rb_compare.py logs\rb\dA\rb_frames.log logs\rb\dB\rb_frames.log
# phase 1 self-test:
$env:TEKKEN4_RB_MODE='test'; $env:TEKKEN4_RB_TEST='start=2100,every=30,depth=8,mispredict=1'
powershell -File tools\run_capture.ps1 -RunDir logs\rb\final -Shots 60,100,140,180,200
Select-String logs\rb\final\rb_frames.log -Pattern 'SUMMARY|MISMATCH' | Select-Object -Last 3
```
Frame numbers are logical frames (= vsync ticks since boot) and are the same on every machine, unlike the
seconds of `-Keys`. The fight starts at about frame 2000.

## Next steps (phase 2)

Done 2026-10-29: see `docs/ROLLBACK_PHASE2.md` (cuts, IOP gate with sound replay, idle loop, selfnet harness;
the rollback commits are exported as `docs/rollback/patches/37..40`, since 33-36 are now the music patches).

1. Turn `0dc98d9` into `patches/33-ps2xRuntime-rollback-hooks.patch` (`git -C D:\tekken4-fork-rb format-patch
   -1 0dc98d9`) and commit `runtime/tekken4_rollback_overrides.cpp` + this doc.
2. Virtual-time re-simulation is already implicit (restored host deadlines are in the past, so resim frames run
   unpaced); add an explicit `resimulating` flag: freeze the IOP (`advanceIopEeCycles` skipped, plan M5b) and drop
   the GS draw (the GIF process callback that `tekken4_rollback_overrides.cpp` already wraps for timing is the cut
   point; keep texture uploads). Target: resim frame < 3 ms vs 12.5 ms EE-only today; profile what is left of the
   12.5 ms (VU1, VIF, IOP) with TEKKEN4_PROFILE.
3. Sound: log/replay RPC 0x100 replies (0x1cca000, 8 words) and other sound calls per frame; re-run `snd` until 0
   mismatches with `TEKKEN4_SOUND=1`.
4. Cheaper snapshots: the per-frame 32 MB hash (3.3 ms) and full copy (1.2 ms) are fine for tests; for the net
   loop use the write-watch undo log (plan M2: ~180 dirty pages/frame) and a small gameplay hash.
5. Pad 2 through the provider (both ports from the net input), then the T5 loop (phase 3).
