"""0.1.4: prebuilt game program + game DLL (tools/build_game_dll.py, build_game.py's prebuilt mode, t4_buildid --prebuilt,
the release layout a launcher 0.1.2 accepts).

    python -m unittest test_game_dll        (from tools\\)
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_game            # noqa: E402
import build_game_dll        # noqa: E402
import package_release       # noqa: E402
import player_common         # noqa: E402
import t4_buildid            # noqa: E402

ROOT = HERE.parent


def fake_release(base):
    """A minimal 0.1.4-shaped folder: what prebuilt_release/build_tree/t4_buildid look at."""
    root = Path(base)
    (root / "toolchain").mkdir(parents=True)
    (root / "toolchain" / "toolchain.json").write_text(json.dumps({"llvm": {"version": "23.1.3"}}), encoding="utf-8")
    for rel, data in (("bin/runtime/ps2EntryRunner.exe", b"MZ runtime ps2_game_dll_init"),
                      ("bin/runtime/ps2EntryRunner-sse2.exe", b"MZ runtime sse2 ps2_game_dll_init"),
                      ("bin/tools/ps2_recomp.exe", b"MZ recomp")):
        (root / rel).parent.mkdir(parents=True, exist_ok=True)
        (root / rel).write_bytes(data)
    src = root / "source" / "ps2recomp"
    (src / "ps2xRuntime" / "include").mkdir(parents=True)
    (src / ".t4-vendored.json").write_text(json.dumps({"head": "x", "patches": []}), encoding="utf-8")
    (src / "ps2xRuntime" / "include" / "ps2_runtime.h").write_text("// header\n", encoding="utf-8")
    for folder in ("runtime", "tools/gamedll/include", "tools/vu", "patches", "config"):
        (root / folder).mkdir(parents=True, exist_ok=True)
    (root / "runtime" / "tekken4_overrides.cpp").write_text("// module\n", encoding="utf-8")
    (root / "tools" / "gamedll" / "t4_game_dll.cpp").write_text("// entry\n", encoding="utf-8")
    shutil.copy2(HERE / "build_game_dll.py", root / "tools" / "build_game_dll.py")
    return root


class PrebuiltLayout(unittest.TestCase):
    def test_prebuilt_release_and_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = fake_release(tmp)
            self.assertTrue(player_common.prebuilt_release(root))
            self.assertEqual(player_common.build_tree(root, {}), (root / "source" / "ps2recomp").resolve())
            (root / "bin" / "runtime" / "ps2EntryRunner.exe").unlink()
            self.assertFalse(player_common.prebuilt_release(root))

    def test_same_step_names_for_every_launcher(self):
        # Launchers 0.1.2/0.1.3 follow "[n/8] <step>" lines with these names: the prebuilt mode keeps them.
        self.assertEqual(set(build_game.PREBUILT_TITLES), set(build_game.ALL_STEPS) - {"verify"})

    def test_zip_never_carries_a_name_launcher_012_protects(self):
        protected_012 = {"deps", "game", "generated", "out", "logs", "build", "settings.json", "openrecomp-release.json"}
        self.assertTrue(protected_012 <= package_release.PLAYER_NAMES)

    def test_scanner_allows_only_the_prebuilt_program_names(self):
        package_release.scan_name("bin/runtime/ps2EntryRunner.exe", 8_000_000)
        package_release.scan_name("bin/runtime/ps2EntryRunner-sse2.exe", 8_000_000)
        for bad in ("bin/ps2EntryRunner.exe", "deps/ps2recomp/out/runtime/ps2xRuntime/ps2EntryRunner.exe",
                    "bin/runtime/ps2_game.dll.obj", "generated/register_functions.cpp"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                package_release.scan_name(bad, 1000)


class SpaceCheck(unittest.TestCase):
    def test_a_full_drive_is_said_before_the_build_with_the_gb_needed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = fake_release(Path(tmp) / "T4")
            b = build_game.Build(build_game.parser().parse_args(["-LogDir", str(Path(tmp) / "logs")]), root)
            try:
                os.environ["T4_TEST_FREE_MB"] = "1000"
                with self.assertRaises(ValueError) as caught:
                    b.space_check()
                self.assertIn("needs about 3.5 GB, 1.0 GB are free", str(caught.exception))
                os.environ["T4_TEST_FREE_MB"] = "9000"
                b.space_check()                                  # enough: no error
            finally:
                os.environ.pop("T4_TEST_FREE_MB", None)
                b.log.close()


class BuildId(unittest.TestCase):
    def ids(self, root):
        lines = t4_buildid.prebuilt_toolchain(str(root))
        return t4_buildid.prebuilt_code_id(str(root), str(root / "source" / "ps2recomp"), lines), lines

    def test_same_id_in_any_folder_and_compiler_lines_for_the_launchers(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            long = Path(b) / "Spieler Müller" / "Тест" / ("x" * 40)
            ra, rb = fake_release(Path(a) / "T4"), fake_release(long / "T4")
            (ida, lines), (idb, _) = self.ids(ra), self.ids(rb)
            self.assertEqual(ida, idb)
            self.assertIn("CXX_ID=Clang", lines)
            self.assertIn("CXX_VERSION=23.1.3", lines)

    def test_another_program_or_module_is_another_id(self):
        with tempfile.TemporaryDirectory() as a:
            root = fake_release(Path(a) / "T4")
            first, _ = self.ids(root)
            (root / "bin" / "runtime" / "ps2EntryRunner-sse2.exe").write_bytes(b"MZ other")
            second, _ = self.ids(root)
            (root / "runtime" / "tekken4_overrides.cpp").write_text("// changed\n", encoding="utf-8")
            third, _ = self.ids(root)
            self.assertEqual(len({first, second, third}), 3)

    def test_crlf_does_not_change_the_id(self):
        with tempfile.TemporaryDirectory() as a:
            root = fake_release(Path(a) / "T4")
            p = root / "runtime" / "tekken4_overrides.cpp"
            p.write_bytes(b"// module\nline\n")
            first, _ = self.ids(root)
            p.write_bytes(b"// module\r\nline\r\n")
            self.assertEqual(first, self.ids(root)[0])


class GameDllTool(unittest.TestCase):
    def test_batches_are_fixed_and_sorted(self):
        names = [Path(f"f{i:04d}.cpp") for i in range(100)]
        shuffled = list(reversed(names))
        self.assertEqual(build_game_dll.batches(names), build_game_dll.batches(shuffled))
        self.assertEqual(len(build_game_dll.batches(names)), build_game_dll.BATCHES)

    def test_flags_have_no_system_headers_and_no_c_runtime(self):
        for flag in ("/X", "/Zl", "/GS-", "/EHs-c-", "-DPS2X_GAME_DLL_VIEW=1"):
            self.assertIn(flag, build_game_dll.FLAGS)
        self.assertFalse(any("Microsoft" in f or "Windows Kits" in f for f in build_game_dll.FLAGS))

    def test_exports_def_names_the_runtime_module(self):
        text = (HERE / "gamedll" / "ps2_runtime_exports.def").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("NAME ps2EntryRunner.exe"))
        self.assertNotRegex(text, r"(?:FUN_[0-9a-f]{8}|_0x[0-9a-f]{6})")      # never a generated game function

    def test_headers_compile_without_visual_studio(self):
        """The game-DLL headers (tools/gamedll/include) with clang's own headers only: a function in the
        generated code's style compiles with /X (needs a clang-cl, e.g. the release's toolchain)."""
        cl = os.environ.get("T4_TEST_CLANG_CL") or shutil.which("clang-cl") or next(
            (str(p) for p in (ROOT / "toolchain/llvm/bin/clang-cl.exe",) if p.is_file()), None)
        if not cl:
            self.skipTest("no clang-cl here")
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp) / "f.cpp"
            src.write_text('#include <cstdint>\n#include <cstring>\n#include <cmath>\n#include <bit>\n#include <limits>\n'
                           'float f(float a, uint32_t b) { uint32_t c; std::memcpy(&c, &a, 4);'
                           ' return std::sqrt(std::max(0.0f, a)) + std::countl_zero(b ^ c) + std::bit_cast<float>(c)'
                           ' + std::numeric_limits<float>::max() * 0.0f; }\n', encoding="utf-8")
            r = subprocess.run([cl] + build_game_dll.FLAGS[:-1] + ["/FI" + str(HERE / "gamedll/include/t4_dll_prefix.h"),
                                "-I" + str(HERE / "gamedll/include"), "/c", "/Fo" + str(Path(tmp) / "f.obj"), str(src)],
                               capture_output=True, text=True, env={k: v for k, v in os.environ.items() if k.upper() not in ("INCLUDE", "LIB")})
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
