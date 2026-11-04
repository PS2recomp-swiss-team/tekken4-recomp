# Tekken 4: match result from the game (SLUS-20328 v1.00)

2026-11-04. The online game now writes the match result itself: winner, round score, both fighters, stage, the
rounds (KO or time-out), the deciding frame and the state hash both games compared there. The lobby client reports
it with source `game`; the player's manual answer stays as the fallback. Code: `runtime/tekken4_match_state.h`
(reads the state), `runtime/tekken4_online_result.h` (the file), the hooks in `runtime/tekken4_rollback_overrides.cpp`.

Everything here is read only: no guest memory is written, so the simulation is unchanged (rollback and lockstep pairs
keep 0 mismatching hashes; the build id changes only because the code changed).

## Addresses (physical RDRAM, US v1.00 only) and their evidence

Found with offline scripted fights (`TEKKEN4_RB_MODE=measure`, both pads scripted, RAM dumps every 60-120 frames,
known outcomes) and then confirmed in the lifted code (the writers named below). Runs and dumps stay local
(they hold game memory); the notes are in the coordinator's `T4_RESULT.md`.

| Field | Address | Encoding | Writers / readers (US) | Evidence |
|---|---|---|---|---|
| Player objects | table `0x2a9420` = {`0x2a95b0` P1, `0x2aa4d0` P2} | pointers, stride 0xF20 | built by FUN_00198a68 (+0x3C side 0/1, +0x3E slot) | constant in every run |
| Health | player +0x6BC | s32, 16.16 fixed, 165.0 full | per-frame round logic FUN_001bcb08 (KO when 0), judge FUN_001bbe70 | hits lower it in steps; reset each round; handicap changes the full value |
| Round wins | player +0x8E | s16 | FUN_001bbe70: `+1` to the winner; equal health at time-out: `+1` to both | 0/1/2 per round in every run; draw rounds 1-1, 2-2 |
| Last round | player +0x90 | s16, 1 won / -1 lost | FUN_001bbe70 | |
| Rounds to win | `0x357d74` | u32, default 2 | read by FUN_00197b78 (match over when wins reach it) | |
| Round timer | `0x356064` (gp-0x6B0C) | s32 frames, 3600 = 60 s | decremented by FUN_001bcb08; 0 = time-out | counts 3600 -> 0 in time-out rounds |
| Round number | `0x356078` (gp-0x6AF8) | u32, 1-based | | |
| Match decision | `0x2a8bf8` +0x2C (+0x2D winner side, +0x2E loser side) | u8: 1 P1, 2 P2, 3 equal wins | FUN_001bbb28, called by FUN_001bbe70 in the frame the deciding round is counted | set in the same frame as the deciding +0x8E increment; stays until the next match |
| Fighters | select result `0x357f78` (P1 u16), `0x357f7a` (P2); model `0x357f80/82` = fighter * 4 + costume | ids 0..18 | FUN_0019d3e0 copies them into the player objects (+0x40 fighter, +0x48 model) at fight set-up | different picks per run; table below |
| Scene | `0x357d38` | 4 = VS fight, 7 = character select | scene manager FUN_001978d0 (found by agent t4autovs) | |
| Stage card | `0x36c490` | u32: 0..9 = the card, 10 = the random card | the stage select's cursor (profile block); left at the confirmed card for the fight | s2 sweep: 0 AIRPORT A ... 9 ARENA, 10 random; d1/s2 fights 0, e1 8 (UNDERGROUND), random-card fights 10 |

During the character select the player objects' +0x40 follows the cursor (the preview), so the fighters are taken
only where the player object and the select record agree (inside the fight).

## Fighter and stage ids

Fighters (select record and player +0x40; select-screen sweep with frame-exact pictures, the HUD name beside the
id, then fights): 0 Paul, 1 Law, 2 Lei, 3 King, 4 Yoshimitsu, 5 Nina, 6 Hwoarang, 7 Xiaoyu, 8 Christie, 9 Jin,
10 Julia, 11 Kuma, 12 Bryan, 13 Heihachi, 14 Kazuya, 15 Lee, 16 Steve, 17 Marduk, 18 Combot. (The cursor preview
does not change for Combot; 18 is proven by a fight with Combot picked.) The game's roster table at 0x30e100 has
the same 19 ids x 4 costumes. Panda, Eddy, Miharu and Violet are this game's alternate costumes of Kuma, Christie,
Xiaoyu and Lee: the id is the base fighter, the costume (0..3) is reported separately (`costumes`); which costume
index shows them is not mapped.

Stages: the card of the stage select, in the order of the game's stage-name table at 0x2c8748: 0 AIRPORT,
1 BUILDING, 2 MALL, 3 JUNGLE, 4 SHINJUKU, 5 BEACH, 6 LABORATORY, 7 PARKING AREA, 8 UNDERGROUND, 9 ARENA.
The random card (10) is reported as no stage (-1): the stage it loads was not found. The cards show "A" after
some names (a variant); the variant is not reported.

The lobby's `data/fighters.json` (`"fighter_ids": "game"`, `"stage_ids": "game"`) carries these ids.

## How a result is decided

1. Every boundary visit (live and re-simulated) samples the fields above into a ring keyed by frame; a rollback
   overwrites a mispredicted frame's sample with the corrected one.
2. Netplay walks the frames whose inputs are all confirmed (`min(remoteContig, frame)`, the same frames whose state
   hashes are compared) in order. Offline (measure/test modes) every frame is final at once.
3. A match starts at the first such frame in the fight scene with 0-0 wins and both fighters alive, after a frame
   that was not like that. A round ends where a side's wins change (time-out when the round timer is 0, else a
   KO); the match ends where a side's wins reach the rounds to win. Winner: more wins; equal wins = draw. The
   result is "proven" only when the game's own decision byte (+0x2C) says the same in that frame.
4. A match that leaves the fight scene before its end, or whose wins go back, is abandoned (no result).
5. The first match of the session is the lobby match. Its result is written to `TEKKEN4_NET_RESULT` once the state
   hash of the first hashed frame at or after the deciding frame has been compared with the peer's (or 10 s later,
   or when the session ends first). A KO that only a predicted input produced is never reported: a rollback
   corrects the sample before the frame is confirmed.

Log lines in `rb_frames.log`: `MATCH start`, `MATCH round`, `MATCHEND`, `MATCH abandoned`, `MATCHRESULT written`.

## Result file (schema `tekken4-online-session-v2`)

```
match                 the lobby's match id (TEKKEN4_NET_MATCH); a file of another match is never reported
match_result_proven   true only for a decided, consistent match
winner                0 = P1 (host), 1 = P2 (join), null = draw (read it only when match_result_proven)
draw, score           [P1 rounds, P2 rounds]
chars, costumes       game fighter ids [P1, P2] (0..18), costume 0..3
stage                 stage card 0..9, -1 = the random card / unknown
rounds                [{frame, winner, by: ko|time, health: [P1, P2]}]
match_start_frame, match_end_frame, frames, rounds_to_win, match_code
hash, hash_frame, hash_agreed   the compared state hash at the first hashed frame >= the deciding frame
desync, hashes_compared         the session's hash comparisons when the result was written
```

The session fields of v1 (`run_id`, `connected`, `local_slot`, `frame`, `final_hash`, `fps`, `reason`, ...) stay.
`lobby/t4lobby/t4game.py` `read_game_result()` reads it (the lobby's T4 client and the OpenRecomp T4 adapter).

## Not covered

- Double KO was not produced in the scripted runs (the judge code handles it like equal health: both get the round).
- A pause/quit to the select screen mid-match is reported as abandoned (no result) by construction; not run online.
