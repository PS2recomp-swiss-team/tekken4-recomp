"""Compare two rb_frames.log files (TEKKEN4_RB_MODE=measure/test) frame by frame.

usage: python -I rb_compare.py <runA/rb_frames.log> <runB/rb_frames.log> [--from F] [--to F] [--show N] [--last]
Only first-pass/normal lines are compared (p=- or p=1); resim lines (p=R) are ignored.
--last: the LAST line of each frame counts, whatever its pass (selfnet: a frame's final, corrected run).
Prints the first frames where the full hash differs, with the differing parts (ram / oth / sch) and the
differing 1-MB RDRAM regions, then a count of differing frames.
"""
import sys


def load(path, last=False):
    frames = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if not line.startswith("f="):
                continue
            v = dict(kv.split("=", 1) for kv in line.split() if "=" in kv)
            if v.get("p") in ("R", "W") and not last:
                continue
            frames[int(v["f"])] = v
    return frames


def main():
    args = sys.argv[1:]
    opts = {"--from": 0, "--to": 1 << 60, "--show": 12}
    files = []
    last = False
    i = 0
    while i < len(args):
        if args[i] == "--last":
            last = True
            i += 1
        elif args[i] in opts:
            opts[args[i]] = int(args[i + 1])
            i += 2
        else:
            files.append(args[i])
            i += 1
    a, b = load(files[0], last), load(files[1], last)
    common = sorted(f for f in a if f in b and opts["--from"] <= f <= opts["--to"])
    print(f"frames: A {len(a)}  B {len(b)}  common {len(common)}")
    diff = 0
    shown = 0
    first = None
    for f in common:
        x, y = a[f], b[f]
        if x["h"] == y["h"]:
            continue
        diff += 1
        if first is None:
            first = f
        if shown < opts["--show"]:
            shown += 1
            parts = [k for k in ("ram", "oth", "sch") if x[k] != y[k]]
            ra, rb = x["reg"], y["reg"]
            regions = [str(r) for r in range(32) if ra[r * 4:r * 4 + 4] != rb[r * 4:r * 4 + 4]]
            extra = []
            for k in ("tick", "cyc", "in", "loop", "run"):
                if x.get(k) != y.get(k):
                    extra.append(f"{k} {x.get(k)}/{y.get(k)}")
            print(f"f={f} differs: {','.join(parts)}  MB regions [{' '.join(regions)}]  {'  '.join(extra)}")
    print(f"differing frames: {diff} of {len(common)}; first {first}")


if __name__ == "__main__":
    main()
