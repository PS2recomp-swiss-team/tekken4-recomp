"""Numbers for a WAV (16-bit PCM), so an AI can judge audio it cannot hear. Stdlib only.

  python -I tools/wav_stats.py <wav> [--win 5] [--silence-thr 8]
Prints one JSON object: duration, channels, rate, per-window rms/peak (dBFS-free, 0..1 rms), clipped sample count
(|x| >= 32767), longest digital silence (run of frames with all channels |x| <= silence-thr, default 8 = near 0), and
flags: "silent" (peak <= 8), "clipping" (clipped > 0), "dead_windows" (windows with rms < 0.0005).
Typical judgement: music/voices -> rms 0.02..0.3 per window, clipped 0, longest_silence_s small; all zeros = no audio.
"""
import array
import json
import math
import sys
import wave


def analyse(path, win_s=5.0, sil_thr=8):
    with wave.open(path, "rb") as w:
        ch, width, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if width != 2:
        return {"file": path, "error": f"{width * 8}-bit not supported"}
    s = array.array("h")
    s.frombytes(raw[: (len(raw) // 2) * 2])
    if sys.byteorder == "big":
        s.byteswap()
    frames = len(s) // ch if ch else 0
    res = {"file": path, "channels": ch, "rate": rate, "frames": frames, "seconds": round(frames / rate, 3) if rate else 0}
    if not frames:
        res.update(windows=[], clipped=0, longest_silence_s=0, flags=["empty"])
        return res
    clipped = sum(1 for v in s if v >= 32767 or v <= -32767)
    peak_all = max(max(s), -min(s))
    # per-window
    wf = max(1, int(win_s * rate))
    windows = []
    dead = 0
    for f0 in range(0, frames, wf):
        seg = s[f0 * ch:(min(frames, f0 + wf)) * ch]
        acc = 0
        pk = 0
        for v in seg:
            acc += v * v
            a = -v if v < 0 else v
            if a > pk:
                pk = a
        rms = math.sqrt(acc / len(seg)) / 32768.0
        if rms < 0.0005:
            dead += 1
        windows.append({"t0": round(f0 / rate, 1), "t1": round(min(frames, f0 + wf) / rate, 1), "rms": round(rms, 5), "peak": pk})
    # longest digital silence
    longest = cur = 0
    for i in range(0, frames * ch, ch):
        if all(-sil_thr <= s[i + k] <= sil_thr for k in range(ch)):
            cur += 1
            if cur > longest:
                longest = cur
        else:
            cur = 0
    flags = []
    if peak_all <= sil_thr:
        flags.append("silent")
    if clipped:
        flags.append("clipping")
    if dead:
        flags.append("dead_windows")
    res.update(peak_all=peak_all, clipped=clipped, longest_silence_s=round(longest / rate, 3), windows=windows, flags=flags)
    return res


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    win, thr, files = 5.0, 8, []
    i = 0
    while i < len(argv):
        if argv[i] == "--win":
            win = float(argv[i + 1]); i += 2
        elif argv[i] == "--silence-thr":
            thr = int(argv[i + 1]); i += 2
        else:
            files.append(argv[i]); i += 1
    for f in files:
        print(json.dumps(analyse(f, win, thr)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
