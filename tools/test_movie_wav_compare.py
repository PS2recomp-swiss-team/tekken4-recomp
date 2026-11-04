"""Synthetic validation of reference-conditioned movie measurements; no game data."""
import array
import importlib.util
import math
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
import wave


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("movie_wav_compare", ROOT / "tools/movie_wav_compare.py")
COMPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COMPARE)


def write(path, samples, rate=8000):
    with wave.open(str(path), "wb") as w:
        w.setparams((2, 2, rate, 0, "NONE", "not compressed"))
        w.writeframes(array.array("h", samples).tobytes())


class LevelMetricsTests(unittest.TestCase):
    def test_half_scale_dbfs_and_section_scope(self):
        pcm = [32767, -32768] + [16384, -16384] * 8 + [32767, -32768]
        result = COMPARE.level_metrics(pcm, 8, 1 / 8, 9 / 8)
        self.assertEqual(result["frames"], 8)
        self.assertEqual(result["measured_s"], 1)
        self.assertAlmostEqual(result["peak_dbfs"], -6.020599913279624)
        self.assertAlmostEqual(result["rms_dbfs"], -6.020599913279624)
        self.assertEqual(result["s16_rail_samples"], 0)
        self.assertEqual(result["near_limiter_ge_32256_samples"], 0)
        decimal = COMPARE.level_metrics([100, -100] * 100, 100, .29, .30)
        self.assertEqual(decimal["frames"], 1)

    def test_rail_and_limiter_are_distinct_observations(self):
        result = COMPARE.level_metrics([32767, -32768, 32256, -32256], 2, 0, 1)
        self.assertEqual(result["peak_dbfs"], 0)
        self.assertEqual(result["s16_rail_samples"], 2)
        self.assertEqual(result["near_limiter_ge_32256_samples"], 4)
        expected = math.sqrt((32767**2 + 32768**2 + 2 * 32256**2) / 4) / 32768
        self.assertAlmostEqual(result["rms_fraction_fs"], expected)

    def test_strictly_over_5ms_and_trailing_silence(self):
        # 40 frames at 8 kHz is exactly 5 ms; only the trailing 41 qualifies.
        pcm = [100, -100] + [0, 0] * 40 + [100, -100] + [2, -2] * 41
        result = COMPARE.level_metrics(pcm, 8000, 0, len(pcm) / 16000)
        self.assertEqual(result["digital_silence_gaps_gt_5ms"], 1)
        self.assertEqual(result["digital_silence_gap_total_ms"], 5.125)
        self.assertEqual(result["digital_silence_gap_max_ms"], 5.125)
        self.assertAlmostEqual(result["digital_silence_gaps_gt_5ms_per_minute"], 60 * 8000 / 83)
        # A single non-silent channel must interrupt the stereo silence run.
        interrupted = [0, 0] * 40 + [0, 3] + [0, 0] * 40
        self.assertEqual(COMPARE.level_metrics(interrupted, 8000, 0, 1)["digital_silence_gaps_gt_5ms"], 0)

    def test_nonintegral_frame_threshold_and_natural_silence(self):
        for frames, expected in ((220, 0), (221, 1)):
            pcm = [0, 0] * frames
            result = COMPARE.level_metrics(pcm, 44100, 0, 1)
            self.assertEqual(result["digital_silence_gaps_gt_5ms"], expected)
            self.assertIsNone(result["peak_dbfs"])
            self.assertIsNone(result["rms_dbfs"])
        # Silence present in both source and capture is still counted. It is
        # an observable run, not a source-conditioned assertion of an underrun.
        natural = [100, 100] * 80 + [0, 0] * 80 + [100, 100] * 80
        result = COMPARE.timeline_metrics(natural, natural, 8000, 8000, 0, 0, .02)
        self.assertEqual(result["capture_levels"]["digital_silence_gaps_gt_5ms"], 1)
        self.assertEqual(result["reference_levels"]["digital_silence_gaps_gt_5ms"], 1)
        self.assertEqual(result["source_qualified_zero_gaps_ge_2ms"], 0)

    def test_empty_and_invalid_spans(self):
        result = COMPARE.level_metrics([100, -100], 8000, 1, 2)
        self.assertEqual(result["measured_s"], 0)
        self.assertEqual(result["sample_count"], 0)
        self.assertIsNone(result["rms_dbfs"])
        self.assertIsNone(result["digital_silence_gaps_gt_5ms_per_minute"])
        for hz, start, end in ((0, 0, 1), (float("nan"), 0, 1), (8000, -1, 1),
                               (8000, 2, 1), (8000, 0, float("inf"))):
            with self.assertRaises(ValueError):
                COMPARE.level_metrics([], hz, start, end)
        with self.assertRaises(ValueError):
            COMPARE.level_metrics([0], 8000, 0, 1)
        result = COMPARE.timeline_metrics([], [], 8000, 8000, 0, 1, 2)
        self.assertEqual(result["measured_s"], 0)


