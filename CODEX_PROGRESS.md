# T4 beta progress, 2026-11-02

## Public-tree preparation, latest session

Publication remains **NO-GO** for the full source/player trees. The new
PowerShell path runs here without Python. It stages files only; it does not
publish, use Git, build or start a game. The earlier Python attempts below
remain historical failures, not executed Python scans.

Done:

- Added [publish_public_tree.ps1](tools/publish_public_tree.ps1), with separate
  patch-header and content-scan helpers. Fresh staging omits image files,
  removes patch author mailboxes, mail transport metadata and coauthor trailers,
  and compares every byte from the first `diff --git` line through EOF before
  and after writing. Display-name attribution and diff notices remain.
- Scans refuse images, disguised image/binary signatures, private mail metadata,
  secrets, machine paths, nonpublic network addresses and unreviewed URLs.
  Export preflights all selected bytes, then scans the written tree again.
  Scan-only checks every staged file without applying export exclusions.
- Ran the real entry with `-Include @('LICENSE','patches')` into a fresh folder
  under `logs/public-publish-tests`: exit 0, 80 files, all 79 patches checked,
  zero image files, postwrite scan passed. There are 78 top-level patches and
  one debug patch; 46 source preambles contain mailboxes/coauthor trailers.
  Source patches were not rewritten or renumbered.
- Ran a broader real selection (runtime, config, launcher, tools, README and
  selected docs): exit 1 before staging. Findings remain in README, launcher
  core and several tools. These need owner scope/content review; no broad
  source-tree pass is claimed. No images exist in this clean input copy;
  omission/refusal is tested with harmless text filenames and in-memory bytes.
- Added entry-point tests and [check_public_publish.ps1](tools/check_public_publish.ps1).
  Tests caught a real PowerShell default-argument failure, which was fixed and
  rerun. Header tests passed 63 checks, including three actual exports and six
  actual scans; safety tests passed 32 assertions through actual subprocesses
  and in-memory signature checks. Both existing 23-tool catalogs have present,
  unique entries. Catalog inspection does not execute the Python packagers.
- Final independent review found a compressed-IPv6 scan bypass. The scanner
  was fixed; real scan regressions now refuse it without echoing the address.
  Root and reviewer ran the finished `check_public_publish.ps1`: exit 0,
  63 patch checks, 32 safety assertions, six syntax parses, both catalogs and
  unchanged names/SHA-256 hashes for all 79 source patches. The reviewer also
  independently exported and compared all 79 diff byte ranges. No remaining
  blocking issue was found in these tool changes; full publication stays NO-GO.
- Documented the workflow in [PUBLIC_SOURCE_EXPORT.md](docs/PUBLIC_SOURCE_EXPORT.md)
  and the remaining permission/notice questions in
  [THIRD_PARTY.md](docs/THIRD_PARTY.md). Document/link checks passed for these
  pages and RELEASING. The older whole-tree filename checker now refuses the
  intentional text-only `.png` test fixtures retained under logs; this is not
  a clean whole-tree checker pass. Nothing was deleted to make it green.
  Final real checker run covered all four changed documents and 27 local links,
  with 49 PowerShell syntax parses; exit 1 solely on those 18 retained fixture
  filenames. The old filename checker was not weakened.

Open / owner-only:

- Review the exact complete public source and player outputs. The successful
  LICENSE/patch export is a test subset, not complete corresponding source.
  Old Python publishers/packagers do not call the new PowerShell sanitizer;
  their outputs must separately pass the new scan and their existing checks.
  Python suites, payload/zip scans and full player output remain unrun here.
- Resolve the VU1 generator grant, PS2SDK reverb/FXAA and imported-code notice
  chains, SCE/game-derived map publication scope, quoted pricing material,
  exact FFmpeg LGPL/source obligations, dependency notices and Microsoft terms.
  Header cleanup proves no rights and cannot replace author-notice review.
