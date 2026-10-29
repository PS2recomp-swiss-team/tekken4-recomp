# stage-pick notes

## Finding 1 — the printed "laboratory" was not a card (2026-10-29)

stage_card.py always prints the nearest of the 10 refs. A real settled card is dist<=14.4 and gap to 2nd >=37 (sweep + airport_hash1 + iopdump1). gap<5 means the screen is not a card.

| frame | mean r/g/b | nearest | dist | gap | what it is |
| music_searchfile1/frame_59s.bmp | 26.5/35.2/35.1 | laboratory | 51.7 | 2.4 | black load, not a card |
| music_port1/frame_59s.bmp | 16.1/21.6/21.5 | laboratory | 59.9 | 2.5 | black load, not a card |
| music_searchfile2/frame_59s.bmp | 82.6/91.4/89.6 | airport | 26.6 | 16.5 | card mid-slide (name drawn twice) |
| music_port2/frame_59s.bmp | 116.9/123.4/120.1 | airport | 11.5 | 37.2 | settled AIRPORT card |
| music_port_nosound/frame_59s.bmp | 117.5/123.9/120.5 | airport | 11.5 | 37.2 | settled AIRPORT card |
| airport_hash1/frame_59s.bmp | 118.9/125.6/121.9 | airport | 9.8 | 37.1 | settled AIRPORT card |
| sweep-airport/frame_59s.bmp | 117.5/123.8/120.5 | airport | 11.7 | 37.1 | settled AIRPORT card |
| sweep-laboratory/frame_62s.bmp | 112.9/120.0/117.0 | laboratory | 3.0 | 41.9 | settled LABORATORY card |
| hud_claude3/frame_59s.bmp | 50.8/90.1/112.0 | airport | 47.0 | 4.2 | intro movie (still playing) |
| hud_claude3/frame_85s.bmp | 38.1/38.0/42.0 | parking | 65.3 | 3.4 | difficulty screen |
| iopdump1/frame_46s.bmp | 134.3/132.1/131.0 | parking | 61.5 | 0.4 | 1P character select, no card |
| iopdump1/frame_51s.bmp | 137.0/121.3/132.5 | parking | 61.5 | 0.4 | CPU character select, no card |
| iopdump1/frame_59s.bmp | 117.2/123.9/120.7 | airport | 10.0 | 37.3 | settled AIRPORT card |
| iopdump1/frame_60s.bmp | 0/0/0 | laboratory | 77.0 | 3.1 | black frame right after confirm |

Fight frames (frame_stats --diff vs sweep fight frames, thr 16):
- music_searchfile1/frame_105s.bmp closest airport pct_diff 11.441 psnr 23.62; next shinjuku 75.421. Kazuya vs Yoshimitsu on the airport. This run did NOT fight on laboratory.
- music_port_nosound/frame_90s.bmp closest airport 11.02 psnr 23.82; next shinjuku 75.962.
- hud_claude3/frame_85s.bmp vs every fight ref pct_diff >=88. Not a fight. Perf: 30 fps sec 35-69 (movie), then 60 fps GS 5 ms (menu). Frame 85 is SET GAME DIFFICULTY.

