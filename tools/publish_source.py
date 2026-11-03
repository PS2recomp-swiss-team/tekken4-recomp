"""Stage a reviewed Git ref for the GPL-3 source mirror. Never publish it.

Only read-only Git commands are used. A finding stops the export before files
are written. This is a conservative guard, not proof that a tree is publishable;
the owner must still review the staged tree and its author notices.
"""
import argparse
import hashlib
import ipaddress
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
IMAGE_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".dib", ".ico",
    ".svg", ".svgz", ".tif", ".tiff", ".avif", ".heic", ".heif",
    ".dds", ".tga", ".psd", ".xcf", ".icns", ".pnm", ".pbm", ".pgm", ".ppm",
    ".apng", ".jfif", ".jxl", ".exr", ".hdr", ".ktx", ".ktx2", ".cur", ".qoi",
}
EXCLUDED_DIRS = {
    ".git", "lobby", "logs", "log", "generated", "ghidra", "build", "out",
    "external", "__pycache__", ".pytest_cache", "node_modules",
}
DATA_SUFFIXES = {
    ".iso", ".elf", ".bin", ".img", ".cso", ".chd", ".mdf", ".nrg",
    ".vob", ".pss", ".adx", ".vag", ".irx", ".ps2", ".mcr", ".psu",
    ".zip", ".7z", ".rar", ".gz", ".tar", ".exe", ".dll", ".pyd",
    ".o", ".obj", ".a", ".lib", ".so", ".dat", ".sav", ".save", ".mcd", ".vmc",
    ".gpr", ".rep", ".rom", ".pkg",
}
KEY_SUFFIXES = {".key", ".keys", ".pem", ".p12", ".pfx", ".kdbx"}
GENERATED_NAMES = {"register_functions.cpp", "ps2_recompiled_functions.h", "ps2_recompiled_stubs.h"}
GENERATED_NAME = re.compile(r"(?i)(?:func_[0-9a-f]{6,8}|_0x[0-9a-f]{6,8})\.(?:cpp|c|h|hpp)$")
GAME_SYMBOL = re.compile(rb"(?:func_[0-9a-fA-F]{6,8}|[A-Za-z_]\w*_0x[0-9a-fA-F]{6,8})")
# Same exact-content pin as package_release.py for the handwritten PAL reference.
HANDWRITTEN_SHA256 = {"c7cec562d2550f3e73f8a11f39b8b5bd9e3da28846bb7f6575424ccead034c91"}
# Reviewed immutable patch: its guest CD path examples resemble a UNC path.
# Only the personal-path category uses this pin; any byte change loses it.
GUEST_PATH_SHA256 = {"9b0151764e50f9eeb7d227d6048ef65567124b89185df24a3ce24e9ff08e0864"}
# Public documentation and dependency downloads are not lobby addresses.
PUBLIC_HOSTS = {
    "github.com", "www.github.com", "api.github.com", "raw.githubusercontent.com",
    "objects.githubusercontent.com", "release-assets.githubusercontent.com",
    "gnu.org", "www.gnu.org", "fsf.org", "www.fsf.org", "ps2recomp.com",
    "pcsx2.net", "www.pcsx2.net", "python.org", "www.python.org",
    "docs.python.org", "llvm.org", "releases.llvm.org", "cmake.org",
    "aka.ms", "download.visualstudio.microsoft.com", "go.microsoft.com",
    "learn.microsoft.com", "visualstudio.microsoft.com", "www.microsoft.com", "developer.microsoft.com",
    "virustotal.com", "www.virustotal.com", "docs.virustotal.com",
    "spdx.org", "opensource.org",
    "git-scm.com", "www.git-scm.com",
    "tailscale.com", "www.tailscale.com",
}
URL = re.compile(r"\b(?:https?|wss?|tcp|udp)://[^\s<>\"'`]+", re.I)
IPV4 = re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])")
IPV6 = re.compile(r"(?<![\w:])(?:[0-9a-f]{0,4}:){2,}[0-9a-f:.%]+", re.I)
PERSONAL = re.compile(
    r"(?i)(?:\b[a-z]:[\\/]|(?<![a-z0-9_.\\/])\\\\[a-z0-9_.-]+[\\/]|"
    r"/(?:home|Users)/[a-z0-9_.-]+|~[\\/])"
)
SECRET = re.compile(
    r"-----BEGIN (?:[A-Z0-9 ]*PRIVATE KEY|PGP PRIVATE KEY BLOCK)-----|"
    r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|"
    r"AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,})\b|"
    r"(?i:" r"\b(?:[a-z][a-z0-9_]*[_-])?(?:api[_-]?key|access[_-]?token|auth[_-]?token|password|"
    r"private[_-]?key|signing[_-]?key|client[_-]?secret|secret|token)\b)[\"']?\s*[:=]\s*"
    r"(?:[rRuUbBfF]{0,2}[\"'](?![<{$])[^\"'\r\n]{8,}[\"']|[a-zA-Z0-9_/-]{20,})|"
    r"(?m:^\s*[0-9a-fA-F]{64}\s*$)"
)
HOST_ASSIGNMENT = re.compile(
    r"(?i)(?:\b(?:[a-z_]*(?:server|host|endpoint|lobby)[a-z_]*)\b[\"']?\s*[:=]\s*"
    r"[\"']?|--(?:server|host|lobby)(?:\s+|=))((?:[a-z0-9][a-z0-9.-]*\.[a-z]{2,}|localhost))(?=[:/\s\"']|$)"
)
HOST_PORT = re.compile(r"(?i)\b[a-z0-9](?:[a-z0-9-]*\.)+[a-z]{2,}:\d{1,5}\b")


