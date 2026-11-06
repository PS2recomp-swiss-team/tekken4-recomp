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


class GameFilesRecord(unittest.TestCase):
    def test_the_record_holds_each_files_sha256_and_reuses_matching_entries(self):
        import hashlib
        import json
        with tempfile.TemporaryDirectory() as temp:
            disc = Path(temp) / "disc"
            (disc / "TEKKEN").mkdir(parents=True)
            (disc / "IRX").mkdir()
            for name, data in (("SLUS_203.28", b"elf"), ("TEKKEN/DATA.BIN", b"data"), ("IRX/IOPRP243.IMG", b"irx")):
                (disc / name).write_bytes(data)
            record = Path(temp) / "t4-game-files.json"
            build_game.write_game_files(disc, record)
            files = json.loads(record.read_text(encoding="utf-8"))["files"]
            self.assertEqual(files["TEKKEN/DATA.BIN"]["sha256"], hashlib.sha256(b"data").hexdigest())
            # a matching entry is reused (no read); a changed file gets a new hash
            files["SLUS_203.28"]["sha256"] = "f" * 64
            record.write_text(json.dumps(dict(schema=1, files=files)), encoding="utf-8")
            build_game.write_game_files(disc, record)
            self.assertEqual(json.loads(record.read_text(encoding="utf-8"))["files"]["SLUS_203.28"]["sha256"], "f" * 64)
            os.utime(disc / "SLUS_203.28", ns=(7, 7))
            build_game.write_game_files(disc, record)
            self.assertEqual(json.loads(record.read_text(encoding="utf-8"))["files"]["SLUS_203.28"]["sha256"],
                             hashlib.sha256(b"elf").hexdigest())


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


class DeveloperShell(unittest.TestCase):
    """A developer PC: an "x64 Native Tools" prompt of VS 2022 or a VS 2026 developer shell (vcvars64's variables)."""

    VCVARS = {
        "VSINSTALLDIR": r"C:\Program Files\Microsoft Visual Studio\18\Community" "\\",
        "VCINSTALLDIR": r"C:\Program Files\Microsoft Visual Studio\18\Community\VC" "\\",
        "VCToolsInstallDir": r"C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36000" "\\",
        "VCToolsVersion": "14.51.36000", "WindowsSdkDir": r"C:\Program Files (x86)\Windows Kits\10" "\\",
        "UniversalCRTSdkDir": r"C:\Program Files (x86)\Windows Kits\10" "\\", "UCRTVersion": "10.0.26100.0",
        "WindowsSDKVersion": "10.0.26100.0\\", "WindowsLibPath": r"C:\Program Files (x86)\Windows Kits\10\UnionMetadata",
        "INCLUDE": r"C:\VS\include", "EXTERNAL_INCLUDE": r"C:\VS\include", "LIB": r"C:\VS\lib", "LIBPATH": r"C:\VS\lib",
        "Platform": "x64", "CommandPromptType": "Native", "VSCMD_ARG_TGT_ARCH": "x64", "VSCMD_VER": "18.0.0",
        "__VSCMD_PREINIT_PATH": r"C:\Windows", "DevEnvDir": r"C:\VS\Common7\IDE" "\\", "IFCPATH": r"C:\VS\ifc",
        "VCPKG_ROOT": r"C:\VS\vcpkg", "VisualStudioVersion": "18.0", "FrameworkDir": r"C:\Windows\Microsoft.NET",
        "CL": "/DFAKE", "_CL_": "/DFAKE2", "LINK": "/FAKE", "_LINK_": "/FAKE2", "CCC_OVERRIDE_OPTIONS": "#^-DFAKE",
        "CPATH": r"C:\fake", "PYTHONPATH": r"C:\py", "PYTHONHOME": r"C:\py", "CMAKE_GENERATOR": "Visual Studio 18 2026",
        "ProgramFiles": r"C:\Program Files", "ProgramFiles(x86)": r"C:\Program Files (x86)",
        "PATH": r"C:\VS\VC\Tools\MSVC\14.51.36000\bin\Hostx64\x64;C:\Program Files\Git\cmd;C:\Python313",
        "SystemRoot": r"C:\Windows", "TEMP": r"C:\t", "LOCALAPPDATA": r"C:\Users\x\AppData\Local",
        "OPENRECOMP_HOME": r"C:\h", "NUMBER_OF_PROCESSORS": "8",
    }

    def test_only_windows_and_the_users_folders_are_kept(self):
        env = build_game.release_environment(self.VCVARS)
        self.assertEqual(set(env), {"PATH", "SystemRoot", "TEMP", "LOCALAPPDATA", "OPENRECOMP_HOME", "NUMBER_OF_PROCESSORS"})
        self.assertEqual(env["PATH"].split(os.pathsep), [r"C:\Windows\System32", r"C:\Windows", r"C:\Windows\System32\Wbem"])
        for key in build_game.RELEASE_DROP:
            self.assertNotIn(key.upper(), {k.upper() for k in env}, key)

    def test_the_build_points_clang_at_the_fetched_sysroot_and_pins_msc_ver(self):
        from unittest import mock
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "T4"
            fake_release(root)
            (root / "toolchain").mkdir()
            (root / "toolchain" / "toolchain.json").write_text("{}", encoding="utf-8")
            args = build_game.parser().parse_args(["-Steps", "prereq"])
            with mock.patch.dict(os.environ, self.VCVARS, clear=True), mock.patch.dict(os.environ, T4_MSVC_CACHE=temp):
                build = build_game.Build(args, root)
            try:
                with mock.patch.object(build, "python", return_value=0):
                    build.compiler_environment()
            finally:
                build.log.close()
            sysroot = fetch_msvc_sysroot.sysroot_dir(root, env=dict(T4_MSVC_CACHE=temp))
            self.assertEqual(build.env["VCToolsInstallDir"], str(sysroot / "msvc") + os.sep)
            self.assertNotIn("Microsoft Visual Studio", build.env["INCLUDE"] + build.env["LIB"] + build.env["PATH"])
            self.assertNotIn("CL", build.env)
        cmake = (Path(__file__).resolve().parent / "t4_toolchain_clangcl.cmake").read_text(encoding="utf-8")
        self.assertIn('set(T4_MSC_VERSION "19.44.35229")', cmake)
        for lang in ("C", "CXX"):
            self.assertIn(f'string(APPEND CMAKE_{lang}_FLAGS_INIT " -fms-compatibility-version=${{T4_MSC_VERSION}}")', cmake)


