"""Compare the NETHASH lines (final state hash every N frames: RDRAM+scratchpad+VU0, IOP, EE cycle) of netplay peers
and, optionally, of a single-process reference run fed the same inputs on time (TEKKEN4_RB_MODE=measure,
TEKKEN4_RB_IOPSTATE=1, TEKKEN4_NET_HASH_EVERY=30).

    python -I docs/rollback/net_compare.py logs/net/n150/host/rb_frames.log logs/net/n150/join/rb_frames.log [--ref logs/rb/nref/rb_frames.log]

Each log's NETHASH lines are frames whose inputs were all confirmed when hashed (netplay) or simply every N-th frame
(reference). Prints frames compared and, per pair, the mismatching frames by component.
"""
import argparse
import re
import sys

LINE = re.compile(r"^NETHASH f=(\d+) h=([0-9a-f]+) ram=([0-9a-f]+) iop=([0-9a-f]+) cyc=(\d+)")


def load(path):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE.match(line)
            if m:
                out[int(m.group(1))] = (m.group(2), m.group(3), m.group(4), int(m.group(5)))
    return out


def compare(name_a, a, name_b, b, limit):
    common = sorted(set(a) & set(b))
    bad = [f for f in common if a[f] != b[f]]
    print(f"{name_a} vs {name_b}: {len(common)} frames compared ({common[0] if common else '-'}..{common[-1] if common else '-'}), "
          f"{len(bad)} differ")
    for f in bad[:limit]:
        parts = [k for k, i in (("ram", 1), ("iop", 2), ("cycle", 3)) if a[f][i] != b[f][i]]
        print(f"  f={f}: differs in {', '.join(parts)}  ({a[f][3]} vs {b[f][3]} cycles)")
    return len(common), len(bad)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("host")
    ap.add_argument("join")
    ap.add_argument("--ref")
    ap.add_argument("--limit", type=int, default=10)
    args = ap.parse_args()
    host, join = load(args.host), load(args.join)
    total_bad = 0
    _, bad = compare("host", host, "join", join, args.limit)
    total_bad += bad
    if args.ref:
        ref = load(args.ref)
        for name, data in (("host", host), ("join", join)):
            _, bad = compare(name, data, "ref", ref, args.limit)
            total_bad += bad
    return 1 if total_bad else 0


if __name__ == "__main__":
    sys.exit(main())
