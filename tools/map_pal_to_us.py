"""Map PAL (SCES-50878) function addresses to the US build (SLUS-20328) without the PAL ELF.

Both builds come from nearly the same source, so their function lists line up: the script aligns the PAL
function map (config/function_map.csv, from git) with a US Ghidra export by function size (difflib on the
size sequence), then keeps only matches inside runs of equal sizes, plus the SDK names of both analyzer seeds.
Usage:
  python -I tools/map_pal_to_us.py <pal_map.csv> <us_functions.csv> <pal_seed.toml> <us_seed.toml> <out.csv>
out.csv: pal,us,size,how   (how = sdk | run<N> = inside a run of N equal sizes)
"""
import csv
import difflib
import re
import sys


def load_map(path):
    rows = []
    with open(path, newline="") as f:
        for r in list(csv.reader(f))[1:]:
            start, end = int(r[1], 16), int(r[2], 16)
            rows.append((start, end - start, r[0]))
    rows.sort()
    out, last = [], None
    for start, size, name in rows:  # one row per start, labels dropped by the caller's CSV choice
        if start != last:
            out.append((start, size, name))
            last = start
    return out


def load_seed(path):
    d = {}
    for name, addr in re.findall(r'"([^"@]+)@0x([0-9A-Fa-f]+)"', open(path).read()):
        d.setdefault(name, []).append(int(addr, 16))
    return {n: a[0] for n, a in d.items() if len(a) == 1}


def main():
    pal_csv, us_csv, pal_seed, us_seed, out = sys.argv[1:6]
    pal, us = load_map(pal_csv), load_map(us_csv)
    sm = difflib.SequenceMatcher(None, [s for _, s, _ in pal], [s for _, s, _ in us], autojunk=False)
    result = {}
    for block in sm.get_matching_blocks():
        for k in range(block.size):
            p, u = pal[block.a + k], us[block.b + k]
            result[p[0]] = (u[0], p[1], f"run{block.size}")
    ps, us_ = load_seed(pal_seed), load_seed(us_seed)
    for name, a in ps.items():
        if name in us_:
            result[a] = (us_[name], 0, "sdk")
    with open(out, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["pal", "us", "size", "how"])
        for a in sorted(result):
            u, size, how = result[a]
            w.writerow([f"0x{a:08x}", f"0x{u:08x}", size, how])
    runs = [b.size for b in sm.get_matching_blocks() if b.size]
    print(f"PAL {len(pal)} functions, US {len(us)}; matched {sum(runs)} in {len(runs)} runs "
          f"(runs >= 3: {sum(r for r in runs if r >= 3)}); -> {out}")


if __name__ == "__main__":
    main()
