"""Exercise the production host font loader without a renderer, game run or network."""
import os
from pathlib import Path
import subprocess
import unittest
import zlib

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "logs/rank-label-tests"

RAYLIB = r'''#pragma once
#include <vector>
struct Color { unsigned char r,g,b,a; };
struct Texture2D { unsigned id; int width,height,mipmaps,format; };
struct Rectangle { float x,y,width,height; };
struct Vector2 { float x,y; };
struct Image { void *data; int width,height,mipmaps,format; };
enum { PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 = 7, TEXTURE_FILTER_BILINEAR = 1 };
namespace test_raylib {
inline std::vector<Color> uploaded;
inline int width=0,height=0,draws=0;
inline Rectangle target{};
inline Color tint{};
}
inline Texture2D LoadTextureFromImage(Image image) {
 test_raylib::width=image.width; test_raylib::height=image.height;
 const auto *p=static_cast<const Color *>(image.data);
 test_raylib::uploaded.assign(p,p+image.width*image.height);
 return Texture2D{1,image.width,image.height,1,image.format};
}
inline void SetTextureFilter(Texture2D,int) {}
inline void DrawTexturePro(Texture2D,Rectangle,Rectangle target,Vector2,float,Color tint) {
 ++test_raylib::draws; test_raylib::target=target; test_raylib::tint=tint;
}
'''

RUNTIME = r'''#pragma once
#include <cstdint>
class PS2Runtime {
 struct Memory { uint8_t *ram; uint8_t *getRDRAM() { return ram; } } memory_;
public:
 explicit PS2Runtime(uint8_t *ram): memory_{ram} {}
 Memory &memory() { return memory_; }
};
'''


class RankLabelTests(unittest.TestCase):
    def test_host_loader(self):
        vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / (
            "Microsoft Visual Studio/Installer/vswhere.exe")
        self.assertTrue(vswhere.exists(), "MSVC discovery tool missing")
        install = subprocess.run([str(vswhere), "-latest", "-products", "*", "-requires",
                                  "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property",
                                  "installationPath"], capture_output=True, text=True, check=True).stdout.strip()
        self.assertTrue(install, "MSVC C++ tools missing")
        BUILD.mkdir(parents=True, exist_ok=True)
        (BUILD / "raylib.h").write_text(RAYLIB, encoding="ascii")
        (BUILD / "ps2_runtime.h").write_text(RUNTIME, encoding="ascii")
        script = BUILD / "build.cmd"
        script.write_text('@echo off\ncall "%s" >nul || exit /b 1\n'
                          'cl /nologo /std:c++17 /EHsc /W4 /WX /D_CRT_SECURE_NO_WARNINGS /O1 /I"%s" "%s" /Fe"%s" /Fo"%s"\n'
                          % (Path(install) / "VC/Auxiliary/Build/vcvars64.bat", BUILD,
                             ROOT / "tools/rank_label_test.cpp", BUILD / "rank_label_test.exe",
                             BUILD / "rank_label_test.obj"), encoding="ascii")
        result = subprocess.run(["cmd", "/c", str(script)], cwd=BUILD, capture_output=True, text=True)
        (BUILD / "compile.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        elf = ROOT / "game/disc/SLUS_203.28"
        arguments = [str(BUILD / "rank_label_test.exe")]
        if elf.exists():
            self.assertEqual(zlib.crc32(elf.read_bytes()), 0xB975F704)
            arguments.append(str(elf))
        result = subprocess.run(arguments, cwd=BUILD, capture_output=True, text=True)
        (BUILD / "result.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("all passed", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
