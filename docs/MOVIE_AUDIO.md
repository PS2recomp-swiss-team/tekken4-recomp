# Intro movie audio: decoding, pacing and verified original level

Worktree `t4-movie-audio`; all changes remain uncommitted. No commit, push,
server connection, real-account login or change to the owner's game data/build
was made. WAVs, game-derived evidence and experimental binaries stay ignored
under `build/` and `deps/`.

## Result and the owner's “LOUD and CHOPPY” report

The stereo corruption and movie queue starvation are reproduced and corrected.
The final callback capture has zero digital-silence gaps over 5 ms, zero newly
introduced resampler/mixing saturation events, and matches the correctly decoded
source at the verified original sustained intro gain throughout 119 seconds.

**Excessive nominal gain was not reproduced.** The old default `0.7` was already
below the original game's gain. Restoring the original level therefore raises
clean movie audio relative to that old setting. This must not be described as
making the intro quieter or proving the owner's subjective “too loud” complaint
resolved. Wrong decoding produced distorted audio and elevated noise/RMS, but
that is distinct from excessive volume. No double movie mix was found.

## Causes and changes

1. The Namco movie container holds MPEG-2 video and SPU ADPCM in sector units;
   it is not an ordinary PSS audio PES track. The original driver copies each
   4096-byte audio unit unchanged, then transfers 512-byte channel chunks.
   The layout is `[L512 R512]` repeated four times: 3584 stereo frames/unit.
   The old HLE alternated channels every 16 bytes, corrupting each channel's
   predictor history. The original checker repeated that same wrong assumption.
   The override and legacy checker now use the verified 512-byte layout.
2. The guest-clock producer WAV hid a separate host-clock underrun. Normal
   vblank catch-up rebasing discarded movie time after stalls, while the audio
   callback continued consuming 48 kHz. The scheduler now preserves deadlines
   while host movie PCM is active. Fight catch-up and cycle-ordered netplay
   scheduling retain their existing behavior. The host flag is not guest state,
   serialized data or a hash exclusion.
3. Cubic interpolation clipped to s16 **before** applying gain. Even with the
   corrected layout it generated overshoot. Streaming linear interpolation now
   matches this port's native SPU voice path, stays between source samples and
   applies gain before the final conversion. Saturation counters cover resampling,
   producer mixing and final callback movie mixing.
4. The HLE bypassed original movie voice/category/master volume and substituted
   the guessed `0.7` gain. It now reads the selected original driver volume record
   and current movie-category value, applies original master/envelope scaling,
   and validates the optional absolute `TEKKEN4_MOVIE_GAIN` override as finite
   and within 0..1. Invalid values fall back to original scaling.

The actual intro probe found original base volume `0x3fff`, movie-category
volume 128/128, master `0x3f00`, and native maximum envelope 32767/32768:

```
gain = (16383 / 16384) * (16128 / 16384) * (32767 / 32768)
     = 0.9842848796106409  (-0.137584 dB)
```

The original default reaches full stream volume after a short two-tick onset
ramp. This change restores the **sustained intro level**; it does not implement
full consumption-time dynamic fade equivalence. Category volume is sampled
while reading ahead, so later volume changes can be delayed by buffered audio.
Only this intro/mode-0 capture was verified. Other attract tracks and mode-1
layout remain unverified. No original volume lookup table or decoded audio is
embedded in source; the original loaded driver's selected record is read only.
Local supporting evidence: `build/movaudio/original-volume-evidence.txt` and
`build/movie-audio/driver-layout-evidence.txt`.

## Peak, RMS, clipping and gaps

All movie rows cover source movie time 1..120 s (119 s). dBFS uses 32768 as full
scale. Silence means both channels within 2 LSB for **strictly more than 5 ms**;
counts are divided by actual measured duration, not rounded movie duration.
Natural silence is counted too; the corresponding original span contains none.
Rail counts are observable WAV samples, not automatically clipping events.

