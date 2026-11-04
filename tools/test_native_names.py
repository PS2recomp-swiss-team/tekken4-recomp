"""Compile/run the production native-name helpers on synthetic RAM. Writes only under this worktree.

python -I tools/test_native_names.py
No game executable or netplay is run. Build artifacts remain in ignored logs/native-name-tests.
"""
import os
from pathlib import Path
import subprocess
import struct
import unittest
import zlib

ROOT = Path(__file__).resolve().parent.parent


class NativeNamesTests(unittest.TestCase):
    def test_us_static_sites(self):
        elf = ROOT / "game/disc/SLUS_203.28"
        if not elf.exists():
            self.skipTest("local US ELF unavailable; helper tests need no game data")
        data = elf.read_bytes()
        self.assertEqual(zlib.crc32(data), 0xB975F704)

        def word(address):
            return struct.unpack_from("<I", data, address - 0x180080 + 0x1080)[0]

        # Independently verify the actual call instructions behind the side/lookup contract.
        for call, target in ((0x1e2e9c, 0x222620), (0x1f5074, 0x1f2e70),
                             (0x1f1b8c, 0x1f0a80), (0x1f1bd0, 0x1f0a80),
                             (0x1f5308, 0x24f0d8), (0x1f1b5c, 0x24f0c0),
                             (0x27ef70, 0x236eb8)):
            self.assertEqual(word(call), (3 << 26) | (target >> 2), hex(call))
        # Active select uses the preserved s3 side loop and separate name widget IDs.
        self.assertEqual(word(0x27e9b0), 0x0000982d)  # s3=0
        self.assertEqual(word(0x27ed90), 0x26640001)  # side+1 for the next iteration
        self.assertEqual(word(0x27ef78), 0x8fb30014)  # s3 restored only after the name draw
        self.assertEqual(word(0x27ef10), 0x24100105)  # P2 name widget
        self.assertEqual(word(0x27ef14), 0x24020104)  # P1 name widget
        # Original HUD names use Z=0x0ffffff0. The font queue must reproduce its low
        # 24 bits after its signed halfword depth is multiplied by 16.
        for load, finish in ((0x1f1b68, 0x1f1b84), (0x1f1bac, 0x1f1bc8)):
            self.assertEqual(word(load), 0x3c080fff)  # lui t0,0x0fff
            self.assertEqual(word(finish), 0x3508fff0)  # ori t0,t0,0xfff0
        self.assertEqual(word(0x22c6f8), 0x00073c03)  # signed queue depth
        self.assertEqual(word(0x1ec7c8), 0x00108100)  # font depth * 16
        descriptor = word(0x31f208)
        offset = descriptor - 0x180080 + 0x1080
        metrics = data[offset:offset + 256]
        self.assertTrue(all(0 < metrics[c] < 128 for c in range(0x20, 0x7f)))
        self.assertNotEqual(metrics[ord("A")], metrics[ord("a")])

    def test_native_helpers(self):
        vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / (
            "Microsoft Visual Studio/Installer/vswhere.exe")
        if not vswhere.exists():
            self.skipTest("MSVC not installed")
        install = subprocess.run([str(vswhere), "-latest", "-products", "*", "-requires",
                                  "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property",
                                  "installationPath"], capture_output=True, text=True, check=True).stdout.strip()
        if not install:
            self.skipTest("MSVC C++ tools not installed")
        vcvars = Path(install) / "VC/Auxiliary/Build/vcvars64.bat"
        build = ROOT / "logs/native-name-tests"
        build.mkdir(parents=True, exist_ok=True)
        script = build / "build.cmd"
        script.write_text('@echo off\ncall "%s" >nul || exit /b 1\n'
                          'cl /nologo /std:c++17 /EHsc /W4 /WX /D_CRT_SECURE_NO_WARNINGS /O1 "%s" /Fe"%s" /Fo"%s"\n'
                          % (vcvars, ROOT / "tools/native_names_test.cpp", build / "native_names_test.exe",
                             build / "native_names_test.obj"), encoding="ascii")
        result = subprocess.run(["cmd", "/c", str(script)], cwd=build, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = subprocess.run([str(build / "native_names_test.exe")], cwd=build, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("all passed", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
