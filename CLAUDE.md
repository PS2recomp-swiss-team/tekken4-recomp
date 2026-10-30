# Tekken 4 Recomp

Static recompilation of Tekken 4 (PS2) to a native Windows executable using PS2Recomp.

## Folders on the user's PC (since 2026-10-29)
- `D:\tekken4-us` = git worktree of branch `us-slus20328` (the US build): work here. It holds the US data too
  (game\, external\, ghidra\, logs\, generated\, the ISO).
- `D:\tekken4-recomp` = the main checkout on `master` (PAL, the colleague's line); no game data there.
- PS2Recomp: `D:\tekken4-fork-ps2recomp` branch `t4-us` (= ..\tekken4-fork-ps2recomp from both folders);
  agents' worktrees `D:\tekken4-fork-{rb,music,net,perf}` are merged into t4-us.

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

## Where to read next
`docs/PROJECT_MAP.md` (where everything is), `docs/SESSIONS.md` (which session owns what, start prompts),
`docs/status.md` (current state, newest first). Update status.md at the end of a session.

## Layout
- `launcher/` launcher | `runtime/` game overrides, staged by `tools\stage_generated.cmd` | `patches/` changes to PS2Recomp, applied
  in name order by `tools\build_runtime.cmd` | `config/` function maps, TOML (no game code) | `tools/` scripts
- Local only (gitignored): `game/`, `ghidra/`, `external/` (JDK 21, Ghidra 12.1.4 + EE plugin + GhidraMCP, `pytools` with Capstone,
  God-of-War reference port), `generated/`, `logs/`, `dist/`, `to clean/`, the ISO. `lobby/` is git-excluded (T5DR-derived).
- `../tekken4-fork-ps2recomp` = default PS2Recomp tree of all scripts (branch `t4-us`); `TEKKEN4_SRC` / `TEKKEN4_BUILD_DIR` override.

## Rules
- **Public vs private:** `origin` (Lautreck) is PUBLIC, `swiss` (PS2recomp-swiss-team) is private. New work goes to `swiss`, not `origin`.
  T5DR-derived code (`lobby/`) must never reach `origin`. Pushes to `swiss` were blocked by the auto-mode classifier: the user
  pushes by hand (`git -C D:\tekken4-us push swiss us-slus20328`).
- Never commit or publish game files, BIOS, Ghidra databases, generated C++ or the built exe (it contains recompiled game code).
- `C:\T5DROnline` is read-only from here: read and copy into this project, never edit. Never connect to, deploy to or change the
  server (VPS) and never use T5DR keys: the T5DR coordinator does the server side.
- Before every heavy build or game run check `C:\T5DROnline\build\int115\HEAVY.lock` and wait while it exists (unless the user says otherwise).
- Respect the budget: check usage between steps and stop at the limit the user set; save the state before it.
- NOBODY deletes (user rule): `powershell -File tools\to_clean.ps1 -Path <item>` moves into `to clean\`; only the user removes files.
- Runtime changes: per-game fixes go in overrides, not the global runtime. Anything running in a fight must keep the rollback
  self-test at 0 mismatches (`docs/ROLLBACK_PHASE2.md`, `tools\perf_rb_run.ps1`).
- Patches: two-digit numbers only (name order is the apply order; `100-` would sort before `57-`). PS2Recomp clones need
  `core.autocrlf=false`; some patches need `--ignore-whitespace` (build scripts handle it).
- Testing: one game run at a time (`logs\run.lock`, `tools\run_lock.ps1`). Never compile while the user plays or while measuring:
  background builds cause stutter and false fps. `tools\run_capture.ps1` presses F1 at start, so do not combine it with
  `PS2X_DEBUG_PANEL=0`. A check that decodes with the same assumptions as the code proves nothing about those assumptions.
- No PCSX2 or BIOS on this PC: optional dev comparison only, never a runtime dependency. Players need only their ISO.
- Addresses on this branch are for SLUS-20328 v1.00 only (PAL lives on `master`). Run Python on anything under `game/` with `python -I`.
