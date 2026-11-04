# Tekken 4: direct-fight discovery and session results

2026-10-31. Source work for **SLUS-20328 v1.00 only**. Default-off diagnostics and an incomplete
online-session result are implemented; direct fight and a persistent game are plans.
2026-11-04: online games boot straight to VS character select from the game's own scene state
(default on, real-game pairs: "Online boot: straight to VS select").
Nothing was built or run in this working copy. Existing documents report real-game tests elsewhere;
those reports are not new validation of these changes.

The owner reports about 20 seconds of boot for each opponent. Measure that separately from
loading, handshake and the first playable frame before claiming a saving. No T5DR code or address
was copied for this work. Its MIT direct-fight implementation was read for behavior and failures only.

## Evidence: what is known and what is missing

| Area | Evidence in this copy | What it proves / what it does not prove |
|---|---|---|
| Function catalogue | `config/ghidra_functions.csv`, e.g. entries for `FUN_00196940`, `FUN_001969f8`, `FUN_001e2cc0`, `FUN_001e2da0`, `FUN_001ec0a0`, `FUN_001ec350` | Function starts/ranges exist. Generic names do not identify a mode manager, round state, health or winner. |
| Main-loop observation | `runtime/tekken4_overrides.cpp`: `kSoundFrameCall = 0x100`, `g_frames`; `runtime/tekken4_rollback_overrides.cpp`: `boundary` | There is a host observation point for frame progress. The rollback VBlank boundary is the probe's clock, not a proven fight-update boundary. |
| Select availability | `runtime/tekken4_unlock_overrides.cpp`, discovery comments and `kAvailableCheck` | Roster/costume table `0x0030e100`: 112 records of 28 bytes, u16 fighter at +0, u16 costume at +2, availability callback at +24. `FUN_001e2da0` invokes the callback; `FUN_001e2cc0` builds the selectable mask at gp-0x52d4. These are roster metadata, not each side's committed battle selection. |
| Unlock/profile | Same file: callback `0x001ec350`, profile check `FUN_001ec0a0` | Availability depends on bit `<costume>` in byte `0x0036c2b8 + 0x60 + fighter`. The existing override returns 1 without modifying the profile. This is not a health, score, winner or mode field. |
| Mode manager / select transition | Found 2026-11-04: scene manager `FUN_001978d0`, record at `0x357d38` (see "Online boot") | Current/requested/previous scene and the MODE SELECT menu/cursor/game type are proven by probe runs and the online boot pairs. The teardown/setup contract for a direct fight (skipping select) is still TODO. |
| Round / winner / score | [MATCH_RESULT_T4.md](MATCH_RESULT_T4.md) (2026-11-04) | Round wins player +0x8E, rounds to win 0x357d74, the game's match decision 0x2a8bf8+0x2C (FUN_001bbe70 / FUN_001bbb28), proven in scripted fights. |
| Health | [MATCH_RESULT_T4.md](MATCH_RESULT_T4.md) (2026-11-04) | Player +0x6BC (16.16 fixed, 165.0 full), read by the round logic FUN_001bcb08; round timer 0x356064. |
| Broad search range | `runtime/tekken4_overrides.cpp`: existing debug RAM dump at `0x00300000..0x00500000` | This was a debug comparison range containing rodata/bss/buffers. It is not evidence that gameplay fields lie there. |
| Confirmed hash | `tekken4_rollback_overrides.cpp`: `npBoundary`, `hashSubmit`, `hashCollect`, `netHashOf` | Existing net hash jobs use snapshots whose earlier inputs are confirmed after pending corrections. A collected hash can lag the live frame. It is not necessarily the match-deciding hash or proof that the peer compared it. |
| Frame rate | Same file: `npFrameTiming`, `npSummary` | Host live-boundary rate is available. Resimulated boundaries are not new live frames; stalls and time-sync waits affect elapsed time. This is not displayed-picture FPS or fight-only FPS. |

