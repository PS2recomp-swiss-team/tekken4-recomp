"""Contact sheet of a run's frame shots (frame_NNs.bmp), half size, in time order, without Pillow.

Usage: python -I tools/contact_sheet.py <run dir> [columns]   -> <run dir>/contact.png
"""
import os
import re
import struct
import sys
import zlib


def read_bmp(path):
    data = open(path, "rb").read()
    offset = struct.unpack_from("<I", data, 10)[0]
    w, h = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    step = bpp // 8
    stride = (w * step + 3) & ~3
    rows = []
    for y in range(abs(h)):
        sy = abs(h) - 1 - y if h > 0 else y
        base = offset + sy * stride
        row = bytearray(w * 3)
        for x in range(w):
            b, g, r = data[base + x * step:base + x * step + 3]
            row[x * 3:x * 3 + 3] = bytes((r, g, b))
        rows.append(row)
    return w, abs(h), rows


def half(w, h, rows):
    out = []
    for y in range(0, h - 1, 2):
        a, b = rows[y], rows[y + 1]
        row = bytearray((w // 2) * 3)
        for x in range(w // 2):
            for c in range(3):
                i = x * 6 + c
                row[x * 3 + c] = (a[i] + a[i + 3] + b[i] + b[i + 3]) // 4
        out.append(row)
    return w // 2, len(out), out


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    open(path, "wb").write(png + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def main():
    folder = sys.argv[1]
    cols = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    shots = sorted((float(m.group(1)), n) for n in os.listdir(folder)
                   if (m := re.fullmatch(r"frame_(\d+(?:\.\d+)?)s\.bmp", n)))
    tiles = [half(*read_bmp(os.path.join(folder, n))) for _, n in shots]
    if not tiles:
        sys.exit("no frame_NNs.bmp in " + folder)
    tw, th = max(t[0] for t in tiles), max(t[1] for t in tiles)
    gap = 4
    rows_n = (len(tiles) + cols - 1) // cols
    W, H = cols * tw + (cols - 1) * gap, rows_n * th + (rows_n - 1) * gap
    canvas = [bytearray(b"\x40" * (W * 3)) for _ in range(H)]
    for i, (w, h, rows) in enumerate(tiles):
        ox, oy = (i % cols) * (tw + gap), (i // cols) * (th + gap)
        for y in range(h):
            canvas[oy + y][ox * 3:(ox + w) * 3] = rows[y]
    out = os.path.join(folder, "contact.png")
    write_png(out, W, H, canvas)
    print(out, "=", ", ".join("%gs" % t for t, _ in shots))


main()
