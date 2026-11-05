# Tekken 4 on weak PCs: controlled stand-in study

Status 2026-11-05: **BLOCKED before the T4 gate; measurements not performed.**

**60 fps from ...: not established for any of the four requested CPUs.** No minimum CPU can be named from the evidence below. No FPS, percentile, hitch count or thread budget has been invented from core counts or historical T5DR results. This is a prerequisite audit and measurement plan, not a completed weak-PC benchmark.

## Admission and candidate

The [T4 gate](RELEASE_GATE_0.1.1.md) still says **IN PROGRESS / NO-GO**, snapshot `2026-11-05T01:04:27+01:00`. The owner requested this study after that gate. Normal 60 Hz menus/player-fight and intro acceptance are among its unresolved checks. All three HEAVY slots were occupied at admission; none was removed or borrowed. No game, build, single-thread benchmark or CPU hog was launched by this task.

Inspected candidate: natural build ID `2cc44895ff88b691`, EXE SHA-256 `6baf32534ef4dbc7cae5ce923c5817371366f431ed91263a6602d38057709ee1`. Its CMake configuration is `RelWithDebInfo`, `PS2X_SIMD_BASELINE=OFF`. This identifies the audited artifact, not an accepted release. Preserve separate outputs/hashes for the baseline build rather than overwriting it.

Admission evidence: [preflight result](../logs/weak-pc-t4/preflight/result.json), [frozen gate snapshot](../logs/weak-pc-t4/preflight/gate-snapshot.md), [runtime audit](../build/weak-pc-t4/runtime-audit.md), [method audit](../build/weak-pc-t4/method-audit.md), [profiling audit](../build/weak-pc-t4/profiling-audit.md). Artifacts under `build/` and `logs/` are ignored local evidence. Owner OpenRecomp configuration hashes were unchanged. No live server, external website or account was used.

## CPU profiles and calibration

Native `GetLogicalProcessorInformationEx` confirms this Ryzen 9 7950X has 16 physical cores / 32 logical processors, with sibling pairs 0/1, 2/3, etc. The masks below have the intended shape: [topology evidence](../build/weak-pc-t4/topology.json). They constrain topology only; they do not reproduce old-core speed.

| Target at requested nominal clock | Topology | Verified affinity mask | Required SIMD path | Comparable target benchmark / calibration |
| --- | --- | --- | --- | --- |
| i5-2500, Sandy Bridge, 3.3 GHz | 4c/4t | `0x55` | Default SSE4.1/SSSE3 | Missing / NOT CALIBRATED |
| i3-3240, Ivy Bridge, 3.4 GHz | 2c/4t | `0xF` | Default SSE4.1/SSSE3 | Missing / NOT CALIBRATED |
| Q6600, 2.4 GHz | 4c/4t | `0x55` | Explicit SSE2 baseline; SSSE3 present, SSE4.1 absent | Missing / NOT CALIBRATED |
| E8400, Penryn, 3.0 GHz | 2c/2t | `0x5` | SSE4.1/SSSE3 supported; whole-binary issue below | Missing / NOT CALIBRATED |

**Core 2 compatibility blocker:** the current linked EXE contains unguarded `POPCNT` at virtual address `0x142ae6820`, bytes `f3 48 0f b8 e8`, in `ps2_vu1_async::start+0xe0`. Source `usableProcessors()` calls `__popcnt64` after a successful/nonzero affinity query without a CPU-feature guard. Neither requested Core 2 CPU supports POPCNT. E8400 supporting SSE4.1 does not solve this separate requirement. The SSE2 replacement header does not replace this intrinsic, so merely selecting the baseline option is insufficient proof. This is disassembly evidence, not an observed old-hardware crash: [ISA audit](../build/weak-pc-t4/core2-isa.json). Correct the path and audit each final binary before making Core 2 support claims; do not silently disable async workers for these rows.

For Q6600 force `TEKKEN4_SIMD_BASELINE=1` / `PS2X_SIMD_BASELINE=ON`: the detector on this Ryzen otherwise chooses the default path. Use `RelWithDebInfo`; the project's `Release` mode adds `/arch:AVX2`, unsuitable for every requested target. Audit reachable instructions and dependency dispatch as well as compiler flags.

