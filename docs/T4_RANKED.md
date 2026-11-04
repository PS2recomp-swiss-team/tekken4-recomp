# Tekken 4 ranked: game-rendered player names

2026-11-04, SLUS-20328 v1.00, branch `t4-ranked`. Supersedes the Plates v2 covering panel.
Local build, loopback pair and screenshot validation is recorded below. Initial captures exposed three bugs:
the active VS select used another draw path, queued fight names had the wrong depth, and badges intermittently
disappeared because of the presenter frame-age check. Those bugs and badge fade opacity are corrected in source.
The local subset passes; the full account-based coordinator acceptance list is not yet passed.

## Visible behavior

The game draws the launcher-provided P1/P2 names using its proportional font 6. The former covering panel and
raylib player-name text are removed. The host overlay draws only the rank badge, four game pixels left of the
queued name. Active VS select positioning follows the name widget's transform on the verified identity-oriented
UI plane; the retained older select path follows its projected name quad. Fight positioning follows the original
HUD draw's centre. A guest (`tier=-1`) has a name and no badge. Ranked and casual use the same path.

Printable ASCII `0x20..0x7e` is retained, including lowercase, spaces, digits and punctuation. Unsupported Unicode
scalars become `?`. Names are capped at 16 ASCII characters, then shortened at draw time to 104 font pixels using
the game's own signed advance metrics. This width leaves room for a 28x16 badge beside the P1 HUD name at x=86.
The game has no native 16-character limit on these former name textures: **16/104 are our layout policy**.
Font 6 has separate upper/lowercase metrics and glyph indices; uppercase conversion is unnecessary.
Windows names are read from the wide environment, avoiding machine-dependent ANSI codepages. UTF-8 helper input
uses one `?` per valid non-ASCII scalar; malformed bytes become `?`. `%` is a literal because no printf parser
receives the name. Empty/malformed side payloads retain the appropriate fighter name.

`TEKKEN4_HUD_PLATES=0` retains the original fighter textures and hides badges. It is a process-start setting.
**Both peers must now use the same effective name/off settings.** A peer on/off difference is refused at HELLO;
the old Plates v2 proof of one PC on and the other off does not apply to this implementation.

## Static findings and addresses

Inspected the existing lifted US functions and ELF read-only. No lifted code, ELF bytes, metrics or textures
were copied into tracked source. The handoff's ASCII-table hypothesis does not describe the visible select/HUD
names: those use pre-rendered name textures, originally uppercase artwork, rather than an ASCII font string.

