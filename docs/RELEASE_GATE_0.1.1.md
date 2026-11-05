# Tekken 4 v0.1.1 release gate

Status: **IN PROGRESS / NO-GO. No release acceptance is granted.**
Snapshot: `2026-11-05T01:04:27+01:00`. Later results must be added before a final decision.

## Final gate run 2026-11-05 (movie guard, build `00bf3c0dd94fc2da`, source f3a5e5c)

Decision: **NETCODE GO, FRAME-TIME CRITERION NOT MET (NO-GO as written)**. All paths are under `logs/release-gate/` unless noted.

- Ancestry: `t4-ranked` (98c51bd, 425e4ea) recorded with `merge -s ours`; every added line of the branch was already in HEAD (99e259e). Widescreen stays off by default and is not merged.
- Build: `build-final-tree-r5` (stage + runtime, 169 s, exit 0). Needs `GIT_CONFIG_*` safe.directory for `deps/ps2recomp` (owned by the Codex sandbox user), no global git config change.
- Movie finding: it is a **scene change inside a re-simulation**, not a movie decoder problem (docs/MOVIE_ROLLBACK_T4.md). Repro `mv-title-off` (guard off): first mismatch 1230, 26 sampled hashes differ. Fix `mv-title-on` (guard on): 0 mismatches, 69 common hashes, lockstep until VS select. The normal online flow never leaves scenes 7/4 (NETSCENE lines of every lobby run), scripted exits from select (`mv-story-on`, `mv-story2-on`) did not leave scene 7; the guard covers the take-over and AUTO_VS=0 cases.
- Local lobby, NET_SIM lat=75 jitter=5 loss=3 per side (RTT ~150), names + badges (cached T5DR plate on one PC, drawn on the other), mirror Kazuya, first-to-3:
  `build/release-gate/lobby-runs/gate-lobby-ranked-r5-rb` PASS (2 matches 3-0, lobby `confirmed`, 487 + 487 hash frames, 0 mismatches, same result hash; ~2,150 rollbacks per match on the joiner, max depth 7-9);
  `gate-lobby-guest-r5-rb` PASS (guest account, sides swapped between the two matches = guest on P1 and P2, 487 + 487, 0 mismatches);
  `gate-lobby-ranked-r5-ls` PASS (whole-session lockstep, 0 rollbacks, 487 + 487, 0 mismatches).
  Not covered: a rematch inside one running process (T4 has no persistent game; every lobby match starts a new process).
