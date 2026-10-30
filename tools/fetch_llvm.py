"""Release maintainer: fetch a pinned LLVM/CMake/Ninja payload. Not run by players."""
import argparse
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_payload import fetch, tree_digest, unpack_selected


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--component", choices=("llvm", "cmake", "ninja"), default="llvm")
    p.add_argument("--cache", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True, help="new directory; never overwritten")
    a = p.parse_args()
    lock = json.loads(Path(__file__).with_name("release_toolchain.json").read_text(encoding="utf-8"))[a.component]
    archive = fetch(lock, a.cache)
    unpack_selected(archive, a.output, a.component)
    required = {"llvm": ("bin/clang-cl.exe", "bin/lld-link.exe", "bin/llvm-lib.exe", "bin/llvm-rc.exe", "bin/llvm-mt.exe"),
                "cmake": ("bin/cmake.exe",), "ninja": ("ninja.exe",)}
    for name in required[a.component]:
        if not (a.output / name).is_file():
            raise ValueError("official archive lacks required file: " + name)
    if a.component == "llvm" and not list((a.output / "lib" / "clang").glob("*/include/stddef.h")):
        raise ValueError("LLVM resource headers are missing")
    receipt = dict(lock, tree_sha256=tree_digest(a.output))
    (a.output / ".t4-payload.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(a.output)


if __name__ == "__main__":
    main()
