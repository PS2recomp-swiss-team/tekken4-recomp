# Rollback next: the gaps a player will feel

Status 2026-10-30. The latest owner-authorized port pass is recorded at the end, after the historical comparison.
The original read-only comparison added only this document. The earlier follow-up source edits below
add two opt-in runtime items. No build, game, network test or patch application was run. No T5DR code was copied
or consulted for those edits. Comparison references below describe the earlier source, not revised line numbers
or the other worktrees mentioned by old reports.

The order is player impact: a steady, responsive and correct fight first, less waiting between fights next,
then recording and watching. It is a proposed priority, not a measured ranking of player complaints.
"Gap" includes missing validation and differences worth measuring; it does not mean T5DR wins every comparison.
This covers the rollback/netplay areas inspected, not uninspected lobby/server or renderer implementations.

## Evidence and limits

- **Reported measurement** means a result in the supplied docs. The logs, executables and hardware behind those
  results were not inspected here. **Source** means the mechanism is present in this copy. **Inference** means
  an expected benefit or risk, not a demonstrated improvement.
- `docs/ROLLBACK_PLAN.md:3-6` is explicitly an unbuilt plan. Later implementation and phase reports supersede
  its full-copy, frozen-IOP and GS-only-cut proposals. The original comparison used T5DR as ideas only;
  the latest owner order explicitly permits MIT source ports from the supplied read-only T5DR tree.
- T4 phase 3 reports sound-on peers and an offline reference agreeing at sampled, confirmed boundaries through
  12,000 frames (`docs/ROLLBACK_PHASE3.md:7-21,70-77`). Phase 3b reports zero sampled hash mismatches after its
  changes (`docs/ROLLBACK_PHASE3B.md:92-96`). This is strong evidence for those scripts, not every frame,
  character, stage, CPU or session transition.
- In particular, the network hash is **not the entire serialized machine**. T4 hashes RDRAM, scratchpad, VU0
  data, selected IOP state and EE cycle (`runtime/tekken4_rollback_overrides.cpp:1036-1046`); it does not hash all
  scheduler/device fields or VU1 state. The separate offline test hash is broader. T5DR's normal network hash
  is smaller still: selected gameplay regions and skips (`T5 src/rollback/rb_state.cpp:245-285`). Neither proves
  that the picture or sound is right.
- T4 phase 3b found **GPU saturation caused most long hitches**: two games drove one RTX 3090 to 99%, with
  35-200 ms vertex-ring fence waits. The slow peer fell behind; the other predicted deeper and time-synced
  (`docs/ROLLBACK_PHASE3B.md:8-17,41-60`). Increasing delay did not fix that (`docs/ROLLBACK_PHASE3B.md:36-39`). Do not tune away this
  harness problem with more input lag.
- Two games on that PC cannot establish normal two-PC fight p99, repeat rate, rollback depth/frequency,
  time-sync fairness or the best input delay. One PC also cannot establish cross-vendor determinism, two
  independent display clocks, real NAT/WAN/relay behaviour or two players' audio experience. Separate PCs
  remove shared-GPU contention; each still needs enough local rendering headroom.
- `docs/PERF.md:12-54` reports a later single-game Practice sweep: all stages 60 fps, fight present p99
  16.9-17.2 ms, zero repeats/skips in those windows. It is not a two-PC VS netplay result. Some runs had other
  instances active, and the measured presenter differs from the exported/current one. Re-test the actual
  combined build before carrying these numbers into a release claim.
- T5DR's docs are also chronological. Use the later results, not its opening full-copy prototype. Its latest
  reported cut resim is 1.10-1.12 ms (`T5 docs/ROLLBACK.md:2594-2616`). Its display tests were also single-PC
  proxy pairs; they do not supply hardware-normalized T4 speedups or prove independent-display drift.

References prefixed `T5` are relative to `C:\OpenRecomp-work\T5DROnline-Source`. All others are relative to T4.
Patch line numbers mean lines in the patch file, not line numbers in an unavailable built runtime.

## 1. Fight headroom: live frame plus rollback must fit

- **T5DR:** cuts render work, bypasses waits and runs early rollback. Latest reported resim is 1.10-1.12 ms,
  versus about 4.0 ms without draw cuts (`T5 docs/ROLLBACK.md:2594-2616`). Earlier snapshot/restore and display
  measurements are from different revisions; do not add them into a supposed current total.
- **T4:** phase 3 measured a cut frame at 6.2-6.5 ms p50 and a drawn tail at 10.5-12.4 ms
  (`docs/ROLLBACK_PHASE3.md:29-31`). Phase 3b removed the netplay drawn tail, uses early rollback and lazy captures
  (`runtime/tekken4_rollback_overrides.cpp:1588-1596,1696-1716,2252-2259`). A100t0 reports capture/restore
  0.43/0.49 ms and **whole rollback** p50 6.6/12.7 ms host/join, p90 13.7/30.8 ms; A150t0 is slower
  (`docs/ROLLBACK_PHASE3B.md:31-34`). Those are not per-resim-frame costs.
- **Next / expected gain (inference):** profile the remaining EE, VIF/VU bookkeeping, IOP and copies separately
  from GPU waits. Reduce the actual bottleneck before adding a presentation margin. The old plan's <3 ms resim
  target (`docs/ROLLBACK_PLAN.md:357-362`) remains a useful investigation target, not an achieved result or a
  reason to claim T4 can reach T5DR's PS3-specific number.
- **Determinism risk:** high for changing IOP/EE interleaving, timer accounting or simulation work; lower for
  output-only GPU work, provided readbacks and guest-visible completion events remain identical.
- **Measure / two PCs:** report live busy time, actual present intervals, repeated pictures, each cut frame,
  restore, captures, whole rollback and depth together: p50/p90/p99/max, not just fps. Sweep stages and depths
  1/2/4/8 with sound on. One process can profile and self-test; **two PCs required** for player-facing acceptance.
- **Safe here without build:** cost model, source audit and measurement specification only. No performance
  implementation can be called safe or faster from this copy alone.

## 2. Re-simulation cuts: save work without wrong pictures

- **T5DR:** indirect/direct render cuts and GPU-wait bypasses (`T5 src/rollback/rb_icall.cpp:52-75,244`,
  `T5 src/rollback/rb_hooks.cpp:278-327`). A later HP-bar cut correction reduced reported bar reversals from
  15 to 2, near baseline, while resim stayed about 1.1 ms (`T5 docs/ROLLBACK.md:2594-2616`). A clean gameplay
  hash had not proved correct cosmetics.
- **T4:** available draw/present and optional upload cuts, then VU1 cuts, are in
  `patches/38-Rollback-phase-2-re-simulation-cuts-GS-draw-upload.patch` and
  `patches/40-Rollback-VU1-cut-idle-loop-skipping-host-profile-c.patch`. Current selection and VU1 hash policy
  are `runtime/tekken4_rollback_overrides.cpp:172,2238-2259`: default net cuts are draw/present/VU1, not upload.
  IOP runs during net resim. With no drawn tail, the
  first live picture after rollback still shows the old prediction; the correction comes one frame later
  (`docs/ROLLBACK_PHASE3B.md:73-77`). This is an explicit visual tradeoff, not free work removal.
- **Next / gain (inference):** retain current cuts as the baseline; audit each proposed deeper cut for gameplay,
  readback and visible HUD effects. Improve correction freshness only if its extra draw fits the budget.
  Lazy capture is already present in both games; it is not missing T4 work.
- **Determinism risk:** high for VU/DMA/GIF cuts; a skipped completion or memory side effect can hang or diverge.
  A cosmetic error may escape network hashes entirely.
- **Measure / two PCs:** cuts on/off against the same offline inputs, broad test hash and page diffs; inspect
  HP bars, shadows, camera, KO undo and correction age. One process proves local resim fidelity for a script;
  **two PCs required** to judge visual correction under late remote inputs.
- **Safe here:** a cut inventory and proof checklist. No new cuts or exclusions without build/game checks.

## 3. Correctness across machines and real connections

- **T5DR:** has build/seed negotiation (`T5 docs/NETPLAY.md:43-46`) and extensive cross-build FP checks.
  The v3/base/native/software-FMA comparisons were on the same Ryzen 7950X; the Intel/AMD claim is a static
  IEEE/MXCSR argument, not an actual cross-vendor run (`T5 docs/NETPLAY.md:1386-1407,1460-1465`).
