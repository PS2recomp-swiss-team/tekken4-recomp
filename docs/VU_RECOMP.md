# VU microprograms: static recompilation (tools/vu)

Status 2026-11-04 (t4vurecomp). The game's VU1 microprograms (and VU0 micro-mode programs, when their micro memory
image is available) are recompiled to native x86 code at build time from the player's own ELF, like the EE code:
the covered paths run without a VU interpreter or run-time timing model. Uncovered paths still use the exact
engine described below; this is not a claim that the entire executable contains no interpreter.

## Why
Before: `patches/11-native-vu1.patch` + `tools/vu1/vu1n_gen.py` (God of War port; generator licence unresolved,
docs/VU1_PROVENANCE.md) translated basic blocks, but every block still ran inside the exact engine's pipeline model
at run time (block timing tables, entry-timing caches, a history ring, MAC/clip flag rings, resetScheduler per
MSCAL), so a fight spent ~15 % of the game thread there (docs/PERF.md profile). The new generator is our own code.

## How
- `tools/vu/vu_isa.py`: decoding, register usage and latency rules, field by field the runtime's exact engine
  (`ps2xRuntime/src/lib/vu/ps2_vu1_core.cpp`: decodeUpperUsage / decodeLowerUsage / decodeInstructionPair).
- `tools/vu/vu_lift.py`: from every program entry (program starts in the image + the overlay addresses of
  tools/vu1_micro_from_elf.py) it follows every code path to the program's end and works out, while generating,
  the cycle at which each instruction pair issues (data stalls on VF/VI/ACC lanes, FDIV, EFU, WAITQ/WAITP) and
  what is in flight then. A block reached with different in-flight states ("timing contexts") is generated once
  per context. So a flag read (FMAND, FCAND, ...) gets the MAC/clip value the engine's 4-cycle flag pipeline would
  show at that cycle, MULq the Q of a DIV that is done by then, MFP the P of an EFU op that is done -- all decided
  at build time. Arithmetic is the engine's, op for op (`ps2_vu_lift_rt.h`: same float operations in the same
  order under the same rounding mode, operand normalisation, the MAC/status/clip rules, the exact-result path for
  zero/overflow/underflow lanes out of line).
- XGKICK uses the engine's own GIF transfer, advanced lazily to the lifted code's cycle before every VU memory
  write (so the packet gets exactly the bytes the cycle-accurate transfer copies); an XGKICK that has to wait for
  the previous transfer stalls by the run-time amount and continues in the context aged by it.
- Anything the generator does not cover hands the exact pipeline state to the engine at an instruction-pair
  boundary (`VuLiftAccess::exportState`), which continues exactly: a JR to a target not known at build time, a
  run close to its cycle budget (checked at loop heads), unknown entries, changed code (each program's pairs are
  hashed per code upload; a mismatch uses the engine).
- Build: `tools\build_runtime.cmd` passes `-DPS2X_VULIFT_GEN=tools/vu/vu_lift.py`; CMake writes
  `vulift_generated/vulift_part0..3.cpp` into the build folder from `game\vu1\micro\*.bin` (and
  `game\vu0\micro\*.bin`). The image and the generated C++ are game code: never committed or published.
  `TEKKEN4_VULIFT=0` builds without it.

## Switches
- `PS2X_VULIFT=0`: run time back to the old path (native blocks / exact engine) in the same exe.
- `PS2X_VULIFT_VERIFY=<n>|all`: every lifted run (or the first n) also runs in the exact engine from the same entry
  state (silently, XGKICK packets captured) and is compared bit for bit: VF/VI/ACC/Q/P/I/R, MAC/status/clip, pc,
  cycle counter, pipeline readiness, VU memory, XGKICK packets. `[vulift-verify]` lines.
- `PS2X_VULIFT_STATS=1`: every 10 s, runs per entry (lifted / handed over / not lifted) and host time.
- `PS2X_VU_CAPTURE=<folder>`: writes each distinct micro memory a program runs from (`vu<unit>_<hash>.bin`).

## Proof
See build/coordination/T4_VURECOMP.md (coordinator notes) for the numbers: offline fuzz
(`tools/vu/vulift_fuzz.cpp`, `tools/vu/build_fuzz.cmd`: random entry states incl. denormal/Inf/NaN operands and
tiny cycle budgets, engine vs lifted bit for bit), in-game verify over real fights, frame-exact picture and
state-hash comparisons (`TEKKEN4_RB_SHOTS`), netplay pairs, ms/frame.

## Execution-path audit and indirect branches (integration stutter audit)

