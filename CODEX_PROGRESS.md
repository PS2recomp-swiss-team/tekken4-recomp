# T4 beta progress, 2026-11-02

## DEFLATE completion follow-up, current session

Release remains **NO-GO**. The selected source-only open item was the observed
truncated empty-DEFLATE false pass. No launcher, runtime, switch or server
behavior changed.

Done:

- Before the fix, the actual `scan_public_zip.ps1` accepted the retained
  truncated stream. It now exits 1 / REFUSED on the same unchanged input:
  SHA-256 `331d43c8da4a4e064ea2fec821a09c274957f3dc48352fef9ba4f478de0576ae`.
  Complete empty controls still pass. Root independently reran the refusal.
- Added [raw DEFLATE validation](tools/public_zip_deflate.ps1), wired through
  the real scanner's checked dependencies and bounded member regions. Stored,
  fixed and dynamic blocks must complete; Huffman trees, repeats, reserved
  symbols, output length and backreference history are checked. Only unused
  bits of the final byte may remain. Later .NET reads and CRC checks still run.
  No compilation, extraction, archive repair or member execution occurs.
- Added [valid stream tests](tools/test_public_zip_deflate_valid.ps1) and
  [malformed stream tests](tools/test_public_zip_deflate_invalid.ps1): actual
  scanner subprocesses, clean controls, unchanged hashes/inventory and output
  redaction. Final helper passed 123 assertions / 11 valid-suite processes,
  260 / 26 malformed-suite processes and 132 / 11 existing integrity processes.
  Root independently ran both final new suites: exit 0, 383 assertions through
  37 actual scanner subprocesses. Clean controls passed; malformed cases refused.
- The final reviewer caught malformed-distance fixtures whose zero declared
  length could cause an earlier refusal. The test agent gave them plausible
  declared lengths and reran the suite; no assertion was weakened.
- Both actual catalogs ran: 23 unique present tools each and three root files.
  The aggregate now parses 13 required files and invokes all six scanner
  suites plus the catalog entry. The separate reviewer ran the frozen aggregate:
  exit 0, 804 assertions through 96 scanner processes (60/10, 171/33, 58/5,
  132/11, 123/11, 260/26); all 79 patch names and hashes stayed unchanged.
- The final helper SHA-256 is
  `049b5972869e0d67e90aac14cc2a90c11123de58fdbbe4665d786c239a803656`.
  A hot-loop optimization landed during initial aggregate/audit runs. Those
  mixed-version runs are not final proof. The separate frozen aggregate and
  five retained-input scans completed with this helper hash unchanged before
  and after execution. No implementation edits followed the frozen checks.
- The final actual archive audit read all three Sunday inputs: expected exit 1,
  123/124/124 files and only the same 138 mail-category records per archive.
  The sanitized portable subset passed: exit 0, 80 files, 2,025,621 bytes.
  All input hashes stayed unchanged. Final concurrent-load wall times were
  42.351/41.485/39.920 seconds for Sunday inputs and 18.483 for the subset,
  materially slower than the earlier 4.2/2.6-second CRC-only reader. See
  [PUBLIC_ZIP_AUDIT.md](docs/PUBLIC_ZIP_AUDIT.md). This remains a test subset,
  not complete corresponding source or a player candidate.
- Updated [scanner scope](docs/PUBLIC_ZIP_SCAN.md) and
  [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md).
  Root's final real document check covered all five changed documents:
  70 local links resolved and 69 PowerShell files parsed, then exit 1 on
  retained image-name and corrupt-ZIP fixtures. No fixture was removed
  or checker relaxed to manufacture a pass.

Open / owner-only:

- The scanner is materially slower. It has byte/memory bounds, not a wall-time
  or work-budget bound; many-block adversarial inputs may take substantial
  time. This performance/resource limitation remains open. Whole-tree source
  checking also remains red on retained image-name/unsafe/corrupt fixtures.
- Exact complete source/player/privacy/licence review, Python suites/payload
  checks, actual launcher GUI/portable first-run, build/game, enabled GUI
  switches and two physical PCs remain open. Those routes are unrun here;
  builds, game and network helpers are forbidden in this copy.

Latest owner-supplied verification, not reproduced here: draft `8f27d7f6be`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 161-second build `943fc4631acf2c13`, finished `2026-11-02T02:17:42`.
Selftest: 6000 wall / 5106 logical frames, 202 successful restores, zero bad,
447 resim comparisons with zero mismatches, 101/101 wrong-input divergences.
Switches-OFF same-PC pair: 6000 frames, 199 hashes per side, zero mismatches
and NETDESYNC lines; host/join run-average FPS 52.0/52.0, stalls 0/88
(0/3052 ms), displayed-frame p99 109.4/102.0 ms. This supersedes the older
supplied reports below; it proves neither this edited tree, the enabled GUI
profile nor two-PC play.

