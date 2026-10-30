"""Rebuild the VU1 micro memory image (game/vu1/micro/vu1_62802e7b8abf4848.bin) from the player's own ELF.

build_runtime.cmd links native VU1 blocks generated from that image; without it the fight runs on the VU1
interpreter (~12 fps instead of full speed). The image used to be captured at runtime (GOW_VU1_CAPTURA). It is
the 18-overlay VU1 program group copied out of .vudata, so it can be assembled from the ELF: the recipe below
holds only addresses (VU micro address, EE address in .vudata, length), no game bytes. The rest is zero.
Checked against the capture of 2026-10-29 (SHA-256 below); the PAL build captured the same image name.
Usage: python -I tools/vu1_micro_from_elf.py [elf] [out_dir]   (defaults: game/disc/SLUS_203.28, game/vu1/micro)
"""
import hashlib
import os
import struct
import sys

NAME = "vu1_62802e7b8abf4848.bin"
SIZE = 0x4000
SHA256 = "ad6526bdeb68fd741d3a35ed5cd26dec2cf611cbaaf364b89102fbe831579eb0"
# (VU1 micro byte address, EE virtual address, length), SLUS-20328 v1.00
RECIPE = [
    (0x0000, 0x305048, 0x10), (0x0010, 0x305060, 0x148), (0x0158, 0x3051b0, 0x140), (0x0298, 0x3052f8, 0x90),
    (0x0328, 0x305390, 0x800), (0x0b28, 0x305b98, 0x800), (0x1328, 0x3063a0, 0x30), (0x14a8, 0x305390, 0x98),
    (0x1540, 0x306470, 0x350), (0x1890, 0x3067c8, 0x30), (0x18c0, 0x306800, 0x328), (0x1be8, 0x306b30, 0x1e0),
    (0x1dc8, 0x306d18, 0x1a0), (0x1f68, 0x306ec0, 0x348), (0x22b0, 0x305390, 0x98), (0x2348, 0x3072a8, 0x360),
    (0x26a8, 0x307610, 0x468), (0x2c40, 0x307a80, 0x3a0), (0x32a0, 0x307e28, 0x650), (0x3c00, 0x308480, 0x290),
]


def ee_reader(elf):
    shoff, = struct.unpack_from("<I", elf, 0x20)
    shentsize, shnum, _ = struct.unpack_from("<HHH", elf, 0x2E)
    secs = [struct.unpack_from("<IIIIII", elf, shoff + i * shentsize) for i in range(shnum)]

    def read(addr, length):
        for _n, typ, _f, base, off, size in secs:
            if typ == 1 and base <= addr and addr + length <= base + size:
                return elf[off + addr - base: off + addr - base + length]
        raise ValueError(f"EE address {addr:#x}+{length:#x} is not in a loaded section")
    return read


def main():
    elf_path = sys.argv[1] if len(sys.argv) > 1 else "game/disc/SLUS_203.28"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "game/vu1/micro"
    read = ee_reader(open(elf_path, "rb").read())
    image = bytearray(SIZE)
    for vu, ee, length in RECIPE:
        image[vu:vu + length] = read(ee, length)
    digest = hashlib.sha256(image).hexdigest()
    if digest != SHA256:
        sys.exit(f"VU1 image SHA-256 {digest} does not match {SHA256}: not SLUS-20328 v1.00?")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, NAME), "wb") as f:
        f.write(image)
    print(f"{os.path.join(out_dir, NAME)}: {SIZE} bytes, SHA-256 ok")


if __name__ == "__main__":
    main()