- Build and run the exact reviewed candidate in the authorized real checkout,
  validate the actual launcher and portable path, and test two physical PCs.
  No build, launcher GUI or game was run in this copy. No network service,
  Git write, history rewrite or release was performed.

The owner's latest supplied verification identifies draft `21d1fbb4b6`, merge
base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean merge;
174-second build `943fc4631acf2c13`. Selftest: 232 successful restores,
514 compared resim frames and zero mismatches. Same-PC 6000-frame pair with
switches off: 199 hash comparisons per side, zero mismatches and zero NETDESYNC
lines; run-average 49.8 fps on both sides, join 122 stalls / 3169 ms. Finished
2026-11-02T01:05:32. This supersedes the older supplied measurement below.
It was not reproduced here and does not prove the edited tree, launcher profile
or two-PC internet play. No personal worktree paths are copied into this record.

Agents this session: `patch_headers`, `public_scanner`, `publish_entry`,
`patch_entry_tests`, `publish_safety_tests`, `tests_catalogs`,
`licence_questions`, `publish_docs`; separate `final_diff_review` reviewed the
finished files and independently ran the checker. Root owns this record and
integration checks. Each agent read AGENTS.md; file ownership was exclusive.

## Earlier beta audit record

Decision: **NO-GO**. The Sunday target was 2026-11-01. Missing acceptance
evidence moves the release date. No build or game was started in this copy.
This file was absent when this session began; there was no earlier progress
record to resume. Read [AGENTS.md](AGENTS.md) before continuing.

## Done in this source-only copy

- Read the existing beta checklist and source audit. Split independent work
  among eight area agents and a tests/catalog agent. A separate final reviewer
  reviewed the final diff and independently ran the named source checker;
  no blocking issue was found in those changes. This does not close the
  production audit findings or supply missing acceptance evidence.
- Updated README, release notes and announcement drafts with current NO-GO,
  offline/direct-IP/VPN scope, pending player tooling and controller checks.
  No lobby, ranked, login/server deployment or T5DR 1.2.0 is included.
- Compared effective switch sources. No switches were changed: the supplied
  all-switches-off measurement does not validate the launcher's COALESCE=1,
  DIAG=1 profile. The remaining experimental switches and AUTO_VS stay off.
- Inspected the three existing Sunday archives without extraction. They have
  123, 124 and 124 members; none has an artifact/image filename detected by
  the limited name check. They omit the launcher and private Python and are
  old source-test payloads, not current player candidates. Content scans
  remain unrun. Latest existing archive SHA-256:
  `eb00046c520efb4bc3f6cfdba12803fb25cbec321f985609093de1880a5c8391`.
- Added [check_beta_source.ps1](tools/check_beta_source.ps1) for local document
  links, PowerShell syntax and artifact/image filenames in this tree and zip
  directories. It explicitly leaves beta acceptance NO-GO. It does not run
  the Python scanners or prove a launcher, build or playable game.

## Real entry-point evidence from this session

Windows PowerShell was available. Python, Python 3, py and a bundled Python
were not found. A missing interpreter means the Python code never started.

| Entry point | Result | Meaning |
|---|---|---|
| `cmd.exe /d /c "call .\Tekken4.cmd < nul"` | Exit 1: private Python missing | Starter executed; GUI never started. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File tools/make_player_zip.ps1` | Exit 1: reviewed inputs/version required | Argument refusal, no package made. |
| Same wrapper with `-ScanOnly` and the existing latest Sunday zip | Exit 1: Python 3.12+ unavailable | Wrapper ran; payload scan never started. |
| `python -B tools/make_public_repo.py --out logs/beta-public-repo-20261102` | Exit 1: interpreter missing | No script code ran; no staging output. This tool has no dry-run flag. |
| `python -B tools/publish_source.py --scan-only .` | Exit 1: interpreter missing | No source scan ran; no publication. |
| `python -B tools/package_release.py --scan-only dist/sunday/tekken4-sunday-test-20261031-205628-895451.zip` | Exit 1: interpreter missing | No payload content scan ran. |
| `python -B -m unittest discover -s tools -p test_launcher_online.py -v` | Exit 1: interpreter missing | Zero tests executed; suite mocks core behavior, never starts GUI. |
| Same unittest entry with `test_publish_source.py` | Exit 1: interpreter missing | Zero tests executed. |
| Same unittest entry with `test_release_catalogs.py` | Exit 1: interpreter missing | Zero tests executed. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_beta_source.ps1` | Exit 0: 7 docs, 43 local links, 43 PowerShell syntax parses; 299 file names, 3 archives / 371 member names | Source checks only; cannot pass beta acceptance. |
| Same checker with `-Docs docs/DOES_NOT_EXIST.md` | Exit 1: missing document | Negative entry test; missing input cannot pass. |
| Same checker with `-Docs ../DOES_NOT_EXIST.md` | Exit 1: outside-tree document refused before read | Boundary negative entry test. |

