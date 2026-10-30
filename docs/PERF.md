# Performance: every stage at 60 fps (US build SLUS-20328, GL GS backend, native VU1)

Status 2026-10-29. Goal: every fight on every stage at a stable 60 fps with headroom, because rollback re-simulates
frames on top of the live frame (docs/ROLLBACK_PHASE2.md, docs/ROLLBACK_PHASE3.md).

**Result: 9 of 10 stages at a steady 60 fps (were 2 of 10); the worst, Arena, 30 -> 60 fps; Building 49 -> 57.**
The GL thread went from 10-28 ms to 7-11 ms per frame, the game (EE) thread from 13.5-32 ms to 11-17.6 ms. Game
results unchanged: rollback self-test 0 mismatches (sound off and on), live-frame state hashes identical with the
changes on and off. 14 commits on PS2Recomp branch `t4-perf`, exported as `docs/perf/patches/43..56-*.patch` (against
t4-us 239c212 = patches 01-42; checked: t4-us + 43..56 gives exactly the tree of t4-perf).

## 2026-10-30: Building to 60, smoothness (patches docs/perf/patches/80-82 against t4-us 702a93a)

**Building 57 -> 60.0 fps (min second 60, two runs), every stage 60.0 fps; fight present p99 16.9-17.2 ms, no frame
repeated or skipped.** PS2Recomp branch `t4-perf80` = t4-us 702a93a + 80-82 (applies cleanly; the measurements below
are from `t4-perf` = the previous t4-us + the same changes + the presenter-on-tick commit 344b8f7, which t4-us's own
"present 2 ms after each guest vblank" presenter supersedes, so it is not exported). Game override (uncommitted, not
a PS2Recomp patch): `runtime/tekken4_perf2_overrides.cpp`.

What it was: the main loop's vsync wait FUN_0022a140 polls 0x1ccafb7 at 0x22a150; the vblank fires by EE cycles, so
the wait burned ~4.0 M of the 4.9 M EE cycles per frame in 32-cycle checkpoints (each advancing EE timers + IOP).
- `runtime/tekken4_perf2_overrides.cpp`: normal play uses the scheduler's idle-loop skip (the one the rollback modes
  use since phase 2) for 0x22a150 (`TEKKEN4_PERF_IDLE=0` off). Building EE 17.6 -> 15.1 ms/frame (`idle0_building` vs
  `idle1_building`, `p3_building1/2`).
- patch 81: the skip caches the thread record (it runs at every checkpoint now; ~1.6% of the game thread); the vblank
  host chain keeps at most `PS2X_VBLANK_CATCHUP` (2) frames of backlog in normal play: after a stage load the game ran
  unpaced (61-80 fps for seconds) until it had caught up the boot-anchored chain.
- patch 82: pacing waits sleep to 1.5 ms before the deadline and yield to it (`PS2X_PACING_SPIN_US`, 0 = old); guest
  frames were 15.7-17.5 ms apart (1 ms timer). The window thread's message wait also wakes on each guest vblank.
- patch 80: `[frames]` line per second (PS2X_PERF_STATS): every present / guest vblank interval, repeated / skipped
  guest frames; `tools/perf_smooth.py` summarises (fight window, or `--from/--to` for boot/menus).

| stage (Practice, Kazuya vs Yoshimitsu, seconds 3..28 of the fight) | fps (min) | EE ms/f | present p50/p95/p99/max ms | repeated/skipped per min | guest frames > 25 ms |
|---|---|---|---|---|---|
| building before (`p3off_building`, all switches off) | 56.5 (55) | 17.1 | 16.7/17.7/18.2/20.3 | 219 / 9 | 0 |
| building (`p3_building1`, `p3_building2`) | 60.0 (60), 60.0 (60) | 15.1, 15.1 | 16.6/16.7/16.9/21.9, -/-/17.1/21.7 | 0 / 0 | 0 |
| laboratory before / after (`p3off_laboratory`, `p3_laboratory_b`) | 60.0 / 60.0 | 11.0 / 9.0 | 16.6/17.7/18.1/19.0 -> 16.6/16.7/17.0/17.7 | 0 / 0 | 0 |
| airport, mall_a, mall_b, shinjuku, beach, laboratory, parking, underground, arena (`p3_*`) | 60.0 each (min 59-60) | 9.0-14.7 | p99 16.9-17.2, max 17.6-25.4 | 0 / 0 | 1 (beach, 25.3 ms, one EE stall mid-fight) |

