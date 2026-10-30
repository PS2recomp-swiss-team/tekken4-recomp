#!/usr/bin/env python3
"""Minimal ISO9660 reader for Tekken 4 (US, SLUS-20328): checks the disc and extracts the files the port needs.

Standard library only (a player's PC may have no 7-Zip). Reads the ISO, never writes to it.

  python -I tools\\iso_extract.py <iso> --check
      verify the image: SYSTEM.CNF must say BOOT2 = cdrom0:\\SLUS_203.28;1 and the ELF's SHA-1 must match
  python -I tools\\iso_extract.py <iso> <outdir> [--files NAME ...]
      the same check, then extract (default: SYSTEM.CNF, SLUS_203.28, IRX/IOPRP243.IMG, TEKKEN/DATA.BIN)
      into <outdir>, keeping the sub-folders; each file is written to <name>.part and renamed when complete.

Machine-readable output lines (the rest is for humans):
  BOOT2 <name>             ELF name from SYSTEM.CNF
  ELF_SHA1 <hex>           SHA-1 of the ELF as stored on the disc
  FILE <path> <size>       one per wanted file (size from the ISO directory)
  EXTRACTED <path> <size>  after a file was written
  OK                       everything passed
Exit codes: 0 ok, 2 wrong/unsupported disc, 3 ELF SHA-1 mismatch, 4 I/O or other error.
"""
import argparse
import hashlib
import os
import re
import sys

EXPECTED_BOOT = "SLUS_203.28"
EXPECTED_SHA1 = "a4b7dde20a2918c550badd127a245db155c36815"
DEFAULT_FILES = ["SYSTEM.CNF", "SLUS_203.28", "IRX/IOPRP243.IMG", "TEKKEN/DATA.BIN"]
# (sector size, offset of the 2048 user bytes inside a sector): plain ISO, raw MODE1, raw MODE2/XA, 2336-byte
_LAYOUTS = [(2048, 0), (2352, 16), (2352, 24), (2336, 8)]


class DiscError(Exception):
    def __init__(self, msg, code=2):
        super().__init__(msg)
        self.code = code


