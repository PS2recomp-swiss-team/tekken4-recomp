# no-interlace notes

## Plan
1. Delay-slot switch: emit both words inside branch delay-slot emission (function_emitter override into ControlFlowEmitter).
2. Switch no_interlace: F48F994A words 0x0022B138 / 0x001EDC24 / 0x001E2254 on v2.00; gsinterlacemode flagged (PCSX2 display).
3. F2 checkbox + PS2X_SETTINGS no_interlace=; load settings at TU init so boot GS reset sees it.
4. Scratch recompile, diff 3 functions, then generated/, grok_build, tests, 2x on/off shots + PRESENT_LOG.

## Emitter
- Removed throw "switch patch in a branch delay slot is not supported".
- emitSwitchableDelaySlot builds if (PS2_SWITCH) {patched} else {original} as delaySlotOverride (resume path included).
- Still throws if patched word is branch/jump, or if delay slot is a GIF DMA kick completion.
- hasRealDelaySlot true when switchName set (nop delay slot + patched addiu).

## Recompile (prior + this)
- Scratch toml output logs/grok/no-interlace-gen/; 4811 same vs generated/, 3 differ: FUN_0022b0c8, FUN_001edbf0, FUN_001e2210.
- Real ps2_recomp into generated/; grok_build no-interlace linked ps2EntryRunner (out/grok-no-interlace).
- Tests: cmd /c logs/grok/no-interlace-tests.cmd -> 496/496 0 failed (7 new delay-slot switch cases in code_generator_tests.cpp all Passed).

## Settings
- noInterlace default false; PS2X_SETTINGS no_interlace=; applySwitchesLocked sets ps2_switches::set("no_interlace").
- Static TU init ps2_graphics::get() so boot sceGsResetGraph sees the switch (consumed at GS reset, not live).
- F2 checkbox; disabled hint restart if toggled mid-run.

## Words (v2.00)
- 0x0022B138 addiu a1,4->6 jal delay FUN_0022af18: GS table row 4 PAL interlaced SMODE2=3 h=0x100 -> row 6 DTV 480p SMODE2=2 omode 0x50 h=0x1C0. This is the bob-removing word.
- 0x001EDC24 addiu v0,2->9 b delay; sb v0 at struct+2 when byte+3 nonzero. Not SMODE2.
- 0x001E2254 addiu v0,1->2; sb at 0x0036E9ED. Not SMODE2. Do not add alone.
- gsinterlacemode=1 not taken (PCSX2 display).

## Measurements (this session)
Present fieldOffset bob (gs_hw_backend fieldOffset=round(scale) when SMODE2 interlaced+frame+odd) is gone on host when switch on.
Game vsync even/odd copy (0x22aaf8) still produces +/-2 guest px on opposite-field pairs in 480p.

2x OFF menu (logs/grok/no-interlace-off-menu, PAL60+main menu, scale 2, 1280x896):
- host 38-43: best_shift +1,-1,+1,-1,+1; unshifted_mad ~8.4-8.7; best_mad ~1.7-2.5
- guest 38-39 shift 0 mad 0.255 (same field) BUT host 38-39 shift 1 mad 1.74: present fieldOffset, not guest copy
- present s38-43 spread 213,401,318,401,215,235
- menu_screen on 2x-downsampled frame_38s: mode/story dist 12.94
- 60 fps s1-10, s31-43; movie 30 fps s21-28

2x ON menu (logs/grok/no-interlace-on-menu, same keys, 1280x1024, extra fbp=140):
- host 38-43: best_shift 0,-1,0,+1,0; same-field pairs mad 0.33-0.60
- guest 38-39 shift 0 mad 0.367 matches host 0: fieldOffset gone
- guest 39-40 shift 2 mad 0.627 unshifted 6.23: remaining game field copy
- present s38-42 spread 162,167,166,167,162
- 480p skips/shortens display menu: movie starts s7 (30 fps); keys 10/12 land in movie
- classify_tall 640x512: other/tall dist 58.71 (menu_screen only knows display at 512)

2x ON arcade timed (logs/grok/no-interlace-on-arcade): movie s7-28 30fps; fight s51-94 60 fps GS 32-167; frame_20s movie mean RGB 132/115/133 blank=false; frame_38s menu; frame_50s load blank; frame_70/80/90 fight blank=false. HUD GAME 60.
2x OFF arcade timed (logs/grok/no-interlace-off-arcade): display until ~20 (frame_20s 98.66% black); movie s22-28 30fps; fight s51-94 60 fps GS 49-221; frame_38s mode-like 55/57/65; frame_70/80/90 fight blank=false. Switch off unchanged.

run_fixed_fight -Task no-interlace ON: menu step failed: display (1280x1024 dist 999). menu_screen rejects any size except 640x448 and 640x512. 2x always 1280x*. Closed-loop unusable at 2x even OFF (1280x896). Timed keys used.

## Open for Claude
- tools/menu_screen.py: 2x 1280x896/1024 and 480p 512-tall post-display screens
- docs/pnach.md still says No-Interlacing "not added"
- 0x22aaf8 field copy still runs in 480p; remaining +/-2 guest on opposite fields
- F2 no_interlace mid-run needs restart (boot GS reset)