- Unit/tool tests (isolated profile, PowerShell host): 142 tests, 2 failing: `test_publish_source.test_server_addresses` (known IPv6 fixture) and `test_player_python.test_dot_sourced_preflight_keeps_identity_api` (UTF-8 BOM on the preflight request pipe in this host; not touched by this change). `tools/test_movie_guard.py` 3/3. Player source catalog scan (`tools/test_zip.py --check-only`): PASS, 160 files.
- Frame times, no input, quiet PC (no other game running; 59 Hz monitor, `run_native_noinput.py`, demo fights = CPU vs CPU): `mv-perf-r5b` fights p50 16.6 / p95 17.6-17.9 / p99 18.1-18.5 ms, over 20 ms: 0, 6 and 4 per fight window (0-10 per minute), max 28.6 ms; title/menu window 2 per minute, p99 18.2. Whole run 47 intervals over 20 ms in 350 s. First run `mv-perf-r5` (other agents' programs active): title 446/min, fights 3-18/min. The "0 above 20 ms per minute" criterion is NOT met; no player-controlled fight and no intro A/V offset measurement (still unestablished).
- LocalTest: runtime staged from this tree with `D:\T4-LocalTest	oolsuild_local_game.py --stage-only` (build id above), `START_HERE.txt` rewritten in German.

## Current candidate and gate decision

Final main natural build ID: `2cc44895ff88b691`. EXE SHA-256: `6baf32534ef4dbc7cae5ce923c5817371366f431ed91263a6602d38057709ee1`. The actual pipeline rebuilt stage/runtime in 498.3 s; its controller ledger includes slot waiting and totals 538.656 s. Evidence: [logs/release-gate/build-final-tree-r3/result.json](<../logs/release-gate/build-final-tree-r3/result.json>) and [logs/release-gate/final-build.json](<../logs/release-gate/final-build.json>).

NO-GO reasons at this snapshot: normal 60 Hz/menu/player-fight and intro A/V acceptance are absent; serialized replay is unsupported; broad source policy and the IPv6 fixture remain failed; exact v0.1.0 provenance and actual LocalTest application are blocked. Remaining network/lobby cases are credited only by their own completed evidence below.

| Requirement | Current result | Evidence |
| --- | --- | --- |
| Ranked integration + final tree build | PASS; requested commits merged/resolved, final main rebuilt | [build/release-gate/ranked-integration-report.json](<../build/release-gate/ranked-integration-report.json>) |
| Unit/tool checks | PARTIAL: final portable 58/58; source-publisher IPv6 fixture still fails | [build/release-gate/portable-python-tests.json](<../build/release-gate/portable-python-tests.json>) |
| Player source catalog | PASS, 160 files; frozen-source actual CLI rerun passed00:38:50 | [logs/release-gate/source-player-catalog-frozen/result.json](<../logs/release-gate/source-player-catalog-frozen/result.json>) |
| Broad source policy | FAIL final 493 files / 72 flagged paths; initial 491/70 retained | [logs/release-gate/source-scan-final/result.json](<../logs/release-gate/source-scan-final/result.json>) |
| Rollback lat75/jitter5/loss3, main guest P1 | PASS correctness; 533 in-range equal checkpoints | [logs/release-gate/rollback-main-guest-p1/pair-result.json](<../logs/release-gate/rollback-main-guest-p1/pair-result.json>) |
| Whole-session lockstep, fresh guest P2 | PASS: all16000 L, zero rollback/resim;533 in-range equal checkpoints; sampled guest/badge visuals pass | [logs/release-gate/lockstep-fresh-guest-p2-r2/console.txt](<../logs/release-gate/lockstep-fresh-guest-p2-r2/console.txt>) |
| Local-lobby ranked FT3/set, reporting, guest sides, rematch | PENDING accepted real scenario summaries; prepare/unit results do not count | [build/release-gate/local_lobby_gate.py](<../build/release-gate/local_lobby_gate.py>) |
| Serialized replay record/playback | UNSUPPORTED / NOT ACCEPTED; rollback resimulation is a different check | [build/release-gate/replay-capability-review.json](<../build/release-gate/replay-capability-review.json>) |
| Fresh ISO build, spaces + Unicode | PASS actual portable Python / installed MSVC; not bundled-compiler acceptance | [build/release-gate/fresh-attempt3/player-build.json](<../build/release-gate/fresh-attempt3/player-build.json>) |
| Exact old v0.1.0 update | UNATTESTED version; isolated older-install data/profile preservation passed | [build/release-gate/old-update.json](<../build/release-gate/old-update.json>) |
| Normal menus + player fight at 60 Hz | PENDING; every interval15.7..17.7ms and zero>20ms/min not established | [build/release-gate/movie-frame-review.md](<../build/release-gate/movie-frame-review.md>) |
| Intro A/V offset<45ms | UNESTABLISHED; producer/served-picture diagnostics do not establish presentation/playback | [build/release-gate/movie-frame-review.md](<../build/release-gate/movie-frame-review.md>) |
| Actual LocalTest update | BLOCKED outside writable roots;537-file final overlay verified | [build/release-gate/localtest-final-verification.json](<../build/release-gate/localtest-final-verification.json>) |
| Widescreen conditional integration | KEEP OFF; current render-only completion not accepted | [build/release-gate/widescreen-final-recheck.json](<../build/release-gate/widescreen-final-recheck.json>) |
| Proton notes | UNCHANGED; real Wine/Deck validation remains pending as before | [docs/LINUX_STEAM_DECK.md](<../docs/LINUX_STEAM_DECK.md>) |

## Integration, fixes and source boundaries

Starting branch `t4-int-prep`, starting HEAD `0cf060b`; pre-existing dirty stutter work was preserved. Requested ranked commits `98c51bd` (round settings) and `425e4ea` (badge redesign) were merged with `--no-commit --no-ff` in the private checkout `build/release-gate/ranked-merge`, seven conflicts resolved, and 30 paths integrated. The linked outer Git metadata is outside writable roots. [build/release-gate/ranked-integration-report.json](<../build/release-gate/ranked-integration-report.json>) records conflict resolutions, earlier failed helper checks and their passing reruns.

The first main build failed because Python staging omitted the transitive badge headers. Python now stages maintained `tekken4_*.h`; the regression traverses actual production include closure. The fresh Unicode build then found a real MSVC PCH-path failure: runtime C/C++ flags now explicitly use `/utf-8` in Python, runtime CMD, portable CMD and performance CMD routes. A real CMake/Ninja/PCH compiler regression reproduces the old failure and passes the corrected flags. Runtime resume fingerprints now include the effective CMake configuration; the stateful regression proves unchanged options skip and changed compiler flags rebuild. See [build/release-gate/utf8-source-review.json](<../build/release-gate/utf8-source-review.json>) and [tools/test_player_unicode.py](<../tools/test_player_unicode.py>).

All 88 patches were reconstructed from pinned PS2Recomp `eb8688b2fd191129f103a39543002c005b33409c`. The initial 345-file comparison found a line-ending-only IOP difference and the deliberately staged generated registration. The IOP file was synchronized to canonical patch bytes; 344 non-registration source files match, while game registration was preserved instead of replacing it with the upstream stub. Overlapping-patch reverse-check warnings in the developer builder are retained; they are not the independent applicability proof. [build/release-gate/patch-stack-03/report.json](<../build/release-gate/patch-stack-03/report.json>); [build/release-gate/patch-stack-03/vendor-sync.json](<../build/release-gate/patch-stack-03/vendor-sync.json>).

Selected player catalog: PASS, 160 files under the unchanged conservative scanner; the actual frozen-source `tools/test_zip.py --check-only` entry passed again at00:38:50 after the resume-fingerprint fix ([logs/release-gate/source-player-catalog-frozen/result.json](<../logs/release-gate/source-player-catalog-frozen/result.json>)). Broad source snapshots both remain visible: initial 491 files / 70 flagged paths and final 493 files / 72 flagged paths (reason categories overlap). The two added finding paths are report/new-Unicode-test machine paths, not newly found game data or keys. Final evidence: [logs/release-gate/source-scan-final/result.json](<../logs/release-gate/source-scan-final/result.json>); [logs/release-gate/source-scan-final/manifest.json](<../logs/release-gate/source-scan-final/manifest.json>); [logs/release-gate/source-scan-final/findings.json](<../logs/release-gate/source-scan-final/findings.json>). Documentary EXE hashes account for credential-pattern hits; the SVG hit is handwritten artwork-generator source. Real machine/private paths and server references remain; the unused PAL diagnostic wrapper has a game-derived116-symbol address/function watch table requiring exclusion/manual source-policy review. No ISO/BIOS/key/archive-signature findings were reported. This is not a clean broad-source publication pass; no scanner was weakened. The35-test source-publisher suite also retains one failing IPv6-address fixture. [build/release-gate/source-scan-triage.json](<../build/release-gate/source-scan-triage.json>).

## Network evidence and its limits

The completed direct main/guest P1 rollback case used NET_SIM `lat=75,jitter=5,loss=3` (harness RTT150), separate local seeds and loopback only. Both peers reached `NETEND f=16000`; actual rollbacks were 8/2459, with 16/4242 resimulated frames. Independent comparison found533 shared checkpoints within the requested range, frames30..15990, zero differences and zero NETDESYNC. Two additional post-end checkpoints are not credited toward this count. Both game-produced results agree: mirrored fighter IDs14/14 (Kazuya), three rounds to win, P1 score 3-0, match end 14057 and agreed result hash. [logs/release-gate/rollback-main-guest-p1/pair-result.json](<../logs/release-gate/rollback-main-guest-p1/pair-result.json>); [build/release-gate/rollback-main-review.json](<../build/release-gate/rollback-main-review.json>).

Sampled native window/framebuffer captures passed guest P1 badge absence, native names, cached T5DR plate on one process and drawn fallback on the other, with three round markers. `Gate_Alpha` displays as `Gate_Alph` under the existing104px fit policy; this is sampled visual coverage, not an every-frame assertion. Captures/game artwork remain in ignored local run folders, not this report.

This direct-IP case does **not** prove local-lobby reporting, a completed ranked set, guest swap/rematch, serialized replay, or isolated 60 Hz performance. Its `reporting_finished` is a game session-result field, not lobby acknowledgment. Online sampled hashes include the documented game/IOP scope and exclude VU1/GS; zero sampled mismatches are not a full graphics-state equality claim. Background peers were intentionally terminated after NETEND, so native graceful exit is not established. Network stress counters show many>20ms intervals; they cannot substitute for normal menu/player-fight acceptance.

Fresh whole-session lockstep/guest P2, case `lockstep-fresh-guest-p2-r2`: **PASS: all16000 L, zero rollback/resim;533 in-range equal checkpoints; sampled guest/badge visuals pass**. First admission attempt `lockstep-fresh-guest-p2` expired after the30-minute queue budget without native launch; it is NOT RUN, not a failed game/hash check. The retry used20ms admission polling. [logs/release-gate/lockstep-fresh-guest-p2/result.json](<../logs/release-gate/lockstep-fresh-guest-p2/result.json>).

Accepted fresh retry: both peers reached NETEND f=16000 with all16000 live boundaries L and no N/R phase, rollbacks, resimulation or depth. Both transport counters compared533 checkpoints with zero mismatches/NETDESYNC; independent in-range comparison also matched533. The actual Unicode EXE, ELF and per-run profile paths were used. Mirrored Kazuya14/14, FT3, P1 wins3-0/end14057 and agreed result hash match. P1 cached plate versus drawn fallback, P2 guest badge absence and sampled native names passed visual review (Gate_Alph under the existing width budget). [logs/release-gate/lockstep-fresh-guest-p2-r2/pair-result.json](<../logs/release-gate/lockstep-fresh-guest-p2-r2/pair-result.json>); [build/release-gate/fresh-lockstep-review.json](<../build/release-gate/fresh-lockstep-review.json>).

Read-only comparison of the completed rollback-main and lockstep-fresh cases found identical shared game outcome fields, including start2206/end14057, rounds,3-0 score, fighter/costume fields and agreed result hash `e795da4079674cb3` at14070. This is separate same-script cohort evidence, not a mixed-ID native session or compatibility override. [build/release-gate/cross-mode-outcome-comparison.json](<../build/release-gate/cross-mode-outcome-comparison.json>).

Local-lobby scenario inventory:

| Scenario/run | Result | Scenario | Mode | Evidence |
| --- | --- | --- | --- | --- |
| gate-lobby-ranked-main2cc-rb | IN PROGRESS / no accepted summary | ranked | rollback | [build/release-gate/lobby-runs/gate-lobby-ranked-main2cc-rb/parameters.json](<../build/release-gate/lobby-runs/gate-lobby-ranked-main2cc-rb/parameters.json>) |
| prepared-main2cc-lobby-admission | PREPARED ONLY; no games/network | ranked | rollback | [build/release-gate/lobby-runs/prepared-main2cc-lobby-admission/parameters.json](<../build/release-gate/lobby-runs/prepared-main2cc-lobby-admission/parameters.json>) |
| prepared-ranked-mirror | PREPARED ONLY; no games/network | ranked | rollback | [build/release-gate/lobby-runs/prepared-ranked-mirror/parameters.json](<../build/release-gate/lobby-runs/prepared-ranked-mirror/parameters.json>) |

Serialized file replay is not implemented: `docs/ROLLBACK_NEXT.md`418-419 marks it planned;573 records missing canonical setup/playback;684-687 are specifications, not dormant switches. Current modes are Off/Measure/Test/SelfNet/Net. Input scripts, `TEKKEN4_NET_REPLAY_BATCH`, `TEKKEN4_NET_REPLAY_BEFORE_SYNC`, and successful rollback resimulation are not serialized record/playback proof. The rule requiring identical replay playback remains unmet; no hidden switch or invented replay pass is claimed. [build/release-gate/replay-capability-review.json](<../build/release-gate/replay-capability-review.json>).

## Player builds, identities and LocalTest

The actual OpenRecomp portable Python 3.12.10 built from the verified US ISO in `build/release-gate/player fresh Tëst`, initially with no game/generated/out. Local dependency caches were disconnected. This validates that interpreter with installed MSVC 19.44.35229.0; it does not validate a bundled clang-cl/sysroot or complete GUI workflow. The all-eight-stage dry run passed. First real attempt failed due to the harness excluding the host-tool runner; second reached runtime and failed the product Unicode PCH path; third passed 430.7 s. Final-helper resume passed 409.938 s with a full 407.4 s runtime recompile: CMakeCache values and compile-command hashes were unchanged, but the no-work expectation was not met; exact dependency/timestamp invalidation remains unverified. Failures and attempts were preserved.

Main natural ID is `2cc44895ff88b691`; fresh natural ID remains `afdb353c7e6525fc`. Both recompute exactly from their own stored fields, with identical compiler configuration. Normalized20 runtime files,262 tool files,6 config files,88 patches,4816 staged generated C++/header inputs, six native VU1 generated files, four lift-generated files, and both micro inputs match. The watched hand-source delta is the fresh local-cache FFmpeg CMake adapter. Existing identity preimages differ: Git tree/diff versus vendored receipt/source hashes. No source/stamp rewrite or identity override was used to force equality. [build/release-gate/identity-recipes-final-main-r3.json](<../build/release-gate/identity-recipes-final-main-r3.json>); [build/release-gate/fresh-native-components.json](<../build/release-gate/fresh-native-components.json>).

Compatibility wording is conditional: native HELLO rejects **differing nonzero IDs** independently of `STRICT_HELLO` (`runtime/tekken4_net.cpp`673-684). Strict mode additionally rejects missing/zero IDs; legacy unknown-ID behavior must not be described as universal rejection. Python preflight compares IDs. Lobby matching defaults to exact recomputed BuildInfo IDs; optional server-approved compatibility groups were not introduced here. Normal stamped main/fresh mixed online compatibility is therefore unavailable/unverified, and source equivalence is not a compatibility approval. No mixed-ID probe or bypass was performed.

An isolated older install was overlaid and updated to final main2cc. Its original game-data hashes and exact synthetic profile sentinel bytes are unchanged; the source old install was untouched. No receipt/tag attests it as exact v0.1.0, so that specific upgrade gate is still open. A checker initially expected LF instead of the Windows-created CRLF sentinel; that fixture-only failure is retained and corrected verification passes without profile writes. [build/release-gate/localtest-final-verification.json](<../build/release-gate/localtest-final-verification.json>).

Actual `D:/T4-LocalTest` is outside this session's writable roots and was not updated. Final537-file reviewable overlay: `build/release-gate/localtest-update/payload`; hash manifest: [build/release-gate/localtest-update/manifest.json](<../build/release-gate/localtest-update/manifest.json>); bounded hash-checking apply helper: [build/release-gate/localtest-update/apply_update.py](<../build/release-gate/localtest-update/apply_update.py>). Top-level German START_HERE is included in that manifest, states final main2cc and NO-GO, and preserves existing starters/profiles/data. The staged EXE hash matches the final main hash above. This is preparation, not a claim that the destination was modified. Proton notes/tests stayed unchanged; real Wine/Deck validation remains pending as documented.

## Widescreen, timing and A/V

Keep both widescreen switches OFF (`TEKKEN4_WIDESCREEN=0`, `PS2X_SWITCH_WIDESCREEN=0`). No pending replacement was imported. The latest reviewed branch/candidate is not a finished passing render-only replacement: current v4 PNACH/HELLO work changes simulation/protocol, its passing cases do not replace the missing current render reverse/lockstep matrix, controlled final performance remains pending, and render replay proof is absent. Historical v3 controlled60Hz failure remains historical evidence, not a current pass. The current render visuals cover only inspected Airport/Arena scenes. [build/release-gate/widescreen-final-recheck.json](<../build/release-gate/widescreen-final-recheck.json>). The conditional4:3-versus16:9 integration gate is not claimed as run on the final OFF candidate.

Normal timing acceptance remains pending: final code, quiet HEAVY scheduling, actual 60 Hz/complete trace, at least60s menus and60s ordinary player fight, every interval15.7..17.7ms and zero strict>20ms/min. Network stress, oracle/hash instrumentation,500Hz sandbox, natural demo-only captures, or a swap-return clock must not be relabelled as normal player/presentation acceptance. Intro A/V<45ms is also not established: current producer/mixer/served-picture clocks do not prove actual presentation/physical playback, and earlier baseline diagnostics exceed45ms. Unmerged newer movie sync attempts are not accepted evidence. [build/release-gate/movie-frame-review.md](<../build/release-gate/movie-frame-review.md>).

## Every recorded gate run

Root/controller wall time includes any slot wait and cleanup; it is not native frame performance. A process exit0 alone does not satisfy game/visual/lobby/timing acceptance. Failed and incomplete invocations remain visible.

| Root invocation | Result / observation | Controller s | Evidence |
| --- | --- | --- | --- |
| build-final-tree | FAIL: Python badge header staging omission | 377.203 | [logs/release-gate/build-final-tree/result.json](<../logs/release-gate/build-final-tree/result.json>) |
| build-final-tree-r2 | PASS; superseded pre-UTF8 build94ccff129dd2b266 | 163.391 | [logs/release-gate/build-final-tree-r2/result.json](<../logs/release-gate/build-final-tree-r2/result.json>) |
| build-final-tree-r3 | PASS final main; pipeline 498.3 s | 538.656 | [logs/release-gate/build-final-tree-r3/result.json](<../logs/release-gate/build-final-tree-r3/result.json>) |
| lockstep-fresh-guest-p2 | NOT RUN: HEAVY admission timed out; no native/game/hash failure | - | [logs/release-gate/lockstep-fresh-guest-p2/result.json](<../logs/release-gate/lockstep-fresh-guest-p2/result.json>) |
| lockstep-fresh-guest-p2-r2 | PASS pair acceptance; review limits separately | 310.359 | [logs/release-gate/lockstep-fresh-guest-p2-r2/result.json](<../logs/release-gate/lockstep-fresh-guest-p2-r2/result.json>) |
| rollback-main-guest-p1 | PASS pair acceptance; review limits separately | 319.563 | [logs/release-gate/rollback-main-guest-p1/result.json](<../logs/release-gate/rollback-main-guest-p1/result.json>) |
| source-player-catalog | PASS invocation | 1.734 | [logs/release-gate/source-player-catalog/result.json](<../logs/release-gate/source-player-catalog/result.json>) |
| source-player-catalog-final | PASS invocation | 1.703 | [logs/release-gate/source-player-catalog-final/result.json](<../logs/release-gate/source-player-catalog-final/result.json>) |
| source-player-catalog-frozen | PASS invocation | 1.687 | [logs/release-gate/source-player-catalog-frozen/result.json](<../logs/release-gate/source-player-catalog-frozen/result.json>) |
| source-scan | FAIL initial source policy (491 files / 70 flagged paths) | 5.922 | [logs/release-gate/source-scan/result.json](<../logs/release-gate/source-scan/result.json>) |
| source-scan-final | FAIL final source snapshot (493 files / 72 flagged paths) | 5.828 | [logs/release-gate/source-scan-final/result.json](<../logs/release-gate/source-scan-final/result.json>) |
| unit-test_launcher_online | PASS invocation; 11 tests | 0.468 | [logs/release-gate/unit-test_launcher_online/result.json](<../logs/release-gate/unit-test_launcher_online/result.json>) |
| unit-test_launcher_widescreen | PASS invocation; 4 tests | 0.157 | [logs/release-gate/unit-test_launcher_widescreen/result.json](<../logs/release-gate/unit-test_launcher_widescreen/result.json>) |
| unit-test_launcher_wine | PASS invocation; 6 tests | 0.141 | [logs/release-gate/unit-test_launcher_wine/result.json](<../logs/release-gate/unit-test_launcher_wine/result.json>) |
| unit-test_match_state | PASS invocation; 1 tests | 3.344 | [logs/release-gate/unit-test_match_state/result.json](<../logs/release-gate/unit-test_match_state/result.json>) |
| unit-test_movie_wav_compare | PASS invocation; 13 tests | 1.703 | [logs/release-gate/unit-test_movie_wav_compare/result.json](<../logs/release-gate/unit-test_movie_wav_compare/result.json>) |
| unit-test_native_names | FAIL helper compilation; later ranked rerun passed; 2 tests | 2.890 | [logs/release-gate/unit-test_native_names/result.json](<../logs/release-gate/unit-test_native_names/result.json>) |
| unit-test_player_python | PASS invocation; 32 tests | 3.250 | [logs/release-gate/unit-test_player_python/result.json](<../logs/release-gate/unit-test_player_python/result.json>) |
| unit-test_publish_source | FAIL: 1 IPv6-address fixture among35 tests; not waived | 0.407 | [logs/release-gate/unit-test_publish_source/result.json](<../logs/release-gate/unit-test_publish_source/result.json>) |
| unit-test_release_catalogs | PASS invocation; 7 tests | 3.062 | [logs/release-gate/unit-test_release_catalogs/result.json](<../logs/release-gate/unit-test_release_catalogs/result.json>) |
| unit-test_rounds_setting | PASS invocation; 1 tests | 0.109 | [logs/release-gate/unit-test_rounds_setting/result.json](<../logs/release-gate/unit-test_rounds_setting/result.json>) |
| unit-test_t4_buildid | PASS invocation; 9 tests | 0.531 | [logs/release-gate/unit-test_t4_buildid/result.json](<../logs/release-gate/unit-test_t4_buildid/result.json>) |
| unit-test_us_tree | PASS invocation; 7 tests | 10.360 | [logs/release-gate/unit-test_us_tree/result.json](<../logs/release-gate/unit-test_us_tree/result.json>) |
| unit-test_zip | NO TESTS / wrong unittest entry (exit5); corrected catalog check below; 0 tests | 0.140 | [logs/release-gate/unit-test_zip/result.json](<../logs/release-gate/unit-test_zip/result.json>) |
| unit-vu-lift | PASS invocation; 5 tests | 0.235 | [logs/release-gate/unit-vu-lift/result.json](<../logs/release-gate/unit-vu-lift/result.json>) |
| gate-lobby-ranked-main2cc-rb | QUEUED / RUNNING; no completed result | - | [logs/release-gate/gate-lobby-ranked-main2cc-rb/console.txt](<../logs/release-gate/gate-lobby-ranked-main2cc-rb/console.txt>) |

Ranked integration worker runs (the later pass does not erase the first failure):

| Helper | Recorded result | Evidence |
| --- | --- | --- |
| test_buildid.py.log | FAIL; Ran 8 tests in 0.073s | [build/release-gate/ranked-unit-tests/test_buildid.py.log](<../build/release-gate/ranked-unit-tests/test_buildid.py.log>) |
| test_buildid.py.rerun.log | PASS; Ran 8 tests in 0.041s | [build/release-gate/ranked-unit-tests/test_buildid.py.rerun.log](<../build/release-gate/ranked-unit-tests/test_buildid.py.rerun.log>) |
| test_launcher_online.py.log | PASS; Ran 11 tests in 0.009s | [build/release-gate/ranked-unit-tests/test_launcher_online.py.log](<../build/release-gate/ranked-unit-tests/test_launcher_online.py.log>) |
| test_native_names.py.log | FAIL; Ran 2 tests in 3.259s | [build/release-gate/ranked-unit-tests/test_native_names.py.log](<../build/release-gate/ranked-unit-tests/test_native_names.py.log>) |
| test_native_names.py.rerun.log | PASS; Ran 2 tests in 3.716s | [build/release-gate/ranked-unit-tests/test_native_names.py.rerun.log](<../build/release-gate/ranked-unit-tests/test_native_names.py.rerun.log>) |
| test_player_python.py.log | PASS; Ran 32 tests in 3.106s | [build/release-gate/ranked-unit-tests/test_player_python.py.log](<../build/release-gate/ranked-unit-tests/test_player_python.py.log>) |
| test_player_python.staging-fix.log | PASS; Ran 33 tests in 5.015s | [build/release-gate/ranked-unit-tests/test_player_python.staging-fix.log](<../build/release-gate/ranked-unit-tests/test_player_python.staging-fix.log>) |
| test_rank_badges.py.log | FAIL; Ran 2 tests in 4.002s | [build/release-gate/ranked-unit-tests/test_rank_badges.py.log](<../build/release-gate/ranked-unit-tests/test_rank_badges.py.log>) |
| test_rank_badges.py.rerun.log | PASS; Ran 2 tests in 3.654s | [build/release-gate/ranked-unit-tests/test_rank_badges.py.rerun.log](<../build/release-gate/ranked-unit-tests/test_rank_badges.py.rerun.log>) |
| test_rank_label.py.log | PASS; Ran 1 test in 3.470s | [build/release-gate/ranked-unit-tests/test_rank_label.py.log](<../build/release-gate/ranked-unit-tests/test_rank_label.py.log>) |
| test_rounds_setting.py.log | PASS; Ran 1 test in 0.002s | [build/release-gate/ranked-unit-tests/test_rounds_setting.py.log](<../build/release-gate/ranked-unit-tests/test_rounds_setting.py.log>) |
| test_t4_buildid.py.log | PASS; Ran 9 tests in 0.243s | [build/release-gate/ranked-unit-tests/test_t4_buildid.py.log](<../build/release-gate/ranked-unit-tests/test_t4_buildid.py.log>) |

Additional nonlaunch checks: ranked local-round contracts 9/9; lobby harness initial 3/3, rerun 4/4 and admission 7/7; pair parser 15/15; fresh-path adapter 8/8; timing-window/duration helper 6/6; PowerShell syntax 5 scripts. These are not real game/lobby/performance passes. Evidence: [build/release-gate/ranked-unit-tests/local-lobby-round-contract.log](<../build/release-gate/ranked-unit-tests/local-lobby-round-contract.log>), [build/release-gate/test_local_lobby_gate.log](<../build/release-gate/test_local_lobby_gate.log>), [build/release-gate/test_local_lobby_gate.rerun.log](<../build/release-gate/test_local_lobby_gate.rerun.log>), [build/release-gate/test_local_lobby_gate.admission.log](<../build/release-gate/test_local_lobby_gate.admission.log>), [build/release-gate/pair-parser-selftest.json](<../build/release-gate/pair-parser-selftest.json>), [build/release-gate/fresh-pair-static-check.json](<../build/release-gate/fresh-pair-static-check.json>), [build/release-gate/native-duration-selftest.json](<../build/release-gate/native-duration-selftest.json>), [logs/release-gate/powershell-syntax.json](<../logs/release-gate/powershell-syntax.json>).

Player worker ledger (18 recorded checks/runs): [build/release-gate/player-run-ledger.json](<../build/release-gate/player-run-ledger.json>). First 55/56/57 passing suites reused a shared log filename later replaced by the final 58 suite; their counts are retained in the ledger. Failed fixtures and heavy attempts have separate preserved artifacts.

| Player check/run | Result | Evidence / observation |
| --- | --- | --- |
| portable Python version | PASS | [build/release-gate/player-run-ledger.json](<../build/release-gate/player-run-ledger.json>); Actual OpenRecomp portable Python3.12.10; C:/OpenRecomp-work/fgc-rel/portable absent; D:/T4-LocalTest/OpenRecomp-FGC/portable present |
| portable tool suite before ranked header fix | PASS; 55 tests | [build/release-gate/player-run-ledger.json](<../build/release-gate/player-run-ledger.json>); 0 failures/errors/skips; original shared suite logs subsequently replaced by later runs |
| portable tool suite after ranked header fix | PASS; 56 tests | [build/release-gate/player-run-ledger.json](<../build/release-gate/player-run-ledger.json>); 0 failures/errors/skips; original shared suite logs subsequently replaced by later runs |
| Unicode all8-stage build dryrun | PASS | [build/release-gate/player-dryrun.json](<../build/release-gate/player-dryrun.json>); ISO verified; no game/generated/out initially existed |
| old-install isolated source overlay and preservation | PASS LIMITED | [build/release-gate/old-update.json](<../build/release-gate/old-update.json>); Copied existing old install data preserved byte-for-byte; original old install version cannot be attested v0.1.0 |
| old-install identity/root preflight drycheck before UTF8 main rebuild | PASS PRE-R3 | [build/release-gate/pre-utf8-local-update/old-update-preflight-drycheck.json](<../build/release-gate/pre-utf8-local-update/old-update-preflight-drycheck.json>); No network; main94cc matching binary; actual ISO identity hashed |
| fresh ISO build attempt1 | FAIL HARNESS PREPARATION | [build/release-gate/fresh-attempt1/player-build.json](<../build/release-gate/fresh-attempt1/player-build.json>); Global runner exclusion removed host-tool main.cpp; restored only host runner; root product unchanged |
| fresh ISO build attempt2 | FAIL PRODUCT UNICODE | [build/release-gate/fresh-attempt2/player-build.json](<../build/release-gate/fresh-attempt2/player-build.json>); MSVC read CMake-generated UTF8 PCH absolute path with wrong source charset; fixed explicit /utf-8 |
| real Unicode PCH old-flags baseline | EXPECTED FAIL | [build/release-gate/unicode-pch-baseline.log](<../build/release-gate/unicode-pch-baseline.log>); Old flags reproduce C1083 with real compiler; no mocked process |
| portable suite with initial PCH regression fixture | FAIL FIXTURE; 57 tests | [build/release-gate/unicode-fixture-std-failure/portable-python-tests.log](<../build/release-gate/unicode-fixture-std-failure/portable-python-tests.log>); Unicode path fixed; tiny fixture needed same C++20 standard as runtime; corrected |
| portable suite after UTF8 and fixture fix | PASS; 57 tests | [build/release-gate/player-run-ledger.json](<../build/release-gate/player-run-ledger.json>); 0 failures/errors/skips; subsequently replaced by final58 suite |
| portable suite final including configuration-cache regression | PASS; 58 tests | [build/release-gate/portable-python-tests.json](<../build/release-gate/portable-python-tests.json>) |
| fresh ISO build attempt3 | PASS | [build/release-gate/fresh-attempt3/player-build.json](<../build/release-gate/fresh-attempt3/player-build.json>); Actual portable interpreter, installed MSVC/local dependencies, Unicode+spaces folder; no bundled-compiler claim |
| final helper full-pipeline resume | PASS WITH FULL RECOMPILE | [build/release-gate/fresh-final-resume/player-resume.json](<../build/release-gate/fresh-final-resume/player-resume.json>); Runtime recompiled with unchanged options/command hashes; no-work expectation not met; naturalID unchanged; exact dependency invalidation unverified |
| final LocalTest actual update | BLOCKED | [build/release-gate/localtest-update/manifest.json](<../build/release-gate/localtest-update/manifest.json>); D:/T4-LocalTest is outside writable roots; final2cc main bits and verified German NO-GO note prepared in537-file overlay, actual target unchanged |
| mainr3/fresh natural recipe and compiled-source comparison | PASS READONLY PROVENANCE; NATURAL IDS DISTINCT | [build/release-gate/identity-recipes-final-main-r3.json](<../build/release-gate/identity-recipes-final-main-r3.json>); Both actual IDs recomputed correctly; compiler flags match; EE4816/runtime20/tools262/config/patches and nativeVU6+4/micro inputs match; existing Git/vendor recipes and local FFmpeg CMake adapter explain distinct IDs; no override or source/stamp mutation |
| final old profile preservation checker first expectation | FAIL CHECKER FIXTURE | [build/release-gate/final-profile-check-fixture-failure/diagnosis.json](<../build/release-gate/final-profile-check-fixture-failure/diagnosis.json>); Expected LF but initial Windows write_text created CRLF; actual original Windows bytes match exactly; checker corrected without profile writes |
| final old-data/profile/payload verification | PASS LIMITED | [build/release-gate/localtest-final-verification.json](<../build/release-gate/localtest-final-verification.json>) |

## Files and commit boundary

The initial final-file snapshot records 44 tracked paths changed relative to starting HEAD plus two untracked source files. Current read-only comparison: 44 tracked paths relative to `0cf060b`, 2 untracked files; 40 paths were captured by external `99e259e`. Remaining relative to current HEAD: 10 modified tracked files plus 2 untracked files. These sets overlap and are not additive; the start comparison includes preserved pre-existing stutter work, not only edits authored by this gate.

The external process created commit `99e259e` while the gate was running. None of this gate's agents ran commit or push; the external commit was preserved, not reset or attributed to this session. [logs/release-gate/external-head-change.json](<../logs/release-gate/external-head-change.json>); [build/release-gate/final-changed-file-review.json](<../build/release-gate/final-changed-file-review.json>).

Tracked paths changed relative to starting HEAD:

```text
docs/PERF_STUTTER_AUDIT.md
docs/T4_RANKED.md
docs/T4_ROUND_SETTING.md
docs/VU_RECOMP.md
docs/status.md
launcher/t4core.py
patches/90-Old-PCs-SSE2-baseline-build-option-OpenGL-4.3-4.6.patch
patches/95-vu-execution-path-audit.patch
patches/96-buffered-frame-trace-and-present-timing.patch
patches/97-iop-runtime-audit.patch
runtime/tekken4_badge_draw.h
runtime/tekken4_hud_overrides.cpp
runtime/tekken4_native_names.h
runtime/tekken4_net.cpp
runtime/tekken4_overrides.cpp
runtime/tekken4_rank_badges.h
runtime/tekken4_rank_cache.h
runtime/tekken4_rank_label.h
runtime/tekken4_rollback_overrides.cpp
runtime/tekken4_rounds.h
tools/build_game.py
tools/build_runtime.cmd
tools/build_runtime_portable.cmd
tools/make_rank_badges.py
tools/match_state_test.cpp
tools/native_names_test.cpp
tools/net_pair.ps1
tools/net_play.ps1
tools/net_play.py
tools/perf_build.cmd
tools/perf_present_report.py
tools/rank_badges_test.cpp
tools/rank_label_test.cpp
tools/stage_generated.cmd
tools/t4_buildid.py
tools/test_buildid.py
tools/test_launcher_online.py
tools/test_native_names.py
tools/test_player_python.py
tools/test_rank_badges.py
tools/test_rank_label.py
tools/test_rounds_setting.py
tools/vu/test_vu_lift.py
tools/vu/vu_lift.py
```

Remaining modified tracked paths relative to current HEAD:

```text
docs/status.md
tools/build_game.py
tools/build_runtime.cmd
tools/build_runtime_portable.cmd
tools/native_names_test.cpp
tools/net_pair.ps1
tools/perf_build.cmd
tools/test_buildid.py
tools/test_player_python.py
tools/test_rank_badges.py
```

Untracked source/document paths:

```text
docs/RELEASE_GATE_0.1.1.md
tools/test_player_unicode.py
```

All large builds, game-derived generated code/data, native captures and run artifacts stay under ignored local build/game/log folders. No game data, BIOS, keys, screenshots or decoded audio are proposed for commit. `CHANGELOG.md` was not edited.

Proposed commit after review: `Fix Python badge staging, UTF-8 resume fingerprints and gate harnesses`.

## Spielerhinweise - Entwurf, noch keine Freigabe

- Die vom Server festgelegte Rundenzahl wird beim Online-Start übernommen.
- Namen und Rangabzeichen wurden überarbeitet; vorhandene T5DR-Abzeichen werden lokal genutzt, sonst gezeichnete Abzeichen.
- Unter Windows funktioniert der Spielbau auch in Ordnern mit Leerzeichen und Umlauten.
- Breitbild bleibt standardmäßig ausgeschaltet.

## Safety and blocked application access

The gate used local network only, no live-server contact or real-account login. Automated games were muted/background/BelowNormal with isolated profiles, atomic HEAVY slots and serialized gate runs; timing requires at least two slots. Protected real OpenRecomp configuration hashes stayed unchanged in the accepted recorded runs. No release/deploy/commit/push was performed by this gate.

Automatic app approval rejected the read-only Explorer `get_window_state` request for the observed old-release window (`release-v0.1.0-test.202611032156`), stating **"Computer Use was not approved to use explorer"**. That prevented confirming its folder path; the rejection was not bypassed. This is separate from the writable-root restriction blocking actual LocalTest application. The known isolated older install is not falsely promoted to an attestedv0.1.0 upgrade.
