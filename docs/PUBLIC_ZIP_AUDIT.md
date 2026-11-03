# Retained source ZIP scan, 2026-11-02

Release remains **NO-GO**. These three retained Sunday source-test archives
are old inputs, not a complete current player candidate. The real
[scan_public_zip.ps1](../tools/scan_public_zip.ps1) command reads member bytes
without extracting or executing them. Its conservative source/privacy checks
are separate from the Python player-payload manifest, lock and pinned-input
checks. A refusal does not establish a runtime failure.

## Input identity

All three archives are under `dist/sunday/`. Counts below were read directly
from ZIP metadata before the content command ran. Compressed size is the
archive file size; member bytes are the declared uncompressed total.

| Archive | Files / entries | Member bytes | Archive bytes | SHA-256 |
|---|---:|---:|---:|---|
| `tekken4-sunday-test-20261031-042256-264836.zip` | 123 / 123 | 4187421 | 1058028 | `15f46619aa5e98ea13005801c2493ee70ed2b6a1c498a5d27f3334cd5c10594c` |
| `tekken4-sunday-test-20261031-205433-879960.zip` | 124 / 124 | 4207076 | 1066041 | `ae318bdc016238299a947ee3618f0819c5fc89678cc9556fb06078c25c392ce4` |
| `tekken4-sunday-test-20261031-205628-895451.zip` | 124 / 124 | 4207280 | 1066135 | `eb00046c520efb4bc3f6cfdba12803fb25cbec321f985609093de1880a5c8391` |

## Content entry results

