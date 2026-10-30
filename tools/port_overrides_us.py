"""Rewrite the PAL addresses in runtime/*.cpp for the US build (SLUS-20328), with a report per literal.

- FUN_<pal>_0x<pal> symbols and code literals: through logs/pal_to_us.csv (containing PAL function -> US match).
- Data literals by region, the deltas read from US code (tools/us_site.py) and the carried-over jump tables:
    .data   PAL 0x2a9240-0x30a580: -0xe40 (reent pointer 0x3059d4 -> 0x304b94; checked per literal, see below)
    .rodata PAL 0x30a580-0x358700: the delta of the nearest jump table below it (-0xe80 .. -0x2980)
    .sdata/.sbss PAL 0x358700-0x35a400: -0x2700 (gp 0x35f270 -> 0x35cb70; done flag gp-0x5148)
    .bss    PAL 0x35a400-0x2000000: -0x2780 (sound client 0x1cccbc0 -> 0x1cca440, IPU jobs, movie tag)
- Every data literal is checked against the US code: "refs" = how many US instructions resolve to that address
  (lui pairs and gp-relative). 0 refs is normal for a struct field, but worth a look.
Usage: external\\pytools\\Scripts\\python.exe -I tools/port_overrides_us.py [--write] runtime/*.cpp
"""
import bisect
import collections
import csv
import re
import struct
import sys

import capstone

ELF = "game/disc/SLUS_203.28"
ROUND = 0x10000  # literals that are multiples of this are sizes/bases, never translated


def load():
    funcs = sorted((int(r[1], 16), int(r[2], 16)) for r in list(csv.reader(open("logs/pal_config/ghidra_functions_only.csv")))[1:])
    extra = sorted((int(r[1], 16), int(r[2], 16)) for r in list(csv.reader(open("logs/pal_config/extra_functions.csv")))[1:])
    fmap = {int(r["pal"], 16): int(r["us"], 16) for r in csv.DictReader(open("logs/pal_to_us.csv"))}
    return sorted(set(funcs + extra)), fmap


def jump_anchors():
    pal = re.findall(r'\[\[jump_tables\.table\]\]\naddress = "(0x[0-9a-f]+)"', open("logs/pal_config/ghidra_export.toml").read())
    return pal


def us_refs():
    elf = open(ELF, "rb").read()
    shoff, = struct.unpack_from("<I", elf, 0x20)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", elf, 0x2E)
    hdrs = [struct.unpack_from("<IIIIII", elf, shoff + i * shentsize) for i in range(shnum)]
    gp = None
    text = None
    stro = hdrs[shstrndx][4]
    for name_off, _t, _f, addr, off, size in hdrs:
        name = elf[stro + name_off:elf.index(b"\0", stro + name_off)].decode()
        if name == ".reginfo":
            gp, = struct.unpack_from("<I", elf, off + 20)
        if name == ".text":
            text = (addr, elf[off:off + size])
    md = capstone.Cs(capstone.CS_ARCH_MIPS, capstone.CS_MODE_MIPS32 + capstone.CS_MODE_LITTLE_ENDIAN)
    md.skipdata = True
    refs = collections.Counter()
    hi = {}
    for ins in md.disasm(text[1], text[0]):
        ops = ins.op_str.replace("$", "").split(", ")
        if ins.mnemonic == "lui":
            hi[ops[0]] = int(ops[1], 0) << 16
            continue
        if ins.mnemonic in ("addiu", "ori") and len(ops) == 3 and ops[1] in hi:
            imm = int(ops[2], 0)
            refs[(hi[ops[1]] + imm if ins.mnemonic == "addiu" else hi[ops[1]] | imm) & 0xFFFFFFFF] += 1
        elif "(" in ins.op_str and len(ops) >= 2:
            disp, base = ops[-1].split("(")
            base = base.rstrip(")")
            d = int(disp, 0) if disp else 0
            if base == "gp":
                refs[(gp + d) & 0xFFFFFFFF] += 1
            elif base in hi:
                refs[(hi[base] + d) & 0xFFFFFFFF] += 1
    return refs