- **T4:** has build rejection, forced-desync detection and seed mixing
  (`docs/ROLLBACK_PHASE3.md:38-41,95-103`; `runtime/tekken4_rollback_overrides.cpp:2048-2067`). But build id
  can be absent/zero in tests (`runtime/tekken4_rollback_overrides.cpp:1803-1813`); same-PC scripts do not validate different CPUs or arbitrary personal
  saves. The real game through the lobby, physical PCs, WAN, NAT and human play were still pending in the handoff
  (`SERVER_HANDOFF_T4.md:127-134`). No claim that the local stub suite proves them.
- **Next / gain:** establish an acceptance matrix for the actual combined patch stack: Intel/AMD, supported
  compiler/settings and render options, direct LAN/WAN and forced relay, loss/reorder/jitter and asymmetric
  load. Keep build mismatch rejection and a known forced desync as controls. This buys trust in the fight,
  rather than a predicted fps gain.
- **Determinism risk:** high if FP flags, clocks, RNG, snapshots or online state differ. Diagnostics alone are
  low risk. Do not mask a mismatch simply to make a test pass.
- **Measure / two PCs:** same confirmed inputs and hashes, round outcomes and dumped differences over long
  sessions/all stages, with honest hash coverage. **Two physical PCs required**, including cross-vendor tests;
  an actual relay hop/router is needed for the corresponding connection claim.
- **Safe here:** static FP/build-id/state audit and the matrix. The matrix has not been executed here.

## 4. Pause and predicted KO must not decide a match

- **T5DR:** gates irreversible actions on confirmed inputs; a predicted KO once caused scripted START to pause
  a restored fight (`T5 docs/ROLLBACK.md:2217-2259`).
- **T4:** `docs/LOBBY.md:128` and `docs/ROLLBACK_PHASE3.md:217-219` leave no-pause and confirmed KO/result
  rules open. The current local sample passes buttons, including START, through
  (`runtime/tekken4_rollback_overrides.cpp:1283-1298`); netplay treats menus and fights as generic frames.
- **Next / gain:** map T4's actual US fight/round/result phases. Filter pause during fights while preserving
  deliberate menu controls; publish results, issue skip/rematch commands and write external state only after
  the deciding inputs are confirmed. Prevents interrupted fights and false wins.
- **Determinism risk:** high if phase detection is wrong, an action runs on a prediction, or an automatic input
  is injected on different logical frames. A result file alone will not fix this.
- **Measure / two PCs:** START mashing in fight and menus; force a last-frame KO prediction to be undone;
  double KO, timeout, replay skip and disconnect beside KO. Require no pause, no early result and matching
  outcomes. Local scripted checks first; **two PCs required** for late-input acceptance.
- **Safe here:** phase/address questions and a rules specification. Address discovery/behaviour needs a real game.

## 5. Sound when the prediction changes

- **T5DR:** current default runs sound bookkeeping during resim, deduplicates starts and returns old handles;
  newly corrected sounds start late. Resim stops are suppressed and a mispredicted sound may continue. Library
  ticking stays live (`T5 src/rollback/rb_sound.cpp:23-50,135-162,265`; `T5 src/rollback/rb_hooks.cpp:398`). This supersedes
  old whole-update skipping. Its later audio results still report late/mispredicted sounds, not perfect audio
  (`T5 docs/ROLLBACK.md:2472-2592`).
- **T4:** rolls back the IOP/SPU2 as well as EE state and runs it muted during resim, rather than using T5DR's
  live-library strategy (`docs/ROLLBACK_PHASE3.md:47-77`;
  `runtime/tekken4_rollback_overrides.cpp:1385-1398,2143-2149,2244-2246`;
  `patches/41-Rollback-the-IOP-in-the-snapshot-SPU2-output-muted-i.patch`). Frozen IOP was found to diverge.
  Reported WAV comparison found 4538/4541 of 4557 non-silent reference windows identical, with differences near
  mispredictions and no doubled output. **There was no playback device**, so this was not a listening test
  (`docs/ROLLBACK_PHASE3.md:32-37`). Muted resim cannot make already-heard audio correct retroactively.
- **Next / gain (inference):** first listen on real devices and measure missing/late attack sounds, music seams,
  crackles and queue underruns. Only then evaluate replacing queued, unplayed audio or selectively starting a
  corrected sound. Preserve the proven IOP timeline; do not revert to the obsolete freeze plan.
- **Determinism risk:** high for changing IOP execution/replies; lower for a strictly host-output queue change
  which cannot affect guest state. Threading and queue truncation still need proof.
- **Measure / two PCs:** offline-vs-network WAV alignment plus listening on both endpoints; corrections at
  depths 1/2/4/8, music across rounds/rematches, no duplicated samples, queue depth/underruns and identical
  confirmed hashes. One PC can compare WAVs; **two PCs with playback devices required** for experience/sign-off.
- **Safe here:** audio policy and test cases only; no audible quality claim or queue rewrite without running it.

## 6. Input delay, short taps and fairness

- **T5DR:** matching explicit settings win; otherwise rollback auto is 1 frame through 60 ms and 2 above,
  bounded by lockstep delay. Ranked normally uses 2; the lobby enforces at least 3 above 150 ms and 4 above
  250 ms (`T5 docs/NETPLAY.md:217-247`). Its 1 ms tap latch has reported 2-5 ms tap tests
  (`T5 docs/NETPLAY.md:364-371`). These are policy layers, not just one universal table.
- **T4:** host picks auto 1/2/3/4, the joiner waits, RTT is a median of up to 32; missing RTT falls back to 2
  (`runtime/tekken4_net.cpp:1004-1067`). Explicit host setting wins (up to 15); the peer preference is logged,
  not negotiated into an equal-setting rule. `docs/LOBBY.md:57` describes ticket delay mapping, but not a
  validated ranked policy. T4 already has a 1 ms XInput tap latch in
  `patches/60-Gamepads-XInput-read-directly-at-pad-read-time-1-ms-.patch:7-13,57-69,99`. Do not list the latch
  as absent. In steady play one future input is sampled per live frame; initialization fills missing future
  frames and resim reuses stored input (`runtime/tekken4_rollback_overrides.cpp:1283-1298,1569-1570,1686-1689`).
  Raylib fallback and keyboard need their own checks.
- **Next / gain:** document and agree casual/ranked policy explicitly, including host/peer disagreement and the
  exact boundaries below. Keep delay stable in a match. Test that taps survive net sampling and stall/lockstep
  transitions. Potential gain is lower avoidable input lag and fair settings, not fewer GPU hitches.

  | Measured RTT | T4 auto | T5DR policy described above |
  |---|---|---|
  | <= 60 ms | 1 | casual auto 1; ranked normally 2 |
  | > 60, <= 150 ms | 2 | casual auto 2; ranked normally 2 |
  | > 150, <= 250 ms | 3 | lobby floor 3 |
  | > 250 ms | 4 | lobby floor 4 |

- **Determinism risk:** low for policy before the first input; high if the peers apply it at different frames
  or change it mid-match without a protocol. Short-tap consumption must occur once, never during resim.
- **Measure / two PCs:** 59/60/61, 149/150/151, 249/250/251 ms, missing samples and unequal settings; report
  measured RTT, delay, depth histogram and input-to-screen time. One-PC protocol tests possible; **two PCs
  required** for choosing defaults and independent-display latency. Phase 3b's delay-3 A/B was GPU-confounded.
- **Safe here:** table, policy and test vectors. Applying a new policy still needs build/protocol/game validation.

## 7. Time sync and display pacing

- **T5DR:** trimmed lead estimate, correction held until the peer can observe it, actual runtime vblank tick
  skips and a 3.5 ms display margin (`T5 src/rollback/rb_net.cpp:176,500,809-835`). Later display-grid tests
  report repeated pictures falling 50->38, 67->40 and 62->36 per match at 60/120/180 ms, with p99
  19.0/19.9/20.6 ms. Margin costs roughly 1-2 ms input-to-screen; it is not a free latency improvement
  (`T5 docs/ROLLBACK.md:2472-2592`).
