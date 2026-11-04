"""Reference-conditioned movie WAV measurements, using only Python's stdlib.

python -I tools/movie_wav_compare.py --reference build/movie-audio/reference-44100.wav \
    --capture build/movaudio/before/mix.wav --json build/movaudio/before/compare.json

The reference is the native-rate direct-ISO decode. --source-hz describes the
rate at which that source should play on the host (default: 44100*30/29.97,
matching the runtime's 30 Hz presentation). Local waveform correlation estimates
alignment and clock drift. Pitch uses the lag between two halves of each local
window; the fit across distant windows measures delivery timing and includes
underrun silence. Neither is guessed from musical fundamentals. Fits require
strong waveform correlation. Stereo is checked separately, including swapped.

"Excess-step events" are a reproducible proxy, not a claim to count perceptual
clicks: only strongly correlated windows are examined, nearby reference sample
steps provide a conservative threshold, and detections within 10 ms are grouped.
This avoids calling legitimate movie transients clicks. The emitted JSON retains
all window results so bad alignment cannot masquerade as an improvement.
"""

import argparse
import array
import cmath
import json
import math
from pathlib import Path
import statistics
import sys
import wave


def load(path):
    with wave.open(str(path), "rb") as wav:
        if wav.getsampwidth() != 2 or wav.getnchannels() != 2:
            raise ValueError("expected stereo signed 16-bit PCM WAV")
        rate = wav.getframerate()
        samples = array.array("h", wav.readframes(wav.getnframes()))
    if sys.byteorder != "little":
        samples.byteswap()
    return rate, samples


def level_metrics(pcm, hz, start, end):
    """Measure a stereo PCM span without assuming its silence is faulty.

    dBFS uses 32768 as full scale; an empty/silent span has null dBFS (negative
    infinity), keeping output valid JSON. Rail and limiter-threshold counts are
    observations, not proof that those samples were clipped. Silence requires
    both channels to be within 2 LSB and includes natural/leading/trailing
    silence. Compare it with the corresponding source span before attributing
    it to an underrun. It does not detect held or repeated nonzero blocks.
    """
    if not all(math.isfinite(v) for v in (hz, start, end)) or hz <= 0 or start < 0 or end < start:
        raise ValueError("expected a positive finite rate and finite 0 <= start <= end")
    if len(pcm) % 2:
        raise ValueError("expected complete stereo PCM frames")
    available = len(pcm) // 2
    def frame_index(seconds):
        position = seconds * hz
        nearest = round(position)
        # Decimal sample-aligned times can land just below their integer frame
        # after binary floating-point multiplication (e.g. 8.38 * 48000).
        return nearest if abs(position - nearest) < 1e-7 else int(position)
    first = min(available, frame_index(start))
    stop = min(available, frame_index(end))
    frames = stop - first
    duration = frames / hz
    peak, energy, rails, near_limiter = 0, 0, 0, 0
    run, gaps, gap_frames, max_gap_frames = 0, 0, 0, 0
    for frame in range(first, stop):
        left, right = pcm[frame * 2], pcm[frame * 2 + 1]
        for value in (left, right):
            magnitude = abs(value)
            peak = max(peak, magnitude)
            energy += value * value
            rails += value <= -32768 or value >= 32767
            near_limiter += magnitude >= 32256
        if abs(left) <= 2 and abs(right) <= 2:
            run += 1
        else:
            # Integer comparison at integer sample rates: exactly 5 ms is
            # excluded without rounding the threshold down to a whole frame.
            if run * 200 > hz:
                gaps += 1
                gap_frames += run
                max_gap_frames = max(max_gap_frames, run)
            run = 0
    if run * 200 > hz:
        gaps += 1
        gap_frames += run
        max_gap_frames = max(max_gap_frames, run)
    rms = math.sqrt(energy / (frames * 2)) / 32768 if frames else 0.0
    return {"start_s": first / hz, "end_s": stop / hz, "measured_s": duration,
            "frames": frames, "sample_count": frames * 2, "rate_hz": hz,
            "peak_lsb": peak, "peak_dbfs": 20 * math.log10(peak / 32768) if peak else None,
            "rms_fraction_fs": rms, "rms_dbfs": 20 * math.log10(rms) if rms else None,
            "s16_rail_samples": rails, "near_limiter_ge_32256_samples": near_limiter,
            "digital_silence_gaps_gt_5ms": gaps,
            "digital_silence_gaps_gt_5ms_per_minute": gaps * 60 / duration if duration else None,
            "digital_silence_gap_total_ms": gap_frames * 1000 / hz,
            "digital_silence_gap_max_ms": max_gap_frames * 1000 / hz}