Boot -> menus -> char select (stats seconds 9..30 of the same runs): guest frames steady (p99 16.9-17.1), no
repeats/skips with the tick present, but presents 12-20 ms apart in 9 of 11 runs (p95 ~20 ms): the window-thread latch
races the guest's buffer swap after vblank. Before (paced clock): p99 19-20 ms and 6-11 repeat+skip pairs per minute.
Uncommitted experiment (`logs/perf/p80/WIP-ee-latch-at-vblank.diff`, PS2X_EE_LATCH): the EE thread latches the picture
at VBlankStart; parking menus present p95 20.4 -> 16.9 ms, p99 22.6 -> 17.6 (`p4_parking` vs `p4_parking_nolatch`);
determinism and other stages not checked, and t4-us's new presenter may make it moot.
Not hitches: no first-use shader compiles (one ubershader built at GS init), no GS drains in fights, no blocking waits
in the IOP/audio path; stage loads run the EE at 100% for ~2 s (33-43 vsyncs/s, a loading screen).

Determinism (`logs/perf/rb/*5`, `logs/perf/p3_results.md`): rollback self-test sound off 232 rollbacks / 514 frames /
**0 mismatches**, sound on 202 / 447 / **0**; measure-mode state hashes switches on vs off **0 of 5945** frames differ,
this build vs the previous perf build 0 of 5945. Measure mode already used the idle skip; measured against iterating
(TEKKEN4_RB_IDLE=0) the skip shifts EE cycles by up to 24 (scheduler/timer state) and RDRAM differs in 7 of 5925
frames (transient): normal play now follows the same timeline as rollback/netplay, not the old 32-cycle interleaving.
Environment: other agents' game instances ran during most runs (contention column "BUSY 1-2").

## Stage sweep

