# Netplay frame pacing: the "fps not right" report (2026-11-03/04)

Owner's two-PC test, 2026-11-03 23:25-23:42 (T4 Easy Launcher, direct over Tailscale, RTT 17 ms, input delay
auto = 1, rollback): "online works, but the fps are not right". Host log of that session, 16.5 minutes, build id
936a92ed7b4ac0de:

- The average was fine: 59,527 live frames, frame time p50 16.65 / p95 17.8 / p99 18.5 ms, 147 rollbacks (depth
  1-2), 0 mismatches.
- What a player sees as "fps not right" were single long frames (the picture held for 2-3 refreshes): 214 frames
  over 20 ms, 27 over 34 ms, max 44 ms. Their causes, by what the per-frame log shows next to them:

| cause | frames > 20 ms | what happens |
|---|---|---|
| summary lines every 600 frames (NETSUMMARY / COST / WAKES / IOP) | 74 of 98 | the percentiles were computed by sorting every sample since the start, on the game thread: 9 ms after 3 minutes, 31 ms after 16 minutes -> a hitch every 10 s that grows with the session (40-44 ms late) |
| time sync | 10 of 10 | a correction (this side 1 frame ahead) paused for one whole frame: the same picture twice (31-34 ms) |
| heavy game frames | 126 | EE time 17-23 ms in some scenes, VU1 10-13 ms of it; the same offline, not a netplay cost |
| rollbacks | 1 | re-simulation runs in the vblank wait (early rollback) and is hidden |

The first minute's 54 fps in stdout ("main loop frame 1000") is the boot/attract loading, not netplay.

## Changes (branch t4-fps)

- **Summary percentiles** (`TimeSamples` in runtime/tekken4_rollback_overrides.cpp): a fixed histogram (0.01 ms
  bins up to 100 ms, exact values outside, exact maximum) instead of re-sorted vectors. O(1) per sample, ~10 us per
  percentile; the printed values differ from the exact ones by at most 0.005 ms. The NETSUMMARY "displayed frame
  ms" percentiles now cover the whole session (they were the last 10,000-20,000 frames).
- **Time sync spread** (`TEKKEN4_NET_SYNC_SPREAD`, default 8): a correction no longer pauses one whole frame; the
  next 8 live frames each start 1/8 of it later (~2 ms each), so no picture is shown twice. `0` or `1` = the old
  single pause. Only host pacing: which inputs a frame uses and what it simulates are unchanged.

Offline play does not run this code (rollback mode is off without TEKKEN4_NET / TEKKEN4_RB_MODE).

Measurements and pair proofs: build/coordination/T4_ONLINE_FPS.md (local notes of the t4fps agent).
