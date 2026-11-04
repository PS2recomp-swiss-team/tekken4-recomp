"""Player pipeline logic and dry-run checks. No game data, real builds or network."""
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import build_game
import net_play
import net_preflight as net
import player_common
import t4_buildid

ROOT = Path(__file__).resolve().parent.parent
IDENTITY = dict(schema=1, build_id="a" * 16, compiler="Clang 21.1.0", iso_sha256="b" * 64,
                elf_sha1="c" * 40, net="7", strict_hello="0", delay_match="0")


class ArgumentsTests(unittest.TestCase):
    def test_build_legacy_and_python_flags(self):
        for flags in (["-iSo", "my own.iso", "-FORCE", "-WhatIf", "-Steps", "STAGE, runtime", "tools"],
                      ["--iso", "my own.iso", "--force", "--dry-run", "--steps", "STAGE, runtime", "tools"]):
            a = build_game.parser().parse_args(flags)
            self.assertEqual(a.Iso, "my own.iso")
            self.assertTrue(a.Force and a.WhatIf)
            self.assertEqual(build_game.parse_steps(a.Steps), ["tools", "stage", "runtime"])

    def test_step_validation_exit_code(self):
        self.assertEqual(build_game.parse_steps(None), list(build_game.ALL_STEPS))
        self.assertEqual(build_game.parse_steps(["fork,fork"]), ["fork"])
        with redirect_stdout(io.StringIO()):
            self.assertEqual(build_game.main(["-Steps", "nope"]), 2)

    def test_online_arguments_and_aliases(self):
        a = net_play.parser().parse_args(["-Host", "-Port", "7401", "-IsoPath", "own.iso", "-NoDiagnostics"])
        self.assertTrue(a.AsHost and a.NoDiagnostics)
        self.assertEqual((a.Port, a.Iso, a.Delay, a.Sound), (7401, "own.iso", "auto", 1))
        b = net_play.parser().parse_args(["--join", "example.invalid", "--preflight-timeout-seconds", "5"])
        self.assertEqual((b.Join, b.PreflightTimeoutSeconds), ("example.invalid", 5))

    def test_invalid_port_timeout_and_conflicting_roles(self):
        for args in (["-Port", "0"], ["-Port", "65536"], ["-PreflightTimeoutSeconds", "4"]):
            with self.subTest(args=args), redirect_stdout(io.StringIO()), patch("sys.stderr", io.StringIO()):
                with self.assertRaises(SystemExit) as ex:
                    net_play.parser().parse_args(args)
                self.assertEqual(ex.exception.code, 2)
        for args, message in (([], "Give -Host"), (["-Host", "-Join", "x"], "either"), (["-Host", "-Sim", "x"], "outside")):
            with self.assertRaisesRegex(ValueError, message):
                net_play.run(net_play.parser().parse_args(args))

    def test_default_profile_clears_harness_but_preserves_explicit_off(self):
        env = net_play.player_environment(net_play.parser().parse_args(["-Host"]), {
            "TEKKEN4_NET_COALESCE": "0", "TEKKEN4_NET_AUTO_VS": "1", "TEKKEN4_NET_DIAG": "0",
            "TEKKEN4_NET_SIM": "experiment", "TEKKEN4_RB_SELFTEST": "1", "TEKKEN4_RAND_SEED": "5", "OTHER": "keep"})
        self.assertEqual(env["TEKKEN4_NET"], "host:7400")
        self.assertEqual(env["TEKKEN4_NET_AUTO_VS"], "0")
        self.assertEqual(env["TEKKEN4_NET_MAXPRED"], "8")
        self.assertEqual(env["TEKKEN4_NET_COALESCE"], "0")
        self.assertEqual(env["TEKKEN4_NET_DIAG"], "0")
        self.assertEqual(env["OTHER"], "keep")
        self.assertFalse({"TEKKEN4_NET_SIM", "TEKKEN4_RB_SELFTEST", "TEKKEN4_RAND_SEED"} & env.keys())

    def test_inherited_profile_and_no_diagnostics(self):
        a = net_play.parser().parse_args(["-Join", "127.0.0.1", "-UseInheritedProfile", "-NoDiagnostics", "-Sim", "20"])
        env = net_play.player_environment(a, {"TEKKEN4_RB_SELFTEST": "1"})
        self.assertEqual(env["TEKKEN4_RB_SELFTEST"], "1")
        self.assertEqual(env["TEKKEN4_NET_DIAG"], "0")
        self.assertEqual(env["TEKKEN4_NET_SIM"], "20")
        self.assertEqual(env["TEKKEN4_NET"], "join:127.0.0.1:7400")


