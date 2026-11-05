# Tekken 4 Recomp v0.1.2 (pre-release) - release notes

Small fix on top of v0.1.1. Everything in [RELEASE_NOTES_0.1.1.md](RELEASE_NOTES_0.1.1.md) still applies:
ranked and casual online through the OpenRecomp-FGC launcher, player names, rank badges, speed and older-PC
notes, Linux / Steam Deck notes.

## What is new

- **Rank badges are hidden whenever the game hides the player names**, for example during the KO replay.
  In v0.1.1 the badges stayed on screen over the replay. They are now drawn only while the game itself
  draws the player's name text. See docs/T4_RANKED.md.

## Known issues

Unchanged from v0.1.1 (see RELEASE_NOTES_0.1.1.md and docs/KNOWN_ISSUES.md): short frame-time stutters in fights,
no widescreen, intro movie sound sync unmeasured, a fresh game per online match (no instant rematch), no replay
recording, both players need a reachable UDP path and the same build, and no pair of physical PCs over the
internet has been tested yet.

## Reporting a problem

Tell us your PC (CPU, GPU), Windows version, whether you played direct IP, VPN or the lobby, and what happened.
Keep both players' `logs` folders and check them for personal details before sharing. Never share your ISO.