music_port1 has shot_105s.png and no frame_105s.bmp (shot at the run's last second is not written). Fight stage from a game frame: unknown. The laboratory label is the same false nearest-neighbor as searchfile1.

Cause of the bad prints: fixed Right at 57 s and Cross at 60 s, check frame at 59 s. On the slow pair the stage card was not on screen yet (black). stage_card.py still named a stage. Keys at 57/60 hit that black, so they did not move a card the script could see. searchfile1 still reached the airport fight (random card was airport, or the card appeared in the 59-60 s gap and the timed keys happened to land). The timed plan cannot tell those apart. hud_claude3 is the earlier-screen version of the same bug: movie still up at 59 s, so every later timed key missed; at 85 s the run is on difficulty.

The card UI is not its own screen. After both fighters are locked, the character-select screen ("CHOOSE YOUR FIGHTER") shows a corner card (crop box 20,290-200,410) plus a countdown (15 at a settled airport frame, 12 after four Lefts on laboratory, 14 during the slide). Left/Right changes that card. Before the card exists, Left/Right moves the character cursor (frame_46 timer 27, frame_51 timer 23, no card). Accept a card only when dist<=22 and gap>=30. Press only then.

Random slot: the opening card art is a real stage, and confirming it picks that stage. Right from the opening slot goes to airport even when the art is some other stage (run_fixed_fight.ps1 header). One press then re-read still reaches the target; a precomputed count from the art does not, when the art is not the slot.

On-demand shots: request file polled from the frameshot thread every 15 ms (same copyLatched path as TEKKEN4_FRAME_SHOTS). Not from UploadFrame: a per-frame disk stat on H: (USB HDD) would hitch the present. TEKKEN4_FRAME_SHOT_POLL=1, default off. Timed TEKKEN4_FRAME_SHOTS unchanged.

Protocol (cwd = run dir): host writes `frame_req.id` as "<id> <id>\n". Override, when both numbers match and differ from the last served id, writes `frame_req_<id8>.bmp` then `frame_req_<id8>.ok`. No deletes.

Picker (run_capture -StagePick, used by run_fixed_fight): after the last timed key (CPU Cross), poll until a settled card, press the shorter ring direction, re-read, Cross when the art is the target, Start 11 s later. Fail exit 2 if the card never appears, shots time out, or 12 presses miss. Banner line kept. Card line kept, printed from the settled frame: "stage card before the confirm: <index> <name> <dist> (index name distance)".

TEKKEN4_FIXED_LATE=<seconds> delays only the CPU-confirm Cross so the card opens after the old 57 s mark. TEKKEN4_IOP_IDLE_SKIP=0 is the documented IOP-cache-off slowdown (docs/status.md IOP-SCHED-3, ~3%).

Ring, Right order: arena airport building mall_a mall_b shinjuku beach laboratory parking underground.

## Probe logs/grok/stagepick-probe (airport, Until 90, TEKKEN4_SOUND=1)

Waited on run lock 128772 (logs/scale1), then the card was already up at 54.3 s. Art flipped mall_b (dist 6.7 gap 40.9) -> shinjuku (1.9/51.7) -> mall_b (12.7/33.7, two reads). That is the random slot: Left once from it is arena, not Left-from-mall_b. Pressed Left at 56.2, next card arena dist 0.2 gap 62.8. Right at 57.6 did not move it (still arena at 59.1); Right again at 59.4, airport dist 1.4 then 11.7. Confirmed at 61.0 s, 3 presses. Start at 72.3 s.
Card line: "stage card before the confirm: 1 airport 11.7 (index name distance)".
frame_90s.bmp mean 74.3/71.2/80.3 black 0.27%. Diff vs sweep fight frames: airport 8.4% psnr 26.19, next shinjuku 74.4%. Fight is airport.
Process ignored CloseMainWindow (pre-existing 8 s then Kill). ran 100.6 s. Exit 0.

## stagepick-1 failed the fight check

Same navigation (mall_b art, Left -> arena, Right -> airport). Card line "1 airport 0.7". frame_req_00000006 is the airport card, timer 17. frame_90s.bmp is the laboratory fight: mean 91.3/93.7/113.4, pct_diff 39.8 vs sweep laboratory, 84.4 vs arena (airport not in the top 4). Cross at 58.1 s, 3.8 s after the first settled card. The probe Cross at 61.0 s (~7 s after the card) loaded airport. Early Cross commits the random stage, not the art. Hold Cross until 7 s after the first settled card.

## probe2 — 7 s hold retest, airport fight (logs/grok/stagepick-probe2)

Exit 0. mall_b stable 2 at 54.8 s (cardSeenAt). Left 55.2 -> arena. Right 56.6 -> underground (one step off the ring; not edited). Right 58.0 -> airport, stable 2 at 59.0. Hold lines 4.2 s through 6.6 s on the card UI. Card line "1 airport 2.0". Cross 62.5 s, 7.7 s after cardSeenAt, 3 presses. Start 73.8 s.
python -I logs/grok/stage_pick_check.py logs/grok/stagepick-probe2 airport 90 logs/grok/stagepick-probe2.txt exit 0.
frame_90 mean 74.3/71.2/80.3 black 0.30%. airport pct_diff 20.5 psnr 21.3, next shinjuku 78.3. check ok.
Same airport-fight mean as stagepick-probe frame_90 (74.3/71.2/80.3). stagepick-1 laboratory mean was 91.3/93.7/113.4. Cross at 3.8 s after the card loaded laboratory; Cross at 7.7 s after the card loaded airport.
