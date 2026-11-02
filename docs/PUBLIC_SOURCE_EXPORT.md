# Prepare public source without changing the private tree

Use [publish_public_tree.ps1](../tools/publish_public_tree.ps1) to prepare a
fresh local source tree. It uses Windows PowerShell, not Git or Python. It
does not publish, rewrite history, change the input patches or delete files.
Keep output under this working copy's `logs/` directory. The output must be
new or empty; an earlier export is never overwritten.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/publish_public_tree.ps1 -Out logs/public-source-review
powershell -NoProfile -ExecutionPolicy Bypass -File tools/publish_public_tree.ps1 -ScanOnly logs/public-source-review
```

The entry supervises an internal worker for both export and scan-only. The
default worker deadline is 120 seconds; `-TimeoutSeconds` accepts integers from
1 through 600. Worker startup, the operation and output collection share this
budget. Wrapper preflight and operating-system termination are outside it, so
this is not a hard wall-time bound for the entire command.

On timeout the entry exits 1, reports refusal and discards worker output. On
any refusal, partly written staging remains for inspection and is not approved.
Do not publish it or reuse that output directory; choose a fresh output for
the next export. A timeout is not a completed content scan. If worker
termination cannot be confirmed, the refusal says so.

A later successful `-ScanOnly` does not prove that a failed export is complete.
It checks the files present, not whether every selected source file arrived.
Even a retained tree containing only `LICENSE` can pass that content check.

The export removes mail addresses and transport headers from patch preambles
and removes `Co-Authored-By` lines there. Every byte starting with the first
`diff --git` line stays unchanged. The tool checks that equality against the
input patches. Copyright notices and attribution inside the diff stay intact.
Original files and patch names stay untouched.

Images, including screenshots, are omitted from the output. Private working
directories and generated outputs are also omitted. Other selected files are
checked before writing. Renamed image or executable content, game data,
credentials, private paths and unreviewed network details cause refusal.
`-ScanOnly` checks every file in an existing staged tree, including files that
an export would omit. A screenshot copied into a staged tree must fail that
scan. Findings report categories, not the matched private values.

The shared [text scanner](../tools/public_tree_scan.ps1) gives each of its
full-content regex operations a two-second .NET regex timeout. Match collections
do not have one shared deadline. A timeout or regex failure stops the scan
with a sanitized error; it never becomes a pass.
Difficult but otherwise valid text can be refused for manual review. This
per-regex limit is separate from the supervised worker deadline above.
Patch-header processing, path checks, I/O and the sum of regex work share the
worker budget. The same regex guard applies to the [ZIP scan](PUBLIC_ZIP_SCAN.md).

Historical documents can cause the full-tree export to fail. Review which
documents belong in the public source. `-Include` accepts paths relative to
`-Source` and can select a reviewed set; the root `LICENSE` is required.
For example, from an interactive PowerShell prompt:

```powershell
& tools/publish_public_tree.ps1 -Out logs/public-source-selected -Include @('LICENSE', 'patches', 'runtime', 'config')
```

That example is a limited selection, not a complete corresponding-source
catalogue. The owner must retain all source, build instructions and notices
needed for the actual distributed code. Review local document links after
choosing a public documentation set. Fix a finding or revise that reviewed
selection; do not relax the scanner to obtain a pass.

Run the tool's real entry tests before using its result:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_public_publish.ps1
```

The tests retain synthetic text fixtures under `logs/`. The shared text tests
exercise [long words](../tools/test_public_text_words.ps1),
[blank lines](../tools/test_public_text_lines.ps1) and
[content categories and timeout refusal](../tools/test_public_text_categories.ps1)
through the actual tree and ZIP commands. Clean controls must pass before
refusals count. A process killed by a test deadline is a failed test.
The [tree deadline tests](../tools/test_public_tree_deadline.ps1) and
[compatibility tests](../tools/test_public_tree_deadline_compat.ps1) use the
actual export/scan entry. An entry's own deadline refusal is distinct from a
test watchdog killing an entry that failed to return.

The [write-failure tests](../tools/test_public_tree_write_failure.ps1) deny
directory creation in empty fixture outputs. The real export writes `LICENSE`,
then refuses when a nested directory cannot be created. The partial output
stays unchanged and retries refuse it; the same selected files export to fresh
outputs. This proves a write error after staging begins, not a timeout during
writing.

The [worker-load tests](../tools/test_public_tree_worker_failure.ps1) briefly
hold read locks on the actual worker and shared text helper without changing
their bytes. The real entry refuses scan and export without creating staging;
the unchanged fixture passes after the locks are released. Run the checker
and these failure suites alone: concurrent tree or ZIP scans can refuse while
the locks are held. OS process-start failure, termination-error and test-watchdog
failure branches remain unforced. These tests do not prove absence of orphan
processes.

Image and binary signature checks use memory fixtures; they do not add game
data or screenshots.
See [CODEX_PROGRESS.md](../CODEX_PROGRESS.md) for the commands actually run,
results and open work. A passing export proves the checked staging behaviour;
it does not prove a launcher, package, build or game run.

The older Python exporters and packagers are separate paths. Python was not
available in this copy, so their code and suites remained unrun. Do not treat
these PowerShell checks as evidence that those paths clean patch headers or
remove screenshots. Scan and review the exact final public trees again after
any later copying or packaging.

ZIP contents can also be checked without extraction using the separate
[PowerShell ZIP scan](PUBLIC_ZIP_SCAN.md). It applies the conservative public
source/privacy policy to member bytes, reports categories with numeric member
indices and refuses binary payloads. It does not replace the Python player's
manifest, pinned-input or dependency-lock checks. See the
[retained archive audit](PUBLIC_ZIP_AUDIT.md) for the bytes and outcomes
actually checked; a source ZIP scan cannot prove a complete player package.

Privacy cleanup does not settle rights to imported code or game material.
The open provenance and licence questions in [THIRD_PARTY.md](THIRD_PARTY.md)
remain owner gates. Retain GPL-3 and third-party notices. Only the owner may
carry reviewed output into the public repositories; this procedure grants no
publication, release or server action.
