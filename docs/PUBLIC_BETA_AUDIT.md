# Public beta source audit, 2026-10-31

This is the historical 2026-10-31 review. For the 2026-11-02 entry-point
attempts, current open findings and owner-only gates, read
[CODEX_PROGRESS.md](../CODEX_PROGRESS.md). Python checks remained blocked;
the real `Tekken4.cmd` starter refused missing private Python before GUI
startup. The beta is still NO-GO; the earlier source fixes below have not
become launcher/build/game acceptance evidence.

Static review of this clean working copy. No Git command, build, project script,
test suite, package creation, download, network probe or game was run. The five
reviewed PowerShell entry points passed syntax parsing only. Python was not
available on PATH, so Python syntax and the new regression cases were reviewed
without execution. Historical results in the docs were not reproduced.

## Findings, ranked

| Priority | Finding | Result / owner action |
|---|---|---|
| High | VU1 generator permission remains unresolved. Other imported material has incomplete source/notice evidence. | [THIRD_PARTY.md](THIRD_PARTY.md) inventories the local evidence, separates the GoW runtime from its main-branch generator, and names whom to ask. Owner must resolve exact grants/notices; this review supplies no legal conclusion. |
| High | The exact beta candidate has no supplied clean-PC portable-build, shared-launcher or sound-on two-physical-PC acceptance evidence. Historical same-PC online runs include severe one-sided stalls. | Remains pending. Follow [BETA_GO_NO_GO.md](BETA_GO_NO_GO.md) on the actual candidate; sampled hash agreement cannot establish usable play. |
| High, fixed in source | A nonexistent package scan directory could pass as an empty scan. A missing directory could also match an empty-tree input digest. | Both paths now refuse missing directories; the PowerShell wrapper also checks its scan target, input-lock file and Python helper. Synthetic regression cases were added but not run. |
| High, fixed in source | Portable builds could fail on an empty VU1 file list and omit the online build-ID sidecar. Portable staging could miss header-only changes. | Corrected tooling and stage fingerprints, matching the existing checkout route. Both build scripts now prevent a failed native launch from inheriting an earlier successful exit code. Real clean-PC builds must verify these changes. |
| Medium | Path B copies all of `docs/`, including historical maintainer paths/internal notes. Its artifact scanner does not detect personal paths, credentials or server addresses. The separate source-export scanner rejects such content. | Historical evidence was retained. Owner must review the player/source documentation sets and prepare a publication revision that passes the appropriate scans. A Path-B asset scan is not a privacy review. |
| Medium, fixed in source | Some docs promoted grouped build steps, a seven-minute run, sampled hashes or a suspected bottleneck into broader claims. Some instructions assumed a private remote or contradicted this clean-copy boundary. | Qualified those claims, corrected the recorded remote-visibility assumption, and added current clean-copy boundaries. No old measurement validates the edited source. |
| Medium, fixed in source | A report-write failure could hide a preflight network failure; compiler labels overstated identity coverage. | Preflight preserves the primary failure. Messages identify the C++ compiler and disclose that SDK/MSVC headers/library versions are not recorded. UDP probe success still cannot prove the game's firewall rule or gameplay. |
| Low, fixed in source | Launch commands, stale patch links, helper names and dry-run wording could mislead players. | Corrected quoting/shell syntax, names and log-write disclosures. Identity-repair advice now shows the cause and says to rebuild before regenerating the stamp. |

## Packaging and provenance limits

Future Sunday source-test archives include `docs/THIRD_PARTY.md`. Portable
packaging requires that file before staging, in addition to its existing
reviewed licence-input requirements. A notice file's presence does not verify
the rights or completeness of its contents.

The existing archive under `dist/sunday/` was left unchanged. Only its entry
names and sizes were inspected, without extraction: they describe an older
source-test payload. It does not contain the new inventory or these fixes.
That listing is not a content scan or release approval.

No runtime source, numbered patch, gameplay/network setting or default was
changed. There were no deletions. The existing MIT-marked T5DR network
adaptation was documented; no T5DR code was added.

## What the owner must prove or decide

1. Resolve the provenance questions in [THIRD_PARTY.md](THIRD_PARTY.md), starting
   with Waffle565/the VU1 generator's rights holders. Confirm exact imported
   runtime/shader/table notices, maps and the maintainer pricing-table scope.
2. Choose reviewed public/player docs and verify destination visibility. The
   internal machine paths are historical evidence, not clean-PC prerequisites.
   Keep provenance and author notices when preparing publication content.
3. In an authorized validation checkout, run the release/catalog, source-export
   and launcher checks; inspect the real staged folder and archive. The new
   missing-directory regression cases remain unexecuted here.
4. Build from a supported own ISO on clean Windows with the exact portable
   inputs: verify Microsoft terms reject/accept, sysroot fetch, ISO-only native
   VU1 generation, stage updates and matching executable/build-ID sidecars.
5. Test the intended launcher, offline controls/settings/sound, then direct-IP
   and advertised VPN routes on two physical PCs. Retain both logs, cold role
   swaps, disconnect recovery and pacing observations. Rebuild changed source;
   do not release the older archive as though it contained this work.

## Review team

`licence_catalog`, `vu1_provenance`, `build_scripts`, `player_zip`,
`net_play_audit`, `net_preflight_audit`, `public_docs`, `tests_catalogs`,
`personal_paths`, and the separate read-only `final_diff_review` agent.
Each followed `AGENTS.md`; edit ownership was split by file.
