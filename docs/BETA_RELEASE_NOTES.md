# Tekken 4 Sunday beta — release notes draft

Candidate only. The owner's two-PC result has not been supplied here. Fill in
the version, checked build/source revision, download and test results before
publishing. The target date was Sunday, 1 November 2026; status on 2 November
remains **NO-GO pending acceptance evidence**. A date is not a pass.

This beta targets offline play and rollback online play by direct IP or VPN
inside the new launcher. There is no lobby, matchmaking or ranked play. Each
player needs their own Tekken 4 USA v1.00 ISO, **SLUS-20328**, including while
playing. No game data, BIOS or recompiled game executable is included. The game
is built on the player's PC. T4's project code is GPL-3.0. T5DR 1.2.0 is outside
this release; lobby, shared login and server deployment come later.

## What the existing evidence covers

The development notes record offline boot, menus, fights, sound, modes, XInput
pads and graphics settings working in a developer build. That does not prove
the exact beta package or the new launcher's integration.

The supplied same-PC network measurements reached 6000 frames in all 14 pair
configurations, with 199 hash comparisons per endpoint, zero mismatches and
zero reported NETDESYNC lines. Those runs shared one PC and GPU and used a
simulated network. They do not prove two-PC direct-IP/VPN play, smooth pacing,
every frame's state or audible sound quality. Some runs had severe unequal
stalls; a smooth final FPS window is not enough to call those runs smooth.

The latest supplied report finished on 2026-11-02 for build
`943fc4631acf2c13`, with the experimental switches reported off. Its rollback
self-test restored 202 of 202 snapshots, compared 447 resimulated frames with
zero mismatches, and detected divergence in all 101 wrong-input passes. The
same-PC pair reached 6000 live frames per side at simulated RTT 150 ms, jitter
5 ms and loss 3%, with 199 hash comparisons per side, zero mismatches and zero
NETDESYNC lines. Run-average FPS was 50.4 on both sides; frame-time p99 was
136.9 ms on host and 104.8 ms on join. These figures do not establish smooth
play or a 15-minute internet test. This is an owner-supplied report, not a run
reproduced here; its logs and game data are absent from this copy.

The current edited source still needs a real build, sound-on rollback
self-test, clean-PC path-B build and the owner's two-PC acceptance run. Neither
the beta nor the new-launcher install/update path was run in this review copy.

## Settings for the acceptance run

Use the same reviewed build on both PCs and the exact profile in
[ROLLBACK_ASYMMETRY.md](ROLLBACK_ASYMMETRY.md). Coalescing is on because its
paired measurement reduced total packet traffic by about 48%. That observation
does not establish a stall fix. Diagnostics are on to collect timing evidence,
not as a speed improvement. Keep an otherwise matching coalescing-off run.

Strict hello, the audio timeline, delay matching, cost/hash profiling,
simulator-safe waiting and remote-confirmation refresh stay off for this run.
Use sound on, automatic delay, time sync on, maximum prediction 8 and no network
simulator. There is no evidence here to force a different delay, raise the
prediction cap or change the pacing thresholds.

`TEKKEN4_NET_AUTO_VS` stays off: no passing AUTO_VS pair report was supplied.
Use manual menus. Automatic menu input must not be advertised as a verified
shortcut to a fight.

## Limits players should know

- Intro-movie music is still rough.
- Online stalls can be much worse on one side. Two games on one PC showed this;
  whether it persists on two physical PCs is still an acceptance question.
- Online uses a fresh boot for each match. Allow time for boot, menus, character
  selection and loading; instant rematch and persistent opponents are not ready.
- Startup/loading pauses and occasional bright dots on the beach stage at high
  resolution are recorded issues.
- Direct-IP/VPN compatibility, two-PC sound and pacing, clean-PC installation,
  and the integrated launcher path remain unverified until the owner records
  their results for this exact candidate.

See [known issues](KNOWN_ISSUES.md) for workarounds and reporting details.

## Owner's result to complete before posting

| Item | Checked fact |
|---|---|
| Version and exact bundle checksum | Pending |
| Reviewed source revision and matching GPL-3 source | Pending |
| New-launcher install/build/offline/return check by pad | Pending |
| Two physical PCs, sound on, direct-IP/VPN route(s) actually checked | Pending |
| Both endpoints' hashes, waits, pacing and audio reviewed | Pending |
| Fresh boot for another match and disconnect/recovery | Pending |
| Package/data scans and licence/source notices | Pending |

Run the [go/no-go checklist](BETA_GO_NO_GO.md). If a required check fails or is
missing, hold the beta. Replace pending fields with the observed result rather
than treating this draft as evidence. The [announcement drafts](BETA_ANNOUNCEMENTS.md)
are for the owner to post only after the applicable gates pass.
