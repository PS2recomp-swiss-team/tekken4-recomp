# Missing background music (BGM): cause, fix, evidence

US build SLUS-20328, `TEKKEN4_SOUND=1` (real Namco driver zsiopdrv on PS2Recomp's emulated IOP). Before the
fix: effects and voices played, the music did not. Session 2026-10-29 (worktree `D:\tekken4-fork-music`, branch
`t4-music` = `t4-us` + 3 commits). IOP addresses below come from an IOP RAM dump of this build.

## Cause

There are two faults. The first one alone is enough to silence the music.

1. **The SPU2 interrupt was never delivered.** zsiopdrv streams the BGM from the disc itself. Its CD thread
   (`sceCdRead` call at IOP 0x48e48, queue at 0x48a28, type 2) reads 64 KB blocks into IOP 0x160100..0x1a0100
   about every 1.3 s (= 44.1 kHz stereo ADPCM). A refill thread copies them on to the SPU ring at 0x1bc000/0x1bc400,
   which is played by core 1 voices 16/17 (pitch 0x0eb2 = 44.1 kHz, volume left-only/right-only). That thread runs
   on the **SPU2 interrupt**: IRQA on core 1 ping-pongs between 0x1b8000 and 0x1b8100, and the handler 0x4f644
   (registered with `sceSdSetSpu2IntrHandler`) signals the thread's semaphore. The thread then refills with
   `sceSdVoiceTrans` 256/512 B pieces and moves IRQA. The libsd HLE stored the handler but never called it. The
   sound engine only counted IRQA crossings for `TEKKEN4_SOUND_TRACE`. Without the interrupt, the stream ring kept
   the silent loop it was given at start-up, so voices 16/17 played silence.
   (The old notes said "the IOP read only two banks": the `[cdvd]` log line is capped at 6 lines, but the reads
   go on all the time.)
2. **The EE's SIF commands never reached the IOP.** zsiopdrv also pulls sound data from EE RAM. It sends SIF
   command 2 (`0xe993/0x1390/0x1391/..` + sector, IOP destination, size) to the EE handler 0x228a08. The EE main
   loop (0x228d90) answers with FUN_00228cc8 = `sceSifSendCmd(cid 0, 0x1ccacc0, 0x24, EE src, IOP dest, size)`.
   That broke in two places. `ps2_syscalls::sceSifSendCmd` read `dest`/`size` from the stack, but on the EE ABI
   they are in `$t0`/`$t1`, and it copied into **EE** RAM. The IOP sifcmd HLE also returned 0 for
   `sceSifAddCmdHandler` and dropped it, so the driver's cid-0 handler 0x4f4c0 (stores the sector count at
   0x521d0) never ran. The payload is 8-16 KB pieces to IOP 0x148100/0x150100, sent when the character select
   loads. The earlier "music-3" note "refuted" this because the handler "only stores a size". The data itself
   travels in the SIF DMA payload, which was lost.

## Fix (fork branch t4-music, D:\tekken4-fork-music)

| commit | what |
|---|---|
| `8f5b93b` SIF: EE sceSifSendCmd payload ($t0/$t1) to IOP RAM, packet to the IOP module's handler | `RPC.cpp` reads `$t0/$t1`, writes the payload with `writeIopMemory`, queues the packet (`ps2x::iop::queueEeSifCommand`). The `SIF.cpp` stub delegates to it. The IOP keeps `sceSifAddCmdHandler`/`Remove` per cid (sound route only) and calls the handler with the SIF header words (size \| dsize<<8, dest, cid) at the start of each `runCycles`. |
| `9774f77` ps2xIOP: deliver the SPU2 interrupt to libsd's handler | The engine sets a core's IRQ bit when a voice decodes the block that holds that core's IRQA (IRQ enable on). After each mixer advance the IOP clears the cores' IRQ enable and calls the `sceSdSetSpu2IntrHandler` handler (core bits, arg) or the `sceSdSetIRQCallback` callback, as ps2sdk libsd's `Spu2Interrupt` does. |
| `16bc431` ps2xIOP: sound debug aids (env-gated) | `TEKKEN4_SOUND_VOICES=1` (voices, libsd call counts, IRQs, IOP->EE commands), `TEKKEN4_SOUND_SOLO=<c0 mask>,<c1 mask>`, `TEKKEN4_IOP_DUMP=<s>,..` (IOP + SPU RAM), `TEKKEN4_IOP_TRACE=<pc>,..`. |

