"""Player ISO-to-game pipeline (Windows or bundled Windows Python under Wine).

No PowerShell, robocopy or batch build scripts are called. -WhatIf checks the
prerequisites and ISO and plans later steps, writing only build_game.log.
"""
import datetime
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parent))
from player_common import ROOT, NO_WINDOW, PlayerParser, build_tree, configure_output, digest, git_output, option, read_json, write_json

EXPECTED_ELF = "a4b7dde20a2918c550badd127a245db155c36815"
PINNED = "eb8688b2fd191129f103a39543002c005b33409c"
ALL_STEPS = ("prereq", "verify", "extract", "fork", "tools", "recomp", "stage", "runtime")
TITLES = {
    "prereq": "bundled compiler (clang-cl, lld-link, CMake, Ninja, Python) or, in a source checkout, Git + VS + CMake + Ninja",
    "extract": "SYSTEM.CNF, SLUS_203.28, IRX\\IOPRP243.IMG, TEKKEN\\DATA.BIN -> game\\disc",
    "tools": "PS2Recomp host tools (ps2_recomp.exe)",
    "recomp": "ps2_recomp.exe config\\ghidra_export.toml -> generated\\",
    "stage": "tools\\stage_generated.cmd",
}


# The files the game reads from the ISO and the launcher's online identity hashes (0.1.3: game files, not the ISO).
GAME_FILES = ("SLUS_203.28", "TEKKEN/DATA.BIN", "IRX/IOPRP243.IMG")


def write_game_files(disc, path):
    """game/t4-game-files.json: size, time and SHA-256 of each game file, so the launcher's first Online login does
    not read 2.7 GB again (it trusts an entry only while size and time still match). Reuses entries that match."""
    old = read_json(path, {}) or {}
    files = {}
    for name in GAME_FILES:
        file = Path(disc) / name
        if not file.is_file():
            continue
        stat = file.stat()
        entry = old.get("files", {}).get(name) if isinstance(old.get("files"), dict) else None
        if not (isinstance(entry, dict) and entry.get("size") == stat.st_size and entry.get("mtime_ns") == stat.st_mtime_ns
                and isinstance(entry.get("sha256"), str)):
            entry = dict(size=stat.st_size, mtime_ns=stat.st_mtime_ns, sha256=digest(file, "sha256"))
        files[name] = entry
    write_json(path, dict(schema=1, files=files))


def parse_steps(values):
    steps = [part.strip().lower() for value in (values or []) for part in value.split(",") if part.strip()]
    if not steps:
        return list(ALL_STEPS)
    for step in steps:
        if step not in ALL_STEPS:
            raise ValueError(f"Unknown step '{step}'. Steps: {', '.join(ALL_STEPS)}")
    return [step for step in ALL_STEPS if step in steps]


def parser():
    ap = PlayerParser(description=__doc__)
    option(ap, "Iso")
    option(ap, "Steps", nargs="+")
    option(ap, "LogDir")
    for name in ("Force", "WhatIf", "AcceptMicrosoftLicense"):
        option(ap, name, action="store_true")
    ap.add_argument("--dry-run", dest="WhatIf", action="store_true")
    return ap


