"""Synthetic source-mirror guard tests; no game assets or Git writes.

Run from the checkout: python -B -m unittest discover -s tools -p test_publish_source.py -v
Fixtures assemble sensitive-looking strings so this test source can itself be scanned.
"""
from pathlib import Path
from contextlib import contextmanager
import unittest
from unittest.mock import patch
import uuid

import publish_source
import test_zip


ROOT = Path(__file__).resolve().parent.parent


@contextmanager
def retained_fixture(prefix):
    """Keep synthetic test files under excluded logs; the owner decides cleanup."""
    root = ROOT / "logs" / "source-guard-tests" / (prefix + uuid.uuid4().hex)
    root.mkdir(parents=True, exist_ok=False)
    yield str(root)


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
            b"https://git-scm.com/download/win\n"
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

    def test_private_configuration_and_lobby_paths_are_refused_by_scan(self):
        for name in (".mcp.json", "nested/.MCP.JSON", "lobby/service.py", "nested/LOBBY/readme.txt"):
            with self.subTest(name=name):
                self.assert_refused(b"synthetic text only\n", name)

    def test_image_names_and_disguised_image_headers_are_refused_by_scan(self):
        for suffix in ("png", "JPG", "svg", "webp", "tiff"):
            with self.subTest(suffix=suffix):
                self.assert_refused(b"synthetic text only\n", "runtime/picture." + suffix)
        samples = (
            bytes((137,)) + b"PNG\r\n" + bytes((26, 10)),
            b"GIF89a",
            b"<sv" + b"g></svg>",
            b"RIFF" + bytes(4) + b"WEBP",
        )
        for data in samples:
            with self.subTest(header=data[:6]):
                self.assert_refused(data, "renamed.txt")

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

    def test_escaped_relative_source_paths_are_allowed(self):
        value = b'"game' + b"\\\\" + b"disc" + b"\\\\" + b'SLUS_203.28"'
        self.assertEqual([], publish_source.scan_file("example.py", value))

    def test_quoted_unc_paths_are_refused(self):
        value = b'output = "' + b"\\\\" + b'private-host\\share\\project"'
        self.assert_refused(value)

    def test_guest_cd_path_pin_accepts_only_immutable_reviewed_patch(self):
        name = "patches/36-ps2xIOP-cdvd-ioman-search-files-in-the-real-image.patch"
        data = (ROOT / name).read_bytes()
        self.assertEqual([], publish_source.scan_file(name, data))
        personal = ("\n/ho" + "me/" + "example/private\n").encode()
        self.assertIn("personal or machine-specific path", publish_source.scan_file(name, data + personal))
        self.assertIn("personal or machine-specific path", publish_source.scan_file(name, data + b"\n"))

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

    def test_loopback_and_bind_constants_are_allowed(self):
        values = ("127." + "0.0.1", "0." + "0.0.0", "::" + "1", "::")
        for value in values:
            with self.subTest(value=value):
                self.assertEqual([], publish_source.scan_file("example.cpp", value.encode()))

    def test_lan_and_vpn_addresses_remain_refused(self):
        values = ("192." + "168.1.20", "100." + "100.20.30", "10." + "20.30.40")
        for value in values:
            with self.subTest(style=value[:3]):
                self.assert_refused(value.encode())

    def test_findings_do_not_echo_sensitive_values(self):
        secret = b"gh" + b"p_" + b"b" * 36
        reasons = self.assert_refused(secret)
        self.assertNotIn(secret.decode(), "\n".join(reasons))

    def test_tree_scan_checks_fake_files_and_is_read_only(self):
        with retained_fixture("scan-") as work:
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
        with retained_fixture("export-") as work:
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
        with retained_fixture("refused-") as work:
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
        with retained_fixture("invalid-") as work:
            for files, modes in cases:
                with self.subTest(names=[name for name, _ in files]):
                    out = Path(work) / "mirror"
                    with patch.object(publish_source, "_git", side_effect=self.fake_git(files, modes)):
                        with self.assertRaises(ValueError):
                            publish_source.export_ref(ROOT, "reviewed", out)
                    self.assertFalse(out.exists())

    def test_existing_output_is_never_overwritten(self):
        with retained_fixture("existing-") as work:
            out = Path(work)
            existing = out / "keep.txt"
            existing.write_bytes(b"unchanged\n")
            with patch.object(publish_source, "_git") as git:
                with self.assertRaises(ValueError):
                    publish_source.export_ref(ROOT, "reviewed", out)
                git.assert_not_called()
            self.assertEqual(b"unchanged\n", existing.read_bytes())


