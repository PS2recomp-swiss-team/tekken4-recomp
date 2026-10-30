"""Numbers for a picture, so an AI can judge a frame without seeing it. Stdlib only.
Reads frame_NNs.bmp (32-bit BI_RGB, runtime/tekken4_frameshot_overrides.cpp), 24-bit BMP, or PNG (8-bit RGB/RGBA/gray,
non-interlaced).

  python -I tools/frame_stats.py <img> [<img> ...]            size, mean/min/max per channel, % near-white/black, blank flag
  python -I tools/frame_stats.py --diff A B [--thr 16] [--out diff.png]
                                                                % pixels differing (any channel > thr), mean abs diff, PSNR
A frame is "blank" when >= 99% of pixels are near-black or >= 99% near-white or all channels have max-min < 4.
Output is one JSON object per line (machine first).
"""
import json
import struct
import sys
import zlib
from pathlib import Path


def load(path):
    """-> (width, height, bytes RGB top-down)"""
    data = Path(path).read_bytes()
    if data[:2] == b"BM":
        return _bmp(data)
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return _png(data)
    raise ValueError(f"{path}: not BMP or PNG")


def _bmp(data):
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    if bpp not in (24, 32):
        raise ValueError(f"{bpp}-bit BMP not supported")
    top_down = height < 0
    height = abs(height)
    bytespp = bpp // 8
    stride = (width * bytespp + 3) & ~3
    rgb = bytearray(width * height * 3)
    for y in range(height):
        src_y = y if top_down else height - 1 - y
        row = data[offset + src_y * stride: offset + src_y * stride + width * bytespp]
        o = y * width * 3
        rgb[o:o + width * 3:3] = row[2::bytespp]
        rgb[o + 1:o + width * 3:3] = row[1::bytespp]
        rgb[o + 2:o + width * 3:3] = row[0::bytespp]
    return width, height, bytes(rgb)


def _png(data):
    pos = 8
    idat = b""
    while pos < len(data):
        n, kind = struct.unpack_from(">I4s", data, pos)
        body = data[pos + 8: pos + 8 + n]
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    if depth != 8 or interlace or ctype not in (0, 2, 6):
        raise ValueError("PNG: only 8-bit gray/RGB/RGBA non-interlaced supported")
    ch = {0: 1, 2: 3, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = width * ch
    prev = bytearray(stride)
    out = bytearray()
    p = 0
    for _ in range(height):
        f = raw[p]
        cur = bytearray(raw[p + 1: p + 1 + stride])
        p += 1 + stride
        if f == 1:
            for i in range(ch, stride):
                cur[i] = (cur[i] + cur[i - ch]) & 255
        elif f == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = cur[i - ch] if i >= ch else 0
                cur[i] = (cur[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = cur[i - ch] if i >= ch else 0
                c = prev[i - ch] if i >= ch else 0
                b = prev[i]
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 255
        prev = cur
        if ch == 3:
            out += cur
        elif ch == 4:
            row = bytearray(width * 3)
            for k in range(3):
                row[k::3] = cur[k::4]
            out += row
        else:
            row = bytearray(width * 3)
            for k in range(3):
                row[k::3] = cur
            out += row
    return width, height, bytes(out)


def write_png(path, width, height, rgb):
    rows = b"".join(b"\x00" + rgb[y * width * 3:(y + 1) * width * 3] for y in range(height))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))


def stats(path):
    w, h, rgb = load(path)
    n = w * h
    out = {"file": str(path), "w": w, "h": h}
    white = black = 0
    for name, k in (("r", 0), ("g", 1), ("b", 2)):
        ch = rgb[k::3]
        out[name] = {"mean": round(sum(ch) / n, 2), "min": min(ch), "max": max(ch)}
    lum = [(rgb[i] + rgb[i + 1] + rgb[i + 2]) // 3 for i in range(0, len(rgb), 3)]
    white = sum(1 for v in lum if v >= 240)
    black = sum(1 for v in lum if v <= 15)
    out["pct_near_white"] = round(100.0 * white / n, 2)
    out["pct_near_black"] = round(100.0 * black / n, 2)
    flat = all(out[c]["max"] - out[c]["min"] < 4 for c in "rgb")
    out["blank"] = bool(flat or out["pct_near_white"] >= 99 or out["pct_near_black"] >= 99)
    return out


def diff(a, b, thr, out_png):
    wa, ha, ra = load(a)
    wb, hb, rb = load(b)
    if (wa, ha) != (wb, hb):
        return {"a": str(a), "b": str(b), "error": f"size differs {wa}x{ha} vs {wb}x{hb}"}
    n = wa * ha
    tot = 0
    sq = 0
    bad = 0
    mask = bytearray(len(ra))
    for i in range(0, len(ra), 3):
        d0, d1, d2 = abs(ra[i] - rb[i]), abs(ra[i + 1] - rb[i + 1]), abs(ra[i + 2] - rb[i + 2])
        tot += d0 + d1 + d2
        sq += d0 * d0 + d1 * d1 + d2 * d2
        if max(d0, d1, d2) > thr:
            bad += 1
            mask[i] = 255
            mask[i + 1] = mask[i + 2] = 0
        else:
            g = (ra[i] + ra[i + 1] + ra[i + 2]) // 6  # dim copy of A where equal
            mask[i] = mask[i + 1] = mask[i + 2] = g
    mse = sq / (n * 3)
    import math
    psnr = None if mse == 0 else round(10 * math.log10(255 * 255 / mse), 2)
    res = {"a": str(a), "b": str(b), "w": wa, "h": ha, "thr": thr, "pct_diff": round(100.0 * bad / n, 3),
           "mean_abs_diff": round(tot / (n * 3), 3), "psnr_db": psnr, "identical": tot == 0}
    if out_png:
        write_png(out_png, wa, ha, bytes(mask))
        res["diff_png"] = str(out_png)
    return res


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[0] == "--diff":
        rest = argv[1:]
        thr, out = 16, None
        files = []
        i = 0
        while i < len(rest):
            if rest[i] == "--thr":
                thr = int(rest[i + 1]); i += 2
            elif rest[i] == "--out":
                out = rest[i + 1]; i += 2
            else:
                files.append(rest[i]); i += 1
        if len(files) != 2:
            print("usage: --diff A B [--thr N] [--out diff.png]")
            return 1
        if out is None:
            out = str(Path(files[1]).with_name(Path(files[1]).stem + "_diff.png"))
        print(json.dumps(diff(files[0], files[1], thr, out)))
        return 0
    for f in argv:
        print(json.dumps(stats(f)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
