"""Logic of the Tekken 4 (US) easy launcher: paths, settings, tool checks, starting the game.

No GUI in here (t4_launcher.pyw is the window), so everything can be tested from a script.
Python 3.8+ standard library only. Written new for this project (see COPIED_FROM_T5DR.txt).
"""
import ctypes
import json
import os
import re
import subprocess
import sys
import threading
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                       # repo root, or the folder of the release zip
SETTINGS_PATH = os.path.join(HERE, "settings.json")
LOG_DIR = os.path.join(ROOT, "logs")
LAUNCHER_LOG_DIR = os.path.join(LOG_DIR, "launcher")
LAST_RUN_LOG = os.path.join(LAUNCHER_LOG_DIR, "last_run.log")
BUILD_LOG = os.path.join(LOG_DIR, "build_game.log")
BUILD_STATE = os.path.join(LOG_DIR, "build_game_state.json")
RUN_LOCK = os.path.join(LOG_DIR, "run.lock")
GAME_ELF = os.path.join(ROOT, "game", "disc", "SLUS_203.28")
DOCS_GRAPHICS = os.path.join(ROOT, "docs", "GRAPHICS.md")
NO_WINDOW = 0x08000000 if os.name == "nt" else 0

IS_RELEASE = os.path.isfile(os.path.join(ROOT, "release.json"))   # unpacked release zip (docs/RELEASE_PLAN_T4.md)
# Saves (memory cards) are written to the working directory of the game: the player's own folder.
SAVE_DIR = os.path.join(ROOT, "save") if IS_RELEASE else os.path.join(HERE, "save")

STEPS = [  # (script step name, short label shown in the Build tab)
    ("prereq", "Check the build tools"),
    ("verify", "Check your Tekken 4 ISO"),
    ("extract", "Unpack the game files from the ISO"),
    ("fork", "Get the PS2Recomp source"),
    ("tools", "Build the recompiler"),
    ("recomp", "Translate the game code"),
    ("stage", "Stage the translated code"),
    ("runtime", "Build the game (the long step)"),
]

# ------------------------------------------------------------------ settings
RESOLUTIONS = [  # key = TEKKEN4_INTERNAL_RES value (docs/GRAPHICS.md), label; the same steps as T5DR's launcher
    ("lowest", "Lowest (0.5x, weak graphics)", None),
    ("native", "Native (640x448)", None),
    ("1080p", "1080p", None),
    ("1440p", "1440p", None),
    ("4k", "4K", None),
    ("auto", "Auto (your screen's step, at most 1080p on integrated graphics)", None),
]
RES_LABEL = {k: l for k, l, _ in RESOLUTIONS}

DEFAULTS = {
    "iso": "",                 # path of the player's Tekken 4 (USA) image
    "resolution": "auto",      # TEKKEN4_INTERNAL_RES
    "fullscreen": False,       # needs a runtime that knows TEKKEN4_FULLSCREEN (checked in the exe)
    "sound": True,             # TEKKEN4_SOUND
    "debug_panel": False,      # PS2X_DEBUG_PANEL (F1 in the game)
    "aa": True,                # TEKKEN4_AA: on = fxaa (the runtime's default), off = off
    "progressive": True,       # TEKKEN4_PROGRESSIVE: the game's own 480p mode (no interlace lines)
    "runtime_exe": "",         # optional: use this ps2EntryRunner.exe instead of the one the build made
    "last_run": None,          # {"time":..., "seconds":..., "exit":..., "ok":bool, "log":path, "note":...}
    "last_build": None,        # {"time":..., "ok":bool, "dry_run":bool, "log":path}
}


def load_settings(path=None):
    path = path or SETTINGS_PATH
    s = dict(DEFAULTS)
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("settings.json is not an object")
        for k, v in data.items():
            if k in DEFAULTS and (DEFAULTS[k] is None or isinstance(v, type(DEFAULTS[k])) or v is None):
                s[k] = v
        if s["resolution"] not in RES_LABEL:
            s["resolution"] = DEFAULTS["resolution"]
    except FileNotFoundError:
        pass
    except (OSError, ValueError) as e:       # unreadable or damaged: keep it for the player, start fresh
        try:
            os.replace(path, path + ".bad")
        except OSError:
            pass
        s["_warning"] = "settings.json was damaged (%s); defaults are used, the old file is settings.json.bad" % e
    return s


