"""Adjust only the staged PS2Recomp source for the local FFmpeg archive.

Never edits patches or the maintainer's source input. Called by package_release.
"""
from pathlib import Path
import re


def prepare(root, tree):
    root, tree = Path(root).resolve(), Path(tree).resolve()
    if tree != root / "deps" / "ps2recomp":
        raise ValueError("only the staged deps/ps2recomp tree may be adapted")
    path = tree / "ps2xRuntime" / "CMakeLists.txt"
    text = path.read_text(encoding="utf-8")
    # The pinned upstream uses a plain set(), which overrides a -D cache argument.
    pattern = r'set\(FFMPEG_PREBUILT_URL\s+"[^"\n]+"\s*\)'
    replacement = ('if(NOT DEFINED FFMPEG_PREBUILT_URL)\n'
                   '    message(FATAL_ERROR "Release requires the local FFmpeg archive")\n'
                   'endif()')
    text, count = re.subn(pattern, lambda _: replacement, text)
    if count != 1:
        raise ValueError("pinned FFmpeg CMake declaration changed; review before packaging")
    path.write_text(text, encoding="utf-8", newline="\n")
