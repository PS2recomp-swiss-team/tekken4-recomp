"""Build identity comparison and the T4TEST1 two-way UDP player preflight."""
import contextlib
import datetime
import hashlib
import io
import ipaddress
import json
import os
from pathlib import Path
import re
import select
import socket
import sys
import time
import uuid
sys.path.insert(0, str(Path(__file__).resolve().parent))
from player_common import PlayerParser, configure_output, digest, integer_range, option, read_json, write_json

RULES = {
    "build_id": r"[0-9a-f]{16}", "compiler": r"[A-Za-z0-9_.+ -]{1,100}",
    "iso_sha256": r"[0-9a-f]{64}", "elf_sha1": r"[0-9a-f]{40}", "net": r"[0-9]{1,3}",
    "strict_hello": r"[01]", "delay_match": r"[01]",
}
REMEDIES = {
    "build_id": "Use the same test zip and build configuration, then rebuild both runtimes.",
    "compiler": "Install/select the same exact MSVC C++ toolset (or the same portable compiler), then rebuild both.",
    "iso_sha256": "The game files from the ISO differ: each player needs a clean US SLUS-20328 v1.00 disc image.",
    "elf_sha1": "Re-extract and rebuild from the matching verified US ISO.",
    "net": "Use the same test zip and rebuild both runtimes.",
    "strict_hello": "Use the same TEKKEN4_NET_STRICT_HELLO setting on both PCs, or clear it on both.",
    "delay_match": "Use the same TEKKEN4_NET_DELAY_MATCH setting on both PCs, or clear it on both.",
}


def identity(value):
    if not isinstance(value, dict):
        raise ValueError("invalid_identity: missing build identity")
    safe = {"schema": 1}
    for name, rule in RULES.items():
        # PowerShell's stamp contains numeric net; the wire uses strings.
        raw = value.get(name)
        text = str(raw) if isinstance(raw, (str, int)) and not isinstance(raw, bool) else ""
        if not re.fullmatch(rule, text):
            raise ValueError("invalid_identity: invalid " + name)
        safe[name] = text
    return safe


def new_identity(stamp_path, iso_path, env=None, root=None):
    env = os.environ if env is None else env
    if not Path(stamp_path).is_file():
        raise ValueError("invalid_identity: t4net_build.json is missing. Rebuild the same runtime on both PCs; do not reuse an old build stamp.")
    if not iso_path or not Path(iso_path).is_file():
        raise ValueError("invalid_identity: ISO missing. Pass -Iso with your own US SLUS-20328 v1.00 ISO.")
    stamp = read_json(stamp_path)
    if not isinstance(stamp, dict):
        raise ValueError("invalid_identity: unreadable t4net_build.json. Rebuild the runtime.")
    lines = stamp.get("toolchain", [])
    if not isinstance(lines, list):
        lines = []
    ids = [x[7:] for x in lines if isinstance(x, str) and x.startswith("CXX_ID=")]
    versions = [x[12:] for x in lines if isinstance(x, str) and x.startswith("CXX_VERSION=")]
    if len(ids) != 1 or len(versions) != 1:
        raise ValueError("invalid_identity: compiler version missing in t4net_build.json. Rebuild the runtime.")
    compiler = ids[0] + " " + versions[0]
    print(f"Compiler: {compiler}. Windows SDK and MSVC headers/library versions are not recorded in this build stamp.", flush=True)
    print("Hashing your game files (SHA-256); this can take a minute.", flush=True)
    return identity(dict(build_id=stamp.get("id"), compiler=compiler, iso_sha256=game_files_sha256(root, env),
                         elf_sha1=stamp.get("elf"), net=stamp.get("net"),
                         strict_hello="1" if env.get("TEKKEN4_NET_STRICT_HELLO") == "1" else "0",
                         delay_match="1" if env.get("TEKKEN4_NET_DELAY_MATCH") == "1" else "0"))


# 0.1.3: the identity's "iso_sha256" is the digest of the game files extracted from the ISO (game\disc), not of
# the ISO file: two clean rips of SLUS-20328 hold the same files but are different ISO files. Same formula as the
# launcher's openrecomp/adapters/t4_online.py game_files_sha256.
GAME_FILES = ("SLUS_203.28", "TEKKEN/DATA.BIN", "IRX/IOPRP243.IMG")


