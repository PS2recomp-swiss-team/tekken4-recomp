"""Mocked launcher checks for the widescreen setting (docs/WIDESCREEN.md). No processes, game files or network traffic.

python -B -m unittest discover -s tools -p test_launcher_widescreen.py -v
"""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("t4core_widescreen_tests", ROOT / "launcher" / "t4core.py")
core = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(core)


class WidescreenSettingTests(unittest.TestCase):
    def env(self, settings, knows):
        support = {"fullscreen": False, "aa": False, "progressive": False, "widescreen": knows}
        with patch.dict(core.os.environ, {"TEKKEN4_WIDESCREEN": "inherited"}, clear=True), \
                patch.object(core, "effective_iso", return_value="own game.iso"), \
                patch.object(core, "graphics_env_names", return_value={}), \
                patch.object(core, "graphics_support", return_value=support):
            return core.game_env(settings)

    def test_default_is_off(self):
        self.assertIs(core.DEFAULTS["widescreen"], False)
        self.assertEqual("0", self.env(dict(core.DEFAULTS), True)["TEKKEN4_WIDESCREEN"])

    def test_on_and_off_reach_the_game(self):
        for value, expected in ((True, "1"), (False, "0")):
            with self.subTest(value=value):
                self.assertEqual(expected, self.env(dict(core.DEFAULTS, widescreen=value), True)["TEKKEN4_WIDESCREEN"])

    def test_old_build_gets_no_switch_and_no_inherited_value(self):
        env = self.env(dict(core.DEFAULTS, widescreen=True), False)
        self.assertNotIn("TEKKEN4_WIDESCREEN", env)

    def test_support_probe_without_the_key_is_off(self):
        support = {"fullscreen": False, "aa": False, "progressive": False}
        with patch.dict(core.os.environ, {}, clear=True), \
                patch.object(core, "effective_iso", return_value="own game.iso"), \
                patch.object(core, "graphics_env_names", return_value={}), \
                patch.object(core, "graphics_support", return_value=support):
            self.assertNotIn("TEKKEN4_WIDESCREEN", core.game_env(dict(core.DEFAULTS, widescreen=True)))


if __name__ == "__main__":
    unittest.main()
