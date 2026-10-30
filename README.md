# Tekken 4 Recomp

A static recompilation of **Tekken 4** (PlayStation 2) into a native Windows program, built on
[PS2Recomp](https://github.com/ran-j/PS2Recomp). The game's MIPS code is translated to C++ ahead of time and
linked against PS2Recomp's runtime, which stands in for the PS2 hardware.

Target: **NTSC-U (USA), v1.00, SLUS-20328** on branch `us-slus20328` (PAL SCES-50878 v2.00 on `master`). Addresses only match that build.

> This repo holds **no game data**: no ELF, no disc files, no BIOS, no generated C++ from the game.
> You need your own copy of the game and a BIOS dumped from your own console.

## Status

US build (SLUS-20328), 2026-10-29:

| Milestone | State |
|---|---|
| Function map (headless Ghidra, 4454 + 359 functions), 40 jump tables, recompiles with 0 errors | done |
| Boot, Namco logo, intro movie, difficulty, mode select, character select, Story prologue | done |
| A fight (Story Battle, Kazuya vs Paul), native VU1, OpenGL renderer, full speed (60 fps) | done |
| Sound incl. background music (real Namco driver on the emulated IOP) | done (confirmed by ear); intro movie music still rough |
| Other modes, long sessions | done (QA: all modes, 7-min run); all fighters unlocked by default |
| PC picture: progressive, resolution steps to 4K, FXAA, fullscreen; 60 fps on all stages; XInput pads | done |
| One-step build from the player's own ISO (no BIOS): `tools/build_game.ps1` | done (run end to end; still needs VS Build Tools) |
| Rollback netplay (GGPO-style, UDP, build id, hash checks) | works between two local instances, 0 desyncs; two-PC test and lobby server next |

The PAL build (`master`) reached all of the above earlier; its log is in [docs/status.md](docs/status.md).

What it took to reach the main loop (PAL, carried over):
- **Functions Ghidra never found** (C++ static constructors and vtable methods, only reachable through
  pointer tables): `tools/find_missing_functions.py` adds 350 of them.
- **The sound driver** (Namco's IOP module, SIF RPC 0x12345) is answered by a silent stand-in in
  `runtime/tekken4_overrides.cpp` until the real module runs on PS2Recomp's emulated IOP.
- **MFIFO**: the game streams its GS packets through a scratchpad -> ring buffer -> VIF1 DMA ring.
  `patches/ps2xRuntime-dmac-mfifo.patch` adds that to the runtime (plus D_ENABLER readback).

The day-to-day log, findings and next steps are in [docs/status.md](docs/status.md).

## Layout

| Path | What |
|---|---|
| `config/` | PS2Recomp TOML and function maps (`function_map.csv` = Ghidra functions + `extra_functions.csv`) |
| `patches/` | Changes to PS2Recomp itself (hardware behaviour), applied automatically by the build script |
| `runtime/` | Game overrides for this ELF (`PS2_REGISTER_GAME_OVERRIDE`) |
| `tools/` | Helper scripts: ELF inspection, Ghidra helpers, missing-function finder, build/run scripts, PCSX2 PINE reader |
| `launcher/` | The launcher: Play, Build game, Settings, Controls |
| `docs/PROJECT_MAP.md`, `docs/SESSIONS.md` | Where everything is, who works on what |
| `docs/status.md` | Current state, findings, next steps |
| `game/`, `ghidra/`, `generated/`, `external/` | Local only, gitignored |

## Building (Windows)

You need your own Tekken 4 USA ISO (SLUS-20328), Visual Studio 2022 Build Tools (C++), CMake, Ninja, Git and Python 3. No BIOS, no Ghidra.
Unpack into a new, empty folder (the build uses the folder next to it for PS2Recomp), then:

```
python launcher\t4_launcher.pyw
```

or `powershell -ExecutionPolicy Bypass -File tools\build_game.ps1 -Iso "C:\path\Tekken 4 (USA).iso"`, then set `TEKKEN4_ISO` and run `tools\run_game.cmd`.
About 7-20 minutes and 6 GB. Details: `START_HIER.txt`, `docs/E2E_BUILD.md`. Project overview: `docs/PROJECT_MAP.md`.

## Thanks

- [ran-j/PS2Recomp](https://github.com/ran-j/PS2Recomp): the recompiler and runtime everything here builds on.
- [Waffle565/God-Of-War-Native-Port](https://github.com/Waffle565/God-Of-War-Native-Port): a reference port
  whose notes saved a lot of guesswork.
- [PCSX2](https://pcsx2.net/): the ground truth for how the hardware behaves.
- [chaoticgd/ghidra-emotionengine-reloaded](https://github.com/chaoticgd/ghidra-emotionengine-reloaded) and
  GhidraMCP.

## License

GPL-3.0, like PS2Recomp (the patches and overrides are derived from its code). See [LICENSE](LICENSE).
Tekken is a trademark of Bandai Namco Entertainment; this project is not affiliated with or endorsed by them.
