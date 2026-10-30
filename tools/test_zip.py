"""Make the Sunday source test zip from this working tree, without Git or builds.

The catalog deliberately includes the CLI build and online test inputs only.
Maintainer notes, local tools/dependencies and local game outputs do not ship.
Every selected byte is checked with publish_source before creating an archive.
"""
import argparse
from datetime import datetime
import os
from pathlib import Path
import sys
import zipfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import publish_source


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRS = ("config", "runtime", "patches")
ROOT_FILES = ("LICENSE", "TEST_ONLINE_DE.txt")
TOOLS = (
    "build_game.ps1", "build_game_portable.ps1", "build_runtime.cmd", "build_runtime_portable.cmd",
    "build_ps2recomp_tools.cmd", "build_ps2recomp_tools_portable.cmd", "stage_generated.cmd",
    "run_game.cmd", "run_lock.ps1", "set_window_title.ps1", "iso_extract.py", "vu1_micro_from_elf.py",
    "t4_buildid.py", "toolchain_env.cmd", "t4_toolchain_clangcl.cmake", "fetch_msvc_sysroot.py",
    "release_payload.py", "net_play.ps1", "net_preflight.ps1", "collect_test_logs.ps1",
    "make_test_zip.ps1", "test_zip.py", "publish_source.py",
)
MAX_FILE_SIZE = 32 * 1024 * 1024


def _walk_error(error):
    raise error


def scan_entries(entries):
    """Validate an iterable of (archive name, bytes); return unchanged entries."""
    checked = []
    findings = []
    seen = {}
    for name, data in entries:
        path = publish_source.safe_name(name)
        for count in range(1, len(path.parts) + 1):
            prefix = "/".join(path.parts[:count])
            previous = seen.setdefault(prefix.casefold(), prefix)
            if previous != prefix:
                raise ValueError("case-colliding source paths")
        if any(name == previous for previous, _ in checked):
            raise ValueError("duplicate source path")
        if len(data) > MAX_FILE_SIZE:
            findings.append(name + ": oversized input; manual review required")
        else:
            findings.extend(name + ": " + reason for reason in publish_source.scan_file(name, data))
        checked.append((name, data))
    if "LICENSE" not in {name for name, _ in checked}:
        raise ValueError("source zip must retain the root LICENSE")
    if findings:
        raise ValueError("Test zip refused; fix the selected source files first:\n" + "\n".join(findings))
    return checked


def source_entries(root):
    """Read only the explicit Sunday catalog; never follow links/reparse points."""
    root = Path(root).absolute()
    publish_source._no_links(root)
    if not root.is_dir():
        raise ValueError("source root must be a directory")
    paths = [root / name for name in ROOT_FILES]
    paths.extend(root / "tools" / name for name in TOOLS)
    for name in SOURCE_DIRS + ("tools/vu1",):
        folder = root / name
        publish_source._no_links(folder)
        if not folder.is_dir():
            raise ValueError("missing source directory: " + name)
        # Do not use an exclusion filter inside source folders: contamination
        # here must fail the scan rather than silently disappear from the zip.
        for parent, directories, filenames in os.walk(folder, followlinks=False, onerror=_walk_error):
            for child in directories + filenames:
                publish_source._no_links(Path(parent) / child)
            paths.extend(Path(parent) / child for child in filenames)
    entries = []
    for path in sorted(paths):
        name = path.relative_to(root).as_posix()
        publish_source._no_links(path)
        if not path.is_file():
            raise ValueError("missing source file: " + name)
        if path.stat().st_size > MAX_FILE_SIZE:
            raise ValueError(name + ": oversized input; manual review required")
        entries.append((name, path.read_bytes()))
    return scan_entries(entries)


def create_zip(root, archive, entries=None):
    """Scan all bytes before writing anything; never overwrite an old archive."""
    root = Path(root).absolute()
    archive = Path(archive).absolute()
    publish_source._no_links(root)
    publish_source._no_links(archive)
    root = root.resolve()
    archive = archive.resolve()
    try:
        relative = archive.relative_to(root)
    except ValueError:
        raise ValueError("test zip output must stay inside the source folder")
    if (not relative.parts or relative.parts[0].lower() in {".git", "config", "runtime", "patches", "tools"}
            or archive.suffix.lower() != ".zip"):
        raise ValueError("output must be a .zip outside source and Git directories")
    if archive.exists():
        raise ValueError("output already exists; nothing was overwritten")
    entries = source_entries(root) if entries is None else scan_entries(entries)
    archive.parent.mkdir(parents=True, exist_ok=True)
    publish_source._no_links(archive.parent)
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, data in entries:
            output.writestr(name, data)
    # Read back the result before reporting success, including CRC and scan.
    with zipfile.ZipFile(archive) as output:
        if output.testzip() is not None:
            raise ValueError("archive CRC check failed; retained for inspection")
        scan_entries((name, output.read(name)) for name in output.namelist())
    return archive, len(entries)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--out-dir", type=Path, help="output folder inside this tree (default: dist/sunday)")
    parser.add_argument("--check-only", action="store_true", help="scan the exact catalog, write nothing")
    args = parser.parse_args(argv)
    try:
        root = args.root.absolute()
        entries = source_entries(root)
        if args.check_only:
            print("Test source scan passed: {} files. Nothing written.".format(len(entries)))
            return 0
        directory = args.out_dir or root / "dist" / "sunday"
        if not directory.is_absolute():
            directory = root / directory
        name = "tekken4-sunday-test-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".zip"
        archive, count = create_zip(root, directory / name, entries)
        print("Test zip: {}".format(archive))
        print("Size: {:,} bytes; {} source files.".format(archive.stat().st_size, count))
        print("Source only. Each player installs the tools and builds from their own ISO; see TEST_ONLINE_DE.txt.")
    except (OSError, UnicodeError, ValueError, zipfile.BadZipFile) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
