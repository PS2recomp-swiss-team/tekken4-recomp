"""Frame pacing of perf runs (docs/PERF.md "Smoothness"): the "[frames]" lines of the runtime (PS2X_PERF_STATS; one per
second: p = intervals between window presents, g = intervals between guest vblanks as the EE processes them, in 0.1 ms;
rep = guest frames shown twice, skip = guest frames never shown).

Usage: python -I tools/perf_smooth.py [--from S] [--to S] <run dir> [<run dir> ...]
Default window: the fight of tools/perf_fight.ps1 (window.txt: from start+3 to until-1); with --from/--to (seconds of the
stats clock) any part of a run (boot, menus). Without window.txt and --from/--to: the whole run.
Columns: presents per second, present interval p50/p95/p99/max, presents > 20 ms / > 33 ms, repeated and skipped guest
frames per minute, guest frame interval p50/p99/max, guest frames > 20 / > 25 / > 33 ms.
"""
import os
import re
import sys

FRAMES = re.compile(r"\[frames\] t=([\d.]+) rep=(\d+) skip=(\d+) p=([\d,]*) g=([\d,]*)")


def pct(values, q):
    if not values:
        return 0.0
    s = sorted(values)
    k = min(len(s) - 1, max(0, int(round(q / 100.0 * (len(s) - 1)))))
    return s[k]


def summarise(run, lo=None, hi=None):
    label = os.path.basename(os.path.normpath(run))
    wpath = os.path.join(run, "window.txt")
    if lo is None and hi is None and os.path.exists(wpath):
        w = open(wpath).read().split()
        lo, hi = float(w[1]) + 3, float(w[2]) - 1
    lo = -1e9 if lo is None else lo
    hi = 1e9 if hi is None else hi
    pres, game, rep, skip, secs = [], [], 0, 0, 0
    for line in open(os.path.join(run, "stdout.txt"), errors="replace"):
        m = FRAMES.search(line)
        if not m or not (lo <= float(m.group(1)) <= hi):
            continue
        secs += 1
        rep += int(m.group(2))
        skip += int(m.group(3))
        pres += [int(x) / 10.0 for x in m.group(4).split(",") if x]
        game += [int(x) / 10.0 for x in m.group(5).split(",") if x]
    if not secs:
        return None
    return {
        "run": label, "s": secs, "pps": len(pres) / secs,
        "p50": pct(pres, 50), "p95": pct(pres, 95), "p99": pct(pres, 99), "pmax": max(pres or [0]),
        "p20": sum(1 for x in pres if x > 20), "p33": sum(1 for x in pres if x > 33),
        "rep": rep * 60.0 / secs, "skip": skip * 60.0 / secs,
        "g50": pct(game, 50), "g99": pct(game, 99), "gmax": max(game or [0]),
        "g20": sum(1 for x in game if x > 20), "g25": sum(1 for x in game if x > 25), "g33": sum(1 for x in game if x > 33),
    }


def main():
    args = sys.argv[1:]
    lo = hi = None
    while args and args[0].startswith("--"):
        if args[0] == "--from":
            lo = float(args[1])
        elif args[0] == "--to":
            hi = float(args[1])
        args = args[2:]
    print("| run | s | presents/s | present p50 / p95 / p99 / max ms | >20 / >33 ms | repeated / skipped per min "
          "| guest frame p50 / p99 / max ms | guest >20 / >25 / >33 ms |")
    print("|---|---|---|---|---|---|---|---|")
    for run in args:
        r = summarise(run, lo, hi)
        if not r:
            print(f"| {os.path.basename(os.path.normpath(run))} | no [frames] lines | | | | | | |")
            continue
        print(f"| {r['run']} | {r['s']} | {r['pps']:.1f} | {r['p50']:.1f} / {r['p95']:.1f} / {r['p99']:.1f} / {r['pmax']:.1f} "
              f"| {r['p20']} / {r['p33']} | {r['rep']:.1f} / {r['skip']:.1f} | {r['g50']:.1f} / {r['g99']:.1f} / "
              f"{r['gmax']:.1f} | {r['g20']} / {r['g25']} / {r['g33']} |")


if __name__ == "__main__":
    main()
