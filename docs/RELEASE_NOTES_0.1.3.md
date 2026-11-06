# Tekken 4 Recomp v0.1.3 (pre-release) - release notes

One build for everyone. Everything in [RELEASE_NOTES_0.1.1.md](RELEASE_NOTES_0.1.1.md) and
[RELEASE_NOTES_0.1.2.md](RELEASE_NOTES_0.1.2.md) still applies.

## What is new

- **The release brings its own compiler.** The zip now carries clang-cl and lld-link (LLVM 23.1.3), CMake 4.4.4,
  Ninja 1.13.2, Python 3.12 and every source the build needs (PS2Recomp at eb8688b with our patches, raylib, imgui,
  rlImGui, ELFIO, toml11, fmt, libdwarf, rabbitizer, FFmpeg). Build never uses a Visual Studio, Git, CMake, Ninja or
  Python installed on the PC: a PC with Visual Studio 2022, one with Visual Studio 2026 and one with none build the
  same game with the same build id. In v0.1.2 a player with VS 2026 (MSVC 19.51) got another build id than one with
  VS 2022 (19.44) and the lobby never paired them.
- **Microsoft's C++ headers and libraries** (MSVC CRT/STL 14.44, Windows SDK 10.0.26100) are downloaded once by the
  first Build, straight from Microsoft, with fixed checksums (`tools/msvc_sysroot.lock.json`): every player gets the
  same bytes. They cannot be part of our zip (Microsoft's licence). About 240 MB download, 760 MB on disk.
  Pressing Build accepts Microsoft's licence terms (`LICENSES/microsoft-*.txt`). After that the build needs no network.
  They are kept once per PC (`%LOCALAPPDATA%\OpenRecomp\cache`) for every Tekken 4 folder and update: a second install
  or an update does not download them again.
- Nothing of the PC reaches the build: a release folder keeps only Windows' own variables (PATH, CL/_CL_/LINK,
  CFLAGS/CXXFLAGS, INCLUDE/LIB, a developer prompt's Visual Studio variables, CMAKE_*, PYTHON* are dropped), and the
  compiler never looks for an installed Visual Studio: it used to take `_MSC_VER` from it (19.44 with VS 2022, 19.51
  with VS 2026, 19.33 with none) -- now fixed at 19.44 for everyone.
- Install folders up to 115+ characters build (checked); spaces are fine.
- Faster build: the first build is about 3.5 minutes here incl. the Microsoft download (0.1.3 test builds: 4.5); the
  disc is unpacked while the compiler is set up; Microsoft's files are fetched six at a time and checked once. A
  rebuild with nothing changed takes about 2 seconds (was 40).
- The online identity uses the game files from your ISO (SLUS_203.28, TEKKEN\DATA.BIN, IRX\IOPRP243.IMG) instead of
  the whole ISO file: two clean rips of the same disc play each other. Direct IP and the lobby use the same rule.

## Everybody builds once more

The new compiler is a new build: after updating, press Build once (about 5 minutes on a recent PC, plus the one-time
Microsoft download). 0.1.2 and 0.1.3 cannot play each other.

## Known issues

Unchanged from v0.1.2 (see RELEASE_NOTES_0.1.1.md and docs/KNOWN_ISSUES.md).
The VU1 generator script's licence (tools/vu1/vu1n_gen.py, docs/THIRD_PARTY.md) is still being settled, as in
v0.1.0-v0.1.2.

## Reporting a problem

Tell us your PC (CPU, GPU), Windows version, whether you played direct IP, VPN or the lobby, and what happened.
Keep both players' `logs` folders and check them for personal details before sharing. Never share your ISO.
