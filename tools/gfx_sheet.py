"""Sheet + numbers for one internal resolution step (tools/gfx_sweep.ps1, docs/GRAPHICS.md).

Usage: python tools/gfx_sheet.py <step> <fight run dir> <movie run dir> <out.png>
Needs Pillow + numpy (the system Python; the project's pytools venv has neither).
Prints: picture size, fight fps (TEKKEN4_PERF_LOG seconds 36..60 of the run: mean / min), and the upscale seam check
(mean |gradient| on the 64-column / 32-row PSMCT32 page grid vs. elsewhere; equal = no grid lines).
Sheet: movie, menu, character select, fight, each area-scaled to 640 px wide, plus a 1:1 crop of the fight's HUD.
"""
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def load(run: Path, second: int):
    for name in (f"frame_{second}s.png", f"frame_{second}s.bmp"):
        p = run / name
        if p.exists():
            return Image.open(p).convert("RGB")
    return None


def seams(img: Image.Image, scale: float):
    a = np.asarray(img, dtype=np.int32).sum(axis=2)
    h, w = a.shape
    gx = np.abs(np.diff(a, axis=1)).mean(axis=0)
    gy = np.abs(np.diff(a, axis=0)).mean(axis=1)
    out = []
    for g, n, per in ((gx, w, 64), (gy, h, 32)):
        grid = [int(round(k * per * scale)) + d for k in range(1, int(n / scale / per) + 1) for d in (-2, -1, 0)]
        grid = [i for i in grid if 0 <= i < len(g)]
        mask = np.ones(len(g), bool)
        mask[grid] = False
        out.append((float(g[grid].mean()) if grid else 0.0, float(g[mask].mean())))
    return out


def fps(run: Path):
    text = (run / "stdout.txt").read_text(encoding="utf-8", errors="replace")
    values = [int(f) for s, f in re.findall(r"perf second (\d+): (\d+) frames", text) if 36 <= int(s) <= 60]
    return (sum(values) / len(values), min(values)) if values else (0.0, 0)


def main() -> int:
    step, fight, movie, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4])
    shots = [("movie", load(movie, 14) or load(movie, 10)), ("menu", load(fight, 12)),
             ("character select", load(fight, 20) or load(fight, 24)), ("fight", load(fight, 56) or load(fight, 40))]
    tiles = []
    for label, img in shots:
        tile = Image.new("RGB", (640, 448))
        if img is not None:
            tile = img.resize((640, round(640 * img.height / img.width)), Image.BOX)
        tiles.append(tile)
    f = shots[3][1]
    size = f"{f.width}x{f.height}" if f is not None else "?"
    crop = f.crop((0, 0, min(f.width, 1280), min(f.height, round(f.height * 0.2)))) if f is not None else Image.new("RGB", (640, 90))
    sheet = Image.new("RGB", (1280, 896 + crop.height), (0, 0, 0))
    for i, t in enumerate(tiles):
        sheet.paste(t.crop((0, 0, 640, 448)), ((i % 2) * 640, (i // 2) * 448))
    sheet.paste(crop, (0, 896))
    sheet.save(out)
    mean, low = fps(fight)
    line = f"{step}: picture {size}, fight {mean:.1f} fps (min {low})"
    if f is not None:
        scale = f.height / 448.0
        (cg, ce), (rg, re_) = seams(f, scale)
        line += f", seams cols grid {cg:.1f} vs {ce:.1f}, rows grid {rg:.1f} vs {re_:.1f}"
    print(line)
    with open(out.with_suffix(".txt"), "w", encoding="utf-8") as t:
        t.write(line + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