def safe_name(name):
    """Reject paths whose meaning differs between Git and the output filesystem."""
    path = PurePosixPath(name)
    if (not name or path.is_absolute() or "\\" in name or "\x00" in name
            or any(part in {"", ".", ".."} or ":" in part
                   or part.rstrip(" .") != part for part in name.split("/"))):
        raise ValueError("unsafe tree path")
    for part in path.parts:
        stem = part.split(".", 1)[0].lower()
        if stem in {"con", "prn", "aux", "nul"} or re.fullmatch(r"(?:com|lpt)[1-9]", stem):
            raise ValueError("Windows device path in tree")
    return path


def excluded(name):
    path = safe_name(name)
    parts = tuple(part.lower() for part in path.parts)
    return (any(part in EXCLUDED_DIRS for part in parts[:-1])
            or parts[:2] in {("docs", "img"), ("config", "output")}
            or parts[-1] in {".git", ".mcp.json", "claude.md"} | GENERATED_NAMES
            or path.suffix.lower() in IMAGE_SUFFIXES | {".log", ".pyc", ".pyo"}
            or ".log." in parts[-1] or parts[-1] in {"log.txt", "debug.txt"}
            or bool(GENERATED_NAME.search(parts[-1]))
            or parts[-1].endswith((".generated.cpp", ".generated.h")))


def is_image(data):
    return (data.startswith((b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff", b"GIF87a", b"GIF89a",
                             b"BM", b"II*\x00", b"MM\x00*", b"\x00\x00\x01\x00", b"DDS "))
            or (data[:4] == b"RIFF" and data[8:12] == b"WEBP")
            or bool(re.search(br"<svg(?:\s|>)", data[:4096], re.I)))


