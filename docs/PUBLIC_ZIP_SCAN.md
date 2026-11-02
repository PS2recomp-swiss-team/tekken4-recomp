# Read-only public ZIP content scan

Use [scan_public_zip.ps1](../tools/scan_public_zip.ps1) for a conservative
source/privacy check of a ZIP already inside this working copy. It reads
members in memory without extracting or running them. It does not write or
repair the archive, start the launcher, build, start a game or publish.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/scan_public_zip.ps1 -Archive dist/sunday/tekken4-sunday-test-20261031-205628-895451.zip
```

Exit 0 means only that this limited scan passed. Exit 1 means findings, an
invalid input or an incomplete scan. Findings use numeric member indices and
categories, without printing member names or matched content. Keep the reported archive SHA-256
with the result so it identifies the bytes checked. See
[PUBLIC_ZIP_AUDIT.md](PUBLIC_ZIP_AUDIT.md) for actual retained-archive results.

The command supervises a separate scanner process. Its default deadline is
120 seconds; `-TimeoutSeconds` accepts integers from 1 through 600. The clock
starts immediately before starting that process and covers its startup,
scan work and output collection. When the deadline expires, the command
terminates the child, discards its buffered output and exits 1 with
`REFUSED: ZIP scan exceeded its process deadline.` It reports neither an
archive hash nor a completed `SCANNED` or `PASS` result for that attempt.
If termination cannot be confirmed, it reports that uncertainty and still
refuses. Wrapper preflight and operating-system process termination are
outside that worker deadline; this is not a hard real-time guarantee for the
entire command.
The [worker](../tools/public_zip_scan_worker.ps1) is an internal implementation,
not a supported direct scan entry. Use the supervised command above.

The entry refuses paths outside this tree and reparse points. Archive members
must have safe, unique paths, including consistent directory spelling and no
file/directory conflicts. Symlinks and other nonregular entries are refused.
Known limitation: a retained audit accepted COM/LPT names containing superscript
digits. That path-check gap remains open; a passing scan is not Windows
extraction validation. Nothing was extracted in that audit.
The fixed limits are 10,000 entries, 32 MiB per file, 128 MiB total uncompressed
content and a 128 MiB archive. Reported ZIP read errors and mismatched
uncompressed lengths cause refusal. Nothing is extracted, including when
a member path is unsafe.

Only ordinary single-disk ZIPs are supported. ZIP64, comments, extra fields
and data descriptors are refused. Local headers must match the central
directory, and member regions must cover the bytes before that directory
without gaps or overlaps. Stored members must declare equal compressed and
uncompressed lengths. The scanner recomputes CRC-32 from the uncompressed
bytes it reads and compares it with the matching header CRCs, including empty
files and directories. A mismatch causes refusal. CRC detects corruption; it
does not authenticate a producer. SHA-256 identifies the archive bytes read.

Deflated members also pass a bounded
[raw DEFLATE check](../tools/public_zip_deflate.ps1) before the .NET reader
returns their content. It checks stored, fixed-Huffman and dynamic-Huffman
blocks, including code tables, length/distance history, the declared output
length and completion of the final block. The compressed extent must end in
that block's last byte; unused bits in that byte are allowed. Truncated
streams, trailing bytes and concatenated streams are refused. This check
does not extract content or replace the later .NET read and CRC comparison.
It is not proof that every possible hidden byte has been found.

The raw DEFLATE check has one fixed work budget shared by all compressed
members in an archive: 1,024 blocks, 2,097,152 decoded Huffman symbols and
1,048,576 allocated Huffman lookup slots. Symbols include literals,
length/distance codes, code-length codes and end-of-block codes. Empty
lookup tables consume one slot. A reused fixed table is charged when it is
first allocated in that member. Stored DEFLATE blocks consume the block
budget; their bytes remain subject to the existing size limits.

Exceeding any counter causes refusal, including for a structurally valid
archive. Counters do not reset between members, and the command has no option
to raise them. These are parser work limits, not a wall-time guarantee or a
speed improvement. The PowerShell check can still be slow. See the measured
retained-input timings in [PUBLIC_ZIP_AUDIT.md](PUBLIC_ZIP_AUDIT.md). A slow
scan is not evidence of a completed scan or a pass.

The shared [text scanner](../tools/public_tree_scan.ps1) gives each of its
full-content regex operations a two-second .NET regex timeout. Match
collections are evaluated inside the guard, but their total enumeration time
is not bounded by one timeout. A timeout or regex failure
refuses the scan without printing the exception or input text; it does not
produce a completed `SCANNED` result or a pass. Difficult but otherwise valid
text can therefore be refused for manual review.

The long-word fix skips the dense-symbol regex only when neither of its
required literal fragments occurs. Blank-line fixes prevent two line-start
checks from retrying across every earlier newline. These changes retain the
content categories and are covered by actual ZIP and tree entry tests below.
The supervised ZIP worker deadline also covers patch-header processing,
path checks, decompression, I/O and the sum of regex work inside that child.
The separate [public-tree export/scan entry](../tools/publish_public_tree.ps1)
also supervises its worker with a process deadline. Its wrapper preflight and
operating-system termination remain outside that deadline.

Member paths must use `/`. Some Windows ZIP convenience methods write `\`
instead; those archives are refused. Use a packager that writes portable
member paths and scan its exact output without relaxing the path check.

The existing [public source scanner](../tools/public_tree_scan.ps1) checks
member bytes for images, game data or executable/archive signatures,
credentials, private paths, network details and other reviewed categories.
This is a conservative text-source policy: even a legitimate runtime or
private Python binary is refused. It cannot approve a complete player ZIP.

Member paths also refuse `.agents`, `.codex` and `.aws` components and files
named `CODEX_PROGRESS.md`. The same credential, private-path and
network-address rules used for text also check member names. Findings keep
numeric member indices and static categories; private names and matched text
are not printed. These limited checks do not guarantee complete privacy.

Run the real subprocess tests through their entry:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_public_zip.ps1
```