| Path | Static evidence |
|---|---|
| Short-name string lookup | `FUN_00222620` at **0x222620** reads `*(0x31a5c8 + 4*a0)`, a table of 24 ASCII string pointers. Its only direct call is **0x1e2e9c**. `FUN_001e2e80(entry)` obtains the name ID from `0x30e100 + 28*entry + 4` and calls it. The input is a roster/costume entry, not a side. |
| Active VS select name | Local captures and bounded diagnostics identify `FUN_0027e900` as the observed VS UI path. It obtains separate portrait/name widget IDs from **0x32dac8 + 8*nameID** (`0x27dfd0` / `0x27dfe8`), copies name graphics into side widgets **0x104/0x105**, then calls **0x236eb8** at **0x27ef70**, return **0x27ef78**. `$s3` remains the side index (0/1) until the instruction after this call. The override also checks the widget ID, VS scene/type and pointer bounds, independently of fighter and local role. |
| Active select geometry | Widget **+0x52** is visibility, **+0x54** identifies the widget, **+0x5c** is opacity, and **+0x10..0x4f** is its transform matrix. Captured name widgets have identity rotation/scale and translations **(-216,5,-297)/(216,5,-297)**. On this verified UI plane, centres are **(320+translationX,224-translationY)**: **(104,219)/(536,219)**. The helper requires finite values, identity orientation/scale, depth **-297**, homogeneous W=1 and viewport bounds; unsupported geometry falls back to the game draw. |
| Retained older select name | `FUN_001f5228` loops P1/P2, obtains a name ID with `FUN_001e2ff8` (same roster +4 field), remaps it with **0x24f0d8** (`0x329f30 + 16*nameID + 4`) and calls **0x1f4da8**. That routine calls **0x1f2e70** at **0x1f5074**, return **0x1f507c**. It queues name texture resource **0x7f**, selected by `a0`, via `FUN_00205ce8`; `a2` is four projected GS vertices, `f12/f13=183/22` texture extents, `f14` opacity. This hook remains guarded and installed, but was not the active path in the observed VS select captures. |
| Older select side | At that entry, caller `$s1` is **0x399ab0 + side*0x190**, the per-side name object. It is independent of texture ID/fighter, including mirrors. `FUN_001d5d90` projects the quad to GS 12.4 integers; subtract origins **1728,1824** after dividing by 16. Replacement text is centred on this quad. |
| Fight HUD name | `FUN_001f1628` looks up each player object's signed roster entry at **+0x48**, calls `0x1e2ff8`, then **0x24f0c0** (`0x329f30 + 16*nameID`). It calls **0x1f0a80** at **0x1f1b8c** (P1) and **0x1f1bd0** (P2). Return addresses **0x1f1b94 / 0x1f1bd8** unambiguously identify sides. `a2/a3` give centres **(86,57)/(557,57)** in 12.4 units. The original queues a texture index in resource **0x4a**, not a string. |
| Game font | Font **6**, descriptor **0x31f208** (`0x31f1d8 + 6*8`), advance/bearing metrics pointer **0x2cebe8**. `0x22c228` reads signed advances; `0x22c280` reads bearings at metrics+0x100. Descriptor gives 18-pixel line spacing and 20x20 glyph quads. `0x22c670` consumes literal text, `0x22c4b0` dispatches glyphs to **0x1ec8e0**, and **0x1ec750** selects font object **0x2bd100**. ASCII indices include separate lowercase; the decoder also has two-byte support, deliberately outside our ASCII policy. Palette **7** at **0x30fa50** is white, full alpha **128**. |
| Font queue | **0x1cd07a0**, size **0x4000**, initialized by `0x22b678 -> 0x22c7f0`. Queue +0 is the next record pointer, records start at +8. `0x22c3d0` is the normal game's string enqueue API; this override writes the same bounded record format directly. Header: halfword next distance, x, y, flags; bytes font, palette, alpha; NUL-terminated literal at +11, next record aligned to 2. Formatter scratch cursor **0x357a54** is updated too. `0x196bd8 -> 0x22b6a0 -> 0x22c7b8` flushes it in the game loop (also flushed by printf). |
| Font depth | Queue **+6** is consumed as a signed halfword and multiplied by 16 by `0x1ec788`. Writing **0xffff** produces **0xfffffff0**, whose GS Z24 low bits **0xfffff0** match the original HUD name depth **0x0ffffff0**. The previous **0xfff0** produced low bits **0xffff00**; with Z GEQUAL, the HUD occluded most glyph rows. |

The five handoff candidates were checked:

- **0x1bb840**: result/message construction; uses `0x1e2e80`, then sprintf into **0x361000**. It is not the life-bar name draw.
- **0x1e2e60**: contrary to the initial handoff description, this function does **not** call `0x1e2e80`. It reads
  roster **+0x10** using player **+0x48**; `0x23f530` uses the returned graphic index to select a 64-byte descriptor.
- **0x1e2ee0**: roster lookup via `0x2ba620 + 12*i + 8`, then `0x1e2e80`; used in records/list construction.
- **0x1fbbc0**: fighter-to-default-costume/availability mapping (including fighter 15 special case), then
  `0x1e2e80`; callers copy three characters for initials. This is not a three-character HUD limit.
- **0x260a20**: uses player **+0x48**, `0x1e2e80`, and `0x261d60/0x261250` for floating in-world labels
  (font 6), not the two life-bar names.

## Implementation and determinism

`runtime/tekken4_hud_overrides.cpp` installs three guarded draw-entry hooks: active VS select widget **0x236eb8**,
older select **0x1f2e70**, and fight **0x1f0a80**. It checks the exact caller and VS
scene/game type; all other callers and interior scheduler resume addresses remain original. On missing name,
invalid geometry/metrics or unavailable queue space it calls the original. It never patches the shared fighter
pointer table, so mirror matches keep different player names. There is no unreserved guest buffer/allocation.

At each original guest name draw, including rollback resimulation, `tekken4_native_names.h` selects immutable
launcher-order `P1|P2`, reads guest font advances/geometry, and writes the literal record and cursor. No local role,
rank, wall clock, presenter frame or host pointer decides those bytes. Both PCs execute that draw at the same
logical guest frame for the same simulated state. Guest snapshots restore queue/cursor/metrics/geometry; there
is no host "already applied" flag that could skip a write during replay.

The net configuration mixes the sanitized names **in side order**, including effective disabled/empty state, into
the existing boot HELLO fingerprint, **even with AUTO_VS=0**. HELLO mismatch rejects before inputs are primed.
This is a guard on the launcher's existing shared-side contract; no launcher/server change is required. Rank
values stay host-only and can differ without changing simulated RAM. The `auto_vs_mismatch` reason code is kept
for compatibility; its text now names boot/native-name settings. Use a new build ID for the candidate.