Address warning: `docs/ROLLBACK_PLAN.md`, “Address caveat”, explicitly says older `FUN_` names in
comments/docs may still be PAL names, including the main-loop name `FUN_001969f8`. The CSV alone
does not repair a semantic label. Re-find callers/writers in the actual US build before treating any
such name as a mode-manager anchor. The unlock constants above are explicitly documented US
constants; no guessed gameplay address is published here.

## Online boot: straight to VS select

2026-11-04 (branch `t4-autovs`). Every netplay session (lobby match, Easy Launcher Host/Join,
`tools/net_play.ps1`) boots straight to **VS character select**; the players only pick fighters.
`TEKKEN4_NET_AUTO_VS=0` (Easy Launcher: untick "Start at VS character select"; `net_play.ps1 -NoAutoVs`)
gives the old manual menus. Both PCs must use the same setting: the HELLO fingerprint refuses a peer
with the other switch, bound or card mode ("AUTO_VS script/window differs").

### The game state it reads (US SLUS-20328 v1.00, found 2026-11-04)

Scene manager `FUN_001978d0` (getter `FUN_001978a0`, both read/write `lui 0x35` + `0x7D38`):

| Address | Meaning | Values seen |
|---|---|---|
| `0x357d38` | current scene | 0 boot, 5 Namco logo, 8 title, 1 (one frame) then 2 MODE SELECT, 7 VS character select, 6 Story's select, 4 the next mode's load/fight (VS) or Story's prologue |
| `0x357d3c` | requested scene | 14 = none; the manager moves it to current at the next update |
| `0x357d40` | previous scene | |
| `0x357d44` | phase inside the scene | resets to 0 at every scene change |
| `0x357724` | active menu in MODE SELECT | 1 = SET GAME DIFFICULTY (only shown when no save was loaded), 2 = the mode list, 0 after it |
| `0x357720` | that menu's cursor | mode list: 0 Story, 1 Arcade / Time Attack, 2 VS Battle, 3 Team, ... 8 Options |
| `0x2a8bf8` | game type, written by the mode list's confirm | 2 Story, 3 VS Battle |

Found with the read-only probe (below) over `.data`/`.sdata`/`.sbss`/the start of `.bss` and frame
shots of the same pair, then confirmed in the lifted code (the manager's store) and by the runs below.

### How it works

- Lockstep from the start until VS select shows (`TEKKEN4_NET_RBSTART` still sets the earliest
  rollback start, default 600). Every boundary is final in lockstep, so both PCs see the same state.
- Only the host's pad (P1) presses; P2 and both PCs' real pads/keyboards are neutral meanwhile.
- Every `max(24, input delay + 16)` target frames the host decides one press for 4 frames from the
  state at the boundary where that input is sampled: scene 5 or 8 -> Start; scene 2 with the difficulty
  prompt -> Start (keeps the default); scene 2 with the mode list -> Down / Up towards cursor 2, Cross
  on it; anything else -> nothing. A press that was not taken is simply decided again.
- Hand-over: at the first boundary with scene 7 and game type 3 (`NETAUTO_VS select f=...` in
  `rb_frames.log`, the same frame on both PCs) every input not yet sampled is normal input; test scripts
  only apply from there on. If no VS select by `TEKKEN4_NET_AUTO_VS_END` (default 3000 frames, ~50 s),
  `NETAUTO_VS timeout` names the scene/menu it stopped in and the players take over.
- Peer lost or handshake failed during the window: the session ends and the native pad comes back
  (unchanged from the earlier version).

### Memory card online (`TEKKEN4_NET_CARD`)

The runtime's memory card is `game\disc\mc0` next to the ELF, shared with offline play (the `mc0`/`mc1`
folders net_pair/net_play create in the run directory were never used). A save there changes the boot
path (no difficulty prompt; the old fixed script then walked into Story Battle and King's prologue,
run `av_save1`) and loads that player's options and records into the game: two PCs with different saves
would not start from the same state. Online games now use `mc0`/`mc1` in their working directory
(`session`, default): `net_play.ps1` and the lobby start every match in a new run directory, so both PCs
boot with an empty card. `TEKKEN4_NET_CARD=shared` keeps the game folder's card (both PCs then need the
same save). Characters are unaffected (`TEKKEN4_UNLOCK_ALL`).