def game_files_sha256(root=None, env=None):
    env = os.environ if env is None else env
    disc = Path(root or Path(__file__).resolve().parent.parent) / "game" / "disc"
    h = hashlib.sha256(b"t4-game-files-v1\n")
    for name in GAME_FILES:
        path = disc.joinpath(*name.split("/"))
        if not path.is_file():
            raise ValueError("invalid_identity: " + name + " is missing in game\\disc. Build the game from your ISO first.")
        h.update(name.encode() + b"\0" + digest(path, "sha256").encode() + b"\n")
    return h.hexdigest()


def compare_identity(local, peer):
    different = []
    for name, remedy in REMEDIES.items():
        if local[name] != peer[name]:
            print(f"DIFFERENT {name}: local={local[name]}; peer={peer[name]}", flush=True)
            print(remedy, flush=True)
            different.append(name)
    return different


def resolve_peer(peer):
    try:
        address = ipaddress.ip_address(peer)
    except ValueError:
        address = None
    if address is not None:
        if address.version == 4:
            return str(address)
        raise ValueError("invalid_peer: the game needs an IPv4 address; IPv6-only peers are not supported.")
    # A daemon thread bounds DNS without an executor shutdown waiting on the OS resolver.
    import queue
    import threading
    answers = queue.Queue()
    def lookup():
        try:
            answers.put(socket.getaddrinfo(peer, None, socket.AF_INET, socket.SOCK_DGRAM)[0][4][0])
        except OSError:
            answers.put(None)
    threading.Thread(target=lookup, daemon=True).start()
    try:
        result = answers.get(timeout=5)
        if result:
            return result
    except queue.Empty:
        pass
    raise ValueError("invalid_peer: host name did not resolve to IPv4 within 5 seconds. Check the name and DNS connection, or use the host public/VPN IPv4 address.")


def encode_packet(nonce, echo, ready, local):
    packet = dict(tag="T4TEST1", nonce=nonce, echo=echo, ready=ready, identity=identity(local))
    raw = json.dumps(packet, separators=(",", ":")).encode("utf-8")
    decode_packet(raw)  # same strict format on send and receive
    return raw


def decode_packet(raw):
    if not 10 <= len(raw) <= 4096:
        raise ValueError("invalid packet size")
    try:
        packet = json.loads(raw.decode("utf-8"))
        if (packet["tag"] != "T4TEST1" or not isinstance(packet["nonce"], str)
                or not re.fullmatch(r"[0-9a-f]{32}", packet["nonce"])
                or not isinstance(packet["echo"], str) or not re.fullmatch(r"(?:[0-9a-f]{32})?", packet["echo"])
                or type(packet["ready"]) is not bool):
            raise ValueError("invalid preflight packet")
        return dict(tag="T4TEST1", nonce=packet["nonce"], echo=packet["echo"], ready=packet["ready"], identity=identity(packet["identity"]))
    except (KeyError, TypeError, UnicodeError) as ex:
        raise ValueError("invalid preflight packet") from ex


