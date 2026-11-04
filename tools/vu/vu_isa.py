"""VU micro-instruction decoding for the T4 VU lifter (tools/vu/vu_lift.py).

Our own code (Tekken 4 port). It mirrors, field by field, the decode rules of the runtime's exact VU engine
(PS2Recomp ps2xRuntime/src/lib/vu/ps2_vu1_core.cpp: decodeUpperUsage, decodeLowerUsage, decodeInstructionPair),
because the lifter must schedule every pair exactly as that engine does: the engine is the reference the lifted
code is checked against bit for bit (PS2X_VULIFT_VERIFY). Reads no game data by itself.
"""
import struct

FMAC_LAT = 4
ACC_FWD_LAT = 1

# pipelines
P_NONE, P_FMAC, P_LSU, P_FDIV, P_EFU, P_IALU, P_BRANCH, P_XGKICK = range(8)


def lane(c):
    """DEST bit of component c (x = 8)."""
    return 1 << (3 - c)


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def imm11(i):
    return sx(i & 0x7FF, 11)


def imm15(i):
    return sx(((i >> 21) & 0xF) << 11 | (i & 0x7FF), 15)


def imm5(i):
    return sx((i >> 6) & 0x1F, 5)


class Usage:
    __slots__ = ('vf_read', 'vf_write', 'vi_read', 'vi_write', 'acc_read', 'acc_write', 'latency', 'vf_latency',
                 'vi_latency', 'pipeline', 'wait_q', 'wait_p', 'reads_clip', 'writes_clip', 'delays_branch',
                 'reserved')

    def __init__(self):
        self.vf_read = []          # [(reg, lanes)] at most 2, merged per reg
        self.vf_write = (0, 0)     # (reg, lanes)
        self.vi_read = 0
        self.vi_write = 0
        self.acc_read = 0
        self.acc_write = 0
        self.latency = 0
        self.vf_latency = 0
        self.vi_latency = 0
        self.pipeline = P_NONE
        self.wait_q = False
        self.wait_p = False
        self.reads_clip = False
        self.writes_clip = False
        self.delays_branch = False
        self.reserved = False

    def add_vf_read(self, reg, lanes):
        if lanes == 0:
            return
        for k, (r, l) in enumerate(self.vf_read):
            if r == reg:
                self.vf_read[k] = (r, l | lanes)
                return
        if len(self.vf_read) < 2:
            self.vf_read.append((reg, lanes))

    def add_vf_write(self, reg, lanes):
        if reg == 0 or lanes == 0:
            return
        r, l = self.vf_write
        if r == 0:
            self.vf_write = (reg, lanes)
        elif r == reg:
            self.vf_write = (reg, l | lanes)

    def vf_read_lanes(self, reg):
        return next((l for r, l in self.vf_read if r == reg), 0)


def upper_special(u):
    return (u & 3) | ((u >> 4) & 0x7C)


def lower_special(l):
    return (l & 3) | ((l >> 4) & 0x7C)


def decode_upper_usage(u):
    us = Usage()
    us.pipeline = P_FMAC
    us.latency = FMAC_LAT
    op = u & 0x3F
    dest = (u >> 21) & 0xF
    fs, ft, fd = (u >> 11) & 0x1F, (u >> 16) & 0x1F, (u >> 6) & 0x1F
    if op <= 0x2F:
        us.add_vf_read(fs, dest)
        us.add_vf_write(fd, dest)
        if op <= 0x1B:
            us.add_vf_read(ft, lane(op & 3))
        elif op >= 0x28:
            us.add_vf_read(ft, 0xE if op == 0x2E else dest)
        if op in (0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x21, 0x23, 0x25, 0x27, 0x29, 0x2D, 0x2E):
            us.acc_read = dest
        return us
    if op >= 0x3C:
        sp = upper_special(u)
        writes_acc = sp <= 0x0F or 0x18 <= sp <= 0x1C or sp == 0x1E or 0x20 <= sp <= 0x2A or 0x2C <= sp <= 0x2E
        if writes_acc:
            us.add_vf_read(fs, dest)
            if sp <= 0x1B:
                us.add_vf_read(ft, lane(sp & 3))
            elif 0x28 <= sp <= 0x2E:
                us.add_vf_read(ft, 0xE if sp == 0x2E else dest)
            us.acc_write = dest
            if 0x08 <= sp <= 0x0F or sp in (0x21, 0x23, 0x25, 0x27, 0x29, 0x2D):
                us.acc_read = dest
        elif 0x10 <= sp <= 0x17 or sp == 0x1D:
            us.add_vf_read(fs, dest)
            us.add_vf_write(ft, dest)
        elif sp == 0x1F:
            us.add_vf_read(fs, 0xE)
            us.add_vf_read(ft, 0x1)
            us.writes_clip = True
        elif sp not in (0x2F, 0x30):
            us.reserved = True
        return us
    us.reserved = True
    return us