- **T4:** has trimmed 20-sample estimates, RTT hold, whole-period waits **plus host-deadline shifts**, not
  T5DR's runtime tick-skip implementation (`runtime/tekken4_rollback_overrides.cpp:1401-1442`). It has
  early rollback and a pacing guard (`runtime/tekken4_rollback_overrides.cpp:1447-1459,1696-1716`). No equivalent net display queue/margin was
  established; phase 3b explicitly defers it until headroom exists (`docs/ROLLBACK_PHASE3B.md:107-110`).
- **Next / gain (inference):** test whether corrections actually extend visible pictures by the intended refresh
  count, then consider a small margin/queue. Target fewer repeated pictures and oscillations, with an explicit
  latency cost. Do not treat changing the correction mechanism as a proven improvement.
- **Determinism risk:** low if only host pacing changes; high if guest vblank/cycle counts or event order change.
- **Measure / two PCs:** log both lead estimates, corrections, actual presents, missed display slots, repeat/skip
  counts and latency. Compare early/margin off/on at equal load. **Two PCs and independent displays required**
  for drift and fairness; same-PC pairs only exercise the algorithm.
- **Safe here:** pacing model and metrics. Runtime/event/presenter changes need build/game evidence.

## 8. Packet rate, size and redundancy

- **T5DR:** current v4 retains last eight inputs, caps batches at 64, includes eight hashes and up to four scene
  barriers; 15 ms stall resend (`T5 src/netplay/netplay_core.cpp:83-108,809-838,1702,1926,2083`). Packed sizes
  imply **29 + 6*n + 12*h + 8*b bytes**, plus 8 keyed: 205 unkeyed for n=8,h=8,b=4, maximum 541 (549 keyed).
  This is source arithmetic, not a packet capture.
- **T4:** v1 retains last eight inputs, caps at 64 and repeats up to eight hashes
  (`runtime/tekken4_net.cpp:39-43,61-98,351-392`). Payload = **28 + 6*n + 12*h**, plus 8 keyed: 172 for
  n=8,h=8; maximum 508 (516 keyed). Add 28 for ordinary IPv4/UDP, before any relay overhead. It sends at
  `setLocal`, extra boundary points and the 15 ms unacked timer
  (`runtime/tekken4_net.cpp:748-785,1090-1101`; `runtime/tekken4_rollback_overrides.cpp:1686-1690,1723-1732`).
- **Evidence / gain:** handoff packet rates 92-140/s are historical measurements; its ~150/s/~250 kbit/s at
  60 fps and T5DR ~60/s/~85 kbit/s are estimates/historical comparisons
  (`SERVER_HANDOFF_T4.md:74-96`). **Current T5DR packets can be larger than T4's**; do not promise halving
  T4 bandwidth merely by matching T5DR. T4 byte counters exist (`runtime/tekken4_net.cpp:270-271`;
  `runtime/tekken4_net.h:102-107`) but the docs say their addition was not built/run. Measure current traffic,
  then coalesce redundant sends and consider fewer repeated hashes while retaining input loss recovery.
- **Determinism risk:** low for coalescing identical data, but lost early inputs can deepen rollback or stall.
  Hash trimming can silently weaken desync detection; size changes need version/build compatibility review.
- **Measure / two PCs:** packet capture plus counters, per-type pps/bytes in/out, keyed/unkeyed, gaps, ack age,
  burst loss/reorder and relay drops. Count attempts separately from delivered packets. One-PC wire tests can
  prove sizes; **two PCs over actual direct and relay paths required** for congestion/limits and player effect.
- **Safe here:** size arithmetic, send-site audit and compatibility/test design. Do not change relay limits or
  remove redundancy on the strength of the old estimates.

## 9. Snapshot and restore: less copying, complete state

- **T5DR:** dirty-page shadow/undo logs with lazy confirmed resim commits, and restore copies each affected page
  once (`T5 src/rollback/rb_state.cpp:455-527,645-724`; `T5 src/rollback/rb_net.cpp:859-861`). Its six ~104 MB saved ranges
  exclude asynchronous output/loader areas and keep selected bytes live (`T5 src/rollback/rb_state.cpp:37-100`). Historical
  A/B reports reduced capture to 0.37 ms and restore 1.13->0.63 ms (`T5 docs/ROLLBACK.md:1653-1659,2333`).
- **T4:** patch 74 already uses Windows write-watch and sequence stamps to update **full-sized per-slot copies**,
  not T5DR's undo representation
  (`patches/74-Rollback-incremental-RDRAM-snapshots.patch:193-198,260-328`). First use is a full copy; failure
  to get dirty pages falls back conservatively. It preserves EE/kernel/device and IOP state through patches
  37/39/41. Default ring = max prediction + 3 (`runtime/tekken4_rollback_overrides.cpp:1898-1901`): with 8,
  RDRAM copies alone eventually occupy 11*32 MiB = **352 MiB**, before IOP and other state (source arithmetic).
  Phase 3b measured ~185 dirty pages, capture 0.42-0.46 ms, restore 0.48-0.50 ms and zero verification mismatching
  pages in one 6000-frame pair (`docs/ROLLBACK_PHASE3B.md:84-87`).
- **Next / gain (inference):** measure RDRAM versus IOP/SPU/kernel/device copy cost and memory/first-touch cost.
  Consider compact undo or dirty tracking of other large memories only if the residual cost warrants it.
  Current incremental capture is already competitive with those historical T5DR numbers; replacing it is not
  automatically faster. Retain the full-copy verification path.
- **Determinism risk:** very high: a missed dirty page, stale sequence, omitted device state or bad restored
  callback breaks the timeline. Do not import T5DR's address exclusions into this machine model.
- **Measure / two PCs:** depth/ring-wrap stress, full versus incremental after each restore, sound on, loads,
  KO/rematch, allocated bytes and capture/restore percentiles. One process can prove local copy fidelity;
  **two PCs required** for acceptance of the whole network timeline.
- **Safe here:** state inventory and memory/cost calculation. No state removal or snapshot rewrite without tests.

## 10. Hash cost and diagnostic coverage

- **T5DR:** per-page state hashing exists but is off by default in net mode
  (`T5 src/rollback/rb_net.cpp:493-495`). Normal arbitration hashes eleven selected regions, about 22,156
  bytes before skips; `HASH_FULL` removes those skips, not the snapshot exclusions
  (`T5 src/rollback/rb_state.cpp:245-323`). Faster checking trades coverage for a curated map.
- **T4:** hashes broad memory every 30 confirmed boundaries; worker hashes and optional dump copies, and ring
  reuse waits for readers (`runtime/tekken4_rollback_overrides.cpp:1036-1046,1155-1213,1761-1773`). Phase 3b
  moved the ~3.7-4 ms hash and 32 MB dump copy off the game thread; this is already implemented
  (`docs/ROLLBACK_PHASE3B.md:58-60,78`). **Capture timing starts after `hashWaitSlot`**
  (`runtime/tekken4_rollback_overrides.cpp:1349-1357`), so
  the capture average does not reveal worker-induced slot waits. Dumps retain RDRAM/scratchpad, not the whole
  machine (`runtime/tekken4_rollback_overrides.cpp:1170-1173,1776-1784`).
- **Next / gain (inference):** instrument queue depth, reader waits, CPU/memory traffic and time-to-detection.
  Prefer an incremental broad hash, if justified, before silently narrowing it to a T5DR-style gameplay map.
  Define a diagnostic dump containing enough state to explain an IOP/device mismatch. No measured new saving yet.
- **Determinism risk:** low for read-only hashing with correct ownership; high for racing a reused snapshot or
  accepting a weak hash as proof. A new gameplay mask needs evidence that its bytes cannot affect gameplay.
- **Measure / two PCs:** force known RDRAM/IOP/cycle differences, test each declared covered field and worker
  backlog/ring wrap, report detection delay and main-thread wait time. Local tests can validate hashing;
  **two PCs required** for cross-machine detection and its actual frame-time cost.
- **Safe here:** coverage map, ownership audit and diagnostic format. Hash algorithms/workers still need build/run.

## 11. Hitches at session start

- **T5DR:** external start lets each game boot/load before the ready barrier (`T5 docs/NETPLAY.md:95-106`).
  It still reported shader work, about 22 pictures per side/match and a first-Fight stall of 320 ms in one run
  (`T5 docs/ROLLBACK.md:2583-2586`). Do not describe its startup as hitch-free.
