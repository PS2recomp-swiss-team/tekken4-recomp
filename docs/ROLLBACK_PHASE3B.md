# Rollback phase 3b: stalls, rebases and hitches of the netplay pair

Status 2026-10-30. Follows `docs/ROLLBACK_PHASE3.md` (protocol, `tools/net_pair.ps1`, NETSUMMARY). T5DR reference:
its `docs/ROLLBACK.md` sections 22-34 ("T5 sec. n").

## Result in one paragraph

The pair's "stalls" were the lockstep boot (frames < 600): gone (411/427 -> 0-5 waits). The fight's hitches have two
causes. (1) **GPU saturation**: two games on this PC drive the RTX 3090 to 99 % in the cage fight (one game alone
~40-50 %); the game that gets less GPU time has its GS worker wait 35-200 ms for a vertex-ring fence every ~6
frames (~370 frames per 100 s), that game falls behind, the pacing guard "rebases", the other side runs ahead,
predicts deeper and time-syncs. This is renderer GPU cost, not netplay, and stays: fights are capped at ~48-55
fps in this two-games-on-one-GPU harness. (2) **Rollback cost**: the drawn tail frame, 1.6 ms full copies per
snapshot/restore and the 4 ms hash on the game thread. Fixed: rollback p50 host 14.9 -> 6.6 ms at RTT 100, fight
48 -> 55 fps, displayed p99 107 -> 70-79 ms, rebases halved. **0 desyncs in every pair** (host = joiner = offline
reference `nref` at every 30th frame). The goal (p99 <= 20 ms, stalls ~0 in the fight) is not reached on one PC;
the GPU cost of the GL renderer has to come down first (gfx/perf work), or the pair has to run on two PCs.

## Before / after (pairs, jitter 5 ms, 3 % loss, $v of PHASE3 sec. 4, boot to frame 6000, fight = frames 2400-6000)

Two games, AboveNormal priority, 8 logical processors each (host 16-23, joiner 24-31), started on a quiet machine
(`load.txt` per run). "before" = `out\netbase` (t4-net merged with t4-us, no 3b change), "after" = `out\net`.
Per side host / joiner. Displayed frame = live-boundary to live-boundary in the fight.

