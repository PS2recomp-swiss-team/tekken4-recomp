# Session plan

The user runs one main session for the launcher and separate sessions below it for the game. Each session owns its area
and stays out of the others'. Read `docs/PROJECT_MAP.md` first. Rules for everyone: `CLAUDE.md`.

## Structure
| Session | Owns | Must not touch |
|---|---|---|
| **1. Main: Launcher** | `launcher\`, the shared launcher design, release flow; merges results, keeps `docs/PROJECT_MAP.md`, this file and the patch numbers | `runtime\`, `patches\` content (asks session 2/3) |
| **2. Game** | `runtime\tekken4_overrides.cpp`, `_unlock_`, `_perf2_`, patches for picture, sound, input, performance | `launcher\`, netplay files |
| **3. Netplay + Online** | `runtime\tekken4_net.*`, `_rollback_`, `lobby\`, rollback patches, `SERVER_HANDOFF_T4.md` | picture and sound code; the VPS |
| **4. Release** (when session 1 asks) | `tools\build_game*`, toolchain, packaging, `docs/RELEASE_PLAN_T4.md`, `START_HIER.txt` | game code |

The launcher talks to the game **only through env switches and files**: the settings table in `docs/GRAPHICS.md`, the
build through `tools\build_game.ps1`, netplay through `TEKKEN4_NET*` (`docs/LOBBY.md`). A new option = session 2/3 adds and
documents the switch, session 1 adds the control.

## Open work by session
**1. Launcher**
- One launcher for T5DR + T4 + future games: a shell with per-game modules (build, play, settings, online). `launcher\t4core.py`
  is the first module. The T5DR launcher lives in `C:\T5DROnline\launcher` and belongs to the T5DR side: agree the plan with
  the owner; other sessions already work on launcher design there ("Launcher-Redesign", "T5DR Online launcher design").
- Real `.exe` starter, updater, Online tab (today a placeholder). The BUILD GAME tab is only dry-run tested (`toolsuild_game.ps1` itself ran end to end).
- Settings still missing in the UI: AA levels, HUD sharp, anisotropic filtering, run-ahead.

**2. Game**
- Intro music still sounds rough to the user (0 gaps, in sync, decoder and channel layout verified; the track is hot,
  gain now 0.7). Needs a comparison with PCSX2/a real PS2 by the user. Tiny hitches at boot and char select -> loading.
- Bright speckles on the beach sand at high resolution. Run-ahead is too slow to enable (43-53 fps).
- Fight stays 60 fps only without background load: measure on a quiet PC.

**3. Netplay + Online**
- Never tested on two PCs or a real WAN: next step, needs the user + a second PC (`tools\net_play.ps1`, `docs/ROLLBACK_PHASE3.md`
  section 5). `docs\rollback\net_build.cmd` has fixed `D:\` paths.
- Lobby: game-level test through a local lobby (`tools\net_lobby_pair.ps1`, `docs/LOBBY.md`) is pending. The server is set up by the
  T5DR coordinator after T5DR 1.1.9 (`SERVER_HANDOFF_T4.md`). Game-side result file (needed for ranked), direct fight.
- Later, as T5DR: replays, spectating, training rooms, leaderboard.

**4. Release**
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

Isolation block for runtime agents (used by about a dozen agents, up to 7 at once):
- Own worktree `git -C D:\tekken4-fork-ps2recomp worktree add D:\tekken4-fork-<x> -b t4-<x> t4-us`, stage with `TEKKEN4_SRC` +
  `tools\stage_generated.cmd`, build with `TEKKEN4_BUILD_DIR=<x>` + `tools\build_runtime.cmd`.
- Commit in that branch; export `format-patch` against `t4-us` into `docs\<x>\patches\`; do not commit in `D:\tekken4-us`; only the
  coordinating session merges (cherry-pick onto `t4-us`, patch into `patches\`, commit).
- One writer per file in `D:\tekken4-us\runtime`. New override files stay out of `runtime\` until they build everywhere
  (`stage_generated.cmd` copies every `*_overrides.cpp` into all trees).

## Start prompts
- **Launcher:** "Read CLAUDE.md, docs/PROJECT_MAP.md, docs/SESSIONS.md (session 1). You are the main launcher session of the Tekken 4 port in D:\tekken4-us. Goal: <...>."
- **Game:** "Read CLAUDE.md, docs/PROJECT_MAP.md, docs/SESSIONS.md (session 2), top of docs/status.md. You own the game runtime. Goal: <...>."
- **Netplay:** "Read CLAUDE.md, docs/PROJECT_MAP.md, docs/SESSIONS.md (session 3), docs/ROLLBACK_PHASE3B.md, docs/LOBBY.md. Goal: <...>."
- **Release:** "Read CLAUDE.md, docs/PROJECT_MAP.md, docs/SESSIONS.md (session 4), docs/RELEASE_PLAN_T4.md, docs/E2E_BUILD.md. Goal: <...>."
