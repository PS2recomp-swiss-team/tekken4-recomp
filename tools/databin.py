#!/usr/bin/env python3
"""Tekken 4 DATA.BIN file table: list, verify, extract (PAL SCES-50878 and US SLUS-20328).

The table is in the boot ELF, not in DATA.BIN. Each row is 16 bytes:

  +0  u32  sector    2048-byte sectors counted from the start of TEKKEN/DATA.BIN
  +4  u32  size      byte length (a signed size <= 0 is not a file)
  +8  u32  checksum
  +12 u16  index     equals the row number for every real row
  +14 i16  key       < 0: stored plain. Else the first 4 KB is decrypted

Decrypt (only when key >= 0), first min(size//4, 1024) little-endian words:

  word = (~word + key) mod 2**32

Checksum, after that decrypt: the sum of every whole word in the file
(size//4 words; the last size%4 bytes are not added), mod 2**32.
The file matches when that sum XOR the table checksum is 0.
This is what PAL FUN_002155d0 does (bltz / nor+addu / addu loop / xor).
The loader never compares the index to a stored length. The table is the
run of rows whose u16 at +12 equals the row index. Past that, .rodata
is other data and must not be read as files.

  PAL  VA 0x314360   1496 rows   ISO LBN 1236   2694412288 bytes
  US   VA 0x313380   1122 rows   ISO LBN 401    2695536640 bytes
       (runtime comment 0x3133e0 is US row 6, not the base)

A loose game/disc/TEKKEN/DATA.BIN is used when its size matches.
Otherwise the single .iso in that project's root is used.
US files live in the sibling tree ../tekken4-recomp_usa (or TEKKEN4_US_ROOT).

Nothing here writes into game/ or an ISO. Extracts go under logs/databin/
unless --out says otherwise. logs/ is gitignored.

Examples:
  python -I tools/databin.py list pal
  python -I tools/databin.py list us --json logs/databin/us-list.json
  python -I tools/databin.py verify both
  python -I tools/databin.py extract pal --index 3 --out logs/databin/pal
  python -I tools/databin.py extract pal --all --out logs/databin/pal
  python -I tools/databin.py compare
"""

import argparse
import array
import hashlib
import json
import os
import struct
import sys
import time

ROW = 16
WORD_BYTES = 4
DECRYPT_WORDS = 0x400  # first 4 KB
SECTOR = 2048
READ = 4 * 1024 * 1024

# Known DATA.BIN sizes (runtime/tekken4_overrides.cpp). Used to pick the
# loose file versus the ISO and to reject a row that runs past the file.
DISCS = {
    "pal": {
        "title": "SCES-50878",
        "elf": os.path.join("game", "disc", "SCES_508.78"),
        "loose": os.path.join("game", "disc", "TEKKEN", "DATA.BIN"),
        "table_va": 0x314360,
        "lbn": 1236,
        "size": 2694412288,
    },
    "us": {
        "title": "SLUS-20328",
        "elf": os.path.join("game", "disc", "SLUS_203.28"),
        "loose": os.path.join("game", "disc", "TEKKEN", "DATA.BIN"),
        "table_va": 0x313380,
        "lbn": 401,
        "size": 2695536640,
    },
}


class UsageError(Exception):
    pass


def repo_root():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def us_root():
    env = os.environ.get("TEKKEN4_US_ROOT")
    if env:
        return os.path.abspath(env)
    return os.path.abspath(os.path.join(os.path.dirname(repo_root()), "tekken4-recomp_usa"))


def disc_root(name):
    if name == "pal":
        return repo_root()
    if name == "us":
        return us_root()
    raise UsageError("disc must be pal or us, not %r" % name)


def elf_loads(data):
    if data[:4] != b"\x7fELF":
        raise UsageError("not an ELF")
    e_phoff, _shoff, _flags, _eh, e_phentsize, e_phnum = struct.unpack_from("<IIIHHH", data, 28)
    loads = []
    for i in range(e_phnum):
        p_type, p_off, p_vaddr, _p, p_filesz, _m, _f, _a = struct.unpack_from(
            "<IIIIIIII", data, e_phoff + i * e_phentsize)
        if p_type == 1 and p_filesz:
            loads.append((p_vaddr, p_off, p_filesz))
    return loads


