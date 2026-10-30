# us-netcheck (2026-10-30)

Run-only. No source edits. Exe `H:\tekken4-fork-ps2recomp_usa\out\runtime\ps2xRuntime\ps2EntryRunner.exe` 49892352 bytes, build id `40f7094523f87dd6` (`t4net_build.txt:1`). Strings present: NETDESYNC, T4NP, Runtime Debugger, build_mismatch. `TEKKEN4_HUD` absent (byte scan). `PS2X_ENABLE_DEBUG_UI=ON` (`out\runtime\CMakeCache.txt:419`).

Every pair: `tools\net_pair.ps1 -Src H:\tekken4-fork-ps2recomp_usa -BuildDir runtime`, PHASE3 env (`ROLLBACK_PHASE3.md:150`, `TEKKEN4_SOUND=1`, `TEKKEN4_NET_DESYNC_DUMP=1`, `TEKKEN4_RAND_SEED=1`, same RB_INPUT/FUZZ), build id from the stamp. PAL `logs\run.lock` held by the queue so the no-interlace capture did not share the CPU. Lock emptied at the end.

Sound: every host and join stderr this session has `[tekken4] sound device 48000 Hz stereo (pulled by the audio thread)` (hud host `stderr.txt:7`, same line on n0/n60/n250/loss10/ndesync and on `pablo-n150b`). No WAV was written.

## 1. Forced desync

`net_pair.ps1 -Name grok-us-ndesync -End 300 -Seconds 240 -Rtt 0 -JoinEnv TEKKEN4_RAND_SEED=2`. Both NETEND in 9 s / 11 s. Logs `H:\tekken4-recomp_usa\logs\net\grok-us-ndesync`.

Host `rb_frames.log:160` `NETDESYNC f=150` then 180, 210, 240, 270, 300, 330, 360 (8 lines). Join `rb_frames.log:161` same frames, local/peer hashes swapped. Frames 330 and 360 are after `NETEND f=300` (script polls every 2 s before closing).

`NETHASH f=120` is the same on both sides (`h=6a872468b72701a1 ram=98b9b5367af8ca93 iop=b2a39f8553004c10 cyc=589835898`, host and join line 127). `f=150` ram diverges; iop `661a6bd132c8d39d` and cycle `737294858` still match. So the first break is RDRAM, not IOP or the EE cycle.

8 dumps a side. `python -I docs\rollback\net_desync_diff.py` on `net_desync_f150.bin`:

```
1 differing 4 KB pages of 8196
  page 00304000: 1 words, first 00304900: 00000001 vs 00000002
```

That word is newlib rand state, `_impure_ptr+88` (`runtime\tekken4_testseed_overrides.cpp:17-28`, reent pointer `0x304b94`). Host seed 1, joiner seed 2 (`params.txt`). Same result PHASE3.md:39-40 recorded.

## 2. Pairs

End 12000, Seconds 900, shots `2400,6000,12000`. Jitter 5. Loss 10 is the section-7 RTT (150), only the loss percent changed. Delay is the host's 16-sample handshake pick (`tekken4_net.cpp:1014`: 1 at <=60, 2 at <=150, 3 at <=250, 4 above).

