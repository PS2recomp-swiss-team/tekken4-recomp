"""Builds and runs tools/match_state_test.cpp (runtime/tekken4_match_state.h on synthetic RAM) with MSVC.
    python -I tools/test_match_state.py     (skips when no Visual Studio C++ compiler is installed)"""
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
VSWHERE = os.path.join(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
                       "Microsoft Visual Studio", "Installer", "vswhere.exe")


def vcvars():
    if not os.path.exists(VSWHERE):
        return None
    out = subprocess.run([VSWHERE, "-latest", "-products", "*", "-requires",
                          "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"],
                         capture_output=True, text=True).stdout.strip()
    bat = os.path.join(out, "VC", "Auxiliary", "Build", "vcvars64.bat") if out else ""
    return bat if bat and os.path.exists(bat) else None


class MatchStateTest(unittest.TestCase):
    def test_tracker(self):
        bat = vcvars()
        if not bat:
            self.skipTest("no MSVC")
        with tempfile.TemporaryDirectory() as tmp:
            exe = os.path.join(tmp, "match_state_test.exe")
            src = os.path.join(HERE, "match_state_test.cpp")
            script = os.path.join(tmp, "build.cmd")
            with open(script, "w", encoding="ascii") as f:
                f.write("@echo off\n")
                f.write('call "%s" >nul || exit /b 1\n' % bat)
                f.write('cl /nologo /std:c++17 /EHsc /W4 /WX /O1 "%s" /Fe"%s" /Fo"%s"\n'
                        % (src, exe, os.path.join(tmp, "match_state_test.obj")))
            build = subprocess.run(["cmd", "/c", script], capture_output=True, text=True, cwd=tmp)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([exe], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout)
            self.assertIn("all passed", run.stdout)


if __name__ == "__main__":
    unittest.main()
