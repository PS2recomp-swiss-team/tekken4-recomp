"""Write the player-facing Tekken4Recomp repository content, without publishing.

Usage: python tools/make_public_repo.py --out <new-or-empty-folder>
Only README.md and LICENSE are written. No source, game files or Git metadata
are copied. Review the result before the owner updates the public repository.
"""
import argparse
from pathlib import Path
import stat
import sys


ROOT = Path(__file__).resolve().parent.parent
PUBLIC = "https://github.com/TheWishin/Tekken4Recomp"
SOURCE = "https://github.com/TheWishin/Tekken4Recomp-Source"
LAUNCHER = "https://github.com/TheWishin/OpenRecomp-FGC"


def player_readme():
    """Keep release promises limited to what the T4 documentation records."""
    return f"""# Tekken 4 Recomp

A native Windows port of **Tekken 4** (PlayStation 2), built on
[PS2Recomp](https://github.com/ran-j/PS2Recomp). The recompiler translates the
game's code on your PC; PS2Recomp's runtime supplies the PS2 hardware behaviour.
This repository holds player information and releases. The GPL-3 source is in
[Tekken4Recomp-Source]({SOURCE}).

You need your own **Tekken 4 USA v1.00 ISO, SLUS-20328**. Other regions and
revisions are not supported by this build. **No BIOS is needed. No game data,
BIOS or recompiled game code is shipped.** Keep your ISO available while playing.

## Install, build and play

T4 ships through the new [OpenRecomp-FGC launcher]({LAUNCHER}), shared with
T5DR. Use the owner's [release notes]({PUBLIC}/releases) for the matching
launcher and T4 package. Download and extract the complete package into a new,
writable folder on **Windows 10/11 x64**; allow roughly **6 GB plus your ISO**.
Follow the shared launcher's instructions to select the T4 installation.

1. Open the launcher and select Tekken 4. Choose your own supported ISO.
2. Use the build-game action. Read Microsoft's terms before accepting the first
   build's download of the C++/SDK headers and libraries from Microsoft.
   Internet access is needed for that download. The intended portable package
   includes private Python, LLVM, CMake, Ninja and source dependencies.
3. Wait for the build to finish, then use offline play. Keep the ISO in place.
   Change picture and sound settings in the launcher as needed.

The T4 backend and portable packaging scripts are implemented. This source
copy does **not** establish that shared-launcher integration, a complete
portable package, or a build on a clean PC has passed testing. The owner must
complete those checks before advertising a release as ready. The legacy
standalone T4 starter is `Tekken4.cmd`; it is not the shared launcher.

For developers building from the [source mirror]({SOURCE}), the documented
checkout route needs Python 3, Git, CMake, Ninja and Visual Studio 2022 Build
Tools with C++. Start `python launcher\\t4_launcher.pyw`, select the ISO in
**Build game**, build, then choose **Play offline**. See the source mirror's
`docs/E2E_BUILD.md` and `docs/RELEASE_PATH_B.md` for the two build routes and
their limits. A previous developer build does not prove the portable route.

## Controls

Default in-game layout (Xbox labels for gamepads):

| Action | Keyboard | Gamepad |
|---|---|---|
| Move / menus | W A S D | D-pad or left stick |
| Left punch (Square / 1) | Left arrow (or Z) | X |
| Right punch (Triangle / 2) | Up arrow (or V) | Y |
| Left kick (Cross / 3) | Down arrow (or X) | A |
| Right kick (Circle / 4) | Right arrow (or C) | B |
| L1 / R1 | Q / E | LB / RB |
| L2 / R2 | Left Shift / Right Shift | LT / RT |
| Start | Enter | Menu / Start |
| Select | Tab | View / Back |
| L3 / R3 | Left Ctrl / Right Ctrl | Stick clicks |

The keyboard remains available with a gamepad connected. Local VS Battle
needs a second controller. F11 or Alt+Enter toggles fullscreen. Close the game
window to quit; Esc does not quit. F1 opens the debug panel.

## Current state

The development notes record offline boot, menus and fights, sound, all modes,
XInput controllers and graphics settings working in the developer build.
Known issues include rough intro-movie music, occasional bright dots on the
beach stage at high resolution, and pauses during startup and loading.
Release-specific results belong in the release notes.

Rollback netplay has been tested between **two local instances** with no
desyncs reported in those tests. A two-PC test and the lobby server are still
pending in the T4 documentation. Do not assume public matchmaking or tested
internet play is available. The existing standalone launcher's online page
is a placeholder. Check each release's notes for any later verified change.

## Credits and licence

- [Lautreck](https://github.com/Lautreck/tekken4-recomp), the colleague whose
  original PAL port and groundwork this T4 work builds on.
- TheWishin and the Tekken 4 port contributors for the US port and continuing work.
- [ran-j/PS2Recomp](https://github.com/ran-j/PS2Recomp), the recompiler and runtime.
- [Waffle565/God-Of-War-Native-Port](https://github.com/Waffle565/God-Of-War-Native-Port),
  a reference port whose notes helped this project.
- [PCSX2](https://pcsx2.net/), a reference for PS2 hardware behaviour.
- [chaoticgd/ghidra-emotionengine-reloaded](https://github.com/chaoticgd/ghidra-emotionengine-reloaded),
  Ghidra and GhidraMCP for reverse-engineering tools.

The port's code is **GPL-3.0**, like PS2Recomp. See [LICENSE](LICENSE) and the
[clean source mirror]({SOURCE}); release notes must identify the corresponding
source revision. Third-party components retain their own licence notices.
The licence does not grant rights to the original game's assets or code.
Tekken is a trademark of Bandai Namco Entertainment. This project is not
affiliated with or endorsed by Bandai Namco Entertainment.
"""


def _no_links(path):
    """Reject symlinks and Windows reparse points, including parent folders."""
    for candidate in (path, *path.parents):
        try:
            info = candidate.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise ValueError("links/reparse points are not staging paths")


def make_public_repo(out, root=ROOT):
    """Write two files into a fresh/empty directory; never overwrite a repo."""
    out = Path(out).absolute()
    root = Path(root).absolute()
    if any(part.lower() == ".git" for part in out.parts):
        raise ValueError("output cannot be Git metadata")
    _no_links(out)
    if out.exists() and (not out.is_dir() or any(out.iterdir())):
        raise ValueError("output must be a new or empty directory")
    license_path = root / "LICENSE"
    _no_links(license_path)
    if not license_path.is_file():
        raise ValueError("source LICENSE must be a regular file")
    license_bytes = license_path.read_bytes()
    readme = player_readme()
    out.mkdir(parents=True, exist_ok=True)
    _no_links(out)
    with (out / "README.md").open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(readme)
    _no_links(out)
    with (out / "LICENSE").open("xb") as handle:
        handle.write(license_bytes)
    return out


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", required=True, type=Path,
                        help="new or empty staging directory; no publishing is done")
    args = parser.parse_args(argv)
    try:
        make_public_repo(args.out)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print("Wrote README.md and LICENSE. Owner review and publication are still required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
