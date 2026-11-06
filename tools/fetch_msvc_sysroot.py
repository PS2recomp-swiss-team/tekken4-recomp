#!/usr/bin/env python3
"""Fetch a locked Microsoft x64 sysroot on the player's PC, never in a release zip.

Uses only Python's standard library and Windows' MSI database reader/expand.exe.
It does not run MSI installers, install Visual Studio, or require elevation.
See docs/MSVC_SYSROOT.md. Downloads/extraction have not been tested here.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import subprocess
import sys
import urllib.parse
import urllib.request
import uuid
import zipfile


CHANNEL = "https://aka.ms/vs/17/release/channel"
LICENSES = {
    "Visual Studio Build Tools": "https://go.microsoft.com/fwlink/?LinkId=2086102",
    "Windows SDK": "https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/",
}
REQUIRED = (
    "msvc/include/vector", "msvc/include/vcruntime.h", "msvc/lib/x64/libcmt.lib",
    "msvc/lib/x64/libcpmt.lib", "winsdk/include/ucrt/stdio.h",
    "winsdk/include/um/Windows.h", "winsdk/include/shared/windef.h",
    "winsdk/lib/ucrt/x64/libucrt.lib", "winsdk/lib/um/x64/kernel32.lib",
)


def license_terms(root, lock):
    """Only owner-reviewed, hash-locked texts qualify as the player's acceptance."""
    if lock.get("license_reviewed") is not True:
        raise ValueError("Microsoft licence texts have not been reviewed by the release owner")
    terms = []
    for name in ("microsoft-build-tools", "microsoft-windows-sdk"):
        record = lock["license_terms"][name]
        relative = "LICENSES/" + name + ".txt"
        if record["path"] != relative or not re.fullmatch(r"[a-f0-9]{64}", record["sha256"]):
            raise ValueError("invalid locked Microsoft licence text: " + name)
        if urllib.parse.urlparse(record["url"]).scheme != "https":
            raise ValueError("licence source must use HTTPS")
        path = root / relative
        if not path.is_file() or sha256(path) != record["sha256"]:
            raise ValueError("Microsoft licence text is missing or changed: " + relative)
        terms.append((name, record["url"], path.read_text(encoding="utf-8-sig")))
    return terms


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_parts(name):
    parts = PurePosixPath(name.replace("\\", "/")).parts
    if not parts or any(p in ("..", ".", "/") or ":" in p for p in parts):
        raise ValueError("unsafe archive path: " + name)
    if name.startswith(("/", "\\")):
        raise ValueError("absolute archive path: " + name)
    return parts


def official_url(url):
    parsed = urllib.parse.urlparse(url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https" or not (host == "aka.ms" or host.endswith(".microsoft.com") or host.endswith(".visualstudio.microsoft.com")):
        raise ValueError("not an official Microsoft HTTPS URL: " + url)
    return url


def get_bytes(url, limit=64 * 1024 * 1024):
    with urllib.request.urlopen(official_url(url), timeout=120) as response:
        official_url(response.geturl())
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("metadata exceeds size limit")
    return data


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, indent=2)
        stream.write("\n")


def version_key(value):
    return tuple(int(n) for n in re.findall(r"\d+", value))


def validate_payload(payload):
    official_url(payload["url"])
    safe_parts(payload["fileName"])
    if not re.fullmatch(r"[a-fA-F0-9]{64}", payload["sha256"]):
        raise ValueError("missing/invalid SHA-256 in Microsoft payload metadata")
    if not isinstance(payload["size"], int) or payload["size"] <= 0:
        raise ValueError("missing/invalid size in Microsoft payload metadata")


