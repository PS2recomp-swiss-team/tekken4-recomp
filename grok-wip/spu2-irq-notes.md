# spu2-irq notes

## 1. Library clears ATTR bit 6; hardware does not

PCSX2 Mixer.cpp fires only while IRQEnable is set (NextA == IRQA, both cores), then SetIrqCall. It does not clear the enable. freesd Spu2Interrupt (ps2sdk iop/sound/libsd/src/freesd.c) reads SD_C_IRQINFO (0xBF9007C2) bits 2..3, shifts to core bits, writes ATTR & 0xFFBF, then calls sceSdSetSpu2IntrHandler(core_bit, arg) or the IRQ callback with 0.

Tekken's own module is the same, not just freesd. Savestate external/pcsx2/sstates/SCES-50878 (2251E14D).02.p2s iopMemory.bin, live libsd (string "libsd   2430" at 0xc3364, SDK 2.4.3). Handler at 0xc2190:

- lhu 0xBF9007C2; andi 0x000c; srl 2 -> a0 core bits
- beq a0, 0, out
- core0 ATTR 0xBF90019A: lhu / andi 0xFFBF / sh (0xc2204-0xc2210) if a0 bit 0
- core1 ATTR 0xBF90059A: same (0xc2220-0xc222c) if a0 bit 1
- jalr word at 0xc3500 with a1 = word at 0xc3504 (the user handler), else the callback with a0 = 0

Unrelocated copy of the same handler at 0x79300 (raw IRX, lui 0). So the clear is Sony libsd, before the user handler. Our HLE calls the user handler from serviceSpu2Irq and was skipping that clear (takeSpu2Irq comment).

## 2. Steady state on PCSX2 still has the enable set (driver re-arms)

SPU2.bin is SPU2Savestate::DataBlock, version 0xe at file 0x210004 (spu2freeze.cpp SAVE_VERSION). Raw spu2regs (64 KiB at file+4) are all zero in both states; the live flags are in V_Core. Core 0 at file 0x210008 (Index 0). Voice size 0x108 (LoopStartA/StartA stride). Core 1 Index 1 at region+0x1FC0. IRQA at core+0x1AA8, IRQEnable is the next byte (FxEnable follows and is 1).

Slot 01 screenshot: mode select (STIL WAHLEN). core0 IRQEnable=0 IRQA=0x800. core1 IRQEnable=1 IRQA=0xdc080. voice 20 NextA=0xdc072 (14 before IRQA). Voices 20-23 SSA 0xdc000..0xdc300.

Slot 02 screenshot: character select, timer 26. core1 IRQEnable=1 IRQA=0xdc000. voice 20 SSA=0xdc000 NextA=0xdc0e3 (already past IRQA). 0xdc000 halfwords = byte 0x1B8000.

Enable is on in both snapshots, including after the voice has passed IRQA. libsd would have cleared it on the cross, so the driver set it again and it stays set until the next cross (~20 ms). Core 0 is not the music IRQ (enable 0, IRQA 0x800).

## 3. What our HLE must do

takeSpu2Irq must clear attr bit 6 before the user handler, matching 0xc220c. The driver re-arms with sceSdSetCoreAttr (ordinal 11, entry 4), which already sets attr bit 6 (sound_engine.cpp setCoreAttr case 4). zsiopdrv's handler only signals a semaphore (music-5 note); the worker runs later. runCycles runs threads before drainMixedAudio, so a large catch-up would play past the next IRQA with the bit still clear. serviceSpu2Irq therefore runs ready threads (bounded) after the handler until bit 6 is set again, then continues the catch-up. insertReady bumps schedEpoch, so the idle-skip cache does not drop the wake either.

Music-3's "driver stops re-arming" was before patch 35 (DATA.BIN search). Re-measure on this tree.

## 4. Build of the clear-and-rearm HLE

cmd /c tools\grok_build.cmd spu2-irq exit 0, ~221 s. sound_engine.cpp.obj and iop_emulator.cpp.obj compiled. Patch warnings 01-36 are "already in the tree" (local edits); 37-39 applied. Exe: external/wt-spu2-irq/out/grok-spu2-irq/ps2xRuntime/ps2EntryRunner.exe.

takeSpu2Irq clears attr bit 6 (sound_engine.cpp). serviceSpu2Irq (iop_emulator.cpp) calls the user handler, then if getCoreAttr(4/5) is still 0 for a fired core, runs up to 24 ready slices (beginNextReady / runCpu(kDefaultSlice) / endTimeslice) with m_inSpu2Irq set so drainMixedAudio cannot re-enter. runCpu's step() adds one totalCycles per instruction, so a full pump is 24*256 = 6144 cycles (~8 samples at 768 cycles/sample), small next to the ~975-sample IRQ period. getCoreAttr case 4 returns (attr>>6)&1, so irqCoresRearmed's ==0 test is the enable bit, not the raw ATTR word.

