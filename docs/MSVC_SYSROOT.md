# Microsoft sysroot for the portable T4 build

`tools/fetch_msvc_sysroot.py` is a Windows-only, standard-library Python fetcher.
It writes the layout used by `toolchain_env.cmd`. It never installs Visual Studio
and does not execute downloaded MSI installers. It reads their `Directory`,
`Component`, `File` and `Media` tables through Windows' read-only MSI database API,
then uses Windows' `expand.exe` on the referenced cabinets. Only headers and x64
libraries are copied to `toolchain/msvc` and `toolchain/winsdk`.

No Microsoft payload, metadata lock, extraction or build was downloaded or run in
this working copy. This is an untested release implementation, not a clean-PC pass.

## Maintainer preparation

Before packaging, use a maintainer Python to resolve a new metadata lock:

```powershell
python tools/fetch_msvc_sysroot.py --make-lock tools/msvc_sysroot.lock.json
```

Use `--crt-version` and `--sdk-version` to select exact versions. Otherwise lock
generation selects the newest matching packages in the VS 2022 release channel.
The player uses the resulting fixed lock; the player never resolves a moving
channel. Existing locks are not overwritten. Review and keep the lock for each
release, including the URLs, sizes, hashes and applicable Microsoft terms. Do not
ship without that review and a clean-PC fetch/build test.

The maintainer downloads these metadata documents:

| Download | Source | Size | Licence / terms |
|---|---|---|---|
| VS 2022 channel manifest | `https://aka.ms/vs/17/release/channel` | Not fixed | Microsoft service metadata |
| VS package manifest (`.vsman`) | Exact Microsoft URL from the channel | Not fixed | Microsoft service metadata |

The lock records the actual SHA-256 of both metadata documents for audit. The VS
service's advertised package-manifest hash has historically not matched its served
bytes; it is recorded separately, not used as a payload-integrity exception. The
initial metadata trust is HTTPS to Microsoft's service plus maintainer review of
the resulting lock. Every downloaded VSIX/MSI/CAB is checked against its locked
SHA-256 **and** exact size before extraction. Unknown layouts stop with an error.

## Player downloads and consent

The launcher must show the applicable Microsoft licence terms and obtain an
explicit acceptance before invoking:

```powershell
.\python\python.exe -I tools/fetch_msvc_sysroot.py --accept-license
```

`--print-license` prints the Microsoft terms/download links without network access.
The Build Tools link is `https://go.microsoft.com/fwlink/?LinkId=2086102`.
The SDK page is `https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/`;
it is a download page, not itself a licence text. The owner must verify and present
the actual applicable SDK terms with the selected release before publishing.
Acceptance is recorded in `toolchain/sysroot.json`, bound to the lock's SHA-256.
`--check` verifies the installed files against their recorded hashes offline.

| Player download | Exact package / payload selection | Source, size and licence |
|---|---|---|
| MSVC STL and CRT headers | `Microsoft.VC.<version>.CRT.Headers.base` VSIX | Microsoft URL, SHA-256 and byte size in the release lock; Microsoft terms |
| MSVC x64 desktop libraries | `Microsoft.VC.<version>.CRT.x64.Desktop.base` VSIX | Same |
| MSVC x64 Store libraries | `Microsoft.VC.<version>.CRT.x64.Store.base` VSIX; only `oldnames.lib` is used as fallback | Same |
| SDK desktop headers | `Windows SDK Desktop Headers x86-x86_en-us.msi` and `Windows SDK Desktop Headers x64-x86_en-us.msi` | Same; the x86-named package contains common headers needed by x64 too |
| SDK common/Store headers | `Windows SDK for Windows Store Apps Headers-x86_en-us.msi` | Same |
| SDK x64 libraries | `Windows SDK Desktop Libs x64-x86_en-us.msi` | Same |
| UCRT headers and libraries | `Universal CRT Headers Libraries and Sources-x86_en-us.msi` | Same; only headers/x64 libraries kept |
| SDK cabinets | Only `.cab` files named by those selected MSIs' `Media` tables | Exact Microsoft URLs, SHA-256 and byte sizes in lock; Microsoft terms |

The lock includes cabinet metadata for the selected SDK so that no unverified
URL can be constructed at runtime. It does not download all of those cabinets.
The installed marker lists every payload actually downloaded, including cabinet
names, source URLs and sizes. Until a lock is resolved and its selected MSIs are
inspected, an exact cabinet list and total download size cannot be stated. The
plan's 150-300 MB network / 0.4-0.8 GB installed figures remain estimates.

Cached payloads and extraction work are retained on the player's PC under
`toolchain/sysroot-cache` and `toolchain/sysroot-work`. This uses additional disk
space beyond the final sysroot estimate. Failed attempts are retained too. No
Microsoft sysroot, cache or extraction directory may be packaged or redistributed.
An unmarked existing `msvc`/`winsdk` folder or a hash mismatch stops the fetcher;
use a new release folder, preserving the old attempt for diagnosis.

## Required clean-PC checks

1. Resolve and review the exact lock and Microsoft terms on the maintainer's PC.
2. On Windows 10 and Windows 11, without VS, Git, Python, CMake or Ninja installed,
   decline consent and verify that no payload is downloaded; then accept.
3. Verify VSIX and MSI layouts for those exact versions, all referenced cabinet
   hashes, header casing, required x64 libraries and the final offline `--check`.
