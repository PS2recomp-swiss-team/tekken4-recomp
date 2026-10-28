# input lag

Shipping path (no env): window thread pumps the posted-key queue about every 1 ms (`timeBeginPeriod(1)` + `MsgWait` + `PollInputEvents`), wndproc keeps an atomic pad mask, `scePadRead` samples that mask (and `GetAsyncKeyState` only when this window is foreground). Present stays on a 16.667 ms clock. `TEKKEN4_INPUT_LEGACY=1` is the old once-per-frame `IsKeyDown` poll. `TEKKEN4_INPUT_PRESENT=tick` presents on the guest vsync tick (measured worse, not the default). `TEKKEN4_INPUT_LAG=1` logs QPC stages and is off in normal play.

t0 = script `QueryPerformanceCounter` immediately before `PostMessage(WM_KEYDOWN)`. t1 = wndproc dispatch. t2 = `scePadRead` packet contains the bit. t3 = GS latch of the next host present after t2. t4 = swap return of that present. t5 = swap return of the first post-t2 present whose 16x16 block-mean hash differs from the hash at t1. N=24 mode-select Down/Up, random 0..16.7 ms. QPC freq 10000000.

## stage table (median ms, frames at 16.6667 ms)

Paired runs, same binary family, hash requires t3 (post-read latch):

| stage | legacy2 | fast paced | delta |
| t1-t0 | 10.73 (0.64f) p95 17.09 | 0.03 (0.00f) p95 2.04 | -10.70 |
| t2-t0 | 15.90 (0.95f) p95 33.80 | 7.75 (0.46f) p95 16.28 | -8.15 |
| t3-t0 | 27.24 (1.63f) p95 50.74 | 17.76 (1.07f) p95 29.15 | -9.48 |
| t4-t0 | 29.83 (1.79f) p95 54.78 | 19.95 (1.20f) p95 31.21 | -9.88 |
| t5-t0 | 29.83 (1.79f) p95 54.78 | 19.95 (1.20f) p95 46.05 | -9.88 |
| t2-t1 | 7.92 | 7.72 | |
| t4-t3 | 2.36 p95 6.43 | 2.24 p95 3.81 | |

Sources: `logs/grok/input-lag-legacy2/lag_summary.txt`, `logs/grok/input-lag-paced/lag_summary.txt`. Samples 24/24 both.

Quieter earlier legacy (old per-pixel hash, t5 not gated): t1 6.27, t2 16.05, t3 22.63, t4 25.30, t5 25.30, t4-t3 2.19 (`logs/grok/input-lag-before/lag_summary.txt`). Paced t5 19.95 is still under that.

Tick present, same pump, rejected: t1 0.03, t2 8.97, t3 24.22, t4 30.06, t5 30.06, t4-t3 5.79 (`logs/grok/input-lag-tick2/lag_summary.txt`). Readback runs while the GS queue is still drawing. Menu frame vs legacy was 18.164% of pixels over thr 16, PSNR 23.36, diff is horizontal bands (`logs/grok/input-lag-after/frame_38s_diff.png`).

## picture

`frame_38s.bmp` mode select, before measurement presses. legacy2 vs paced: 640x448, blank false, means r/g/b 54.81/57.11/64.97 vs 54.76/57.06/64.91, pct_diff 0.0, mean_abs_diff 0.053, psnr 54.98.

## 60 fps

`TEKKEN4_PERF_LOG` on the shipping path (no `TEKKEN4_INPUT_LAG`, no `LEGACY`, no `PRESENT`). Fight keys through 46:Cross, process held to 145 s. Guest frames (sound call) seconds 50-139: n=90, none missing, min 46 (second 50 only), median 60, p05 60, max 61, mean 59.87. Second 0 was 41, so the counter moves. `logs/grok/input-lag-fight/stdout.txt`.

## what moved, what cannot

- Host poll wait is gone. Legacy raylib polls once per frame inside `EndDrawing` (after the swap when `SetTargetFPS` is 0). Fast path dispatches posted keys in about 1 ms. Median t1 10.73 -> 0.03. p95 still 2 ms: a key that lands during `glReadPixels` waits out the rest of that present.
- The game sees the bit on the next `scePadRead` instead of the next poll plus the next read. t2 15.90 -> 7.75. t2-t1 stays ~7.7 ms. That is the guest's own read point: random sub-frame t0, one read per frame, floor about half a frame, p95 one frame (16.28 ms). Cutting it means the guest calling `scePadRead` more often. Not this host.
- Present-on-tick did not move the picture earlier and added ~3.5 ms of readback. Default is the 16.667 ms clock.
- t4-t3 ~2.2 ms is `glReadPixels` of the presented image (`gs_hw_backend.cpp` present, the `ReadPixels` into `frame.pixels`) plus the raylib upload and swap. `GSSharedPresent::Acquire` has no caller. `PS2Runtime::syncCoreSubsystems` calls `m_gs.init` before `InitWindow`, so the GS context is not shared with the window. A shared `Present` returns an empty CPU frame, and frame shots read `copyLatchedHostPresentationFrame`. Not switched on.
- t5 equals t4 on 27/30 paced log lines (3 later). The block hash does not hold between presses (0/24), so t5 is not a clean cursor detector on this screen; the median matches the first present after the read. The menu frame at a fixed second does match (diff above).

## tests

`logs/grok/input-lag-tests.cmd` sets `TEKKEN4_SRC` to `external\wt-input-lag` and calls `tools\build_tests.cmd`. Total 482, passed 482, failed 0. PadInput scePadRead tests passed.

## PCSX2

`logs/grok/pcsx2-input-lag/pcsx2_lag.txt`. Window 656x519, foreground true. 8 Down/Up presses, PrintWindow hash. changed_ms: 29.1, 4.8, 18.5, 30.6, 3.3, 38.8, 9.0, 3.7. Four of those are one poll and under one frame (3.3-9.0 ms), so the hash moves without a completed game frame. Not used as the game's latency. A no-key run of the same hash would settle it.

## code

- `ps2_input_latency.cpp` compiled via `#include` from `gs/gpu/gs_gl.cpp` (CMake source list is not owned).
- `Pad.cpp` reads `memory().gs().vsyncTick` (the counter `EeScheduler::VBlankStart` stores). `eeScheduler()` is an incomplete type in that TU.
- Keyboard map unchanged. Gamepad path still `IsGamepadButtonDown` on the game thread. Raylib/GLFW calls stay on the window thread. `GetAsyncKeyState` is the game-thread physical-key path.
