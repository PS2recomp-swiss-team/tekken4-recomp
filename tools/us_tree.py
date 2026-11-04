"""Resolve the US build tree; the shell compatibility wrappers call this too."""
import sys
from pathlib import Path
import os
sys.path.insert(0, str(Path(__file__).resolve().parent))
from player_common import ROOT, PlayerParser, configure_output, option, resolve_us_tree, git_output


def main(argv=None):
    configure_output()
    ap = PlayerParser(description=__doc__)
    option(ap, "Root", default=str(ROOT))
    option(ap, "Branch")
    ap.add_argument("--cmd-choice", action="store_true", help="ASCII-only selection for cmd.exe environment assignment")
    a = ap.parse_args(argv)
    try:
        if a.Branch:
            print(git_output(a.Branch, "rev-parse", "--abbrev-ref", "HEAD"))
        else:
            tree = resolve_us_tree(a.Root)
            print(("environment" if os.environ.get("TEKKEN4_SRC") else "own" if tree.name.endswith("_usa") else "plain") if a.cmd_choice else tree)
        return 0
    except (OSError, ValueError) as ex:
        print(str(ex), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