- **T4:** handshake/RTT sampling, lockstep input priming and deadline rebase are explicit
  (`runtime/tekken4_rollback_overrides.cpp:1543-1582`). The separate boot delay reduced peer waits from
  411/427 to 0-5 (`docs/ROLLBACK_PHASE3B.md:65-68`), but boot still locks step through frame 600. Ring slots
  start empty (`runtime/tekken4_rollback_overrides.cpp:1898-1901`); first full captures/allocation may hitch
  (inference, **not measured**).
  `docs/PERF.md:40-47` reports stage-load EE work and menu latch jitter, but no first-use shader compilation
  in that T4 renderer. Do not assume T5DR's shader cause applies here.
- **Next / gain (inference):** measure handshake, allocation/first-touch, boot, first stage and first fight
  separately; preallocate/warm host resources before the ready barrier if they are the cause. Keep MPEG/IPU
  outside rollback until its state is supported; a fixed frame-600 assumption needs a slow-load test.
- **Determinism risk:** low for host buffer reservation; high for moving the simulation start, skipping movie
  frames or entering rollback while an unsnapshotted decoder is active.
- **Measure / two PCs:** cold/warm command-to-ready/FIGHT times; first capture of each slot; first-present
  p99/max; mismatched loading speeds and dropped handshake packets. Local profiling is useful; **two PCs
  required** for asymmetric ready/start behaviour.
- **Safe here:** phase timeline and profiling plan. Prewarming or changing the boundary is unproved without a run.

## 12. Rematch without a game boot

- **T5DR:** select runs in lockstep and documented rematches reached FIGHT START 1.8-5.7 s after command with
  matching winners/hashes (`T5 docs/ROLLBACK.md:1874-1880,1925-1928`), on its local harness.
- **T4:** the scripted phase-3 path reaches another match through game menus
  (`docs/ROLLBACK_PHASE3.md:9-10,107-110`). That does **not** implement lobby rematch: process mode has no
  rematch in the running games (`docs/LOBBY.md:75-77`).
- **Next / gain:** add a confirmed-end -> synchronized select/rematch flow with fresh match identity and
  cleared score/input history as appropriate. Saves a repeated ~20 s boot/menu setup; no T4 time saving measured.
- **Determinism risk:** high: stale KO/score, held START, differing select state or unsynchronized reset.
- **Measure / two PCs:** ten or more consecutive rematches, fighter/stage changes, delayed commands, KO undo,
  hash agreement and command-to-fight time. One-PC smoke tests possible; **two PCs required** for acceptance.
- **Safe here:** state machine and reset checklist only. Needs mapped US game state and a real build/game run.

## 13. Persistent game across opponents

- **T5DR:** session begin/end use a new socket/session id/nonce and configuration overlay; threads follow the
  new socket (`T5 docs/NETPLAY.md:108-125`). Rollback reset clears history, sound/cuts, bypass, pacing, stats
  and display margin (`T5 src/rollback/rb_net.cpp:519-551`). Warm-versus-fresh testing reported 5/5 matches
  without mismatches (`T5 docs/ROLLBACK.md:1568-1570`).
- **T4:** `docs/LOBBY.md:75-77,127` explicitly leaves this open. The transport API has start and bye, without
  equivalent reusable session begin/end/reset (`runtime/tekken4_net.h:56-111`); rollback/hash workers and
  histories live for the process. Rematching one opponent is a smaller feature than changing opponents safely.
- **Next / gain:** idle between sessions and rebuild all per-session state while retaining the booted game.
  Removes reboot per opponent and may retain warm resources (inference). Reset hash-worker ownership before
  destroying/reusing ring slots; reject old key/session/nonce traffic and old result files.
- **Determinism risk:** high: host state outside snapshots, old jobs/packets, sound flags and warm heap/load state.
- **Measure / two PCs:** alternate warm/fresh players, change ports/keys/seed, fail during resim or hash work,
  reconnect to another peer; compare outcomes/hashes with cold sessions and watch memory growth.
  **Two PCs required** for acceptance; local reset tests are preparatory.
- **Safe here:** lifecycle/ownership specification. Implementing lifecycle cannot be validated in this copy.

## 14. Direct fight from lobby selections

- **T5DR:** external fight start establishes a ready barrier, identical frame counters/input ring and seed;
  repeated calls synchronize subsequent fights (`T5 docs/NETPLAY.md:95-106`; `T5 src/netplay/netplay.h:219-244`).
- **T4:** menu-driven VS remains the route; roster/stage ids are placeholders and direct fight is missing
  (`docs/LOBBY.md:20-21,75-77,126-127`; `docs/ROLLBACK_PHASE3.md:215-217`). No direct-fight addresses were
  discovered or verified in this review.
- **Next / gain:** map US fighter/stage/round settings and a safe ready boundary; validate the complete selected
  setup on both peers before play. Removes repeated menu navigation and prevents lobby selection/actual fight
  disagreement. Benefit is expected, not a measured T4 startup improvement.
- **Determinism risk:** high: incomplete initialization, wrong stage ids, RNG, loaders or counters can diverge.
- **Measure / two PCs:** all roster/stage settings, random choices resolved once, wrong/late setup rejected,
  cold/warm starts and command-to-identical-fight hashes. Local mapping tests first; **two PCs required** for
  ready-barrier and selection acceptance.
- **Safe here:** setup schema, address questions and test matrix. Game-memory writes need real-game proof.

## 15. Fixed online state and unlocks

- **T5DR:** normalizes online save/unlocks so personal save state cannot change character selection
  (`T5 docs/NETPLAY.md:1252,1284-1314`).
- **T4:** the older reports used empty cards and left online save/unlocks open
  (`docs/ROLLBACK_PHASE3.md:107,217-219`; `docs/LOBBY.md:127`). Current source already makes all fighters and
  costumes available by default, with `TEKKEN4_UNLOCK_ALL=0` restoring game rules, without changing the save
  (`runtime/tekken4_unlock_overrides.cpp:3-14,34-43`). Both peers must match that setting; a normalized online
  profile/save policy and explicit setting enforcement remain unproved. The plan's suggestion to disable saves
  (`docs/ROLLBACK_PLAN.md:279-281`) is not implementation evidence.
- **Next / gain:** keep the existing unlock default and specify a reproducible online profile and agreed
  settings, separate from personal progress. Makes selections and cold/warm startup consistent, rather than
  relying on users manually matching cards or environment values.
- **Determinism risk:** high if save contents, file timestamps, auto-save or unlock-dependent menu paths differ.
- **Measure / two PCs:** different personal cards/progress, first boot, all unlock choices, rematch and new
  opponent; require identical online setup and no writes to personal progress. One-PC profile tests possible;
  **two PCs required** for independent-profile acceptance.
- **Safe here:** policy/schema and read-only save-path audit. Do not add saves/game data to this copy.

## 16. Game result file before ranked

- **T5DR:** reports match id, actual round score, deciding-frame hash, desyncs, frames, local fps and lost reason;
  writes a temporary file then replaces it, waiting for checked-through with a 3 s fallback
  (`T5 src/netplay/t5_hooks.cpp:994-1009,1029-1057,1072-1081`; `T5 docs/NETPLAY.md:50-93`). Its historical score
  bug is a warning: a winner byte alone does not give a round score.
- **T4:** no result file; client uses the player's answer or no result (`docs/LOBBY.md:71-73,124-125`;
  `SERVER_HANDOFF_T4.md:102-103`). `NETEND` is a harness frame limit, not a detected match outcome
  (`runtime/tekken4_rollback_overrides.cpp:1794-1799`). Ranked cannot be justified by a clean net summary alone.
- **Next / gain:** define a T4 result contract with unique match id, real rounds, confirmed deciding frame and
  compared hash, reason and incomplete/unverified status. Atomic publication must happen once per match.
  Define timeout behaviour explicitly; do not convert missing confirmation into a trusted win. Enables ranked
  integration and reliable history; it does not itself implement or validate server rating rules.
- **Determinism risk:** low for a read-only asynchronous writer; high for wrong game addresses, predicted KO
  publication or a writer blocking/mutating the simulation.
- **Measure / two PCs:** 3-2/3-1/3-0, draw/double KO/timeout, predicted KO undone, quit near KO, stale match ids,
  delayed hash comparison and write failure. One-PC schema/atomic-write tests can help; **two PCs required**
  for agreement and ranked acceptance.
