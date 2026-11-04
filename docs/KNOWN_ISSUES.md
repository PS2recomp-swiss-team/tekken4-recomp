# T4 beta: known issues and limits

2026-10-31. Intended scope: offline play and rollback online by direct IP or
VPN in the new launcher, using each player's own USA v1.00 ISO (SLUS-20328).
There is no lobby, matchmaking or ranked mode in this beta scope.
The owner's two-PC test is still pending in the evidence available here.

## Reported issues

* **Intro-movie music is rough.** Sound and background music were reported
  working in the developer build, but the intro is not clean. Lower volume is
  not an audio fix; sound-on testing of the release build is still required.
* **One side can stall.** The supplied simulated-network pairs ran two games
  on one PC and GPU. Some runs had deep prediction and seconds of waiting on
  one side; other runs of the same build were balanced. Coalescing reduced
  traffic, but a stall cure has not been proved. Two physical PCs remove that
  shared contention, not every possible cause. See
  [ROLLBACK_ASYMMETRY.md](ROLLBACK_ASYMMETRY.md).
* **Online still pays the boot cost.** Plan for a cold boot per online match
  or new opponent; the owner reports about 20 seconds per opponent. Persistent
  opponent sessions and direct entry into a fight are not implemented features.
  An in-game rematch is a separate path and must pass the two-PC test before
  being advertised. See [DIRECTFIGHT_T4.md](DIRECTFIGHT_T4.md).
* **Startup and loading can pause.** Short pauses at startup and after character
  selection were reported. A game that remains stuck needs investigation;
  indefinite loading is not accepted as normal.
* **Beach-stage rendering can show bright dots** in the sand at high resolution.

## Limits that still need release proof

* Local-instance netplay reports include zero mismatches, but they do not prove
  two-PC pacing, every frame, audible output, rematches or internet compatibility.
  Test the exact candidate with sound on and no network simulator. State which
  direct-IP or VPN route passed; a VPN relay can add delay.
* Both players need a reachable UDP path and matching game/build identities.
  The beta does not configure a router or firewall. A failed connection that
  leaves an offline game running is not a successful online session.
* Online games boot straight to VS character select (`TEKKEN4_NET_AUTO_VS`,
  default on since 2026-11-04; docs/DIRECTFIGHT_T4.md "Online boot"). The
  presses follow the game's own scene/menu state; an unknown screen makes the
  automation wait, and after `TEKKEN4_NET_AUTO_VS_END` (3000 frames) the
  players take over with their pads. Online games use an empty memory card in
  their run folder (`TEKKEN4_NET_CARD`), not the offline save.
* The portable path B scripts exist, but this source copy proves no complete
  player zip, clean-PC build or integration with the new launcher. The standalone
  `Tekken4.cmd` starter does not establish that integration. Microsoft build
  libraries are fetched on the player's PC after licence acceptance; they must
  not ship in the zip. See [RELEASE_PATH_B.md](RELEASE_PATH_B.md).
* Trusted online winner/score reporting and persistent sessions remain future
  work. An incomplete session report is not proof of a win. Do not advertise
  automatic updates or recovery without testing the actual launcher path.

Stop on a desync, different scenes/results, persistent stalls, peer loss or a
failed release gate. Keep both sides' logs and the scene/time of the problem
for the maintainer; do not include ISO files, game data, saves or memory dumps.

Release claims and the final decision belong in
[BETA_RELEASE_NOTES.md](BETA_RELEASE_NOTES.md) and
[BETA_GO_NO_GO.md](BETA_GO_NO_GO.md). No build or game run was performed here.
