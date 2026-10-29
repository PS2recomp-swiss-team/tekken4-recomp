"""Which stage card does the Practice stage select show? (tools/run_fixed_fight.ps1 checks its run with it.)

  python -I tools/stage_card.py <frame_NNs.bmp> [target] -> "<index> <name> <distance> [<Right presses to target>]"
                                                             of the closest reference card
  python -I tools/stage_card.py --json <frame_NNs.bmp>    -> {"index","name","dist","second","gap"} (gap = 2nd dist - best)
  python -I tools/stage_card.py --make-refs <run dir>     -> crops the 10 reference cards from a probe run into
                                                             logs/stage_refs/ (game imagery: stays under logs/, never in git)

The stage select opens on a RANDOM slot showing a random card (confirming it picks that stage; not the rand seed).
From that slot Right goes airport .. arena, then back to the slot; Left goes the other way. Card order with Right:
"""
import os
import struct
import sys

STAGES = ["arena", "airport", "building", "mall_a", "mall_b", "shinjuku", "beach", "laboratory", "parking", "underground"]
__doc__ += "  " + " -> ".join(STAGES) + " -> arena\n"
# Probe run logs/fixed_probe1 (Right at 55, 56, ... 64): the frame second showing each settled card.
PROBE_SECONDS = {"arena": 52, "airport": 54, "building": 55, "mall_a": 56, "mall_b": 57, "shinjuku": 58, "beach": 59,
                 "laboratory": 60, "parking": 61, "underground": 62}
BOX = (20, 290, 200, 410)  # x0, y0, x1, y1 of the card in the 640x448 frame
REF_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "logs", "stage_refs")


def read_bmp(path):
    """32-bit top-down BMP (tools/run_capture frame shots) -> (w, h, bytes BGRA)."""
    data = open(path, "rb").read()
    off, = struct.unpack_from("<I", data, 10)
    w, h = struct.unpack_from("<ii", data, 18)
    bpp, = struct.unpack_from("<H", data, 28)
    if bpp != 32:
        sys.exit(f"{path}: {bpp} bpp, expected 32")
    return w, abs(h), data[off:], h < 0


def crop(path):
    w, h, px, top_down = read_bmp(path)
    x0, y0, x1, y1 = BOX
    out = bytearray()
    for y in range(y0, y1):
        row = y if top_down else h - 1 - y
        base = (row * w + x0) * 4
        line = px[base:base + (x1 - x0) * 4]
        out += bytes(b for i, b in enumerate(line) if i % 4 != 3)  # drop alpha
    return out


def rank(path):
    """[(dist, index, name), ...] closest first. A settled card is dist<=22 and gap>=30 (see logs/grok/stage-pick-notes.md)."""
    probe = crop(path)
    rows = []
    for name in STAGES:
        ref_path = os.path.join(REF_DIR, f"{STAGES.index(name):02d}_{name}.raw")
        ref = open(ref_path, "rb").read()
        if len(ref) != len(probe) or not ref:
            sys.exit(f"{ref_path}: {len(ref)} bytes, crop {len(probe)}")
        dist = sum(abs(a - b) for a, b in zip(probe, ref)) / len(ref)
        rows.append((dist, STAGES.index(name), name))
    rows.sort()
    return rows


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--make-refs":
        os.makedirs(REF_DIR, exist_ok=True)
        for name, sec in PROBE_SECONDS.items():
            with open(os.path.join(REF_DIR, f"{STAGES.index(name):02d}_{name}.raw"), "wb") as f:
                f.write(crop(os.path.join(sys.argv[2], f"frame_{sec}s.bmp")))
        print(f"{len(PROBE_SECONDS)} reference cards in {REF_DIR}")
        return
    if len(sys.argv) == 3 and sys.argv[1] == "--json":
        rows = rank(sys.argv[2])
        best, second = rows[0], rows[1]
        print('{"index": %d, "name": "%s", "dist": %.2f, "second": "%s", "gap": %.2f}'
              % (best[1], best[2], best[0], second[2], second[0] - best[0]))
        return
    if len(sys.argv) not in (2, 3) or (len(sys.argv) == 3 and sys.argv[2] not in STAGES):
        sys.exit(__doc__)
    best = rank(sys.argv[1])[0]
    presses = f" {(STAGES.index(sys.argv[2]) - best[1]) % len(STAGES)}" if len(sys.argv) == 3 else ""
    print(f"{best[1]} {best[2]} {best[0]:.1f}{presses}")


if __name__ == "__main__":
    main()
