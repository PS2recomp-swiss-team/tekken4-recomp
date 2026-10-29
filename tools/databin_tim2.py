#!/usr/bin/env python3
"""Write PNG previews of TIM2 pictures stored in Tekken 4 DATA.BIN files.

Reads the manifest from `python -I tools/databin.py verify <disc>` (which
file holds a TIM2 header, after decrypt). Extracts the smallest such files
until --count pictures are converted, then builds a contact sheet.

Conversion is the vendored tool:

  python -I tools/console-skill/console-graphics/tim2.py scan <file> --extract <dir>
  python -I tools/console-skill/console-graphics/tim2.py topng <dir> --out <dir>

That tool is MIT, standard library only. This script does not run any
console-skill command that deletes or replaces an existing tree
(memcard restore/sync, targets.py package, the console-skill tests).

Output (default): logs/databin/<disc>/tim2/  (gitignored). Never game/ or an ISO.

Examples:
  python -I tools/databin.py verify pal
  python -I tools/databin_tim2.py pal
  python -I tools/databin_tim2.py pal --count 24
  python -I tools/databin_tim2.py us --index 2 --count 8
"""

import argparse
import os
import struct
import subprocess
import sys

# python -I does not put the script directory on sys.path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import databin

TIM2 = os.path.join(os.path.dirname(os.path.abspath(__file__)), "console-skill", "console-graphics", "tim2.py")


class UsageError(Exception):
    pass


def run_tim2(args):
    cmd = [sys.executable, "-I", TIM2] + args
    print(" ".join(cmd), file=sys.stderr)
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out = proc.stdout.decode("utf-8", "replace")
    err = proc.stderr.decode("utf-8", "replace")
    if out:
        sys.stdout.write(out)
    if err:
        sys.stderr.write(err)
    if proc.returncode not in (0, 1):
        raise UsageError("tim2.py exited %d" % proc.returncode)
    return out


def png_size(path):
    data = open(path, "rb").read(24)
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise UsageError("%s is not a PNG" % path)
    w, h = struct.unpack(">II", data[16:24])
    return w, h, os.path.getsize(path)


def load_tim2_mod():
    path = os.path.dirname(TIM2)
    if path not in sys.path:
        sys.path.insert(0, path)
    import tim2 as mod
    return mod