class TestZipTests(unittest.TestCase):
    def test_scan_preserves_licence_and_source_bytes(self):
        entries = [("LICENSE", b"Synthetic GPL-3.0 notice\n"),
                   ("runtime/example.cpp", b"// Copyright Original Author\nint value = 1;\n")]
        self.assertEqual(entries, test_zip.scan_entries(iter(entries)))

    def test_scan_refuses_private_paths_images_and_personal_content(self):
        samples = (
            (".mcp.json", b"{}\n"),
            ("lobby/example.py", b"# synthetic source\n"),
            ("runtime/example.PNG", b"synthetic text\n"),
            ("runtime/secret.key", b"synthetic text\n"),
            ("runtime/example.txt", ("/ho" + "me/" + "example/private").encode()),
        )
        for name, data in samples:
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    test_zip.scan_entries([("LICENSE", b"Synthetic GPL-3.0\n"), (name, data)])

    def test_scan_refuses_missing_license_duplicates_collisions_and_traversal(self):
        cases = (
            [("README.md", b"Synthetic notes\n")],
            [("LICENSE", b"notice\n"), ("LICENSE", b"notice\n")],
            [("LICENSE", b"notice\n"), ("Runtime/a.cpp", b"int a;\n"), ("runtime/b.cpp", b"int b;\n")],
            [("LICENSE", b"notice\n"), ("../escape.txt", b"text\n")],
        )
        for entries in cases:
            with self.subTest(names=[name for name, _ in entries]):
                with self.assertRaises(ValueError):
                    test_zip.scan_entries(entries)

    def test_scan_failure_does_not_create_output_directory(self):
        with retained_fixture("zip-refused-") as work:
            root = Path(work)
            archive = root / "result" / "test.zip"
            with self.assertRaises(ValueError):
                test_zip.create_zip(root, archive, [("README.md", b"missing licence\n")])
            self.assertFalse(archive.parent.exists())

    def test_output_traversal_is_refused_before_any_write(self):
        entries = [("LICENSE", b"Synthetic GPL-3.0 notice\n")]
        with retained_fixture("zip-traversal-") as work:
            root = Path(work)
            archive = root / "result" / ".." / ".." / "escape.zip"
            with patch.object(Path, "mkdir") as mkdir, patch.object(test_zip.zipfile, "ZipFile") as zip_open:
                with self.assertRaises(ValueError):
                    test_zip.create_zip(root, archive, entries)
                mkdir.assert_not_called()
                zip_open.assert_not_called()
            self.assertFalse((root / "result").exists())

    def test_zip_round_trip_and_existing_output_retained(self):
        entries = [("LICENSE", b"Synthetic GPL-3.0 notice\n"),
                   ("runtime/example.cpp", b"// Copyright Original Author\nint value = 1;\n")]
        with retained_fixture("zip-") as work:
            root = Path(work)
            archive = root / "result" / "test.zip"
            path, count = test_zip.create_zip(root, archive, entries)
            self.assertEqual(archive, path)
            self.assertEqual(len(entries), count)
            before = archive.read_bytes()
            with self.assertRaises(ValueError):
                test_zip.create_zip(root, archive, entries)
            self.assertEqual(before, archive.read_bytes())


if __name__ == "__main__":
    unittest.main()
