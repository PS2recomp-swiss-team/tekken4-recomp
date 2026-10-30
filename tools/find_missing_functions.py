"""Find functions the Ghidra map is missing because nothing calls them directly.

Usage:
  python -I tools/find_missing_functions.py            # report only
  python -I tools/find_missing_functions.py --write    # also write config/extra_functions.csv

Seeds:
- C++ static constructor/destructor lists. ee-gcc keeps them in .data as
  [count, ptr * count, 0]; FUN_0029b1f0 (__do_global_ctors) walks the ctor list backwards.
- With --data-pointers: aligned words in .data/.rodata/.sdata that point into .text at an address
  no known function covers (vtables, callback tables).
- With --escapes: branch/jump targets that leave a function (known or new) into .text no function covers,
  e.g. a switch's default case past its case labels. Current map: --data-pointers --escapes --write.

Each seed is traced through its branches to find where it ends; calls to unknown addresses become
new seeds. Function bounds stop at the next known function start, so a seed can't swallow a neighbour.
postprocess_ghidra_export.py merges config/extra_functions.csv into the function map after each export.
"""
import argparse
import bisect
import csv
import struct
import sys

ELF = "game/disc/SLUS_203.28"
MAP_CSV = "config/ghidra_functions_only.csv"
EXTRA_CSV = "config/extra_functions.csv"
DATA_SECTIONS = (".data", ".rodata", ".sdata")


def load_elf(path):
    with open(path, "rb") as f:
        elf = f.read()
    shoff, = struct.unpack_from("<I", elf, 0x20)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", elf, 0x2E)
    headers = [struct.unpack_from("<IIIIII", elf, shoff + i * shentsize) for i in range(shnum)]
    strtab_off = headers[shstrndx][4]
    sections = {}
    for name_off, sh_type, _flags, addr, off, size in headers:
        name = elf[strtab_off + name_off:elf.index(b"\0", strtab_off + name_off)].decode()
        if sh_type == 1 and addr:  # PROGBITS with a load address
            sections[name] = (addr, elf[off:off + size])
    return sections


class Image:
    def __init__(self, sections):
        self.sections = sections
        self.text_lo, text = sections[".text"]
        self.text_hi = self.text_lo + len(text)

    def word(self, addr):
        for base, data in self.sections.values():
            if base <= addr < base + len(data) - 3:
                return struct.unpack_from("<I", data, addr - base)[0]
        return None

    def in_text(self, addr):
        return self.text_lo <= addr < self.text_hi and addr % 4 == 0


def load_map(path):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))[1:]
    return [(r[0], int(r[1], 16), int(r[2], 16)) for r in rows]


def find_init_lists(img):
    """[count, ptr * count, 0] runs in .data whose pointers all land in .text."""
    base, data = img.sections[".data"]
    words = struct.unpack_from(f"<{len(data) // 4}I", data)
    found = []
    for i, n in enumerate(words):
        if not 1 <= n <= 4096 or i + n + 1 >= len(words) or words[i + n + 1] != 0:
            continue
        ptrs = words[i + 1:i + n + 1]
        if all(img.in_text(p) for p in ptrs) and (i == 0 or words[i - 1] == 0 or not img.in_text(words[i - 1])):
            found.append((base + i * 4, list(ptrs)))
    return found


def branch_info(w, pc):
    """Returns (kind, target). kind: None, 'branch', 'always', 'call', 'jump', 'return', 'indirect'."""
    op = w >> 26
    rs, rt = (w >> 21) & 31, (w >> 16) & 31
    rel = pc + 4 + ((((w & 0xFFFF) ^ 0x8000) - 0x8000) << 2)
    if op == 0:
        funct = w & 0x3F
        if funct == 8:
            return ("return" if rs == 31 else "indirect"), None
        if funct == 9:
            return "call", None
        return None, None
    if op == 1:
        if rt in (0, 2, 3) or (rt == 1 and rs != 0):
            return "branch", rel
        if rt == 1:
            return "always", rel                  # bgez $zero = b
        if rt in (0x10, 0x11, 0x12, 0x13):
            return "call", rel                    # bltzal/bgezal family (bal)
        return None, None
    if op in (2, 3):
        target = ((pc + 4) & 0xF0000000) | ((w & 0x3FFFFFF) << 2)
        return ("jump" if op == 2 else "call"), target
    if op in (4, 5, 6, 7, 0x14, 0x15, 0x16, 0x17):
        if op == 4 and rs == 0 and rt == 0:
            return "always", rel                  # beq $zero,$zero = b
        return "branch", rel
    if op in (0x10, 0x11, 0x12) and rs == 8:      # bc0x/bc1x/bc2x
        return "branch", rel
    return None, None


