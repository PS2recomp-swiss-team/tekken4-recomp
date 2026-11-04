"""Static recompiler for VU microprograms (Tekken 4 port, our own code).

usage: python -I tools/vu/vu_lift.py <out dir> [--vu1 <image.bin|dir>]... [--vu0 <image.bin|dir>]... [--parts N]
                                     [--heads <file>] [--report <file>]

Reads the player's own VU micro memory images (VU1: rebuilt from the ELF by tools/vu1_micro_from_elf.py; VU0: the
same way when present) and writes C++ (vulift_part<k>.cpp) that runs each microprogram natively: every code path from
an entry to the program's end, with the exact engine's pipeline timing worked out here, while generating:

  * every pair's issue cycle (data stalls on VF/VI/ACC lanes, FDIV/EFU/WAITQ/WAITP) relative to its block's entry,
    per "timing context" (what is still in flight when the block starts: lanes, Q, P, MAC/status/clip writers) --
    a block reached with different contexts is generated once per context (worklist over (pc, context));
  * MAC/status/clip flags become visible exactly kFmacLatency cycles after their writer, Q/P when their unit is done,
    so a reader gets the value the engine gives at that cycle (statically resolved, no run-time flag queue);
  * XGKICK uses the engine's own transfer code, advanced lazily to the lifted code's cycle before every VU memory
    write; an XGKICK that must wait for the previous transfer gets its (data-dependent) stall at run time and
    continues in the context aged by that stall;
  * anything not handled (JR to a target not seen here, the cycle budget close, ...) hands the exact pipeline state
    to the exact engine at a pair boundary (VuLiftAccess::exportState).

The reference is the runtime's exact engine (ps2xRuntime/src/lib/vu: decode rules in vu_isa.py, arithmetic in
ps2_vu_lift_rt.h); PS2X_VULIFT_VERIFY=<runs> compares both bit for bit in the running game. The images and the C++
written here are game code: they stay in the build folder and are never committed or published.
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vu_isa import (FMAC_LAT, ACC_FWD_LAT, P_FDIV, P_EFU, P_BRANCH, P_XGKICK, Pair, lane, upper_special,
                    lower_special, imm11)  # noqa: E402

REV4 = [0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15]
MAX_CTX_PER_PC = 48
MAX_FLAGS = 8


class Unliftable(Exception):
    pass


def fnv32(data):
    h = 2166136261
    for b in data:
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return h


def lane_vf(r, c):
    return r * 4 + c


def lane_vi(r):
    return 128 + r


def lane_acc(c):
    return 144 + c


def comps(lanes):
    return [c for c in range(4) if lanes & lane(c)]


class Ctx:
    """Timing state at a block head; every cycle value is relative to the block's entry cycle E (= 0)."""
    __slots__ = ('lanes', 'fdiv', 'efu', 'efures', 'flags', 'kick', 'bk')

    def __init__(self):
        self.lanes = {}        # lane -> ready (> 0)
        self.fdiv = None       # ready of the pending Q (value in qn / qdi)
        self.efu = [None, None]  # ready of the pending P in slot k (value in pn<k>)
        self.efures = 0        # EFU unit free again
        self.flags = []        # pending flag writers, oldest first: (ready, kind 'f'|'c'|'s', writes) -> slot = index
        self.kick = 0          # 1: an XGKICK transfer may be running
        self.bk = 0            # branch backup register (old value in bkv)

    def key(self):
        return (tuple(sorted(self.lanes.items())), self.fdiv, tuple(self.efu), self.efures,
                tuple((r, k, w) for r, k, w in self.flags), self.kick, self.bk)

    def max_rel(self):
        m = 0
        for v in self.lanes.values():
            m = max(m, v)
        if self.fdiv is not None:
            m = max(m, self.fdiv)
        for v in self.efu:
            if v is not None:
                m = max(m, v)
        m = max(m, self.efures)
        for r, _k, _w in self.flags:
            m = max(m, r)
        return m


class Group:
    """One generated function: a set of entries whose reachable code overlaps."""

    def __init__(self, unit, code, entries, jr_targets, name):
        self.unit = unit
        self.code = code
        self.mask = 0x3FFF if unit == 1 else 0xFFF
        self.size = len(code)
        self.entries = sorted(entries)
        self.jr_targets = jr_targets
        self.name = name
        self.queued = unit == 0  # VU0 runs with queued register writes (setDirectRegisterWrites is VU1 only)
        self.pairs = {}
        self.blocks = {}       # (pc, ctxkey, kickwait) -> label
        self.order = []        # (pc, ctx, kickwait, label) in creation order
        self.covered = set()
        self.lines = []
        self.nlabel = 0
        self.backtargets = set()  # labels a backward branch reaches (+ XGKICK waits): they check the cycle budget
        self.block_len = {}

    def pair(self, pc):
        if pc not in self.pairs:
            if pc + 8 > self.size:
                raise Unliftable(f'pc {pc:#x} outside micro memory')
            lo, up = struct.unpack_from('<II', self.code, pc)
            self.pairs[pc] = Pair(pc, lo, up, vu1=self.unit == 1)
        return self.pairs[pc]

    def label(self, pc, ctx, kickwait=False):
        k = (pc, ctx.key(), kickwait)
        if k not in self.blocks:
            n = sum(1 for b in self.blocks if b[0] == pc)
            if n >= MAX_CTX_PER_PC:
                raise Unliftable(f'too many timing contexts at {pc:#x}')
            self.nlabel += 1
            lab = f'L{pc:04x}_{self.nlabel}'
            self.blocks[k] = lab
            self.order.append((pc, copy_ctx(ctx), kickwait, lab))
        return self.blocks[k]

    def generate(self):
        start = Ctx()
        heads = [(e, self.label(e, start)) for e in self.entries]
        body = []
        tails = []
        done = 0
        while done < len(self.order):
            pc, ctx, kickwait, lab = self.order[done]
            done += 1
            bg = BlockGen(self, pc, ctx, kickwait, lab)
            bg.run()
            body.extend(bg.out)
            self.block_len[lab] = bg.max_len
            if kickwait:
                self.backtargets.add(lab)
        # Loop heads and XGKICK waits check the cycle budget and hand over at their head. Between two checks a run
        # passes every block at most once (each cycle of blocks has a backward branch), so "the function's whole length
        # plus the longest XGKICK transfer (4096 qwords, 2 cycles each)" bounds it: the engine never reaches its budget
        # inside lifted code, and a hand-over at a block head is exact wherever it happens.
        margin = sum(self.block_len.values()) + 8200
        body = [l for l in body if not (l.startswith('/*BUDGET ') and l.split()[1] not in self.backtargets)]
        body = [l.split('*/', 1)[1].replace('MARGIN', str(margin)) if l.startswith('/*BUDGET ') else l for l in body]
        for pc, ctx, kickwait, lab in self.order:
            if lab in self.backtargets:
                hb = BlockGen(self, pc, ctx, kickwait, lab)
                tails.append(f'B{lab}:')
                tails.extend('    ' + l for l in hb.export_lines(pc, 1))
        fn = f'vl_{self.name}'
        o = self.lines
        o.append(f'static uint32_t {fn}(VuLiftCtx &X, uint32_t entry)')
        o.append('{')
        o.append('    VU1State &S = *X.s;')
        o.append('    float (*VF)[4] = S.vf;')
        o.append('    ' + ' '.join(f'int32_t v{r} = S.vi[{r}];' for r in range(1, 16)))
        o.append('    float q = S.q, p = S.p, ri = S.i;')
        o.append('    uint32_t mac = S.mac, status = S.status, clip = S.clip, wclip = S.clip;')
        for k in range(SLOTS):
            o.append(f'    uint32_t fm{k} = 0, fc{k} = 0, fx{k} = 0, fk{k} = 0;')
        o.append('    float qn = 0.f, pn0 = 0.f, pn1 = 0.f; uint32_t qdi = 0, jtv = 0; int32_t bkv = 0; bool brc = false;')
        o.append('    uint64_t kc = 0, E = X.c0;')
        o.append('    switch (entry)')
        o.append('    {')
        for e, lab in heads:
            o.append(f'    case 0x{e:x}: goto {lab};')
        o.append('    default: return kVuLiftNoEntry;')
        o.append('    }')
        o.extend(body)
        o.extend(tails)
        o.append('}')
        return fn


