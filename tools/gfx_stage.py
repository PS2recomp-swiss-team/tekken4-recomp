"""Stages the game overrides for the graphics worktree (D:\\tekken4-fork-gfx, branch t4-gfx) in isolation.

Other agents edit runtime\\*_overrides.cpp in this working tree at the same time; staging their uncommitted work broke
the graphics build. This writes the COMMITTED (HEAD) version of every tracked runtime\\*_overrides.cpp into
<tree>\\ps2xRuntime\\src\\runner, plus the graphics session's video-mode override (progressive 480p + sceGsGParam),
taken from the working copy of runtime\\tekken4_overrides.cpp between the markers below. Untracked override files of
other agents are not staged.

Usage: python -I tools/gfx_stage.py <PS2Recomp tree>
       python -I tools/gfx_stage.py --patch <out.patch>   (that video-mode block as a diff against HEAD, to commit it)
"""
import difflib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BEGIN = "    // Progressive scan (480p)."
APPLY = "    void apply(PS2Runtime &runtime)\n    {\n"
APPLY_BLOCK_BEGIN = "        {\n            const char *progressive = std::getenv(\"TEKKEN4_PROGRESSIVE\");"
APPLY_BLOCK_END = "        }\n"
LF = "\n"
CRLF = "\r\n"


def head(path: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), "show", f"HEAD:{path}"], check=True, capture_output=True,
                          text=True, encoding="utf-8").stdout.replace(CRLF, LF)


def with_video_mode(text: str, work: str) -> str:
    work = work.replace(CRLF, LF)
    funcs = work[work.index(BEGIN):work.index(APPLY)]
    a = work.index(APPLY_BLOCK_BEGIN)
    block = work[a:work.index(APPLY_BLOCK_END, a) + len(APPLY_BLOCK_END)]
    i = text.index(APPLY)
    return text[:i] + funcs + APPLY + block + text[i + len(APPLY):]


def main() -> int:
    work = (ROOT / "runtime" / "tekken4_overrides.cpp").read_text(encoding="utf-8")
    if sys.argv[1] == "--patch":
        old = head("runtime/tekken4_overrides.cpp")
        new = with_video_mode(old, work)
        diff = difflib.unified_diff(old.splitlines(True), new.splitlines(True), "a/runtime/tekken4_overrides.cpp",
                                    "b/runtime/tekken4_overrides.cpp")
        Path(sys.argv[2]).write_text("".join(diff), encoding="utf-8", newline=LF)
        return 0
    runner = Path(sys.argv[1]) / "ps2xRuntime" / "src" / "runner"
    files = subprocess.run(["git", "-C", str(ROOT), "ls-files", "runtime/*_overrides.cpp"], check=True,
                           capture_output=True, text=True).stdout.split()
    files = [f for f in files if f.count("/") == 1]  # runtime/pal/ holds the parked PAL camera overrides
    for f in files:
        text = head(f)
        if f.endswith("/tekken4_overrides.cpp") and BEGIN not in text:
            text = with_video_mode(text, work)
        out = runner / Path(f).name
        old = out.read_text(encoding="utf-8") if out.exists() else None
        if old != text:
            out.write_text(text, encoding="utf-8", newline=LF)
            print("staged", out.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
