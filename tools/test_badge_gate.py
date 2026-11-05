"""Badge visibility gate (runtime/tekken4_badge_gate.h): synthetic counters, no game or network.

python -I tools/test_badge_gate.py
Build artifacts stay in logs/badge-gate-tests.
"""
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent


class BadgeGateTests(unittest.TestCase):
    def test_cpp_gate(self):
        vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / (
            "Microsoft Visual Studio/Installer/vswhere.exe")
        if not vswhere.exists():
            self.skipTest("MSVC not installed")
        install = subprocess.run([str(vswhere), "-latest", "-products", "*", "-requires",
                                  "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property",
                                  "installationPath"], capture_output=True, text=True, check=True).stdout.strip()
        if not install:
            self.skipTest("MSVC C++ tools not installed")
        build = ROOT / "logs/badge-gate-tests"
        build.mkdir(parents=True, exist_ok=True)
        script = build / "build.cmd"
        script.write_text('@echo off\ncall "%s" >nul || exit /b 1\n'
                          'cl /nologo /std:c++17 /EHsc /W4 /WX /D_CRT_SECURE_NO_WARNINGS /O1 "%s" /Fe"%s" /Fo"%s"\n'
                          % (Path(install) / "VC/Auxiliary/Build/vcvars64.bat", ROOT / "tools/badge_gate_test.cpp",
                             build / "badge_gate_test.exe", build / "badge_gate_test.obj"), encoding="ascii")
        result = subprocess.run(["cmd", "/c", str(script)], cwd=build, capture_output=True, text=True)
        (build / "build.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = subprocess.run([str(build / "badge_gate_test.exe")], cwd=build, capture_output=True, text=True)
        (build / "result.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("all passed", result.stdout)

    def test_presenter_uses_the_gate(self):
        """The presenter must not fall back to scene-only visibility, and the queue must stamp the frame."""
        source = (ROOT / "runtime/tekken4_hud_overrides.cpp").read_text(encoding="utf-8")
        self.assertIn("tekken4_badge_gate::visible(a.valid, a.scene, a.alpha, a.frame, scene, frame)", source)
        self.assertRegex(source, r"Anchor\{x, y, scene, alpha, rd32\(ram, tekken4_badge_gate::kGameFrame\), true\}")
        draw = source[source.index("void draw(PS2Runtime"):]
        self.assertNotRegex(draw, r"!a\.valid \|\| a\.scene != scene")
        # Host only: the override must never store into guest RAM (netplay hashes cover it).
        self.assertNotRegex(source, r"memcpy\(\s*(ram|rdram)\s*\+")
        self.assertNotRegex(source, r"\bwr32\(|\bsetRegU32\(|ctx->r\[")


if __name__ == "__main__":
    (ROOT / "logs").mkdir(exist_ok=True)
    unittest.main(verbosity=2)