Changed guest RAM includes the text queue, its head/formatter cursor and downstream font rendering output.
`netHashOf` hashes the entire snapshot RDRAM (`hashBytes(snap.rdram.data(), snap.rdram.size(), 11)`), so
**these bytes are hash-covered**. Accepted peers have the same effective names and execute the same writes at
identical guest calls, so these bytes are identical by construction. No new hash mask or exclusion was added.
This reasoning is not a replacement for zero-mismatch rollback/lockstep acceptance runs.

The badge presenter reads a mutex-protected host copy of the actual queued text position and checks scene and
visibility/opacity. It never feeds simulation state. The former frame-age comparison against live guest RAM was
removed: RAM can advance or roll back while an older framebuffer is presented, causing valid badges to disappear
intermittently. Hidden active-select widgets and fallback draws invalidate their badge anchor. Badge shapes,
outline, text and highlight now receive the name's alpha (128 means opaque; the highlight keeps its 0.22 factor).
Badge text alone still uses the existing host font; the player's name uses the game font. Final screenshot and
pair evidence must establish the completed candidate's visual and netplay acceptance.

## Environment and staging

| Variable | Meaning |
|---|---|
| `TEKKEN4_HUD_NAMES` | `P1 name|P2 name`, identical order on host and joiner |
| `TEKKEN4_HUD_RANKS` | `P1 tier,P2 tier`, 0..46, -1 for guest/no badge |
| `TEKKEN4_HUD_PLATES` | `0` restores fighter names; effective setting must match on both peers |
| `TEKKEN4_HUD_SHOTS` | `s,s,...` -> window screenshots `hud_<s>s.png` |
| `TEKKEN4_HUD_WINDOW` | `WxH` for screenshot window size |

`tools/stage_generated.cmd` stages the new header along with existing overrides/badges. The production tree
is built by the coordinator; do not edit the game/generated junctions. Patch 88 still provides the badge overlay.

## Local verification

- `python -I tools/test_native_names.py`: MSVC C++17 `/W4 /WX`, synthetic RAM: sanitizer (ASCII, Unicode,
  controls, malformed UTF-8, truncation, Windows wide input), side mapping (both peers, mirrors, wrong callers),
  normalized fingerprint, font-width cap, literal `%`, queue bounds/record layout/padding and restore/replay writes.
- MSVC `/Zs` parsed the three changed `.cpp` files against this worktree's runtime headers and existing target flags.
  No game executable was linked or launched. `git diff --check` passed.
- The optional read-only US ELF test passed: CRC32, actual JAL sites and printable-ASCII font advances/case.
- Test-only outputs are ignored under `logs/native-name-tests`. No game data or generated code was changed.

## Local v3 loopback evidence (2026-11-04)

Final candidate `9bb76e274205ca6e`, base `c0db855`, built/staged from this worktree's private dependency tree.
The executable SHA-256 is `656904a9418283b7a5419d3b8617bbd55ed1f5ee384ebba6af0f654014fc682c`.
`python -I tools/test_native_names.py` passed both tests, including MSVC `/W4 /WX` helper checks and independent
US ELF call/depth assertions. No game data or lifted/generated source was edited; no commit or push was made.

All positive rows use host/join processes on one PC, bind/join `127.0.0.1`, simulator **each way**
`lat=75,jitter=5,loss=3`, fresh per-side run directories, muted audio, background windows and BelowNormal priority.
Names are launcher-order `Wishin|JinFury`, ranks `21,14`, except the guest row (`Wishin|Guest_4711`, `21,-1`).
The directory column is relative to `logs/net/`; each contains `host/` and `join/` with `params.txt`, full
`rb_frames.log` NETSUMMARY/NETHASH evidence, transport log and captures. Counts are host/join at NETSUMMARY final.

| Directory | Compared hashes | Mismatches | Rollbacks | Result |
|---|---|---|---|---|
| `v3_ranked_final` | 119/119 | 0/0 | 341/326 | Local ranked-style rollback; select and active fight visually pass |
| `v3_guest` | 119/119 | 0/0 | 309/286 | Guest P2 has no badge; same displayed name on both peers |
| `v3_hud1_final` | 119/119 | 0/0 | 116/361 | Native internal resolution, 1920x1080 window |
| `v3_hudhi` | 119/119 | 0/0 | 72/197 | Maximum raw 8x resolution, same window/filter/AA |
| `v3_lockstep` | 119/119 | 0/0 | 0/0 | RBSTART=1000000; no predicted-input frames |

The plates-OFF pair could not acquire a heavy slot during its ten-minute wait (16:46:46 to 16:56:46 local).
No OFF game launched and no run directory was created. The two negative handshake pairs were not started after
that wait limit. These three optional checks remain **unrun**, not passed.

