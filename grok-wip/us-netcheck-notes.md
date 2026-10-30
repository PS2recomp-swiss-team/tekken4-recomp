# us-netcheck notes

Exe H:\tekken4-fork-ps2recomp_usa\out\runtime\ps2xRuntime\ps2EntryRunner.exe size 49892352. Strings: NETDESYNC at 47469992, T4NP, Runtime Debugger, build_mismatch. TEKKEN4_HUD absent (scan). t4net_build.txt: 40f7094523f87dd6. PS2X_ENABLE_DEBUG_UI=ON (CMakeCache.txt:419). Debug panel m_visible defaults true (ps2_debug_panel.h:19); draw is on the present thread (ps2_runtime.cpp:2540), not the EE thread. net_pair.ps1:82-86 posts F1, which toggles that panel off. HUD-on run uses logs/grok/us-netcheck-hudpair.ps1 (same launcher, F1 not posted).

PAL lock held by this queue (pid 112732) so no-interlace captures do not share the CPU. User pcsx2.exe pid 106324 has been up since 2026-10-28 from E:\ (idle, not the project capture).

## desync (done)

Command: net_pair.ps1 -Name grok-us-ndesync -Src H:\tekken4-fork-ps2recomp_usa -BuildDir runtime -End 300 -Seconds 240 -Rtt 0 -Env PHASE3 $v (SOUND=1, DESYNC_DUMP=1, RAND_SEED=1) -JoinEnv TEKKEN4_RAND_SEED=2.
Logs: H:\tekken4-recomp_usa\logs\net\grok-us-ndesync. Both NETEND ~9-11 s, script ran 20 s.
Host NETDESYNC x8 from f=150 (rb_frames.log:160) then 180,210,240,270,300,330,360. Join the same frames, hashes swapped (join log:161).
NETHASH f=120 identical both sides (h=6a872468b72701a1 ram=98b9b5367af8ca93 iop=b2a39f8553004c10 cyc=589835898). f=150 ram diverges, iop and cycle still match (host iop=661a6bd132c8d39d cyc=737294858 = join).
Dumps: 8 per side. python -I docs/rollback/net_desync_diff.py on net_desync_f150.bin: "1 differing 4 KB pages of 8196" / "page 00304000: 1 words, first 00304900: 00000001 vs 00000002". That is _impure_ptr+88 (tekken4_testseed_overrides.cpp:17-28, kReentPtr 0x304b94).
Summary at the End=300 line: host mismatches 5 of 9 hashes (the five frames 150-270); frames 330 and 360 are after NETEND while the script was still closing the windows.

## pairs

rtt0/60/250 jitter 5 loss 3, and rtt 150 jitter 5 loss 10, then HUD (rtt 150 jitter 5 loss 3, no F1). Same $v as section 7, End 12000, Seconds 900, shots 2400,6000,12000. Baseline pablo-n150b final: host 58.3/51.2 rb 2019 resim 3861 depth 5 rbms 17.00/27.24/91.60 stalls 410 (3742 ms) disp 16.4/32.9/75.6 rtt 152 delay 3 hash 399 mis 0.

grok-us-n0 (set rtt 0 jitter 5 loss 3; handshake rtt 2 ms -> delay 1, net.log:6; final median rtt 3): both NETEND, 399 hashes, 0 desync. host fps 60.0/56.7 rb 44 resim 50 depth 2 rbms 13.28/20.12/77.22 stalls 0 disp 16.6/17.6/78.6 ts 2 (33 ms). join fps 60.0/56.7 rb 693 resim 2073 depth 9 rbms 20.50/46.53/68.78 stalls 19 (190 ms) disp 16.6/17.9/66.5 ts 143 (4567 ms). sim-dropped host 746 / join 760.

grok-us-n60 (set 60; handshake sample 61 ms -> delay 2, net.log:6; final median 59): 399 hashes, 0 desync. host 60.1/56.3 rb 475 resim 524 depth 4 rbms 11.44/16.25/103.94 stalls 42 (116 ms) disp 16.6/18.2/81.9 ts 2. join 60.0/56.3 rb 1011 resim 2720 depth 9 rbms 19.31/45.12/67.94 stalls 53 (356 ms) disp 16.6/18.2/68.7 ts 141 (4717 ms).

grok-us-n250: handshake 252 ms -> delay 4 (net.log:6), final rtt 249/250. NETEND 242 s both. host 53.2/50.3 rb 2348 resim 8379 depth 9 rbms 25.19/47.44/622.34 stalls 522 (8220 ms) ts 101. join 53.0/50.3 rb 1954 resim 6260 depth 9 rbms 23.51/43.75/541.73 stalls 455 (6969 ms) ts 16. 0 desync. rb max 622.34 already at f=1800 summary.

grok-us-n150-loss10: handshake 151 -> delay 3. NETEND 226 s. host 58.2/54.0 rb 1647 resim 3268 depth 6 drop 2984. join 58.2/54.0 rb 2413 resim 6597 depth 9 drop 3100 ts 132. 0 desync.

grok-us-hud: hudpair.ps1 (no F1). params.txt:1 "hud on (no F1)". handshake 152 -> delay 3. NETEND 226 s. host 58.4/54.1 rb 1655 resim 3269 depth 6 disp 16.2/29.1/77.8. join 58.8/54.1 rb 2412 resim 6452 depth 9 ts 134. 0 desync. Counters match loss10, not a panel cost.

f=12000 hash identical on n0, n60, n250, loss10, hud, pablo-n150b, both sides: h=9acc728a4b8df02c ram=5d9639f61b3acd53 iop=e9b00ac548781476 cyc=58983588006 (us-netcheck-hash.py ALL_MATCH).

Sound device opened on every stderr (48000 Hz stereo). Report: logs/grok/us-netcheck-report.md. Queue DONE 10:00:36, PAL lock emptied.
