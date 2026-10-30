# End-to-end player build test (2026-10-30)

Fresh clone `D:\t4-e2e\tekken4-recomp` (plain `git clone` of D:\tekken4-us, branch us-slus20328, HEAD cbe9004, so only
committed files; the uncommitted work in D:\tekken4-us was not part of it), ISO `D:\tekken4-us\Tekken 4 (USA).iso`,
`TEKKEN4_SRC=D:\t4-e2e\tekken4-fork-ps2recomp`, `TEKKEN4_BUILD_DIR=runtime`. The pipeline is `tools\build_game.ps1`.

## Machine prerequisites found
Python 3.12.10, Git 2.55, CMake 4.4.4 and Ninja 1.13.2 (both winget packages, found by the script outside PATH),
Visual Studio 2022 Build Tools (MSVC x64, `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`). Internet
needed for the PS2Recomp clone and for CMake fetching the runtime's libraries. No BIOS, no Ghidra.

## Steps (wall time)
| Step | Result | Time |
|---|---|---|
| prereq | ok | 0.1 s |
| verify | SLUS-20328, ELF SHA-1 ok | 0.1 s |
| extract | SYSTEM.CNF, ELF, IOPRP243.IMG, DATA.BIN (2.6 GB) | 50.8 s |
| fork | clone ran-j/PS2Recomp, eb8688b, patches 01-57 applied (18-23, 30 with --ignore-whitespace; the `error: patch failed` lines in the log are the expected failed `--check` before the retry) | 36.3 s |
| tools | ps2_recomp.exe built | 96.3 s |
| recomp | `generated\` (4816 files, 78 MB) | 4.0 s |
| stage | copied into the fork tree | 2.9 s |
| runtime | VU1 image from the ELF (SHA-256 ok), cmake + ninja (287 targets, 220 native VU1 blocks, 0 unsupported), ps2EntryRunner.exe | 325.8 s (1st try failed at once, see below) |

Total about 8.6 minutes of build on this machine (fast CPU, SSD), not the "10-40 minutes" the script announces.
The steps were run in groups with `-Steps` (prereq,verify,extract,fork / tools / recomp,stage / runtime) only because the
heavy-step lock had to be checked between them; a single invocation was not re-run, so the "everything in one go" path is
the one thing not verified end to end (the steps are independent and use the same state file).

## Game run
`tools\run_capture.ps1 -Keys "8:Start,13:Start,17:Start,21:Cross,26:Start" -Shots 40,60` with PS2X_DEBUG_PANEL=0,
TEKKEN4_SOUND=1, TEKKEN4_ISO=the ISO. Result (logs\run_e2e in the fresh folder): Story Battle Stage 1, Kazuya vs Paul,
rendered correctly; log has 0 "VU1 INTERPRETER" lines (native VU1 linked). Timer: round timer 57 at the 40 s shot and 40 at the
60 s shot, the stage clock went 00:02:10 -> 00:19:10: 17 game seconds in 20 wall seconds, i.e. about 85 % by this crude
measure. The two window captures are not timed to the frame, so this shows "fight reached, running at roughly full
speed", NOT a verified 60 fps; a frame-timed measurement (PS2X_PERF_STATS, tools\frame_stats.py) was not done.
Sound was enabled; not listened to.

## Problems found and fixes
1. `build_game.ps1` runtime step died with `The property 'Count' cannot be found` (StrictMode: `Files` returns an empty array,
   which PowerShell turns into `$null`, when `game\vu1\micro` does not exist yet, which is always true for a new player).
   Fix: `$vu1 = @(Files ...)` (tools\build_game.ps1 line 474). Not committed.
2. Cosmetic, not fixed: when the run does not include the `verify` step (e.g. `-Steps runtime`), the closing "Ready" text
   omits the `set TEKKEN4_ISO=...` line, so a player who re-runs only the runtime step is not reminded that the ISO must be given
   via TEKKEN4_ISO (or sit in the repo root).
3. Cosmetic: the script says the runtime step takes "10-40 minutes"; measured 5.4 minutes here.
No problem was found in iso_extract.py or vu1_micro_from_elf.py. The README "Building" section still describes the manual
steps; it does not mention `tools\build_game.ps1` yet (not changed).

## What a player still needs installed
Python 3.8+ (not the Store stub), Git, Visual Studio 2022 Build Tools with "Desktop development with C++", CMake, Ninja,
internet. `prereq` checks all of these and prints the winget lines. The Build Tools are by far the largest download.

## Disk space
Fresh folder game\ 2.6 GB (extracted DATA.BIN), generated\ 78 MB, PS2Recomp tree with both build dirs (out\tools, out\runtime)
2.7 GB: about 5.4 GB, plus the ISO itself.

## Not verified
Single-invocation run of all steps; clean machine without VS/CMake/Ninja (prereq failure path only seen in the dry-run test
earlier); frame-accurate speed; sound by ear; the TEKKEN4_BUILD_DIR/TEKKEN4_SRC defaults (sibling folder) without the env vars.
