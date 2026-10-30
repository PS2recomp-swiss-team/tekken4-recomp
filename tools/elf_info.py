"""Quick PS2 (MIPS R5900) ELF inspector.

Usage: python -I tools/elf_info.py game/disc/SLUS_203.28

Prints headers, sections, symbol-table stats, debug-info hints and the
Sony SDK library version strings embedded in the binary. Read-only.
"""
import re
import struct
import sys
from collections import Counter

SHT = {0: "NULL", 1: "PROGBITS", 2: "SYMTAB", 3: "STRTAB", 4: "RELA", 5: "HASH",
       6: "DYNAMIC", 7: "NOTE", 8: "NOBITS", 9: "REL", 11: "DYNSYM",
       0x70000005: "MIPS_DEBUG", 0x70000006: "MIPS_REGINFO", 0x70000080: "MIPS_IOPMOD"}
PT = {0: "NULL", 1: "LOAD", 2: "DYNAMIC", 3: "INTERP", 4: "NOTE", 6: "PHDR",
      0x70000000: "MIPS_REGINFO", 0x70000080: "PS2_IOPMOD"}
STT = {0: "NOTYPE", 1: "OBJECT", 2: "FUNC", 3: "SECTION", 4: "FILE"}


def cstr(buf, off):
    end = buf.find(b"\0", off)
    return buf[off:end].decode("latin-1")


def main(path):
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF":
        sys.exit("not an ELF")
    (e_type, e_machine, e_version, e_entry, e_phoff, e_shoff, e_flags, _ehsize,
     e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx) = struct.unpack_from("<HHIIIIIHHHHHH", data, 16)
    print(f"file      {path}  ({len(data)} bytes)")
    print(f"type={e_type} machine={e_machine} (8=MIPS) flags=0x{e_flags:08x} entry=0x{e_entry:08x}")

    print(f"\nprogram headers ({e_phnum}):")
    for i in range(e_phnum):
        p_type, p_off, p_vaddr, _paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack_from(
            "<IIIIIIII", data, e_phoff + i * e_phentsize)
        rwx = "".join(c if p_flags & b else "-" for c, b in (("R", 4), ("W", 2), ("X", 1)))
        print(f"  {PT.get(p_type, hex(p_type)):<13} off=0x{p_off:06x} vaddr=0x{p_vaddr:08x} "
              f"filesz=0x{p_filesz:06x} memsz=0x{p_memsz:06x} {rwx}")

    sections = []
    for i in range(e_shnum):
        sections.append(struct.unpack_from("<IIIIIIIIII", data, e_shoff + i * e_shentsize))
    shstr_off = sections[e_shstrndx][4] if e_shnum else 0

    print(f"\nsections ({e_shnum}):")
    for name_off, sh_type, _flags, addr, off, size, link, _info, _align, entsize in sections:
        name = cstr(data, shstr_off + name_off) if e_shnum else ""
        print(f"  {name:<14} {SHT.get(sh_type, hex(sh_type)):<13} addr=0x{addr:08x} off=0x{off:06x} size=0x{size:06x}")

    print("\nsymbols:")
    found = False
    for name_off, sh_type, _f, _a, off, size, link, _i, _al, entsize in sections:
        if sh_type not in (2, 11):
            continue
        found = True
        strtab_off = sections[link][4]
        types, names = Counter(), []
        for j in range(size // (entsize or 16)):
            st_name, st_value, st_size, st_info, _other, _shndx = struct.unpack_from("<IIIBBH", data, off + j * 16)
            types[STT.get(st_info & 0xF, str(st_info & 0xF))] += 1
            if st_info & 0xF == 2 and st_name:
                names.append((st_value, cstr(data, strtab_off + st_name)))
        print(f"  {cstr(data, shstr_off + name_off)}: {sum(types.values())} entries {dict(types)}")
        for value, name in sorted(names)[:15]:
            print(f"    0x{value:08x} {name}")
        if len(names) > 15:
            print(f"    ... {len(names) - 15} more functions")
    if not found:
        print("  none (stripped)")

    print("\ncompiler / SDK strings:")
    seen = set()
    for pat in (rb"GCC: \([^\0]{1,60}", rb"PsII[\w ]{2,24}\d{4}", rb"SN Systems[^\0]{0,60}",
                rb"ProDG[^\0]{0,40}", rb"Sony Computer Entertainment[^\0]{0,60}"):
        for m in re.finditer(pat, data):
            s = m.group().decode("latin-1").strip()
            if s not in seen:
                seen.add(s)
                print(f"  0x{m.start():06x} {s}")
    if not seen:
        print("  none found")

    srcs = sorted({m.group().decode("latin-1") for m in re.finditer(rb"[\w/\\.:-]{2,80}\.(?:c|cpp|cc|s|h)\b", data)})
    print(f"\nsource-file-like strings: {len(srcs)}")
    for s in srcs[:40]:
        print(f"  {s}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "game/disc/SLUS_203.28")
