# Session plan

For this clean source copy, read `AGENTS.md` first. Maintainer paths, worktrees, builds and Git writes
described below are outside this copy's scope. Existing test results were not reproduced here.

There is one T4 session for the game, netplay + online and release packaging. Launcher work is in the separate
OpenRecomp-FGC project. One coordinating Main session outside this project merges results and cuts releases.
Each session owns its area and stays out of the others'. Read `docs/PROJECT_MAP.md` first. Rules for everyone: `CLAUDE.md`.

## Structure
| Session | Owns | Must not touch |
|---|---|---|
| **Main** (outside this project) | coordination, release flow; keeps `docs/PROJECT_MAP.md`, this file and patch numbers; alone merges into `t4-us` and `patches\` and cuts releases | private remote pushes (owner does these by hand) |
| **T4** | game runtime (`tekken4_overrides.cpp`, `_unlock_`, `_perf2_`), picture, sound, input, performance; netplay + online (`tekken4_net.*`, `_rollback_`, `lobby\`, rollback patches, `SERVER_HANDOFF_T4.md`); `tools\build_game*`, toolchain, release packaging, `docs/RELEASE_PLAN_T4.md`, `START_HIER.txt`; `launcher\t4core.py` interface | OpenRecomp-FGC UI; the server; Main's merges and releases |
| **Launcher** (OpenRecomp-FGC, separate project) | the one launcher for T5DR, T4 and future games; PySide6 + QML, controller first; `adapters/t4.py` | T4 runtime and switches; unannounced T4 interface changes |
| **Server** (outside this project) | prepares the T4 lobby instance from `SERVER_HANDOFF_T4.md`; goes live only when T4 plays online | T4 source and Main's merges |

The owner chose [OpenRecomp-FGC](https://github.com/TheWishin/OpenRecomp-FGC) as the one launcher. It loads
`launcher\t4core.py` from a T4 install at run time. T4's own Tk launcher in `launcher\` stays until each part has moved.
`t4core.py` is now an interface: changing its functions breaks OpenRecomp-FGC's `adapters/t4.py`, so announce changes first.

The launcher talks to the game **only through env switches and files**: the settings table in `docs/GRAPHICS.md`, the
build through `tools\build_game.ps1`, netplay through `TEKKEN4_NET*` (`docs/LOBBY.md`). A new option = the T4 session adds and
documents the switch in `docs/GRAPHICS.md`, then the launcher session adds the control.

## Open work by area
**Launcher (in OpenRecomp-FGC)**
- Move each part of the T4 Tk launcher into OpenRecomp-FGC.
- Real `.exe` starter, updater and shared Online integration. The standalone Tk Host/Join controls exist but have not been run here. The Tk BUILD GAME tab is only dry-run tested; `tools\build_game.ps1` reached a fight through grouped `-Steps` runs on a developer PC (`docs/E2E_BUILD.md`), not a verified single invocation or clean-PC setup.
- Settings still missing in the T4 Tk UI: AA levels, HUD sharp, anisotropic filtering, run-ahead.

**T4: Game**
- Intro music still sounds rough to the user (0 gaps, in sync, decoder and channel layout verified; the track is hot,
  gain now 0.7). Needs a comparison with PCSX2/a real PS2 by the user. Tiny hitches at boot and char select -> loading.
- Bright speckles on the beach sand at high resolution. Run-ahead is too slow to enable (43-53 fps).
- Fight stays 60 fps only without background load: measure on a quiet PC.

**T4: Netplay + Online**
- Never tested on two PCs or a real WAN: next step, needs the user + a second PC (`tools\net_play.ps1`, `docs/ROLLBACK_PHASE3.md`
  section 5). `docs\rollback\net_build.cmd` uses the sibling `tekken4-fork-net` by default; override with
  `TEKKEN4_SRC` / `TEKKEN4_BUILD_DIR` (section 4).
- Lobby: game-level test through a local lobby (`tools\net_lobby_pair.ps1`, `docs/LOBBY.md`) is pending. `SERVER_HANDOFF_T4.md`
  exists; the Server session prepares the T4 lobby instance, which goes live only when T4 plays online. Game-side result file (needed for ranked), direct fight.
- Later, as T5DR: replays, spectating, training rooms, leaderboard.

**T4: Release packaging (Main cuts releases)**
- Decide option B (compiler in the zip, MSVC libs fetched on the player's PC) or A (game code as a DLL): recommended B first,
  then A. Name and channel: proposed "Tekken 4 Online" with releases in the Swiss repo (owner's decision).
- Skip extracting the 2.7 GB DATA.BIN? Prebuilt `ps2_recomp.exe`? Release build flags, signing: see `docs/RELEASE_PLAN_T4.md`.

## Agents
Spawn subagents only when the user allows it; every one needs the isolation block below.
| Role | Model | Use for |
|---|---|---|
| Runtime work | default (Opus) | renderer, netplay, scheduler: anything that needs real debugging |
| Tooling, launcher, test runs | Sonnet | scripts, UI, E2E runs, reverse-engineering with clear start points |
| Read-only research | Sonnet | "how does T5DR do X", plans |

An outside coding agent may work on a clean copy of this source without game data. It never commits or pushes.
Claude reviews, tests, carries the change over and commits. The isolation block below is for runtime agents in the
maintainer's worktrees, not outside clean-copy agents.

Isolation block for runtime agents (used by about a dozen agents, up to 7 at once):
- Own worktree `git -C D:\tekken4-fork-ps2recomp worktree add D:\tekken4-fork-<x> -b t4-<x> t4-us`, stage with `TEKKEN4_SRC` +
  `tools\stage_generated.cmd`, build with `TEKKEN4_BUILD_DIR=<x>` + `tools\build_runtime.cmd`.
- Commit in that branch; export `format-patch` against `t4-us` into `docs\<x>\patches\`; do not commit in `D:\tekken4-us`; only the
  coordinating session merges (cherry-pick onto `t4-us`, patch into `patches\`, commit).
- One writer per file in `D:\tekken4-us\runtime`. New override files stay out of `runtime\` until they build everywhere
  (`stage_generated.cmd` copies every `*_overrides.cpp` into all trees).

## Start prompts
- **T4:** "Read CLAUDE.md, docs/PROJECT_MAP.md, docs/SESSIONS.md, top of docs/status.md. You are the one T4 session for game, netplay + online and release packaging. For netplay read docs/ROLLBACK_PHASE3B.md and docs/LOBBY.md; for packaging read docs/RELEASE_PLAN_T4.md and docs/E2E_BUILD.md. Launcher work is in OpenRecomp-FGC; announce t4core.py function changes first. Main outside this project alone merges into t4-us and patches and cuts releases. Goal: <...>."
- **Outside coding agent:** "Read AGENTS.md first, then docs/PROJECT_MAP.md and docs/SESSIONS.md. Work only in this clean source copy, without game data. Never commit or push. Claude reviews, tests, carries changes over and commits. Goal: <...>."
