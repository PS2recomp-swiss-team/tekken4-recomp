# menu-pick notes

## Finding 1 — screens that already exist as 640x448 frames

Guest frames are 640x448 (frameshot override). Older logs\user_path3 frames before the movie are 640x512 and are not refs.

Timed path that reached PRACTICE (logs/fixed_probe1 keys 40-43 Down, frame_43s): highlight is PRACTICE. Initial MODE SELECT row is STORY (logs/gl_screens1/frame_38s.bmp, Cross at 36, shot at 38, no Down yet).

Highlight text Y (orange band, x 20-280, count>=8), median:
story 92, arcade 116, team 164, survival 188, practice 212, training 236, tekken-force 260. Pitch 24. VS sits between arcade and team (not captured highlighted). 4 Downs from STORY land on PRACTICE, so Down skips VS.

Start-game (logs/gl_screens1/frame_14s.bmp): olive panel, default cursor is No. Yellow glyphs x 332-353 y 209-218.

Difficulty (logs/gl_screens1/frame_34s.bmp and logs/hud_claude3/frame_85s.bmp): same MODE SELECT header as the mode list (crop dist 0). MEDIUM highlight y 183-190. Squares column crop separates them: mode-vs-mode dist <=14, difficulty-vs-mode ~27 (logs/grok/menu_dist.py).

Fighter header crop (170,8)-(470,42): fighter self dist <=24, mode ~156.

1P select (logs/fixed_probe1/frame_46s.bmp, logs/iopdump1/frame_46s.bmp): Kazuya name bar, right side empty.
After the 1P Cross the CPU cursor is on XIAOYU (frame_49s), not Kazuya. One Up -> HWOARANG (frame_50s, frame_51s, iopdump frame_51s). The fixed-fight Right after that is the Yoshimitsu step. Name bars (left 0,360-250,410 and right 400,360-630,410) are pixel-stable across those frames. The corner stage card can cover the left bar before the CPU Cross (frame_52s left mean changed, right HWOARANG mean unchanged).

Movie frames (logs/grok/music-1/frame_25s.bmp, logs/hud_claude3/frame_59s.bmp) match none of the menu crops.

## Finding 2 — display menu capture

