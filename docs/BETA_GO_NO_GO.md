# Sunday T4 beta: go or no-go

Decision sheet for the maintainer after the two-PC test. Allow about five
minutes to review evidence already collected; this is not a five-minute
replacement for a clean-PC build, licence review or full play test.

Scope: offline plus direct-IP/VPN online inside the new launcher, from each
player's own Tekken 4 USA v1.00 ISO (SLUS-20328). No lobby, ranked mode or
matchmaking. Release as a beta pre-release. No build or game was run in this
source-only copy, and no two-PC pass was supplied.

Latest supplied owner verification finished `2026-11-02T08:02:46`: draft
`363433d330`, merge base `8b15202341` (branch base `7992837fc3`), onto
`us-slus20328` at `c17fd979ca`; clean merge, build OK in 165 seconds,
build ID `943fc4631acf2c13`, experimental switches OFF. The self-test reported
6600 wall / 5572 logical frames, 232 good restores, zero bad restores and
zero mismatches in 514 resim frame comparisons; all 116 wrong-input checks
diverged. The simulated 150 ms RTT, 5 ms jitter, 3% loss pair on one PC
reached live/logical 6000 on both peers, with 199 hash comparisons and zero
mismatches each, and no NETDESYNC lines. Run-average FPS was 52.1/52.2
(host/join); displayed-frame p99 was 119.6/100.0 ms. Host/join stalls were
0/79 (0/2843 ms), and restore-and-resim maximum was 144.82/53.82 ms.
See [switch evidence](ONLINE_SWITCH_EVIDENCE.md) for the detailed supplied
summary. These results support the covered state checks; they do not
establish playable internet Versus, a 15-minute two-PC pass, or acceptance
of this working tree. This verification was not reproduced here.

The launcher profile differs from that OFF run: `launcher/t4core.py` clears
inherited network experiments before `tools/net_play.ps1` normally enables
COALESCE=1 and DIAG=1. Runtime experiment fallbacks remain OFF. No defaults
were changed here without a build/game test. Retain the earlier traffic-saving
rationale in [ROLLBACK_ASYMMETRY.md](ROLLBACK_ASYMMETRY.md), but require new
evidence for the exact launcher profile before approving it for release.

## Evidence to have before this review

- Exact candidate version, reviewed source revision, build IDs on both PCs,
  input locks, zip SHA-256 and matching source export. Rebuild changed source;
  the supplied `363433d330` results do not validate this working tree.
- Resolved VU1 generator provenance/licence and dependency notices/source
  offers; reviewed Microsoft terms and pinned payload lock. No Microsoft
  sysroot in the zip. See [RELEASE_PATH_B.md](RELEASE_PATH_B.md).
- Path-B staged-folder and zip scans passed; public README/LICENSE and clean
  source scans passed. No game data, BIOS, generated game code, built game
  runtime, saves, keys or screenshots in distributed project inputs. Public
  repository outputs contain no images.
- Exact new-launcher bundle passed a clean Windows installation/build from a
  supported own ISO, licence reject/accept, offline play, controls, sound,
  settings retention and applicable update/recovery checks. A standalone
  `Tekken4.cmd` run alone is insufficient.
- Two physical PCs tested that exact candidate with separate displays, sound
  on, real controllers, no simulator or scripted/fuzz input. Keep both logs,
  PC facts, route (direct IP or VPN, including relay status if applicable),
  actual delay and effective switches. Only advertise routes actually tested.

## Five-minute decision

Any unchecked required item means **NO-GO** for the scoped beta. Missing proof
is pending, not a pass. Record an evidence file or test note beside each box.

- [ ] Candidate identity and packaging/licence/clean-PC evidence above match
  the files being released. No changed code, stale zip or unresolved scan finding.
- [ ] Both PCs used the Sunday profile in
  [ROLLBACK_ASYMMETRY.md](ROLLBACK_ASYMMETRY.md): COALESCE=1, DIAG=1,
  STRICT_HELLO/AUDIO_TIMELINE/DELAY_MATCH/COST_PROFILE/HASH_PROFILE/
  SIM_SAFE_WAIT/REFRESH_RC=0, simulator empty, delay auto, time sync on,
  max prediction 8, early/lazy/local pad on and sound on. No unrecorded tuning.
- [ ] `TEKKEN4_NET_AUTO_VS=0`. Enable it only with retained evidence for its
  exact matching sound-on pair and all required boot/save/handoff cases in
  [DIRECTFIGHT_T4.md](DIRECTFIGHT_T4.md), including both physical PCs.
  No such evidence was supplied, so the candidate default remains off.
- [ ] Offline boot, menus, character/stage selection, a complete fight, input
  and sound worked through the new launcher with the player's selected ISO.
- [ ] Online host/join connected through the advertised direct-IP/VPN route;
  both players reached VS manually, selected characters/stage and finished
  at least 15 minutes of Versus with usable input and sound. Both peers report
  no hash mismatch or NETDESYNC. Clean hashes alone are insufficient if either
  player cannot play. Both logs were collected and sent to Main.
- [ ] Both sides were acceptably paced throughout the test, without repeated
  disruptive one-sided stalls or sustained slowdown. Review both logs and
  player observations, not only a final FPS window. Retain the sound-on
  COALESCE=0 reference and a role-swapped cold session requested by the
  asymmetry protocol. No claim that coalescing fixed stalls.
- [ ] A second match worked after closing and freshly booting both games;
  host/join role swap and disconnect/exit recovery worked. No persistent
  opponent, warm rematch, automatic result or ranked promise appears in notes.
- [ ] [Beta notes](BETA_RELEASE_NOTES.md) and
  [known issues](KNOWN_ISSUES.md) match actual results: rough intro music,
  measured one-PC stalls, loading pauses and boot per online match are disclosed.
  Launcher, download/source links and checksums point to the exact candidate.
- [ ] The owner checked the exact draft asset on VirusTotal under the procedure
  in [RELEASING.md](RELEASING.md). It stays a pre-release; no automatic latest
  promotion, lobby deployment or announcement is implied by this checklist.

Record: `GO / NO-GO`, date, owner, candidate version/source/build ID, zip hash,
tested routes, evidence locations, remaining issues and AUTO_VS state.
GO authorizes the owner to continue the release procedure; it does not publish
anything. NO-GO leaves the draft unreleased. Fix the failure, choose a new
version if an asset was already published, and repeat the affected checks.

Current source-review status: **NO-GO pending owner evidence**. The two-PC
sound-on result, clean-PC path-B/new-launcher proof, real payload scans and
licence sign-off cannot be established here. See [RELEASING.md](RELEASING.md)
for the full order and [BETA_ANNOUNCEMENTS.md](BETA_ANNOUNCEMENTS.md) for drafts.