Game override (main repo, `runtime/tekken4_overrides.cpp`, sound part, not committed): `sifSendCmd` now leaves
every cid except SET_SREG to the fixed `ps2_syscalls::sceSifSendCmd`. `TEKKEN4_BGM=0` brings back the old
behaviour for A/B runs: the EE command is dropped here, and the IOP skips the SPU2 interrupt.
New tools: `tools\wav_sections.py` (level + spectrum per named section), `tools\run_music_ab.ps1` (the evidence
runs below).

## Evidence

All runs use the standard path `8:Start,13:Start,17:Start,21:Cross,26:Start` (movie skip, MEDIUM, Story Battle,
Kazuya, prologue skip; fight from ~32 s), with WAVs in `logs\music_ab_<variant>\mix.wav`. Sections are in WAV
seconds. "stream" = only the driver's stream voices (core 1: 16-17 and 20-23) in the mix
(`TEKKEN4_SOUND_SOLO=0,f30000`). "fx" = every voice except those. "base" = `TEKKEN4_BGM=0` (before the fix).

| section | base stream rms | **fix stream** rms / quiet share / L-R corr / energy <250 Hz | fix fx rms | base full rms | fix full rms |
|---|---|---|---|---|---|
| title 9-12.5 s | 0.000 | 0.000 (no BGM on the title) | 0.207 | 0.209 | 0.202 |
| mode select 14-17 s | 0.000 | 0.058 / 0.93 / 0.45 / 0.59 (music starts ~16 s) | 0.274 | 0.273 | 0.297 |
| char select 18-26 s | 0.000 | **0.229 / 0.04 / 0.54 / 0.70** | 0.382 | 0.374 | 0.439 |
| prologue 27-31 s | 0.000 | 0.094 / 0.78 / 0.53 (track change) | 0.407 | 0.405 | 0.435 |
| fight 34-58 s | 0.000 | **0.189 / 0.00 / 0.92 / 0.78** | 0.593 | 0.562 | 0.616 |

Stream-only rms in 2 s windows. In the fix it is about 0.16-0.30 from 16 s to 26 s, 0 during the 26-30 s
transition, then about 0.17-0.28 without a gap to the end of the fight. In the base it is 0.000 in every window
after the movie (the 6-10 s values in both are the movie PCM, which is mixed after the voices).
The music is a real stereo signal (L/R correlation 0.45-0.92, while every effect voice here is centred: 1.00),
has no quiet gaps and is bass-heavy, and the full mix of the fix is stereo for the first time (L/R 0.89 in char
select vs 1.00 in the base).

Effects and voices show no regression: the effects-only mix of the fix matches the full base mix in every section
(rms 0.207/0.274/0.382/0.407/0.593 vs 0.209/0.273/0.374/0.405/0.562, same spectrum shape, mono).

Driver activity with the fix (`TEKKEN4_SOUND_VOICES=1`, logs\music3): about 49 SPU2 IRQs/s and 295
`sceSdVoiceTrans`/s, steady from boot to the fight. EE->IOP: 4 commands in 50 s (char-select data), each
answered (`IOP->EE cid=2 body e993 f7 148100 4000` -> `EE cmd cid=0x0 -> handler 0x4f4c0` -> `b922` ack).

FPS (`TEKKEN4_PERF_LOG=70`, mean frames/s over perf seconds 36-58 = the fight, two alternating pairs,
`logs\music_fps{1,2}_{fix,base}_full`): fix **55.1 / 53.3**, base **53.0 / 53.9**. The fix costs nothing
measurable. However, **neither** variant reached 60 tonight: every fight second was below 58 in all four runs,
other agents' runs/builds shared the machine, and the earlier sound-on runs logged 60.1. So the run-to-run
difference here is about +-1 fps; recheck the absolute 60 on a quiet machine.