Eight area agents have exclusive files: `deflate_validator`, `zip_integration`,
`deflate_valid_tests`, `deflate_invalid_tests`, `tests_catalogs`, `deflate_docs`,
`retained_archive_audit`, `verify_evidence`. Separate `final_diff_review_deflate`
reviewed the finished code against original bytes saved under
`logs/deflate-session-9e5a0645172b4663abda18faada7015c/` and reran real entries.
Final code and document review completed; no blocking issue was found.
All read AGENTS.md. Root owns this record, `docs/status.md` and the scanner
entry dependency list. No Git command, build, game, network helper, server,
push or release ran here.

## Earlier ZIP integrity follow-up

Release remains **NO-GO**. The selected open source-only item was actual ZIP
member CRC verification. Matching header fields alone did not check the bytes
read. No production launcher, runtime, switch or server behavior changed.

Done:

- The real `scan_public_zip.ps1` accepted a harmless stored text fixture with
  matching but incorrect local/central CRC fields before the fix. The exact
  same retained input now exits 1 / REFUSED, unchanged SHA-256
  `2f7ef08e9f2edfd56ff206d77701dd111ac619bbb8ace69ac311431b2611ebae`.
- [public_zip_scan.ps1](tools/public_zip_scan.ps1) recomputes each safe member's
  CRC from the uncompressed bytes read, including empty files/directories,
  using a bounded in-memory .NET writer. It checks stored-member length
  consistency. No compilation, extraction, archive repair or execution occurs.
- Added [known-vector tests](tools/test_public_zip_crc.ps1) and
  [corruption tests](tools/test_public_zip_integrity.ps1), all through actual
  `scan_public_zip.ps1` subprocesses. Literal standard CRC vectors, stored and
  deflated text, empty members, per-member reset, multiple buffers, wrong
  CRCs, changed content and both stored-length mismatch directions ran.
  Clean controls must pass; archive hashes, inventory and redaction are checked.
- The area agent ran the real [aggregate](tools/check_public_zip.ps1): exit 0,
  ten syntax parses; both actual catalogs, 23 unique present tools each and
  three root files; 421 assertions through 59 scanner subprocesses across
  four suites (60/10, 171/33, 58/5, 132/11). All 79 patch names and SHA-256
  hashes stayed unchanged. Catalogs did not need developer-test entries.
- The actual scanner reread all three retained Sunday archives: expected
  exit 1, 123/124/124 files and 138 mail-category records each, about 4.2 s
  per archive. The existing sanitized portable LICENSE/patch subset passed:
  exit 0, 80 files, 2,025,621 bytes, 2.569 s. All hashes stayed unchanged.
  This subset is not a complete corresponding-source or player candidate.
  See [PUBLIC_ZIP_AUDIT.md](docs/PUBLIC_ZIP_AUDIT.md).
- Root and the separate final reviewer independently reran the finished
  aggregate: both exit 0, the same 421 assertions / 59 scanner subprocesses
  and unchanged 79 patch hashes. Review against saved original file bytes
  found no blocking issue in the scoped CRC/stored-length changes. It does
  not close the known compressed-format gap below or release acceptance.
- An independent read-only audit ran ten additional real scan subprocesses.
  It confirmed CRC/stored-size refusals and found the remaining DEFLATE
  limitation below. Root's final real source check covered all five changed
  documents: 57 local links resolved and 63 PowerShell files parsed, then
  exit 1 on retained image-name fixtures and an intentionally corrupt ZIP.
- Updated [ONLINE_SWITCH_EVIDENCE.md](docs/ONLINE_SWITCH_EVIDENCE.md) with the
  latest owner-supplied verification below. This documents supplied evidence,
  not a run of this tree.

Open / owner-only:

- A harmless truncated empty DEFLATE stream (one byte `01`, declared length
  and CRC zero, beside a clean member) still passes the actual scanner because
  .NET returns no bytes without reporting truncation. CRC validates returned
  bytes; it does not prove complete DEFLATE consumption or format validity.
  Reproducer SHA-256:
  `331d43c8da4a4e064ea2fec821a09c274957f3dc48352fef9ba4f478de0576ae`.
  Evidence is under `logs/zip-integrity-audit-fbce2d67a16346bbaef8f49f083017a1/`.
  This is an observed open limitation, not a fixed or passing safety case.
  See [PUBLIC_ZIP_SCAN.md](docs/PUBLIC_ZIP_SCAN.md).
