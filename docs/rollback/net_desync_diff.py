"""Diff two netplay desync dumps (net_desync_f<frame>.bin, written by both peers with TEKKEN4_NET_DESYNC_DUMP=1:
RDRAM 32 MB + scratchpad 16 KB of the frame whose final state hash differed).

    python -I docs/rollback/net_desync_diff.py logs/net/x/host/net_desync_f9000.bin logs/net/x/join/net_desync_f9000.bin

Prints the differing 4 KB pages (physical RDRAM address; scratchpad as 0x70000000+) and the first differing words.
"""
import sys

RAM = 32 * 1024 * 1024


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    a = open(sys.argv[1], "rb").read()
    b = open(sys.argv[2], "rb").read()
    n = min(len(a), len(b))
    pages = []
    for p in range(0, n, 4096):
        if a[p:p + 4096] != b[p:p + 4096]:
            pages.append(p)
    print(f"{len(pages)} differing 4 KB pages of {n // 4096}")
    for p in pages[:64]:
        base = p if p < RAM else 0x70000000 + (p - RAM)
        words = []
        for w in range(p, min(p + 4096, n), 4):
            if a[w:w + 4] != b[w:w + 4]:
                words.append(w)
        first = words[0] if words else p
        addr = first if first < RAM else 0x70000000 + (first - RAM)
        print(f"  page {base:08x}: {len(words)} words, first {addr:08x}: "
              f"{int.from_bytes(a[first:first + 4], 'little'):08x} vs {int.from_bytes(b[first:first + 4], 'little'):08x}")
    return 0 if not pages else 1


if __name__ == "__main__":
    sys.exit(main())
