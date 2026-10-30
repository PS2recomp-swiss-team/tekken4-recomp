"""Game frames of input lag (docs/INPUT.md): compares the [vblank] lines of two deterministic runs
(TEKKEN4_VBLANK_HASH=1, TEKKEN4_RAND_SEED, scripted TEKKEN4_RB_INPUT) that differ only in a few presses.
For every press of run A that B does not have: the guest tick whose pad read first saw it, the first shown
picture that differs from B, and the difference in frames.
  python -I tools/chain_compare.py logs/input/chainA2/stderr.txt logs/input/chainB2/stderr.txt
Also summarises [present] lines (TEKKEN4_PRESENT_LOG=1) of any file given with --present."""
import re
import sys


def vblanks(path):
    rows = re.findall(r'\[vblank\] shown=(\d+) hash=([0-9a-f]+) pad=([0-9a-f]+)', open(path, errors='ignore').read())
    return {int(t): (h, int(p, 16)) for t, h, p in rows}


def quant(vals, q):
    s = sorted(vals)
    if not s:
        return float('nan')
    i = max(0, min(len(s) - 1, int(-(-q * len(s) // 1)) - 1))
    return s[i]


def present(path):
    rows = re.findall(r'\[present\] tick=(\d+) vb=(\d+) latch=(\d+) swap=(\d+)', open(path, errors='ignore').read())
    freq = 1e7
    m = re.search(r'qpc_freq=(\d+)', open(path, errors='ignore').read())
    if m:
        freq = float(m.group(1))
    lat, sw, gap = [], [], []
    prev = None
    for t, vb, la, swp in rows:
        t, vb, la, swp = int(t), int(vb), int(la), int(swp)
        if vb == 0 or swp < vb:
            continue
        sw.append((swp - vb) / freq * 1000)
        lat.append((la - vb) / freq * 1000)
        if prev is not None:
            gap.append(t - prev)
        prev = t
    n = len(sw)
    print(f'{path}: {n} presented guest frames')
    if n:
        print(f'  vblank -> latch  median {quant(lat, .5):.2f} ms  p95 {quant(lat, .95):.2f} ms')
        print(f'  vblank -> swap   median {quant(sw, .5):.2f} ms  p95 {quant(sw, .95):.2f} ms')
        skipped = sum(1 for g in gap if g > 1)
        print(f'  guest frames not presented (tick jumps >1): {skipped} of {len(gap)}')
        # guest speed over the last 20 s of the log (fight part of a fixed-fight run)
        pts = [(int(t), int(vb)) for t, vb, la, swp in rows if int(vb)]
        if len(pts) > 2:
            t_end, vb_end = pts[-1]
            first = next(((t, vb) for t, vb in pts if (vb_end - vb) / freq <= 20.0), pts[0])
            secs = (vb_end - first[1]) / freq
            if secs > 0:
                print(f'  guest fps over the last {secs:.1f} s: {(t_end - first[0]) / secs:.1f}')


def main(argv):
    if argv and argv[0] == '--present':
        for p in argv[1:]:
            present(p)
        return
    a, b = vblanks(argv[0]), vblanks(argv[1])
    common = sorted(set(a) & set(b))
    presses = [t for t in common if a[t][1] and a[t][1] != b[t][1] and not (a.get(t - 1, ('', 0))[1] & a[t][1])]
    for t in presses:
        diff = next((u for u in common if u >= t and a[u][0] != b[u][0]), None)
        before = next((u for u in common if u < t and a[u][0] != b[u][0]), None)
        if before is not None:
            print(f'press at tick {t}: pictures already differ at {before}, skipped')
            continue
        print(f'press {a[t][1]:04x} read at tick {t}: first different picture shown at tick {diff}'
              f' -> {diff - t if diff is not None else "?"} frames')


if __name__ == '__main__':
    main(sys.argv[1:])