def trace(img, start, limit):
    """Walks one function from start. Returns (end, call_targets, escapes, problems).

    escapes = branch/jump targets outside [start, limit). The recompiled code reaches them through the
    function table, so each one must be a function start (a switch's default case past its last case label
    froze the game after a Story Battle win: 0x268bf8 -> 0x268c30)."""
    seen, todo, calls, escapes, problems = set(), [start], set(), set(), []
    while todo:
        pc = todo.pop()
        while pc not in seen:
            if not start <= pc < limit:
                problems.append(f"ran to 0x{pc:08x} (limit 0x{limit:08x})")
                break
            w = img.word(pc)
            if w is None:
                problems.append(f"unmapped 0x{pc:08x}")
                break
            seen.add(pc)
            kind, target = branch_info(w, pc)
            if kind is None:
                pc += 4
                continue
            seen.add(pc + 4)                      # delay slot
            if kind == "call":
                if target is not None:
                    calls.add(target)
                pc += 8
            elif kind == "branch":
                if start <= target < limit:
                    todo.append(target)
                else:
                    escapes.add(target)
                pc += 8
            elif kind == "always" or (kind == "jump" and start <= target < limit):
                if start <= target < limit:
                    pc = target
                else:
                    escapes.add(target)
                    break                         # tail call
            else:                                 # return, indirect jump, tail call
                if kind == "jump":
                    escapes.add(target)
                break
    return max(seen) + 4, calls, escapes, problems


def data_pointer_seeds(img, starts, bodies):
    lo_ends = [lo for lo, _ in bodies]
    seeds = set()
    for name in DATA_SECTIONS:
        base, data = img.sections[name]
        for i in range(0, len(data) - 3, 4):
            p = struct.unpack_from("<I", data, i)[0]
            if not img.in_text(p) or p in starts:
                continue
            j = bisect.bisect_right(lo_ends, p) - 1
            if j >= 0 and bodies[j][0] <= p < bodies[j][1]:
                continue                          # inside a known function: case label, not a new function
            seeds.add(p)
    return seeds


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help=f"write {EXTRA_CSV}")
    ap.add_argument("--data-pointers", action="store_true", help="also seed from pointers into uncovered .text")
    ap.add_argument("--escapes", action="store_true",
                    help="also seed from branch/jump targets that leave a known function into uncovered .text")
    args = ap.parse_args()

    img = Image(load_elf(ELF))
    known = load_map(MAP_CSV)
    starts = {s for _, s, _ in known}
    bodies = sorted((s, e) for _, s, e in known)

    seeds = {}
    for addr, ptrs in find_init_lists(img):
        print(f"init list at 0x{addr:08x}: {len(ptrs)} entries")
        for p in ptrs:
            tag = "known" if p in starts else "MISSING"
            print(f"  0x{p:08x} {tag}")
            if p not in starts:
                seeds[p] = f"init_{p:08x}"
    if args.data_pointers:
        extra = data_pointer_seeds(img, starts, bodies)
        print(f"data pointers into uncovered .text: {len(extra)}")
        for p in sorted(extra):
            seeds.setdefault(p, f"FUN_{p:08x}")

    def inside_known(addr):
        j = bisect.bisect_right(bodies, (addr, 0xFFFFFFFF)) - 1
        return bodies[j][0] if j >= 0 and bodies[j][0] < addr < bodies[j][1] else None

    if args.escapes:
        escaped = set()
        for _, s, e in known:
            for t in trace(img, s, e)[2]:
                if not img.in_text(t) or t in starts:
                    continue
                owner = inside_known(t)
                if owner is not None:
                    print(f"  note 0x{s:08x}: branches to 0x{t:08x}, inside known function at 0x{owner:08x}")
                    continue
                escaped.add(t)
        print(f"branch targets leaving known functions into uncovered .text: {len(escaped)}")
        for p in sorted(escaped):
            seeds.setdefault(p, f"FUN_{p:08x}")

    found, todo = {}, sorted(seeds)
    while todo:
        start = todo.pop()
        if start in found or start in starts:
            continue
        nxt = sorted(starts | set(found) | set(seeds) | set(todo))
        k = bisect.bisect_right(nxt, start)
        limit = min(nxt[k] if k < len(nxt) else img.text_hi, img.text_hi)
        end, calls, escapes, problems = trace(img, start, limit)
        found[start] = (seeds.get(start, f"FUN_{start:08x}"), end)
        for p in problems:
            print(f"  warning 0x{start:08x}: {p}")
        for c in calls | (escapes if args.escapes else set()):
            if img.in_text(c) and c not in starts and c not in found:
                owner = inside_known(c)
                if owner is not None:
                    print(f"  note 0x{start:08x}: reaches 0x{c:08x}, inside known function at 0x{owner:08x}")
                    continue
                todo.append(c)

    print(f"new functions: {len(found)}")
    for start in sorted(found):
        name, end = found[start]
        print(f"  {name:<20} 0x{start:08x}-0x{end:08x} ({end - start} bytes)")
    if args.write:
        with open(EXTRA_CSV, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["Name", "Start", "End", "Size"])
            for start in sorted(found):
                name, end = found[start]
                w.writerow([name, f"0x{start:08X}", f"0x{end:08X}", end - start])
        print(f"wrote {EXTRA_CSV}")


if __name__ == "__main__":
    sys.exit(main())
