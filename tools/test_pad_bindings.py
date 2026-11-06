"""Pad bindings (patches/99-ps2xRuntime-pad-bindings.patch): builds tools/pad_bindings_test.cpp against the header the
patch adds and runs it (parser, default layout vs a copy of the old fixed code, mappings, live reload), and checks the
patch's place in the stack. Needs MSVC (like test_rank_label.py); no game, no window, no pad."""
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "logs/pad-bindings-tests"
PATCH = ROOT / "patches/99-ps2xRuntime-pad-bindings.patch"
HEADER = "ps2xRuntime/include/runtime/ps2_pad_bindings.h"


def added_file(patch_text, name):
    """The text of a file a patch creates ('+' lines of its hunk)."""
    marker = "+++ b/" + name
    start = patch_text.index(marker)
    lines = patch_text[start:].splitlines()[2:]      # skip the +++ line and the @@ line
    out = []
    for line in lines:
        if line.startswith("diff --git"):
            break
        if line.startswith("+"):
            out.append(line[1:])
    return "\n".join(out) + "\n"


class PadBindingsPatch(unittest.TestCase):
    def test_patch_is_last_in_name_order(self):
        names = sorted(p.name for p in (ROOT / "patches").glob("*.patch"))
        self.assertEqual(names[-1], PATCH.name)

    def test_patch_touches_only_the_pad_files(self):
        text = PATCH.read_text(encoding="utf-8")
        files = set(re.findall(r"^diff --git a/(\S+) b/", text, re.M))
        self.assertEqual(files, {
            "ps2xRuntime/include/runtime/ps2_host_pad.h", "ps2xRuntime/include/runtime/ps2_input_latency.h",
            "ps2xRuntime/include/runtime/ps2_pad.h", "ps2xRuntime/include/runtime/ps2_pad_bindings.h",
            "ps2xRuntime/src/lib/Kernel/Stubs/Pad.cpp", "ps2xRuntime/src/lib/ps2_host_pad.cpp",
            "ps2xRuntime/src/lib/ps2_input_latency.cpp", "ps2xRuntime/src/lib/ps2_pad.cpp"})
        self.assertNotIn("\r", text)

    def test_header_builds_and_passes(self):
        vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / (
            "Microsoft Visual Studio/Installer/vswhere.exe")
        if not vswhere.exists():
            self.skipTest("MSVC discovery tool missing")
        install = subprocess.run([str(vswhere), "-latest", "-products", "*", "-requires",
                                  "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property",
                                  "installationPath"], capture_output=True, text=True).stdout.strip()
        if not install:
            self.skipTest("MSVC C++ tools missing")
        include = BUILD / "include/runtime"
        include.mkdir(parents=True, exist_ok=True)
        (include / "ps2_pad_bindings.h").write_text(added_file(PATCH.read_text(encoding="utf-8"), HEADER),
                                                    encoding="utf-8", newline="\n")
        script = BUILD / "build.cmd"
        script.write_text('@echo off\ncall "%s" >nul || exit /b 1\n'
                          'cl /nologo /std:c++17 /EHsc /W4 /WX /D_CRT_SECURE_NO_WARNINGS /O1 /I"%s" "%s" /Fe"%s" /Fo"%s"\n'
                          % (Path(install) / "VC/Auxiliary/Build/vcvars64.bat", BUILD / "include",
                             ROOT / "tools/pad_bindings_test.cpp", BUILD / "pad_bindings_test.exe",
                             BUILD / "pad_bindings_test.obj"), encoding="ascii")
        result = subprocess.run(["cmd", "/c", str(script)], cwd=BUILD, capture_output=True, text=True)
        (BUILD / "compile.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = subprocess.run([str(BUILD / "pad_bindings_test.exe"), str(BUILD)], cwd=BUILD, capture_output=True,
                                text=True, timeout=120)
        (BUILD / "result.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("all passed", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