def save_settings(s, path=None):
    path = path or SETTINGS_PATH
    data = {k: s.get(k, v) for k, v in DEFAULTS.items()}
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
    os.replace(tmp, path)


# ------------------------------------------------------------------ screen / resolution
def screen_height():
    try:
        return ctypes.windll.user32.GetSystemMetrics(1)      # primary screen height in pixels (DPI aware process)
    except Exception:
        return 1080


def internal_res(s):
    """TEKKEN4_INTERNAL_RES value; the runtime picks the scale (auto = the screen's step, see docs/GRAPHICS.md)."""
    return s["resolution"] if s.get("resolution") in RES_LABEL else "native"


# ------------------------------------------------------------------ finding things
def find_python():
    """Interpreter for the helper scripts: the release's own python\\, else the one running the launcher."""
    own = os.path.join(ROOT, "python", "python.exe")
    if os.path.isfile(own):
        return own
    exe = sys.executable
    if exe.lower().endswith("pythonw.exe"):
        alt = exe[:-len("pythonw.exe")] + "python.exe"
        if os.path.isfile(alt):
            return alt
    return exe


def read_json(path):
    try:
        with open(path, "r", encoding="utf-8-sig") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def ps2recomp_tree():
    """Same rule as tools\\build_game.ps1: TEKKEN4_SRC, else a vendored deps\\ps2recomp (release), else ..\\tekken4-fork-ps2recomp."""
    if os.environ.get("TEKKEN4_SRC"):
        return os.path.abspath(os.environ["TEKKEN4_SRC"])
    vendored = os.path.join(ROOT, "deps", "ps2recomp")
    if os.path.isdir(vendored):
        return vendored
    return os.path.abspath(os.path.join(ROOT, "..", "tekken4-fork-ps2recomp"))


def find_runtime(s=None):
    """Path of ps2EntryRunner.exe to start, with a short note where it came from; (None, why) when there is none."""
    env = os.environ.get("T4_LAUNCHER_RUNTIME")            # test hook
    cands = []
    if env:
        cands.append((env, "T4_LAUNCHER_RUNTIME"))
    if s and s.get("runtime_exe"):
        cands.append((s["runtime_exe"], "settings"))
    st = read_json(BUILD_STATE) or {}
    exe = (st.get("runtime") or {}).get("exe") if isinstance(st.get("runtime"), dict) else None
    if exe:
        cands.append((exe, "last build"))
    build_dir = os.environ.get("TEKKEN4_BUILD_DIR") or "runtime"
    cands.append((os.path.join(ps2recomp_tree(), "out", build_dir, "ps2xRuntime", "ps2EntryRunner.exe"), "build tree"))
    cands.append((os.path.join(ROOT, "bin", "ps2EntryRunner.exe"), "bin folder"))
    for path, why in cands:
        if path and os.path.isfile(path):
            return os.path.abspath(path), why
    return None, "the game is not built yet: use the Build game tab"


def find_isos():
    """*.iso files worth offering: the project root, Downloads, Desktop, Documents (top level only)."""
    home = os.path.expanduser("~")
    out = []
    for d in (ROOT, os.path.join(home, "Downloads"), os.path.join(home, "Desktop"), os.path.join(home, "Documents")):
        try:
            for n in sorted(os.listdir(d)):
                if n.lower().endswith(".iso") and os.path.isfile(os.path.join(d, n)):
                    out.append(os.path.join(d, n))
        except OSError:
            pass
    return out


def effective_iso(s):
    """The ISO the game will read: the chosen one, else an .iso in the project root (the runtime finds that one itself)."""
    iso = s.get("iso") or ""
    if iso and os.path.isfile(iso):
        return iso
    for p in find_isos():
        if os.path.dirname(p).lower() == ROOT.lower():
            return p
    return ""


def verify_iso(path):
    """(ok, message). Runs tools\\iso_extract.py --check, the same check the build's verify step does."""
    script = os.path.join(ROOT, "tools", "iso_extract.py")
    if not os.path.isfile(path):
        return False, "File not found: %s" % path
    if not os.path.isfile(script):
        return False, "tools\\iso_extract.py is missing from this folder"
    try:
        r = subprocess.run([find_python(), "-I", script, path, "--check"], capture_output=True, text=True,
                           timeout=300, creationflags=NO_WINDOW, encoding="utf-8", errors="replace")
    except (OSError, subprocess.SubprocessError) as e:
        return False, "Could not run the check: %s" % e
    out = (r.stdout or "") + (r.stderr or "")
    if r.returncode == 0:
        return True, "This is Tekken 4 (USA), SLUS-20328. Good."
    err = next((l for l in out.splitlines() if l.startswith("ERROR")), "").strip()
    if r.returncode in (2, 3):
        return False, "Not the supported disc. %s\nOnly Tekken 4 (USA), serial SLUS-20328, is supported." % err
    return False, err or ("The check failed (exit %d)." % r.returncode)