The local T5DR `docs/WEAK_PC.md`, `docs/RENDER_PERF.md` and `tools/slow_core.py` supply the affinity/hog method. Scoped local searches found no comparable single-thread reference scores for these four CPUs. Player FPS, GHz ratios and a fresh benchmark on the Ryzen cannot supply a missing old-CPU score. No external lookup was made under the local-only instruction.

Post-gate calibration must use the **same single-thread benchmark version, workload, compiler/ISA path and score convention** as a trustworthy target measurement. Record target clock/turbo policy, benchmark hash, reference provenance, host unthrottled score, each busy fraction/period trial, achieved score and repeated spread. Pin benchmark and game at BelowNormal to the selected cores. Search the hog duty using measured throughput, with a declared tolerance (proposed +/-5%), and verify every selected core before and after the scene suite. The Q6600 reference benchmark must run without SSE4.1/POPCNT.

Never copy a duty cycle and call it an i3: historical T5DR evidence has requested busy78 giving 60 fps with a 1 ms hog period versus 41-53 fps with 4 ms. Requested occupancy also differs from measured occupancy. Repeat with another period calibrated to the same score to expose periodic scheduling artifacts; report both if their game results differ. Zen SMT, cache, memory and branch behavior still differ from Sandy/Ivy/Core 2. Results remain **calibrated stand-ins**, with real-hardware validation outstanding.

## Required native/Low configuration and scenes

Explicit settings, matching the T4 launcher Low preset:

```text
TEKKEN4_INTERNAL_RES=native
TEKKEN4_AA=off
TEKKEN4_ANISO=1
TEKKEN4_PROGRESSIVE=1
TEKKEN4_SOUND=1
TEKKEN4_AUDIO_MUTE=1
PS3_AUDIO_MUTE=1
PS3_WINDOW_BACKGROUND=1
TEKKEN4_WIDESCREEN=0
PS2X_SWITCH_WIDESCREEN=0
PS2X_GS_BACKEND=gl
PS2X_GS_DIRECT_PRESENT=1
PS2X_DEBUG_PANEL=0
```

The launcher's native "480p" is the game's **640x448 progressive** output. Keep IOP/SPU2/movie processing active; `TEKKEN4_SOUND=0` removes work and invalidates the comparison. The T4 mute switch zeros final device output after audio work.

Each calibration, build or game needs the coordination lock protocol. Atomically create available `HEAVY.lock` / `HEAVY2.lock` / `HEAVY3.lock` without replacement, record owner/time/purpose and release owned locks in `finally`, including failure. Timing requires **at least two slots**; three exclude all compliant heavy competitors. Reject intervals with other games/builds or competing load. Yield to the gate. Each run gets isolated `OPENRECOMP_HOME`, `APPDATA`, `LOCALAPPDATA`, `TEMP` and `TMP`, background/muted game output, BelowNormal priority and explicit cleanup of its own hogs. Hash-check the owner's config before/after. Keep writable profiles, saves and outputs isolated; verified ELF/ISO inputs may be shared read-only. Networking is unnecessary for this study.

Use ordinary offline execution for final pacing. `build/release-gate/run_native_noinput.py` is a useful starting point but defaults to 1080p, has no calibration/affinity, and cannot hold character select or an ordinary player fight. Legacy `tools/perf_fight.ps1` uses desktop input and wall-time navigation; it is unsuitable unchanged for a throttled background run. Build reviewed background-compatible scene fixtures, verify transitions from captures/logs, and identify title/menu, select and fight independently of assumed seconds. A natural demo is not a player fight.

Sweep all ten stages on the current candidate before choosing the heaviest. Historical **Building** was EE-heavy and **Arena** renderer-heavy; test both, then retain whichever is worse for each stand-in, with fighters/mode/inputs recorded. Use at least 60 s of stable title/menu, select and fight per repeat, excluding separately reported load/warmup periods. Intro has finite duration: capture the entire verified movie, report its measured duration and normalize hitches by that duration. Separate encoded movie-picture cadence from 60 Hz guest/presentation cadence; a film with repeated source pictures is not necessarily dropping game frames.

## Requested results: no accepted measurements

`NM` means **not measured**, not zero or pass. Every row is NOT RUN because the gate/calibration prerequisites are missing. The Core 2 rows additionally have the ISA blocker. The [machine-readable matrix](../logs/weak-pc-t4/preflight/result.json) stores all missing metrics as null.