class PlanningTests(unittest.TestCase):
    def test_dependency_changes_force_downstream_work(self):
        for step, dependencies in (("tools", ["fork"]), ("recomp", ["tools", "extract"]),
                                   ("stage", ["recomp", "fork"]), ("runtime", ["stage"])):
            self.assertFalse(build_game.needs_step(step, False, [], True, "same", "same"))
            for dep in dependencies:
                self.assertTrue(build_game.needs_step(step, False, [dep], True, "same", "same"))
            self.assertTrue(build_game.needs_step(step, True, [], True, "same", "same"))
            self.assertTrue(build_game.needs_step(step, False, [], False, "same", "same"))
            self.assertTrue(build_game.needs_step(step, False, [], True, "old", "new"))

    def test_cmake_plan_keeps_spaces_literal_and_matches_build_options(self):
        root, tree = Path("release with spaces").resolve(), Path("source with spaces").resolve()
        for runtime in (False, True):
            commands = build_game.cmake_plan(root, tree, "runtime", runtime, True, {})
            self.assertEqual(commands[0][2], str(tree))
            self.assertEqual(commands[1][0], str(root / "toolchain/cmake/bin/cmake.exe"))
            self.assertIn("-DCMAKE_TOOLCHAIN_FILE=" + (root / "tools/t4_toolchain_clangcl.cmake").as_posix(), commands[0])
            self.assertFalse(any("powershell" in str(arg).lower() or str(arg).endswith(".cmd") for command in commands for arg in command))
            if runtime:
                self.assertIn("-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=/Z7 /O2 /Ob2 /DNDEBUG", commands[0])
                self.assertIn("-DPS2X_ENABLE_AGRESSIVE_LOGS=OFF", commands[0])
                self.assertEqual(commands[1][-2:], ["--target", "ps2EntryRunner"])

    def test_complete_dry_run_checks_and_plans_without_mutations(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "patches").mkdir()
            (root / "patches/0001.patch").write_text("dummy patch")
            iso = root / "own.iso"
            iso.write_text("synthetic fixture")
            env = {"TEKKEN4_SRC": str(root / "source")}
            def checked(build):
                build.iso_files = dict.fromkeys(["SYSTEM.CNF", "SLUS_203.28", "IRX/IOPRP243.IMG", "TEKKEN/DATA.BIN"], 1)
            with patch.dict(os.environ, env), patch.object(build_game.Build, "prereq", return_value="ok"), \
                    patch.object(build_game.Build, "check_iso", autospec=True, side_effect=checked), \
                    patch.object(build_game.Build, "run_command", side_effect=AssertionError("dry run executed a build")), \
                    redirect_stdout(io.StringIO()) as out:
                result = build_game.main(["-Iso", str(iso), "-WhatIf", "-AcceptMicrosoftLicense"], root=root)
            self.assertEqual(result, 0, out.getvalue())
            self.assertIn("[8/8] runtime -", out.getvalue())
            self.assertIn("    checked (", out.getvalue())
            self.assertIn('Dry run only:', out.getvalue())
            self.assertEqual(out.getvalue().count("would run ("), 6)
            self.assertEqual({str(p.relative_to(root)) for p in root.rglob("*") if p.is_file()},
                             {"own.iso", str(Path("patches/0001.patch")), str(Path("logs/build_game.log"))})

    def test_cli_dry_run_in_isolated_release(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "tools").mkdir()
            for name in ("build_game.py", "player_common.py"):
                shutil.copy2(ROOT / "tools" / name, root / "tools" / name)
            env = dict(os.environ, TEKKEN4_SRC=str(root / "source"))
            command = [sys.executable, "-I", str(root / "tools/build_game.py"), "-WhatIf", "-Steps", "tools,recomp,stage,runtime"]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("[4/4] runtime -", result.stdout)
            self.assertFalse((root / "source").exists())
            self.assertFalse((root / "logs/build_game_state.json").exists())
            self.assertTrue((root / "logs/build_game.log").is_file())

    def test_staging_does_not_purge_and_touches_rollback_for_new_header(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "generated").mkdir()
            (root / "runtime").mkdir()
            (root / "generated/register_functions.cpp").write_text("synthetic")
            (root / "runtime/tekken4_rollback_overrides.cpp").write_text("override")
            (root / "runtime/tekken4_net.h").write_text("transport")
            tree = root / "source"
            runner = tree / "ps2xRuntime/src/runner"
            runner.mkdir(parents=True)
            stale = runner / "stale.cpp"
            stale.write_text("preserve")
            build_game.stage_generated(root, tree)
            rollback = runner / "tekken4_rollback_overrides.cpp"
            stamp = rollback.stat().st_mtime_ns
            build_game.stage_generated(root, tree)
            self.assertEqual(rollback.stat().st_mtime_ns, stamp)
            self.assertEqual(stale.read_text(), "preserve")
            self.assertEqual((runner / "tekken4_net.h").read_text(), "transport")

    def test_portable_source_selection_requires_no_git(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "toolchain").mkdir()
            (root / "toolchain/toolchain.json").write_text("{}")
            with patch.object(player_common, "git_output", side_effect=AssertionError("Git in release")):
                self.assertEqual(player_common.build_tree(root, {"TEKKEN4_SRC": "ignored"}), root / "deps/ps2recomp")


