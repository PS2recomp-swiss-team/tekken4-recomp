"""List the sprites in a GIF packet log written by the Tekken 4 override (TEKKEN4_GS_DUMP -> gif_packets_frame<N>.txt).

Replays the GS registers a sprite depends on (PRIM, RGBAQ, UV, XYZ2, TEX0, CLAMP, TEX1, XYOFFSET, FRAME) through
PACKED, REGLIST and A+D data, and prints one line per sprite: screen rectangle (XYOFFSET removed), UVs, texture
and its CLAMP / filtering. Packets are logged as quadwords "hi lo", the GIF tag first (whole packets since
2026-10-21; older logs kept only the first 0x800 bytes of each packet, so long packets lose their tail).

Usage: python -I tools/gif_sprites.py logs/<run>/gif_packets_frame<N>.txt [--min-y Y --max-y Y]
"""
import argparse
import re


def packets(path):
    cur = None
    for line in open(path, encoding="utf-8"):
        if line.startswith("packet"):
            if cur:
                yield cur
            cur = []
        else:
            m = re.match(r"\s*[0-9a-f]+: ([0-9a-f]{16}) ([0-9a-f]{16})", line)
            if m and cur is not None:
                cur.append((int(m.group(2), 16), int(m.group(1), 16)))  # (lo, hi)
    if cur:
        yield cur


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--min-y", type=float, default=-1e9)
    ap.add_argument("--max-y", type=float, default=1e9)
    args = ap.parse_args()
    regs = {0x00: 0, 0x01: 0, 0x03: 0, 0x06: 0, 0x07: 0, 0x08: 0, 0x09: 0, 0x14: 0, 0x15: 0, 0x18: 0, 0x19: 0,
            0x4C: 0, 0x4D: 0}
    verts = []
    count = 0

    def write(addr, value):
        nonlocal verts, count
        if addr == 0x00:
            regs[0x00] = value
            verts = []
        elif addr in (0x04, 0x05, 0x0C, 0x0D):
            verts.append((value & 0xFFFF, (value >> 16) & 0xFFFF, regs[0x03]))
            prim = regs[0x00]
            if (prim & 7) == 6 and len(verts) == 2:
                ctx = (prim >> 9) & 1
                ofs = regs[0x18 + ctx]
                ox, oy = (ofs & 0xFFFF) / 16.0, ((ofs >> 32) & 0xFFFF) / 16.0
                (x0, y0, uv0), (x1, y1, uv1) = verts
                fx0, fy0, fx1, fy1 = x0 / 16.0 - ox, y0 / 16.0 - oy, x1 / 16.0 - ox, y1 / 16.0 - oy
                if args.min_y <= min(fy0, fy1) <= args.max_y or args.min_y <= max(fy0, fy1) <= args.max_y:
                    tex0, clamp, tex1 = regs[0x06 + ctx], regs[0x08 + ctx], regs[0x14 + ctx]
                    frame = regs[0x4C + ctx]
                    u0, v0 = (uv0 & 0x3FFF) / 16.0, ((uv0 >> 16) & 0x3FFF) / 16.0
                    u1, v1 = (uv1 & 0x3FFF) / 16.0, ((uv1 >> 16) & 0x3FFF) / 16.0
                    tw, th = 1 << ((tex0 >> 26) & 0xF), 1 << ((tex0 >> 30) & 0xF)
                    print(f"sprite ctx{ctx} fb {frame & 0x1FF:#x} x {fx0:g}..{fx1:g} y {fy0:g}..{fy1:g} "
                          f"uv {u0:g},{v0:g}..{u1:g},{v1:g} tme {(prim >> 4) & 1} abe {(prim >> 6) & 1} "
                          f"tex {tex0 & 0x3FFF:#x} psm {(tex0 >> 20) & 0x3F:#x} {tw}x{th} "
                          f"clamp wms {clamp & 3} wmt {(clamp >> 2) & 3} minu {(clamp >> 4) & 0x3FF} "
                          f"maxu {(clamp >> 14) & 0x3FF} minv {(clamp >> 24) & 0x3FF} maxv {(clamp >> 34) & 0x3FF} "
                          f"linear {((tex1 >> 5) & 1) | (((tex1 >> 6) & 7) == 1)}")
                count += 1
                verts = []
        else:
            regs[addr] = value

    for pkt in packets(args.log):
        i = 0
        while i < len(pkt):
            lo, hi = pkt[i]
            i += 1
            nloop, flg, nreg = lo & 0x7FFF, (lo >> 58) & 3, (lo >> 60) & 0xF or 16
            if (lo >> 46) & 1:
                write(0x00, (lo >> 47) & 0x7FF)
            descs = [(hi >> (4 * r)) & 0xF for r in range(nreg)]
            if flg == 0:
                for _ in range(nloop):
                    for d in descs:
                        if i >= len(pkt):
                            break
                        dlo, dhi = pkt[i]
                        i += 1
                        if d == 0xE:
                            write(dhi & 0xFF, dlo)
                        elif d == 0x3:
                            write(0x03, (dlo & 0x3FFF) | (((dlo >> 32) & 0x3FFF) << 16))
                        elif d in (0x4, 0x5):
                            write(0x05, (dlo & 0xFFFF) | (((dlo >> 32) & 0xFFFF) << 16))
                        elif d != 0xF:
                            write(d, dlo)
            elif flg == 1:
                vals = []
                for _ in range((nloop * nreg + 1) // 2):
                    if i >= len(pkt):
                        break
                    vals += list(pkt[i])
                    i += 1
                for k, v in enumerate(vals[:nloop * nreg]):
                    d = descs[k % nreg]
                    if d not in (0xE, 0xF):
                        write(d, v)
            else:
                i += nloop
    print(f"{count} sprites")


if __name__ == "__main__":
    main()
