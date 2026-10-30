# Tekken 4: direct-fight discovery and session results

2026-10-31. Source work for **SLUS-20328 v1.00 only**. Default-off diagnostics, scripted
online boot navigation and an incomplete online-session result are implemented;
direct fight and a persistent game are plans.
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
| Mode manager / select transition | `docs/ROLLBACK_NEXT.md`, “T4 discovery required” and “Session, result and replay contracts” | The game teardown/setup path, current/pending mode fields and transition values are still TODO. No address is proven for direct-fight entry. |
| Round / winner / score | Same discovery section; no verified implementation in the runtime | Round phase, deciding boundary, winner encoding and two-side scores are TODO. Do not derive score from the winner or configured rounds-to-win. |
| Health | No verified field in the inspected CSV, docs, overrides or rollback code | Both players' live health fields, widths, encodings, bases/strides, KO/timeout rules and reset timing are TODO. A HUD drain value may lag true health. |
| Broad search range | `runtime/tekken4_overrides.cpp`: existing debug RAM dump at `0x00300000..0x00500000` | This was a debug comparison range containing rodata/bss/buffers. It is not evidence that gameplay fields lie there. |
| Confirmed hash | `tekken4_rollback_overrides.cpp`: `npBoundary`, `hashSubmit`, `hashCollect`, `netHashOf` | Existing net hash jobs use snapshots whose earlier inputs are confirmed after pending corrections. A collected hash can lag the live frame. It is not necessarily the match-deciding hash or proof that the peer compared it. |
| Frame rate | Same file: `npFrameTiming`, `npSummary` | Host live-boundary rate is available. Resimulated boundaries are not new live frames; stalls and time-sync waits affect elapsed time. This is not displayed-picture FPS or fight-only FPS. |

Address warning: `docs/ROLLBACK_PLAN.md`, “Address caveat”, explicitly says older `FUN_` names in
comments/docs may still be PAL names, including the main-loop name `FUN_001969f8`. The CSV alone
does not repair a semantic label. Re-find callers/writers in the actual US build before treating any
such name as a mode-manager anchor. The unlock constants above are explicitly documented US
constants; no guessed gameplay address is published here.

## Default-off online boot navigation

`TEKKEN4_NET_AUTO_VS=1` enables a bounded script for a netplay session. Unset or any
other value is off. It uses the existing pad/input exchange, with the same presses for both
players on both PCs at the same logical input frames. Real pad input is held neutral in this
window. This is a first step toward entering VS without menu clicks; it does not call a game
mode manager or skip a loader by writing memory.

The default script is the existing pair-test prefix:

```
500:Start,800:Start,960:Down,1020:Down,1080:Cross
```

Presses last six frames by default, using the existing script parser. The prefix is intended to
reach VS character select; it omits the later character/stage confirms used by the fight test.
`TEKKEN4_RB_INPUT` can supply a shared boot script; an explicitly empty value supplies neutral
input for the whole window. Malformed presses abort netplay configuration with a log line and
restore native offline input. Invalid auto-VS/netplay configuration, a failed handshake or
detected peer loss also logs `NETAUTO_VS aborted:` and restores the native pad path, without
retaining a scripted provider. Peer loss uses the transport's existing timeout; its last remote
boot press cannot repeat forever after that abort.
Presses are clipped by the window and cannot extend it. During the window,
pad 2's separate script, fuzz input and local devices do not affect either player's buttons.
Both peers must agree on the normalized boot schedule, window, effective rollback start and
boundary configuration before the handshake can succeed; enabling the switch on only one peer
or using a different schedule is rejected.

`TEKKEN4_NET_AUTO_VS_END` is the logical handoff frame, default 1200, bounded to 1..3600.
Frame END supplies neutral input to release the last scripted press; the normal input path
resumes from END+1. Finite per-slot presses whose start frame is at or before END are discarded
after handoff, so a long boot press cannot leak into manual select. Later per-slot presses,
fuzz and local devices use the normal path. Boot runs in lockstep through this handoff even if
the configured rollback start was earlier. The script depends on logical frames, not elapsed host time, keyboard
sampling, local slot, or replay count.

There is no proven select/mode field, so reaching the end cannot prove that select was reached.
The `NETAUTO_VS` timeout log always describes an unverified handoff and restores ordinary
input. If a save or language dialog consumed a press, players can recover manually after the
bounded window. The script neither retries indefinitely nor reports a successful select detection.
The bound is in simulated frames: it cannot resolve an unrelated stalled loader. Peer loss uses
the separate transport timeout and abort path above.

The maintainer must run the real pair with sound on in three separate cases: fresh/fresh cards,
matching existing/existing cards, and mixed fresh/existing cards. Require **0 mismatches**,
visible VS character select without manual menu input, neutral physical pads during boot,
and working normal input after handoff.
Continue through character/stage confirms into a VS fight using the existing pair-test tail.
Mixed cards may expose save-dependent divergence or a different menu path; support for them is
unproved until this case passes, and automatic input must still release on its scheduled frame.
Also hold physical buttons during the boot window, use an altered dialog path to check manual
recovery after the timeout line, and verify mismatched on/off/scripts are rejected. Equal hashes
alone can mean both games reached the same wrong screen. Compare with the switch off and retain
the effective script, handoff frame, save identity and both logs. Two physical PCs must repeat the
checks; no such run was performed here.

