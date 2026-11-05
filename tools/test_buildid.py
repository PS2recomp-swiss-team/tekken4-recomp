"""Regression tests for CMake compiler identity discovery; no game files or processes.

python -I -B tools/test_buildid.py
All synthetic build metadata is created under ignored logs/buildid-tests.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("t4_buildid_tests_subject", ROOT / "tools/t4_buildid.py")
buildid = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(buildid)


class ToolchainMetadataTests(unittest.TestCase):
    def setUp(self):
        output = ROOT / "logs/buildid-tests"
        output.mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(prefix="cmake-", dir=output)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def build(self, name):
        path = self.root / name
        path.mkdir()
        (path / "CMakeCache.txt").write_text(
            "CMAKE_CACHE_MAJOR_VERSION:INTERNAL=3\n"
            "CMAKE_CACHE_MINOR_VERSION:INTERNAL=31\n"
            "CMAKE_CACHE_PATCH_VERSION:INTERNAL=6\n"
            "CMAKE_BUILD_TYPE:STRING=Release\n"
            "CMAKE_C_FLAGS:STRING= /DWIN32  /D_WINDOWS \n"
            "CMAKE_CXX_FLAGS:STRING=/EHsc\n"
            "CMAKE_C_FLAGS_RELEASE:STRING=/O2\n"
            "CMAKE_CXX_FLAGS_RELEASE:STRING=/O2 /DNDEBUG\n"
            "PS2X_VU1_MICROCODE_DIR:PATH=/synthetic/vu1\n"
            "PS2X_USE_IOP:BOOL=ON\n", encoding="utf-8")
        return path

    def compiler(self, build, folder, *, version="19.44.35214.0", languages=("C", "CXX")):
        path = build / "CMakeFiles" / folder
        path.mkdir(parents=True, exist_ok=True)
        for lang in languages:
            (path / f"CMake{lang}Compiler.cmake").write_text(
                f'set(CMAKE_{lang}_COMPILER_ID "MSVC")\n'
                f'set(CMAKE_{lang}_COMPILER_VERSION "{version}")\n'
                f'set(CMAKE_{lang}_COMPILER_ARCHITECTURE_ID "x64")\n', encoding="utf-8")
        return path

    def test_numeric_and_vendor_suffix_produce_identical_identity(self):
        exact = self.build("exact")
        suffix = self.build("suffix")
        self.compiler(exact, "3.31.6")
        self.compiler(suffix, "3.31.6-msvc6")
        expected = ["C_ID=MSVC", "C_VERSION=19.44.35214.0", "C_ARCHITECTURE_ID=x64",
                    "CXX_ID=MSVC", "CXX_VERSION=19.44.35214.0", "CXX_ARCHITECTURE_ID=x64",
                    "build_type=Release", "CMAKE_C_FLAGS=/DWIN32 /D_WINDOWS", "CMAKE_CXX_FLAGS=/EHsc",
                    "CMAKE_C_FLAGS_RELEASE=/O2", "CMAKE_CXX_FLAGS_RELEASE=/O2 /DNDEBUG",
                    "PS2X_USE_IOP=ON", "vu1_native=1"]
        self.assertEqual(buildid.toolchain(str(exact)), expected)
        self.assertEqual(buildid.toolchain(str(suffix)), expected)

    def test_exact_and_suffix_directories_are_ambiguous(self):
        path = self.build("precedence")
        self.compiler(path, "3.31.6", version="19.44.35214.0")
        self.compiler(path, "3.31.6-msvc6", version="19.43.34808.0")
        with self.assertRaisesRegex(SystemExit, "expected one compiler metadata directory.*found 2"):
            buildid.toolchain(str(path))

    def test_msvc_unquoted_architecture_matches_quoted_identity(self):
        path = self.build("unquoted")
        folder = self.compiler(path, "3.31.6-msvc6")
        quoted = buildid.toolchain(str(path))
        for lang in ("C", "CXX"):
            source = folder / f"CMake{lang}Compiler.cmake"
            source.write_text(source.read_text().replace('"x64"', 'x64'), encoding="utf-8")
        self.assertEqual(buildid.toolchain(str(path)), quoted)

    def test_other_cmake_version_is_not_a_fallback(self):
        path = self.build("wrong-version")
        self.compiler(path, "3.31.7-msvc6")
        with self.assertRaisesRegex(SystemExit, "expected one compiler metadata directory"):
            buildid.toolchain(str(path))

    def test_ambiguous_vendor_suffix_is_refused(self):
        path = self.build("ambiguous")
        self.compiler(path, "3.31.6-msvc5")
        self.compiler(path, "3.31.6-msvc6")
        with self.assertRaisesRegex(SystemExit, "expected one compiler metadata directory"):
            buildid.toolchain(str(path))

    def test_missing_metadata_is_refused(self):
        path = self.build("missing")
        with self.assertRaisesRegex(SystemExit, "cannot read CMake compiler metadata"):
            buildid.toolchain(str(path))

    def test_missing_cxx_compiler_metadata_is_refused(self):
        path = self.build("missing-cxx")
        self.compiler(path, "3.31.6-msvc6", languages=("C",))
        with self.assertRaisesRegex(SystemExit, "cannot read compiler metadata"):
            buildid.toolchain(str(path))

    def test_missing_compiler_version_is_refused(self):
        path = self.build("incomplete")
        folder = self.compiler(path, "3.31.6-msvc6")
        (folder / "CMakeCCompiler.cmake").write_text('set(CMAKE_C_COMPILER_ID "MSVC")\n',
                                                    encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "expected one CMAKE_C_COMPILER_VERSION"):
            buildid.toolchain(str(path))


if __name__ == "__main__":
    unittest.main(verbosity=2)
