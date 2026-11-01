# Path B: release preparation and proof still needed

2026-11-02: scripts implemented, no download, build, package or game run performed in this working copy.
The old E2E result is a developer/MSVC build, not proof of this release path.

Sunday beta scope is offline plus online by direct IP or VPN in the new launcher,
from the player's own USA ISO. No lobby or ranked. The owner's two-PC result,
the exact integrated launcher, and clean-PC packaging remain release gates.
Use [BETA_GO_NO_GO.md](BETA_GO_NO_GO.md) after the test; player-facing limits are
in [BETA_RELEASE_NOTES.md](BETA_RELEASE_NOTES.md) and [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

## Entry-point checks in this copy, 2026-11-02

- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/make_player_zip.ps1`
  exited 1: reviewed `-Inputs` and `-Version` are required. No portable zip,
  source fallback or download was attempted.
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/make_player_zip.ps1 -ScanOnly dist/sunday/tekken4-sunday-test-20261031-205628-895451.zip`
  exited 1: the maintainer needs Python 3.12+ to run packaging/scanning.
  The archive was not scanned by this command.

These are real wrapper refusals, not passing package or build tests. The private
Python/Tk check, staged-folder/zip scans and clean build with installed Python,
Git and Visual Studio hidden remain unrun. The owner must supply reviewed inputs
and run the exact candidate on clean Windows. Until that passes, do not advertise
a player zip that builds without those installed tools. If using the source test
archive, state the installed-tool requirements in the fallback section below.

## Maintainer preparation

Use `tools/make_player_zip.ps1` with a reviewed local input lock, a new staging directory and a new zip path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/make_player_zip.ps1 -Inputs release-inputs/inputs.json -Version X.Y.Z-beta.1 -Stage release-output/T4 -Zip release-output/T4-X.Y.Z-beta.1.zip
```

This is a future maintainer command, not a command run in this copy. The wrapper
uses `tools/package_release.py` for path B. It must stop when real reviewed inputs
are missing; it must not substitute a source-only archive and call it portable.
It does not clone, build or change the input trees. Exact lock fields, download sources, sizes and licences are in
[RELEASE_DOWNLOADS.md](RELEASE_DOWNLOADS.md); Microsoft preparation is in [MSVC_SYSROOT.md](MSVC_SYSROOT.md).
Prepare clean PS2Recomp sources at the full pinned revision, apply every current two-digit patch in name order,
and record the head and patch hashes in `.t4-vendored.json`. Do not take a used runtime build tree.
The input hash lock identifies the exact prepared files. A receipt is an attestation by the maintainer; it does not prove
that a patch was actually applied. Review the source before signing off the lock.

The private Python input must include tkinter, `_tkinter`, Tcl/Tk and its licence texts. The embeddable Python zip alone
does not suffice. The tool payload helper checks pinned archive SHA-256 before extraction and retains notices.
The packager tests the staged Python with a bare PATH during a future packaging run.
Microsoft headers and libraries must not be provided as package inputs: the player fetches them after acceptance.
Keep the reviewed Microsoft payload lock in the release; it prevents the player from resolving a changing manifest.

The path-B backend zip includes `Tekken4.cmd` as its standalone starter. The beta
must also prove the new launcher's T4 install/build/offline/direct-IP/VPN path;
the standalone starter alone does not satisfy that gate.
Its new standalone Host/Join controls use the existing direct-IP preflight and
runtime path; these controls were not run here and do not supply the external
shared-launcher integration.
A native signed `Tekken4.exe` is a later owner decision; no compiled starter
is created or shipped by this source change. No prebuilt recompiler is required: its sources and all its dependencies
are included, and the player's compiler builds it. The game runtime is always built on the player's PC.

Only the copied release PS2Recomp CMake file is adapted to honour the local FFmpeg zip. The input source and numbered
patches stay untouched. `tools/prepare_portable_tree.py` refuses a changed upstream FFmpeg declaration.
Runtime and recompiler FetchContent sources come from `deps/fetch`; CMake runs disconnected. There should be no
dependency download during a player's CMake build. The payload lock and archive scans are release gates, not a malware
or copyright detector: the maintainer must review provenance and licence terms as well.

## Explicit source fallback

If the path-B payloads or clean-PC gates are unavailable, the maintainer can use
`tools/make_test_zip.ps1` for a source test archive. This is for testers who install
Python 3 with tkinter, Git, CMake, Ninja and Visual Studio 2022 Build Tools with
C++, MSVC and the Windows SDK themselves. They build from their own supported ISO.
The source test archive is a CLI kit without the launcher; use its `TEST_ONLINE_DE.txt`.
It contains no bundled compiler/runtime tools or game data and is not the promised
portable player zip. A successful source test cannot approve path B or shared-launcher integration.

## Build switch and paths

`build_game.ps1` selects the portable prototype when `toolchain/toolchain.json` exists. Without that marker it keeps
the existing developer pipeline and `TEKKEN4_SRC` override. The `.cmd` build entry points use the same switch.
In a bundle, build, stage, run and launcher use `deps/ps2recomp`, even if an old `TEKKEN4_SRC` is inherited.
Toolchain paths resolve relative to the unpacked folder, including paths with spaces. Portable C/C++ targets use the
static MSVC CRT/STL so our executables do not require a separately installed VC runtime; check the supplied FFmpeg
DLLs and Python dependencies on the clean PC too. The bundled CMake/Ninja take
priority over installed tools; VU1 generation uses the private Python explicitly. Netplay build IDs work without Git.

BUILD GAME presents the complete owner-reviewed, hash-locked Microsoft licence texts before passing `-AcceptMicrosoftLicense` to the build script.
For the command line, review the linked terms first and explicitly pass that switch to authorize the fetch.
Dry run never authorizes or performs downloads. A partial or corrupt sysroot must fail the offline integrity check.

Developer experiment helpers also use script-relative checkout paths and explicit overrides. Historical docs and patch
contexts can still name old machines; those are records, not player inputs. The release includes only required tools.

## Clean-PC acceptance checklist (owner runs later)

1. Resolve the VU1 generator's licence/provenance: its current header says the copied upstream main branch had no
   licence. Use the local evidence and owner questions in [THIRD_PARTY.md](THIRD_PARTY.md).
   Review every dependency's notices and the exact FFmpeg LGPL build/source offer, including bundled libraries.
2. Prepare reviewed input locks and real payloads. Verify official archive hashes, extracted tool names, licence texts,
   private Python/Tcl/Tk isolation, source-only trees and all ordered patches. Produce a zip and review both scan results
   and `SHA256SUMS`. Feed renamed disc files, ELF, BIOS, generated C++, compiled game code, nested archives and Microsoft
   sysroots into negative scanner tests in a disposable test folder outside this clean source copy.
3. On Windows 10/11 x64 with no Python, Git, CMake, Ninja, VS or SDK installed, extract to a writable path containing
   spaces and non-ASCII characters. Start `Tekken4.cmd`, select a supported US ISO, reject the licence prompt, and prove
   no Microsoft payload was fetched. Accept next time; verify payload sizes/hashes, cabinet/MSI extraction without admin,
   retries after interrupted downloads, retained terms and the installed sysroot receipt. Check proxies and TLS failures.
4. Build once from a clean bundle in one invocation. Verify recompiler, generated functions, native VU1 blocks,
   resource compilation/linking/manifest embedding, FFmpeg DLL staging, CRT dependencies and the runtime executable.
   Then disconnect the network and prove an already fetched sysroot needs no further downloads. Check a failed/resumed
   build, a second up-to-date build, and that an installed developer toolchain cannot hide a missing bundled component.
5. Move a fresh bundle to another drive and repeat. Test inherited `TEKKEN4_SRC`/PATH/Python variables, then compare
   a developer checkout build without the marker against its previous behaviour. Check that netplay build IDs agree
   across two identical portable builds on different paths and differ when compiler inputs change.
6. Play through boot, character selection and fights on all stages; measure frame timing against MSVC, listen to sound,
   test controllers/settings/saves, and compare graphics and native VU1 behaviour. Test the advertised CPU baseline.
7. Test the exact new launcher with offline play and two physical PCs over the advertised direct-IP/VPN route,
   with sound on and matching build IDs. Use cold boot for every online match, test both host/join roles,
   and retain both logs. Compare COALESCE ON/OFF as described in [ROLLBACK_ASYMMETRY.md](ROLLBACK_ASYMMETRY.md).
   No supplied report validates `TEKKEN4_NET_AUTO_VS`; leave it off unless its separate matching pair passes.
   Do not claim one-sided stalls are fixed from zero hashes or a final 60 fps window alone.

## Questions for the owner

* Confirm Microsoft terms and the pinned MSVC/SDK selection; supply the exact reviewed texts and their source URLs.
* Supply the VU1 generator licence resolution and exact dependency/source-offer notices before publication.
* Accept a `.cmd` starter for the first release, or supply a reviewed native starter and signing plan.
* Choose Release versus current RelWithDebInfo, CPU/AVX baseline, and whether a future game-free prebuilt recompiler
  should skip its build. Current scripts preserve the existing runtime flags.
* Decide whether extraction can omit DATA.BIN, where to publish checksums, and when updater support is required.
