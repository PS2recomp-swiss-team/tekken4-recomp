# Path B: release preparation and proof still needed

2026-10-30: scripts implemented, no download, build, package or game run performed in this working copy.
The old E2E result is a developer/MSVC build, not proof of this release path.

## Maintainer preparation

Use `tools/package_release.py` with a reviewed local input lock, a new staging directory and a new zip path.
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

The zip uses `Tekken4.cmd` as its starter. A native signed `Tekken4.exe` is a later owner decision; no compiled starter
is created or shipped by this source change. No prebuilt recompiler is required: its sources and all its dependencies
are included, and the player's compiler builds it. The game runtime is always built on the player's PC.

Only the copied release PS2Recomp CMake file is adapted to honour the local FFmpeg zip. The input source and numbered
patches stay untouched. `tools/prepare_portable_tree.py` refuses a changed upstream FFmpeg declaration.
Runtime and recompiler FetchContent sources come from `deps/fetch`; CMake runs disconnected. There should be no
dependency download during a player's CMake build. The payload lock and archive scans are release gates, not a malware
or copyright detector: the maintainer must review provenance and licence terms as well.

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
   licence. Review every dependency's notices and the exact FFmpeg LGPL build/source offer, including bundled libraries.
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

## Questions for the owner

* Confirm Microsoft terms and the pinned MSVC/SDK selection; supply the exact reviewed texts and their source URLs.
* Supply the VU1 generator licence resolution and exact dependency/source-offer notices before publication.
* Accept a `.cmd` starter for the first release, or supply a reviewed native starter and signing plan.
* Choose Release versus current RelWithDebInfo, CPU/AVX baseline, and whether a future game-free prebuilt recompiler
  should skip its build. Current scripts preserve the existing runtime flags.
* Decide whether extraction can omit DATA.BIN, where to publish checksums, and when updater support is required.
