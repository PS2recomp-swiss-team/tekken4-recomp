OWNS: external/PS2Recomp/ps2xRuntime/include/ps2_runtime_macros.h,external/PS2Recomp/ps2xRecomp/src/lib/fpu_translator.cpp,external/PS2Recomp/ps2xRecomp/src/lib/vu_translator.cpp,external/PS2Recomp/ps2xRecomp/src/lib/vu_translation_helpers.cpp,external/PS2Recomp/ps2xTest/src/ps2_float_semantics_tests.cpp,external/PS2Recomp/ps2xTest/src/ps2_vu_tests.cpp
TASK: implement your fpu-audit fixes in the recompiler/runtime macros, each with a unit test. Work mode, high effort.
CTX: your audit logs/grok/fpu-audit_20261022_062059.json (fix[] ranked, contra 7, open 6). SQRT.S is already fixed (patches/16, ft operand): keep it. Patches 01-16 are in the tree; the GS/IOP/audio files belong to other tasks.
ASK (in this order, one commit-sized change each):
1. CVT.W.S: chop toward zero with EE saturation (ps2_runtime_macros.h:856 via fpu_translator.cpp:78; 497 sites, no CTC1 so RM never changes) - match PCSX2 FPU.cpp exactly incl. out-of-range (0x7FFFFFFF / 0x80000000) and NaN-free inputs; test edge values (+-0.5, +-1.5, 2^31, -2^31-1, max float).
2. VCLIP macro side bits (vu_translator.cpp:264-281): bit order as PCSX2 VUops.cpp (bit0 x>+|w|, bit1 x<-|w|, ...), 6-bit shift of the 24-bit history; test.
3. VU0 macro FMAC ops write vu0_mac_flags (vu_translation_helpers.cpp) the way CFC2 MAC reads them; test with the CFC2.MAC sites' instruction kinds.
4. vftoi saturation (vu_translation_helpers.cpp:750-765); test.
Do NOT regenerate generated/ (Claude does that and runs the game). Build the recompiler: `cmd /c tools\build_ps2recomp_tools.cmd`; tests: `cmd /c tools\build_tests.cmd` (builds the shared tree: if a failure is in a file you do not own, report it, do not fix it).
TOOLS: one simple command per tool call; never chain with ; or && or set $env: inline.
LIMITS: OWNS files + logs/grok/ only; no git write commands.
PACING: do not return the final JSON until the DOD is met or you are blocked after trying; notes in logs/grok/fpu-fixes-notes.md.
DOD: the four changes with tests passing (counts); per change: generated-code impact (which instruction kinds change); final JSON.