def preflight(as_host, peer, port, local, timeout_seconds, output_path, env=None):
    env = os.environ if env is None else env
    local = identity(local)
    report = dict(schema=1, time_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  role="host" if as_host else "join", status="failed", local=local, peer=None,
                  reason="udp_timeout", mismatch_fields=[])
    udp = None
    try:
        remote = None
        if not as_host:
            report["reason"] = "invalid_peer"
            remote = (resolve_peer(peer), port)
            report["reason"] = "udp_timeout"
        local_port = port if as_host else 0
        if not as_host and env.get("TEKKEN4_NET_PORT"):
            try:
                local_port = int(env["TEKKEN4_NET_PORT"])
                if not 0 <= local_port <= 65535:
                    raise ValueError()
            except ValueError:
                report["reason"] = "invalid_local_port"
                raise ValueError("invalid_local_port: TEKKEN4_NET_PORT must be 0 through 65535.")
        bind = env.get("TEKKEN4_NET_BIND") or "0.0.0.0"
        try:
            bind = str(ipaddress.IPv4Address(bind))
        except ipaddress.AddressValueError:
            report["reason"] = "invalid_bind"
            raise ValueError("invalid_bind: TEKKEN4_NET_BIND must be a local IPv4 address.")
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            udp.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        try:
            udp.bind((bind, local_port))
        except OSError:
            report["reason"] = "udp_bind_failed"
            raise ValueError(f"udp_bind_failed: local UDP port {local_port} is unavailable. Close the previous test/game; check TEKKEN4_NET_BIND and TEKKEN4_NET_PORT.")
        print(f"UDP check: {report['role']}, host port {port}. Start the other PC now; waiting up to {timeout_seconds} seconds.", flush=True)
        nonce, peer_nonce = uuid.uuid4().hex, ""
        seen, ready, peer_ready = False, False, False
        different, finish_at, last_send = [], None, -1.0
        started = time.monotonic()
        while time.monotonic() - started < timeout_seconds:
            now = time.monotonic() - started
            if remote and now - last_send >= .15:
                try:
                    udp.sendto(encode_packet(nonce, peer_nonce, ready, local), remote)
                except (ConnectionResetError, ConnectionRefusedError):
                    pass
                last_send = now
            if select.select([udp], [], [], .02)[0]:
                try:
                    raw, sender = udp.recvfrom(65535)
                except (ConnectionResetError, ConnectionRefusedError):
                    continue
                if remote and sender != remote:
                    continue
                try:
                    packet = decode_packet(raw)
                except ValueError:
                    continue
                if peer_nonce and packet["nonce"] != peer_nonce:
                    continue
                if not peer_nonce:
                    remote, peer_nonce = sender, packet["nonce"]
                    report["peer"] = received = packet["identity"]
                    print(f"Peer build: {received['build_id']}\nPeer C++ compiler: {received['compiler']}\nPeer ISO SHA-256: {received['iso_sha256']}", flush=True)
                    report["mismatch_fields"] = different = compare_identity(local, received)
                    if different:
                        report["reason"], finish_at = "build_mismatch", now + 1.5
                    last_send = -1.0
                seen = seen or packet["echo"] == nonce
                ready = seen and not different
                peer_ready = peer_ready or (ready and packet["ready"])
                if ready and peer_ready and finish_at is None:
                    finish_at = now + 1.5
            if finish_at is not None and now >= finish_at:
                if different:
                    raise ValueError("build_mismatch: the values above differ. Fix them on both PCs and retry.")
                report.update(status="ok", reason="matched")
                print("MATCH: build id, C++ compiler, ISO hash and protocol settings agree.", flush=True)
                print("UDP OK: both PCs exchanged and acknowledged packets on the host game port.", flush=True)
                print("Allow ps2EntryRunner.exe separately in Windows Firewall. This Python probe cannot check its application rule.", flush=True)
                return report
        raise ValueError(f"udp_timeout: no complete two-way check within {timeout_seconds} seconds. Both PCs must run this command. Check the host IPv4/UDP port, router forwarding or VPN, and the Python firewall rule; then retry both.")
    finally:
        if udp:
            udp.close()
        try:
            write_json(output_path, report)
        except OSError as ex:
            message = f"Could not write the preflight report to {output_path}: {ex}"
            if report["status"] == "ok":
                raise OSError(message) from ex
            print("WARNING: " + message, flush=True)


def wrapper_request(request):
    """JSON RPC for dot-sourced PowerShell compatibility functions; stdout stays machine-readable."""
    op = request["operation"]
    if op == "identity":
        return identity(request["value"])
    if op == "new":
        return new_identity(request["stamp"], request["iso"])
    if op == "compare":
        return compare_identity(identity(request["local"]), identity(request["peer"]))
    if op == "resolve":
        return resolve_peer(request["peer"])
    if op == "preflight":
        return preflight(request["as_host"], request["peer"], request["port"], request["identity"], request["timeout"], request["output"])
    raise ValueError("Unknown preflight operation")


def main(argv=None):
    configure_output()
    if argv == ["--request"] or (argv is None and sys.argv[1:] == ["--request"]):
        messages = io.StringIO()
        try:
            with contextlib.redirect_stdout(messages):
                result = wrapper_request(json.load(sys.stdin))
            response = dict(result=result, messages=messages.getvalue().splitlines(), error=None)
        except (OSError, ValueError, KeyError, TypeError) as ex:
            response = dict(result=None, messages=messages.getvalue().splitlines(), error=str(ex))
        print(json.dumps(response))
        return 1 if response["error"] else 0
    ap = PlayerParser(description=__doc__)
    option(ap, "AsHost", action="store_true")
    ap.add_argument("-Host", "--host", dest="AsHost", action="store_true")
    option(ap, "Peer", default="")
    option(ap, "Port", type=integer_range(1, 65535), default=7400)
    option(ap, "TimeoutSeconds", type=integer_range(5, 600), default=90)
    option(ap, "Identity", required=True, help="path to build_identity.json")
    option(ap, "OutputPath", required=True)
    a = ap.parse_args(argv)
    try:
        preflight(a.AsHost, a.Peer, a.Port, read_json(a.Identity), a.TimeoutSeconds, a.OutputPath)
        return 0
    except (OSError, ValueError) as ex:
        print(str(ex), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
