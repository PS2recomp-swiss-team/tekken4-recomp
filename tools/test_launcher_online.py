"""Mocked launcher online checks. No processes, game files or network traffic.

Run only in an owner-authorized validation session:
python -B -m unittest discover -s tools -p test_launcher_online.py -v
"""
from contextlib import ExitStack
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import mock_open, patch


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("t4core_online_tests", ROOT / "launcher" / "t4core.py")
core = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(core)


class OnlineCommandTests(unittest.TestCase):
    def ready(self, runtime=None):
        stack = ExitStack()
        self.addCleanup(stack.close)
        runtime = runtime or os.path.join(core.ROOT, "deps", "ps2recomp", "out", "runtime", "ps2xRuntime", "ps2EntryRunner.exe")
        stack.enter_context(patch.object(core, "find_runtime", return_value=(runtime, "selected")))
        stack.enter_context(patch.object(core, "play_problems", return_value=[]))
        stack.enter_context(patch.object(core, "effective_iso", return_value="own game.iso"))
        stack.enter_context(patch.object(core.os.path, "isfile", return_value=True))
        return runtime

    def test_host_and_join_use_selected_build_and_mandatory_preflight(self):
        self.ready()
        for role in ("host", "join"):
            with self.subTest(role=role):
                command = core.online_command({}, role, "127.0.0.1", 7401)
                self.assertEqual("powershell.exe", command[0])
                self.assertIn("-NoProfile", command)
                self.assertIn("-NonInteractive", command)
                self.assertEqual("own game.iso", command[command.index("-Iso") + 1])
                self.assertEqual("7401", command[command.index("-Port") + 1])
                self.assertEqual("runtime", command[command.index("-BuildDir") + 1])
                self.assertEqual("auto", command[command.index("-Delay") + 1])
                self.assertEqual("1", command[command.index("-Sound") + 1])
                self.assertNotIn("-SkipPreflight", command)
                self.assertEqual(["-Host"] if role == "host" else ["-Join", "127.0.0.1"], command[-1:] if role == "host" else command[-2:])

    def test_auto_vs_is_default_and_can_be_turned_off(self):
        self.ready()
        self.assertTrue(core.DEFAULTS["auto_vs"])
        self.assertNotIn("-NoAutoVs", core.online_command({}, "host"))
        self.assertNotIn("-NoAutoVs", core.online_command({"auto_vs": True}, "host"))
        command = core.online_command({"auto_vs": False}, "join", "127.0.0.1")
        self.assertIn("-NoAutoVs", command)
        self.assertEqual(["-Join", "127.0.0.1"], command[-2:])

    def test_invalid_role_port_and_peer_fail_before_play_checks(self):
        cases = (("lobby", "", 7400), ("host", "", 0), ("host", "", 65536),
                 ("host", "", "bad"), ("join", "host.invalid", 7400),
                 ("join", "127.0.0.1; ignored", 7400))
        with patch.object(core, "play_problems") as problems:
            for role, peer, port in cases:
                with self.subTest(role=role, peer=peer, port=port):
                    with self.assertRaises(ValueError):
                        core.online_command({}, role, peer, port)
            problems.assert_not_called()

    def test_missing_build_or_iso_blocks_online(self):
        with patch.object(core, "play_problems", return_value=["Choose your own ISO."]):
            with self.assertRaisesRegex(ValueError, "own ISO"):
                core.online_command({}, "host")

    def test_unusual_runtime_layout_and_missing_identity_block_online(self):
        self.ready(os.path.join(core.ROOT, "custom", "ps2EntryRunner.exe"))
        with self.assertRaisesRegex(ValueError, "local build"):
            core.online_command({}, "host")
        with patch.object(core, "find_runtime", return_value=(os.path.join(core.ROOT, "deps", "ps2recomp", "out", "runtime", "ps2xRuntime", "ps2EntryRunner.exe"), "selected")):
            with patch.object(core.os.path, "isfile", return_value=False):
                with self.assertRaisesRegex(ValueError, "identity"):
                    core.online_command({}, "host")


class EnvironmentTests(unittest.TestCase):
    def test_offline_and_online_helper_start_without_inherited_net_test_state(self):
        inherited = {"TEKKEN4_NET": "host:7400", "TEKKEN4_NET_AUTO_VS": "1",
                     "TEKKEN4_NET_SIM": "old experiment", "TEKKEN4_RB_SELFTEST": "1",
                     "TEKKEN4_RAND_SEED": "42", "UNRELATED_SETTING": "keep"}
        settings = dict(core.DEFAULTS)
        with patch.dict(core.os.environ, inherited, clear=True), \
                patch.object(core, "effective_iso", return_value="own game.iso"), \
                patch.object(core, "graphics_env_names", return_value={}), \
                patch.object(core, "graphics_support", return_value={"fullscreen": False, "aa": False, "progressive": False}):
            env = core.game_env(settings)
        self.assertFalse(any(name.startswith(("TEKKEN4_NET", "TEKKEN4_RB_")) for name in env))
        self.assertNotIn("TEKKEN4_RAND_SEED", env)
        self.assertEqual("keep", env["UNRELATED_SETTING"])
        self.assertEqual("own game.iso", env["TEKKEN4_ISO"])


class OnlineLifecycleTests(unittest.TestCase):
    def prepare(self):
        stack = ExitStack()
        self.addCleanup(stack.close)
        stack.enter_context(patch.object(core, "find_runtime", return_value=("selected runner", "selected")))
        stack.enter_context(patch.object(core, "online_command", return_value=["mock helper"]))
        stack.enter_context(patch.object(core, "game_env", return_value={"checked": "environment"}))
        mkdir = stack.enter_context(patch.object(core.os, "makedirs"))
        opened = stack.enter_context(patch("builtins.open", mock_open()))
        spawn = stack.enter_context(patch.object(core.subprocess, "Popen"))
        return core.OnlineRun({}, "host"), mkdir, opened, spawn

    def test_start_and_successful_helper_exit_do_not_claim_connection_passed(self):
        run, mkdir, opened, spawn = self.prepare()
        spawn.return_value.wait.return_value = 0
        run.start()
        spawn.assert_called_once_with(["mock helper"], cwd=core.ROOT, env={"checked": "environment"},
                                      stdout=opened(), stderr=core.subprocess.STDOUT, creationflags=core.NO_WINDOW)
        mkdir.assert_called_once_with(core.LAUNCHER_LOG_DIR, exist_ok=True)
        record = run.wait()
        self.assertTrue(record["ok"])
        self.assertIn("see the log", record["note"])
        opened().close.assert_called_once()

    def test_failed_spawn_closes_log(self):
        run, _, opened, spawn = self.prepare()
        spawn.side_effect = OSError("synthetic spawn failure")
        with self.assertRaises(OSError):
            run.start()
        opened().close.assert_called_once()

    def test_stop_kills_helper_tree_and_nonzero_exit_is_reported(self):
        run, _, _, spawn = self.prepare()
        spawn.return_value.poll.return_value = None
        spawn.return_value.wait.return_value = 7
        run.start()
        with patch.object(core, "kill_tree") as kill:
            run.stop()
            kill.assert_called_once_with(run.proc)
        self.assertTrue(run.stopped_by_user)
        self.assertEqual("stopped from the launcher", run.wait()["note"])
        run.stopped_by_user = False
        record = run.wait()
        self.assertFalse(record["ok"])
        self.assertEqual(7, record["exit"])


if __name__ == "__main__":
    unittest.main()