- Whole-tree source checking remains red on retained text-only image-name,
  unsafe-name and corrupt ZIP fixtures. Document-specific real checker runs
  resolved their links and parsed PowerShell before the archive reader stopped.
  Nothing was deleted or the checker relaxed to manufacture a pass.
- Review the exact complete public source/player outputs and rights; run
  Python suites/payload checks, the actual complete launcher, exact build/game
  and two physical PCs in the authorized checkout. GUI startup, portable
  first-run, enabled switch profile, results, private protocol and licensing
  gates remain open. No Python, GUI, build, game or network helper ran here.
  CRC agreement cannot close those gates or authenticate a producer.

Latest owner-supplied verification, not reproduced here: draft `9cdebb4f93`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 167-second build `943fc4631acf2c13`, finished `2026-11-02T02:06:00`.
Selftest: 6000 wall / 5106 logical frames, 202 successful restores, zero bad,
447 resim comparisons with zero mismatches, 101/101 wrong-input divergences.
Switches-OFF same-PC pair: 6000 frames, 199 hashes per side, zero mismatches
and NETDESYNC lines; host/join run-average FPS 52.0/52.1, stalls 0/71
(0/2411 ms), displayed-frame p99 107.5/100.0 ms. This supersedes the older
supplied reports below; it proves neither this edited tree, the enabled GUI
profile nor two-PC play.

Agents with exclusive source-file ownership: `zip_crc_reader`,
`zip_crc_vectors`, `zip_crc_corruption`, `tests_catalogs`, `zip_crc_docs`,
`retained_zip_audit`, `verify_evidence`; `zip_integrity_audit` was a read-only
coverage audit. Separate `final_diff_review_crc` reviewed the finished diff.
All read AGENTS.md. Root owns this record and `docs/status.md`. No Git command,
compilation, build, game, network helper, server, push or release ran here.
## Earlier ZIP content scan follow-up

Release remains **NO-GO**. The most useful open source-only item selected here
is reading the retained ZIP contents through an actual scanner entry, rather
than treating filename checks or a missing Python interpreter as a payload scan.
No production launcher, runtime, switch or server behavior changed.

Done:

- Added [scan_public_zip.ps1](tools/scan_public_zip.ps1) and its bounded,
  read-only ZIP helper. It refuses outside-tree paths, links, unsafe/colliding
  member names, unsupported metadata, oversized inputs and read failures.
  It never extracts or executes members. Findings print numeric positions and
  categories, not member names or matched values. SHA-256 identifies the exact
  locked archive snapshot checked. The existing source-content rules apply;
  this cannot approve legitimate binary player payloads.
- Real subprocess tests require clean text ZIPs to pass before checking
  refusals. The first aggregate run caught a fixture-writer error and failed;
  its owner fixed the fixture and reran it. Independent review reproduced two
  real false passes with harmless text ZIPs: mismatched local-header names and
  unindexed gaps. The helper now rejects inconsistent local/central headers
  and gaps/overlaps. The reviewer reran the same unchanged reproductions:
  clean still passes; both bypasses now refuse. No test was weakened.
- Ran [check_public_zip.ps1](tools/check_public_zip.ps1): eight syntax parses,
  actual catalogs (23 unique tools each, three root files), 60 positive-entry
  assertions / 10 subprocesses, and 171 safety assertions / 33 subprocesses.
  Root, the area agent and independent reviewer runs exited 0. All 79 patch
  names and SHA-256 hashes stayed unchanged.
- The actual command read all three retained source-test archives: 123, 124
  and 124 files; each exited 1 after scanning contents. Each has 46 members
  with email, patch-author mailbox and coauthor-mail categories (138 category
  records per archive). Archive hashes stayed unchanged. See
  [PUBLIC_ZIP_AUDIT.md](docs/PUBLIC_ZIP_AUDIT.md) for exact identities/results.
- Exercised the existing public-source export on `LICENSE` and all 79 patches:
  80 files, cleaned preambles, byte-identical diff parts, postwrite scan passed.
  The Windows convenience ZIP writer then produced backslash paths and the
  ZIP entry correctly refused them. A separate archive with explicit portable
  paths passed: 80 files, 2,025,621 bytes, SHA-256
  `fb80808520f464250cd13a548413f2d04771461251e8bdb03993599aae3d1f7d`.
  Both experiments remain under logs; neither is a complete source/player
  candidate. No retained input archive or source patch was rewritten.

