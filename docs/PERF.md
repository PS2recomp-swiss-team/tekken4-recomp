# Performance: every stage at 60 fps (US build SLUS-20328, GL GS backend, native VU1)

Status 2026-10-29. Goal: every fight on every stage at a stable 60 fps with headroom, because rollback re-simulates
frames on top of the live frame (docs/ROLLBACK_PHASE2.md, docs/ROLLBACK_PHASE3.md).

**Result: 9 of 10 stages at a steady 60 fps (were 2 of 10); the worst, Arena, 30 -> 60 fps; Building 49 -> 57.**
The GL thread went from 10-28 ms to 7-11 ms per frame, the game (EE) thread from 13.5-32 ms to 11-17.6 ms. Game
results unchanged: rollback self-test 0 mismatches (sound off and on), live-frame state hashes identical with the
changes on and off. 14 commits on PS2Recomp branch `t4-perf`, exported as `docs/perf/patches/43..56-*.patch` (against
t4-us 239c212 = patches 01-42; checked: t4-us + 43..56 gives exactly the tree of t4-perf).

## 2026-11-04: VU1 + GS on worker threads (patch 89), old PCs (patch 90)

Owner: "keep working on performance", "T4 should run on old PCs", "faster than an emulator on the same PC".
Measured with sound ON (the real Namco driver on the emulated IOP, what players run), fights of a scripted VS
match (both pads fuzzed), `TEKKEN4_RB_MODE=measure` without the frame hash, per frame: EE thread time and its
**processor cycles** (`mcyc`, QueryThreadCycleTime: other programs do not inflate it), VU1 / GS / VIF time.
PC: Ryzen 9 7950X + RTX 3090, shared with other agents' games (30-70 % load): interleaved A/B pairs only.

### What a fight frame cost before (EE thread, sound on)

| part | ms per fight frame (mean) | share |
|---|---|---|
| EE thread total | 13.0-15.2 (p99 18.8-22.6); 1,555 of 5,311 frames over 16.7 ms | 100 % |
| VIF1 processing incl. VU1 microprograms (native blocks + their timing model) | 7.4-8.0, of it VU1 6.0-6.9 | ~55 % |
| GS frontend (GIF packets: PATH1 XGKICK, PATH2, PATH3) | 1.8-2.3 (inside the VIF time for XGKICKs) | |
| sound: IOP interpreter (Namco driver) + SPU2 mixer | ~5 (15.2 with sound vs 10.1 silent HLE) | ~33 % |
| game code (recompiled EE C++), scheduler, timers | the rest, ~3 | |

So the "emulated" parts -- not the recompiled game code -- were the cost: VU1 + GS + IOP/SPU2 ~13 of ~15 ms.

### Patch 89: VU1 and the GS frontend on their own threads (`PS2X_VU1_ASYNC`, default on)

