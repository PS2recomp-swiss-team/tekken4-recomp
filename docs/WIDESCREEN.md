# Widescreen 16:9 (US build SLUS-20328)

Setting `TEKKEN4_WIDESCREEN` = **0** / 1 (also `on`, `16:9`); Easy Launcher: Settings, "Widescreen 16:9"; OpenRecomp:
Tekken 4 settings, Display, "Aspect ratio" 4:3 / 16:9. **F9** switches it while playing. Runtime patch 89.

What the player sees: fights (and every other scene with 3D) at 16:9 with a wider view: the sides show what lies
beyond the 4:3 picture. The HUD (life bars, timer, names) keeps its 4:3 shape in the middle. Menus, movies and
loading screens stay 4:3 with black bars at the sides. The window opens 16:9.

Online: each player picks their own. A 16:9 player and a 4:3 player play together; nothing of the setting reaches
the game's simulation (below), so there is no desync and no build difference.

## How it works: host side only

The game runs its own 4:3 code; no guest instruction, guest memory word, IOP state or EE cycle changes. All of it is
in the GS frontend (`GS::widescreenAdjust`, `gs_frontend.cpp`) and the window (`ps2_runtime.cpp`):

- **3D** (VU1 = GIF PATH1 draws into a 640-wide target): x squeezed to 3/4 around the screen centre. The 4:3 view then
  fills the middle 480 pixels of the target and the sides fill with geometry the game draws beyond the 4:3 edges.
  This works because the game's VU1 microprograms map their vertices straight to GS screen coordinates and clip
  only against the GS's 4096-unit guard band (the test after the perspective divide), not against the screen:
  the geometry beyond the 4:3 edges already reaches the GS, where the 640-pixel scissor used to drop it.
- **EE 2D** (PATH2/PATH3) into a target that holds 3D of this or the last picture: squeezed the same way. The HUD
  keeps its shape and place, the hit sparks the EE projects itself as sprites stay on the fighters.
- Not squeezed: draws that read a render target (frame-buffer format texture >= 512 texels wide whose base lies in a
  recent target: the back->display copy, post effects; they pass the "3D" mark on to their own target) and draws
  spanning the whole width or >= 400 lines (fills, fades, flashes; the game clears the screen with ten 64-pixel
  columns, which squeezed would leave the sides uncleared).
- **Window**: a latched picture whose display circuit or display source holds 3D of this or the last picture is
  shown at 16:9, anything else at 4:3. With shared GL presentation (no pixels read back) the targets come from the
  presentation request (display circuits, preferred display source).

`PS2X_WS_DEBUG=1` prints a `[ws]` line every 120 pictures (3D draws, squeezed 2D, skipped by reason, targets).

## Why not the PCSX2 patch's instruction words

The PCSX2 widescreen patch for SLUS-20328 (six words: the camera's and a second projection's aspect argument
0x216EA0 / 0x1F6BF8, a viewport width 0x18D408, a matrix builder 0x200D84..94) was tried first as runtime-switchable
guest instructions. Offline, same input script, words on vs off:

| part | first difference |
|---|---|
| guest RAM | frame 1056 (menus) |
| EE cycle at the frame boundary | frame 1862 |
| IOP state | frame 1890 |
| fighter blocks 0x2A95B0 / 0x2AA4D0 | +0xDA8 from the first fight frames, whole blocks by frame 4200: the fight diverged |

Cause: FUN_00182A80 projects each fighter with the camera matrix and stores the fighter's screen position
(`cvt.w.s`) at player +0xDA8 / +0xDAC; 0x1D2B04 / 0x1D2BD4 compare the two fighters' values and the camera code
(0x216500) reads them. A wider projection changes gameplay, and the extra visible geometry costs the EE ~5 ms per
fight frame. So the words would make a 16:9 and a 4:3 player desync. They are not used.

## Evidence

Offline (measure mode, same script, NETHASH every 30 frames, RDRAM dumps): widescreen on vs off: see the table in
"Measured" below. Netplay pairs on one PC (tools\net_pair.ps1, RTT 150, jitter 5, 3 % loss): see "Measured".

## Measured

(filled in by the runs below)