The round timer in the fight screenshots agrees: from `shot_40s` to `shot_60s` (20 s wall time) the
in-game fight clock moves 00:00:70 -> 00:19:23 in the fix (`music_fps1_fix_full`) and 00:00:66 -> 00:19:28 in the
base (`music_ab_base_full`). That is ~18.5 game seconds per 20 s in both (the round timer counts 59 -> 40/41),
which matches the ~54-55 fps above. It is the same in both, so it is not caused by the fix.

IOP unit tests (`tools\build_iop_tests.cmd`, TEKKEN4_SRC=D:\tekken4-fork-music): emulator, import and
compatibility tests (18/18) all pass; `tools\build_tests.cmd`: ps2x_tests 482/482.

## Reproduce

```
set TEKKEN4_SRC=D:\tekken4-fork-music
set TEKKEN4_BUILD_DIR=music
tools\build_runtime.cmd            (after tools\stage_generated.cmd)
powershell -File tools\run_music_ab.ps1 -Prefix music_ab
external\pytools\Scripts\python.exe -I tools\wav_sections.py logs\music_ab_fix_stream\mix.wav title=9-12.5 mode=14-17 charsel=18-26 prologue=27-31 fight=34-58
```

## Not fixed / found on the way

- ~~Effect voices that never stop~~: fixed, see "Never-ending voices" below.
- The host warning "AUDIO: Failed to initialize playback device" only means there is no output device. At night
  the RME ADI-2 DAC endpoints are all "Unknown" (off); only a microphone is present. The IOP mix and the WAV do not
  depend on the device (`MixedOutput::push` writes the WAV first, `pumpDevice` waits for `IsAudioDeviceReady`).
- The core 1 voices 20-23 (22 kHz, ring 0x1b8000, IRQ ping-pong) are a second stream that stays silent in these
  scenes (voice lines?). It is refilled the same way.

## Never-ending voices (fixed 2026-10-29, fork commit `e3349b1`)

**Symptom.** Every menu press keyed a core 1 voice that never stopped and played on through the whole bank (SSA
0xcef0, 0x77a0, 0x9dc0, ... in the middle of continuous audio). The bank at SPU 0x5010 had no ADPCM end flag
between 0x5010 and 0xb6030, and the EE frees voices only through ENDX. So the voices piled up: the mix reached rms
~0.6 and 5-9 % of the fight's samples hit the rail, which drowned the music.

**Cause: the IOP read the wrong part of the disc.** The SPU RAM bank matched the disc byte for byte, but it came
from the wrong sectors. At boot zsiopdrv calls `sceCdSearchFile("\TEKKEN\DATA.BIN;1")` (IOP 0x488d4) and keeps the
LSN at 0x521a0. It then reads every sound bank and the BGM as `0x521a0 + sector` (CD thread 0x48e1c). The cdvd
HLE answered from the *virtual* ISO it builds from the extracted files (there DATA.BIN sits at LBN 1106), or
otherwise from hard-coded PAL numbers (LBN 1236). But `sceCdRead` reads the *real* image, where the US DATA.BIN
starts at LBN 401. So every sound read landed 705 sectors too far: the first bank came from LSN 20188 instead of
19483. LSN 19483 holds the real bank: blocks with loop-start (0x04) and end (0x01) flags. The data at 20188 is
other audio (flag 0x02 everywhere). ioman's `cdrom0:` open had the same PAL constant.

**Fix (`ps2xIOP: cdvd/ioman look file paths up in the disc image's ISO9660 directory`).** With a disc image,
`sceCdSearchFile` and ioman's `cdrom0:` open now resolve the path in the image's own ISO9660 directory
(`imports/iop_iso9660.h`). The virtual ISO is only used without an image, so no numbers from either disc remain.
Log: `[cdvd] sceCdSearchFile \TEKKEN\DATA.BIN;1 -> LBN 401 size 2695536640`, first bank read
`lsn=19483`. The BGM is read through the same base, so before this fix the music also came from the wrong place
on the disc (it happened to be music, about 705 sectors later).

