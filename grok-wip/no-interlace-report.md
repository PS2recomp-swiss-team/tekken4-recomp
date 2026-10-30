# no-interlace report

## Result
Present-time 2x field bob (`fieldOffset = round(scale)` in `gs_hw_backend.cpp` when SMODE2 interlaced+frame+odd) is removed by runtime switch `no_interlace` (F48F994A words on v2.00). Host same-content pairs at 2x: OFF shift 1 window px, ON shift 0. Game vsync even/odd copy still yields +/-2 guest px on opposite-field pairs. Menus/movie/fight render; 60 fps fight both on and off. Tests 496/496.

## Mechanism
`0x0022B138` `addiu a1,4->6` (jal delay of `FUN_0022af18`): GS table row 4 `01 03 ...` PAL interlaced SMODE2=3 height 0x100 -> row 6 `00 50 ...` DTV 480p SMODE2=2 omode 0x50 height 0x1C0. Interlace bit clear => `fieldOffset` stays 0. Also `0x001EDC24` (b delay v0 2->9) and `0x001E2254` (store 2 not 1 at `0x0036E9ED`). `gsinterlacemode=1` not taken. Do not add `0x001E2254` alone.

Delay-slot switches: `function_emitter.cpp` `emitSwitchableDelaySlot` as `delaySlotOverride`; `hasRealDelaySlot` true when `switchName` set. Rejects patched branch/jump and GIF DMA kick delay.

Settings: `no_interlace=` in PS2X_SETTINGS; F2 checkbox; TU-init `ps2_graphics::get()` so boot GS reset sees the switch.

## Recompiler / tests
- Scratch gen `logs/grok/no-interlace-gen/` then `generated/`: only FUN_0022b0c8, FUN_001edbf0, FUN_001e2210 differ.
- `cmd /c logs\grok\no-interlace-tests.cmd` (TEKKEN4_SRC=external\wt-no-interlace): Total 496 Passed 496 Failed 0.
- New: JAL delay, BEQ delay, BEQL delay, nop delay, body switch, switch-to-branch throw, GIF DMA kick delay throw. All Passed.

## 2x menu (PAL60 10:Down,12:Cross then 15:Left,16.5:Cross,30:Start,36:Cross)

### OFF `logs/grok/no-interlace-off-menu` (internal_scale=2 no_interlace=0)
- stderr: scale 2.00; fbp 0/210/290; guest 1280x896
- host_38s..43s.png 640x480 blank=false mean RGB ~53/56/63
- field_shift host: 38-39 +1 mad 1.74 unshifted 8.62; 39-40 -1 1.74/8.61; 40-41 +1 2.36/8.36; 41-42 -1 2.48/8.54; 42-43 +1 2.47/8.72
- field_shift guest: 38-39 0 mad 0.255; 40-41 +2 0.96/8.62; 42-43 -2 1.00/8.67
- present s38-43 spread 213,401,318,401,215,235 (1/100 line)
- perf 60 fps s1-19 except transitions; movie 30 fps s21-28
- menu_screen 640x448: screen=mode row=story dist=12.94
- shots: frame_38s.bmp..frame_43s.bmp host_38s.png..host_43s.png

### ON `logs/grok/no-interlace-on-menu` (internal_scale=2 no_interlace=1)
- stderr: scale 2.00; extra fbp=140; guest 1280x1024
- host_38s..43s.png 640x480 blank=false mean RGB ~61/64/73
- field_shift host: 38-39 0 mad 0.331; 39-40 -1 1.82/6.37; 40-41 0 0.602; 41-42 +1 1.89/6.55; 42-43 0 0.322
- field_shift guest: 38-39 0 mad 0.367; 39-40 +2 0.627/6.23; 40-41 0 0.384; 41-42 -2 0.610/6.24; 42-43 0 0.367
- present s38-42 spread 162,167,166,167,162
- movie starts s7 (display menu skipped/short); 30 fps s7-28; 60 fps s31-43
- classify 640x512: other/tall dist 58.71 (menu_screen has no 512-tall mode refs)
- shots: frame_38s.bmp..frame_43s.bmp host_38s.png..host_43s.png

Headline: guest 38-39 both shift 0, host OFF +1 vs ON 0 => present fieldOffset gone. Remaining ON +/-1 host / +/-2 guest when opposite game fields.

## Movie / fight 2x timed arcade (same keys + 40:Down,41.5:Cross,46:Cross)

### ON `logs/grok/no-interlace-on-arcade`
- movie frame_20s.bmp 1280x1024 mean 131.57/114.87/132.98 blank=false; 30 fps s7-28
- menu frame_38s.bmp mean 61.88/65.02/74.10 blank=false
- load frame_50s.bmp blank=true (s50 25 frames)
- fight frame_70s.bmp 101.71/104.26/128.79 blank=false; frame_80s 92.23/96.14/121.54; frame_90s 149.73/144.68/149.35
- host_20s.png / host_80s.png blank=false
- perf s51-94 all 60 fps (GS 32-167 ms); HUD GAME 60
- extra fbp=475 512x1024

### OFF `logs/grok/no-interlace-off-arcade` (unchanged path)
- no fbp=140; guest 1280x896
- frame_20s.bmp 98.66% black (still display); movie 30 fps s22-28
- frame_38s.bmp 55.03/57.36/65.36 blank=false (matches OFF menu)
- fight frame_70s 65.12/62.96/73.47; frame_80s 65.77/63.82/72.20; frame_90s 76.41/72.78/84.37; all blank=false
- perf s51-94 60 fps (GS 49-221 ms); HUD GAME 60

## Closed-loop
`run_fixed_fight.ps1 -Task no-interlace` ON: `menu step failed: display` at ~43s; every poll `size 1280x1024 dist 999`. `menu_screen.py` accepts only 640x448 or 640x512. 2x OFF would be 1280x896, also rejected. Timed keys used.

## Files
- wt-no-interlace: function_emitter.cpp, control_flow_emitter.cpp, code_generator_tests.cpp, ps2_graphics_settings.cpp/.h, ps2_debug_panel.cpp
- config/ghidra_export.toml three no_interlace words
- generated/ FUN_0022b0c8_0x22b0c8.cpp, FUN_001edbf0_0x1edbf0.cpp, FUN_001e2210_0x1e2210.cpp