On the PS2 the VU1 and the GS run beside the EE. Here the EE thread ran them inside its own DMA writes. Now the EE
thread records that work in order (VIF1 UNPACKs with the VIF registers they read, MPG uploads, MSCAL/MSCNT with
TOP/ITOP and MXCSR, every GIF packet) and a **VU1 worker** runs it; with 3+ logical processors a **GS frontend
worker** takes the GIF packets (`PS2X_GS_SPLIT=0`: one worker). The EE waits for empty queues before it could
see their results: every VBlankStart (the presenter's latch), GS privileged register reads/writes, EE loads/stores
to VU1 memory, the GS stubs, rollback capture/restore/hash and every change of the rollback cuts. Frames with
rollback cuts and VU runs with D/T stop bits stay synchronous. Design + rules: `ps2xRuntime/include/runtime/ps2_vu1_async.h`.

| fight, all 32 logical processors, interleaved (`v2_all`) | before (`PS2X_VU1_ASYNC=0`) | after |
|---|---|---|
| EE thread ms per frame mean / p99 | 13.0 / 18.8 | **6.3 / 16.0** |
| EE thread Mcycles per frame mean / p99 | 56.2 / 79.1 | **27.1 / 41.1** (-52 %) |
| fight frames with EE work > 16.7 ms | 233 of 3,376 | **25 of 3,385** |
| guest frames > 20 ms (menus -> fight, 45 s) | 10 | **1** |
| repeated frames per minute (picture shown twice) | 26.7 | **1.3** |
| 4c/4t stand-in (mask 0x55): EE Mcycles, frames > 16.7 ms, guest > 20 ms | 53.3, 98, 23 | **27.3, 21, 1** |

The VU1 (6-7 ms) and GS frontend (2-4 ms) now run beside the game code. A 2-core PC (masks 0x5 = 2c/2t, 0xF =
2c/4t) stays CPU-bound: the whole frame is EE ~6 + VU1 ~7 + GS frontend ~4 + GL thread ~8 ms of a fast core,
more than two cores of an old CPU give in 16.7 ms; the remaining levers are the VU1 timing model and the sound
(agents t4vurecomp: VU1 microprograms lifted to native code; t4iop: IOP/SPU2) and the GL thread.

Determinism: `TEKKEN4_RB_MODE=measure` with the **full per-frame state hash** (RDRAM, scratchpad, VU0/VU1 memory
and registers, scheduler, device and GS privileged registers): 6,005 / 6,071 / 6,093 frames identical to the old path
(three builds of the change). Netplay pairs: see "Pairs" below.

### Patch 90 + tools: old PCs

**Hard requirements found in the build (before):**

| | what the build needed | why | now |
|---|---|---|---|
| CPU instruction set | **SSE4.1 + SSSE3** (Core 2 Penryn 2008+, any Core i, AMD Bulldozer 2011+; NOT AMD Phenom II / Athlon II, Core 2 65 nm) | intrinsics in the recompiled code's macros (`_mm_blendv_ps` at 2,494 sites, `_mm_extract_epi32`, `_mm_mullo_epi32`, `_mm_shuffle_epi8`, `_mm_abs_*`) | default build unchanged; **`PS2X_SIMD_BASELINE=ON` = SSE2 only (any x86-64 CPU)**, chosen by BUILD GAME on a CPU without SSSE3/SSE4.1 (`tools/cpu_needs_baseline.ps1`, `TEKKEN4_SIMD_BASELINE=1/0` forces) |
| AVX / AVX2 / FMA / BMI | **none required**: the exe's AVX/AVX2/BMI/POPCNT code is all MSVC runtime-dispatched (STL vector algorithms, auto-vectorized loops behind `__isa_available` checks); the few "AVX" hits inside recompiled functions are jump tables read as code | `/arch:AVX2` exists only in `ReleaseMode.cmake` for CMAKE_BUILD_TYPE=Release, which no T4 build uses (RelWithDebInfo) | checked by disassembling both exes with their PDBs (D:\t4perf\isa_count.py) |
| GPU API | an **OpenGL 4.6** core context was requested; the renderer uses GL 4.3-4.5 functions (glBufferStorage, glClearBufferData, glTextureBarrier; a compute shader only for a frame-hash diagnostic); shaders `#version 430` with GLSL 3.30-level features | | asks 4.6, 4.5, 4.4, then 4.3 (`[gs-gl]` logs the version); minimum now **OpenGL 4.3 + ARB_buffer_storage + texture barrier**: NVIDIA GeForce GTX 400 (2010)+, AMD Radeon HD 5000/6000 with their last drivers (GL 4.4) or HD 7000 (2012)+, Intel HD 4600 (Haswell, 2013, GL 4.3) maybe, Intel HD 2000-4000 (2nd/3rd gen Core iGPU, GL 3.1-4.0) **no** |
| RAM | see "Pairs" (working set of one game) | | |
| cores | 2 run, 4 needed for 60 in fights today (above) | | |

SSE2 baseline cost: EE Mcycles +0.5 % (all LPs) / +5 % (2c/4t), VU1 worker +8-9 % (`blab_*`): small, so it is used
only where it is needed. Same game state: measure-mode full state hash 6,115 of 6,115 frames identical to the
default build; `tools/t4_buildid.py` leaves PS2X_SIMD_BASELINE out of the build id so both meet online (pairs below).

An old-GPU path (OpenGL 3.3 / Direct3D 10, Intel HD 2000-4000): the shaders already use only texelFetch / unsigned
samplers; it would need the GL 3.3 context with `#version 330` + the texture-barrier extension (blending feedback),
plain glBufferData instead of the persistent vertex ring, no glClearBufferData, and the hash diagnostic off --
roughly 2-3 agent-days, but it cannot be tested on this PC (no such GPU; NVIDIA hands out its newest context for
any request), so it is not done.

**Low preset (launcher):** Internal resolution "Low: 480p native, no smoothing (old PCs)" = `TEKKEN4_INTERNAL_RES=native`,
`TEKKEN4_AA=off`, `TEKKEN4_ANISO=1`; picked on the first start of a PC with at most 4 logical processors. (The new
OpenRecomp launcher's T4 adapter should offer the same three variables.)

### Native code vs emulated parts (for the "recomps are slower than emulators" question)

| part | how it runs in T4 today | origin |
|---|---|---|
| EE game code (Namco's MIPS R5900 program) | **statically recompiled to C++** ahead of time (PS2Recomp, built on the player's PC from their ISO), VU0 macro instructions inline | PS2Recomp (ran-j), GPL-3.0 |
| VU1 microprograms | **translated ahead of time to C++ blocks** (tools/vu1/vu1n_gen.py from the game's micro memory), but run inside an exact VU timing model (pipeline/flag rings, resetScheduler per MSCAL); since patch 89 on their own thread | God of War native port (Waffle565), runtime GPL-3.0, generator licence unresolved (docs/THIRD_PARTY.md) |
| VU0 micro mode | interpreter (rare) | same |
| VIF1 / DMA / MFIFO / GIF | emulated device model (HLE-level, no cycle-exact DMA) | PS2Recomp + our patches |
| GS | emulated: frontend (registers, primitives) + OpenGL hardware renderer | GoW port / sotc-port lineage |
| IOP (sound driver, CD, pads, memory card) | **R3000A interpreter** running Namco's IRX + HLE kernel/libraries | PS2Recomp ps2xIOP |
| SPU2 | native mixer at the libsd API level (no register-level SPU2) | GoW port; DSP algorithms described "as in PCSX2 and psx-spx" (comments), no PCSX2 code copied that this tree records |
| BIOS / kernel | HLE syscalls, no BIOS | PS2Recomp |

PCSX2: no PCSX2 source is part of T4 according to docs/THIRD_PARTY.md and the code's comments (some algorithms are
documented as matching PCSX2's behaviour). PCSX2's own Tekken 4 page lists no open issues; its fixed ones were
vertical lines in hardware mode (fixed in PCSX2 1.5.0; the T4 port had the same kind of seam and fixed it itself:
patch 70, docs/GRAPHICS.md) and a freeze when choosing Story/Arcade (not seen here); a 2015 forum report of
invisible fighters in hardware mode belongs to the same vertical-line cause.

Faster than an emulator? The recompiled game code is a small part of a frame (~3 ms). What still costs is emulated
hardware (VU1 timing model, IOP interpreter, GS); patch 89 moves the VU1/GS half off the game's critical path, the
VU1 recompile (t4vurecomp) and the IOP/SPU2 work (t4iop) are the next big items. No PCSX2 run was done here (no
PCSX2/BIOS on this PC by rule), so no side-by-side fps number exists.

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