Open / owner-only:

- The scan does not recompute CRCs, authenticate producers, inspect every
  possible hidden compressed representation, validate player manifests/locks
  or establish licences. Its restricted ordinary-ZIP support refuses ZIP64,
  comments, extra fields and data descriptors. See
  [PUBLIC_ZIP_SCAN.md](docs/PUBLIC_ZIP_SCAN.md) for scope and commands.
- Whole-tree source checking remains red: in addition to the 18 older text-only
  image-name fixtures, retained unsafe ZIP fixtures trigger name findings and
  intentionally corrupt ZIPs stop the old archive-name reader. Document links
  and PowerShell parses run before that stop: the final six-document check
  resolved 51 local links and parsed 58 PowerShell files, then exited 1 on an
  intentionally corrupt ZIP. Nothing was deleted or the old checker weakened
  to manufacture a pass.
- Review and prepare the exact complete public source/player outputs. Run the
  Python suites and payload checks with a real interpreter, then prove the
  actual launcher, exact build, game and two-PC routes in the authorized
  checkout. GUI startup, Host/Join, results, private protocol and licensing
  gates elsewhere in this record remain open. No Python, GUI, build, game or network helper
  ran here; a source ZIP pass cannot close those gates.

Eight area agents read AGENTS.md and have separate file ownership:
`zip_reader`, `zip_entry`, `zip_entry_tests`, `zip_safety_tests`,
`zip_catalogs_tests`, `zip_docs`, `archive_audit`, `verify_evidence`.
Separate `final_diff_review` independently ran the aggregate checker, latest
archive scan and before/after bypass reproductions, and reviews the finished
diff against the saved original document bytes. Root owns this record and
`docs/status.md`. All work stays in this tree; no Git command,
build, game, network helper, server, push or release is authorized.

Latest owner-supplied verification, not reproduced here: draft `477105a109`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 164-second build `943fc4631acf2c13`. Selftest: 232 successful restores,
514 resim comparisons, zero mismatches, 116/116 deliberate wrong-input
divergences. Same-PC 6000-frame pair, experiment switches OFF: 199 hashes per
side, zero mismatches and NETDESYNC lines, run-average 52.3 FPS on both sides;
host/join stalls 0/78 (0/2862 ms). Finished `2026-11-02T01:50:45`.
This supersedes the supplied reports below. It does not prove this edited
tree, the GUI's enabled COALESCE/DIAG profile or two physical PCs.

## Package 5 online follow-up, latest session

Online acceptance remains **BLOCKED**. No production launcher, runtime, switch
or server behavior changed. The shared OpenRecomp-FGC launcher, private lobby
and T5DR launcher sources are absent from this copy. Python is unavailable;
builds, game runs and `tools/net_*` execution are forbidden here. A passing
source test cannot establish that online works.

Done:

- Put the current package-5 decisions above the historical proposals in
  [SERVER_HANDOFF_T4.md](SERVER_HANDOFF_T4.md) and [LOBBY.md](docs/LOBBY.md):
  lobby protocol stays 1, existing accounts carry over, T4 matches/ratings
  stay separate, and no server change is authorized now. Package 5 follows
  the planned 2026-11-03 reset; no reset is claimed to have happened.
- Recorded [accounts/kicked](docs/ONLINE_ACCOUNTS.md),
  [coexistence](docs/ONLINE_COEXISTENCE.md),
  [client rank text](docs/ONLINE_RANKS.md) and
  [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md), with concrete owner
  cases through the actual launchers. Today's supplied one-login takeover
  rule is distinct from the later target of concurrent per-game sessions.
- Found an existing optional diagnostic session report, not a usable ranked
  result: `winner` and `score` are null, `match_result_proven` is false, and
  there is no proven match-end detector. No ranked result was produced here.
- Added [check_online_readiness.ps1](tools/check_online_readiness.ps1).
  It checks source/docs, invokes actual catalog and starter-refusal entries,
  and exits **2 / BLOCKED** after successful source checks. Exit 1 means a
  source/input failure; exit 0 is unavailable. It is not a payload/privacy
  scanner and does not replace the existing beta/publication gates.
- Added [test_launcher_entry.ps1](tools/test_launcher_entry.ps1), which checks
  the exact starter hash and refuses private Python/reparse points before
  invoking the real `Tekken4.cmd`. Its observed missing-Python exit 1 proves
  only the refusal branch. The GUI never started. No interpreter or game was
  substituted to turn that result green.
