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

## Still open

No archive was extracted, modified or run. Python packagers and their payload
checks, the launcher GUI, build, game, two-PC play, complete corresponding
source and owner licence/publication review remain unrun or unresolved here.
A real build and game run in the owner's authorized checkout must prove the
exact candidate's startup, gameplay and network behavior.

See [PUBLIC_ZIP_SCAN.md](PUBLIC_ZIP_SCAN.md) for scope and commands, and
[CODEX_PROGRESS.md](../CODEX_PROGRESS.md) for current release gates.
