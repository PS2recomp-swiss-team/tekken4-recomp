# T4 player release: plan for a zip that needs no Visual Studio

Status 2026-10-30: plan plus a working prototype of the switch (nothing downloaded, no zip built yet).
Goal (owner): download one zip, start the launcher, BUILD GAME from your own ISO (no BIOS), play. Like T5DR Online.

## 1. How T5DR ships its toolchain (read from its launcher/tools/docs, measured values from its docs/RELEASE.md)

* `package_release.py --release` stages a folder and a zip. The player needs no Visual Studio, Git or Python:
  * `python\` a private copy of a python.org CPython **with tkinter/Tcl-Tk** (the "embeddable" zip has no tkinter),
    isolated with a `python3XY._pth`, self-tested with a bare PATH. 38 MB unpacked, about 13 MB zipped.
  * `toolchain\llvm\` = `clang-cl.exe` (105 MB), `lld-link.exe` (72 MB), `llvm-profdata.exe` (6 MB) and clang's own
    resource headers (16 MB): 201 MB raw, **72.6 MB zipped**. Pinned LLVM 23.1.3, fetched by `tools/fetch_llvm.py`
    from the official GitHub release with a pinned SHA-256 (the zip keeps the Apache-2.0 + LLVM-exception text).
  * `deps\ps3recomp\` the recompiler source at the pinned commit with its patches already applied (no Git on the
    player's PC), `runtime\t5dr.exe + t5dr.lib` the **prebuilt** runtime without any game code (1.9 MB).
  * `T5DR Online.exe` a 120-140 KB native starter that runs `python\pythonw.exe launcher\t5dr_launcher.pyw`.
  * Total: **90 MB zip, 250 MB unpacked**; the player's disk after the build: +0.8 GB. Without it the player would
    install VS Build Tools (6.4 GB, admin prompt, 10-20 min).
* The trick that makes this possible: the **game code is compiled on the player's PC into a DLL with clang-cl +
  lld-link only**. That code needs no Windows SDK or C runtime headers (clang's own headers + 7 tiny headers in
  `tools/gamedll/include`) and links against two import libraries made from our own `.def` files (`t5dr_host.def`,
  `ucrt_min.def`). So no MSVC STL, no Windows SDK, no CMake/Ninja for the player (`build_game_dll.py` drives clang-cl itself).
* Safety net: `package_release.py` scans folder and zip and fails on game file names, game content (ELF/PKG magic,
  `func_XXXXXXXX` lifted code), keys, and any big binary outside `toolchain\llvm`.

## 2. How T4 differs (why it cannot be copied one to one)

| | T5DR | T4 today (`tools\build_game.ps1`) |
|---|---|---|
| game code | lifted into `t5dr_game.dll` (separate) | 4816 generated `.cpp` (78 MB) are **linked into** `ps2EntryRunner.exe` (48 MB) together with the whole runtime |
| runtime | prebuilt, ships | built on the player's PC (several hundred files, 10-40 min with MSVC) |
| compiler needs | clang-cl + lld-link only | MSVC STL/CRT headers and libs + Windows SDK, CMake, Ninja, Git (FetchContent: raylib, imgui, rlImGui, sse2neon; ExternalProject: a prebuilt LGPL ffmpeg zip), PS2Recomp clone + 57 patches |
| game data | extracted ~600 MB | `game\disc` 2.6 GB (DATA.BIN 2.7 GB is extracted, but the runtime reads the ISO itself, see open questions) |
| more game-derived code | none | `game\vu1\micro\*.bin` (VU1 microcode from the ELF, `vu1_micro_from_elf.py`) is turned into native C++ blocks by `vu1\vu1n_gen.py` inside the runtime build |

Consequence: **a prebuilt `ps2EntryRunner.exe` can never ship** (it contains the recompiled game). Whatever links
with the generated code is built on the player's PC; the question is only how little of it.

Measured tonight: LLVM 23.1.3 `clang-cl` (the T5DR pin) accepts a generated function
(`AdjustTime_0x2962e8.cpp`, `-fsyntax-only`, same include dirs as the runtime, MSVC STL on the include path): rc 0.
The generated code only uses the `READ*/WRITE*/GPR_*/ADD32/FPU_*` macros, `R5900Context`, and 9 calls into
`PS2Runtime` (`dispatchGuestBranch` 22951x, `eeCheckpointDue` 2821x, `Load*/Store*` 423x, `SignalException`,
`handleBreak`, `handleSyscall`, `executeVU`, `clearLLBit`). That is a narrow interface.

## 3. Options for "no Visual Studio"

**A. T5DR route: split game code from runtime (recommended end state).** Prebuilt, shippable `ps2x_host.exe`
(runtime + our overrides, built by us with MSVC at release time) loads `t4_game.dll` which the player's PC compiles from
`generated\` + the native VU1 blocks with clang-cl + lld-link. Needs: a slim `ps2_game_abi.h` (R5900Context, the macros,
a table of the 9 runtime entry points instead of `ps2_runtime.h` and the STL), an import library from a `.def`, and the
runtime loading the DLL instead of linking `register_functions.cpp`. Player needs only `llvm` (about 75 MB zipped). No
Microsoft files, no CMake/Ninja/Git, the 10-40 min runtime build drops to the 4816-file compile (T5DR: 40 s for 39 MB
of C on 16 cores). Effort: days, and it touches the runtime (other agents' area); cross-DLL cost of
`dispatchGuestBranch` must be measured (it is already an indirect call).

**B. Bundled clang-cl + fetched Microsoft sysroot (quick, prototype below).** Zip ships LLVM, CMake, Ninja, Python,
the vendored PS2Recomp + FetchContent sources; the launcher downloads the MSVC STL/CRT and Windows SDK headers and
libs (`toolchain\msvc`, `toolchain\winsdk`, a `tools\fetch_msvc_sysroot.py` in the style of `xwin`, from Microsoft's
public manifest, player accepts Microsoft's licence in the launcher). Those files must **not** be in our zip (Microsoft's
terms do not list them as redistributable). Costs the player roughly 0.4-0.8 GB of disk and a 150-300 MB download
(estimate, not measured) and the full runtime build (10-40 min). Works with today's code, no runtime changes; first run
needs internet (it already does for the libraries).

**C. llvm-mingw (clang + libc++ + mingw-w64, all freely redistributable).** No Microsoft files, but the runtime and its
dependencies (raylib, ffmpeg/SDL import libs, OpenGL) must build and run with the MinGW ABI. Unknown risk; not tried.

Recommendation: ship **B** first (days, no engineering risk), design **A** as the 1.0 goal (it also removes the long
build for the player, the biggest usability problem), keep C as the fallback if Microsoft's terms for B are a problem.

## 4. Contents of the release zip `T4-<version>.zip` (estimates; T5DR numbers are measured)

| Folder / file | What | Unpacked | Zipped |
|---|---|---|---|
| `Tekken4.exe` (starter) | runs `python\pythonw.exe launcher\t4_launcher.pyw` (T5DR's `t5dr_stub.c` idea; write our own, MSVC or clang-cl) | 0.15 MB | 0.1 MB |
| `launcher\` | `t4_launcher.pyw`, `t4core.py`, (later updater, controls editor) | 0.1 MB | - |
| `python\` | private CPython with tkinter, `._pth` isolated | 38 MB | 13 MB |
| `toolchain\llvm\` | clang-cl, lld-link, llvm-lib, llvm-rc, llvm-mt, clang headers, LLVM license | ~215 MB | ~78 MB |
| `toolchain\cmake\`, `toolchain\ninja\` | CMake 4.x (bin + Modules/share only), Ninja | ~90 MB | ~30 MB |
| `toolchain\toolchain.json` | pinned versions + SHA-256 of every part (marker the scripts look for) | - | - |
| `tools\`, `patches\`, `config\`, `runtime\`, `docs\` | build scripts, our patches, TOML + function map, game overrides | ~7 MB | ~2 MB |
| `deps\ps2recomp\` | PS2Recomp at `eb8688b` with `patches\*.patch` applied, **without** `out\`, `.git`, staged `generated` | ~8 MB | ~2 MB |
| `deps\fetch\{raylib,imgui,rlimgui,sse2neon}` | sources only (not the 488 MB `_deps` build dir) | ~25 MB | ~7 MB |
| `deps\ffmpeg\` | the LGPL shared prebuilt zip the runtime CMake downloads today + its license text | ~45 MB | ~25 MB |
| prebuilt `ps2_recomp.exe` | the recompiler (1.4 MB, no game code) so the "tools" step is skipped | 1.4 MB | 0.6 MB |
| `LICENSES\`, `README.txt`, `release.json` | licences (GPL-3.0 project, LLVM, CMake, Ninja, Python, raylib, imgui, ffmpeg, SDL2, OpenEXR), version | - | - |
| **Total (option B, sysroot not included)** | | **~430 MB** | **~160 MB** |
| fetched on first build (B only) | MSVC STL/CRT + Windows SDK, x64 | 0.4-0.8 GB | 150-300 MB |
| made on the player's PC | `game\disc` (2.6 GB, or ~0.1 GB without DATA.BIN), `generated\` 78 MB, `out\` 0.5-1.7 GB | 3-4.5 GB | - |

For option A the zip is about 100 MB (no CMake/ninja/ffmpeg sources, no sysroot) plus the prebuilt host.

### Must never be in the zip (check with a T4 version of `package_release.py --scan-only`, to be written)
No ISO, no `SLUS_203.28`, no `DATA.BIN`/`IOPRP243.IMG`, no `game\`, no `generated\`, no `game\vu1\micro\*.bin`, no built
`ps2EntryRunner.exe` or any exe with `*_0x` function tables, no BIOS (none is needed), no `launcher\settings.json`, no
logs, no Ghidra project. Content checks: ELF magic with the SLUS SHA-1, `func_`/`_0x` function-name density, any file
byte-identical to a file under `game\disc`, any exe over 20 MB outside `toolchain\llvm`.

## 5. Licensing notes
* Project is GPL-3.0 (derived from PS2Recomp): shipping the vendored patched PS2Recomp source and our repo files in the
  zip satisfies the source offer. Keep the licence texts in `LICENSES\`.
* LLVM: Apache-2.0 with LLVM exception (redistributable, as T5DR does). CMake BSD-3, Ninja Apache-2.0, Python PSF,
  raylib/rlImGui zlib, imgui/sse2neon MIT, SDL2 zlib, OpenEXR BSD-3, FFmpeg **LGPL** (shared DLLs only, ship licence +
  link to the exact build the CMake uses).
* Microsoft MSVC STL/CRT/Windows SDK: not shipped; option B downloads them on the player's PC after the player accepts
  Microsoft's licence; option A and C do not use them. Owner to decide.
* "Tekken" is a Bandai Namco trademark; zip and README say "no game data, no BIOS, bring your own disc" and "not
  affiliated" (already in README). The recompiled code and VU1 micro images only ever exist on the player's PC.

## 6. Making `build_game.ps1` use the bundled toolchain (prototype in this repo, 2026-10-30)

Implemented as COPIES so no tracked, shared script changed (merge into one script with a switch when the other
agents are done):

| New file | What it does |
|---|---|
| `tools\build_game_portable.ps1` | copy of `build_game.ps1`; `toolchain\toolchain.json` present = portable mode. prereq: checks `python\python.exe`, clang-cl, lld-link, llvm-lib, CMake, Ninja, the MSVC/SDK sysroot, `deps\ps2recomp` and prints what is missing (tested with an empty and a faked bundle); no vswhere, no Git. fork: a tree with `.t4-vendored.json` is used as is (no clone, no patch loop). `Get-TreeHead` reads the head from that file. `T4_PYTHON` (the launcher's interpreter) is honoured. Without `toolchain\` it behaves exactly like `build_game.ps1` (dry run compared). |
| `tools\toolchain_env.cmd` | puts `toolchain\llvm\bin`, cmake, ninja on PATH, sets INCLUDE/LIB from `toolchain\msvc` + `toolchain\winsdk`, `CC/CXX`, `T4_TOOLCHAIN_FILE`; exit code 2 = no bundle (caller falls back to vswhere/vcvars64). |
| `tools\t4_toolchain_clangcl.cmake` | CMake toolchain file: clang-cl, lld-link, llvm-lib/rc/mt, bundled ninja; points `FETCHCONTENT_SOURCE_DIR_*` at `deps\fetch\*` (no Git, no network). |
| `tools\build_runtime_portable.cmd`, `tools\build_ps2recomp_tools_portable.cmd` | copies of the two scripts; call `toolchain_env.cmd` and pass the toolchain file; fall back to Visual Studio when there is no bundle; the runtime copy skips the Git patch loop for a vendored tree. |
| `launcher\t4core.py` | picks `build_game_portable.ps1` when `toolchain\toolchain.json` exists and shows the bundled parts in its prerequisite list. |

Still to do before a zip can be built (needs downloads or the other agents' trees, so not done tonight):
1. `tools\fetch_llvm.py` (copy the idea of T5DR's: pinned URL + SHA-256, unpack `bin\` + `lib\clang`, keep also
   llvm-rc, llvm-mt, llvm-lib) and the same for CMake (zip, drop docs/GUI) and Ninja. LLVM 23.1.3 asset is 901 MB.
2. `tools\fetch_msvc_sysroot.py` (option B): Microsoft manifest, x64 only, no symbols, licence prompt.
3. `tools\package_release.py` for T4: stage folders, vendor PS2Recomp (checkout `eb8688b`, apply patches, drop `.git`,
   write `.t4-vendored.json {head}`), vendor the FetchContent sources, copy the python with tkinter + `._pth`,
   `release.json`, scan folder and zip, `SHA256SUMS`.
4. Make the runtime CMake take ffmpeg from a local zip (one more patch: `FFMPEG_PREBUILT_URL` is a plain `set()` today,
   not a cache variable, so `-D` cannot override it) and check `clang-cl` builds the whole runtime and the game identically
   (RelWithDebInfo `/Z7` flags are clang-cl compatible; performance vs MSVC must be measured: fight fps, 60 on 9 of 10 stages).
5. The starter exe, an offline test on a clean Windows 11 VM without VS/Git/Python (the T5DR smoke recipe).
6. Option A work item list: `ps2_game_abi.h`, `.def`/import lib, DLL loading in the runtime, VU1 blocks into the DLL.

## 7. Open questions for the owner
1. Option B first, A as goal? (B needs Microsoft's licence acceptance on the player's PC; A takes days of runtime work.)
2. Does the runtime really need `game\disc\DATA.BIN` (2.7 GB copy)? It reads sector data from `TEKKEN4_ISO`
   (`runtime/tekken4_overrides.cpp`, falls back to DATA.BIN). If not, the extract step can skip it (saves 2.7 GB and minutes).
3. Ship a prebuilt `ps2_recomp.exe` (1.4 MB) and skip the "tools" step? (saves 1-2 min and the MSVC dependency of step 5.)
4. Release flags: RelWithDebInfo with `/Z7` makes `out\` 1.7 GB here; a player build should be Release (no debug info).
   AVX2: T5DR decides by CPU at build time; T4 has no such switch yet.
5. Code signing / SmartScreen / AV false positives: T5DR spent a whole doc on it; budget the same.
6. Updater (T5DR `updater.py`, ~1500 lines, release signature check): copy later? List it in `launcher\COPIED_FROM_T5DR.txt`.
7. Where the zip is published (the T4 repo is public, GPL-3.0): GitHub Releases like T5DR, with `SHA256SUMS`.
