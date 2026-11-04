# VU microprograms: static recompilation (tools/vu)

Status 2026-11-04 (t4vurecomp). The game's VU1 microprograms (and VU0 micro-mode programs, when their micro memory
image is available) are recompiled to native x86 code at build time from the player's own ELF, like the EE code:
no VU interpreter and no run-time timing model runs for them.

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
