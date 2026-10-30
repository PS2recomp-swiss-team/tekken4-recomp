"""Shared, standard-library-only release input verification. No work on import."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tarfile
import urllib.request
import zipfile


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def files(root):
    root = Path(root)
    for path in sorted(root.rglob("*")):
        if path.is_symlink() or (getattr(path.lstat(), "st_file_attributes", 0) & 0x400):
            raise ValueError("links/reparse points are not release inputs: " + str(path))
        if path.is_file():
            yield path


def tree_digest(root):
    h = hashlib.sha256()
    for path in files(root):
        if path.name == ".t4-payload.json":
            continue
        h.update(path.relative_to(root).as_posix().encode("utf-8") + b"\0")
        h.update(bytes.fromhex(digest(path)))
    return h.hexdigest()


def checked_input(record, directory=False):
    path = Path(record["path"]).resolve()
    expected = record.get("sha256", "")
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("a reviewed SHA-256 is required for " + str(path))
    actual = tree_digest(path) if directory else digest(path)
    if actual != expected:
        raise ValueError("SHA-256 mismatch: " + str(path))
    if not record.get("source") or not record.get("version"):
        raise ValueError("source and version are required for " + str(path))
    return path


def safe_name(name):
    name = name.replace("\\", "/")
    p = PurePosixPath(name)
    if not name or p.is_absolute() or ".." in p.parts or any(":" in part for part in p.parts):
        raise ValueError("unsafe archive path: " + name)
    return p


def fetch(record, cache):
    """Never use an unverified cached file; keep failed files for inspection."""
    sha = record["sha256"]
    if not re.fullmatch(r"[0-9a-f]{64}", sha):
        raise ValueError("download has no pinned SHA-256")
    if not record["url"].startswith("https://"):
        raise ValueError("downloads require HTTPS")
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / record["filename"]
    if not target.exists():
        # Exclusive creation: failed downloads remain and are refused on retry.
        with urllib.request.urlopen(record["url"], timeout=120) as src, target.open("xb") as dst:
            if not src.geturl().startswith("https://"):
                raise ValueError("download redirected away from HTTPS")
            shutil.copyfileobj(src, dst)
    if digest(target) != sha:
        raise ValueError("download SHA-256 mismatch (retained): " + str(target))
    return target


def unpack_selected(archive, target, component):
    """Extract only files needed by the player; never extract archive links."""
    target = Path(target)
    target.mkdir(parents=True, exist_ok=False)

    def output(name):
        parts = safe_name(name).parts
        if component in ("llvm", "cmake"):
            parts = parts[1:]  # official archive's single versioned root
        if not parts:
            return None
        rel = "/".join(parts)
        low = rel.lower()
        license_file = any(x in parts[-1].lower() for x in ("license", "copyright", "copying", "notice"))
        if component == "llvm":
            keep = low in {"bin/" + x + ".exe" for x in ("clang-cl", "lld-link", "llvm-lib", "llvm-rc", "llvm-mt", "llvm-profdata")} or low.startswith("lib/clang/") or license_file
        elif component == "cmake":
            keep = low == "bin/cmake.exe" or low.startswith("share/") or license_file
        else:
            keep = low == "ninja.exe" or license_file
        return target.joinpath(*parts) if keep else None

    def save(name, stream):
        dst = output(name)
        if dst is not None:
            dst.parent.mkdir(parents=True, exist_ok=True)
            with dst.open("xb") as f:
                shutil.copyfileobj(stream, f)

    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as z:
            for item in z.infolist():
                safe_name(item.filename)
                if (item.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError("archive symlink: " + item.filename)
                if not item.is_dir():
                    with z.open(item) as stream:
                        save(item.filename, stream)
    else:
        with tarfile.open(archive, "r:xz") as t:
            for item in t:
                safe_name(item.name)
                if not item.isfile() and not item.isdir():
                    raise ValueError("archive link/special file: " + item.name)
                if item.isfile():
                    with t.extractfile(item) as stream:
                        save(item.name, stream)
