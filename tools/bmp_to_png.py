"""Convert the runtime's frame shots (frame_NNs.bmp, 32-bit BI_RGB, see runtime/tekken4_frameshot_overrides.cpp)
to PNG next to them, stdlib only (image viewers and Claude's Read tool take PNG).

Usage: python -I tools/bmp_to_png.py <file.bmp | run dir> [...]
"""
import struct
import sys
import zlib
from pathlib import Path


def bmp_to_png(src: Path) -> Path:
    data = src.read_bytes()
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    if bpp != 32:
        raise ValueError(f"{src}: {bpp}-bit BMP not supported")
    top_down = height < 0
    height = abs(height)
    rows = []
    for y in range(height):
        row_index = y if top_down else height - 1 - y
        row = data[offset + row_index * width * 4: offset + (row_index + 1) * width * 4]
        rgb = bytearray(width * 3)
        rgb[0::3] = row[2::4]
        rgb[1::3] = row[1::4]
        rgb[2::3] = row[0::4]
        rows.append(b"\x00" + bytes(rgb))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 6)) + chunk(b"IEND", b"")
    out = src.with_suffix(".png")
    out.write_bytes(png)
    return out


def main(args):
    for arg in args:
        path = Path(arg)
        for bmp in (sorted(path.glob("frame_*.bmp")) if path.is_dir() else [path]):
            print(bmp_to_png(bmp))


if __name__ == "__main__":
    main(sys.argv[1:])