TEKKEN4_LIBSD_LOG=1 logs ordinal 11 entry 4 and setAddr id 0x1F (fprintf stderr, first 48 then every 256th) with ra, inirq, pump, attrOn/attrOff/irqa. Run cwd is the RunDir (run_capture.ps1 Start-Process -WorkingDirectory $RunDir), so the wav path must be absolute or mix.wav.

## 5. Prime (spu2irq-1, first ~100 stderr lines, v=true): worker re-arms inside the pump

logs/grok/spu2irq-1/stderr.txt. After sceSdInit and VoiceTrans to spu 0x1b8000/0x1bc000:

- irqa n=1 entry=1f01 val=1b8100 ra=4b9b8 inirq=0 pump=0 (before any cross)
- coreattr n=2 entry=5 val=1 ra=4bbd4 pump=0 (core 1 enable on)
- KON core=1 mask=f30000, irq-cross core=1 voice=20 irqa=dc080
- then every cross, all pump=1: coreattr entry=5 val=0 ra=4bc58, often VoiceTrans, irqa entry=1f01 val=1b8000 or 1b8100 ra=4c110, coreattr entry=5 val=1 ra=4c69c
- by n=40: attrOn=13 attrOff=13 irqa=14. The handler does not call setCoreAttr (no inirq=1 lines). The worker does, and it runs in the pump.

entry 5 is core 1 SD_CORE_IRQ_ENABLE (entry & ~1 == 4). The driver clears the enable itself, moves IRQA between 0x1b8000 and 0x1b8100, then sets the enable. That is the re-arm. It is not "a few times then stop" in the prime. Steady-state (char select, fight) still to measure; the log then prints every 256th line.

## 6. Full airport fight spu2irq-1 (exit 0, 110.6 s wall). Re-arm does not stop.

Same three calls, every logged line pump=1, inirq=0 (no inirq=1 in the file). Last line: coreattr n=16128 entry=5 val=0 ra=4bc58 attrOn=5376 attrOff=5376 irqa=5376. attrOn stays within 1 of attrOff the whole log. No "ordinal N stubbed" lines.

snd-trace every 5 mix-seconds: irqHits 217 at mix=5, 2431 at 50, 3661 at 75, 4891 at 100, 5383 at 110. About 49/s the whole way (5383-217)/105 s. irqa stays 0/dc000. attr 4080/40c0 until the effect-off at mix~70 (effect mode 0, lines 237-240), then 4000/4040 through mix=110. Core 1 bit 6 is set at every 5 s sample. maxAdv stays 2605 (boot spike, field is a max). dropped=0.

Music reads: lsn 1070970 dst=0x160000 then 1071034/0x180000, 1071098/0x1a0000, then 32-sector steps through 0x160000..0x1a0000 (stderr 182-224). Second stream lsn 1112416 at the stage load (line 243) still stepping 0x160000..0x1a0000 at mix=110 (lsn 1113568, line 312).

WAV mix.wav 110.037 s, rate 48000, clipped 52 (peak_all 32768 = a -32768), longest_silence_s 9.716 (boot: rms 0 for t 0-9). Char select per-second rms t=46..60 all >= 0.22461. Fight per-second from t=80: 0.200, 0.237, 0.285, 0.294, 0.293, 0.302, 0.279, 0.257, 0.265, 0.260, then 0.250..0.146 through t=100, still above 0.145 with peaks 24k-32k. Reference excerpt_fight_80s last second was 0.180. 10 s windows: 40-50 0.239, 50-60 0.274, 80-90 0.269, 90-100 0.182.

Perf stdout: seconds 75-99 are 60 frames except 81=61, 83=59, 85=61. GS ~132-144 ms. Airport fight held 60.

PCSX2 char-select state 02 had core1 IRQEnable=1 IRQA=0xdc000. Our fight samples match that (bit 6 on, irqa=dc000). No fight p2s this session.

## 7. TEKKEN4_SOUND unset still reaches the fight

logs/grok/spu2irq-2, exit 0, 82.6 s. params.txt has no TEKKEN4_SOUND. stderr has no "sound route". Stage confirmed airport, Start at 74.7 s. frame_80s.bmp 640x448 blank=false r/g/b mean 79.94/67.94/70.39, pct_near_white 1.95, pct_near_black 5.23. The frame is the airport fight: Kazuya vs Yoshimitsu, round timer 00, damage 0.

## 8. Tests

cmd /c logs\grok\spu2irq-tests.cmd (TEKKEN4_SRC=external\wt-spu2-irq) exit 0. ps2x_tests Total 482 Passed 482 Failed 0.
