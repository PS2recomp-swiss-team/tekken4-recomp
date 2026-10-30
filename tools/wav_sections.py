"""Level and spectrum per named section of a 16-bit PCM WAV, so music can be told from effects without ears. Stdlib only.

  python -I tools/wav_sections.py <wav> <name>=<t0>-<t1> [<name>=<t0>-<t1> ...] [--frames 24]

Per section: rms (0..1), peak, clipped share, zero-crossing rate (per second), L/R correlation, spectral flatness
(0 = tonal, 1 = noise) and the share of energy per octave-ish band (from 2048-point FFTs of --frames frames spread
evenly over the section, Hann window, mid channel). Prints one JSON object per section, one per line.
Music typically: steady rms over the section, flatness well below 0.3, energy spread over 100 Hz .. 6 kHz;
silence: rms ~0; a lone effect: rms bursts with long quiet gaps (see 'rms_quiet_share').
"""
import array
import cmath
import json
import math
import sys
import wave

BANDS = [(20, 100), (100, 250), (250, 500), (500, 1000), (1000, 2000), (2000, 4000), (4000, 8000), (8000, 20000)]
N = 2048


def fft(x):
    n = len(x)
    if n == 1:
        return x
    even = fft(x[0::2])
    odd = fft(x[1::2])
    out = [0j] * n
    for k in range(n // 2):
        t = cmath.exp(-2j * math.pi * k / n) * odd[k]
        out[k] = even[k] + t
        out[k + n // 2] = even[k] - t
    return out


def analyse(samples, ch, rate, t0, t1, frames):
    a = max(0, int(t0 * rate))
    b = min(len(samples) // ch, int(t1 * rate))
    if b - a < N:
        return {"error": "section too short or past the end"}
    left = samples[a * ch:b * ch:ch]
    right = samples[a * ch + 1:b * ch:ch] if ch > 1 else left
    n = len(left)
    ss = sum(v * v for v in left) + sum(v * v for v in right)
    rms = math.sqrt(ss / (2 * n)) / 32768.0
    peak = max(max(left), -min(left), max(right), -min(right))
    clipped = sum(1 for v in left if abs(v) >= 32256) + sum(1 for v in right if abs(v) >= 32256)
    zc = sum(1 for i in range(1, n) if (left[i - 1] < 0) != (left[i] < 0))
    lr = sum(l * r for l, r in zip(left, right))
    ll = sum(l * l for l in left)
    rr = sum(r * r for r in right)
    corr = lr / math.sqrt(ll * rr) if ll and rr else 0.0
    # rms per 100 ms block: how much of the section is quiet (effects leave gaps, music does not)
    block = rate // 10
    blocks = []
    for i in range(0, n - block + 1, block):
        s = sum(v * v for v in left[i:i + block])
        blocks.append(math.sqrt(s / block) / 32768.0)
    quiet = sum(1 for v in blocks if v < 0.01) / len(blocks) if blocks else 0.0
    band = [0.0] * len(BANDS)
    flat = []
    window = [0.5 - 0.5 * math.cos(2 * math.pi * i / (N - 1)) for i in range(N)]
    step = max(1, (n - N) // max(1, frames - 1))
    for f in range(frames):
        start = min(f * step, n - N)
        mid = [(left[start + i] + right[start + i]) * 0.5 * window[i] for i in range(N)]
        spec = fft([complex(v, 0) for v in mid])
        power = [abs(spec[k]) ** 2 for k in range(1, N // 2)]
        for k, p in enumerate(power, start=1):
            hz = k * rate / N
            for j, (lo, hi) in enumerate(BANDS):
                if lo <= hz < hi:
                    band[j] += p
                    break
        valid = [p for p in power if p > 0]
        if valid and sum(valid) > 1e3 * len(valid):
            geo = math.exp(sum(math.log(p) for p in valid) / len(valid))
            flat.append(geo / (sum(valid) / len(valid)))
    total = sum(band) or 1.0
    return {
        "rms": round(rms, 5),
        "peak": peak,
        "clipped_share": round(clipped / (2 * n), 5),
        "zero_cross_per_s": round(zc * rate / n),
        "lr_corr": round(corr, 3),
        "rms_quiet_share": round(quiet, 3),
        "rms_100ms_min_max": [round(min(blocks), 4), round(max(blocks), 4)] if blocks else None,
        "flatness": round(sum(flat) / len(flat), 4) if flat else None,
        "bands": {f"{lo}-{hi}": round(e / total, 3) for (lo, hi), e in zip(BANDS, band)},
    }


def main():
    args = sys.argv[1:]
    frames = 24
    if "--frames" in args:
        i = args.index("--frames")
        frames = int(args[i + 1])
        del args[i:i + 2]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    with wave.open(args[0], "rb") as w:
        ch, width, rate, count = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(count)
    if width != 2:
        sys.exit("16-bit PCM only")
    samples = array.array("h")
    samples.frombytes(raw[: (len(raw) // 2) * 2])
    if sys.byteorder == "big":
        samples.byteswap()
    for spec in args[1:]:
        name, span = spec.split("=", 1)
        t0, t1 = (float(v) for v in span.split("-", 1))
        res = {"section": name, "t0": t0, "t1": t1}
        res.update(analyse(samples, ch, rate, t0, t1, frames))
        print(json.dumps(res))


if __name__ == "__main__":
    main()