The ranked/1x/8x/lockstep final shared hash at frame 3600 is `f343e567eebae718` on both peers; guest is
`606c1f549e556402`. Offline comparison also found zero differences in all 120 shared hash frames through 3600.
Initial and diagnostic runs remain under `v3_ranked`, `v3_diag` through `v3_diag4`, and `v3_hud1`; their
network comparisons were equal, but early visual failures are **not** acceptance passes.

Window PNGs show names in the game font, no fighter-name artwork beneath, badges directly left on both sides,
and original life bars/round markers. Framebuffer PNGs contain the names and exclude badges. Captures and the
complete per-run report are local build artifacts under `C:\T5DROnline\build\t4ranked\shots\v3_*`.
The guest input `Guest_4711` measures 114 font pixels: the existing 104-pixel policy displays `Guest_471`
(102 pixels). This is documented truncation, not a claimed full-string capture.

The 1x and 8x framebuffer shots verify 640x448 versus 5120x3584. At the same 1920x1080 client size, soft HUD,
FXAA and area window filtering, 8x has visibly crisper bar/name edges. The original PS2 texture detail is unchanged:
the GL renderer scales GS sprite geometry into larger targets and applies sampling/AA/resolve there. It does not
keep the complete HUD in a fixed native-resolution layer. The paired crops use the same window box and 3x nearest
enlargement; they show different live fight frames. See `docs/GRAPHICS.md` for the separate `HUD=sharp` option.

This does not establish the unrun OFF/negative pairs, real ranked accounts, confirmed best-of-three/rating/character-lock flow, reversed guest
roles, all mirror/cancel/rematch/Unicode/wide-name combinations or two physical PCs. Standalone replay playback is
still listed as missing in `docs/ROLLBACK_NEXT.md`; helper restore/replay writes and real online rollback were tested.

## Coordinator acceptance: required pair runs and screenshots

Local validation is in progress; final evidence and coverage belong in the final results section. Use the coordinator's `D:\t4ranked\tools\pair.ps1` / launcher lobby workflow and
fresh run directories with the new staged/built candidate. Record build ID, effective env, names/side order,
result files, rollbacks, compared hashes and NETSUMMARY from **both PCs**. Keep artifacts outside tracked source.

Run each row **twice**, with a process restart: first names ON on both PCs, then `TEKKEN4_HUD_PLATES=0` on both.
That is **eight positive pairs**:

| Pair | Queue / participants | Net mode |
|---|---|---|
| `native_ranked_rb_on/off` | Real ranked account vs account, complete best-of-three set | Rollback; NET_SIM each side `lat=75,jitter=5,loss=3`; require actual rollbacks >0 and zero mismatches |
| `native_ranked_ls_on/off` | Same ranked workflow, complete set | Whole-session lockstep (`TEKKEN4_NET_RBSTART=1000000`); zero mismatches |
| `native_guest_rb_on/off` | Casual account vs guest, then reverse host/join assignment in game 2 so guest occupies the other side | Same rollback simulator; actual rollbacks >0, zero mismatches, no ranked rating change |
| `native_guest_ls_on/off` | Same casual account/guest side reversal | Whole-session lockstep; zero mismatches |

For every ON pair, capture select and active-fight **host and joiner window screenshots** at 1280x896, e.g.
`<pair>_select_host/join.png`, `<pair>_fight_host/join.png`. Also capture a game framebuffer shot of both screens:
player names must appear in the game framebuffer; rank badges appear only in window shots. Verify no fighter-name
texture remains underneath, no panel, matching P1/P2 strings on both PCs, badge left on both sides, guest no badge,
and unchanged life bars/round markers. Capture guest-on-P1 and guest-on-P2 fights.

In each net mode include mirror fighters, a cursor move/cancel/reconfirm at select, next-round reset and a rematch.
Use `Alice_rb-09.%|Guest_123456789012345` plus a Unicode case (e.g. `Zo` + U+00EB + U+1F600 + `|Bob`, rendered as `Zo??|Bob`) and a wide-letter name (`WWWWWWWWWWWWWWWW`)
across the games. Capture truncation/fallback and both badge edges; compare frames around the select/fight transition
and rollback catch-up. At 640x448 and a letterboxed window also capture one ranked select/fight pair for badge fit.
For every OFF pair capture select/fight host+joiner shots showing original fighter names and no badges; hashes and
results must still agree. Ranked results must be game+game confirmed with normal set/rating/character-lock behavior.

Finally run **two negative handshake pairs**: same names but ON vs OFF, and reversed `Alice|Bob` vs `Bob|Alice` with
`TEKKEN4_NET_AUTO_VS=0` on both. Require boot/native-name refusal before play (no hash mismatches during a match).
Do not publish as visually/netplay validated until these runs and screenshots pass.

Proposed commit: `Render T4 online player names with the game font and anchor rank badges beside them`
