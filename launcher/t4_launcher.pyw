"""Tekken 4 (US, SLUS-20328) native port - easy launcher.

    pythonw launcher\\t4_launcher.pyw
    python  launcher\\t4_launcher.pyw --screenshot PNG [--tab N]    (save a picture of the window, then exit)
    python  launcher\\t4_launcher.pyw --selftest                    (no window: settings, paths, env switches)

Tabs: Play offline, Build game (from your own ISO, no BIOS), Settings, Controls, Online (not yet).
Python 3 standard library only (tkinter). Logic is in t4core.py.
"""
import argparse
import ctypes
import os
import queue
import subprocess
import sys
import threading
import time
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from tkinter.scrolledtext import ScrolledText

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ["PYTHONUTF8"] = "1"
import t4core as core  # noqa: E402

TITLE = "TEKKEN 4 (US) - Easy Launcher"
COL = {"ok": "#1a7f37", "warn": "#9a6700", "bad": "#cf222e", "muted": "#57606a", "accent": "#b3261e",
       "accent_hover": "#8f1d17", "log_bg": "#0d1117", "log_fg": "#c9d1d9"}
GLYPH = {"pending": "○", "running": "◔", "done": "✔", "skip": "✔", "failed": "✖",
         "plan": "▷"}

# Keyboard / gamepad table: from dist\T4-Offline-Test-*\LIESMICH.txt and patch 29 (ps2xRuntime-keyboard-layout) and
# the gamepad code in ps2xRuntime/src/lib/ps2_pad.cpp (raylib's standard layout: an Xbox pad is the reference).
CONTROLS = [
    ("Move / menus (D-pad)", "W A S D", "D-pad or left stick"),
    ("Left punch (Square)", "Left arrow  (or Z)", "X"),
    ("Right punch (Triangle)", "Up arrow  (or V)", "Y"),
    ("Left kick (Cross)", "Down arrow  (or X)", "A"),
    ("Right kick (Circle)", "Right arrow  (or C)", "B"),
    ("L1 / R1", "Q / E", "LB / RB"),
    ("L2 / R2", "Left Shift / Right Shift", "LT / RT"),
    ("Start", "Enter", "Menu"),
    ("Select", "Tab", "View"),
    ("L3 / R3 (stick click)", "Left Ctrl / Right Ctrl", "Stick clicks"),
    ("Debug panel on/off", "F1", "-"),
    ("Fullscreen", "Alt+Enter or F11 (may work)", "-"),
    ("Quit the game", "Close the window (Esc does NOT quit)", "-"),
]
CONTROLS_NOTE = ("The keyboard always works, also while a gamepad is plugged in. One gamepad is player 1. "
                 "VS Battle needs a second controller. Changing the keys comes in a later version.")


