#!/usr/bin/env python3
"""Compile the code generated from the player's disc into ps2_game.dll -- clang-cl + lld-link only (0.1.4).

    python -I tools/build_game_dll.py --tree <PS2Recomp tree> --generated generated --vulift <dir> --out <dir>/ps2_game.dll
                                      [--simd sse41|sse2] [--jobs N] [--obj DIR] [--llvm DIR]

The player's half of the "nothing to download" build, the way T5DR Online does it (its tools/build_game_dll.py):
ps2EntryRunner.exe -- the PS2Recomp runtime with our game modules, no game code -- is compiled once by us
(PS2X_GAME_DLL, patches/99-ps2xRuntime-game-dll.patch) and shipped in bin/runtime. The player's PC compiles only what
came out of their own disc: the functions ps2_recomp.exe wrote to generated/ and the VU programs tools/vu/vu_lift.py
lifted from the disc's microcode. That code needs no C++ standard library and no Windows SDK: clang's own headers plus
the few declarations in tools/gamedll/include, the runtime's headers in their game-DLL view (PS2X_GAME_DLL_VIEW), and it
links against an import library made from tools/gamedll/ps2_runtime_exports.def (what ps2EntryRunner.exe exports, its C
runtime's memset/sqrtf included: one implementation for every player). clang-cl, lld-link and clang's headers are
redistributable (Apache-2.0 WITH LLVM-exception).

Same inputs, same DLL: the sources are compiled in fixed batches (the same on every PC), with relative names only, and
linked with /Brepro, so two players' DLLs are byte-identical (tools/t4_buildid.py relies on the inputs, not the bytes:
the SSE2 build of the same code must keep the same identity).

A batch whose sources, headers and flags are unchanged keeps its object (a second Build compiles nothing). Progress
lines are "[k/n] ..." like ninja's, so the launcher's progress bar follows them.
Test hooks (environment): T4_DLL_TEST_FREE_MB = the free memory the job count sees.
"""
import argparse
import concurrent.futures
import glob
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GDIR = ROOT / "tools" / "gamedll"
NO_WINDOW = 0x08000000 if os.name == "nt" else 0
BATCHES = 32                  # fixed: the same batches (and objects) on every PC
FORMAT = 1                    # bump when the batching or the object stamp changes
JOB_MB = 900                  # one clang-cl on a batch of generated code: ~0.3-0.7 GB measured (LLVM 23.1.3)
RESERVE_MB = 1024

# Same code generation as the CMake build of 0.1.3 had for the generated code (RelWithDebInfo /O2 /Ob2, C++20, the
# _MSC_VER clang-cl had there), minus what needs a C runtime: no exceptions, no RTTI, no thread-safe static guards, no
# stack cookies, no default libraries. /X: no system include paths -- only clang's own headers and ours.
FLAGS = ["/nologo", "/X", "-TP", "-std:c++20", "/O2", "/Ob2", "/DNDEBUG", "/GS-", "/Zl", "/EHs-c-", "/GR-",
         "/Zc:threadSafeInit-", "-fms-compatibility-version=19.44.35229", "/clang:-fno-caret-diagnostics",
         "-DPS2X_GAME_DLL_VIEW=1", "-DPS2_RUNTIME_LOGS=1", "-DPS2X_ENABLE_IOP_RPC_TRACE=1",
         "-Wno-everything"]


def say(text):
    print(text, flush=True)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def find_llvm(explicit=None):
    for cand in ([Path(explicit)] if explicit else []) + [ROOT / "toolchain" / "llvm" / "bin"]:
        if (cand / "clang-cl.exe").is_file() and (cand / "lld-link.exe").is_file():
            return cand
    raise SystemExit("ERROR: clang-cl.exe / lld-link.exe not found in toolchain\\llvm\\bin (unpack the release zip again)")


