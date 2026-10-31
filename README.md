# Tekken 4 Recomp

A static recompilation of **Tekken 4** (PlayStation 2) into a native Windows program, built on
[PS2Recomp](https://github.com/ran-j/PS2Recomp). The game's MIPS code is translated to C++ ahead of time and
linked against PS2Recomp's runtime, which stands in for the PS2 hardware.

Target: **NTSC-U (USA), v1.00, SLUS-20328** on branch `us-slus20328` (PAL SCES-50878 v2.00 on `master`). Addresses only match that build.

> This repo holds **no game data**: no ELF, no disc files, no BIOS, no generated C++ from the game.
> You need your own Tekken 4 USA ISO. No BIOS is needed.

## Status

Sunday beta target (2026-11-01): offline play and online by direct IP or VPN,
inside the new launcher, built from each player's own ISO. No lobby or ranked.
Release is conditional on the owner's two-PC test and the
[go/no-go checklist](docs/BETA_GO_NO_GO.md). Shared-launcher integration and a
clean-PC path-B build are not proved by this source copy.

See the [beta notes](docs/BETA_RELEASE_NOTES.md),
[known issues](docs/KNOWN_ISSUES.md) and
[announcement drafts](docs/BETA_ANNOUNCEMENTS.md). Intro music is rough;
one-sided stalls occurred with two games on one PC and are not proved fixed.
Online still boots a new game for each match; persistent sessions and automatic
VS entry are not release promises. `TEKKEN4_NET_AUTO_VS` stays off without its
own passed pair test.

Recorded developer-build results for SLUS-20328, 2026-10-29/30. These are
historical reports; their logs and game data are absent from this review copy:

| Milestone | State |
|---|---|
| Function map (headless Ghidra, 4454 + 359 functions), 40 jump tables, recompiles with 0 errors | done |
| Boot, Namco logo, intro movie, difficulty, mode select, character select, Story prologue | done |
| A fight (Story Battle, Kazuya vs Paul), native VU1, OpenGL renderer | reported working; the E2E run reached a fight but did not measure frame-accurate speed |
| Sound incl. background music (real Namco driver on the emulated IOP) | done (confirmed by ear); intro movie music still rough |
| Other modes, stability | mode checks and a 7-minute run reported; long sessions remain unproved; all fighters unlocked by default |
| PC picture: progressive, resolution steps to 4K, FXAA, fullscreen; XInput pads | developer checks reported; the [stage sweep](docs/PERF.md) records 60 fps on its test machine, not a minimum-PC guarantee |
| Build from the player's own ISO (no BIOS): `tools/build_game.ps1` | [developer E2E steps](docs/E2E_BUILD.md) reached a fight using installed VS Build Tools; a single invocation of all steps was not checked in that run |
| Rollback netplay (GGPO-style, UDP, build id, hash checks) | recorded local-pair tests had 0 mismatches; two-PC direct-IP/VPN acceptance still pending; lobby outside beta scope |

Earlier PAL development results are recorded in [docs/status.md](docs/status.md).
They do not validate the US beta candidate.

What it took to reach the main loop (PAL, carried over):
- **Functions Ghidra never found** (C++ static constructors and vtable methods, only reachable through
  pointer tables): `tools/find_missing_functions.py` adds 350 of them.
- **The sound driver** (Namco's IOP module, SIF RPC 0x12345) is answered by a silent stand-in in
  `runtime/tekken4_overrides.cpp` until the real module runs on PS2Recomp's emulated IOP.
- **MFIFO**: the game streams its GS packets through a scratchpad -> ring buffer -> VIF1 DMA ring.
  `patches/01-ps2xRuntime-dmac-mfifo.patch` adds that to the runtime (plus D_ENABLER readback).

The day-to-day log, findings and next steps are in [docs/status.md](docs/status.md).

## Layout

| Path | What |
|---|---|
| `config/` | PS2Recomp TOML and function maps (`function_map.csv` = Ghidra functions + `extra_functions.csv`) |
| `patches/` | Changes to PS2Recomp itself (hardware behaviour), applied automatically by the build script |
| `runtime/` | Game overrides for this ELF (`PS2_REGISTER_GAME_OVERRIDE`) |
| `tools/` | Helper scripts: ELF inspection, Ghidra helpers, missing-function finder, build/run scripts, PCSX2 PINE reader |
| `launcher/` | Standalone T4 launcher: Play, Build game, Settings, Controls, direct-IP Host/Join (new controls not run here) |
| `docs/PROJECT_MAP.md`, `docs/SESSIONS.md` | Where everything is, who works on what |
| `docs/status.md` | Current state, findings, next steps |
| `game/`, `ghidra/`, `generated/`, `external/` | Local only, gitignored |

## Building (Windows)

Player zip (path B, pending clean-PC validation): extract everything into a new writable folder and
use the matching new launcher's T4 entry. The included `Tekken4.cmd` is the standalone T4
starter; it does not establish shared-launcher integration. Private Python, LLVM, CMake, Ninja
and vendored sources need no separate installation.
The standalone T4 Online tab now has Host/Join controls for an IPv4 address and UDP
port. Those controls have not been run here; they are not the external shared launcher.
BUILD GAME asks you to accept Microsoft's terms before fetching the C++/SDK build libraries directly from Microsoft.
Nothing from the game or a BIOS ships. The scripts are implemented; no portable zip or portable game build was tested here.
Release preparation and the remaining gates: [docs/RELEASE_PATH_B.md](docs/RELEASE_PATH_B.md).
The maintainer's player-package entry point is `tools/make_player_zip.ps1`
with `-Inputs`, `-Version`, `-Stage` and `-Zip`. It requires reviewed path-B payloads.
If those are unavailable, `tools/make_test_zip.ps1` makes a **source test zip**:
each tester must install the developer tools below. That fallback is not a portable player release.

Developer checkout or source test zip (without `toolchain/toolchain.json`): you need your own
Tekken 4 USA ISO (SLUS-20328), Visual Studio 2022 Build Tools with C++, MSVC and the Windows SDK,
CMake, Ninja, Git and Python 3 with tkinter. No BIOS, no Ghidra.
Unpack into a new, empty folder (the build uses the folder next to it for PS2Recomp).
The source test zip is a CLI test kit; follow its `TEST_ONLINE_DE.txt`. A full
developer checkout also includes the standalone launcher:

```
python launcher\t4_launcher.pyw
```

or `powershell -ExecutionPolicy Bypass -File tools\build_game.ps1 -Iso "C:\path\Tekken 4 (USA).iso"`, then set `TEKKEN4_ISO` and run `tools\run_game.cmd`.
The recorded developer build used about 5.4 GB plus the ISO and took about 8.6 minutes
on its test machine; allow more space and time for a different PC or build configuration.
Details: `START_HIER.txt`, `docs/E2E_BUILD.md`. Project overview: `docs/PROJECT_MAP.md`.

## Thanks

- [ran-j/PS2Recomp](https://github.com/ran-j/PS2Recomp): the recompiler and runtime everything here builds on.
- [Waffle565/God-Of-War-Native-Port](https://github.com/Waffle565/God-Of-War-Native-Port): a reference port
  whose notes saved a lot of guesswork.
- [PCSX2](https://pcsx2.net/): the ground truth for how the hardware behaves.
- [chaoticgd/ghidra-emotionengine-reloaded](https://github.com/chaoticgd/ghidra-emotionengine-reloaded) and
  GhidraMCP.

## License

GPL-3.0, like PS2Recomp (the patches and overrides are derived from its code). See [LICENSE](LICENSE).
Copied components and unresolved provenance are listed in [docs/THIRD_PARTY.md](docs/THIRD_PARTY.md).
The project's licence statement does not resolve the VU1 generator's missing licence evidence.
Tekken is a trademark of Bandai Namco Entertainment; this project is not affiliated with or endorsed by them.
