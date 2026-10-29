"""The build identity both players of a Tekken 4 netplay match must share (rollback phase 3, docs/ROLLBACK_PHASE3.md).

Rollback netplay only works when both PCs run identical game code. Like T5DR Online's lobby/t5lobby/buildid.py:

    elf_sha1  SHA-1 of game/disc/SLUS_203.28 (the game itself: a4b7dde2... for SLUS-20328 v1.00)
    code_id   SHA-1 over the PS2Recomp tree's commit and uncommitted diff, our patches/*.patch, config/*.toml,
              config/*.csv (function maps: what the recompiler generated), and the game modules staged into the
              runner (src/runner/*_overrides.cpp, tekken4_net*.cpp/.h)
    net       the netplay protocol version (runtime/tekken4_net.h kNetVersion)

build id = first 16 hex digits of SHA-1("t4dr-build:<elf_sha1>:<code_id>:<net>").

    python -I tools/t4_buildid.py --src D:\\tekken4-fork-net --out D:\\tekken4-fork-net\\out\\net\\ps2xRuntime

writes <out>/t4net_build.txt ("<id> <elf_sha1> <code_id> <net>") and t4net_build.json; tools/net_pair.ps1 passes the
id as TEKKEN4_NET_BUILD, and a peer whose HELLO carries another id is refused (build_mismatch).
"""
import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def us_tree():
    """tools/us_tree.ps1's rule: TEKKEN4_SRC, else ../tekken4-fork-ps2recomp_usa when it exists, else the plain sibling
    when it is free or on branch t4-us, else ../tekken4-fork-ps2recomp_usa (the plain one is the PAL cousin project's)."""
    if os.environ.get("TEKKEN4_SRC"):
        return os.environ["TEKKEN4_SRC"]
    parent = os.path.dirname(ROOT)
    own = os.path.join(parent, "tekken4-fork-ps2recomp_usa")
    plain = os.path.join(parent, "tekken4-fork-ps2recomp")
    if os.path.isdir(own):
        return own
    if not os.path.isdir(os.path.join(plain, ".git")):
        return plain
    branch = subprocess.run(["git", "-C", plain, "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True,
                            text=True).stdout.strip()
    return plain if branch == "t4-us" else own


def sha1_file(path, chunk=1 << 20):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def net_version():
    text = open(os.path.join(ROOT, "runtime", "tekken4_net.h"), encoding="utf-8").read()
    m = re.search(r"kNetVersion\s*=\s*(\d+)", text)
    return int(m.group(1)) if m else 0


def git(src, *args):
    return subprocess.run(["git", "-C", src] + list(args), capture_output=True, check=False).stdout


def code_id(src):
    h = hashlib.sha1()
    h.update(b"commit:" + git(src, "rev-parse", "HEAD").strip())
    # uncommitted edits of the tree, without the staged generated code / game modules (hashed below)
    h.update(b"diff:" + git(src, "diff", "HEAD", "--", ".", ":(exclude)ps2xRuntime/src/runner"))
    for path in sorted(glob.glob(os.path.join(ROOT, "patches", "*.patch"))):
        h.update(b"patch:" + os.path.basename(path).encode() + b":" + sha1_file(path).encode())
    for pattern in ("*.toml", "*.csv"):
        for path in sorted(glob.glob(os.path.join(ROOT, "config", pattern))):
            h.update(b"config:" + os.path.basename(path).encode() + b":" + sha1_file(path).encode())
    runner = os.path.join(src, "ps2xRuntime", "src", "runner")
    for pattern in ("*_overrides.cpp", "tekken4_net*.cpp", "tekken4_net*.h"):
        for path in sorted(glob.glob(os.path.join(runner, pattern))):
            h.update(b"module:" + os.path.basename(path).encode() + b":" + sha1_file(path).encode())
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=us_tree())
    ap.add_argument("--out", help="directory for t4net_build.txt/.json (default: print only)")
    ap.add_argument("--elf", default=os.path.join(ROOT, "game", "disc", "SLUS_203.28"))
    a = ap.parse_args()
    elf = sha1_file(a.elf)
    code = code_id(a.src)
    net = net_version()
    build = hashlib.sha1(f"t4dr-build:{elf}:{code}:{net}".encode()).hexdigest()[:16]
    print(f"{build} elf {elf} code {code} net {net}")
    if a.out:
        with open(os.path.join(a.out, "t4net_build.txt"), "w", encoding="ascii") as f:
            f.write(f"{build} {elf} {code} {net}\n")
        with open(os.path.join(a.out, "t4net_build.json"), "w", encoding="utf-8") as f:
            json.dump({"id": build, "elf": elf, "code": code, "net": net}, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