def make_lock(destination, channel_url, crt_version=None, sdk_version=None):
    """Resolve metadata only. The owner reviews this lock before shipping it."""
    if destination.exists():
        raise ValueError("lock already exists; choose a new filename")
    channel_data = get_bytes(channel_url)
    channel = json.loads(channel_data.decode("utf-8-sig"))
    items = [p for p in channel["channelItems"] if p.get("type") == "Manifest"]
    if len(items) != 1 or len(items[0]["payloads"]) != 1:
        raise ValueError("unexpected VS channel manifest layout")
    manifest_payload = items[0]["payloads"][0]
    manifest_data = get_bytes(manifest_payload["url"])
    # The service's vsman hash has historically described other bytes. Record
    # the actual metadata hash for audit; never relax payload hash verification.
    packages = json.loads(manifest_data.decode("utf-8-sig"))["packages"]
    headers = [p for p in packages if re.fullmatch(r"Microsoft\.VC\.[\d.]+\.CRT\.Headers\.base", p["id"])]
    if crt_version:
        headers = [p for p in headers if p["id"] == "Microsoft.VC." + crt_version + ".CRT.Headers.base"]
    header = max(headers, key=lambda p: version_key(p["id"]))
    crt_version = header["id"].split("Microsoft.VC.", 1)[1].split(".CRT.", 1)[0]
    selected = [header]
    for variant in ("Desktop", "Store"):
        name = "Microsoft.VC." + crt_version + ".CRT.x64." + variant + ".base"
        selected.append(next(p for p in packages if p["id"] == name))
    sdks = [p for p in packages if re.fullmatch(r"Win\d+SDK_[\d.]+", p["id"])]
    if sdk_version:
        sdks = [p for p in sdks if p["id"].endswith("_" + sdk_version)]
    sdk = max(sdks, key=lambda p: version_key(p["id"].split("_", 1)[1]))
    sdk_version = sdk["id"].split("_", 1)[1]
    payloads = []
    for package in selected:
        choices = [p for p in package["payloads"] if p["fileName"].lower().endswith((".vsix", ".zip"))]
        if len(choices) != 1:
            raise ValueError("expected one CRT VSIX: " + package["id"])
        payloads.append(dict(choices[0], kind="crt", package=package["id"]))
    wanted = (
        "Windows SDK Desktop Headers x86-x86_en-us.msi",
        "Windows SDK Desktop Headers x64-x86_en-us.msi",
        "Windows SDK Desktop Libs x64-x86_en-us.msi",
        "Windows SDK for Windows Store Apps Headers-x86_en-us.msi",
        # SDK 10.0.26100 moved windef.h/minwindef.h & co. (include/shared) into this package.
        "Windows SDK for Windows Store Apps Headers OnecoreUap-x86_en-us.msi",
        # ... and kernel32.lib, user32.lib & co. (lib/um/x64) into this one.
        "Windows SDK for Windows Store Apps Libs-x86_en-us.msi",
        # windowsx.h (include/shared) and other OneCore desktop headers.
        "Windows SDK OnecoreUap Headers x86-x86_en-us.msi",
        "Windows SDK OnecoreUap Headers x64-x86_en-us.msi",
        "Universal CRT Headers Libraries and Sources-x86_en-us.msi",
    )
    for suffix in wanted:
        choices = [p for p in sdk["payloads"] if p["fileName"].endswith(suffix)]
        if len(choices) != 1:
            raise ValueError("SDK manifest changed; cannot find " + suffix)
        payloads.append(dict(choices[0], kind="sdk-msi", package=sdk["id"]))
    # CABs are fetched only when selected MSIs' Media tables refer to them.
    for payload in sdk["payloads"]:
        if payload["fileName"].lower().endswith(".cab"):
            payloads.append(dict(payload, kind="sdk-cab", package=sdk["id"]))
    for payload in payloads:
        validate_payload(payload)
    lock = {
        "schema": 1, "architecture": "x64", "crt_version": crt_version,
        "sdk_version": sdk_version, "licenses": LICENSES,
        "license_reviewed": False,
        "license_terms": {},
        "channel_url": channel_url,
        "channel_sha256": hashlib.sha256(channel_data).hexdigest(),
        "manifest_url": manifest_payload["url"],
        "manifest_sha256": hashlib.sha256(manifest_data).hexdigest(),
        "manifest_advertised_sha256": manifest_payload.get("sha256"),
        "payloads": payloads,
    }
    write_json(destination, lock)
    print("Metadata lock written. Review exact payloads/licences before shipping:", destination)


def fetch(payload, cache):
    validate_payload(payload)
    # Short names on purpose: Windows' MSI reader and expand.exe have no long-path support, and a player's install
    # folder can be 100+ characters deep (0.1.3: "Windows MSI database error 110" at 115 characters).
    suffix = Path(payload["fileName"].replace("\\", "/")).suffix.lower()
    destination = cache / (payload["sha256"].lower()[:20] + suffix)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if sha256(destination) == payload["sha256"].lower():
            return destination
        raise ValueError("cached payload is corrupt; preserve it and choose a fresh cache: " + str(destination))
    partial = destination.with_name(destination.name + ".part" + uuid.uuid4().hex[:8])
    print("Download", payload["fileName"], payload["size"], "bytes", flush=True)
    digest = hashlib.sha256()
    count = 0
    with urllib.request.urlopen(official_url(payload["url"]), timeout=120) as response, partial.open("xb") as output:
        official_url(response.geturl())
        for chunk in iter(lambda: response.read(1024 * 1024), b""):
            count += len(chunk)
            # The manifest's "size" is not always the served byte count (VSIX: 2,128,977 listed,
            # 2,116,223 served, same SHA-256): it only bounds the download; the SHA-256 decides.
            if count > payload["size"] * 2 + (16 << 20):
                raise ValueError("payload exceeds locked size")
            digest.update(chunk)
            output.write(chunk)
    if digest.hexdigest() != payload["sha256"].lower():
        raise ValueError("payload size/SHA-256 mismatch: " + payload["fileName"])
    partial.rename(destination)
    return destination


