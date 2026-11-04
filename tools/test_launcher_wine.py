"""Wine / Proton (Linux, Steam Deck; docs/LINUX_STEAM_DECK.md): the launcher core says that Tekken 4's PowerShell
build and online helper cannot run there, and on Windows nothing changes. Mocked: no PowerShell is started.

python -B -m unittest discover -s tools -p test_launcher_wine.py -v
"""
import importlib.util
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("t4core_wine_tests", ROOT / "launcher" / "t4core.py")
core = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(core)


class Fn:
    def __init__(self, ret):
        self.ret = ret

    def __call__(self):
        return self.ret


class WineNtdll:
    wine_get_version = Fn(b"10.0")


class WindowsNtdll:
    pass


def never(*_a, **_k):
    raise AssertionError("PowerShell was started")


class Detect(unittest.TestCase):
    def test_stand_ins(self):
        self.assertEqual(core.wine_version(WineNtdll()), "Wine 10.0")
        self.assertIsNone(core.wine_version(WindowsNtdll()))

    @unittest.skipUnless(os.name == "nt", "Windows")
    def test_this_pc_is_windows(self):
        self.assertIsNone(core.wine_version())


class PowerShell(unittest.TestCase):
    def test_windows_never_asks(self):
        self.assertEqual(core.powershell_problem(run=never, wine=""), "")
        with patch.object(core, "wine_version", return_value=None), patch.object(core.subprocess, "run", never):
            self.assertEqual(core.powershell_problem(), "")

    def test_wine_stand_in_powershell(self):
        silent = lambda *a, **k: subprocess.CompletedProcess(a[0], 0, "", "")     # Wine's stub: no output
        self.assertEqual(core.powershell_problem(run=silent, wine="Wine 10.0"), core.NO_POWERSHELL)
        answers = lambda *a, **k: subprocess.CompletedProcess(a[0], 0, "t4psok\r\n", "")
        self.assertEqual(core.powershell_problem(run=answers, wine="Wine 10.0"), "")

        def missing(*_a, **_k):
            raise FileNotFoundError("powershell.exe")
        self.assertEqual(core.powershell_problem(run=missing, wine="Wine 10.0"), core.NO_POWERSHELL)

        def slow(*a, **_k):
            raise subprocess.TimeoutExpired(a[0], 20)
        self.assertEqual(core.powershell_problem(run=slow, wine="Wine 10.0"), core.NO_POWERSHELL)

    def test_online_refused_under_wine_only(self):
        with patch.object(core, "powershell_problem", return_value=core.NO_POWERSHELL):
            with self.assertRaises(ValueError) as e:
                core.online_command({}, "host")
            self.assertIn("PowerShell", str(e.exception))
        with patch.object(core, "powershell_problem", return_value=""), \
                patch.object(core, "play_problems", return_value=["not built"]):
            with self.assertRaises(ValueError) as e:      # Windows: on to the usual checks, as before
                core.online_command({}, "host")
            self.assertEqual(str(e.exception), "not built")

    def test_prereq_row_under_wine_only(self):
        with patch.object(core, "wine_version", return_value="Wine 10.0"), \
                patch.object(core, "powershell_problem", return_value=core.NO_POWERSHELL), \
                patch.object(core, "bundled_toolchain", return_value=True), \
                patch.object(core, "sysroot_ready", return_value=False):
            rows = core.check_prereqs()
        self.assertEqual(rows[0]["id"], "powershell")
        self.assertFalse(rows[0]["ok"])
        self.assertEqual(rows[0]["fix"], core.NO_POWERSHELL)
        with patch.object(core, "wine_version", return_value=None), \
                patch.object(core, "powershell_problem", never), \
                patch.object(core, "bundled_toolchain", return_value=True), \
                patch.object(core, "sysroot_ready", return_value=False):
            rows = core.check_prereqs()
        self.assertNotIn("powershell", [r["id"] for r in rows])


if __name__ == "__main__":
    unittest.main()