- **Safe here:** concrete schema, confirmation rules and fixtures in a future authorized tooling task. Game
  outcome detection and ranked sign-off require a real build/game/lobby run.

## 17. Connection loss, handover and usable feedback

- **T5DR:** loss writes an incomplete result and persistent mode returns to idle without closing the game
  (`T5 docs/NETPLAY.md:123-125`). Its protocol has session identities/authentication/build checks
  (`T5 docs/NETPLAY.md:43-46,350-362`). T4 already shares these basic ideas; they are not absent features.
- **T4:** handshake failure continues offline (`runtime/tekken4_rollback_overrides.cpp:1548-1552`); transport
  detects timeout/BYE and logs reasons (`runtime/tekken4_net.cpp:748-788`; `runtime/tekken4_net.h:63-65`).
  The rollback loop avoids waiting once the peer is lost (`runtime/tekken4_rollback_overrides.cpp:1735-1759`).
  That is not a complete in-game cancellation/result/return flow. The documented launcher fallback can restart
  the game; real lobby game and WAN paths remain untested (`docs/LOBBY.md:66-77,134-135`). Socket-file handover
  is absent, but port handover is also T5DR's default: it is optional, not a mandatory parity fix
  (`docs/LOBBY.md:134`).
- **Next / gain:** a visible failed/lost reason and defined neutral/stop/return behaviour, no accidental trusted
  result after offline continuation, and verified direct->relay recovery. Reduces unexplained waits and restarts.
  Prefer proving current port handover before adding another socket ownership path.
- **Determinism risk:** low for feedback; high around late packets, switching session/path and publishing a result.
- **Measure / two PCs:** close each peer, timeout, build/key mismatch, failed bind, loss during KO/rematch,
  direct failure and relay transition. Check reason, wait bound, stale traffic rejection and no false result.
  Local injection tests first; **two PCs/router/real relay required** for network acceptance.
- **Safe here:** failure-state/feedback contract and log/counter audit; no server contact or runtime change here.

## 18. Saved input replays

- **T5DR:** records only confirmed two-pad inputs, periodic hashes, seeds/counters, match setups and results;
  playback uses the same simulation loop without a socket and checks hashes
  (`T5 src/netplay/replay.h:2-19`).
- **T4:** this is planned, not implemented in the inspected runtime (`docs/ROLLBACK_PLAN.md:384-386`). The
  in-game KO replay exercised by phase 3 is a different feature (`docs/ROLLBACK_PHASE3.md:9-10,107-110`).
- **Next / gain:** versioned input recording with build/setup/profile identity and a precise start boundary;
  publish only final inputs, once, even after resim. Supports match review and reproducible bug reports. Build
  replay playback before spectating so both use the same confirmed stream.
- **Determinism risk:** low for bounded, nonblocking read-only recording; moderate/high for reconstructing the
  start state or replaying files across incompatible builds. Never treat predicted inputs as final records.
- **Measure / two PCs:** replay every recorded hash and final result, multi-match/rematch files, truncated or
  edited data, incompatible build and slow disk. **One PC suffices for playback validation**; capture actual
  two-PC matches for end-to-end acceptance. File tests can use synthetic data without game data.
- **Safe here:** file format, validation rules and synthetic test design. Runtime recorder/player needs build/game.

## 19. Spectating

- **T5DR:** worker writes a live replay stream; viewer follows a growing file with a default 120-frame buffer,
  checking hashes/results (`T5 src/netplay/replay.h:103-109`). This is delayed simulation of confirmed inputs,
  not sending live player snapshots or rendering on the players' machines.
- **T4:** copied spectator code is documented as unused; day-one spectating is off
  (`docs/LOBBY.md:30-34`; `SERVER_HANDOFF_T4.md:104-105`). No T4 runtime replay-stream/viewer path was found
  in the inspected netplay/rollback code. Lobby protocol availability alone does not make spectating work.
- **Next / gain:** extend validated replay output with bounded queues and a spectator buffer. Viewers must
  never delay either player. Adds watching/streaming; no expected improvement to playing latency.
- **Determinism risk:** low to players if strictly observational; high to viewer correctness if starting state,
  confirmed ordering or catch-up is wrong. Disk/network backpressure can still hitch players.
- **Measure / two PCs:** viewer delay/underruns, matching hashes/results, slow viewer, join/reconnect policy,
  relay restart and unchanged player p99/pps with viewers. **Prefer three PCs** (two players plus viewer);
  two are useful only with viewer capacity isolated. Three games on the phase-3b GPU cannot judge performance.
- **Safe here:** stream/buffering/backpressure specification. Implementation and service integration need real runs.

## Work that is safe in this copy, and the next proof

The original comparison authorized only this document. The follow-up task explicitly authorizes small runtime
edits behind separate default-OFF switches, documented below. "Safe here" in the comparison describes its
original review scope, not validation of those edits. A source-only runtime edit is reviewable here but cannot
be declared working, deterministic, faster or audibly better without a real build and game evidence.

### Source follow-up: two small opt-in items (2026-10-30)

Both switches default OFF. Keep them unset (or `0`) for the previous runtime behaviour. New code is confined
to `runtime/`; no patches, game addresses, simulated state, hash coverage or wire fields were changed.
`kNetVersion` stays 1 because the existing packet layout and meaning are unchanged. No T5DR code was copied.

1. **Hash-worker visibility, items 1/9/10: `TEKKEN4_NET_HASH_PROFILE=1`.** In
   `runtime/tekken4_rollback_overrides.cpp`, add bounded aggregate diagnostics beside the existing periodic/final
   summaries in `rb_frames.log`: `NETHASH_PROFILE` reports collected jobs, pending peak (queued + active), queue
   wait avg/max, submit-to-collect age avg/max, slot checks, reader waits and total/max slot-call time. Slot-call
   timing starts before mutex acquisition; reader waits count slots still owned by a queued/active reader after
   acquiring the mutex. These calls were excluded from capture timing. Queue/age averages cover collected jobs;
   pending peak excludes completed jobs. Submit-to-collect is local availability, not peer desync-detection delay.
   Host clock values feed these diagnostics only. Existing reader ownership and wait predicate are retained.
   This measures a possible hitch source; it does not itself reduce copying or hash work.

   **Compile confidence:** high from source review of existing types, includes, format arguments and worker
   ownership; uncompiled. No per-job logs or growing sample storage were added. Worker timestamps/results use
   the existing job/mutex handoff; aggregate counters belong to the EE thread. Profiling can add overhead.

   **Test outside this copy:** first run the sound-on rollback self-test with `TEKKEN4_RB_MODE=test`,
   `TEKKEN4_RB_IOPSTATE=1` and `TEKKEN4_RB_TEST="start=600,every=30,depth=8,mispredict=1"`; require **0 mismatches**,
   including restore checks. The offline self-test does not exercise this netplay-only hash worker.
   Then run a sound-on pair, one game per PC, OFF/ON with identical build/seed/scripts/settings. Require zero
   hash mismatches and agreement with the offline reference. Cover depths 1/2/4/8 and repeated ring wraps; use
   `TEKKEN4_NET_HASH_EVERY=1` and desync dumps in a separate stress pass to exercise worker backlog. Verify that
   profile lines are absent OFF, queue/age/wait values are finite and nonnegative ON, reader waits remain safe
   under backlog, and covered RDRAM/IOP/cycle forced differences are still detected. Report profiling overhead
   and slot waits separately from capture averages; a short run with zero reader waits does not prove no risk.

