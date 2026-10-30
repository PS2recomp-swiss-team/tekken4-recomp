"""Checks the intro movie's sound in a run's WAV (TEKKEN4_SOUND_WAV) against the movie's own audio decoded from the
disc. Stdlib only. Run with python -I.

  python -I tools/movie_audio_check.py <iso> <wav> [--from 0] [--to 40] [--win 1.0] [--step 2.0] [--hz 44100]

Reference: the intro movie (DATA.BIN sector 67289, 0x27 video + 2 audio sectors per unit; audio = SPU ADPCM, left
and right alternating every 16-byte block, 3584 stereo frames per unit), decoded at --hz and resampled to 48 kHz.
1. Finds where the movie starts in the WAV (100 Hz loudness envelopes, cross-correlation).
2. Every --step seconds, correlates a --win second window of the WAV with the reference near the expected place
   (+-60 ms) and prints the lag and the correlation. Right pitch and speed: lag constant (drift ~0 ms) and
   correlation near 1; too fast or slow playback: a drifting lag; gaps or garbage: low correlation.
3. Gaps: runs of >= 2 ms of digital silence (|x| <= 2) in the WAV where the reference is not silent.
   Clicks: sample steps above 4x the reference's largest step in the same window.
"""
import array
import math
import sys
import wave

DATA_BIN_LBN = 401
MOVIE_SECTOR = 67289
MOVIE_SIZE = 128974848
VIDEO = 0x27 * 2048
AUDIO = 2 * 2048
UNIT = VIDEO + AUDIO
FILTERS = [(0, 0), (60, 0), (115, -52), (98, -55), (122, -60)]


def decode_block(blk, st, out):
    shift = blk[0] & 15
    if shift > 12:
        shift = 9
    f0, f1 = FILTERS[min((blk[0] >> 4) & 7, 4)]
    for b in blk[2:16]:
        for nib in (b & 15, b >> 4):
            r = (nib << 12) & 0xFFFF
            if r >= 32768:
                r -= 65536
            r >>= shift
            s = r + ((st[0] * f0 + st[1] * f1 + 32) >> 6)
            s = -32768 if s < -32768 else 32767 if s > 32767 else s
            st[1] = st[0]
            st[0] = s
            out.append(s)


def reference(iso_path, seconds, hz):
    units = int(seconds * hz / 3584) + 2
    left, right = [], []
    sl, sr = [0, 0], [0, 0]
    with open(iso_path, "rb") as iso:
        for u in range(units):
            iso.seek((DATA_BIN_LBN + MOVIE_SECTOR) * 2048 + u * UNIT + VIDEO)
            a = iso.read(AUDIO)
            for k in range(0, AUDIO, 32):
                decode_block(a[k:k + 16], sl, left)
                decode_block(a[k + 16:k + 32], sr, right)
    # linear resample to 48 kHz (good enough for correlation)
    n = int(len(left) * 48000 / hz) - 2
    step = hz / 48000.0
    mono = []
    for i in range(n):
        p = i * step
        j = int(p)
        t = p - j
        mono.append(((left[j] + right[j]) * (1 - t) + (left[j + 1] + right[j + 1]) * t) * 0.5)
    return mono


