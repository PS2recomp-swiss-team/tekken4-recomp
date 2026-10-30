"""Walks the MFIFO ring dump as a VIF1 tag chain from every REF whose tag-hi holds DIRECTHL with the same count
(the image-upload REFs seen before our stall: REF qwc=0x46 / 0xa + DIRECTHL) and prints the next tags."""
import struct
import sys

path = sys.argv[1]
BASE, SIZE = 0x100000, 0x80000
d = open(path, 'rb').read()
ids = {0: 'REFE', 1: 'CNT', 2: 'NEXT', 3: 'REF', 4: 'REFS', 5: 'CALL', 6: 'RET', 7: 'END'}


def at(addr):
    o = (addr - BASE) % SIZE
    return struct.unpack_from('<QQ', d, o)


shown = 0
for off in range(0, SIZE, 16):
    lo, hi = struct.unpack_from('<QQ', d, off)
    if ((lo >> 28) & 7) != 3 or (lo & 0xFFFF) not in (0x46, 0xA):
        continue
    if ((hi >> 32) & 0xFF00FFFF) != (0x51000000 | (lo & 0xFFFF)):
        continue
    shown += 1
    if shown > 6:
        break
    t = BASE + off
    print('chain from %08x' % t)
    for _ in range(10):
        lo, hi = at(t)
        idv, qwc, addr = (lo >> 28) & 7, lo & 0xFFFF, (lo >> 32) & 0x7FFFFFF0
        print('   %08x %-4s qwc=%-4x addr=%08x hi=%08x %08x' % (t, ids[idv], qwc, addr, hi & 0xFFFFFFFF, hi >> 32))
        if idv in (1, 2, 7):   # data follows the tag
            nxt = t + 16 + qwc * 16
        else:
            nxt = t + 16
        if idv == 2:
            nxt = addr
        if idv in (0, 7):
            break
        t = BASE + ((nxt - BASE) % SIZE)
print('chains shown:', shown)
