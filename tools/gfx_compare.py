"""Before/after crops for docs/GRAPHICS.md: the same region of two frame shots side by side, nearest-zoomed.

Usage: python tools/gfx_compare.py <before.png> <after.png> <out.png> <x> <y> <w> <h> [zoom] [label_before] [label_after]
The region is given in PS2 pixels (640x448 picture); each frame's own scale (height / 448) maps it to its pixels, so a
5x frame and a native frame can be compared. Needs Pillow (the system Python).
"""
import sys

from PIL import Image, ImageDraw


def region(path, x, y, w, h, out_w):
    img = Image.open(path).convert("RGB")
    s = img.height / 448.0
    crop = img.crop((round(x * s), round(y * s), round((x + w) * s), round((y + h) * s)))
    return crop.resize((out_w, round(out_w * crop.height / crop.width)), Image.NEAREST)


def main() -> int:
    before, after, out = sys.argv[1:4]
    x, y, w, h = (int(v) for v in sys.argv[4:8])
    zoom = float(sys.argv[8]) if len(sys.argv) > 8 else 4.0
    labels = (sys.argv[9] if len(sys.argv) > 9 else "before", sys.argv[10] if len(sys.argv) > 10 else "after")
    out_w = round(w * zoom)
    a, b = region(before, x, y, w, h, out_w), region(after, x, y, w, h, out_w)
    sheet = Image.new("RGB", (out_w * 2 + 8, max(a.height, b.height) + 24), (0, 0, 0))
    sheet.paste(a, (0, 24))
    sheet.paste(b, (out_w + 8, 24))
    d = ImageDraw.Draw(sheet)
    d.text((4, 4), labels[0], fill=(255, 255, 0))
    d.text((out_w + 12, 4), labels[1], fill=(255, 255, 0))
    sheet.save(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
