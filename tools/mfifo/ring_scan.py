"""Scans a dump (ring at 0x100000 or scratchpad) for the end of a VIF1 list as our trace shows it: REF qwc=0 then REFE
qwc=0, and prints the qwords around it (tag id / qwc / addr of each) to see what follows a list end on PCSX2."""
import struct
import sys

path, base = sys.argv[1], int(sys.argv[2], 16)
d = open(path, 'rb').read()
ids = {0: 'REFE', 1: 'CNT', 2: 'NEXT', 3: 'REF', 4: 'REFS', 5: 'CALL', 6: 'RET', 7: 'END'}


def tag(off):
    lo, hi = struct.unpack_from('<QQ', d, off)
    return lo, hi, ids[(lo >> 28) & 7], lo & 0xFFFF, (lo >> 32) & 0x7FFFFFF0


hits = 0
for off in range(0, len(d) - 16 * 8, 16):
    lo, hi, name, qwc, addr = tag(off)
    if name != 'REF' or qwc != 0:
        continue
    lo2, hi2, name2, qwc2, addr2 = tag(off + 16)
    if name2 != 'REFE' or qwc2 != 0:
        continue
    hits += 1
    if hits > 12:
        continue
    print('list end at %08x: REF qwc=0 @%08x, REFE qwc=0 addr=%08x @%08x' % (base + off, base + off, addr2, base + off + 16))
    for k in range(-2, 6):
        o = off + 16 * k
        if 0 <= o <= len(d) - 16:
            lo, hi, name, qwc, addr = tag(o)
            print('   %+d %08x: %016x %016x  as tag: %s qwc=%x addr=%08x' % (k, base + o, lo, hi, name, qwc, addr))
print('list ends found:', hits)