# ------------------------------------------------------------------ prerequisites (Build tab)
def _first_ok(cmds):
    for c in cmds:
        try:
            r = subprocess.run(c + ["--version"], capture_output=True, text=True, timeout=20, creationflags=NO_WINDOW)
            if r.returncode == 0:
                return (r.stdout or r.stderr).strip().splitlines()[0]
        except (OSError, subprocess.SubprocessError):
            pass
    return None


def _which(name):
    for d in os.environ.get("PATH", "").split(os.pathsep):
        p = os.path.join(d.strip('"'), name + ".exe")
        if os.path.isfile(p):
            return p
    return None


def bundled_toolchain():
    """True when this folder carries its own compiler (release zip: toolchain\\toolchain.json, docs/RELEASE_PLAN_T4.md)."""
    return os.path.isfile(os.path.join(ROOT, "toolchain", "toolchain.json"))


def check_prereqs():
    """List of dicts {id, name, ok, detail, fix}. Mirrors the prereq step of tools\\build_game.ps1."""
    items = []

    def add(id_, name, ok, detail, fix=""):
        items.append({"id": id_, "name": name, "ok": bool(ok), "detail": detail, "fix": "" if ok else fix})

    if bundled_toolchain():
        tc = os.path.join(ROOT, "toolchain")
        for id_, name, rel in (("python", "Python (bundled)", r"..\python\python.exe"),
                               ("clang", "clang-cl (bundled)", r"llvm\bin\clang-cl.exe"),
                               ("lld", "lld-link (bundled)", r"llvm\bin\lld-link.exe"),
                               ("cmake", "CMake (bundled)", r"cmake\bin\cmake.exe"),
                               ("ninja", "Ninja (bundled)", r"ninja\ninja.exe")):
            p = os.path.normpath(os.path.join(tc, rel))
            add(id_, name, os.path.isfile(p), p if os.path.isfile(p) else "missing: " + p,
                "Extract the whole release zip again (not from inside the zip viewer).")
        return items

    py = None
    for c in ([find_python()], ["py", "-3"], ["python"]):
        py = _first_ok([c])
        if py:
            break
    add("python", "Python 3", py, py or "not found",
        "winget install Python.Python.3.12   (or python.org; tick 'Add python.exe to PATH')")
    git = _which("git")
    add("git", "Git", git, git or "not found", "winget install Git.Git   (or https://git-scm.com/download/win)")
    vsw = os.path.join(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
                       "Microsoft Visual Studio", "Installer", "vswhere.exe")
    vs = None
    if os.path.isfile(vsw):
        try:
            r = subprocess.run([vsw, "-latest", "-products", "*", "-requires",
                                "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"],
                               capture_output=True, text=True, timeout=30, creationflags=NO_WINDOW)
            vs = (r.stdout or "").strip().splitlines()[0].strip() if r.returncode == 0 and (r.stdout or "").strip() else None
        except (OSError, subprocess.SubprocessError):
            vs = None
    add("msvc", "Visual Studio 2022 Build Tools (C++)", vs and os.path.isdir(vs), vs or "not found",
        "winget install Microsoft.VisualStudio.2022.BuildTools --override \"--passive --wait --add "
        "Microsoft.VisualStudio.Workload.VCTools --includeRecommended\"  (about 6 GB)")
    extra = [os.path.join(os.environ.get("ProgramFiles", ""), "CMake", "bin"),
             os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Links")]
    if vs:
        extra += [os.path.join(vs, "Common7", "IDE", "CommonExtensions", "Microsoft", "CMake", "CMake", "bin"),
                  os.path.join(vs, "Common7", "IDE", "CommonExtensions", "Microsoft", "CMake", "Ninja")]
    for name, label, fix in (("cmake", "CMake", "winget install Kitware.CMake"),
                             ("ninja", "Ninja", "winget install Ninja-build.Ninja")):
        found = _which(name)
        if not found:
            for d in extra:
                p = os.path.join(d, name + ".exe")
                if os.path.isfile(p):
                    found = p
                    break
        add(name, label, found, found or "not found", fix)
    return items


# ------------------------------------------------------------------ build script
def build_script():
    """The portable script when this folder has its own toolchain, else the normal one."""
    portable = os.path.join(ROOT, "tools", "build_game_portable.ps1")
    if bundled_toolchain() and os.path.isfile(portable):
        return portable
    return os.path.join(ROOT, "tools", "build_game.ps1")


def build_command(iso, dry_run=False):
    cmd = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", build_script()]
    if iso:
        cmd += ["-Iso", iso]
    if dry_run:
        cmd.append("-WhatIf")
    return cmd


RE_STEP = re.compile(r"^\[(\d+)/(\d+)\]\s+(\w+)\s+-\s+(.*)$")
RE_RESULT = re.compile(r"^\s{2,}(.+?)\s+\((\d+(?:\.\d+)?)s\)\s*$")
RE_NINJA = re.compile(r"^\[(\d+)/(\d+)\]\s")
RE_PERCENT = re.compile(r"\b(\d{1,3})%")


class LogTail(threading.Thread):
    """Follows logs\\build_game.log from a start offset and reports ninja's [done/total] counter."""

    def __init__(self, path, callback):
        super().__init__(daemon=True)
        self.path, self.callback = path, callback
        self.stop_flag = threading.Event()
        try:
            self.pos = os.path.getsize(path)
        except OSError:
            self.pos = 0

    def run(self):
        while not self.stop_flag.wait(0.7):
            try:
                with open(self.path, "rb") as f:
                    f.seek(self.pos)
                    data = f.read()
                    self.pos += len(data)
            except OSError:
                continue
            last = None
            for line in data.decode("utf-8", "replace").splitlines():
                m = RE_NINJA.match(line.strip())
                if m and int(m.group(2)) >= 5:
                    last = (int(m.group(1)), int(m.group(2)))
            if last:
                self.callback(*last)


def kill_tree(proc):
    try:
        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True, creationflags=NO_WINDOW,
                       timeout=30)
    except (OSError, subprocess.SubprocessError):
        try:
            proc.kill()
        except OSError:
            pass


