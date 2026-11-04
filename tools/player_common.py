"""Shared player helpers. Python standard library only; no work on import."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0


def configure_output():
    """Launcher pipes and log collectors use UTF-8, including under -I (which ignores PYTHONUTF8)."""
    for stream in (sys.stdout, sys.stderr):
        if stream is not None and hasattr(stream, "reconfigure") and not stream.isatty():
            stream.reconfigure(encoding="utf-8", errors="replace")


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return default


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def digest(path, algorithm="sha1"):
    h = hashlib.new(algorithm)
    with open(path, "rb") as src:
        for block in iter(lambda: src.read(4 << 20), b""):
            h.update(block)
    return h.hexdigest()


class PlayerParser(argparse.ArgumentParser):
    """Accept documented PowerShell spellings (case insensitive) and Python --flags."""
    def parse_known_args(self, args=None, namespace=None):
        args = list(sys.argv[1:] if args is None else args)
        options = {key.lower(): key for key in self._option_string_actions}
        args = [options.get(arg.lower(), arg) for arg in args]
        return super().parse_known_args(args, namespace)


def option(parser, name, **kwargs):
    # --kebab-case plus the original -PowerShellName.
    import re
    flag = "--" + re.sub(r"(?<!^)([A-Z])", r"-\1", name).lower()
    parser.add_argument("-" + name, flag, dest=name, **kwargs)


def integer_range(low, high):
    def parse(value):
        try:
            result = int(value)
        except ValueError:
            raise argparse.ArgumentTypeError("must be an integer")
        if not low <= result <= high:
            raise argparse.ArgumentTypeError(f"must be {low} through {high}")
        return result
    return parse


def git_output(tree, *args):
    try:
        p = subprocess.run(["git", "-C", str(tree), *args], capture_output=True, text=True, creationflags=NO_WINDOW)
        return p.stdout.strip() if p.returncode == 0 else ""
    except OSError:
        return ""


def resolve_us_tree(root=ROOT, env=None):
    env = os.environ if env is None else env
    plain = Path(root).resolve().parent / "tekken4-fork-ps2recomp"
    own = plain.with_name(plain.name + "_usa")
    tree = (Path(env["TEKKEN4_SRC"]) if env.get("TEKKEN4_SRC") else own if own.exists()
            else plain if not (plain / ".git").exists() or git_output(plain, "rev-parse", "--abbrev-ref", "HEAD") == "t4-us"
            else own).resolve()
    if (tree / ".git").exists():
        branch = git_output(tree, "rev-parse", "--abbrev-ref", "HEAD")
        if branch != "t4-us":
            raise ValueError(f"{tree} is on branch '{branch}', not t4-us: not the US PS2Recomp tree. Set TEKKEN4_SRC to the US tree.")
    return tree


def build_tree(root=ROOT, env=None):
    env = os.environ if env is None else env
    vendored = Path(root) / "deps/ps2recomp"
    if (Path(root) / "toolchain/toolchain.json").is_file() or ((vendored / ".t4-vendored.json").is_file() and not env.get("TEKKEN4_SRC")):
        return vendored.resolve()
    return resolve_us_tree(root, env)
