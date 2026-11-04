"""Start one host/join game with the player profile, build identity and UDP check."""
import datetime
import os
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from player_common import ROOT, NO_WINDOW, PlayerParser, configure_output, digest, integer_range, option, read_json, resolve_us_tree, write_json
from net_preflight import new_identity, preflight, resolve_peer


def parser():
    ap = PlayerParser(description=__doc__)
    option(ap, "AsHost", action="store_true")
    ap.add_argument("-Host", "--host", dest="AsHost", action="store_true")
    for name, default in (("Join", ""), ("Delay", "auto"), ("Sim", ""), ("RunDir", ""),
                          ("Src", os.environ.get("TEKKEN4_SRC", "")),
                          ("BuildDir", os.environ.get("TEKKEN4_BUILD_DIR", ""))):
        option(ap, name, default=default)
    option(ap, "Iso", default=os.environ.get("TEKKEN4_ISO", ""))
    ap.add_argument("-IsoPath", "--iso-path", dest="Iso", default=__import__('argparse').SUPPRESS)
    option(ap, "Port", type=integer_range(1, 65535), default=7400)
    option(ap, "Pad", type=int, default=0)
    option(ap, "Sound", type=int, default=1)
    option(ap, "PreflightTimeoutSeconds", type=integer_range(5, 600), default=90)
    for name in ("NoDiagnostics", "SkipPreflight", "UseInheritedProfile"):
        option(ap, name, action="store_true")
    return ap


def player_environment(a, inherited):
    env = dict(inherited)
    if not a.UseInheritedProfile:
        off = "STRICT_HELLO DELAY_MATCH COST_PROFILE HASH_PROFILE SIM_SAFE_WAIT REFRESH_RC AUTO_VS".split()
        env.update({"TEKKEN4_NET_" + name: "0" for name in off})
        env.update({"TEKKEN4_NET_" + name: "1" for name in "TIMESYNC EARLY LAZY LOCALPAD".split()})
        env.update(TEKKEN4_RB_AUDIO_TIMELINE="0", TEKKEN4_NET_MAXPRED="8")
        if env.get("TEKKEN4_NET_COALESCE") != "0":
            env["TEKKEN4_NET_COALESCE"] = "1"
        clear = {"TEKKEN4_NET_" + name for name in "SIM SEED END SHOTS DESYNC_DUMP RBSTART EARLY_MS LOCKDELAY HASH_EVERY AUTO_VS_END RESULT".split()}
        clear.add("TEKKEN4_RAND_SEED")
        for name in list(env):
            if name in clear or (name.startswith("TEKKEN4_RB_") and name != "TEKKEN4_RB_AUDIO_TIMELINE"):
                env.pop(name, None)
    if a.NoDiagnostics:
        env["TEKKEN4_NET_DIAG"] = "0"
    elif (not a.UseInheritedProfile and env.get("TEKKEN4_NET_DIAG") != "0") or not env.get("TEKKEN4_NET_DIAG"):
        env["TEKKEN4_NET_DIAG"] = "1"
    env.update(TEKKEN4_NET=f"host:{a.Port}" if a.AsHost else f"join:{a.Join}:{a.Port}",
               TEKKEN4_NET_DELAY=a.Delay, TEKKEN4_NET_PAD=str(a.Pad), TEKKEN4_SOUND=str(a.Sound))
    if a.Sim:
        env["TEKKEN4_NET_SIM"] = a.Sim
    if not env.get("PS2X_GS_BACKEND"):
        env["PS2X_GS_BACKEND"] = "gl"
    return env


def select_build(root, src, build_dir):
    if not src:
        candidates = [(root.parent / "tekken4-fork-net", "net"), (root / "deps/ps2recomp", "runtime")]
        try:
            candidates.append((resolve_us_tree(root), "runtime"))
        except ValueError as ex:
            print("WARNING: " + str(ex), flush=True)
        for candidate, default in candidates:
            selected = build_dir or default
            if (candidate / "out" / selected / "ps2xRuntime/ps2EntryRunner.exe").is_file():
                src, build_dir = candidate, selected
                break
        if not src:
            vendored = root / "deps/ps2recomp"
            src = vendored if (vendored / ".t4-vendored.json").is_file() else resolve_us_tree(root)
    src = Path(src).resolve()
    if not build_dir:
        build_dir = "net" if (src / "out/net/ps2xRuntime/ps2EntryRunner.exe").is_file() else "runtime"
    return src, build_dir


