"""Synthetic source-mirror guard tests; no game assets or Git writes.

Run from the checkout: python -B -m unittest discover -s tools -p test_publish_source.py -v
Fixtures assemble sensitive-looking strings so this test source can itself be scanned.
"""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import publish_source


ROOT = Path(__file__).resolve().parent.parent


class ExclusionTests(unittest.TestCase):
    def test_private_and_generated_paths_are_excluded(self):
        for name in (
            "docs/img/readme.txt", "docs/IMG/readme.txt", "lobby/service.py",
            "CLAUDE.md", ".mcp.json", "nested/.mcp.json", "logs/session.txt",
            "generated/translation.cpp", "runtime/__pycache__/helper.pyc",
            "runtime/register_functions.cpp", "runtime/ps2_recompiled_functions.h",
            "runtime/ps2_recompiled_stubs.h", "logs/session.log.1",
        ):
            with self.subTest(name=name):
                self.assertTrue(publish_source.excluded(name))

    def test_images_are_excluded_outside_docs(self):
        for suffix in ("png", "JPG", "jpeg", "gif", "webp", "svg", "ico", "bmp", "tiff"):
            with self.subTest(suffix=suffix):
                self.assertTrue(publish_source.excluded("assets/picture." + suffix))

    def test_license_source_and_credits_are_kept(self):
        for name in ("LICENSE", "README.md", "CREDITS.md", "runtime/handwritten.cpp", "patches/01-example.patch"):
            with self.subTest(name=name):
                self.assertFalse(publish_source.excluded(name))


class ContentScanTests(unittest.TestCase):
    def assert_refused(self, data, name="fixture.txt"):
        reasons = publish_source.scan_file(name, data)
        self.assertTrue(reasons, "guard accepted " + name)
        return reasons

    def test_handwritten_source_and_public_project_links_are_allowed(self):
        data = (
            b"// Copyright Example Author; GPL-3.0\nint main() { return 0; }\n"
            b"https://github.com/TheWishin/Tekken4Recomp-Source\n"
            b"https://github.com/ran-j/PS2Recomp\n"
        )
        self.assertEqual([], publish_source.scan_file("example.cpp", data))

    def test_forbidden_asset_names(self):
        for name in ("disc.ISO", "DATA.BIN", "SLUS_203.28", "dump.elf", "secret.key", "id_rsa"):
            with self.subTest(name=name):
                self.assert_refused(b"synthetic fixture only\n", name)

    def test_disguised_executable_and_disc_signatures(self):
        samples = (
            bytes((127,)) + b"ELF" + bytes(64),
            b"MZ" + bytes(64),
            bytes(0x8001) + b"CD001" + bytes(8),
        )
        for data in samples:
            with self.subTest(magic=data[:4]):
                self.assert_refused(data)

    def test_opaque_binary_is_refused(self):
        self.assert_refused(bytes(range(256)))

    def test_generated_code_renamed_as_handwritten_source(self):
        data = "\n".join("void func_" + format(0x100000 + i, "08x") + "() {}" for i in range(80))
        self.assert_refused(data.encode(), "innocent.cpp")

    def test_archives_cannot_hide_assets(self):
        self.assert_refused(b"PK" + bytes((3, 4)) + bytes(40))

    def test_private_keys_and_tokens(self):
        samples = (
            b"-----BEGIN " + b"PRIVATE KEY-----\nfake\n",
            b"gh" + b"p_" + b"a" * 36,
            b"api_" + b"key = '" + b"a" * 40 + b"'\n",
            b"T4_API_" + b"KEY = '" + b"c" * 40 + b"'\n",
            b"RELEASE_SIGNING_" + b"KEY = '" + b"d" * 64 + b"'\n",
        )
        for data in samples:
            with self.subTest(kind=data[:8]):
                self.assert_refused(data)

    def test_personal_paths(self):
        samples = (
            "C:" + "\\Users\\" + "example\\project",
            "D:" + "\\" + "private-work\\project",
            "/ho" + "me/" + "example/project",
            "/Us" + "ers/" + "example/project",
            "\\\\" + "private-host\\share\\project",
        )
        for value in samples:
            with self.subTest(style=value[:3]):
                self.assert_refused(value.encode())

    def test_server_addresses(self):
        samples = (
            "203." + "0.113.42",
            "[2001:" + "db8::42]:9999",
            "wss" + "://" + "lobby.example.invalid/socket",
            "LOBBY_" + "HOST = '" + "match.example.invalid'",
            "--lob" + "by=" + "match.example.invalid",
            "match.example.invalid" + ":9999",
        )
        for value in samples:
            with self.subTest(style=value[:3]):
                self.assert_refused(value.encode())

    def test_findings_do_not_echo_sensitive_values(self):
        secret = b"gh" + b"p_" + b"b" * 36
        reasons = self.assert_refused(secret)
        self.assertNotIn(secret.decode(), "\n".join(reasons))

    def test_tree_scan_checks_fake_files_and_is_read_only(self):
        with tempfile.TemporaryDirectory(prefix="source-guard-test-", dir=ROOT) as work:
            root = Path(work)
            safe = root / "LICENSE"
            safe.write_text("Synthetic author credit; GPL-3.0\n", encoding="utf-8")
            self.assertEqual([], publish_source.scan_tree(root))
            bad = root / "fixture.txt"
            data = ("/ho" + "me/" + "example/project").encode()
            bad.write_bytes(data)
            findings = publish_source.scan_tree(root)
            self.assertTrue(findings)
            self.assertTrue(any("fixture.txt" in finding for finding in findings))
            self.assertEqual(data, bad.read_bytes())
            self.assertEqual("Synthetic author credit; GPL-3.0\n", safe.read_text(encoding="utf-8"))