def reconstruction_metrics(reference, capture, source_hz, capture_hz, onset, start, end, gain):
    """Compare every frame against fixed-onset linear source interpolation.

    No local lag or gain refit can conceal a repeated/dropped nonzero block.
    The source decode already contains any source-domain saturation. Expected
    interpolation is floating point and is not clipped; gain above unity can
    therefore flag limiting as residual error. Residuals also include clock,
    onset, interpolation and quantization differences, so they are not by
    themselves counts of dropped/repeated blocks or newly clipped samples.
    """
    if (not all(math.isfinite(v) for v in (source_hz, capture_hz, onset, start, end, gain))
            or min(source_hz, capture_hz) <= 0 or start < 0 or end < start or gain < 0):
        raise ValueError("invalid reconstruction rate, gain or span")
    if len(reference) % 2 or len(capture) % 2:
        raise ValueError("expected complete stereo PCM frames")
    origin = onset * capture_hz
    first = min(len(capture) // 2, max(0, math.ceil(origin + start * capture_hz)))
    # Only interpolate where both source neighbours exist. Ceil implements the
    # requested half-open timeline interval without rounding its start down.
    stop = min(len(capture) // 2, math.ceil(origin + end * capture_hz),
               math.ceil(origin + max(0, len(reference) // 2 - 1) * capture_hz / source_hz))
    stop = max(first, stop)
    frames = stop - first
    step = source_hz / capture_hz
    maximum_error, squared_error, bad_samples, bad_frames = 0.0, 0.0, 0, 0
    for frame in range(first, stop):
        position = (frame - origin) * step
        bad_frame = False
        for channel in (0, 1):
            expected = sample(reference, position, channel) * gain
            error = abs(capture[frame * 2 + channel] - expected)
            maximum_error = max(maximum_error, error)
            squared_error += error * error
            bad_samples += error > 4
            bad_frame |= error > 4
        bad_frames += bad_frame
    duration = frames / capture_hz
    rms = math.sqrt(squared_error / (frames * 2)) / 32768 if frames else 0.0
    return {"available": True, "expected_gain": gain, "onset_s": onset,
            "capture_start_s": first / capture_hz, "capture_end_s": stop / capture_hz,
            "source_start_s": (first - origin) / capture_hz,
            "source_end_s": (stop - origin) / capture_hz,
            "measured_s": duration, "frames": frames, "local_lag_refit": False,
            "maximum_absolute_error_lsb": maximum_error,
            "residual_rms_dbfs": 20 * math.log10(rms) if rms else None,
            "samples_error_gt_4lsb": bad_samples, "bad_frames_gt_4lsb": bad_frames,
            "bad_frame_fraction": bad_frames / frames if frames else None,
            "bad_frames_per_minute": bad_frames * 60 / duration if duration else None}


def add_reconstruction(result, args, reference, capture, capture_hz):
    """Require explicit onset or a strongly correlated, stable waveform fit."""
    gain = getattr(args, "expected_gain", None)
    if gain is None:
        return
    onset = getattr(args, "onset", None)
    alignment = "explicit_onset"
    if onset is None:
        if (result.get("strongly_correlated_windows", 0) < 2
                or result.get("fit_residual_span_ms", math.inf) > 2
                or "movie_onset_waveform_s" not in result):
            result["reconstruction"] = {"available": False,
                "reason": "requires explicit onset or at least two strongly correlated windows with fit residual span <=2 ms"}
            return
        onset = result["movie_onset_waveform_s"]
        alignment = "strong_waveform_fit"
    result["reconstruction"] = reconstruction_metrics(reference, capture, args.source_hz,
        capture_hz, onset, args.start, args.end, gain)
    result["reconstruction"]["alignment_source"] = alignment


def corr(a, b):
    n = min(len(a), len(b))
    if not n:
        return 0
    sa, sb = sum(a[:n]), sum(b[:n])
    aa = sum(x * x for x in a[:n]) - sa * sa / n
    bb = sum(x * x for x in b[:n]) - sb * sb / n
    return ((sum(x * y for x, y in zip(a[:n], b[:n])) - sa * sb / n) / math.sqrt(aa * bb)) if aa > 0 and bb > 0 else 0


def sample(pcm, position, channel):
    i = int(position)
    if i < 0 or i + 1 >= len(pcm) // 2:
        return 0.0
    fraction = position - i
    return pcm[2 * i + channel] * (1 - fraction) + pcm[2 * i + 2 + channel] * fraction


def ref_window(pcm, start_seconds, seconds, source_hz, destination_hz, stride):
    left, right, mono = [], [], []
    for i in range(0, int(seconds * destination_hz), stride):
        position = (start_seconds + i / destination_hz) * source_hz
        l, r = sample(pcm, position, 0), sample(pcm, position, 1)
        left.append(l)
        right.append(r)
        mono.append((l + r) * 0.5)
    return left, right, mono


def cap_window(pcm, start, frames, stride, channel=None):
    end = min(len(pcm) // 2, start + frames)
    if start < 0:
        return []
    if channel is None:
        return [(pcm[i * 2] + pcm[i * 2 + 1]) * 0.5 for i in range(start, end, stride)]
    return [pcm[i * 2 + channel] for i in range(start, end, stride)]


def envelopes(pcm, hz, seconds=None):
    frames = len(pcm) // 2
    if seconds is not None:
        frames = min(frames, int(seconds * hz))
    result = []
    for hop in range(int(frames / hz * 100)):
        begin, end = int(hop * hz / 100), int((hop + 1) * hz / 100)
        values = [(pcm[2 * i] ** 2 + pcm[2 * i + 1] ** 2) * 0.5 for i in range(begin, min(end, frames), 8)]
        result.append(math.sqrt(sum(values) / len(values)) if values else 0)
    return result


def linear_fit(points):
    x = [p[0] for p in points]
    y = [p[1] for p in points]
    mx, my = statistics.mean(x), statistics.mean(y)
    denominator = sum((v - mx) ** 2 for v in x)
    slope = sum((a - mx) * (b - my) for a, b in points) / denominator if denominator else 0
    intercept = my - slope * mx
    residuals = [b - intercept - slope * a for a, b in points]
    return slope, intercept, max(residuals) - min(residuals)


def spectrum_bands(values, hz):
    """Hann-windowed radix-2 FFT, integrated into fixed frequency bands."""
    count = 1
    while count * 2 <= min(4096, len(values)):
        count *= 2
    if count < 2:
        return []
    data = [complex(values[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (count - 1)))) for i in range(count)]
    j = 0
    for i in range(1, count):
        bit = count >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            data[i], data[j] = data[j], data[i]
    length = 2
    while length <= count:
        root = cmath.exp(-2j * math.pi / length)
        for start in range(0, count, length):
            coefficient = 1 + 0j
            for offset in range(length // 2):
                even, odd = data[start + offset], data[start + offset + length // 2] * coefficient
                data[start + offset], data[start + offset + length // 2] = even + odd, even - odd
                coefficient *= root
        length *= 2
    edges = (0, 250, 1000, 4000, 12000, hz / 2 + 1)
    bands = [0.0] * 5
    for i in range(1, count // 2 + 1):
        frequency = i * hz / count
        for band in range(5):
            if edges[band] <= frequency < edges[band + 1]:
                bands[band] += abs(data[i]) ** 2
                break
    total = sum(bands)
    return [v / total for v in bands] if total else bands


def timeline_metrics(reference, capture, source_hz, capture_hz, onset, start, end):
    """Predetermined timeline metrics, independent of waveform alignment success.

    A 100 ms window is flagged if its maximum channel step exceeds four times
    the reference's maximum plus 500 LSB. Adjacent flagged windows form one
    event. These are deliberately named proxies; timing gaps can misalign the
    device reference and legitimate movie transients may be flagged as a result.
    """
    if not all(math.isfinite(v) for v in (source_hz, capture_hz, onset, start, end)) or min(source_hz, capture_hz) <= 0 or start < 0 or end < start or onset + start < 0:
        raise ValueError("invalid timeline rate or span")
    stop = max(start, min(end, len(reference) / (2 * source_hz) - 0.01, len(capture) / (2 * capture_hz) - onset))
    duration = max(0, stop - start)
    hop = max(1, capture_hz // 10)
    windows, flagged, events, previous_flag = 0, 0, 0, False
    zero_run, zero_qualified, gaps, gap_frames, qualified_gaps, qualified_gap_frames = 0, False, 0, 0, 0, 0
    source_position = start * source_hz
    source_step = source_hz / capture_hz
    capture_start = int((onset + start) * capture_hz)
    total_frames = int(duration * capture_hz)
    max_capture_step, rail = 0, 0
    previous_ref = [sample(reference, max(0, source_position - source_step), ch) for ch in (0, 1)]
    previous_capture = [capture[max(0, capture_start - 1) * 2 + ch] for ch in (0, 1)] if total_frames else [0, 0]
    for base in range(0, total_frames, hop):
        ref_max, cap_max = 0, 0
        for i in range(base, min(base + hop, total_frames)):
            source_index = int(source_position)
            fraction = source_position - source_index
            actual = capture[(capture_start + i) * 2:(capture_start + i) * 2 + 2]
            expected = [reference[source_index * 2 + ch] * (1 - fraction) +
                        reference[(source_index + 1) * 2 + ch] * fraction for ch in (0, 1)]
            for ch in (0, 1):
                ref_max = max(ref_max, abs(expected[ch] - previous_ref[ch]))
                cap_max = max(cap_max, abs(actual[ch] - previous_capture[ch]))
                rail += actual[ch] <= -32768 or actual[ch] >= 32767
            if max(map(abs, actual)) <= 2:
                zero_run += 1
                zero_qualified |= max(map(abs, expected)) > 200
            else:
                if zero_run >= capture_hz // 500:
                    gaps += 1
                    gap_frames += zero_run
                    if zero_qualified:
                        qualified_gaps += 1
                        qualified_gap_frames += zero_run
                zero_run, zero_qualified = 0, False
            previous_ref, previous_capture = expected, actual
            source_position += source_step
        this_flag = cap_max > 4 * ref_max + 500
        flagged += this_flag
        events += this_flag and not previous_flag
        previous_flag = this_flag
        max_capture_step = max(max_capture_step, cap_max)
        windows += 1
    if zero_run >= capture_hz // 500:
        gaps += 1
        gap_frames += zero_run
        if zero_qualified:
            qualified_gaps += 1
            qualified_gap_frames += zero_run
    return {"onset_s": onset, "source_start_s": start, "source_end_s": stop,
            "measured_s": duration, "proxy_100ms_windows": windows,
            "proxy_flagged_100ms_windows": flagged, "proxy_excess_step_events": events,
            "proxy_excess_step_events_per_minute": events * 60 / duration if duration else None,
            "maximum_capture_channel_step": max_capture_step,
            "digital_zero_gaps_ge_2ms": gaps, "digital_zero_gap_ms": gap_frames * 1000 / capture_hz,
            "source_qualified_zero_gaps_ge_2ms": qualified_gaps,
            "source_qualified_zero_gap_ms": qualified_gap_frames * 1000 / capture_hz,
            "movie_rail_samples": rail, "movie_rail_percent": 100 * rail / max(1, total_frames * 2),
            "capture_levels": level_metrics(capture, capture_hz, onset + start, onset + stop),
            "reference_levels": level_metrics(reference, source_hz, start, stop)}


def compare(args):
    source_rate, reference = load(args.reference)
    capture_rate, capture = load(args.capture)
    duration = len(capture) / (2 * capture_rate)
    source_duration = len(reference) / (2 * args.source_hz)
    if getattr(args, "timeline_only", False):
        result = {"reference": str(args.reference), "capture": str(args.capture),
                "timeline": timeline_metrics(reference, capture, args.source_hz, capture_rate,
                                             args.onset, args.start, args.end)}
        add_reconstruction(result, args, reference, capture, capture_rate)
        return result
    re = envelopes(reference, args.source_hz, min(6, source_duration))
    ce = envelopes(capture, capture_rate)
    all_re = envelopes(reference, args.source_hz)
    candidates = range(max(1, min(int(args.onset_search * 100), len(ce) - len(re) + 1)))
    onset_hop = max(candidates, key=lambda i: corr(re, ce[i:i + len(re)]))
    onset = int(args.onset * capture_rate) if getattr(args, "onset", None) is not None else onset_hop * capture_rate // 100
    onset_score = corr(re, ce[onset_hop:onset_hop + len(re)])
    frames = int(args.window * capture_rate)
    radius = int(args.search_ms * capture_rate / 1000)
    rows = []
    time = args.start
    stop = min(args.end, source_duration - args.window, duration - onset / capture_rate - args.window)
    while time <= stop:
        expected = onset + int(time * capture_rate)
        rl, rr, rm = ref_window(reference, time, args.window, args.source_hz, capture_rate, 8)
        best_score, best_offset = -2, 0
        # 16-sample coarse lag search, then individual-sample refinement. Lag is
        # unconstrained across windows so a gap/drift remains visible in the rows.
        if args.search_ms > 250:
            # An underrunning device can accumulate seconds of silence while
            # each surviving waveform fragment still has the correct pitch.
            # First shortlist envelope matches at 100 Hz, then search samples.
            env_ref = all_re[int(time * 100):int((time + args.window) * 100)]
            center = int(expected * 100 / capture_rate)
            env_radius = int(args.search_ms / 10)
            ranked = sorted(((corr(env_ref, ce[i:i + len(env_ref)]), i)
                             for i in range(max(0, center - env_radius),
                                            min(len(ce) - len(env_ref), center + env_radius) + 1)), reverse=True)
            shortlist = []
            for _, i in ranked:
                if all(abs(i - previous) >= 3 for previous in shortlist):
                    shortlist.append(i)
                    if len(shortlist) == 12:
                        break
            offsets = sorted({offset for hop in shortlist
                              for offset in range(int(hop * capture_rate / 100) - expected - capture_rate // 100,
                                                  int(hop * capture_rate / 100) - expected + capture_rate // 100 + 1, 16)})
        else:
            offsets = range(-radius, radius + 1, 16)
        for offset in offsets:
            cm = cap_window(capture, expected + offset, frames, 8)
            score = corr(rm, cm)
            if score > best_score:
                best_score, best_offset = score, offset
        fine_best = best_offset
        rl, rr, rm = ref_window(reference, time, args.window, args.source_hz, capture_rate, 2)
        best_score = -2
        for offset in range(best_offset - 16, best_offset + 17):
            score = corr(rm, cap_window(capture, expected + offset, frames, 2))
            if score > best_score:
                best_score, fine_best = score, offset
        at = expected + fine_best
        cl = cap_window(capture, at, frames, 2, 0)
        cr = cap_window(capture, at, frames, 2, 1)
        gains = [sum(x * y for x, y in zip(r, c)) / sum(x * x for x in r) if any(r) else 0 for r, c in ((rl, cl), (rr, cr))]
        normal = [corr(rl, cl), corr(rr, cr)]
        swapped = [corr(rl, cr), corr(rr, cl)]
        row = {"reference_time_s": time, "capture_time_s": at / capture_rate,
               "lag_ms": fine_best * 1000 / capture_rate, "mono_correlation": best_score,
               "channel_correlation": normal, "swapped_channel_correlation": swapped,
               "channel_gain": gains}
        if min(normal) >= args.minimum_correlation:
            # Estimate local sample clock from the relative lag of two halves.
            # Unlike a fit between distant windows, this does not interpret
            # accumulated underrun silence as a musical pitch change.
            half = frames // 2
            half_lags, half_scores = [], []
            for half_index in (0, 1):
                _, _, half_reference = ref_window(reference, time + half_index * half / capture_rate,
                                                  half / capture_rate, args.source_hz, capture_rate, 8)
                score, lag = -2, 0
                for offset in range(-capture_rate // 500, capture_rate // 500 + 1):
                    current = corr(half_reference, cap_window(capture, at + half_index * half + offset, half, 8))
                    if current > score:
                        score, lag = current, offset
                half_scores.append(score)
                half_lags.append(lag)
            if min(half_scores) >= 0.95:
                row["local_source_playback_hz"] = args.source_hz / (1 + (half_lags[1] - half_lags[0]) / half)
            # Full-rate steps, conditioned on a +/-1 ms reference neighbourhood.
            full_l, full_r, _ = ref_window(reference, time, args.window, args.source_hz, capture_rate, 1)
            reference_spectrum = spectrum_bands([(l + r) * 0.5 for l, r in zip(full_l, full_r)], capture_rate)
            capture_spectrum = spectrum_bands(cap_window(capture, at, frames, 1), capture_rate)
            row.update(reference_spectrum_band_fractions=reference_spectrum,
                       capture_spectrum_band_fractions=capture_spectrum)
            step_ref = [[abs(values[i] - values[i - 1]) for i in range(1, len(values))] for values in (full_l, full_r)]
            bucket = max(1, capture_rate // 1000)
            maxima = [[max(values[i:i + bucket], default=0) for i in range(0, len(values), bucket)] for values in step_ref]
            events, last_event, gaps, zero_run, gap_frames = 0, -capture_rate, 0, 0, 0
            for i in range(1, frames):
                transient = False
                for ch in (0, 1):
                    j = i // bucket
                    nearby = max(maxima[ch][max(0, j - 1):j + 2], default=0) * abs(gains[ch])
                    step = abs(capture[(at + i) * 2 + ch] - capture[(at + i - 1) * 2 + ch])
                    if step > max(4096, 4 * nearby + 1024):
                        transient = True
                if transient and i - last_event >= capture_rate // 100:
                    events += 1
                if transient:
                    last_event = i
                expected_level = max(abs(full_l[i] * gains[0]), abs(full_r[i] * gains[1]))
                if abs(capture[(at + i) * 2]) <= 2 and abs(capture[(at + i) * 2 + 1]) <= 2 and expected_level > 200:
                    zero_run += 1
                else:
                    if zero_run >= capture_rate // 500:
                        gaps += 1
                        gap_frames += zero_run
                    zero_run = 0
            if zero_run >= capture_rate // 500:
                gaps += 1
                gap_frames += zero_run
            row.update(excess_step_events=events, conditioned_silence_gaps=gaps,
                       conditioned_silence_gap_ms=gap_frames * 1000 / capture_rate)
        rows.append(row)
        time += args.step
    valid = [r for r in rows if min(r["channel_correlation"]) >= args.minimum_correlation]
    result = {"reference": str(args.reference), "capture": str(args.capture),
              "source_file_hz": source_rate, "assumed_source_playback_hz": args.source_hz,
              "capture_hz": capture_rate, "capture_duration_s": duration,
              "onset_envelope_s": onset / capture_rate, "onset_envelope_correlation": onset_score,
              "windows": rows, "strongly_correlated_windows": len(valid),
              "rail_samples": sum(v <= -32768 or v >= 32767 for v in capture),
              "rail_percent": 100 * sum(v <= -32768 or v >= 32767 for v in capture) / max(1, len(capture)),
              "spectrum_band_edges_hz": [0, 250, 1000, 4000, 12000, capture_rate / 2],
              "peak": max(map(abs, capture), default=0),
              "mean_mono_correlation": statistics.mean(r["mono_correlation"] for r in rows) if rows else None}
    result["poorly_correlated_windows"] = len(rows) - len(valid)
    if len(valid) >= 2:
        slope, offset, spread = linear_fit([(r["reference_time_s"], r["lag_ms"] / 1000) for r in valid])
        hz = args.source_hz / (1 + slope)
        result.update(effective_source_delivery_hz=hz,
                      drift_ms_per_s=slope * 1000, fit_residual_span_ms=spread * 1000,
                      movie_onset_waveform_s=onset / capture_rate + offset,
                      aligned_measured_seconds=len(valid) * args.window,
                      excess_step_events=sum(r["excess_step_events"] for r in valid),
                      excess_step_events_per_measured_minute=sum(r["excess_step_events"] for r in valid) * 60 / (len(valid) * args.window),
                      spectrum_fraction_max_error=max(abs(a - b) for r in valid for a, b in zip(r["reference_spectrum_band_fractions"], r["capture_spectrum_band_fractions"])),
                      channel_gain_median=[statistics.median(r["channel_gain"][ch] for r in valid) for ch in (0, 1)])
        result["clock_fit_includes_gaps"] = True
        local_rates = [r["local_source_playback_hz"] for r in valid if "local_source_playback_hz" in r]
        if local_rates:
            local_rate = statistics.median(local_rates)
            result.update(inferred_source_playback_hz=local_rate,
                          inferred_pitch_cents_from_native=1200 * math.log2(local_rate / source_rate))
    if getattr(args, "timeline", False):
        result["timeline"] = timeline_metrics(reference, capture, args.source_hz, capture_rate,
                                              args.onset if args.onset is not None else result.get("movie_onset_waveform_s", onset / capture_rate),
                                              args.start, args.end)
    add_reconstruction(result, args, reference, capture, capture_rate)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--source-hz", type=float, default=44100 * 30 / 29.97)
    parser.add_argument("--onset-search", type=float, default=20)
    parser.add_argument("--onset", type=float, help="explicit movie onset in capture seconds, bypassing envelope alignment")
    parser.add_argument("--timeline", action="store_true", help="also measure whole-span predetermined-timeline step/gap proxies")
    parser.add_argument("--timeline-only", action="store_true", help="skip waveform searches; requires --onset")
    parser.add_argument("--search-ms", type=float, default=120)
    parser.add_argument("--start", type=float, default=1)
    parser.add_argument("--end", type=float, default=120)
    parser.add_argument("--step", type=float, default=10)
    parser.add_argument("--window", type=float, default=0.5)
    parser.add_argument("--minimum-correlation", type=float, default=0.85)
    parser.add_argument("--expected-gain", type=float, help="optionally reconstruct every sample at this gain; requires explicit onset or a stable strong waveform fit")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()
    if args.source_hz <= 0 or args.window <= 0 or args.step <= 0 or args.search_ms < 0 or args.onset_search < 0:
        parser.error("rates/window/step must be positive; search limits must be nonnegative")
    if args.timeline_only and args.onset is None:
        parser.error("--timeline-only requires --onset")
    if args.expected_gain is not None and (not math.isfinite(args.expected_gain) or args.expected_gain < 0):
        parser.error("--expected-gain must be finite and nonnegative")
    result = compare(args)
    encoded = json.dumps(result, indent=2, sort_keys=True)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)


if __name__ == "__main__":
    main()