| run | side | fps window / run | rollbacks | resim | max depth | rollback ms p50/p90/max | stalls | displayed ms p50/p90/p99 | rtt / delay | hashes | mismatches |
|---|---|---|---|---|---|---|---|---|---|---|---|
| n0 set 0/5/3 | host | 60.0 / 56.7 | 44 | 50 | 2 | 13.28 / 20.12 / 77.22 | 0 (0 ms) | 16.6 / 17.6 / 78.6 | 3 / 1 | 399 | 0 |
| n0 | join | 60.0 / 56.7 | 693 | 2073 | 9 | 20.50 / 46.53 / 68.78 | 19 (190 ms) | 16.6 / 17.9 / 66.5 | 3 / 1 | 399 | 0 |
| n60 set 60/5/3 | host | 60.1 / 56.3 | 475 | 524 | 4 | 11.44 / 16.25 / 103.94 | 42 (116 ms) | 16.6 / 18.2 / 81.9 | 59 / 2 | 399 | 0 |
| n60 | join | 60.0 / 56.3 | 1011 | 2720 | 9 | 19.31 / 45.12 / 67.94 | 53 (356 ms) | 16.6 / 18.2 / 68.7 | 59 / 2 | 399 | 0 |
| n250 set 250/5/3 | host | 53.2 / 50.3 | 2348 | 8379 | 9 | 25.19 / 47.44 / 622.34 | 522 (8220 ms) | 16.3 / 34.6 / 97.2 | 249 / 4 | 399 | 0 |
| n250 | join | 53.0 / 50.3 | 1954 | 6260 | 9 | 23.51 / 43.75 / 541.73 | 455 (6969 ms) | 16.3 / 34.4 / 93.3 | 250 / 4 | 399 | 0 |
| loss10 set 150/5/10 | host | 58.2 / 54.0 | 1647 | 3268 | 6 | 17.97 / 27.11 / 202.75 | 415 (3824 ms) | 16.3 / 29.1 / 75.9 | 150 / 3 | 399 | 0 |
| loss10 | join | 58.2 / 54.0 | 2413 | 6597 | 9 | 20.24 / 38.66 / 70.45 | 439 (4938 ms) | 16.3 / 30.9 / 77.5 | 150 / 3 | 399 | 0 |
| hud set 150/5/3, panel on | host | 58.4 / 54.1 | 1655 | 3269 | 6 | 17.61 / 27.32 / 136.98 | 397 (3735 ms) | 16.2 / 29.1 / 77.8 | 150 / 3 | 399 | 0 |
| hud | join | 58.8 / 54.1 | 2412 | 6452 | 9 | 19.54 / 38.88 / 68.61 | 439 (4727 ms) | 16.2 / 30.3 / 78.9 | 150 / 3 | 399 | 0 |
| pablo-n150b (section 7, 01:31) | host | 58.3 / 51.2 | 2019 | 3861 | 5 | 17.00 / 27.24 / 91.60 | 410 (3742 ms) | 16.4 / 32.9 / 75.6 | 152 / 3 | 399 | 0 |
| pablo-n150b | join | 59.0 / 51.2 | 2044 | 4079 | 5 | 17.64 / 26.83 / 86.75 | 426 (3670 ms) | 16.1 / 33.5 / 76.9 | 152 / 3 | 399 | 0 |

NETEND wall time: n0 215/216 s, n60 218/218 s, n250 242/242 s, loss10 226/226 s, hud 226/226 s (`us-netcheck-queue.txt`). NETDESYNC lines 0 on all ten sides.

Handshake vs the bucket edge (`host\net.log:6`): n0 sample 2 ms -> delay 1. n60 sample 61 ms -> delay 2 (final median later 59). n250 sample 252 ms -> delay 4 (final median 249/250). loss10 sample 151 -> delay 3. hud sample 152 -> delay 3. Jitter 5 on a threshold RTT crosses `<=60` and `<=250`.

Frame 12000 final-state hash is the same 12 ways (n0, n60, n250, loss10, hud, pablo-n150b, both sides): `h=9acc728a4b8df02c ram=5d9639f61b3acd53 iop=e9b00ac548781476 cyc=58983588006`. RTT, 10% loss, and the debug panel did not change guest state. `f=11970` matches between hud host and hud join as well.

Extra counters (time sync, sim-dropped, resends), host then join:

| run | time sync | sim-dropped | resends |
|---|---|---|---|
| n0 | 2 (33 ms) / 143 (4567 ms) | 746 / 760 | 1393 / 1220 |
| n60 | 2 (33 ms) / 141 (4717 ms) | 848 / 867 | 4837 / 4582 |
| n250 | 101 (1950 ms) / 16 (267 ms) | 919 / 928 | 5509 / 5636 |
| loss10 | 3 (50 ms) / 132 (3333 ms) | 2984 / 3100 | 4988 / 4644 |
| hud | 4 (67 ms) / 134 (3217 ms) | 878 / 907 | 4852 / 4647 |
| pablo-n150b | 8 (133 ms) / 7 (117 ms) | 907 / 926 | 5608 / 5651 |