# ------------------------------------------------------------------ the game
def pid_alive(pid):
    try:
        h = ctypes.windll.kernel32.OpenProcess(0x1000, False, int(pid))     # PROCESS_QUERY_LIMITED_INFORMATION
        if not h:
            return False
        code = ctypes.c_ulong()
        ok = ctypes.windll.kernel32.GetExitCodeProcess(h, ctypes.byref(code))
        ctypes.windll.kernel32.CloseHandle(h)
        return bool(ok) and code.value == 259                                # STILL_ACTIVE
    except Exception:
        return False


def run_lock_holder():
    """Text of logs\\run.lock when a live process holds it (dev checkouts share the PC between test runs), else ''."""
    try:
        with open(RUN_LOCK, "r", encoding="utf-8", errors="replace") as f:
            first = (f.readline() or "").strip()
    except OSError:
        return ""
    head = first.split(" ")[0]
    if head == os.environ.get("T4_RUN_LOCK_HELD_BY"):      # test hook: a wrapper script holds the lock for this launcher
        return ""
    if head.isdigit() and pid_alive(int(head)):
        return first
    return ""


def take_run_lock(what="launcher-play"):
    """Only where a dev checkout has tools\\run_lock.ps1. Released = emptied, never deleted (project rule)."""
    if not os.path.isfile(os.path.join(ROOT, "tools", "run_lock.ps1")):
        return False
    os.makedirs(LOG_DIR, exist_ok=True)
    with open(RUN_LOCK, "w", encoding="ascii") as f:
        f.write("%d %s\n" % (os.getpid(), what))
    return True


def release_run_lock():
    try:
        with open(RUN_LOCK, "r", encoding="utf-8", errors="replace") as f:
            first = (f.readline() or "").strip()
        if first.split(" ")[0] == str(os.getpid()):
            with open(RUN_LOCK, "w", encoding="ascii") as f:
                f.write("")
    except OSError:
        pass


_feature_cache = {}