class IdentityTests(unittest.TestCase):
    def test_sanitizer_keeps_only_protocol_fields(self):
        self.assertEqual(net.identity(dict(IDENTITY, path="private", name="private")), IDENTITY)
        for key in net.RULES:
            bad = dict(IDENTITY)
            bad.pop(key)
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, key):
                net.identity(bad)
        self.assertEqual(net.identity(dict(IDENTITY, net=7))["net"], "7")

    def test_rejects_invalid_compiler_and_hashes(self):
        for key, value in (("compiler", "Clang\nprivate"), ("compiler", ""), ("build_id", "A" * 16),
                           ("iso_sha256", "b" * 63), ("net", True), ("strict_hello", "2")):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                net.identity(dict(IDENTITY, **{key: value}))

    def test_identity_hashes_local_iso_and_uses_exact_compiler(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            iso = root / "own.iso"
            iso.write_bytes(b"synthetic ISO test bytes")
            stamp = root / "stamp.json"
            data = dict(id=IDENTITY["build_id"], elf=IDENTITY["elf_sha1"], net=7,
                        toolchain=["CXX_ID=Clang", "CXX_VERSION=21.1.0"])
            player_common.write_json(stamp, data)
            with redirect_stdout(io.StringIO()):
                result = net.new_identity(stamp, iso, {"TEKKEN4_NET_STRICT_HELLO": "1"})
            self.assertEqual(result["iso_sha256"], player_common.digest(iso, "sha256"))
            self.assertEqual(result["compiler"], IDENTITY["compiler"])
            self.assertEqual(result["strict_hello"], "1")
            data["toolchain"].append("CXX_VERSION=21.1.1")
            player_common.write_json(stamp, data)
            with self.assertRaisesRegex(ValueError, "compiler version missing"):
                net.new_identity(stamp, iso)

    def test_comparison_lists_all_different_fields(self):
        with redirect_stdout(io.StringIO()) as output:
            self.assertEqual(net.compare_identity(IDENTITY, IDENTITY), [])
            self.assertEqual(net.compare_identity(IDENTITY, dict(IDENTITY, compiler="Clang 22", strict_hello="1")), ["compiler", "strict_hello"])
        self.assertIn("DIFFERENT compiler:", output.getvalue())

    def test_build_code_identity_normalizes_line_endings_and_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            roots = [Path(temp) / name for name in ("one", "other path")]
            for i, root in enumerate(roots):
                (root / "source").mkdir(parents=True)
                (root / "patches").mkdir()
                (root / "config").mkdir()
                (root / "source/.t4-vendored.json").write_text('{"head":"test"}\n')
                (root / "source/source.cpp").write_bytes(b"line\r\n" if i else b"line\n")
                (root / "patches/one.patch").write_bytes(b"patch\r\n" if i else b"patch\n")
            ids = []
            for root in roots:
                with patch.object(t4_buildid, "ROOT", str(root)):
                    ids.append(t4_buildid.code_id(str(root / "source"), ["CXX_ID=Clang", "CXX_VERSION=21"]))
            self.assertEqual(ids[0], ids[1])


class OnlineStartTests(unittest.TestCase):
    def test_preflight_precedes_game_and_exit_code_and_logs_are_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            src = root / "source"
            exe_dir = src / "out/runtime/ps2xRuntime"
            exe_dir.mkdir(parents=True)
            exe = exe_dir / "ps2EntryRunner.exe"
            exe.touch()
            elf = root / "game/disc/SLUS_203.28"
            elf.parent.mkdir(parents=True)
            elf.write_text("synthetic ELF fixture")
            iso = root / "own.iso"
            iso.write_text("synthetic ISO fixture")
            run_dir = root / "run"
            a = net_play.parser().parse_args(["-Host", "-Src", str(src), "-Iso", str(iso), "-RunDir", str(run_dir)])
            local = dict(IDENTITY, elf_sha1=player_common.digest(elf))
            calls = []
            with patch.object(net_play, "new_identity", return_value=local), \
                    patch.object(net_play, "preflight", side_effect=lambda *args: calls.append("preflight")) as probe, \
                    patch.object(net_play.subprocess, "Popen") as spawn, redirect_stdout(io.StringIO()):
                spawn.side_effect = lambda *args, **kwargs: calls.append("game") or type("Process", (), {"wait": lambda self: 37})()
                self.assertEqual(net_play.run(a, root), 37)
            self.assertEqual(calls, ["preflight", "game"])
            self.assertEqual(probe.call_args.args[:4], (True, "", 7400, local))
            self.assertEqual(spawn.call_args.args[0], [str(exe), str(elf)])
            self.assertEqual(spawn.call_args.kwargs["cwd"], run_dir)
            self.assertEqual(spawn.call_args.kwargs["env"]["TEKKEN4_NET_BUILD"], local["build_id"])
            self.assertEqual(player_common.read_json(run_dir / "run_info.json")["exit_code"], 37)
            self.assertTrue((run_dir / "stdout.txt").is_file() and (run_dir / "stderr.txt").is_file())
            with patch.object(net_play, "new_identity", return_value=local), \
                    patch.object(net_play, "preflight", side_effect=ValueError("udp_timeout")), \
                    patch.object(net_play.subprocess, "Popen") as spawn, redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(ValueError, "udp_timeout"):
                    net_play.run(a, root)
                spawn.assert_not_called()


@unittest.skipUnless(os.name == "nt" and shutil.which("powershell"), "Windows compatibility wrappers")
class WrapperTests(unittest.TestCase):
    def test_developer_compiler_environment_handles_spaces(self):
        with tempfile.TemporaryDirectory() as temp:
            vcvars = Path(temp) / "compiler environment.cmd"
            vcvars.write_bytes(b"@echo off\r\nset T4_COMPILER_PROBE=ok\r\n")
            self.assertIn("T4_COMPILER_PROBE=ok", build_game.visual_studio_environment(vcvars))

    def test_build_wrappers_preserve_unknown_step_exit_code(self):
        for name in ("build_game.ps1", "build_game_portable.ps1"):
            result = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                     str(ROOT / "tools" / name), "-Steps", "invalid"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn("Unknown step 'invalid'. Steps:", result.stdout)

    def test_dot_sourced_preflight_keeps_identity_api(self):
        script = ". '" + str(ROOT / "tools/net_preflight.ps1") + "'; "
        payload = json.dumps(IDENTITY).replace("'", "''")
        script += "$v = '" + payload + "' | ConvertFrom-Json; ConvertTo-T4NetIdentity $v | ConvertTo-Json -Compress"
        result = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout), IDENTITY)


