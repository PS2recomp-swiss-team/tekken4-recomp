"""Summarises perf runs (tools/perf_fight.ps1): the fight window's [perf] lines (runtime, PS2X_PERF_STATS) and
"perf second" lines (game frames, TEKKEN4_PERF_LOG).

Usage: python -I tools/perf_table.py <run dir> [<run dir> ...]
One row per run: game fps (mean, min, seconds below 59), presented fps, EE busy ms per frame, GIF ms per frame (GS
packet work on the EE thread incl. its waits), GS queue back-pressure and drain waits per frame, GS worker busy per
frame, GL batches / draws per frame, texture decodes per second.
"""
import os
import re
import statistics
import sys

PERF = re.compile(r"\[perf\] t=([\d.]+) (.*)")
GAME = re.compile(r"perf second (\d+): (\d+) frames, GS (\d+) ms")


def fields(text):
    out = {}
    for item in text.split():
        key, _, value = item.partition("=")
        if "/" in value:
            a, b = value.split("/")
            out[key] = float(a)
            out[key + "_n"] = float(b)
        else:
            out[key] = float(value)
    return out


def summarise(run):
    window = open(os.path.join(run, "window.txt")).read().split()
    start, until = float(window[1]), float(window[2])
    stage = window[3] if len(window) > 3 else os.path.basename(run)
    lo, hi = start + 3, until - 1
    perf, game = [], []
    for line in open(os.path.join(run, "stdout.txt"), errors="replace"):
        m = PERF.search(line)
        if m and "drains_by" not in line and lo <= float(m.group(1)) <= hi:
            perf.append(fields(m.group(2)))
        m = GAME.search(line)
        if m and lo <= int(m.group(1)) + 1 <= hi:
            game.append(int(m.group(2)))
    if not perf:
        return None
    # contention.txt (perf_fight.ps1): compilers / other game instances seen during the fight window
    busy = 0
    cpath = os.path.join(run, "contention.txt")
    if os.path.exists(cpath):
        for line in open(cpath):
            parts = line.split()
            if len(parts) == 3 and lo - 2 <= float(re.sub(r"[^0-9]", "", parts[0]) or 0) <= hi + 2:
                busy = max(busy, int(parts[1]) + int(parts[2]))
    def per_frame(key):
        total = sum(p.get(key, 0.0) for p in perf)
        frames = sum(game) if game else sum(p["vsyncs"] for p in perf)
        return total / max(frames, 1)
    fps = game if game else [p["vsyncs"] for p in perf]
    return {
        "stage": stage, "run": os.path.basename(os.path.normpath(run)), "n": len(fps),
        "fps": statistics.mean(fps), "min": min(fps), "below59": sum(1 for f in fps if f < 59),
        "vsyncs": statistics.mean(p["vsyncs"] for p in perf),
        "ee": per_frame("ee_busy"), "gif": per_frame("gif"), "pub": per_frame("gs_pubwait"),
        "drain": per_frame("gs_drain"), "drains": per_frame("gs_drain_n"), "worker": per_frame("gs_worker"),
        "batches": per_frame("batches"), "draws": per_frame("draws"),
        "texdec": statistics.mean(p.get("texdec", 0) + p.get("rowdec", 0) for p in perf),
        "vu1": per_frame("vu1"), "vif1": per_frame("vif1"), "busy": busy,
    }


def main():
    rows = [r for r in (summarise(d) for d in sys.argv[1:]) if r]
    print("| stage | run | s | fps mean | min | s<59 | EE busy ms/f | GIF ms/f | GS backpressure ms/f | GS drain ms/f (n/f) "
          "| GS worker ms/f | VU1 ms/f | batches/f | draws/f | tex decodes/s | contention |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        print(f"| {r['stage']} | {r['run']} | {r['n']} | {r['fps']:.1f} | {r['min']} | {r['below59']} | {r['ee']:.2f} | "
              f"{r['gif']:.2f} | {r['pub']:.2f} | {r['drain']:.2f} ({r['drains']:.1f}) | {r['worker']:.2f} | "
              f"{r['vu1']:.2f} | {r['batches']:.0f} | {r['draws']:.0f} | {r['texdec']:.0f} | {'BUSY ' + str(r['busy']) if r['busy'] else '-'} |")


if __name__ == "__main__":
    main()
