# Rollback and movies / scene changes (Tekken 4 online)

Finding (widescreen round, `D:\tekken4-wide` docs/WIDESCREEN.md "movie-start rollback failure"): with both peers at 4:3, no
auto-VS, the host pressing Start on the title at frame 1201 (input delay 0, NET_SIM lat=75 jitter=5 loss=3 per side, rollback
from frame 600), the peers matched at 1200 and then differed from 1230 on (RAM/IOP/EE-cycle).

## What it really is

Reproduced on this tree (t4-int-prep, build `00bf3c0dd94fc2da`), `TEKKEN4_NET_MOVIE_GUARD=0`: run `mv-title-off`, first
mismatch at 1230, 26 of 66 sampled hashes differ, 8 rollbacks / 43 re-simulated frames on the joiner. The scene record
(`0x357d38`) shows the run is on the title (scene 8) until the press; scene 1 at 1224, MODE SELECT (2) at 1225. So the
peer that did not know the press ran 1201..1205 on a prediction (no press), received the press, rolled back and
**re-simulated the title -> MODE SELECT scene change**. A scene change that starts inside a re-simulation is not equal to the live
one (the scene loader, CD streams and the movie/attract machinery live partly outside the snapshot: IOP/streaming state, timers).
The same holds for a movie start (title -> attract, Story prologue, ...): they are scene changes too.

Lockstep never has this problem (the whole boot, the intro movie and the title ran in lockstep in every pair so far).

## Can the online flow reach a movie?

Normal flow: boot, logo, intro movie, title, MODE SELECT, the first-boot prompt are walked by the host's pad in
**lockstep** (auto VS); rollback starts at VS select (scene 7, game type 3) at the earliest at frame 600. From there the flow is
select (7) -> fight (4, type 3) -> select (7) ... Scene log of the ranked local-lobby sets (`NETSCENE` lines, both PCs, both
games): `0 -> 5 -> 2 -> 7 (f=241) -> 4 (f=1949)` and never another scene, no movie.
Scripted exit attempts from the select screen (Circle, Triangle, Select, runs `mv-story-on`, `mv-story2-on`) did not leave scene 7.
So a normal online match cannot reach a movie. It *can* in two cases: the auto-VS walk times out
(`NETAUTO_VS timeout`, the players take over at the title/menus, rollback active), and `TEKKEN4_NET_AUTO_VS=0` sessions
(test scripts, direct IP). Both end up in title / MODE SELECT / attract / Story, i.e. the failing situation above.

## Fix: the movie guard (default on)

`npMovieGuard` (runtime/tekken4_rollback_overrides.cpp), at every **live** boundary reads scene, requested scene and game
type: rollback is only used in the online VS flow (scene 7 or 4 with game type 3, requested scene none/7/4). In any other
scene, and for 8 frames after the last one, the boundary runs as **lockstep** (`need = f + 1`: every input confirmed, no
prediction, therefore no rollback can start a scene change; mispredictions made before the window are still scanned and rolled
back before the next frame, which cannot reach the new scene). Log lines: `NETSCENE` on every change, `NETGUARD lockstep from f=`
at the start of a window; frames in the window show phase `L` in `rb_frames.log`. `TEKKEN4_NET_MOVIE_GUARD=0` switches it off (only
to reproduce the finding). The input delay is unchanged (the window just waits for the peer's input); a lockstep window at a high round
trip is slow, which only matters for menus that the online product does not use.

No game state changes, no HELLO change (both PCs decide on their own state; a PC without the guard would still desync alone,
which the hash check would show).

## Proof

See docs/RELEASE_GATE_0.1.1.md "Movie guard" for the run table (paths under `logs/release-gate/`, harness
`build/release-gate/run_movie_pair.py`, unit check `tools/test_movie_guard.py`).