EFU_LAT = {0x70: 11, 0x71: 18, 0x72: 18, 0x79: 18, 0x73: 24, 0x74: 54, 0x75: 54, 0x7D: 54, 0x76: 12, 0x78: 12,
           0x7A: 12, 0x7C: 29, 0x7E: 44}


def decode_lower_usage(l, vu1=True):
    us = Usage()
    if l == 0 or l == 0x8000033C:
        return us
    op = (l >> 25) & 0x7F
    vft, vfs = (l >> 16) & 0x1F, (l >> 11) & 0x1F
    vit, vis, vid = (l >> 16) & 0xF, (l >> 11) & 0xF, (l >> 6) & 0xF
    dest = (l >> 21) & 0xF

    def rvi(r):
        if r:
            us.vi_read |= 1 << r

    def wvi(r):
        if r:
            us.vi_write |= 1 << r

    if op == 0x00:
        us.pipeline, us.latency = P_LSU, 4; rvi(vis); us.add_vf_write(vft, dest); return us
    if op == 0x01:
        us.pipeline, us.latency = P_LSU, 1; rvi(vit); us.add_vf_read(vfs, dest); return us
    if op == 0x04:
        us.pipeline, us.latency = P_LSU, 4; rvi(vis); wvi(vit); return us
    if op == 0x05:
        us.pipeline, us.latency = P_LSU, 1; rvi(vis); rvi(vit); return us
    if op in (0x08, 0x09):
        us.pipeline, us.latency, us.delays_branch = P_IALU, 1, True; rvi(vis); wvi(vit); return us
    if op in (0x10, 0x12, 0x13):
        us.pipeline, us.latency, us.reads_clip = P_IALU, 1, True; wvi(1); return us
    if op == 0x11:
        us.pipeline, us.latency, us.writes_clip = P_FMAC, FMAC_LAT, True; return us
    if op in (0x14, 0x16, 0x17):
        us.pipeline, us.latency = P_IALU, 1; wvi(vit); return us
    if op == 0x15:
        us.pipeline, us.latency = P_FMAC, FMAC_LAT; return us
    if op in (0x18, 0x1A, 0x1B):
        us.pipeline, us.latency = P_IALU, 1; rvi(vis); wvi(vit); return us
    if op == 0x1C:
        us.pipeline, us.latency, us.reads_clip = P_IALU, 1, True; wvi(vit); return us
    if op == 0x20:
        us.pipeline = P_BRANCH; return us
    if op == 0x21:
        us.pipeline, us.latency = P_BRANCH, 1; wvi(vit); return us
    if op == 0x24:
        us.pipeline = P_BRANCH; rvi(vis); return us
    if op == 0x25:
        us.pipeline, us.latency = P_BRANCH, 1; rvi(vis); wvi(vit); return us
    if op in (0x28, 0x29):
        us.pipeline = P_BRANCH; rvi(vis); rvi(vit); return us
    if op in (0x2C, 0x2D, 0x2E, 0x2F):
        us.pipeline = P_BRANCH; rvi(vis); return us
    if op != 0x40:
        us.reserved = True
        return us
    d = l & 0x3F
    if d in (0x30, 0x31, 0x34, 0x35):
        us.pipeline, us.latency, us.delays_branch = P_IALU, 1, True; rvi(vis); rvi(vit); wvi(vid); return us
    if d == 0x32:
        us.pipeline, us.latency, us.delays_branch = P_IALU, 1, True; rvi(vis); wvi(vit); return us
    if d < 0x3C:
        us.reserved = True
        return us
    sp = lower_special(l)
    fsf, ftf = (l >> 21) & 3, (l >> 23) & 3
    if sp in (0x30, 0x31):
        us.pipeline, us.latency = P_FMAC, 4
        us.add_vf_read(vfs, 0xF if sp == 0x31 else dest)
        us.add_vf_write(vft, dest)
    elif sp in (0x34, 0x36):
        us.pipeline, us.latency, us.vi_latency, us.delays_branch = P_LSU, 4, 1, True
        rvi(vis); wvi(vis); us.add_vf_write(vft, dest)
    elif sp in (0x35, 0x37):
        us.pipeline, us.latency, us.delays_branch = P_LSU, 1, True
        rvi(vit); wvi(vit); us.add_vf_read(vfs, dest)
    elif sp == 0x38:
        us.pipeline, us.latency = P_FDIV, 7
        us.add_vf_read(vfs, lane(fsf)); us.add_vf_read(vft, lane(ftf))
    elif sp == 0x39:
        us.pipeline, us.latency = P_FDIV, 7
        us.add_vf_read(vft, lane(ftf))
    elif sp == 0x3A:
        us.pipeline, us.latency = P_FDIV, 13
        us.add_vf_read(vfs, lane(fsf)); us.add_vf_read(vft, lane(ftf))
    elif sp == 0x3B:
        us.pipeline, us.wait_q = P_FDIV, True
    elif sp == 0x3C:
        us.pipeline, us.latency, us.delays_branch = P_IALU, 1, True
        us.add_vf_read(vfs, lane(fsf)); wvi(vit)
    elif sp == 0x3D:
        us.pipeline, us.latency = P_FMAC, 4
        rvi(vis); us.add_vf_write(vft, dest)
    elif sp == 0x3E:
        us.pipeline, us.latency = P_LSU, 4; rvi(vis); wvi(vit)
    elif sp == 0x3F:
        us.pipeline, us.latency = P_LSU, 1; rvi(vis); rvi(vit)
    elif sp in (0x40, 0x41):
        us.pipeline, us.latency = P_FMAC, 4; us.add_vf_write(vft, dest)
    elif sp in (0x42, 0x43):
        us.pipeline, us.latency = P_IALU, 1; us.add_vf_read(vfs, lane(fsf))
    elif sp == 0x64:
        if not vu1:
            us.reserved = True
        else:
            us.pipeline, us.latency = P_FMAC, 4; us.add_vf_write(vft, dest)
    elif sp in (0x68, 0x69):
        us.pipeline, us.latency = P_IALU, 1; wvi(vit)
    elif sp == 0x6C:
        if not vu1:
            us.reserved = True
        else:
            us.pipeline, us.latency = P_XGKICK, 2; rvi(vis)
    elif sp in EFU_LAT:
        if not vu1:
            us.reserved = True
        else:
            us.pipeline, us.latency = P_EFU, EFU_LAT[sp]
            if 0x70 <= sp <= 0x73:
                us.add_vf_read(vfs, 0xE)
            elif sp == 0x74:
                us.add_vf_read(vfs, 0xC)
            elif sp == 0x75:
                us.add_vf_read(vfs, 0xA)
            elif sp == 0x76:
                us.add_vf_read(vfs, 0xF)
            else:
                us.add_vf_read(vfs, lane(fsf))
    elif sp == 0x7B:
        if not vu1:
            us.reserved = True
        else:
            us.pipeline, us.wait_p = P_EFU, True
    else:
        us.reserved = True
    return us