Full direct fight remains deferred until the state probe and writer investigation prove T4's
mode manager, select state and safe transition contract. No new game addresses are guessed.

## Save and boot-path evidence

The older T4 netplay reports used cold, empty memory cards (`docs/ROLLBACK_PHASE3.md`,
"The loop" and "What is left"). That document and `docs/ROLLBACK_PHASE01.md`, phase 0 item 7,
explicitly warn that a player's own card changes the boot path. No inspected T4 source or
document proves the exact fresh-card versus existing-card dialog sequence, or a language/save
dialog state address. A timed input sequence cannot infer which screen accepted a press.

`tools/net_pair.ps1` keeps `mc0`/`mc1` in each side's run directory. Its directory creation
does not reset an existing card: reusing a pair name can reuse saves. Use distinct run names
for fresh-card checks and deliberately prepared, matching existing cards for the old-save checks
in the real game setup. Do not put those cards in this clean copy.

The current unlock override answers the save-dependent fighter/costume availability callback
without changing the profile or memory card (`runtime/tekken4_unlock_overrides.cpp`). It does
not normalize saved options or boot dialogs. A fixed online profile remains future work;
automatic menu input does not make different personal cards equivalent.

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

Set `TEKKEN4_NET_RESULT=<path>` for an online process. Unset, empty or `0` is off. The parent
directory must already exist. Use a unique path per process/session; concurrent writers must not
share a destination. Successful configuration/start writes an incomplete record so a later forced kill cannot
leave a previous session's win at that path. A write failure can leave an older destination intact;
consumers must check run identity and must not accept this incomplete schema as a match win. Updates use a sibling `.tmp` file and replacement;
failed writes are logged and do not alter simulation. Windows paths use the current narrow API.

Schema `tekken4-online-session-v1` contains a local `run_id`, `connected`, `local_slot` (1=P1 host,
2=P2 join, null unknown), `winner: null`, `score: null`, `match_result_proven: false`, current `frame`,
`final_hash`, `hash_scope`, `hash_includes_iop_state`, `fps`, `reason`, `reason_detail` and named `TODO_winner`, `TODO_score`,
`TODO_match_end`. The local clock-based run ID is not a negotiated match/session identity.
`reporting_finished` says this report was finalized; it does not prove the game or process stopped.

`final_hash` is null until an existing confirmed hash job has been collected; otherwise it contains
hex value, frame, `kind: latest_confirmed_sampled_boundary` and `peer_agreement_proven: false`.
It may precede the report boundary and has not been tied to a proven match-ending decision. The
normal net hash covers RDRAM, scratchpad, VU0 data and EE cycle; `hash_includes_iop_state` records
whether IOP state was enabled for that sample (default on in netplay). VU1 and GS
output are excluded; full EE context/scheduler/device state and the complete saved IOP state are
also not covered by this network hash. It must not be presented as complete-state or peer-equality
proof. See `netHashOf` and `docs/ROLLBACK_NEXT.md`, “RNG and hashes”.

`fps` measures host live-boundary progress divided by elapsed session wall time since handshake;
resimulated passes do not add live frames, while stalls and time-sync waits add time. It is neither
fight-only nor presented-picture FPS. Missing timing is null. Reasons include `rollback_log_failed`,
`configure_failed`, `handshake_failed`, `desync`, `peer_lost`, `frame_limit` and
`process_exit`, with detail where available; they describe transport/harness/process lifecycle.
`frame_limit` is `TEKKEN4_NET_END`, not game match completion. On desync the report can finish
while gameplay continues. Finalization drains already submitted confirmed hash jobs for at most
250 ms before collection; this neither guarantees the latest boundary nor waits for peer agreement. A normal exit has a cached `process_exit` fallback; crashes,
forced termination and power loss cannot guarantee a final update, so an initial pending record
can remain. No new winner, health or score address is read by the result writer.

TODOs required before winner/score can become non-null:

- **TODO_MODE_PHASE:** prove fight, round-end, match-end, select, pending transition and safe teardown;
  exclude stale match-over state on re-entry.
- **TODO_HEALTH:** establish both live health fields and reset/KO/timeout behavior; do not consume HUD
  animation or infer a final winner from health alone.
- **TODO_WINNER_SCORE:** prove winner/draw encoding, separate round and match decisions, and both actual
  round counters through 3-0/3-1/3-2, timeout, double KO and rematch resets.
- **TODO_DECIDING_HASH:** retain the corrected confirmed deciding boundary and require an exact peer
  equal-hash receipt for that frame. Aggregate comparison counts and a later sampled hash are insufficient.
- **TODO_MATCH_ID:** negotiate fresh session/match/setup identity and carry it through commands/results;
  a stale previous file must not be accepted for a new opponent.

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


