"""Review items 2 and 3 (docs/REVIEW_WISHIN.md): the US PS2Recomp tree rule, and the StrictMode @() in the portable build.

The launcher (launcher/t4core.py), tools/us_tree.cmd and tools/us_tree.ps1 must pick the same tree for the same layout
and never the PAL cousin project's ..\\tekken4-fork-ps2recomp (any branch but t4-us). Builds real throwaway git repos in
a temp folder; no game files, no network.
python -B -m unittest discover -s tools -p test_us_tree.py -v
"""
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("t4core_us_tree_tests", ROOT / "launcher" / "t4core.py")
core = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(core)
GIT = shutil.which("git")
CLEAN_ENV = {k: v for k, v in os.environ.items() if k.upper() != "TEKKEN4_SRC"}


def git(*args, cwd):
    subprocess.run([GIT, *args], cwd=cwd, check=True, capture_output=True, env=CLEAN_ENV)


@unittest.skipUnless(GIT and os.name == "nt", "needs git on Windows")
class UsTreeRuleTests(unittest.TestCase):
    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="t4_us_tree_"))
        self.addCleanup(shutil.rmtree, self.base, ignore_errors=True)
        self.repo = self.base / "tekken4-us"
        (self.repo / "tools").mkdir(parents=True)
        for name in ("us_tree.cmd", "us_tree.ps1", "us_tree.py", "player_common.py", "player_python.ps1"):
            shutil.copy2(ROOT / "tools" / name, self.repo / "tools" / name)
        self.plain = self.base / "tekken4-fork-ps2recomp"
        self.own = self.base / "tekken4-fork-ps2recomp_usa"

    def clone(self, path, branch):
        path.mkdir()
        git("init", "-q", "-b", branch, cwd=path)
        git("-c", "user.name=t", "-c", "user.email=t@localhost", "commit", "-q", "--allow-empty", "-m", "x", cwd=path)

    def via_cmd(self):
        probe = self.base / "probe.cmd"
        probe.write_text(f'@echo off\r\ncall "{self.repo / "tools" / "us_tree.cmd"}" || exit /b 1\r\necho TREE=%TEKKEN4_SRC%\r\n',
                         encoding="ascii")
        r = subprocess.run(["cmd", "/d", "/c", str(probe)], capture_output=True, text=True, env=CLEAN_ENV)
        m = re.search(r"TREE=(.*)", r.stdout)
        return os.path.normcase(os.path.abspath(m.group(1).strip())) if r.returncode == 0 and m else None

    def via_ps1(self):
        cmd = f". '{self.repo / 'tools' / 'us_tree.ps1'}'; Resolve-UsTree '{self.repo}'"
        r = subprocess.run(["powershell", "-NoProfile", "-Command", cmd], capture_output=True, text=True, env=CLEAN_ENV)
        return os.path.normcase(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None

    def via_py(self):
        return os.path.normcase(os.path.abspath(core.us_tree(str(self.repo))))

    def check(self, expected):
        want = os.path.normcase(str(expected))
        self.assertEqual(self.via_py(), want, "launcher/t4core.py")
        self.assertEqual(self.via_ps1(), want, "tools/us_tree.ps1")
        self.assertEqual(self.via_cmd(), want, "tools/us_tree.cmd")

    def test_nothing_there_uses_the_plain_name(self):
        self.check(self.plain)

    def test_plain_tree_on_t4_us(self):
        self.clone(self.plain, "t4-us")
        self.check(self.plain)

    def test_pal_tree_on_plain_name_is_never_taken(self):
        self.clone(self.plain, "gs-gl")  # Pablo's PC: the PAL project's tree
        self.check(self.own)

    def test_own_us_tree_wins(self):
        self.clone(self.plain, "t4-us")
        self.clone(self.own, "t4-us")
        self.check(self.own)

    def test_worktree_branch_is_read(self):
        self.clone(self.base / "main", "master")
        git("worktree", "add", "-q", "-b", "t4-us", str(self.plain), cwd=self.base / "main")
        self.assertEqual(core.git_branch(str(self.plain)), "t4-us")
        self.check(self.plain)


class BuildScriptDefaultTests(unittest.TestCase):
    """No build script may fall back to ..\\tekken4-fork-ps2recomp without the t4-us check."""

    def test_no_unchecked_plain_default(self):
        plain = re.compile(r"""set\s+"SRC=%~dp0\.\.\\\.\.\\tekken4-fork-ps2recomp"|Join-Path \$Root '\.\.\\tekken4-fork-ps2recomp'""", re.I)
        for name in ("build_runtime.cmd", "build_runtime_portable.cmd", "build_ps2recomp_tools.cmd",
                     "build_ps2recomp_tools_portable.cmd", "build_tests.cmd", "build_game.ps1", "build_game_portable.ps1",
                     "net_play.ps1"):
            text = (ROOT / "tools" / name).read_text(encoding="utf-8", errors="replace")
            self.assertIsNone(plain.search(text), name)
            self.assertIn("us_tree", text, name)


class PortableStrictModeTests(unittest.TestCase):
    """Item 3: a Files result whose .Count is read must be wrapped in @() (an empty result is $null under StrictMode)."""

    def test_counted_files_results_are_arrays(self):
        for name in ("build_game.ps1", "build_game_portable.ps1"):
            text = (ROOT / "tools" / name).read_text(encoding="utf-8", errors="replace")
            for m in re.finditer(r"^\s*\$(\w+)\s*=\s*(@\()?\s*Files\b", text, re.M):
                if re.search(r"\$" + m.group(1) + r"\.Count\b", text):
                    self.assertTrue(m.group(2), f"{name}: ${m.group(1)} = Files ... is counted but not wrapped in @()")


if __name__ == "__main__":
    unittest.main()