### Timing

Boot to VS select (frame 241 at RTT 0-60, process start to select ~4-6 s) instead of ~1100 frames
(~19 s) with the old fixed script: Start at the Namco logo skips logo and title.
### Pairs (this PC, 2026-11-04, build `out\avs` id 237631523a2b1e8d, `tools/net_pair.ps1 -AutoVs`)

Each pair: two games over loopback with the in-process network simulator, host + join, P1/P2 confirm
fighter, handicap and stage with Cross after the hand-over (frames 1500/1700/1900), then pseudo-random
fight input from 2400; frame shots and the host's state probe show the screens. "Fight" = the VS load
scene (4) after select, then READY/FIGHT/KO/replay in the shots.

| Run | Path | Card | Mode | Select at (both) | Mismatching hashes | Fight |
|---|---|---|---|---|---|---|
| av_n1 | RTT 0 | session (empty) | rollback | f 241 | 0 / 119 | yes |
| av_n2_saved | RTT 0 | shared, existing save | rollback | f 241 | 0 / 89 | yes |
| av_m1_r17 | RTT 17 j3 | session | rollback | f 241 | 0 / 119 | yes |
| av_m1_r60l1 | RTT 60 j5 loss 1 % | session | rollback | f 241 | 0 / 119 | yes |
| av_m1_r150l3 | RTT 150 j5 loss 3 % | session | rollback | f 241 | 0 / 119 | yes |
| av_m1_r150l3sv | RTT 150 j5 loss 3 % | shared, existing save | rollback | f 241 | 0 / 119 | yes |
| av_m1_r250l5 | RTT 250 j10 loss 5 % (lock delay 10) | session | rollback | f 261 | 0 / 139 | yes |
| av_m1_ls_r100 | RTT 100 j5 | session | lockstep | f 241 | 0 / 119 | yes |
| av_m1_ls_r150sv | RTT 150 j5 loss 2 % | shared, existing save | lockstep | f 241 | 0 / 119 | yes |
| av_m1_ls_r0 | RTT 0 | session | lockstep | f 241 | 0 / 119 | yes |
| av_m1_r30 | RTT 30 j3 | session | rollback | f 241 | 0 / 119 | yes |
| av_m1_r150l3b | RTT 150 j5 loss 3 % | session | rollback | f 241 | 0 / 119 | yes |
| av_m1_r0sv | RTT 0 | shared, existing save | rollback | f 241 | 0 / 119 | yes |

13 of 13: both games at VS select at the same frame, 0 mismatching hashes, 0 NETDESYNC, a fight after.
Lockstep = `TEKKEN4_NET_RBSTART=1000000`. Rollback pairs had 4-505 rollbacks per side.

Refusals and the bound (`av_neg_*`): host on / joiner `TEKKEN4_NET_AUTO_VS=0` -> the two never connect
(protocol v5 with the fingerprint vs v1: both keep "waiting for the opponent's game to answer", no
explicit message: an older behaviour of the transport); session card vs `shared` -> `auto_vs_mismatch`
on both sides, "use the same settings on both PCs"; `TEKKEN4_NET_AUTO_VS_END=150` -> both
`NETAUTO_VS timeout f=150 ... (scene=2 menu=1 ...)`, players take over at 152, in sync.

Before (old fixed script, `av_disc1` / `av_save1`): fresh card reached select at ~1082 (18 s of
frames); with an existing save the same presses chose Story Battle and started King's prologue.

