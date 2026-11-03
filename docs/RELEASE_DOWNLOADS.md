# Path B: inputs, downloads and release gates

Status 2026-10-30: scripts written; no payload downloaded, packaged, built or run here.
The package tool takes reviewed local inputs. It never clones, builds or installs software.
The player gets their own private Python with Tk, compiler, CMake, Ninja and source dependencies.
Only Microsoft's headers/libraries are fetched on the player's PC, after licence acceptance.
No game data, BIOS, translated code or built game executable may enter the zip.

## Maintainer downloads (become zip inputs)

Every local input must have a SHA-256, version and source URL in the input lock below.
Directory digests pin the exact supplied content, not just a movable Git tag.
The helper `tools/fetch_llvm.py` additionally checks official pinned archive hashes before extraction.
It defaults to LLVM; `--component cmake` and `--component ninja` use the other pins.
Its cache and output must be new/reviewed directories; a failed download is kept and refused.
These commands are instructions for a future maintainer run, not operations performed here.

| Input | Exact source/version | Download size, when documented | Licence/notices to keep |
|---|---|---|---|
| LLVM | [23.1.3 Windows x64 archive](https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.3/clang+llvm-23.1.3-x86_64-pc-windows-msvc.tar.xz) | 860 MB, GitHub display | [Apache-2.0 with LLVM exception](https://github.com/llvm/llvm-project/blob/llvmorg-23.1.3/LICENSE.TXT), all included third-party notices |
| CMake | [4.4.4 Windows x64 zip](https://github.com/Kitware/CMake/releases/download/v4.4.4/cmake-4.4.4-windows-x86_64.zip) | 51.9 MB, GitHub display | BSD-3-Clause and bundled third-party notices |
| Ninja | [1.13.2 Windows x64 zip](https://github.com/ninja-build/ninja/releases/download/v1.13.2/ninja-win.zip) | 285 KB, GitHub display | [Apache-2.0](https://github.com/ninja-build/ninja/blob/v1.13.2/COPYING); supply COPYING separately if binary zip lacks it |
| CPython + Tcl/Tk | Reviewed full x64 [python.org distribution](https://www.python.org/downloads/windows/), not the embeddable zip | Owner selects current full version; historical [3.12.10](https://www.python.org/downloads/release/python-31210/) installer is 25.7 MB | PSF/Python history, Tcl/Tk and every bundled component's notices from the exact distribution |
| PS2Recomp | [ran-j/PS2Recomp](https://github.com/ran-j/PS2Recomp/tree/eb8688b2fd191129f103a39543002c005b33409c), `eb8688b2fd191129f103a39543002c005b33409c`, all local numbered patches already applied | Not measured | GPL-3.0 project source and upstream notices |
| raylib | [raysan5/raylib](https://github.com/raysan5/raylib/tree/5.5), `5.5` | Not measured | zlib and bundled notices |
| imgui | [ocornut/imgui](https://github.com/ocornut/imgui/tree/v1.92.7-docking), `v1.92.7-docking` | Not measured | MIT |
| rlImGui | [raylib-extras/rlImGui](https://github.com/raylib-extras/rlImGui/tree/Raylib_5_5), `Raylib_5_5` | Not measured | zlib |
| sse2neon | [DLTcollab/sse2neon](https://github.com/DLTcollab/sse2neon/tree/v1.9.1), `v1.9.1` (ARM dependency; retained with source) | Not measured | MIT |
| ELFIO | [serge1/ELFIO](https://github.com/serge1/ELFIO/tree/Release_3.12), `Release_3.12` | Not measured | MIT |
| toml11 | [ToruNiina/toml11](https://github.com/ToruNiina/toml11/tree/v4.4.0), `v4.4.0` | Not measured | [MIT](https://github.com/ToruNiina/toml11/blob/v4.4.0/LICENSE) |
| fmt | [fmtlib/fmt](https://github.com/fmtlib/fmt/tree/12.1.0), `12.1.0` | Not measured | [MIT with optional exception](https://github.com/fmtlib/fmt/blob/12.1.0/LICENSE) |
| libdwarf | [davea42/libdwarf-code](https://github.com/davea42/libdwarf-code/tree/v2.2.0), `v2.2.0` | Not measured | [LGPL-2.1 library, GPL-2.0 dwarfdump, BSD and public-domain files](https://github.com/davea42/libdwarf-code/blob/v2.2.0/COPYING); retain all notices, not only top COPYING |
| Rabbitizer | [Decompollaborate/rabbitizer](https://github.com/Decompollaborate/rabbitizer/tree/1.14.3), `1.14.3` | Not measured | MIT; keep exact upstream notices |
| FFmpeg shared prebuilt | [System233 n7.1-241205 LGPL amd64 zip](https://github.com/System233/ffmpeg-msvc-prebuilt/releases/download/n7.1-241205/ffmpeg-n7.1-241205-lgpl-amd64-shared.zip) | Plan estimate 25 MB zip / 45 MB unpacked, not measured | LGPL shared build; exact build source/relink information and bundled notices must accompany it |
| SDL2 / OpenEXR | Included by upstream/prebuilt dependencies if present, not a new player download | No separate size documented | zlib / BSD-3-Clause respectively; exact component versions/notices must be recorded from supplied inputs |
| VU1 generator | Existing `tools/vu1/vu1n_gen.py`, origin noted in its header | Already source in this checkout | **Unresolved: header says upstream GoW copy has no licence. Owner must settle permission before publication. Required `vu1_generator` licence input is a release gate.** |

The three archive SHA-256 values are in `tools/release_toolchain.json` with official
[LLVM](https://github.com/llvm/llvm-project/releases/expanded_assets/llvmorg-23.1.3),
[CMake](https://github.com/Kitware/CMake/releases/expanded_assets/v4.4.4) and
[Ninja](https://github.com/ninja-build/ninja/releases/expanded_assets/v1.13.2) metadata links.
No installer executable is run by the download helper. LLVM's xz archive is larger than
the tool subset finally staged. The old plan's 901 MB asset estimate is superseded by this exact archive choice.

The source versions above come from pinned upstream CMake declarations. No Git command is needed
by the package tool or player. The maintainer supplies already patched source trees and records
their exact tree digests. Source acquisition, patch verification and FFmpeg/Python archive provenance
remain maintainer work before packaging; hashes for those inputs have not been invented here.
There is no shipped prebuilt `ps2_recomp.exe` in this implementation: the player builds it from source.

## Player downloads

| Download | Source | Size | Licence |
|---|---|---|---|
| Initial T4 zip and checksum | Owner's release hosting, not selected yet | Plan estimate about 160 MB; not measured | Project GPL-3.0 plus the component texts in `LICENSES/` and source folders |
| Microsoft MSVC CRT/STL header VSIX and x64 Desktop/Store library VSIX | Exact HTTPS payload URLs from the reviewed `tools/msvc_sysroot.lock.json`, originating at [VS 17 release channel](https://aka.ms/vs/17/release/channel) and its referenced Microsoft public manifest | Exact per-file bytes in lock; not resolved here | Applicable Microsoft Build Tools terms; [licence link](https://go.microsoft.com/fwlink/?LinkId=2086102), owner must verify it for selected payloads |
| Windows SDK desktop headers x86/x64, desktop libs x64, Store headers and Universal CRT Headers/Libraries/Sources MSIs | Same Microsoft manifest and reviewed lock | Exact MSI/CAB bytes in lock; combined sysroot plan estimate 150-300 MB download / 0.4-0.8 GB disk remains unmeasured | Exact Windows SDK terms must be selected by owner; SDK download landing page is not a substitute for the terms |
| CAB files referenced by those MSIs' Media tables | Only matching payloads in the same locked manifest | Selected CAB bytes logged in `toolchain/sysroot.json` after installation | Same applicable SDK terms |

The release does **not** download a compiler, Python, Git, CMake, Ninja, source dependency,
extractor, BIOS or game data on the player's PC. MSI reading and CAB expansion use Windows APIs
and `expand.exe`. Lock creation on the maintainer's machine fetches channel/manifest metadata;
the player uses the shipped lock. See [MSVC_SYSROOT.md](MSVC_SYSROOT.md) for the exact process,
acceptance record and failure/resume limitations. The complete resolved Microsoft URL/byte inventory
cannot be stated until the owner generates and reviews the lock; packaging requires it.

## Local input lock and staging

Use Python 3.12+ on the maintainer's PC. Keep all preparation/output inside a permitted work folder.
For each directory, `python -I tools/package_release.py --hash-tree <directory>` prints a digest
without writing. Files use ordinary SHA-256 (`Get-FileHash`). Directory digest is SHA-256 of the
sorted UTF-8 relative path + NUL + raw file SHA-256 for every file; `.t4-payload.json` is excluded
so its receipt can contain that digest. Links/reparse points are refused.

Create an owner-reviewed JSON lock. Every record has `path`, lowercase `sha256`, `source`, `version`.
Paths point at local inputs. Required top-level records: `python`, `ps2recomp`, `llvm`, `cmake`, `ninja`,
`ffmpeg` (the exact shared zip), `sysroot_lock` (the reviewed Microsoft lock file),
plus `fetch` and `licenses` maps:

```json
{
  "python": {"path": "release-inputs/python", "sha256": "<tree digest>", "source": "<exact python.org release/installer URL>", "version": "<reviewed version>"},
  "ps2recomp": {"path": "release-inputs/ps2recomp", "sha256": "<tree digest>", "source": "https://github.com/ran-j/PS2Recomp", "version": "eb8688b2fd191129f103a39543002c005b33409c + local patches"},
  "llvm": {"path": "release-inputs/llvm", "sha256": "<tree digest>", "source": "<pinned archive URL>", "version": "23.1.3"},
  "fetch": {"raylib": {"path": "release-inputs/raylib", "sha256": "<tree digest>", "source": "<exact upstream source>", "version": "5.5"}},
  "licenses": {"project": {"path": "LICENSE", "sha256": "<file digest>", "source": "this project", "version": "GPL-3.0"}}
}
```

This is an abbreviated schema example, deliberately not a usable release lock. Add all required
records, all nine `fetch` names from the table, and licence keys `project`, `python`, `llvm`, `cmake`,
`ninja`, `ps2recomp`, `ffmpeg`, `sdl2`, `openexr`, `vu1_generator` and all nine dependency names.
Also require `microsoft-build-tools` and `microsoft-windows-sdk` with the actual reviewed terms.
The Microsoft lock must set `license_reviewed: true`; its `license_terms["microsoft-build-tools"]` and
`license_terms["microsoft-windows-sdk"]` records must have `path` exactly `LICENSES/microsoft-build-tools.txt`
and `LICENSES/microsoft-windows-sdk.txt`, the matching licence file `sha256`, and applicable HTTPS `url`.
Packaging copies those exact texts into the zip, so the launcher can show the terms before acceptance.
A licence record may point to a collected text containing all notices for that component.
Existing source notices stay in place too. LLVM/CMake/Ninja directories must have the helper's
`.t4-payload.json` receipt matching both the official archive pin and current tree digest.

The supplied prepatched PS2Recomp tree must contain `.t4-vendored.json` with the full pinned
`head` above and `patches`: an array of `{"name": "01-....patch", "sha256": "..."}` for **all**
current patches, sorted by filename. The marker is a maintainer attestation, not proof that
patches were applied correctly: review that separately before preparing inputs.
No packaging operation writes to the input tree, applies patches or writes Git metadata.
Checkout `.git`, `out`, `generated` and source dependency build directories are omitted on copy.

Future maintainer commands, **not run in this task**:

```text
python -I tools/fetch_llvm.py --component llvm --cache release-inputs/cache --output release-inputs/llvm
python -I tools/fetch_llvm.py --component cmake --cache release-inputs/cache --output release-inputs/cmake
python -I tools/fetch_llvm.py --component ninja --cache release-inputs/cache --output release-inputs/ninja
python -I tools/package_release.py --inputs release-inputs/inputs.json --version <version> --stage release-output/T4 --zip release-output/T4-<version>.zip
python -I tools/package_release.py --scan-only release-output/T4
python -I tools/package_release.py --scan-only release-output/T4-<version>.zip
```

The stage/zip must be new paths; nothing is removed or overwritten. Partial outputs remain for
inspection after failure. Staging copies a full Python runtime's standard library, DLLs and Tcl/Tk,
excludes installed site packages/tests, writes a `python3XY._pth` without `import site`, and runs
the staged interpreter with a bare system PATH to import helpers and create/destroy a Tk window.
An embeddable Python distribution cannot pass the Tk checks. Tcl/Tk and bundled DLL notices must
be included in the reviewed `python` licence text. `Tekken4.cmd` starts private `pythonw.exe`.
Native signed starter/signing remains owner work.

The tool writes `release.json` with source/version/digests but no maintainer input paths,
`toolchain/toolchain.json`, per-file `SHA256SUMS` and the final zip's `.sha256`.
The portable CMake adapter edits only the staged copy to use the local FFmpeg archive.
Both stage and zip must pass the scanner, including zip members nested in bundled FFmpeg/Python.

## Scan scope and clean-PC proof still required

The scanner refuses forbidden names/directories, ISO/ELF/PKG content, known VU1 image digest,
files byte-identical to local `game/disc` files when such a reference exists, lifted-symbol density,
unapproved compiled files, executables over 20 MiB outside LLVM, links, unsafe/duplicate zip paths,
and a Microsoft sysroot in the zip. Only the exact small upstream runtime placeholder paths may
contain `register_functions.cpp`/generated-header names; they must contain no game symbols.
The existing handwritten PAL camera source has an exact SHA-256 exception for symbol density;
the exception does not bypass path, magic or game-file-hash checks and does not apply to edits.
It is a release guard, not a proof against deliberately disguised/stripped game data. The source
inputs and exact binary provenance still need owner review. No game reference exists in this copy.

Before shipping, actually fetch and verify each tool, resolve source/FFmpeg/Python licences and
hashes, generate/review the Microsoft lock and applicable terms, run packaging and scan both outputs.
On a fresh Windows PC with no Python/Git/CMake/Ninja/VS: launch from a path with spaces/non-ASCII,
check licence refusal makes no sysroot download, accept and fetch, interrupt/resume safely, build
all steps from the owner's supported ISO, verify native VU1 and play/sound/speed, move the extracted
folder and build again, rebuild offline, and confirm the developer checkout still uses its old tools.
Record actual bytes/disk/time and all final resolved downloads. None of those steps was run here.