def main():
    write = "--write" in sys.argv
    files = [a for a in sys.argv[1:] if not a.startswith("--")]
    funcs, fmap = load()
    starts = [f[0] for f in funcs]
    anchors = sorted((int(p, 16), d) for p, d in RODATA_ANCHORS)
    refs = us_refs()
    problems = 0

    def code(a):
        i = bisect.bisect_right(starts, a) - 1
        if i >= 0 and funcs[i][0] <= a < max(funcs[i][1], funcs[i][0] + 4) and funcs[i][0] in fmap:
            return fmap[funcs[i][0]] + (a - funcs[i][0]), "code"
        return None, "code: no US function"

    def data(a):
        if 0x2a9240 <= a < 0x30a580:
            return a - 0xe40, ".data"
        if 0x30a580 <= a < 0x358700:
            i = bisect.bisect_right([x for x, _ in anchors], a) - 1
            return a + anchors[i][1], f".rodata (anchor {anchors[i][0]:#x})"
        if 0x358700 <= a < 0x35a400:
            return a - 0x2700, ".sdata/.sbss"
        if 0x35a400 <= a < 0x2000000:
            return a - 0x2780, ".bss"
        return None, None

    for path in files:
        src = open(path, encoding="utf-8", newline="").read()
        log = []

        def fun_sub(m):
            nonlocal problems
            pal = int(m.group(1), 16)
            us = fmap.get(pal)
            if us is None:
                problems += 1
                log.append(f"  !! {m.group(0)}: no US match")
                return m.group(0)
            return f"FUN_{us:08x}_0x{us:x}"

        src2 = re.sub(r"FUN_([0-9a-f]{8})_0x[0-9a-f]+", fun_sub, src)
        # bare FUN_xxxxxxxx in comments
        src2 = re.sub(r"\bFUN_([0-9a-f]{8})\b(?!_0x)", lambda m: f"FUN_{fmap[int(m.group(1), 16)]:08x}" if int(m.group(1), 16) in fmap else m.group(0), src2)

        def lit_sub(m):
            nonlocal problems
            text, digits, suffix = m.group(0), m.group(1), m.group(2) or ""
            a = int(digits, 16)
            if a % ROUND == 0 or a < 0x180080 or a >= 0x1FFF000:  # sizes, bases, address masks
                return text
            if a in MANUAL:
                log.append(f"  {text} -> {MANUAL[a]:#x}{suffix}  [manual, checked with tools/us_site.py]")
                return f"0x{MANUAL[a]:0{len(digits)}x}" + suffix
            if 0x180080 <= a < 0x2a91f8:
                us, how = code(a)
            else:
                us, how = data(a)
                if us is None:
                    return text
            if us is None:
                problems += 1
                log.append(f"  !! {text}: {how}")
                return text
            width = len(digits)
            new = f"0x{us:0{width}x}" if digits.islower() or not any(c.isalpha() for c in digits) else f"0x{us:0{width}X}"
            note = "" if how == "code" else f" refs={refs.get(us, 0)}"
            log.append(f"  {text} -> {new}{suffix}  [{how}]{note}")
            return new + suffix

        src3 = re.sub(r"\b0x([0-9a-fA-F]{5,8})(u)?\b", lit_sub, src2)
        print(f"{path}: {sum(1 for l in log if '->' in l)} literals changed")
        for line in sorted(set(log)):
            print(line)
        if write and src3 != src:
            open(path, "w", encoding="utf-8", newline="").write(src3)
    print(f"problems: {problems}")


# Checked by hand with tools/us_site.py: SIF callbacks that are not in the PAL function map.
MANUAL = {0x229328: 0x2289c8, 0x229350: 0x2289f0}

# rodata deltas from tools/translate_jump_tables.py (PAL table -> US table)
RODATA_ANCHORS = [("0x30a580", -0xe80), ("0x30c580", -0xec0), ("0x30c970", -0xf80), ("0x31cb80", -0x2740),
                  ("0x3212a0", -0x2900), ("0x32bb60", -0x2900), ("0x32cbc0", -0x2980), ("0x32f350", -0x26f0)]

if __name__ == "__main__":
    main()