def destination_for(path, kind):
    """Keep headers and x64 import/static libraries, never compilers or installers."""
    parts = list(safe_parts(path))
    lower = [p.lower() for p in parts]
    for index, part in enumerate(lower):
        if part == "include" and index + 1 < len(parts):
            tail = parts[index + 1:]
            if kind == "crt":
                return Path("msvc", "include", *tail)
            if re.fullmatch(r"\d+(\.\d+)+", tail[0]):
                tail = tail[1:]
            if tail and tail[0].lower() in ("ucrt", "um", "shared", "winrt", "cppwinrt"):
                return Path("winsdk", "include", *tail)
        if part == "lib" and index + 2 < len(parts):
            tail = parts[index + 1:]
            if kind == "crt" and tail[0].lower() == "x64":
                if len(tail) == 2 and tail[-1].lower().endswith(".lib"):
                    return Path("msvc", "lib", "x64", tail[-1])
                # Store provides oldnames.lib on some toolsets; Desktop wins conflicts.
                if len(tail) == 3 and tail[1].lower() == "store" and tail[-1].lower() == "oldnames.lib":
                    return Path("msvc", "lib", "x64", tail[-1])
            if re.fullmatch(r"\d+(\.\d+)+", tail[0]):
                tail = tail[1:]
            if kind == "sdk" and len(tail) == 3 and tail[0].lower() in ("ucrt", "um") and tail[1].lower() == "x64" and tail[-1].lower().endswith(".lib"):
                return Path("winsdk", "lib", *tail)
    return None


def copy_one(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if sha256(source) != sha256(destination):
            raise ValueError("conflicting sysroot files: " + str(destination))
        return
    shutil.copy2(source, destination)


def extract_crt(archive, staging):
    with zipfile.ZipFile(archive) as source:
        for entry in source.infolist():
            safe_parts(entry.filename)
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("symlink in CRT archive")
            target = destination_for(urllib.parse.unquote(entry.filename), "crt")
            if target is None or entry.is_dir():
                continue
            destination = staging / target
            destination.parent.mkdir(parents=True, exist_ok=True)
            if "/store/" in urllib.parse.unquote(entry.filename).replace("\\", "/").lower() and destination.exists():
                continue
            with source.open(entry) as stream:
                data = stream.read()
            if destination.exists():
                if destination.read_bytes() != data:
                    raise ValueError("conflicting CRT archive members: " + str(target))
            else:
                with destination.open("xb") as output:
                    output.write(data)


class MsiDatabase:
    """Read-only Windows Installer database access; does not execute the package."""
    def __init__(self, path):
        from ctypes import wintypes
        self.api = ctypes.WinDLL("msi", use_last_error=True)
        signatures = {
            "MsiOpenDatabaseW": ([wintypes.LPCWSTR, wintypes.LPCWSTR, ctypes.POINTER(wintypes.UINT)], wintypes.UINT),
            "MsiDatabaseOpenViewW": ([wintypes.UINT, wintypes.LPCWSTR, ctypes.POINTER(wintypes.UINT)], wintypes.UINT),
            "MsiViewExecute": ([wintypes.UINT, wintypes.UINT], wintypes.UINT),
            "MsiViewFetch": ([wintypes.UINT, ctypes.POINTER(wintypes.UINT)], wintypes.UINT),
            "MsiRecordGetStringW": ([wintypes.UINT, wintypes.UINT, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)], wintypes.UINT),
            "MsiCloseHandle": ([wintypes.UINT], wintypes.UINT),
        }
        for name, (arguments, result) in signatures.items():
            function = getattr(self.api, name)
            function.argtypes, function.restype = arguments, result
        self.handle = wintypes.UINT()
        self.ok(self.api.MsiOpenDatabaseW(str(path), None, ctypes.byref(self.handle)))

    @staticmethod
    def ok(result):
        if result:
            raise OSError("Windows MSI database error " + str(result))

    def rows(self, table, columns):
        from ctypes import wintypes
        view = wintypes.UINT()
        query = "SELECT " + ", ".join("`" + c + "`" for c in columns) + " FROM `" + table + "`"
        self.ok(self.api.MsiDatabaseOpenViewW(self.handle, query, ctypes.byref(view)))
        try:
            self.ok(self.api.MsiViewExecute(view, 0))
            while True:
                record = wintypes.UINT()
                result = self.api.MsiViewFetch(view, ctypes.byref(record))
                if result == 259:
                    break
                self.ok(result)
                try:
                    row = []
                    for index in range(1, len(columns) + 1):
                        buffer = ctypes.create_unicode_buffer(32768)
                        size = wintypes.DWORD(len(buffer))
                        self.ok(self.api.MsiRecordGetStringW(record, index, buffer, ctypes.byref(size)))
                        row.append(buffer.value)
                    yield row
                finally:
                    self.api.MsiCloseHandle(record)
        finally:
            self.api.MsiCloseHandle(view)

    def close(self):
        self.api.MsiCloseHandle(self.handle)