| run | RTT, delay | fight fps | displayed p50 / p90 / p99 ms (host; join) | frames > 34 ms | GS fence-stall frames | rollbacks | rollback ms p50 / p90 (host; join) | capture / restore ms | rebases in fight | waits for the peer, whole run | desyncs |
|---|---|---|---|---|---|---|---|---|---|---|---|
| B50 before | 47, 1 | 48.4 | 15.5/30.4/118.6; 15.2/33.6/113.5 | 328 / 346 | 325 / 1 | 316 / 810 | 14.6/28.8; 21.1/50.4 | 1.6 / 1.7 | 168 / 158 | 389 / ~400 (boot) | 0 |
| A50 after (tail drawn; machine busy, 51 % load) | 51, 1 | 48.9 | 16.5/31.5/94.6; 14.4/36.8/98.5 | 253 / 439 | 1394 / 0 | 156 / 912 | 12.8/28.9; 22.4/43.5 | 0.5 / 0.5 | 172 / 134 | 0 / 21 | 0 |
| B100 before | 99, 2 | 48.2 | 14.1/35.9/107.5; 14.2/35.4/106.7 | 398 / 396 | 378 / 0 | 342 / 815 | 14.9/30.0; 22.3/51.1 | 1.8 / 1.7 | 173 / 164 | 411 / 427 (boot) | 0 |
| A100 after, tail drawn | 99, 2 | 48.3 | 15.5/31.9/121.8; 14.7/36.0/113.3 | 346 / 385 | 372 / 0 | 270 / 935 | 12.1/31.3; 20.7/45.5 | 0.46 / 0.50 | 162 / 138 | 0 / 38 | 0 |
| **A100t0 after (final default)** | 101, 2 | **54.7** | 16.2/23.9/**79.3**; 15.9/28.5/**70.1** | 249 / 203 | 289 / 0 | 393 / 965 | **6.6/13.7; 12.7/30.8** | 0.43 / 0.49 | **74 / 52** | **0 / 14** | 0 |
| B150 before (machine busy, 55 % load: not comparable) | 149-155, 2 | 29 | 22.5/50.6/290.8; 16.0/56.8/343.8 | 702 / 793 | 1043 / 33 | 499 / 907 | 23.3/38.9; 29.5/69.5 | 2.2 / 1.9 | 552 / 386 | 508 / 895 | 0 |
| A150 after, tail drawn | 148, 3 | 48.4 | 14.2/36.3/128.4; 13.3/36.1/117.4 | 384 / 400 | 358 / 0 | 307 / 889 | 14.8/28.5; 22.2/46.4 | 0.42 / 0.48 | 160 / 129 | 0 / 48 | 0 |
| **A150t0 after (final default)** | 148-150, 2 | **54.5** | 13.7/30.8/**68.3**; 12.5/31.7/**65.0** | 267 / 280 | 253 / 0 | 807 / 1010 | 15.4/23.9; 18.1/31.4 | 0.42 / 0.49 | **89 / 77** | **0 / 7** | 0 |

The user's `n100perf` (same harness, no affinity): fight 47 fps, p99 ~120 ms, stalls 445/477 (boot), rebases 177/167.
Also measured: delay 3 instead of 2 (`A100d3`, `A150d3`): fight 48-49.5 fps, p99 104-125 ms -- no better, the
joiner's rollbacks come from the host's GPU stalls, not from the delay; auto delay stays T5DR's table. RTT 150 is at
the 2/3 boundary of that table (a pair picked 2 or 3 by its measured 148-152 ms).

Long fight frames (> 20 ms) by cause (`why.py`-style split of `rb_frames.log`), RTT 100: before, host 399 GS fence
stalls (62 ms avg) + 292 rollbacks (30 ms); joiner 687 rollbacks (47 ms) + 78 time-sync. After (tail drawn): host 395
GS stalls (68 ms) + 165 rollbacks (26 ms); joiner 735 rollbacks (45 ms) + 87 time-sync. The GS stalls are the
`[gs-slow] ... vertex ring fence wait` lines (`PS2X_GS_SLOW_LOG=1`): the whole chunk time is the fence wait.

## Causes

- **Stalls** (`stalls N (ms)` in NETSUMMARY) = waits for the peer's input. 97-100 % were the lockstep boot (frames <
  600: boot, intro movie): with input delay 2 at RTT 100 every lockstep frame waits ~8 ms (40 fps boot).
- **Rebases** = the pacing guard moving the host schedule when the game is > 50 ms behind it: one per long hitch.
  Sum of rebases ms ~= time lost to frames that ran long: GS fence stalls (one side) and rollbacks.
- **GPU**: `nvidia-smi pmon` during a pair: GPU 99 %, P0 1980 MHz, the two games ~50/50 (e.g. 61/37, 49/49); one
  game alone 34-49 % even in menus. Not the cause: window focus (host brought to front: still host stalls), GPU
  scheduling priority (set HIGH on both: the stall moves sides), the vertex ring itself (bounding the GPU lag per
  frame: same waits, just shorter and more often), texture barriers (~300-400 per frame; skipping them: 45.7 -> 50.4
  fps, still 99 %), the shadow-volume per-triangle path. The CPU GS backend is no way around it (17.8 fps).
  -> For the gfx/perf work: the GL renderer's GPU time per frame in the cage fight.
- **Rollback cost** before: restore 1.6-1.9 ms + per re-simulated frame ~6 ms + capture 1.6-1.9 ms each + the drawn
  tail frame ~11 ms (and its GPU work); a depth-1 rollback ~15 ms on top of an 11-13 ms live frame = always a picture
  shown twice. Hash 3.7 ms (+ the 32 MB desync-dump copy) on the game thread every 30th frame.

## Changes

Game side (`runtime/tekken4_rollback_overrides.cpp`, `runtime/tekken4_net.{h,cpp}`; not committed in D:\tekken4-us):
1. **Lockstep input delay** (`TEKKEN4_NET_LOCKDELAY`, auto = one way + 12 ms in frames + 1, at least the session
   delay; 5 at RTT 100): during the boot each side samples its input that far ahead, so the peer's input is there
   when the frame comes (T5 sec. 22: no lockstep crawl). Boot waits 411 -> 0-5. The time-sync estimate starts
   `kMaxLockDelay + 4` frames after the lockstep.
2. **Early rollback** (T5 sec. 27; `TEKKEN4_NET_EARLY`, `TEKKEN4_NET_EARLY_MS` = 4): the schedule runs 4 ms ahead of
   the frames' vblank times; at a boundary this side's input is sampled and sent at once, then a misprediction already
   known -- or found while waiting for the vblank time (`t4net::waitRemoteUs`) -- is rolled back in the wait; the live
   part (time sync, prediction window, the late check) comes at the vblank time. 98-100 % of the rollbacks run early.
3. **No drawn tail in netplay** (`TEKKEN4_RB_CUT_TAIL` default 0 in `Mode::Net`, `=1` as before): the first live frame
   after a rollback shows the mispredicted pass's picture, the corrected one comes a frame later. Shots of the pairs
   (2400/4500/6000) show the expected scenes on both sides.
4. **Lazy re-simulation captures** (T5 sec. 33.4, `TEKKEN4_NET_LAZY`): re-simulated boundaries below the confirmed
   input (no rollback can reach them) are not captured unless a hash is still due; their ring slot is marked empty.
5. **Desync hash and dump copy on a worker thread**; a capture into a slot waits for its job.
6. **Time sync**: as T5 sec. 28/34 (trimmed mean, hold until the peer saw it, whole vblank periods given up).
7. GPU scheduling priority HIGH for netplay processes (`TEKKEN4_NET_GPU_PRIORITY=0` off): harmless, did not help.
8. NETSUMMARY additions: lockstep waits, lock delay, early rollbacks, lazy captures skipped, frames > 20/34 ms,
   RDRAM pages per capture/restore, VERIFY MISMATCH PAGES (only if incremental copies ever differ).

PS2Recomp (`D:\tekken4-fork-net`, branch t4-net, merged with t4-us first), `docs/rollback/patches/`:
- `0074` incremental RDRAM snapshots: RDRAM under a Windows write watch; captures/restores copy only pages written
  since (~185 of 8192): capture 1.6-1.9 -> 0.42-0.46 ms, restore 1.6-1.9 -> 0.48-0.50 ms. `PS2X_RB_WW_VERIFY=1`
  (full compare after every copy) ran a 6000-frame pair: 0 mismatching pages. Applies on t4-us 702a93a.
- `0075` GS measurement switches (`PS2X_GS_SLOW_LOG`, `PS2X_GL_MAX_GPU_LAG`, `PS2X_GL_NO_BARRIER`,
  `PS2X_GL_WRAP_BATCH`; all off). Conflicts with t4-us 702a93a's gs_hw_backend.cpp (gfx changes): optional,
  diagnostics only.

## Correctness

Every pair above (and the experiments `p3b_x_*`): host vs joiner 0 mismatching hashes, NETDESYNC 0;
`docs/rollback/net_compare.py ... --ref logs/net/nref/rb_frames.log`: A50, A100, A100t0, A150t0 0 of 201-214 frames
differ from the offline reference.

## Reproduce

`docs\rollback\net_build.cmd`, then `tools\net_pair.ps1 -Name <n> -Rtt <50|100|150> -Jitter 5 -Loss 3 -End 6000 -Env $v`.
Runs: `logs/net/p3b_{B50,A50,B100,A100,A100t0,B150,A150,A150t0,A100d3,A150d3}`, experiments `logs/net/p3b_x_*`.
Note: net_build/build_runtime applied D:\tekken4-us\patches 58+ (other agents' movie/pad/runahead patches) to the
t4-net tree; they are uncommitted there and in the "after" exe (not in "before").

## What is left

- The GL renderer's GPU time (cage fight ~half of an RTX 3090 per game): with it two games on one PC cannot both run
  60 fps; on two PCs this harness artifact disappears. Then re-measure: the netplay side now costs ~0.4 ms per
  snapshot and 6-13 ms p50 per rollback.
- A display margin / picture queue (T5 sec. 34) only pays once the live frame has headroom.