`PS2X_RECOMP_AUDIT=1` enables independent counters at the execution sites. Each host thread owns separate VU0/VU1
counters and prints `[recomp-audit]` about once per second of activity. Divide counts by the reported `seconds`
for rates. `runs/cycles` cover whole real runs; `lifted_calls/cycles` cover generated lifted functions before
handover; `native_calls/cycles` cover the older native block runner; `compiled_calls/cycles` cover the older
predecoded-pair backend; `interpreted_pairs/cycles` count actual `stepInterpreted` execution, including a lifted
handover and isolated missing native blocks. `missing` counts lift lookup misses, `handovers` lifted exits to the
exact engine. Silent verification/oracle passes are excluded. `missing_native_dispatch_total` is a process-wide
atomic count of EE missing-function reports. The audit is a diagnostic run and adds counter/report overhead;
leave it off for final frame-pacing measurements. A final interval shorter than one second is not printed.

The earlier `GOW_VU1_STATS` interpreted-step count omitted some native-block and lifted handover paths; a zero
there was not evidence of zero interpretation. It also shared report state across VU units/threads. Use the new
counters for the coverage claim.

The lifter now discovers additional JR/JALR candidates from immediate VI assignments in the player's own micro
image, restricted to valid entries already discovered in that image. Candidates are grouped with their callers
so their incoming pipeline contexts are compiled together. Every candidate remains guarded by an exact run-time
target comparison, and unknown targets still export the full pipeline state to the exact engine. This covers
indirect dispatch table targets reproducibly on clean builds without adding a game-derived address map to source.
`tools/vu/test_vu_lift.py` exercises synthetic programs for register isolation, literal/relative-write exclusions,
unsigned immediate and unit address wrap semantics, image bounds, and the unknown-target handover.

The broader executable audit distinguishes these paths:

| Component | Runtime behavior |
| --- | --- |
| EE functions | Generated native function table; missing target reports/stops according to the debug policy. No EE instruction interpreter. |
| COP2 macro instructions | Translated into native operations along with EE code. VCALLMS/VCALLMSR enter VU0 micro mode. |
| VU0/VU1 micro mode | Build-time lifted programs first; older native blocks/predecoded pairs or exact interpreted pairs remain available as fallback. Coverage must be measured. |
| IOP physical IRX modules | R3000 instruction interpreter plus native HLE imports/services. Existing `PS2X_IOP_PROF=1` reports instructions and host time; `PS2X_IOP_PROF_PCS=1` adds hot blocks. This part is not statically recompiled. |
| EE kernel/library, IOP imports, VIF/GIF/GS, SPU2 | Native host implementations of the required hardware/services. Native service code is not lifted guest code. |
| Guest JIT | No runtime guest-code JIT in these paths. GPU-driver shader compilation is separate from guest CPU execution. |

The offline proof workflow is `tools\vu\build_fuzz.cmd <output> <generated-parts>` followed by `vulift_fuzz.exe
<image> <iterations> <seed> [vu0]`, and real runs with `PS2X_VULIFT_VERIFY=all`. The verifier compares registers,
flags, cycle and pipeline state, VU memory and emitted GIF packets bit for bit. New target coverage must pass both;
synthetic target-discovery tests alone do not prove arithmetic/timing equivalence.

### Integration proof, 2026-11-04

The expanded indirect-target set passed five synthetic target-discovery tests under isolated Python (`python -I
tools/vu/test_vu_lift.py -v`). Offline fuzz used 500 iterations per lifted entry, seed 1204:

| Unit | Entries | Attempted | Compared bit for bit | Excluded oracle stops | Mismatches |
| --- | ---: | ---: | ---: | ---: | ---: |
| VU1 | 65 | 32,500 | 27,742 | 4,758 | 0 |
| VU0 | 9 | 4,500 | 4,500 | 0 | 0 |

Excluded random cases are not equivalence proofs. The existing verifier calls its stopped-oracle category
"rejected XGKICK packet"; the random initial states also produce reserved-pair diagnostics after arbitrary
indirect jumps. The complete result and build/input SHA256 manifest remain local under `logs/stutter/fuzz-*`.
A first VU1 launch failed in its PowerShell output wrapper and provided no recoverable proof; its metadata is
retained separately. Re-running with redirection inside cmd produced the VU1 result above. Both completed fuzz
runs exited zero, and every heavy slot was released after its run.

A separate real-game verification run, bounded at rollback frame 2600, reported at least 1,020,000 lifted/exact
oracle comparisons with zero mismatches. Included fight audit intervals had zero VU0/VU1 interpreted pairs,
legacy native/compiled calls, missing lifted entries and handovers; EE missing-dispatch total was zero. The
verifier substantially reduces host-frame throughput, so its host-second rates are not normal-game rates.
The phase interval table and its edge exclusions are in `logs/stutter/runs/after_verify2/audit-phase-table.md`.
No whole-binary interpreter-free claim follows: the IOP interpreter is still active in that same session.
