"""Read memory and hardware registers from a running PCSX2 through its PINE socket.

PCSX2 must run with PINE enabled ([EmuCore] EnablePINE = true, PINESlot = 28011 in inis/PCSX2.ini).
PCSX2 is the ground truth for this project: compare what the recompiled game does against these values.

Usage:
  python -I tools/pine.py status
  python -I tools/pine.py read32 0x1000e000 0x1000e040 ...
  python -I tools/pine.py dmac [--samples N] [--interval S]   # MFIFO/DMAC registers, sampled N times
  python -I tools/pine.py dump 0x100000 0x400 [--out file.bin]  # RAM as quadwords ("hi lo"), or raw to a file
"""
import argparse
import socket
import struct
import sys
import time

READ32, READ64, VERSION, TITLE, GAME_ID, STATUS = 0x02, 0x03, 0x08, 0x0B, 0x0C, 0x0F
STATUSES = {0: "running", 1: "paused", 2: "shutdown"}

DMAC_REGS = [
    ("D_CTRL", 0x1000E000), ("D_STAT", 0x1000E010), ("D_RBSR", 0x1000E040), ("D_RBOR", 0x1000E050),
    ("D_ENABLER", 0x1000F520),
    ("VIF1_CHCR", 0x10009000), ("VIF1_MADR", 0x10009010), ("VIF1_QWC", 0x10009020), ("VIF1_TADR", 0x10009030),
    ("GIF_CHCR", 0x1000A000), ("GIF_TADR", 0x1000A030),
    ("SPRF_CHCR", 0x1000D000), ("SPRF_MADR", 0x1000D010),
]


class Pine:
    def __init__(self, port=28011):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)

    def call(self, payload):
        self.sock.sendall(struct.pack("<I", 4 + len(payload)) + payload)
        size = struct.unpack("<I", self._recv(4))[0]
        body = self._recv(size - 4)
        if body[0] != 0:
            raise RuntimeError(f"PINE command 0x{payload[0]:02x} failed")
        return body[1:]

    def _recv(self, n):
        data = b""
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                raise ConnectionError("PINE socket closed")
            data += chunk
        return data

    def read32(self, addr):
        return struct.unpack("<I", self.call(struct.pack("<BI", READ32, addr)))[0]

    def read64(self, addr):
        return struct.unpack("<Q", self.call(struct.pack("<BI", READ64, addr)))[0]

    def string(self, opcode):
        body = self.call(bytes([opcode]))
        size = struct.unpack("<I", body[:4])[0]
        return body[4:4 + size].rstrip(b"\0").decode(errors="replace")

    def status(self):
        return STATUSES.get(struct.unpack("<I", self.call(bytes([STATUS])))[0], "?")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    r = sub.add_parser("read32")
    r.add_argument("addrs", nargs="+")
    d = sub.add_parser("dmac")
    d.add_argument("--samples", type=int, default=1)
    d.add_argument("--interval", type=float, default=0.5)
    m = sub.add_parser("dump")
    m.add_argument("addr")
    m.add_argument("size")
    m.add_argument("--out")
    args = ap.parse_args()

    pine = Pine()
    if args.cmd == "status":
        print(f"{pine.string(VERSION)} | {pine.status()} | {pine.string(GAME_ID)} | {pine.string(TITLE)}")
    elif args.cmd == "read32":
        for a in args.addrs:
            addr = int(a, 16)
            print(f"0x{addr:08x}: 0x{pine.read32(addr):08x}")
    elif args.cmd == "dump":
        base, size = int(args.addr, 16), int(args.size, 16)
        data = b"".join(struct.pack("<Q", pine.read64(base + off)) for off in range(0, size, 8))
        if args.out:
            with open(args.out, "wb") as f:
                f.write(data)
        else:
            for off in range(0, len(data), 16):
                lo, hi = struct.unpack_from("<QQ", data, off)
                print(f"{base + off:08x}: {hi:016x} {lo:016x}")
    else:
        print(" ".join(f"{name:>10}" for name, _ in DMAC_REGS))
        for i in range(args.samples):
            print(" ".join(f"{pine.read32(addr):10x}" for _, addr in DMAC_REGS))
            if i + 1 < args.samples:
                time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