**Evidence** (`tools\run_music_ab.ps1 -Prefix music_v2a -Only fix_full,fix_stream,fix_fx`, same key path and
sections as above; "before" = `music_ab_fix_full`, the state after the BGM fix and before this one).

| section | before: full rms / clipped | **after: full rms / clipped** | after: stream (music) only | after: effects only |
|---|---|---|---|---|
| title 9-12.5 s | 0.202 / 0 | **0.031 / 0** (quiet 83 %) | 0.000 | 0.029 |
| mode select 14-17 s | 0.297 / 0.27 % | **0.127 / 0.01 %** | 0.161 | 0.126 |
| char select 18-26 s | 0.439 / 1.62 % | **0.245 / 0.09 %** | 0.189 | 0.130 |
| prologue 27-31 s | 0.435 / 1.84 % | **0.156 / 0 %** | 0.195 | 0.118 |
| fight 34-58 s | 0.616 / 8.60 % | **0.193 / 0.01 %** | 0.164 | 0.170 |

- **Menu presses now play short sounds that end.** Title/menu sections are 80-86 % quiet between presses. With
  `TEKKEN4_SOUND_VOICES=1` (`logs\voices1`) no voice is still sounding at the 5/10/15/20/25 s checks; before,
  one more voice was left at every check, from every press. In the fight, only the stage's looping stereo pair
  (core 1 voices 0/1, panned hard L/R, volume moving) and short hit/voice sounds remain.
- **The fight no longer clips:** 0.01 % (before 8.6 %), and the full-mix rms fell from 0.62 to 0.19-0.21. A second
  full run (`music_v2b_fix_full`) gives the same: 0.023/0.127/0.245/0.154/0.205.
- **Music is audible over the effects:** the music alone is as loud as the effects alone in the fight (0.164 vs
  0.170) and louder in char select (0.189 vs 0.130). Before, it was at most a third of the drone level.
  (`music_v2b_fix_fx` is left out: its movie-skip press missed and its timeline is shifted.)
- **FPS** (fight, perf seconds 36-58): 56.5 (`music_v2a`) and 55.0 (`music_v2b`), the same range as before.
  The machine is still not reaching a clean 60 tonight in any variant (see above).
- **Tests:** IOP tests 18/18 + smoke/import, ps2x_tests 482/482 (tree D:\tekken4-fork-music at `e3349b1`).

## Intro movie (fixed 2026-10-30, override movie code + fork commits `dac4e50`, `d578f3c` = patches 90/91)

**Symptom (user).** The intro FMV's sound was "garbage": choppy and broken, high-pitched.

**Cause: the sound played at the wrong rate, with a gap after every unit.** The movie file (DATA.BIN sector
67289, 1536 units of 0x27 video sectors + 2 audio sectors) carries SPU ADPCM stereo, left and right alternating
every 16-byte block, 3584 frames per unit. The local HLE (`queueMovieAudio`, the movie calls 0x3000/0x3200/0x3100
never reach zsiopdrv) queued them as 48 kHz. The data is **44.1 kHz**. The MPEG sequence header says 29.97 fps,
there are 3675 pictures = 122.6 s, and the 1519 units that carry sound last 123.4 s at 44.1 kHz but only 113.4 s at
48 kHz. So the sound ran 8.8 % fast and high. Because a unit is read only when the player needs the next video,
the queue ran dry after every unit. Measured on the old path (`TEKKEN4_MOVIE_AUDIO_HZ=48000`, `logs\movie_full3_old`):
7.1 s of gaps in the 121 s intro, the sound 5.8 s behind the picture at 102 s, and the WAV uncorrelated with the
disc's audio (0.06).

**Fix (movie parts of `runtime\tekken4_overrides.cpp`):**
- Decode at the source rate and resample it to the mixer's 48 kHz with a streaming 4-point (Catmull-Rom) resampler
  that carries over between units.
- The runtime hands the pictures out on its 60.000 Hz vsync, i.e. at 30.000 fps, not 29.97. The sound is consumed
  at the same rate: 44100 x 30/29.97 = 44144 Hz, +1.7 cents, inaudible. Without this it falls 0.1 % (120 ms)
  behind over the intro.