def run(a, root=ROOT):
    root = Path(root)
    if a.AsHost and a.Join:
        raise ValueError("Give either -Host or -Join <host>, not both.")
    if not a.AsHost and not a.Join:
        raise ValueError("Give -Host or -Join <host>.")
    side = "host" if a.AsHost else "join"
    if a.Sim and not a.UseInheritedProfile:
        raise ValueError("-Sim is outside the Sunday beta profile. Use -UseInheritedProfile only for a separate maintainer experiment.")
    src, build_dir = select_build(root, a.Src, a.BuildDir)
    exe_dir = src / "out" / build_dir / "ps2xRuntime"
    exe, elf = exe_dir / "ps2EntryRunner.exe", root / "game/disc/SLUS_203.28"
    if not exe.is_file():
        raise ValueError(f"Runner missing: {exe}. Build locally from your own ISO with tools\\build_game.ps1; check -Src and -BuildDir.")
    if not elf.is_file():
        raise ValueError("Game ELF missing. Run tools\\build_game.ps1 -Iso <your ISO> locally first.")
    run_dir = Path(a.RunDir or root / "logs/net" / (f"play_{side}_" + datetime.datetime.now().strftime("%Y%m%d_%H%M%S_%f")[:-3])).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    iso = a.Iso
    if not iso:
        isos = sorted(root.glob("*.iso"))
        if len(isos) > 1:
            raise ValueError("More than one ISO in the project folder. Choose yours with -Iso <path>.")
        if isos:
            iso = str(isos[0])
    if not iso:
        iso = (read_json(root / "logs/build_game_state.json", {}) or {}).get("verify", {}).get("iso", "")
    if a.Join:
        a.Join = resolve_peer(a.Join)
    env = player_environment(a, os.environ)
    if iso:
        iso = str(Path(iso).resolve())
        env["TEKKEN4_ISO"] = iso
    if a.UseInheritedProfile:
        print("WARNING: Inherited experimental profile: this is not the Sunday beta acceptance profile.", flush=True)
    local = None
    try:
        if not iso:
            raise ValueError("ISO missing. Pass -Iso <your US SLUS-20328 v1.00 ISO>, set TEKKEN4_ISO, or use the ISO saved by build_game.ps1.")
        local = new_identity(exe_dir / "t4net_build.json", iso, env)
        if digest(elf) != local["elf_sha1"]:
            raise ValueError("The extracted ELF differs from the build identity. Rebuild locally from the intended US v1.00 ISO, then regenerate the build identity.")
        write_json(run_dir / "build_identity.json", local)
        env["TEKKEN4_NET_BUILD"] = local["build_id"]
        print(f"Build id: {local['build_id']}\nC++ compiler version: {local['compiler']}\nISO SHA-256: {local['iso_sha256']}", flush=True)
    except (OSError, ValueError) as ex:
        if not a.SkipPreflight:
            print(f"Build identity check failed: {ex}\nIf the identity is missing or stale, rebuild the runtime first, then regenerate it with:\n  python -I \"{root / 'tools/t4_buildid.py'}\" --src \"{src}\" --out \"{exe_dir}\"", flush=True)
            raise
        print(f"WARNING: Identity could not be checked: {ex}", flush=True)
        stamp = exe_dir / "t4net_build.txt"
        env["TEKKEN4_NET_BUILD"] = stamp.read_text(encoding="utf-8-sig").split()[0] if stamp.is_file() and stamp.read_text(encoding="utf-8-sig").strip() else ""
    info = dict(started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), side=side, port=a.Port,
                pad=a.Pad, delay=a.Delay, sound=a.Sound, diagnostics=env["TEKKEN4_NET_DIAG"] == "1", exit_code=None,
                profile="inherited-experiment" if a.UseInheritedProfile else "sunday-beta",
                coalesce=env.get("TEKKEN4_NET_COALESCE"), auto_vs=env.get("TEKKEN4_NET_AUTO_VS"))
    write_json(run_dir / "run_info.json", info)
    print(f"{side}: build {env['TEKKEN4_NET_BUILD']}, diagnostics={env['TEKKEN4_NET_DIAG']}, logs: {run_dir}", flush=True)
    if a.SkipPreflight:
        print("WARNING: Preflight skipped explicitly: build/compiler/ISO comparison and UDP reachability have NOT been verified.", flush=True)
    else:
        print("Both PCs must run this command now. Waiting for matching build/compiler/ISO and a two-way UDP reply.", flush=True)
        print("Firewall: allow this Python UDP check AND ps2EntryRunner.exe, or configure the UDP port rule yourself.", flush=True)
        preflight(a.AsHost, a.Join, a.Port, local, a.PreflightTimeoutSeconds, run_dir / "preflight.json", env)
    for name in ("TEKKEN4_NET_END", "TEKKEN4_NET_SHOTS", "TEKKEN4_NET_DESYNC_DUMP", "TEKKEN4_NET_SIM"):
        if env.get(name):
            print(f"WARNING: Inherited {name}={env[name]}. For an ordinary Sunday test, use a fresh shell without harness settings.", flush=True)
    print("Starting the game. Close its window when done; then collect the logs on both PCs.", flush=True)
    with (run_dir / "stdout.txt").open("wb") as stdout, (run_dir / "stderr.txt").open("wb") as stderr:
        process = subprocess.Popen([str(exe), str(elf)], cwd=run_dir, env=env, stdout=stdout, stderr=stderr, creationflags=NO_WINDOW)
        code = process.wait()
    info["exit_code"] = code
    write_json(run_dir / "run_info.json", info)
    rb_log = run_dir / "rb_frames.log"
    if rb_log.is_file():
        lines = [line for line in rb_log.read_text(encoding="utf-8", errors="replace").splitlines() if line.startswith(("NETSUMMARY", "NETDESYNC"))]
        for line in lines[-3:]:
            print(line, flush=True)
    else:
        print("WARNING: No rb_frames.log was written. Check net.log and the startup/error output.", flush=True)
    print(f"Game exit code: {code}. Logs: {run_dir}", flush=True)
    return code


def main(argv=None):
    configure_output()
    a = parser().parse_args(argv)
    try:
        return run(a)
    except (OSError, ValueError) as ex:
        print(str(ex), file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