def exe_knows(exe, name):
    """True when the runtime executable contains the environment variable name (so it will honour it)."""
    try:
        st = os.stat(exe)
    except OSError:
        return False
    key = (exe, st.st_size, st.st_mtime_ns, name)
    if key in _feature_cache:
        return _feature_cache[key]
    needle = name.encode("ascii")
    found, tail = False, b""
    try:
        with open(exe, "rb") as f:
            while True:
                chunk = f.read(8 << 20)
                if not chunk:
                    break
                if needle in tail + chunk:
                    found = True
                    break
                tail = chunk[-len(needle):]
    except OSError:
        pass
    _feature_cache[key] = found
    return found


def graphics_env_names():
    """Names of the anti-aliasing / progressive / fullscreen switches. Read from docs\\GRAPHICS.md when another agent
    has written it (first TEKKEN4_* token that contains AA / PROGRESSIVE / FULLSCREEN); else the agreed defaults."""
    names = {"aa": "TEKKEN4_AA", "progressive": "TEKKEN4_PROGRESSIVE", "fullscreen": "TEKKEN4_FULLSCREEN"}
    try:
        with open(DOCS_GRAPHICS, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        for key, pat in (("aa", r"TEKKEN4_AA[A-Z0-9_]*|TEKKEN4_[A-Z0-9_]*ANTIALIAS[A-Z0-9_]*"),
                         ("progressive", r"TEKKEN4_[A-Z0-9_]*PROGRESSIVE[A-Z0-9_]*"),
                         ("fullscreen", r"TEKKEN4_[A-Z0-9_]*FULLSCREEN[A-Z0-9_]*")):
            m = re.search(pat, text)
            if m:
                names[key] = m.group(0)
    except OSError:
        pass
    return names


def graphics_support(exe):
    """{'aa': bool, 'progressive': bool, 'fullscreen': bool}: which switches this runtime build knows."""
    names = graphics_env_names()
    return {k: bool(exe) and exe_knows(exe, v) for k, v in names.items()}


def game_env(s, exe=None):
    """Environment of the game process. Same switches as dist\\...\\Tekken4.cmd, plus the graphics options."""
    env = dict(os.environ)
    env["PS2X_GS_BACKEND"] = "gl"
    env["PS2X_GS_THREADS"] = "auto"
    env["PS2X_DEBUG_PANEL"] = "1" if s.get("debug_panel") else "0"
    env["TEKKEN4_SOUND"] = "1" if s.get("sound") else "0"
    env["TEKKEN4_INTERNAL_RES"] = internal_res(s)
    env.pop("PS2X_GS_HW_SCALE", None)    # the raw override would win over the step
    iso = effective_iso(s)
    if iso:
        env["TEKKEN4_ISO"] = iso
    env["TEKKEN4_WINDOW_TITLE"] = "TEKKEN 4"
    names, sup = graphics_env_names(), graphics_support(exe)
    if sup["fullscreen"] and s.get("fullscreen"):
        env[names["fullscreen"]] = "1"
    if sup["aa"]:
        env[names["aa"]] = "fxaa" if s.get("aa") else "off"
    if sup["progressive"]:
        env[names["progressive"]] = "1" if s.get("progressive") else "0"
    return env


def play_problems(s):
    """List of sentences that stop Play (empty = ready), the first one is the main reason."""
    out = []
    exe, why = find_runtime(s)
    if not exe:
        out.append("The game is not built yet. Open the 'Build game' tab and press BUILD GAME.")
    if not os.path.isfile(GAME_ELF):
        out.append("game\\disc\\SLUS_203.28 is missing: the build unpacks it from your ISO (Build game tab).")
    iso = effective_iso(s)
    if not iso:
        iso = s.get("iso") or ""
        out.append("Your Tekken 4 ISO is needed for the game's data and sound: choose it in the 'Build game' tab"
                   + (" (saved path not found: %s)." % iso if iso else "."))
    return out


def tail_lines(path, n=25):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 64 * 1024))
            data = f.read().decode("utf-8", "replace")
        return [l.rstrip() for l in data.splitlines() if l.strip()][-n:]
    except OSError:
        return []