| Stand-in | Scene | FPS | Frame time median ms | Frame time p99 ms | Frames strictly >20 ms/min | Result |
| --- | --- | --- | --- | --- | --- | --- |
| i5-2500 | Title/menus | NM | NM | NM | NM | NOT RUN |
| i5-2500 | Character select | NM | NM | NM | NM | NOT RUN |
| i5-2500 | Heaviest-stage fight | NM | NM | NM | NM | NOT RUN |
| i5-2500 | Intro movie | NM | NM | NM | NM | NOT RUN |
| i3-3240 | Title/menus | NM | NM | NM | NM | NOT RUN |
| i3-3240 | Character select | NM | NM | NM | NM | NOT RUN |
| i3-3240 | Heaviest-stage fight | NM | NM | NM | NM | NOT RUN |
| i3-3240 | Intro movie | NM | NM | NM | NM | NOT RUN |
| Q6600, SSE2 | Title/menus | NM | NM | NM | NM | NOT RUN; ISA blocker |
| Q6600, SSE2 | Character select | NM | NM | NM | NM | NOT RUN; ISA blocker |
| Q6600, SSE2 | Heaviest-stage fight | NM | NM | NM | NM | NOT RUN; ISA blocker |
| Q6600, SSE2 | Intro movie | NM | NM | NM | NM | NOT RUN; ISA blocker |
| E8400 | Title/menus | NM | NM | NM | NM | NOT RUN; ISA blocker |
| E8400 | Character select | NM | NM | NM | NM | NOT RUN; ISA blocker |
| E8400 | Heaviest-stage fight | NM | NM | NM | NM | NOT RUN; ISA blocker |
| E8400 | Intro movie | NM | NM | NM | NM | NOT RUN; ISA blocker |

Per-frame work, ms/frame, for **each of the four scenes** above:

| Stand-in | EE game thread | VU1 worker | GS frontend | GS renderer | IOP within EE | SPU2/audio | Over 16.667 ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| i5-2500 | NM | NM | NM | NM | NM | NM | Unknown |
| i3-3240 | NM | NM | NM | NM | NM | NM | Unknown |
| Q6600 | NM | NM | NM | NM | NM | NM | Unknown |
| E8400 | NM | NM | NM | NM | NM | NM | Unknown |

Existing counters do not yet supply that complete thread table. IOP interpretation and SPU2 mixing run **inside EE**, while the host audio callback is separate and lacks a duration counter. `rb_frames.log` EE/VU/VIF/GS/IOP fields are overlapping elapsed scopes, not exclusive OS thread CPU times; missing/disabled counters must not become zero. `mcyc` is consumed thread cycles, not milliseconds. Hash-free rollback Measure still changes scheduling/logging and is only a separate work diagnostic.

Collect host thread consumed CPU time and critical-path elapsed spans separately, aligned to verified scene windows; use explicit nested IOP/SPU2 spans, and measure audio callback work independently. Report mean/median/p99 and actual per-frame >16.667 ms violations, including waits/preemption semantics. Do not sum nested scopes or use aggregate CPU milliseconds to decide which individual frame missed budget. Detailed profiling and final low-overhead pacing need separate runs with instrumentation overhead checked.

For pacing use `PS2X_FRAME_TRACE=1` and the existing [present analyzer](../tools/perf_present_report.py). It retains absolute timestamp precision and emits every strict >20 ms interval. Example **analysis only**, once a genuine run exists:

```powershell
python -I -B tools/perf_present_report.py logs/weak-pc-t4/RUN --from 60 --to 120 --label "verified fight" --out logs/weak-pc-t4/RUN/fight
```

Report guest-frame FPS and presentation FPS separately, linear median/p99, count, duration and `count * 60 / observed_seconds`. Reject dropped/truncated/nonmonotonic traces and incomplete windows. Quantiles alone do not establish zero hitches. Check completed-image tick repeats/skips and actual monitor/swap configuration. Swap-return timestamps do not measure monitor scanout. A smooth-60 conclusion requires approximately 60 unique game frames/s, stable presentation near 16.667 ms, no strict >20 ms intervals in the accepted windows, and repeated runs across every required scene; use the gate's stricter interval range where applicable.

## GPU eligibility: OpenGL 4.3 is a floor