def validate_cabinet(path):
    # Windows expand receives only hash-verified cabinets with safe member names.
    with path.open("rb") as stream:
        header = stream.read(36)
        if len(header) != 36 or header[:4] != b"MSCF":
            raise ValueError("invalid cabinet")
        file_offset = struct.unpack_from("<I", header, 16)[0]
        count = struct.unpack_from("<H", header, 28)[0]
        flags = struct.unpack_from("<H", header, 30)[0]
        if flags & 3:
            raise ValueError("split cabinets are not supported")
        stream.seek(file_offset)
        for _ in range(count):
            if len(stream.read(16)) != 16:
                raise ValueError("truncated cabinet file record")
            name = bytearray()
            while True:
                byte = stream.read(1)
                if not byte or len(name) > 32768:
                    raise ValueError("invalid cabinet filename")
                if byte == b"\0":
                    break
                name.extend(byte)
            safe_parts(name.decode("utf-8", errors="strict"))


def extract_sdk(msi, payloads, cache, work, staging, downloaded):
    database = MsiDatabase(msi)
    try:
        directories = {row[0]: row[1:] for row in database.rows("Directory", ("Directory", "Directory_Parent", "DefaultDir"))}
        components = dict(database.rows("Component", ("Component", "Directory_")))
        cabinets = [row[0] for row in database.rows("Media", ("Cabinet",)) if row[0]]
        files = list(database.rows("File", ("File", "Component_", "FileName")))
    finally:
        database.close()
    def directory_path(key, seen=None):
        seen = set() if seen is None else seen
        if key in seen:
            raise ValueError("cycle in MSI directories")
        seen.add(key)
        parent, name = directories[key]
        # MSI DefaultDir may specify target:source and short|long names.
        name = name.split(":", 1)[0].split("|")[-1]
        result = directory_path(parent, seen) if parent else []
        if name not in (".", "SourceDir", "TARGETDIR", ""):
            result.extend(safe_parts(name))
        return result
    expanded = work / ("x" + uuid.uuid4().hex[:8])
    expanded.mkdir(parents=True)
    for cabinet in cabinets:
        if cabinet.startswith("#"):
            raise ValueError("embedded MSI cabinet unsupported; owner must update locked SDK selection")
        name = Path(cabinet.replace("\\", "/")).name
        matches = [p for p in payloads if p["kind"] == "sdk-cab" and Path(p["fileName"].replace("\\", "/")).name == name]
        if len(matches) != 1:
            raise ValueError("cabinet absent/ambiguous in lock: " + name)
        payload = matches[0]
        archive = fetch(payload, cache)
        downloaded[payload["sha256"]] = payload
        validate_cabinet(archive)
        expand = Path(os.environ["SystemRoot"]) / "System32" / "expand.exe"
        subprocess.run([str(expand), str(archive), "-F:*", str(expanded)], check=True, creationflags=subprocess.CREATE_NO_WINDOW)
    for key, component, filename in files:
        relative = "/".join(directory_path(components[component]) + [filename.split("|")[-1]])
        target = destination_for(relative, "sdk")
        if target is None:
            continue
        safe_parts(key)
        source = expanded / key
        if not source.is_file():
            raise ValueError("SDK cabinet missing MSI file: " + key)
        copy_one(source, staging / target)