def free_mb():
    test = os.environ.get("T4_DLL_TEST_FREE_MB")
    if test:
        return int(test)
    if os.name != "nt":
        return 1 << 20
    import ctypes

    class MemoryStatus(ctypes.Structure):
        _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong), ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong), ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong), ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong), ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]
    status = MemoryStatus()
    status.dwLength = ctypes.sizeof(status)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
        return 1 << 20
    return int(min(status.ullAvailPhys, status.ullAvailPageFile) // (1 << 20))


def auto_jobs(requested):
    cpus = os.cpu_count() or 2
    if requested:
        return max(1, requested), f"{requested} (asked for)"
    by_memory = max(1, (free_mb() - RESERVE_MB) // JOB_MB)
    jobs = max(1, min(cpus, by_memory, BATCHES))
    why = "processors" if jobs == min(cpus, BATCHES) else "free memory"
    return jobs, f"{jobs} ({why}: {cpus} processors, {free_mb()} MB free)"


def batches(sources):
    """Fixed round-robin over the sorted names: every PC gets the same batches."""
    names = sorted(sources, key=lambda p: p.name.lower())
    return [names[i::BATCHES] for i in range(BATCHES) if names[i::BATCHES]]


def header_digest(dirs):
    h = hashlib.sha256()
    for d in dirs:
        for path in sorted(Path(d).rglob("*"), key=lambda p: p.as_posix().lower()):
            if path.is_file() and path.suffix.lower() in ("", ".h", ".hpp", ".inl"):
                h.update(path.relative_to(d).as_posix().encode() + b"\0" + sha256_file(path).encode() + b"\n")
    return h.hexdigest()


def compile_one(cl, cwd, flags, src_rel, obj_rel):
    cmd = [str(cl)] + flags + ["/c", "/Fo" + obj_rel, src_rel]
    started = time.monotonic()
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace",
                       creationflags=NO_WINDOW)
    return r.returncode, (r.stdout or "") + (r.stderr or ""), time.monotonic() - started


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--tree", required=True, help="PS2Recomp tree with patch 99 (source\\ps2recomp in a release)")
    ap.add_argument("--generated", required=True, help="ps2_recomp.exe's output (generated\\)")
    ap.add_argument("--vulift", default="", help="folder with vulift_part*.cpp (empty: no lifted VU programs)")
    ap.add_argument("--out", required=True, help="ps2_game.dll to write")
    ap.add_argument("--obj", default="", help="object folder (default: build\\gamedll\\<simd>)")
    ap.add_argument("--simd", choices=("sse41", "sse2"), default="sse41")
    ap.add_argument("--jobs", type=int, default=0)
    ap.add_argument("--llvm", default="")
    a = ap.parse_args(argv)

    llvm = find_llvm(a.llvm)
    cl, lld = llvm / "clang-cl.exe", llvm / "lld-link.exe"
    tree = Path(a.tree).resolve()
    rt = tree / "ps2xRuntime"
    gen = Path(a.generated).resolve()
    obj = Path(a.obj).resolve() if a.obj else (ROOT / "build" / "gamedll" / a.simd)
    obj.mkdir(parents=True, exist_ok=True)
    out = Path(a.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    if not (gen / "register_functions.cpp").is_file():
        raise SystemExit(f"ERROR: {gen} has no register_functions.cpp: run the recomp step first")
    if not (rt / "include" / "ps2_game_dll_abi.h").is_file():
        raise SystemExit(f"ERROR: {tree} is not the PS2Recomp tree of this release (no game-DLL view)")

    # Only clang's own and our headers; nothing of an installed Visual Studio / Windows SDK can leak in.
    env = {k: v for k, v in os.environ.items()
           if k.upper() not in ("INCLUDE", "LIB", "LIBPATH", "EXTERNAL_INCLUDE", "CL", "_CL_", "LINK", "_LINK_",
                                "CPATH", "C_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "CCC_OVERRIDE_OPTIONS",
                                "VCINSTALLDIR", "VCTOOLSINSTALLDIR", "WINDOWSSDKDIR", "UCRTVERSION", "UNIVERSALCRTSDKDIR")}
    os.environ.clear()
    os.environ.update(env)

    simd = ["-msse4.1"] if a.simd == "sse41" else ["-DPS2X_SIMD_BASELINE=1", "/FI" + str(rt / "include" / "ps2_simd_baseline.h")]
    includes = ["/FI" + str(GDIR / "include" / "t4_dll_prefix.h"), "-I" + str(GDIR / "include"),
                "-I" + str(rt / "include"), "-I" + str(rt / "src" / "lib" / "Kernel"), "-I" + str(gen), "-I" + str(GDIR)]
    if a.vulift:
        includes.append("-I" + str(Path(a.vulift).resolve()))
    flags = FLAGS + simd + includes
    # What the objects depend on besides their own sources: the flags (without the folder names), the compiler, the
    # headers. A batch is compiled again when any of these or one of its sources changed.
    stamp_base = hashlib.sha256(json.dumps(dict(format=FORMAT, flags=FLAGS + [s.replace(str(rt), "<tree>") for s in simd],
                                                compiler=sha256_file(cl),
                                                headers=header_digest([GDIR / "include", rt / "include", rt / "src" / "lib" / "Kernel"]),
                                                gen_headers=[sha256_file(p) for p in sorted(gen.glob("*.h"))]),
                                           sort_keys=True).encode()).hexdigest()

    units = []                                   # (name, unity source text or None, [sources])
    for i, group in enumerate(batches(list(gen.glob("*.cpp")))):
        units.append((f"gen_{i:02d}", "".join(f'#include "{p.name}"\n' for p in group), group))
    for part in sorted(Path(a.vulift).glob("vulift_part*.cpp")) if a.vulift else []:
        units.append((part.stem, f'#include "{part.name}"\n', [part]))
    entry = GDIR / "t4_game_dll.cpp"
    units.append(("t4_game_dll", f'#include "{entry.name}"\n', [entry]))

    jobs, why = auto_jobs(a.jobs)
    say(f"game DLL: {len(units)} parts ({sum(len(u[2]) for u in units)} source files), {a.simd}, jobs {why}")
    todo, kept = [], 0
    stamps = {}
    for name, text, sources in units:
        h = hashlib.sha256((stamp_base + text).encode())
        for s in sources:
            h.update(s.name.encode() + b"\0" + sha256_file(s).encode())
        stamps[name] = h.hexdigest()
        unity = obj / f"u_{name}.cpp"
        stamp = obj / f"{name}.stamp"
        if (obj / f"{name}.obj").is_file() and stamp.is_file() and stamp.read_text(encoding="ascii").strip() == stamps[name]:
            kept += 1
            continue
        if not unity.is_file() or unity.read_text(encoding="utf-8") != text:
            unity.write_text(text, encoding="utf-8")
        stamp.unlink(missing_ok=True)
        todo.append(name)
    if kept:
        say(f"    {kept} of {len(units)} parts unchanged (objects kept)")

    started = time.monotonic()
    failed = []
    if todo:
        compile_flags = flags + ["-DT4_GAME_DLL_SIMD=" + ("1" if a.simd == "sse41" else "0")]
        with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
            futures = {pool.submit(compile_one, cl, obj, compile_flags, f"u_{n}.cpp", f"{n}.obj"): n for n in todo}
            done = 0
            for fut in concurrent.futures.as_completed(futures):
                n = futures[fut]
                code, text, took = fut.result()
                done += 1
                if code:
                    failed.append((n, text))
                    say(f"[{done}/{len(todo)}] FAILED {n} ({took:.1f}s)")
                else:
                    (obj / f"{n}.stamp").write_text(stamps[n] + "\n", encoding="ascii")
                    say(f"[{done}/{len(todo)}] compiled {n} ({took:.1f}s)")
        if failed:
            for n, text in failed[:3]:
                lines = [l for l in text.splitlines() if l.strip()]
                say(f"--- {n} ---")
                for line in [l for l in lines if " error" in l or "fatal" in l][:20] or lines[-20:]:
                    say("    " + line)
            say(f"ERROR: {len(failed)} part(s) of the game code did not compile")
            return 1
    took_compile = time.monotonic() - started

    objs = [f"{name}.obj" for name, _, _ in units]
    link_stamp = hashlib.sha256(("".join(stamps[n] for n, _, _ in units) + sha256_file(lld) +
                                 sha256_file(GDIR / "ps2_runtime_exports.def")).encode()).hexdigest()
    stamp_file = obj / "ps2_game.dll.stamp"
    if out.is_file() and stamp_file.is_file() and stamp_file.read_text(encoding="ascii").strip() == link_stamp + " " + sha256_file(out):
        say(f"game DLL up to date: {out}")
        return 0
    started = time.monotonic()
    subprocess.run([str(lld), "/lib", "/nologo", "/machine:x64", "/def:" + str(GDIR / "ps2_runtime_exports.def"),
                    "/out:ps2EntryRunner.lib"], cwd=obj, check=True, creationflags=NO_WINDOW,
                   capture_output=True)
    tmp = obj / "ps2_game.dll"
    link = [str(lld), "/nologo", "/DLL", "/NOENTRY", "/NODEFAULTLIB", "/MACHINE:X64", "/OPT:REF", "/OPT:ICF",
            "/Brepro", "/OUT:ps2_game.dll", "/IMPLIB:ps2_game.lib"] + objs + ["ps2EntryRunner.lib"]
    r = subprocess.run(link, cwd=obj, capture_output=True, text=True, encoding="utf-8", errors="replace",
                       creationflags=NO_WINDOW)
    if r.returncode:
        for line in ((r.stdout or "") + (r.stderr or "")).splitlines()[:30]:
            say("    " + line)
        say("ERROR: linking ps2_game.dll failed")
        return 1
    replace_with_retry(tmp, out)
    stamp_file.write_text(link_stamp + " " + sha256_file(out) + "\n", encoding="ascii")
    say(f"wrote {out} ({out.stat().st_size / 1e6:.1f} MB): compile {took_compile:.1f}s, link {time.monotonic() - started:.1f}s")
    return 0


def replace_with_retry(src, dst, seconds=10.0):
    """The game may still hold the old DLL a moment after its window closed."""
    end = time.monotonic() + seconds
    while True:
        try:
            shutil.copyfile(src, str(dst) + ".new")
            os.replace(str(dst) + ".new", dst)
            return
        except PermissionError:
            if time.monotonic() > end:
                raise SystemExit(f"ERROR: {dst} is in use: close Tekken 4 and press Build again")
            time.sleep(0.5)


if __name__ == "__main__":
    sys.exit(main())
