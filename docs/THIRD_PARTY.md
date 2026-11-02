# Third-party sources and provenance

Source-only audit, 2026-10-31. This records what this working copy says, not a
legal opinion or release approval. No upstream checkout, history, download,
build or game run was used. An upstream licence reported by a local comment or
document is labelled as such; it was not independently verified for the exact
copied revision. Missing evidence stays missing.

This is an attribution-based inventory of the available source and docs. It
cannot detect undocumented copying or certify that no other origins exist.

The project declares GPL-3.0 in [README.md](../README.md); [LICENSE](../LICENSE)
contains the GNU GPL version 3 text. That declaration does not settle the
separately sourced items below. Keep their existing notices.

## Material present in this tree

| Item and local evidence | Source recorded here | Licence evidence and remaining question |
|---|---|---|
| `LICENSE` | Free Software Foundation, GNU GPL v3, 29 June 2007 | The document itself permits verbatim copying and says changes are not allowed. It is the project's supplied licence text. |
| Original PAL port and inherited T4 groundwork | [Lautreck/tekken4-recomp](https://github.com/Lautreck/tekken4-recomp), colleague's PAL `master` line, named in `docs/PROJECT_MAP.md`, `docs/HANDOFF_T4_TO_MAIN.md` and the credits in `tools/make_public_repo.py` | The current project declares GPL-3.0. No exact original-port import revision or separate original licence snapshot is supplied. `runtime/pal/tekken4_camera_overrides.cpp` explicitly targets PAL; historical docs also describe PAL config/tooling later adapted to US. They do not provide a complete per-file authorship map. Owner must preserve the colleague's attribution and verify inherited source/notices rather than assign all current tooling to one author. |
| All PS2Recomp patch context and adaptations in `patches/`, including `debug/vif1-dma-trace.patch`; `docs/gfx/tekken4_overrides-video-mode.patch`; `docs/rollback/optional/0075-*.patch`; PS2Recomp-derived overrides under `runtime/` | [ran-j/PS2Recomp](https://github.com/ran-j/PS2Recomp), base `eb8688b2fd191129f103a39543002c005b33409c` recorded in `tools/package_release.py` and `docs/RELEASE_DOWNLOADS.md`; individual patch headers identify their changed upstream paths | README declares the patches and overrides derived from PS2Recomp and GPL-3.0. Extra origins in the following rows must be retained separately. The base checkout and its full notices are absent here. |
| Readback fallback in `patches/87-Shared-present-readback-fallback.patch`; inherited one-step netplay staging/build-id work in `tools/stage_generated.cmd`, `tools/build_game.ps1` | Patch 87 says Pablo's patch 44, `Lautreck/PS2Recomp` `ebae275`; `docs/status.md`, “PABLO'S WORK REVIEWED 2026-10-30”, records staging/build-id changes from `swiss us-iso` `aff2a4c` | Project/PS2Recomp GPL-3.0 declaration; patch preserves its author/coauthor headers. These are specifically documented imported changes, distinct from the older PAL groundwork. The log says only patches 01-32 were shared and other proposed changes were not taken; do not attribute those absent changes to this copy. |
| Native VU1 runtime, diagnostics and tests in `patches/11-native-vu1.patch` | [Waffle565/God-Of-War-Native-Port](https://github.com/Waffle565/God-Of-War-Native-Port), `origin/runtime`; `docs/status.md`, “Native VU1 port” | Local patch and log say GPL-3.0. The log names whole-file copies of `ps2_vu1.h`, `ps2_vu1_native.h`, `ps2_perf.h`, `ps2_vu1_core.cpp`, `ps2_vu1_lower.cpp`, `ps2_vu1_upper.cpp`, `ps2_vu1_step.inl`, `ps2_vu1_native.inl`, `ps2_vu1_tests.cpp`, plus runtime/CMake adaptations. Exact imported runtime revision and its notices need owner verification. The log's `c5a9d02` describes the common base, not a pinned import revision. |
| **VU1 generator: `tools/vu1/vu1n_gen.py`** | Same GoW repository, **`main` at `b76921c`**, source path `tools/vu1/vu1n_gen.py`, stated in its first lines | **Unresolved.** Its header reports no LICENSE on that branch and distinguishes the GPL-3.0 runtime branch. The local GPL declaration is not evidence of a grant for this script. Ask Waffle565/the script's rights holders for the licence covering that exact copy and any earlier contributors. See the trace below. |
| Sound mixer `sound_engine.cpp` and `sound_engine.h` carried by `patches/19-ps2xIOP-sound-and-scheduler.patch` | GoW `origin/runtime`, upstream paths `ps2xIOP/src/emulator/core/sound_engine.{cpp,h}`; added file comments name that origin | Comments say GPL-3.0. No exact mixer import revision or full upstream licence file is present. Ask the owner to retain the exact source/notices. |
| Reverb preset data `kEffectPacked[10][16]` in patch 19 | Comment identifies PS2SDK `iop/sound/libsd/src/effect.c`; table expands packed halves into SPU register words | The copied table's separate licence and revision are **not recorded in this tree**. “Published libsd” in a comment is not a licence. Owner must identify the exact PS2SDK source revision and applicable file notices, asking the PS2SDK maintainers/rights holders if unclear. |
| OpenGL GS backend and supporting code in `patches/22-ps2xRuntime-gs-gl-backend.patch` | GoW runtime; comments credit **Taylor N. Albarnaz / LightVelox**, **PS2Recomp `sotc-port` at `ac9efa070638ad3b3accd284de6f898d5ab271d1`** | Added file headers say GPL-3.0. Preserve this earlier credit as well as GoW's. Verify the exact GoW import and earlier source notices. File scope is listed below. |
| FXAA shader `kFxaaFs` in `patches/71-Graphics-options-internal-resolution-steps-FXAA-SSAA.patch` | Comment identifies FXAA 3.11 quality preset, “after Timothy Lottes” | No exact shader source, imported revision or shader-specific notice is recorded. This establishes an algorithm credit, not whether code was copied or independently written. Owner must establish which and supply the applicable notices if copied; ask the shader's contributor for its source. |
| `runtime/tekken4_net.cpp` and `runtime/tekken4_net.h`, including their transport/SipHash implementation | Both headers explicitly say adapted from T5DR Online `src/netplay/netplay_core.cpp`; comments describe it as the user's code | Both files retain the full **MIT** permission/disclaimer and “Copyright (c) 2026 TheWishin and the T5DR Online contributors”. No original revision is recorded. This is an existing T5DR adaptation; no T5DR source was added by this audit. The launcher note below only covers the launcher directory. |
| Existing “Based on Blackline Interactive implementation” context in patches 15, 40 and `patches/debug/vif1-dma-trace.patch` | Comment inherited in PS2Recomp VIF code | No separate revision or licence for that earlier implementation is recorded. These are context lines, not evidence that those patches newly imported it. Owner should check the upstream attribution chain. |
| `config/analyzer_seed.toml`, `ghidra_export.toml`, `extra_functions.csv`, `function_map.csv`, `ghidra_functions.csv`, `ghidra_functions_only.csv` | Local analysis of Tekken 4 executables; Ghidra/PS2Recomp analyzer output, supplemented by SCE SDK symbol matching. `tools/ghidra_apply_sdk_names.py`, `tools/postprocess_ghidra_export.py`, `tools/find_missing_functions.py` and `docs/status.md` describe the process | These contain addresses, function names/sizes and jump-table targets, not a supplied game executable. No separate grant for game-derived metadata or the SCE symbol source is documented. Owner must confirm the provenance and intended public scope of these maps, including which analyzer symbol database was used. Do not describe the analysis origin as a game-data licence. |
| Game-specific addresses, instruction descriptions and constants in handwritten `runtime/`, `tools/vu1_micro_from_elf.py`, config and technical docs | Tekken 4 USA SLUS-20328 and historical PAL SCES-50878 analysis, documented locally | Project source is declared GPL-3.0; no grant to distribute Tekken 4 code/assets is supplied. The scripts read the player's own game locally. Review any copied guest code/table separately; this catalogue does not certify a source scan as rights clearance. |
| `tools/usage_meter.py` price table and `HAIKU55_LONG` | Comment identifies `pricing_tiers` in Claude Code **2.1.307 (`claude.exe`)**; related investigation described in `docs/ai/usage-meter.md` | No separate licence/grant for the extracted table is recorded. It is data in a maintainer helper, not a bundled Claude binary. Owner must decide whether it belongs in the public tree and establish its source/terms; ask its contributor for the extraction provenance. |
| Text of historical AI prompts, responses/reviews and handoffs in `docs/ai/`, including `reviews/*.json` | The local collaboration logs identify Claude/Grok work; no third-party software import is declared there | No additional software licence is recorded for these records. They are provenance/history, not proof of code authorship or of rights to unrelated quoted material. Owner must review their publication scope. |
| Existing `dist/sunday/tekken4-sunday-test-20261031-042256-264836.zip` | Earlier source-test snapshot of this project | Read-only entry listing found `LICENSE`, config, patches, runtime, tools and `TEST_ONLINE_DE.txt` (123 entries). It is a separate, older artifact and does not acquire this catalogue or later fixes automatically. The copies of the items above keep the same provenance questions. No extraction/build was performed. |

Patch 22's file scope is its `diff --git` list: CMake; `ThreadPriority.h`;
GS headers `gs_backend.h`, `gs_backend_state.h`, `gs_hw_backend.h`,
`gs_shared_present.h`, `gs_swizzle.h`, `gs_threaded_backend.h`, `gs_types.h`,
`gs_upload24.h`, `ps2_gs_memory.h`; GPU files `gs_gl.cpp`, `gs_gl.h`,
`gs_hw_backend.cpp`, `gs_texture_store.cpp`, `gs_texture_store.h`; helpers
`gs_gpu_helpers.h`, `gs_inventory.h`; and implementation files `gs_frontend.cpp`,
`gs_swizzle.cpp`, `gs_threaded_backend.cpp`, `ps2_gs_memory.cpp`.

## VU1 generator trace

1. `tools/vu1/vu1n_gen.py:1-5` identifies the copied GoW **main** script at
   `b76921c` and the unresolved licence. It records the T4 change: native
   OPMULA/OPMSUB generation for `xyz`, needed for observed MAC flags.
2. `docs/status.md`, “Native VU1 port (session 3, 2026-10-21)”, records that the
   generator was initially copied unchanged, the licence question was deferred,
   and Waffle565 should be asked before making the repository public again.
3. The same section records the separate GoW **runtime** import as patch 11 and
   calls that runtime GPL-3.0. It does not extend that statement to main's script.
   The earlier GoW `514f891` entry in “Pinned dependencies” is a reference checkout
   pin; it is not a substitute for the generator's stated `b76921c` origin.
4. `tools/build_game.ps1`, `tools/build_game_portable.ps1`, runtime build helpers
   and patch 11 use this generator after local micro-memory extraction.
   `tools/package_release.py` copies `tools/vu1/` and requires a
   `vu1_generator` licence input. Supplying an arbitrary text under that key
   would satisfy a packaging shape check, not establish permission.
5. No written resolution/grant is present in this copy. The owner must obtain
   the applicable grant and retain the exact source/notices, or decide how to
   replace the unresolved component. This audit changes no build or runtime
   selection. Captured VU1 memory and generated C++ remain game code and must
   stay out of the public source and player archive.

## Dependencies described here, absent from this source copy

These are planned release inputs or installed developer tools, not vendored
payloads found in this tree. Versions/licences below reproduce the local
[download inventory](RELEASE_DOWNLOADS.md) and `tools/release_toolchain.json`;
they are not fresh upstream verification. The owner must review the actual
input trees and their bundled notices, including transitive components.

| Dependency | Source/version recorded here | Licence recorded here |
|---|---|---|
| LLVM | `llvm/llvm-project`, 23.1.3 | Apache-2.0 WITH LLVM-exception; bundled notices |
| CMake | `Kitware/CMake`, 4.4.4 | BSD-3-Clause; bundled notices |
| Ninja | `ninja-build/ninja`, 1.13.2 | Apache-2.0 |
| CPython and Tcl/Tk | python.org full x64 distribution; owner selects exact version | PSF/Python historical notices, Tcl/Tk and bundled component notices; exact input required |
| PS2Recomp source | `ran-j/PS2Recomp`, `eb8688b2fd191129f103a39543002c005b33409c` plus ordered patches | GPL-3.0 and upstream notices |
| raylib | `raysan5/raylib`, 5.5 | zlib; bundled notices |
| imgui | `ocornut/imgui`, v1.92.7-docking | MIT |
| rlImGui | `raylib-extras/rlImGui`, Raylib_5_5 | zlib |
| sse2neon | `DLTcollab/sse2neon`, v1.9.1 | MIT |
| ELFIO | `serge1/ELFIO`, Release_3.12 | MIT |
| toml11 | `ToruNiina/toml11`, v4.4.0 | MIT |
| fmt | `fmtlib/fmt`, 12.1.0 | MIT with optional exception |
| libdwarf | `davea42/libdwarf-code`, v2.2.0 | LGPL-2.1 library, GPL-2.0 dwarfdump, BSD/public-domain files; exact file notices matter |
| Rabbitizer | `Decompollaborate/rabbitizer`, 1.14.3 | MIT |
| FFmpeg shared prebuilt | `System233/ffmpeg-msvc-prebuilt`, n7.1-241205 LGPL amd64 shared zip | Locally described as LGPL; exact build configuration, source/relink material and bundled notices remain owner work |
| SDL2 / OpenEXR | Mentioned as upstream/prebuilt bundled components; exact versions unrecorded | zlib / BSD-3-Clause respectively, per local docs; verify actual payload |
| MSVC CRT/STL headers/libraries | Microsoft VS 17 release channel; exact reviewed sysroot lock absent | Applicable Microsoft terms, not GPL. Owner must select/review the payloads and exact terms. Player download after acceptance; not a redistributable sysroot input to this package |
| Windows SDK/UCRT headers/libraries | Same Microsoft metadata/lock process | Applicable SDK terms; SDK landing page is not the licence text. See [MSVC_SYSROOT.md](MSVC_SYSROOT.md) |

The package tool's required licence keys cover the planned dependency set,
including the VU1 generator, SDL2 and OpenEXR. A key's presence is not review of
its content or completeness. No supplied lock here settles exact CPython,
FFmpeg subcomponents, Microsoft selections or all upstream transitive notices.

## References and explicitly absent copies

* `launcher/COPIED_FROM_T5DR.txt` says **no launcher code** was copied: only the
  tab layout/ideas, with new T4 files dated 2026-10-30. This is the local author's
  statement; it does not negate the MIT transport adaptation elsewhere.
* PCSX2 and psx-spx are named hardware/algorithm references, including DSP in
  patch 19 and VU behaviour in `docs/status.md`. The latter reports PCSX2 VU code
  GPL-3.0+ in the GoW reference. This copy contains no standalone PCSX2 source
  checkout or complete psx-spx document; exact upstream-derived portions must
  be checked with the GoW runtime imports. No separate reference-text grant is
  recorded locally.
* `tools/pine.py` implements the PCSX2 PINE memory/register protocol using the
  Python socket/struct APIs. Its header describes PCSX2 setup; it supplies no
  copied-client attribution or separate licence. Protocol interoperability is
  documented, but does not establish a third-party code import.
* `docs/status.md` mentions libmpeg2 GPL-2+ in the GoW reference port. That is
  not evidence that libmpeg2 was imported into this T4 source copy.
* Ghidra, `chaoticgd/ghidra-emotionengine-reloaded` v2.1.38 and GhidraMCP are
  analysis tools/references; their distributions are absent. Local Java/Python
  scripts call their APIs; no copied upstream implementation is identified by
  those scripts. Their distribution licences were not supplied here.
* `docs/MSVC_SYSROOT.md` cites `Jake-Shadle/xwin` for package-layout research
  and explicitly says no xwin source is bundled or executed. No xwin grant is
  supplied or needed as evidence for an import in this catalogue.
* Pillow/PIL, NumPy, capstone and other helper imports are optional installed analysis
  dependencies, not copied packages in this tree. No payload or corresponding
  licence text is supplied here. They are not required by the standalone
  launcher's standard-library Python source.
* Historical lobby/server documents refer to a private T5DR-derived lobby and
  tests. No `lobby/` tree is present; their claimed historical results do not
  inventory or license a future public lobby bundle.

## Public-tree privacy gate

The public-tree staging tool removes private mail addresses and Co-Authored-By
trailers from patch preambles, while retaining the diff bytes exactly. It omits
image files and scans the staged tree. These are privacy and content checks,
not permission to publish. Original patches remain in this working copy.
Retain author names, copyright notices, licence texts and provenance credits;
mail-header cleanup must not erase notices carried by the diff. Review any
attribution that existed only in a removed trailer before publication.

A clean scan does not settle the VU1 generator grant, PS2SDK reverb-table and
FXAA provenance, exact inherited PAL/GoW/LightVelox/Blackline notices, rights
in SCE/game-derived maps or the extracted pricing table. It also does not
settle the chosen FFmpeg LGPL build/source obligations, exact dependency
notices or Microsoft's terms. Those questions remain open on the local
evidence above. GPL-3.0 covers the port's declared source licence; it grants
no rights to game screenshots, assets or original game code.

## Owner follow-up before publication

1. Obtain the exact VU1 generator licence resolution from Waffle565/its rights
   holders. Keep a record tied to the imported revision and contributor chain.
2. Establish the PS2SDK reverb-table and FXAA shader provenance/notices; confirm
   the GoW runtime, LightVelox and Blackline attribution chains with their
   maintainers or the contributor who imported them.
3. Review public scope/source evidence for the SCE/game-derived maps and the
   Claude pricing table. This catalogue makes no legal conclusion about them.
4. Prepare exact release inputs, Microsoft terms and dependency/source notices.
   The existing source-test zip is an older artifact; review/recreate the chosen
   candidate after fixes, without assuming it matches the current tree.

No build or game run can prove a missing permission. Real package inspection
must establish what actually ships; clean-PC builds and game tests separately
prove the technical release path. No such validation was performed here.
