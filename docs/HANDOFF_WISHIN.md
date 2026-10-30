# Handoff for TheWishin (Pablo + Claude, 2026-10-29/30)

Short version: the repo moved to the team organisation, your US line is kept separate from PAL, one-step US
builds now include netplay (pair test 0 desyncs here), and PAL gained music, graphics, controls and tooling you
can port later. Your netcode was not changed.

## 1. Repo and branches

- Active repo: **github.com/PS2recomp-swiss-team/tekken4-recomp** (you and Pablo are admins). The old
  `Lautreck/tekken4-recomp` is archived as a backup. Your PR #2 there was **not merged** (Pablo's decision).
- `master` = PAL (SCES-50878). `us-slus20328` = your branch, untouched. `us-iso` = your branch + our commits
  below: work on `us-iso` from now on.
- Pablo's rule: **PAL and US are two independent cousin projects, never merged into each other.** Fixes are
  ported by hand at the other disc's addresses. End goal: one recompiler that handles both ISOs, with online play
  on both. Online work focuses on US (PAL is too heavy network-wise).

## 2. What we added on `us-iso` (all additive, your netcode untouched)

| commit | what | why |
|---|---|---|
| f05630e | `tools/us_tree.cmd` / `us_tree.ps1`: every US script finds its PS2Recomp tree (TEKKEN4_SRC, else `..\tekken4-fork-ps2recomp_usa`, else `..\tekken4-fork-ps2recomp` on branch t4-us) and refuses a tree not on `t4-us`; backups to `~\tekken4-backup-us`; `build_game.ps1` StrictMode fix (empty VU1 list `.Count`) | on a PC with both projects the plain sibling is the PAL tree; nothing changes on your PC |
| 1dcd9aa | `tools/console-skill/` (MIT, github.com/Jakeschincariol/console-skill), see its ORIGIN.md | extra tools (pnach, TIM2, memcard, packaging); not run as skills |
| f755771 / aff2a4c | `docs/NETPLAY_CHECK_PABLO_PC.md`; `stage_generated.cmd` now stages `runtime/tekken4_net*.cpp/.h` and re-touches `tekken4_rollback_overrides.cpp`; `build_game.ps1` writes `t4net_build.txt` | **one-step builds had no netplay**: net files were only copied by `docs/rollback/net_build.cmd` (D:\ paths), and the unity build reused a netplay-off object |

Pair test on Pablo's PC with the one-step build (`net_pair.ps1 -Rtt 150 -Jitter 5 -Loss 3 -End 12000`, your
PHASE3 inputs): 12000 frames, **399 hashes, 0 mismatches**, ~2000 rollbacks per side (max depth 5), fps window
58-59, displayed frame p50 16 ms. Build id here `40f7094523f87dd6` (yours in SERVER_HANDOFF_T4.md: `9e861817...`).

## 3. Netplay findings for you (details: docs/NETPLAY_CHECK_PABLO_PC.md)

- `code_id` in `t4_buildid.py` does not hash the compiler or flags: two players on different MSVC versions get the
  same id and could still desync. Worth adding the compiler version.
- Gaps for real internet play (your open items are marked there): lobby + game handoff, NAT traversal / relay,
  two-PC test, no reconnect of a running match, no on-screen version-mismatch message, bandwidth (bytes) not in
  NETSUMMARY, result file for ranked.
- If PAL features are ported to US: only the widescreen switch changes which guest code runs, so both peers must
  have the same widescreen setting (or the lobby forces it). Music, resolution, filters, controls do not touch
  determinism.

## 4. New on `master` (PAL) that you may want on US later

| patch / tool | what | note for US |
|---|---|---|
| 35, 36, 41 | music: `sceCdSearchFile` via ISO9660, SPU2 IRQ + SIF user commands, libsd IRQ ack like Sony | you have your own versions (US 33/34/36): compare, do not apply both |
| 37 | F2 settings window: aspect 4:3/16:9/stretch, smooth scaling, `settings.ini` | host only |
| 38 | internal resolution 1x-4x live, sprite X alignment (PCSX2 alignSprite) | host only |
| 39 | recompiler: switchable instruction patches (`PS2_SWITCH`), widescreen 16:9 | US block ready in `docs/pnach.md` (addresses 0x216EA0, 0x1F6BF8, 0x18D408, 0x200D84/88/94) |
| 40 | texture filtering, FXAA, sharpening | host only |
| 42 | controls: presets, per-button gamepad/keyboard remap, deadzone, invert, swap, trigger threshold, F2 Controls | pad word only |
| `tools/pal_us_map.py`, `config/pal_us_map.csv` | PAL<->US address and patch translator (4757 of 4811 functions) | built on your map_pal_to_us / us_site; use it to port |
| `tools/databin.py` | DATA.BIN file table extractor for both discs (US 663 files, all checksums ok) | |
| `tools/pnach_to_switch.py`, `package_game.ps1`, `saves.ps1` | PCSX2 patch converter, package without game files, save backups | |

## 5. Questions for you

1. OK to keep the netplay staging in `stage_generated.cmd` (it changes `code_id`: one-step builds and your
   net builds now hash the same transport files)?
2. Compiler version in the build id: your call.
3. Which PAL features do you want ported to US first (widescreen needs patch 39 on US first)?