def sha_text(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


def ticks(path):
    return Path(path).stat().st_mtime_ns // 100 + 621355968000000000


def fingerprint(paths, content=False):
    lines = []
    for path in sorted(map(Path, paths), key=lambda p: str(p).lower()):
        if path.is_file():
            value = digest(path).upper() if content else f"{path.stat().st_size}|{ticks(path)}"
            lines.append(f"{path.name}|{value}")
    return sha_text("\n".join(lines))


def needs_step(step, force, changed, have_output, recorded, current):
    """Pure resume/dependency decision shared by execution and dry runs."""
    dependencies = {"tools": {"fork"}, "recomp": {"tools", "extract"},
                    "stage": {"recomp", "fork"}, "runtime": {"stage"}}
    return force or bool(dependencies.get(step, set()) & set(changed)) or not have_output or recorded != current


def copy_changed(source, target):
    """Copy only changes; preserve timestamps so Ninja can reuse objects. Never purge."""
    if target.is_file() and source.stat().st_size == target.stat().st_size and digest(source) == digest(target):
        return False
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    return True


def visual_studio_environment(vcvars):
    if any(c in str(vcvars) for c in '\"%\r\n'):
        raise ValueError("Unsupported character in Visual Studio installation path")
    # cmd.exe needs its own quoting, not subprocess's MS C argv escaping.
    # Passing this /c command as a list corrupts paths containing spaces.
    command = f'cmd.exe /d /s /c ""{vcvars}" >nul && set"'
    return subprocess.run(command, capture_output=True, text=True, check=True, creationflags=NO_WINDOW).stdout


# Variables of the PC that would change what a release folder compiles (and so its build id) or point the build at
# the PC's own Visual Studio / Git / CMake: never passed on in a release folder (0.1.3: one build id for everyone).
# CL/_CL_/LINK/_LINK_ add compiler/linker options (clang-cl reads them too); CFLAGS & co. become CMake's flags.
RELEASE_DROP = {
    "CL", "_CL_", "LINK", "_LINK_", "CFLAGS", "CXXFLAGS", "CPPFLAGS", "LDFLAGS", "RCFLAGS", "ASMFLAGS",
    "INCLUDE", "LIB", "LIBPATH", "EXTERNAL_INCLUDE", "CC", "CXX", "VCINSTALLDIR", "VSINSTALLDIR", "VCTOOLSINSTALLDIR",
    "VCTOOLSVERSION", "VCTOOLSREDISTDIR", "VCIDEINSTALLDIR", "WINDOWSSDKDIR", "WINDOWSSDKVERSION", "WINDOWSSDKBINPATH",
    "WINDOWSSDKLIBVERSION", "WINDOWSSDKVERBINPATH", "UNIVERSALCRTSDKDIR", "UCRTVERSION", "DEVENVDIR",
    "PLATFORM", "VSCMD_ARG_TGT_ARCH", "VSCMD_ARG_HOST_ARCH", "VSCMD_VER", "VISUALSTUDIOVERSION",
    "PYTHONPATH", "PYTHONHOME", "PYTHONSTARTUP", "TEKKEN4_SRC", "TEKKEN4_VULIFT", "TEKKEN4_VU1N", "TEKKEN4_FORK_URL",
    "NINJA_STATUS", "SCCACHE_DIR", "CCACHE_DIR",
}


def release_environment(env):
    """The environment a release folder builds with: the PC's PATH is replaced by Windows' own folders (the bundled
    tools are put in front later), every CMAKE_* and the variables above are dropped. Nothing of an installed
    Visual Studio 2022/2026, Git, CMake, Ninja or Python can reach the build."""
    out = {key: value for key, value in env.items()
           if key.upper() not in RELEASE_DROP and not key.upper().startswith(("CMAKE_", "VSCMD_", "__VSCMD", "__DOTNET"))}
    for key in [k for k in out if k.upper() == "PATH"]:
        out.pop(key)
    system = env.get("SYSTEMROOT") or env.get("SystemRoot") or os.path.join((env.get("SYSTEMDRIVE") or "C:") + os.sep, "Windows")
    out["PATH"] = os.pathsep.join([os.path.join(system, "System32"), system, os.path.join(system, "System32", "Wbem")])
    return out


def stage_generated(root, tree):
    gen, runtime = root / "generated", tree / "ps2xRuntime"
    if not (gen / "register_functions.cpp").is_file():
        raise ValueError("generated\\ is empty: run ps2_recomp first")
    runner = runtime / "src/runner"
    for src in gen.rglob("*.cpp"):
        if not src.name.endswith("_overrides.cpp"):
            copy_changed(src, runner / src.relative_to(gen))
    for src in (root / "runtime").glob("*_overrides.cpp"):
        copy_changed(src, runner / src.name)
    touch = False
    # Stage every maintained runtime header: names, rounds and the host badge renderer
    # have transitive includes that must also be present in fresh portable builds.
    for pattern in ("tekken4_net*.cpp", "tekken4_*.h"):
        for src in (root / "runtime").glob(pattern):
            touch = copy_changed(src, runner / src.name) or touch
    rollback = runner / "tekken4_rollback_overrides.cpp"
    if touch and rollback.is_file():
        rollback.touch()
    for name in ("ps2_recompiled_functions.h", "ps2_recompiled_stubs.h"):
        src = gen / name
        if src.is_file():
            copy_changed(src, runtime / "include" / name)


def simd_baseline(env):
    """Use SSE2 when Windows/Wine cannot confirm both newer instructions."""
    if env.get("TEKKEN4_SIMD_BASELINE") in ("0", "1"):
        return env["TEKKEN4_SIMD_BASELINE"] == "1"
    try:
        import ctypes
        feature = ctypes.WinDLL("kernel32", use_last_error=True).IsProcessorFeaturePresent
        feature.argtypes, feature.restype = [ctypes.c_uint], ctypes.c_int
        return not (feature(36) and feature(37))
    except (AttributeError, OSError):
        return True


def cmake_plan(root, tree, build_dir, runtime, portable, env):
    """Return argv lists, never shell strings; spaces and metacharacters stay literal."""
    cmake = str(root / "toolchain/cmake/bin/cmake.exe") if portable else "cmake"
    out = tree / "out" / (build_dir if runtime else "tools")
    configure = [cmake, "-S", str(tree), "-B", str(out), "-G", "Ninja"]
    if portable:
        configure.append("-DCMAKE_TOOLCHAIN_FILE=" + (root / "tools/t4_toolchain_clangcl.cmake").as_posix())
    if runtime:
        micro = root / "game/vu1/micro"
        native = any(micro.glob("*.bin")) and env.get("TEKKEN4_VU1N") != "0"
        micro0 = root / "game/vu0/micro"
        lift = env.get("TEKKEN4_VULIFT") != "0"
        # CMake PCH/unity sources embed absolute UTF-8 paths, including player folder names.
        configure += ["-DCMAKE_BUILD_TYPE=RelWithDebInfo",
                      "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=/Z7 /O2 /Ob2 /DNDEBUG /utf-8",
                      "-DCMAKE_C_FLAGS_RELWITHDEBINFO=/Z7 /O2 /Ob2 /DNDEBUG /utf-8",
                      "-DPS2X_BUILD_RECOMP=OFF", "-DPS2X_BUILD_ANALYZER=OFF",
                      "-DPS2X_BUILD_TEST=OFF", "-DPS2X_BUILD_STUDIO=OFF",
                      "-DPS2X_ENABLE_AGRESSIVE_LOGS=OFF", "-DPS2X_ENABLE_RUNTIME_LOGS=ON", "-DPS2X_ENABLE_IOP_RPC_TRACE=ON",
                      "-DPS2X_VU1_MICROCODE_DIR=" + (micro.as_posix() if native else ""),
                      "-DPS2X_VU1N_GEN=" + (root / "tools/vu1/vu1n_gen.py").as_posix(),
                      "-DPS2X_VULIFT_GEN=" + ((root / "tools/vu/vu_lift.py").as_posix() if lift else ""),
                      "-DPS2X_VU0_MICROCODE_DIR=" + (micro0.as_posix() if any(micro0.glob("*.bin")) else ""),
                      "-DPS2X_SIMD_BASELINE=" + ("ON" if simd_baseline(env) else "OFF")]
    else:
        # The analyzer is a maintainer tool and the only user of nlohmann_json (not vendored in the release).
        configure += ["-DCMAKE_BUILD_TYPE=Release", "-DPS2X_BUILD_RUNTIME=OFF", "-DPS2X_BUILD_TEST=OFF", "-DPS2X_BUILD_STUDIO=OFF",
                      "-DPS2X_BUILD_ANALYZER=OFF"]
    build = [cmake, "--build", str(out)]
    if runtime:
        build += ["--target", "ps2EntryRunner"]
    return [configure, build]


class Build:
    def __init__(self, args, root=ROOT):
        self.a, self.root = args, Path(root).resolve()
        self.steps = parse_steps(args.Steps)
        self.env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
        self.portable = (self.root / "toolchain/toolchain.json").is_file()
        if self.portable:
            self.env = release_environment(self.env)
        self.tree = build_tree(self.root, self.env)
        self.vendored = (self.tree / ".t4-vendored.json").is_file()
        self.build_dir = self.env.get("TEKKEN4_BUILD_DIR") or "runtime"
        self.recomp = self.tree / "out/tools/ps2xRecomp/ps2_recomp.exe"
        self.runner = self.tree / "out" / self.build_dir / "ps2xRuntime/ps2EntryRunner.exe"
        self.disc = self.root / "game/disc"
        self.iso = Path(args.Iso).resolve() if args.Iso else next(iter(sorted(self.root.glob("*.iso"))), None)
        self.log_dir = Path(args.LogDir or self.root / "logs").resolve()
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.log_path, self.state_path = self.log_dir / "build_game.log", self.log_dir / "build_game_state.json"
        self.state = read_json(self.state_path, {})
        if not isinstance(self.state, dict):
            self.state = {}
        self.log = self.log_path.open("a", encoding="utf-8", buffering=1)
        self.changed, self.last_lines, self.timings, self.iso_files = set(), [], [], {}
        self.iso_fp = ""
        self.compiler_ready = False

    def say(self, text):
        print(text, flush=True)
        self.log.write(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S ") + text + "\n")

    def record(self, step, **values):
        if self.a.WhatIf:
            return
        if not isinstance(self.state.get(step), dict):
            self.state[step] = {}
        self.state[step].update(values)
        self.state["updated"] = datetime.datetime.now().isoformat(timespec="seconds")
        write_json(self.state_path, self.state)

    def get(self, step, key):
        value = self.state.get(step)
        return value.get(key) if isinstance(value, dict) else None

    def run_command(self, argv, cwd=None, echo="", check=True):
        argv = list(map(str, argv))
        if not Path(argv[0]).is_absolute():
            argv[0] = shutil.which(argv[0], path=self.env.get("PATH")) or argv[0]
        self.last_lines = []
        self.log.write(f"> {subprocess.list2cmdline(argv)}   (cwd {cwd or self.root})\n")
        p = subprocess.Popen(argv, cwd=cwd or self.root, env=self.env, stdin=subprocess.DEVNULL,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace", creationflags=NO_WINDOW)
        try:
            for line in p.stdout:
                line = line.rstrip()
                if line:
                    self.log.write(line + "\n")
                    self.last_lines = (self.last_lines + [line])[-40:]
                    if echo and re.search(echo, line):
                        print("    " + line, flush=True)
            code = p.wait()
        except BaseException:
            p.terminate()
            p.wait()
            raise
        finally:
            p.stdout.close()
        self.log.write(f"< exit code {code}\n")
        if code and check:
            raise ValueError(next((line for line in self.last_lines if line.startswith("ERROR:")), f"{argv[0]} failed (exit {code})"))
        return code

    def python(self, script, *args, **kwargs):
        return self.run_command([sys.executable, "-I", "-X", "utf8", self.root / "tools" / script, *args], **kwargs)

    def head(self):
        marker = read_json(self.tree / ".t4-vendored.json", {})
        return str(marker.get("head", "vendored")) if self.vendored else git_output(self.tree, "rev-parse", "HEAD")

    def paths(self, folder, pattern="*", recurse=False):
        path = self.root / folder
        return list(path.rglob(pattern) if recurse else path.glob(pattern))

    def plan(self, step, text):
        self.say("    [WhatIf] would " + text)
        self.changed.add(step)
        return "would run"

    def compiler_environment(self):
        if self.compiler_ready:
            return
        tc = self.root / "toolchain"
        if self.portable:
            self.python("fetch_msvc_sysroot.py", "--check", "--root", self.root)
            directories = [self.root / "python", tc / "llvm/bin", tc / "cmake/bin", tc / "ninja"]
            self.env["PATH"] = os.pathsep.join(map(str, directories)) + os.pathsep + release_environment(self.env)["PATH"]
            includes = [tc / "msvc/include"] + [tc / "winsdk/include" / name for name in ("ucrt", "um", "shared")]
            if (tc / "winsdk/include/winrt").is_dir():
                includes.append(tc / "winsdk/include/winrt")
            self.env["INCLUDE"] = ";".join(map(str, includes))
            self.env["LIB"] = ";".join(map(str, [tc / "msvc/lib/x64", tc / "winsdk/lib/ucrt/x64", tc / "winsdk/lib/um/x64"]))
            self.env["CC"] = self.env["CXX"] = str(tc / "llvm/bin/clang-cl.exe")
        elif (self.root / "release.json").is_file():
            raise ValueError("This release folder is missing its bundled compiler (toolchain\\toolchain.json). "
                             "Unpack the whole release zip again or install Tekken 4 fresh from the launcher.")
        else:
            drive = Path(self.env.get("SYSTEMDRIVE", "C:") + os.sep)
            vswhere = Path(self.env.get("PROGRAMFILES(X86)", str(drive / "Program Files (x86)"))) / "Microsoft Visual Studio/Installer/vswhere.exe"
            result = subprocess.run([str(vswhere), "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"], capture_output=True, text=True, check=True, creationflags=NO_WINDOW)
            vs = result.stdout.strip()
            if not vs:
                raise ValueError("MSVC not found")
            vcvars = Path(vs) / "VC/Auxiliary/Build/vcvars64.bat"
            # Only developer builds need cmd.exe to import Visual Studio's environment.
            # The release/Wine path above invokes every bundled executable directly.
            for line in visual_studio_environment(vcvars).splitlines():
                key, sep, value = line.partition("=")
                if sep and key:
                    # Windows environment keys are case insensitive; Python dicts are not.
                    for old in list(self.env):
                        if old.upper() == key.upper():
                            self.env.pop(old)
                    self.env[key.upper()] = value
            extra = [Path(self.env.get("PROGRAMFILES", str(drive / "Program Files"))) / "CMake/bin",
                     Path(self.env.get("LOCALAPPDATA", "")) / "Microsoft/WinGet/Links",
                     Path(vs) / "Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin",
                     Path(vs) / "Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja"]
            self.env["PATH"] = os.pathsep.join(map(str, extra)) + os.pathsep + self.env.get("PATH", "")
        self.compiler_ready = True

    def prereq(self):
        self.say(f"    Python {sys.version_info.major}.{sys.version_info.minor}: {sys.executable}")
        if self.portable:
            tc = self.root / "toolchain"
            if self.a.AcceptMicrosoftLicense and not self.a.WhatIf:
                self.python("fetch_msvc_sysroot.py", "--accept-license", "--root", self.root)
            parts = [self.root / "python/python.exe"] + [tc / f"llvm/bin/{name}.exe" for name in ("clang-cl", "lld-link", "llvm-lib", "llvm-rc", "llvm-mt")] + [tc / "cmake/bin/cmake.exe", tc / "ninja/ninja.exe"]
            missing = [str(p) for p in parts if not p.is_file()]
            for p in parts:
                if p.is_file():
                    self.say(f"    {p.stem}: {p}")
            if not self.vendored:
                missing.append("deps\\ps2recomp is missing (the PS2Recomp source is part of the release zip)")
            if missing:
                self.say("Missing parts of the bundled toolchain:")
                for i, item in enumerate(missing, 1):
                    self.say(f"  {i}. {item}")
                raise ValueError(f"{len(missing)} part(s) of the bundled toolchain missing, see above")
            self.compiler_environment()
            return "ok (bundled)"
        if (self.root / "release.json").is_file():
            raise ValueError("This release folder is missing its bundled compiler (toolchain\\toolchain.json). "
                             "Unpack the whole release zip again or install Tekken 4 fresh from the launcher.")
        if not shutil.which("git"):
            raise ValueError("Git (clones PS2Recomp and builds fetch their libraries with it) is missing. Install Git and restart the launcher.")
        self.say(f"    Git: {shutil.which('git')}")
        self.compiler_environment()
        for name in ("cmake", "ninja"):
            found = shutil.which(name, path=self.env.get("PATH"))
            if not found:
                raise ValueError(f"Missing prerequisites: {name}. Install {name} and restart the launcher.")
            self.say(f"    {name}: {found}")
        return "ok"

    def check_iso(self):
        code = self.python("iso_extract.py", self.iso, "--check", check=False)
        if code:
            error = next((line for line in self.last_lines if line.startswith("ERROR:")), f"iso_extract.py exited with code {code}")
            if code in (2, 3):
                raise ValueError(f"{self.iso} is not a supported disc image.\n    {error}\n    Only Tekken 4 (USA), serial SLUS-20328, is supported.")
            raise ValueError(error)
        if f"ELF_SHA1 {EXPECTED_ELF}" not in self.last_lines:
            raise ValueError(f"ELF SHA-1 on the disc does not match {EXPECTED_ELF}")
        self.iso_files = {m[1]: int(m[2]) for line in self.last_lines if (m := re.fullmatch(r"FILE (\S+) (\d+)", line))}
        if len(self.iso_files) < 4:
            raise ValueError("the disc is missing files the port needs")

    def verify(self):
        if not self.a.Force and self.get("verify", "fingerprint") == self.iso_fp and self.get("verify", "elfSha1") == EXPECTED_ELF and self.get("verify", "files"):
            self.iso_files = self.get("verify", "files")
            return "up to date"
        self.check_iso()
        self.say(f"    BOOT2 = cdrom0:\\SLUS_203.28;1, ELF SHA-1 {EXPECTED_ELF} - ok")
        self.record("verify", fingerprint=self.iso_fp, iso=str(self.iso), elfSha1=EXPECTED_ELF, files=self.iso_files)
        return "checked" if self.a.WhatIf else "verified"

    def extract(self):
        if not self.iso_files:
            # An extract-only run must verify the *current* ISO, not reuse another disc's file table.
            self.check_iso()
        have = all((self.disc / p).is_file() and (self.disc / p).stat().st_size == n for p, n in self.iso_files.items())
        have = have and digest(self.disc / "SLUS_203.28") == EXPECTED_ELF
        recorded = self.get("extract", "fingerprint")
        if not self.a.Force and have and (not recorded or recorded == self.iso_fp):
            if not recorded:
                self.record("extract", fingerprint=self.iso_fp, adopted=True)
            if not self.a.WhatIf:
                write_game_files(self.disc, self.root / "game/t4-game-files.json")
            return "up to date"
        if self.a.WhatIf:
            return self.plan("extract", f"extract 4 files ({round(sum(self.iso_files.values()) / (1 << 20))} MB) into {self.disc}")
        files = sorted(self.iso_files, key=lambda name: name.endswith("DATA.BIN"))
        self.python("iso_extract.py", self.iso, self.disc, "--files", *files, echo=r"^\s+\S+ \d+%")
        if digest(self.disc / "SLUS_203.28") != EXPECTED_ELF:
            raise ValueError("extracted SLUS_203.28 has the wrong SHA-1")
        for name, size in self.iso_files.items():
            if not (self.disc / name).is_file() or (self.disc / name).stat().st_size != size:
                raise ValueError(f"{name} was not extracted completely")
        self.record("extract", fingerprint=self.iso_fp, adopted=False)
        write_game_files(self.disc, self.root / "game/t4-game-files.json")
        self.changed.add("extract")
        return "extracted"

    def fork(self):
        patches = sorted(self.paths("patches", "*.patch"))
        if self.vendored:
            if self.portable:
                marker = read_json(self.tree / ".t4-vendored.json", {})
                if marker.get("head") != PINNED:
                    raise ValueError("Wrong vendored PS2Recomp revision.")
                receipt = marker.get("patches", [])
                if not patches or len(receipt) != len(patches):
                    raise ValueError("Incomplete vendored patch receipt.")
                for patch in patches:
                    entries = [p for p in receipt if p.get("name") == patch.name]
                    if len(entries) != 1 or entries[0].get("sha256") != digest(patch, "sha256"):
                        raise ValueError(f"Vendored patch receipt does not match {patch.name}. Extract the release again.")
            return "vendored (no Git)" if self.portable else "vendored"
        if self.portable:
            raise ValueError("The release is missing its vendored PS2Recomp marker.")
        if not patches:
            raise ValueError("patches\\*.patch not found (incomplete checkout of this repo?)")
        exists = (self.tree / ".git").exists()
        in_progress = self.get("fork", "inProgress") and self.get("fork", "tree") == str(self.tree)
        if exists and not in_progress:
            self.say(f"    using the existing tree, HEAD {self.head()[:7]}")
            return "exists"
        url = self.env.get("TEKKEN4_FORK_URL") or "https://github.com/ran-j/PS2Recomp"
        if self.a.WhatIf:
            return self.plan("fork", f"clone {url} into {self.tree}, check out eb8688b as branch t4-us and apply {len(patches)} patches")
        self.record("fork", inProgress=True, tree=str(self.tree))
        if not exists:
            if self.tree.exists() and any(self.tree.iterdir()):
                raise ValueError(f"{self.tree} exists but is not a git clone and is not empty; move it away or set TEKKEN4_SRC to another folder")
            self.tree.parent.mkdir(parents=True, exist_ok=True)
            self.say(f"    cloning {url} (a few minutes)")
            self.run_command(["git", "-c", "core.autocrlf=false", "clone", url, self.tree])
            self.run_command(["git", "-C", self.tree, "config", "core.autocrlf", "false"])
        if git_output(self.tree, "branch", "--show-current") != "t4-us":
            self.run_command(["git", "-C", self.tree, "checkout", "-B", "t4-us", "eb8688b"])
        n = 0
        for patch in patches:
            base = ["git", "-C", self.tree, "-c", "core.autocrlf=false", "apply"]
            if self.run_command([*base, "--reverse", "--check", patch], check=False) == 0:
                continue
            mode = []
            if self.run_command([*base, "--check", patch], check=False):
                mode = ["--ignore-whitespace"]
                self.run_command([*base, "--check", *mode, patch])
            self.run_command([*base, *mode, patch])
            self.say(f"    applied {patch.name}" + ("  (--ignore-whitespace)" if mode else ""))
            n += 1
        self.record("fork", inProgress=False, tree=str(self.tree), head=self.head(), patches=len(patches))
        self.changed.add("fork")
        return f"cloned, {n} patches"

    def compile(self, runtime):
        if not (self.tree / "CMakeLists.txt").is_file():
            raise ValueError(f"{self.tree} is not a PS2Recomp tree")
        self.compiler_environment()
        if runtime and not self.vendored:
            patches = sorted(self.paths("patches", "*.patch"))
            if patches and self.run_command(["git", "-C", self.tree, "apply", "--reverse", "--check", patches[-1]], check=False):
                for patch in patches:
                    base = ["git", "-C", self.tree, "apply"]
                    if self.run_command([*base, "--reverse", "--check", patch], check=False) == 0:
                        continue
                    if self.run_command([*base, "--check", patch], check=False):
                        self.say(f"WARNING: {patch.name} is neither applied nor applicable: building the PS2Recomp tree as it is (local edits?)")
                    else:
                        self.run_command([*base, patch])
        if runtime and not self.paths("game/vu1/micro", "*.bin"):
            self.say("WARNING: no game\\vu1\\micro bin file - building the VU1 INTERPRETER only: the fight runs about 12 fps instead of 27. Restore the captured micro memory, see docs/status.md Native VU1 port.")
        for command in cmake_plan(self.root, self.tree, self.build_dir, runtime, self.portable, self.env):
            self.run_command(command)

    def tools(self):
        head, built = self.head(), self.get("tools", "head")
        if not needs_step("tools", self.a.Force, self.changed, self.recomp.is_file(), built or head, head):
            if not built:
                self.record("tools", head=head, adopted=True)
            return "up to date"
        if self.a.WhatIf:
            return self.plan("tools", "run tools\\build_ps2recomp_tools_portable.cmd" if self.portable else "run tools\\build_ps2recomp_tools.cmd")
        self.compile(False)
        if not self.recomp.is_file():
            raise ValueError(f"build finished but {self.recomp} is missing")
        self.record("tools", head=head, adopted=False)
        self.changed.add("tools")
        return "built"

    def recompile(self):
        cfg = [p for p in self.paths("config") if p.suffix in (".toml", ".csv")]
        fp = sha_text(f"{fingerprint(cfg, True)}|{EXPECTED_ELF}|{fingerprint([self.recomp])}")
        if not needs_step("recomp", self.a.Force, self.changed, (self.root / "generated/register_functions.cpp").is_file(), self.get("recomp", "fingerprint"), fp):
            return "up to date"
        if self.a.WhatIf:
            return self.plan("recomp", "run ps2_recomp.exe config\\ghidra_export.toml (writes generated\\)")
        self.run_command([self.recomp, "config/ghidra_export.toml"])
        if not (self.root / "generated/register_functions.cpp").is_file():
            raise ValueError("ps2_recomp finished but generated\\register_functions.cpp is missing")
        self.record("recomp", fingerprint=fp)
        self.changed.add("recomp")
        return "recompiled"

    def stage(self):
        gen = self.paths("generated", "*.cpp") + self.paths("generated", "*.h")
        fp = sha_text(f"{fingerprint(gen)}|{fingerprint(self.paths('runtime', '*.cpp', True))}|{fingerprint(self.paths('runtime', '*.h', True))}|{self.head()}")
        runner = self.tree / "ps2xRuntime/src/runner"
        have = all((runner / name).is_file() for name in ("register_functions.cpp", "tekken4_net.cpp"))
        if not needs_step("stage", self.a.Force, self.changed, have, self.get("stage", "fingerprint"), fp):
            return "up to date"
        if self.a.WhatIf:
            return self.plan("stage", "run tools\\stage_generated.cmd")
        stage_generated(self.root, self.tree)
        self.record("stage", fingerprint=fp)
        self.changed.add("stage")
        return "staged"

    def write_build_id(self):
        if self.python("t4_buildid.py", "--src", self.tree, "--out", self.runner.parent, check=False):
            self.say("    NOTE: the netplay build id could not be written: online matches will refuse this build.")

    def runtime(self):
        # The micro images are inputs of the fingerprint below: make them first, so a second Build with nothing
        # changed says "up to date" (0.1.3; they used to appear only after the fingerprint was taken).
        if not self.a.WhatIf and (not self.paths("game/vu1/micro", "*.bin") or not self.paths("game/vu0/micro", "*.bin")):
            if self.python("vu1_micro_from_elf.py", self.disc / "SLUS_203.28", self.root / "game/vu1/micro", self.root / "game/vu0/micro", check=False):
                self.say("    NOTE: the VU1 micro image could not be built: the runtime gets the VU1 interpreter only (about 12 fps in a fight).")
        # A resumed player build must also pick up changed compiler/CMake options.
        configuration = sha_text("\n".join(cmake_plan(self.root, self.tree, self.build_dir, True, self.portable, self.env)[0]))
        fp = sha_text(f"{self.get('stage', 'fingerprint') or ''}|{fingerprint(self.paths('patches', '*.patch'))}|{fingerprint(self.paths('game/vu1/micro', '*.bin'))}|{fingerprint(self.paths('game/vu0/micro', '*.bin'))}|{fingerprint(self.paths('tools/vu', '*.py'))}|{fingerprint(self.paths('runtime', '*.cpp', True))}|{self.head()}|{self.build_dir}|{self.env.get('TEKKEN4_VULIFT', '')}|{simd_baseline(self.env)}|{configuration}")
        if not needs_step("runtime", self.a.Force, self.changed, self.runner.is_file(), self.get("runtime", "fingerprint"), fp):
            if not self.a.WhatIf:
                self.write_build_id()
            return "up to date"
        if self.a.WhatIf:
            return self.plan("runtime", "run tools\\build_runtime_portable.cmd (cmake + ninja, 10-40 minutes the first time)" if self.portable else "run tools\\build_runtime.cmd (cmake + ninja, 10-40 minutes the first time)")
        self.say("    this is the long step (several hundred C++ files); progress is in the log")
        self.compile(True)
        if not self.runner.is_file():
            raise ValueError(f"build finished but {self.runner} is missing")
        self.write_build_id()
        self.record("runtime", fingerprint=fp, exe=str(self.runner))
        self.changed.add("runtime")
        return "built"

    def execute(self):
        started, step = time.monotonic(), "verify"
        try:
            self.say(f"=== build_game {datetime.datetime.now().isoformat(timespec='seconds')}  root={self.root}  steps={','.join(self.steps)}  force={self.a.Force}  whatif={self.a.WhatIf}")
            if {"verify", "extract"} & set(self.steps):
                if not self.iso:
                    raise ValueError(f"no ISO given and no *.iso in {self.root}. Usage: python -I tools/build_game.py -Iso \"./Tekken 4 (USA).iso\"")
                if not self.iso.is_file():
                    raise ValueError(f"ISO not found: {self.iso}")
                self.iso_fp = f"{str(self.iso).lower()}|{self.iso.stat().st_size}|{ticks(self.iso)}"
            for n, step in enumerate(self.steps, 1):
                title = TITLES.get(step) or (f"ISO is Tekken 4 US (SLUS-20328): {self.iso}" if step == "verify" else f"PS2Recomp tree at eb8688b + patches\\*.patch ({self.tree})" if step == "fork" else f"tools\\build_runtime{'_portable' if self.portable else ''}.cmd -> {self.runner}")
                self.say("")
                self.say(f"[{n}/{len(self.steps)}] {step} - {title}")
                self.last_lines = []
                timer = time.monotonic()
                result = (self.recompile if step == "recomp" else getattr(self, step))()
                elapsed = time.monotonic() - timer
                self.timings.append(f"{step:<8} {result:<12} {elapsed:.1f}s")
                self.say(f"    {result} ({elapsed:.1f}s)")
            self.say("\n--- timings ---")
            for timing in self.timings:
                self.say("  " + timing)
            self.say(f"  total    {time.monotonic() - started:.1f}s")
            self.say("")
            if self.a.WhatIf:
                self.say('Dry run only: the build log was written; steps marked "would run" were not run.')
            elif "runtime" in self.steps:
                self.say("Ready. In Command Prompt, start the game with:")
                if self.iso and self.iso.parent != self.root and not list(self.root.glob("*.iso")):
                    self.say(f'    set "TEKKEN4_ISO={self.iso}"')
                self.say(f'    "{self.root / "tools/run_game.cmd"}"')
                self.say("Close the game window to stop it; the console output goes to logs\\run.log.")
            self.log.write("=== build_game finished\n")
            return 0
        except (OSError, ValueError, subprocess.SubprocessError) as ex:
            self.say(f"\nFAILED at step '{step}': {ex}")
            if self.last_lines:
                self.say("--- last output ---")
                for line in self.last_lines:
                    print(line, flush=True)
                self.say("-------------------")
            self.say(f"Full log: {self.log_path}")
            return 1
        finally:
            self.log.close()


def main(argv=None, root=ROOT):
    configure_output()
    a = parser().parse_args(argv)
    try:
        parse_steps(a.Steps)
    except ValueError as ex:
        print(str(ex), flush=True)
        return 2
    try:
        return Build(a, root).execute()
    except (OSError, ValueError) as ex:
        print(str(ex), file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