class DiscBesideCompiler(unittest.TestCase):
    """0.1.3: verify + extract (disk) run beside prereq/fork/tools (network, CPU); recomp waits for both."""

    def build(self, temp, **steps):
        import threading
        import time as clock
        root = Path(temp) / "T4"
        (root / "toolchain").mkdir(parents=True)
        (root / "toolchain" / "toolchain.json").write_text("{}", encoding="utf-8")
        iso = Path(temp) / "t4.iso"
        iso.write_bytes(b"x")
        args = build_game.parser().parse_args(["-Iso", str(iso), "-Steps", "prereq,verify,extract,fork"])
        build = build_game.Build(args, root)
        seen = []

        def step(name, seconds=0.0, fail=False):
            def run():
                seen.append((name, threading.current_thread().name, clock.monotonic()))
                clock.sleep(seconds)
                if fail:
                    raise ValueError(name + " broke")
                return name + " done"
            return run
        for name in ("prereq", "verify", "extract", "fork"):
            setattr(build, name, step(name, **steps.get(name, {})))
        return build, seen

    def test_the_disc_runs_on_its_own_thread_during_prereq(self):
        with tempfile.TemporaryDirectory() as temp:
            build, seen = self.build(temp, prereq=dict(seconds=0.4))
            self.assertEqual(build.execute(), 0)
            threads = {name: thread for name, thread, _t in seen}
            self.assertEqual(threads["verify"], "disc")
            self.assertEqual(threads["extract"], "disc")
            self.assertNotEqual(threads["prereq"], "disc")
            start = {name: t for name, _thread, t in seen}
            self.assertLess(start["extract"], start["prereq"] + 0.4)      # began before prereq was over
            text = (Path(temp) / "T4" / "logs" / "build_game.log").read_text(encoding="utf-8")
            self.assertIn("verify done", text)
            self.assertIn("extract done", text)

    def test_a_disc_error_stops_the_build_at_its_step(self):
        with tempfile.TemporaryDirectory() as temp:
            build, seen = self.build(temp, verify=dict(fail=True))
            self.assertEqual(build.execute(), 1)
            text = (Path(temp) / "T4" / "logs" / "build_game.log").read_text(encoding="utf-8")
            self.assertIn("FAILED at step 'verify': verify broke", text)
            self.assertNotIn("fork", [name for name, _thread, _t in seen])

    def test_a_dry_run_or_a_source_checkout_keeps_the_old_order(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "T4"
            root.mkdir()
            iso = Path(temp) / "t4.iso"
            iso.write_bytes(b"x")
            build = build_game.Build(build_game.parser().parse_args(["-Iso", str(iso)]), root)
            try:
                build._disc_start()
                self.assertIsNone(build._disc)                    # not portable
            finally:
                build.log.close()


class SysrootPaths(unittest.TestCase):
    def test_cache_names_stay_short_and_a_damaged_download_is_fetched_again(self):
        import hashlib
        import io
        from unittest import mock
        data = b"the real payload"
        payload = dict(url="https://download.visualstudio.microsoft.com/x/Windows%20SDK.msi", size=len(data),
                       sha256=hashlib.sha256(data).hexdigest(),
                       fileName="Installers\\Windows SDK for Windows Store Apps Headers OnecoreUap-x86_en-us.msi")

        class Response(io.BytesIO):
            def geturl(self):
                return payload["url"]

        with tempfile.TemporaryDirectory() as temp:
            cache = Path(temp)
            target = cache / (payload["sha256"][:20] + ".msi")
            target.write_bytes(b"x")                                 # damaged (antivirus, disk)
            with mock.patch.object(fetch_msvc_sysroot.urllib.request, "urlopen", lambda *a, **k: Response(data)):
                progress = dict(done=0, total=len(data))
                self.assertEqual(fetch_msvc_sysroot.fetch(payload, cache, progress), target)
            self.assertEqual(target.read_bytes(), data)
            self.assertEqual(progress["done"], len(data))
            self.assertEqual(len(list(cache.glob("*.bad-*"))), 1)    # kept aside, never deleted
            self.assertLessEqual(len(target.name), 24)
            # found under its short name and checked: no download
            with mock.patch.object(fetch_msvc_sysroot.urllib.request, "urlopen", side_effect=AssertionError("network")):
                self.assertEqual(fetch_msvc_sysroot.fetch(payload, cache), target)


def fake_release(root):
    """A release folder with an owner-reviewed lock and licence texts."""
    import hashlib
    import json
    (root / "LICENSES").mkdir(parents=True)
    (root / "tools").mkdir()
    terms = {}
    for name in ("microsoft-build-tools", "microsoft-windows-sdk"):
        text = root / "LICENSES" / (name + ".txt")
        text.write_text("terms " + name, encoding="utf-8")
        terms[name] = dict(path="LICENSES/" + name + ".txt", sha256=hashlib.sha256(text.read_bytes()).hexdigest(),
                           url="https://learn.microsoft.com/x")
    lock = root / "tools" / "msvc_sysroot.lock.json"
    lock.write_text(json.dumps(dict(schema=1, architecture="x64", licenses=fetch_msvc_sysroot.LICENSES,
                                    license_reviewed=True, license_terms=terms, crt_version="14.44", sdk_version="10.0",
                                    payloads=[])), encoding="utf-8")
    return lock


def fake_sysroot(folder, lock):
    import hashlib
    import json
    inventory = {}
    for relative in fetch_msvc_sysroot.REQUIRED + ("msvc/include/extra.h",):
        path = folder / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(relative.encode())
        inventory[relative] = hashlib.sha256(relative.encode()).hexdigest()
    (folder / "sysroot.json").write_text(json.dumps(dict(schema=1, lock_sha256=fetch_msvc_sysroot.sha256(lock),
                                                         license_accepted=True, files=inventory)), encoding="utf-8")


class SharedSysroot(unittest.TestCase):
    """0.1.3: Microsoft's files are downloaded and verified once per PC, for every install and update."""

    def test_one_folder_per_lock_in_the_shared_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "T4"
            lock = fake_release(root)
            name = "msvc-" + fetch_msvc_sysroot.sha256(lock)[:16]
            local = Path(r"C:\Users\x\AppData\Local")
            self.assertEqual(fetch_msvc_sysroot.sysroot_dir(root, env=dict(LOCALAPPDATA=str(local))),
                             local / "OpenRecomp" / "cache" / name)
            self.assertEqual(fetch_msvc_sysroot.sysroot_dir(root, env=dict(LOCALAPPDATA=str(local), OPENRECOMP_HOME=r"E:\h")),
                             Path(r"E:\h") / "cache" / name)
            self.assertEqual(fetch_msvc_sysroot.sysroot_dir(root, env=dict(T4_MSVC_CACHE=r"E:\c", OPENRECOMP_HOME=r"E:\h")),
                             Path(r"E:\c") / name)
            self.assertEqual(fetch_msvc_sysroot.sysroot_dir(root, env={}), root / "toolchain")
            # a sysroot an earlier 0.1.3 test build put into the folder stays in use
            fake_sysroot(root / "toolchain", lock)
            self.assertEqual(fetch_msvc_sysroot.sysroot_dir(root, env=dict(LOCALAPPDATA=str(local))), root / "toolchain")

    def test_the_launchers_rule_is_the_same(self):
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "launcher"))
        try:
            import t4core
        finally:
            sys.path.pop(0)
        root = Path(t4core.ROOT)
        for env in (dict(LOCALAPPDATA=r"C:\L"), dict(OPENRECOMP_HOME=r"E:\h", LOCALAPPDATA=r"C:\L"), dict(T4_MSVC_CACHE=r"E:\c")):
            self.assertEqual(Path(t4core.sysroot_dir(env)), fetch_msvc_sysroot.sysroot_dir(root, env=env))

    def test_each_file_is_hashed_once_and_again_only_when_it_changed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "T4"
            lock = fake_release(root)
            sysroot = Path(temp) / "cache" / "msvc-x"
            fake_sysroot(sysroot, lock)
            count = len(fetch_msvc_sysroot.REQUIRED) + 1
            self.assertEqual(fetch_msvc_sysroot.check(root, lock, sysroot)["_hashed"], count)
            self.assertEqual(fetch_msvc_sysroot.check(root, lock, sysroot)["_hashed"], 0)     # stamp: no hashing
            header = sysroot / "msvc/include/extra.h"
            os.utime(header, ns=(1, 1))
            self.assertEqual(fetch_msvc_sysroot.check(root, lock, sysroot)["_hashed"], 1)
            header.write_bytes(b"changed!!!!!!!!!!!!!!!!")
            with self.assertRaisesRegex(ValueError, "integrity"):
                fetch_msvc_sysroot.check(root, lock, sysroot)
            header.unlink()
            with self.assertRaisesRegex(ValueError, "integrity"):
                fetch_msvc_sysroot.check(root, lock, sysroot)

    def test_a_second_install_or_update_uses_the_cache_without_network(self):
        from unittest import mock
        with tempfile.TemporaryDirectory() as temp:
            cache = Path(temp) / "cache"
            first, second = Path(temp) / "a" / "T4", Path(temp) / "an update" / "T4"
            lock = fake_release(first)
            fake_release(second)
            sysroot = fetch_msvc_sysroot.sysroot_dir(first, env=dict(T4_MSVC_CACHE=str(cache)))
            self.assertEqual(sysroot, fetch_msvc_sysroot.sysroot_dir(second, env=dict(T4_MSVC_CACHE=str(cache))))
            fake_sysroot(sysroot, lock)
            with mock.patch.object(fetch_msvc_sysroot.urllib.request, "urlopen", side_effect=AssertionError("network")), \
                    mock.patch.dict(os.environ, T4_MSVC_CACHE=str(cache)):
                self.assertEqual(fetch_msvc_sysroot.install(second, second / "tools" / "msvc_sysroot.lock.json"), sysroot)
            self.assertFalse((second / "toolchain").exists())          # nothing copied into the install

    def test_an_old_launcher_hears_that_it_must_update_first(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "T4"
            lock = fake_release(root)
            with self.assertRaisesRegex(ValueError, "needs OpenRecomp-FGC 0.1.3 or newer"):
                fetch_msvc_sysroot.check(root, lock, Path(temp) / "cache" / "msvc-x")

    def test_build_game_compiles_against_the_shared_sysroot(self):
        from unittest import mock
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "T4"
            lock = fake_release(root)
            (root / "toolchain").mkdir()
            (root / "toolchain" / "toolchain.json").write_text("{}", encoding="utf-8")
            cache = Path(temp) / "cache"
            args = build_game.parser().parse_args(["-Steps", "prereq"])
            with mock.patch.dict(os.environ, T4_MSVC_CACHE=str(cache)):
                build = build_game.Build(args, root)
            try:
                with mock.patch.object(build, "python", return_value=0):
                    build.compiler_environment()
            finally:
                build.log.close()
            sysroot = cache / ("msvc-" + fetch_msvc_sysroot.sha256(lock)[:16])
            self.assertEqual(build.env["INCLUDE"].split(";")[0], str(sysroot / "msvc/include"))
            self.assertIn(str(sysroot / "winsdk/lib/um/x64"), build.env["LIB"].split(";"))


class ExtractHashesOnce(unittest.TestCase):
    def test_the_sha256_from_the_extraction_is_used(self):
        import json
        from unittest import mock
        with tempfile.TemporaryDirectory() as temp:
            disc = Path(temp) / "disc"
            (disc / "TEKKEN").mkdir(parents=True)
            (disc / "TEKKEN" / "DATA.BIN").write_bytes(b"data")
            record = Path(temp) / "r.json"
            with mock.patch.object(build_game, "digest", side_effect=AssertionError("read again")):
                build_game.write_game_files(disc, record, {"TEKKEN/DATA.BIN": "a" * 64})
            self.assertEqual(json.loads(record.read_text(encoding="utf-8"))["files"]["TEKKEN/DATA.BIN"]["sha256"], "a" * 64)


if __name__ == "__main__":
    unittest.main()
