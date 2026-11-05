"""Source-level checks of the netplay movie guard (docs/MOVIE_ROLLBACK_T4.md): rollback only in the online VS flow."""
import re
import unittest
from pathlib import Path

SRC = (Path(__file__).resolve().parent.parent / "runtime" / "tekken4_rollback_overrides.cpp").read_text(encoding="utf-8-sig")


class MovieGuardSource(unittest.TestCase):
    def test_flow_scenes_are_vs_select_and_vs_fight_only(self):
        body = re.search(r"bool avOnlineFlowScene\(.*?\n    }", SRC, re.S).group(0)
        self.assertIn("kAvGameTypeVs", body)
        self.assertIn("kAvSceneSelect", body)
        self.assertIn("kAvSceneFight", body)
        self.assertEqual(len(re.findall(r"kAvScene\w+", body)), 2)
        self.assertIn("kAvSceneFight = 4u", SRC)
        self.assertIn("kAvSceneSelect = 7u", SRC)

    def test_lockstep_decision_uses_the_guard_on_live_boundaries(self):
        self.assertIn("const bool lockstep = npLockstepAt(f);", SRC)
        self.assertRegex(SRC, r"if \(!g_np\.movieGuard \|\| g_np\.resim")
        self.assertIn("f >= g_np.guardFrom && f < g_np.guardUntil", SRC)

    def test_switch_defaults_on_and_is_documented(self):
        self.assertIn("bool movieGuard = true;", SRC)
        self.assertIn("TEKKEN4_NET_MOVIE_GUARD", SRC)


if __name__ == "__main__":
    unittest.main()