def asset_reasons(name, data):
    """Check asset names and signatures even when export would omit the path."""
    path = safe_name(name)
    reasons = []
    parts = tuple(part.lower() for part in path.parts)
    if path.suffix.lower() in IMAGE_SUFFIXES or is_image(data):
        reasons.append("image filename or content")
    if (path.suffix.lower() in DATA_SUFFIXES
            or path.name.lower() in {"data.bin", "system.cnf", "rom0", "rom1", "rom2"}
            or any(part in {"game", "bios", "saves", "save", "memcards"} for part in parts[:-1])
            or re.match(r"(?i)^(?:slus|sles|sces|slps|scps)[_-]\d", path.name)):
        reasons.append("game data or binary/archive filename")
    if (data.startswith((b"\x7fELF", b"MZ", b"PK\x03\x04", b"7z\xbc\xaf\x27\x1c", b"Rar!", b"\x1f\x8b"))
            or data[32769:32774] == b"CD001" or data[34817:34822] == b"CD001"):
        reasons.append("game/executable/archive signature")
    return reasons


def scan_file(name, data):
    """Return category names only: never print matched credentials or addresses."""
    path = safe_name(name)
    reasons = asset_reasons(name, data)
    parts = tuple(part.lower() for part in path.parts)
    if ".mcp.json" == parts[-1] or "lobby" in parts[:-1]:
        reasons.append("private source path")
    if path.name.lower() in GENERATED_NAMES or GENERATED_NAME.search(path.name):
        reasons.append("generated game source filename")
    if len(set(GAME_SYMBOL.findall(data))) >= 64 and hashlib.sha256(data).hexdigest() not in HANDWRITTEN_SHA256:
        reasons.append("dense lifted game function names")
    if (path.suffix.lower() in KEY_SUFFIXES or "keys" in parts[:-1]
            or path.name.lower() in {".env", "id_rsa", "id_ed25519", "credentials"}):
        reasons.append("key or credential filename")
    try:
        text = data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return reasons + ["non-UTF-8 or binary content; manual review required"]
    if any(ord(char) < 32 and char not in "\t\n\r\f" for char in text):
        reasons.append("binary content; manual review required")
    if SECRET.search(text):
        reasons.append("credential or private key content")
    if PERSONAL.search(text) and hashlib.sha256(data).hexdigest() not in GUEST_PATH_SHA256:
        reasons.append("personal or machine-specific path")
    for match in list(IPV4.finditer(text)) + list(IPV6.finditer(text)):
        try:
            address = ipaddress.ip_address(match.group().split("%", 1)[0])
        except ValueError:
            continue
        # C++ and PowerShell scope operators such as "ad::" parse as short IPv6: a real one has more groups.
        if ":" in match.group() and match.group().count(":") < 4:
            continue
        # Bind-any and loopback constants are not a player's or server's address.
        if address.is_loopback or address.is_unspecified:
            continue
        reasons.append("literal network address")
        break
    for match in URL.finditer(text):
        try:
            url = urlsplit(match.group().rstrip(".,;)]}"))
            host = (url.hostname or "").lower()
            unsafe = (url.scheme.lower() not in {"http", "https"}
                      or host not in PUBLIC_HOSTS or url.username is not None
                      or url.password is not None or url.port not in {None, 80, 443})
        except ValueError:
            unsafe = True
        if unsafe:
            reasons.append("unreviewed server URL")
            break
    if HOST_ASSIGNMENT.search(text) or HOST_PORT.search(text):
        reasons.append("server hostname assignment")
    if re.search(r"(?im)^\s*(?://|/\*|#|\*)?\s*(?:automatically generated|generated by (?:ps2recomp|ghidra))", text):
        reasons.append("generated game code marker")
    return list(dict.fromkeys(reasons))


def _no_links(path):
    for candidate in (path, *path.parents):
        if candidate.is_symlink() or (candidate.exists() and getattr(candidate.lstat(), "st_file_attributes", 0) & 0x400):
            raise ValueError("links/reparse points are not export paths")


def scan_tree(root):
    """Scan every staged file, including files that export would omit."""
    root = Path(root).absolute()
    _no_links(root)
    if not root.is_dir():
        raise ValueError("scan root must be a directory")
    findings = []
    for path in sorted(root.rglob("*")):
        _no_links(path)
        if path.is_file():
            name = path.relative_to(root).as_posix()
            if path.stat().st_size > 32 * 1024 * 1024:
                findings.append(name + ": oversized input; manual review required")
                continue
            for reason in scan_file(name, path.read_bytes()):
                findings.append(name + ": " + reason)
    return findings


