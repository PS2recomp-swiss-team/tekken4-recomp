# Graphics: progressive 480p, internal resolution, anti-aliasing (US build SLUS-20328, GL GS backend)

Status 2026-10-30. Goal (user): the picture of a real PC port: no interlace lines, no upscaling seams, sharp at high
resolutions, anti-aliased, settings like T5DR Online. All switches are environment variables of the game process
(the launcher, `launcher\t4core.py`, sets them). Defaults are in **bold**.

## Settings (launcher list)

| setting | switch | values | notes |
|---|---|---|---|
| Internal resolution | `TEKKEN4_INTERNAL_RES` | lowest, **native**, 1080p, 1440p, 4k, auto | T5DR's steps. Picture height 448 x scale: lowest 0.5x (224 lines), native 1x (448, the PS2's), 1080p 2.41x, 1440p 3.21x, 4k 4.82x. auto = the step of the window's monitor (largest of 1080p/1440p/4K not taller than its desktop, else native), at most 1080p on integrated graphics (GL renderer string: Intel without Arc, Radeon "Graphics"/Vega APUs, software renderers). |
| (raw override) | `PS2X_GS_HW_SCALE` | a number (0.5 .. 8, fractional ok) or a step name | wins over `TEKKEN4_INTERNAL_RES`; kept for tools and old launchers. The launcher should set `TEKKEN4_INTERNAL_RES` (or put the step name into `PS2X_GS_HW_SCALE`) instead of the old integer scales 1..5. |
| Progressive scan | `TEKKEN4_PROGRESSIVE` | **1**, 0 | 1 = the game's own 480p mode: full 448-line frames, no fields, no line doubling. 0 = NTSC interlaced FRAME mode as on a TV. Netplay always uses the default (both peers the same). |
| Anti-aliasing | `TEKKEN4_AA` | off, **fxaa**, smaa, ssaa2, ssaa3, ssaa4, msaa2, msaa4, msaa8; `+` combines (e.g. `ssaa2+fxaa`); 1/on = fxaa, 0 = off | fxaa = FXAA 3.11 (quality preset) on the presented picture. ssaaN = the scene drawn N times larger per axis and averaged down (true supersampling; costs N^2 the fill rate). msaaN = N samples per pixel done as SSAA (sqrt N per axis), see "Why no MSAA". The drawn size is capped at 8x native (4K + msaa4 draws at 8x = 1.66x per axis). smaa = FXAA (SMAA needs its precomputed lookup textures, not in this tree). `TEKKEN4_FXAA_SUBPIX` = FXAA sub-pixel amount 0..1 (**0.5**). |
| Anisotropic filtering | `TEKKEN4_ANISO` | 1/off, 2, **4**, 8, 16 | filtered taps along the long axis of each pixel's texture footprint for filtered 3D draws (the game has no mipmaps): sharper, less shimmering floors at a distance. 8 cost the 4K step 3.4 fps on the Arena stage (56.6 vs 60.0), hence 4. |
| 2D / HUD | `TEKKEN4_HUD` | **soft**, sharp | sharp = "sharp bilinear" for magnified 2D sprites of game textures (HUD, menus, fonts, portraits): each texel keeps its colour with a one-pixel smooth edge instead of the GS's bilinear blur stretched over several pixels. Only above native. |
| Fullscreen | `TEKKEN4_FULLSCREEN` | **0**, 1/borderless, exclusive | 1 = borderless fullscreen on the window's monitor; exclusive = exclusive fullscreen at the monitor's resolution (no desktop compositor in between: about one refresh less latency than a window). **F11** toggles while playing (Alt+Enter is not used: Enter is the pad's Start). |
| Window scaling | `TEKKEN4_WINDOW_FILTER` | **area**, sharp, bilinear, nearest | how the picture is scaled to the window: area = averages all picture pixels under a window pixel when the picture is larger (a 4K picture in a 1080p window = supersampling), bilinear when it is smaller; sharp = sharp bilinear when enlarging (native in a big window). |

Developer switches: `PS2X_GL_SPRITE_SNAP=0` (old sprite edges), `PS2X_GL_REGION_LINEAR=0` (CLAMP region modes point
sampled as before), `PS2X_GS_NATIVE_LINES` (picture height the steps are computed from, 448).

Suggested: a strong graphics card at a 1440p screen: `TEKKEN4_INTERNAL_RES=auto` (= 1440p), AA fxaa; for the best
picture `TEKKEN4_INTERNAL_RES=1440p` + `TEKKEN4_AA=ssaa2+fxaa` (draws at 2880 lines; fps not measured yet). Integrated graphics: auto
(1080p at most) or native.

## What was wrong and what changed

### 1. Interlace lines -> the game's own progressive mode (runtime/tekken4_overrides.cpp)
The US game runs NTSC interlaced in FRAME mode: it draws a 640x448 frame, and its vsync handler (0x22a178) copies the
even or odd lines (CSR.FIELD) into a 224-line display buffer; the runtime showed that field line-doubled with a
one-line field offset (patches 03/06): visible line structure and edge flicker. The ELF already has the 480p path
(the PAL release offers "Progressive Scan"): the video-mode setup `FUN_0022a598(keep, index)` takes entry `index` of
the 6-byte table at 0x31e970 (interlace, omode, double-buffer psm, display FBP):

| index | interlace | omode | psm | display FBP | copy packets (0x2ce550) |
|---|---|---|---|---|---|
| 0 | 0 | 2 NTSC | CT24 | 0xd2 | same both fields |
| 1, 2 | 1 | 2 NTSC | CT24 | 0xd2 (640x224 field) | even / odd lines (what the US game uses: index 1) |
| 3, 4 | 1 | 3 PAL | CT24 / CT16 | 0xd2 | per field |
| **5** | 0 | 0x50 DTV480P | CT24 | 0x8c (640x448) | **one packet, whole frame** |
| 6, 7 | 0 | 0x50 | CT16 | 0xd2 | 6: per field, 7: one |

`index` comes from the request table at 0x31e4e0 (request -> index) and is 1 for the US game. The override maps 1/2
to 5 (`TEKKEN4_PROGRESSIVE`, default on). Index 5 calls sceGsResetGraph(0, 0, 0x50, 1), sets the 480p flag
(0x1ccafb4: the vsync handler then toggles its "field" itself instead of reading CSR.FIELD, and the copy packet is
the same for both), builds a 640x448 CT24 display buffer and DISPLAY with DH 447, MAGH 1, SMODE2 2.
Second fix needed: sceGsResetGraph is the runtime's stub, which never wrote libgraph's sceGsGParam (0x3018c0:
interlace, omode, ffmode; the ELF data holds 1, 2, 1). FUN_0022a370 reads omode there and took the interlaced
double-buffer setup (SMODE2 3, DH 895: line doubling again). The override now stores the three values on reset
mode 0 like the real function (interlaced mode writes the values that were there anyway).
Game logic and timing: the vsync handler and the 60 Hz pacing are the same; only the display buffer, its copy packets
and the 480p flag differ (all in RDRAM, part of the state hash: both netplay peers must use the same mode, which
netplay forces). Rollback self-test with the final build: see "Checks".

### 2. Upscaling seams (PS2Recomp patch 70, docs\gfx\patches)
The game's full-screen pass copies the back buffer into the display buffer as 64-px wide sprite columns from X 64k to
64k + 63.5. The GS covers pixels 64k .. 64k + 63 (pixel n is covered when x0 <= n < x1) and the next column starts at
64k + 64; at scale n the GL quad covered host pixels only up to 64k + 63.5, so the host pixels of [63.5, 64) stayed
unpainted: a thin black line every 64 PS2 pixels through the picture and HUD (at 5x, 2 host pixels). In interlaced
mode the field copy's 16-row bands added steps every 32 output lines.
Fix (like PCSX2's "align sprite" for upscaled copies, done exactly): every sprite quad is snapped to the PS2 pixels the
GS covers, [ceil(x0), ceil(x1)), with the texture coordinates continued linearly to those edges (the same sampling
function, so native is unchanged: static menu frames are bit-identical with and without). Shared strip sides are now
found among the last 48 sprites of a batch (a copy drawn as columns of bands has its left neighbour several sprites
back) and the texture clamp opens there. With integer edges, fractional scales (1080p = 2.41x ...) are watertight.

### 3. PC options (PS2Recomp patches 71-73; patch 73 = fullscreen + aniso default 4)
- Internal resolution steps, `auto` from the monitor and the GL renderer (integrated graphics).
- Uploads into render targets at scales other than 1 (the intro movie writes its pictures straight into the back
  buffer): staged at native size and blitted filtered into the scaled target; before, the movie stayed black above
  native.
- FXAA / SSAA post passes in the GS presentation (`Present`): compose the display circuits at the internal
  resolution, FXAA, then an area resolve to the step's size; the window gets that picture (shared texture).
- Anisotropic taps, sharp 2D, bilinear filtering of the CLAMP region modes in the draw shader. The region modes
  (REGION_CLAMP / REGION_REPEAT, ~95% of the stage draws) were point sampled even when the game asks for bilinear;
  now they filter like the GS (the wrap applies to each of the four texels).
- The window draws the picture through a filter shader (area / sharp / bilinear / nearest); the shared picture used
  to be drawn nearest, so a picture larger than the window aliased.

### Why no MSAA
The GS emulation reads its render targets back in many ways: the destination colour in the shader for GS blends that
fixed-function blending cannot express, the destination alpha test (DATE) and Z kept in colour memory (texture
barrier feedback), sampling a target as a texture in another format (16-bit views, channel shuffles, CLUTs from
targets), and downloads to GS memory. With multisampled targets every one of these needs a resolve or per-sample
shading, and the GS's exact per-pixel results (shadow volumes, Z inversion passes) would change at edges. So the
`msaaN` values give the same sample count as supersampling (N samples per pixel, sqrt N per axis), which is exact
and works with every pass; FXAA is the cheap option.

## Checks (final build: t4-gfx 702a93a = t4-us 25265d7 + patches 70-73, RTX 3090, 2560x1440 monitor)

Every step, Story Battle Kazuya vs Paul on the beach (tools\gfx_sweep.ps1; fps = game frames per second over the fight
seconds 36..60; seams = mean |gradient| on the 64-column / 32-row page grid vs. elsewhere, equal = no lines). Sheets
`logs\gfx
es_<step>.png` (movie, menu, character select, fight, 1:1 HUD crop), numbers in `res_<step>.txt`.

| step | picture | fight fps (min) | seam grid vs elsewhere (cols / rows) | movie, menus, char select |
|---|---|---|---|---|
| lowest | 320x224 | 60.0 (59) | 20.3/18.5, 28.8/33.5 | ok |
| native | 640x448 | 60.0 (60) | 10.7/10.9, 20.4/21.2 | ok |
| 1080p | 1543x1080 | 60.0 (60) | 4.7/5.6, 12.3/11.9 | ok |
| 1440p | 2058x1440 | 60.0 (60) | 7.1/6.9, 11.9/11.9 | ok |
| 4k | 3086x2160 | 60.0 (60) | 2.7/3.1, 7.2/7.2 | ok |
| auto (= 1440p on this monitor) | 2058x1440 | 60.0 (59) | 6.1/7.0, 12.4/11.8 | ok |
| before (5x, old build, logs\scale5) | 3200x2240 | - | **161 / 4.4** (cols) | lines every 64 px |

Heaviest stage (Practice, Arena, sound on, tools\gfx_perf.ps1 -> perf_fight.ps1; AA fxaa, aniso 4):
native 60.0 (min 60), 1080p 60.1 (60), 1440p 60.0 (60), 4k 60.1 (59); integer scales with the build before the aniso
default change (aniso 8): 2x 60.0, 3x 60.0, 4x 59.8 (another game ran for a second), 4k 56.6 (aniso 8) -> 60.0 with 4.
Building (native) 56.5 fps as before these changes (EE-bound, docs\PERF.md). Raw tables: logs\gfx\perf	able.md.

Rollback self-test with the final build (p2c: TEKKEN4_RB_MODE=test, all cuts, mispredict, sound off; progressive on,
FXAA, aniso 4): **232 rollbacks, 514 re-simulated frames compared, 0 mismatches**, restores 232/232
(logs\perf
b\gfx_p2c, logs\gfx\perf
b_selftest.txt).

Native, static menu: identical pixels with and without the sprite snapping (PS2X_GL_SPRITE_SNAP=0).

Fullscreen: TEKKEN4_FULLSCREEN=1 gives a 2560x1440 borderless window and the fight still runs at 60 fps
(logs\gfx\sweep_final_1440p_*); GDI captures (PrintWindow, CopyFromScreen) of the fullscreen window come back black
(flip presentation of a window covering the monitor), so the fullscreen picture itself still needs a look by a person.

Evidence (logs\gfx\evidence): seams_5x_hud.png and seams_5x_vs_4k_mid.png (before/after crops of the old seam areas),
native_interlaced_vs_progressive.png (line doubling gone), hud_native_vs_4k_sharp.png (TEKKEN4_HUD=sharp at 4K with
ssaa1.5+fxaa), res_*.png per step, after_4k_sharp_ssaa_fxaa.png, final_1440p_fight_frame.png.

## Reproduce

Patches: docs\gfx\patches8..73 (against PS2Recomp t4-us 25265d7; checked: t4-us + 70..73 = the tree of t4-gfx);
the video-mode override as docs\gfx	ekken4_overrides-video-mode.patch (against HEAD of runtime	ekken4_overrides.cpp;
the same block is in the working copy next to the movie-audio edits).

```
:: build the graphics worktree (D:\tekken4-fork-gfx, branch t4-gfx) with the committed overrides + the video-mode override
::   (tools\gfx_stage.py stages HEAD's runtime\*_overrides.cpp plus the progressive block of the working copy)
:: every step: fight run (fps from TEKKEN4_PERF_LOG, seconds 36..60) + intro movie run, sheet + seam numbers
powershell -ExecutionPolicy Bypass -File tools\gfx_sweep.ps1
powershell -ExecutionPolicy Bypass -File tools\gfx_sweep.ps1 -Steps 1080p,1440p -Env "TEKKEN4_AA=ssaa2+fxaa" -Label _ssaa2
python tools\gfx_sheet.py <step> <fight run> <movie run> <out.png>   (Pillow + numpy: the system Python)
```