| Capture/reference | Peak dBFS | RMS dBFS | s16 rail samples | Gaps >5 ms/min |
|---|---:|---:|---:|---:|
| Correct original ISO decode, native PCM sampled at movie playback time | 0.000 | -11.409 | 7 | 0 |
| Before: wrong layout, old catch-up, gain 0.7; callback WAV | -3.098 | -14.113 | 0 | 43.866 |
| Previous fix: correct layout/clock, gain 0.7; callback WAV | -3.098 | -14.525 | 0 | 0 |
| Final: original gain + bounded interpolation; callback WAV | -0.184 | -11.612 | 0 | 0 |
| Fight BGM/voices/effects before, producer seconds 35..46 | -0.137 | -13.588 | 0 | 0 |
| Fight BGM/voices/effects prior after, producer seconds 35..46 | -0.137 | -13.635 | 0 | 0 |

The final producer movie WAV has the same peak and RMS as the final callback
within rounding. Source-native 44.1 kHz seconds 1..120 give RMS -11.412 dBFS;
-11.409 above uses the existing playback clock 44144.144 Hz. Linear interpolation
and original scaling account for the final -11.612 dBFS. It matches the expected
original-level reconstruction, rather than normalizing movie loudness to fights.
The original movie is about 2 dB above the measured mixed fight section in RMS.
Fight rows are scene-level mixed audio, not isolated BGM masters or bit-identical
fight proofs.

Before has **87 gaps**, totaling **4479.75 ms**, maximum **325.04 ms**. The final
callback has none. Its whole-movie queue counter reports **0 missing frames**,
versus **232322 frames / 4840.04 ms** in the old baseline. The before WAV's
119-second span excludes movie boundaries, hence its smaller total than the
whole-movie counter. Its producer falsely reported zero gaps.

The final run logs **resampler clipped samples 0**, **callback movie clipped
samples 0**, and **producer movie clipped samples 0**. Both final WAV spans have
zero samples at the existing 32256 threshold as well as zero s16 rails. The raw
source's seven rail samples are inherent ADPCM decoding saturation; this patch
does not pretend to recover already-lost source peaks. Offline whole-reference
cubic audits found 10282 intermediate saturation samples with the wrong layout,
and 12 with the corrected layout, including 10 overshoots whose source neighbours
were below the rails. Those audit totals cover the entire reference, not just
this 119-second WAV section, and are not mislabeled as WAV rail counts.

Machine-readable evidence:

- `build/movaudio/loudness-baseline.json`: original, before, prior-after and fight
  section levels, exact sample counts, paths and gap definitions.
- `build/movaudio/after-native-level/device-linear-reference.json`
- `build/movaudio/after-native-level/mix-linear-reference.json`
- Corresponding `mix.wav`, `device.wav`, `stdout.txt`, `stderr.txt`, `params.txt`
  and `result.txt` under each capture folder.
- `build/movie-audio/catmull-audit.json` and `catmull-audit-512.json`: earlier
  offline overshoot audits, explicitly separate from output WAV rail counts.

## Continuous delivery, stereo, rate and video

The final independent comparison checks 12 separated stereo windows and then
**all 5712000 stereo frames** over the 119-second span against linear source
interpolation at the externally verified gain. It uses one fixed waveform onset;
it does not refit lag or gain inside the span. Maximum absolute sample error is
**1.00803 LSB**, residual RMS **-95.0787 dBFS**, and **0 samples exceed 4 LSB**.
This establishes no dropped/repeated content in that measured span within the
stated tolerance, complementing the zero-silence and queue counters.

Mean mono correlation improves **0.106205 -> 0.999999998987** on the callback;
strong stereo windows improve **0/12 -> 12/12**. Separate L/R checks and a
swapped-channel negative control are retained. Final fitted drift is **0 ms/s**
and residual lag spread **0 ms** at the tool's resolution. Source playback is
**44144.144 Hz**, the existing deliberate **+1.7321 cents** correction for the
port's 30.000 versus 29.970 fps presentation. A whole-capture timing fit including
baseline gaps is not described as pitch.

The same 3643 pictures take **129.199 s /28.189 fps before**, versus
**121.398 s /30.0005 fps final**. Host presentation hitches remain: the final
maximum served-picture interval is 258.434 ms. Zero audio gaps do not claim
perfectly smooth rendering. The existing player serves 3643 of 3675 file
pictures and closes with trailing audio queued; that end-of-movie behavior is
unchanged.