class ReconstructionTests(unittest.TestCase):
    def test_exact_scaled_content_and_repeated_nonzero_block(self):
        reference = []
        for frame in range(4000):
            reference.extend((2000 + (frame * 138) % 10000, -2000 - (frame * 246) % 8000))
        capture = [value // 2 for value in reference]
        clean = COMPARE.reconstruction_metrics(reference, capture, 1000, 1000, 0, 0, 3.5, .5)
        self.assertEqual(clean["maximum_absolute_error_lsb"], 0)
        self.assertIsNone(clean["residual_rms_dbfs"])
        self.assertEqual(clean["bad_frames_gt_4lsb"], 0)
        self.assertEqual(clean["measured_s"], 3.5)
        # Repetition is nonzero, so a digital-silence-gap detector cannot see it.
        capture[1500 * 2:1600 * 2] = capture[1200 * 2:1300 * 2]
        result = COMPARE.reconstruction_metrics(reference, capture, 1000, 1000, 0, 0, 3.5, .5)
        self.assertEqual(result["bad_frames_gt_4lsb"], 100)
        self.assertEqual(result["samples_error_gt_4lsb"], 200)
        self.assertAlmostEqual(result["bad_frames_per_minute"], 100 * 60 / 3.5)
        self.assertGreater(result["maximum_absolute_error_lsb"], 4)
        self.assertLess(result["residual_rms_dbfs"], 0)
        self.assertEqual(COMPARE.level_metrics(capture, 1000, 0, 3.5)["digital_silence_gaps_gt_5ms"], 0)

    def test_linear_interpolation_fixed_fractional_onset_and_rate(self):
        reference = [1000, -1000, 3000, -3000, 5000, -5000, 7000, -7000]
        # Source starts at capture time .5 s. At capture t=1,2,3,4,5 s its
        # source positions are .25,.75,1.25,1.75,2.25, giving these exact values.
        capture = [0, 0, 750, -750, 1250, -1250, 1750, -1750, 2250, -2250, 2750, -2750]
        result = COMPARE.reconstruction_metrics(reference, capture, .5, 1, .5, 0, 5, .5)
        self.assertEqual(result["frames"], 5)
        self.assertEqual(result["capture_start_s"], 1)
        self.assertEqual(result["maximum_absolute_error_lsb"], 0)
        self.assertFalse(result["local_lag_refit"])

    def test_unreliable_fit_does_not_reconstruct_without_explicit_onset(self):
        args = SimpleNamespace(expected_gain=.5, onset=None, source_hz=1000, start=0, end=1)
        result = {"strongly_correlated_windows": 12, "fit_residual_span_ms": 20, "movie_onset_waveform_s": 0}
        COMPARE.add_reconstruction(result, args, [100, 100] * 1001, [50, 50] * 1000, 1000)
        self.assertFalse(result["reconstruction"]["available"])
        args.onset = 0
        COMPARE.add_reconstruction(result, args, [100, 100] * 1001, [50, 50] * 1000, 1000)
        self.assertTrue(result["reconstruction"]["available"])
        self.assertEqual(result["reconstruction"]["alignment_source"], "explicit_onset")
        self.assertEqual(result["reconstruction"]["maximum_absolute_error_lsb"], 0)


class CompareTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "build").mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="movie-compare-test-", dir=ROOT / "build")
        self.folder = Path(self.temp.name)
        self.reference = []
        for i in range(12 * 8000):
            t = i / 8000
            envelope = 0.4 + 0.3 * math.sin(t * 1.71) + 0.2 * math.cos(t * 3.19)
            left = (math.sin(2 * math.pi * (97 * t + 1.1 * t * t)) +
                    0.6 * math.sin(2 * math.pi * 271.37 * t) + 0.3 * math.cos(2 * math.pi * 463.11 * t))
            right = (math.cos(2 * math.pi * (151 * t + 0.7 * t * t)) +
                     0.5 * math.sin(2 * math.pi * 313.71 * t) + 0.4 * math.cos(2 * math.pi * 419.13 * t))
            self.reference.extend((int(6000 * envelope * left), int(5000 * envelope * right)))
        write(self.folder / "reference.wav", self.reference)

    def tearDown(self):
        self.temp.cleanup()

    def run_compare(self, capture):
        write(self.folder / "capture.wav", capture)
        return COMPARE.compare(SimpleNamespace(reference=self.folder / "reference.wav",
            capture=self.folder / "capture.wav", source_hz=8000, onset_search=1,
            search_ms=30, start=1, end=10, step=3, window=0.5, minimum_correlation=0.85))

    def test_unchanged_transients_are_not_clicks(self):
        result = self.run_compare(self.reference)
        self.assertAlmostEqual(result["inferred_source_playback_hz"], 8000)
        self.assertEqual(result["excess_step_events"], 0)
        self.assertGreater(result["mean_mono_correlation"], 0.999999)
        self.assertLess(result["spectrum_fraction_max_error"], 0.000001)

    def test_spectral_band_of_known_tone(self):
        signal = [math.sin(2 * math.pi * 1400 * i / 8000) for i in range(4096)]
        bands = COMPARE.spectrum_bands(signal, 8000)
        self.assertGreater(bands[2], 0.999)

    def test_timeline_proxy_and_digital_gap(self):
        clean = COMPARE.timeline_metrics(self.reference, self.reference, 8000, 8000, 0, 1, 2)
        self.assertEqual(clean["proxy_excess_step_events"], 0)
        capture = self.reference[:]
        capture[int(1.2 * 8000) * 2] = 32767
        capture[int(1.2 * 8000) * 2 + 1] = -32768
        capture[int(1.4 * 8000) * 2:int(1.42 * 8000) * 2] = [0] * (160 * 2)
        result = COMPARE.timeline_metrics(self.reference, capture, 8000, 8000, 0, 1, 2)
        self.assertEqual(result["proxy_excess_step_events"], 1)
        self.assertEqual(result["digital_zero_gaps_ge_2ms"], 1)
        self.assertEqual(result["digital_zero_gap_ms"], 20)

    def test_delay_gain_clock_drift(self):
        capture = [0] * (1040 * 2)
        for i in range(95000):
            for channel in (0, 1):
                capture.append(int(COMPARE.sample(self.reference, i * 1.0005, channel) * 0.7))
        result = self.run_compare(capture)
        self.assertAlmostEqual(result["movie_onset_waveform_s"], 0.13, delta=0.0003)
        self.assertAlmostEqual(result["inferred_source_playback_hz"], 8004, delta=0.2)
        self.assertAlmostEqual(result["channel_gain_median"][0], 0.7, delta=0.005)

    def test_channel_swap_and_injected_click(self):
        swapped = []
        for i in range(0, len(self.reference), 2):
            swapped.extend((self.reference[i + 1], self.reference[i]))
        result = self.run_compare(swapped)
        self.assertGreater(result["windows"][0]["swapped_channel_correlation"][0], 0.999)
        capture = self.reference[:]
        capture[int(1.2 * 8000) * 2] = 32767
        capture[int(1.2 * 8000) * 2 + 1] = -32768
        result = self.run_compare(capture)
        self.assertEqual(result["excess_step_events"], 1)


if __name__ == "__main__":
    unittest.main()