Practice, Kazuya vs CPU Yoshimitsu, each stage, sound on, the fight's seconds 3..28 (`tools\perf_fight.ps1`,
`tools\perf_sweep.ps1`, table by `tools\perf_table.py`). Per frame: fps = game frames per second (TEKKEN4_PERF_LOG);
EE = game-thread busy time (wall minus the scheduler's pacing waits; includes its waits on the GS queue);
GL = GS worker thread busy time (GL calls, texture decodes); back-pressure = EE time blocked on a full GS queue.
Run lock held, no compiler or other game instance during the window (column "contention" in the raw tables; runs
with contention were repeated). Debug panel visible in all runs (run_capture's F1 arrives before the window exists);
counters on (PS2X_PERF_STATS, PS2X_PERF_STATS_VU: ~0.4 ms of EE time per frame).

| stage | before fps (min) | after fps (min) | EE ms/f before -> after | GL ms/f before -> after | GS back-pressure ms/f before -> after | GL batches/f |
|---|---|---|---|---|---|---|
| arena | **30.0** (30) | **60.0** (60) | 31.8 -> 12.6 | 28.2 -> 9.8 | 16.9 -> 0.0 | 1198 -> 1206 |
| airport | 46.8 (46) | 60.0 (58) | 21.4 -> 16.1 | 17.3 -> 10.6 | 2.4 -> 0.0 | 1309 -> 1262 |
| building | 48.9 (48) | 57.0 (56) | 19.8 -> 17.6 | 15.8 -> 10.5 | 0.2 -> 0.0 | 953 -> 985 |
| shinjuku | 53.4 (53) | 60.0 (60) | 18.1 -> 15.2 | 13.8 -> 9.7 | 0.3 -> 0.0 | 1068 -> 1062 |
| mall_a | 53.6 (53) | 60.0 (60) | 18.1 -> 14.7 | 14.2 -> 10.5 | 0.7 -> 0.0 | 1037 -> 1031 |
| mall_b | 54.1 (53) | 60.0 (60) | 17.9 -> 14.4 | 14.7 -> 10.9 | 1.1 -> 0.0 | 1164 -> 1160 |
| beach | 57.2 (56) | 60.0 (60) | 16.9 -> 14.0 | 11.4 -> 7.7 | 0.5 -> 0.0 | 774 -> 723 |
| underground | 57.6 (57) | 60.0 (60) | 16.8 -> 12.7 | 12.4 -> 9.5 | 1.6 -> 0.0 | 750 -> 749 |
| parking | 60.0 (60) | 60.0 (60) | 15.6 -> 11.7 | 12.0 -> 7.6 | 1.7 -> 0.0 | 846 -> 835 |
| laboratory | 60.0 (60) | 60.0 (60) | 13.5 -> 10.9 | 9.9 -> 7.1 | 0.6 -> 0.0 | 727 -> 723 |

Before = `logs/perf/base2_*` (arena: `base3_arena`; base2's arena run had two foreign game instances), exe
`out\perfbase` (t4-us before patches 41/42 + the counters of patch 43; 41/42 are rollback/netplay hooks). After =
`logs/perf/after2_*` (building: `ab10_building`, after patch 55), exe `out\perf` (t4-us + 43..55). At 60 fps the EE
"after" includes the vsync wait loop's own time up to the deadline, so it is an upper bound of the real work.

Headroom after: the GL thread has 6-10 ms per frame left on every stage; the EE thread 0-6 ms (Building is EE-bound:
~17 ms, ~57 fps). Without the VU counters (PS2X_PERF_STATS_VU=0) Building runs 56.7 fps, EE 17.0 ms
(`ab10_building_novu`; the old exe the same way: 49.1 fps, EE 20.4 ms, `base10_building_novu`).

## What changed (and the evidence)

In commit order. A/B with one exe through the env switch where there is one (each switch's "off" is the old path).

| patch | change | switch (old path) | evidence |
|---|---|---|---|
| 43 | per-second counters: `[perf]` line (EE busy, GIF time, GS queue waits/drains, GS worker busy, batches, draws, texture decodes, VU1/VIF1 time); the scheduler's host waits are measured in every mode | `PS2X_PERF_STATS=<s>` turns it on | basis of every table here |
| 44 | FINISH, Flush (presenter latch) and the sceGsSwapDBuff clears are queued instead of waiting for the GS worker | `PS2X_GS_SYNC_DRAIN=1` | EE-side drains 3/frame -> 0; small alone (most waits were the presenter's, see 49) |
| 45 | upload invalidation walks only the valid textures, not the whole cache | - | same textures invalidated |
| 46 | GL state filter (redundant enables, blend, depth, uniforms per program, bindings per unit, texture parameters per texture dropped; deletions forget), batch key without registers the draw does not use, 64 MB persistently mapped vertex ring with fenced quarters | `PS2X_GL_STATE_CACHE=0`, `PS2X_GL_BATCH_KEY=0`, `PS2X_GL_VERTEX_RING=0` | filter: airport GL 16.8 -> 16.0 ms (`ab1_airport_nocache` vs `_nokey`); batch key: no fewer batches (they end on real TEX0/CLAMP/ABE changes) |
| 47 | counter: GS round trips by caller (`drains_by`) | - | showed the presenter reading the picture back every vsync |
| 48 | padding-free batch key (the first version split batches at random); host->local uploads that leave the bytes unchanged keep their textures | `PS2X_GL_UPLOAD_SAME=0` | ~6600 same-byte uploads per 5 s on airport kept their textures |
| 49 | **shared presentation**: the GoW port's zero-copy present was never armed (no CaptureHostContext; the GS context was created before the window), so every vsync the presenter drained the GS queue, glReadPixels'd the picture (a full GPU sync on the GL thread) and uploaded it again. Now the window draws the GS's shared texture; after a latch it waits <= 12 ms for that picture, so it is as recent as before; frame shots read back on demand | `PS2X_GS_DIRECT_PRESENT=0` | arena 30.0 -> 32.1 fps, drains 1.9/frame -> 0 (`ab3_arena_shared` vs `_readback`) |
| 50 | index textures keep up to 8 earlier decodes per VRAM slot by content hash | `PS2X_GL_TEX_VERSIONS=0` | ~250 hits/s on arena; small |
| 51 | TEKKEN4_SOUND_TRACE read once (no static guard per sample block) | - | ~1% of the EE thread |
| 52 | **tall index textures decoded only in the rows the draws sample** | `PS2X_GL_PARTIAL_ROWS=0` | GL profile (arena): GSMem::ReadIndexRun 47% of the GL thread: the game declares T8/T4 textures of 1024x1024 and 128x1024 and samples a small part; every upload into such an area re-decoded the declared size (~41 decodes/frame). Arena 35.3 -> 49.8 fps (`ab5_arena_all` vs `_nopartial`) |
| 53 | partial textures in both axes; REGION_REPEAT range [UFIX, UMSK\|UFIX] whatever the coordinates (most of the Arena's 1024x1024 draws); REPEAT edge-exact | (same) | arena 49.8 -> 60.0 fps, GL 17.0 -> 10.2 ms (`diag9_arena`); `PS2X_GL_DECODE_LOG=1` lists the most-decoded slots and draws that still decode a big texture whole |
| 54 | **no audio drain after an IOP advance that mixed no sample** (it ran after every EE checkpoint, ~100k per frame, locking the output mutex) | - | EE profile: drainOutput + its inlined debug check ~8% of the game thread; airport 53.6 -> 60.0, building 50.2 -> 56.8 (`after1_*` vs `ab8_*`) |
| 55 | VU1 round-toward-zero set through MXCSR instead of fegetround/fesetround per run (~3000 runs/frame) | - | ~2% of the game thread; building 55.9 -> 57.0; state hashes identical to the build before (5940 frames) |
| 56 | the same-bytes upload check of 48 off by default: with partial decodes, hashing every upload twice cost more than it saved | `PS2X_GL_UPLOAD_SAME=1` turns it on | arena, two runs each: GL 9.5-10.2 ms/frame with it, 8.5-8.7 without (`ab11_arena_same*` vs `_nosame*`) |

### A/B of the small switches (arena, all changes, 20 s each)

| run | GL ms/f | EE ms/f |
|---|---|---|
| all on (`ab11_arena_same1`, `_same2`) | 10.2, 9.5 | 13.3, 12.3 |
| PS2X_GL_UPLOAD_SAME=0 (`_nosame1`, `_nosame2`) | 8.5, 8.7 | 12.6, 12.3 |
| PS2X_GL_STATE_CACHE=0 | 10.6 | 13.1 |
| PS2X_GL_VERTEX_RING=0 | 10.4 | 12.4 |

Final build (patch 56) check runs: arena 60.0 fps (GL 9.5, EE 13.3), airport 59.9 (GL 9.9, EE 16.5), building 57.1
(GL 9.7, EE 17.5) (`final_*`); old exe the same day: airport 46.4, building 48.5 (`base_*_shot`). Frame shots of
`final_*` and `base_*_shot` at 62 s show the same picture.

### Profiles

- GL thread, arena before (`prof3_arena_gs`, TEKKEN4_PROFILE + TEKKEN4_PROFILE_THREADS=GSThread): ReadIndexRun 46.6%,
  hashBlocks 5.9%, WriteRun 4.5%, driver ~6%, idle 8%. After patch 52 (`prof6_arena_gs`): ReadIndexRun 33%, idle 22%;
  after 53 the thread is idle ~40% of a frame.
- GL thread, airport before the shared presentation (`prof1_airport`): DrvPresentBuffers + DDIEscape +
  GetDeviceState ~27% (the per-vsync readback stall), ReadIndexRun 16%.
- EE thread (TEKKEN4_STACKPROF; `prof3_airport_ee`, `prof8_building_ee`): flat. Top after the changes (building):
  processVIF1Data 5.0%, VU1 runNative 5.0%, VU1 resetScheduler 3.8%, applyEeTimerTicks 2.7%, VU1 block timing
  (walkHistory/blockTiming) 3.7%, SPU2 IRQ service per IOP advance 2.3%, ps2_vu_mac_apply 2.2%, the vsync wait loop
  2.2%. VU1 including its XGKICK GS work is ~7.8 ms of a Building frame.

## Game results unchanged

- Rollback self-test with the perf build (docs/ROLLBACK_PHASE2.md `p2c` script: TEKKEN4_RB_MODE=test, all cuts,
  mispredict, sound off): **232 rollbacks, 514 re-simulated frames compared, 0 mismatches**, restores 232/232
  (`logs/perf/rb/p2c_perf2`); after patch 55: 202 rollbacks, 447 frames, 0 mismatches (`p2c_perf3`); sound on
  (`s2a` script): 202 rollbacks, 447 frames, **0 mismatches** (`s2a_perf2`).
- Live frames, perf changes on vs all switches off (same exe, TEKKEN4_RB_MODE=measure, full state hash per frame:
  RDRAM, scratchpad, VU memories, scheduler, device registers incl. GS privileged registers): **0 differing frames of
  5399** (`mref_on2` vs `mref_off2`); patch 54 build vs the build before: 0 of 5954; patch 55 vs before: 0 of 5940.
- Picture: frame shots before/after on the arena (`ab3_arena_shared` vs `_readback`, `ab5_arena_all` vs
  `_nopartial`, `diag9_arena/frame_62s`): same scene, cage, crowd, fighters and HUD; the window shows the shared
  texture (window capture `ab3_arena_shared/shot_60s.png`).

## Not done / next

- (done 2026-10-30, see above) Building was EE-bound at ~17 ms (57 fps). The EE time is spread over VU1 (timing simulation per native block, the
  scheduler reset per MSCAL), VIF1 unpack, the IOP/SPU2 advanced per checkpoint and game code. Next candidates: VU1
  `resetScheduler` / block timing, the IOP advanced per 32-cycle checkpoint in the vsync wait loop (batching it changes
  the IOP/EE interleaving: needs care for determinism), SPU2 mixing off the game thread.
- GL batches are still ~1000-1300 per frame (they end on real TEX0/CLAMP/ABE changes); the GL thread has headroom now.
- Direct-colour texture decodes (ReadCT32 ~4% of the GL thread) could use the same partial decode.
- run_capture's F1 (hide the debug panel) arrives before the window exists, so all test runs show the panel.

## Reproduce

```
:: build (worktree D:\tekken4-fork-perf, branch t4-perf; stages generated code + HEAD overrides, applies no patches)
tools\perf_build.cmd
:: one stage (fight from ~50 s; -Env for switches, -Build perfbase for the old exe)
powershell -ExecutionPolicy Bypass -File tools\perf_fight.ps1 -Stage arena -RunDir logs\perf\x_arena -Env PS2X_GL_PARTIAL_ROWS=0
:: all stages + table (logs\perf\<label>_table.md)
powershell -ExecutionPolicy Bypass -File tools\perf_sweep.ps1 -Label after2
python -I tools\perf_table.py logs\perf\after2_arena logs\perf\base3_arena
:: profiles: GL thread / EE thread
...perf_fight.ps1 ... -Env "TEKKEN4_PROFILE=56:15,TEKKEN4_PROFILE_THREADS=GSThread"   or   -Env "TEKKEN4_STACKPROF=56:15"
:: rollback self-test and live-frame comparison with the perf build (tools\perf_rb_run.ps1)
powershell -ExecutionPolicy Bypass -File tools\perf_rb_check.ps1
```
Never pipe these scripts through `Select-Object -First`: the stopped pipe blocks run_capture and the game stays open.
New env switches: PS2X_PERF_STATS, PS2X_PERF_STATS_VU, PS2X_GS_SYNC_DRAIN, PS2X_GL_STATE_CACHE, PS2X_GL_BATCH_KEY,
PS2X_GL_VERTEX_RING, PS2X_GL_UPLOAD_SAME (default off), PS2X_GL_TEX_VERSIONS, PS2X_GL_PARTIAL_ROWS, PS2X_GL_DECODE_LOG
(PS2X_GS_DIRECT_PRESENT existed). To make the patches part of the normal build, move `docs/perf/patches/43..56-*.patch`
to `patches/` (or cherry-pick t4-perf onto t4-us).