def load_wav(path):
    with wave.open(path, "rb") as w:
        ch, rate, count = w.getnchannels(), w.getframerate(), w.getnframes()
        raw = w.readframes(count)
    s = array.array("h")
    s.frombytes(raw[: len(raw) // 2 * 2])
    if sys.byteorder == "big":
        s.byteswap()
    if rate != 48000:
        sys.exit("expects a 48 kHz WAV")
    if ch == 1:
        return list(s)
    return [(s[i] + s[i + 1]) * 0.5 for i in range(0, len(s) - 1, 2)]


def envelope(x, hop=480):
    return [math.sqrt(sum(v * v for v in x[i:i + hop]) / hop) for i in range(0, len(x) - hop, hop)]


def corr(a, b):
    n = min(len(a), len(b))
    if n == 0:
        return 0.0
    ma = sum(a[:n]) / n
    mb = sum(b[:n]) / n
    num = sum((a[i] - ma) * (b[i] - mb) for i in range(n))
    da = math.sqrt(sum((a[i] - ma) ** 2 for i in range(n)))
    db = math.sqrt(sum((b[i] - mb) ** 2 for i in range(n)))
    return num / (da * db) if da and db else 0.0


def main():
    args = sys.argv[1:]
    opts = {"--from": 0.0, "--to": 40.0, "--win": 1.0, "--step": 2.0, "--hz": 44100.0}
    for k in list(opts):
        if k in args:
            i = args.index(k)
            opts[k] = float(args[i + 1])
            del args[i:i + 2]
    iso, wav = args[0], args[1]
    span = opts["--to"] - opts["--from"]
    ref = reference(iso, span + 2.0, opts["--hz"])
    x = load_wav(wav)
    x0 = int(opts["--from"] * 48000)
    x = x[x0:x0 + int((span + 15.0) * 48000)]
    # 1. movie start in the WAV: envelope correlation of the first 8 s of the reference
    ex, er = envelope(x), envelope(ref[: 8 * 48000])
    best = max(range(0, max(1, len(ex) - len(er))), key=lambda L: corr(ex[L:L + len(er)], er))
    start = best * 480
    print("movie audio starts at WAV %.3f s (envelope)" % ((x0 + start) / 48000))
    # 2. lag and correlation per window, refined at full rate +-60 ms (decimated by 4 for speed)
    win = int(opts["--win"] * 48000)
    rows = []
    t = 0.5
    while (t + opts["--win"]) * 48000 < len(ref) and start + (t + opts["--win"]) * 48000 + 4000 < len(x):
        r0 = int(t * 48000)
        bestc, bestl = -2.0, 0
        for lags, dec in ((range(-2880, 2881, 16), 8), (None, 2)):
            if lags is None:  # fine pass around the coarse best
                lags = range(bestl - 16, bestl + 17, 2)
                bestc = -2.0
            rseg = ref[r0:r0 + win:dec]
            for lag in lags:
                a = start + r0 + lag
                if a < 0:
                    continue
                c = corr(x[a:a + win:dec], rseg)
                if c > bestc:
                    bestc, bestl = c, lag
        rows.append((t, bestl / 48.0, bestc))
        t += opts["--step"]
    for t, lag, c in rows:
        print("  movie t=%5.1f s  lag %+7.2f ms  corr %.3f" % (t, lag, c))
    if rows:
        lags = [r[1] for r in rows]
        cs = [r[2] for r in rows]
        print("lag drift %.2f ms (min %.2f, max %.2f), correlation mean %.3f min %.3f" %
              (max(lags) - min(lags), min(lags), max(lags), sum(cs) / len(cs), min(cs)))
    # 3. gaps and clicks over the compared span
    end = min(len(x), start + len(ref))
    gaps = 0
    gap_ms = 0.0
    run = 0
    for i in range(start, end):
        if abs(x[i]) <= 2 and abs(ref[i - start]) > 200:
            run += 1
        else:
            if run >= 96:
                gaps += 1
                gap_ms += run / 48.0
            run = 0
    clicks = 0
    for w0 in range(start, end - 4800, 4800):
        rmax = max(abs(ref[i - start + 1] - ref[i - start]) for i in range(w0, w0 + 4799))
        xmax = max(abs(x[i + 1] - x[i]) for i in range(w0, w0 + 4799))
        if xmax > 4 * rmax + 500:
            clicks += 1
    print("gaps >= 2 ms: %d (%.1f ms total); 100 ms windows with clicks: %d of %d" %
          (gaps, gap_ms, clicks, max(0, (end - start - 4800) // 4800)))


if __name__ == "__main__":
    main()
