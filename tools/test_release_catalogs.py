"""Release catalog checks. No builds, game launches, downloads or Git writes.

Run only in an owner-authorized validation session:
python -B -m unittest discover -s tools -p test_release_catalogs.py -v
"""
import hashlib
from pathlib import Path
import unittest
from unittest.mock import patch

import package_release
import release_payload
import test_zip


ROOT = Path(__file__).resolve().parent.parent


class ReleaseCatalogTests(unittest.TestCase):
    def test_portable_bundle_contains_online_launcher_dependencies(self):
        for name in ("net_play.ps1", "net_preflight.ps1", "collect_test_logs.ps1", "t4_buildid.py"):
            with self.subTest(name=name):
                self.assertIn(name, package_release.TOOLS)

    def test_every_catalog_tool_exists_and_names_are_unique(self):
        for catalog in (package_release.TOOLS, test_zip.TOOLS):
            self.assertEqual(len(catalog), len(set(catalog)))
            for name in catalog:
                with self.subTest(name=name):
                    self.assertTrue((ROOT / "tools" / name).is_file(), name)

    def test_source_fallback_has_instructions_and_no_incomplete_portable_wrapper(self):
        self.assertIn("TEST_ONLINE_DE.txt", test_zip.ROOT_FILES)
        self.assertIn("docs/THIRD_PARTY.md", test_zip.ROOT_FILES)
        self.assertNotIn("make_player_zip.ps1", test_zip.TOOLS)
        for name in ("build_game.ps1", "net_play.ps1", "net_preflight.ps1", "t4_buildid.py"):
            self.assertIn(name, test_zip.TOOLS)
        for name in test_zip.ROOT_FILES:
            with self.subTest(name=name):
                self.assertTrue((ROOT / name).is_file(), name)

    def test_starter_launcher_and_beta_documents_exist(self):
        for name in ("Tekken4.cmd", "launcher/t4core.py", "launcher/t4_launcher.pyw",
                     "docs/BETA_RELEASE_NOTES.md", "docs/KNOWN_ISSUES.md", "docs/BETA_GO_NO_GO.md",
                     "docs/THIRD_PARTY.md"):
            with self.subTest(name=name):
                self.assertTrue((ROOT / name).is_file(), name)


class ReleaseInputTests(unittest.TestCase):
    def test_missing_scan_directory_is_refused(self):
        with patch.object(Path, "is_file", return_value=False), \
                patch.object(Path, "is_dir", return_value=False):
            with self.assertRaisesRegex(ValueError, "existing directory or zip"):
                package_release.scan(ROOT / "missing-release-input")

    def test_missing_input_directory_cannot_match_an_empty_tree_digest(self):
        record = {"path": str(ROOT / "missing-release-input"), "source": "synthetic fixture",
                  "version": "test", "sha256": hashlib.sha256(b"").hexdigest()}
        with patch.object(Path, "is_dir", return_value=False):
            with self.assertRaisesRegex(ValueError, "existing directory"):
                release_payload.checked_input(record, directory=True)


if __name__ == "__main__":
    unittest.main()
