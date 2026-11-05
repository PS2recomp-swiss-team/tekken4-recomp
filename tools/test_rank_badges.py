"""Production badge geometry/cache tests using synthetic renderer calls; no game or network.

python -I tools/test_rank_badges.py
Artifacts/logs stay in logs/rank-badge-tests. No real launcher configuration is read.
"""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
STUB = r'''#pragma once
#include <vector>
struct Vector2 { float x,y; };
struct Rectangle { float x,y,width,height; };
struct Color { unsigned char r,g,b,a; };
struct Image { void *data; int width,height,mipmaps,format; };
struct Texture2D { unsigned int id; int width,height,mipmaps,format; };
constexpr int TEXTURE_FILTER_BILINEAR=1;
namespace test_renderer {
inline std::vector<Vector2> vertices;
inline std::vector<Color> colors;
inline int imageLoads=0,textureDraws=0;
inline Rectangle target{};
inline Color tint{};
inline void reset() { vertices.clear(); colors.clear(); textureDraws=0; }
}
inline void DrawTriangle(Vector2 a,Vector2 b,Vector2 c,Color color) {
 test_renderer::vertices.insert(test_renderer::vertices.end(),{a,b,c});
 test_renderer::colors.push_back(color);
}
inline Image LoadImageFromMemory(const char *,const unsigned char *data,int size) {
 ++test_renderer::imageLoads;
 return size>=24 && data[0]==1 ? Image{const_cast<unsigned char *>(data),192,96,1,7} : Image{};
}
inline Texture2D LoadTextureFromImage(Image image) { return Texture2D{1,image.width,image.height,1,7}; }
inline void SetTextureFilter(Texture2D,int) {}
inline void UnloadImage(Image) {}
inline void DrawTexturePro(Texture2D,Rectangle,Rectangle target,Vector2,float,Color tint) {
 ++test_renderer::textureDraws;test_renderer::target=target;test_renderer::tint=tint;
}
'''

class RankBadgeTests(unittest.TestCase):
    def test_metadata(self):
        spec = importlib.util.spec_from_file_location("make_rank_badges", ROOT / "tools/make_rank_badges.py")
        badges = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(badges)
        self.assertEqual(len(badges.NAMES), 37)
        self.assertEqual(badges.NAMES[19], "Warrior")
        self.assertEqual(badges.NAMES[22], "Champion")
        self.assertEqual(badges.NAMES[-1], "Tekken Lord (Kirin)")
        self.assertEqual(badges.spec(19)["plate"], "#2f9446")
        self.assertEqual(badges.W / badges.H, 1.6)
        for tier in range(37):
            image = ET.fromstring(badges.svg(tier))
            self.assertEqual(image.attrib["viewBox"], "0 0 160 100")
            self.assertEqual(image.findall(".//{http://www.w3.org/2000/svg}text"), [])
            self.assertEqual(image.findall(".//{http://www.w3.org/2000/svg}circle"), [])

        with tempfile.TemporaryDirectory(dir=ROOT / "logs") as folder:
            header = Path(folder) / "metadata.h"
            badges.header(header)
            self.assertEqual(header.read_text(encoding="utf-8"), (ROOT / "runtime/tekken4_rank_badges.h").read_text(encoding="utf-8"))

    def test_cpp_helpers(self):
        vswhere = Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / (
            "Microsoft Visual Studio/Installer/vswhere.exe")
        if not vswhere.exists():
            self.skipTest("MSVC not installed")
        install = subprocess.run([str(vswhere), "-latest", "-products", "*", "-requires",
                                  "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property",
                                  "installationPath"], capture_output=True, text=True, check=True).stdout.strip()
        if not install:
            self.skipTest("MSVC C++ tools not installed")
        build = ROOT / "logs/rank-badge-tests"
        build.mkdir(parents=True, exist_ok=True)
        (build / "raylib.h").write_text(STUB, encoding="ascii")
        vcvars = Path(install) / "VC/Auxiliary/Build/vcvars64.bat"
        script = build / "build.cmd"
        script.write_text('@echo off\ncall "%s" >nul || exit /b 1\n'
                          'cl /nologo /std:c++17 /EHsc /W4 /WX /D_CRT_SECURE_NO_WARNINGS /O1 /I"%s" "%s" /Fe"%s" /Fo"%s"\n'
                          % (vcvars, build, ROOT / "tools/rank_badges_test.cpp", build / "rank_badges_test.exe",
                             build / "rank_badges_test.obj"), encoding="ascii")
        result = subprocess.run(["cmd", "/c", str(script)], cwd=build, capture_output=True, text=True)
        (build / "build.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = subprocess.run([str(build / "rank_badges_test.exe")], cwd=build, capture_output=True, text=True)
        (build / "result.log").write_text(result.stdout + result.stderr, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("all passed", result.stdout)

if __name__ == "__main__":
    (ROOT / "logs").mkdir(exist_ok=True)
    unittest.main(verbosity=2)