- The first unit is read about 80 ms before the decoder hands out the first picture, so the sound is held until
  then and starts with the picture.
- `TEKKEN4_MOVIE_AUDIO_HZ=<rate>` overrides the source rate (48000 = the old behaviour, for A/B runs).
  `TEKKEN4_MOVIE_SYNC=1` logs, once a second, pictures vs sound played (A/V offset), gaps and queue, and a summary
  at the close (picture intervals, fps).

Runtime (fork):
- `ps2MoviePcmStats()` = movie PCM played/missing/queued (patch 90).
- `ps2_stubs::mpegPicturesServed()` / `mpegServeStats()` = pictures handed out and their wall-clock intervals
  (patch 91). The player FUN_00227bd8 runs the whole movie inside one call, so the game side has no per-picture
  hook.

**Evidence** (full 140 s runs without key presses, so the whole intro plays):

| | before (48 kHz, `logs\movie_full3_old`) | **after** (`logs\movie_full4`) |
|---|---|---|
| sound gaps in the movie (runtime count) | 7096 ms | **0 ms** |
| A/V offset (sound minus picture) | +82 ms -> -5.8 s at 102 s | **-33 ms at the start -> -6 ms at the end** |
| WAV vs the disc's audio (`tools\movie_audio_check.py`, 1 s windows every 10 s) | corr 0.06, lag wandering +-60 ms (40 s check, `logs\movie_old`) | **corr 0.964-1.000 (mean 0.986), lag constant -1.50 ms, drift 0.00 ms over 121 s** |
| pictures | 3643 at 30.000 fps, intervals 28-38 ms: 3639/3642, max 43 ms | 3643 at 30.04 fps, 28-38 ms: 3636/3642 (6 < 20 ms), **max 35.5 ms** |

- Pitch and duration are right: the WAV matches the disc's audio decoded at 44144 Hz with a constant lag over the
  whole movie. At a wrong rate the lag would drift by 8.8 % (10.6 s over the movie).
- The checker's only digital-silence runs fall after 121.4 s. The player closes on the last picture, while the
  audio sectors hold about 2 s more; the game stops its sound there as well. Inside the movie there are none, and
  2 of 1229 100 ms windows show a step above 4x the reference's.
- Video: no stutter (every interval within one frame of 33.4 ms). 3643 of the file's 3675 pictures are handed
  out, before and after the fix alike: the player ends about 1 s before the file does. The 30.000 vs 29.97 fps
  pacing is the runtime's 60 Hz vsync; the sound now follows it.
- In-game sound unchanged (standard path, `logs\movie_ingame_fix_full`): title/mode/charsel/prologue/fight rms
  0.039/0.225/0.232/0.206/0.212, clipping at most 0.08 %. This is in the range of `music_v2a`/`music_v2b`; mode
  select varies with when the menu music starts.
- Nothing that runs in a fight changed guest state. The mixer reads one host flag (movie open), and the MPEG stub
  and movie code only run during movies. So no rollback re-test was needed.
- Tests: IOP tests 18/18 + smoke/import, ps2x_tests 482/482 (D:\tekken4-fork-music at `d578f3c` = t4-us + patches 90/91).

Reproduce:
```
set TEKKEN4_SRC=D:\tekken4-fork-music & set TEKKEN4_BUILD_DIR=music & set TEKKEN4_SOUND=1 & set TEKKEN4_MOVIE_SYNC=1
set TEKKEN4_SOUND_WAV=D:\tekken4-us\logs\movie_full4\mix.wav
powershell -File tools\run_capture.ps1 -RunDir logs\movie_full4 -Shots "30,60,90,120,140"     (no keys: the intro plays)
external\pytools\Scripts\python.exe -I tools\movie_audio_check.py "Tekken 4 (USA).iso" logs\movie_full4\mix.wav --to 121 --step 10 --hz 44144.14
```
Old behaviour for comparison: `set TEKKEN4_MOVIE_AUDIO_HZ=48000`.
