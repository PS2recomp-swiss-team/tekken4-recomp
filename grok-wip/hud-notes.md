# hud notes (2026-10-28)

Overlay is raylib after DrawTexturePro, before the debug UI (ps2_runtime.cpp presentHostFrame). Frame shots stay the latched GS image. F3 toggles in the Win32 window proc (same hook as key stamps); legacy with no hook uses IsKeyPressed(KEY_F3). Default visible. TEKKEN4_HUD=0 hides. TEKKEN4_HUD_LOG=1 prints one stdout line per second: `[hud] s=N game= host= input= avg= input_ms= avg_ms= n=`. Numbers on screen are the 2 Hz snapshot (last 1 s of presents, refreshed every 0.5 s). GAME counts presents whose vsync tick changed. HOST counts presents. INPUT is last t4-t1; AVG is the last 10. Box is DrawRectangle black alpha 190, text white 18 px.

t1 is still WM_KEYDOWN QPC (not auto-repeat). t2 is stamped from sampleKeyboard on the fast-path pad read, because scePadRead calls notePad only when TEKKEN4_INPUT_LAG=1 (Pad.cpp, not owned). notePad still stamps if the slot is still stage 1. t4 is the swap of the latch after t2. No frame hash unless TEKKEN4_INPUT_LAG=1. g_open==0 skips the mutex on note/latch/swap. Hash path and `[input-lag]` lines unchanged when the env is on.

## fps (airport practice, Kazuya vs CPU Yoshimitsu)

logs/grok/hud-on (HUD on, TEKKEN4_HUD_LOG=1, TEKKEN4_PERF_LOG=98): perf seconds 75-97 all 60 frames (n=23 mean 60.00), GS 314-322 ms mean 317.78. HUD s=76-98 game mean 59.78 (21/23 equal perf at s=perf+1; two seconds 58 and 57), host 60. Menu perf seconds 31-41 all 60; HUD s=32-42 game 60 host 60. Movie perf seconds 22-27 all 30 while HUD game stays 60: the vsync tick still changes at 60. Stage card frame: 1 airport 9.8. frame_85s.bmp 640x448 blank=false mean rgb 74.27/71.2/80.3.

logs/grok/hud-off: TEKKEN4_HUD=0, process killed at 108 s, stdout perf stops at second 59 (buffer). Menu seconds 31-41 mean 60.00. frame_85s.bmp blank=false mean 74.33/71.23/80.33. Not used for fight fps.

logs/grok/hud-off2: clean exit, same env. perf seconds 75-97 n=23 min 58 max 62 mean 60.04. GS 184-284 mean 232.83. Menu 31-41 mean 60.09. No [hud] lines. Stage card 1 airport 1.5.

Fight frame count is unchanged (60.00 vs 60.04). GS ms was higher on the HUD-on run; both stay under the 60 cap. Not a second pair, so the GS gap is not pinned on the overlay.

## input

logs/grok/hud-lag: tools/input_lag.ps1 -Task hud -Mode fast -Present paced, 24/24 samples, freq 10000000. meas t4-t1 median 21.36 ms mean 21.76 ms (stderr seq, vk 83/87). Every HUD input_ms with n>0 matches some press t4-t1 within 0.049 ms (41 lines, 0 farther than 0.15). Rolling avg while n=10 was 19.7-24.0 ms.

## tests

cmd /c tools\build_tests.cmd after the last ps2_input_latency.cpp edit: Total 482, Passed 482, Failed 0.

## build

cmd /c tools\grok_build.cmd hud, exit 0, exe external/wt-hud/out/grok-hud/ps2xRuntime/ps2EntryRunner.exe.
