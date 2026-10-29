# Vendored: console-skill (third-party, MIT)

- Source: https://github.com/Jakeschincariol/console-skill, commit `a508929` ("The Console skill: 11 Claude skills,
  v1.0", 2026-10-22). Licence: MIT, see `LICENSE` in this folder (keep it with the code).
- Taken 2026-10-29 at the user's request ("take all the tools we don't have"), into both cousin projects (PAL `master`,
  US `us-iso`). Copied unchanged: the eleven `console-*` folders (Python tools, `reference/*.md` format notes,
  `templates/`, each `SKILL.md` as documentation), `tests/`, `README.md`, `LICENSE`. Left out: `.claude-plugin/`
  (plugin wiring). Nothing here is installed as a Claude skill: Claude Code only loads skills from `.claude/skills`
  or a plugin, so the `SKILL.md` files are plain docs.
- Reviewed before committing (2026-10-29): standard-library Python only; no network access, no eval/exec, no encoded
  payloads. `memcard.py` uses `socket.gethostname()` only to name sync-conflict copies; `targets.py doctor` runs
  compiler version checks; `console-tester/run.py` kills only the process tree it started. Not yet executed here:
  Claude Code's permission rules block running external code until the user allows it.

## Tools (what they add next to our own)

| tool | does | ours already |
| --- | --- | --- |
| `console-reverse/iso.py`, `elf.py`, `state.py` | read a disc image, boot ELF facts and CRCs, PS2Recomp TOML, STATE.md | `tools/elf_info.py`, US `tools/iso_extract.py`, docs/status.md |
| `console-backend/stubs.py` | rank "unimplemented stub / syscall TODO" lines of a run log | partly (manual) |
| `console-tester/run.py`, `triage.py`, `abdiff.py` | boot with a timeout, triage crash logs, A/B log diffs | `tools/run_capture.ps1`, `run_fixed_fight.ps1` |
| `console-graphics/tim2.py`, `gspacket.py`, `widescreen.py` | TIM2 textures to/from PNG, GS packet / DMA chain decode from RAM dumps, widescreen candidate scan | widescreen done by hand (patch 39) |
| `console-sound/vag.py` | VAG / PS-ADPCM to and from WAV | `tools/wav_stats.py` (stats only) |
| `console-levels/datascan.py` | find archives and embedded files in disc data | no |
| `console-physics/tune.py` | find float constants (speed, gravity, frame rate) in the ELF | no |
| `console-mod/pnach.py`, `override.py` | classify PCSX2 .pnach patches, scaffold game override modules | `[patches]` switch entries in config (patch 39) |
| `console-controller/padmap.py` | controller layouts (DualSense, Xbox, Switch Pro, keyboard) into pad code | one raylib gamepad + keyboard |
| `console-saves/memcard.py` | PCSX2 / raw memory card images to the runtime's `mc0` folders, .psu, backups, cloud sync | no |
| `console-anywhere/targets.py` | per-platform build doctor and packaging with a no-game-files guard | no |

## Project rules that apply here

- Run them with `python -I tools/console-skill/<skill>/<tool>.py ...` (CLAUDE.md: `python -I` on anything under `game/`).
- These commands DELETE or replace files: `memcard.py` (restore, sync, import into an existing `mc0` save),
  `targets.py package` (clears its staging and output folders), the `tests/` (their temp folders). Claude, its
  subagents and Grok never run them on project data (no-delete rule); the user runs them, or they get pointed at a
  scratch copy.
- Their output folder default is `console/` in the working directory; point outputs into `logs/` (gitignored) so
  nothing from the game lands in git. Never commit textures, audio, saves or other data they extract.