The ordinary SPU producer queue is distinct from the movie callback queue. The
retained fight-after captures show roughly 41..47 fps and ordinary host output
starvation. In the repeat, callback WAV seconds 45..62 have 51 digital-zero gaps
>=2 ms totaling 3889.40 ms. That older statistic uses a different threshold and
is not the requested movie >5 ms/min metric. This change does not solve slow-fight
output starvation or its adaptive-rate pitch modulation. Fight BGM/voices use
the original IOP per-channel DMA path, not the erroneous movie deinterleaver.

## Every game/build run

All game runs use isolated APPDATA, LOCALAPPDATA and OPENRECOMP_HOME, muted
playback (`PS3_AUDIO_MUTE=1`), background windows and BelowNormal priority. Two
heavy slots were atomically acquired for timing runs and released afterwards;
each build used one slot. The owner's launcher config SHA-256 stayed unchanged
before/after every successful game run. No live or local network game was needed
because no simulated guest state or protocol was changed.

| Run | Local result path | Result |
|---|---|---|
| Instrumented baseline relink | `build/movaudio/build-before.log` | Pass; audio object recompiled, cached game objects linked |
| 35 s probe | `build/movaudio/probe/` | Clean mixer WAV; no endpoint, hence no callback WAV |
| Baseline null-clock relink | `build/movaudio/build-before-clock.log` | Pass |
| 150 s full before intro | `build/movaudio/before/` | Completed; wrong layout and 4840 ms callback underrun reproduced |
| 70 s old-layout catch-up=0 A/B | `build/movaudio/catchup0/` | Completed; near 30 fps and zero movie callback underruns |
| Layout + scoped-clock relink | `build/movaudio/build-after.log` | Pass; audio, scheduler and override unity batch recompiled |
| 145 s full after intro | `build/movaudio/after/` | Completed; correct-reference correlation 0.999776, zero callback gaps |
| 65 s original-build fight | `build/movaudio/fight-before/` | Fight verified in frame_50s.bmp; clean close, mixer capture only |
| 65 s fixed-build fight | `build/movaudio/fight-after/` | Fight verified; close exceeded 8 s, killed (-1); valid captured audio |
| 65 s fixed-build fight repeat | `build/movaudio/fight-after-repeat/` | Fight verified; exit 0, producer BGM/voices present; underspeed device gaps remain |

| Continuation run | Local result path | Result |
|---|---|---|
| Volume-probe relink | `build/movaudio/HEAVY2.lock.stdout.log`, `.stderr.log`, `.result.txt`; `build-volume-probe-diagnosis.txt` | Compiler/linker completed; initial wrapper lost exit status and incorrectly reported failure; produced executable verified by succeeding probe; wrapper corrected |
| First volume-probe launch | `build/movaudio/volume-probe/failure-note.txt` | Failed before game start because preceding linker still held executable; no measurement; acquired locks released |
| 20 s actual volume probe | `build/movaudio/volume-probe-actual/` | Exit 0; category2=128 and fade command confirmed; original config hash unchanged |
| Original-level/linear relink | `build/movaudio/build-native-level.{stdout.log,stderr.log,result.txt}` | Exit 0; audio, scheduler and override rebuilt/relinked |
| 145 s final intro | `build/movaudio/after-native-level/` | Exit 0; zero movie underruns or new saturation; all-span reconstruction passes; config hash unchanged |
| Extracted production C++ gain/resampler harness build and execution | `build/movaudio/movie-level-harness.{stdout.log,stderr.log,result.txt}` | Exit 0; 32 native-gain cases, 12 rate/partition/gain cases, two bounds cases, 11 override invocations pass |

Build logs retain the installed vcvars helper's missing-vswhere diagnostic and
existing duplicate CloseWindow/ShowCursor plus /FORCE linker warnings. No new
compiler error remains. One exploratory apply-check against the old normalized
scratch copy failed; the authoritative read-only apply-check against the
unmodified dependency source passes (`build/movaudio/patch-check-followup.txt`).
The patch preserves the original dependency's mixed CRLF/LF context bytes.
No unrelated generated or original owner files were modified.

