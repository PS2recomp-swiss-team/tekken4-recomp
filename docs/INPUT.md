# Input latency: gamepad, frame chain, run-ahead

Work of 2026-10-30 (branch `t4-input` of the PS2Recomp fork, worktree `D:\tekken4-fork-input`, rebased on `t4-us`
4b07b2f). User report: "gameplay lags with controller" (the keyboard was already fast since patch 31). Later scope
(lead): also remove the game's own input lag (T5DR port: "a jab shows ~35-40 ms after the press in fullscreen, a
frame less than before").

Patches against `t4-us` in `docs\input\patches` (numbered from 60: 58 and 59 were taken by the movie/MPEG
patches meanwhile; not yet in `patches\`):
- 60 `189b825` gamepads: XInput read directly at pad-read time, 1 ms tap latch, raylib fallback
- 61 `8a79c6d` frame-chain instrumentation (vblank picture hash, present log)
- 62 `22c4b52` run-ahead (`TEKKEN4_RUNAHEAD`, default off); 63 `8775a27` run-ahead pauses during movies
- 64 `8fe8cbd` vblank-phase-locked present (option); 65 `25265d7` present 2 ms after each guest vblank (default)

**Result (menu, press -> first changed frame, keys and scripted pad presses in the same run, 40 each):**

| | key median / p95 | gamepad median / p95 | gamepad presses picked up a frame late |
|---|---|---|---|
| before (old pad path, old presenter clock; `logs\input\before_both`) | 21.9 / 39.7 ms | 20.7 / 27.3 ms | 5 of 40 |
| after (defaults; `logs\input\final_both`) | **14.5 / 19.9 ms** | **10.8 / 20.6 ms** | **0 of 40** |

Left stick -> d-pad (scripted stick, `logs\input\final_stick`): 24 of 24 presses moved the cursor, 11.9 ms median.
Rollback self-test with this build (run-ahead off, sound off): **0 mismatches** of 514 re-simulated frames, 232
rollbacks, restores 232/232 (`logs\input\p2c_final`, before the rebase onto 4b07b2f; the rebase touched nothing of it).

## 1. Gamepad path

### Cause

Before: every gamepad came from raylib/GLFW. GLFW reads XInput/DirectInput only inside `PollInputEvents`
on the window thread (`run()`: once per ~1 ms idle wait, once after the readback, once inside `EndDrawing`),
and the game thread copied raylib's last state at `scePadRead`. The keyboard instead is sampled at the pad
read itself (`GetAsyncKeyState`, patch 31). So a pad press that arrived after the window thread's last poll
but before the game's pad read was seen one game frame later (+16.7 ms). Port 2 (VS) used the same path.

Measured with a scripted XInput pad (fake `XInputGetState`, see "How it was measured") pressed at random
sub-frame times in the mode-select menu, interleaved with posted key presses in the same run:

| path | presses picked up one pad read late (+16.7 ms) | raylib sample age at the pad read |
|---|---|---|
| old (raylib snapshot, `TEKKEN4_PAD_BACKEND=raylib`) | **3 of 40** (`logs\input\both_raylib1`) | avg 0.6-0.9 ms, max 2.3-3.7 ms |
| new (XInput read at the pad read) | **0 of 40** (`logs\input\ra0_both`) | - (fresh read) |
| keyboard (patch 31), same runs | 0 of 40 | - |

On this PC the old path cost little (the window thread polls ~1 kHz while idle); it grows with whatever
keeps the window thread busy (readback, swap, higher internal resolution, a slow driver). The real Xbox
controller on this PC: `XInputGetState` 8-9 us average (max 49-240 us), `logs\input\kbd1` (`[pad-stats]`).

What the user calls "lag" is most likely the whole chain (section 2: ~3 game frames + the presenter), which
a keyboard player feels the same way; the gamepad itself is now on the keyboard's footing.

### Fix (fork commit `189b825`, patch 60)

`ps2xRuntime/src/lib/ps2_host_pad.cpp` (`runtime/ps2_host_pad.h`):
- **XInput read directly** (xinput1_4 / 1_3 / 9_1_0 loaded at run time) at the moment the game reads the pad
  (`scePadRead` port 0 via `PSPadBackend::readState`, ports 1+ and the netplay frame sample via
  `sampleHostPad`): no cache, every read is fresh.
- **1 ms poll thread** (high-resolution waitable timer; ~650 wakes/s measured) that only latches presses that
  start and end between two pad reads: such a tap is reported held for exactly one read (T5DR's tap latch).
  Releases are never delayed. Empty XInput slots are probed once a second (hot-plug).
- **Other pads** (DualShock 4 / DualSense without DS4Windows/Steam, generic DirectInput) still come from
  raylib/GLFW (its SDL mapping database), now as a snapshot the window thread publishes right after each raylib
  poll; XInput pads GLFW also sees are skipped (GUID `78696e707574...`), so no pad counts twice.
- **Layout** = the keyboard's (patch 29) by position: A/B/X/Y = Cross/Circle/Square/Triangle, LB/RB = L1/R1,
  LT/RT = L2/R2 (XInput trigger threshold 30/255), Back = Select, Start = Start, LS/RS = L3/R3, d-pad = d-pad.
  **Left stick** also presses the d-pad (8-way: on past 50 %, off below 40 % per axis); both sticks get a radial
  deadzone of 24 % (`XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE`) rescaled to full range; `TEKKEN4_PAD_STICK_DPAD=0` turns
  the stick -> d-pad off.
- **Two pads**: host controllers are ordered XInput slots first, then DirectInput pads; port 1 (P1) = keyboard +
  host pad 1, port 2 (P2) = host pad 2, as before (patch 13: port 2 disconnected without a second pad).
- **Netplay/rollback contract unchanged**: the netplay frame sample (`npSampleLocal` -> `sampleHostPad`) reads
  the pad once per frame at the boundary like before (now fresh XInput); rollback re-simulation never reads
  devices (the provider answers). A speculative run-ahead frame (section 3) reads but does not consume taps.
- Switches: `TEKKEN4_PAD_BACKEND=raylib` (old path), `TEKKEN4_PAD_STATS=1` (every 5 s a `[pad-stats]` line:
  reads/s, XInput call cost, raylib sample age, taps, poll rate), `TEKKEN4_PAD_TEST=...` (scripted pad, below).
  stderr shows `[pad] XInput slot N connected` / `[pad] raylib gamepad N '<name>' connected (...)`.

## 2. Frame chain: game frames vs host

### Game's own lag (native): 3 frames

`TEKKEN4_VBLANK_HASH=1` (fork commit `8a79c6d`): at every VBlankStart the game thread latches the shown picture
and logs its exact pixel hash with the buttons the game read in that frame. Two deterministic runs
(`TEKKEN4_RAND_SEED=1`, rollback `measure` driver with scripted input, CPU renderer) that differ only in one press;
`tools\chain_compare.py` finds the first shown picture that differs:

| press (Story Battle, Kazuya vs Yoshimitsu) | read in frame | first different picture | game frames |
|---|---|---|---|
| Square (left punch, jab) | 2500 | 2503 | **3** (`logs\input\chainA2` vs `chainB2`) |
| Cross (left kick) | 2650 | 2653 | **3** (`logs\input\chainC` vs `chainB3`) |

So the game logic of frame N reads the pad, and the first picture that shows the reaction is scanned out in
frame N+3 (PS2 hardware: the same 3 frames; the game keeps DISPFB1 at 0 and copies its picture there).

### Host-added (presenter), GL renderer with shared presentation (the user's setup)

`TEKKEN4_PRESENT_LOG=1`: per presented guest frame the host time of its VBlankStart, the latch and the swap
(`tools\chain_compare.py --present`), Story fight, `logs\input\presP`:

| | median | p95 |
|---|---|---|
| guest VBlankStart -> latch (16.667 ms present clock, random phase) | 9.3 ms | 15.5 ms |
| guest VBlankStart -> swap returned | 11.3 ms | 25.5 ms |
| guest frames never shown (tick jumped by 2) | 189 of 2234 (8.5 %) | |

Plus the Windows compositor in a window (about one refresh; not visible from inside the process; fullscreen
avoids it, T5DR measured the same "+1 frame in a window").

Total for a jab, read at a random time in frame N: wait for the pad read (0-16.7 ms, ~8 avg) + 3 game frames
(50 ms) + presenter (~11 ms median) + compositor -> roughly 70 ms + a refresh in a window.

(Story fight, `presP`; in the Practice fights below the old clock gave a 6.9-7.8 ms median.)

### Host fix: present right after the guest vblank (fork commits `8fe8cbd`, `25265d7`)

The paced present ran on a free 16.667 ms clock, so it latched each guest frame at a random phase after its
vblank, and about every 50th guest frame was never shown (the two 60 Hz clocks drift). Now the paced present
is due 2 ms after each guest VBlankStart (`TEKKEN4_PRESENT_PHASE_MS`, default 2; negative = the old clock; the
clock stays as the fallback when no guest frame comes). Practice fight, GL renderer, sound on, 60 fps both ways:

| Practice fight (Kazuya vs Yoshimitsu) | vblank -> swap median | p95 | guest frames never shown |
|---|---|---|---|
| beach, old clock (`logs\input\ffp_beach`) | 6.9 ms | 16.7 ms | 121 of 6254 (1.9 %) |
| arena, old clock (`logs\input\ffp_arena`) | 7.8 ms | 18.0 ms | 125 of 6390 (2.0 %) |
| beach, 2 ms after the vblank (`logs\input\ffp_beach_ph2`) | **5.4 ms** | **7.1 ms** | **24 of 6464 (0.4 %)** |

The picture latched 2 ms after the vblank is already the new one: press -> first changed frame in the menu
(posted keys and scripted pad presses in the same run, readback probe):

| menu, 40 + 40 presses | key t5-t0 median / p95 | pad t5-t0 median / p95 | t5-t2 (pad read -> new picture) |
|---|---|---|---|
| old clock (`logs\input\ra0_both2`) | 19.6 / 39.0 ms | 18.2 / 28.1 ms | 12-13 ms |
| 2 ms after the vblank (`logs\input\ph2_both`) | **14.9 / 21.0 ms** | **14.6 / 20.0 ms** | **4.4-5.0 ms** |
| final defaults (`logs\input\final_both`) | 14.5 / 19.9 ms | 10.8 / 20.6 ms | 4.6-5.0 ms |

(Across runs the medians move by several ms with the phase between the game and the host clock; compare the
p95 and t5-t2 columns.) `TEKKEN4_INPUT_PRESENT=tick` (present on every guest tick) stays unusable with the
shared GL presentation: the game slowed to a few frames per second (`logs\input\presT`).

Left on the host side: the Windows compositor in a window (about one refresh). Fullscreen (exclusive or a
flip-model swap chain) would remove it; not done here (the renderer agent's area).

## 3. Run-ahead (`TEKKEN4_RUNAHEAD=1`, fork commits `22c4b52`, `8775a27`), default OFF

RetroArch-style single-instance run-ahead on the rollback machinery (`ps2_rollback::capture/restore`, the cuts
of patches 37-42): per host frame the real frame runs hidden (cuts draw, VU1, present; IOP live, its sound is
what you hear), the machine is captured (IOP included), N speculative frames run with the same input (IOP muted,
the last one draws), their picture is latched for the presenter, and the machine is restored. The host deadlines
move N frames earlier once, so the picture of frame k+N is shown when frame k's would have been: the game's
3 frames become 2 (N = 1). `runtime/ps2_runahead.h` lists the switches (`TEKKEN4_RUNAHEAD_START`, `_HIDDEN_CUTS`,
`_STATS`, `_IDLE=22a150` = the game's vsync wait loop, skipped as the rollback driver does).
- Off in netplay and in the rollback test/selfnet modes (they re-simulate already); allowed with
  `TEKKEN4_RB_MODE=measure`, whose per-frame state hash then checks the real timeline.
- The scheduler got a boundary wrapper: the game's boundary hook (rollback driver) only sees real frames.
- Movies: the host MPEG decoder is not in the snapshot; any MPEG call pauses run-ahead for 30 real frames
  (without that the intro movie stuck). Memory card writes would happen twice (speculative + real, same data).
- A speculative pad read does not consume latched taps (the real frame after it does).

**Game results unchanged:** scripted Story Battle with fuzz fight input from frame 2100, rollback `measure`
hashes (RDRAM, scratchpad, VU, scheduler, devices) of every real frame: **0 differing of 4377** against the same
run without run-ahead (`logs\input\raref` vs `logs\input\ra1`, `docs\rollback\rb_compare.py`).

**Cost: 60 fps does not hold.** Practice fight, sound on (`logs\input\ff_*_ra1`, `[runahead]` lines):

| stage | fps without | fps with run-ahead 1 | capture | restore | hidden real frame | speculative frame |
|---|---|---|---|---|---|---|
| beach | 60.0 | **43-44** | 1.45 ms | 1.47 ms | 7.5 ms | 12.5 ms |
| arena | 60.0 | **52-53** | 1.43 ms | 1.45 ms | 5.4 ms | 10.7 ms |

One host frame needs hidden + speculative + capture + restore = 19-23 ms > 16.7 ms. In the menus (30 fps game
logic) it holds 60 fps but gains a frame only every other frame, below the run-to-run noise of the probe
(`logs\input\ra1_both3` vs `ra0_both2`). To make it pay, the speculative frame must get cheaper than ~9 ms (the
GS/VU1 work on the game thread) or the hidden frame cheaper (e.g. the IOP replayed instead of run), or both
frames must run on two cores (a second instance). Until then: `TEKKEN4_RUNAHEAD=0` (the default).

## Summary of the chain (Practice fight, 60 fps, window, GL)

| part | before | now |
|---|---|---|
| gamepad press -> the game's pad read | 0-16.7 ms wait, +1 frame for 3 of 40 presses | 0-16.7 ms wait (as keys), 0 of 40 late |
| game: pad read -> picture with the reaction | 3 frames (50 ms) | 3 frames (2 with run-ahead 1, not at 60 fps yet) |
| guest vblank -> swap | median 6.9 ms, p95 16.7 ms, 1.9 % of frames dropped | median 5.4 ms, p95 7.1 ms, 0.4 % dropped |
| compositor (window) | ~1 refresh | ~1 refresh (fullscreen would remove it) |

## How the user tests by hand

1. Build: `tools\input_build.cmd` (stages the committed overrides, builds `D:\tekken4-fork-input\out\input`).
   Run: `set TEKKEN4_SRC=D:\tekken4-fork-input`, `set TEKKEN4_BUILD_DIR=input`, `tools\run_game.cmd`.
2. Plug the controller in before or after the start; `logs\run.log` shows `[pad] XInput slot 0 connected` (Xbox /
   XInput pads) or `[pad] raylib gamepad 0 '<name>' connected (DirectInput)` (DualShock 4 / DualSense without
   DS4Windows or Steam Input).
3. Layout: A/B/X/Y = Cross/Circle/Square/Triangle (Tekken: X = 1, Y = 2, A = 3, B = 4), LB/RB = L1/R1,
   LT/RT = L2/R2, Back = Select, Start = Start; the d-pad and the left stick both move (stick: past half way).
4. Feel: Practice mode, jab (X on an Xbox pad) again and again, then the same with the keyboard (Left arrow =
   Square, Tekken 1). Both should feel the same now. Numbers: `set TEKKEN4_PAD_STATS=1` -> every 5 s a
   `[pad-stats]` line (reads/s, `xinput_us` = cost of one read, `raylib_age_ms` = age of a DirectInput pad's state
   at the read, `taps`).
5. A/B: `set TEKKEN4_PAD_BACKEND=raylib` = the old pad path; `set TEKKEN4_PRESENT_PHASE_MS=-1` = the old presenter
   clock.
6. Two pads: VS BATTLE needs the second controller; P2 = host pad 2 (XInput slots first, then DirectInput pads).
   With DS4Windows / Steam Input a PlayStation pad can appear twice (virtual XInput + DirectInput): turn one off.
7. Run-ahead (experimental, below 60 fps in fights on this PC): `set TEKKEN4_RUNAHEAD=1` and
   `set TEKKEN4_RUNAHEAD_IDLE=22a150` (+ `set TEKKEN4_RUNAHEAD_STATS=1` for `[runahead]` fps lines).

## How it was measured (reproduce)

New tools in `D:\tekken4-us\tools` (left uncommitted as agreed): `input_build.cmd`, `pad_lag.ps1`,
`input_rb_run.ps1`, `chain_compare.py`. Every game run takes `logs\run.lock`; builds wait for
`C:\T5DROnline\build\int115\HEAVY.lock`.
- Gamepad vs keyboard (menu): `powershell -ExecutionPolicy Bypass -File tools\pad_lag.ps1 -Exe <runner>
  -Presses 40 -Source both -Backend direct|raylib [-Env "A=1;B=2"] -RunDir logs\input\<name>`. Keys are posted at
  40 + 0.8 i s; a scripted XInput pad (`TEKKEN4_PAD_TEST=start=40.4,count=40,period=800,hold=70,what=dpad|stick`:
  a fake `XInputGetState`, no real pad needed) presses d-pad Down/Up 0.4 s later at random sub-frame offsets.
  With `-Backend raylib` the fake pad becomes visible only when the window thread polls raylib, as GLFW does.
  `t2-read` / `missed_reads` = pad reads after the press that missed it (the input path's own delay).
- Game frames: `powershell -File tools\input_rb_run.ps1 -Name chainA2 -Shots 75,105 -Env "TEKKEN4_RAND_SEED=1;
  TEKKEN4_RB_MODE=measure;TEKKEN4_VBLANK_HASH=1;PS2X_GS_BACKEND=cpu;PS2X_DEBUG_PANEL=0;TEKKEN4_RB_INPUT=500:Start,
  800:Start,1040:Start,1280:Cross,1580:Start,2500:Square:3"`, the same without the last press (chainB2), then
  `python -I tools\chain_compare.py logs\input\chainA2\stderr.txt logs\input\chainB2\stderr.txt`.
- Presenter: `TEKKEN4_PRESENT_LOG=1` in any run (e.g. `tools\run_fixed_fight.ps1 -Stage beach -Env
  TEKKEN4_SOUND=1,TEKKEN4_PRESENT_LOG=1`), then `python -I tools\chain_compare.py --present <stderr.txt>`.
- Run-ahead check: the Story script above with `TEKKEN4_RB_FUZZ=2100` in `measure` mode, once more with
  `TEKKEN4_RUNAHEAD=1`, then `python -I docs\rollback\rb_compare.py <ref>\rb_frames.log <ra>\rb_frames.log`.
- Rollback self-test (run-ahead off, sound off): docs\ROLLBACK_PHASE2.md "Reproduce" with this build
  (`tools\input_rb_run.ps1 -Name p2c -Shots 60,100 -Env "<script>;TEKKEN4_RB_MODE=test;TEKKEN4_RB_TEST=..."`):
  `SUMMARY ... rollbacks 232 restore ok 232 bad 0, resim frames compared 514 mismatches 0` (`logs\input\p2c` with
  the gamepad change, `logs\input\p2c_final` with everything).
- Before/after summary at the top: `pad_lag.ps1 -Source both -Backend raylib -Env "TEKKEN4_PRESENT_PHASE_MS=-1"`
  (before_both) vs `-Backend direct` with the defaults (final_both), same build.
