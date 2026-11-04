"""The build identity both players of a Tekken 4 netplay match must share (rollback phase 3, docs/ROLLBACK_PHASE3.md).

Rollback netplay only works when both PCs run identical game code. Like T5DR Online's lobby/t5lobby/buildid.py:

    elf_sha1  SHA-1 of game/disc/SLUS_203.28 (the game itself: a4b7dde2... for SLUS-20328 v1.00)
    code_id   SHA-1 over the PS2Recomp tree's content (tree id, not the commit: build_game.ps1 commits the patches at
              build time, so every player's commit differs) and uncommitted diff, our patches/*.patch, config/*.toml,
              config/*.csv (function maps: what the recompiler generated), the game modules staged into the
              runner (src/runner/*_overrides.cpp, tekken4_net*.cpp/.h, tekken4_state_probe.h,
              tekken4_online_result.h), and the toolchain of the CMake build: compiler
              id and exact version, build type, flags, PS2X_* options (players compile locally: another compiler
              version can round floats differently and desync). No paths, they differ per PC.
    net       the netplay protocol version (runtime/tekken4_net.h kNetVersion)

build id = first 16 hex digits of SHA-1("t4dr-build:<elf_sha1>:<code_id>:<net>").

    python -I tools/t4_buildid.py --src .\\deps\\ps2recomp --out .\\deps\\ps2recomp\\out\\runtime\\ps2xRuntime

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


def sha1_text(path):
    """Line endings do not change the code: a git checkout (autocrlf) and a release zip must give the same id."""
    with open(path, "rb") as f:
        return hashlib.sha1(f.read().replace(b"\r\n", b"\n")).hexdigest()


def net_version():
    text = open(os.path.join(ROOT, "runtime", "tekken4_net.h"), encoding="utf-8").read()
    m = re.search(r"kNetVersion\s*=\s*(\d+)", text)
    return int(m.group(1)) if m else 0


def git(src, *args):
    return subprocess.run(["git", "-C", src] + list(args), capture_output=True, check=False).stdout


def toolchain(build):
    """What the CMake build at <build> compiles with, one "name=value" per line. Exits when it cannot be read: an id
    without the compiler would match a peer on another compiler."""
    cache_path = os.path.join(build, "CMakeCache.txt")
    if not os.path.isfile(cache_path):
        sys.exit(f"no CMake build at {build}: build the runtime first, or pass --build")
    cache = {}
    with open(cache_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r"([A-Za-z0-9_.\-]+):([A-Z]+)=(.*)$", line.rstrip("\r\n"))
            if m:
                cache[m.group(1)] = (m.group(2), m.group(3))
    cmake = ".".join(cache.get(f"CMAKE_CACHE_{p}_VERSION", ("", ""))[1] for p in ("MAJOR", "MINOR", "PATCH"))
    lines = []
    for lang, name in (("C", "CMakeCCompiler.cmake"), ("CXX", "CMakeCXXCompiler.cmake")):
        path = os.path.join(build, "CMakeFiles", cmake, name)
        text = open(path, encoding="utf-8", errors="replace").read() if os.path.isfile(path) else ""
        for key in ("ID", "VERSION", "ARCHITECTURE_ID"):
            m = re.search(rf'set\(CMAKE_{lang}_COMPILER_{key} "([^"]+)"\)', text)
            if not m:
                sys.exit(f"{path}: no CMAKE_{lang}_COMPILER_{key}")
            lines.append(f"{lang}_{key}={m.group(1)}")
    build_type = cache.get("CMAKE_BUILD_TYPE", ("", ""))[1]
    lines.append(f"build_type={build_type}")
    for var in ("CMAKE_C_FLAGS", "CMAKE_CXX_FLAGS", f"CMAKE_C_FLAGS_{build_type.upper()}",
                f"CMAKE_CXX_FLAGS_{build_type.upper()}"):
        lines.append(f"{var}={' '.join(cache.get(var, ('', ''))[1].split())}")
    for name in sorted(cache):
        if name.startswith("PS2X_") and cache[name][0] == "BOOL":
            lines.append(f"{name}={cache[name][1]}")
    # native VU1 blocks or the interpreter; the directory itself is a path
    lines.append(f"vu1_native={1 if cache.get('PS2X_VU1_MICROCODE_DIR', ('', ''))[1] else 0}")
    return lines


def code_id(src, tool_lines):
    h = hashlib.sha1()
    h.update(b"toolchain:" + "\n".join(tool_lines).encode())
    marker = os.path.join(src, ".t4-vendored.json")
    if os.path.isfile(marker):
        # Released sources have no Git. Hash actual source contents, never absolute paths or build outputs.
        h.update(b"vendored:" + sha1_text(marker).encode())
        for folder, dirs, files in os.walk(src):
            dirs[:] = sorted(d for d in dirs if d not in (".git", "out", "build", "generated", "__pycache__"))
            for name in sorted(files):
                path = os.path.join(folder, name)
                rel = os.path.relpath(path, src).replace("\\", "/")
                if rel.startswith("ps2xRuntime/src/runner/"):
                    continue  # generated code is identified by the ELF; overrides are hashed below
                if name.endswith((".cpp", ".c", ".h", ".hpp", ".inl", ".cmake", ".txt")):
                    h.update(b"source:" + rel.encode() + b":" + sha1_text(path).encode())
    else:
        h.update(b"tree:" + git(src, "rev-parse", "HEAD^{tree}").strip())
        # uncommitted edits of the tree, without the staged generated code / game modules (hashed below)
        h.update(b"diff:" + git(src, "diff", "HEAD", "--", ".", ":(exclude)ps2xRuntime/src/runner"))
    for path in sorted(glob.glob(os.path.join(ROOT, "patches", "*.patch"))):
        h.update(b"patch:" + os.path.basename(path).encode() + b":" + sha1_text(path).encode())
    for pattern in ("*.toml", "*.csv"):
        for path in sorted(glob.glob(os.path.join(ROOT, "config", pattern))):
            h.update(b"config:" + os.path.basename(path).encode() + b":" + sha1_text(path).encode())
    runner = os.path.join(src, "ps2xRuntime", "src", "runner")
    for pattern in ("*_overrides.cpp", "tekken4_net*.cpp", "tekken4_net*.h",
                    "tekken4_state_probe.h", "tekken4_online_result.h", "tekken4_match_state.h"):
        for path in sorted(glob.glob(os.path.join(runner, pattern))):
            h.update(b"module:" + os.path.basename(path).encode() + b":" + sha1_text(path).encode())
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=us_tree())
    ap.add_argument("--out", help="directory for t4net_build.txt/.json (default: print only)")
    ap.add_argument("--build", help="CMake build directory (default: the parent of --out, else <src>/out/$TEKKEN4_BUILD_DIR or out/runtime)")
    ap.add_argument("--elf", default=os.path.join(ROOT, "game", "disc", "SLUS_203.28"))
    a = ap.parse_args()
    cmake_build = a.build or (os.path.dirname(os.path.abspath(a.out)) if a.out else
                              os.path.join(a.src, "out", os.environ.get("TEKKEN4_BUILD_DIR") or "runtime"))
    tool_lines = toolchain(cmake_build)
    elf = sha1_file(a.elf)
    code = code_id(a.src, tool_lines)
    net = net_version()
    build = hashlib.sha1(f"t4dr-build:{elf}:{code}:{net}".encode()).hexdigest()[:16]
    print(f"{build} elf {elf} code {code} net {net}")
    print("toolchain: " + "; ".join(tool_lines[:6]))
    if a.out:
        with open(os.path.join(a.out, "t4net_build.txt"), "w", encoding="ascii") as f:
            f.write(f"{build} {elf} {code} {net}\n")
        with open(os.path.join(a.out, "t4net_build.json"), "w", encoding="utf-8") as f:
            json.dump({"id": build, "elf": elf, "code": code, "net": net, "toolchain": tool_lines}, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
