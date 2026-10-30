# zero-copy

Shared presentation is on. The raylib window is created before the GS context, `CaptureHostContext` records that GL context, and the GS 4.6 context shares it. The window draws the published texture. `PS2X_GS_DIRECT_PRESENT=0` never captures, so the old `glReadPixels` path remains. Frame shots still read pixels (`forceReadback`). RTX 5090, driver 617.14, host GL 3.3 core shared with GS 4.6 (no "WGL sharing failed" line).

Same binary (`external/wt-zero-copy/out/grok-zero-copy`). Closed-loop Practice, Kazuya vs CPU Yoshimitsu, PAL60, Until 105. 2x/4x stay at 1x until `PS2X_SCALE_AT` (airport 72s, beach 84s) because `menu_screen.py` only accepts 640x448. Fight window is after that switch: airport stdout s>=80, beach s>=90. `TEKKEN4_PERF_LOG=120` (the value is seconds, not a flag).

## Fight window averages

| run | stage | scale | path | game fps | host fps | GS ms/s | upload us | interval us | hud avg_ms (n=10) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| zero-copy-b1 | airport | 1 | readback | 60.0 | 60.0 | 167.8 | 6299 | 16660 | 12.4 |
| zero-copy-a1 | airport | 1 | shared | 60.0 | 60.0 | 111.6 | 1776 | 16676 | 28.5 |
| zero-copy-b2 | airport | 2 | readback | 60.0 | 60.0 | 177.9 | 5243 | 16689 | 29.9 |
| zero-copy-a2 | airport | 2 | shared | 60.0 | 60.0 | 87.2 | 300 | 16667 | 27.8 |
| zero-copy-b4 | airport | 4 | readback | 60.0 | 60.0 | 167.3 | 6489 | 16666 | 18.4 |
| zero-copy-a4 | airport | 4 | shared | 60.0 | 60.0 | 95.5 | 630 | 16675 | 30.7 |
| zero-copy-b4be | beach | 4 | readback | 60.0 | 60.0 | 246.2 | 9346 | 16687 | 31.2 |
| zero-copy-a4be | beach | 4 | shared | 60.0 | 60.0 | 74.6 | 98 | 16673 | 20.4 |

GS ms is host time inside `processGIFPacket` per wall second. upload us is host time inside `UploadFrame` (readback copy, or the shared acquire). interval us is the displayed frame period (60 Hz lock: 16667). blank count in every fight window is 0. Shared runs have readback count 0.

Spot check at s=100 (one second, not the average):

- b1 readback upload 6379 us, GS 171 ms, 60 frames (`zero-copy-b1/stdout.txt:543`)
- a1 shared upload 1892 us, GS 110 ms (`zero-copy-a1/stdout.txt:541`)
- b2 readback upload 4930 us, GS 177 ms (`zero-copy-b2/stdout.txt:552`)
- a2 shared upload 324 us, GS 87 ms (`zero-copy-a2/stdout.txt:539`)
- b4 readback upload 6548 us, GS 167 ms (`zero-copy-b4/stdout.txt:543`)
- a4 shared upload 550 us, GS 96 ms (`zero-copy-a4/stdout.txt:536`)
- b4be readback upload 9440 us, GS 254 ms (`zero-copy-b4be/stdout.txt:563`)
- a4be shared upload 94 us, GS 74 ms (`zero-copy-a4be/stdout.txt:541`)

Frame shots (blank false): airport 1x 640x448 mean r~74; 2x 1280x896; 4x 2560x1792 mean r~74. Beach 4x 2560x1792 mean r~127. Both stages, both paths.

## What did not move

Host and game fps stay 60 on this GPU even at 4x readback (18 MB, 2560x1792). The 60 Hz present lock is the limiter, not the copy. HUD `avg_ms` is the mean of the 10 menu presses (n=10 still at s=105). Those presses happen at 1x, before `PS2X_SCALE_AT`. The means overlap (readback 12.4–31.2, shared 20.4–30.7), so this is not a latency win. A Cross posted at 90s did not add a sample.

## F2 on the shared texture

`zero-copy-f2off` aspect 4:3, smooth off, fxaa off, sharpen 0. `zero-copy-f2on` aspect 16:9, smooth on, fxaa on, sharpen 40. Both shared, 1x, airport fight, host shot at 90s (rlReadScreenPixels).

- 4:3 host 640x480 top40 mean 101.79, bottom40 57.08, row corr vs guest 0.979, mean abs diff vs nearest scale 4.41
- 16:9 host top40 7.80, bottom40 0.00, mid 98.75, row corr 0.976, mean abs diff 7.57

Bottom rows at 0 are the 16:9 letterbox. The higher diff is bilinear + FXAA + sharpen (the post shader runs only when fxaa or sharpen is set). Guest frames themselves stay 640x448 and non-blank. Orientation vs a readback frame shot: row corr 0.966, flipped corr -0.207 (`zero-copy-smoke2` frame_16s vs host_16s). No flip.

## Tests

`logs/grok/zero-copy-tests.cmd` (`TEKKEN4_SRC=external\wt-zero-copy`): Total 489, Passed 489, Failed 0, exit 0.