def enable_dpi_awareness():
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        try:
            ctypes.windll.user32.SetProcessDPIAware()
        except Exception:
            pass


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(TITLE)
        self.geometry("940x780")
        self.minsize(820, 620)
        self.settings = core.load_settings()
        self.q = queue.Queue()
        self.game = None              # core.GameRun while the game runs
        self.build_proc = None
        self.build_busy = False
        self.step_state = {}
        self.step_rows = {}
        self.cur_step = None
        self.step_frac = 0.0
        self.build_started = 0.0
        self.build_dry = False
        self.build_failed = False
        self.build_total_steps = len(core.STEPS)
        self.tail = None
        self.style = ttk.Style(self)
        if "vista" in self.style.theme_names():
            self.style.theme_use("vista")
        self.style.configure("TNotebook.Tab", padding=(14, 6))
        self.style.configure("Head.TLabel", font=("Segoe UI", 16, "bold"))
        self.style.configure("Muted.TLabel", foreground=COL["muted"])

        head = ttk.Frame(self, padding=(16, 10, 16, 0))
        head.pack(fill="x")
        ttk.Label(head, text="TEKKEN 4", style="Head.TLabel").pack(side="left")
        ttk.Label(head, text="   native PC port of the US version (SLUS-20328)  -  bring your own ISO, no BIOS needed",
                  style="Muted.TLabel").pack(side="left")
        self.nb = ttk.Notebook(self)
        self.nb.pack(fill="both", expand=True, padx=12, pady=10)
        self.tab_play = ttk.Frame(self.nb, padding=16)
        self.tab_build = ttk.Frame(self.nb, padding=12)
        self.tab_set = ttk.Frame(self.nb, padding=16)
        self.tab_ctl = ttk.Frame(self.nb, padding=16)
        self.tab_online = ttk.Frame(self.nb, padding=16)
        for f, t in ((self.tab_play, "  Play offline  "), (self.tab_build, "  Build game  "), (self.tab_set, "  Settings  "),
                     (self.tab_ctl, "  Controls  "), (self.tab_online, "  Online (soon)  ")):
            self.nb.add(f, text=t)
        self._build_play()
        self._build_build()
        self._build_settings()
        self._build_controls()
        self._build_online()
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        warn = self.settings.pop("_warning", None)
        if warn:
            self.after(300, lambda: messagebox.showwarning(TITLE, warn))
        self.refresh_play()
        self.after(100, self.pump)
        # first start: no game yet -> show the Build tab
        if core.play_problems(self.settings) and not self.settings.get("last_build"):
            self.nb.select(self.tab_build)
        threading.Thread(target=self._auto_iso, daemon=True).start()
        threading.Thread(target=self._prereq_check, daemon=True).start()

    # ------------------------------------------------------------ helpers
    def post(self, kind, *a):
        self.q.put((kind, a))

    def save(self):
        try:
            core.save_settings(self.settings)
        except OSError as e:
            messagebox.showerror(TITLE, "Could not save settings.json:\n%s" % e)

    def pump(self):
        try:
            while True:
                kind, a = self.q.get_nowait()
                getattr(self, "ev_" + kind)(*a)
        except queue.Empty:
            pass
        self.after(100, self.pump)

    # ============================================================ Play tab
    def _build_play(self):
        f = self.tab_play
        ttk.Label(f, text="Play offline", font=("Segoe UI", 14, "bold")).pack(anchor="w")
        ttk.Label(f, text="Fight on this PC against the computer (or a friend with a second controller).",
                  style="Muted.TLabel").pack(anchor="w", pady=(0, 18))
        self.btn_play = tk.Button(f, text="PLAY", font=("Segoe UI", 28, "bold"), bg=COL["accent"], fg="white",
                                  activebackground=COL["accent_hover"], activeforeground="white", relief="flat",
                                  cursor="hand2", command=self.on_play, height=2)
        self.btn_play.pack(fill="x", pady=(0, 6))
        self.lbl_ready = ttk.Label(f, text="", wraplength=820, justify="left")
        self.lbl_ready.pack(anchor="w", pady=(4, 2))
        self.lbl_summary = ttk.Label(f, text="", style="Muted.TLabel")
        self.lbl_summary.pack(anchor="w")
        row = ttk.Frame(f)
        row.pack(anchor="w", pady=10)
        self.btn_stop = ttk.Button(row, text="Stop game", command=self.on_stop)
        self.btn_log = ttk.Button(row, text="Open last log", command=lambda: self.open_path(core.LAST_RUN_LOG))
        self.btn_save = ttk.Button(row, text="Open save folder", command=lambda: self.open_path(core.SAVE_DIR, True))
        self.btn_set = ttk.Button(row, text="Settings...", command=lambda: self.nb.select(self.tab_set))
        for b in (self.btn_set, self.btn_log, self.btn_save):
            b.pack(side="left", padx=(0, 8))
        ttk.Separator(f).pack(fill="x", pady=8)
        ttk.Label(f, text="Last run", font=("Segoe UI", 10, "bold")).pack(anchor="w")
        self.lbl_last = ttk.Label(f, text="", wraplength=820, justify="left")
        self.lbl_last.pack(anchor="w", pady=(2, 4))
        self.txt_crash = tk.Text(f, height=9, wrap="none", bg=COL["log_bg"], fg=COL["log_fg"], font=("Consolas", 9),
                                 relief="flat")
        # (shown only after a crash: the end of the game's log)

    def refresh_play(self):
        s = self.settings
        problems = core.play_problems(s)
        running = self.game is not None
        ok = not problems and not running and not self.build_busy
        self.btn_play.config(state="normal" if ok else "disabled",
                             text="RUNNING..." if running else "PLAY",
                             bg=COL["accent"] if ok else "#9a9a9a")
        if running:
            self.btn_stop.pack(side="left", padx=(0, 8), before=self.btn_set)
            self.lbl_ready.config(text="The game is running in its own window. Close that window to quit.",
                                  foreground=COL["muted"])
        else:
            self.btn_stop.pack_forget()
            if problems:
                self.lbl_ready.config(text="\n".join(problems), foreground=COL["bad"])
            elif self.build_busy:
                self.lbl_ready.config(text="A build is running (Build game tab).", foreground=COL["warn"])
            else:
                exe, why = core.find_runtime(s)
                self.lbl_ready.config(text="Ready. Game build: %s (%s)" % (exe, why), foreground=COL["ok"])
        sup = core.graphics_support(core.find_runtime(s)[0])
        extra = []
        if sup["fullscreen"] and s["fullscreen"]:
            extra.append("fullscreen")
        self.lbl_summary.config(text="Resolution: %s   |   Sound: %s   |   Debug panel: %s%s"
                                % (core.RES_LABEL[s["resolution"]], "on" if s["sound"] else "off",
                                   "on" if s["debug_panel"] else "off", ("   |   " + ", ".join(extra)) if extra else ""))
        lr = s.get("last_run")
        if lr:
            self.lbl_last.config(text="%s - ran %s, %s (exit code %d)\nLog: %s"
                                 % (lr.get("time", "?"), self.fmt_secs(lr.get("seconds", 0)), lr.get("note", ""),
                                    lr.get("exit", 0), lr.get("log", core.LAST_RUN_LOG)),
                                 foreground=COL["ok"] if lr.get("ok") else COL["bad"])
        else:
            self.lbl_last.config(text="The game has not been started from this launcher yet.", foreground=COL["muted"])
        if not (lr and not lr.get("ok")):
            self.txt_crash.pack_forget()

    @staticmethod
    def fmt_secs(x):
        x = int(x)
        return "%d:%02d" % (x // 60, x % 60) if x < 3600 else "%d:%02d:%02d" % (x // 3600, x % 3600 // 60, x % 60)

    def open_path(self, path, folder=False):
        try:
            if folder:
                os.makedirs(path, exist_ok=True)
            if not os.path.exists(path):
                messagebox.showinfo(TITLE, "Nothing there yet:\n%s" % path)
                return
            os.startfile(path)
        except OSError as e:
            messagebox.showerror(TITLE, str(e))

    def on_play(self):
        s = self.settings
        problems = core.play_problems(s)
        if problems or self.game:
            self.refresh_play()
            return
        holder = core.run_lock_holder()
        if holder:
            messagebox.showwarning(TITLE, "Another game run holds logs\\run.lock (%s).\nClose it first, then press PLAY."
                                   % holder)
            return
        run = core.GameRun(s)
        try:
            run.start()
        except OSError as e:
            messagebox.showerror(TITLE, "The game could not be started:\n%s\n\nProgram: %s" % (e, run.exe))
            return
        core.take_run_lock()
        self.game = run
        self.refresh_play()
        threading.Thread(target=lambda: self.post("game_done", run.wait()), daemon=True).start()

    def on_stop(self):
        if self.game:
            self.game.stop()

    def ev_game_done(self, rec):
        core.release_run_lock()
        self.game = None
        self.settings["last_run"] = rec
        self.save()
        self.refresh_play()
        if not rec["ok"]:
            self.show_crash(rec)

    def show_crash(self, rec):
        lines = core.tail_lines(rec["log"], 14)
        self.txt_crash.config(state="normal")
        self.txt_crash.delete("1.0", "end")
        self.txt_crash.insert("end", "\n".join(lines) if lines else "(the log is empty)")
        self.txt_crash.config(state="disabled")
        self.txt_crash.pack(fill="both", expand=True, pady=(4, 0))
        self.nb.select(self.tab_play)
        messagebox.showerror(TITLE, "The game stopped unexpectedly (%s) after %s.\n\nThe log is here:\n%s\n\n"
                             "Please send this file when you report the problem."
                             % (rec["note"], self.fmt_secs(rec["seconds"]), rec["log"]))

    # ============================================================ Build tab
    def _build_build(self):
        f = self.tab_build
        top = ttk.Frame(f)
        top.pack(fill="x")
        ttk.Label(top, text="1. Your Tekken 4 disc image (USA, SLUS-20328) - the game is built from it on this PC; "
                  "nothing is downloaded from the game.", wraplength=840, justify="left").pack(anchor="w")
        r = ttk.Frame(top)
        r.pack(fill="x", pady=4)
        self.var_iso = tk.StringVar(value=self.settings.get("iso", ""))
        self.ent_iso = ttk.Entry(r, textvariable=self.var_iso)
        self.ent_iso.pack(side="left", fill="x", expand=True)
        ttk.Button(r, text="Browse...", command=self.on_browse).pack(side="left", padx=(6, 0))
        self.btn_verify = ttk.Button(r, text="Check ISO", command=self.on_verify)
        self.btn_verify.pack(side="left", padx=(6, 0))
        self.lbl_iso = ttk.Label(top, text="", wraplength=840, justify="left")
        self.lbl_iso.pack(anchor="w")
        ttk.Label(top, text="2. Tools needed on this PC", wraplength=840).pack(anchor="w", pady=(8, 0))
        self.frm_pre = ttk.Frame(top)
        self.frm_pre.pack(fill="x", padx=14)
        self.lbl_pre = ttk.Label(self.frm_pre, text="checking...", style="Muted.TLabel")
        self.lbl_pre.pack(anchor="w")
        mid = ttk.Frame(f)
        mid.pack(fill="x", pady=(8, 2))
        ttk.Label(mid, text="3. Build").pack(side="left")
        self.btn_build = tk.Button(mid, text="BUILD GAME", font=("Segoe UI", 12, "bold"), bg=COL["accent"], fg="white",
                                   activebackground=COL["accent_hover"], activeforeground="white", relief="flat",
                                   padx=18, pady=4, cursor="hand2", command=lambda: self.on_build(False))
        self.btn_build.pack(side="left", padx=12)
        self.btn_dry = ttk.Button(mid, text="Dry run (change nothing)", command=lambda: self.on_build(True))
        self.btn_dry.pack(side="left")
        self.btn_cancel = ttk.Button(mid, text="Cancel", command=self.on_cancel, state="disabled")
        self.btn_cancel.pack(side="left", padx=8)
        self.lbl_build = ttk.Label(f, text="", style="Muted.TLabel", wraplength=880, justify="left")
        self.lbl_build.pack(anchor="w")
        body = ttk.Frame(f)
        body.pack(fill="both", expand=True)
        steps = ttk.Frame(body)
        steps.pack(side="left", fill="y", padx=(0, 10))
        for i, (name, label) in enumerate(core.STEPS):
            g = tk.Label(steps, text=GLYPH["pending"], width=2, fg=COL["muted"], font=("Segoe UI", 11))
            t = ttk.Label(steps, text="%d. %s" % (i + 1, label))
            m = ttk.Label(steps, text="", style="Muted.TLabel")
            g.grid(row=i, column=0, sticky="w")
            t.grid(row=i, column=1, sticky="w")
            m.grid(row=i, column=2, sticky="w", padx=(8, 0))
            self.step_rows[name] = (g, t, m)
            self.step_state[name] = "pending"
        self.bar = ttk.Progressbar(steps, mode="determinate", maximum=1000, length=300)
        self.bar.grid(row=len(core.STEPS), column=0, columnspan=3, sticky="we", pady=(10, 0))
        self.lbl_prog = ttk.Label(steps, text="", style="Muted.TLabel")
        self.lbl_prog.grid(row=len(core.STEPS) + 1, column=0, columnspan=3, sticky="w")
        self.log = ScrolledText(body, height=10, wrap="none", bg=COL["log_bg"], fg=COL["log_fg"],
                                font=("Consolas", 9), relief="flat", state="disabled")
        self.log.pack(side="left", fill="both", expand=True)
        self.log.tag_config("err", foreground="#ff7b72")
        self.log.tag_config("step", foreground="#79c0ff")
        self.log.tag_config("ok", foreground="#7ee787")

    def _auto_iso(self):
        if self.settings.get("iso") and os.path.isfile(self.settings["iso"]):
            self.post("iso_found", self.settings["iso"], False)
            return
        found = core.find_isos()
        if found:
            self.post("iso_found", found[0], True)

    def ev_iso_found(self, path, fresh):
        if fresh:
            self.var_iso.set(path)
            self.lbl_iso.config(text="Found an ISO here: %s - press 'Check ISO' to make sure it is the right one."
                                % path, foreground=COL["muted"])
        elif not self.lbl_iso.cget("text"):
            self.lbl_iso.config(text="", foreground=COL["muted"])

    def on_browse(self):
        p = filedialog.askopenfilename(title="Choose your Tekken 4 (USA) ISO",
                                       filetypes=[("Disc image", "*.iso"), ("All files", "*.*")])
        if p:
            self.var_iso.set(os.path.normpath(p))
            self.on_verify()

    def on_verify(self):
        path = self.var_iso.get().strip().strip('"')
        if not path:
            self.lbl_iso.config(text="Choose your ISO first.", foreground=COL["bad"])
            return
        self.lbl_iso.config(text="Checking the disc image...", foreground=COL["muted"])
        self.btn_verify.config(state="disabled")

        def work():
            ok, msg = core.verify_iso(path)
            self.post("verified", path, ok, msg)
        threading.Thread(target=work, daemon=True).start()

    def ev_verified(self, path, ok, msg):
        self.btn_verify.config(state="normal")
        self.lbl_iso.config(text=msg, foreground=COL["ok"] if ok else COL["bad"])
        if ok:
            self.settings["iso"] = path
            self.save()
            self.refresh_play()

    def _prereq_check(self):
        self.post("prereqs", core.check_prereqs())

    def ev_prereqs(self, items):
        for w in self.frm_pre.winfo_children():
            w.destroy()
        self.prereq_ok = all(i["ok"] for i in items)
        for it in items:
            row = ttk.Frame(self.frm_pre)
            row.pack(fill="x", anchor="w")
            tk.Label(row, text=GLYPH["done"] if it["ok"] else GLYPH["failed"], fg=COL["ok"] if it["ok"] else COL["bad"],
                     width=2).pack(side="left")
            det = it["detail"] if len(it["detail"]) <= 72 else "..." + it["detail"][-69:]
            ttk.Label(row, text="%s  -  %s" % (it["name"], det), wraplength=800,
                      foreground=COL["muted"] if it["ok"] else COL["bad"]).pack(side="left")
            if not it["ok"] and it["fix"]:
                ttk.Label(self.frm_pre, text="      How to get it: " + it["fix"], wraplength=800,
                          style="Muted.TLabel").pack(anchor="w")
        if not self.prereq_ok:
            ttk.Label(self.frm_pre, text="Install what is marked, then press 'Recheck'. (You need an internet connection "
                      "for the first build: it downloads open-source libraries.)", wraplength=800,
                      foreground=COL["warn"]).pack(anchor="w", pady=2)
        ttk.Button(self.frm_pre, text="Recheck", command=lambda: threading.Thread(
            target=self._prereq_check, daemon=True).start()).pack(anchor="w", pady=2)

    def log_add(self, text, tag=None):
        self.log.config(state="normal")
        self.log.insert("end", text + "\n", tag)
        n = int(self.log.index("end-1c").split(".")[0])
        if n > 4000:
            self.log.delete("1.0", "%d.0" % (n - 4000))
        self.log.see("end")
        self.log.config(state="disabled")

    def set_step(self, name, state, note=None):
        self.step_state[name] = state
        g, t, m = self.step_rows[name]
        color = {"pending": COL["muted"], "running": COL["warn"], "done": COL["ok"], "skip": COL["ok"],
                 "failed": COL["bad"], "plan": COL["accent"]}[state]
        g.config(text=GLYPH[state], fg=color)
        if note is not None:
            m.config(text=note)

    def update_bar(self):
        names = [n for n, _ in core.STEPS]
        done = sum(1 for n in names if self.step_state[n] in ("done", "skip", "plan"))
        total = max(1, sum(1 for n in names if self.step_state[n] != "off"))
        val = (done + (self.step_frac if self.cur_step else 0.0)) / total
        self.bar.config(value=int(1000 * min(1.0, val)))
        el = time.time() - self.build_started if self.build_started else 0
        self.lbl_prog.config(text="%d%%   %s elapsed" % (int(val * 100), self.fmt_secs(el)))

    def on_build(self, dry):
        if self.build_busy:
            return
        iso = self.var_iso.get().strip().strip('"')
        if not iso or not os.path.isfile(iso):
            self.lbl_iso.config(text="Choose your Tekken 4 (USA) ISO first.", foreground=COL["bad"])
            messagebox.showinfo(TITLE, "Please choose your Tekken 4 (USA) ISO first (Browse...).")
            return
        self.settings["iso"] = iso
        self.save()
        script = core.build_script()
        if not os.path.isfile(script):
            messagebox.showerror(TITLE, "Missing: %s\nThis folder is incomplete." % script)
            return
        for n, _ in core.STEPS:
            self.set_step(n, "pending", "")
        self.cur_step, self.step_frac, self.build_failed = None, 0.0, False
        self.build_busy, self.build_dry = True, dry
        self.build_started = time.time()
        self.btn_build.config(state="disabled")
        self.btn_dry.config(state="disabled")
        self.btn_cancel.config(state="normal")
        self.lbl_build.config(text="Dry run..." if dry else "Building... (keep this window open)", foreground=COL["warn"])
        self.log.config(state="normal")
        self.log.delete("1.0", "end")
        self.log.config(state="disabled")
        self.refresh_play()
        cmd = core.build_command(iso, dry)
        self.log_add("> " + " ".join('"%s"' % c if " " in c else c for c in cmd), "step")
        self.tail = core.LogTail(core.BUILD_LOG, lambda a, b: self.post("ninja", a, b))
        self.tail.start()
        threading.Thread(target=self._build_thread, args=(cmd,), daemon=True).start()
        self.after(1000, self._tick)

    def _tick(self):
        if self.build_busy:
            self.update_bar()
            self.after(1000, self._tick)

    def _build_thread(self, cmd):
        try:
            env = dict(os.environ, PYTHONUTF8="1", T4_PYTHON=core.find_python())
            self.build_proc = subprocess.Popen(cmd, cwd=core.ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                               creationflags=core.NO_WINDOW, env=env)
            for raw in iter(self.build_proc.stdout.readline, b""):
                self.post("bline", raw.decode("utf-8", "replace").rstrip("\r\n"))
            code = self.build_proc.wait()
        except OSError as e:
            self.post("bline", "Could not start PowerShell: %s" % e)
            code = 1
        self.post("bdone", code)

    def ev_bline(self, line):
        tag = None
        m = core.RE_STEP.match(line)
        if m:
            name = m.group(3)
            if name in self.step_state:
                if self.cur_step and self.step_state.get(self.cur_step) == "running":
                    self.set_step(self.cur_step, "done")
                self.cur_step, self.step_frac = name, 0.0
                self.set_step(name, "running", "")
                tag = "step"
        else:
            r = core.RE_RESULT.match(line)
            if r and self.cur_step and self.step_state.get(self.cur_step) == "running":
                res = r.group(1)
                st = "plan" if res in ("would run",) else ("skip" if res in ("up to date", "exists", "checked") else "done")
                self.set_step(self.cur_step, st, "%s (%ss)" % (res, r.group(2)))
                self.cur_step, self.step_frac = None, 0.0
                tag = "ok"
            elif self.cur_step == "extract":
                p = core.RE_PERCENT.search(line)
                if p:
                    self.step_frac = min(1.0, int(p.group(1)) / 100.0)
        if line.startswith("FAILED at step"):
            self.build_failed = True
            tag = "err"
            mm = line.split("'")
            if len(mm) >= 2 and mm[1] in self.step_state:
                self.set_step(mm[1], "failed")
        elif "Missing prerequisites" in line or line.startswith("ERROR"):
            tag = "err"
        self.log_add(line, tag)
        self.update_bar()

    def ev_ninja(self, done, total):
        if self.cur_step == "runtime" or self.step_state.get("runtime") == "running":
            self.step_frac = done / float(total)
            self.set_step("runtime", "running", "%d / %d files" % (done, total))
            self.update_bar()
        elif self.cur_step in ("tools",):
            self.step_frac = done / float(total)
            self.set_step("tools", "running", "%d / %d files" % (done, total))
            self.update_bar()

    def ev_bdone(self, code):
        if self.tail:
            self.tail.stop_flag.set()
        self.build_busy = False
        self.btn_build.config(state="normal")
        self.btn_dry.config(state="normal")
        self.btn_cancel.config(state="disabled")
        cancelled = getattr(self, "_cancelled", False)
        self._cancelled = False
        ok = code == 0 and not self.build_failed and not cancelled
        if self.cur_step and self.step_state.get(self.cur_step) == "running":
            self.set_step(self.cur_step, "failed" if not ok else "done")
        self.step_frac = 0.0
        self.update_bar()
        if cancelled:
            msg, color = "Cancelled. Press BUILD GAME again to continue where it stopped.", COL["warn"]
        elif ok and self.build_dry:
            msg, color = "Dry run finished: nothing was changed. The steps marked with a triangle would run.", COL["ok"]
        elif ok:
            msg, color = "Build finished. Go to 'Play offline' and press PLAY.", COL["ok"]
        else:
            msg, color = ("The build stopped (see the red lines in the log and the step marked with a cross). "
                          "Full log: %s" % core.BUILD_LOG), COL["bad"]
        self.lbl_build.config(text=msg, foreground=color)
        self.settings["last_build"] = {"time": time.strftime("%Y-%m-%d %H:%M:%S"), "ok": ok, "dry_run": self.build_dry,
                                       "log": core.BUILD_LOG}
        self.save()
        self.refresh_play()
        threading.Thread(target=self._prereq_check, daemon=True).start()
        if ok and not self.build_dry:
            self.nb.select(self.tab_play)
        elif not ok and not cancelled:
            messagebox.showerror(TITLE, "The build stopped.\n\n%s\n\nFull log:\n%s" % (self.last_error_hint(), core.BUILD_LOG))

    def last_error_hint(self):
        txt = self.log.get("1.0", "end").splitlines()
        for i, l in enumerate(txt):
            if l.startswith("FAILED at step"):
                return "\n".join(x for x in txt[i:i + 4] if x.strip())
            if "Missing prerequisites" in l:
                return "\n".join(x for x in txt[i:i + 8] if x.strip())
        return "\n".join(x for x in txt[-6:] if x.strip())

    def on_cancel(self):
        if self.build_proc and self.build_proc.poll() is None:
            if messagebox.askyesno(TITLE, "Stop the build? The next BUILD GAME continues where it stopped."):
                self._cancelled = True
                core.kill_tree(self.build_proc)

    # ============================================================ Settings tab
    def _build_settings(self):
        f = self.tab_set
        s = self.settings
        ttk.Label(f, text="Settings", font=("Segoe UI", 14, "bold")).grid(row=0, column=0, columnspan=3, sticky="w")
        ttk.Label(f, text="Saved in launcher\\settings.json, used the next time you press PLAY.",
                  style="Muted.TLabel").grid(row=1, column=0, columnspan=3, sticky="w", pady=(0, 12))
        ttk.Label(f, text="Internal resolution").grid(row=2, column=0, sticky="w", pady=4)
        self.var_res = tk.StringVar(value=core.RES_LABEL[s["resolution"]])
        cb = ttk.Combobox(f, textvariable=self.var_res, values=[l for _, l, _ in core.RESOLUTIONS], state="readonly",
                          width=38)
        cb.grid(row=2, column=1, sticky="w", padx=10)
        cb.bind("<<ComboboxSelected>>", lambda e: self.on_setting())
        self.lbl_res = ttk.Label(f, text="", style="Muted.TLabel", wraplength=300)
        self.lbl_res.grid(row=2, column=2, sticky="w")
        ttk.Label(f, text="Higher than Native is experimental: thin vertical lines and small steps can show at 64x32 pixel "
                  "borders.", style="Muted.TLabel", wraplength=700).grid(row=3, column=1, columnspan=2, sticky="w", padx=10)
        self.var_sound = tk.BooleanVar(value=s["sound"])
        self.var_debug = tk.BooleanVar(value=s["debug_panel"])
        self.var_full = tk.BooleanVar(value=s["fullscreen"])
        self.var_aa = tk.BooleanVar(value=s["aa"])
        self.var_prog = tk.BooleanVar(value=s["progressive"])
        self.var_excl = tk.BooleanVar(value=s["fullscreen_exclusive"])
        self.var_unlock = tk.BooleanVar(value=s["unlock_all"])
        self.chk = {}
        rows = [("sound", "Sound (music, effects, voices)", self.var_sound, "TEKKEN4_SOUND"),
                ("debug", "Show the debug panel at start (off for normal play; F1 toggles it in the game)",
                 self.var_debug, "PS2X_DEBUG_PANEL"),
                ("full", "Start in fullscreen", self.var_full, "fullscreen"),
                ("aa", "Anti-aliasing", self.var_aa, "aa"),
                ("prog", "Progressive scan (sharper picture, no interlace flicker)", self.var_prog, "progressive"),
                ("excl", "Exclusive fullscreen (a little less input lag; F11 / Alt+Enter toggle)", self.var_excl,
                 "TEKKEN4_FULLSCREEN"),
                ("unlock", "All characters unlocked (your save is not changed)", self.var_unlock, "TEKKEN4_UNLOCK_ALL")]
        for i, (key, text, var, _) in enumerate(rows):
            c = ttk.Checkbutton(f, text=text, variable=var, command=self.on_setting)
            c.grid(row=4 + i, column=0, columnspan=2, sticky="w", pady=4)
            n = ttk.Label(f, text="", style="Muted.TLabel", wraplength=300)
            n.grid(row=4 + i, column=2, sticky="w")
            self.chk[key] = (c, n)
        ttk.Separator(f).grid(row=10, column=0, columnspan=3, sticky="we", pady=14)
        ttk.Label(f, text="Game build:").grid(row=11, column=0, sticky="w")
        self.lbl_exe = ttk.Label(f, text="", style="Muted.TLabel", wraplength=700)
        self.lbl_exe.grid(row=11, column=1, columnspan=2, sticky="w", padx=10)
        ttk.Label(f, text="Saves go to:").grid(row=12, column=0, sticky="w", pady=4)
        ttk.Label(f, text=core.SAVE_DIR, style="Muted.TLabel").grid(row=12, column=1, columnspan=2, sticky="w", padx=10)
        self.update_settings_notes()

    def update_settings_notes(self):
        s = self.settings
        exe, why = core.find_runtime(s)
        sup = core.graphics_support(exe)
        names = core.graphics_env_names()
        self.lbl_res.config(text="-> TEKKEN4_INTERNAL_RES=%s" % core.internal_res(s) +
                            (" (your screen: %dp)" % core.screen_height() if s["resolution"] == "auto" else ""))
        for key, flag in (("full", "fullscreen"), ("aa", "aa"), ("prog", "progressive")):
            c, n = self.chk[key]
            if sup[flag]:
                c.state(["!disabled"])
                n.config(text="(%s)" % names[flag])
            else:
                c.state(["disabled"])
                n.config(text="not in this build yet (%s)" % names[flag] if exe else "needs a built game")
        if not sup["fullscreen"]:
            self.chk["full"][1].config(text="Not in this build yet. In the game try Alt+Enter or F11.")
        self.lbl_exe.config(text="%s (%s)" % (exe, why) if exe else why)

    def on_setting(self):
        s = self.settings
        for k, l, _ in core.RESOLUTIONS:
            if l == self.var_res.get():
                s["resolution"] = k
        s["sound"], s["debug_panel"] = bool(self.var_sound.get()), bool(self.var_debug.get())
        s["fullscreen"], s["aa"], s["progressive"] = bool(self.var_full.get()), bool(self.var_aa.get()), bool(self.var_prog.get())
        s["fullscreen_exclusive"], s["unlock_all"] = bool(self.var_excl.get()), bool(self.var_unlock.get())
        self.save()
        self.update_settings_notes()
        self.refresh_play()

    # ============================================================ Controls tab
    def _build_controls(self):
        f = self.tab_ctl
        ttk.Label(f, text="Controls (player 1)", font=("Segoe UI", 14, "bold")).pack(anchor="w")
        ttk.Label(f, text=CONTROLS_NOTE, style="Muted.TLabel", wraplength=820, justify="left").pack(anchor="w", pady=(0, 10))
        tv = ttk.Treeview(f, columns=("kb", "pad"), show="tree headings", height=len(CONTROLS), selectmode="none")
        tv.heading("#0", text="PS2 button / action")
        tv.heading("kb", text="Keyboard")
        tv.heading("pad", text="Gamepad (Xbox layout)")
        tv.column("#0", width=260)
        tv.column("kb", width=300)
        tv.column("pad", width=220)
        for a, k, g in CONTROLS:
            tv.insert("", "end", text=a, values=(k, g))
        tv.pack(fill="x")
        ttk.Label(f, text="In Tekken 4: Square = left punch, Triangle = right punch, Cross = left kick, "
                  "Circle = right kick.", style="Muted.TLabel").pack(anchor="w", pady=8)

    # ============================================================ Online tab
    def _build_online(self):
        f = self.tab_online
        ttk.Label(f, text="Online play", font=("Segoe UI", 14, "bold")).pack(anchor="w")
        ttk.Label(f, text="Comes with the T4 lobby server.", font=("Segoe UI", 12)).pack(anchor="w", pady=(10, 4))
        ttk.Label(f, text="Rollback netplay already works between two local copies of the game; the lobby (finding "
                  "and joining matches) is being built. Nothing to set up here yet.", style="Muted.TLabel",
                  wraplength=760, justify="left").pack(anchor="w")
        for text in ("Server address", "Player name"):
            r = ttk.Frame(f)
            r.pack(anchor="w", pady=6)
            ttk.Label(r, text=text, width=16).pack(side="left")
            e = ttk.Entry(r, width=40, state="disabled")
            e.pack(side="left")
        ttk.Button(f, text="Find a match", state="disabled").pack(anchor="w", pady=8)

    # ============================================================ closing
    def on_close(self):
        if self.build_busy:
            if not messagebox.askyesno(TITLE, "A build is running. Stop it and close the launcher?\n"
                                       "(The next BUILD GAME continues where it stopped.)"):
                return
            self._cancelled = True
            core.kill_tree(self.build_proc)
        if self.game:
            self.game.stop()
            core.release_run_lock()
        self.destroy()


# ---------------------------------------------------------------- command line helpers
def selftest():
    s = core.load_settings()
    exe, why = core.find_runtime(s)
    print("root", core.ROOT, "release" if core.IS_RELEASE else "checkout")
    print("settings", {k: v for k, v in s.items() if k != "last_run"})
    print("runtime", exe, "|", why)
    print("graphics env names", core.graphics_env_names(), "support", core.graphics_support(exe))
    print("play problems", core.play_problems(s))
    for res, _, _ in core.RESOLUTIONS:
        s2 = dict(s, resolution=res)
        e = core.game_env(s2, exe)
        print(" %-6s res=%s sound=%s debug=%s" % (res, e["TEKKEN4_INTERNAL_RES"], e["TEKKEN4_SOUND"], e["PS2X_DEBUG_PANEL"]))
    for it in core.check_prereqs():
        print(" prereq", "ok " if it["ok"] else "MISSING", it["name"], "-", it["detail"])
    print("build command", core.build_command(s.get("iso", ""), True))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--screenshot", metavar="PNG")
    ap.add_argument("--tab", type=int, default=0)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--auto-dry-run", action="store_true", help="test: press 'Dry run' after start")
    ap.add_argument("--auto-play", type=float, metavar="SECONDS", help="test: press PLAY, stop the game after SECONDS")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(selftest())
    enable_dpi_awareness()
    app = App()
    if a.tab:
        app.nb.select(a.tab)
    if a.auto_dry_run:
        app.nb.select(app.tab_build)
        app.after(1500, lambda: app.on_build(True))
    if a.auto_play:
        app.after(1500, app.on_play)
        app.after(int(a.auto_play * 1000) + 1500, app.on_stop)
    if a.screenshot:
        def shot():
            app.update_idletasks()
            hwnd = ctypes.windll.user32.GetParent(app.winfo_id()) or app.winfo_id()
            print("screenshot", a.screenshot, core.capture_window(hwnd, a.screenshot))
            if not (a.auto_dry_run or a.auto_play):
                app.destroy()
        app.after(2500 if not (a.auto_dry_run or a.auto_play) else 8000, shot)
    app.mainloop()


if __name__ == "__main__":
    main()