4. Corrupt a cached payload and a final header; verify both paths refuse to proceed.
   Interrupt a transfer and retry. Check proxy and TLS-certificate behavior.
5. Build from an ISO through the launcher with a bare PATH, and rebuild offline.
   Check a path containing spaces/non-ASCII characters and a non-admin account.
6. Measure network and peak disk use, including cache/work directories. Confirm
   no compiler/SDK installations or registry writes occurred.
7. Prove clang-cl can build the recompiler, runtime, generated game and native VU1
   blocks; run the game and compare rendering, sound, input and speed with MSVC.

Embedded or split cabinets currently fail closed. If Microsoft's selected SDK
uses either, update the extraction implementation and repeat these checks.

Implementation references: [Microsoft VS channel URI documentation](https://learn.microsoft.com/en-us/visualstudio/install/command-line-parameter-examples?view=vs-2022),
[Windows expand syntax](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/expand),
and [xwin's upstream package-layout implementation](https://github.com/Jake-Shadle/xwin/blob/main/src/lib.rs).
No xwin or T5DR source is bundled or executed.

Licence gate added in this change: `--make-lock` writes `license_reviewed: false` and empty `license_terms`.
The owner must obtain and review the actual applicable terms (the SDK landing page is not the licence text).
Set `license_reviewed` to true only after review, and populate these records in the reviewed lock:

```json
"license_terms": {
  "microsoft-build-tools": {"path": "LICENSES/microsoft-build-tools.txt", "sha256": "<64 lowercase hex>", "url": "https://<actual terms source>"},
  "microsoft-windows-sdk": {"path": "LICENSES/microsoft-windows-sdk.txt", "sha256": "<64 lowercase hex>", "url": "https://<actual terms source>"}
}
```

Supply those exact UTF-8 texts as the matching licence inputs to the packager. The launcher displays both complete
texts in a scrollable window before acceptance; `--print-license` prints them for command-line users. The installer
and offline checker verify their hashes. Missing/unreviewed/changed terms stop the fetch before any payload request.

## 0.1.3: first real run (2026-11-06)

The fetcher ran for real for the first time (lock CRT 14.44.17.14, SDK 10.0.26100, `tools/msvc_sysroot.lock.json`
in the release). Findings, fixed in the script:

- The VS manifest's `size` is not always the served byte count (a VSIX listed 2,128,977 bytes was served as
  2,116,223 with the listed SHA-256): the SHA-256 decides, the size only bounds the download.
- SDK 10.0.26100 spreads what the build needs over more MSIs: `windef.h` and the other `include/shared` headers come
  from "Windows SDK for Windows Store Apps Headers OnecoreUap", `kernel32.lib` & co. from "Windows SDK for Windows
  Store Apps Libs", `windowsx.h` from "Windows SDK OnecoreUap Headers x86/x64". All four are in the lock now.
- Windows' MSI reader and expand.exe have no long-path support: cache and work files use short names
  (20 hex digits of the SHA-256), so install folders of 115 characters work.

Measured: about 240 MB download, 757 MB installed (msvc 217 MB, winsdk 540 MB), 40-90 s. `--check` verifies offline.
The licence texts were taken from Microsoft's pages on 2026-11-06 (Build Tools: the VS 2022 Build Tools licence
document; SDK: learn.microsoft.com/legal/windows-sdk/license) and still need the owner's review.

## 0.1.3: one shared copy per PC, never the PC's Visual Studio (2026-11-06, day)

- **Shared cache.** The sysroot is unpacked once per PC into `%LOCALAPPDATA%/OpenRecomp/cache/msvc-<16 hex of the lock's
  SHA-256>/` (`OPENRECOMP_HOME/cache` when the launcher runs with its own home; `T4_MSVC_CACHE` for tests), not into the
  install folder. Every install, reinstall and update with the same lock uses it: nothing is downloaded twice. The
  downloaded payloads stay in `cache/msvc-downloads/` (a damaged extraction is unpacked again without the network).
  "Uninstall OpenRecomp completely" removes it with the rest of `%LOCALAPPDATA%/OpenRecomp`. A sysroot an earlier test
  build put into `toolchain/` stays in use (`sysroot_dir`).
- **Verified once.** After unpacking, every file's SHA-256 is checked against the marker and `verified.json` keeps
  each file's size and modification time; later checks hash only files whose size or time changed (no-change rebuild:
  37 s of hashing -> under a second). The atomic rename of the finished folder makes two builds at once safe.
- **Faster first download.** VSIX/MSI files, then the cabinets their Media tables name, are fetched six at a time;
  progress lines `Microsoft download N% (x of y MB)` reach the launcher's Build card.
- **_MSC_VER pinned.** clang-cl takes `_MSC_VER` from whatever Visual Studio it finds through Windows' setup API (not
  PATH): 19.44 with VS 2022, 19.51 with VS 2026, 19.33 with none. That is not part of the build id, so two players could
  get the same id with differently preprocessed STL/library code. `tools/t4_toolchain_clangcl.cmake` now passes
  `-fms-compatibility-version=19.44.35229` (the fetched CRT/STL 14.44), and `build_game.py` sets `VCToolsInstallDir` to
  the fetched sysroot so clang-cl and lld-link never look for an installed Visual Studio. The release build keeps only
  an allowlist of the PC's environment (`RELEASE_KEEP`).