The GS backend requests core contexts 4.6, 4.5, 4.4, then **4.3**. It also requires `glBufferStorage` (core 4.4 or the extension on 4.3) and the texture-barrier functionality used by the classic raster path. A GL version alone is insufficient. Source: `deps/ps2recomp/ps2xRuntime/src/lib/gs/gpu/gs_gl.cpp`; local hardware discussion: [PERF.md](PERF.md).

| Old GPU family | Current path |
| --- | --- |
| Intel HD 2000/3000, including i5-2500's Sandy Bridge integrated graphics | Excluded: below OpenGL 4.3 |
| Intel HD 2500/4000, including i3-3240's Ivy Bridge integrated graphics | Excluded: below OpenGL 4.3 |
| Pre-Fermi NVIDIA, e.g. GeForce 8/9 and GTX 200 | Excluded: below OpenGL 4.3 |
| AMD Radeon HD 2000-4000 | Excluded: below OpenGL 4.3 |
| Fermi GTX 400/500 and newer; Radeon HD 5000/6000/7000 and newer; Intel Haswell HD 4600 | Driver/extension candidates only; verify actual buffer-storage and texture-barrier entry points, then benchmark |

These exclusions are based on local source/docs; no external driver lookup was made. No old GPU was tested. RTX 3090 performance cannot establish a minimum GPU or old-driver overhead, and a compatible CPU does not make its integrated GPU eligible.

## Ranked next levers

Before optimization: finish the gate, obtain comparable target scores, fix/audit Core 2 ISA compatibility and complete the ordinary scene/profiling fixtures. The order below is a **profiling hypothesis**, not a new measured speedup ranking.

1. **VU1 timing/dispatch and synchronization.** Measure current lifted coverage, exact-engine handovers, flag/pipeline/reset bookkeeping and worker queue waits. Native arithmetic alone does not remove these costs. Preserve exact-state behavior and oracle/full-state/rollback proof.
2. **GS CPU work and handover to presentation.** Separate GIF/frontend work, renderer commands/texture work, queue back-pressure and shared-texture waits. Reduce redundant work or waits where the new profiles identify it. At native resolution, lowering pixel count cannot solve CPU-side packet cost.
3. **Two-core worker policy and scheduling.** Compare split GS/VU workers against a combined policy under calibrated 2c/2t and 2c/4t contention. Account for presenter/audio and hog-period artifacts; extra threads do not add physical execution capacity.
4. **EE scheduler and IOP idle-call overhead.** Profile the current idle fast path before more interpreter work. [Earlier follow-up IOP sampling](../build/weak-pc-t4/iop-followup-context.md) attributed about 0.1 ms/frame to interpreted code and about 0.13 ms to mixing in its old scene, with much more fixed call overhead. The historical sound-on ~5 ms delta is not an exclusive IOP measurement. Recompiling all IOP code therefore has no demonstrated large payoff; exact current costs remain NM.
5. **An older-GPU backend.** A GL3.3-compatible streaming-buffer/feedback path could expand eligible machines. This is compatibility work, requires real old-driver testing and does not prove any requested CPU can maintain 60 fps.

Any runtime change needs its own deterministic proof, loopback rollback/lockstep pairs with zero mismatches and the coordination replay requirements. No simulation changes were made here.

## Run ledger and handoff

- [Run ledger](../logs/weak-pc-t4/RUNS.md): every task validation and result path; **zero game/build/calibration runs**.
- [Preflight JSON](../logs/weak-pc-t4/preflight/result.json): BLOCKED, all 16 cases NOT RUN/null, gate/lock/config snapshot, candidate hash and unchanged owner config.
- [Native topology](../build/weak-pc-t4/topology.json): all three affinity shapes verified, no workload calibration.
- [Core 2 linked-binary audit](../build/weak-pc-t4/core2-isa.json): POPCNT found, no old-hardware execution claim.

Resume when the gate has completed and timing slots are available. Obtain target-score evidence and resolve the ISA/fixture/counter prerequisites before running the matrix. Replace NM only with retained raw calibrated scene evidence; then update the opening "60 fps from ..." conclusion. No minimum CPU, old-GPU FPS or successful SSE2 build is claimed by this report.

Only this documentation is intended as the tracked task change. Supporting audits/scripts/logs stay ignored. No commit or push. Proposed commit: `Document T4 weak-PC prerequisites and Core 2 ISA blocker`. Suggested player-facing note after a real fix: `Improve compatibility checks for older CPUs; weak-PC performance requirements remain under validation.`