class Iso:
    def __init__(self, path):
        self.f = open(path, "rb")
        self.size = os.fstat(self.f.fileno()).st_size
        self.ss, self.off = self._detect()
        pvd = self._read_sector(16)
        self.block = int.from_bytes(pvd[128:130], "little") or 2048
        root = pvd[156:190]
        self.root = (int.from_bytes(root[2:6], "little"), int.from_bytes(root[10:14], "little"))

    def _detect(self):
        head = self.f.read(8)
        if head[:4] == b"CISO" or head[:4] == b"ZISO":
            raise DiscError("this is a CSO/ZSO compressed image; convert it to a plain .iso first")
        if head[:8] == b"MComprHD":
            raise DiscError("this is a CHD image; convert it to a plain .iso first (chdman extractdvd)")
        for ss, off in _LAYOUTS:
            self.f.seek(16 * ss + off)
            d = self.f.read(6)
            if len(d) == 6 and d[0] == 1 and d[1:6] == b"CD001":
                return ss, off
        raise DiscError("not an ISO9660 image (no CD001 volume descriptor); use the plain .iso of the disc, "
                        "not CUE/BIN, CCD, NRG, MDF or a compressed format")

    def _read_sector(self, lba):
        self.f.seek(lba * self.ss + self.off)
        return self.f.read(2048)

    def read(self, lba, length):
        """Yield the bytes of an extent in chunks."""
        if self.ss == 2048:
            self.f.seek(lba * 2048)
            left = length
            while left > 0:
                d = self.f.read(min(left, 4 << 20))
                if not d:
                    raise DiscError("ISO is truncated (read past the end of the image)", 4)
                left -= len(d)
                yield d
        else:
            left = length
            while left > 0:
                d = self._read_sector(lba)[:left]
                if not d:
                    raise DiscError("ISO is truncated (read past the end of the image)", 4)
                left -= len(d)
                lba += 1
                yield d

    def listdir(self, extent):
        lba, size = extent
        data = b"".join(self.read(lba, size))
        pos = 0
        while pos < len(data):
            n = data[pos]
            if n == 0:  # padding up to the next sector
                pos = (pos // 2048 + 1) * 2048
                continue
            rec = data[pos:pos + n]
            pos += n
            nlen = rec[32]
            name = rec[33:33 + nlen]
            if name in (b"\x00", b"\x01"):
                continue
            name = name.decode("ascii", "replace").split(";")[0]
            if name.endswith("."):
                name = name[:-1]
            yield name, int.from_bytes(rec[2:6], "little"), int.from_bytes(rec[10:14], "little"), bool(rec[25] & 2)

    def find(self, path):
        cur = self.root
        parts = [p for p in re.split(r"[\\/]", path) if p]
        for i, part in enumerate(parts):
            hit = None
            for name, lba, size, is_dir in self.listdir(cur):
                if name.upper() == part.upper():
                    hit = (lba, size, is_dir)
                    break
            if hit is None:
                return None
            if i < len(parts) - 1:
                if not hit[2]:
                    return None
                cur = (hit[0], hit[1])
            else:
                return hit[0], hit[1]
        return None

    def read_all(self, path):
        e = self.find(path)
        if e is None:
            raise DiscError("%s is not on the disc" % path)
        return b"".join(self.read(e[0], e[1]))


def say(msg):
    print(msg, flush=True)


def verify(iso):
    """Returns (boot name, sha1 of the ELF). Raises DiscError for any other build."""
    try:
        cnf = iso.read_all("SYSTEM.CNF").decode("ascii", "replace")
    except DiscError:
        raise DiscError("no SYSTEM.CNF in the image root: this is not a PS2 game disc image")
    m = re.search(r"BOOT2\s*=\s*cdrom0:\\?([^;\s\r\n]+);?\s*1?", cnf, re.I)
    if not m:
        raise DiscError("SYSTEM.CNF has no BOOT2 line (a PS1 disc or a non-game disc?):\n" + cnf.strip())
    boot = m.group(1)
    say("BOOT2 %s" % boot)
    if boot.upper() != EXPECTED_BOOT:
        raise DiscError("this disc boots %s, but only the US release (Tekken 4 NTSC-U, SLUS-20328, "
                        "BOOT2 = cdrom0:\\SLUS_203.28;1) is supported. The function map in this repo does not "
                        "fit other builds (PAL SCES-50878, Japan SLPS-25??? ...)." % boot)
    e = iso.find(boot)
    if e is None:
        raise DiscError("SYSTEM.CNF names %s but it is not in the image root" % boot)
    h = hashlib.sha1()
    for d in iso.read(e[0], e[1]):
        h.update(d)
    say("ELF_SHA1 %s" % h.hexdigest())
    if h.hexdigest() != EXPECTED_SHA1:
        raise DiscError("%s on this disc has SHA-1 %s, expected %s: a different revision/dump of the US game "
                        "(or a modified/corrupt image). Refusing to continue." % (boot, h.hexdigest(), EXPECTED_SHA1), 3)
    return boot, h.hexdigest()


def extract(iso, rel, outdir):
    e = iso.find(rel)
    if e is None:
        raise DiscError("%s is not on the disc" % rel, 4)
    lba, size = e
    dest = os.path.join(outdir, *[p for p in re.split(r"[\\/]", rel) if p])
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    part = dest + ".part"
    done = 0
    nextpct = 10
    h = hashlib.sha1() if os.path.basename(rel).upper() == EXPECTED_BOOT else None
    with open(part, "wb") as out:
        for d in iso.read(lba, size):
            out.write(d)
            if h:
                h.update(d)
            done += len(d)
            if size > (64 << 20) and done * 100 // size >= nextpct:
                say("  %s %d%% (%d MB)" % (rel, done * 100 // size, done >> 20))
                nextpct += 10
    if h and h.hexdigest() != EXPECTED_SHA1:
        raise DiscError("extracted %s has SHA-1 %s, expected %s" % (rel, h.hexdigest(), EXPECTED_SHA1), 3)
    if os.path.getsize(part) != size:
        raise DiscError("extracted %s has the wrong size" % rel, 4)
    os.replace(part, dest)
    say("EXTRACTED %s %d" % (rel, size))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("iso")
    ap.add_argument("outdir", nargs="?")
    ap.add_argument("--check", action="store_true", help="only verify the disc, extract nothing")
    ap.add_argument("--files", nargs="+", default=DEFAULT_FILES, help="paths inside the ISO to extract")
    a = ap.parse_args()
    if not a.check and not a.outdir:
        ap.error("give an output directory, or --check")
    try:
        iso = Iso(a.iso)
        verify(iso)
        for rel in a.files:
            e = iso.find(rel)
            if e is None:
                raise DiscError("%s is not on the disc" % rel, 4)
            say("FILE %s %d" % (rel.replace("\\", "/"), e[1]))
        if not a.check:
            for rel in a.files:
                extract(iso, rel, a.outdir)
        say("OK")
        return 0
    except DiscError as ex:
        say("ERROR: %s" % ex)
        return ex.code
    except OSError as ex:
        say("ERROR: %s" % ex)
        return 4


if __name__ == "__main__":
    sys.exit(main())