## Verification and reproduction

- `python -I tools/pss_audio_reference.py --self-test`: **12 pass**;
  `build/movaudio/reference-self-test-followup.json`.
- `python -I tools/test_movie_wav_compare.py`: **13 pass**;
  `build/movaudio/movie-wav-tests.txt`. Covers known delay/gain/drift, stereo
  swapping, silence thresholds including exactly 5 ms versus >5 ms, trailing
  silence, clipping observations, and repeated nonzero content invisible to a
  silence-only check.
- Extracted production C++ harness: pass; command/source provenance in
  `build/movaudio/movie_level_harness.{cmd,cpp}` and
  `movie_level_harness-source.json`. Chunked versus one-pass conversion differs
  by at most 1 LSB from floating-point rounding; signed extremes remain bounded.
- Previous extracted queue, atomic active-flag and diagnostic-clock harnesses
  remain under `build/movaudio/audio_{queue,active,clock}_harness.*`.
- Patch 88: `git apply --check` passes against original dependency tree.
  `git diff --check` passes. No full clean game rebuild or online pair was run.

```powershell
powershell -NoProfile -File tools/run_movie_audio.ps1 -Name verify -Seconds 145 `
  -Iso $iso -Elf $elf -Exe $runner -HeavyRoot $coordinationLocks
python -I tools/pss_audio_reference.py --iso $iso --sector $movieSector --size $movieSize `
  --wav build/movie-audio/reference.wav --json build/movie-audio/reference.json
python -I tools/movie_wav_compare.py --reference build/movie-audio/reference.wav `
  --capture build/movaudio/verify/device.wav --timeline `
  --expected-gain 0.9842848796106409 --json build/movaudio/verify/compare.json
```

The runner rejects an already-recorded run name instead of overwriting evidence.
`TEKKEN4_AUDIO_DEVICE_WAV` records the callback before master mute.
`TEKKEN4_AUDIO_TEST_CLOCK=1` explicitly enables the 48 kHz/10 ms diagnostic clock
only when no endpoint is ready. `TEKKEN4_AUDIO_STATS=1` exposes movie consumption
and saturation counters. All new capture paths remain local and ignored.

## Limits

Windows reported **AUDIO: Failed to initialize playback device** in the final
run. Callback WAVs use the real `onDeviceRequest` path driven by a diagnostic
host clock; they are **not hardware/loopback recordings**. They prove sample
values and host queue behavior, not endpoint-driver behavior. Physical playback,
a listening check and whether the owner still considers the original level too
loud remain unverified. The current evidence cannot honestly call excessive
nominal gain reproduced or claim subjective loudness fixed. Optional gain 0..1
is available, but another arbitrary attenuation is not described as original
volume restoration. Onset/dynamic fades, other movies, ending truncation and
slow-fight starvation have the limits stated above.

## Files and proposed commit

- `.gitignore`
- `runtime/tekken4_overrides.cpp`
- `patches/88-ps2xRuntime-movie-clock-and-device-diagnostics.patch`
- `tools/pss_audio_reference.py`
- `tools/movie_wav_compare.py`
- `tools/test_movie_wav_compare.py`
- `tools/movie_audio_check.py`
- `tools/run_movie_audio.ps1`
- `docs/MUSIC_FIX.md`
- `docs/MOVIE_AUDIO.md`

Patch 88 carries the ignored dependency edits to
`ps2xRuntime/include/runtime/ps2_audio.h`, `ps2xRuntime/src/lib/ps2_audio.cpp`,
and `ps2xRuntime/src/lib/Kernel/EeScheduler.cpp`. The staged override, generated
unity build, objects, executable, PDB and decoded audio remain ignored.

Proposed commit message: **Fix movie stereo decoding and pacing; restore original gain without resampler clipping**

Player-facing changelog lines (CHANGELOG.md was not edited):

- Correct intro-movie stereo decoding and prevent audio gaps after host stalls.
- Restore original sustained movie volume and remove interpolation clipping.
