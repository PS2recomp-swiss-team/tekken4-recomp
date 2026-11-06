"""Adjust only the staged PS2Recomp source for the local FFmpeg archive.

Never edits patches or the maintainer's source input. Called by package_release.
"""
from pathlib import Path
import re


def prepare(root, tree):
    root, tree = Path(root).resolve(), Path(tree).resolve()
    if tree not in (root / "deps" / "ps2recomp", root / "source" / "ps2recomp"):
        raise ValueError("only the staged source/ps2recomp (0.1.4) or deps/ps2recomp tree may be adapted")
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
    # The release compiles with the bundled clang-cl, which has /Qspectre but no "/Qspectre-" (off is its default):
    # drop that one MSVC-only flag from the Release options (host tools only; the game runtime is RelWithDebInfo
    # and never gets these options).
    release_mode = tree / "ps2xRuntime" / "cmake" / "ReleaseMode.cmake"
    text = release_mode.read_text(encoding="utf-8")
    text, count = re.subn(r"^[ \t]*/Qspectre-[^\n]*\n", "", text, flags=re.M)
    if count != 1:
        raise ValueError("pinned ReleaseMode.cmake changed; review before packaging")
    release_mode.write_text(text, encoding="utf-8", newline="\n")
