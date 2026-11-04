"""Build identity metadata checks using synthetic CMake outputs; no builds or network."""
from pathlib import Path
import tempfile
import unittest

import t4_buildid


class CompilerMetadataTests(unittest.TestCase):
    def fixture(self, root, version="3.31.6", quoted=True):
        root = Path(root)
        root.mkdir(parents=True, exist_ok=True)
        (root / "CMakeCache.txt").write_text(
            "CMAKE_CACHE_MAJOR_VERSION:INTERNAL=3\n"
            "CMAKE_CACHE_MINOR_VERSION:INTERNAL=31\n"
            "CMAKE_CACHE_PATCH_VERSION:INTERNAL=6\n"
            "CMAKE_BUILD_TYPE:STRING=RelWithDebInfo\n"
            "CMAKE_CXX_FLAGS_RELWITHDEBINFO:STRING=/Z7 /O2 /Ob2 /DNDEBUG\n"
            "PS2X_SIMD_BASELINE:BOOL=OFF\n", encoding="utf-8")
        metadata = root / "CMakeFiles" / version
        metadata.mkdir(parents=True, exist_ok=True)
        for language in ("C", "CXX"):
            fields = {"ID": "MSVC", "VERSION": "19.44.35229.0", "ARCHITECTURE_ID": "x64"}
            lines = []
            for key, value in fields.items():
                scalar = '"' + value + '"' if quoted or key != "ARCHITECTURE_ID" else value
                lines.append(f"set(CMAKE_{language}_COMPILER_{key} {scalar})")
            (metadata / f"CMake{language}Compiler.cmake").write_text("\n".join(lines) + "\n", encoding="utf-8")
        return metadata

    def test_visual_studio_suffix_and_unquoted_architecture_keep_same_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            plain, visual_studio = Path(temp) / "plain", Path(temp) / "vendor"
            self.fixture(plain)
            self.fixture(visual_studio, "3.31.6-msvc6", quoted=False)
            expected = t4_buildid.toolchain(plain)
            self.assertEqual(t4_buildid.toolchain(visual_studio), expected)
            self.assertEqual(expected[:6], ["C_ID=MSVC", "C_VERSION=19.44.35229.0", "C_ARCHITECTURE_ID=x64",
                                           "CXX_ID=MSVC", "CXX_VERSION=19.44.35229.0", "CXX_ARCHITECTURE_ID=x64"])
            self.assertFalse(any("msvc6" in line for line in expected))

    def test_other_cmake_versions_are_not_candidates(self):
        with tempfile.TemporaryDirectory() as temp:
            metadata = self.fixture(temp, "3.31.6-msvc6")
            for other in ("3.31.60", "3.31.7-msvc6", "pkgRedirects"):
                (metadata.parent / other).mkdir()
            self.assertIn("C_ID=MSVC", t4_buildid.toolchain(temp))

    def test_ambiguous_exact_and_vendor_directories_fail_closed(self):
        for extra in ("3.31.6", "3.31.6-other"):
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as temp:
                metadata = self.fixture(temp, "3.31.6-msvc6")
                (metadata.parent / extra).mkdir()
                with self.assertRaisesRegex(SystemExit, "expected one compiler metadata directory.*found 2"):
                    t4_buildid.toolchain(temp)

    def test_missing_matching_directory_and_incomplete_language_fail_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            metadata = self.fixture(temp, "3.31.7")
            with self.assertRaisesRegex(SystemExit, "expected one compiler metadata directory.*found 0"):
                t4_buildid.toolchain(temp)
            metadata.rename(metadata.with_name("3.31.6-msvc6"))
            (metadata.with_name("3.31.6-msvc6") / "CMakeCXXCompiler.cmake").unlink()
            with self.assertRaisesRegex(SystemExit, "cannot read compiler metadata"):
                t4_buildid.toolchain(temp)

    def test_missing_or_pathlike_cache_version_fails_closed(self):
        for cache in ("", "CMAKE_CACHE_MAJOR_VERSION:INTERNAL=../outside\n"):
            with self.subTest(cache=cache), tempfile.TemporaryDirectory() as temp:
                self.fixture(temp)
                (Path(temp) / "CMakeCache.txt").write_text(cache, encoding="utf-8")
                with self.assertRaisesRegex(SystemExit, "invalid or missing CMake cache version"):
                    t4_buildid.toolchain(temp)

    def test_missing_duplicate_and_nonliteral_compiler_fields_fail_closed(self):
        invalid = ("", "set(CMAKE_C_COMPILER_ID MSVC)\nset(CMAKE_C_COMPILER_ID MSVC)\n",
                   "set(CMAKE_C_COMPILER_ID MSVC GNU)\n", 'set(CMAKE_C_COMPILER_ID "${OTHER}")\n',
                   'set(CMAKE_C_COMPILER_ID "MSVC;GNU")\n', 'set(CMAKE_C_COMPILER_ID "")\n')
        for declaration in invalid:
            with self.subTest(declaration=declaration), tempfile.TemporaryDirectory() as temp:
                metadata = self.fixture(temp)
                compiler = metadata / "CMakeCCompiler.cmake"
                rest = "\n".join(compiler.read_text().splitlines()[1:])
                compiler.write_text(declaration + rest + "\n", encoding="utf-8")
                with self.assertRaises(SystemExit):
                    t4_buildid.toolchain(temp)

    def test_unquoted_scalar_fields_and_whitespace_are_supported(self):
        with tempfile.TemporaryDirectory() as temp:
            metadata = self.fixture(temp)
            for language in ("C", "CXX"):
                compiler = metadata / f"CMake{language}Compiler.cmake"
                compiler.write_text(f"SET ( CMAKE_{language}_COMPILER_ID Clang ) # compiler\n"
                                    f"set(CMAKE_{language}_COMPILER_VERSION 21.1.0)\n"
                                    f"set(CMAKE_{language}_COMPILER_ARCHITECTURE_ID ARM64)\n", encoding="utf-8")
            self.assertEqual(t4_buildid.toolchain(temp)[:3],
                             ["C_ID=Clang", "C_VERSION=21.1.0", "C_ARCHITECTURE_ID=ARM64"])

    def test_simd_baseline_remains_excluded_from_toolchain_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            self.fixture(temp)
            before = t4_buildid.toolchain(temp)
            cache = Path(temp) / "CMakeCache.txt"
            cache.write_text(cache.read_text().replace("PS2X_SIMD_BASELINE:BOOL=OFF", "PS2X_SIMD_BASELINE:BOOL=ON"))
            self.assertEqual(before, t4_buildid.toolchain(temp))


class NativeNameIdentityTests(unittest.TestCase):
    def test_staged_native_name_header_changes_code_identity(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            runner = source / "ps2xRuntime/src/runner"
            runner.mkdir(parents=True)
            (source / ".t4-vendored.json").write_text('{"head":"synthetic"}\n')
            header = runner / "tekken4_native_names.h"
            with patch.object(t4_buildid, "ROOT", str(root)):
                before = t4_buildid.code_id(str(source), ["CXX_ID=MSVC"])
                header.write_text("synthetic native-name implementation v1\n")
                first = t4_buildid.code_id(str(source), ["CXX_ID=MSVC"])
                header.write_text("synthetic native-name implementation v2\n")
                second = t4_buildid.code_id(str(source), ["CXX_ID=MSVC"])
            self.assertNotEqual(before, first)
            self.assertNotEqual(first, second)


if __name__ == "__main__":
    unittest.main()
