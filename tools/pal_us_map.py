"""PAL (SCES-50878) <-> US (SLUS-20328) address and patch translator.

Function addresses come from the two config/function_map.csv lists. Unique
function names of equal size are anchors; the size sequences between those
anchors are aligned with difflib. An address inside a matched function maps
by its byte offset. That is exact when the two copies are the same instruction
stream (immediates and branch targets may differ).

Data addresses come from those instruction streams: every lui/addiu/ori and
every gp-relative or lui-based load/store in a structurally equal function is
a (PAL, US) pair. An address that is not itself referenced takes the delta of
the nearest code references in the same ELF section when those agree.

Nothing from the discs is written. config/pal_us_map.csv is addresses and
sizes only.

  python -I tools/pal_us_map.py addr 0x2177E0
  python -I tools/pal_us_map.py addr 0x216EA0 --from us
  python -I tools/pal_us_map.py func 0x2177E0
  python -I tools/pal_us_map.py csv --out config/pal_us_map.csv
  python -I tools/pal_us_map.py patches widescreen.pnach --from pal --to us
  python -I tools/pal_us_map.py overrides runtime/tekken4_overrides.cpp
  python -I tools/pal_us_map.py check

US tree: TEKKEN4_US, else ../tekken4-recomp_usa. Read-only.
"""
from __future__ import annotations

import argparse
import bisect
import csv
import difflib
import os
import re
import struct
import sys
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT_LO = 0x00100000
TEXT_HI_FALLBACK = 0x02000000
MEMOPS = {0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x28, 0x29, 0x2B, 0x37, 0x3F}
STORES = {0x1F, 0x28, 0x29, 0x2B, 0x38, 0x3F}
DATA_SECTIONS = (".data", ".rodata", ".gcc_except_table", ".lit4", ".sdata", ".sbss", ".bss")
# Listed in the task, plus sceIpuStopDMA which the same pnach pairs by value.
LISTED_PAIRS = (
    (0x002177E0, 0x00216EA0),
    (0x001F7028, 0x001F6BF8),
    (0x0018D408, 0x0018D408),
    (0x002015D4, 0x00200D84),
    (0x002015D8, 0x00200D88),
    (0x002015E4, 0x00200D94),
    (0x00292424, 0x002917E4),
)
# Lockstep results from this tree's ELFs. check() requires these.
DATA_PAIRS = (
    (0x003059D4, 0x00304B94, "reent"),
    (0x00314360, 0x00313380, "file table"),
    (0x0035A128, 0x00357A28, "disc done flag"),
    (0x0035A12C, 0x00357A2C, "movie read result"),
    (0x01CCCBC0, 0x01CCA440, "sound client"),
    (0x01CCD2B0, 0x01CCAB30, "movie IPU tag"),
    (0x00358754, 0x00356054, "pad"),
)


def us_root():
    env = os.environ.get("TEKKEN4_US")
    if env:
        return Path(env)
    return ROOT.parent / "tekken4-recomp_usa"


def run_conf(run, named):
    if named and run >= 3:
        return 0.99
    if named:
        return 0.97
    if run >= 20:
        return 0.96
    if run >= 8:
        return 0.93
    if run >= 3:
        return 0.86
    if run == 2:
        return 0.62
    return 0.42


class Func(object):
    def __init__(self, start, end, name):
        self.start = start
        self.end = end
        self.size = end - start
        self.name = name


class Match(object):
    def __init__(self, pal, us, how, run):
        self.pal = pal
        self.us = us
        self.how = how
        self.run = run
        self.named = how.startswith("name")
        self.conf = run_conf(run, self.named)
        self.mismatch = None  # byte offset of the first real difference, or None if identical
        self.struct_checked = False


class Result(object):
    def __init__(self, src, dst=None, conf=0.0, method="", detail="", reason=""):
        self.src = src
        self.dst = dst
        self.conf = conf
        self.method = method
        self.detail = detail
        self.reason = reason

    @property
    def ok(self):
        return self.dst is not None


def load_functions(path):
    rows = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        for r in list(csv.reader(f))[1:]:
            if len(r) < 3 or not r[1] or not r[2]:
                continue
            start, end = int(r[1], 16), int(r[2], 16)
            if end < start:
                continue
            rows.append((start, end, r[0] or ""))
    rows.sort()
    out = []
    for start, end, name in rows:
        if out and out[-1].start == start:
            if end > out[-1].end:
                out[-1] = Func(start, end, name or out[-1].name)
            continue
        out.append(Func(start, end, name))
    return out


def unique_names(funcs):
    d = defaultdict(list)
    for i, fn in enumerate(funcs):
        if fn.name and not fn.name.startswith("FUN_"):
            d[fn.name].append(i)
    return {n: ix[0] for n, ix in d.items() if len(ix) == 1}