2. **Redundant boundary sends, item 8: `TEKKEN4_NET_COALESCE=1`.** In `runtime/tekken4_net.cpp`, suppress only
   an identical `sendNow()` INPUT attempt less than 15 ms after the previous INPUT attempt. Compare the complete
   serialized packet, its length, destination and peer nonce. Immediate `setLocal()` sends, the tick retry and
   `waitRemote()` retry remain unconditional. Changed inputs, acknowledgements, hashes, lead or delay send at
   once. An identical `sendNow()` after 15 ms also sends, even if all inputs are acknowledged; skipped calls
   do not reset retry deadlines. Only the exact value `1` enables this switch. Authentication, packet redundancy
   and hash count stay unchanged. At orderly shutdown, `NETCOALESCE skipped=N` in `net.log` counts suppressed
   calls; existing packet/byte totals still count actual send attempts before simulator loss, not delivery.

   **Compile confidence:** high from source review, uncompiled. The cache is fixed-size and protected by the
   existing transport mutex. Its clock only controls transport sends, never simulated state. Fewer redundant
   attempts are an expected saving, not measured bandwidth or frame-time improvement. A suppressed duplicate
   removes one chance to recover a lost packet early, so loss and stalls need particular attention.

   **Test outside this copy:** first run the same rollback self-test at **0 mismatches** (this transport switch
   is inactive in offline test mode). Then run a pair OFF/OFF, ON/ON and ON/OFF, with fixed seed/input delay and
   sound on. Require zero peer/reference hash mismatches, unchanged final inputs/outcomes, and no new stalls.
   Capture keyed/unkeyed INPUTs: changed ack/hash/lead/delay and every new local frame must send immediately;
   unchanged boundary duplicates within 15 ms may disappear, while tick/wait retries and later `sendNow()`
   recovery still send. Include a lost final ack/hash, burst loss, jitter/reorder, ring wraps and peer address
   changes. Compare attempted packets/bytes, simulator drops, resends, depth and fight p99; ON changes the
   simulator's send sequence, so an equal simulator seed does not mean the same dropped packets. Repeat on
   direct LAN/WAN and forced relay before claiming a player benefit.

Stopped here: deeper render/IOP cuts, snapshot representation, hash narrowing, pacing/margins and audio queues
need measurements and runtime proof. Pause/confirmed KO, rematch and direct fight need verified game-phase
addresses; none were guessed. Wire changes, hash trimming and new negotiation are left out. Only static review
and whitespace checks were possible here; a real combined build and the self-test then pair remain required.

The maintainer's next acceptance pass should keep one declared combined build/settings identity and separate:

| Pass outside this copy | What it can prove | What it cannot prove alone |
|---|---|---|
| Static review / synthetic packet, result, replay fixtures | sizes, schemas, ownership/rules under stated assumptions | game state addresses, pacing, sound or working netplay |
| One game, offline reference and rollback self-test | capture/restore and resim fidelity for exercised inputs; component cost | cross-PC agreement, WAN behaviour or human experience |
| One game per PC, direct LAN with controlled impairment | actual fight p99/repeats, depth, time sync, device audio, outcomes | real NAT/relay route; every CPU/display combination |
| Two independent PCs over WAN and forced relay | deployment path, limits, failure/recovery and end-to-end match flow | universal hardware support or untested states |
| Cross-vendor PCs, all stages/roster, repeated rematch/new-peer sessions | much broader determinism/lifecycle evidence | a mathematical proof for all inputs |
| Two players plus separate spectator capacity | viewer correctness/lag and player overhead | safety at unlimited viewers without load testing |

Keep the phase-3b fight target of p99 <=20 ms and near-zero fight input waits as a stated target
(`docs/ROLLBACK_PHASE3B.md:16`), plus repeated-picture counts and correction age. Separate intentional whole-tick
time-sync holds from unexplained stalls; publish both. Do not hide first-fight/load/KO/rematch hitches by pooling
them into an average or omitting them from the report. Record test duration, stage, inputs, audio/device path,
RTT/jitter/loss/reorder, GPU load, build identity and hash coverage alongside every result.

The current evidence supports a functioning deterministic local rollback prototype with substantial phase-3b
improvements. It does not yet establish T4 rollback equal to or better than T5DR for two human players. The
highest-value missing proof is the current T4 build running one game per PC; the largest code opportunities
then depend on that profile, followed by confirmed game rules and the session/result features above.

## Owner-authorized MIT port pass (2026-10-30)

This section supersedes the earlier source-work stopping point. The owner explicitly authorized reading
`C:\OpenRecomp-work\T5DROnline-Source` and porting its MIT code. That tree was read only. Its
`docs/ROLLBACK.md`, `docs/NETPLAY.md` and `docs/DIRECTFIGHT.md` were reviewed by area, including their later
bug fixes. Full MIT notices are at the top of both receiving transport files. The new profiling and audio
code is original T4 code. All new code is in `runtime/`; no patches, addresses or game data were added.

Four source items changed. Every new switch defaults OFF and requires the exact value `1`; unset, `0` and
`01` retain the old selection. None of the changes puts wall-clock values, host state or thread timing into
simulated state. Profiling clocks feed logs; RTT selects a transported delay before input priming. This is
source work, not proof that rollback equals T5DR. No build, game, test executable or network session was run.

### Item-by-item outcome, in plan order

"High, uncompiled" means separate source review found the types, includes, format arguments and ownership
consistent with this copy. It is not compiler evidence. A dash means no new implementation to compile.
Tests below are instructions for the maintainer outside this copy, not reported results.

| Item | Outcome and switch | Compile confidence | Test to run |
|---|---|---|---|
| 1. Headroom | Profiling done; optimization/drain parity not done. New `TEKKEN4_NET_COST_PROFILE=1`. | High, uncompiled | Sound-on self-test, then two PCs OFF/ON, depths 1/2/4/8, all stages; compare hashes, component costs, actual presents and profiling overhead. |
| 2. Resim cuts | Deeper cuts not done; existing draw/present/VU1 and optional upload retained. No new switch. | — | Map complete draw functions first; cut/no-cut resim comparisons plus HP bars, shadows, camera, GS readbacks and KO undo. |
| 3. Cross-machine correctness | Strict HELLO source change done; cross-machine proof pending. New `TEKKEN4_NET_STRICT_HELLO=1`. | High, uncompiled | Matching/nonzero builds, missing/mismatched builds, forged HELLO/REJECT, reordered/lost handshake; then Intel/AMD, direct/WAN/relay. |
| 4. Pause/predicted KO | Not done: verified T4 phase/decision map missing. No new switch. | — | Map phases, then both pads START in fight/menus, KO undo, double KO, timeout and quit beside KO. |
| 5. Sound | No-cut/drawn-tail output mute fix done. New `TEKKEN4_RB_AUDIO_TIMELINE=1`. Selective corrected starts not done. | High, uncompiled | Sound-on wrong-input self-test, cuts default/none/draw+VU1, depths 1/2/4/8; WAV samples and two-PC playback. |
| 6. Input delay | Matching-setting negotiation done. New `TEKKEN4_NET_DELAY_MATCH=1`; ranked policy not done. | High, uncompiled | Equal/unequal/auto settings, RTT boundary vectors below, missing RTT; taps, stalls and fixed delay during RTT drift. |
| 7. Time sync | Existing trimmed estimator/hold/early rollback retained; new display margin/tick skips not done. No new switch. | — | Two independent displays: lead/hold, actual presents/repeats, correction duration, latency and equal-load OFF/ON comparisons. |
| 8. Packets | Audit done; existing `TEKKEN4_NET_COALESCE=1` retained, no new change. | Existing source only, uncompiled | Existing OFF/OFF, ON/ON, mixed test above; lost final ACK/hash, loss/reorder, actual direct/relay captures. |
| 9. Snapshots | Inventory/audit done; representation change not done. No new switch. | — | Full/incremental sound-on verification, ring wraps, depth 1/2/4/8, load/KO/rematch and worker backlog. |
| 10. Hash/RNG | Coverage/reseed audit done; no new masks or reseeds. Existing hash-profile switch retained. | — | Force differences in declared covered fields; broad restore tests and cold/warm/all-stage RNG caller traces. |
| 11. Startup | Slow-load/drain audit done; safe phase-based start not done. No new switch. | — | Unskipped/restarted movies and asymmetric loading beyond frame 600; verify no active decoder at first rollback. |
| 12. Rematch | Not done: game phase/select map missing. No new switch. | — | After mapping, 10+ rematches, skewed commands, mirror picks, mashing, slow loads, KO undo and aborts. |
| 13. Persistent game | Not done: transport/hash lifecycle and canonical warm state missing. No new switch. | — | Warm/fresh/new-opponent cycles, changed ports/keys/seeds; disconnect in resim/hash work, memory/socket/worker growth. |
| 14. Direct fight | Not done: committed selection/stage/mode/ready fields missing. No new switch. | — | Map every selection and safe boundary locally; two-PC wrong/late setups, random picks and asymmetric loads. |
| 15. Online state | Not done: card isolation/profile policy and effective unlock agreement missing. No new switch. | — | Different personal progress/options, isolated online profiles, both unlock settings, cold/warm/rematch/new peer. |
| 16. Result file | Not done: actual scores/decision and exact compared-hash receipt missing. No new switch. | — | Real 3–0/3–1/3–2, draw/timeout/KO undo, late comparison, quit, stale IDs and write failure. |
| 17. Loss/fallback | Failure/close audit done; safe cancellation/result/return not done. No new switch. | — | Failed bind/handshake, peer quit/kill, close during wait, silent and alive-but-stalled peer, slow load and relay fallback. |
| 18. Replays | Not done: canonical start/setup and playback missing. No new switch. | — | Synthetic malformed/truncated files, every-hash one-PC playback, multi-match end boundary, slow disk; two-PC captures. |
| 19. Spectating | Not done: validated replay stream/viewer missing. No new switch. | — | After replay validation, three PCs: join/refill, rematches, slow viewer/disk, late hashes, relay fallback and player overhead. |

