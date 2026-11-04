# Integrated T4 stutter and native-code audit

Status: source audit complete; runtime acceptance results pending. This document must not be read as a claim
that the 0 frames >20 ms/minute target or interpreter-free execution has been achieved.

## Surviving owner evidence

[Owner analysis](../logs/stutter/owner-analysis.md) and [provenance](../logs/stutter/owner-provenance.json)
record the preserved logs and their hashes. The requested 2026-11-04 19:45-20:30 session logs were overwritten
by the launcher. Surviving logs cover approximately 20:31:42-20:33:39. They have no per-frame timing, hitch,
NETHASH or fallback totals. Cumulative startup/movie fps cannot establish fight pacing.

The packaged and original integration EXEs match: build `fda47faa5656a184`, SHA256
`cf59ba4d237d48b95a3ec73f6e174b65305b221410627266306c4a3cd6c27be0`. Settings include RTX 3090,
1080p internal resolution, FXAA, anisotropic 4x and borderless fullscreen. Concurrent T5 compilation overlapped
the surviving session; no particular hitch, or overlap in the earlier requested interval, is proved by that fact.
VU1 notices establish real exact-engine handovers, including program 0328 at pc 0768. Sixteen capped notices
are not a total; matching all captured microcode groups is not proof that every executed path is lifted.

## Source findings and changes

- EE functions dispatch through generated native functions. Missing EE dispatch reports are counted;
  there is no hidden EE interpreter that makes missing functions work.
- The lifter now infers guarded JR/JALR candidates from immediate VI assignments in the player's microcode.
  Candidates are restricted to discovered entries and grouped with callers for static pipeline-context analysis.
  Unknown targets retain the exact-state handover. See [VU_RECOMP.md](VU_RECOMP.md) for proof requirements.
- Patch 95 adds actual VU execution-path counters, excluding silent verifier passes; patch 97 distinguishes
  actual IOP interpreted instructions, native HLE imports and skipped idle cycles. Rates use reported seconds.
- Patch 96 buffers per-frame and hitch diagnostics, avoids diagnostic file I/O inside present/EE frame locks,
  joins the reporter before runtime destruction and flushes the final partial second. Bounded-buffer overflow
  explicitly marks the trace incomplete. The owner had these diagnostics disabled: moving this I/O alone
  cannot explain or fix the reported owner-session stutter.
- GS hardware initialization (`gs_hw_backend.cpp::ensure`) compiles its main draw ubershader and auxiliary
  shaders once. The window filter is compiled on first presentation. No per-material shader/pipeline creation
  path was found in steady fighting. Driver-internal first-use work is not excluded by this source inspection.
- `UploadFrame` calls `GS::latchHostPresentationFrame`, whose first operation synchronizes VU/frontend work.
  It then polls for a completed shared texture for up to 12 ms. `upload_ns` includes the latch; `shared_wait_ns`
  isolates the later acquisition loop. Their distinction matters when identifying which queue blocked.
- Each queued shared Present publishes a new sequence, including static menus/blank output. The trace records
  the completed image's tick/sequence separately from the requested tick; old counters labeled the request as
  the displayed frame even when the prior image was acquired again.
- The presenter normally reanchors to guest vblank +2 ms and waits through `waitMessage(1)`. Thus guest delivery
  jitter can reach presentation. A late guest frame cannot be diagnosed as a Windows timer fault without evidence.
- Raylib requests swap interval 0; the runtime removes Raylib's 60 Hz limiter and applies its own pacing.
  Startup `[present-config]` logs query actual WGL swap interval, monitor Hz/size and the 1 ms timer request result.
  These values do not measure driver overrides, compositor scanout or actual timer wake precision.
- The growing netplay-summary sorting cost was already replaced by bounded histograms. Normal offline play
  does not enter netplay's NETSUMMARY path; an offline hitch cannot be assigned to that line merely by cadence.
- Existing patch 90 needed refreshed context after patch 88 added audio diagnostic lines. This changes patch
  applicability only, with no audio runtime semantics. Movie A/V synchronization remains the separate movaudio
  task: its newer presentation-sync work is absent from the original integrated binary.

## Native code versus remaining runtime models