Ran the real command once for each archive above:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/scan_public_zip.ps1 -Archive dist/sunday/tekken4-sunday-test-20261031-042256-264836.zip
powershell -NoProfile -ExecutionPolicy Bypass -File tools/scan_public_zip.ps1 -Archive dist/sunday/tekken4-sunday-test-20261031-205433-879960.zip
powershell -NoProfile -ExecutionPolicy Bypass -File tools/scan_public_zip.ps1 -Archive dist/sunday/tekken4-sunday-test-20261031-205628-895451.zip
```

All three exited **1 / REFUSED** after reading every member. Actual scanned
entry, file and byte counts matched the metadata table. SHA-256 was unchanged
before and after every command; the scanner's reported identity matched too.

Each archive had the same three categories across 46 members:

| Category | Findings per archive |
|---|---:|
| Email address; manual review required | 46 |
| Patch coauthor mail trailer | 46 |
| Patch author mailbox | 46 |

These are 138 category records per archive, not 138 separate files. Output
identifies numeric member positions and categories, without echoing member
names or matched values. No other finding category was reported by these
runs. This is a result of the limited scanner, not proof that all private or
restricted material is absent.

The redacted command output is retained under
`logs/public-zip-audit-2414422e63944bd79dfa72928b727c1e/`, one text log per archive.
The archives were left unchanged. Prepare a fresh reviewed source output with
[publish_public_tree.ps1](../tools/publish_public_tree.ps1), then scan the exact
output again after packaging. Do not sanitize these retained inputs in place
or treat a successful limited source scan as player-package acceptance.

## CRC validation follow-up

Reran the same three archives through the real command after the reader added
CRC-32 checks against the uncompressed bytes. The command also ran against
the existing portable sanitized subset below. No archive was rewritten or
extracted. Every reported SHA-256 matched the before/after file hashes and
the identities recorded on this page.

| Input | Exit | Entries / files / bytes read | Elapsed seconds |
|---|---:|---:|---:|
| Sunday `042256-264836` | 1 | 123 / 123 / 4,187,421 | 4.247 |
| Sunday `205433-879960` | 1 | 124 / 124 / 4,207,076 | 4.294 |
| Sunday `205628-895451` | 1 | 124 / 124 / 4,207,280 | 4.217 |
| Portable sanitized subset | 0 | 80 / 80 / 2,025,621 | 2.569 |

These are single observed wall times, including PowerShell startup, not a
performance guarantee. All three Sunday archives completed CRC/content reads
and still reported only the same 138 mail-category records per archive. The
portable subset still passed the limited source scan. A matching CRC detects
accidental corruption; it does not authenticate a producer or establish rights.
It does not prove that every hidden compressed representation was inspected.

The command output and before/after hashes are retained under
`logs/public-zip-crc-audit-69c2e5ac5d3a4520979ec0544815e9a2/`.

## DEFLATE validation follow-up

Reran all four inputs through the actual command with the completed raw
DEFLATE validator. The helper SHA-256 was
`049b5972869e0d67e90aac14cc2a90c11123de58fdbbe4665d786c239a803656`
before and after every subprocess. Every archive hash stayed unchanged and
the scanner's reported identity matched the recorded input hash.

| Input | Exit | Entries / files / bytes read | Elapsed seconds |
|---|---:|---:|---:|
| Sunday `042256-264836` | 1 | 123 / 123 / 4,187,421 | 42.351 |
| Sunday `205433-879960` | 1 | 124 / 124 / 4,207,076 | 41.485 |
| Sunday `205628-895451` | 1 | 124 / 124 / 4,207,280 | 39.920 |
| Portable sanitized subset | 0 | 80 / 80 / 2,025,621 | 18.483 |

All three Sunday archives again reported only the same 46 email, 46 coauthor
mail and 46 author-mailbox categories. The portable subset passed. These are
observed wall times with other test processes running, including PowerShell
startup. They are materially slower than the earlier CRC-only checks above;
they are not an isolated benchmark or a performance guarantee.

The exact retained truncated-empty DEFLATE reproducer now exits **1 /
REFUSED** through the same command, in 0.541 seconds. Its SHA-256 stayed
`331d43c8da4a4e064ea2fec821a09c274957f3dc48352fef9ba4f478de0576ae`.
The earlier scanner accepted these same bytes; no archive was repaired to
obtain the refusal. This closes that observed false pass, not the separate
player acceptance or rights gates.

Final command output and hash/timing records are the `final-*` files under
`logs/public-zip-deflate-audit-970f5bfc8abd4293ba7d92f95eaba629/`.
Earlier files there are preliminary runs; some preceded the final helper.
No member was extracted, modified or executed.

## DEFLATE work-budget follow-up

Reran all four inputs through the actual scanner after adding one shared
archive-wide budget: 1,024 DEFLATE blocks, 2,097,152 decoded symbols and
1,048,576 Huffman lookup slots. These are work limits, not a wall-time limit.
The final helper SHA-256 was
`5f37e906109b081b622938c25f58f0908c56cfbd642b4c539563a7974eb508df`
before and after every subprocess. The reader helper hash also stayed
unchanged. Every input hash matched the identities already recorded above,
and every scanner-reported identity matched its input hash.

| Input | Exit | Entries / files / bytes read | Elapsed seconds |
|---|---:|---:|---:|
| Sunday `042256-264836` | 1 | 123 / 123 / 4,187,421 | 41.919 |
| Sunday `205433-879960` | 1 | 124 / 124 / 4,207,076 | 40.759 |
| Sunday `205628-895451` | 1 | 124 / 124 / 4,207,280 | 40.959 |
| Portable sanitized subset | 0 | 80 / 80 / 2,025,621 | 19.112 |

All Sunday scans completed and reported only the same 138 mail-category
records each; the portable subset passed. These observed wall times include
PowerShell startup and concurrent symbol-budget tests. They are not an
isolated benchmark, a speed improvement claim or a time guarantee.

The first proposed symbol allowance was 1,048,576. Two real retained-input
scans stopped with generic refusals before reporting content counts. A
separate raw-helper diagnosis identified symbol exhaustion in the first
archive; that diagnosis was not scanner-entry proof. The allowance was
raised before the four final runs above. Preliminary evidence remains under
`logs/public-zip-budget-audit-245a1378e4784827b4386f22916a652d/`;
the completed frozen runs, hashes and output are under
`logs/public-zip-budget-audit-final-f1c16c2c43594ad3a59b03c1c5469469/`.
No retained archive was changed to obtain these results. The sanitized
subset is still not complete corresponding source or a player candidate.

## Text-work follow-up

Reran the two original timeout fixtures and all four retained inputs through
the actual scanner after the text-check changes. The frozen text helper
SHA-256 was
`5e279f9372d63bc0cc97e0c1a2f20aa4a3bdde7fd4e44ee70dde60291cb83f7c`.
All five scanner entry/helper hashes and all six archive hashes stayed
unchanged before, between and after subprocesses. Every reported archive
identity matched the recorded input hash.

| Input | Exit | Entries / files / bytes read | Elapsed seconds |
|---|---:|---:|---:|
| Original giant-word fixture | 0 | 1 / 1 / 1,048,575 | 2.517 |
| Original pure-newline fixture | 0 | 1 / 1 / 2,097,151 | 2.950 |
| Sunday `042256-264836` | 1 | 123 / 123 / 4,187,421 | 41.410 |
| Sunday `205433-879960` | 1 | 124 / 124 / 4,207,076 | 41.226 |
| Sunday `205628-895451` | 1 | 124 / 124 / 4,207,280 | 41.485 |
| Portable sanitized subset | 0 | 80 / 80 / 2,025,621 | 18.984 |

Both original timeout fixtures now completed with `SCANNED` counts and
`PASS`, using their unchanged bytes. Their SHA-256 values remain
`9adcb8e2df7445658ad78a7c4c766ab098b43e720c89ae83e773c6bd8d297bf1`
and `6b19a98f6ac0d7fb98442a7d7398988697dd5151cb47aedfdacc8bc3976feaae`,
respectively. Their earlier 180-second timeouts remain failed tests, not
scanner refusals or passes.

All three Sunday scans completed content reads and reported only the same
46 email, 46 coauthor-mail and 46 author-mailbox categories. The subset
passed. No subprocess timed out or wrote standard error. These observed
wall times include PowerShell startup and concurrent tests; they are not
an isolated benchmark or a whole-scan time guarantee. The two-second regex
matching limits do not impose a hard process deadline.

Final command output, six result records and before/after hashes are under
`logs/public-text-audit-final-cfe1442fcf614b41a485116a3c3f4355/`.
The earlier attempt under
`logs/public-text-audit-f39b0291f6114362973013f31f4f0f97/` detected a helper
change and failed; it is preliminary evidence only. No retained archive was
changed, repaired or extracted. This closes the two observed timeout cases,
not complete source/player acceptance or the owner-only runtime gates.

## Sanitized source subset experiment

The real `publish_public_tree.ps1` entry also staged `LICENSE` and all
79 patches into fresh `logs/public-zip-sanitized-source-review/` output.
It cleaned the mail preambles and proved every diff byte unchanged. Its
postwrite source scan passed. Source patches were not edited.

Packaging that selection with Windows `ZipFile.CreateFromDirectory` produced
backslash member paths: the real ZIP scan refused 79 unsafe paths, exit 1.
That retained test archive was not rewritten. A separate ZIP written with
explicit `/` member paths then passed the real scan, exit 0: 80 files,
2,025,621 uncompressed bytes, SHA-256
`fb80808520f464250cd13a548413f2d04771461251e8bdb03993599aae3d1f7d`.
It is retained as `logs/public-zip-sanitized-source-portable.zip`.

This proves the selected sanitized source bytes can pass the ZIP entry. It
is a limited subset, not complete corresponding source or a player package.
The CRC follow-up above checks the read bytes; producer authenticity and every
possible hidden compressed representation remain unproved. No publication is
authorized.

## Worker lifecycle follow-up

The [worker lifecycle test](../tools/test_public_zip_process_lifecycle.ps1)
passed 77 assertions through four actual scanner entries. The same unchanged
1,000-member text ZIP completed before and after two genuine one-second
deadline refusals. All four workers were observed independently through the
Windows `Process` performance counters, linked by parent PID and guarded by
UTC process creation time. Three checks after each entry returned found its
observed worker identity absent; the supervisor had also exited.

The test requires usable `ID Process` and `Creating Process ID` counters.
Unavailable counters or an unobserved worker fail the test; neither is a skip
or a pass. Seven source hashes, archive bytes and fixture inventory stayed
unchanged, stderr was empty, and nothing was extracted. Evidence is under
`logs/zip-process-lifecycle-8c27a8cac0c84716bd12f5d23454a022/`.

No production scanner changed. This covers the observed direct workers in
these four runs; it does not prove absence of every possible descendant or
force termination-error and test-watchdog failure branches. The launcher,
Python release tools, build, game and two-PC gates remain unrun here.

## Still open

No archive was extracted, modified or run. Python packagers and their payload
checks, the launcher GUI, build, game, two-PC play, complete corresponding
source and owner licence/publication review remain unrun or unresolved here.
A real build and game run in the owner's authorized checkout must prove the
exact candidate's startup, gameplay and network behavior.

See [PUBLIC_ZIP_SCAN.md](PUBLIC_ZIP_SCAN.md) for scope and commands, and
[CODEX_PROGRESS.md](../CODEX_PROGRESS.md) for current release gates.