Additional inline PowerShell checks found both 23-name tool catalogs present
and unique, the starter/beta files present, announcement tweet within 280
characters, and the updated communication documents' local links resolving.
These are limited checks, not passes of the Python suites.

## Open in source; no untested production fixes

- Static core review found fullscreen environment inheritance when unchecked
  and an unclosed offline log if process creation fails. Neither was reproduced;
  both remain open. Do not label the audit closed. No production Python was
  changed without execution proof.
- The UI source has no gamepad navigation implementation. Its controls table
  describes in-game controls. The by-pad launcher requirement is unresolved.
- The supplied 2026-11-02 report identifies draft `8f1aa94684`, build
  `943fc4631acf2c13`, a successful selftest and 6000-frame same-PC pair with
  zero mismatches in 199 hash comparisons per side. Run-average speed was
  50.4 fps; displayed-frame p99 was 136.9/104.8 ms and join had 96 stalls.
  This was supplied evidence, not reproduced here, and does not validate the
  edited tree, advertised launcher profile, internet route or physical PCs.
- Python scanner dry-runs and content/privacy scans remain open. Historical
  maintainer docs still need a reviewed public set. Do not weaken scanners to
  turn this tree green. The Git pointer leads outside this copy; no Git export
  was attempted. No Git writes, downloads, server work or release occurred.

## Only the owner or an authorized real validation checkout

1. Resolve the provenance/licence and reviewed pinned payload inputs in
   [THIRD_PARTY.md](docs/THIRD_PARTY.md) and
   [RELEASE_PATH_B.md](docs/RELEASE_PATH_B.md). Choose the exact candidate,
   source revision, matching source export, locks, build IDs and zip hash.
2. Run `make_public_repo.py` into fresh staging and `publish_source.py` scans
   on the reviewed outputs with Python. Run `package_release.py` on the exact
   staged player folder and zip. Review content, secrets/privacy and notices;
   filename inspection here cannot prove their absence.
3. Run the three Python suites. Then start the complete actual launcher;
   GUI/Tk and first-run install/build/play/return, settings and controller
   navigation need a hands-on check. Core mocks cannot replace this.
4. On both PCs, build the exact zip from each player's own supported ISO.
   Prove path B with installed Python, Git and Visual Studio hidden, or state
   the actual needed tools in the beta. No build is permitted in this copy.
5. Play at least 15 minutes of real internet Versus with zero mismatches,
   usable pacing/input/sound, rematch and role-swap/disconnect recovery. Collect
   both logs and send to Main. Check the measured switches match the candidate.
6. Complete [BETA_GO_NO_GO.md](docs/BETA_GO_NO_GO.md). Only the owner checks
   VirusTotal, publishes the draft, chooses latest and posts on Discord. No
   release action is authorized by passing a source check.

## Agents

`launcher_core`, `launcher_ui`, `public_export`, `source_publish`,
`payload_scan`, `portable_path_b`, `player_comms`, `candidate_gate`,
`tests_catalogs`; separate `final_diff_review` completed. Each read AGENTS.md;
file ownership was exclusive. Root owns this record and the source checker.