- Added [check_online_catalogs.ps1](tools/check_online_catalogs.ps1): actual
  source catalogs contain 23 unique present tools each and three source root
  files; Host/Join dependencies are present. This is literal source inspection,
  not execution of Python suites, packagers or a complete player package.
- Added [test_online_readiness.ps1](tools/test_online_readiness.ps1), which
  invokes the actual checker three times: blocked readiness, missing document
  and outside-tree document refusal before child entries. All three cases ran.

Latest supplied verification, not reproduced here: draft `42c131551e`, merge
base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean merge;
163-second build `943fc4631acf2c13`. Selftest: 202 successful restores,
447 resim comparisons, zero mismatches, 101/101 wrong-input divergences.
Same-PC 6000-frame pair, switches OFF, RTT target 150 ms, jitter 5 ms, loss 3%:
199 hashes per side, zero mismatches and NETDESYNC lines, 52.2 FPS run average
on both sides; host/join stalls 0/73 (0/2411 ms). Finished
`2026-11-02T01:18:22`. This supersedes the older supplied reports below.

The latest pair covers the reported OFF experiment configuration only.
It proves no newly enabled experimental switch. Source inspection shows
ordinary GUI Host/Join clears inherited overrides, then the helper enables
COALESCE=1 and DIAG=1. That launcher profile remains unproved by the latest
pair. Existing baseline time sync/early/lazy controls are not all disabled
by the phrase "switches OFF"; full effective settings still need recording.
No switch was changed without its required real-entry proof.

Root verification ran the real readiness entry: 12 required files, seven
PowerShell parses, seven documents and 47 local links checked; both catalog
and actual starter-refusal entries ran; final exit 2 / BLOCKED. The real
readiness test entry passed all three subprocess cases (exit 0 for the tests,
not acceptance). The existing `check_beta_source.ps1` also ran on all eight
changed documents: 48 local links and 53 PowerShell parses passed; overall
exit 1 solely for the same 18 retained text-only `.png` fixture filenames
recorded previously. Nothing was deleted or weakened to remove that failure.

Open / owner-only:

- Provide/review the shared-launcher and private protocol sources in their
  authorized lanes. Settle outgoing fields/caps, saved-login policy and a
  shared one-game-per-PC guard. Do not copy T5DR code into this GPL-3 tree.
- Start both actual launchers and prove login/search, then match/ready/result,
  then rooms/friends, then tournaments/spectating. Show `kicked` clearly and
  stop automatic login in both directions. Current takeover is supplied
  behavior, not a server test performed here. Account changes wait until after
  the T4 release; the later per-game session model needs its own acceptance.
- Build the exact reviewed candidate in the authorized checkout, prove the
  selected switches through actual GUI Host and Join, and repeat on two
  physical PCs, including direct/relay routes, rematch and disconnect recovery.
  Source tests and the supplied same-PC pair do not prove any of those routes.
- Prove winner, score and match end before ranked reporting. Rank names remain
  client text only; Tekken 8 names belong to Bandai Namco. No art was added.
- Python suites, GUI/Tk startup, Host/Join game launch, cross-launcher locking,
  server compatibility and all real build/game checks remain UNRUN here.
  Existing beta/publication NO-GO requirements below remain open.

Agents: `protocol_contract`, `accounts_kicked`, `rollback_evidence`,
`rank_text`, `coexistence`, `starter_entry`, `readiness_entry`,
`catalogs_tests`; separate `final_diff_review` completed with no blocking
issue found in these tools/docs. The reviewer independently reproduced all
three entry tests, readiness exit 2 and the existing source check's 18 fixture
findings. Review used current files and recorded text edits; a complete
original-byte/Git baseline was unavailable. This does not close online acceptance.
All read AGENTS.md; file ownership was exclusive. Root owns this record and
`docs/status.md`. No Git command, server, push or release was used.

## Earlier public-tree preparation

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

An earlier supplied verification identified draft `21d1fbb4b6`, merge
base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean merge;
174-second build `943fc4631acf2c13`. Selftest: 232 successful restores,
514 compared resim frames and zero mismatches. Same-PC 6000-frame pair with
switches off: 199 hash comparisons per side, zero mismatches and zero NETDESYNC
lines; run-average 49.8 fps on both sides, join 122 stalls / 3169 ms. Finished
2026-11-02T01:05:32. The package-5 section above records the newer report.
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