### The four changes and their acceptance checks

**Item 1, cost visibility.** `NETCOST` lines in `rb_frames.log` use fixed-size quarter-millisecond histogram
buckets through 64 ms and one overflow bucket. They report count, mean, p50/p90/p99 upper bounds and max
for boot/live/cut/tail EE busy time and GS/VIF/VU/IOP counters, capture, restore and whole rollback.
Overflow quantiles report the observed maximum. Component timers nest/overlap: do not add them. EE busy is
the existing host estimate, which may include OS descheduling. "Boot" means before the existing `rbStart`,
not a verified game phase. Capture still excludes hash-reader waits; use `NETHASH_PROFILE` beside it.
These are boundary/component costs, not measured displayed-picture intervals. OFF must emit no `NETCOST`;
ON must have finite nonnegative values, ordered quantiles and fixed storage. No speedup is claimed.

The baseline already has early rollback and lazy captures. T4's EE guest threads are cooperative and its
IOP/kernel state is serialized. Patch 44 retains drains for guest-readable GS paths; a blanket output-worker
drain could restore historical 5–7 ms waits. T5's side-thread manager addresses and semaphore writes were not
ported. Prove that no host worker can write restored memory before changing a capture/load boundary.

**Item 3, strict HELLO.** Strict mode requires equal nonzero build IDs, opposite pad slots, nonzero nonce,
nonzero host session and bounded explicit delay. Foreign-version HELLO failure, HELLO restarts and REJECT
handling validate the tag or expected source first. Unkeyed configured-source checks identify an IP, not
cryptographic authentication. Host recovery from a lost session echo requires a previously validated HELLO
identity; early INPUT/PING cannot bypass build validation. A host without a configured peer/key still uses
first-contact discovery. Existing handshake failure can still continue offline: item 17 remains open.

Exercise keyed/unkeyed wrong/missing tags, unexpected sources, wrong slots, nonce/session zero, delay 16–254,
INPUT/PING before HELLO, matching and mismatching IDs, and lost/reordered echo recovery. A valid mismatched
peer must fail; untrusted traffic must not cancel a strict session. Strict mode does not compare saves,
unlocks or every environment setting. Build equality alone is not complete setup identity.

**Item 5, audio timeline.** The old boundary mute used `g_frameCuts != 0`. With `TEKKEN4_RB_CUT=none`, or a
custom cut set whose drawn tail clears all cuts, it could overwrite the rollback-start mute and queue audio
from replayed frames again. The opt-in selector uses Test wrong/resim, SelfNet resim or Net resim state.
IOP/SPU2 execution and snapshot contents stay intact; the existing host output mute runs after SPU2 bookkeeping.
Test with `TEKKEN4_RB_IOPSTATE=1` and misprediction, normal cuts, `none`, and `draw,vu1` with tail 1. Require
zero restore/hash mismatches and no extra samples from wrong/resim passes. With IOPSTATE=0 the new selection
has no output-mute effect. Listen on both PCs for music seams, late/missing sounds, crackle and underruns.
Already-heard wrong sounds remain irreversible; this is not a claim of perfect corrected audio.

**Item 6, agreed delay.** Equal explicit settings 0–15 win. Otherwise the host uses measured median RTT:
1 through 60 ms, 2 through 150, 3 through 250, 4 above; missing RTT selects 2. The joiner follows that pick
before input priming. Negative API settings normalize to auto; values above 15 clamp to 15 before HELLO.
The host retains its decision on repeated agreement calls. This adapts T5's equal-setting policy while
retaining T4's high-RTT auto floors; it does not implement T5's separate casual/ranked/lobby policy layers.
Equal explicit settings can override auto floors. Delay stays fixed for the session.

Wire compatibility is deliberately separate for every combination, with unchanged packet layouts:

| Strict HELLO | Delay match | Effective `kNetVersion` selection |
|---|---|---|
| OFF | OFF | 1, original `kNetVersion` |
| ON | OFF | 2, `kNetVersionStrict` |
| OFF | ON | 3, `kNetVersionDelayMatch` |
| ON | ON | 4, `kNetVersionStrictDelayMatch` |

There is no automatic downgrade. Mixed versions must never reach input priming; a strict discovery host
without a trusted source may wait for the connection timeout rather than accept a foreign-version failure.
Test all pairs of combinations. Test equal 0/0, 1/1, 15/15; unequal 1/2 and explicit/auto; RTT
59/60/61, 149/150/151, 249/250/251 ms and no samples. Verify OFF preserves host precedence. The 1 ms tap
latch already exists: verify keyboard/Raylib/XInput taps, stalls and resim without consuming a tap twice.
T4 has no phase-based mid-fight lockstep windows. Keep boot lockstep and the prediction-history safety wait;
do not import T5's obsolete phase windows or its old two-second wait-then-predict behavior.

### T4 discovery required before the remaining behavior changes

Known addresses below are tracing anchors from this T4 source, not new runtime writes. No T5 address was
carried over. The maintainer must perform these probes in the real SLUS-20328 game, outside this copy.

1. **Draw cuts (2).** Existing T4 packet-builder/end routines, including `FUN_00233b60`, are not proven safe
   whole-function draw cuts. Use `TEKKEN4_STACKPROF`, lifted US function callers and VIF/GIF buffer-write
   traces to classify complete functions, return contracts, memory/RNG/loader effects and GS readbacks.
   Preserve render begin/end pairing and full function epilogues. T5's HP-drain update fix (`ROLLBACK.md`
   section 35) proves a clean gameplay hash does not validate HUD animation. Do not mask unexplained differences.
2. **Phases, setup, pause, scores (4/12/14/16).** Start from `FUN_00196940` / `FUN_001969f8` and the documented
   VBlank boundary (`ROLLBACK_PHASE01.md:44`). Align traces through title, each select, loading, intro, READY,
   fight, START pause/resume, KO slow motion/replay, next round, final pose and return to select. Follow field
   writers to establish widths, side strides and resets. The known roster table `0x0030e100` has 112 entries
   of 28 bytes: u16 fighter at +0, u16 costume at +2, availability callback at +24 (`tekken4_unlock_overrides.cpp`).
   Trace `FUN_001e2da0`/`FUN_001e2cc0` callers at each player's confirm to find committed selections; table
   metadata is not committed battle state. Trace stage confirm into resource loading to replace lobby
   placeholder IDs. Find actual two-side round counts with 3–0/3–1/3–2, timeout and double KO. Verify stale
   decision flags clearing into rematch and pending mode teardown; never infer scores from a winner byte.
3. **Ready/load/drain (9/11/13/14/17).** Host MPEG decoder state is outside snapshots (patch 63); the fixed
   frame-600 threshold is unproved with slow movies. Trace MPEG creation/deletion and T4 movie RPC open
   `0x3000`, read `0x3200`, close `0x3100` in `tekken4_overrides.cpp`. Establish no active decoder or pending
   movie I/O before rollback. The runahead-only quiet heuristic is not a rollback-safe completion query.
   Trace actual loader queues, completion tokens and any host writes. Timeout ends a session; it never means
   a partial load has completed. T4 already snapshots emulated semaphore state, unlike T5's native semaphore
   token bug; do not add PS3 token repair writes. Stress full/incremental RDRAM verification with
   `PS2X_RB_INCREMENTAL=0/1` and `PS2X_RB_WW_VERIFY=1`, sound on and repeated ring wraps.
