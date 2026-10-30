"""Contact sheet of a netplay pair's frame shots (TEKKEN4_NET_SHOTS: net_shot_f<frame>.bmp, both peers at the same
logical frames): host row on top, joiner row below, one column per frame, quarter size. Also says which pairs of
shots are pixel-identical.

    python -I docs/rollback/net_contact.py logs/net/n150        -> logs/net/n150/contact.png
"""
import os
import re
import sys
import types

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# tools/contact_sheet.py's helpers (read_bmp, half, write_png); its last line runs main(), left out here
_src = open(os.path.join(ROOT, "tools", "contact_sheet.py"), encoding="utf-8").read()
cs = types.ModuleType("contact_sheet")
exec(compile(_src[:_src.rindex("main()")], "contact_sheet.py", "exec"), cs.__dict__)


def shots(folder):
    return {int(m.group(1)): os.path.join(folder, n) for n in os.listdir(folder)
            if (m := re.fullmatch(r"net_shot_f(\d+)\.bmp", n))}


def main():
    base = sys.argv[1]
    host, join = shots(os.path.join(base, "host")), shots(os.path.join(base, "join"))
    frames = sorted(set(host) & set(join))
    if not frames:
        sys.exit("no common net_shot_f*.bmp")
    tiles = []
    same = []
    for f in frames:
        a, b = cs.read_bmp(host[f]), cs.read_bmp(join[f])
        same.append(a[2] == b[2])
        tiles.append([cs.half(*cs.half(*a)), cs.half(*cs.half(*b))])
    tw, th = max(t[0][0] for t in tiles), max(t[0][1] for t in tiles)
    gap = 4
    W, H = len(frames) * tw + (len(frames) - 1) * gap, 2 * th + gap
    canvas = [bytearray(b"\x40" * (W * 3)) for _ in range(H)]
    for i, pair in enumerate(tiles):
        for r, (w, h, rows) in enumerate(pair):
            ox, oy = i * (tw + gap), r * (th + gap)
            for y in range(h):
                canvas[oy + y][ox * 3:(ox + w) * 3] = rows[y]
    out = os.path.join(base, "contact.png")
    cs.write_png(out, W, H, canvas)
    print(out)
    for f, s in zip(frames, same):
        print(f"  f={f}: host and join pictures {'identical' if s else 'differ'}")


if __name__ == "__main__":
    main()