def va_to_off(loads, va):
    for vaddr, off, size in loads:
        if vaddr <= va < vaddr + size:
            return off + (va - vaddr)
    raise UsageError("VA 0x%X is not in a LOAD segment" % va)


def read_table(elf_path, table_va):
    """Rows until the u16 index stops matching the row number."""
    with open(elf_path, "rb") as f:
        data = f.read()
    loads = elf_loads(data)
    base = va_to_off(loads, table_va)
    rows = []
    # Upper bound: rest of this LOAD, so a missing terminator cannot run off the file.
    room = 0
    for vaddr, off, size in loads:
        if off <= base < off + size:
            room = (off + size - base) // ROW
            break
    for i in range(room):
        o = base + i * ROW
        sector, size, checksum = struct.unpack_from("<III", data, o)
        index, key = struct.unpack_from("<Hh", data, o + 12)
        if index != i:
            break
        rows.append({
            "index": i,
            "sector": sector,
            "size": size,
            "checksum": checksum,
            "key": key,
        })
    if not rows:
        raise UsageError("no file-table rows at VA 0x%X in %s" % (table_va, elf_path))
    return rows


def signed_size_ok(size):
    """Loader uses bgtzl: a signed size <= 0 is rejected (0 and 0xFFFFFFFF)."""
    return 0 < size < 0x80000000


