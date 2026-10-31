# Making a T4 release

The Sunday beta scope is offline play plus online by direct IP or VPN, inside
the new launcher, built from the player's own USA ISO. No lobby, matchmaking or
ranked mode is part of this beta. This page is the owner's procedure, not
evidence that launcher integration or the two-PC test has passed.
As of 2026-10-31, this copy has packaging scripts but no release workflow,
automatic updater or tested portable release. Do not substitute T5DR's commands,
signing keys or server configuration for missing T4 integration.

The repositories have different jobs:

| Repository | Content |
|---|---|
| [TheWishin/Tekken4Recomp-Dev](https://github.com/TheWishin/Tekken4Recomp-Dev) | Private work, history and owner release tooling |
| [TheWishin/Tekken4Recomp](https://github.com/TheWishin/Tekken4Recomp) | Player README, LICENSE and game releases; no source tree |
| [TheWishin/Tekken4Recomp-Source](https://github.com/TheWishin/Tekken4Recomp-Source) | Clean GPL-3 source mirror, LICENSE and author credits |

Only the owner publishes, tags, deploys or updates the public repositories. The
helpers below only prepare local content. In this review copy, leave changes in
the working tree: no build, game run, tag, Git write or publication.

## Required order

Preflight and two-PC gates pass -> owner tags -> draft -> owner checks
VirusTotal -> final [beta go/no-go](BETA_GO_NO_GO.md) -> publish as pre-release -> update check -> public
repositories -> announcement. The Sunday beta stays a pre-release; setting it
latest is a later promotion decision. Use the same checks for hotfixes. Stop on
a failed or missing check; do not replace a published asset or reuse a version.

1. **Preflight, before the tag.** Choose a new version and write player release
   notes describing only what was checked. Follow the input, licence and clean-PC
   gates in [RELEASE_PATH_B.md](RELEASE_PATH_B.md),
   [RELEASE_DOWNLOADS.md](RELEASE_DOWNLOADS.md) and
   [MSVC_SYSROOT.md](MSVC_SYSROOT.md). Resolve the VU1 generator's licence and
   dependency/source-offer notices first. Prepare a candidate with reviewed input
   locks, then scan the staged folder and zip:

   ```text
   powershell -NoProfile -ExecutionPolicy Bypass -File tools/make_player_zip.ps1 -Inputs release-inputs/inputs.json -Version X.Y.Z-beta.1 -Stage release-output/T4 -Zip release-output/T4-X.Y.Z-beta.1.zip
   python -B tools/package_release.py --scan-only release-output/T4
   python -B tools/package_release.py --scan-only release-output/T4-X.Y.Z-beta.1.zip
   ```

   These are future owner commands; they were not run in this copy. The packager
   requires real reviewed payloads and may start the supplied Python/Tk for its
   isolation check. It does not build the game. Check the generated `SHA256SUMS`
   and zip `.sha256` sidecar. No release signature is implemented here.

   Path B is the player route. If its reviewed inputs are unavailable, stop the
   player release. `tools/make_test_zip.ps1` is an explicit source-test fallback
   for testers who install Python 3, Git, CMake, Ninja and Visual Studio 2022 Build
   Tools with C++; it is not a portable player package or proof of path B.

   Test the exact new-launcher bundle on a clean Windows PC: start with a selected
   SLUS-20328 ISO, reject and accept the Microsoft terms, build, play, restart and
   retain settings. No BIOS is needed. Check controls, sound and every advertised
   feature. The standalone starter currently documented is `Tekken4.cmd`; its
   existence does not prove new-launcher integration. Test the integrated launch
   path too. Prepare and scan the public content before tagging so publication
   problems are found now. Run all required owner CI checks if configured; no T4
   `release_preflight.py` or workflow is supplied by this change.

   Complete the sound-on two-physical-PC direct-IP/VPN test on this exact build
   and launch path, with separate displays and normal controllers. Retain both
   logs, actual negotiated delay, route and effective switches. Follow
   [ROLLBACK_ASYMMETRY.md](ROLLBACK_ASYMMETRY.md), including its coalescing-OFF
   reference and role swap. Severe one-sided stalls remain a no-go until this
   test establishes acceptable play on both PCs. Keep `TEKKEN4_NET_AUTO_VS=0`
   unless its matching sound-on pair and save-path cases in
   [DIRECTFIGHT_T4.md](DIRECTFIGHT_T4.md) passed on this build. No such pass was
   supplied here. Boot a fresh game for each online match; do not promise warm
   rematches, persistent opponents or trusted winner/score reporting.

2. **Tag.** After preflight and required checks pass, the owner tags the reviewed
   private release revision as `vX.Y.Z` (or a unique preview suffix). Record the
   revision and input locks with the release evidence. No agent creates or pushes
   this tag. If the owner wires up CI, verify its draft-only behaviour first.

3. **Draft.** In `Tekken4Recomp`, prepare a draft marked **pre-release** with the
   exact checked new-launcher bundle, checksum files and release notes. Include
   the matching source revision and source-mirror link. Confirm the bundle has no
   ISO, ELF, DATA.BIN, BIOS, generated game code, built game executable or keys.
   The runtime containing game code is built on the player's PC. Review the
   actual draft assets; do not assume a workflow created them correctly.

4. **Owner checks VirusTotal.** The owner downloads the draft asset and checks
   that exact file on VirusTotal. Keep the result and checksum. While any scanner
   flags it, leave it a draft, investigate/report the detection and check again.
   An antivirus result does not replace the game-data and licence reviews.

5. **Publish as pre-release.** Only after the owner's VirusTotal check, publish
   with **Set as a pre-release** still checked. Do not mark it latest yet.

6. **Update check.** From each of the last two supported releases, exercise the
   new launcher's real player update path to this pre-release, using its tag and
   the owner's own ISO. Check download verification, extraction, saved ISO path
   and settings, any required rebuild, launch with that ISO selected, and that
   the launcher and game stay usable. Also check interrupted/failed updates and
   recovery. For the first release, record that no previous T4 release exists and
   test fresh installation plus the applicable new-launcher upgrade path.
   This copy has no T4 update-drill tool or proven updater: the owner must supply
   and verify that integration before promotion. A failed check leaves the
   release a pre-release; fix and issue a new version. Do not claim an automatic
   update interval, signature check or rollback without proof.

7. **Later stable promotion only.** The Sunday beta remains a pre-release.
   After separate stable acceptance and the update checks pass, the owner edits the
   release, clears **Set as a pre-release** and selects **Set as the latest
   release**. Preview/RC builds intended only for manual testing stay pre-releases.
   Check the release page and verify what the new launcher actually offers.

8. **Services and metadata.** Direct-IP/VPN play does not require a T4 lobby
   deployment. Record lobby/server deployment as not applicable for this beta;
   online acceptance still requires the two-PC test above. If the new launcher
   needs release metadata, the owner updates and verifies that separately. Keep
   T4 separate from T5DR's service, keys and data. No deploy command is supplied
   here. `lobby/` is absent and must not enter the source mirror. Lobby and ranked
   work in other documents is outside the advertised beta scope.

9. **Public repositories.** Prepare fresh local output directories:

   ```text
   python -B tools/make_public_repo.py --out release-output/player
   python -B tools/publish_source.py --ref vX.Y.Z --out release-output/source
   ```

   The first makes the game repository's player files. The second exports the
   specified revision without development history and excludes private lobby
   code, local configuration, logs and generated code. Public output must contain
   no game data or images. The tools refuse unsafe content; historical
   documentation can trigger the scan too. Fix findings in
   a reviewed revision and repeat preflight rather than bypassing the scan.
   Review both outputs, retain LICENSE and author credits, and verify that the
   source corresponds to the distributed project code. The owner carries the
   reviewed files into the two public repositories separately. These scripts
   never commit or publish. Check the public README, download, checksums and
   GPL-3 source link before announcing.

10. **Announcement.** Use [BETA_RELEASE_NOTES.md](BETA_RELEASE_NOTES.md),
    [KNOWN_ISSUES.md](KNOWN_ISSUES.md) and the English Discord/tweet drafts in
    [BETA_ANNOUNCEMENTS.md](BETA_ANNOUNCEMENTS.md). Replace placeholders with
    checked facts only after the go/no-go passes. The owner posts the messages;
    these instructions send nothing. If online fails, the scoped beta is a no-go;
    an offline-only release needs its own explicitly revised notes and decision.

Record the checks that passed and the ones still pending. A source-only review
and fake-file scanner tests cannot prove packaging, clean-PC builds, gameplay,
updates, new-launcher integration or server deployment.