menupick-disp: keys 11 Down, 13 Cross, shots 9,12,15. frame_18s.bmp is absent (shot at the run's last second is not written). Display menu is 640x512 until PAL60 Cross; start-game and later are 640x448.

## Finding 3 — display rows, classifier, one-shot confirms (rechecked)

python -I logs\grok\menu_disp.py on menupick-disp:
- frame_9s.bmp 640x512 yellow n=170 x 244-422 y 293-306 cx 327 cy 299 (PAL50, detail=above)
- frame_12s.bmp 640x512 yellow n=154 x 244-422 y 320-333 cx 333 cy 326 (PAL60)
- frame_15s.bmp 640x448 yellow n=28 x 332-352 y 209-218 cx 339 cy 214 (Start game, No)

python -I tools\menu_screen.py --check exit 0, 23/23. Same list as the CHECK table (display above/pal60, startgame no, loading, difficulty medium, mode story/arcade/team/survival/practice/training/tekken, fighter 1p kazuya / cpu xiaoyu / cpu hwoarang, two movies).

luma() used to sample only the first quarter of the buffer (n = len//16 then range(0, n*4, 4)), which is the black band above the 512-tall panel, so frame_9 and frame_12 classified as loading. It now steps 16 bytes across the whole buffer.

run_fixed_fight.ps1 no longer passes timed menu keys. run_capture.ps1 -StagePick with zero keys starts phase=menu. Confirm Cross (display pal60, startgame yes, title, difficulty medium, mode practice) goes through Press-Confirm: same tag is not repeated for 2200 ms (fighter 1P Kazuya 4500 ms). Press-Menu also ignores a second press on the same signature for 1800 ms. Hwoarang Right is sent once (expectYoshi set only after padOk). A blank CPU name while expectYoshi is set is not sent Up; after 3 identical reads Save-YoshimitsuRef copies the bmp to logs\grok\menupick-yoshi.bmp and --make-refs writes name_yoshimitsu.raw. Parser.ParseFile on run_capture.ps1: PARSE_OK.

Yoshimitsu nameplate is still unseen. First fight run must capture it before the CPU Cross.

## Finding 4 — menupick-1 died on the CPU cursor (exit 2, 54.8 s)

Menus before the fighter screen worked on the first closed-loop run (logs/grok/menupick-1). Display above then pal60 (Down), startgame no then yes (Left, Cross), movie, difficulty medium (Cross), mode story-arcade-team-survival-practice (Down skips VS, Cross). 1P Kazuya at frame_req_00000061 (timer 28), one Cross (Press-Confirm; the screen stayed on CHOOSE YOUR FIGHTER for 26 s, so CPU was not locked).

CPU cursor is Kazuya, not Xiaoyu. frame_req_00000091 and frame_req_00000064 right name bar reads KAZUYA; pairwise right-bar dist between those and frame_req_00000085 is 9.1 (animation), vs Xiaoyu ref 25.6-28.9, vs Hwoarang ref 59-62 (logs/grok/menu_namedist.py). fighter_id did not rank Kazuya on the right bar (left ref is 250 px, right crop is 230 px), so side/char stayed blank and the step clock fired "menu step failed: fighter".

Grid (strategywiki Tekken 4 character select, matches the old Up-from-Xiaoyu = Hwoarang, Right = Yoshimitsu): Kazuya is directly under Xiaoyu, Xiaoyu under Hwoarang, Yoshimitsu is Right of Hwoarang. Path from a Kazuya CPU cursor: Up, Up, Right. fixed_probe1 frame_49s Xiaoyu is the cell above Kazuya (a timed Up, or a run that started there). name_kazuya_r.raw is the right plate of frame_req_00000091.

Press lines were invisible: Send-Pad writes to the pipeline, and `if (Press-Confirm)` / `[void](Press-Menu)` swallow it. Send-Pad now uses Write-Host.

## Finding 5 — menupick-2 arena reached the fight (exit 0, 92.6 s)

Path: display Down+Cross, startgame Left+Cross, movie Start at 20.7 s, difficulty Cross, mode four Downs then Cross on practice, 1P Kazuya Cross at 30.0 s, CPU Kazuya Up at 31.8 s -> Xiaoyu, Up at 32.7 s -> Hwoarang, Right at 33.7 s. Right bar then unmatched (hashes 97c67eda / 7ad09a95). Saved logs/grok/menupick-yoshi.bmp from frame_req_00000086. Reclassify: yoshimitsu. CPU Cross at 39.8 s (late 0).

stage card before the confirm: 0 arena 15.4 (index name distance)
One Left (mall_b -> arena). Stage Cross at 48.7 s, Start at 60.0 s.
python -I logs/grok/stage_pick_check.py logs/grok/menupick-2 arena 90 logs/grok/menupick-2-console.txt
card 0 arena 15.4 mean 77.4/67.1/64.6 black% 2.00
arena:29.6/19.61 shinjuku:79.5/10.95 underground:80.8/12.91 mall_b:81.2/12.98
check ok
frame_90s is Kazuya vs Yoshimitsu in the cage (guest HUD names both). Both nameplate phases classify cpu yoshimitsu (frame_req_00000081 and 00000086).

Wall 92.6 s, under the ~110 s budget. Banner still says fight from ~73 s (old timed math); the closed loop confirmed the card at 48.7 s.

## Finding 6 — eight exit-0 fights (menupick-2 through menupick-9)

python -I logs/grok/menu_dod_check.py (stage_pick_check, frame_90s vs sweep refs, pct_diff/psnr, gap rule):

- menupick-2 arena, no extra env, card 0 arena 15.4, ran 92.6 s. mean 77.4/67.1/64.6 black% 2.00. arena 29.6/19.61 vs shinjuku 79.5. check ok.
- menupick-3 arena, TEKKEN4_FIXED_LATE=4, card 0 arena 15.5, ran 92.6 s. yoshimitsu at 35.2 s, CPU Cross in 4 s, confirmed 39.3 s. mean 77.4/66.9/64.5 black% 2.00. arena 31.1/19.47 vs shinjuku 77.9. check ok.
- menupick-4 airport, card 1 airport 9.8, ran 100.6 s (did not close, killing). mean 74.4/71.2/80.3 black% 0.27. airport 6.8/26.78 vs shinjuku 74.9. check ok.
- menupick-5 airport, card 1 airport 10.5, ran 92.7 s. mean 74.4/71.3/80.4 black% 0.29. airport 10.2/23.9 vs shinjuku 75.3. check ok.
- menupick-6 underground, card 9 underground 11.6, ran 92.7 s. mean 77.2/63.2/45.4 black% 1.04. underground 21.6/18.81 vs mall_b 76.4. check ok.
- menupick-7 beach, card 6 beach 2.3, ran 92.7 s. mean 127.2/119.3/133.9 black% 0.11. beach 12.8/20.59 vs arena 89.1. check ok.
- menupick-8 building, card 2 building 14.3, ran 100.6 s (did not close, killing). mean 85.5/75.9/71.7 black% 0.35. closest arena 83.7/11.12, building 85.3/10.41. stage_pick_check exit 1. logs/grok/sweep-building/frame_77s.bmp is Kazuya vs Hwoarang on the glass-floor stage; menupick-8 frame_90s is Kazuya vs Yoshimitsu on that same stage (dinosaurs, neon). Full-frame diff is the opponent. floor crop (20,360)-(180,447) pct_diff building 72.8, arena 83.5, airport 94.3 (logs/grok/menu_bgdiff.py). Not a 15-point gap.
- menupick-9 laboratory, TEKKEN4_IOP_IDLE_SKIP=0 plus SOUND=1, card 7 laboratory 8.9, ran 92.6 s. yoshimitsu at 42.7 s (later than the ~35 s runs). mean 95.1/96.7/117.8 black% 0.40. laboratory 37.7/18.79 vs arena 86.2. check ok. The card left laboratory during the 7 s hold (arena, underground) with no press logged, then Left brought it back and the confirm stuck.

menu_screen.py --check 28/28. CPU path each run: Kazuya, Up, Xiaoyu, Up, Hwoarang, Right, Yoshimitsu, then Cross.