| Part | Execution path and claim boundary |
| --- | --- |
| EE game functions | Statically generated native C++; missing dispatch reports/stops under the selected debug policy. |
| COP2 macro mode | Native operations generated with EE functions; VCALLMS/VCALLMSR can enter VU0 micro mode. |
| VU0/VU1 micro mode | Lifted native programs first; native blocks, predecoded pairs and interpreted exact-engine pairs remain possible. Real counters determine coverage. |
| IOP IRX code | R3000 interpreter plus native HLE services and idle skipping. It is not statically recompiled. |
| Kernel/imports, VIF/GIF/GS, SPU2 | Native host service/device implementations; host C++ is distinct from lifted guest code. |
| Guest JIT | No runtime guest-code JIT in the audited paths. GPU-driver shader compilation is a separate mechanism. |

Consequently, ?T4 is entirely static recompilation? is currently false. Preserving exact VU fallback and the IOP
interpreter is preferable to silently removing required behavior. Remaining conversion work needs its own proof.

## Measurement and acceptance method

Use an isolated profile, copied ELF/IRX/cards, local networking only, muted output and BelowNormal/background
launches. Acquire two atomic HEAVY slots for timing; reject windows with competing game/build load. Record actual
EXE hash/build ID, switches, QPC frequency, monitor Hz, swap interval and screenshots identifying each scene.
Normal posted-input menu/fight runs are the owner-performance reference. Rollback `measure` mode changes event
ordering and adds hash work; use it for state comparisons rather than substituting its timings for normal play.

Enable `PS2X_FRAME_TRACE=1` on the candidate; keep verifier, fallback audit, IOP profile and VU stats off for final
timing. Original-build `TEKKEN4_PRESENT_LOG=1` records legacy QPC; its synchronous diagnostic overhead differs
from buffered candidate logging. Report this limitation when comparing their traces. Do not enable
`TEKKEN4_INPUT_LAG=1` during shared-presentation timing: that probe forces the readback path.

```powershell
python -I tools/perf_present_report.py logs/stutter/runs/RUN --from 55 --to 115 --label "steady fight" --out logs/stutter/runs/RUN/fight
```

The command writes percentile/count JSON and a CSV listing **every interval strictly >20 ms** in the selected
window. Cutoffs use interval end timestamps; adjust scene windows against the run's actual captures. CSV clocks
are monotonic ns relative to perf start; legacy QPC requires recorded frequency/origin. Present timestamps measure
swap return, not physical 60 Hz scanout. `swap_ns` covers EndDrawing, including batch flush, swap and input polling.
GS/EE deltas overlap across threads and cannot be summed as exclusive costs. They identify instrumented spans,
not exact root causes for shader work, file I/O, allocation/GC, audio or OS scheduling; untraced delay stays unknown.

`[logic]` counts the sound-driver 0x100 main-loop call by scene; it is not a counter at every UI animation/input
update. In diagnostic `after_verify2` (measure mode with hashing), scene 2 reports about 60 calls/second. Static
inspection finds no every-other-frame gate in the outer scene dispatch, scene manager or active main-menu input
handler. The historical 30 Hz menu-logic statement in INPUT.md is therefore unproven for this integrated path;
it must not be used as the explanation for lag. This also does not establish that every UI animation runs at 60 Hz.
Shared sequence and renderSequence count completed presentation publications, not distinct pixel content.
Preserve guest timing. Separate `PS2X_RECOMP_AUDIT=1` runs report real VU/IOP rates. Use fuzz plus
`PS2X_VULIFT_VERIFY=all` for bit-identical VU proof, offline full-state/NETHASH comparisons before/after,
and a loopback rollback pair with zero mismatches.

## Results and remaining acceptance

The candidate was rebuilt successfully and staged into the existing LocalTest folder. Build `81d558b686ecf118`,
EXE SHA256 `42f1b1d1b526b0fb43dbe07c5d86fb7993c247a2ae0f45a5b6ef8116f1d197d0`.
This task has **not** demonstrated the requested steady 16.7 ms / zero >20 ms present-interval target.
It has not isolated every owner-session hitch or established a measured menu-lag improvement.