Not covered: two physical PCs (the owner's next test), physical pads pressed during the boot window
(the code returns before any device is sampled).

## Default-off read-only probe

The probe observes host boundaries and RDRAM only. It does not set modes, force health, select
fighters, inject pads or change the simulation. Candidate labels are hypotheses. Correlation in a
trace narrows the search; field writers and controlled gameplay changes must establish semantics.
The hook excludes logical re-simulation, including rollback tails that draw and tests that use
wrong input. Draw-cut state alone would not be a sufficient guard.

Use `TEKKEN4_RB_MODE=measure`, `TEKKEN4_RB_FRAMEHASH=0` and `TEKKEN4_STATE_PROBE=1` for the discovery run. The probe uses the existing rollback boundary hook and therefore requires an enabled rollback mode; the probe switch alone installs no hook. Unset or any other probe-switch value is off. The file is
`TEKKEN4_STATE_PROBE_FILE` or `t4_state_probe.log` in the run directory. It appends a new
`PROBE version=1` section for each process. Use a fresh path to simplify analysis.

No mode/round/health addresses are selected by default: none are proven. Optional environment lists
`TEKKEN4_STATE_PROBE_MODE`, `TEKKEN4_STATE_PROBE_ROUND` and `TEKKEN4_STATE_PROBE_HEALTH` accept
comma-separated `physical_address[:width]` hypotheses; width is 1, 2 or 4 bytes, default 4. These log
raw little-endian integers every observed frame. Labels do not make a hypothesis a known field.

Discovery ranges use `TEKKEN4_STATE_PROBE_RANGES=address:size,address:size`; physical addresses,
hexadecimal allowed, nonoverlapping, at most 64 ranges and 32 MiB total. The default
`0x300000:0x200000` follows the existing debug dump range only. `none` disables range scanning.
`0:0x2000000` covers all 32 MiB RDRAM when the maintainer needs broader discovery; it is expensive
and logs raw game memory, so keep this output outside the clean copy. Default coverage cannot
promise discovery of any gameplay field.

Each `F` row marks the sampled frame and host milliseconds since probe initialization, for correlation
with the observation sheet. `C` rows give category, address, byte width and raw value.
`B` rows contain baseline address/length/hex bytes; `D` rows contain changed 16-byte blocks in the
same format. Reconstruct the range by applying B/D records in order, then inspect bytes, words or
float interpretations offline. Every changed byte in a configured range is retained; this does not
prove its meaning. The first baseline can be large, and changed graphics/buffers can make logs
large. Scan/write overhead affects FPS; do not use a discovery trace as a performance benchmark.
Invalid configuration or output errors are reported to stderr and disable the probe. Rows show the first live visit, which may contain predicted input in netplay; corrected re-simulation is deliberately absent. These rows cannot establish a confirmed online result by themselves.

## Maintainer's probe run

Perform these steps in the real project's approved game setup, outside this clean copy. Do not put
game data, generated code, RAM dumps, BIOS, saves, keys or screenshots in this working copy.

1. Build the reviewed source in the real project. Record the exact US game/build identity, effective
   runtime switches, round/time settings, unlock setting and input configuration. Start with a local
   two-player VS observation run; network delay is an unnecessary discovery variable at this stage.
2. Enable the probe using the settings above and a fresh output path in the real run directory.
   Preserve the probe header and effective configuration with the trace. Start an observation timer
   when the probe enables and use the `F` elapsed-millisecond column to align observations.
   Set up an observation sheet: frame or host time, visible screen, both picks/costumes, stage,
   round counters, displayed health, action and expected result.
3. Hold at title, main menu, VS entry, each player's select/confirm and stage confirm long enough to
   distinguish stable state from transition state. Change one choice at a time. Include a cancel
   followed by confirm and mirror picks. Mark loading, intro, READY and first controllable frame.
4. In the first round leave both players idle, then land isolated known hits on P1 and on P2 with
   pauses between them. Observe visible damage and round reset. Avoid assigning semantics merely
   because a small value falls; animation, timer, HUD drain and unrelated counters also change.
5. Exercise pause/resume locally and mark the frames. Then win rounds on alternating sides to
   expose each score, round start, KO, replay, next-round load, final result and return to select.
   Obtain 3-0, 3-1 and 3-2 when rounds-to-win is 3; record the actual configured rule if different.
6. Include timeout with unequal health, timeout with equal health, and double KO where possible.
   Record draw behavior, score changes and whether a result flag remains set on select or rematch.
   A single ordinary KO cannot establish winner encoding or match completion.
7. Narrow candidate addresses, then follow their actual US writers/callers in Ghidra. Verify type,
   alignment, signedness/float encoding, pointer lifetime, P1/P2 mapping/stride and reset conditions.
   Separate current mode from requested mode; highlight/preview from committed selection; live HP
   from HUD smoothing; round win from match win. If the first run's coverage misses the fields,
   use its phase markers and writer investigation to configure the next run. Do not invent addresses.
8. Repeat the same transitions with probe OFF and ON. A real rollback self-test must remain at
   zero mismatches with sound enabled. In test/selfnet/net logs, verify that the probe has no rows
   for `R`/`W` passes and no duplicate rows produced by a corrected replay of a logical frame.
   Compare timing separately: logging overhead is not a performance improvement.
9. After the local map is proven, use two physical PCs. Force delayed-input KO undo, timeout,
   double KO, disconnect near KO, late hashes and rematch. A predicted KO must never commit a
   result or automatic skip. Pin the corrected deciding input prefix and compare the exact final
   boundary hash before a future verified result is published.

Keep a small evidence table per field: US build, physical address or pointer chain, width/encoding,
writers, P1/P2 mapping, trace frames for each controlled change and cases still untested. Promote a
candidate to a named runtime constant only after those checks. One well-annotated run can narrow
many candidates; it does not guarantee every semantic field has been found.

## Online-session result file

Since 2026-11-04 the online game writes the match result itself: see [MATCH_RESULT_T4.md](MATCH_RESULT_T4.md)
(addresses with their evidence, how a result is decided on confirmed frames, the file schema
`tekken4-online-session-v2`). Set `TEKKEN4_NET_RESULT=<path>` for an online process (unset, empty or `0` is off;
the parent directory must exist; one path per process). `TEKKEN4_NET_MATCH` names the lobby match in the file.
The session fields of v1 stay (`run_id`, `connected`, `local_slot`, `frame`, `final_hash`, `fps`, `reason`,
`reason_detail`, `reporting_finished`); `winner`/`score` are filled only when `match_result_proven` is true.

## Direct-fight plan after discovery

1. Map the real mode manager and its teardown/setup contract. Find committed fighter/model/costume,
   stage, rounds/options and ready/load completion state. Use the normal manager to release old scene
   resources. Do not call select setup repeatedly in place or write an unverified mode byte.
2. Define versioned setup negotiation: build/game identity, unique match/session IDs, concrete picks,
   stage, seed, round rules, input delay and online profile/options identity. Resolve random choices once
   from shared setup. Both sides validate and acknowledge before entering the fight.
3. Reach a proven ready boundary after movie/loader completion and before gameplay RNG/input begins.
   Slow loading must wait or abort explicitly; elapsed time and the current frame-600 boot threshold are
   not proofs that host decoders and asynchronous loads are quiescent.
4. Initialize synchronized input/hash epochs and RNG through traced T4 mechanisms. Match committed
   state on both peers before enabling rollback. Preserve the whole-RDRAM/EE-cycle hash contract;
   unexplained warm/cold differences must be explained, not hidden behind T5DR masks or address ranges.
5. Add confirmed-result policy, then symmetric pause/skip/rematch input rules. Commit actions only after
   the deciding input prefix is final; retract pending actions if rollback removes the KO. Keep menu
   controls usable and require fresh released/pressed transitions for automatic commands.
6. Accept only after repeated real matches across roster/stages, all score endings, asymmetric loads,
   random/mirror picks, reordered setup and early/late commands. Measure boot-to-ready and rematch-to-ready
   separately from fight pacing. Two PCs are required for network outcome acceptance.

## Persistent game plan

A persistent process must distinguish **rematch within one session** from **a new opponent/session**.
The present T4 transport is process-lifetime oriented: `start()` returns when already running, worker
threads are detached, and `bye()` sends BYE but does not implement full reset/close. See
`runtime/tekken4_net.cpp` and `docs/ROLLBACK_NEXT.md`, “Persistent sessions”. Reusing the current
process without that work would reuse state that a new handshake must not inherit.

Add a bounded host command/state interface with monotonic request IDs and acknowledged idle/loading/
fighting/ended states. Before replacing an opponent, stop new hash work, drain active readers of rollback
slots, cancel waits, shut down/join or safely park socket workers, close the socket and discard delayed
packets. Use session generations to reject old worker completions. Reset keys, peer identity, nonces,
RTT/delay/lead/input/hash histories, pending results, cuts/mute/pacing and session options. Environment
settings cached at startup need an explicit per-session configuration source. Failure should produce an
incomplete result and a defined idle/restart outcome.

Find a canonical guest re-entry state by tracing T4 teardown. Never restore a raw snapshot of active
loader queues, busy flags or live host services. Prove warm-new-opponent state against fresh boot,
including first fight, scene changes, return-to-title and cancellation during load/resim/hash work.
Run many cycles and check resource/task counts, memory, sockets, worker lifetimes, matched hashes and
first-fight pacing. Recovering gracefully or restarting is preferable to reporting a fabricated win.

## T5DR lessons: failures to avoid, not T4 addresses

References below are the owner's read-only T5DR `docs/DIRECTFIGHT.md` and `src/directfight` files.
They are design evidence for T5DR only; they do not prove a T4 field or manager contract.

| T5DR evidence | Failure and lesson for the T4 plan |
|---|---|
| `DIRECTFIGHT.md:44-48,79-83,170-173` | Match IDs prevented stale/voided result reuse; netplay owned online result publication. An early score source always read zero. Read proven live counters, never synthesize score from winner or rounds-to-win. |
| `DIRECTFIGHT.md:38-42,157-164` | Random stage selection required shared resolution before hashed state. Negotiate concrete choices. |
| `DIRECTFIGHT.md:431-487`; `df_fight.cpp` match-end handling | Mashing after KO could auto-start an unauthorized fight with a random stage and desync. A predicted KO could be rolled back. Gate pad suppression/skips/results on a confirmed fresh decision; undo pending actions when the decision disappears. |
| `DIRECTFIGHT.md:544-635` | Persistent commands required acknowledgements, fresh session identity and real transport teardown. Played-versus-fresh state and cache-dependent loading caused mismatches. Separate new opponent from rematch and prove canonical warm start. |
| `DIRECTFIGHT.md:663-689,826-879` | Repeated title/select entry or reset during pending mode change corrupted resources; repeated select setup leaked preview/resource tasks and broke later restarts. Use actual teardown/rebuild through the game manager. |
| `DIRECTFIGHT.md:1510-1531,1621-1639` | Save/unlock grid differences changed cursor targets; saved Difficulty/Round Time leaked into battle state. Agree on effective online profile/options and exposed roster, rather than assuming matching binaries imply matching setup. |
| `DIRECTFIGHT.md:958-1003` | Broad snapshots restored async reader busy/queue state and could stall loading permanently. Exclude active host services, require quiescence and judge watchdogs by real progress as well as time. |

## Validation in this copy

Source inspection and a separate final-diff review only. No compiler, game, networking harness, build
script or runtime test was executed. A real build must check header staging and API compatibility.
A real game must prove all gameplay fields and transitions, probe exclusion during re-simulation,
result-file lifecycle/failure handling, unchanged rollback hashes and acceptable logging overhead.
Direct fight, trusted match results and persistent opponents are not working features claimed here.