4. **RNG and hashes (10).** Source-backed `srand=0x002a2528`, `rand=0x002a2538`, `_impure_ptr=0x00304b94`,
   generator at pointee +88, scene caller `FUN_0020e090`/return `0x20e0cc` are tracing anchors. Current
   `loggedSrand` XORs the negotiated seed only when the game calls it; it is not an explicit sync-point
   reseed. `TEKKEN4_RAND_SEED` bypasses that hook. Trace all RNG state/callers across cold/warm loading and
   identify a ready boundary before the first intro draw. Never use host-timed draws for gameplay.
   Normal network hash covers all RDRAM, scratchpad, VU0 data, selected IOP state and EE cycle. VU1/GS output
   omissions follow the cut policy. EE context/scheduler/device fields, VU code/interpreter state and much
   saved IOP kernel/device/SPU2 state are coverage limits, not proven cosmetic exclusions. IOP hash includes
   RAM, sample RAM, selected emulator/thread scalars and sound cycle, not the complete IOP snapshot.
   Keep broad restore checks. T5's camera and alleged timestamp exclusions hid sidestep/RNG feedback
   (`NETPLAY.md` desync hunts); none were imported.
5. **Online profile (15).** `TEKKEN4_UNLOCK_ALL=0` alone disables the existing unlock override; agreement is
   still missing. Availability callback `0x001ec350` and profile `0x0036c2b8+0x60+fighter` are unlock evidence,
   not fixed-online-state evidence. Trace mapped SDK calls `sceMcOpen=0x2947e0`, `Read=0x294b70`,
   `Write=0x294c90`, `Sync=0x294e80`, `GetInfo=0x294fb8`, `GetDir=0x2951b0` from `config/analyzer_seed.toml`
   and `function_map.csv`: paths, caller PCs, read destinations and asynchronous completion. Locate every
   option copy, including repeated in-fight copies. No public card-path setter was found. Normal launcher
   storage uses the player's SAVE_DIR; isolate online storage before profile load through supported storage
   integration. T5's difficulty/time and unlock-grid desyncs show why agreeing only a build or one byte fails.

### Session, result and replay contracts still to implement

These are specifications, not dormant features or switches. Future behavior needs separate default-OFF
`TEKKEN4_` gates, new switched wire versions where needed, and a separate review.

- **Pause/rematch (4/12):** apply symmetric input rules after both pads are exchanged on every live/resim
  boundary. Preserve menu controls. Confirm the deciding input prefix before pad holds/skips/results; undo
  pending actions if rollback removes KO. Do not wait for the entire moving live state to become final.
  Require a fresh decision transition, and rematch readiness for the locally driven side. T5's stale decision,
  predicted-START pause, same-character skewed-command deadlock and select-reinitialization heap leak
  (`DIRECTFIGHT.md` rematch/select restart sections) must not recur. Keep the session but give each match a
  fresh identity/setup; reset input/hash epochs only through a synchronized protocol.
- **Persistent sessions (13):** current `start()` returns when already on; detached RX/tick/simulator workers
  never stop, and `bye()` does not close/reset the transport. The hash worker reads snapshot slots outside
  its mutex under ownership. Stop submissions and drain queued/active readers before touching the ring;
  use session generations for late completions. Wake/join or safely park socket workers, close the old socket,
  discard delayed packets, and clear keys/nonces/RTT/history/lead/delay/results/cuts/mute/pacing. A new session
  requires fresh identity and a proven canonical guest re-entry state. Whole-RDRAM/EE-cycle hashes mean warm
  versus cold differences cannot be dismissed by importing T5 boot ranges or masks.
- **Direct fight (14):** negotiate version/build/match identity, actual fighter/model/costume/stage, rounds,
  seed and online profile/options identity. Resolve random choices once. Both peers validate/acknowledge
  setup and reach a verified ready boundary before synchronized counters/RNG/input epoch begin. Never
  invent an opponent pick on timeout or copy live loader queues into a reusable boot image.
- **Result file (16):** versioned match/session/build/setup identity, actual scores, deciding boundary/hash,
  match-local mismatches, `verified|unverified|incomplete`, nullable winner and explicit reason. Require the
  corrected confirmed deciding prefix and an exact equal-hash receipt for that boundary. Transport `checked`
  skips sparse and aged-out absent hashes; it is NOT proof of comparison. Add an exact receipt and pin the
  deciding hash. Timeout/missing comparison/quit yields no trusted winner. Bounded host writer and atomic
  replace once per match; write failure cannot affect simulation. `NETEND` remains a harness limit.
- **Loss/closed window/fallback (17):** handshake failure currently continues offline; peer loss bypasses the
  wait and can keep predicting. An alive PINGing peer without input progress can wait indefinitely. Existing
  window-close code requests runtime stop, but blocking handshake/input waits lack an exposed stop predicate.
  A future cancellation path must stop simulation at a boundary, release workers safely, and retain a known
  confirmed result or emit incomplete/null winner. Distinguish bind/build/rejection/no-peer, quit/silence,
  input stall, start/load timeouts and local close. Authenticated load-progress signaling must precede a
  progress watchdog; a slow loader is not automatically a stalled peer. No abrupt process-exit workaround
  was added. Direct-to-relay fallback must not resume an ended match or reuse stale identity/results.
- **Replay (18):** T5's replay path excludes boot-through-menu sessions (`REPLAYS.md:267–268`), T4's current
  route. First prove canonical setup/start/barriers and playback. Then record final raw P1/P2 inputs with a
  monotonic cursor after pending corrections resolve; do not serialize predicted `g_np.inputs`. Header needs
  T4 magic/version, build/effective wire/settings/profile identity, seed/delay/hash coverage and start identity.
  Records need bounded lengths, setup/barriers/RNG/counters, ordered two-pad frames, final hashes/results,
  completeness and LAST actually executed frame. T4 axes are `rx,ry,lx,ly`; do not copy T5 column order.
  Future delayed inputs are not executed frames. Slow disk/full queue makes recording incomplete and stops
  it without blocking players. Validate truncation, ordering, integer bounds and incompatible identities.
- **Spectating (19):** build on validated replay with SESSION/INPUTS/HASH/BARRIER/MATCH/LAST/END records and
  bounded worker queues. Viewer waits/refills (T5 uses 120 frames), players never wait. Join from session
  start until independently complete rematch start state is proved; fast catch-up is unproved. Bound record,
  decompression, session and per-viewer storage. Host timestamps stay diagnostic. Preserve stream identity
  across pre-handshake relay fallback; do not publish false END for a replaced attempt.

### Review, proof still needed and agents

Separate reviewer `review_early` reviewed the source changes for compile issues, determinism, switch defaults,
wire compatibility and license notices. Its two HELLO recovery findings were fixed: strict build validation
and matching-delay preference negotiation can no longer be bypassed by early INPUT/PING recovery.
Separate reviewer `review_final` passed the final combined code/documentation diff with no must-fix findings.
Both reviews cover every changed item; deferred items have no code diff. Static/whitespace review is the only
verification performed here; compiler, linker, patched-runtime API compatibility and runtime behavior remain
unproved. Nothing was committed or written through git.

**A running game is required** for draw/phase/score/pause/selection/stage/load/RNG/profile discovery, sound
WAVs/listening, broad snapshot checks, cost measurements, canonical replay starts and safe warm transitions.
**Two physical PCs are required** for cross-machine determinism, actual direct/WAN/relay behavior, delay and
display fairness, late-input KO undo, two-endpoint sound, rematch/session/outcome acceptance. Use independent
displays and sound devices with rendering headroom. **Three PCs are preferred** for spectator overhead.
Do not claim faster resim, trusted ranked results or feature parity until those tests pass.

Area agents: `item01_headroom`, `item02_cuts`, `item03_negotiation`, `item04_pause`, `item05_audio`,
`item06_delay`, `item07_timesync`, `item08_packets`, `item09_snapshot`, `item10_hash`, `item11_startup`,
`item12_rematch`, `item13_persistent`, `item14_directfight`, `item15_online_state`, `item16_results`,
`item17_loss`, `item18_replay`, `item19_spectating`. Each owned one plan item; only the designated owner edited
each runtime file, with sequential ownership transfers. Unimplemented items received read-only audits.