| Check | Original / before | Fixed candidate / after |
| --- | --- | --- |
| EE missing dispatch | No counter in preserved owner run | 0 in real verification session |
| VU interpretation | 16 capped owner notices prove a real handover, not its total rate | 0 actual interpreted pairs/handovers in included real VU0/VU1 audit intervals |
| Main-menu 30 Hz explanation | Historical documentation, not established here | 60 main-loop calls/s and 60 publication events/s in diagnostic scene2; individual UI animation rate unproved |
| Native work cost, VU elapsed mean | 9.384 ms/frame | 9.506 ms/frame in concurrent full-hash diagnostic: no clear improvement |
| Native work cost, EE thread Mcycles mean | 44.226 | 44.729 in that same diagnostic; no normal-FPS inference |
| Title/main/character-select present p99 | Not accepted/measured | Blocked on visible-app access |
| Steady-fight present intervals >20 ms/minute | Not accepted/measured | Blocked; do not claim zero |

The work-cost window is 3901 common logical frames2600..6500. It includes full-state hashing and concurrent
processes, preemption and waits. It is not a controlled normal-player benchmark. See the full
[work-cost table](../logs/stutter/hashpair/before_after_6500/work-cost-comparison.md).

Correctness evidence:

- Five synthetic target tests passed. VU1 fuzz compared27742 valid cases, VU0 compared4500, all0mismatches;
 4758 VU1 random stopped-oracle cases remain excluded, never proof claims.
- The real all-VU oracle run was deliberately bounded at frame2600 (native exit0) after more than1020000
 comparisons, all0mismatches. The oracle makes fights very slow; those timings are not acceptance data.
- Original/current offline runs agree for all6500 full-state-hash records and216 NETHASH records. Both
 required termination after a failed WM_CLOSE timeout; raw overall passed=false is retained. The state
 comparison passed independently of cleanup.
- One loopback rollback pair reached NETEND4800 both sides,162/161rollbacks,169/165resimulated frames,
 0 hash mismatches,0 NETDESYNC. All160 common confirmed samples matched. Net samples cover the net hash
 domain (RDRAM/scratchpad/VU0/IOP/EE-cycle; VU1/GS are cut). This is not an every-frame render comparison.
 Native exit1 was intentional headless test cleanup after NETEND, not a claimed graceful exit.
- The IOP remains an interpreter. Diagnostic menu intervals measured about159k interpreted instructions/s;
 verification-slowed fight intervals about10.9k/s. These fight rates must not be presented as normal60FPS rates.

The owner-specific sound starter also inherited automated-test `PS3_WINDOW_BACKGROUND=1` and BelowNormal
priority through the local support guard. That manual path now requests a focused window and Normal priority
for the native game only; build tools and automated tests remain BelowNormal. Four dry-run cases and the
existing guard tests pass. No audible game was launched and the practical FPS benefit remains unmeasured.
This change lives in LocalTest/tools/local_guard.py; the START filenames and launcher source stay intact.

Computer Use rejected both visible launch attempts: `not approved to use perflaunch` and
`not approved to use start_t4`. The prepared validated helper was not run via another path. App access is
required to complete the normal-pacing visible-desktop A/B. An instrumented sandbox run reported monitor_hz500;
that is not independent confirmation of the owner's visible60Hz display. Clarification remains pending.
No display/security settings changed. Movie A/V synchronization remains the separate task's responsibility.

[Every run/result](../logs/stutter/RUNS.md), [VU proof](../logs/stutter/fuzz-summary.md),
[real audit intervals](../logs/stutter/runs/after_verify2/audit-phase-table.md),
[offline hashes](../logs/stutter/hashpair/before_after_6500/comparison.json),
[rollback proof](../logs/stutter/rollback-pair/frozen_rollback_4800/SUMMARY.md).

The verification run also retains every recorded interval and every strict >20ms event in
`logs/stutter/runs/after_verify2/frame_trace.csv` and `all-hitches.hitches.csv`. Its9799present intervals
include150 >20ms events and7237 repeated completed ticks while the all-VU oracle deliberately slows guest
execution. These are verification-load diagnostics, not an owner-session or normal-mode acceptance run;
uncaptured thread/OS causes are not silently assigned. Physical60Hz and all normal-rate fallback/latency
measurements remain to collect after app access is available.

No commits or pushes. Proposed commit: `Expand VU indirect recompilation coverage and add runtime pacing audits`.
