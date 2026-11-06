#!/usr/bin/env python3
"""Maintainer tool (0.1.4): build the prebuilt game program of a release zip -- bin\\runtime and bin\\tools.

    python tools/build_release_runtime.py --work <empty dir> --tree <prepared PS2Recomp tree> --fetch <deps\\fetch>
        --ffmpeg <ffmpeg zip> --python <dir> --llvm <dir> --cmake <dir> --ninja <dir> --sysroot <dir> --sysroot-lock <msvc_sysroot.lock.json> --licenses <dir> --out <stage>\\bin

The player's PC no longer compiles the runtime (0.1.3 did, after downloading ~240 MB of Microsoft's C++ files): we
compile it once here, with the same pinned clang-cl / lld-link / CMake / Ninja and Microsoft's static C/C++ runtime
(our own sysroot, tools/fetch_msvc_sysroot.py), in PS2X_GAME_DLL mode (patches/99): ps2EntryRunner.exe holds the
PS2Recomp runtime and our game modules (runtime\\*.cpp) but no game code; it loads ps2_game.dll, which the player's PC
builds from their own disc (tools/build_game_dll.py). Two variants: SSE4.1 (ps2EntryRunner.exe) and SSE2 for old
processors (ps2EntryRunner-sse2.exe, PS2X_SIMD_BASELINE: the same game state). bin\\tools\\ps2_recomp.exe is the
recompiler the player runs on their disc. None of these files contain anything from the game.

The work folder is a 0.1.3-style portable tree (toolchain, deps\\ps2recomp, deps\\fetch, deps\\ffmpeg, python, tools) made
of links and copies; the inputs are never changed.
"""
import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FETCH = ("raylib", "imgui", "rlimgui", "sse2neon", "elfio", "toml11", "fmt", "libdwarf", "rabbitizer")
NO_WINDOW = 0x08000000 if os.name == "nt" else 0


def link_dir(link, target):
    link.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cmd", "/d", "/c", "mklink", "/J", str(link), str(target)], check=True, capture_output=True,
                   creationflags=NO_WINDOW)


def copy_tree(src, dst, skip=()):
    for path in Path(src).rglob("*"):
        rel = path.relative_to(src)
        if any(part.lower() in skip for part in rel.parts) or not path.is_file():
            continue
        (dst / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dst / rel)


def assemble(a, work):
    t4 = work / "T4"
    if t4.exists():
        raise SystemExit(f"ERROR: {t4} exists; give a new --work folder")
    tc = t4 / "toolchain"
    for name, path in (("llvm", a.llvm), ("cmake", a.cmake), ("ninja", a.ninja)):
        link_dir(tc / name, Path(path).resolve())
    for name in ("msvc", "winsdk"):
        link_dir(tc / name, Path(a.sysroot).resolve() / name)
    shutil.copy2(Path(a.sysroot) / "sysroot.json", tc / "sysroot.json")
    shutil.copy2(ROOT / "tools" / "release_toolchain.json", tc / "toolchain.json")
    link_dir(t4 / "python", Path(a.python).resolve())
    for name in FETCH:
        link_dir(t4 / "deps" / "fetch" / name, Path(a.fetch).resolve() / name)
    (t4 / "deps" / "ffmpeg").mkdir(parents=True)
    shutil.copy2(a.ffmpeg, t4 / "deps" / "ffmpeg" / "ffmpeg.zip")
    copy_tree(Path(a.tree), t4 / "deps" / "ps2recomp", {".git", "out", "__pycache__"})
    for name in ("tools", "runtime", "patches", "config"):
        copy_tree(ROOT / name, t4 / name, {"__pycache__", "pal"})
    shutil.copy2(a.sysroot_lock, t4 / "tools" / "msvc_sysroot.lock.json")
    (t4 / "LICENSES").mkdir()
    for name in ("microsoft-build-tools", "microsoft-windows-sdk"):     # the sysroot check wants the reviewed texts
        shutil.copy2(Path(a.licenses) / (name + ".txt"), t4 / "LICENSES" / (name + ".txt"))
    # Our game modules, as tools\stage_generated.cmd stages them (no generated code: it is the DLL's).
    runner = t4 / "deps" / "ps2recomp" / "ps2xRuntime" / "src" / "runner"
    for pattern in ("*_overrides.cpp", "tekken4_net*.cpp", "tekken4_*.h"):
        for path in (ROOT / "runtime").glob(pattern):
            shutil.copy2(path, runner / path.name)
    return t4


