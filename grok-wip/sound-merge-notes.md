# sound-merge

Patch vs PS2Recomp HEAD (eb8688b): logs/grok/sound-merge.patch (10 files, owned only). runtime/tekken4_overrides.cpp matches the game-repo HEAD, so logs/grok/sound-merge-overrides.patch is empty. Do not apply sound-merge.patch on top of patches/19 (same sound hunks plus the heap test and the trace). HEAD iop_emulator.cpp does not reference SoundEngine (git grep exit 1). The working-tree dispatch is iop-sched-2's file and is not in this patch; without it the new .cpp is linked and never called.

## Heap (ASK 1)

Gated. iop_memory.cpp reset() sets m_topDown only when TEKKEN4_SOUND is exactly "1"; otherwise bottom-up from HeapBase 0x120000. Floor on the sound route is SoundHeapFloor 0x80000, cursor starts at HeapLimit 0x1F0000. Test is iop_memory.cpp under PS2X_IOP_HEAP_DIRECTION_TEST, wired from CMakeLists.txt inside PS2X_IOP_BUILD_TESTS (off in tools/build_tests.cmd). Standalone logs/grok/heap_direction_test.exe: `heap-direction ok bottom=00120000 top=001ef780 big=00106380` (0x106380+0xE9400=0x1EF780, big>=0x80000). Bottom-up 0xE9400 returns 0.

No-sound run logs/grok/sound-merge-nosound-2. params.txt env is only TEKKEN4_BUILD_DIR=grok-sound-merge. frame_55s and frame_70s: Stage 1 Kazuya vs Law, timer 60, clock 00:00:00. frame_stats blank false (55: mean 28.29/28.65/33.93 pct_near_black 16.39; 70: mean 100.99/97.87/91.49 pct_near_black 2.12).

## Character select (ASK 2)

logs/grok/sound-merge-sound-3. Keys 10:Down,12:Cross,15:Left,16.5:Cross,45:Start,52:Cross,58:Down,60:Cross. Shots 55/75/95/115. Wall 130.2 s. WAV 5232000 frames = 109.000 s. frame_75s is CHOOSE YOUR FIGHTER, Kazuya, timer 16 (mean 125.3/122.93/122.86, blank false). frame_95s is the stage card. frame_115s is the round (timer 59, 00:00:03).

WAV windows: 0-5 rms 0; 5-20 menu bed; 20-45 movie peak 32768; 55-65 rms 0.08102/0.15499 peak 32255/32256; 65-85 rms 0; 85-109 sound returns (peaks 24802, 26180, 15295, 32256, 30679). longest_silence_s 25.929. clipped 1184.

stderr: voice 1 KON at mix 59.916 ssa=12b090 pitch=0555 vol=2caf/2caf adsr=0000/0000, right after sceCdRead lsn=1045690 sectors=15 (ram write 29824 bytes, 14737 nonzero halfwords). endx bit 1 is set by mix 65. peak 0 at mix 70, 75, 80, 85. No KON, no sceCdRead, no ram write until mix 89.100 (stage cue, voice 0 ssa=9dc0). Through the gap: mvol=3f00/3f00 vmix=ffffff/ffffff irqa=0/dc080 attr=4080/40c0 dropped=0 maxAdv=2605.

ISO at LSN 1045690, 29824 bytes: 1864 ADPCM blocks. Block 0 flags 4 (loop start). Block 1860 flags 1 (loop end, no repeat). Block 1861 flags 7 is never reached. 1861 blocks * 28 samples * 0x1000/0x0555 / 48000 = 3.258 s. 59.916+3.258=63.174; 89.100-63.174=25.926 s, matching longest_silence_s 25.929.

The mixer is not muting the screen. The one-shot ends and the driver does not ask for anything else until the stage card. Missing: the forwarded 0x100 send buffer during mix 65-85 (tekken4_overrides.cpp sifCallRpc does not log it), which is what would split "EE queued no BGM" from "IOP sequencer ignored a queued BGM".

spu2Handler is stored at iop_emulator.cpp:546 and never called. irqHits still climb across the gap and IRQA stays dc080, the same as while voice 0 was being keyed. That missing call does not explain this stop. Do not add it from this evidence.

## Short WAV

dropped=0 on every 5 s line. maxAdv=2605 (0.054 s), so the counter can move and did not. mix tracks wall through mix 65 wall 65.3, then mix 70 wall 71.1, mix 105 wall 119.5. 109 s of audio for 130.2 s wall. Samples follow IOP cycles (EE/8). Host time after the select screen is not guest time. Do not raise kMaxBufferedFrames and do not stretch the WAV.

## Clipping (ASK 3)

sound-3 clipped=1184 peak_all=32768. The only windows at 32768 are 20-45 (the movie). Later peaks are <= 32256, which is 32767*16128/16384 after the dry-sum clamp and MVOL 0x3f00. Movie PCM is added after that clamp (ps2_audio.cpp onMixedAudio). Not a mix wrap. Do not scale the movie. sound-merge-sound-1 clipped=47 because Start at 30 cut the movie; that is not the char-select run.

## Tests (ASK 4)

cmd /c tools\build_tests.cmd: Total 481, Passed 481, Failed 0. vswhere.exe is not on PATH inside that cmd; cmake still configured and the exe ran (exit 0). The heap-direction executable is not one of the 481.

## Patch files

sound-merge.patch:
- ps2xIOP/CMakeLists.txt
- ps2xIOP/include/ps2x/iop/iop_host.h
- ps2xIOP/src/emulator/core/iop_memory.cpp
- ps2xIOP/src/emulator/core/iop_memory.h
- ps2xIOP/src/emulator/imports/iop_cdvd.cpp
- ps2xIOP/src/emulator/imports/iop_ioman.cpp
- ps2xRuntime/include/runtime/ps2_audio.h
- ps2xRuntime/src/lib/ps2_audio.cpp
- ps2xIOP/src/emulator/core/sound_engine.cpp (new)
- ps2xIOP/src/emulator/core/sound_engine.h (new)

Clean vs HEAD, not in the patch: libsd.cpp, iop_imports.cpp, iop_imports.h, iop_subsystem.cpp, ps2_audio_device.cpp, runtime/tekken4_overrides.cpp.

User may delete (not deleted here): H:\tekken4-recomp\iop_memory.obj, logs/grok/heap_direction_test.exe, logs/grok/heap_direction_build.cmd.