def thumb(w, h, rgba, side):
    tw = max(1, min(side, int(round(side * w / max(w, h)))))
    th = max(1, min(side, int(round(side * h / max(w, h)))))
    out = []
    for y in range(th):
        sy = min(h - 1, y * h // th)
        row = sy * w
        for x in range(tw):
            sx = min(w - 1, x * w // tw)
            out.append(rgba[row + sx])
    return tw, th, out


def contact_sheet(pngs, dest, cols, side):
    """Assemble already-written PNGs. Uses tim2.decode_png / encode_png."""
    mod = load_tim2_mod()
    tiles = []
    for path in pngs:
        blob = open(path, "rb").read()
        w, h, rgba, _idx, _pal = mod.decode_png(blob, os.path.basename(path))
        tw, th, px = thumb(w, h, rgba, side)
        # mean of the full image (the check that the PNG is not an empty decode)
        n = max(1, w * h)
        acc = [0, 0, 0]
        for c in rgba:
            acc[0] += c[0]
            acc[1] += c[1]
            acc[2] += c[2]
        mean = (acc[0] // n, acc[1] // n, acc[2] // n)
        tiles.append((tw, th, px, mean, path))
    gap = 4
    rows = (len(tiles) + cols - 1) // cols
    W = cols * side + (cols - 1) * gap
    H = rows * side + (rows - 1) * gap
    canvas = [(40, 40, 40, 255)] * (W * H)
    for i, (tw, th, px, _mean, _path) in enumerate(tiles):
        ox = (i % cols) * (side + gap) + (side - tw) // 2
        oy = (i // cols) * (side + gap) + (side - th) // 2
        for y in range(th):
            dst = (oy + y) * W + ox
            src = y * tw
            canvas[dst:dst + tw] = px[src:src + tw]
    if os.path.exists(dest):
        raise UsageError("refusing to overwrite %s" % dest)
    blob = mod.encode_png(W, H, canvas)
    with open(dest, "xb") as f:
        f.write(blob)
    return tiles


def candidate_indices(doc, forced):
    if forced:
        return forced
    rows = [r for r in doc["files"] if r.get("tim2")]
    rows.sort(key=lambda r: (r["size"], r["index"]))
    return [r["index"] for r in rows]


def main(argv=None):
    p = argparse.ArgumentParser(prog="databin_tim2.py", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("disc", choices=("pal", "us"))
    p.add_argument("--count", type=int, default=24, help="stop after this many PNGs (default 24)")
    p.add_argument("--index", type=int, action="append", default=[],
                   help="force these DATA.BIN indices (default: manifest files that contain TIM2)")
    p.add_argument("--out", help="output directory (default logs/databin/<disc>/tim2)")
    args = p.parse_args(argv)
    if args.count < 1:
        print("databin_tim2.py: --count must be >= 1", file=sys.stderr)
        return 2
    if not os.path.isfile(TIM2):
        print("databin_tim2.py: missing %s" % TIM2, file=sys.stderr)
        return 2
    doc, path = databin.load_manifest(args.disc)
    if doc is None:
        print("databin_tim2.py: no manifest at %s; run: python -I tools/databin.py verify %s" % (path, args.disc),
              file=sys.stderr)
        return 2
    indices = candidate_indices(doc, args.index)
    if not indices:
        print("databin_tim2.py: manifest has no TIM2 headers", file=sys.stderr)
        return 1
    out = args.out or os.path.join(databin.default_out(args.disc), "tim2")
    files_dir = os.path.join(databin.default_out(args.disc), "files")
    tm2_dir = os.path.join(out, "tm2")
    png_dir = os.path.join(out, "png")
    os.makedirs(tm2_dir, exist_ok=True)
    os.makedirs(png_dir, exist_ok=True)
    pngs = []
    used = []
    try:
        for index in indices:
            if len(pngs) >= args.count:
                break
            dest = os.path.join(files_dir, "%05d.bin" % index)
            if not os.path.isfile(dest):
                databin.extract_rows(args.disc, [index], files_dir)
            if not os.path.isfile(dest):
                raise UsageError("extract did not write %s" % dest)
            before = set(os.listdir(tm2_dir))
            need = args.count - len(pngs)
            run_tim2(["scan", dest, "--extract", tm2_dir, "--limit", str(need)])
            fresh = sorted(set(os.listdir(tm2_dir)) - before)
            tm2s = [os.path.join(tm2_dir, n) for n in fresh if n.lower().endswith(".tm2")]
            if not tm2s:
                print("index %d: scan found no TIM2" % index)
                continue
            for tm2 in tm2s:
                run_tim2(["topng", tm2, "--out", png_dir, "--rgba"])
            # topng rewrites every .tm2 already in the folder. New png names
            # follow the tm2 stem. Collect pngs that correspond to this batch
            # first, then any png not yet listed.
            for tm2 in tm2s:
                stem = os.path.splitext(os.path.basename(tm2))[0]
                for dirpath, _dirs, names in os.walk(png_dir):
                    for name in sorted(names):
                        if not name.lower().endswith(".png"):
                            continue
                        if os.path.splitext(name)[0] == stem or os.path.splitext(name)[0].startswith(stem + "_"):
                            full = os.path.join(dirpath, name)
                            if full not in pngs:
                                pngs.append(full)
            used.append(index)
            print("index %d -> %d png(s) so far" % (index, len(pngs)))
    except (UsageError, databin.UsageError) as exc:
        print("databin_tim2.py: %s" % exc, file=sys.stderr)
        return 2
    pngs = pngs[:args.count]
    if len(pngs) < min(20, args.count):
        print("only %d PNG(s); wanted %d" % (len(pngs), args.count))
        return 1
    lines = []
    for path_png in pngs:
        w, h, n = png_size(path_png)
        lines.append("%s %d %d %d" % (path_png, n, w, h))
        print("png %s bytes=%d %dx%d" % (path_png, n, w, h))
    sheet = os.path.join(out, "contact.png")
    tiles = contact_sheet(pngs, sheet, cols=5, side=128)
    print("contact %s" % sheet)
    means = []
    for _tw, _th, _px, mean, path_png in tiles:
        means.append("%s mean=%d,%d,%d" % (os.path.basename(path_png), mean[0], mean[1], mean[2]))
        print("mean %s" % means[-1])
    report = os.path.join(out, "report.txt")
    body = "disc %s indices %s pngs %d\n%s\ncontact %s\n%s\n" % (
        args.disc, used, len(pngs), "\n".join(lines), sheet, "\n".join(means))
    with open(report, "xb") as f:
        f.write(body.encode("utf-8"))
    print("report %s" % report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
