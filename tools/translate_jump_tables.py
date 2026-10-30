"""Carry the validated PAL [jump_tables] over to the US ELF.

Each PAL target is mapped through logs/pal_to_us.csv (its containing PAL function -> the US match, same size);
the table itself is found by searching the US data sections for that exact sequence of target words (a table is
a run of .word targets), so the US table address is read from the US ELF, not guessed.
Usage: python -I tools/translate_jump_tables.py <pal_export.toml> <us_export.toml>   (appends to the US TOML)
"""
import bisect
import csv
import re
import struct
import sys

ELF = "game/disc/SLUS_203.28"


def main():
    pal_toml, us_toml = sys.argv[1:3]
    funcs = sorted((int(r[1], 16), int(r[2], 16)) for r in list(csv.reader(open("logs/pal_config/ghidra_functions_only.csv")))[1:])
    fmap = {int(r["pal"], 16): int(r["us"], 16) for r in csv.DictReader(open("logs/pal_to_us.csv"))}
    starts = [f[0] for f in funcs]

    def map_code(a):
        i = bisect.bisect_right(starts, a) - 1
        if i >= 0 and funcs[i][0] <= a < funcs[i][1] and funcs[i][0] in fmap:
            return fmap[funcs[i][0]] + (a - funcs[i][0])
        return None

    elf = open(ELF, "rb").read()
    shoff, = struct.unpack_from("<I", elf, 0x20)
    shentsize, shnum, _ = struct.unpack_from("<HHH", elf, 0x2E)
    data = []
    for i in range(shnum):
        _n, typ, _f, addr, off, size = struct.unpack_from("<IIIIII", elf, shoff + i * shentsize)
        if typ == 1 and addr >= 0x2a8600 and size:  # PROGBITS data sections after .text
            data.append((addr, elf[off:off + size]))

    text = open(pal_toml).read()
    tables = re.findall(r'\[\[jump_tables\.table\]\]\naddress = "(0x[0-9a-f]+)"\nentries = \[\n(.*?)\n\]', text, re.S)
    out = ["", "# Validated switch tables, carried over from the PAL build by tools/translate_jump_tables.py.",
           "# address and target are absolute EE VAs. PS2Recomp ignores index.", "[jump_tables]"]
    ok = bad = 0
    for addr, body in tables:
        entries = [(int(i), int(t, 16)) for i, t in re.findall(r'index = (\d+), target = "(0x[0-9a-f]+)"', body)]
        us_t = [map_code(t) for _, t in entries]
        if None in us_t:
            print(f"PAL table {addr}: a target has no US function, skipped")
            bad += 1
            continue
        blob = b"".join(struct.pack("<I", t) for t in us_t)
        hits = [base + m.start() for base, d in data for m in re.finditer(re.escape(blob), d) if m.start() % 4 == 0]
        if len(hits) != 1:
            print(f"PAL table {addr}: {len(hits)} matches in US data, skipped")
            bad += 1
            continue
        ok += 1
        out += ["", "[[jump_tables.table]]", f'address = "{hits[0]:#x}"', "entries = ["]
        out += [f'  {{ index = {i}, target = "{t:#x}" }},' for (i, _), t in zip(entries, us_t)]
        out += ["]"]
        print(f"PAL table {addr} -> US {hits[0]:#x} ({len(entries)} entries, delta {hits[0] - int(addr, 16):+#x})")
    with open(us_toml, "a", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print(f"{ok} tables carried over, {bad} skipped")


if __name__ == "__main__":
    main()