class ExportTests(unittest.TestCase):
    def fake_git(self, files, modes=None):
        """A Git object reader double; never initialize or write a repository."""
        modes = modes or {}
        objects = {format(i + 1, "040x"): data for i, (_, data) in enumerate(files)}
        tree = b"".join(
            (modes.get(name, "100644") + " blob " + format(i + 1, "040x") + "\t" + name).encode() + b"\0"
            for i, (name, _) in enumerate(files)
        )

        def read(repo, *args):
            if args[0] == "rev-parse":
                self.assertEqual(("rev-parse", "--verify", "--end-of-options", "reviewed^{commit}"), args)
                return b"a" * 40 + b"\n"
            if args[0] == "ls-tree":
                self.assertEqual(("ls-tree", "-r", "-z", "--full-tree", "a" * 40), args)
                return tree
            if args[:2] == ("cat-file", "-s"):
                return str(len(objects[args[2]])).encode()
            if args[:2] == ("cat-file", "blob"):
                return objects[args[2]]
            self.fail("unexpected Git operation: " + args[0])

        return read

    def test_export_keeps_license_and_author_bytes_and_omits_private_files(self):
        license_data = b"Synthetic GPL-3.0 licence text\n"
        source_data = b"// Copyright Original Author\nint value = 1;\n"
        files = [
            ("LICENSE", license_data), ("runtime/example.cpp", source_data),
            ("CREDITS.md", b"Original Author\n"), ("docs/img/note.txt", b"omit\n"),
            ("lobby/service.py", b"omit\n"), ("CLAUDE.md", b"omit\n"),
            ("assets/picture.PNG", b"fake image\n"),
            ("assets/renamed.txt", bytes((137,)) + b"PNG\r\n" + bytes((26, 10))),
        ]
        with tempfile.TemporaryDirectory(prefix="source-export-test-", dir=ROOT) as work:
            out = Path(work) / "mirror"
            with patch.object(publish_source, "_git", side_effect=self.fake_git(files)):
                commit, count = publish_source.export_ref(ROOT, "reviewed", out)
            self.assertEqual("a" * 40, commit)
            self.assertEqual(3, count)
            self.assertEqual(license_data, (out / "LICENSE").read_bytes())
            self.assertEqual(source_data, (out / "runtime/example.cpp").read_bytes())
            self.assertEqual({"LICENSE", "runtime/example.cpp", "CREDITS.md"},
                             {p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file()})

    def test_scan_failure_writes_nothing(self):
        files = [("LICENSE", b"Synthetic GPL-3.0\n"),
                 ("note.txt", ("/ho" + "me/" + "example/private").encode())]
        with tempfile.TemporaryDirectory(prefix="source-export-test-", dir=ROOT) as work:
            out = Path(work) / "mirror"
            with patch.object(publish_source, "_git", side_effect=self.fake_git(files)):
                with self.assertRaises(ValueError):
                    publish_source.export_ref(ROOT, "reviewed", out)
            self.assertFalse(out.exists())

    def test_missing_license_links_and_unsafe_paths_are_refused(self):
        cases = (
            ([("README.md", b"Synthetic notes\n")], {}),
            ([("LICENSE", b"Synthetic GPL-3.0\n"), ("link", b"destination")], {"link": "120000"}),
            ([("LICENSE", b"Synthetic GPL-3.0\n"), ("../escape.txt", b"no\n")], {}),
            ([("LICENSE", b"Synthetic GPL-3.0\n"), ("Readme.md", b"a\n"), ("README.md", b"b\n")], {}),
        )
        with tempfile.TemporaryDirectory(prefix="source-export-test-", dir=ROOT) as work:
            for files, modes in cases:
                with self.subTest(names=[name for name, _ in files]):
                    out = Path(work) / "mirror"
                    with patch.object(publish_source, "_git", side_effect=self.fake_git(files, modes)):
                        with self.assertRaises(ValueError):
                            publish_source.export_ref(ROOT, "reviewed", out)
                    self.assertFalse(out.exists())

    def test_existing_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory(prefix="source-export-test-", dir=ROOT) as work:
            out = Path(work)
            existing = out / "keep.txt"
            existing.write_bytes(b"unchanged\n")
            with patch.object(publish_source, "_git") as git:
                with self.assertRaises(ValueError):
                    publish_source.export_ref(ROOT, "reviewed", out)
                git.assert_not_called()
            self.assertEqual(b"unchanged\n", existing.read_bytes())


if __name__ == "__main__":
    unittest.main()