class GameRun:
    """One start of the game: process, log file, exit handling. wait() runs in a thread of the caller."""

    def __init__(self, s):
        self.s = s
        self.proc = None
        self.started = 0.0
        self.stopped_by_user = False
        self.exe, self.exe_why = find_runtime(s)

    def start(self):
        os.makedirs(SAVE_DIR, exist_ok=True)
        os.makedirs(LAUNCHER_LOG_DIR, exist_ok=True)
        env = game_env(self.s, self.exe)
        self.log = open(LAST_RUN_LOG, "wb")
        head = ("T4 launcher start %s\nexe: %s (%s)\ncwd: %s\nargs: %s\nres %s sound %s debug %s iso %s\n----\n"
                % (time.strftime("%Y-%m-%d %H:%M:%S"), self.exe, self.exe_why, SAVE_DIR, GAME_ELF,
                   env["TEKKEN4_INTERNAL_RES"], env["TEKKEN4_SOUND"], env["PS2X_DEBUG_PANEL"],
                   env.get("TEKKEN4_ISO", "-")))
        self.log.write(head.encode("utf-8", "replace"))
        self.log.flush()
        self.started = time.time()
        self.proc = subprocess.Popen([self.exe, GAME_ELF], cwd=SAVE_DIR, env=env, stdout=self.log,
                                     stderr=subprocess.STDOUT, creationflags=NO_WINDOW)

    def stop(self):
        self.stopped_by_user = True
        if self.proc and self.proc.poll() is None:
            kill_tree(self.proc)

    def wait(self):
        """Blocks until the game ends; returns the record stored in settings['last_run']."""
        code = self.proc.wait()
        secs = time.time() - self.started
        try:
            self.log.close()
        except OSError:
            pass
        code32 = code & 0xFFFFFFFF
        crashed = (not self.stopped_by_user) and code32 != 0
        if self.stopped_by_user:
            note = "stopped from the launcher"
        elif code32 == 0:
            note = "closed normally"
        else:
            note = "ended with error code 0x%08X" % code32
        return {"time": time.strftime("%Y-%m-%d %H:%M:%S"), "seconds": round(secs, 1), "exit": code32,
                "ok": not crashed, "log": LAST_RUN_LOG, "note": note}


# ------------------------------------------------------------------ window screenshot (PrintWindow -> PNG)
def capture_window(hwnd, path):
    """Saves the window (also when covered) as PNG with PrintWindow(PW_RENDERFULLCONTENT). Returns (w, h)."""
    user32, gdi32 = ctypes.windll.user32, ctypes.windll.gdi32

    class RECT(ctypes.Structure):
        _fields_ = [("l", ctypes.c_long), ("t", ctypes.c_long), ("r", ctypes.c_long), ("b", ctypes.c_long)]

    class BIH(ctypes.Structure):
        _fields_ = [("biSize", ctypes.c_uint32), ("biWidth", ctypes.c_int32), ("biHeight", ctypes.c_int32),
                    ("biPlanes", ctypes.c_uint16), ("biBitCount", ctypes.c_uint16), ("biCompression", ctypes.c_uint32),
                    ("biSizeImage", ctypes.c_uint32), ("biXPelsPerMeter", ctypes.c_int32),
                    ("biYPelsPerMeter", ctypes.c_int32), ("biClrUsed", ctypes.c_uint32),
                    ("biClrImportant", ctypes.c_uint32)]

    rc = RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rc))
    w, h = rc.r - rc.l, rc.b - rc.t
    hdc = user32.GetWindowDC(hwnd)
    mdc = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mdc, bmp)
    user32.PrintWindow(hwnd, mdc, 2)
    bih = BIH(ctypes.sizeof(BIH), w, -h, 1, 32, 0, 0, 0, 0, 0, 0)
    buf = ctypes.create_string_buffer(w * h * 4)
    gdi32.GetDIBits(mdc, bmp, 0, h, buf, ctypes.byref(bih), 0)
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mdc)
    user32.ReleaseDC(hwnd, hdc)
    raw = bytearray()
    row = w * 4
    data = buf.raw
    for y in range(h):
        raw.append(0)
        line = data[y * row:(y + 1) * row]
        rgb = bytearray(w * 3)               # BGRA -> RGB
        rgb[0::3], rgb[1::3], rgb[2::3] = line[2::4], line[1::4], line[0::4]
        raw += rgb

    def chunk(tag, body):
        c = tag + body
        return len(body).to_bytes(4, "big") + c + (zlib.crc32(c) & 0xFFFFFFFF).to_bytes(4, "big")

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", w.to_bytes(4, "big") + h.to_bytes(4, "big") + b"\x08\x02\x00\x00\x00")
           + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    return w, h
