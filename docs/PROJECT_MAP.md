# Project map: where everything is

Start here, then `docs/SESSIONS.md` (who works on what). Current state and log: `docs/status.md` (newest entry on top).

In this clean source copy, `AGENTS.md` controls work. The machine paths below describe the maintainer's
checkout, not folders to access or prerequisites for players. Historical test logs and game data are absent.

## Goal
A native PC port of Tekken 4 (US, SLUS-20328) that anyone can play: download, point it at your own ISO, build, play,
then online with rollback as good as T5DR Online. No BIOS, no game data shipped. The owner chose
**OpenRecomp-FGC as the one launcher for T5DR, T4 and future games**: a separate project, PySide6 + QML, controller first.

One T4 session covers game, netplay + online and release packaging. Launcher work is outside T4. One coordinating Main
session outside this project alone merges into `t4-us` and `patches\` and cuts releases. The owner pushes to the chosen
remote by hand after checking its visibility. An outside coding agent may work on a clean source copy without game data, but never commits or pushes;
Claude reviews, tests, carries the change over and commits.

## Repositories
| Repo | Visibility | Use |
|---|---|---|
| `PS2recomp-swiss-team/tekken4-recomp` (remote `swiss`) | do not assume private; `docs/status.md` records public visibility on 2026-10-30 | historical working remote, branch `us-slus20328`; owner must verify visibility before publication |
| `Lautreck/tekken4-recomp` (remote `origin`) | **PUBLIC** | the colleague's PAL line (`master`). Do not push new work; **never T5DR-derived code** |
| `ran-j/PS2Recomp` | public upstream | pinned at `eb8688b`; our changes are `patches/*.patch`, not pushed anywhere |
| [TheWishin/OpenRecomp-FGC](https://github.com/TheWishin/OpenRecomp-FGC) | not recorded here | separate project; the one launcher; loads `launcher\t4core.py` from a T4 install at run time |
| `TheWishin/T5DROnline-Source` (local `C:\T5DROnline`) | private | the T5DR project: read-only reference from T4 sessions |

## Folders on the user's PC
| Path | What |
|---|---|
| `D:\tekken4-us` | **The US project: work here.** Worktree of branch `us-slus20328`, with `game\`, `external\`, `ghidra\`, `logs\`, `generated\`, the ISO |
| `D:\tekken4-recomp` | main checkout on `master` (PAL), no game data; leave it alone |
| `D:\tekken4-fork-ps2recomp` | PS2Recomp, branch `t4-us` = `eb8688b` + the 78 patches in `patches\` (01-87 with gaps) as commits; the default build tree (`out\runtime`) |
| `D:\tekken4-fork-{gfx,input,movie,music,net,net2,perf,rb,smooth,unlock}` | finished agents' worktrees, all merged into `t4-us`, safe to remove (user decides). `net2` has the current netplay build (`out\net`) |
| `D:\t4-e2e`, `D:\t4-kollege-test`, `D:\t4-stackcheck*` | test folders of the player build (5.4 GB each for the first two), safe to remove (user decides) |
| `dist\T4-Mini-Release-2026-10-30` | the user's local test build (Tekken4.cmd, Launcher.cmd). Contains the recompiled exe: **never share or commit** |
| `dist\T4-Mini-Release-Kollege-2026-10-30.zip` | shareable mini release: source + tools only, no game data; `START_HIER.txt` is its guide |
| `C:\T5DROnline` | T5DR project: **read-only** from T4 sessions |

## In the repo (D:\tekken4-us)
| Path | Area | What |
|---|---|---|
| `launcher\` | T4 interface + existing launcher | `t4_launcher.pyw` (Tk UI) stays until each part has moved to OpenRecomp-FGC; `t4core.py` (settings, env, build, run) is the interface loaded at run time. Written new, no T5DR code |
| `lobby\` (absent from this copy) | Online | historical private T5DR lobby adaptation (`t4lobby`, `t4game.py`); do not add it here or assume any remote is private |
| `tools\build_game.ps1`, `iso_extract.py`, `vu1_micro_from_elf.py` | Build | ISO -> runnable game in one step |
| `tools\*_portable*`, `toolchain_env.cmd`, `t4_toolchain_clangcl.cmake` | Release | prototype: build without Visual Studio |
| `config\` | Game | US function map, jump tables, recompiler TOML (no game code) |
| `runtime\*.cpp` | Game | overrides staged into the runtime: `tekken4_overrides.cpp` (sound, movie, video mode), `_unlock_`, `_perf2_`, `_rollback_`, `tekken4_net.*`, `_frameshot_`, `_testseed_`, `_profiler_`. `runtime\pal\` = PAL-only camera log, not built |
| `patches\NN-*.patch` | Game | changes to PS2Recomp, applied in **name order** |
| `tools\run_capture.ps1`, `perf_*`, `gfx_*`, `pad_lag.ps1`, `net_pair.ps1`, `net_play.ps1`, `us_site.py`, `ghidra_*` | Dev | test, measure, reverse-engineer |
| `tools\make_test_zip.ps1`, `test_zip.py`, `collect_test_logs.ps1` | Sunday test | scanned source-only test zip; selected netplay diagnostics and PC facts to return |
| `tools\net_play.ps1`, `net_preflight.ps1` | Sunday test | peer identity comparison, UDP preflight and instrumented manual play; still needs two-PC validation |
| `tools\grok_*`, `docs\ai\`, `pcsx2_*`, `tools\ai\` | Legacy | the colleague's Grok/PCSX2 workflow on his PC, not set up here |

`launcher\t4core.py` is an interface: changing its functions breaks OpenRecomp-FGC's `adapters/t4.py`, so announce changes
first. For a new game option, the T4 session adds and documents the switch in `docs/GRAPHICS.md`, then the launcher session
adds the control.

## Docs
| Doc | Topic |
|---|---|
| `docs/SESSIONS.md` | session plan, ownership, start prompts, agent roles |
| `docs/status.md` | log, newest first (older parts describe PAL and old paths) |
| `docs/GRAPHICS.md` | resolution steps, AA, progressive, fullscreen, settings table for the launcher |
| `docs/INPUT.md` | gamepad, presenter, run-ahead, input lag |
| `docs/PERF.md` | stage table, smoothness |
| `docs/MUSIC_FIX.md` | BGM, voices, intro movie audio |
| `docs/ROLLBACK_PLAN.md`, `ROLLBACK_PHASE01.md`, `PHASE2.md`, `PHASE3.md`, `PHASE3B.md` | rollback + netplay |
| `docs/DIRECTFIGHT_T4.md` | opt-in automatic Versus boot input, save/menu limits, state discovery and later direct-fight plan |
| `docs/LOBBY.md`, `SERVER_HANDOFF_T4.md` | lobby integration, existing handoff to the Server session; it prepares the T4 lobby instance, which goes live only when T4 plays online |
| `docs/RELEASE_PLAN_T4.md`, `E2E_BUILD.md`, `START_HIER.txt` | release options, player build test, tester guide |
| `TEST_ONLINE_DE.txt` | short German two-PC internet test guide, router/VPN choices, errors and return logs |

## Runtime switches (env)
`TEKKEN4_INTERNAL_RES`, `TEKKEN4_AA`, `TEKKEN4_ANISO`, `TEKKEN4_HUD`, `TEKKEN4_WINDOW_FILTER`, `TEKKEN4_FULLSCREEN` (1 | exclusive), `TEKKEN4_PROGRESSIVE`,
`TEKKEN4_UNLOCK_ALL`, `TEKKEN4_SOUND`, `TEKKEN4_ISO`, `TEKKEN4_MOVIE_GAIN`, `TEKKEN4_AUDIO_BUFFER_MS`, `TEKKEN4_RUNAHEAD`, `TEKKEN4_RB_MODE`, `TEKKEN4_NET*` (including `TEKKEN4_NET_AUTO_VS`, default on: boot straight to VS select, its bound `TEKKEN4_NET_AUTO_VS_END`, and the online card `TEKKEN4_NET_CARD`; see `docs/DIRECTFIGHT_T4.md`),
`PS2X_DEBUG_PANEL`, `PS2X_PERF_STATS`, `PS2X_GS_HW_SCALE` (raw override, wins over the resolution step). Details in the docs above.

Rollback switch results and the exact Sunday two-PC settings are in `docs/ROLLBACK_ASYMMETRY.md`;
the player commands are also in `TEST_ONLINE_DE.txt`, which ships in the test zip.
`TEKKEN4_NET_REFRESH_RC=1` is a new default-off fix: refresh contiguous remote-input progress after
time sync before the prediction-window check and late-input scan. It was not built or run here and
stays off for Sunday. Runtime changes ship through the existing recursive `runtime/` source catalog.
Sunday uses `TEKKEN4_NET_COALESCE=1` for the measured roughly 48% packet/payload reduction and
`TEKKEN4_NET_DIAG=1` for observation. Coalescing has not been shown to cure one-sided stalls on two PCs;
follow the main run with a matched coalescing-off reference. Other experimental switches stay off.