class Pair:
    """One decoded instruction pair, as VU1Interpreter::decodeInstructionPair builds it."""

    def __init__(self, pc, lower, upper, vu1=True):
        self.pc = pc
        self.lower, self.upper = lower, upper
        self.ibit = bool(upper & 0x80000000)
        self.ebit = bool(upper & 0x40000000)
        self.mbit = bool(upper & 0x20000000)
        self.dbit = bool(upper & 0x10000000)
        self.tbit = bool(upper & 0x08000000)
        self.uu = decode_upper_usage(upper)
        self.upper_nop = (upper & 0x3F) >= 0x3C and upper_special(upper) in (0x2F, 0x30)
        self.lu = Usage() if self.ibit else decode_lower_usage(lower, vu1)
        self.shadow = 0
        self.suppressed = 0
        w = self.uu.vf_write[0]
        if w and (self.lu.vf_read_lanes(w) or self.lu.vf_write[0] == w):
            self.shadow = w
            if self.lu.vf_write[0] == w:
                self.suppressed = w

    @property
    def reserved(self):
        return self.uu.reserved or self.lu.reserved

    def lower_op(self):
        return (self.lower >> 25) & 0x7F

    def is_branch(self):
        return not self.ibit and self.lu.pipeline == P_BRANCH

    def branch_target(self, mask):
        """Static target of B/BAL/conditional branches (None for JR/JALR)."""
        op = self.lower_op()
        if op in (0x24, 0x25):
            return None
        return (self.pc + 8 + imm11(self.lower) * 8) & mask


def pairs_of(code, vu1=True):
    n = len(code) // 8
    return [Pair(i * 8, *struct.unpack_from('<II', code, i * 8), vu1=vu1) for i in range(n)]