## 3. What degrades, and where

Per-600 `fps window` (host). The f=3000 / f=4800 / f=6600 dips are in the rtt-0 host too, which by then has 8, 27 and 41 rollbacks total, so those dips are the match (fuzz starts at frame 2400), not the net.

| f | n0 | n60 | n250 | loss10 | hud | pablo |
|---|---|---|---|---|---|---|
| 600 | 57.6 | 59.5 | 35.5 | 43.7 | 43.9 | 43.9 |
| 2400 | 60.0 | 60.0 | 60.0 | 60.0 | 60.0 | 60.0 |
| 3000 | 48.4 | 48.6 | 45.9 | 46.7 | 47.3 | 41.8 |
| 6600 | 47.1 | 47.2 | 44.1 | 45.6 | 45.2 | 40.2 |
| 7800 | 60.0 | 60.0 | 54.3 | 60.0 | 60.0 | 58.6 |
| 12000 | 60.0 | 60.1 | 53.2 | 58.2 | 58.4 | 58.3 |

RTT 250 is where fps leaves 60 and does not come back. From f=3000 through f=12000 the window is 44-57 (end 53.2 / 53.0), run fps 50.3. Boot is the other hit: f=600 window 35.5, stalls already 455 (7016 ms) on the host and 452 (6898 ms) on the joiner, and that stall count barely moves after f=7200 (522 / 8220 ms). At rtt 0 stalls stay 0. At rtt 150 they freeze near 400 (~3.7 s) after f=600, same shape as section 7. One early rollback is an outlier, not a fight hitch: host rb max is already 622.34 ms at the f=1800 summary (4 rollbacks total), while the menu windows are still 60 fps.

The faster peer eats the rollbacks once the fuzz is on. Depth goes to 9 and time-sync jumps at the f=3000 summary, not before (n0 join: f=2400 rb 0 ts 0; f=3000 rb 88 depth 9 ts 19). At rtt 0/60/150 the joiner is that peer (ts ~130-143, depth 9) and the host stays depth 2-6 with 2-4 corrections. At rtt 250 it flips: host ts 101 (1950 ms), join ts 16. Both sides still share a fps window and the same final hash, because time sync locks the rates. Section 7's pair was balanced (ts 8/7, depth 5/5). This morning's pairs are not. Same exe, same final hash.

Loss 10 does not move fps or the hash. sim-dropped 2984/3100 against hud's 878/907 at loss 3 (ratio 3.40 and 3.42; 10/3 = 3.33). Resends stay in the same band (host 4988 vs hud 4852). The single worst rollback is larger (host max 202.75 ms, first seen at f=6600, vs hud 136.98 ms at f=3600). Mismatches 0.

HUD: this exe has no `TEKKEN4_HUD`. The host overlay `net_pair.ps1:82-86` turns off with F1 is the ImGui Runtime Debugger (`m_visible` defaults true, `ps2_debug_panel.h:19`; draw bails when hidden, `ps2_debug_panel.cpp:2214`; drawn on the present thread, `ps2_runtime.cpp:2540`). The hud pair is `logs\grok\us-netcheck-hudpair.ps1`, the same launcher with that PostMessage removed. Host `params.txt:1` records `hud on (no F1)`. Against loss10 (F1 hidden, same morning, rtt 150, loss 10 not 3) and against section 7 (F1 hidden, loss 3): fps window, displayed p50 (16.2 vs 16.3 vs 16.4), boot window, and the final hash do not move. Rollbacks match the loss10 pair (host ~1650 depth 6, join ~2410 depth 9), not the balanced section-7 pair, so that split is the morning's window focus, not the panel. No guest-frame shot can show the panel (shots are the guest frame). The counters are the evidence: leaving it up did not degrade this 12000-frame pair.

Sound was on for every row above, including the rtt-0 pair whose fight windows sit at 60. There is no sound-off pair in this session, so sound's own cost is not separated. It is inside the numbers, and it is not what breaks 60. RTT 250 is.
