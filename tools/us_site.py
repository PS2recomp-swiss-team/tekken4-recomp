"""Show the US (SLUS_203.28) code that corresponds to a PAL address, for porting PAL-only constants.

Maps the PAL address through logs/pal_to_us.csv (tools/map_pal_to_us.py: the containing PAL function and its US
match, same size), disassembles the US function (or N instructions from the site) and resolves lui/addiu/ori,
lui+load/store and gp-relative accesses to absolute addresses.
Usage (Capstone from external/pytools):
  external\\pytools\\Scripts\\python.exe -I tools/us_site.py <pal_addr> [count] [--us]   (--us: address is US already)
"""
import bisect
import csv
import struct
import sys

import capstone

ELF = "game/disc/SLUS_203.28"
MAP = "logs/pal_to_us.csv"
PAL_FUNCS = "config/ghidra_functions_only.csv"


def load_elf(path):
    elf = open(path, "rb").read()
    shoff, = struct.unpack_from("<I", elf, 0x20)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", elf, 0x2E)
    hdrs = [struct.unpack_from("<IIIIII", elf, shoff + i * shentsize) for i in range(shnum)]
    stro = hdrs[shstrndx][4]
    secs = {}
    gp = None
    for name_off, typ, _fl, addr, off, size in hdrs:
        name = elf[stro + name_off:elf.index(b"\0", stro + name_off)].decode()
        secs[name] = (addr, off, size, typ)
        if name == ".reginfo":
            gp, = struct.unpack_from("<I", elf, off + 20)
    return elf, secs, gp


def pal_to_us(addr):
    rows = [(int(r["pal"], 16), int(r["us"], 16), int(r["size"]), r["how"]) for r in csv.DictReader(open(MAP))]
    rows.sort()
    funcs = []
    for r in list(csv.reader(open(PAL_FUNCS, newline="")))[1:]:
        funcs.append((int(r[1], 16), int(r[2], 16)))
    funcs.sort()
    i = bisect.bisect_right(funcs, (addr, 0xFFFFFFFF)) - 1
    if i < 0 or not (funcs[i][0] <= addr < max(funcs[i][1], funcs[i][0] + 4)):
        start = None
    else:
        start = funcs[i][0]
    j = bisect.bisect_right(rows, (addr, 0xFFFFFFFF)) - 1
    if start is not None:
        for pal, us, size, how in rows:
            if pal == start:
                return us + (addr - start), f"in PAL func {start:#x} -> US {us:#x} ({how})"
    pal, us, size, how = rows[j]
    return us + (addr - pal), f"nearest mapped PAL func {pal:#x} -> US {us:#x} ({how}), delta guess"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    addr = int(args[0], 16)
    count = int(args[1]) if len(args) > 1 else 40
    elf, secs, gp = load_elf(ELF)
    if "--us" in sys.argv:
        us, why = addr, "US address given"
    else:
        us, why = pal_to_us(addr)
    print(f"PAL {addr:#x} -> US {us:#x}: {why}; US gp = {gp:#x}")
    taddr, toff, tsize, _ = secs[".text"]
    md = capstone.Cs(capstone.CS_ARCH_MIPS, capstone.CS_MODE_MIPS32 + capstone.CS_MODE_LITTLE_ENDIAN)
    md.detail = True
    md.skipdata = True  # R5900-only opcodes (lq/sq, MMI) show as .byte instead of ending the listing
    code = elf[toff + (us - taddr): toff + (us - taddr) + count * 4]
    hi = {}
    for ins in md.disasm(code, us):
        note = ""
        ops = ins.op_str.replace("$", "").split(", ")
        if ins.mnemonic == "lui":
            hi[ops[0]] = int(ops[1], 0) << 16
        elif ins.mnemonic in ("addiu", "ori") and len(ops) == 3 and ops[1] in hi:
            imm = int(ops[2], 0)
            note = f"= {(hi[ops[1]] + imm if ins.mnemonic == 'addiu' else hi[ops[1]] | imm) & 0xFFFFFFFF:#x}"
        elif "(" in ins.op_str:
            mem = ops[-1]
            disp, base = mem.split("(")
            base = base.rstrip(")")
            d = int(disp, 0) if disp else 0
            if base == "gp" and gp is not None:
                note = f"= {(gp + d) & 0xFFFFFFFF:#x} (gp{d:+#x})"
            elif base in hi:
                note = f"= {(hi[base] + d) & 0xFFFFFFFF:#x}"
        elif ins.mnemonic in ("jal", "j"):
            note = ""
        print(f"  {ins.address:08x}: {ins.mnemonic:8s} {ins.op_str:28s} {note}")


if __name__ == "__main__":
    main()
