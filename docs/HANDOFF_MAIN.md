# Handoff to the Main session: Tekken 4 port (2026-10-30)

From the session that built the US port. You are the **Main session** (launcher + coordination). Your first job: read this,
then write one brief per working session (`docs/sessions/launcher.md`, `game.md`, `netplay.md`, `release.md`) that the user can
paste into new sessions. `docs/SESSIONS.md` already has the split and start prompts; turn them into full briefs and keep them current.

## Goal (user)
- A native PC port of Tekken 4 anyone can play: download, point at your own ISO, BUILD GAME, play. No BIOS, no game data shipped.
- Online with rollback as good as the user's T5DR Online.
- **One launcher for T5DR, T4 and future games.**

## Read these
`CLAUDE.md` (rules), `docs/PROJECT_MAP.md` (where everything is), `docs/SESSIONS.md` (ownership), top of `docs/status.md` (log).

## Where things are
- Work in `D:\tekken4-us` (git worktree, branch `us-slus20328`). `D:\tekken4-recomp` = `master`, the colleague's PAL line: leave it.
- PS2Recomp: `D:\tekken4-fork-ps2recomp`, branch `t4-us` = upstream `eb8688b` + the 77 patches in `patches\`. Verified: applying
  them to a clean clone gives exactly this tree.
- Remotes: `swiss` = PS2recomp-swiss-team/tekken4-recomp (**private**, new work goes here); `origin` = Lautreck/tekken4-recomp (**PUBLIC**).
- Pushes to `swiss` were blocked by the auto-mode classifier: the user pushes by hand. 3+ local commits are not pushed yet.

## State
| Area | State | Evidence |
|---|---|---|
| Offline game, all modes | works | QA report `logs\qa\REPORT.md`, 7-min run; user played |
| Picture: 480p progressive, resolution steps to 4K, FXAA, fullscreen | works | `docs/GRAPHICS.md`; user: looks good |
| Performance: 60 fps on all 10 stages, even frame delivery | works on a quiet PC | `docs/PERF.md`; user: much smoother, occasional micro stutter |
| Controller (XInput) | works | `docs/INPUT.md`; user with a real pad: good, very slight lag |
| In-game music and sound | works | user by ear: good |
| All fighters unlocked by default | works | char select in Story, Arcade, VS; Eddy/Miharu/Violet not selected one by one |
| Build from own ISO | `tools\build_game.ps1` ran in one go from a fresh zip: 6.6 min, reached a fight | `docs/E2E_BUILD.md`; only on this PC, which has all tools |
| Rollback netplay | 0 desyncs at 0/50/100/150 ms with 3 % loss | `docs/ROLLBACK_PHASE3.md`, `PHASE3B.md`; **two instances on one PC only**, about 55 fps there because both share one GPU |
| Launcher | first version: Play, Build, Settings, Controls, Online placeholder | BUILD GAME tab only dry-run |
| Lobby | T4 copy of the T5DR lobby, 12/12 local tests with a stub game | `docs/LOBBY.md`; real game through the lobby not run; code local only in `lobby\` |

## Open, by session
**Launcher (you):** shared shell with per-game modules; real `.exe`, updater, Online tab; missing settings (AA levels, HUD sharp, aniso,
run-ahead). The T5DR launcher is in `C:\T5DROnline\launcher`, read-only from T4 sessions. Other sessions already work on launcher
design ("Launcher-Redesign", "T5DR Online launcher design"): agree the plan with the user before merging anything.

**Game:** intro movie music still sounds rough to the user. Checked: no gaps, in sync, decoder and channel layout right, gain now 0.7.
Not known whether a real PS2 sounds the same: needs a comparison with PCSX2 or a console by the user. Also speckles on the beach sand at
high resolution, hitches at boot and char select -> loading, run-ahead too slow (43-53 fps, stays off).

**Netplay + Online:** two-PC and WAN test (user + second PC, `tools\net_play.ps1`); real game through a local lobby
(`tools\net_lobby_pair.ps1`); result file for ranked; direct fight; later replays, spectating, training rooms.

**Release:** player still needs Python, Git, CMake, Ninja, VS 2022 Build Tools. Options in `docs/RELEASE_PLAN_T4.md`: B = compiler in the zip,
MSVC libs fetched on the player's PC; A = game code as a DLL like T5DR. Recommended: B first, then A.

## Decisions the user still has to make
- Release path (B then A?), product name and channel (proposed: "Tekken 4 Online", releases in the Swiss repo).
- Where the lobby code goes: allowed into the Swiss repo on its own branch; not done yet.
- Removing old worktrees and test folders (about 11 GB in `D:\t4-e2e`, `D:\t4-kollege-test`): only the user deletes.

## External
- T5DR coordinator: sets up a separate T4 lobby instance on the VPS after T5DR 1.1.9, from `SERVER_HANDOFF_T4.md`. Whether they have
  picked it up is unknown here. No T4 session touches the server or T5DR keys.
- Colleague: got `dist\T4-Mini-Release-Kollege-2026-10-30.zip` from the user (or will); no feedback yet. It needs his own US ISO.

## Rules that bit us
- Never put T5DR-derived code or the built exe in a public place; the exe contains recompiled game code.
- `C:\T5DROnline` read-only. Check `C:\T5DROnline\build\int115\HEAVY.lock` before heavy builds and game runs; wait while it exists.
- No compiling while the user plays or while measuring: it causes stutter and false fps.
- Patches: two-digit names only, they apply in name order. Only one session merges into `t4-us` and `patches\`: you.
- New `*_overrides.cpp` files go into every tree via `stage_generated.cmd`: keep unfinished ones out of `runtime\`.
- Runtime changes in a fight need the rollback self-test at 0 mismatches.
- Budget: weekly limit about 92 % on 2026-10-30, resets 2026-11-03 around 02:00 local. Check usage; the user sets the ceiling. Up to 7 parallel
  agents used about 10 points overnight.
