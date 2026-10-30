# Rules for coding agents: Tekken 4 working copy

This folder is a clean copy of the Tekken 4 port's source, without history, screenshots or game data. The real project lives elsewhere, and only the maintainer touches it.

- Read and change files only in this folder. `CLAUDE.md` and the docs name other folders on this PC (`D:\...`): do not open them.
- **Do not commit, push, merge, tag, release or open pull requests.** Leave your changes in the working tree. The maintainer reviews them and carries them over.
- Do not build, do not start a game, do not run `tools\build_*` or `tools\net_*`. There is no game data here and there must never be: no ISO, ELF, DATA.BIN, generated code, BIOS, saves, keys, screenshots.
- Do not add T5DR code here. T4 is GPL-3.
- Nobody deletes anything in this project: don't remove files unless the task says so.
- Patches in `patches\` have two-digit names and apply in name order. Don't renumber or edit them unless the task says so.
- Match the surrounding code and the style of the docs: plain, short, honest about what was not tested.

Your report says: what changed, what you could not check, and what needs a real build or a game run to prove.
