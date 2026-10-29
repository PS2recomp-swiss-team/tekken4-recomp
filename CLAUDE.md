# Tekken 4 Recomp

Static recompilation of Tekken 4 (PS2) to a native Windows executable using PS2Recomp.

## Folders on the user's PC (since 2026-10-29)
- `D:\tekken4-us` = git worktree of branch `us-slus20328` (the US build): work here. It holds the US data too
  (game\, external\, ghidra\, logs\, generated\, the ISO).
- `D:\tekken4-recomp` = the main checkout on `master` (PAL, the colleague's line); no game data there.
- PS2Recomp: `D:\tekken4-fork-ps2recomp` branch `t4-us` (= ..\tekken4-fork-ps2recomp from both folders);
  agents' worktrees `D:\tekken4-fork-{rb,music,net,perf}` are merged into t4-us.
- Pablo's PC (2026-10-29): `H:\tekken4-recomp_usa` = checkout of branch `us-iso` (US ISO there), PS2Recomp tree
  `H:\tekken4-fork-ps2recomp_usa` (t4-us); `H:\tekken4-recomp` + `H:\tekken4-fork-ps2recomp` are the PAL cousin project.
- PAL (master) and US (us-iso / us-slus20328) are independent cousin projects (user, 2026-10-29): never merge one into
  the other. Every US script finds its tree through tools\us_tree.cmd / us_tree.ps1 (TEKKEN4_SRC, else
  ..\tekken4-fork-ps2recomp_usa, else ..\tekken4-fork-ps2recomp when on t4-us) and refuses a tree not on t4-us.
  Backups go to ~\tekken4-backup-us. Repo: PS2recomp-swiss-team/tekken4-recomp (organisation).

## Target (branch us-slus20328, since 2026-10-29; `master` keeps the PAL build)
- Tekken 4, NTSC-U (USA), v1.00, serial SLUS-20328 (US frame data; one DATA.BIN, no PAL60 menu)
- Main ELF: `game/disc/SLUS_203.28` (SHA-1 `a4b7dde20a2918c550badd127a245db155c36815`, CRC32 `0xB975F704`)
- SYSTEM.CNF: `BOOT2 = cdrom0:\SLUS_203.28;1`, `VMODE = NTSC`
- Disc data: `TEKKEN/DATA.BIN` (2.7 GB, LBN 401), `IRX/IOPRP243.IMG`
- ELF facts: stripped, C++ (ee-gcc), entry `0x00180088`, `.text` 0x00180080-0x002a85b8, gp `0x35cb70`,
  22 `.DVP.overlay` VU microcode sections (same VU1 micro memory as PAL: `vu1_62802e7b8abf4848.bin`).
- Ported from PAL without the PAL ELF: `tools/map_pal_to_us.py` (function lists aligned by size),
  `tools/us_site.py` (US code at a PAL address), `tools/translate_jump_tables.py`, `tools/port_overrides_us.py`.
  PAL -> US data deltas: .data -0xe40, .sdata/.sbss -0x2700, .bss -0x2780, .rodata per jump-table anchor.
- Ghidra runs headless: `tools\ghidra_headless.cmd <elf> <analyzer_seed.toml> <out_dir>`, then
  `python -I tools/postprocess_ghidra_export.py --starts <out_dir>\ghidra_starts.txt`. No GhidraMCP needed.
- Goals (user): players need no BIOS, only their ISO; rollback online as good as T5DR Online
  (TheWishin/T5DROnline-Source, `src/rollback`, `docs/ROLLBACK.md`); plan in `docs/ROLLBACK_PLAN.md`.

## Layout
- `game/` - files extracted from the disc (gitignored, never commit)
- `ghidra/` - Ghidra project (gitignored; contains game code)
- `../tekken4-fork-ps2recomp` (H:\tekken4-fork-ps2recomp) - DEFAULT PS2Recomp tree of all build/run scripts since 2026-10-28
  (user's choice): branch = pinned upstream commit + patches/*.patch committed one by one; `TEKKEN4_SRC` overrides.
- `external/PS2Recomp` - old toolchain tree (ran-j/PS2Recomp), gitignored; holds Grok's uncommitted WIP, kept, not built
- `external/God-Of-War-Native-Port` - reference port (GS/VU1/IOP/sound solutions to study)
- `external/ghidra_12.1.4_PUBLIC` - Ghidra (needs JDK 21) with `ghidra-emotionengine-reloaded` v2.1.38 and
  GhidraMCP 2.0 in `Ghidra/Extensions`. GhidraMCP serves on http://127.0.0.1:8080/ only while a CodeBrowser
  has the plugin enabled; bridge is `external/ghidramcp-venv/Scripts/ghidra-mcp.exe`
- `external/pcsx2` - PCSX2 v2.8.2 portable (needs a BIOS dumped from the user's own console; the user's dumps are
  in `E:\God Hand + Emulator\bios`, PAL SCPH-70004 v12 fits this game; never copy them into the repo)
- `config/` - our PS2Recomp TOML + function maps (`function_map.csv` = Ghidra + `extra_functions.csv`; no game code)
- `patches/` - our changes to PS2Recomp itself (hardware behaviour), applied by `tools\build_runtime.cmd`
- `runtime/` - our game overrides (`*_overrides.cpp`), staged into ps2xRuntime by `tools\stage_generated.cmd`
- `tools/` - our own helper scripts
- `docs/status.md` - current state and next steps; read it first, update it at the end of a session

## Rules
- Never commit or publish game files, Ghidra databases, or generated C++ from the ELF.
  Only configs, function maps, patches, runtime code and docs go in git.
- Per-game fixes go in game overrides (`PS2_REGISTER_GAME_OVERRIDE`), not the global runtime.
- PCSX2 is ground truth: compare behaviour against PCSX2's debugger before "fixing" anything.
- One goal per session (one crash, one syscall, one subsystem). Commit after each working step.
- Addresses on this branch are for SLUS-20328 v1.00 only (PAL SCES-50878 v2.00 lives on `master`); map with tools/map_pal_to_us.py.
- Run Python on anything under `game/` with `python -I`.
- Push after every commit (private remote Lautreck/tekken4-recomp): git is the only copy of tools/docs/config/patches/runtime. 
  NOBODY deletes (Claude, subagents, Grok): user rule 2026-10-27, only the user removes files, each step authorised by them. Deny rules in tools/grok_task.ps1 and ~/.claude/settings.json.
  tools/backup_local.ps1 copies ghidra/, logs/, external/PS2Recomp and the fork tree (+ its git bundle) to ~/tekken4-backup (run by grok_start.ps1).

- Clearing away (user, 2026-10-28): only `powershell -File tools\to_clean.ps1 -Path <item>` = MOVE into `to clean\` (gitignored, logged in logs\to_clean.log), never delete; the user inspects it.