def align_functions(pal, us):
    """Return pal_start -> Match. Equal-size unique names are hard anchors."""
    pn, un = unique_names(pal), unique_names(us)
    raw = []
    for name, pi in pn.items():
        ui = un.get(name)
        if ui is None or pal[pi].size != us[ui].size or pal[pi].size <= 0:
            continue
        raw.append((pi, ui, name))
    raw.sort()
    mono = []
    last = -1
    for pi, ui, name in raw:
        if ui > last:
            mono.append((pi, ui, name))
            last = ui
    fmap = {}
    bounds = [(-1, -1)] + [(pi, ui) for pi, ui, _n in mono] + [(len(pal), len(us))]
    for (p0, u0), (p1, u1) in zip(bounds, bounds[1:]):
        ps, uss = pal[p0 + 1:p1], us[u0 + 1:u1]
        if not ps or not uss:
            continue
        sm = difflib.SequenceMatcher(None, [f.size for f in ps], [f.size for f in uss], autojunk=False)
        for b in sm.get_matching_blocks():
            if not b.size:
                continue
            for k in range(b.size):
                p, u = ps[b.a + k], uss[b.b + k]
                fmap[p.start] = Match(p, u, "run%d" % b.size, b.size)
    for pi, ui, name in mono:
        p, u = pal[pi], us[ui]
        prev = fmap.get(p.start)
        if prev and prev.us.start == u.start:
            how = "name+" + prev.how
            run = prev.run
        else:
            how, run = "name", prev.run if prev else 0
        fmap[p.start] = Match(p, u, how, run)
    # A short run squeezed between two solid matches that share its delta is the
    # same shift, not a one-function coincidence (srand sits just before rand).
    ordered = sorted(fmap.values(), key=lambda m: m.pal.start)

    def _solid(m):
        return m.named or m.run >= 3

    def _side(i, step):
        d = ordered[i].pal.start - ordered[i].us.start
        j = i + step
        while 0 <= j < len(ordered):
            a, b = (ordered[j - 1], ordered[j]) if step > 0 else (ordered[j], ordered[j + 1])
            if b.pal.start - a.pal.end > 0x20:
                return False
            o = ordered[j]
            if o.pal.start - o.us.start != d:
                return False
            if _solid(o):
                return True
            j += step
        return False

    for i, m in enumerate(ordered):
        if _solid(m):
            continue
        if _side(i, -1) and _side(i, +1):
            m.conf = max(m.conf, 0.90)
            if not m.how.endswith("+nbr"):
                m.how += "+nbr"
    return fmap


class Elf(object):
    def __init__(self, path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        self.secs = {}
        self.gp = None
        self._text = None
        self._tbase = None
        self._parse()

    def _parse(self):
        data = self.data
        if data[:4] != b"\x7fELF":
            raise SystemExit("not an ELF: %s" % self.path)
        e_shoff = struct.unpack_from("<I", data, 32)[0]
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 46)
        sections = [struct.unpack_from("<IIIIIIIIII", data, e_shoff + i * e_shentsize) for i in range(e_shnum)]
        shstr = sections[e_shstrndx][4]
        for name_off, sh_type, _flags, addr, off, size, *_rest in sections:
            end = data.find(b"\0", shstr + name_off)
            name = data[shstr + name_off:end].decode("latin-1")
            self.secs[name] = (addr, off, size, sh_type)
        reg = self.secs.get(".reginfo")
        if reg and reg[2] >= 24:
            self.gp = struct.unpack_from("<I", data, reg[1] + 20)[0]

    def text(self):
        if self._text is None:
            addr, off, size, _typ = self.secs[".text"]
            self._tbase = addr
            self._text = self.data[off:off + size]
        return self._tbase, self._text

    def func_bytes(self, start, size):
        base, text = self.text()
        off = start - base
        if off < 0 or off + size > len(text):
            return b""
        return text[off:off + size]

    def section_of(self, addr):
        for name in (".text",) + DATA_SECTIONS:
            sec = self.secs.get(name)
            if sec and sec[0] <= addr < sec[0] + sec[2]:
                return name
        return None

    def bounds(self, name):
        addr, _off, size, _typ = self.secs[name]
        return addr, size


def same_op(w1, w2):
    op1, op2 = w1 >> 26, w2 >> 26
    if op1 != op2:
        return False
    if op1 in (2, 3):
        return True
    if ((w1 >> 21) & 31) != ((w2 >> 21) & 31) or ((w1 >> 16) & 31) != ((w2 >> 16) & 31):
        return False
    if op1 in (0, 0x1C):
        if (w1 & 63) != (w2 & 63) or ((w1 >> 11) & 31) != ((w2 >> 11) & 31):
            return False
    return True


