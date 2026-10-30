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