def check(root, lock_path):
    license_terms(root, read_json(lock_path))
    toolchain = root / "toolchain"
    marker = read_json(toolchain / "sysroot.json")
    if marker.get("schema") != 1 or marker.get("lock_sha256") != sha256(lock_path) or not marker.get("license_accepted"):
        raise ValueError("sysroot marker does not match this release's Microsoft lock/licence acceptance")
    for relative in REQUIRED:
        if relative.lower() not in {name.lower() for name in marker.get("files", {})} or not (toolchain / relative).is_file():
            raise ValueError("incomplete Microsoft sysroot: " + relative)
    for relative, digest in marker["files"].items():
        safe_parts(relative)
        path = toolchain / relative
        if not path.is_file() or sha256(path) != digest:
            raise ValueError("Microsoft sysroot integrity check failed: " + relative)
    return marker


def install(root, lock_path):
    if os.name != "nt":
        raise ValueError("sysroot extraction requires Windows")
    lock = read_json(lock_path)
    if lock.get("schema") != 1 or lock.get("architecture") != "x64" or lock.get("licenses") != LICENSES:
        raise ValueError("unsupported Microsoft lock/licence set")
    license_terms(root, lock)
    for payload in lock["payloads"]:
        validate_payload(payload)
    toolchain = root / "toolchain"
    if (toolchain / "sysroot.json").exists():
        check(root, lock_path)
        print("Microsoft sysroot is already verified")
        return
    if (toolchain / "msvc").exists() or (toolchain / "winsdk").exists():
        raise ValueError("unmarked/partial sysroot exists; keep it and use a fresh release folder")
    work = toolchain / "sysroot-work" / uuid.uuid4().hex[:8]
    work.mkdir(parents=True)
    staging = work / "staging"
    staging.mkdir()
    cache = toolchain / "sysroot-cache"
    downloaded = {}
    for payload in lock["payloads"]:
        if payload["kind"] == "sdk-cab":
            continue
        archive = fetch(payload, cache)
        downloaded[payload["sha256"]] = payload
        if payload["kind"] == "crt":
            extract_crt(archive, staging)
        elif payload["kind"] == "sdk-msi":
            extract_sdk(archive, lock["payloads"], cache, work, staging, downloaded)
        else:
            raise ValueError("unknown payload kind")
    for relative in REQUIRED:
        if not (staging / relative).is_file():
            raise ValueError("Microsoft sysroot extraction did not produce " + relative)
    inventory = {p.relative_to(staging).as_posix(): sha256(p) for p in staging.rglob("*") if p.is_file()}
    (staging / "msvc").rename(toolchain / "msvc")
    (staging / "winsdk").rename(toolchain / "winsdk")
    write_json(toolchain / "sysroot.json", {
        "schema": 1, "architecture": "x64", "lock_sha256": sha256(lock_path),
        "crt_version": lock["crt_version"], "sdk_version": lock["sdk_version"],
        "license_accepted": True, "licenses": LICENSES, "files": inventory,
        "downloads": list(downloaded.values()),
    })
    print("Microsoft sysroot verified. Payload cache retained on this PC; never redistribute it.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--lock", type=Path)
    parser.add_argument("--accept-license", action="store_true", help="the player has read and accepted the linked Microsoft terms")
    parser.add_argument("--print-license", action="store_true")
    parser.add_argument("--check", action="store_true", help="verify an existing sysroot without network access")
    parser.add_argument("--make-lock", type=Path, help="maintainer: resolve official metadata into a new release lock")
    parser.add_argument("--channel", default=CHANNEL)
    parser.add_argument("--crt-version")
    parser.add_argument("--sdk-version")
    args = parser.parse_args()
    if args.print_license:
        print("Microsoft files are downloaded on your PC and are not included in the T4 zip.")
        lock_path = args.lock or args.root / "tools" / "msvc_sysroot.lock.json"
        for name, url, text in license_terms(args.root, read_json(lock_path)):
            print(name + ": " + url + "\n" + text + "\n")
        return 0
    if args.make_lock:
        make_lock(args.make_lock, args.channel, args.crt_version, args.sdk_version)
        return 0
    lock = args.lock or args.root / "tools" / "msvc_sysroot.lock.json"
    if not lock.is_file():
        raise ValueError("release is missing its reviewed tools/msvc_sysroot.lock.json; contact the release owner")
    if args.check:
        check(args.root, lock)
        print("Microsoft sysroot integrity verified")
    elif not args.accept_license:
        parser.error("read --print-license, then pass --accept-license only after accepting Microsoft's terms")
    else:
        install(args.root, lock)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, StopIteration, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print("ERROR:", error, file=sys.stderr)
        sys.exit(1)
