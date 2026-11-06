# Online presentation (patch 99a, `TEKKEN4_NET_PRESENT`)

Problem: online (rollback, `TEKKEN4_RB_MODE=net`) a 60 Hz screen recording showed ~45 new pictures/s and more
two-frame holds than offline, while the loop reported 60.0 fps and every guest vblank carried a new picture.

Cause (host side only): the paced present of patches 64/65 is due 2 ms after each guest VBlankStart and waits for the
GS worker's picture inside the present. Online the netplay loop sets the vblank times (early boundary up to 4 ms before
its slot, time-sync pauses, re-simulation), and the GS finishes the picture at a varying time after the vblank
(measured vblank -> swap 3.4 - 15 ms). On a display without vsync each picture stays until the next swap, so the
swaps came in clusters (two pictures a few ms apart, then a long hold).

Fix (`ps2_runtime.cpp`, run loop, online only): one present per new live picture, started at once at the tick (latch,
wait for the GS), then the picture is held and swapped at a time of its own: not before `lead` ms after its vblank, and
one frame (16.567 ms) after the previous swap, never more than `cap` after the first. `lead` follows the recent
picture-ready times (90th percentile of the last 64, plus draw + swap) between 3 and 10 ms, so a GS that needs 8 ms
every time still gets an even swap clock. Re-simulated frames are never shown (unchanged). Game state is not read or
written. Offline runs, `TEKKEN4_PRESENT_PHASE_MS` and the latency probe are untouched.

| variable | default | meaning |
|---|---|---|
| `TEKKEN4_NET_PRESENT` | on online | `legacy` (or `off`, `0`) = the patch 64/65 presenter online too |
| `TEKKEN4_NET_PRESENT_LEAD_MS` | 3 | floor of the vblank -> swap lead |
| `TEKKEN4_NET_PRESENT_LEAD_MAX_MS` | 10 | ceiling of the adaptive lead |
| `TEKKEN4_NET_PRESENT_PCT` | 90 | percentile of the picture-ready times the lead follows |
| `TEKKEN4_NET_PRESENT_CAP_MS` | 6 | most the even-spacing rule may delay a picture |

The runtime prints `[present] online presenter on: ...` at start. Measured with `TEKKEN4_PRESENT_LOG=1` (the
`[present]` lines: one per new picture; guest ticks 3600-5900 of a mashed fight, two games on this PC, one per CCD,
host and joiner averaged, 2-3 runs each; this PC runs the fight at ~48 pictures/s, so the producer is the limit):

| scenario | | swap gap sd | gaps < 12 ms | swap gap p99 | vblank -> swap p50 / p99 | 60 Hz capture repeats |
|---|---|---|---|---|---|---|
| RTT 66, delay 1 | old | 5.66 ms | 5.0 % | 36.2 ms | 6.9 / 15.5 ms | 25.2 % |
| | new | 4.31 ms | 0.2 % | 32.6 ms | 2.9 / 11.6 ms | 22.3 % |
| RTT 20, delay 2 | old | 5.03 ms | 4.0 % | 33.9 ms | 5.7 / 15.8 ms | 21.3 % |
| | new | 3.76 ms | 0.1 % | 31.3 ms | 3.0 / 15.2 ms | 19.7 % |

"60 Hz capture repeats" is a simulated 60 Hz capture of the swap log; with pictures arriving every ~20.8 ms the
floor is 19.9 %, which the new presenter reaches. At a steady 60 pictures/s the presenter has nothing to smooth;
the owner's 500 Hz display and a real remote opponent are untested here. A 14000-frame match pair (rollback, RTT 66,
mashing) with the new runtime: 466 hashes compared, 0 mismatches on both sides.