def run(cmd, env, log):
    started = time.monotonic()
    with open(log, "a", encoding="utf-8") as out:
        out.write("> " + subprocess.list2cmdline([str(c) for c in cmd]) + "\n")
        out.flush()
        r = subprocess.run([str(c) for c in cmd], env=env, stdout=out, stderr=subprocess.STDOUT, creationflags=NO_WINDOW)
    print(f"    {Path(str(cmd[0])).name} {' '.join(str(c) for c in cmd[1:3])}: exit {r.returncode} ({time.monotonic() - started:.0f}s)", flush=True)
    if r.returncode:
        raise SystemExit(f"ERROR: build failed, see {log}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    for name in ("work", "tree", "fetch", "ffmpeg", "python", "llvm", "cmake", "ninja", "sysroot", "sysroot-lock", "licenses", "out"):
        ap.add_argument("--" + name, required=True)
    a = ap.parse_args(argv)
    work, out = Path(a.work).resolve(), Path(a.out).resolve()
    if out.exists() and any(out.iterdir()):
        raise SystemExit(f"ERROR: {out} is not empty")
    work.mkdir(parents=True, exist_ok=True)
    t4 = assemble(a, work)
    sys.path.insert(0, str(t4 / "tools"))
    import build_game
    b = build_game.Build(build_game.parser().parse_args(["-LogDir", str(work / "logs")]), t4)
    assert b.portable and not b.prebuilt
    b.compiler_environment()
    log = work / "build.log"
    exports = (t4 / "tools" / "gamedll" / "ps2_runtime_exports.def").as_posix()
    built = {}
    for variant, baseline in (("sse41", "0"), ("sse2", "1")):
        env = dict(b.env, TEKKEN4_SIMD_BASELINE=baseline, TEKKEN4_VULIFT="0", TEKKEN4_VU1N="0")
        configure, build = build_game.cmake_plan(t4, b.tree, "host-" + variant, True, True, env)
        configure += ["-DPS2X_GAME_DLL=ON", "-DPS2X_GAME_DLL_DEF=" + exports]
        print(f"runtime ({variant})", flush=True)
        run(configure, b.env, log)
        run(build, b.env, log)
        built[variant] = b.tree / "out" / ("host-" + variant) / "ps2xRuntime"
    print("recompiler (ps2_recomp.exe)", flush=True)
    configure, build = build_game.cmake_plan(t4, b.tree, "tools", False, True, b.env)
    run(configure, b.env, log)
    run(build, b.env, log)
    recomp = b.tree / "out" / "tools" / "ps2xRecomp"

    (out / "runtime").mkdir(parents=True)
    (out / "tools").mkdir(parents=True)
    shutil.copy2(built["sse41"] / "ps2EntryRunner.exe", out / "runtime" / "ps2EntryRunner.exe")
    shutil.copy2(built["sse2"] / "ps2EntryRunner.exe", out / "runtime" / "ps2EntryRunner-sse2.exe")
    dlls = sorted(p.name for p in built["sse41"].glob("*.dll"))
    if dlls != sorted(p.name for p in built["sse2"].glob("*.dll")):
        raise SystemExit("ERROR: the two runtime variants ship different DLLs")
    for name in dlls:
        shutil.copy2(built["sse41"] / name, out / "runtime" / name)
    shutil.copy2(recomp / "ps2_recomp.exe", out / "tools" / "ps2_recomp.exe")
    for dll in recomp.glob("*.dll"):
        shutil.copy2(dll, out / "tools" / dll.name)
    print(f"bin written: {out} (runtime: 2 programs + {len(dlls)} DLLs)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
