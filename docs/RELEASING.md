# Making a T4 release

T4 follows T5DR's release order and ships inside the new launcher. This page is
the owner's procedure, not evidence that the launcher integration is finished.
As of 2026-10-30, this copy has packaging scripts but no release workflow,
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

Preflight passes -> owner tags -> draft -> owner checks VirusTotal -> publish as
pre-release -> update check -> owner sets latest -> server deploy -> public
repositories -> Discord. Use this order for hotfixes too. Stop on a failed or
missing check; do not replace an already published asset or reuse a version.

1. **Preflight, before the tag.** Choose a new version and write player release
   notes describing only what was checked. Follow the input, licence and clean-PC
   gates in [RELEASE_PATH_B.md](RELEASE_PATH_B.md),
   [RELEASE_DOWNLOADS.md](RELEASE_DOWNLOADS.md) and
   [MSVC_SYSROOT.md](MSVC_SYSROOT.md). Resolve the VU1 generator's licence and
   dependency/source-offer notices first. Prepare a candidate with reviewed input
   locks, then scan the staged folder and zip:

   ```text
   python -B tools/package_release.py --inputs release-inputs/inputs.json --version X.Y.Z --stage release-output/T4 --zip release-output/T4-X.Y.Z.zip
   python -B tools/package_release.py --scan-only release-output/T4
   python -B tools/package_release.py --scan-only release-output/T4-X.Y.Z.zip
   ```

   These are future owner commands; they were not run in this copy. The packager
   requires real reviewed payloads and may start the supplied Python/Tk for its
   isolation check. It does not build the game. Check the generated `SHA256SUMS`
   and zip `.sha256` sidecar. No release signature is implemented here.

   Test the exact new-launcher bundle on a clean Windows PC: start with a selected
   SLUS-20328 ISO, reject and accept the Microsoft terms, build, play, restart and
   retain settings. No BIOS is needed. Check controls, sound and every advertised
   feature. The standalone starter currently documented is `Tekken4.cmd`; its
   existence does not prove new-launcher integration. Test the integrated launch
   path too. Prepare and scan the public content before tagging so publication
   problems are found now. Run all required owner CI checks if configured; no T4
   `release_preflight.py` or workflow is supplied by this change.

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

7. **Owner sets latest.** After the update checks pass, the owner edits the
   release, clears **Set as a pre-release** and selects **Set as the latest
   release**. Preview/RC builds intended only for manual testing stay pre-releases.
   Check the release page and verify what the new launcher actually offers.

8. **Server deploy.** The owner/coordinator deploys the reviewed T4 server change
   or release metadata, then checks health and compatible build identity. Keep
   this separate from T5DR's service, keys and data. No deploy command is supplied
   here: `lobby/` is absent from this copy and must not enter the source mirror.
   [LOBBY.md](LOBBY.md) and the server handoff describe local work and open items,
   not a deployed public service. Two-PC online play and public lobby availability
   remain unproven here. If shipping offline, record server deployment as not
   applicable and say clearly that online is unavailable.

9. **Public repositories.** Prepare fresh local output directories:

   ```text
   python -B tools/make_public_repo.py --out release-output/player
   python -B tools/publish_source.py --ref vX.Y.Z --out release-output/source
   ```

   The first makes the game repository's player files. The second exports the
   specified revision without development history and excludes images, private
   lobby code, local configuration, logs and generated code. It refuses unsafe
   content; historical documentation can trigger the scan too. Fix findings in
   a reviewed revision and repeat preflight rather than bypassing the scan.
   Review both outputs, retain LICENSE and author credits, and verify that the
   source corresponds to the distributed project code. The owner carries the
   reviewed files into the two public repositories separately. These scripts
   never commit or publish. Check the public README, download, checksums and
   GPL-3 source link before announcing.

10. **Discord text.** Replace every bracketed field with checked facts, then the
    owner posts it. This procedure sends no message:

    > Tekken 4 Recomp [version] is available in the new launcher:
    > https://github.com/TheWishin/Tekken4Recomp/releases/tag/[tag]
    > You need your own Tekken 4 USA ISO (SLUS-20328). No BIOS or game data is
    > included. [Brief changes and known issues.] Online: [state exactly what
    > passed; otherwise unavailable in this release]. GPL-3 source:
    > https://github.com/TheWishin/Tekken4Recomp-Source

Record the checks that passed and the ones still pending. A source-only review
and fake-file scanner tests cannot prove packaging, clean-PC builds, gameplay,
updates, new-launcher integration or server deployment.