class PacketTests(unittest.TestCase):
    def fake_probe(self, root, *, host=False, mismatch=False, silent=False):
        class Socket:
            closed = False
            sent = []
            def setsockopt(self, *args):
                pass
            def bind(self, endpoint):
                self.endpoint = endpoint
            def sendto(self, raw, endpoint):
                self.sent.append(raw)
            def recvfrom(self, size):
                echo = json.loads(self.sent[-1])["nonce"] if self.sent else ""
                peer = dict(IDENTITY, compiler="Clang 22") if mismatch else IDENTITY
                return net.encode_packet("f" * 32, echo, bool(echo), peer), ("127.0.0.1", 7400)
            def close(self):
                self.closed = True
        udp = Socket()
        timer = iter(n / 10 for n in range(1000))
        with patch.object(net.socket, "socket", return_value=udp), \
                patch.object(net.select, "select", return_value=([] if silent else [udp], [], [])), \
                patch.object(net.time, "monotonic", side_effect=lambda: next(timer)), redirect_stdout(io.StringIO()):
            try:
                net.preflight(host, "127.0.0.1", 7400, IDENTITY, 5, root / "report.json", {})
            except ValueError:
                if not (mismatch or silent):
                    raise
        self.assertTrue(udp.closed)
        return player_common.read_json(root / "report.json"), udp

    def test_both_roles_confirm_nonce_and_release_port(self):
        with tempfile.TemporaryDirectory() as temp:
            for host in (True, False):
                with self.subTest(host=host):
                    report, udp = self.fake_probe(Path(temp), host=host)
                    self.assertEqual(report["status"], "ok")
                    self.assertEqual(report["reason"], "matched")
                    self.assertEqual(udp.endpoint[1], 7400 if host else 0)
                    self.assertTrue(any(json.loads(raw)["ready"] for raw in udp.sent))

    def test_mismatch_and_timeout_never_report_success(self):
        with tempfile.TemporaryDirectory() as temp:
            report, _ = self.fake_probe(Path(temp), mismatch=True)
            self.assertEqual(report["reason"], "build_mismatch")
            self.assertEqual(report["mismatch_fields"], ["compiler"])
            self.assertEqual(report["status"], "failed")
            report, _ = self.fake_probe(Path(temp), silent=True)
            self.assertEqual(report["reason"], "udp_timeout")
            self.assertEqual(report["status"], "failed")

    def test_wire_format_interoperates_with_legacy_packet(self):
        raw = net.encode_packet("d" * 32, "", False, IDENTITY)
        decoded = net.decode_packet(raw)
        self.assertEqual(set(decoded), {"tag", "nonce", "echo", "ready", "identity"})
        self.assertEqual(decoded["tag"], "T4TEST1")
        self.assertEqual(decoded["identity"], IDENTITY)
        self.assertLess(len(raw), 4096)
        legacy = json.dumps(dict(decoded, echo="e" * 32, ready=True)).encode()
        self.assertTrue(net.decode_packet(legacy)["ready"])

    def test_rejects_bad_and_oversized_packets(self):
        good = json.loads(net.encode_packet("d" * 32, "", False, IDENTITY))
        invalid = [b"", b"a" * 4097, b"\xff" * 100, b"null", b"[]", b"not json"]
        for key, value in (("tag", "game"), ("nonce", "D" * 32), ("echo", "x"), ("ready", 1), ("identity", {})):
            invalid.append(json.dumps(dict(good, **{key: value})).encode())
        for raw in invalid:
            with self.subTest(raw=raw[:40]), self.assertRaises(ValueError):
                net.decode_packet(raw)

    def test_probe_does_not_send_paths_or_machine_names(self):
        raw = net.encode_packet("d" * 32, "", False, dict(IDENTITY, path="secret path", machine="secret PC"))
        self.assertNotIn(b"secret", raw)

    def test_ipv4_resolution_and_ipv6_rejection(self):
        self.assertEqual(net.resolve_peer("127.0.0.1"), "127.0.0.1")
        with self.assertRaisesRegex(ValueError, "IPv6"):
            net.resolve_peer("::1")
        with patch.object(net.socket, "getaddrinfo", return_value=[(2, 2, 17, "", ("127.0.0.1", 0))]):
            self.assertEqual(net.resolve_peer("host.invalid"), "127.0.0.1")

    def test_invalid_bind_and_port_save_failure_reports_without_network(self):
        cases = [({"TEKKEN4_NET_BIND": "::1"}, "invalid_bind"),
                 ({"TEKKEN4_NET_PORT": "65536"}, "invalid_local_port")]
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "preflight.json"
            for env, reason in cases:
                with self.subTest(reason=reason), self.assertRaisesRegex(ValueError, reason), \
                        patch.object(net.socket, "socket", side_effect=AssertionError("unexpected network")):
                    net.preflight(False, "127.0.0.1", 7400, IDENTITY, 5, output, env)
                self.assertEqual(player_common.read_json(output)["reason"], reason)


if __name__ == "__main__":
    unittest.main()
