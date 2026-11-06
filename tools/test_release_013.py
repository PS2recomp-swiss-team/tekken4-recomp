"""0.1.3: one build id for everyone. A release folder builds with its bundled compiler only, never with the PC's
Visual Studio 2022/2026, Git, CMake or Ninja, whatever its PATH and compiler variables say. No build runs here."""
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_game
import fetch_msvc_sysroot
import prepare_portable_tree

FAKE_VS = r"D:\fake\VS2026\VC\Tools\MSVC\14.51\bin\Hostx64\x64"


class ReleaseEnvironment(unittest.TestCase):
    def pc(self):
        return {"PATH": FAKE_VS + r";C:\Program Files\Git\cmd;C:\Program Files\CMake\bin", "Path": FAKE_VS,
                "SystemRoot": r"X:\Win", "CL": "/DFAKE", "_CL_": "/DFAKE2", "CXXFLAGS": "-DFAKE", "CFLAGS": "-DFAKE",
                "INCLUDE": r"D:\fake\include", "LIB": r"D:\fake\lib", "VCINSTALLDIR": r"D:\fake\VC",
                "VisualStudioVersion": "18.0", "CMAKE_GENERATOR": "Visual Studio 18 2026", "VSCMD_VER": "18.0",
                "TEKKEN4_SRC": r"D:\dev\tree", "TEKKEN4_VULIFT": "0", "USERPROFILE": r"C:\Users\x", "TEMP": r"C:\t"}

    def test_nothing_of_the_pcs_tools_reaches_the_build(self):
        env = build_game.release_environment(self.pc())
        self.assertEqual(env["PATH"].split(os.pathsep), [r"X:\Win\System32", r"X:\Win", r"X:\Win\System32\Wbem"])
        self.assertNotIn("Path", env)
        for key in ("CL", "_CL_", "CXXFLAGS", "CFLAGS", "INCLUDE", "LIB", "VCINSTALLDIR", "VisualStudioVersion",
                    "CMAKE_GENERATOR", "VSCMD_VER", "TEKKEN4_SRC", "TEKKEN4_VULIFT"):
            self.assertNotIn(key, env)
        # what the build itself needs from Windows stays
        self.assertEqual(env["TEMP"], r"C:\t")
        self.assertEqual(env["USERPROFILE"], r"C:\Users\x")

    def test_a_release_folder_gets_the_clean_environment_and_its_own_tree(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "toolchain").mkdir()
            (root / "toolchain" / "toolchain.json").write_text("{}", encoding="utf-8")
            args = build_game.parser().parse_args(["-WhatIf"])
            saved = dict(os.environ)
            try:
                os.environ.update(CL="/DFAKE", TEKKEN4_SRC=r"D:\dev\tree", PATH=FAKE_VS + os.pathsep + os.environ["PATH"])
                build = build_game.Build(args, root)
                build.log.close()
            finally:
                os.environ.clear()
                os.environ.update(saved)
            self.assertNotIn("CL", build.env)
            self.assertNotIn(FAKE_VS.lower(), build.env["PATH"].lower())
            self.assertEqual(build.tree, (root / "deps" / "ps2recomp").resolve())

    def test_a_release_folder_without_its_compiler_never_uses_visual_studio(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "release.json").write_text('{"version": "0.1.3"}', encoding="utf-8")
            args = build_game.parser().parse_args(["-Steps", "prereq"])
            build = build_game.Build(args, root)
            try:
                with self.assertRaisesRegex(ValueError, "missing its bundled compiler"):
                    build.prereq()
                with self.assertRaisesRegex(ValueError, "missing its bundled compiler"):
                    build.compiler_environment()
            finally:
                build.log.close()

    def test_host_tools_skip_the_analyzer_and_its_unvendored_json_library(self):
        configure = build_game.cmake_plan(Path("R"), Path("T"), "runtime", False, True, {})[0]
        self.assertIn("-DPS2X_BUILD_ANALYZER=OFF", configure)


class PortableTree(unittest.TestCase):
    def test_qspectre_off_switch_is_dropped_for_clang_cl(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            tree = root / "deps" / "ps2recomp" / "ps2xRuntime"
            (tree / "cmake").mkdir(parents=True)
            (tree / "CMakeLists.txt").write_text('set(FFMPEG_PREBUILT_URL\n "https://x/y.zip")\n'.replace("\n ", " "),
                                                 encoding="utf-8")
            (tree / "cmake" / "ReleaseMode.cmake").write_text("    /GS- # a\n    /Qspectre- # b\n    /O2\n",
                                                              encoding="utf-8")
            prepare_portable_tree.prepare(root, root / "deps" / "ps2recomp")
            text = (tree / "cmake" / "ReleaseMode.cmake").read_text(encoding="utf-8")
            self.assertNotIn("Qspectre", text)
            self.assertIn("/GS-", text)


class SysrootPaths(unittest.TestCase):
    def test_cache_names_stay_short_for_deep_install_folders(self):
        payload = dict(url="https://download.visualstudio.microsoft.com/x/Windows%20SDK.msi", size=10, sha256="ab" * 32,
                       fileName="Installers\\Windows SDK for Windows Store Apps Headers OnecoreUap-x86_en-us.msi")
        with tempfile.TemporaryDirectory() as temp:
            cache = Path(temp)
            target = cache / ("ab" * 10 + ".msi")
            target.write_bytes(b"x")
            with self.assertRaisesRegex(ValueError, "corrupt"):
                fetch_msvc_sysroot.fetch(payload, cache)            # found under its short name (and checked)
        self.assertLessEqual(len(target.name), 24)


if __name__ == "__main__":
    unittest.main()
