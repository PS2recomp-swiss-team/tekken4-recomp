# Review of us-slus20328 c7f13d6..caf10f5 (Pablo + Claude, 2026-11-03)

Your 22 commits of 2026-10-29/30 (patches 57-86, launcher, perf/unlock overrides, netplay polish). Read-only review:
nothing built or run from your branch yet, nothing of yours changed. Items marked **(checked)** were confirmed in
the code by Claude; the others come from review agents and still need a look.

## Passed

- No game files, binaries, Ghidra databases or generated C++ in the range; US addresses stay in `runtime/*_overrides.cpp`.
- No delete / move / purge anywhere in the scripts or the launcher; subprocess calls are argument lists, no `shell=True`.
- Patches 57-86 apply cleanly, one by one, on `t4-us` at 56 (`H:\tekken4-fork-ps2recomp_usa`, scratch index).
- Merge with `us-iso`: one conflict, `tools/build_game.ps1:475`, the same `@()` fix on both sides (your line kept).
- Patch 74 (incremental RDRAM snapshots): the dirty-page logic looked correct, including restores and the fallbacks.

## To fix, most important first

1. **Unlock vs netplay (checked).** `runtime/tekken4_unlock_overrides.cpp:36` reads `TEKKEN4_UNLOCK_ALL` without the
   netplay pin that progressive has (`runtime/tekken4_overrides.cpp:1410-1413`), and it is not in the build id or HELLO.
   Peers with different settings connect, then the character-select RAM differs: a silent NETDESYNC after char select
   (only logged, the match goes on). Force it on under `TEKKEN4_NET`, or carry it in the HELLO flags. Also worth a test:
   a Story/Arcade win with a normally locked fighter may still save the game's own unlock bits to the card.
2. **Default PS2Recomp tree (checked).** `launcher/t4core.py:146`, `tools/build_game_portable.ps1:70`,
   `build_ps2recomp_tools_portable.cmd:17`, `build_runtime_portable.cmd:23` default to `..\tekken4-fork-ps2recomp`.
   On Pablo's PC that is the PAL tree (branch gs-gl): BUILD GAME would apply US patches and stage US code into it.
   `tools/us_tree.cmd` / `us_tree.ps1` (from `us-iso`) find the right tree and refuse a tree not on `t4-us`.
3. **`build_game_portable.ps1:522` (checked)** lacks the `@()` around `Files ...`: every fresh portable build stops at the
   runtime step under StrictMode (the fix that is already in `build_game.ps1`). `tools\fetch_msvc_sysroot.py` (named at
   :233) does not exist yet.
4. **Readback present above native (checked).** `gs_frontend.cpp:676` copies rows with the fixed 640-pixel stride and
   `UploadFrame` crops to the 640x512 texture: any frame wider than 640 is sheared on the readback path
   (`PS2X_GS_DIRECT_PRESENT=0`, `TEKKEN4_INPUT_LAG=1`, no context sharing, patch 61 hashes). PAL patch 38 fixed both.
5. **Patch 82 spin (checked).** `pacedWaitUntil` yields for the last 1.5 ms of each host wait: about 12 % of a core,
   more with alarms; on 4-core PCs it can starve the GS workers. The waitable timer from patch 60 would avoid it.
6. Unchecked, from the review:
   - Patches 72/84: the widened staging blit repaints one texel left of / above each upload from an undefined
     `stageTex` (seams next to drawn content). Patch 71: window-filter shader uses `srcSize` instead of
     `textureSize()` (wrong on readback, 640x512 vs 640x448); post programs not link-checked (black screen if FXAA fails).
   - Patch 84 movie audio: callback erases from the front and shares a mutex with a reallocating vector; the buffer
     grows without limit if no device pulls. A ring buffer would fix all three.
   - Patches 73/83: Alt+Enter also reaches the game as Enter (Start).
   - Patch 60: pad ports follow connection order and shift on hot-plug; the poll thread is never stopped.
   - Patch 80: `onSwapReturned()` now runs twice per present.
   - Netplay: the hash worker thread is detached (`tekken4_rollback_overrides.cpp:1192`) while `g_hw` / `g_np.ring` are
     statics: possible crash at exit. Patch 74 allocates RDRAM with `MEM_WRITE_WATCH` for every player: gate it to
     netplay / run-ahead. Run-ahead (off by default): the pause of patch 63 starts one window late, and the memory-card
     host files and device movie PCM are outside the snapshot.
7. Shared runtime: many `TEKKEN4_*` options, "Tekken 4 port" comments, `PS2X_GS_NATIVE_LINES=448`, global sprite snap
   and stick-to-d-pad sit in global PS2Recomp patches. For the later two-disc recompiler they want `PS2X_*` names
   and game defaults set from the overrides.

## Notes

- Your status plans to push the T5DR lobby code "into the private Swiss repo": **the organisation repo is public**.
- "0 desyncs" holds for the test as run (one PC, same settings, empty cards, 6000 frames). The 48 -> 55 fps gain
  comes mostly from not drawing the tail frame; patch 74 alone did not move fps.
- Ahead of PAL: resolution steps + seam fix, FXAA/SSAA/aniso, fullscreen, pad latency, movie audio at 44.1 kHz.
  PAL is ahead on the in-game settings window (live, saved), control rebinding and the readback fix.

## Addendum 2026-11-03: your commits after caf10f5 (up to 10edeb3)

Merged into `us-iso` (9762ca3) with three small conflicts: `build_game.ps1` takes your `Write-NetBuildId`;
`run_game.cmd` and `stage_generated.cmd` take your release-bundle tree (`deps\ps2recomp`) and the new staged headers,
and keep `tools\us_tree.cmd` for checkouts. Patch 87 builds; fight 60 fps; netplay pairs 0 mismatches. But the pairs
are less smooth than at caf10f5 (rebases x2.5-4, fps run 56.8 -> 52.6, p99 ~91 ms): docs\NETPLAY_CHECK_PABLO_PC.md
section 9. Items 1-3 above (unlock vs netplay, launcher/portable tree default, `build_game_portable.ps1` `@()`) are
still open on your branch. Not reviewed line by line: the 101 Codex draft commits.

**Correction (same day):** the "less smooth than caf10f5" above is not a code regression. A bisect over all your
netplay changes found every state at 55.9-56.6 fps, and the final code itself gave both 55.9 and 53.2 in two runs:
it is run-to-run variance on one PC (NETPLAY_CHECK_PABLO_PC.md section 10). Item 1 (unlock vs netplay) is fixed on
`us-iso` faf7d21: unlock is always on when TEKKEN4_NET is set (was 198/199 hashes differing with one side at 0).