SLOTS = MAX_FLAGS + 8


def copy_ctx(c):
    n = Ctx()
    n.lanes = dict(c.lanes)
    n.fdiv = c.fdiv
    n.efu = list(c.efu)
    n.efures = c.efures
    n.flags = list(c.flags)
    n.kick = c.kick
    n.bk = c.bk
    return n


def vfp(r):
    return f'VF[{r}]'


def vi(r):
    return '0' if r == 0 else f'v{r}'


class BlockGen:
    """One (pc, context) block: straight-line pairs until a branch + delay slot, a program end or an XGKICK that may
    have to wait. Cycle values are relative to the block's entry cycle E; self.now = the engine's m_cycle when the next
    pair's step begins (prologue)."""

    def __init__(self, g, pc, ctx, kickwait, lab):
        self.g = g
        self.out = []
        self.pc = pc
        self.kickwait = kickwait
        self.lab = lab
        self.now = 0
        self.flags = [dict(ready=r, kind=k, slot=i, w=w) for i, (r, k, w) in enumerate(ctx.flags)]
        self.lanes = dict(ctx.lanes)
        self.fdiv = ctx.fdiv
        self.efu = list(ctx.efu)
        self.efures = ctx.efures
        self.kick = ctx.kick
        self.bk = ctx.bk
        self.max_len = 1

    def clone(self):
        b = BlockGen.__new__(BlockGen)
        b.g, b.out, b.pc, b.kickwait, b.lab, b.now = self.g, [], self.pc, self.kickwait, self.lab, self.now
        b.flags = [dict(f) for f in self.flags]
        b.lanes, b.fdiv, b.efu, b.efures = dict(self.lanes), self.fdiv, list(self.efu), self.efures
        b.kick, b.bk, b.max_len = self.kick, self.bk, self.max_len
        return b

    def e(self, s):
        self.out.append('    ' + s)

    # --- pending state -------------------------------------------------------------------------------------------------
    def free_slot(self):
        used = {f['slot'] for f in self.flags}
        for k in range(SLOTS):
            if k not in used:
                return k
        raise Unliftable('flag slots exhausted')

    def new_flag(self, kind, t, w=(1, 1, 0)):
        if len(self.flags) >= MAX_FLAGS:
            raise Unliftable('more than 8 flag writers in flight')
        s = self.free_slot()
        self.flags.append(dict(ready=t + FMAC_LAT, kind=kind, slot=s, w=w))
        return s

    def commit_until(self, t):
        """Everything with ready <= t becomes visible, in the engine's order: by cycle; within a cycle the flags (in
        issue order), then Q, then P (slot order) -- commitReadyPipelines' order."""
        events = []
        for n, f in enumerate(self.flags):
            if f['ready'] <= t:
                events.append((f['ready'], 0, n, f))
        if self.fdiv is not None and self.fdiv <= t:
            events.append((self.fdiv, 1, 0, None))
        for k in range(2):
            if self.efu[k] is not None and self.efu[k] <= t:
                events.append((self.efu[k], 2, k, None))
        events.sort(key=lambda x: (x[0], x[1], x[2]))
        for _r, typ, k, f in events:
            if typ == 0:
                s = f['slot']
                wm, ws, wc = f['w']
                if f['kind'] == 'f':
                    if wm:
                        self.e(f'mac = fm{s};')
                    if ws:
                        self.e(f'status = vl::statusFmac(status, fc{s}, fx{s});')
                elif f['kind'] == 'c':
                    if wc:
                        self.e(f'clip = fk{s};')
                elif f['kind'] == 's' and ws:  # FSSET
                    self.e(f'status = (status & 0x03Fu) | (fk{s} & 0xFC0u);')
                self.flags.remove(f)
            elif typ == 1:
                self.e('q = qn; status = vl::statusDiv(status, qdi);')
                self.fdiv = None
            else:
                self.e(f'p = pn{k};')
                self.efu[k] = None

    def prepare_leave(self):
        """Commit what is due and move the pending flag values into slots 0..n-1 (the successor's layout). Once."""
        self.commit_until(self.now)
        moves = [(i, f['slot']) for i, f in enumerate(self.flags) if f['slot'] != i]
        if moves:
            a = [f'const uint32_t t_m{i} = fm{s}, t_c{i} = fc{s}, t_x{i} = fx{s}, t_k{i} = fk{s};' for i, s in moves]
            b = [f'fm{i} = t_m{i}; fc{i} = t_c{i}; fx{i} = t_x{i}; fk{i} = t_k{i};' for i, _s in moves]
            self.e('{ ' + ' '.join(a + b) + ' }')
        for i, f in enumerate(self.flags):
            f['slot'] = i

    def ctx_now(self):
        c = Ctx()
        t = self.now
        c.lanes = {k: v - t for k, v in self.lanes.items() if v - t > 0}
        c.fdiv = self.fdiv - t if self.fdiv is not None and self.fdiv - t > 0 else None
        c.efu = [v - t if v is not None and v - t > 0 else None for v in self.efu]
        c.efures = max(0, self.efures - t)
        c.flags = [(f['ready'] - t, f['kind'], f['w']) for f in self.flags]
        c.kick = self.kick
        c.bk = self.bk
        return c

    def jump(self, pc, kickwait=False, from_pc=None):
        """'goto' to the block at pc with the current context (after prepare_leave)."""
        lab = self.g.label(pc, self.ctx_now(), kickwait)
        if from_pc is not None and pc <= from_pc:
            self.g.backtargets.add(lab)
        return f'E += {self.now}; goto {lab};' if self.now else f'goto {lab};'

    def writeback(self):
        return [' '.join(f'S.vi[{r}] = v{r};' for r in range(1, 16)),
                'S.q = q; S.p = p; S.i = ri; S.mac = mac; S.status = status; S.clip = clip;']

    def export_lines(self, pc, why, pc_expr=None):
        """Hand the state at the start of the pair at pc (cycle E + now, prologue not run) to the exact engine."""
        b = self.clone()
        b.commit_until(b.now)
        t = b.now
        lines = ['{'] + ['    ' + l for l in b.out] + ['    ' + l for l in b.writeback()]
        lines.append('    for (uint64_t &l : X.lane) l = 0;')
        for k, v in sorted(b.lanes.items()):
            if v - t > 0:
                lines.append(f'    X.lane[{k}] = E + {v};')
        if b.fdiv is not None:
            lines.append(f'    X.qValid = true; X.qReady = E + {b.fdiv}; X.qValue = qn; X.qDi = qdi;')
        for k in range(2):
            if b.efu[k] is not None:
                lines.append(f'    X.pValid[{k}] = true; X.pReady[{k}] = E + {b.efu[k]}; X.pValue[{k}] = pn{k};')
        if b.efures - t > 0:
            lines.append(f'    X.efuRes = E + {b.efures};')
        for i, f in enumerate(b.flags):
            s = f['slot']
            wm, ws, wc = f['w']
            if f['kind'] == 's':
                raise Unliftable('FSSET in flight at a hand-over')
            lines.append(f'    X.flags[{i}] = VuLiftFlagOut{{E + {f["ready"]}, fm{s}, fc{s}, fx{s}, fk{s}, '
                         f'{int(wm)}, {int(ws)}, {int(wc)}}};')
        lines.append(f'    X.flagCount = {len(b.flags)};')
        if b.bk:
            lines.append(f'    X.branchBackupReg = {b.bk}; X.branchBackupValue = bkv;')
        pcs = pc_expr or f'0x{pc:x}u'
        lines.append(f'    X.workingClip = wclip; X.bailPc = {pcs}; X.bailWhy = {why};')
        if b.kick:
            lines.append(f'    VuLiftAccess::kickAdvance(*X.vu, E + {t}, kc);')
        lines.append(f'    VuLiftAccess::exportState(*X.vu, X, E + {t}, {pcs});')
        lines.append('    return kVuLiftBailed;')
        lines.append('}')
        return lines

    # --- the block -----------------------------------------------------------------------------------------------------
    def run(self):
        g = self.g
        self.out.append(f'{self.lab}:')
        self.out.append('{')
        budget_at = len(self.out)
        self.out.append(None)
        pc = self.pc
        first = True
        pending_branch = None
        ebit_seen = False
        count = 0
        while True:
            count += 1
            if count > 4096:
                raise Unliftable(f'no branch or end after {self.pc:#x}')
            p = g.pair(pc)
            g.covered.add(pc)
            if p.reserved:
                raise Unliftable(f'reserved instruction at {pc:#x}')
            if p.dbit or p.tbit:
                raise Unliftable(f'D/T bit at {pc:#x}')
            is_kick = not p.ibit and p.lu.pipeline == P_XGKICK
            if is_kick and self.kick:
                if not (first and self.kickwait):
                    if pending_branch is not None or ebit_seen:
                        raise Unliftable(f'XGKICK that may wait, in a delay slot at {pc:#x}')
                    self.prepare_leave()
                    self.e(self.jump(pc, kickwait=True))
                    break
                self.kick_wait(p)
                break
            issue = self.ready_of(p)
            self.commit_until(issue)
            self.out.append('    {')
            self.pair_code(p, issue)
            self.out.append('    }')
            self.now = issue + 1
            self.max_len = self.now
            first = False
            if ebit_seen:
                if p.is_branch():
                    raise Unliftable(f'branch after the E bit at {pc:#x}')
                self.end_program((pc + 8) if pc + 8 < g.size else 0)
                break
            if pending_branch is not None:
                if p.is_branch() or p.ebit:
                    raise Unliftable(f'branch/E bit in a delay slot at {pc:#x}')
                self.after_branch(pending_branch, pc)
                break
            if p.ebit:
                if p.is_branch():
                    raise Unliftable(f'E bit on a branch at {pc:#x}')
                ebit_seen = True
            elif p.is_branch():
                pending_branch = self.branch_info
            pc = pc + 8 if pc + 8 < g.size else 0
        self.out[budget_at] = f'/*BUDGET {self.lab} */    if (E + MARGIN >= X.budgetEnd) goto B{self.lab};'
        self.out.append('}')

    def ready_of(self, p):
        """calculatePairReadyCycle (the XGKICK rule apart: see kick_wait)."""
        r = self.now
        for us in (p.uu, p.lu):
            for reg, lanes in us.vf_read:
                for c in comps(lanes):
                    r = max(r, self.lanes.get(lane_vf(reg, c), 0))
            for reg in range(1, 16):
                if us.vi_read & (1 << reg):
                    r = max(r, self.lanes.get(lane_vi(reg), 0))
            for c in comps(us.acc_read):
                r = max(r, self.lanes.get(lane_acc(c), 0))
        lu = p.lu
        if lu.pipeline == P_FDIV and self.fdiv is not None:
            r = max(r, self.fdiv)
        if lu.pipeline == P_EFU:
            r = max(r, self.efures)
        if lu.wait_q and self.fdiv is not None:
            r = max(r, self.fdiv)
        if lu.wait_p:
            for v in self.efu:
                if v is not None:
                    r = max(r, v)
        return r

    def kick_wait(self, p):
        """First pair is an XGKICK while the transfer before may still run: the engine stalls until it is done, at a
        cycle that depends on the packet (run time). Continue in the context aged by that stall."""
        r0 = self.ready_of(p)
        base = self.clone()
        base.kick = 0
        maxrel = 0
        for v in list(base.lanes.values()) + [f['ready'] for f in base.flags] + \
                ([base.fdiv] if base.fdiv is not None else []) + [v for v in base.efu if v is not None] + [base.efures]:
            maxrel = max(maxrel, v)
        self.e('{')
        self.e('    const uint64_t ke = VuLiftAccess::kickFinish(*X.vu, kc);')
        self.e(f'    if (ke <= E + {r0}) goto {self.g.label(self.pc, base.ctx_now())};')
        self.e('    const uint64_t A = ke - E;')
        self.e('    switch (A)')
        self.e('    {')
        hi = max(maxrel, r0 + 1)
        for a in range(r0 + 1, hi + 1):
            b = base.clone()
            b.now = a
            b.prepare_leave()
            lab = self.g.label(self.pc, b.ctx_now())
            body = ' '.join(l.strip() for l in b.out)
            if a < hi:
                self.e(f'    case {a}: {{ {body} E = ke; goto {lab}; }}')
            else:
                self.e(f'    default: {{ {body} E = ke; goto {lab}; }}')
        self.e('    }')
        self.e('}')
        self.max_len = r0 + 1

    # --- pairs ---------------------------------------------------------------------------------------------------------
    def pair_code(self, p, t):
        self.e(f'// {p.pc:04x}: {p.upper:08x} {p.lower:08x} @{t}')
        self.wrote_vf0 = False
        self.shadow_store = None
        old_bk = self.bk
        self.branch_info = None
        if not p.upper_nop:
            self.upper_code(p, t)
        if p.ibit:
            self.e(f'ri = vl::nrmf(vl::bitsf(0x{p.lower:08x}u));')
        else:
            self.lower_code(p, t, old_bk)
        if self.shadow_store is not None:
            self.e(self.shadow_store)
        if self.wrote_vf0:
            self.e('_mm_storeu_ps(VF[0], _mm_setr_ps(0.f, 0.f, 0.f, 1.f));')
        # markPairWrites
        lu, uu = p.lu, p.uu
        reg, lanes = lu.vf_write
        if reg and p.suppressed != reg:
            lat = lu.vf_latency or lu.latency
            for c in comps(lanes):
                self.lanes[lane_vf(reg, c)] = t + lat
        reg, lanes = uu.vf_write
        if reg:
            lat = uu.vf_latency or uu.latency
            for c in comps(lanes):
                self.lanes[lane_vf(reg, c)] = t + lat
        for r in range(1, 16):
            if lu.vi_write & (1 << r):
                self.lanes[lane_vi(r)] = t + (lu.vi_latency or lu.latency)
        for c in comps(uu.acc_write):
            self.lanes[lane_acc(c)] = t + ACC_FWD_LAT
        # the branch backup is valid for the next pair only
        self.bk = 0
        w = lu.vi_write & 0xFFFE
        if not p.ibit and w and lu.delays_branch:
            self.bk = (w & -w).bit_length() - 1
        if self.g.queued:
            self.check_queued(p, t)

    def check_queued(self, p, t):
        """VU0 (queued writes): a lane read while its write is in flight gives the old value. The usage sets the stall
        rule uses cover every lane the semantics read except OPMSUB/OPMULA's cross lanes of fs: refuse those."""
        u = p.upper
        op = u & 0x3F
        if not (op == 0x2E or (op >= 0x3C and upper_special(u) == 0x2E)):
            return
        dest = (u >> 21) & 0xF
        fs = (u >> 11) & 0x1F
        cl = [1, 2, 0, 3]
        for c in comps(dest):
            if self.lanes.get(lane_vf(fs, cl[c]), 0) > t:
                raise Unliftable(f'OPMSUB/OPMULA reads a lane in flight at {p.pc:#x} (queued writes)')

    def upper_store(self, p, to, M, val):
        """Writes the upper op's result; with a shadowed register the pair's lower op sees the old value first."""
        if M == 0:
            return
        if to == 'acc':
            self.e(f'vl::st<{M}>(S.acc, {val});')
            return
        if to == 0:
            self.wrote_vf0 = True
        if p.shadow and p.shadow == to:
            self.e(f'const __m128 shv = _mm_blend_ps(vl::ld({vfp(to)}), {val}, {M});')
            self.shadow_store = f'_mm_storeu_ps({vfp(to)}, shv);'
            return
        self.e(f'vl::st<{M}>({vfp(to)}, {val});')

    def upper_code(self, p, t):
        u = p.upper
        op = u & 0x3F
        dest = (u >> 21) & 0xF
        M = REV4[dest]
        fs, ft, fd = (u >> 11) & 0x1F, (u >> 16) & 0x1F, (u >> 6) & 0x1F
        bcc = None
        to = fd
        if op < 0x3C:
            if op <= 0x1B:
                kind = ['add', 'sub', 'madd', 'msub', 'max', 'mini', 'mul'][op >> 2]
                src, bcc = 'bc', op & 3
            else:
                table = {0x1C: ('mul', 'q'), 0x1D: ('max', 'i'), 0x1E: ('mul', 'i'), 0x1F: ('mini', 'i'),
                         0x20: ('add', 'q'), 0x21: ('madd', 'q'), 0x22: ('add', 'i'), 0x23: ('madd', 'i'),
                         0x24: ('sub', 'q'), 0x25: ('msub', 'q'), 0x26: ('sub', 'i'), 0x27: ('msub', 'i'),
                         0x28: ('add', 'v'), 0x29: ('madd', 'v'), 0x2A: ('mul', 'v'), 0x2B: ('max', 'v'),
                         0x2C: ('sub', 'v'), 0x2D: ('msub', 'v'), 0x2E: ('opmsub', 'v'), 0x2F: ('mini', 'v')}
                if op not in table:
                    raise Unliftable(f'upper op {op:#x}')
                kind, src = table[op]
        else:
            sp = upper_special(u)
            to = 'acc'
            if sp <= 0x0F:
                kind = ['add', 'sub', 'madd', 'msub'][sp >> 2]
                src, bcc = 'bc', sp & 3
            elif 0x18 <= sp <= 0x1B:
                kind, src, bcc = 'mul', 'bc', sp & 3
            elif 0x10 <= sp <= 0x13:
                self.upper_store(p, ft, M, f'vl::itof<{[0, 4, 12, 15][sp & 3]}>(vl::ld({vfp(fs)}))')
                return
            elif 0x14 <= sp <= 0x17:
                self.upper_store(p, ft, M, f'vl::ftoi<{[0, 4, 12, 15][sp & 3]}>(vl::nrm(vl::ld({vfp(fs)})))')
                return
            elif sp == 0x1D:
                self.upper_store(p, ft, M,
                                 f'_mm_and_ps(vl::nrm(vl::ld({vfp(fs)})), _mm_castsi128_ps(_mm_set1_epi32(0x7FFFFFFF)))')
                return
            elif sp == 0x1F:
                s = self.new_flag('c', t, (0, 0, 1))
                self.e(f'wclip = ((wclip << 6) | vl::clipFlags({vfp(fs)}, {vfp(ft)})) & 0xFFFFFFu; fk{s} = wclip;')
                return
            else:
                table = {0x1C: ('mul', 'q'), 0x1E: ('mul', 'i'), 0x20: ('add', 'q'), 0x21: ('madd', 'q'),
                         0x22: ('add', 'i'), 0x23: ('madd', 'i'), 0x24: ('sub', 'q'), 0x25: ('msub', 'q'),
                         0x26: ('sub', 'i'), 0x27: ('msub', 'i'), 0x28: ('add', 'v'), 0x29: ('madd', 'v'),
                         0x2A: ('mul', 'v'), 0x2C: ('sub', 'v'), 0x2D: ('msub', 'v'), 0x2E: ('opmula', 'v')}
                if sp not in table:
                    raise Unliftable(f'upper special {sp:#x}')
                kind, src = table[sp]
        a = f'vl::nrm(vl::ld({vfp(fs)}))'
        if src == 'bc':
            b = f'vl::bc<{bcc}>(vl::nrm(vl::ld({vfp(ft)})))'
        elif src == 'q':
            b = '_mm_set1_ps(vl::nrmf(q))'
        elif src == 'i':
            b = '_mm_set1_ps(vl::nrmf(ri))'
        else:
            b = f'vl::nrm(vl::ld({vfp(ft)}))'
        if kind in ('max', 'mini'):
            self.upper_store(p, to, M, f'{"_mm_max_ps" if kind == "max" else "_mm_min_ps"}({a}, {b})')
            return
        if dest == 0:
            return  # an FMAC without DEST lanes writes nothing and pushes no flag writer
        L = [f'const __m128 a = {a};', f'const __m128 b = {b};']
        if kind in ('madd', 'msub', 'opmsub'):
            L.append('const __m128 c = vl::nrm(vl::ld(S.acc));')
        else:
            L.append('const __m128 c = _mm_setzero_ps();')
        K = {'add': 'kAdd', 'sub': 'kSub', 'mul': 'kMul', 'madd': 'kMadd', 'msub': 'kMsub', 'opmsub': 'kOpmsub',
             'opmula': 'kOpmula'}[kind]
        fa, fb = 'a', 'b'
        if kind in ('opmsub', 'opmula'):
            L.append('const __m128 aa = vl::crossL(a), bb = vl::crossR(b);')
            L.append('const __m128 pr = _mm_mul_ps(aa, bb);')
            L.append('__m128 r = _mm_blend_ps(' + ('_mm_sub_ps(c, pr)' if kind == 'opmsub' else 'pr') +
                     ', _mm_setzero_ps(), 8);')
            fa, fb = 'aa', 'bb'
        elif kind == 'add':
            L.append('__m128 r = _mm_add_ps(a, b); const __m128 pr = r;')
        elif kind == 'sub':
            L.append('__m128 r = _mm_sub_ps(a, b); const __m128 pr = r;')
        elif kind == 'mul':
            L.append('__m128 r = _mm_mul_ps(a, b); const __m128 pr = r;')
        elif kind == 'madd':
            L.append('const __m128 pr = _mm_mul_ps(a, b); __m128 r = _mm_add_ps(c, pr);')
        else:
            L.append('const __m128 pr = _mm_mul_ps(a, b); __m128 r = _mm_sub_ps(c, pr);')
        s = self.new_flag('f', t)
        L.append(f'r = vl::fin<vl::{K}, {M}>(r, {fa}, {fb}, c, pr, fm{s}, fc{s}, fx{s});')
        L.append('uv = r;')
        self.e('__m128 uv;')
        self.e('{ ' + ' '.join(L) + ' }')
        self.upper_store(p, to, M, 'uv')

    def lower_vf(self, reg, M, expr):
        if M == 0:
            return
        if reg == 0:
            self.wrote_vf0 = True
        self.e(f'vl::st<{M}>({vfp(reg)}, {expr});')

    def catchup(self, t):
        if self.kick:
            self.e(f'VuLiftAccess::kickAdvance(*X.vu, E + {t}, kc);')

    def set_vi(self, r, expr, backup):
        """The lower op's VI write (int16 as at the end of stepPair); the old value for the branch quirk."""
        if r == 0:
            return
        if backup:
            self.e(f'bkv = v{r};')
        self.e(f'v{r} = static_cast<int16_t>({expr});')

    def bvi(self, r, old_bk):
        """VI as a conditional branch reads it (readBranchVi)."""
        if r == 0:
            return '0'
        return 'bkv' if old_bk == r else f'v{r}'

    def lower_code(self, p, t, old_bk):
        g = self.g
        lo = p.lower
        if lo == 0 or lo == 0x8000033C:
            return
        op = (lo >> 25) & 0x7F
        vft, vfs = (lo >> 16) & 0x1F, (lo >> 11) & 0x1F
        vit, vis = (lo >> 16) & 0xF, (lo >> 11) & 0xF
        dest = (lo >> 21) & 0xF
        M = REV4[dest]
        delays = bool(p.lu.delays_branch)
        imm = imm11(lo)
        e = self.e
        if op == 0x00:  # LQ
            self.lower_vf(vft, M, f'vl::ldq(X, vl::addr(X, {vi(vis)} + {imm}))')
        elif op == 0x01:  # SQ
            self.catchup(t)
            if M:
                e(f'vl::stq<{M}>(X, vl::addr(X, {vi(vit)} + {imm}), vl::ld({vfp(vfs)}));')
        elif op == 0x04:  # ILW
            comp = 0 if dest & 8 else 1 if dest & 4 else 2 if dest & 2 else 3
            self.set_vi(vit, f'vl::ldw(X, vl::addr(X, {vi(vis)} + {imm}), {comp})', False)
        elif op == 0x05:  # ISW
            self.catchup(t)
            if dest:
                e(f'vl::stw<{dest}>(X, vl::addr(X, {vi(vis)} + {imm}), {vi(vit)});')
        elif op in (0x08, 0x09):  # IADDIU / ISUBIU: unsigned 15-bit immediate
            u15 = (lo & 0x7FF) | ((lo >> 10) & 0x7800)
            self.set_vi(vit, f'{vi(vis)} {"+" if op == 0x08 else "-"} {u15}', delays)
        elif op in (0x10, 0x12, 0x13):  # FCEQ / FCAND / FCOR
            i24 = lo & 0xFFFFFF
            cond = {0x10: f'(clip & 0xFFFFFFu) == 0x{i24:x}u', 0x12: f'(clip & 0x{i24:x}u) != 0u',
                    0x13: f'(clip | 0x{i24:x}u) == 0xFFFFFFu'}[op]
            self.set_vi(1, f'({cond}) ? 1 : 0', False)
        elif op == 0x11:  # FCSET: cancels this cycle's CLIP writer
            for f in self.flags:
                if f['ready'] == t + FMAC_LAT and f['kind'] == 'c':
                    f['w'] = (f['w'][0], f['w'][1], 0)
            s = self.new_flag('c', t, (0, 0, 1))
            e(f'wclip = 0x{lo & 0xFFFFFF:x}u; fk{s} = wclip;')
        elif op in (0x14, 0x16, 0x17):  # FSEQ / FSAND / FSOR
            i12 = (((lo >> 21) & 1) << 11) | (lo & 0x7FF)
            ex = {0x14: f'((status & 0xFFFu) == 0x{i12:x}u) ? 1u : 0u', 0x16: f'(status & 0xFFFu) & 0x{i12:x}u',
                  0x17: f'(status & 0xFFFu) | 0x{i12:x}u'}[op]
            self.set_vi(vit, f'static_cast<int32_t>({ex})', False)
        elif op == 0x15:  # FSSET: cancels this cycle's status writer
            i12 = (((lo >> 21) & 1) << 11) | (lo & 0x7FF)
            for f in self.flags:
                if f['ready'] == t + FMAC_LAT and f['kind'] == 'f':
                    f['w'] = (f['w'][0], 0, f['w'][2])
            s = self.new_flag('s', t, (0, 1, 0))
            e(f'fk{s} = 0x{i12 & 0xFC0:x}u;')
        elif op in (0x18, 0x1A, 0x1B):  # FMEQ / FMAND / FMOR
            m16 = f'static_cast<uint32_t>(static_cast<uint16_t>({vi(vis)}))'
            ex = {0x18: f'((mac & 0xFFFFu) == {m16}) ? 1 : 0', 0x1A: f'static_cast<int32_t>(mac & {m16})',
                  0x1B: f'static_cast<int32_t>(mac | {m16})'}[op]
            self.set_vi(vit, ex, False)
        elif op == 0x1C:  # FCGET
            self.set_vi(vit, 'static_cast<int32_t>(clip & 0x0FFFu)', False)
        elif op in (0x20, 0x21):  # B / BAL
            if op == 0x21:
                self.set_vi(vit, f'{(p.pc + 16) // 8}', False)
            self.branch_info = ('b', (p.pc + 8 + imm * 8) & g.mask)
        elif op in (0x24, 0x25):  # JR / JALR read the current VI
            e(f'jtv = (static_cast<uint32_t>(static_cast<uint16_t>({vi(vis)})) * 8u) & 0x{g.mask:x}u;')
            if op == 0x25:
                self.set_vi(vit, f'{(p.pc + 16) // 8}', False)
            self.branch_info = ('j', p.pc)
        elif op in (0x28, 0x29, 0x2C, 0x2D, 0x2E, 0x2F):
            a = f'static_cast<int16_t>({self.bvi(vis, old_bk)})'
            b = f'static_cast<int16_t>({self.bvi(vit, old_bk)})'
            cond = {0x28: f'{a} == {b}', 0x29: f'{a} != {b}', 0x2C: f'{a} < 0', 0x2D: f'{a} > 0', 0x2E: f'{a} <= 0',
                    0x2F: f'{a} >= 0'}[op]
            e(f'brc = {cond};')
            self.branch_info = ('c', (p.pc + 8 + imm * 8) & g.mask)
        elif op == 0x40:
            self.lower40(p, t, lo)
        else:
            raise Unliftable(f'lower op {op:#x} at {p.pc:#x}')

    def lower40(self, p, t, lo):
        e = self.e
        d = lo & 0x3F
        vft, vfs = (lo >> 16) & 0x1F, (lo >> 11) & 0x1F
        vit, vis, vid = (lo >> 16) & 0xF, (lo >> 11) & 0xF, (lo >> 6) & 0xF
        dest = (lo >> 21) & 0xF
        M = REV4[dest]
        delays = bool(p.lu.delays_branch)
        if d in (0x30, 0x31, 0x34, 0x35):  # IADD / ISUB / IAND / IOR
            opc = {0x30: '+', 0x31: '-', 0x34: '&', 0x35: '|'}[d]
            self.set_vi(vid, f'{vi(vis)} {opc} {vi(vit)}', delays)
            return
        if d == 0x32:  # IADDI
            i5 = (lo >> 6) & 0x1F
            i5 = i5 - 32 if i5 & 0x10 else i5
            self.set_vi(vit, f'{vi(vis)} + ({i5})', delays)
            return
        if d < 0x3C:
            raise Unliftable(f'lower op {lo:#x}')
        sp = lower_special(lo)
        fsf, ftf = (lo >> 21) & 3, (lo >> 23) & 3
        if sp == 0x30:  # MOVE
            self.lower_vf(vft, M, f'vl::ld({vfp(vfs)})')
        elif sp == 0x31:  # MR32
            self.lower_vf(vft, M, f'_mm_shuffle_ps(vl::ld({vfp(vfs)}), vl::ld({vfp(vfs)}), _MM_SHUFFLE(0, 3, 2, 1))')
        elif sp == 0x34:  # LQI
            self.lower_vf(vft, M, f'vl::ldq(X, vl::addr(X, static_cast<uint16_t>({vi(vis)})))')
            self.set_vi(vis, f'{vi(vis)} + 1', delays)
        elif sp == 0x35:  # SQI
            self.catchup(t)
            if M:
                e(f'vl::stq<{M}>(X, vl::addr(X, static_cast<uint16_t>({vi(vit)})), vl::ld({vfp(vfs)}));')
            self.set_vi(vit, f'{vi(vit)} + 1', delays)
        elif sp == 0x36:  # LQD
            self.set_vi(vis, f'{vi(vis)} - 1', delays)
            self.lower_vf(vft, M, f'vl::ldq(X, vl::addr(X, static_cast<uint16_t>({vi(vis)})))')
        elif sp == 0x37:  # SQD
            self.catchup(t)
            self.set_vi(vit, f'{vi(vit)} - 1', delays)
            if M:
                e(f'vl::stq<{M}>(X, vl::addr(X, static_cast<uint16_t>({vi(vit)})), vl::ld({vfp(vfs)}));')
        elif sp in (0x38, 0x39, 0x3A):  # DIV / SQRT / RSQRT
            if sp == 0x38:
                e(f'qn = vl::div({vfp(vfs)}[{fsf}], {vfp(vft)}[{ftf}], qdi);')
            elif sp == 0x39:
                e(f'qn = vl::sqrt({vfp(vft)}[{ftf}], qdi);')
            else:
                e(f'qn = vl::rsqrt({vfp(vfs)}[{fsf}], {vfp(vft)}[{ftf}], qdi);')
            self.fdiv = t + (13 if sp == 0x3A else 7)
        elif sp in (0x3B, 0x7B):  # WAITQ / WAITP: timing only
            pass
        elif sp == 0x3C:  # MTIR
            self.set_vi(vit, f'static_cast<int16_t>(vl::fbits({vfp(vfs)}[{fsf}]) & 0xFFFFu)', delays)
        elif sp == 0x3D:  # MFIR
            self.lower_vf(vft, M, f'vl::splatBits(static_cast<int16_t>({vi(vis)} & 0xFFFF))')
        elif sp == 0x3E:  # ILWR
            comp = 0 if dest & 8 else 1 if dest & 4 else 2 if dest & 2 else 3
            self.set_vi(vit, f'vl::ldw(X, vl::addr(X, static_cast<uint16_t>({vi(vis)})), {comp})', False)
        elif sp == 0x3F:  # ISWR
            self.catchup(t)
            if dest:
                e(f'vl::stw<{dest}>(X, vl::addr(X, static_cast<uint16_t>({vi(vis)})), {vi(vit)});')
        elif sp == 0x40:  # RNEXT
            e('{ const uint32_t x = (S.r >> 4) & 1u, y = (S.r >> 22) & 1u; '
              'S.r = (((S.r << 1) ^ x ^ y) & 0x007FFFFFu) | 0x3F800000u; }')
            self.lower_vf(vft, M, 'vl::splatBits(static_cast<int32_t>(S.r))')
        elif sp == 0x41:  # RGET
            self.lower_vf(vft, M, 'vl::splatBits(static_cast<int32_t>(S.r))')
        elif sp == 0x42:  # RINIT
            e(f'S.r = 0x3F800000u | (vl::fbits({vfp(vfs)}[{fsf}]) & 0x007FFFFFu);')
        elif sp == 0x43:  # RXOR
            e(f'S.r = 0x3F800000u | ((S.r ^ vl::fbits({vfp(vfs)}[{fsf}])) & 0x007FFFFFu);')
        elif sp == 0x64:  # MFP
            self.lower_vf(vft, M, '_mm_set1_ps(p)')
        elif sp in (0x68, 0x69):  # XTOP / XITOP
            self.set_vi(vit, f'static_cast<int32_t>(S.{"top" if sp == 0x68 else "itop"} & 0x3FFu)', False)
        elif sp == 0x6C:  # XGKICK
            e(f'VuLiftAccess::kickStart(*X.vu, static_cast<uint32_t>(static_cast<uint16_t>({vi(vis)})), E + {t}, kc);')
            self.kick = 1
        elif sp in (0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x78, 0x79, 0x7A, 0x7C, 0x7D, 0x7E):
            lat = p.lu.latency
            v = vfp(vfs)
            fn = {0x70: f'vl::esadd({v})', 0x71: f'vl::ersadd({v})', 0x72: f'vl::eleng({v})',
                  0x73: f'vl::erleng({v})', 0x74: f'vl::eatanxy({v})', 0x75: f'vl::eatanxz({v})',
                  0x76: f'vl::esum({v})', 0x78: f'vl::esqrt({v}[{fsf}])', 0x79: f'vl::ersqrt({v}[{fsf}])',
                  0x7A: f'vl::ercpr({v}[{fsf}])', 0x7C: f'vl::esinv({v}[{fsf}])', 0x7D: f'vl::eatanv({v}[{fsf}])',
                  0x7E: f'vl::eexpv({v}[{fsf}])'}[sp]
            k = 0 if self.efu[0] is None else 1 if self.efu[1] is None else None
            if k is None:
                raise Unliftable(f'both EFU slots busy at {p.pc:#x}')
            e(f'pn{k} = {fn};')
            self.efu[k] = t + lat
            self.efures = t + max(lat - 1, 0)
        else:
            raise Unliftable(f'lower special {sp:#x} at {p.pc:#x}')

    # --- control flow --------------------------------------------------------------------------------------------------
    def after_branch(self, info, delay_pc):
        g = self.g
        kind, x = info
        fall = delay_pc + 8 if delay_pc + 8 < g.size else 0
        self.prepare_leave()
        bpc = delay_pc - 8
        if kind == 'b':
            self.e(self.jump(x, from_pc=bpc))
        elif kind == 'c':
            self.e(f'if (brc) {{ {self.jump(x, from_pc=bpc)} }}')
            self.e(self.jump(fall, from_pc=bpc))
        else:
            # known targets (heads file) + every entry of this group: jump tables point at program starts
            targets = sorted(set(g.jr_targets.get(x, [])) | set(g.entries))
            self.e('switch (jtv)')
            self.e('{')
            for tg in targets:
                self.e(f'case 0x{tg:x}: {{ {self.jump(tg, from_pc=bpc)} }}')
            self.e('default:')
            for line in self.export_lines(0, 2, pc_expr='jtv'):
                self.e(line)
            self.e('}')

    def end_program(self, end_pc):
        """flushPipelines and the end of run(): everything in flight lands; m_cycle = when the last of it is done."""
        t = self.now
        last = t
        for v in [f['ready'] for f in self.flags] + ([self.fdiv] if self.fdiv is not None else []) + \
                [v for v in self.efu if v is not None]:
            last = max(last, v)
        if self.g.queued:
            for v in self.lanes.values():
                last = max(last, v)
        lanes_after = {k: v for k, v in self.lanes.items() if v > t}
        efures = self.efures
        bk = self.bk
        self.commit_until(10 ** 9)
        e = self.e
        e('{')
        e(f'    uint64_t endc = E + {last};')
        if self.kick:
            e(f'    VuLiftAccess::kickAdvance(*X.vu, E + {t}, kc);')
            e('    const uint64_t ke = VuLiftAccess::kickFinish(*X.vu, kc);')
            e('    if (ke > endc) endc = ke;')
        for line in self.writeback():
            e('    ' + line)
        e('    for (uint64_t &l : X.lane) l = 0;')
        for k, v in sorted(lanes_after.items()):
            e(f'    X.lane[{k}] = E + {v};')
        if efures > t:
            e(f'    X.efuRes = E + {efures};')
        if bk:
            e(f'    X.branchBackupReg = {bk}; X.branchBackupValue = bkv;')
        e('    X.workingClip = wclip;')
        e(f'    VuLiftAccess::finishRun(*X.vu, X, endc, 0x{end_pc:x}u);')
        e('    return kVuLiftEnded;')
        e('}')