def _git(repo, *args):
    result = subprocess.run(["git", "-C", str(repo), *args], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise ValueError("read-only git command failed: " + args[0])
    return result.stdout


def export_ref(repo, ref, out):
    repo = Path(repo).resolve()
    out = Path(out).absolute()
    if any(part.lower() == ".git" for part in out.parts):
        raise ValueError("output cannot be Git metadata")
    _no_links(out)
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        raise ValueError("output must be a new or empty directory")
    commit = _git(repo, "rev-parse", "--verify", "--end-of-options", ref + "^{commit}").decode("ascii").strip()
    tree = _git(repo, "ls-tree", "-r", "-z", "--full-tree", commit)
    selected = []
    findings = []
    seen = {}
    for entry in tree.split(b"\0"):
        if not entry:
            continue
        meta, raw_name = entry.split(b"\t", 1)
        mode, kind, oid = meta.decode("ascii").split()
        name = raw_name.decode("utf-8")
        safe_name(name)
        # Refuse contamination rather than silently hiding it in an omitted
        # directory. Private source exclusions still apply after this check.
        named_assets = asset_reasons(name, b"")
        if named_assets:
            findings.extend(name + ": " + reason for reason in named_assets)
            continue
        if mode not in {"100644", "100755"} or kind != "blob":
            if excluded(name):
                continue
            raise ValueError("links and submodules are not mirror inputs")
        size = int(_git(repo, "cat-file", "-s", oid))
        if size > 32 * 1024 * 1024:
            findings.append(name + ": oversized input; manual review required")
            continue
        data = _git(repo, "cat-file", "blob", oid)
        assets = asset_reasons(name, data)
        if assets:
            findings.extend(name + ": " + reason for reason in assets)
            continue
        if excluded(name):
            continue
        components = PurePosixPath(name).parts
        for count in range(1, len(components) + 1):
            prefix = "/".join(components[:count])
            key = prefix.casefold()
            if key in seen and seen[key] != prefix:
                raise ValueError("case-colliding tree paths")
            seen[key] = prefix
        findings.extend(name + ": " + reason for reason in scan_file(name, data))
        selected.append((name, data, mode))
    if "LICENSE" not in {name for name, _, _ in selected}:
        raise ValueError("ref must retain the root LICENSE")
    if findings:
        raise ValueError("mirror refused:\n" + "\n".join(findings))
    # All content is checked before creating anything. Never rewrite notices or authors.
    out.mkdir(parents=True, exist_ok=True)
    for name, data, mode in selected:
        target = out.joinpath(*PurePosixPath(name).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        _no_links(target)
        with target.open("xb") as stream:
            stream.write(data)
        if mode == "100755":
            target.chmod(target.stat().st_mode | 0o111)
    return commit, len(selected)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", help="reviewed commit, branch or tag to read; required for export")
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--out", type=Path, help="new or empty staging directory; never a public checkout")
    parser.add_argument("--scan-only", type=Path, metavar="DIR", help="scan an existing staged tree without writing")
    args = parser.parse_args(argv)
    try:
        if args.scan_only is not None:
            if args.ref is not None or args.out is not None:
                parser.error("--scan-only cannot be combined with --ref or --out")
            findings = scan_tree(args.scan_only)
            if findings:
                raise ValueError("mirror refused:\n" + "\n".join(findings))
            print("Source scan passed; owner review is still required.")
        else:
            if not args.ref or args.out is None:
                parser.error("export requires --ref and --out")
            commit, count = export_ref(args.repo, args.ref, args.out)
            print("Staged {} files from {}. Nothing published.".format(count, commit))
    except (OSError, UnicodeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