def pair_refs(pb, ub, pgp, ugp):
    """Lockstep the two copies. Stop at the first real instruction difference."""
    if len(pb) != len(ub) or (len(pb) % 4) or not pb:
        return [], 0
    ph = [None] * 32
    uh = [None] * 32
    refs = []
    for i in range(len(pb) // 4):
        w1 = struct.unpack_from("<I", pb, i * 4)[0]
        w2 = struct.unpack_from("<I", ub, i * 4)[0]
        if not same_op(w1, w2):
            return refs, i * 4
        op = w1 >> 26
        rs, rt = (w1 >> 21) & 31, (w1 >> 16) & 31
        imm1, imm2 = w1 & 0xFFFF, w2 & 0xFFFF
        sim1 = imm1 - 0x10000 if imm1 & 0x8000 else imm1
        sim2 = imm2 - 0x10000 if imm2 & 0x8000 else imm2
        if op == 0x0F:
            ph[rt] = imm1 << 16
            uh[rt] = imm2 << 16
            continue
        if op in (0x09, 0x0D) and ph[rs] is not None and uh[rs] is not None:
            if op == 0x09:
                a1 = (ph[rs] + sim1) & 0xFFFFFFFF
                a2 = (uh[rs] + sim2) & 0xFFFFFFFF
            else:
                a1 = (ph[rs] | imm1) & 0xFFFFFFFF
                a2 = (uh[rs] | imm2) & 0xFFFFFFFF
            refs.append((a1, a2, "abs"))
            ph[rt] = None
            uh[rt] = None
            continue
        if op in MEMOPS:
            if rs == 28 and pgp is not None and ugp is not None:
                refs.append(((pgp + sim1) & 0xFFFFFFFF, (ugp + sim2) & 0xFFFFFFFF, "gp"))
            elif ph[rs] is not None and uh[rs] is not None:
                refs.append(((ph[rs] + sim1) & 0xFFFFFFFF, (uh[rs] + sim2) & 0xFFFFFFFF, "mem"))
        if op not in (2, 3) and op not in STORES and op != 0x0F:
            ph[rt] = None
            uh[rt] = None
    return refs, None


def ref_conf(n, kind):
    if n >= 5:
        conf = 0.99
    elif n >= 2:
        conf = 0.96
    else:
        conf = 0.90
    if kind == "gp":
        conf = min(0.99, conf + 0.01)
    return conf


class World(object):
    def __init__(self, pal_root, us_root):
        self.pal_root = Path(pal_root)
        self.us_root = Path(us_root)
        self.pal = load_functions(self.pal_root / "config" / "function_map.csv")
        self.us = load_functions(self.us_root / "config" / "function_map.csv")
        self.fmap = align_functions(self.pal, self.us)
        self.by_us = {}
        self.clashes = []
        for m in self.fmap.values():
            prev = self.by_us.get(m.us.start)
            if prev is not None and prev.pal.start != m.pal.start:
                self.clashes.append((prev, m))
                if m.conf > prev.conf:
                    self.by_us[m.us.start] = m
            else:
                self.by_us[m.us.start] = m
        self.pal_starts = [f.start for f in self.pal]
        self.us_starts = [f.start for f in self.us]
        self.pal_elf = None
        self.us_elf = None
        self._data = None
        self.code_agree = 0
        self.code_disagree = 0
        self.code_bad = []
        self.struct_bad = []

    def elfs(self):
        if self.pal_elf is None:
            self.pal_elf = Elf(self.pal_root / "game" / "disc" / "SCES_508.78")
            self.us_elf = Elf(self.us_root / "game" / "disc" / "SLUS_203.28")
        return self.pal_elf, self.us_elf

    def data(self):
        if self._data is None:
            self._data = self._build_data()
        return self._data

    def _plausible(self, pal_addr, us_addr):
        pe, ue = self.elfs()
        sp, su = pe.section_of(pal_addr), ue.section_of(us_addr)
        if sp is None or sp != su or sp == ".text":
            return False
        pa, psz = pe.bounds(sp)
        ua, usz = ue.bounds(su)
        sd = pa - ua
        ed = (pa + psz) - (ua + usz)
        delta = pal_addr - us_addr
        if delta == 0 and sd != 0:
            return False
        lo = min(sd, ed) - 0x20
        hi = max(sd, ed) + (0x100 if sp == ".bss" else 0x400)
        return lo <= delta <= hi

    def _build_data(self):
        pe, ue = self.elfs()
        bucket = defaultdict(Counter)
        kinds = defaultdict(Counter)
        code_bucket = defaultdict(Counter)
        for m in self.fmap.values():
            if m.pal.size < 4:
                continue
            pb = pe.func_bytes(m.pal.start, m.pal.size)
            ub = ue.func_bytes(m.us.start, m.us.size)
            refs, mismatch = pair_refs(pb, ub, pe.gp, ue.gp)
            m.mismatch = mismatch
            m.struct_checked = True
            if mismatch is not None:
                self.struct_bad.append(m)
            for a, b, k in refs:
                if pe.section_of(a) == ".text" and ue.section_of(b) == ".text":
                    code_bucket[a][b] += 1
                    continue
                if not self._plausible(a, b):
                    continue
                bucket[a][b] += 1
                kinds[a][k] += 1
        pal_to_us = {}
        for a, c in bucket.items():
            b, n = c.most_common(1)[0]
            if len(c) > 1 and c.most_common(2)[1][1] == n:
                continue
            pal_to_us[a] = (b, n, kinds[a].most_common(1)[0][0])
        us_to_pal = {}
        inv = defaultdict(Counter)
        ink = defaultdict(Counter)
        for a, (b, n, k) in pal_to_us.items():
            inv[b][a] += n
            ink[b][k] += n
        for b, c in inv.items():
            a, n = c.most_common(1)[0]
            if len(c) > 1 and c.most_common(2)[1][1] == n:
                continue
            us_to_pal[b] = (a, n, ink[b].most_common(1)[0][0])
        for a, c in code_bucket.items():
            b, _n = c.most_common(1)[0]
            got = self.map_code(a, "pal")
            if got.ok and got.dst == b:
                self.code_agree += 1
            elif got.ok and a == b:
                continue  # same immediate on both discs: a constant, not a relocated pointer
            elif got.ok:
                self.code_disagree += 1
                if len(self.code_bad) < 16:
                    self.code_bad.append((a, b, got.dst))
        return {
            "pal": pal_to_us,
            "us": us_to_pal,
            "pal_keys": sorted(pal_to_us),
            "us_keys": sorted(us_to_pal),
        }

    def _find_func(self, funcs, starts, addr):
        i = bisect.bisect_right(starts, addr) - 1
        if i < 0:
            return None
        fn = funcs[i]
        if fn.start <= addr < fn.end:
            return fn
        return None

    def map_code(self, addr, src):
        if src == "pal":
            fn = self._find_func(self.pal, self.pal_starts, addr)
            m = self.fmap.get(fn.start) if fn else None
            if fn is None:
                return Result(addr, reason="not inside a PAL function")
            if m is None:
                return Result(addr, reason="PAL function 0x%08x %s has no equal-size US partner" % (fn.start, fn.name))
            off = addr - fn.start
            dst = m.us.start + off
            detail = "%s+0x%x -> %s+0x%x" % (fn.name, off, m.us.name, off)
            return self._code_result(addr, dst, m, off, detail)
        fn = self._find_func(self.us, self.us_starts, addr)
        m = self.by_us.get(fn.start) if fn else None
        if fn is None:
            return Result(addr, reason="not inside a US function")
        if m is None:
            return Result(addr, reason="US function 0x%08x %s has no PAL partner" % (fn.start, fn.name))
        off = addr - fn.start
        dst = m.pal.start + off
        detail = "%s+0x%x -> %s+0x%x" % (fn.name, off, m.pal.name, off)
        return self._code_result(addr, dst, m, off, detail)

    def ensure_struct(self, m):
        if m.struct_checked:
            return
        try:
            pe, ue = self.elfs()
        except OSError:
            return
        pb = pe.func_bytes(m.pal.start, m.pal.size)
        ub = ue.func_bytes(m.us.start, m.us.size)
        if len(pb) != m.pal.size or len(ub) != m.us.size:
            m.mismatch = 0
        else:
            _refs, m.mismatch = pair_refs(pb, ub, pe.gp, ue.gp)
        m.struct_checked = True

    def _code_result(self, addr, dst, m, off, detail):
        self.ensure_struct(m)
        conf = m.conf
        method = "insn:" + m.how
        if m.mismatch is not None and off >= m.mismatch:
            conf = min(conf, 0.55)
            method += ":shifted"
            detail += " stream diverges at +0x%x" % m.mismatch
        return Result(addr, dst, conf, method, detail)

    def _gap(self, addr, src):
        """Map a .text hole when the surrounding functions share one delta."""
        if src == "pal":
            starts, funcs, table = self.pal_starts, self.pal, self.fmap
            def other(fn):
                m = table.get(fn.start)
                return m.us if m else None
        else:
            starts, funcs = self.us_starts, self.us
            def other(fn):
                m = self.by_us.get(fn.start)
                return m.pal if m else None
        i = bisect.bisect_right(starts, addr) - 1
        if i < 0 or i + 1 >= len(funcs):
            return None
        prev, nxt = funcs[i], funcs[i + 1]
        if not (prev.end <= addr < nxt.start):
            return None
        op, on = other(prev), other(nxt)
        if op is None or on is None:
            return None
        if (nxt.start - prev.start) != (on.start - op.start):
            return None
        delta = prev.start - op.start
        return addr - delta, "text-gap", "between 0x%08x and 0x%08x" % (prev.start, nxt.start)

    def _interp(self, addr, src):
        data = self.data()
        elf = self.elfs()[0 if src == "pal" else 1]
        sec = elf.section_of(addr)
        if sec is None or sec == ".text":
            return None
        table = data[src]
        keys = data["pal_keys" if src == "pal" else "us_keys"]
        if addr in table:
            dst, n, kind = table[addr]
            return dst, ref_conf(n, kind), "code-ref:" + kind, "n=%d" % n
        pred = self._neighbor(keys, addr, elf, sec, -1)
        succ = self._neighbor(keys, addr, elf, sec, +1)
        if pred is not None and succ is not None:
            d1 = pred - table[pred][0]
            d2 = succ - table[succ][0]
            if d1 == d2:
                gap = succ - pred
                conf = 0.92 if gap <= 0x400 else (0.84 if gap <= 0x2000 else 0.70)
                return addr - d1, conf, "section-delta", "%s d=%+#x gap=0x%x" % (sec, d1, gap)
            return None, 0.0, "", "delta changes in %s between 0x%08x (%+#x) and 0x%08x (%+#x)" % (
                sec, pred, d1, succ, d2)
        base, size = elf.bounds(sec)
        other = self.elfs()[1 if src == "pal" else 0]
        ob, osz = other.bounds(sec)
        start_d = base - ob
        end_d = (base + size) - (ob + osz)
        if pred is not None and succ is None:
            d1 = pred - table[pred][0]
            if d1 == end_d or (base + size - pred) <= 0x200:
                return addr - d1, 0.80, "section-delta", "%s tail d=%+#x" % (sec, d1)
        if succ is not None and pred is None:
            d2 = succ - table[succ][0]
            if d2 == start_d or (succ - base) <= 0x200:
                return addr - d2, 0.80, "section-delta", "%s head d=%+#x" % (sec, d2)
        return None

    def _neighbor(self, keys, addr, elf, sec, step):
        if step < 0:
            i = bisect.bisect_right(keys, addr) - 1
            while i >= 0:
                s = elf.section_of(keys[i])
                if s == sec:
                    return keys[i]
                if s is not None:
                    return None
                i -= 1
            return None
        i = bisect.bisect_right(keys, addr)
        while i < len(keys):
            s = elf.section_of(keys[i])
            if s == sec:
                return keys[i]
            if s is not None:
                return None
            i += 1
        return None

    def map_addr(self, addr, src="pal"):
        addr &= 0xFFFFFFFF
        try:
            pe, ue = self.elfs()
        except OSError as e:
            pe = ue = None
            elf_err = str(e)
        else:
            elf_err = ""
        elf = pe if src == "pal" else ue
        if elf is not None:
            sec = elf.section_of(addr)
            if sec == ".text" or self._find_func(
                    self.pal if src == "pal" else self.us,
                    self.pal_starts if src == "pal" else self.us_starts, addr):
                code = self.map_code(addr, src)
                if code.ok or (sec == ".text" and "not inside" not in code.reason):
                    if code.ok:
                        return code
                    gap = self._gap(addr, src) if sec == ".text" else None
                    if gap:
                        dst, method, detail = gap
                        return Result(addr, dst, 0.75, method, detail)
                    return code
                if sec == ".text":
                    gap = self._gap(addr, src)
                    if gap:
                        dst, method, detail = gap
                        return Result(addr, dst, 0.75, method, detail)
                    return code
            if sec in DATA_SECTIONS:
                got = self._interp(addr, src)
                if got is None:
                    return Result(addr, reason="no code-reference anchor in %s" % sec)
                if got[0] is None:
                    return Result(addr, reason=got[3])
                dst, conf, method, detail = got
                return Result(addr, dst, conf, method, detail)
            if elf_err:
                return Result(addr, reason="ELF unreadable (%s)" % elf_err)
            if addr >= 0x80000000:
                return Result(addr, reason="kseg or integer constant (top bit set)")
            if 0x10000000 <= addr < 0x20000000:
                return Result(addr, reason="hardware or IOP register")
            if addr >= 0x20000000:
                return Result(addr, reason="integer constant, not an EE address")
            if addr < elf.secs[".text"][0]:
                return Result(addr, reason="below EE .text (IOP address, scratchpad, or an id constant)")
            return Result(addr, reason="not in a relocated ELF section (mask or length)")
        # No ELF: code map only.
        code = self.map_code(addr, src)
        if code.ok or "function" in code.reason:
            return code
        return Result(addr, reason="ELF not available and address is outside the function lists")


def fmt(r):
    if r.ok:
        extra = (" " + r.detail) if r.detail else ""
        return "0x%08x -> 0x%08x conf=%.2f method=%s%s" % (r.src, r.dst, r.conf, r.method, extra)
    return "0x%08x UNMAPPED reason=%s" % (r.src, r.reason)


def write_csv(world, path):
    path = Path(path)
    rows = sorted(world.fmap.values(), key=lambda m: m.pal.start)
    with open(path, "w", newline="\n", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["pal", "us", "size", "method", "conf"])
        for m in rows:
            w.writerow(["0x%08x" % m.pal.start, "0x%08x" % m.us.start, m.pal.size, m.how, "%.2f" % m.conf])
    return len(rows)


def cmd_addr(world, addrs, src):
    bad = 0
    for text in addrs:
        r = world.map_addr(int(text, 16), src)
        print(fmt(r))
        if not r.ok:
            bad += 1
    return bad


def cmd_func(world, addrs, src):
    bad = 0
    for text in addrs:
        addr = int(text, 16)
        if src == "pal":
            fn = world._find_func(world.pal, world.pal_starts, addr)
            m = world.fmap.get(fn.start) if fn else None
        else:
            fn = world._find_func(world.us, world.us_starts, addr)
            m = world.by_us.get(fn.start) if fn else None
        if fn is None:
            print("0x%08x UNMAPPED reason=not inside a %s function" % (addr, src))
            bad += 1
            continue
        if m is None:
            print("0x%08x-0x%08x size=%d UNMAPPED reason=no equal-size partner name=%s" % (
                fn.start, fn.end, fn.size, fn.name))
            bad += 1
            continue
        if src == "pal":
            print("pal 0x%08x-0x%08x size=%d -> us 0x%08x-0x%08x conf=%.2f method=%s name=%s/%s" % (
                m.pal.start, m.pal.end, m.pal.size, m.us.start, m.us.end, m.conf, m.how, m.pal.name, m.us.name))
        else:
            print("us 0x%08x-0x%08x size=%d -> pal 0x%08x-0x%08x conf=%.2f method=%s name=%s/%s" % (
                m.us.start, m.us.end, m.us.size, m.pal.start, m.pal.end, m.conf, m.how, m.us.name, m.pal.name))
    return bad


PNACH_RE = re.compile(
    r"^(\s*patch\s*=\s*[^,]*,\s*)(EE|IOP)(\s*,\s*)([0-9A-Fa-f]+)(\s*,\s*)([^,\s]+)(\s*,\s*)(\S+)(.*)$",
    re.IGNORECASE)
TOML_ADDR = re.compile(r'(address\s*=\s*")(0x[0-9A-Fa-f]+)(")')


def translate_pnach(world, text, src):
    out = ["// translated %s -> %s by tools/pal_us_map.py" % (src, "us" if src == "pal" else "pal")]
    bad = 0
    for line in text.splitlines():
        m = PNACH_RE.match(line)
        if not m or m.group(2).upper() != "EE":
            out.append(line)
            continue
        addr = int(m.group(4), 16)
        ptype = m.group(6).lower()
        hi = addr & 0xF0000000
        lo = addr & 0x0FFFFFFF
        use = lo if ptype == "extended" and hi else addr
        r = world.map_addr(use, src)
        if not r.ok:
            out.append("// " + line + "  // UNMAPPED " + r.reason)
            bad += 1
            continue
        new = r.dst | hi if ptype == "extended" and hi else r.dst
        out.append("%s%s%s%08x%s%s%s%s%s  // from 0x%08x %s conf=%.2f" % (
            m.group(1), m.group(2), m.group(3), new, m.group(5), m.group(6), m.group(7), m.group(8),
            m.group(9), addr, r.method, r.conf))
    return "\n".join(out) + "\n", bad


def translate_patches_toml(world, text, src):
    lines = text.splitlines()
    start = end = None
    for i, line in enumerate(lines):
        if line.strip() == "[patches]":
            start = i
            continue
        if start is not None and i > start and re.match(r"^\[[A-Za-z]", line):
            end = i
            break
    if start is None:
        block = lines
        prefix = []
    else:
        block = lines[start:end]
        prefix = ["# translated %s -> %s by tools/pal_us_map.py (switch names unchanged)" % (
            src, "us" if src == "pal" else "pal")]
    bad = 0
    out = list(prefix)
    for line in block:
        m = TOML_ADDR.search(line)
        if not m:
            out.append(line)
            continue
        r = world.map_addr(int(m.group(2), 16), src)
        if not r.ok:
            bad += 1
            out.append("# " + line + "  # UNMAPPED " + r.reason)
            continue
        new = line[:m.start()] + '%s0x%08X%s' % (m.group(1), r.dst, m.group(3)) + line[m.end():]
        if "#" not in line:
            new = new.rstrip() + "  # %s conf=%.2f" % (r.method, r.conf)
        out.append(new)
    return "\n".join(out) + "\n", bad


def cmd_patches(world, path, src):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    head = text[:4000]
    if re.search(r"(?i)patch\s*=", head):
        body, bad = translate_pnach(world, text, src)
    else:
        body, bad = translate_patches_toml(world, text, src)
    sys.stdout.write(body)
    return bad


LIT_RE = re.compile(r"\b0x([0-9A-Fa-f]{5,8})u?\b")
FUN_RE = re.compile(r"\bFUN_([0-9A-Fa-f]{8})\b")


def scan_overrides(paths):
    found = defaultdict(list)  # addr -> [(file, line)]
    for path in paths:
        lines = Path(path).read_text(encoding="utf-8", errors="replace").splitlines()
        for n, line in enumerate(lines, 1):
            addrs = set(int(x, 16) for x in LIT_RE.findall(line))
            addrs.update(int(x, 16) for x in FUN_RE.findall(line))
            for a in addrs:
                found[a].append((Path(path).name, n))
    return found


def cmd_overrides(world, paths):
    found = scan_overrides(paths)
    mapped = unmapped = 0
    for addr in sorted(found):
        if addr % 0x10000 == 0 and addr < 0x80000000:
            unmapped += 1
            print("0x%08x UNMAPPED reason=64K-aligned literal (length, RAM window or bound, not a relocated symbol)  %s" % (
                addr, ",".join("%s:%d" % (fn, ln) for fn, ln in found[addr][:4])))
            continue
        r = world.map_addr(addr, "pal")
        where = ",".join("%s:%d" % (fn, ln) for fn, ln in found[addr][:4])
        if len(found[addr]) > 4:
            where += ",+%d" % (len(found[addr]) - 4)
        if r.ok:
            mapped += 1
            print("%s  %s" % (fmt(r), where))
        else:
            unmapped += 1
            print("%s  %s" % (fmt(r), where))
    print("overrides mapped=%d unmapped=%d addresses=%d" % (mapped, unmapped, len(found)), file=sys.stderr)
    return 0


def pnach_ee_words(text):
    rows = []
    section = ""
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            section = s[1:-1]
            continue
        m = PNACH_RE.match(line)
        if not m or m.group(2).upper() != "EE":
            continue
        rows.append((int(m.group(4), 16), m.group(8).lower(), section, m.group(6).lower()))
    return rows


def cmd_check(world):
    """Return (failures, report lines)."""
    lines = []
    fail = 0
    # name invariant
    pn, un = unique_names(world.pal), unique_names(world.us)
    name_bad = 0
    for name, pi in pn.items():
        ui = un.get(name)
        if ui is None or world.pal[pi].size != world.us[ui].size:
            continue
        m = world.fmap.get(world.pal[pi].start)
        if m is None or m.us.start != world.us[ui].start:
            name_bad += 1
    lines.append("name_anchors_disagree=%d" % name_bad)
    if name_bad:
        fail += 1
    hi = sum(1 for m in world.fmap.values() if m.conf >= 0.85)
    mid = sum(1 for m in world.fmap.values() if 0.75 <= m.conf < 0.85)
    low = sum(1 for m in world.fmap.values() if m.conf < 0.75)
    lines.append("functions pal=%d us=%d mapped=%d unmapped_pal=%d unmapped_us=%d clashes=%d conf>=0.85 %d conf>=0.75 %d low %d" % (
        len(world.pal), len(world.us), len(world.fmap),
        len(world.pal) - len(world.fmap), len(world.us) - len(world.by_us), len(world.clashes),
        hi, hi + mid, low))
    world.data()  # one pass over both .text sections; later addr calls reuse it
    # roundtrip functions
    rt = 0
    for m in world.fmap.values():
        back = world.map_addr(m.us.start, "us")
        if not back.ok or back.dst != m.pal.start:
            rt += 1
    lines.append("func_roundtrip_fail=%d" % rt)
    if rt:
        fail += 1
    # listed pairs
    pair_ok = 0
    for pal, us in LISTED_PAIRS:
        r = world.map_addr(pal, "pal")
        mark = r.ok and r.dst == us
        pair_ok += int(mark)
        lines.append("pair %s 0x%08x -> 0x%08x expect 0x%08x %s" % (
            "OK" if mark else "BAD", pal, r.dst or 0, us, r.method if r.ok else r.reason))
        if not mark:
            fail += 1
        else:
            back = world.map_addr(us, "us")
            if not back.ok or back.dst != pal:
                lines.append("  reverse BAD")
                fail += 1
    lines.append("listed_pairs %d/%d" % (pair_ok, len(LISTED_PAIRS)))
    # zip ground truth: pair EE word lines by order, values must match
    zpath = world.pal_root / "external" / "pcsx2" / "resources" / "patches.zip"
    if not zpath.is_file():
        lines.append("pnach_zip MISSING %s" % zpath)
        fail += 1
    else:
        with zipfile.ZipFile(zpath) as z:
            pal_txt = z.read("SCES-50878_2251E14D.pnach").decode("latin-1")
            us_txt = z.read("SLUS-20328_833FE0A4.pnach").decode("latin-1")
        pr, ur = pnach_ee_words(pal_txt), pnach_ee_words(us_txt)
        lines.append("pnach_ee_lines pal=%d us=%d" % (len(pr), len(ur)))
        exact = off4 = other = 0
        pe, ue = world.elfs()
        pbase, ptext = pe.text()
        ubase, utext = ue.text()
        for (pa, pv, ps, pt), (ua, uv, us_, ut) in zip(pr, ur):
            if pv != uv:
                lines.append("value mismatch pal 0x%08x %s us 0x%08x %s" % (pa, pv, ua, uv))
                fail += 1
                continue
            r = world.map_addr(pa, "pal")
            if r.ok and r.dst == ua:
                exact += 1
                lines.append("pnach OK 0x%08x -> 0x%08x %s %s" % (pa, ua, pt, r.method))
            elif r.ok and abs(r.dst - ua) == 4:
                off4 += 1
                def word(buf, base, a):
                    return struct.unpack_from("<I", buf, a - base)[0]
                same_map = word(ptext, pbase, pa) == word(utext, ubase, r.dst)
                same_pnach = word(ptext, pbase, pa) == word(utext, ubase, ua)
                lines.append(
                    "pnach OFF4 pal 0x%08x pnach_us 0x%08x mapped 0x%08x word_eq_mapped=%s word_eq_pnach=%s" % (
                        pa, ua, r.dst, same_map, same_pnach))
                if not (same_map and not same_pnach):
                    fail += 1
            else:
                other += 1
                lines.append("pnach BAD pal 0x%08x us 0x%08x mapped %s" % (
                    pa, ua, fmt(r)))
                fail += 1
        lines.append("pnach_exact=%d off4=%d other=%d" % (exact, off4, other))
        if exact < 7:
            fail += 1
    # documented data
    for pal, us, name in DATA_PAIRS:
        r = world.map_addr(pal, "pal")
        mark = r.ok and r.dst == us
        lines.append("data %s %s 0x%08x -> %s" % ("OK" if mark else "BAD", name, pal, fmt(r)))
        if not mark:
            fail += 1
        else:
            back = world.map_addr(us, "us")
            if not back.ok or back.dst != pal:
                lines.append("  data reverse BAD %s" % fmt(back))
                fail += 1
    lines.append("code_pointer_agree=%d disagree=%d struct_diverged=%d data_anchors=%d" % (
        world.code_agree, world.code_disagree, len(world.struct_bad), len(world.data()["pal"])))
    for pal_a, voted, mapped in world.code_bad:
        lines.append("  code_ref pal 0x%08x voted 0x%08x mapped 0x%08x" % (pal_a, voted, mapped))
    # overrides in the main file: every literal is mapped or has a reason
    path = world.pal_root / "runtime" / "tekken4_overrides.cpp"
    found = scan_overrides([path])
    om = ou = 0
    reasons = Counter()
    for addr in sorted(found):
        if addr % 0x10000 == 0 and addr < 0x80000000:
            ou += 1
            reasons["64K-aligned literal"] += 1
            lines.append("override 0x%08x UNMAPPED reason=64K-aligned literal (length, RAM window or bound, not a relocated symbol)" % addr)
            continue
        r = world.map_addr(addr, "pal")
        if r.ok:
            om += 1
        else:
            ou += 1
            reasons[r.reason.split("(")[0].strip()] += 1
            lines.append("override %s" % fmt(r))
    lines.append("tekken4_overrides mapped=%d unmapped=%d" % (om, ou))
    for reason, n in reasons.most_common():
        lines.append("  unmapped %d %s" % (n, reason))
    # unmapped functions, one line each
    lines.append("unmapped_functions")
    for fn in world.pal:
        if fn.start not in world.fmap:
            lines.append("  0x%08x size=%d %s" % (fn.start, fn.size, fn.name))
    if world.struct_bad:
        lines.append("struct_diverged")
        for m in world.struct_bad:
            lines.append("  0x%08x -> 0x%08x at +0x%x %s" % (
                m.pal.start, m.us.start, m.mismatch, m.pal.name))
    return fail, lines


def default_world(args):
    pal = Path(args.pal_root) if getattr(args, "pal_root", None) else ROOT
    us = Path(args.us_root) if getattr(args, "us_root", None) else us_root()
    return World(pal, us)


def build_parser():
    p = argparse.ArgumentParser(
        prog="pal_us_map.py",
        description="Translate Tekken 4 addresses and instruction patches between the PAL "
                    "SCES-50878 and US SLUS-20328 ELFs. Mappings carry a confidence and a method. "
                    "Patch values and switch= names are not rewritten; only the address moves.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""methods
  name / runN / name+runN   function list alignment (csv confidence)
  insn:<those>              byte offset inside that function
  insn:<those>:shifted      the two copies diverge before this offset
  code-ref:abs|mem|gp       a matched instruction pair computes this data address
  section-delta             between two code-ref anchors that share one delta
  text-gap                  hole between two functions that share one delta

examples
  python -I tools/pal_us_map.py addr 0x2177E0 0x314360
  python -I tools/pal_us_map.py addr 0x216EA0 --from us
  python -I tools/pal_us_map.py func 0x00282808
  python -I tools/pal_us_map.py csv --out config/pal_us_map.csv
  python -I tools/pal_us_map.py patches file.pnach --from pal
  python -I tools/pal_us_map.py patches config/ghidra_export.toml
  python -I tools/pal_us_map.py overrides runtime/tekken4_overrides.cpp
  python -I tools/pal_us_map.py check

overrides treats a 64K-aligned literal below kseg (0x10000, 0x200000, 0x300000)
as a length or debug window and reports it unmapped. addr still maps such a
value when it falls inside a function or a data section. conf in the csv is the
alignment confidence; addr lowers it when the instruction streams diverge.
""",
    )
    p.add_argument("--pal-root", help="PAL tree (default: this repo)")
    p.add_argument("--us-root", help="US tree (default: TEKKEN4_US or ../tekken4-recomp_usa)")
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("addr", help="map one or more addresses")
    a.add_argument("addrs", nargs="+")
    a.add_argument("--from", dest="src", choices=("pal", "us"), default="pal")
    f = sub.add_parser("func", help="map the function that contains an address")
    f.add_argument("addrs", nargs="+")
    f.add_argument("--from", dest="src", choices=("pal", "us"), default="pal")
    c = sub.add_parser("csv", help="write the function map (addresses and sizes only)")
    c.add_argument("--out", default=str(ROOT / "config" / "pal_us_map.csv"))
    t = sub.add_parser("patches", help="translate a .pnach or a [patches] block")
    t.add_argument("path")
    t.add_argument("--from", dest="src", choices=("pal", "us"), default="pal")
    o = sub.add_parser("overrides", help="map addresses in runtime/*_overrides.cpp")
    o.add_argument("paths", nargs="*")
    sub.add_parser("check", help="verify widescreen pairs, data anchors, override coverage")
    return p


def main(argv):
    args = build_parser().parse_args(argv)
    world = default_world(args)
    if args.cmd == "addr":
        return 1 if cmd_addr(world, args.addrs, args.src) else 0
    if args.cmd == "func":
        return 1 if cmd_func(world, args.addrs, args.src) else 0
    if args.cmd == "csv":
        n = write_csv(world, args.out)
        print("wrote %s rows=%d unmapped_pal=%d unmapped_us=%d" % (
            args.out, n, len(world.pal) - n, len(world.us) - len(world.by_us)), file=sys.stderr)
        return 0
    if args.cmd == "patches":
        return 1 if cmd_patches(world, args.path, args.src) else 0
    if args.cmd == "overrides":
        paths = [Path(x) for x in args.paths] if args.paths else sorted((ROOT / "runtime").glob("*_overrides.cpp"))
        if not paths:
            print("no override files", file=sys.stderr)
            return 1
        return cmd_overrides(world, paths)
    if args.cmd == "check":
        fail, lines = cmd_check(world)
        for line in lines:
            print(line)
        print("check_fail=%d" % fail)
        return 1 if fail else 0
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
