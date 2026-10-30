# Project map: where everything is

Start here, then `docs/SESSIONS.md` (who works on what). Current state and log: `docs/status.md` (newest entry on top).

## Goal
A native PC port of Tekken 4 (US, SLUS-20328) that anyone can play: download, point it at your own ISO, build, play,
then online with rollback as good as T5DR Online. No BIOS, no game data shipped. Long term: **one launcher for T5DR, T4
and future games**.

## Repositories
| Repo | Visibility | Use |
|---|---|---|
| `PS2recomp-swiss-team/tekken4-recomp` (remote `swiss`) | **private** | where new work goes, branch `us-slus20328` |
| `Lautreck/tekken4-recomp` (remote `origin`) | **PUBLIC** | the colleague's PAL line (`master`). Do not push new work; **never T5DR-derived code** |
| `ran-j/PS2Recomp` | public upstream | pinned at `eb8688b`; our changes are `patches/*.patch`, not pushed anywhere |
| `TheWishin/T5DROnline-Source` (local `C:\T5DROnline`) | private | the T5DR project: read-only reference from T4 sessions |

## Folders on the user's PC
| Path | What |
|---|---|
| `D:\tekken4-us` | **The US project: work here.** Worktree of branch `us-slus20328`, with `game\`, `external\`, `ghidra\`, `logs\`, `generated\`, the ISO |
| `D:\tekken4-recomp` | main checkout on `master` (PAL), no game data; leave it alone |
| `D:\tekken4-fork-ps2recomp` | PS2Recomp, branch `t4-us` = `eb8688b` + the 77 patches in `patches\` (01-86 with gaps) as commits; the default build tree (`out\runtime`) |
| `D:\tekken4-fork-{gfx,input,movie,music,net,net2,perf,rb,smooth,unlock}` | finished agents' worktrees, all merged into `t4-us`, safe to remove (user decides). `net2` has the current netplay build (`out\net`) |
| `D:\t4-e2e`, `D:\t4-kollege-test`, `D:\t4-stackcheck*` | test folders of the player build (5.4 GB each for the first two), safe to remove (user decides) |
| `dist\T4-Mini-Release-2026-10-30` | the user's local test build (Tekken4.cmd, Launcher.cmd). Contains the recompiled exe: **never share or commit** |
| `dist\T4-Mini-Release-Kollege-2026-10-30.zip` | shareable mini release: source + tools only, no game data; `START_HIER.txt` is its guide |
| `C:\T5DROnline` | T5DR project: **read-only** from T4 sessions |

## In the repo (D:\tekken4-us)
| Path | Area | What |
|---|---|---|
| `launcher\` | Launcher | `t4_launcher.pyw` (Tk UI), `t4core.py` (settings, env, build, run). Written new, no T5DR code |
| `lobby\` (git-excluded, local only) | Online | copy of the private T5DR lobby adapted to T4 (`t4lobby`, `t4game.py`). May go to the Swiss repo on its own branch; never to `origin` |
| `tools\build_game.ps1`, `iso_extract.py`, `vu1_micro_from_elf.py` | Build | ISO -> runnable game in one step |
| `tools\*_portable*`, `toolchain_env.cmd`, `t4_toolchain_clangcl.cmake` | Release | prototype: build without Visual Studio |
| `config\` | Game | US function map, jump tables, recompiler TOML (no game code) |
| `runtime\*.cpp` | Game | overrides staged into the runtime: `tekken4_overrides.cpp` (sound, movie, video mode), `_unlock_`, `_perf2_`, `_rollback_`, `tekken4_net.*`, `_frameshot_`, `_testseed_`, `_profiler_`. `runtime\pal\` = PAL-only camera log, not built |
| `patches\NN-*.patch` | Game | changes to PS2Recomp, applied in **name order** |
| `tools\run_capture.ps1`, `perf_*`, `gfx_*`, `pad_lag.ps1`, `net_pair.ps1`, `net_play.ps1`, `us_site.py`, `ghidra_*` | Dev | test, measure, reverse-engineer |
| `tools\grok_*`, `docs\ai\`, `pcsx2_*`, `tools\ai\` | Legacy | the colleague's Grok/PCSX2 workflow on his PC, not set up here |

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
| `docs/LOBBY.md`, `SERVER_HANDOFF_T4.md` | lobby integration, handoff to the T5DR coordinator |
| `docs/RELEASE_PLAN_T4.md`, `E2E_BUILD.md`, `START_HIER.txt` | release options, player build test, tester guide |

## Runtime switches (env)
`TEKKEN4_INTERNAL_RES`, `TEKKEN4_AA`, `TEKKEN4_ANISO`, `TEKKEN4_HUD`, `TEKKEN4_WINDOW_FILTER`, `TEKKEN4_FULLSCREEN` (1 | exclusive), `TEKKEN4_PROGRESSIVE`,
`TEKKEN4_UNLOCK_ALL`, `TEKKEN4_SOUND`, `TEKKEN4_ISO`, `TEKKEN4_MOVIE_GAIN`, `TEKKEN4_AUDIO_BUFFER_MS`, `TEKKEN4_RUNAHEAD`, `TEKKEN4_RB_MODE`, `TEKKEN4_NET*`,
`PS2X_DEBUG_PANEL`, `PS2X_PERF_STATS`, `PS2X_GS_HW_SCALE` (raw override, wins over the resolution step). Details in the docs above.