# --- program discovery -----------------------------------------------------------------------------------------------

def default_entries(code, unit):
    """Program starts: the first pair of every non-empty run after an empty pair (or pc 0), and the pair after each
    program end (E bit + 1), plus the VU1 overlay load addresses of tools/vu1_micro_from_elf.py (MSCAL targets)."""
    n = len(code) // 8
    words = [struct.unpack_from('<II', code, i * 8) for i in range(n)]
    heads = set()
    for i in range(n):
        if words[i] == (0, 0):
            continue
        if i == 0 or words[i - 1] == (0, 0):
            heads.add(i * 8)
        if i >= 2 and (words[i - 2][1] & 0x40000000):
            heads.add(i * 8)
        # the pair after an unconditional jump's delay slot is not reached by falling through: another entry
        if i >= 2:
            lo2, up2 = words[i - 2]
            if not (up2 & 0x80000000) and ((lo2 >> 25) & 0x7F) in (0x20, 0x24):
                heads.add(i * 8)
    if unit == 1:
        try:
            sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
            import vu1_micro_from_elf as recipe
            for vu, _ee, _len in recipe.RECIPE:
                if vu < len(code) and words[vu // 8] != (0, 0):
                    heads.add(vu)
        except Exception:
            pass
    return heads


def reach(code, unit, entry, jr_targets):
    """Pairs a program can execute from entry (to split entries into groups)."""
    mask = 0x3FFF if unit == 1 else 0xFFF
    seen = set()
    work = [entry]
    while work:
        pc = work.pop()
        while pc not in seen and pc + 8 <= len(code):
            seen.add(pc)
            p = Pair(pc, *struct.unpack_from('<II', code, pc), vu1=unit == 1)
            if p.ebit:
                seen.add((pc + 8) & mask)
                break
            if p.is_branch():
                seen.add((pc + 8) & mask)
                t = p.branch_target(mask)
                if t is None:
                    work.extend(jr_targets.get(pc, []))
                    break
                work.append(t)
                if p.lower_op() == 0x20:
                    break
                pc = (pc + 16) & mask
                continue
            pc = (pc + 8) & mask
    return seen


def ranges_of(pcs):
    out = []
    for pc in sorted(pcs):
        if out and out[-1][1] == pc:
            out[-1][1] = pc + 8
        else:
            out.append([pc, pc + 8])
    return out


def load_images(paths):
    imgs = []
    for p in paths:
        if os.path.isdir(p):
            for n in sorted(os.listdir(p)):
                if n.endswith('.bin'):
                    imgs.append(os.path.join(p, n))
        elif os.path.exists(p):
            imgs.append(p)
    return imgs


def read_heads(path):
    """Optional local file: lines 'vu1 <pc>' / 'vu0 <pc>' (extra entries) and 'jr1 <jr pc> <target>' (JR targets).
    Run-time logs name what is missing ('no lifted program at pc', 'handed ... at pc'). Addresses only."""
    heads = {0: set(), 1: set()}
    jr = {0: {}, 1: {}}
    if path and os.path.exists(path):
        for line in open(path):
            f = line.split('#')[0].split()
            if len(f) == 2 and f[0] in ('vu0', 'vu1'):
                heads[int(f[0][2])].add(int(f[1], 16))
            elif len(f) == 3 and f[0] in ('jr0', 'jr1'):
                jr[int(f[0][2])].setdefault(int(f[1], 16), set()).add(int(f[2], 16))
    return heads, jr


def main(argv):
    out_dir = argv[0]
    vu = {0: [], 1: []}
    parts = 4
    heads_path = None
    report = None
    i = 1
    while i < len(argv):
        a = argv[i]
        if a in ('--vu0', '--vu1'):
            vu[int(a[4])].append(argv[i + 1])
            i += 2
        elif a == '--parts':
            parts = int(argv[i + 1])
            i += 2
        elif a == '--heads':
            heads_path = argv[i + 1]
            i += 2
        elif a == '--report':
            report = argv[i + 1]
            i += 2
        else:
            sys.exit(f'unknown argument {a}')
    extra, jr = read_heads(heads_path)
    os.makedirs(out_dir, exist_ok=True)
    funcs = []   # (unit, name, fn, entries, ranges, hash)
    log = []
    for unit in (1, 0):
        for img_path in load_images(vu[unit]):
            code = open(img_path, 'rb').read()
            if unit == 1 and len(code) != 0x4000 or unit == 0 and len(code) != 0x1000:
                log.append(f'{img_path}: wrong size {len(code)}')
                continue
            tag = f'u{unit}_{fnv32(code):08x}'
            entries = sorted(default_entries(code, unit) | extra[unit])
            reach_of = {e: reach(code, unit, e, jr[unit]) for e in entries}
            # groups: union entries whose reachable pairs overlap
            groups = []
            for e in entries:
                merged = [gp for gp in groups if gp[1] & reach_of[e]]
                ents = {e}
                pcs = set(reach_of[e])
                for gp in merged:
                    groups.remove(gp)
                    ents |= gp[0]
                    pcs |= gp[1]
                groups.append((ents, pcs))
            for k, (ents, _pcs) in enumerate(sorted(groups, key=lambda x: min(x[0]))):
                name = f'{tag}_{k}'
                try:
                    grp = Group(unit, code, ents, jr[unit], name)
                    fn = grp.generate()
                except Unliftable as ex:
                    # try the entries one by one: one bad program must not take the others with it
                    log.append(f'{name}: group not liftable ({ex}); entries one by one')
                    for e in sorted(ents):
                        try:
                            grp = Group(unit, code, {e}, jr[unit], f'{name}_{e:x}')
                            fn = grp.generate()
                        except Unliftable as ex2:
                            log.append(f'  VU{unit} {e:#06x}: not lifted ({ex2})')
                            continue
                        rng = ranges_of(grp.covered)
                        funcs.append((unit, grp.name, fn, [e], rng, grp))
                    continue
                rng = ranges_of(grp.covered)
                funcs.append((unit, grp.name, fn, sorted(ents), rng, grp))
                log.append(f'{name}: VU{unit} entries {" ".join(f"{e:04x}" for e in sorted(ents))}: '
                           f'{len(grp.covered)} pairs, {len(grp.blocks)} blocks')
    # write parts
    per = [[] for _ in range(max(parts, 1))]
    for k, f in enumerate(funcs):
        per[k % len(per)].append(f)
    for k, fl in enumerate(per):
        lines = ["// Generated by tools/vu/vu_lift.py from the player's VU micro memory: game code, never commit.",
                 '#include "runtime/ps2_vu_lift_rt.h"',
                 '#if defined(_MSC_VER)', '#pragma float_control(precise, on, push)', '#pragma fp_contract(off)',
                 '#pragma warning(disable: 4102 4189 4101 4065)', '#endif',
                 '#if defined(__clang__)', '#pragma clang diagnostic ignored "-Wunused-label"',
                 '#pragma clang diagnostic ignored "-Wunused-variable"', '#endif']
        for unit, name, fn, ents, rng, grp in fl:
            lines.extend(grp.lines)
            rl = ', '.join(f'{{0x{a:x}, 0x{b:x}}}' for a, b in rng)
            el = ', '.join(f'0x{e:x}' for e in ents)
            lines.append(f'static const VuLiftRange r_{name}[] = {{{rl}}};')
            lines.append(f'static const uint16_t e_{name}[] = {{{el}}};')
        lines.append('static const VuLiftProgramDesc g_programs[] = {')
        for unit, name, fn, ents, rng, grp in fl:
            h = 2166136261
            for a, b in rng:
                for x in grp.code[a:b]:
                    h = ((h ^ x) * 16777619) & 0xFFFFFFFF
            lines.append(f'    {{{unit}, 0x{h:08x}u, r_{name}, {len(rng)}u, e_{name}, {len(ents)}u, {fn}, "{name}"}},')
        if not fl:
            lines.append('    {0, 0, nullptr, 0, nullptr, 0, nullptr, ""},')
        lines.append('};')
        lines.append(f'static const int g_registered = (vuLiftRegister(g_programs, {len(fl)}u), 0);')
        lines += ['#if defined(_MSC_VER)', '#pragma float_control(pop)', '#endif', '']
        path = os.path.join(out_dir, f'vulift_part{k}.cpp')
        new = '\n'.join(lines)
        if not os.path.exists(path) or open(path).read() != new:
            with open(path, 'w', newline='\n') as f:
                f.write(new)
    summary = f'vu_lift: {len(funcs)} functions, ' + ', '.join(
        f'VU{u} {sum(len(f[3]) for f in funcs if f[0] == u)} entries' for u in (1, 0))
    log.append(summary)
    print(summary)
    if report:
        with open(report, 'w') as f:
            f.write('\n'.join(log) + '\n')
    else:
        for line in log:
            print(line)


if __name__ == '__main__':
    main(sys.argv[1:])
