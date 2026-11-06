"""Stage a source-only T4 path-B player zip from reviewed local inputs.

This tool does not clone, build or install anything. Download helpers are separate.
See docs/RELEASE_DOWNLOADS.md for the input lock format and release gates.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from release_payload import checked_input, digest, files, safe_name, tree_digest

ROOT = Path(__file__).resolve().parent.parent
PS2_HEAD = "eb8688b2fd191129f103a39543002c005b33409c"
FETCH = ("raylib", "imgui", "rlimgui", "sse2neon", "elfio", "toml11", "fmt", "libdwarf", "rabbitizer")
TOOLS = (
    "build_game.py", "net_play.py", "net_preflight.py", "player_common.py", "player_python.ps1",
    "us_tree.py", "us_tree.ps1", "us_tree.cmd",
    "build_game.ps1", "build_game_portable.ps1", "build_runtime.cmd", "build_runtime_portable.cmd",
    "build_ps2recomp_tools.cmd", "build_ps2recomp_tools_portable.cmd", "stage_generated.cmd", "cpu_needs_baseline.ps1",
    "run_game.cmd", "run_lock.ps1", "set_window_title.ps1", "iso_extract.py", "vu1_micro_from_elf.py", "t4_buildid.py",
    "toolchain_env.cmd", "t4_toolchain_clangcl.cmake", "fetch_msvc_sysroot.py",
    "prepare_portable_tree.py", "release_payload.py", "package_release.py", "release_toolchain.json",
    "net_play.ps1", "net_preflight.ps1", "collect_test_logs.ps1",
)
BAD_PARTS = {"game", "generated", "logs", "save", "saves", "bios", "keys", "screenshots", ".git", "__pycache__", "out", "sysroot-cache", "sysroot-work"}
BAD_NAMES = {"data.bin", "system.cnf", "ioprp243.img", "slus_203.28", "sces_508.78", "ps2entryrunner.exe",
             "register_functions.cpp", "ps2_recompiled_functions.h", "ps2_recompiled_stubs.h", "settings.json"}
BAD_SUFFIXES = {".iso", ".elf", ".irx", ".cso", ".chd", ".mcd", ".ps2", ".sav", ".log", ".gpr", ".rep", ".obj", ".o", ".pdb", ".ilk", ".key", ".keys", ".pem"}
GAME_SYMBOL = re.compile(rb"(?:func_[0-9a-fA-F]{6,8}|[A-Za-z_]\w*_0x[0-9a-fA-F]{6,8})")
KNOWN_GAME_SHA256 = {"ad6526bdeb68fd741d3a35ed5cd26dec2cf611cbaaf364b89102fbe831579eb0"}
# Reviewed handwritten PAL reference source has many named guest entry points.
# Pin content, not a path exemption: edits or substituted lifted source fail again.
HANDWRITTEN_SHA256 = {"c7cec562d2550f3e73f8a11f39b8b5bd9e3da28846bb7f6575424ccead034c91"}


def scan_name(name, size):
    p = safe_name(name)
    parts = [part.lower() for part in p.parts]
    placeholder = "/".join(parts) in {
        "deps/ps2recomp/ps2xruntime/src/runner/register_functions.cpp",
        "deps/ps2recomp/ps2xruntime/include/ps2_recompiled_functions.h",
        "deps/ps2recomp/ps2xruntime/include/ps2_recompiled_stubs.h",
    }
    # Rabbitizer's own sources keep enum tables in folders named "generated" (upstream, not game code).
    checked_parts = [q for q in parts if q != "generated"] if parts[:3] == ["deps", "fetch", "rabbitizer"] else parts
    if any(part in BAD_PARTS for part in checked_parts) or (parts[-1] in BAD_NAMES and not placeholder) or p.suffix.lower() in BAD_SUFFIXES:
        raise ValueError("forbidden release path: " + name)
    if re.search(r"(?:slus|sces|scus|sles)[_.-]?\d{3}[_.-]?\d{2}", parts[-1]):
        raise ValueError("disc executable name: " + name)
    if re.search(r"(?:scph|ps2bios|biosdump|vu1_)[\w.-]*\.(?:bin|rom|dat)", parts[-1]):
        raise ValueError("BIOS/microcode name: " + name)
    if "screenshot" in parts[-1] or parts[-1] in {"id_rsa", "id_ed25519"}:
        raise ValueError("private/test artifact name: " + name)
    if re.search(r"(?:func_[0-9a-f]{6,8}|_0x[0-9a-f]{6,8})\.(?:cpp|c|h|hpp)$", parts[-1]):
        raise ValueError("lifted game source filename: " + name)
    if any(parts[i:i + 2] in (["toolchain", "msvc"], ["toolchain", "winsdk"]) for i in range(len(parts) - 1)):
        raise ValueError("Microsoft sysroot must only be fetched on the player's PC: " + name)
    approved_binary_prefix = "/".join(parts).startswith(("python/", "toolchain/llvm/", "toolchain/cmake/", "toolchain/ninja/", "deps/ffmpeg/"))
    if p.suffix.lower() in {".bin", ".rom", ".img"} and not approved_binary_prefix:
        raise ValueError("unapproved binary data: " + name)
    # All compiled files need a narrow tool/dependency location, regardless of size.
    if p.suffix.lower() in {".exe", ".dll", ".pyd", ".lib", ".a"}:
        if not approved_binary_prefix:
            raise ValueError("unapproved compiled file: " + name)
    if p.suffix.lower() == ".exe" and size > 20 * 1024 * 1024 and not "/".join(parts).startswith("toolchain/llvm/"):
        raise ValueError("large executable outside LLVM: " + name)
    if size > 2 * 1024 ** 3:
        raise ValueError("unexpectedly large release member: " + name)


def scan_stream(name, size, stream, reference_hashes, depth=0):
    scan_name(name, size)
    h = hashlib.sha256()
    symbols = set()
    tail = b""
    first = b""
    archive = io.BytesIO() if name.lower().endswith(".zip") else None
    if archive is not None and size > 256 * 1024 * 1024:
        raise ValueError("nested archive exceeds 256 MiB scan budget: " + name)
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        h.update(block)
        if len(first) < 0x9000:
            first += block[:0x9000 - len(first)]
        if len(symbols) < 64:
            symbols.update(GAME_SYMBOL.findall(tail + block))
        tail = block[-256:]
        if archive is not None:
            archive.write(block)
    if first.startswith((b"\x7fELF", b"\x7fPKG")) or first[0x8001:0x8006] == b"CD001":
        raise ValueError("disc/ELF/PKG content: " + name)
    if first.startswith((b"MZ", b"!<arch>\n")) and Path(name).suffix.lower() not in {".exe", ".dll", ".pyd", ".lib", ".a"}:
        raise ValueError("disguised compiled binary: " + name)
    if h.hexdigest() in reference_hashes | KNOWN_GAME_SHA256:
        raise ValueError("byte-identical game content: " + name)
    if len(symbols) >= 64 and h.hexdigest() not in HANDWRITTEN_SHA256:
        raise ValueError("dense lifted game function names: " + name)
    if Path(name).name.lower() in {"register_functions.cpp", "ps2_recompiled_functions.h", "ps2_recompiled_stubs.h"} and (symbols or size > 65536):
        raise ValueError("upstream placeholder contains generated game declarations: " + name)
    # FFmpeg's bundled zip and Python stdlib zip receive the same content checks.
    if archive is not None:
        if depth >= 2:
            raise ValueError("nested archive exceeds scan depth: " + name)
        archive.seek(0)
        with zipfile.ZipFile(archive) as z:
            scan_zip(z, reference_hashes, prefix=name + "!", depth=depth + 1)


def scan_zip(z, reference_hashes, prefix="", depth=0):
    seen = set()
    total = 0
    for member in z.infolist():
        safe_name(member.filename)
        key = member.filename.replace("\\", "/").casefold()
        if key in seen:
            raise ValueError("duplicate/case-colliding zip member: " + key)
        seen.add(key)
        if (member.external_attr >> 16) & 0o170000 == 0o120000:
            raise ValueError("zip symlink: " + member.filename)
        if not member.is_dir():
            total += member.file_size
            if total > 4 * 1024 ** 3:
                raise ValueError("archive exceeds 4 GiB scan budget")
            with z.open(member) as stream:
                # Prefix is diagnostic only; nested members still obey the same path rules.
                scan_stream(prefix + member.filename, member.file_size, stream, reference_hashes, depth)


def scan(path):
    references = set()
    disc = ROOT / "game" / "disc"
    if disc.is_dir():
        references = {digest(p) for p in files(disc)}
    path = Path(path)
    if path.is_file():
        with zipfile.ZipFile(path) as z:
            scan_zip(z, references)
    else:
        if not path.is_dir():
            raise ValueError("scan input must be an existing directory or zip: " + str(path))
        seen = set()
        for file in files(path):
            name = file.relative_to(path).as_posix()
            if name.casefold() in seen:
                raise ValueError("case-colliding release path: " + name)
            seen.add(name.casefold())
            with file.open("rb") as stream:
                scan_stream(name, file.stat().st_size, stream, references)


def copy_tree(src, dst, skip=()):
    for path in files(src):
        rel = path.relative_to(src)
        if any(part.lower() in skip for part in rel.parts):
            continue
        target = dst / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)


def private_python(src, dst):
    """Full python.org install/layout, never the embeddable distribution."""
    required = ("python.exe", "pythonw.exe", "Lib/tkinter/__init__.py", "DLLs/_tkinter.pyd", "LICENSE.txt")
    for name in required:
        if not (src / name).is_file():
            raise ValueError("private Python requires tkinter/Tcl-Tk and licence: " + name)
    if not (src / "tcl").is_dir():
        raise ValueError("private Python has no tcl directory")
    # Only standard library/runtime files. Site packages and user hooks cannot enter the zip.
    for path in files(src):
        rel = path.relative_to(src)
        if any(part.lower() in {"site-packages", "__pycache__", "test", "tests", "idlelib", "ensurepip"} for part in rel.parts):
            continue
        if rel.parts[0] not in {"Lib", "DLLs", "tcl"} and len(rel.parts) != 1:
            continue
        if len(rel.parts) == 1 and not (path.suffix.lower() in {".exe", ".dll", ".txt"}):
            continue
        if path.suffix.lower() in {".pyc", ".pdb"}:
            continue
        target = dst / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    dlls = list(dst.glob("python3[0-9][0-9].dll"))
    if len(dlls) != 1:
        raise ValueError("expected exactly one versioned CPython DLL")
    (dst / (dlls[0].stem + "._pth")).write_text(".\nLib\nDLLs\n", encoding="ascii")


def python_self_test(stage):
    env = {k: v for k, v in os.environ.items() if k.upper() not in {"PATH", "PYTHONPATH", "PYTHONHOME", "TCL_LIBRARY", "TK_LIBRARY"}}
    env["PATH"] = str(Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32")
    code = "import sys, pathlib, tkinter, ssl, ctypes, json, zlib; p=pathlib.Path(sys.executable).parent.resolve(); assert sys.flags.isolated; assert all(pathlib.Path(x).resolve().is_relative_to(p) for x in sys.path); t=tkinter.Tk(); t.withdraw(); t.update(); t.destroy(); print('private Python/Tk OK')"
    subprocess.run([str(stage / "python" / "python.exe"), "-I", "-B", "-c", code], cwd=stage, env=env, check=True)


def package(a):
    lock = json.loads(a.inputs.read_text(encoding="utf-8"))
    stage = a.stage.resolve()
    archive = a.zip.resolve()
    if stage.exists() or archive.exists():
        raise ValueError("stage and zip must both be new paths; nothing is deleted or overwritten")
    if stage == ROOT or ROOT.is_relative_to(stage) or archive.is_relative_to(stage):
        raise ValueError("unsafe staging/output location")
    if not (ROOT / "docs" / "THIRD_PARTY.md").is_file():
        raise ValueError("missing provenance inventory: docs/THIRD_PARTY.md")
    # Validate every input before writing the staging directory.
    dirs = {name: checked_input(lock[name], directory=True) for name in ("python", "ps2recomp", "llvm", "cmake", "ninja")}
    sources = {name: checked_input(lock["fetch"][name], directory=True) for name in FETCH}
    ffmpeg = checked_input(lock["ffmpeg"])
    sysroot_lock = checked_input(lock["sysroot_lock"])
    sysroot_data = json.loads(sysroot_lock.read_text(encoding="utf-8"))
    if sysroot_data.get("schema") != 1 or sysroot_data.get("architecture") != "x64" or not sysroot_data.get("payloads") or sysroot_data.get("license_reviewed") is not True:
        raise ValueError("reviewed x64 Microsoft payload lock is required")
    from fetch_msvc_sysroot import validate_payload
    for payload in sysroot_data["payloads"]:
        validate_payload(payload)
    licenses = {name: checked_input(record) for name, record in lock["licenses"].items()}
    required_licenses = {"project", "python", "llvm", "cmake", "ninja", "ps2recomp", "ffmpeg", "sdl2", "openexr", "vu1_generator", "microsoft-build-tools", "microsoft-windows-sdk", *FETCH}
    if not required_licenses.issubset(licenses):
        raise ValueError("missing licence texts: " + ", ".join(sorted(required_licenses - licenses.keys())))
    for name in ("microsoft-build-tools", "microsoft-windows-sdk"):
        terms = sysroot_data.get("license_terms", {}).get(name, {})
        if terms.get("path") != "LICENSES/" + name + ".txt" or terms.get("sha256") != digest(licenses[name]) or not terms.get("url", "").startswith("https://"):
            raise ValueError("Microsoft lock does not match reviewed licence text: " + name)
    pins = json.loads((ROOT / "tools" / "release_toolchain.json").read_text(encoding="utf-8"))
    for name in ("llvm", "cmake", "ninja"):
        receipt = json.loads((dirs[name] / ".t4-payload.json").read_text(encoding="utf-8"))
        if receipt["sha256"] != pins[name]["sha256"] or receipt["tree_sha256"] != tree_digest(dirs[name]):
            raise ValueError("tool payload differs from verified archive: " + name)
    marker = json.loads((dirs["ps2recomp"] / ".t4-vendored.json").read_text(encoding="utf-8"))
    patches = [{"name": p.name, "sha256": digest(p)} for p in sorted((ROOT / "patches").glob("*.patch"))]
    if marker.get("head") != PS2_HEAD or marker.get("patches") != patches:
        raise ValueError("vendored PS2Recomp must attest the exact pinned head and all current patches")
    stage.mkdir(parents=True)
    for name in ("LICENSE", "README.md", "START_HIER.txt", "Tekken4.cmd"):
        shutil.copy2(ROOT / name, stage / name)
    for name in ("config", "runtime", "patches", "docs"):
        # runtime/pal is the PAL cousin's reference source; the US build never stages it (0.1.2 zip had none).
        copy_tree(ROOT / name, stage / name, {"__pycache__", "pal"} if name == "runtime" else {"__pycache__"})
    for name in ("t4core.py", "t4_launcher.pyw", "COPIED_FROM_T5DR.txt"):
        target = stage / "launcher" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "launcher" / name, target)
    for name in TOOLS:
        target = stage / "tools" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "tools" / name, target)
    shutil.copy2(sysroot_lock, stage / "tools" / "msvc_sysroot.lock.json")
    copy_tree(ROOT / "tools" / "vu1", stage / "tools" / "vu1", {"__pycache__"})
    copy_tree(ROOT / "tools" / "vu", stage / "tools" / "vu", {"__pycache__"})
    private_python(dirs["python"], stage / "python")
    for name in ("llvm", "cmake", "ninja"):
        copy_tree(dirs[name], stage / "toolchain" / name)
    # Omit checkout metadata/build directories without modifying the supplied tree.
    # A source tree contaminated with staged game code still fails the final scan.
    copy_tree(dirs["ps2recomp"], stage / "deps" / "ps2recomp", {".git", "out", "generated", "__pycache__"})
    for name, path in sources.items():
        copy_tree(path, stage / "deps" / "fetch" / name, {".git", "out", "build", "__pycache__"})
    (stage / "deps" / "ffmpeg").mkdir(parents=True)
    shutil.copy2(ffmpeg, stage / "deps" / "ffmpeg" / "ffmpeg.zip")
    (stage / "LICENSES").mkdir()
    for name, path in licenses.items():
        if not re.fullmatch(r"[a-z0-9_-]+", name):
            raise ValueError("invalid licence component name: " + name)
        shutil.copy2(path, stage / "LICENSES" / (name + ".txt"))
    from fetch_msvc_sysroot import license_terms
    license_terms(stage, sysroot_data)
    from prepare_portable_tree import prepare
    prepare(stage, stage / "deps" / "ps2recomp")
    (stage / "toolchain" / "toolchain.json").write_text(json.dumps(pins, indent=2) + "\n", encoding="utf-8")
    # Strip maintainer paths from public provenance; retain exact digests, source and version.
    def public(value):
        if isinstance(value, dict):
            return {k: public(v) for k, v in value.items() if k != "path"}
        return value
    (stage / "release.json").write_text(json.dumps({"version": a.version, "path": "B", "inputs": public(lock)}, indent=2) + "\n", encoding="utf-8")
    python_self_test(stage)
    scan(stage)
    sums = "".join(digest(p) + "  " + p.relative_to(stage).as_posix() + "\n" for p in files(stage))
    (stage / "SHA256SUMS").write_text(sums, encoding="utf-8")
    archive.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for path in files(stage):
            z.write(path, path.relative_to(stage).as_posix())
    scan(archive)
    checksum = archive.with_name(archive.name + ".sha256")
    with checksum.open("x", encoding="ascii") as f:
        f.write(digest(archive) + "  " + archive.name + "\n")
    print("Staged, private-Python-tested, scanned folder and zip:", archive)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--scan-only", type=Path, help="scan a folder or zip, write nothing")
    p.add_argument("--hash-tree", type=Path, help="print a local input directory digest, write nothing")
    p.add_argument("--inputs", type=Path, help="reviewed local input lock JSON")
    p.add_argument("--stage", type=Path)
    p.add_argument("--zip", type=Path)
    p.add_argument("--version")
    a = p.parse_args()
    try:
        if a.scan_only:
            scan(a.scan_only)
            print("Release scan passed:", a.scan_only)
        elif a.hash_tree:
            print(tree_digest(a.hash_tree))
        else:
            if not all((a.inputs, a.stage, a.zip, a.version)):
                p.error("packaging requires --inputs, --stage, --zip and --version")
            package(a)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as e:
        print("ERROR:", e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