def row_fits(row, databin_size):
    if not signed_size_ok(row["size"]):
        return False
    end = row["sector"] * SECTOR + row["size"]
    return row["sector"] < (databin_size // SECTOR) and end <= databin_size


def classify(magic):
    if magic.startswith(b"TIM2"):
        return "TIM2"
    if magic.startswith(b"\x00\x00\x01\xba"):
        return "MPEG-PS"
    if magic.startswith(b"\x00\x00\x01\xb3"):
        return "MPEG-ES"
    if magic.startswith(b"VAGp"):
        return "VAGp"
    if magic.startswith(b"VAGi"):
        return "VAGi"
    if magic.startswith(b"AFS\x00"):
        return "AFS"
    if magic.startswith(b"IECS"):
        return "IECS"
    if magic.startswith(b"\x7fELF"):
        return "ELF"
    if magic.startswith(b"\x1f\x8b"):
        return "gzip"
    if len(magic) >= 4:
        return "data:" + magic[:4].hex()
    return "empty"


def _count_magic(buf, needle, begin, header_ok):
    n = 0
    idx = buf.find(needle, begin)
    while idx >= 0:
        if header_ok(buf, idx):
            n += 1
        idx = buf.find(needle, idx + 1)
    return n


def _tim2_header(buf, i):
    if i + 8 > len(buf):
        return False
    if buf[i:i + 4] != b"TIM2":
        return False
    _ver, fmt, count = struct.unpack_from("<BBH", buf, i + 4)
    return fmt in (0, 1) and 0 < count <= 4096


def _mpeg_header(buf, i):
    return buf[i:i + 4] == b"\x00\x00\x01\xba"


def process_file(fh, base, row, out_fh=None):
    """Decrypt, checksum, hash, and count embedded magics. Streamed.

    Returns the word-sum, sha256 hex, format name, tim2 headers, mpeg-ps packs.
    Raises UsageError on a short read.
    """
    if sys.byteorder != "little":
        raise UsageError("this tool sums PS2 little-endian words and needs a little-endian host")
    size = row["size"]
    key = row["key"]
    fh.seek(base + row["sector"] * SECTOR)
    sha = hashlib.sha256()
    total = 0
    left = size
    words_dec = min(size // WORD_BYTES, DECRYPT_WORDS) if key >= 0 else 0
    words_sum = size // WORD_BYTES
    pending = b""
    magic = b""
    tail = b""
    tim2_n = 0
    mpeg_n = 0
    while left:
        want = min(left, READ)
        chunk = fh.read(want)
        if len(chunk) != want:
            raise UsageError("short read index %d sector %d: got %d of %d" % (
                row["index"], row["sector"], size - left + len(chunk), size))
        left -= want
        data = pending + chunk
        nwords = len(data) // WORD_BYTES
        body = data[:nwords * WORD_BYTES]
        pending = data[nwords * WORD_BYTES:]
        if words_dec and nwords:
            k = min(words_dec, nwords)
            dec = array.array("I")
            dec.frombytes(body[:k * WORD_BYTES])
            add = key & 0xFFFFFFFF
            for i in range(k):
                dec[i] = ((~dec[i]) + add) & 0xFFFFFFFF
            body = dec.tobytes() + body[k * WORD_BYTES:]
            words_dec -= k
        sha.update(body)
        take = min(nwords, words_sum)
        if take:
            words = array.array("I")
            words.frombytes(body[:take * WORD_BYTES])
            total = (total + sum(words)) & 0xFFFFFFFF
            words_sum -= take
        if not magic:
            magic = body[:16]
        if out_fh is not None:
            out_fh.write(body)
        # 4-byte magics: search from len(tail)-3 so a magic split across
        # chunks is counted once (it could not fit in the previous tail).
        buf = tail + body
        # Retry a magic whose header ran off the end of the previous chunk.
        # An 8-byte TIM2 header cannot fit in the last 7 carried bytes, so
        # those starts were not counted yet. A 4-byte MPEG code uses 3.
        tim2_n += _count_magic(buf, b"TIM2", max(0, len(tail) - 7), _tim2_header)
        mpeg_n += _count_magic(buf, b"\x00\x00\x01\xba", max(0, len(tail) - 3), _mpeg_header)
        tail = buf[-15:] if len(buf) > 15 else buf
    if pending:
        sha.update(pending)
        if out_fh is not None:
            out_fh.write(pending)
        if not magic:
            magic = pending[:16]
        buf = tail + pending
        tim2_n += _count_magic(buf, b"TIM2", max(0, len(tail) - 7), _tim2_header)
        mpeg_n += _count_magic(buf, b"\x00\x00\x01\xba", max(0, len(tail) - 3), _mpeg_header)
    return {
        "sum": total,
        "sha256": sha.hexdigest(),
        "fmt": classify(magic),
        "magic": magic[:4].hex(),
        "tim2": tim2_n,
        "mpeg_ps": mpeg_n,
    }


def find_iso(root):
    names = sorted(n for n in os.listdir(root) if n.lower().endswith(".iso"))
    if len(names) != 1:
        raise UsageError("expected one .iso in %s, found %d" % (root, len(names)))
    return os.path.join(root, names[0])


def open_source(name):
    """Return (file, byte_base, description, databin_size). Does not write."""
    spec = DISCS[name]
    root = disc_root(name)
    loose = os.path.join(root, spec["loose"])
    if os.path.isfile(loose) and os.path.getsize(loose) == spec["size"]:
        return open(loose, "rb"), 0, loose, spec["size"]
    iso = find_iso(root)
    return open(iso, "rb"), spec["lbn"] * SECTOR, iso, spec["size"]


def load_rows(name):
    spec = DISCS[name]
    elf = os.path.join(disc_root(name), spec["elf"])
    if not os.path.isfile(elf):
        raise UsageError("ELF not found: %s" % elf)
    return read_table(elf, spec["table_va"]), elf


def default_out(name):
    return os.path.join(repo_root(), "logs", "databin", name)


def manifest_path(name):
    return os.path.join(default_out(name), "manifest.json")


def scan(name, progress=True):
    """Verify every loadable row. Returns the manifest dict. Does not write files."""
    spec = DISCS[name]
    rows, elf = load_rows(name)
    fh, base, source, databin_size = open_source(name)
    t0 = time.time()
    files = []
    bad = 0
    loadable = 0
    formats = {}
    try:
        order = sorted(range(len(rows)), key=lambda i: (rows[i]["sector"], i))
        done = 0
        for i in order:
            row = rows[i]
            rec = {
                "index": row["index"],
                "sector": row["sector"],
                "size": row["size"],
                "key": row["key"],
                "checksum": row["checksum"],
                "loadable": False,
                "checksum_ok": None,
                "fmt": None,
                "magic": None,
                "sha256": None,
                "tim2": 0,
                "mpeg_ps": 0,
                "reason": None,
            }
            if not signed_size_ok(row["size"]):
                rec["reason"] = "size<=0"
            elif not row_fits(row, databin_size):
                rec["reason"] = "past-end"
            else:
                rec["loadable"] = True
                loadable += 1
                got = process_file(fh, base, row)
                ok = ((got["sum"] ^ row["checksum"]) & 0xFFFFFFFF) == 0
                rec["checksum_ok"] = ok
                rec["fmt"] = got["fmt"]
                rec["magic"] = got["magic"]
                rec["sha256"] = got["sha256"]
                rec["tim2"] = got["tim2"]
                rec["mpeg_ps"] = got["mpeg_ps"]
                rec["sum"] = got["sum"]
                if not ok:
                    bad += 1
                    rec["reason"] = "checksum"
                    sys.stderr.write("BAD idx=%d sec=%d size=%d key=%d sum=%08x csum=%08x\n" % (
                        row["index"], row["sector"], row["size"], row["key"], got["sum"], row["checksum"]))
                    sys.stderr.flush()
                formats[got["fmt"]] = formats.get(got["fmt"], 0) + 1
                done += 1
                if progress and (done % 25 == 0 or done == 1):
                    sys.stderr.write("[%s %d/%d] idx=%d bad=%d\n" % (name, done, loadable_guess(rows, databin_size), row["index"], bad))
                    sys.stderr.flush()
            files.append(rec)
    finally:
        fh.close()
    files.sort(key=lambda r: r["index"])
    coarse = {}
    for fmt, n in formats.items():
        key = "data" if fmt.startswith("data:") else fmt
        coarse[key] = coarse.get(key, 0) + n
    return {
        "disc": name,
        "title": spec["title"],
        "elf": elf,
        "table_va": "0x%X" % spec["table_va"],
        "source": source,
        "base": base,
        "databin_size": databin_size,
        "rows": len(rows),
        "loadable": loadable,
        "bad": bad,
        "formats": dict(sorted(formats.items(), key=lambda kv: (-kv[1], kv[0]))),
        "formats_coarse": dict(sorted(coarse.items(), key=lambda kv: (-kv[1], kv[0]))),
        "seconds": round(time.time() - t0, 3),
        "files": files,
    }


def loadable_guess(rows, databin_size):
    return sum(1 for r in rows if row_fits(r, databin_size))


def write_manifest(doc):
    path = manifest_path(doc["disc"])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # Exclusive create the first time. A second verify writes manifest-N.json
    # beside it so an existing manifest is not truncated.
    dest = path
    if os.path.exists(dest):
        n = 2
        while os.path.exists(os.path.join(os.path.dirname(path), "manifest-%d.json" % n)):
            n += 1
        dest = os.path.join(os.path.dirname(path), "manifest-%d.json" % n)
    with open(dest, "xb") as f:
        f.write(json.dumps(doc).encode("utf-8"))
        f.write(b"\n")
    return dest


def load_manifest(name):
    """Newest non-empty manifest. An empty manifest.json is left in place (never deleted)."""
    folder = default_out(name)
    paths = []
    if os.path.isdir(folder):
        for n in os.listdir(folder):
            if n == "manifest.json":
                paths.append((1, os.path.join(folder, n)))
            elif n.startswith("manifest-") and n.endswith(".json"):
                try:
                    paths.append((int(n[len("manifest-"):-len(".json")]), os.path.join(folder, n)))
                except ValueError:
                    pass
    best = None
    for _n, path in sorted(paths):
        if not os.path.isfile(path) or os.path.getsize(path) == 0:
            continue
        try:
            with open(path, "rb") as f:
                doc = json.loads(f.read().decode("utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            continue
        if isinstance(doc, dict) and doc.get("files"):
            best = (doc, path)
    if best:
        return best
    return None, manifest_path(name)


def fmt_row(rec):
    ok = rec["checksum_ok"]
    ok_s = "-" if ok is None else ("yes" if ok else "NO")
    fmt = rec["fmt"] or rec["reason"] or "-"
    return "%5d %8d %10d %6d %s %-18s %s" % (
        rec["index"], rec["sector"], rec["size"] if rec["size"] < 0x80000000 else -1,
        rec["key"], ok_s, fmt, rec["sha256"] or "")


def cmd_list(args):
    rows, elf = load_rows(args.disc)
    spec = DISCS[args.disc]
    if args.check:
        doc = scan(args.disc)
        if args.json:
            _write_json(args.json, doc)
        print("# %s rows=%d loadable=%d bad=%d elf=%s" % (
            args.disc, doc["rows"], doc["loadable"], doc["bad"], elf))
        print("# formats %s" % json.dumps(doc["formats_coarse"], sort_keys=True))
        print("index sector size key ok format sha256")
        for rec in doc["files"]:
            print(fmt_row(rec))
        return 1 if doc["bad"] else 0
    print("# %s rows=%d table=%s elf=%s (checksums not read; pass --check)" % (
        args.disc, len(rows), hex(spec["table_va"]), elf))
    print("index sector size key")
    out_rows = []
    for row in rows:
        size = row["size"] if row["size"] < 0x80000000 else -1
        print("%5d %8d %10d %6d" % (row["index"], row["sector"], size, row["key"]))
        out_rows.append(row)
    if args.json:
        _write_json(args.json, {"disc": args.disc, "table_va": hex(spec["table_va"]), "rows": out_rows})
    return 0


def _write_json(path, doc):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    if os.path.exists(path):
        raise UsageError("refusing to overwrite %s" % path)
    with open(path, "xb") as f:
        f.write(json.dumps(doc).encode("utf-8"))
        f.write(b"\n")
    print("wrote %s" % path)


def cmd_verify(args):
    names = ["pal", "us"] if args.disc == "both" else [args.disc]
    rc = 0
    for name in names:
        doc = scan(name)
        path = write_manifest(doc)
        print("%s rows=%d loadable=%d bad=%d seconds=%s formats=%s" % (
            name, doc["rows"], doc["loadable"], doc["bad"], doc["seconds"],
            json.dumps(doc["formats_coarse"], sort_keys=True)))
        print("manifest %s" % path)
        tim2 = sum(r["tim2"] for r in doc["files"])
        mpeg = sum(r["mpeg_ps"] for r in doc["files"])
        print("%s embedded TIM2-headers=%d MPEG-PS=%d" % (name, tim2, mpeg))
        if doc["bad"]:
            rc = 1
            for rec in doc["files"]:
                if rec["checksum_ok"] is False:
                    print("BAD %s" % fmt_row(rec))
    return rc


def extract_rows(name, indices, out_dir):
    rows, _elf = load_rows(name)
    by_index = {r["index"]: r for r in rows}
    spec_size = DISCS[name]["size"]
    fh, base, source, databin_size = open_source(name)
    os.makedirs(out_dir, exist_ok=True)
    written = []
    bad = 0
    try:
        for index in indices:
            if index not in by_index:
                raise UsageError("index %d is not in the %s table (0..%d)" % (index, name, len(rows) - 1))
            row = by_index[index]
            if not row_fits(row, databin_size):
                raise UsageError("index %d is not a loadable file (size=%d)" % (index, row["size"]))
            dest = os.path.join(out_dir, "%05d.bin" % index)
            if os.path.exists(dest):
                raise UsageError("refusing to overwrite %s" % dest)
            with open(dest, "xb") as out:
                got = process_file(fh, base, row, out)
            ok = ((got["sum"] ^ row["checksum"]) & 0xFFFFFFFF) == 0
            if not ok:
                bad += 1
            print("extract %s idx=%d bytes=%d key=%d checksum=%s fmt=%s tim2=%d mpeg=%d -> %s" % (
                name, index, row["size"], row["key"], "yes" if ok else "NO", got["fmt"],
                got["tim2"], got["mpeg_ps"], dest))
            written.append({
                "index": index, "path": dest, "size": row["size"], "key": row["key"],
                "checksum_ok": ok, "fmt": got["fmt"], "sha256": got["sha256"],
                "tim2": got["tim2"], "mpeg_ps": got["mpeg_ps"],
            })
    finally:
        fh.close()
    print("source %s base %d databin %d" % (source, base, spec_size))
    return written, bad


def cmd_extract(args):
    if args.all and args.index:
        raise UsageError("pass --all or --index, not both")
    if not args.all and not args.index:
        raise UsageError("pass --index N (repeatable) or --all")
    out = args.out or os.path.join(default_out(args.disc), "files")
    if args.all:
        rows, _elf = load_rows(args.disc)
        _fh, _b, _s, databin_size = open_source(args.disc)
        _fh.close()
        indices = [r["index"] for r in rows if row_fits(r, databin_size)]
    else:
        indices = args.index
    _written, bad = extract_rows(args.disc, indices, out)
    return 1 if bad else 0


def _by_hash(doc):
    groups = {}
    for rec in doc["files"]:
        if not rec.get("sha256"):
            continue
        groups.setdefault(rec["sha256"], []).append(rec)
    return groups


def cmd_compare(_args):
    docs = {}
    for name in ("pal", "us"):
        doc, path = load_manifest(name)
        if doc is None:
            print("no %s; verifying" % path, file=sys.stderr)
            doc = scan(name)
            path = write_manifest(doc)
            print("manifest %s" % path)
        docs[name] = doc
    pal = _by_hash(docs["pal"])
    us = _by_hash(docs["us"])
    both = sorted(set(pal) & set(us))
    pal_only = sorted(set(pal) - set(us))
    us_only = sorted(set(us) - set(pal))
    identical = []
    for digest in both:
        pr, ur = pal[digest][0], us[digest][0]
        identical.append({
            "sha256": digest,
            "size": pr["size"],
            "fmt": pr["fmt"],
            "pal": [r["index"] for r in pal[digest]],
            "us": [r["index"] for r in us[digest]],
        })
    def only(groups, digests):
        out = []
        for digest in digests:
            recs = groups[digest]
            out.append({
                "sha256": digest,
                "size": recs[0]["size"],
                "fmt": recs[0]["fmt"],
                "index": [r["index"] for r in recs],
            })
        return out
    # Same size, different bytes: a size that appears on both discs but no shared hash of that size.
    pal_sizes = {}
    us_sizes = {}
    for digest, recs in pal.items():
        pal_sizes.setdefault(recs[0]["size"], set()).add(digest)
    for digest, recs in us.items():
        us_sizes.setdefault(recs[0]["size"], set()).add(digest)
    same_size_differ = 0
    for size, pset in pal_sizes.items():
        uset = us_sizes.get(size)
        if not uset:
            continue
        if pset.isdisjoint(uset):
            same_size_differ += 1
    summary = {
        "pal_rows": docs["pal"]["rows"],
        "us_rows": docs["us"]["rows"],
        "pal_loadable": docs["pal"]["loadable"],
        "us_loadable": docs["us"]["loadable"],
        "pal_bad": docs["pal"]["bad"],
        "us_bad": docs["us"]["bad"],
        "pal_unique": len(pal),
        "us_unique": len(us),
        "identical_hashes": len(both),
        "pal_only_hashes": len(pal_only),
        "us_only_hashes": len(us_only),
        "identical_pal_rows": sum(len(pal[d]) for d in both),
        "identical_us_rows": sum(len(us[d]) for d in both),
        "same_size_no_shared_hash": same_size_differ,
        "pal_formats": docs["pal"]["formats_coarse"],
        "us_formats": docs["us"]["formats_coarse"],
    }
    doc = {
        "summary": summary,
        "identical": identical,
        "pal_only": only(pal, pal_only),
        "us_only": only(us, us_only),
    }
    dest_dir = os.path.join(repo_root(), "logs", "databin")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, "compare.json")
    if os.path.exists(dest):
        n = 2
        while os.path.exists(os.path.join(dest_dir, "compare-%d.json" % n)):
            n += 1
        dest = os.path.join(dest_dir, "compare-%d.json" % n)
    with open(dest, "xb") as f:
        f.write(json.dumps(doc).encode("utf-8"))
        f.write(b"\n")
    lines = [
        "pal_loadable %d bad %d unique %d" % (summary["pal_loadable"], summary["pal_bad"], summary["pal_unique"]),
        "us_loadable %d bad %d unique %d" % (summary["us_loadable"], summary["us_bad"], summary["us_unique"]),
        "identical_hashes %d (pal rows %d, us rows %d)" % (
            summary["identical_hashes"], summary["identical_pal_rows"], summary["identical_us_rows"]),
        "pal_only_hashes %d us_only_hashes %d" % (summary["pal_only_hashes"], summary["us_only_hashes"]),
        "same_size_but_no_shared_hash %d" % summary["same_size_no_shared_hash"],
        "pal_formats %s" % json.dumps(summary["pal_formats"], sort_keys=True),
        "us_formats %s" % json.dumps(summary["us_formats"], sort_keys=True),
        "table %s" % dest,
    ]
    text_path = os.path.splitext(dest)[0] + ".txt"
    text = ["\n".join(lines), "sha256 size fmt pal us"]
    for row in identical:
        text.append("%s %d %s %s %s" % (row["sha256"], row["size"], row["fmt"], row["pal"], row["us"]))
    text.append("# pal only")
    for row in doc["pal_only"]:
        text.append("%s %d %s pal %s" % (row["sha256"], row["size"], row["fmt"], row["index"]))
    text.append("# us only")
    for row in doc["us_only"]:
        text.append("%s %d %s us %s" % (row["sha256"], row["size"], row["fmt"], row["index"]))
    with open(text_path, "xb") as f:
        f.write(("\n".join(text) + "\n").encode("utf-8"))
    print("\n".join(lines))
    print("text %s" % text_path)
    return 1 if summary["pal_bad"] or summary["us_bad"] else 0


def build_parser():
    p = argparse.ArgumentParser(
        prog="databin.py",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("list", help="print the file table (add --check to verify checksums)")
    sp.add_argument("disc", choices=("pal", "us"))
    sp.add_argument("--check", action="store_true", help="read DATA.BIN and verify every checksum")
    sp.add_argument("--json", help="also write this JSON file (must not already exist)")
    sp.set_defaults(func=cmd_list)
    sp = sub.add_parser("verify", help="checksum every loadable file and write logs/databin/<disc>/manifest.json")
    sp.add_argument("disc", choices=("pal", "us", "both"))
    sp.set_defaults(func=cmd_verify)
    sp = sub.add_parser("extract", help="write decrypted files under --out (default logs/databin/<disc>/files)")
    sp.add_argument("disc", choices=("pal", "us"))
    sp.add_argument("--index", type=int, action="append", default=[], help="one file index; repeat for several")
    sp.add_argument("--all", action="store_true", help="every loadable file (about 2.6 GB per disc)")
    sp.add_argument("--out", help="output directory")
    sp.set_defaults(func=cmd_extract)
    sp = sub.add_parser("compare", help="PAL vs US by sha256 of decrypted bytes (verifies first if needed)")
    sp.set_defaults(func=cmd_compare)
    return p


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except UsageError as exc:
        print("databin.py: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