Tests retain harmless text ZIP fixtures under unique `logs/` directories.
They exercise the actual scan command; syntax parsing is reported separately.
The [CRC vectors](../tools/test_public_zip_crc.ps1) check clean stored and
deflated text, empty members and known CRC values. The
[integrity cases](../tools/test_public_zip_integrity.ps1) check corrupt
content and matching but incorrect header CRCs after a clean control passes.
The [valid DEFLATE cases](../tools/test_public_zip_deflate_valid.ps1) and
[invalid DEFLATE cases](../tools/test_public_zip_deflate_invalid.ps1) exercise
compressed-format checks through the same actual scanner entry.
The [block budget](../tools/test_public_zip_budget_blocks.ps1),
[symbol budget](../tools/test_public_zip_budget_symbols.ps1) and
[table budget](../tools/test_public_zip_budget_tables.ps1) suites exercise the
fixed work counters through that entry, including cumulative member work.
The shared text regressions cover [long words](../tools/test_public_text_words.ps1),
[blank lines](../tools/test_public_text_lines.ps1) and
[content categories and timeout refusal](../tools/test_public_text_categories.ps1)
through both actual scanner entries, with clean controls and bounded test
processes. The [deadline cases](../tools/test_public_zip_deadline.ps1) exercise
the actual supervised command's timeout refusal and cleanup. The
[compatibility cases](../tools/test_public_zip_deadline_compat.ps1) exercise
completed scans and refusals through that command, including unusual paths.
An outer test deadline expiring is a failed test, not a scanner refusal.
No game data, keys, screenshots or real credentials are needed for them.
The shared [path privacy tests](../tools/test_public_path_privacy.ps1) exercise
private working paths and private-looking names through both actual tree
and ZIP scan entries, including clean controls and sanitized refusals.
Read [CODEX_PROGRESS.md](../CODEX_PROGRESS.md) for what actually ran and what
remains open.

The Python packager's payload manifest, pinned inputs, dependency locks and
hash rules remain separate checks. This command does not run that packager,
prove complete corresponding source, establish licence permission or test the
actual launcher. The owner still needs the reviewed final source/player
outputs, Python suites and payload checks, then a real launcher, build, game
and two-PC run in the authorized checkout. A passing source ZIP scan does not
close [BETA_GO_NO_GO.md](BETA_GO_NO_GO.md) or the rights questions in
[THIRD_PARTY.md](THIRD_PARTY.md).
