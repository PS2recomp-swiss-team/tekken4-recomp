# Tekken 4 Recomp

Static recompilation of Tekken 4 (PS2) to a native Windows executable using PS2Recomp.

## Target
- Tekken 4, PAL (Europe/Australia), v2.00, serial SCES-50878
- Main ELF: `game/disc/SCES_508.78` (SHA-1 `24ced2b7f3a0a40b3cacec56a030701d6be8e5ce`)
- SYSTEM.CNF: `BOOT2 = cdrom0:\SCES_508.78;1`, `VMODE = PAL`
- Disc data: `TEKKEN/DATA.BIN` (2.6 GB), `TEKKEN/DATA2.BIN` (1.7 GB), `IRX/IOPRP243.IMG`
- ELF facts: stripped (no symtab), C++ (ee-gcc, has `.gcc_except_table`), entry `0x00180088`,
  `.text` 0x00180080-0x002a91f8, 22 `.DVP.overlay` VU microcode sections, SDK libs 2.3x-2.4x
  (kernel, dma, graph, mpeg, ipu, pkt, pad, mc, scf, cdvd). Run `python -I tools/elf_info.py` to re-check.

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
- Addresses in this repo are for SCES-50878 v2.00 only; they do not carry over to NTSC-U/J builds.
- Run Python on anything under `game/` with `python -I`.
- Push after every commit (private remote PS2recomp-swiss-team/tekken4-recomp, the team organisation since 2026-10-29;
  the old Lautreck/tekken4-recomp is remote `old`): git is the only copy of tools/docs/config/patches/runtime. Branch
  `us-iso` (= `us-slus20328`, TheWishin's US SLUS-20328 port + rollback netplay) is a separate line: never merge it into master.
  NOBODY deletes (Claude, subagents, Grok): user rule 2026-10-27, only the user removes files, each step authorised by them. Deny rules in tools/grok_task.ps1 and ~/.claude/settings.json.
  tools/backup_local.ps1 copies ghidra/, logs/, external/PS2Recomp and the fork tree (+ its git bundle) to ~/tekken4-backup (run by grok_start.ps1).

- Clearing away (user, 2026-10-28): only `powershell -File tools\to_clean.ps1 -Path <item>` = MOVE into `to clean\` (gitignored, logged in logs\to_clean.log), never delete; the user inspects it.
