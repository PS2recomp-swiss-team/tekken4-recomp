# T4 beta progress, 2026-11-03

## Current: bound the settling hold by its nominal wall duration

Latest supplied real verify finished 2026-11-03T01:30:39. SYNC_GAP_RESET
really acted: host/join resets 298/173, discarded samples 2938/1483. Yet
rollbacks are 257/1016 (3.95x), replay frames 461/4045 (8.77x), mean depth
1.79/3.98. Aggregate 1273 rollbacks and 4506 replay frames. Expiring old
windows did not remove the imbalance; keep GAP_RESET default-off. OFF host
is truncated, so no complete controlled OFF/ON aggregate conclusion follows.
Join excess stall+sync is 3488 ms, host excess rebase 3483 ms: coupled timing
accounting, not evidence of the initiating side. Active new counters show
changed runtime behavior despite a historical repeated build ID; exact
reviewed/executed bytes remain unproved.

Done: 24 independent area agents read AGENTS.md/current progress. Safe
in-tree inventory found eight .log files, all ZIP/scanner evidence; latest
verify pointers contain no paired runtime chronology. Unique first arrivals,
advantage sequence and first-wait order remain UNKNOWN. No outside folder
was opened. No fixed role/sign/publication/ACK/snapshot defect established.
Positive advantage estimates the peer being paused AHEAD. Replay can delay
its next local publication, but source opportunity is not causal chronology.

One new hypothesis: the post-correction settling hold counts live frames,
although its nominal duration includes RTT wall time. Replay/producer gaps
consume wall time without advancing those frames and can prolong controller
blindness. FAST_SYNC changed refill length; GAP_RESET cleared old samples;
CAP_ONE shortened pauses while retaining this hold. Those did not test wall
expiry. The original frame hold may intentionally require input progression:
elapsed RTT alone does NOT prove that fresh peer feedback has propagated.
This is an experiment, not a proved cause or release fix.

Changed runtime/tekken4_rollback_overrides.cpp behind literal default-off
TEKKEN4_NET_SYNC_WALL_HOLD=1. After a correction ends, record a steady-clock
deadline: sleepEnd + (tsHold - correctionFrame) * 16667 us, using the original
hold count unchanged. ON admits a sample if the original frame hold OR wall
deadline expires. It only shortens an overlong hold; it cannot extend the
original frame guard. tsFrom, 20-sample filter, trimmed mean, thresholds,
ten-frame correction spacing, pause size, replay order and input/wire policy
are retained. Deadline and sample flags are host-only, outside guest restore.
OFF uses the original sample guard; both arms add observations and logging
cost, with no zero-overhead claim.

Both arms append NETSYNCHOLD to retained NETSUMMARY: sync_wall_hold, time_sync,
eligible_visits (wall expired while f < tsHold), released_holds (distinct ON
holds admitting early), early_samples, window_evals and window_corrections
(windows containing an early sample). The flags follow ring replacement and
refill; pending replay corrections retain their selected window count.
DIAG=1 logs NETSYNCHOLD_SET (correction end, nominal deadline, frame hold),
NETSYNCHOLD_SAMPLE (eligible visits, admitted flag, lead/frontier), and
NETSYNCHOLD_EVAL (early-sample window, filtered advantage). These are not
unique arrival timestamps. A flagged window can still trim its early sample
or choose the same action: counts do not prove a numerical counterfactual.

VERIFY_ENV.txt is exactly one ASCII line plus LF, no BOM:
TEKKEN4_NET_SYNC_WALL_HOLD=1

Open / owner-only REAL-ENTRY TEST: stage/build these exact reviewed runtime
bytes and run actual paired Mode::Net games OFF/ON through the external
verify wrapper. Forward VERIFY_ENV.txt explicitly through -Env for ON;
net_pair clears inherited settings and does not read this file itself.
Common BOTH arms: DELAY=3, LOCKDELAY=7, DIAG=1, LOCALPAD=0 (all with
TEKKEN4_NET_ prefix), RBSTART=600, TIMESYNC=1, normal 20-sample filter,
RB_MODE unset/net, RTT150/jitter5/loss3, 6000 frames and matching workload/
foreground conditions. Keep GAP_RESET, CAP_ONE, FAST_SYNC, FULL_SYNC,
SUBFRAME_SYNC, REPLAY_BEFORE_SYNC, REPLAY_BATCH, ATOMIC_INPUT,
SIM_NORMAL_PRIORITY, SIM_SAFE_WAIT, LIVE_LEAD, ORDERED_LEAD, REFRESH_RC,
SEND_FIRST, REBASE_CATCHUP, EARLY_DEADLINE, PRED_HEADROOM and other experiments
equal/off. Retain effective settings and full paired rb_frames/transport
logs, stdout/stderr and timings. Reviewed/staged runtime SHA-256 must match;
refresh identity after staging, clear explicit BUILD overrides, retain build
success and each launched executable SHA-256. Identity hashes staged inputs,
not executable bytes. Equal seeds do not control per-input delivery history.

Require OFF sync_wall_hold=0 and released_holds=early_samples=window_evals=
window_corrections=0. Require ON literal banner, sync_wall_hold=1,
released_holds>0, early_samples>0 and window_evals>0; otherwise it has not
exercised the proposed controller mechanism. SAMPLE admitted=1 requires
f<hold_until and steady_ms>=deadline_ms (display values rounded). SET deadline
uses the original post-sleep nominal frame duration. Inspect actual windows
and correction events; window_corrections>0 is stronger exposure evidence,
not benefit proof. Compare publication/frontier gaps, advantage and first
recorded waits in paired logs. Existing logs still miss unique arrivals.
Success requires lower absolute combined replay/depth with acceptable lead,
stalls, total waits, FPS and frame tails. Reject benefit only from worsening
the other peer or added lead/stalls. Require zero hash mismatches/NETDESYNC;
repeat same roles, swap roles, then two physical PCs. Default remains OFF.

Ran: tests_catalogs invoked actual tools/check_online_catalogs.ps1, exit 0:
both 23-tool catalogs, three root inputs and Host/Join dependencies present.
Source inventory only. Test and SelfNet dispatch to different boundaries;
neither exercises paired npBoundary. Root checked exact env bytes and source
diff against retained originals. Compilation, activation, safety and benefit
are UNRUN: AGENTS.md forbids builds, games and tools/net_* here. No changed
runtime entry ran. This has NOT met the requested real-entry-test requirement;
only the owner's actual paired verify can close it. Release acceptance OPEN.

Original bytes of the three changed files are retained under
logs/runtime-sync-wall-hold/originals. Root alone edits runtime/progress/env;
all area agents are read-only. No Git command, outside-tree access, deletion,
patch edit, build, game, forbidden helper, server, push or release occurred.

Area agents: pair_logs, verify_metrics, advantage_sign, sync_filter,
prediction_cap, vblank_pacing, input_sampling, publication_guard,
transport_send, transport_receive, resend_coalesce, arrival_observability,
simulated_network, early_replay, replay_scheduler, snapshot_state, hash_locks,
startup_roles, switch_history, build_identity, tests_catalogs, experiment_design,
runtime_entry_route, fresh_feedback. Separate final_diff_review_wall_hold
completed the final three-file review with no blocking source issue. It
independently verified OFF guard, correction-end deadline, ring refill/reset,
pending metadata, chrono/printf plausibility, exact env bytes, unchanged
history suffix and runtime SHA-256. No compilation or runtime proof follows.

Reviewed runtime SHA-256: 6dc64f11029414f7d036f99e747ed04895b44e8ba7a7f7997c7fb2ee4db2197c

# T4 beta progress, 2026-11-03

## Current: expire time-sync feedback after a long live-frame gap

Latest supplied real verify finished 2026-11-03T01:13:56. SYNC_CAP_ONE really
acted: join changed 53 corrections, reducing requested pauses from 3666.740
to 1516.697 ms, max 16.667 ms. Yet ON host/join rollbacks are 286/1019 (3.56x)
and replay frames 489/3706 (7.58x), aggregate 1305/4195. Mean depths are
1.71/3.64. Large pause size is insufficient to explain the imbalance. Keep
cap-one default-off. OFF host is truncated; no controlled aggregate benefit
or regression is established. Join stall+sync 3492.850 ms and host excess
rebase 3461 ms fit coupled pacing accounting, not an initiating cause.

Done: 24 independent read-only area agents read AGENTS.md/current progress.
Safe in-tree inventory again found eight .log files, all ZIP/scanner output;
no paired runtime arrival/advantage/wait chronology. First unique arrivals,
advantage sequence and first-wait order remain UNKNOWN. No fixed role/sign,
publication index, ACK, snapshot or scheduler-restore defect was found.
Positive advantage estimates the waiting peer AHEAD. Do not invent chronology
from totals. Latest switch activation disproves the inference that a repeated
historical build ID necessarily means no runtime changed; exact executed
bytes remain unproved. Identity hashes staged modules, not executable bytes.

One new hypothesis: a long replay/producer interruption leaves the 20-live-
frame time-sync window holding feedback from before the interruption. Its
next evaluation can mix different producer phases and select an obsolete
correction. Source has no wall-age expiry. This is a source-supported
opportunity, NOT a demonstrated cause. FAST_SYNC already tried a shorter
window; this experiment retains the normal length and resets only at gaps.
A later pacing-guard reset would miss the current evaluation, so this check
runs at npTimeSync before sampling/evaluation, once per new live frame.

Root changed runtime/tekken4_rollback_overrides.cpp behind literal default-off
TEKKEN4_NET_SYNC_GAP_RESET=1. In time-sync-enabled evaluations at/after tsFrom,
a steady-clock gap strictly >50 ms from the preceding live sync visit clears
a nonempty lead window when ON. The current sample then starts the refill;
20 fresh samples are needed with FAST_SYNC off. No added settling hold:
tsHold, lastCorrection, duration/threshold/gain, replay order, pacing and
input/wire/snapshot policy are retained. OFF leaves the filter unchanged.
Both arms add clock/counter/log overhead; no zero-overhead claim is made.
This check measures live controller visits, not individual input arrivals.

Both arms append NETSYNCGAP to retained NETSUMMARY: sync_gap_reset, time_sync,
gap_events (>50 ms eligible visits), eligible_resets (nonempty windows),
resets (actual ON clears), discarded_samples (valid entries, capped at window
length per clear), max_gap_ms (long-gap maximum), threshold_ms=50. Counts
cover all qualifying visits, including empty windows after a correction.
DIAG=1 logs NETSYNCGAP_EVENT: steady time, slot/frame, gap, samples before,
reset flag, raw mine/peer lead, frontier and existing hold. Peer lead is an
observation under its own transport lock, not an atomic paired estimate.
These observations do not recover unique input first-arrival times.

VERIFY_ENV.txt is exactly one ASCII line plus LF, no BOM:
TEKKEN4_NET_SYNC_GAP_RESET=1

Open / owner-only REAL-ENTRY TEST: stage/build this exact reviewed runtime
module and run actual paired Mode::Net games OFF/ON through the external
verify wrapper. Forward VERIFY_ENV.txt via -Env in ON; net_pair clears
inherited settings and does not read this file. Common settings in BOTH arms:
TEKKEN4_NET_DELAY=3;TEKKEN4_NET_LOCKDELAY=7;TEKKEN4_NET_DIAG=1;TEKKEN4_NET_LOCALPAD=0
RBSTART=600, TIMESYNC=1, normal 20-sample filter, RB_MODE unset/net,
RTT150/jitter5/loss3, 6000 frames, matching workload/foreground conditions.
Keep SYNC_CAP_ONE and every other experiment equal/off, especially FAST_SYNC,
FULL_SYNC, SUBFRAME_SYNC, REPLAY_BEFORE_SYNC, REPLAY_BATCH, ATOMIC_INPUT,
SIM_NORMAL_PRIORITY, SIM_SAFE_WAIT, LIVE_LEAD, ORDERED_LEAD, REFRESH_RC,
SEND_FIRST, REBASE_CATCHUP, EARLY_DEADLINE and PRED_HEADROOM. Retain effective
parameters, paired full rb_frames/transport logs, stdout/stderr and timings.
Compare reviewed/staged SHA-256, refresh identity after staging, clear BUILD
overrides and record successful build plus each launched executable SHA-256.
No build/identity refresh occurred here; equal seeds do not control arrivals.

Require OFF sync_gap_reset=0 and resets=discarded_samples=0; ON literal banner,
sync_gap_reset=1, resets=eligible_resets>0, discarded_samples>=resets, each
reset event samples_before>0 and gap_ms>=50.000 (rounded display; the branch
requires strictly >50 ms). No nonempty resets means
UNEXERCISED. Compare full paired first recorded waits, publication/frontier
gaps and advantage around reset/refill/correction sequences. Success requires
lower absolute aggregate replay/depth with acceptable sustained advantage,
stalls, total waits, FPS and frame tails. Fewer sync corrections alone is
not success: frequent resets can starve this controller. Reject increased
lead/stalls/repeated replay or benefit obtained only by worsening the other
peer. Require zero hash mismatches/NETDESYNC; repeat same roles, swap roles,
then use two physical PCs. Default stays OFF; release acceptance stays OPEN.

Ran: tests_catalogs invoked actual tools/check_online_catalogs.ps1, exit 0:
both 23-tool catalogs, three root inputs and Host/Join dependencies present.
Inventory only. Selftest/SelfNet dispatch to different boundaries; neither
runs paired npBoundary. Root checked exact env bytes and source changes.
Compilation, activation, safety and benefit are UNRUN: AGENTS.md forbids
builds, games and tools/net_* here. No changed runtime entry ran; this has
NOT met the requested real-entry-test requirement. Only the owner's actual
paired verify can close it. No source check is represented as runtime proof.

Original bytes of all three changed files are retained under
logs/runtime-sync-gap-reset/originals. Root alone edits runtime/progress/env;
all area agents are read-only. No Git command, outside-tree access, deletion,
patch edit, build, game, forbidden helper, server, push or release occurred.

Area agents: pair_logs, verify_metrics, advantage_sign, sync_filter,
prediction_cap, vblank_pacing, input_sampling, publication_guard,
transport_send, transport_receive, resend_coalesce, arrival_observability,
simulated_network, early_replay, replay_scheduler, snapshot_state, hash_locks,
startup_roles, switch_history, build_identity, tests_catalogs, experiment_design,
runtime_entry_route, fresh_feedback. Separate final_diff_review_sync_gap
completed the final three-file review with no blocking source issue. Checked
chrono/format arguments, OFF filter policy, ON reset/refill/hold lifecycle,
exact env bytes, LF-only additive runtime diff and retained history suffix.
Review corrected proof wording for three-decimal gap_ms rounding. Source
review proves no compilation, runtime activation, safety or benefit.

Reviewed runtime SHA-256: 3d1476c8c11282a5f01a99c26090b22e889888658117900ea8aa1fc42436ad50

# T4 beta progress, 2026-11-03

## Current: test one-frame time-sync pauses with the original settling hold

Latest supplied real verify finished 2026-11-03T00:57:33. SIM_NORMAL_PRIORITY
really acted: both workers started, priority calls succeeded and reported
NORMAL. Send lateness stayed below 1.6 ms, with zero >=2 ms observations.
Nevertheless ON host/join rollbacks are 314/928 (2.96x), replay frames
508/3852 (7.58x), mean depths 1.62/4.15. Aggregate is 1242 rollbacks and
4360 replay frames. This weakens simulator priority as the main explanation;
leave that switch default-off. OFF host is truncated, so no complete OFF/ON
aggregate benefit is attributed. Latest summaries have no executable hash or
build ID. Priority activation proves that runtime path ran; the old identity
943fc4631acf2c13 cannot establish that runtime code never changed. Earlier
history already records newer IDs. Exact reviewed/executed bytes remain open.

Done: 24 independent read-only area agents read AGENTS.md/current progress.
Safe in-tree inventory found eight .log files, all ZIP/scanner output; the
latest-verify pointers also contain no runtime chronology. No reparse point
was followed. Full paired rb_frames/transport/arrival logs are absent here.
Input first-arrival timing, advantage sequence and first-wait order remain
UNKNOWN. Do not reconstruct them from summaries. No fixed role/sign defect
was established. Positive advantage means the waiting peer is estimated
AHEAD, not behind. Join excess stall+sync is 6899 ms; host excess rebase is
6891 ms. That near equality fits timing accounting at equal frame counts;
it does not identify the initiating peer or causal order.

One new bounded hypothesis: large time-sync pauses interrupt subsequent
input production and amplify replay bursts. Latest join requested 4500.090 ms
across 91 corrections, average 49.45 ms (~2.97 frames), while host made one
16.667 ms correction. Source jumps from one to three frames at filtered
advantage 2.5 and caps at four. Replay also delays the next live publication.
These are observations and a source opportunity, NOT proof of causation.
Waiting the ahead peer is intended to let the other catch up: reducing it
can UNDER-correct lead, increase stalls and increase repeated replay.

Root changed only runtime/tekken4_rollback_overrides.cpp for behavior behind
literal, default-off TEKKEN4_NET_SYNC_CAP_ONE=1. Compute the existing selected
base duration first, including FULL/SUBFRAME choices. ON caps only the pause
and corresponding scheduler shift to one kVblank (16667 us). Keep the
pre-cap rounded frames for the original RTT settling hold. Thus no deliberate
filter/refill/threshold/gap/once-live/replay-order policy change accompanies
the cap; wall timing can still change later samples and RTT observations.
Pending REPLAY_BEFORE_SYNC corrections retain base duration and capped give.
OFF keeps the old duration and hold. No input/wire/snapshot policy changed.
This differs from FULL_SYNC, which follows measured lead and changes its
derived hold. Keep all earlier experiments equal/off in this comparison.

Both arms append NETSYNCCAP to the same retained NETSUMMARY line: sync_cap_one,
time_sync, actions (all applied corrections), eligible_actions (applied base
pauses > one vblank), changed_actions (give != base), base_ms/requested_ms/
actual_ms totals and max_request_ms. These are correction observations, not
arrivals. Totals include every correction and overlap existing sync counters;
NEVER add them together. actual_ms includes any remaining liveT margin and
scheduling oversleep; only give_us is capped, not the full measured pause.
DIAG=1 emits NETSYNCCAP_EVENT with steady start/end, slot/frame, filtered adv,
base_us/give_us, actual_ms, retained hold_frames/rtt_ms/hold_until and
rc_before/after.
rc_before is the selection frontier (also for deferred replay), not an input
arrival timestamp. Existing FULLSYNC changed_actions compares pre-cap policy
to legacy; its requested/actual totals continue to describe applied pauses.
Shared counters and DIAG logging add observations in OFF; no zero-overhead
claim is made. No logging was added to the receive loop.

VERIFY_ENV.txt is one ASCII line plus LF, no BOM:
TEKKEN4_NET_SYNC_CAP_ONE=1

Open / owner-only REAL-ENTRY TEST: stage/build these exact reviewed runtime
bytes and run actual paired Mode::Net games OFF/ON through the external
verify wrapper. Forward VERIFY_ENV.txt explicitly via -Env in ON; net_pair
clears inherited settings and does not read this file. Put these settings in
BOTH arms, outside the ON-only file:
TEKKEN4_NET_DELAY=3;TEKKEN4_NET_LOCKDELAY=7;TEKKEN4_NET_DIAG=1;TEKKEN4_NET_LOCALPAD=0
Use RBSTART=600, TIMESYNC=1, normal 20-sample filter, RB_MODE unset/net,
RTT150/jitter5/loss3, 6000 frames, matching workload/foreground conditions.
Keep FULL_SYNC, SUBFRAME_SYNC, FAST_SYNC, REPLAY_BEFORE_SYNC, REPLAY_BATCH,
ATOMIC_INPUT, SIM_NORMAL_PRIORITY, SIM_SAFE_WAIT, LIVE_LEAD, ORDERED_LEAD,
REFRESH_RC, SEND_FIRST, REBASE_CATCHUP, EARLY_DEADLINE, PRED_HEADROOM and other
experiments equal/off. Record all effective parameters, not just the label.
Retain full paired rb_frames/transport logs, stdout/stderr and timing records.
Reviewed/staged source SHA-256 must match; refresh identity after staging,
clear explicit BUILD overrides, retain build success and each launched exe
SHA-256. Identity hashes staged inputs, not executable bytes. No identity
refresh or build was performed here. Equal RNG seeds do not ensure equal
per-input delivery histories.

Require OFF sync_cap_one=0, changed_actions=0, base_ms=requested_ms.
Require ON literal banner, sync_cap_one=1 and nonzero eligible_actions;
changed_actions=eligible_actions>0, requested_ms<base_ms and max_request_ms
<=16.667. ON event give_us=min(base_us,16667), hold_frames=ceil(base_us/16667),
The original hold formula remains f+hold_frames+trunc(rtt_ms/16.667+0.999)+2
for positive RTT, else f+hold_frames+2. Event rtt_ms/hold_until record the
actual sampled RTT and chosen result. Zero changed means
UNEXERCISED. NETFULLSYNC changed_actions should stay zero with FULL_SYNC off.
Require pending replay correction drained at normal final. Compare first
recorded sync/wait and prior producer/frontier gaps in both full logs; existing
diagnostics still cannot recover every unique input's first arrival.
Success requires lower absolute aggregate replay/depth and acceptable total
waits, stalls, FPS and frame tails. A ratio improved by worsening the other
peer is not success. Increased sustained advantage, stalls, repeated replay
or total burden rejects this candidate. Require zero hash mismatches and
NETDESYNC; repeat same roles, swap roles, then use two physical PCs. Default
stays OFF and release acceptance stays OPEN.

Ran: tests_catalogs invoked actual tools/check_online_catalogs.ps1, exit 0:
both 23-tool catalogs, three root inputs and Host/Join dependencies present.
Inventory only. Test/SelfNet dispatch to different boundaries; neither proves
paired npBoundary. Root checked source changes, env encoding and retained
history. These are SOURCE CHECKS. Compilation, activation, safety and benefit
are UNRUN: AGENTS.md forbids builds, games and tools/net_* here. No changed
runtime entry ran; this candidate has NOT met the requested real-entry-test
requirement. Only the owner's actual paired verify can close it. No mock or
source check is represented as execution of the changed runtime.

Original bytes of the three changed files are retained under
logs/runtime-sync-cap-one/originals. Root alone edits runtime/progress/env;
all area agents are read-only. No Git command, outside-tree access, deletion,
patch edit, build, game, forbidden helper, server, push or release occurred.

Area agents: pair_logs, verify_metrics, advantage_sign, sync_filter,
prediction_cap, vblank_pacing, input_sampling, publication_guard,
transport_send, transport_receive, resend_coalesce, arrival_observability,
simulated_network, early_replay, replay_scheduler, snapshot_state, hash_locks,
startup_roles, switch_history, build_identity, tests_catalogs, experiment_design,
runtime_entry_route, fresh_feedback. Separate final_diff_review_sync_cap_one
completed the final three-file review with no blocking source issue. Checked
OFF duration, pre-cap hold, pending lifetime, counters/format arguments,
FULLSYNC separation, exact env bytes and retained history. Review clarified
that actual_ms includes remaining liveT margin as well as oversleep. Source
review cannot prove compilation, runtime activation, safety or benefit.

Reviewed runtime SHA-256: 858c04454582c5627874661bb3214b93e068339b0ba2a4db609f552ce682cb19

# T4 beta progress, 2026-11-03

## Current: test simulator sender priority on the same-PC pair

Latest supplied real verify finished 2026-11-03T00:41:21. The previous
REPLAY_BEFORE_SYNC switch was recognized but its changed ordering NEVER ran:
both peers report mismatch=deferred=applied=0 across 96 eligible corrections.
It does not explain this run. Keep it default-off and do not repeat it here.
The complete ON pair is host/join 321/922 rollbacks (2.87x), 638/3636 replay
frames (5.70x), mean depths 1.99/3.94. Join excess stall+sync is 7110 ms;
host excess rebase is 7087 ms. This supports coupled pacing, not the order
of causation. More join corrections means the controller estimated it AHEAD.
OFF host is truncated and delay changed 2 -> 3, so no aggregate OFF/ON benefit
can be attributed. Latest output has no executable hash or build ID; earlier
history already records IDs newer than 943fc4631acf2c13. Exact bytes remain
unproved by the supplied summary.

Done: 24 separate read-only area agents read AGENTS.md/current progress.
Safe inventory found eight .log files, all scanner/ZIP output, and no paired
runtime, rb_frames, transport or arrival chronology. No reparse point was
traversed. Input first arrivals, advantage sequence and first-wait order are
UNKNOWN. No fixed host/join sign, input commit, ACK or scheduler-restore defect
was established. Do not reconstruct that missing chronology from summaries.

One new hypothesis: each outgoing network simulator worker runs at Windows
THREAD_PRIORITY_HIGHEST and yield-spins during the final <=1.5 ms to a packet
deadline. Two such workers on one PC can compete with game input producers,
amplifying unequal producer/replay gaps. This is a source-supported scheduling
opportunity, NOT a proved initiating cause or a two-PC Internet defect.

Root changed runtime/tekken4_net.cpp behind literal, default-off
TEKKEN4_NET_SIM_NORMAL_PRIORITY=1. ONLY the simulator worker's requested
relative priority changes from HIGHEST to NORMAL. Its wait/spin condition,
queue behavior, due times, loss/jitter RNG, wire layout and game pacing policy
are retained. Existing SIM_SAFE_WAIT remains a separate equal/off setting;
its retained unlocked deque-reference hazard is not fixed by this experiment.
No simulator means no changed scheduling behavior. Failed priority calls do
not fall back to a different policy and must be reported as unexercised.

Both arms collect host-only atomic observations: thread-started, priority
call success, reported relative priority, spin calls/wall duration/max,
sendWire attempts, packet lateness max and count >=2 ms. No log in spin loop.
NETSIMPRIO_START in transport log records requested/reported priority and
success. runtime/tekken4_net.h exposes observations through Stats;
runtime/tekken4_rollback_overrides.cpp appends NETSIMPRIO to the retained
NETSUMMARY line. Spin time is WALL time including preemption, not CPU time;
do not add it to waits. Send calls are attempts, not successful sends.
Lateness is measured before sendWire, not socket arrival. Atomic snapshots
are observations of a running worker, not a transactional accounting record.
OFF includes shared measurement/logging overhead; zero overhead is not claimed.

VERIFY_ENV.txt is one ASCII line plus LF, no BOM:
TEKKEN4_NET_SIM_NORMAL_PRIORITY=1

Open / owner-only REAL-ENTRY TEST: stage/build these exact reviewed THREE
runtime files and run actual paired Mode::Net games OFF/ON using the external
verify wrapper. It must forward VERIFY_ENV.txt via -Env; net_pair does not
read it. Put these common settings in BOTH arms, outside the ON-only file:
TEKKEN4_NET_DELAY=3;TEKKEN4_NET_LOCKDELAY=7;TEKKEN4_NET_DIAG=1;TEKKEN4_NET_LOCALPAD=0
Use RBSTART=600, TIMESYNC=1, normal 20-sample filter, RB_MODE unset/net,
RTT150/jitter5/loss3, 6000 frames, matching workload and foreground conditions.
Keep every other experiment equal/off, especially REPLAY_BEFORE_SYNC,
REPLAY_BATCH, ATOMIC_INPUT, FULL_SYNC, SUBFRAME_SYNC, FAST_SYNC, LIVE_LEAD,
ORDERED_LEAD, REBASE_CATCHUP, EARLY_DEADLINE, PRED_HEADROOM and SIM_SAFE_WAIT.
Retain full paired rb_frames/transport logs, effective parameters and stderr.
Compare reviewed/staged SHA-256 of all three modules, refresh identity, clear
explicit BUILD overrides and retain each launched executable SHA-256. Identity
hashes staged sources, not executable bytes. Equal RNG seeds do not guarantee
identical frame-level delivery. No build or identity refresh happened here.

Require BOTH arms sim_active=started=set_ok=1, nonzero spin_calls/send_calls.
Require OFF normal_priority=0/thread_priority=2 (HIGHEST); ON literal banner
and normal_priority=1/thread_priority=0 (NORMAL), plus matching START records.
GetThreadPriority reports a relative setting, not instantaneous CPU priority;
retain process_class from NETDIAG. No active worker or failed set means UNRUN.
Compare cumulative late_max_ms/late_ge2ms and interval sim_late_ms/sim_late_n,
producer local_gap_ms, receiver rx_lock_ms and tick_gap_ms. Read paired steady
wait/sync events to find first recorded wait and prior publication/frontier
gaps; existing diagnostics still do not log each unique input's first arrival.
Require lower absolute aggregate replay/depth/burden and acceptable frame
tails/FPS, not just a ratio improved by worsening the other peer or changing
the effective network. If lowering priority worsens packet lateness, report
that tradeoff; do not call it equivalent-network proof. If priority really
changes but gaps and rollback burden persist, weaken this hypothesis. Require
zero hash mismatches/NETDESYNC, repeat same roles, swap roles, then test two
physical PCs. Default stays OFF; release acceptance remains OPEN.

Ran: tests_catalogs invoked actual tools/check_online_catalogs.ps1, exit 0:
both 23-tool catalogs, three root inputs and Host/Join dependencies present.
This is inventory only. No test entry runs actual paired npBoundary;
SELFTEST dispatches to a different boundary. Root checked retained originals,
source bytes and environment encoding. These are SOURCE CHECKS, not runtime
proof. Compilation, switch propagation/activation, priority result, safety,
timing and performance are UNRUN: AGENTS.md forbids builds, games and
tools/net_* here. No changed runtime entry ran. This change has NOT met the
real-entry-test requirement; only the owner's actual paired verify can close
it. No substitute/mock test is represented as evidence that it ran.

Original bytes of the five changed files are retained under
logs/runtime-sim-normal-priority/originals. Root alone edits runtime/progress/
env files. No Git command, outside-tree access, deletion, patch edit, build,
game, forbidden helper, server, push or release was performed.

Area agents used: pair_logs, verify_metrics, advantage_sign, sync_filter,
prediction_cap, vblank_deadline, input_sampling, publication_guard,
transport_send, transport_receive, resend_coalesce, arrival_observability,
simulated_network, early_replay, replay_scheduler, snapshot_state, hash_locks,
startup_roles, switch_history, build_identity, tests_catalogs, experiment_design,
runtime_entry_route, fresh_feedback. Separate final_diff_review_sim_priority
reviewed the final five-file diff with no blocking source issue. It checked
OFF/ON scope, atomics/ready publication, format arguments, retained unsafe
reference, exact env bytes and byte-identical progress history. Review is
SOURCE ONLY; no compile, activation, runtime safety or benefit is proved.
Reviewed runtime SHA-256:
tekken4_net.cpp dd612b5f9cc1c42c55c6bcc71ce60ebc3acae884c3a4a90b9f26f19f4a98b117
tekken4_net.h d266a422f3cb66e3b0af583e6c2d887ee2324685deb14eb3f0f32c68298c23e4
tekken4_rollback_overrides.cpp 9691013fa87716aad4088a00140493147fbcdbe72e6bb06b2e1e443db5952563

# T4 beta progress, 2026-11-03

## Current: test replay before an already-selected time-sync correction

Latest supplied real verify finished 2026-11-03T00:21:54. REPLAY_BATCH acted:
ON host/join rollbacks 381/834, replay frames 751/2818, mean depth 1.97/3.38.
Join/host rollback ratio 2.19 and replay ratio 3.75 remain unequal. Join OFF
-> ON replay fell 3768 -> 2818, but >34 ms frames rose 379 -> 448. Combined
stall+sync+BATCH category time on join rose 6535 -> 12073.445 ms. Most batch
calls were early, so this sum does NOT prove extra wall time. OFF host is
truncated; aggregate OFF/ON improvement cannot be established. Keep batching
default-off. No supplied build ID/executable hash identifies this latest run.
Earlier history already contains newer IDs than 943fc4631acf2c13; no current
executable identity is proved by that historical observation.

Done: 24 separate area agents read AGENTS.md/current progress and inspected
source/evidence, all read-only. Safe inventory found eight .log files, all
ZIP/scanner output; no rb_frames or host/join/arrival/transport chronology.
No reparse point was traversed or outside-tree location opened. Requested
paired first arrivals, advantage sequence and first-wait order remain UNKNOWN.
No fixed host/join runtime defect was established. Latest ON join's 89 sync
corrections versus host's 3 means its controller repeatedly estimated it ahead;
more waiting does not mean it was behind. Excess join stall+sync 4441 ms nearly
matches excess host rebases 4409 ms, without identifying the initiating cause.

One new bounded hypothesis: a mismatch confirmed during the final early sleep
can wait through a selected 16-67 ms time-sync correction before late replay.
This delays correcting the state and may amplify publication/rollback burden.
This is a source ordering opportunity, NOT an established cause of the ratio.
Only 57/834 latest join rollbacks were late; overlap with corrections may be
small. Existing correction sleep also lets confirmations arrive before replay;
replaying sooner can INCREASE repeated replay. Actual overlap and net benefit
must be measured. Earlier startup/controller/rebase/early/headroom/publication/
flush/atomic/batch experiments are not promoted or repeated as this candidate.

Root changed only runtime/tekken4_rollback_overrides.cpp for behavior, behind
default-off literal TEKKEN4_NET_REPLAY_BEFORE_SYNC=1. At an actually eligible
correction, BOTH arms nonconsumingly inspect the same confirmed interval.
OFF applies the existing selected correction immediately. ON, only with a
confirmed mismatch and valid snapshot, consumes that mismatch and starts the
ordinary late rollback first. Store the exact selected frame, frontier, lead,
duration and settling-frame count in host-only state. Mark lastLiveFrame on
return so replay never takes another filter sample or selects another wait.
After npEndResim restores the live scheduler at matching catch-up f, clear the
pending flag and apply that saved correction once, before any later scan.
Failure to start rollback clears pending state and applies normally. No new
wait duration, input sampling policy, wire layout or guest snapshot data added.
On pending catch-up, retain the saved pre-sleep frontier unless the existing
explicit REFRESH_RC guard is enabled, just as in the immediate ordering.
Controller resets/accounting share the original application body, preserved
byte-for-byte in npApplyTimeSync. Normal post-sleep RTT still sets the hold.
OFF adds observations, scan locks and diagnostics; zero timing overhead is not
claimed. This is an ordering test, not a claim the asymmetry has been fixed.

Both arms append NETREPLAYSYNC to the same retained NETSUMMARY line:
replay_before_sync, time_sync, eligible (selected correction opportunities),
mismatch (opportunities with a confirmed mismatch), deferred, applied, pending,
deferred_us/applied_us (selected durations, not extra waits), delay_ms/max_delay_ms
(selection to application START, including replay and intervening work), last_f
and last_from (last deferred correction). These are decision counts, not arrivals.
DIAG=1 emits NETREPLAYSYNC_EVENT for each selected opportunity in both arms,
with shared steady-clock selection time, slot, f, rc, mismatch/from/snapshot_ok,
deferred, adv and give_us. With no mismatch, from is the unsigned sentinel.
ON NETREPLAYSYNC_APPLY marks application start; the existing NETFULLSYNC_EVENT
or NETSUBFRAME_EVENT then records the actual sleep and unchanged chosen give.
For a deferred correction rc_before is the saved SELECTION frontier, not a
fresh measurement at sleep start; rc_after is current after the sleep.
The new delay_ms is NOT another wait total and must not be added to workload.
Existing restore+resim cost excludes the correction sleep in either ordering.

VERIFY_ENV.txt is one ASCII line plus LF, no BOM:
TEKKEN4_NET_REPLAY_BEFORE_SYNC=1

Open / owner-only REAL-ENTRY TEST: stage/build these exact reviewed runtime
bytes and run actual paired Mode::Net games OFF/ON through the external verify
wrapper. It must forward VERIFY_ENV.txt via -Env; net_pair does not read it.
Set common settings in BOTH arms, outside the ON-only file:
TEKKEN4_NET_DELAY=3;TEKKEN4_NET_LOCKDELAY=7;TEKKEN4_NET_DIAG=1;TEKKEN4_NET_LOCALPAD=0
Keep RBSTART=600, TIMESYNC=1, normal 20-sample filter, RB_MODE unset/net,
RTT150/jitter5/loss3, 6000 frames; all previous experiments equal/off,
especially REPLAY_BATCH, ATOMIC_INPUT, FULL_SYNC, SUBFRAME_SYNC, FAST_SYNC,
EARLY_DEADLINE and PRED_HEADROOM. Retain full paired runtime/transport logs,
effective params and stdout/stderr. Compare reviewed/staged SHA-256, refresh
identity, retain SHA-256 of each launched executable, and avoid explicit BUILD
overrides. Build identity hashes staged inputs, not executable bytes. Same RNG
seeds do not ensure identical frame-level delivery between arms.

Require OFF replay_before_sync=0, deferred=applied=pending=0 and selected
opportunity events. Require ON literal banner, replay_before_sync=1 and
0 < deferred=applied <= mismatch <= eligible, pending=0 on normal final,
deferred_us=applied_us, and matching selection/application/sleep events at the
same f with the same give_us. Require at most one filter sample/selected correction per live f,
valid restored snapshots and unchanged scheduler restoration. Zero/tiny overlap
weakens this candidate as a major cause; zero deferred means unexercised.
Compare absolute aggregate replay/depth, repeated replay, combined waits, FPS
and frame tails; a ratio improved by worsening the other side is no success.
Require zero hashes mismatching/NETDESYNC, repeat same roles, swap roles and
then two physical PCs. Keep default-off; release acceptance remains OPEN.

Ran: tests_catalogs ran actual tools/check_online_catalogs.ps1, exit0: both
23-tool catalogs, three root inputs and Host/Join dependencies present. This
is inventory only. No existing test entry runs paired npBoundary; SELFTEST
bypasses it. Root compared extracted correction body against retained original
and checked encoding/env bytes. These are SOURCE CHECKS, not runtime tests.
Compilation, switch activation, correction preservation, safety, timing and
performance are UNRUN: AGENTS.md forbids builds, games and tools/net_* here.
No changed runtime entry ran. This candidate does NOT meet the real-entry-test
requirement yet. Only the owner's actual paired game verify can close it.

Original bytes of source/progress/env are retained under
logs/runtime-replay-before-sync/originals. Root alone edits these three files;
all agents are read-only. No Git, outside-tree access, deletion, patch edit,
build, game, forbidden helper, server, push or release was performed.

Area agents: pair_log_inventory, verify_metrics, timesync_estimate,
timesync_filter, prediction_wait, vblank_pacing, startup_roles, input_sampling,
send_first_guards, hash_reader_wait, hash_collect, snapshot_restore,
transport_sender, transport_receiver, resend_coalesce, arrival_timestamps,
simulation_rng, scheduler_restore, early_rollback, state_serialization,
switch_entry_route, build_identity, tests_catalogs, experiment_gate.
experiment_gate reviewed the design, required preserving the selected correction
and once-live markers, and warned that earlier replay can lose confirmations.
Separate final reviewer final_diff_review_replay_before_sync completed the
three-file review with no remaining source blocker. It caught and root fixed
an implicit frontier refresh in ON; both arms now retain pre-sleep rc unless
REFRESH_RC is enabled. Reviewer checked OFF policy, nonconsuming scan, snapshot
validation, pending lifetime, once-live markers, scheduler restoration, exact
correction body, summary formats, env bytes and retained history. Source review
only: activation, runtime safety and benefit remain unproved.
Reviewed runtime SHA-256:
91b23bb7f8adb7fa6007cc18cade1b2383a18114f1d7a7d965d79861cfc541fd

# T4 beta progress, 2026-11-03

## Current: test bounded confirmation batching before replay

Latest supplied verify finished 2026-11-02T23:57:30. ATOMIC_INPUT enabled
on both peers but recovered/advanced/ahead_frontier/future_fallback counts
were all zero. Its changed selection path made no observed recovery; this
strongly weakens it as the main explanation. Leave it default-off. Latest
excerpt supplies no build ID. Earlier progress records newer identities than
943fc4631acf2c13; the current executable bytes remain unproved here.

ON host/join: rollbacks 342/941, replay frames 595/3398, mean replay depth
1.74/3.61, stall+sync waits 33/5433 ms, rebases 15915/10502 ms. Join/host
rollback ratio is 2.75, replay ratio 5.71. Excess join waits 5400 ms nearly
match excess host rebases 5413 ms. That does not identify the initial lead.
OFF host summary is truncated in the supplied excerpt, and delay changed
2 -> 3. No aggregate OFF/ON improvement is attributed to ATOMIC_INPUT.

Done: 24 independent area agents read AGENTS.md and reviewed separate source
or evidence areas. Safe in-tree inventory again found exactly eight .log
files, all ZIP/scanner results, and no rb_frames, paired runtime/transport
chronology or JSONL arrivals. No reparse point was traversed. Requested last
verify pair logs cannot be read because they are absent from this copy.
First input arrivals, advantage sequence and first-wait order remain UNKNOWN.
No fixed role/sign/snapshot/sender/receiver defect was established. Earlier
controller, early-deadline, publication, headroom, startup, rebase, flush and
atomic-input experiments are not repeated.

One new bounded hypothesis: replay begins while part of its input interval
is still predicted. Further confirmations can then cause another replay,
delaying fresh publication and amplifying unequal prediction exposure.
This is a source-supported possibility, NOT the established initiating cause.
Previous EARLY_DEADLINE deferred overdue scans; PRED_HEADROOM waited only
after the prediction cap. This candidate instead waits after a known mismatch,
including early mismatches, before restoring that preserved mismatch.

Root changed only runtime/tekken4_rollback_overrides.cpp for runtime behavior,
behind default-off literal TEKKEN4_NET_REPLAY_BATCH=1. After validating the
snapshot, if remoteContig < live f, request confirmation through f-1 using
waitRemoteUs(f-1,16667), at most once per live f. An ahead peer may require
the lagging peer to sample more inputs; it is NOT guaranteed they already
exist. The finite timeout avoids an indefinite wait for that progress.
Actual elapsed time can exceed the requested budget because of scheduling
or mutex contention. On timeout or peer loss, keep the pending mismatch and
perform the ordinary restore/replay. No second npScan consumes it. The live
deadline is not shifted. Batch bookkeeping is host-only and survives restore.
OFF adds observations but retains the original immediate restore policy;
shared diagnostic/lock overhead is not claimed to be zero.

Both arms append NETREPLAYBATCH to the retained NETSUMMARY line:
replay_batch; opportunities (first eligible rollback at a live f); waits
(actual ON wait calls); early_waits; advanced (returned frontier > observed
before); completed (returned frontier >= f); revisits (all additional valid
rollback starts at the same live f, including OFF); wait_ms/max_ms; last_f,
rc_before/after (last ON call); budget_us=16667. These are decision/call
counts, not unique input arrivals. A call can return immediately if reception
advanced between locks; advanced does not prove it slept or helped.
DIAG=1 emits NETREPLAYBATCH_EVENT for each opportunity in BOTH arms with
common steady start/end times, slot, switch, live f, first mismatch, early
flag, before/after frontier, target f and elapsed wait. OFF reports equal
start/end, unchanged observed frontier and zero wait; it makes no extra wait.
The event does not timestamp unique network arrivals. overdueEarly keeps its
original trigger-time classification before batching. Existing restore+resim
and stall+sync totals EXCLUDE batch wait: include NETREPLAYBATCH wait_ms in
all total-workload wait comparisons. Do not sum max_ms as a total.

VERIFY_ENV.txt is exactly one ASCII line plus LF, no BOM:
TEKKEN4_NET_REPLAY_BATCH=1

Open / owner-only real-entry test: stage/build these exact reviewed runtime
bytes and run actual paired Mode::Net games OFF/ON via the external verify
wrapper. The wrapper must forward VERIFY_ENV.txt through -Env; net_pair
does not read the file. Put common settings in BOTH arms, not the ON file:
TEKKEN4_NET_DELAY=3;TEKKEN4_NET_LOCKDELAY=7;TEKKEN4_NET_DIAG=1;TEKKEN4_NET_LOCALPAD=0
Keep RBSTART=600, TIMESYNC=1, normal 20-sample filter, RB_MODE unset/net,
RTT 150/jitter 5/loss 3, 6000 frames and all other experiments equal/off,
including ATOMIC_INPUT, FULL_SYNC, SUBFRAME_SYNC, FAST_SYNC, EARLY_DEADLINE
and PRED_HEADROOM. Retain full paired rb_frames/transport logs and effective
params/stdout/stderr. Compare reviewed and staged runtime SHA-256 bytes,
refresh build identity and retain launched executable SHA-256 per peer;
identity hashes staged sources rather than the executable. Equal simulator
seeds do not ensure identical frame-by-frame conditions across arms.

Require OFF replay_batch=0 and waits=early_waits=advanced=completed=0;
ON literal banner, replay_batch=1, waits=opportunities>0, early_waits>0 for
this mostly-early workload, matching events and advanced/completed activity.
Check early_waits/advanced/completed <= waits, event target=f and requested
budget_us=16667, and no second wait at the same live f. Record actual max_ms;
do not impose a false hard elapsed-time ceiling. If nothing advances, the
candidate did not batch useful confirmations. If OFF revisits are negligible,
that weakens same-live-frame repetition as a major source of amplification;
it does not count all possible later-frame repeated work. Compare absolute
aggregate replay/depth, predicted replay decisions, revisits, combined
stall+sync+BATCH waits, FPS and frame tails. Require worthwhile net benefit,
not a nicer ratio caused by worsening the other peer. Substantial actions
without less replay/burden weaken this hypothesis. Require zero hash
mismatches/NETDESYNC, repeat same-role runs, swap roles, then two physical PCs.
Keep candidate default-off until real proof. Release acceptance stays OPEN.

Ran: tests_catalogs invoked actual tools/check_online_catalogs.ps1, exit 0:
both 23-tool catalogs, three root inputs and Host/Join dependencies present.
This is inventory only. Existing test_* entries do not run actual paired
Mode::Net; SELFTEST bypasses npBoundary. No model/mock/source assertion is
counted as runtime proof. Root checked file bytes/environment/history only.
Compilation, switch activation, runtime safety, timing and performance are
UNRUN here: AGENTS.md forbids builds, games and tools/net_* execution. No
changed runtime entry ran. This candidate has NOT met the real-entry test
requirement. The owner's actual paired game verify is the required test.

Original bytes of the three edited files are retained under
logs/runtime-replay-batch/originals. Root alone edits source/progress/env;
area agents are read-only. No Git command, outside-tree read, deletion, patch
change, build, game, forbidden helper, server, push or release was used.

Area agents: pair_log_inventory, verify_metrics, timesync_estimate,
timesync_filter, prediction_wait, vblank_pacing, startup_roles, input_sampling,
send_first_guards, hash_reader_wait, hash_collect, snapshot_restore,
transport_sender, transport_receiver, resend_coalesce, arrival_timestamps,
simulation_rng, scheduler_restore, early_rollback, state_serialization,
switch_entry_route, build_identity, tests_catalogs, experiment_gate.
experiment_gate reviewed the candidate and found no source safety blocker;
it corrected the assumption that the remote inputs must already be sampled,
and required accounting for batch wait and possible timeout overshoot.
Separate final reviewer final_diff_review_replay_batch completed the
three-file diff against retained originals with no blocking source issue.
It checked OFF immediate-restore policy, once/f guard, pending mismatch,
timeout/loss and underflow handling, scheduler preservation, counters,
varargs formats, retained summary newline, exact environment bytes, runtime
LF/no BOM and unchanged progress history suffix. Source review only;
compilation, activation, runtime safety and performance remain UNRUN.
Reviewed runtime SHA-256:
c17a19ae60059f7b96b6bbf3b892d0640baff7aa30c5cdcd00092a7584612a16

# T4 beta progress, 2026-11-02

## Current: test the remote-input selection race

Latest supplied verify finished 2026-11-02T23:38:53. FULL_SYNC really acted:
ON host/join changed_actions=1/59. Combined OFF -> ON rollbacks 1263 -> 1279
(+1.3%), replay frames 4223 -> 4349 (+3.0%), stall+sync waits 6635 -> 7455 ms
(+12.4%). Join/host rollback ratio stayed about 3.0. The correction-duration
hypothesis is weakened; FULL_SYNC stays default-off and is not repeated.
Latest excerpt gives no build ID. The previous supplied ID f682731375e32a72
already superseded the old 943fc4631acf2c13 concern, but neither an ID nor
these summaries proves which executable bytes ran in the latest comparison.

Done: 24 independent area agents read AGENTS.md and source/evidence. Safe
inventory found eight .log files, all scanner/catalog output, and no rb_frames
or host/join runtime pair chronology. No outside-tree location was opened.
We could not read the requested last-verify pair logs because they are absent.
Unique input first-arrival times, advantage sequence and first-wait order
remain unknown. Join accumulated the waits; that does not establish the
initiating cause. Rebase gaps again nearly equal excess join waits:
OFF 6623 vs 6635 ms; ON 7419 vs 7421 ms. No fixed role or time-sync sign bug
was found. Prior controller, publication, early, startup, flush and headroom
experiments are not repeated.

One new source hypothesis: npDecideInputs separately locks remote(g),
remoteContig(), then remote(rc-1). If reception advances between the first
two calls, exact g is now available but the fallback may take a later frame's
input and mark g predicted. A later mismatch can then cause avoidable replay.
The race exists in the source; its frequency and role in the imbalance are
UNKNOWN. Its window is small. It may explain little or none of this workload.
An advanced frontier or recovered classification does not prove pad bytes
differed, and cannot by itself establish a performance benefit.

Root changed runtime/tekken4_net.cpp, runtime/tekken4_net.h and
runtime/tekken4_rollback_overrides.cpp behind default-off literal
TEKKEN4_NET_ATOMIC_INPUT=1. After the existing initial exact-input miss, ON
rechecks exact g and selects a held prediction under one transport mutex.
It returns confirmed only when g is below the contiguous frontier and its
ring tag matches. Otherwise it holds rc-1 only when 0 < rc <= g and the tag
matches, or returns neutral. It never chooses a future frame. OFF retains
the original input-selection calls and predicted classification. Added
counters/logging affect execution time in both arms; zero overhead is not
claimed. No input sampling, wire, guest snapshot, time-sync or wait policy
was changed. All new counters are host-only and survive guest restores.

Both arms append NETATOMICINPUT to the same retained NETSUMMARY line:
atomic_input; misses_live/replay (initial exact lookup failures);
recovered_live/replay (ON locked recheck found exact input);
advanced_live/replay (frontier after initial miss is now > g);
ahead_frontier_live/replay (frontier-1 > g, a future fallback target);
future_fallbacks_live/replay (OFF actually selected that future target).
Live/replay count execution decisions, including repeated executions, not
unique input arrivals. ON future_fallbacks must stay zero. A recovery at
rc=g+1 only changes confirmation classification versus the old coherent
fallback; it need not change input bytes. With DIAG=1, advanced cases emit
NETATOMICINPUT_EVENT with common steady timestamp, slot, g, replay, switch,
rc and confirmed. Events occur after locks release; they are decision times,
not first-arrival timestamps. No pad contents or network addresses are logged.

VERIFY_ENV.txt is exactly one ASCII line plus LF, no BOM:
TEKKEN4_NET_ATOMIC_INPUT=1

Open / owner-only real-entry test: stage/build these exact three runtime
files, refresh identity, and run actual paired Mode::Net games OFF/ON through
the external verify wrapper. It must forward VERIFY_ENV.txt via -Env;
net_pair does not read the file itself. Keep these common settings in BOTH
arms, not only the ON-only file:
TEKKEN4_NET_DELAY=3;TEKKEN4_NET_LOCKDELAY=7;TEKKEN4_NET_DIAG=1;TEKKEN4_NET_LOCALPAD=0
Keep RBSTART=600, TIMESYNC=1, normal 20-sample filtering, RB_MODE unset/net,
RTT 150/jitter 5/loss 3 and 6000 frames. All other experiments equal/off,
especially FULL_SYNC, SUBFRAME_SYNC and FAST_SYNC. Retain full paired
rb_frames and transport logs, effective params, stdout/stderr, exact reviewed
and staged runtime SHA-256 hashes, launched executable SHA-256 and build ID.
The build ID hashes staged inputs, not the executable. Same simulator seeds
do not guarantee identical per-frame conditions when datagram counts differ.

Require OFF atomic_input=0 and recovered_live/replay=0; ON literal activation,
atomic_input=1, recovered_live+recovered_replay > 0 with matching confirmed=1
events, and future_fallbacks_live/replay=0. In ordinary retained histories,
ON advanced counts should equal recovered counts. Inspect ahead_frontier and
OFF future_fallback counts separately from classification-only recoveries.
Zero recovered actions means the changed race path was not exercised; tiny
counts strongly weaken it as the main explanation. Even many recoveries
without lower absolute aggregate replay/depth and acceptable combined waits,
FPS and frame tails do not establish benefit. Do not accept a nicer ratio
produced by worsening the other side. Require zero hash mismatches/NETDESYNC,
repeat same-role runs, then swap roles and use two physical PCs. Keep this
candidate default-off until actual proof; release acceptance stays open.

Ran: tests_catalogs invoked actual tools/check_online_catalogs.ps1, exit 0:
both 23-tool catalogs, three root inputs and Host/Join dependencies present.
Inventory only. No existing test_* entry exercises Mode::Net; SELFTEST
bypasses npBoundary and cannot test this race. No mock/model/source assertion
is counted as runtime proof. Source byte checks found LF-only runtime files,
exact env bytes and retained history. Compilation, literal activation, race
frequency, replay safety and performance remain UNRUN here: AGENTS.md forbids
builds, games and tools/net_* execution. No changed runtime entry ran. This
candidate has NOT met the real-entry test requirement; only the owner's
actual paired game verify can close it. No passing runtime test is claimed.

Original bytes of the five edited files are retained under
logs/runtime-atomic-input/originals. Root alone edits; all area agents are
read-only. No Git command, outside-tree read, deletion, patch change, build,
game, forbidden helper, server, push or release was used.

Area agents: pair_logs, verify_metrics, timesync_estimate, timesync_filter,
prediction_wait, vblank_pacing, startup_roles, input_sampling,
send_first_guards, hash_reader_wait, hash_collect, snapshot_restore,
transport_sender, transport_receiver, resend_coalesce, arrival_timestamps,
simulation_rng, scheduler_restore, early_rollback, state_serialization,
switch_entry_route, build_identity, tests_catalogs, experiment_gate.
experiment_gate found no source-design blocker, while requiring real action
counts and explicitly rejecting an established causal or performance claim.
Separate final reviewer: final_diff_review_atomic_input completed the five-file
diff against retained originals with no blocking source issue. It checked OFF
selection equivalence, ON atomic exact/tag/frontier and fallback bounds,
live/replay counters, format arguments, literal Mode::Net routing, summary
retention, exact environment bytes, LF-only runtime and unchanged history
suffix. This is source review only; no changed runtime entry was executed.

# T4 beta progress, 2026-11-02

## Current: test continuous correction of whole-frame lead

Latest supplied verify finished 2026-11-02T23:20:40, build in 180 seconds,
build ID f682731375e32a72. The unchanged-ID concern is superseded.
SUBFRAME_SYNC acted: host/join 6/7 fractional corrections, 90.968 ms requested
and 91.137 ms actual combined. Yet join still had 940 rollbacks, 3667 replay
frames and 5809 ms stall+sync waits. OFF/ON combined rollback 1453 -> 1251,
replay 5324 -> 4297, but join/host rollback ratio 2.20 -> 3.02 and combined
stall+sync time 5506 -> 5851 ms. Delay changed 2 -> 3, so these differences
cannot isolate SUBFRAME_SYNC. Small fractional deadband is weakened as the
main explanation. No prior experiment becomes a default. SELFTEST does not
enter npBoundary and cannot prove its timing policies.

Done: 24 independent area agents read source/evidence. Eight .log files in
this tree are scanner/catalog output; there are no chronological host/join
runtime or transport pair logs. No outside-tree location was opened. Unique
input first-arrival times, sampled advantage chronology and first-wait order
remain unknown. Summaries cannot establish why one side rolls back more.
Rebase gaps again match unequal waits: OFF 5400 versus 5406 ms; ON 5741
versus 5767 ms. No fixed role policy, sign or counting defect was established.
The ahead side can retain more prediction exposure, while replay delays its
next fresh input, but the initiating event is not known. Prior lead metadata,
filter/refill, early, headroom, rebase, send, flush and startup experiments
are not repeated. Generic earlier references to a gain experiment were
inaccurate: no documented correction-duration experiment was found.

One new hypothesis: the whole-frame controller's correction quantization
sustains residual producer lead or overshoots it. For 1 <= adv < 2.5 it gives
only one frame; above that it rounds and caps at four. Latest join made 92
total sync corrections but only seven fractional ones; the actual whole-frame
advantage distribution was not supplied. This is a bounded source hypothesis,
NOT a measured explanation or a tested fix. Delayed/noisy estimates can make
continuous correction worse too.

Root changed runtime/tekken4_rollback_overrides.cpp behind default-off literal
TEKKEN4_NET_FULL_SYNC=1. Only for filtered adv >= 1, request
min(4.0, adv) * 16667 microseconds, truncated to integer microseconds. OFF
keeps the exact old correction duration. The settling hold rounds the chosen
microseconds up to whole frames, then adds the existing RTT allowance and two
frames. Thus the experiment changes duration AND its derived settling hold.
For example adv=2.0 changes 16667 -> 33334 us; adv=2.75 changes 50001 ->
45834 us. Cap four, 20-sample trimming, startup exclusion, ten-live-frame gap
and once-per-live-frame/replay guard remain. SUBFRAME_SYNC independently
controls adv < 1 and must be off in this comparison. No guest state, input,
transport, prediction limit or snapshot policy was changed.

Both arms append NETFULLSYNC to the retained NETSUMMARY line: full_sync,
time_sync, eligible_actions, actions, changed_actions, requested_ms, legacy_ms,
actual_ms, last_eligible_f/adv. Eligible means an actual >=1 correction
opportunity where the candidate duration differs from legacy; actions counts
ALL >=1 corrections in either arm, changed_actions only executed differences.
Last eligible values refer to that opportunity, not final frame. Requested
and legacy totals cover actual >=1 actions, excluding subframe corrections.
Actual time includes any wait to liveT and shift overhead, not isolated sleep.
Both arms emit NETFULLSYNC_EVENT per >=1 correction with common steady-clock
start/end, slot, f, adv, selected/legacy/candidate us, hold frames, window,
samples and remote frontier before/after. The after-action frontier is queried
during event formatting, after NETTS, rather than atomically at sleepEnd.
NETTS reports selected fractional frames truthfully. Under common DIAG=1,
NETWAIT_EVENT records prediction and
lockstep wait start/end, slot, frame, decision frontier, result, need, time and
peer-loss state. The decision frontier may predate a sync sleep; it is not a
unique input-arrival timestamp. These diagnostics add equal code paths in
both arms; their overhead is not claimed to be zero. No per-input first-arrival
telemetry was added, and it cannot be reconstructed from these events.

VERIFY_ENV.txt is exactly one ASCII line plus LF, no BOM:
TEKKEN4_NET_FULL_SYNC=1

Open / owner-only real-entry test: stage/build these exact runtime bytes,
refresh identity, and run the actual paired Mode::Net game OFF/ON through
the external verify wrapper. The wrapper must forward the file through -Env;
net_pair itself does not read it. Explicit common settings in BOTH arms:
TEKKEN4_NET_DELAY=3;TEKKEN4_NET_LOCKDELAY=7;TEKKEN4_NET_DIAG=1;TEKKEN4_NET_LOCALPAD=0
Keep RBSTART=600, TIMESYNC=1, the normal 20-sample window and RB_MODE unset/net.
All unrelated experiments equal/off, including SUBFRAME_SYNC and FAST_SYNC.
Do not put common settings only in this ON-only environment file. Retain both
full rb_frames and transport logs, params, stdout/stderr, staged runtime and
executable SHA-256 hashes and build ID. Identity hashes staged inputs rather
than the executable; the text ID alone does not prove those bytes ran.

Require OFF full_sync=0, changed_actions=0, selected us == legacy us; ON literal
activation, full_sync=1, time_sync=1, changed_actions>0 and matching events
with selected us == candidate us, adv>=1, 16667<=give_us<=66668, window=20,
hold_frames=ceil(give_us/16667). ON eligible_actions must equal changed_actions;
a peer can legitimately have no eligible actions. No changed actions leaves
the hypothesis untested. Compare event advantage distribution, repeated lead
and which peer waits, then absolute aggregate replay/depth, combined waits,
FPS and frame tails. Require meaningful workload improvement, not a better
ratio from making the other peer worse. If substantial changed actions occur
without less persistent lead/burden, the hypothesis weakens. Require zero
hash mismatches/NETDESYNC and full logs. Repeat same-role runs, then role swaps
and two physical PCs. Simulator draws follow datagram counts, so equal seeds
do not provide identical per-frame loss/jitter between arms.

Ran: tests_catalogs invoked actual tools/check_online_catalogs.ps1 once,
exit 0: both 23-tool catalogs, three root inputs and Host/Join dependencies
present. Inventory only. No new source test/model/mock is runtime evidence.
Compilation, literal activation, timing behavior, replay safety, input-arrival
chronology and performance remain UNRUN here: AGENTS.md forbids builds,
games and tools/net_* execution. No changed runtime entry ran. This candidate
has NOT met the user's real-entry test requirement; the required test is
owner-only and release acceptance remains open.

Original bytes of all three edited files are retained under
logs/runtime-full-sync/originals. Root alone edits; area agents are read-only.
No Git command, outside-tree read, deletion, patch change, build, game,
forbidden helper, server, push or release was used.

Area agents: pair_logs, verify_metrics, timesync_estimate, timesync_filter,
prediction_wait, vblank_pacing, startup_roles, input_sampling,
send_first_guards, hash_reader_wait, hash_collect, snapshot_restore,
transport_sender, transport_receiver, resend_coalesce, arrival_timestamps,
simulation_rng, scheduler_restore, early_rollback, state_serialization,
switch_entry_route, build_identity, tests_catalogs, experiment_gate.
experiment_gate independently assessed the proposed policy and found no
source-design blocker, while requiring actual changed actions and real proof.
Separate final reviewer: final_diff_review_full_sync completed the three-file
diff against retained originals with no blocking source issue. It checked OFF
duration/hold equivalence, bounded ON duration/hold, live/replay guards,
counter/event semantics, format arguments, summary retention, exact env bytes
and retained progress history. It highlighted that the after-action frontier
is not atomic with the captured wait endpoint; this is documented above.
Root also checked LF-only runtime bytes, exact environment bytes and preserved
progress suffix bytes. These are source/integrity checks, not runtime proof.

# T4 beta progress, 2026-11-02

## Current: test the steady-state time-sync deadband

Latest supplied verify: draft 627c87cafe, clean merge, 198-second build,
build ID 5f9d20dbdd2c0012, finished 2026-11-02T23:02:40. The old unchanged-ID
concern is superseded. BOOT_RENDEZVOUS really ran: both ON peers observed
f=605, target=608, local_max=609, rc=607->609, ready=1, calls=1; host/join
waited 56.045/96.173 ms. Yet join/host rollback ratio stayed 2.99 -> 3.00,
combined replay rose 4254 -> 4379 (+2.9%), and stall+sync time rose
6666 -> 7771 ms (+16.6%). This weakens a startup-only explanation. No prior
experiment becomes a default. SELFTEST still bypasses npBoundary.

Done: 24 independent area agents reviewed source/evidence, including one
running the actual catalog entry. Safe inventory found eight .log files,
all scanner/catalog output; no chronological host/join runtime pair logs.
No outside-tree location was opened. Unique input arrivals, initial lead
and first-wait order remain unknown. The summaries cannot establish cause.
Rebase differences again match extra join waits (OFF 6563 vs 6600 ms;
ON 7753 vs 7737 ms), rather than proving a separate pacing debt defect.
No fixed host/join steady-state policy, time-sync sign or counting error
was found. Prior filter/rebase/early/headroom/publication/flush experiments
already cover those mechanisms; they are not repeated here.

One new hypothesis: a persistent subframe producer phase survives the
one-frame time-sync deadband, sustaining unequal prediction exposure.
At RTT 150 ms and delay 3, nominal one-way transit beyond input delay is
about 1.5 frames. A residual phase below one frame is large relative to that
window. This is a source-based hypothesis, NOT a measured explanation of
the rollback ratio. The filtered lead estimate is quantized and delayed;
smaller corrections can chase noise, add waits and worsen performance.

Root changed runtime/tekken4_rollback_overrides.cpp behind default-off literal
TEKKEN4_NET_SUBFRAME_SYNC=1. For eligible filtered advantage 0.25 <= adv < 1,
give up adv * 16667 microseconds, truncated to integer microseconds (at least
4166 us). At adv >= 1 the existing correction arithmetic is retained. The
20-sample window, trimming, startup exclusion, ten-live-frame minimum gap,
and RTT settling hold remain: fractional corrections use one whole frame
for the hold. Host-only flags/counters stay outside snapshots. Existing
once-per-live-frame sync dispatch prevents replay from repeating a correction.
This differs from FAST_SYNC (refill length) and BOOT (one-time perturbation).

Both arms append NETSUBFRAME to the same NETSUMMARY line retained by the
pair report: subframe_sync, time_sync, eligible_evals, corrections,
requested_ms, actual_ms, last_f and last_adv. Eligible evaluations overlap;
they are NOT distinct phase episodes and are counted after filter/spacing
guards. OFF records opportunities with zero fractional corrections/time.
ON records actual actions. actual_ms includes waiting to max(now,liveT)
plus the requested interval and deadline-shift overhead; it is not isolated
sleep time. Last f/adv refer to the last eligible evaluation, not necessarily
the final frame. ON logs literal activation and NETSUBFRAME_EVENT with
steady start/end timestamps, slot, f, adv, give_us, hold_frames, window,
samples and remote frontier before/after. The before value is the frontier
snapshot passed into time sync. Events do not timestamp unique input arrivals.
Fractional actions use NETSUBFRAME_EVENT; legacy whole-frame actions use NETTS.

VERIFY_ENV.txt is exactly one ASCII line plus LF, no BOM:
TEKKEN4_NET_SUBFRAME_SYNC=1

Open / owner-only real-entry test: stage/build these exact runtime bytes,
refresh identity and run real paired netplay OFF/ON through the external
verify wrapper, varying only SUBFRAME_SYNC. net_pair does not read this file;
the wrapper must forward its content through -Env. Explicitly pass common
TEKKEN4_NET_DELAY=3;TEKKEN4_NET_LOCKDELAY=7;TEKKEN4_NET_DIAG=1 in BOTH arms.
Keep RBSTART=600, RB_MODE unset/net, TIMESYNC=1, the normal 20-sample window,
and other experiments equal/off, including BOOT_RENDEZVOUS. Record simulator
settings/seeds and effective parameters; same seeds do not imply identical
loss/jitter draws when packet counts change. Preserve full rb_frames and
transport logs, stdout/stderr, staged-source/executable hashes and build ID.

Require OFF NETSUBFRAME subframe_sync=0, corrections=0, requested_ms=actual_ms=0;
ON literal activation, subframe_sync=1, time_sync=1 and real fractional
corrections with matching events and nonzero times. Each such event must
have 0.25 <= adv < 1, give_us < 16667, hold_frames=1 and window=20.
Some peers may never enter that band: do not require fabricated actions on
both. No eligible evaluations/actions leaves the hypothesis untested; few
evaluations in OFF weakens deadband as the main cause. Align same-PC steady
timestamps to compare sampled advantage, frontiers and wait dominance before
and after actions; transport session-relative timestamps need calibration.
Require reduced absolute aggregate replay/depth and acceptable combined waits,
FPS and frame tails, rather than a better ratio alone. If substantial actions
occur but asymmetry quickly returns, the hypothesis weakens. Require zero hash
mismatches/NETDESYNC and complete logs; repeat same-role pairs, then two PCs.

Ran: tests_catalogs invoked tools/check_online_catalogs.ps1, exit 0: two
23-tool catalogs, three root inputs and Host/Join dependencies present.
Inventory only. No mock, source assertion or model is counted as runtime proof.
Compilation, actual switch activation, scheduling/peer-loss behavior, replay
safety and benefit remain UNRUN here: AGENTS.md forbids builds, games and
tools/net_* execution. No changed runtime entry ran; this is a candidate for
the owner's next real verify, not a tested fix or release acceptance.

Original bytes of the three changed files are retained under
logs/runtime-subframe-sync/originals. Root alone edits; all area agents are
read-only. No Git command, outside-tree read, deletion, patch change, build,
game, forbidden helper, server, push or release was used.

Area agents: pair_logs, verify_metrics, timesync_sign, timesync_filter,
prediction_wait, vblank_pacing, startup_roles, input_sampling,
send_first_guards, hash_reader_wait, hash_collect, snapshot_restore,
transport_sender, transport_receiver, resend_coalesce, arrival_timestamps,
simulation_rng, scheduler_restore, early_rollback, state_serialization,
switch_entry_route, build_identity, tests_catalogs, experiment_gate.
experiment_gate reviewed the implemented candidate and found no source blocker.
Separate final reviewer: final_diff_review_subframe completed the three-file
diff review against retained originals with no blocking source issue. It checked
OFF/ON scope, filter/spacing/RTT hold, replay guards, format types, summary
retention, exact environment bytes, latest arithmetic and retained history.
Root also checked LF-only runtime bytes, exact environment bytes and preserved
progress suffix. These are source/integrity checks, not runtime proof.

# T4 beta progress, 2026-11-02

## Current: test startup producer phase after the real flush comparison

Latest supplied verify: draft 7f51c79087, clean merge, 196-second build,
build ID ad61f024a887170a, finished 2026-11-02T22:43:07. The unchanged-ID
concern is superseded. SELFTEST OFF/ON: 202 good restores, 447 replay
comparisons with zero mismatches, 101/101 wrong-input divergences. Those
modes bypass npBoundary; they do not test the new experiment below.

DEFER_RESIM_FLUSH really activated: deferred boundaries equal replay frames
on both ON peers, with zero replay flushes. Aggregate rollbacks 1390 -> 1207
(-13.2%), replay 5387 -> 4492 (-16.6%), but combined stall+sync time 8282 ->
9440 ms (+14.0%). Join/host rollback ratio 2.57 -> 3.99. OFF replay flushes
cost only 92.958 ms combined; join 63.509 ms across 4368 frames. Total explicit
flush cost rose 287.077 -> 386.105 ms, moving into live flushes. This strongly
weakens flushing as the main cause. Delay also changed 2 -> 3, so the replay
reduction cannot be attributed to flushing. No previous switch becomes a default.

Evidence: 24 read-only area agents inspected separate areas. Safe inventory
found exactly eight .log files, all ZIP scanner/checker output. Chronological
host/join runtime logs are absent; no outside-tree location was opened. Unique
input arrival times, initial frame advantage and first wait order remain unknown.
Join's prediction/time-sync waits fit an ahead producer. Host-minus-join rebase
time differs by 8208 ms OFF / 9390 ms ON, nearly matching extra join stall+sync
8248 / 9406 ms: deadline accounting, not a separately proven pacing defect.
No sign, counting or fixed steady-state role error was established.

One new hypothesis: asymmetric handshake/delay-negotiation completion and
independent boot deadline shifts seed a producer phase offset; replay/producer
gaps then sustain it. Host leaves delay publication before join receives it.
Boot waits shift each local schedule separately; there is no common release
clock. This source mechanism is real, but its causal role is NOT established
by the summaries. Prior gain/filter/rebase/early/headroom experiments are not
repeated. A proposed sparse-input experiment was rejected: redundant contiguous
packet prefixes cannot normally leave later accepted inputs behind a hole.

Root changed runtime/tekken4_rollback_overrides.cpp behind default-off literal
TEKKEN4_NET_BOOT_RENDEZVOUS=1. At the first live frame strictly beyond
rbStart + (lockDelay - delay), after current input publication and after boot
prefill has drained, wait once for remote input through f + delay. Both peers
have published that target before waiting; no future local sample is required.
The transport keeps receiving/resending and the existing peer-loss return
ends the wait. Its measured duration shifts scheduler deadlines AND liveT.
The host-only once flag is set before waiting and is not restored; replay and
same-frame returns cannot repeat it. OFF observes the same boundary without
calling waitRemote or shifting deadlines. Both arms add one event and summary
fields; this small logging cost is not claimed to be zero.

This is a phase perturbation, not a synchronized start or a claimed fix. With
equal one-way transit and an entry gap smaller than transit, it can reverse
the gap. Independent lockDelay choices can give different trigger frames;
record both. Peer loss does not count as successful receipt. An observed role
swap alone is phase-sensitivity evidence, not a performance improvement.

Both arms append NETBOOT to the NETSUMMARY line retained by the pair script:
rendezvous, observed, calls, f, target, local_max, rc_before/after, ready,
wait_ms. One NETBOOT_EVENT records steady_ms/end_steady_ms and slot alongside
those frontiers. It timestamps this wait, NOT unique packet/input arrivals.
ON also logs literal activation. These counters/times are outside snapshots.

VERIFY_ENV.txt contains exactly one ASCII line plus LF, no BOM:
TEKKEN4_NET_BOOT_RENDEZVOUS=1

Owner-only real-entry test: stage/build these exact runtime bytes, refresh
identity, and run the actual same-build paired netplay OFF/ON through the
external verify wrapper. net_pair does not read this file; the wrapper must
forward its content through -Env. In BOTH arms pass common controls
TEKKEN4_NET_DELAY=3;TEKKEN4_NET_LOCKDELAY=7;TEKKEN4_NET_DIAG=1.
Keep RBSTART=600, RB_MODE unset/net, and all other experiments equal/off,
including DEFER_RESIM_FLUSH and SEND_FIRST. The file varies only RENDEZVOUS;
common settings cannot merely be inherited because net_pair clears them.
With those controls expect f=605, target=608, local_max >= 609 on BOTH peers.
Require OFF rendezvous=0, observed=1, calls=0, wait_ms=0; ON literal activation,
rendezvous=1, observed=1, calls=1, ready=1, rc_after > target. Require meaningful
wait/changed phase before interpreting the experiment; already-ready/negligible
waits or different trigger frames weaken it. Retain full rb_frames/transport
logs, params, stdout/stderr, new build identity and binary hash. The text ID
alone does not attest that the executable contains these staged bytes.

Align same-PC steady timestamps, compare lead/frontiers and wait dominance
before/after f=605 over the following 100+ frames, then final absolute aggregate
replay/depth, combined waits, FPS and frame tails. If phase changes but the
same side quickly regains sustained lead and replay burden, the seed-only
hypothesis weakens. Require zero hash mismatches/desync and complete logs.
Repeat same-role pairs because changed packet counts alter simulator RNG
consumption even with fixed seeds; then repeat on two physical PCs.

Ran: tests_catalogs invoked actual tools/check_online_catalogs.ps1 once,
exit 0, both 23-tool catalogs, three root inputs and Host/Join dependencies
present. Inventory only. No new source assertion/model/mock is counted as
runtime proof. Compilation, actual switch activation, peer-loss behavior,
replay safety and performance remain UNRUN: AGENTS.md forbids builds, games
and tools/net_* execution here. The required real-entry test is owner-only;
release acceptance remains open. No test that runs npBoundary ran here.

Original bytes of all three edited files are under
logs/runtime-boot-rendezvous/originals. Root alone edits; all area agents are
read-only. No Git command, outside-tree read, deletion, patch edit, build,
game, forbidden helper, server, push or release was used.

Area agents: pair_logs, verify_metrics, timesync_sign, timesync_filter,
prediction_wait, vblank_pacing, startup_roles, input_sampling,
send_first_guards, hash_reader_wait, hash_collect, snapshot_restore,
transport_sender, transport_receiver, resend_coalesce, arrival_timestamps,
simulation_rng, scheduler_restore, early_rollback, state_serialization,
switch_entry_route, build_identity, tests_catalogs, experiment_gate.
Separate final reviewer: final_diff_review_boot found no blocking source
issue. It independently checked publication/wait dependency, first-live/once
and replay guards, scheduler/liveT shift, peer-loss readiness, format types,
exact environment bytes and retained progress history. A no-lockstep start
can still fire the wait; the prescribed RBSTART=600 boot avoids that edge.
Root also checked LF-only runtime bytes, exact environment line and retained
progress suffix. These checks are source/integrity checks, not runtime proof.

## Current: defer ordinary replay-boundary log flushes

Latest supplied verify: draft 86c36dd1df, clean merge, build in 263 s,
build ID dbbc892dd1c14cf9, finished 2026-11-02T22:26:52. The ID changed;
the old unchanged-943fc4631acf2c13 concern is superseded. This is the first
supplied SEND_FIRST paired result, replacing the pending wording below.
SELFTEST OFF/ON reports 202 good restores, 447 replay comparisons with zero
mismatches and 101/101 wrong-input divergences. It does not prove npBoundary.

SEND_FIRST profile OFF/ON: combined replay 6073 -> 4979 (-18.0%), rollbacks
1070 -> 1149 (+7.4%), stall+sync time 11762 -> 10014 ms, run FPS 42.0 -> 46.3.
Both arms report delay 3. Join still bears the work: ON replay 4591 versus
host 388; rollbacks 964 versus 185. Join alone has prediction/time-sync
waits. The depth histograms reproduce actual replay, not duplicate counts.
OFF diagnostic/hash-profile settings and ON activation/action counters were
not supplied; packet-count changes also alter simulator loss/jitter draws.
This supports an improved ON profile, not an isolated SEND_FIRST benefit or
a proven explanation of the initial lead. Both arms report zero sampled
hash mismatches and NETDESYNC lines; this is not full release acceptance.

Evidence: 24 independent read-only area agents investigated runtime and
transport. Exactly eight .log files are present, all ZIP scanner output.
No chronological host/join runtime or transport pair logs are in this tree.
No outside-tree location was opened. Unique input first-arrival timestamps
are not recorded; packet age includes resends. Full NETDIAG logs can show
sampled frame advantage/frontier and wait chronology, but summaries cannot.
No time-sync sign, fixed role policy or snapshot-state error was found.
Boot handshake/full lockstep deadline shifts are a possible seed phase;
without transition chronology this is not established as the cause.

Single new hypothesis: synchronous ordinary log flushes on every replay
boundary amplify unequal replay workload and delay the next fresh input.
SEND_FIRST moves current publication earlier, but replay still blocks the
next live sample. The hook explicitly flushes rb_frames and optional trace
streams even on intermediate replay boundaries. The latest ON join executes
4591 replay frames versus host 388. More flush opportunities are source
facts; a material I/O delay or causal feedback loop has NOT been measured.

Root changed runtime/tekken4_rollback_overrides.cpp behind default-off literal
TEKKEN4_NET_DEFER_RESIM_FLUSH=1. Only ordinary hook-end flushes are deferred
while the post-npBoundary state remains resimulating in an active net session.
Records are still written; stdio may flush automatically as buffers fill.
Live return and failed/ended sessions use the ordinary flush path. Explicit
handshake/failure flushes and the final ordinary flush path are retained. No sampling,
transport, prediction, scheduler, snapshot or hash policy changed. Abrupt
termination during replay can lose the buffered tail; this is an opt-in
experiment, not a release default or a proven fix.

Both arms append NETFLUSH to each NETSUMMARY line so the existing pair
summary extraction retains it: defer_resim_flush,
deferred_boundaries, live_flushes/live_ms/live_max_ms and
replay_flushes/replay_ms/replay_max_ms. Timings/counters are host-only,
cumulative and outside snapshots. The live/replay bucket is the state ABOUT
TO execute after npBoundary, so the initial restore boundary belongs to
replay and its live return belongs to live. They measure only the explicit
ordinary flush block, not all log I/O, skipped time or disk durability.
Summary values exclude that boundary's subsequent ordinary flush and every
explicit flush elsewhere. Compare both buckets: ON can move buffered write
cost into the live bucket. Skipped calls alone do not demonstrate benefit.
ON logs the literal switch after handshake; OFF reports
defer_resim_flush=0 and zero deferred_boundaries.

VERIFY_ENV.txt contains exactly one ASCII line plus LF, without BOM:
TEKKEN4_NET_DEFER_RESIM_FLUSH=1

The file intentionally contains only the new experiment, so the wrapper's
with/without-the-file convention varies one setting. SEND_FIRST and earlier
experiments remain equal/off for this next isolated comparison; no new
production default is enabled. If retaining SEND_FIRST for follow-up, pass
it equally in BOTH arms and record it. Pass DELAY=3 and any DIAG/HASH_PROFILE
controls explicitly through common -Env in BOTH arms. net_pair clears
inherited TEKKEN4_/PS2X_ settings and does not read VERIFY_ENV itself.
RB_MODE must be unset or net. The external verify wrapper is absent here.

Ran: tests_catalogs invoked the actual tools/check_online_catalogs.ps1,
exit 0: both 23-tool catalogs, three root inputs and Host/Join dependencies
present. Inventory only. No source assertion, model or mock is counted as
runtime proof. Compilation, actual switch activation, buffered-log behavior,
replay safety and performance remain UNRUN here: AGENTS.md forbids builds,
games and tools/net_* execution. The requested real-entry test therefore
remains owner-only, and release acceptance stays open.

Open / owner-only: stage/build these exact runtime bytes, refresh identity,
run the real same-build paired netplay OFF/ON with common controls above.
Retain full rb_frames/transport logs, effective params, stdout/stderr and
build identity. Require literal ON activation, defer_resim_flush=1 and
increasing deferred_boundaries on BOTH peers with actual replay. OFF must
show defer_resim_flush=0, zero deferrals and nonzero replay_flushes. Low OFF
flush cost weakens this hypothesis; compare total flush cost in both buckets,
next-input producer gaps, replay p50/p90/tails, absolute aggregate replay/depth,
waits, FPS and frame tails. Zero deferrals leaves it untested. A smaller
rollback ratio alone is no win. Require zero hash mismatches/desync and
complete final logs. Repeat same-role pairs, then two physical PCs. Full
chronology is still required before claiming why one peer first gets ahead.

Original bytes for the three edited files are retained under
logs/runtime-defer-resim-flush/originals. Root alone edits them; all area
agents are read-only. No Git command, outside-tree read, deletion, patch
edit, build, game, forbidden helper, server, push or release was used.

Area agents: pair_logs, verify_metrics, timesync_sign, timesync_filter,
prediction_wait, vblank_pacing, startup_roles, input_sampling,
send_first_guards, hash_reader_wait, hash_collect, snapshot_restore,
transport_sender, transport_receiver, resend_coalesce, arrival_timestamps,
simulation_rng, scheduler_restore, early_rollback, state_serialization,
switch_entry_route, build_identity, tests_catalogs, experiment_gate.
Separate final reviewer: final_diff_review_defer_flush found no blocking
source issue. It independently checked OFF/non-net flush behavior, replay/live
guards, failure/end paths, format arguments, exact environment bytes and
preserved progress history. hash_collect and experiment_gate also reviewed
the implemented candidate. These are source reviews, not runtime proof.
Root checked LF-only runtime formatting, the environment bytes and the
retained progress suffix; the final-summary telemetry omits its own later
ordinary flush as stated above.

## Continuation: pending SEND_FIRST needs its first real result

The supplied 707a8083df / 559637893924db84 verify is the same result already
analyzed below. It tests PRED_HEADROOM, not the newer SEND_FIRST candidate.
No new paired runtime result or chronological pair logs were supplied.
Do not replace this pending hypothesis with another untested switch.

Done: 24 independent read-only area agents rechecked the runtime candidate,
transport, evidence and catalogs. No blocking source issue was found. No new
runtime code or environment settings changed this continuation. The existing
runtime change and exact VERIFY_ENV.txt line below remain the experiment to
prove. Only this progress record changed; its prior bytes are retained in
logs/runtime-send-first-followup/CODEX_PROGRESS.before.md.

Evidence precision: hashCollect inserts/compares transport hashes and performs
synchronous logging; confirmedHash updates memory, not a report file there.
HASH_PROFILE slot timing includes mutex/predicate overhead as well as reader
waiting. It is not isolated blocked time. NETDIAG packet ages include resends;
there is no unique per-input first-receipt timestamp. Full logs could establish
sampled lead and correction chronology, not complete input-arrival chronology.
Exactly eight .log files remain scanner output, not paired runtime evidence.

Ran: tests_catalogs invoked the actual tools/check_online_catalogs.ps1, exit 0:
both 23-tool catalogs, three root inputs and Host/Join dependencies present.
This checks inventory only. No changed game entry ran. Under AGENTS.md, builds,
games and tools/net_* execution remain forbidden here. The selftest dispatch
bypasses npBoundary; it cannot validate SEND_FIRST. Compilation, activation,
replay safety, packet-arrival improvement and performance remain UNRUN.

Open / owner-only: run the existing candidate through real netplay OFF/ON,
with DELAY=3, DIAG=1 and HASH_PROFILE=1 explicitly passed through common -Env
in BOTH arms. Change only SEND_FIRST. net_pair clears inherited settings;
the external wrapper must supply those controls, not merely inherit them.
Its with/without-the-whole-file convention alone changes four settings and
cannot isolate SEND_FIRST. Require ON literal activation and increasing
send_first_frames AND send_first_inputs on both peers, zero early-publication
counters OFF, and preparation samples/effective settings in both arms. Retain
full pair logs and compare absolute aggregate replay/depth, waits, FPS and
tails. Tiny preparation cost or no benefit despite meaningful publication
actions weakens this hypothesis. Repeat same-role pairs, then two PCs.

Agents: pair_logs, verify_metrics, send_first_guards, input_schedule,
snapshot_order, scheduler_restore, hash_reader_wait, hash_collect,
send_diagnostics, timesync_sign, timesync_filter, prediction_wait,
vblank_pacing, startup_roles, transport_sender, arrival_timestamps,
transport_receiver, resend_coalesce, simulation_rng, state_serialization,
switch_entry_route, build_identity, tests_catalogs, experiment_gate.
Separate final reviewer: final_diff_review_continuation_2 found no blocking
source issue; compilation and real-entry proof remain unrun.
Root alone edits progress; every area agent is read-only. No Git command,
outside-tree read, deletion, patch edit, build, game, forbidden helper,
server, push or release was used.

## Current: send fresh input before capture/hash work

Latest owner-supplied verify: draft 707a8083df, clean merge, build in 210 s,
build ID 559637893924db84, finished 2026-11-02T20:39:12. This supersedes the
incomplete excerpt immediately below and the old unchanged-943fc4631acf2c13
concern. SELFTEST OFF/ON both exercised 202 restores, 447 replay comparisons
with zero mismatches and 101/101 wrong-input divergences. Its effective mode
was not supplied; test/selfnet do not exercise npBoundary's scheduling.

PRED_HEADROOM shows no benefit in this result: aggregate replay 4272 -> 5087
(+19.1%), rollbacks 1214 -> 1409 (+16.1%). Both peers worsened. The smaller
join/host rollback ratio, 3.45 -> 2.52, is not an improvement by itself.
Combined stall+sync time fell 7765 -> 6824 ms; run FPS fell 50.1 -> 49.9.
For interpretation, negotiated delay was 3 OFF and 2 ON. Auto
delay crosses its threshold at 150 ms, the simulator's target RTT. Diagnostic
settings are also unspecified OFF. This is not an isolated headroom result,
and literal activation/action counters were not supplied. Do not claim its
mechanism is disproved or re-enable it alongside the new experiment.

Evidence limit: 24 independent read-only area agents found no paired runtime
or transport logs in this tree. The eight .log files are ZIP scanner output.
No outside-tree path was opened. Input first-arrival times, sustained frame
advantage and chronological wait order remain unknown. The summaries identify
join as the waiting side (OFF: 87 stalls, 94 sync corrections; host zero of
each), consistent with an ahead peer approaching its prediction cap. The
histograms reproduce actual replay work; this is not duplicate counting.
No time-sync sign/unit or steady-state host/join policy error was found.
Host-minus-join rebases differ by 7743 ms, versus 7765 ms extra join waits:
that is consistent with deadline accounting, not proof of a pacing cause.

Single new hypothesis: first-live snapshot/hash preparation delays fresh
input publication, so a capture/hash hitch can amplify peer prediction and
replay asymmetry. npCapture waits for hash readers BEFORE its capture timer;
the reported ~0.43 ms capture average excludes that wait. hashCollect also
runs transport/report/log work before publication. This is a source-supported
mechanism, not a demonstrated explanation of the fourfold imbalance.

Root changed runtime/tekken4_rollback_overrides.cpp behind default-off literal
TEKKEN4_NET_SEND_FIRST=1. A first live visit samples/sends through the same
f+delay (or boot lockDelay) before capture/hash collection. Replay boundaries
and returns to the same live frame reuse recorded input; liveT assignment
stays after npEndResim restores the scheduler. Captures still precede scans,
restores and final hashes. The OFF sampling/send location is retained via the
same helper. Earlier host-pad sampling can legitimately observe a different
physical input; scripted target-frame inputs are unchanged. No transport,
prediction limit, input delay policy or time-sync controller was changed.

Literal activation is logged after handshake. With DIAG=1, NETDIAG reports
send_first, cumulative send_first_frames (early publication calls),
send_first_inputs (new input samples published there), send_prep_frames,
send_prep_ms, cumulative send_prep_max_ms, and last send_prep_f/last_ms.
Preparation measures first-live capture including hash-slot wait plus
hashCollect: before send OFF, after send ON. It excludes sample/send time,
replay captures and any later waits. This is time moved out of the pre-send
path, NOT measured packet arrival improvement. send_first_frames can include
calls with no new input after priming; require send_first_inputs too. All
counters are host-only and not restored. HASH_PROFILE adds actual reader-wait
totals; low preparation/wait times would weaken this candidate's relevance.

VERIFY_ENV.txt now contains exactly one ASCII line plus LF, without BOM:
TEKKEN4_NET_SEND_FIRST=1;TEKKEN4_NET_DIAG=1;TEKKEN4_NET_HASH_PROFILE=1;TEKKEN4_NET_DELAY=3

Open / owner-only: stage/build these exact bytes in the authorized checkout,
refresh identity, and run the actual same-build OFF/ON netplay entry. The
absent outer verify wrapper must pass the file via common -Env; net_pair does
not read it. In BOTH arms set DELAY=3, DIAG=1 and HASH_PROFILE=1, varying ONLY
SEND_FIRST (OFF unset/0, ON 1). The line pins the ON profile; it cannot set the
OFF profile by itself. If the wrapper simply omits the whole line OFF, inspect
effective params and repeat with common controls before drawing a causal
conclusion. Keep PRED_HEADROOM and all other experiments equal/off, including
SIM_SAFE_WAIT; do not silently bundle a second runtime change.

Require both ON peers' literal TEKKEN4_NET_SEND_FIRST=1, send_first=1 and
increasing send_first_frames AND send_first_inputs. OFF must show send_first=0
and zero early publication counters. Require preparation samples in BOTH arms;
retain HASH_PROFILE, full rb_frames/net logs, effective params, stdout/stderr
and build identity. Align same-PC steady times and frontiers with NETTS,
producer gaps and actual waits. Packet input_age includes resends; it is not
unique input first-arrival timing. Compare absolute aggregate replay/depth,
combined wait time, FPS and frame tails on BOTH peers. Activation alone is no
benefit; tiny preparation times or unchanged poor replay with meaningful
publication actions weakens this hypothesis. Repeat same-role pairs because
packet-count changes also change simulator RNG consumption, then two PCs.

Ran: tests_catalogs executed the actual tools/check_online_catalogs.ps1,
exit 0; both 23-tool catalogs, three root inputs and Host/Join dependencies
present. This proves inventory only. No test through the changed real game
entry could run: AGENTS.md forbids builds, games and tools/net_* execution.
Compilation, switch activation, replay safety and performance remain UNRUN;
no model, mocked entry or source assertion is presented as runtime proof.
The source candidate is therefore unvalidated and release acceptance stays open.
Original bytes for the three edited files are under
logs/runtime-send-first/originals. Root alone edits these files; all area
agents are read-only. Separate final_diff_review_send_first found no blocking
source issue in OFF publication, first-live/replay guards, snapshot/scan/hash
ordering, scheduler restoration or diagnostic formats. It independently
confirmed the exact ASCII environment line and retained progress history.
Root also checked original/current LF-only runtime formatting, the environment
line's encoding and the original progress suffix. These are source/integrity
checks, not compilation or real-entry runtime proof.

Area agents: pair_evidence, timesync_sign, timesync_filter, wait_order,
vblank_pacing, prediction_budget, startup_roles, transport_poll, resend_order,
input_sampling, peer_feedback, resim_cost, state_ring, mismatch_detection,
coalescing, clock_domains, simulation_bias, diag_contention, frontier_refresh,
switch_route, build_identity, tests_catalogs, experiment_gate, arrival_telemetry.
Separate reviewer: final_diff_review_send_first. No Git command, outside-tree
read, deletion, patch edit, build, game, forbidden helper, server, push or
release was used.

## Current continuation: headroom still needs its first real paired result

Latest owner-supplied excerpt: draft de203b767d, clean merge, build completed
in 249 s, printed build ID 559637893924db84. This supersedes the old unchanged
943fc4631acf2c13 concern. The excerpt stops at switches-OFF SELFTEST: 1800 wall
and logical frames, zero rollbacks, restores, replay comparisons and wrong-input
passes. No paired result, ON activation or effective selftest settings were
supplied. A completed build and this zero-work summary do not prove rollback
restore/replay or the pending headroom experiment. No new improvement is claimed.

Done this continuation: 24 independent read-only area agents reviewed evidence,
runtime scheduling, transport and test coverage. Exactly eight .log files are
present, all ZIP scanner outputs. No host/join runtime or transport pair logs
are available here. Exact first-arrival times, sustained frame advantage and
chronological wait order remain unknown. No outside-tree path was opened.
The latest meaningful paired summary remains the EARLY_DEADLINE comparison
recorded below; no new PRED_HEADROOM comparison has been received.

No new runtime code or switch was added. Keep the existing single hypothesis:
releasing the prediction wait at its minimum frontier leaves the ahead peer
near the prediction cap; repeated deep replay then delays its next fresh
input. Existing PRED_HEADROOM requests up to two extra confirmations before
late replay. It is a pending experiment, not a fix or a proven root cause.
Replacing it before its real result would leave another hypothesis untested.
The time-sync sign is consistent with the measured-ahead peer waiting; source
review found no host/join sign inversion or count-only explanation. Sampling
and sending precede sync/prediction waits, but replay delays the NEXT sample.

VERIFY_ENV.txt is unchanged and still contains exactly:
TEKKEN4_NET_PRED_HEADROOM=1;TEKKEN4_NET_DIAG=1

Correction to earlier selftest wording below: the absent outer verify wrapper's
mode is unknown. Source dispatches RB_MODE=test to testBoundary, selfnet to
netBoundary, and net to npBoundary. Both test modes bypass the changed netplay
entry. The in-tree perf_rb_check.ps1 uses test. Do not infer the supplied run's
mode, or claim the runtime experiment was exercised, from the SELFTEST label.
Retain effective mode/start/every/depth settings and full output to explain the
zero-work selftest. That is a separate coverage gap from paired netplay proof.

Open / owner-only: build the exact staged candidate in the authorized checkout
and run the real same-build OFF/ON paired netplay entry, repeating same-role
runs. Pass the file line via common -Env; net_pair does not read this file.
Use DIAG=1 in BOTH arms; change only PRED_HEADROOM. Keep other experiments,
including SIM_SAFE_WAIT, equal. Require both ON peers' literal activation and
pred_headroom=1, plus increasing headroom waits/completions, meaningful elapsed
wait and frontier movement on the burdened peer. Zero actions leaves it untested.
Retain full paired runtime/transport logs, effective parameters and stdout/stderr.
Compare absolute replay work/depth, combined stall/sync time, FPS and frame tails
on BOTH peers. Fewer rollbacks on one side or a smaller ratio alone is no win.
Input packet age includes resends and cannot establish unique first arrivals.
The extra wait is frame-bounded, not wall-time-bounded; a live but stalled peer
can keep it waiting. Safety and pacing therefore need the actual paired run.

Other source findings do not establish the cause: the simulator's existing
SIM_SAFE_WAIT switch avoids an unlocked deque-reference hazard; synchronous
logging and hash-slot waits can delay input production. Do not silently combine
those experiments with headroom. Paired chronology is needed to distinguish
initial lead from workload amplification. No source audit substitutes for it.

Ran: tests_catalogs executed the actual tools/check_online_catalogs.ps1, exit 0;
both 23-tool catalogs and three root inputs present, Host/Join dependencies
present. This proves inventory only. Compilation, launcher/game startup,
selftest and real paired runtime-entry checks remain UNRUN here under AGENTS.md.
No runtime behavior change from this continuation needs claiming as tested.

Agents: pair_evidence, input_arrivals, timesync_sign, timesync_filter,
wait_order, prediction_budget, vblank_pacing, startup_roles, transport_poll,
resend_order, input_sampling, peer_feedback, resim_cost, state_ring,
mismatch_detection, coalescing, clock_domains, simulation_bias,
diag_contention, frontier_refresh, switch_route, build_identity,
tests_catalogs, experiment_gate. Separate final reviewer:
final_diff_review_continuation. Root alone edits this record; area agents
are read-only. No Git command, build, game, forbidden helper, patch edit,
deletion, server, push or release ran this continuation.

## Current: prediction-wait headroom after the real EARLY_DEADLINE comparison

Latest owner-supplied verify: draft 9e442d7e74, build bbf39286af338c8e,
finished 2026-11-02T17:25:31. The printed build ID changed; the old unchanged
943fc4631acf2c13 concern is superseded. EARLY_DEADLINE OFF/ON rollbacks were
host 212/233, join 969/961; replay frames host 304/444, join 4109/4010.
Aggregate replay rose 4413 to 4454. Join early rollbacks fell 880 to 280,
but late rollbacks consequently rose 89 to 681. This mostly moved correction
work and did not demonstrate a benefit. Full activation/opportunity logs
were not supplied. Both arms reported zero hash mismatches and NETDESYNC.

Done: 24 independent area agents audited runtime, transport and tests/catalogs.
There are still no paired runtime/transport logs in this tree: the eight .log
files are scanner outputs. No outside-tree log path was opened. Exact input
first-arrival times, sustained frame advantage and chronological wait order
remain unknown. Latest OFF join/host rollback ratio is 4.57, replay ratio
13.52; the depth histograms reproduce the actual reported work. Join is the
waiting side in these summaries: 117 prediction stalls and 96 sync corrections,
versus host zero of each. Host-minus-join discarded pacing time nearly equals
join wait time; that is consistent with deadline accounting, not proof that
host pacing caused the imbalance. No root cause is proved.

Single new hypothesis: releasing a prediction-limit wait at its minimum
frontier leaves the ahead peer at the prediction cap, sustaining deep replay
and delaying its next input production. Default maxPred=8 permits nine
consecutive predicted inputs, including the current frame. The join OFF
histogram has 98 depth-nine rollbacks versus host zero. Existing time sync
runs only once per live frame; its corrections and the earlier early-deadline
experiment do not restore prediction headroom at the wait's release.
This is a testable workload-amplification hypothesis, not an explanation of
which peer first gets ahead. Same-PC foreground/GPU scheduling remains a
possible initial cause. Summaries cannot establish its chronology.

Root changed runtime/tekken4_rollback_overrides.cpp behind default-off literal
TEKKEN4_NET_PRED_HEADROOM=1. After the existing prediction-wait call returns,
if its confirmed frontier is below min(f+1, need+2), ON waits for that target
before scanning/replaying. It requests at most two further confirmed inputs,
never beyond current input f. Both peers already sample and send through
f+delay before waiting; no future sample is required. Lockstep waits retain
their existing target. The ring size, maximum prediction limit, input delay,
input values, time-sync controller and transport stay the same. Extra elapsed
time is included in the existing stall total and deadline shift. OFF adds
diagnostics but no extra wait. This can add stalls and worsen pacing; it is
an unvalidated runtime candidate, not a demonstrated fix.

An existing wait call can return immediately because its rc snapshot was stale
after time sync. Thus the trigger is that existing branch/call, not proof of
a physically blocking baseline wait. It does not scan and discard a mismatch:
checked, hashNext, logical frame and ring slots do not advance during waiting.
The existing late scan still corrects state before final hashes/live inputs.
The second wait retains existing peer-loss handling. Its target is bounded
in input frames, not in elapsed milliseconds; it may wait until peer loss.

Runtime activation prints the literal switch after handshake. New one-second
NETDIAG reports pred_headroom plus cumulative headroom_opportunities (baseline
prediction-wait returns short of the extra target, in either arm),
headroom_waits (extra calls, ON only), headroom_completed (returned frontier
reached target), headroom_requested (sum of target minus frontier at extra-call
entry, one or two each) and headroom_wait_ms (extra-call elapsed time).
headroom_f/rc/need/target describe the LAST extra call; rc is before->after.
These are host-only counters, not restored. Completion alone can be an
immediate return and proves no actual blocking; inspect elapsed time too.
The existing wait_need and long-wait message use the effective target.
No per-input first-arrival telemetry was invented.

VERIFY_ENV.txt contains exactly one line:
TEKKEN4_NET_PRED_HEADROOM=1;TEKKEN4_NET_DIAG=1

Open / owner-only: stage these reviewed bytes into the authorized validation
checkout, build and refresh identity, then run actual selftest and repeated
same-build OFF/ON pairs through tools/net_pair.ps1. The absent outer wrapper
must pass the file line via common -Env; net_pair does not read the file.
Use DIAG=1 or TimingDiag in BOTH arms; vary only PRED_HEADROOM. Keep
EARLY_DEADLINE, FAST_SYNC, LIVE_LEAD, ORDERED_LEAD, REBASE_CATCHUP, REFRESH_RC
and other experiments equal/off; retain ordinary early rollback, existing
MAXPRED and delay. Peer overrides must not replace the common experiment.
Retain full paired runtime/transport logs, stdout/stderr and effective params.
Build/source IDs and requested parameters alone do not prove code activation.

Require literal TEKKEN4_NET_PRED_HEADROOM=1 and pred_headroom=1 on BOTH ON peers.
On the burdened peer require headroom_waits and headroom_completed to increase,
with meaningful headroom_wait_ms and rc reaching target. OFF must show
pred_headroom=0 and zero waits/completed/requested/wait_ms; opportunities may
be positive. Zero ON opportunities/actions leaves the mechanism unexercised.
Align same-PC steady_ms/frame/frontier with NETTS, sync_eval_f, progress/local
gaps and actual waits. Determine whether extra confirmations reduce repeated
deep work; packet input_age includes resends and is not first-arrival timing.
Compare absolute rollback/replay totals and depth distribution, total stall
plus sync time, run FPS and displayed-frame tails on both peers. A smaller
ratio, fewer early rollbacks or more waiting alone is no win. Similar poor
behavior despite exercised headroom weakens this hypothesis. Repeat same-PC
runs, then two physical PCs; role swaps also change input/simulator streams.

Compilation, selftest and real OFF/ON runtime-entry testing remain UNRUN here:
AGENTS.md forbids builds, games and tools/net_* execution. This request's real
entry proof therefore remains owner-only; no model/source test substitutes
for it. Selftest dispatches to netBoundary, not npBoundary/npTimeSync. The
tests_catalogs agent ran the actual check_online_catalogs.ps1: exit 0, both
23-tool catalogs, three root inputs and Host/Join dependencies present. This
proves inventory only, not any changed runtime behavior. Source safety reviews
by prediction_budget and state_ring found no blocker; that is no runtime pass.
Original bytes for the three edited files are in
logs/runtime-pred-headroom/originals. Root alone edits runtime, VERIFY_ENV and
this record; area agents are read-only. Separate final diff review found no
blocking source issue in OFF behavior, literal activation, target bounds,
peer-loss handling, stall/deadline accounting, ring/hash/mismatch ordering or
diagnostic formats. It confirmed the exact ASCII environment line plus LF,
no BOM, and unchanged prior progress history. This does not prove compilation,
runtime safety, switch activation or benefit in a game run.

Area agents: pair_evidence, timesync_sign, timesync_settling, peer_feedback,
input_arrivals, wait_order, vblank_pacing, prediction_budget, startup_roles,
resim_cost, transport_poll, resend_order, switch_route, tests_catalogs,
build_identity, clock_domains, simulation_bias, input_sampling, telemetry,
state_ring, mismatch_detection, coalescing, diag_contention, frontier_refresh.
Separate reviewer: final_diff_review_pred_headroom. No Git command,
outside-tree read, deletion, patch edit, build, game, forbidden helper,
server, push or release ran this continuation.

## Current: deadline-first early rollback after the real FAST_SYNC comparison

Latest owner-supplied verify: draft 950e73dce1, build 86157305ed349c48,
finished 2026-11-02T17:02:36. The printed build ID changed; the old unchanged
943fc4631acf2c13 concern is superseded. FAST_SYNC OFF/ON rollbacks were host
245/238, join 961/917; resim frames host 346/422, join 3894/3795. Join sync
corrections rose 95 to 151 and stall time rose 4453 to 5173 ms. More frequent
corrections did little to resolve the imbalance. Both arms reported zero
hash mismatches and NETDESYNC lines. Full activation logs were not supplied.

Done: 25 independent area agents audited runtime, transport, evidence and
tests/catalogs. No paired runtime/transport logs exist in this tree; its eight
.log files are scanner output. No outside-tree log path was opened. Exact
input first arrivals, sustained advantage and chronological wait order remain
unknown. All four depth histograms reproduce actual rollback/resim work.
The host's extra discarded pacing time nearly equals the join's extra waits;
this is consistent with pacing accounting, not proof of a slow-host cause.

Single new hypothesis: overdue early rollbacks repeatedly postpone time sync
and the prediction wait, letting the ahead peer replay separately as inputs
arrive instead of first yielding and batching corrections. The early loop
currently scans and starts rollback BEFORE checking liveT. A resim return can
therefore start another early rollback after that deadline. Early rollback
counts alone do not show replay happened in spare vblank time. The supplied
878/799 join early rollbacks make this worth testing, but do not prove chains.

Root changed runtime/tekken4_rollback_overrides.cpp behind default-off literal
TEKKEN4_NET_EARLY_DEADLINE=1. At an expired liveT it skips the early scan and
reaches existing sync/prediction waiting before the existing late scan. It
does not call npScan and discard a mismatch: checked remains pending. Late
correction still precedes final hashes and live input selection. No logical
frame/ring slot advances during this deferral. Input samples, transport,
prediction limit, controller gains and deadlines are unchanged. OFF retains
its scheduling decisions, with added diagnostics. This candidate may merely
move replay later or worsen frame tails; it is not a demonstrated fix.

Activation logs the literal switch after handshake. An additional one-second
NETDIAG line in both arms reports early_deadline and cumulative counters:
early_due_skips counts expired early scans skipped; early_due_revisits is its
subset after an earlier early rollback at that same live frame;
early_overdue_rb counts early rollbacks started after liveT, with
early_overdue_revisits the subset after an earlier early rollback there;
early_deferred_late counts successful late rollbacks at a skipped live frame,
including repeated late replays. Skips alone do not prove a mismatch was
pending at the skipped instant. Scan overhead can cross liveT after the ON
precheck, so early_overdue_rb need not be exactly zero ON. Counters are
host-only and not restored. No per-input first-arrival telemetry was invented.

VERIFY_ENV.txt contains exactly one line:
TEKKEN4_NET_EARLY_DEADLINE=1;TEKKEN4_NET_DIAG=1

Open / owner-only: stage these reviewed working-tree bytes, build and refresh
identity, then run actual selftest and repeated same-build OFF/ON pairs through
tools/net_pair.ps1. The absent outer wrapper must pass the file line via common
-Env; net_pair does not read the file itself. Keep DIAG=1 or TimingDiag in BOTH
arms and only EARLY_DEADLINE different. Keep FAST_SYNC, LIVE_LEAD, ORDERED_LEAD,
REBASE_CATCHUP, REFRESH_RC and other experiments equal/off. Leave ordinary early
rollback enabled. Peer overrides must not replace the common experiment.
Retain full paired runtime/transport logs, stdout/stderr and effective params.
The printed source ID and params alone do not prove executable activation.

Require literal activation and early_deadline=1 on both ON peers. OFF should
show early_deadline=0 and zero early_due_skips, early_due_revisits and
early_deferred_late. On the
burdened OFF peer require early_overdue_rb>0, and early_overdue_revisits>0 to
support repeated overdue chains specifically. ON should exercise
early_due_skips and early_deferred_late; early_due_revisits>0 demonstrates a
return from early resim was deferred. Zero opportunity counters leave the
mechanism unexercised or weaken it; skip counts without late corrections are
not proof of changed rollback work. Compare dated NETDIAG/NETTS, transport
progress/local gaps, actual waits, absolute rollback/resim totals and depths,
stalls, run FPS and displayed-frame tails. A smaller ratio or early count
alone is no win. Similar poor behavior with the branch exercised weakens the
hypothesis. Repeat same-PC runs, then two physical PCs; role swaps also change
input/simulator streams. Full first-arrival timing remains unavailable.

Compilation, selftest and real OFF/ON entry validation remain UNRUN here:
AGENTS.md forbids builds, games and tools/net_* execution. No fake harness,
source assertion or catalog result is counted as runtime proof. Selftest
dispatches through netBoundary, not npBoundary/npTimeSync. The tests/catalogs
agent ran the real check_online_catalogs.ps1: exit 0, both 23-tool catalogs
and three root inputs; this proves only catalogs. Owner validation must prove
compilation, switch activation, safety and benefit before enabling by default.
Original bytes for the three edited files are in
logs/runtime-early-deadline/originals. Root alone edits runtime, VERIFY_ENV and
this record; all area agents are read-only. Separate final diff review found
no blocking source issue in OFF behavior, parsing/activation, checked, late
correction, hashes/ring, counter formats, exact environment line and preserved
history. Its one wording clarification now spells out the three zero OFF
counters; early_overdue_revisits may be positive OFF. Review does not prove
compilation or runtime safety/benefit. No Git command, outside-tree read,
deletion, patch edit, build, game,
forbidden helper, server, push or release ran this continuation.

Area agents: pair_evidence, timesync_sign, timesync_settling, peer_feedback,
input_arrivals, wait_order, vblank_pacing, prediction_budget, startup_roles,
resim_cost, transport_poll, resend_order, switch_route, tests_catalogs,
build_identity, clock_domains, simulation_bias, input_sampling, telemetry,
state_ring, mismatch_detection, coalescing, diag_contention, frontier_refresh,
experiment_falsification. state_ring retried after a capacity failure;
timesync_sign, prediction_budget and transport_poll supplied findings before
their final response hit capacity. Separate reviewer: final_diff_review_early_deadline.

## Current: shorter time-sync window after the real LIVE_LEAD comparison

Latest owner-supplied verify: draft 7c12b4b5ba, build 09ae6812c84e6c3e,
finished 2026-11-02T16:42:35. The changed printed ID supersedes the old
unchanged-ID concern. LIVE_LEAD OFF/ON rollbacks were host 217/212,
join 987/979; resim frames host 426/466, join 4062/4478. Join had 132/150
stalls and 94/95 time-sync corrections; host had none. Both arms reported
zero hash mismatches and NETDESYNC lines. This weakens stale send-time lead
as the explanation; full activation/change diagnostics were not supplied.

Done: 25 independent read-only area agents reviewed runtime, transport,
evidence and tests/catalogs. No paired runtime logs are in this tree. Its
eight .log files are scanner output. Exact per-frame first-arrival times,
sustained advantage and chronological wait order cannot be reconstructed.
The histograms reproduce actual rollback/resim work, not a counting artifact.
No root cause is proved. No outside-tree log path was opened.

Single new hypothesis: the ahead peer reacquires time-sync feedback too
slowly after yielding, allowing its lead and prediction debt to rebuild.
npTimeSync clears the lead window after each correction, suppresses samples
for correction frames plus one RTT plus two frames, then requires twenty
fresh live samples. At RTT 150 ms this permits roughly 31-34 live frames
between corrections, while prediction reaches depth nine. The supplied join
waits and larger host discarded pacing debt fit that mechanism, but do not
prove it. Dedicated transport threads keep receiving during main-thread waits.

Root changed runtime/tekken4_rollback_overrides.cpp behind default-off literal
TEKKEN4_NET_FAST_SYNC=1. It uses eight lead samples rather than twenty,
trimming one from each tail instead of four. This saves twelve refill frames.
The RTT settling hold, startup exclusion, correction threshold/gain/cap and
minimum spacing remain the same. Input, prediction budget, wire format and
transport are unchanged. Shorter filtering can react to noise and add waits;
this is an unvalidated experiment, not a demonstrated fix.

Runtime activation logs the literal switch. One-second NETDIAG now appends
sync_fast, sync_window, sync_eval, sync_eval_f, sync_early_eval and
sync_early_corrections. Counters are cumulative: early means evaluation or
correction with fewer than twenty samples, including first acquisition after
startup. sync_eval_f dates the last computed adv; adv is stale during refill.
NETTS appends window, samples and logical-frame gap from the previous
correction (zero for the first). Existing inspected collectors retain these
prefixes; the outer verify wrapper is absent and could not be checked.

VERIFY_ENV.txt contains exactly one line:
TEKKEN4_NET_FAST_SYNC=1;TEKKEN4_NET_DIAG=1

Open / owner-only: stage this working-tree runtime, build once and regenerate
identity, then run the actual selftest and same-build OFF/ON pair through
tools/net_pair.ps1. No script change is needed. Pass the line through common
-Env; peer overrides must not replace it. Keep DIAG=1 or TimingDiag in BOTH
arms. Only FAST_SYNC differs; keep LIVE_LEAD, ORDERED_LEAD, REBASE_CATCHUP,
REFRESH_RC and other experiments equal and off. Keep full host/join runtime
and transport logs, stdout/stderr and effective params. A printed source ID
alone does not prove executable activation.

Require literal TEKKEN4_NET_FAST_SYNC=1 activation and sync_window=8 with
sync_early_eval>0 on BOTH ON peers after startup. This may plateau after
first acquisition on a peer that never yields; require renewed increments
on the repeatedly yielding peer. OFF must show sync_window=20 and zero
early counters. Require sync_early_corrections>0 on
the yielding ON peer to show that reduced refill changed correction timing;
zero leaves that action unexercised. Compare NETTS gaps and samples, dated
advantage, contiguous progress/input/local gaps, actual waits, absolute
rollback/resim work, stalls, run FPS and displayed-frame tails. Input packet
ages include repeats, not per-frame first arrivals. More corrections alone
or a smaller rollback ratio proves no benefit. Similar poor behavior despite
exercised earlier correction weakens this hypothesis. Repeat same-PC pairs,
then two physical PCs. Packet draws depend on send timing, so OFF/ON need
repeats; role swaps also change simulator and input streams. Changed noise
filtering is a confound: earlier correction alone does not prove latency as
the unique cause.

Compilation, selftest and real OFF/ON runtime validation remain UNRUN here:
AGENTS.md forbids builds, games and tools/net_* execution. Selftest uses a
different boundary and cannot test npTimeSync. No model or source test was
substituted. The tests/catalogs agent ran check_online_catalogs.ps1: exit 0,
both 23-tool catalogs and three root inputs; that proves no runtime behavior.
Original bytes are in logs/runtime-fast-sync/originals. Root alone edits the
runtime, VERIFY_ENV and this record. Separate final diff review found no
blocking source issue in OFF behavior, array bounds, switch parsing,
activation, formats/counters, exact environment line or preserved history.
This source review does not prove compilation, activation or runtime benefit.

Area agents: pair_evidence, timesync_control, input_arrivals, wait_order,
vblank_pacing, prediction_budget, startup_roles, resim_cost, transport_poll,
resend_order, peer_feedback, switch_route, tests_catalogs, build_identity,
clock_domains, simulation_bias, input_sampling, telemetry, state_ring,
mismatch_detection, coalescing, diag_contention, frontier_refresh,
controller_recovery, experiment_falsification.
Separate reviewer: final_diff_review_fast_sync.
No Git command, outside-tree read, deletion, patch edit, build, game,
forbidden helper, server, push or release ran this continuation.

## Current: send-time lead experiment after ordered-lead comparison

Latest owner-supplied verify: draft d17f6d8031, build e50c0af46744c322,
finished 2026-11-02T16:23:01. The printed build changed; the old unchanged-ID
concern is superseded. Ordered-lead OFF/ON rollbacks were host 223/212,
join 965/973; resim frames host 468/461, join 4110/4054. Join still had
126/132 stalls and 93/95 time-sync corrections, versus host 0 stalls and
2/0 corrections. Both arms reported zero hash mismatches and NETDESYNC lines.
This weakens the ordering hypothesis. Full activation/rejection diagnostics
were not supplied, so whether that branch changed feedback is still unknown.

Done: 24 independent read-only area agents checked runtime, transport,
evidence and tests/catalogs. The eight .log files in this tree are ZIP scanner
outputs, not paired runtime logs. Exact input first-arrival times, sustained
advantage and actual wait ordering cannot be reconstructed from summaries.
The imbalance is real work: all four depth histograms reproduce the reported
rollback and resim totals. Predicted-input counts include resimulation;
early rollback figures are subtotals. No root cause is proved.

New single hypothesis: a slow sender keeps advertising an inflated old lead
while remote inputs arrive during resimulation or waits. Its ahead peer then
underestimates its advantage and yields too little, predicting deeper. Both
boundary sends precede npTimeSync/setLead. The resend thread keeps that stored
value until the next live estimate; ORDERED_LEAD cannot fix stale content in
newer envelopes. Root added default-off TEKKEN4_NET_LIVE_LEAD in
runtime/tekken4_net.cpp: sample signed localMax - remoteContig under the
transport mutex for each outgoing INPUT, with the existing +/-100 clamp.
At steady live boundaries this equals the current mine formula. Keep zero
startup feedback until the first setLead. Lockstep prefill briefly adds
lockDelay-delay; existing tsFrom excludes that transition from sampling.
No input, wire layout, controller gain or wait policy was changed.

Both arms now log a separate bounded-size NETDIAG line: lead_live,
lead_send_cached, lead_send_fresh, lead_send_diff, lead_send_changed and
lead_send_delta_max. The values are from the last attempted INPUT send;
counters are cumulative after coalescing, before simulated loss/delivery.
A changed send does not prove that packet was delivered or affected a wait.

VERIFY_ENV.txt contains exactly one line:
TEKKEN4_NET_LIVE_LEAD=1;TEKKEN4_NET_DIAG=1

Open / owner-only: stage this working-tree runtime, build once and regenerate
identity, then run the real selftest and same-build OFF/ON pair. The actual
live entry is tools/net_pair.ps1. Selftest and catalog checks do not enter
npBoundary/npTimeSync. Pass the file line through common -Env. Keep DIAG=1
(or TimingDiag) in BOTH arms; only LIVE_LEAD differs. Keep ORDERED_LEAD,
REBASE_CATCHUP and every other experiment equal and off. Peer overrides must
not replace the common experiment. Retain complete paired runtime/transport
logs, stdout/stderr and effective params. Require both ON peers' literal
TEKKEN4_NET_LIVE_LEAD=1 activation, lead_live=1 and increasing lead_send_changed
after lockstep/tsFrom warmup, with nonzero delta. OFF lead_send_changed must stay zero;
lead_send_diff measures the stale-feedback opportunity in either arm.
Compare cached/fresh direction, input/progress/local gaps, estimated advantage,
NETTS corrections, actual waits, absolute rollback/resim work and displayed
pacing. More corrective yielding can be expected; fewer corrections or a
smaller rollback ratio alone is no win. Similar poor behavior with altered
feedback weakens this hypothesis. Repeat same-PC runs, then two physical PCs.

Compilation, selftest and real pair validation of this change remain UNRUN here:
AGENTS.md forbids builds, game and tools/net_* execution in this copy. This
is an unvalidated default-off candidate, not a demonstrated fix. No model,
source checker or catalog pass is counted as runtime evidence. Original bytes
for this continuation are in logs/runtime-live-lead/originals. Root alone
edits runtime, VERIFY_ENV and this progress record. Separate final diff review
found no blocking source issue in signed math, locking, startup, OFF feedback,
wire layout, counters, diagnostic bounds, exact environment line or preserved
progress history. It cannot replace compilation or real-entry validation.

Area agents: pair_evidence, timesync_sign, lead_estimator, peer_feedback,
input_arrivals, wait_order, vblank_pacing, polling_delivery, prediction_budget,
startup_roles, resim_cost, resend_order, switch_route, tests_catalogs,
build_identity, clock_domains, simulation_bias, input_sampling, telemetry,
state_ring, mismatch_detection, coalescing, diag_contention, frontier_refresh.
Separate reviewer: final_diff_review_live_lead. No Git command, outside-tree
read, deletion, patch edit, build, game, forbidden helper, server, push or
release ran this continuation.

## Current: ordered peer-lead experiment after the real catchup comparison

Latest owner-supplied verify: draft 657b040128, build a597efc21b859a12,
finished 2026-11-02T16:03:33. The printed build ID changed. Catchup OFF/ON
rollbacks were host 239/234, join 963/964; join time-sync corrections stayed
94. ON increased join resim frames from 3963 to 4141 and stall time from
4489 to 7531 ms. Both arms reported zero hash mismatches and NETDESYNC lines.
These supplied real runs supersede the old unrun-catchup status below and
weaken the catchup hypothesis. Full logs are absent, so branch activation
and equal diagnostic settings cannot be independently checked here.

Done: 25 independent read-only area agents checked runtime and evidence,
including tests/catalogs. Inventory found no raw paired logs in this tree;
the eight .log files are scanner output. Input first-arrival times, sustained
advantage and exact wait ordering cannot be recovered from the summaries.
No cause of the one-sided rollback burden is proved.

New hypothesis: reordered INPUT packets replace newer peer-lead feedback,
distorting which peer yields time. Input ACK/progress is monotonic, but the
old receive path assigned peerLeadV from every packet. Root added the
default-off TEKKEN4_NET_ORDERED_LEAD switch in runtime/tekken4_net.cpp. It
ignores only lead metadata when the packet ACK or first+count falls below
the observed high-water marks. Input, ACK, hash and delay processing continues.
No wire format or controller gains changed. Equal-frontier reorder remains
indistinguishable without a packet sequence; this is a bounded experiment,
not a proved fix. NETDIAG now includes cumulative lead_stale, lead_stale_diff,
lead_rejected and the metadata high-water marks in both arms.

VERIFY_ENV.txt now contains exactly one line:
TEKKEN4_NET_ORDERED_LEAD=1;TEKKEN4_NET_DIAG=1

Open / owner-only: stage this working-tree runtime, build once and regenerate
identity, then run the real selftest and same-build OFF/ON pair. The actual
entry is tools/net_pair.ps1; do not substitute catalogs or a model test.
Pass the file line through common -Env. Keep TimingDiag/DIAG=1 in BOTH arms,
the previous catchup switch OFF in BOTH, and every other setting equal.
Peer overrides must not replace the common experiment. Keep full paired
runtime/transport logs, stdout/stderr and effective params. Require both ON
peers' literal TEKKEN4_NET_ORDERED_LEAD=1 activation, lead_ordered=1, and
nonzero lead_rejected plus lead_stale_diff to demonstrate altered feedback.
Zero rejections leaves the mechanism unexercised; rejections without a
different value do not demonstrate changed pacing feedback. Compare lead,
frontier/input gaps, NETTS corrections and actual waits, absolute rollback
and resim work, stalls and displayed pacing. Similar bad results despite
changed feedback weaken this hypothesis. A smaller ratio alone is no win.
Repeated same-PC runs and then two physical PCs remain necessary.

Compilation, selftest and the new real OFF/ON entry are UNRUN here. AGENTS.md
forbids their build/game/network entries. No substitute test was counted as
runtime validation; this candidate still needs its first real-entry test.
Original bytes for this change are in logs/runtime-ordered-lead/originals.
Only root edits runtime, VERIFY_ENV and this record; all area agents are
read-only. Separate final diff review completed with no blocking source
issue found. It checked the original/current changes, switch default and
parsing, metadata-only filtering, diagnostic format/buffer bounds, exact
VERIFY_ENV line and unchanged historical progress. This was source review,
not compilation or runtime validation.

Area agents: pair_evidence, timesync_sign, peer_lead_order, local_advantage,
input_arrival, wait_order, vblank_pacing, transport_poll, prediction_budget,
role_startup, resim_cost, resend_order, switch_route, tests_catalogs,
build_identity, clock_domains, simulation_bias, input_sampling, telemetry,
state_ring, mismatch_detection, coalescing, diag_contention, frontier_refresh,
experiment_design. Separate reviewer: final_diff_review_ordered_lead.
No Git command, outside-tree read, deletion, patch edit, build, game,
forbidden helper, server, push or release ran this continuation.

## Current continuation: real-entry evidence is still missing

Done this continuation: 24 read-only area agents reviewed independent runtime
and evidence paths, including one tests/catalog agent. No new runtime change
or test pass is claimed. The 14 latest-verify/runtime/release-b13 directories
and 14 supplied-* directories contain no .log files. The latest existing-name
refusal launched no pair. The recorded 206/874 are
early rollback subtotals; total rollbacks were 209/989. Neither supplies input
arrival timing, sustained advantage or actual wait ordering.

The pending hypothesis stays unchanged: full pacing rebases discard the slow
sender's catchup headroom. Resimulation preserves the saved live deadline;
the existing default-off experiment retains 33.334 ms at the >50 ms guard.
Source review found no blocking defect, but cannot establish causality.
Runtime and VERIFY_ENV.txt are unchanged. The switch line remains exactly:
TEKKEN4_NET_REBASE_CATCHUP=1;TEKKEN4_NET_DIAG=1

Open / owner-only: preserve existing output and choose a fresh unused name.
Stage the working-tree runtime into the real runner before building and
regenerating identity. tools/input_build.cmd stages committed HEAD; it can
omit this edit. The actual outer verify route is absent, so stale staging is
a risk, not a proved explanation. An unchanged printed ID does not prove an
unchanged executable: net_pair reads an existing sidecar and preserves an
explicit TEKKEN4_NET_BUILD; input_build does not regenerate identity. The
identity tool hashes staged source, not executable bytes. Regenerate identity
after staging/building. Use one new build for OFF/ON, with an ID different
from 943fc4631acf2c13. Keep TimingDiag, scripts, simulation and all
other switches equal; pass the line through common -Env without peer overrides
replacing it. Require both ON peers' literal activation and nonzero
NETREBASE_CATCHUP rebases. Retain full host/join runtime and transport logs,
stdout/stderr and effective params. Compare sustained lead, sender gaps,
confirmed progress, actual waits, absolute rollback/resim work and pacing.
Comparable problems with ON exercised weaken the hypothesis; a lower ratio
or rebase counter alone proves no benefit.

Compilation, selftest and real OFF/ON entry remain UNRUN. AGENTS.md forbids
their required build/game/network entries here. Selftest and catalogs never
enter the live pacing guard. No unrelated green check replaced runtime proof.
Only this current-status section changed; root is its sole editor. Further
source audits cannot substitute for the missing paired real-entry run.

Area agents: verify_pair_evidence, catchup_guard, timesync_order,
advantage_estimator, input_arrivals, vblank_deadlines, transport_delivery,
prediction_waits, startup_roles, resim_deadline, resend_order, env_route,
tests_catalogs, build_identity, clock_domains, simulation_streams,
input_sampling, catchup_telemetry, state_ring, mismatch_detection,
send_coalescing, diagnostic_contention, frontier_refresh,
experiment_falsification. Separate final reviewer: final_diff_review.
All are read-only and follow
AGENTS.md. No Git command, outside-tree read, deletion, patch edit, build,
game, forbidden helper, server, push or release ran this continuation.

## Current status: catchup experiment still has no real verify

Done this continuation: 24 read-only area agents checked separate runtime,
evidence and test areas. The 14 retained latest-verify/runtime/release-b13
directories still contain no .log files. The supplied existing-name refusal
launched no pair. Input arrival timing, sustained advantage and which peer
actually waited remain unknown. No cause of the 206/874 imbalance is proved.

The pending default-off runtime change remains the single experiment.
Hypothesis: full deadline rebases discard the slow sender's catchup headroom;
the ahead peer predicts further, rolls back more and waits. Resimulation
restores the saved live deadline, leaving elapsed work as debt. The experiment
retains 33.334 ms at the >50 ms guard. Source supports this mechanism, not its
causal role or benefit. No new runtime edit or test pass is claimed.

Open / owner-only: preserve existing output and choose a fresh unused name.
Stage the working-tree runtime into the actual runner, build and regenerate
identity. input_build.cmd stages committed HEAD and can omit this edit;
the outer verify route is absent, so whether staging omitted it is unknown.
Use the same new build for OFF and ON, with an ID different from
943fc4631acf2c13. Identity hashes staged source, not executable bytes.
VERIFY_ENV.txt remains exactly one line:
TEKKEN4_NET_REBASE_CATCHUP=1;TEKKEN4_NET_DIAG=1
Pass through common -Env; peer overrides must not replace it. Keep TimingDiag,
scripts, simulation and every other switch equal across both arms. Require
both ON peers' literal activation and nonzero NETREBASE_CATCHUP rebases.
Retain full paired logs and effective params. Compare sustained lead, sender
gaps, frontier progress, actual waits, absolute rollback/resim work and pacing.
Lower ratios or rebase totals alone prove no improvement. Comparable problems
with ON exercised weaken the hypothesis. Repeat runs; role swaps also change
simulation streams and input scripts.

Compilation, selftest and real OFF/ON runtime entry remain UNRUN: AGENTS.md
forbids the required build/game/network entries here. Only Mode::Net reaches
the live pacing guard; selftest and catalog checks do not. No substitute green
check ran. Only this progress section changed; runtime and VERIFY_ENV did not.

Area agents: pair_logs_pass, catchup_guard_pass, timesync_pass, advantage_pass,
arrival_pass, vblank_pass, poll_delivery_pass, prediction_pass, roles_pass,
resim_pass, resend_pass, env_route_pass, tests_catalogs_pass,
build_identity_pass, clocks_pass, simulation_pass, sampling_pass,
telemetry_pass, state_ring_pass, mismatch_pass, coalescing_pass,
diag_contention_pass, frontier_refresh_pass, falsification_pass.
Separate final reviewer: final_diff_review_pass found no blocking source issue;
runtime proof remains unrun. All agents are read-only; root alone edits this
record. No Git command, outside-tree read, deletion,
patch edit, build, game, forbidden helper, server, push or release ran here.

## Current refusal: stage the pending runtime before the next verify

Done: 24 read-only area agents checked independent runtime/evidence paths.
No raw .log files exist in the 14 latest-verify*, runtime* and release-b13
evidence directories. The supplied existing-name refusal did not launch a
pair. Arrival timing, sustained advantage and actual wait ordering remain
unknown. No runtime fix, causal proof or test pass is claimed this pass.

Concrete staging risk: tools/input_build.cmd stages committed HEAD overrides,
so that route can omit the pending working-tree runtime edit. This helper was
read, not run; the absent outer verify wrapper prevents identifying the route
actually used. tools/t4_buildid.py hashes staged runner source, not executable
bytes. An unchanged ID is consistent with stale staging but does not prove it.

Open / owner-only: preserve existing output; use a fresh unused verify name.
Stage the pending runtime source, build once, then run that same new build OFF
and ON with equal diagnostics, scripts, simulation and all other switches.
Require an ID different from 943fc4631acf2c13, both ON peers' literal activation
and nonzero NETREBASE_CATCHUP rebases. VERIFY_ENV.txt remains exactly:
TEKKEN4_NET_REBASE_CATCHUP=1;TEKKEN4_NET_DIAG=1
Pass it through common -Env without peer overrides replacing it. Retain full
paired logs and effective params. Test whether retained catchup debt reduces
sustained lead, sender gaps, actual waits and absolute rollback/resim work.
Lower rebase totals or a smaller rollback ratio alone prove no improvement.

Compilation, selftest and real OFF/ON pair remain UNRUN under AGENTS.md.
The tests/catalog agent confirmed that selftest and catalog checks never enter
the live pacing guard. No substitute check was counted as runtime validation.
Runtime and VERIFY_ENV.txt are unchanged. Root alone edits this record.

Area agents: pair_evidence_current, catchup_guard_current, timesync_current,
advantage_current, arrival_current, vblank_current, polling_current,
prediction_wait_current, startup_roles_current, resim_deadline_current,
resend_current, switch_route_current, tests_catalogs_current,
build_identity_current, clock_domains_current, simulation_current,
sampling_current, catchup_telemetry_current, state_ring_current,
mismatch_current, coalescing_current, diagnostic_contention_current,
frontier_refresh_current, falsification_current. Separate final reviewer:
final_diff_review_current. All follow AGENTS.md; no agent edits overlap.
No Git command, outside-tree read, deletion, patch edit, build, game, forbidden
helper, server, push or release ran this pass.

## Repeat refusal: runtime proof is still the next open item

Done this pass: 24 read-only area agents checked the pending experiment and
its evidence route. The in-tree latest-verify/runtime/release-b13 folders have
no raw paired timing logs. The supplied existing-name refusal stopped before
launch. Input arrivals, sustained advantage and actual wait ordering remain
unknown. No new runtime change, build or test pass is claimed. Runtime and
VERIFY_ENV.txt are unchanged. The separate tests/catalog agent confirmed that
selftest and catalog checks do not enter the live pacing guard.

Open / owner-only: preserve the existing output and use a fresh unused verify
name. Stage the pending runtime, build once, then run that same new build OFF
and ON with equal TimingDiag, scripts, simulation and all other switches.
Require a build ID different from 943fc4631acf2c13, both ON peers' literal
activation and nonzero NETREBASE_CATCHUP rebases. VERIFY_ENV.txt stays exactly:
TEKKEN4_NET_REBASE_CATCHUP=1;TEKKEN4_NET_DIAG=1
Pass it through common -Env; peer overrides must not replace it. Retain full
paired logs and params. The outer verify wrapper is absent here. Compare
sustained lead, sender gaps, actual waits and absolute rollback/resim work;
lower rebase counters or a smaller rollback ratio alone prove no improvement.
Compilation, selftest and real OFF/ON pair remain UNRUN under AGENTS.md.
The existing catchup hypothesis remains unproved; another source audit cannot
replace the first real run of this experiment.

Area agents: paired_log_evidence, catchup_guard_math, timesync_wait_order,
advantage_estimation, arrival_frontier, vblank_schedule, transport_polling,
prediction_waits, role_startup, resimulation_deadlines, resend_ordering,
switch_env_route, tests_catalog_coverage, build_identity_staging, clock_domains,
network_simulation, local_input_sampling, catchup_diagnostics, state_ring_limits,
prediction_mismatch, send_coalescing, diagnostic_lock_cost, frontier_refresh,
experiment_falsification. Root alone edits this record. Separate final reviewer:
final_diff_review_repeat. All agents follow AGENTS.md. No Git command,
outside-tree read, deletion, patch edit, build, game, forbidden helper, server,
push or release ran this pass.

## Continuation: pending runtime experiment needs its first real run

Done: 24 independent area agents read AGENTS.md and checked the runtime,
transport, evidence and test routes. No raw paired game/transport logs were
found. The latest supplied result is still an existing-name refusal before
launch. No input-arrival trace, measured advantage or actual wait ordering
can be recovered from it. No new runtime edit or test pass is claimed.

The existing default-off catchup patch remains the single pending experiment.
Hypothesis: full deadline rebases discard the slow sender's catchup headroom,
leaving its ahead peer predicting deeper and waiting. Resimulation restores
the saved live deadline; the guard then discards debt above 50 ms. The switch
retains 33.334 ms of live debt. Source fits this mechanism but does not prove
it caused the supplied imbalance. Reordered peer-lead metadata, stale frontier
samples and diagnostic lock contention remain unproved alternatives.

Open / owner-only: stage the pending runtime patch into the real runner and
choose a fresh unused verify name. Run the same new build OFF and ON, keeping
TimingDiag, scripts, simulation and all other switches identical. Require a
build ID different from 943fc4631acf2c13, both ON peers' literal activation,
and nonzero NETREBASE_CATCHUP rebases. The ID hashes staged source, not binary
bytes. Keep VERIFY_ENV.txt unchanged, exactly one line:
TEKKEN4_NET_REBASE_CATCHUP=1;TEKKEN4_NET_DIAG=1
Pass it through common -Env; per-peer overrides must not replace it. The outer
verify wrapper is absent here, so its file ingestion remains unchecked.

Retain full paired runtime/transport logs and effective settings. Compare
sustained lead, confirmed progress, sender gaps, actual waits, absolute
rollback/resimulation work and pacing. A smaller ratio or rebase counter is
insufficient. If exercised ON leaves those problems comparable, the hypothesis
is weakened. Role swaps also change simulator streams and input scripts.
Compilation, selftest, actual OFF/ON pair and improvement remain UNRUN.
AGENTS.md forbids their real entries here. Selftest does not call this pacing
path. No catalog rerun or substitute test was counted as runtime evidence.

Area agents: pair_log_inventory, catchup_bounds, timesync_wait,
advantage_estimate, input_frontier, vblank_deadlines, transport_poll,
prediction_wait, role_startup, resim_cost, resend_order, env_route,
tests_catalogs, build_identity, clock_domains, network_simulation,
local_sampling, diagnostic_counters, state_ring, prediction_compare,
coalescing, thread_contention, frontier_refresh, experiment_falsification.
All read-only; root owns this progress insertion. Separate final reviewer:
final_diff_review_evidence_gate. Runtime and VERIFY_ENV.txt remain unchanged.
No Git command, outside-tree read, deletion, patch edit, build, game, forbidden
helper, server, push or release ran here.

## Current continuation: real verify still blocked before launch

The latest supplied result again refused an existing output name before
launch. It supplies no new build, selftest or pair evidence. Safe inventory
found no raw paired runtime/transport logs here. The eight .log files are ZIP
scanner regression output. Input arrival times, measured advantage and which
peer waited remain unknown; no cause of the rollback imbalance is proved.

Done: sixteen area agents checked separate runtime/evidence paths. No blocking
source defect was found in the pending experiment. No new runtime edit, switch
or unrelated catalog run was added. Runtime source and VERIFY_ENV.txt hashes
are unchanged. Keep the existing default-off experiment and exact switch line:
TEKKEN4_NET_REBASE_CATCHUP=1;TEKKEN4_NET_DIAG=1

The single hypothesis remains lost catchup headroom after processing,
restore/resimulation, hitches or oversleep. The switch retains about 33 ms of
live schedule debt at the >50 ms guard. It does not reduce resimulation cost
or prove recovered time. Source review found no fixed host/join branch in live
pacing. Input frontiers advance monotonically; reordered peer-lead metadata
remains an unproved alternative. Diagnostics timestamp packet handling, not
each input's first arrival; paired process log clocks have separate origins.

Open / owner-only: stage the existing runtime patch into the actual runner,
choose a fresh unused -Name, then build and run the same new build OFF and ON.
The outer verify wrapper is absent here; its file ingestion cannot be checked.
Build IDs hash staged source, not executable bytes. Require an ID different
from 943fc4631acf2c13 AND both ON peers' literal switch activation plus nonzero
NETREBASE_CATCHUP rebases. Pass the switch line through common -Env; per-peer
overrides must not replace it. Keep TimingDiag on in BOTH arms, and keep input
scripts, simulated network settings and other switches identical. Retain full
paired runtime/transport logs and effective params. Compare sustained lead,
confirmed progress, sender gaps, actual waits, rollback depth/cost/totals and
pacing. A smaller ratio or rebase time alone is not success. If the branch runs
but sustained lead and imbalance persist, the hypothesis is weakened. Role
swaps also change simulated network streams and input scripts.

Compilation, selftest, actual OFF/ON pair and runtime improvement remain UNRUN.
AGENTS.md forbids their real build/game/network entries here. Selftest does not
reach this pacing path, and no current test enters catchup. No test pass is
claimed this continuation. Further source-only audit cycles cannot replace
the missing real run; the next useful runtime step requires owner evidence.

Area agents: pair_logs_available, catchup_guard, timesync_deadlines,
advantage_estimator, input_frontier, vblank_schedule, poll_delivery,
prediction_budget, role_branches, resim_work, resend_order, verify_env_route,
tests_catalog_coverage, build_id_provenance, clock_measurements,
experiment_falsification. All read-only. Root owns this progress update and
its original/hash evidence in logs/runtime-catchup-blocked/. Separate reviewer
final_diff_review_blocked owns only final-review.txt in that directory.
No Git command, outside-tree read, deletion, patch edit, build, game, forbidden
helper, server, push or release ran here.

## Catchup follow-up: latest verify stopped before testing

The latest supplied verify refused an existing output name. It supplies no new
build, selftest or pair result. Use a fresh unused `-Name`; preserve the earlier
output. The verify wrapper itself is absent here, so its refusal path was not
executed or inspected. No outside-tree logs were opened.

Done:

- Sixteen area agents rechecked independent runtime paths and the test route.
  No raw paired host/join logs were found in the retained verify folders.
  Arrival timing, measured advantage and wait ordering remain unobserved.
- The existing default-off runtime change below remains the single experiment.
  Its source hash still matches the previous inspection. No additional runtime
  change or switch was added without a completed OFF/ON result. The hypothesis
  remains that full deadline rebases remove the slow sender's catchup headroom;
  the ahead peer predicts further, rolls back more and waits. Source review
  found no fixed host/join branch in time sync, prediction waits or resends.
- Confirmed that the rollback selftest does not execute netplay pacing.
  Selftest success alone cannot validate this switch. `retained_debt_ms` can
  count overlapping allowances and is not measured recovery. Stall counts can
  include immediately satisfied waits; inspect wait durations and frontiers.
- Actual catalog checker: exit 0, empty stderr, two 23-tool catalogs and three
  root inputs. Evidence: `logs/runtime-catchup-followup/tests-catalogs/`.
  This does not execute or validate runtime behavior.

Open / owner-only:

- Stage the changed `runtime/tekken4_rollback_overrides.cpp` into the real runner,
  use a fresh verify name, and require a build ID different from
  `943fc4631acf2c13`. Keep that new ID identical across OFF/ON. The ID hashes
  staged source, not executable bytes; activation evidence is also necessary.
  The real verify and build environment are outside this copy.
- Keep root `VERIFY_ENV.txt` exactly:
  `TEKKEN4_NET_REBASE_CATCHUP=1;TEKKEN4_NET_DIAG=1`.
  Pass it through common `-Env` to both peers; inherited settings are cleared.
  Check that per-peer environment overrides do not replace these assignments.
  Keep `-TimingDiag` on in both arms so only catchup differs. Keep other
  experiments, including `TEKKEN4_NET_REFRESH_RC`, identical in both arms.
- Run actual selftest and OFF/ON pairs. Require both ON peers to log the literal
  catchup activation and nonzero `NETREBASE_CATCHUP` rebases. Retain complete
  paired runtime and transport logs. Compare sender gaps, confirmed frontiers,
  sustained lead, wait durations, rollback totals/depth/cost and frame pacing.
  A smaller ratio or mechanically smaller rebase time alone is insufficient.
  Repeat and swap roles; two-PC and sound-on acceptance remain open.
- Compilation, selftest, actual pair, per-input arrival timing and causal proof
  are still **UNRUN here**. AGENTS.md forbids the required builds, game and
  network helpers. No new runtime correctness or improvement is claimed.

Area agents this follow-up: `pair_evidence`, `rebase_logic`, `sync_waits`,
`advantage_math`, `arrival_frontiers`, `vblank_pacing`, `transport_ingestion`,
`prediction_stalls`, `startup_roles`, `rollback_resim`, `resend_ordering`,
`verify_switch_route`, `tests_catalogs_now`, `diagnostic_proof`, `build_identity`,
`clock_accounting`. All were read-only except `tests_catalogs_now`, which owned
only its new evidence directory. Root owns this progress update. Separate
reviewer `final_diff_review_followup` owns
`logs/runtime-catchup-followup/final-review.txt`.
No Git command, deletion, patch edit, build, game, forbidden helper, server,
push or release ran here.

## Runtime experiment: bounded catchup after pacing rebases

Current priority is the owner's one-sided rollback investigation. The older
launcher/scanner work below does not advance this runtime question. No cause
or improvement is proved. Build, selftest and actual pair remain **UNRUN here**:
AGENTS.md forbids builds, games and the build/network helpers in this copy.
The requested real-entry runtime test must happen in the owner's verify.

Done:

- Read AGENTS.md and this record first. Sixteen area agents inspected runtime
  paths and evidence. No raw host/join game logs exist in this tree; retained
  verify files contain summaries and checker output. Input arrival times,
  measured frame advantage and the exact wait sequence could not be read.
- Supplied b13 host/join totals: 209/989 rollbacks (206/874 early), rebases
  24691/13757 ms, time sync 0/5317 ms and prediction stalls 0/5629 ms.
  Host's extra rebase time is 10934 ms; join's sync plus prediction waits total
  10946 ms. These are different counters, not an accounting identity or causal
  proof. They fit a hypothesis that the slower sender loses schedule headroom
  in full rebases, while its ahead peer predicts deeper and waits. Earlier
  role reversal is supplied by the owner; it suggests a timing-dependent loop.
- Changed only runtime pacing behavior behind new default-off
  `TEKKEN4_NET_REBASE_CATCHUP=1`. At the existing >50 ms debt guard, live frames
  retain two vblank periods (about 33.334 ms) of deadline debt; only the excess
  shifts the schedule. Boot rebases and the switch-off path retain the prior
  behavior. This bounds retained debt after a hitch but can cause short catchup
  bursts and more GPU contention. It does not guarantee two recovered frames.
- Enabled runs log the exact switch at handshake and `NETREBASE_CATCHUP` beside
  summaries with affected rebase count and cumulative retained debt. Retained
  debt is not measured recovered time. Existing `rebases (... ms)` continues to
  mean actual schedule shifts; a lower value alone is not improvement evidence.
- Root [VERIFY_ENV.txt](VERIFY_ENV.txt) contains exactly one line:
  `TEKKEN4_NET_REBASE_CATCHUP=1;TEKKEN4_NET_DIAG=1`.
  Original runtime/progress bytes are retained under
  `logs/runtime-rebase-catchup/originals/`; no Git command was used.
- Tests/catalog agent ran the actual catalog checker: exit 0, two 23-tool
  catalogs and three root inputs. This did not run the changed runtime and is
  not rollback validation. No mock, extracted arithmetic test or source check
  is counted as real-entry runtime proof. Exact switch-file inspection and
  original/current source comparison completed; neither executes the runtime.
- Separate reviewer `final_diff_review_runtime` found no blocking source issue:
  default-off/boot behavior, positive bounded shift, gated telemetry, exact
  switch line and preserved progress history checked. Compilation, selftest
  and OFF/ON runtime verification remain unrun. Review record:
  `logs/runtime-rebase-catchup/final-review.txt`.

Open / owner-only next verify:

1. Stage this changed runtime into the real runner before building. Require a
   build ID different from `943fc4631acf2c13`; build IDs hash staged runner
   overrides. Keep this new build identical between OFF and ON arms. Both
   peers must show the activation line and nonzero affected-rebase counters in
   ON, with the switch absent in OFF. A zero counter leaves the experiment
   unexercised. Run the actual selftest and OFF/ON pair at the same settings.
2. Pass the file's assignments through the pair helper's `-Env` on both peers:
   inherited variables are cleared. Keep `-TimingDiag` enabled identically in
   both arms, and keep all other switches unchanged. Retain effective params,
   complete host/join runtime and transport logs, including NETTS and NETDIAG.
3. Compare paired local/input gaps and progress ages, frame/confirmed frontiers,
   advantage, rebase debt, which side sleeps, rollback depth/count and resim
   cost. Hypothesis predicts less sustained lead on the high-rollback peer
   when the slow peer retains catchup debt. It is weakened if the branch is
   exercised but lead and rollback imbalance persist. A reduced ratio obtained
   by making both sides worse is not success: inspect total rollbacks, FPS,
   stalls, p99 displayed times, zero hash mismatches and zero NETDESYNC too.
4. Repeat and swap roles, then use two physical PCs. A same-PC pair cannot
   establish internet pacing. Full per-input arrival timestamps are not in the
   existing one-second diagnostic samples. Raw logs and runtime proof remain
   open; no release, server or enabled GUI profile is authorized by this change.

Area agents: `pair_logs`, `time_sync`, `frame_advantage`, `input_arrival`,
`vblank_wait`, `pacing_rebase`, `transport_poll`, `prediction_window`,
`role_startup`, `rollback_cost`, `input_resend`, `switch_wiring`,
`tests_catalogs`, `diagnostic_fields`, `verify_comparison`, `clock_sources`.
All followed AGENTS.md and were read-only; root exclusively owns runtime,
VERIFY_ENV and this record. Separate reviewer: `final_diff_review_runtime`.
No file deletion, patch edit, outside-tree read, build, game, forbidden helper,
server, Git command, push or release ran here.

## URI and credential-directory scanner regressions; supplied b13f80b4da

Release remains **NO-GO**. Actual App startup and portable first-run remain
the main release blocker. The complete reviewed candidate/private runtime
and permitted validation environment are still absent. No repeated starter
refusal was run or counted as App evidence.

Done; aggregate verification and final review in progress:

- Real publisher scan/export entries demonstrated that unreviewed URI schemes
  and credential-named directories passed the old scanner. Independent actual
  ZIP entries demonstrated the URI gap too. Only harmless text fixtures were
  used. Initial failing permanent regressions remain under
  `logs/public-uri-schemes-b20eb6b25f8647b88bd42cfe278a1085/` and
  `logs/public-credential-paths-324343b7f8394f4e8b1a178a933d0915/`.
- The shared scanner now discovers additional `scheme://` forms before
  applying the existing reviewed HTTP(S) policy, and checks existing credential
  names/suffixes on every path component. New
  [URI](tools/test_public_uri_schemes.ps1) and
  [credential-path](tools/test_public_credential_paths.ps1) regressions invoke
  actual export, tree scan and ZIP scan entries. Both are registered in both
  aggregates. Frozen standalone URI entry: exit 0, 375 assertions across 39
  real entries, empty stderr and unchanged tool/input hashes. Evidence:
  `logs/public-uri-schemes-10f5469ded7a4d8f96d65e4298477f3e/summary.json`.
  Full aggregates are running sequentially; separate final review is pending.
- Added 200,000-character dotted-text controls hit the scan limit in all
  three modes, both before and after the URI matcher was adjusted to consume
  each scheme-like run once. An exact copied original publisher entry also
  refused that input; this is a pre-existing manual-review limit, not a proved
  URI regression. Original entry controls passed with 4,000 characters and
  with that text followed by an approved URI. Tool hashes and results are in
  `logs/release-b13/uri_entry/baseline/summary.json`. Final regressions use
  those bounded compatibility controls. Failed larger-control runs remain under
  `logs/public-uri-schemes-8b16b2d3859e46478a91c861ffa6b090/` and
  `logs/public-uri-schemes-84e67f789fa64bd582dd2c47bb7e14b2/`. URI syntax
  and HTTP(S) policy remain checked after discovery. The credential test
  passed 377 assertions/41 entries
  before that final performance adjustment, with unchanged inputs and empty
  stderr, under `logs/public-credential-paths-7da7fd5a14934ca99a121019946ed69d/`.
- Actual catalog entry passed with exit 0, empty stderr and unchanged four
  inputs: two 23-tool catalogs and three root inputs. Registration inspection
  found 17 tree suites/25 parse inputs and 20 ZIP suites plus catalog/29 parse
  inputs, with both new suites in both required and run lists. No player
  catalog changed. Evidence: `logs/release-b13/tests_catalogs/`.
- The actual source checker on the switch-evidence document exited 1 with
  empty stderr. Its eight local links and 364 PowerShell parses passed; the
  whole-tree scan found 174 retained fixture findings, including 77 incomplete
  archives. This is not a clean whole-tree pass. Evidence:
  `logs/release-b13/supplied_evidence/summary.json`. Nothing was deleted or
  weakened to remove these fixtures.
- Recorded supplied draft `b13f80b4da`, finished `2026-11-02T14:27:59`:
  clean 188-second build `943fc4631acf2c13`; OFF selftest 6000 wall / 5106
  logical, 202 good restores, zero bad, 447 resim comparisons with zero
  mismatches and 101/101 wrong-input divergences. OFF same-PC pair reached
  6000 live/logical each, 199 hashes each, zero mismatches/NETDESYNC,
  48.1/48.1 run-average FPS, stalls 0/136 (0/5629 ms), displayed-frame
  p99 161.6/117.1 ms, delay 3. Restore-and-resim maxima were
  200.68/62.93 ms. Supplied, not reproduced here; no cause, usable pacing,
  enabled GUI profile, App startup or two-PC proof follows.

Open locally: failed OS termination, interruption inside one file write,
unobserved descendants, output-collection watchdog and other suites' watchdogs
remain unproved. Further URI forms without `://` are outside this narrow fix.
Two actual publisher topology samples observed the worker and two console
hosts, including a depth-two descendant; recorded identities were absent in
two later samples. This does not prove cleanup of unobserved descendants.
Evidence: `logs/release-b13/descendant_cleanup/`.

Owner-only: supply exact reviewed candidate/ZIP hash, matching complete source
and reviewed locks/notices; run actual App/portable acceptance in the authorized
environment. Python suites, complete source/player content and licence review,
enabled GUI Host/Join profile, two physical PCs and sound-on usable pacing
remain open. GUI, Python release tools, packagers, build, game, network helpers
and server remain **UNRUN here**. A same-PC pair is not two-PC proof.

Area agents: `uri_entry`, `key_directory_entry`, `write_interruption`,
`termination_failure`, `descendant_cleanup`, `collection_watchdog`,
`watchdog_suites`, `tests_catalogs_b13`, `supplied_evidence_b13`,
`source_uri_boundary`, `source_matching_b13`, `payload_scan_b13`,
`readiness_claims_b13`, `licence_candidate_b13`, `gui_profile_b13`,
`app_candidate_b13`; separate reviewer `final_diff_review_b13`.
All read AGENTS.md. URI and credential agents exclusively own their respective
new tests; supplied-evidence agent owned only the switch-evidence document.
Root owns shared scanner/aggregate integration, remaining docs and this record.
Originals are under `logs/release-b13/originals/` and
`logs/release-b13/supplied_evidence/original.md`. No file was deleted, no Git
command or outside-tree read was used, and no build, game, forbidden helper,
server, push or release ran.

## Forced tree-test watchdog through the real publisher

Release remains **NO-GO**. Actual App startup and portable first-run are still
the most valuable release item, but the complete candidate/private Python
and permitted validation environment remain absent. The supplied verification
`294b927b6f` below is already recorded accurately. No repeated starter refusal
was run or counted as App evidence. Work instead advanced an executable open
item: failure of the tree lifecycle test's outer watchdog.

Done:

- Added [the watchdog regression](tools/test_public_tree_outer_watchdog.ps1)
  and registered it in both lists of the real public-tree aggregate. It runs
  clean actual publisher scans before and after one expected failing lifecycle
  child. [The lifecycle test](tools/test_public_tree_process_lifecycle.ps1)
  now offers `-ExerciseOuterWatchdog`: after independently observing the real
  scanner worker it starts a one-millisecond test budget, then reaches the
  existing watchdog throw/cleanup branch. Its ordinary 150-second budget and
  eight cases remain. No production publisher or launcher code changed.
- Standalone parent entry: exit 0, 141 assertions, two clean controls and one
  actual publisher scan inside the child. The child exited 1 with the precise
  watchdog failure and no pass claim. Two independent parent samples found
  the recorded supervisor/worker identities absent; source/helper bytes were
  unchanged. Evidence:
  `logs/tree-outer-watchdog-bab90cc58fc0404b97a25b9966ef81ff/summary.json`.
  A separate forced child also exited 1 with trigger, cleanup and unchanged
  input flags true under
  `logs/tree-process-lifecycle-80d472fc0b794ca3ab312d65259bad80/`.
- The first parent run caught a generic-list conversion bug in the new test
  harness; it was fixed before the passing run. Its failed evidence remains
  under `logs/tree-outer-watchdog-1ffd4f7547f9459fbd4e3549424df439/`.
  It is not publisher-defect or unobserved-descendant cleanup evidence.

- Full actual [public-tree checker](tools/check_public_publish.ps1): exit 0,
  empty stderr, 15 suites and 23 PowerShell parses. Both 23-tool catalogs were
  checked, all 79 source patch names/hashes matched, and seven entry/helper/test
  hashes stayed unchanged during the run. The normal lifecycle suite passed
  eight real entries; the new regression also passed through the aggregate.
  Evidence: `logs/release-outer-watchdog/aggregate-summary.json` and
  `aggregate.stdout.txt` there. The run took 514 seconds.
- Separate reviewer `final_diff_review` found no blocking code issue and
  independently ran the new parent entry: exit 0, empty stderr, unchanged seven
  code inputs, two clean controls, expected child exit 1 and two independent
  absence samples. Its evidence/report are under
  `logs/release-outer-watchdog/final-review/`. Local-link inspection passed for
  both changed documents (266 links); external URLs and anchors were not checked.
  The whole-tree beta checker and ZIP aggregate were not rerun.

Open locally: failed OS termination, interruption inside one file write,
unobserved descendants, output-collection watchdog and other suites' watchdogs
remain unproved. Source-only observations about additional URI schemes and
private-key directory names need actual scanner-entry reproduction before a
fix; they are not demonstrated defects. Do not repeat another App refusal or
general source audit as acceptance.

Owner-only: supply the exact reviewed complete candidate, ZIP hash, matching
source and reviewed locks/notices; run actual App/portable acceptance in the
authorized environment. Python suites, full source/player content and licence
review, enabled GUI Host/Join profile, two physical PCs and sound-on usable
pacing remain open. GUI, Python release tools, packagers, build, game, network
helpers and server stayed **UNRUN here**. A same-PC pair is not two-PC proof.

Area agents: `app_route`, `candidate_inputs`, `scanner_termination`,
`scanner_write`, `outer_watchdog`, `descendant_processes`, `tests_catalogs`,
`source_privacy`, `payload_validation`, `source_matching`, `gui_profile`,
`licence_gate`, `readiness_semantics`, `supplied_evidence`, `entry_test_honesty`,
`release_priority`; separate reviewer `final_diff_review`. All read AGENTS.md.
Only `outer_watchdog` and `entry_test_honesty` edited their own test files;
root owns aggregate/docs/progress. Originals are retained under
`logs/release-outer-watchdog/originals/` and
`logs/outer-watchdog-original-f00144d1067e481e8103586bc8582cbd/`.
No file was deleted and no Git command, outside-tree read, build, game,
forbidden helper, server, push or release ran here.

Earlier entries below retain their original evidence and limits. Only the
forced watchdog of this tree lifecycle test has new coverage; no broader
watchdog or launcher acceptance claim supersedes those limits.

## Current blocker and supplied verification 294b927b6f

Release remains **NO-GO**. Actual App startup and portable first-run are the
most valuable open item. Sixteen area agents found no complete candidate or
permitted actual App route. Private Python/Tk, dependencies, reviewed
locks/notices and portable marker remain absent; App initialization also
discovers locations outside this tree. No production or test code changed:
an App fix could not receive the required real-entry test here.

Done:

- Actual [starter test](tools/test_launcher_entry.ps1): test exit 0, real
  `Tekken4.cmd` exit 1 for missing private Python, empty stderr and three
  unchanged input hashes. **The App never started.** Evidence:
  `logs/starter-294b-a66d7502d9044fcb85a67e2e50d1efe8/summary.json`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both exit 0, empty
  stderr; two 23-tool catalogs, three root inputs and three actual checker
  subprocess cases passed. Normal readiness remains 2 / BLOCKED. All 37
  hashed source inputs were unchanged; documents were excluded. Evidence:
  `logs/tests-catalogs-294b/summary.json`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md),
  [decision sheet](docs/BETA_GO_NO_GO.md) and [status](docs/status.md) with
  supplied draft `294b927b6f`, finished `2026-11-02T13:53:59`: clean
  185-second build `943fc4631acf2c13`; OFF selftest 6000 wall / 5106 logical,
  202 good restores, zero bad, 447 comparisons with zero mismatches and
  101/101 wrong-input divergences. OFF same-PC pair: 6000 live/logical each,
  199 hashes each, zero mismatches/NETDESYNC, FPS 47.8/47.8, stalls 0/139
  (0/5619 ms), displayed-frame p99 166.1/120.5 ms, delay 3. Supplied, not
  reproduced here. Versus `d1a2bb15db`, host FPS stayed at 47.8 and join
  fell from 47.9; both p99 values fell. Join stalls rose but total stall
  time fell. Restore-and-resim maxima changed from 255.16/63.22 to
  110.51/66.70 ms: host fell, join rose. No cause or usable pacing is proved.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Pad navigation remains absent;
fullscreen inheritance and offline spawn-failure cleanup remain unexecuted
source observations. Failed scanner termination, interruption inside one
write, outer watchdog failure and unobserved descendants remain unproved.
Existing long aggregates and the whole-tree beta checker were not rerun.

Owner-only next step: supply the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices, then follow
[actual launcher acceptance](docs/RELEASE_PATH_B.md) in the authorized
environment: responsive App/process identity, exit/reopen/settings, licence
cancel/accept and portable build/play/return. Retain both full logs and
effective settings for pacing review. Python alone is insufficient. GUI,
Python suites, packagers, build, game and network helpers stayed **UNRUN
here**. A same-PC pair does not replace two PCs.

Resume from this blocker: without new candidate inputs or authorization for
the real validation environment, another refusal run or source audit cannot
advance App acceptance. Do not count another green audit as a launcher pass.

Area agents: `starter_294b`, `tests_catalogs_294b`, `supplied_verify_294b`,
`candidate_294b`, `python_tk_294b`, `app_boundary_294b`, `settings_294b`,
`controller_294b`, `offline_294b`, `licences_294b`, `source_privacy_294b`,
`player_payload_294b`, `source_matching_294b`, `gui_profile_294b`,
`two_pc_294b`, `scanner_gaps_294b`. All read AGENTS.md; only starter and
tests/catalog agents ran entries. Root owns all four document changes;
editing ownership was exclusive. Four originals and a 350-file source
baseline are under `logs/release-294b/`. Combined actual readiness evidence
is `combined-entry-final/summary.json` there. The first wrapper nested
the baseline array and stopped before checker execution; it is not test
evidence. The second ran the checker but lost its child exit code; its
`combined-entry-checked/` result is not exit-2 proof. The final wrapper reads
all 350 records and captures the native child exit directly. Separate final diff reviewer
`final_diff_review_294b` owns `final-review/` there; its report records its
assessment and independent entry results. These source checks cannot prove
App acceptance. No Git command, deletion, outside-tree read, build, game,
forbidden helper, server, push or release ran here.

## Current blocker and supplied verification d1a2bb15db

Release remains **NO-GO**. Actual App startup and portable first-run remain
the most valuable open item. Sixteen area agents checked its independent
prerequisites; no runnable complete candidate was found. Private Python/Tk,
dependencies, reviewed locks/notices and portable marker remain absent. App
initialization also probes outside this permitted tree. No production or test
code changed: no App fix could receive the required real-entry test here.
Another source audit cannot close this gate.

Done:

- Actual [starter test](tools/test_launcher_entry.ps1): test exit 0, real
  `Tekken4.cmd` exit 1 for missing private Python; empty stderr, three input
  hashes unchanged. **The App never started.** Evidence:
  `logs/starter-d1a2-d33c3be54f3d43f3b97421c73cc40564/summary.json`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both exit 0, empty
  stderr; two 23-tool catalogs, three root inputs and three actual checker
  subprocess cases passed. Normal readiness remains 2 / BLOCKED. All 47
  hashed source inputs were unchanged; changing documents were excluded.
  Evidence: `logs/tests-catalogs-d1a2-161d7bea959c4cf2a814f0e4d7c8f8da/summary.json`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md),
  [decision sheet](docs/BETA_GO_NO_GO.md) and [status](docs/status.md) with
  supplied draft `d1a2bb15db`, finished `2026-11-02T13:40:25`: clean
  191-second build `943fc4631acf2c13`; OFF selftest 6000 wall / 5106 logical,
  202 good restores, zero bad, 447 comparisons with zero mismatches and
  101/101 wrong-input divergences. OFF same-PC pair: 6000 live/logical each,
  199 hashes each, zero mismatches/NETDESYNC, FPS 47.8/47.9, stalls 0/130
  (0/6593 ms), displayed-frame p99 174.8/126.0 ms, delay 3. Supplied, not
  reproduced here. Versus `7e0bf150da`, both FPS values fell, both p99 values
  rose and join stalls/time rose. Restore-and-resim maxima fell from
  282.18/70.29 to 255.16/63.22 ms. No cause or usable pacing is established.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Pad navigation remains absent;
fullscreen inheritance and offline spawn-failure cleanup remain unexecuted
source observations. Failed scanner termination, interruption inside one
write, outer watchdog failure and unobserved descendants remain unproved.
Existing long aggregates and the whole-tree beta checker were not rerun.

Owner-only next step: supply the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices, then follow
[actual launcher acceptance](docs/RELEASE_PATH_B.md) in the authorized
environment: responsive App/process identity, exit/reopen/settings, licence
cancel/accept and portable build/play/return. Retain both full logs and
effective settings to investigate pacing. Python alone is insufficient.
GUI, Python suites, packagers, build, game and network helpers stayed
**UNRUN here**. A same-PC pair does not replace two PCs.

Area agents: `starter_d1a2`, `tests_catalogs_d1a2`, `supplied_verify_d1a2`,
`candidate_d1a2`, `python_tk_d1a2`, `app_boundary_d1a2`, `settings_d1a2`,
`controller_d1a2`, `offline_d1a2`, `licences_d1a2`, `source_privacy_d1a2`,
`player_payload_d1a2`, `source_matching_d1a2`, `gui_profile_d1a2`,
`two_pc_d1a2`, `scanner_gaps_d1a2`. All read AGENTS.md; only starter and
tests/catalog agents ran entries. Root owns all four document changes;
editing ownership was exclusive. Originals and a 348-file baseline are under
`logs/release-d1a2-a7d7b0890f1d4dfaa51767c787f51d4b/`.
Combined actual readiness evidence is `combined-entry/summary.json` there;
it records the four-document check, entry result and source hashes.
Separate reviewer `final_diff_review_d1a2` owns `final-review/` there;
its report records final diff review and independent entry results.
Neither source check can establish App acceptance.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Current blocker and supplied verification 7e0bf150da

Release remains **NO-GO**. Actual App startup and portable first-run remain
the most valuable open item. Sixteen area agents found no new runnable route:
the complete candidate, private Python/Tk, dependencies, reviewed locks/notices
and portable marker are absent. App initialization also discovers locations
outside this permitted tree. No production or test code changed. Another
source audit cannot close this gate.

Done:

- Actual [starter test](tools/test_launcher_entry.ps1): test exit 0, real
  `Tekken4.cmd` exit 1 for missing private Python; empty stderr, three input
  hashes unchanged. **The App never started.** Evidence:
  `logs/starter-7e0b-91bf0b1207524ee8a2cc60c89e8779bb/summary.json`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both exit 0, empty
  stderr; two 23-tool catalogs, three root inputs and three actual checker
  subprocess cases passed. Normal readiness remains 2 / BLOCKED. All 37
  hashed source inputs were unchanged; changing documents were excluded.
  Evidence: `logs/tests-catalogs-7e0b-da05bdc8e555442cb25dbdcffc090a7b/summary.json`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md),
  [decision sheet](docs/BETA_GO_NO_GO.md) and [status](docs/status.md) with
  supplied draft `7e0bf150da`, finished `2026-11-02T13:25:38`: clean
  187-second build `943fc4631acf2c13`; OFF selftest 6000 wall / 5106 logical,
  202 good restores, zero bad, 447 comparisons with zero mismatches and
  101/101 wrong-input divergences. OFF same-PC pair: 6000 live/logical each,
  199 hashes each, zero mismatches/NETDESYNC, FPS 48.4/48.4, stalls 0/121
  (0/4607 ms), displayed-frame p99 155.1/112.3 ms, delay 3. Supplied, not
  reproduced here. Versus `2c83c6a764`, FPS rose, both p99 values fell and
  join stalls/time fell. Restore-and-resim maximum changed from
  253.25/83.45 to 282.18/70.29 ms: host rose, join fell. No cause or usable
  pacing is established.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Pad navigation remains absent;
fullscreen inheritance and offline spawn-failure cleanup remain unexecuted
source observations. Failed scanner termination, interruption inside one
write, outer watchdog failure and unobserved descendants remain unproved.
Existing long aggregates and the whole-tree beta checker were not rerun.

Owner-only next step: supply the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices, then follow
[actual launcher acceptance](docs/RELEASE_PATH_B.md) in the authorized
environment: responsive App/process identity, exit/reopen/settings, licence
cancel/accept and portable build/play/return. Retain both full logs and
effective settings to investigate timing maxima. Python alone is insufficient.
GUI, Python suites, packagers, build, game and network helpers stayed
**UNRUN here**. A same-PC pair does not replace two PCs.

Area agents: `starter_7e0b`, `tests_catalogs_7e0b`, `supplied_verify_7e0b`,
`candidate_7e0b`, `python_tk_7e0b`, `app_boundary_7e0b`, `settings_7e0b`,
`controller_7e0b`, `offline_7e0b`, `licences_7e0b`, `source_privacy_7e0b`,
`player_payload_7e0b`, `source_matching_7e0b`, `gui_profile_7e0b`,
`two_pc_7e0b`, `scanner_gaps_7e0b`. All read AGENTS.md; only starter and
tests/catalog agents ran entries. Root owns all four document changes;
editing ownership was exclusive. Originals and a 347-file baseline are under
`logs/release-7e0b-71ec5c1a594d41d5b45206873d8e193a/`.
Combined actual readiness checked all four changed documents / 287 local
links, 12 required inputs and seven parses, then ran catalogs and actual
starter refusal: exit 2 / BLOCKED, empty stderr, all 347 baseline hashes
unchanged during the run. Exactly four documents differ from their originals.
Evidence: `combined-entry-checked/summary.json` under that folder. An initial
wrapper stopped before execution after nesting the baseline array. The next
ran the checker but captured wrapper exit 1 and module-progress stderr;
its `combined-entry/` result is not the clean exit-2 evidence. The corrected
wrapper explicitly preserves the child exit and suppresses progress output.
Separate reviewer `final_diff_review_7e0b` owns `final-review/` there; consult
its report for the final diff review and independent entry results.
Neither source check can prove App acceptance.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Current blocker and supplied verification 2c83c6a764

Release remains **NO-GO**. Actual App startup and portable first-run remain
the most valuable open item. Sixteen area agents checked its independent
prerequisites. The complete candidate, private Python/Tk, dependencies,
reviewed locks/notices and portable marker remain absent. App initialization
also discovers locations outside this permitted tree. No production or test
code changed: no App fix could receive the required actual-entry proof here.
Another source audit or ordinary scanner fixture cannot close this gate.

Done:

- Actual [starter test](tools/test_launcher_entry.ps1): test exit 0, real
  `Tekken4.cmd` exit 1 for missing private Python. Empty stderr; three input
  hashes unchanged. **The App never started.** Evidence:
  `logs/starter-2c83-b24a98d8c6ca4c3fae1c2b4eb1e69a38/summary.json`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both exit 0, empty
  stderr; two 23-tool catalogs, three root inputs and three actual checker
  subprocess cases passed. Normal readiness remains 2 / BLOCKED. Forty
  input hashes unchanged. Evidence:
  `logs/tests-catalogs-2c83-6316b2b4f30d487490101dbd47d6749e/summary.json`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md),
  [decision sheet](docs/BETA_GO_NO_GO.md) and [status](docs/status.md) with
  supplied draft `2c83c6a764`, finished `2026-11-02T13:12:04`: clean
  237-second build `943fc4631acf2c13`; OFF selftest 6000 wall / 5106
  logical frames, 202 good restores, zero bad, 447 comparisons with zero
  mismatches and 101/101 wrong-input divergences. OFF same-PC pair: 6000
  live/logical frames, 199 hashes each, zero mismatches/NETDESYNC,
  FPS 47.9/47.9, stalls 0/127 (0/5411 ms), displayed-frame p99
  163.0/120.0 ms, delay 3. Supplied, not reproduced here. Versus
  `75cdf51c7c`, both run-average FPS values rose; host p99 fell and join
  p99 rose. Join stalls and total stall time fell. Restore-and-resim maximum
  changed from 254.37/77.48 to 253.25/83.45 ms. No cause or usable pacing
  is established.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Pad navigation remains absent;
fullscreen inheritance and offline spawn-failure cleanup are unexecuted
source observations. Failed scanner termination, interruption inside one
write and unobserved descendants remain unproved. Existing long aggregates
and the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices, then follow
[actual launcher acceptance](docs/RELEASE_PATH_B.md) in the authorized
environment: responsive App/process identity, exit/reopen/settings, licence
cancel/accept and portable build/play/return. Python alone is insufficient.
Retain both full logs and effective settings to investigate the pacing
maxima. GUI, Python suites, packagers, build, game and network helpers stayed
**UNRUN here**. A same-PC pair does not replace two PCs.

Area agents: `starter_2c83`, `tests_catalogs_2c83`, `supplied_verify_2c83`,
`candidate_2c83`, `python_tk_2c83`, `app_boundary_2c83`, `settings_2c83`,
`controller_2c83`, `offline_2c83`, `licences_2c83`, `source_privacy_2c83`,
`player_payload_2c83`, `source_matching_2c83`, `gui_profile_2c83`,
`two_pc_2c83`, `scanner_gaps_2c83`. All read AGENTS.md; only starter and
tests/catalog agents ran entries. Root owns all four document changes;
editing ownership was exclusive. Originals and a 350-file baseline are
retained under `logs/release-2c83-8ac39eafb53f41999fd30b391cae7506/`.
Combined actual readiness checked all four changed documents / 280 local
links, 12 required inputs and seven parses, then ran catalogs and actual
starter refusal: exit 2 / BLOCKED, empty stderr, 350 baseline hashes unchanged
during the run. Exactly four documents differ from their originals. Evidence:
`combined-entry-checked/summary.json` there. The first wrapper preflight treated
the JSON records as one nested array and stopped before checker execution;
the next attempt refused its existing output directory. Neither ran a checker
or supports a hash claim. The corrected wrapper validates 350 records.
Separate reviewer `final_diff_review_2c83` owns `final-review/` there; consult
its report for final diff review and independent entry results.
Neither source check can prove App acceptance.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Current blocker and supplied verification 75cdf51c7c

Release remains **NO-GO**. The most valuable open item is actual App startup
and portable first-run. Sixteen area agents checked its prerequisites. The
complete candidate, private Python/Tk, dependencies, reviewed locks/notices
and portable marker remain absent. Actual App initialization also discovers
locations outside this permitted tree. No production or test code changed:
no App fix could receive the required real-entry proof here. Repeating source
audits or ordinary scanner fixtures cannot close this acceptance gate.

Done:

- Actual [starter test](tools/test_launcher_entry.ps1): test exit 0, real
  `Tekken4.cmd` exit 1 for missing private Python. Empty stderr; three input
  hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-75cd-a9c6cff53c7c46c99a0a43d70e2fe39d/summary.json`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both exit 0, empty
  stderr; two 23-tool catalogs, three root inputs and three real checker
  subprocess cases passed. Normal readiness remains 2 / BLOCKED. Fourteen
  input hashes unchanged. Evidence:
  `logs/tests-catalogs-75cd-cec3f126a25742d9808b404669c235d5/summary.json`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md),
  [decision sheet](docs/BETA_GO_NO_GO.md) and [status](docs/status.md) with
  supplied draft `75cdf51c7c`, finished `2026-11-02T12:58:17`: clean
  195-second build `943fc4631acf2c13`; OFF selftest 6000 wall / 5106
  logical frames, 202 good restores, zero bad, 447 comparisons with zero
  mismatches and 101/101 wrong-input divergences. OFF same-PC pair: 6000
  live/logical frames, 199 hashes each, zero mismatches/NETDESYNC,
  FPS 47.7/47.7, stalls 0/143 (0/5951 ms), displayed-frame p99
  168.7/117.7 ms, delay 3. Supplied, not reproduced here. Versus
  `09fb6191e9`, host FPS stayed the same, join FPS fell and both p99 values
  fell. Join stalls rose while total stall time fell. Restore-and-resim
  maximum rose from 19.14/63.48 to 254.37/77.48 ms. No cause or usable
  pacing is established.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Pad navigation remains absent;
fullscreen inheritance and offline spawn-failure cleanup are unexecuted
source observations. Failed scanner termination, interruption inside one
write and unobserved descendants remain unproved. Existing long aggregates
and the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices, then follow
[actual launcher acceptance](docs/RELEASE_PATH_B.md) in the authorized
environment: responsive App/process identity, exit/reopen/settings, licence
cancel/accept and portable build/play/return. Python alone is insufficient.
Capture both full logs and effective settings before investigating the
254.37 ms host maximum. GUI, Python suites, packagers, build, game and
network helpers stayed **UNRUN here**. A same-PC pair does not replace two PCs.

Area agents: `launcher_entry_75cd`, `tests_catalogs_75cd`,
`supplied_verify_75cd`, `portable_candidate_75cd`, `python_tk_75cd`,
`settings_process_75cd`, `controller_ui_75cd`, `offline_flow_75cd`,
`licence_inputs_75cd`, `source_privacy_75cd`, `player_payload_75cd`,
`corresponding_source_75cd`, `effective_profile_75cd`, `two_pc_pacing_75cd`,
`scanner_gaps_75cd`, `integrated_launcher_75cd`. All read AGENTS.md; only
starter and tests/catalog agents ran entries. Root owns all four document
changes; editing ownership was exclusive. Originals and a 347-file baseline
are retained under `logs/release-75cd-7f84cc757b614439b3704f039548478f/`.
Combined actual readiness evidence is `combined-entry/summary.json` there;
it records the entry result and source hashes. Separate reviewer
`final_diff_review_75cd` owns `final-review/` there; its report records final
diff review and independent entry verification. Neither check can establish
App acceptance. No Git command, deletion, outside-tree read, build, game,
forbidden helper, server, push or release ran here.

## Current blocker and supplied verification 09fb6191e9

Release remains **NO-GO**. Actual App startup and portable first-run remain
the most valuable open item. Sixteen agents checked independent release
areas; the complete candidate, private Python/Tk, dependencies, reviewed
locks/notices and portable marker are still absent. App initialization also
discovers locations outside this permitted tree. No production or test code
changed: no local App fix could receive the required real-entry proof.

Done:

- Actual [starter test](tools/test_launcher_entry.ps1): test exit 0; real
  `Tekken4.cmd` exit 1 for missing private Python. Empty stderr, three input
  hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-09fb-52e20bc58280454bbb4a81555edfb12e/summary.json`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both exit 0, empty
  stderr; two 23-tool catalogs, three root inputs and three real checker
  subprocess cases passed. Normal readiness remains 2 / BLOCKED. Fourteen
  tracked input hashes unchanged. Evidence:
  `logs/tests-catalogs-09fb-a5ea4763d5884825aed02f22b8bb6638/summary.json`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md),
  [decision sheet](docs/BETA_GO_NO_GO.md) and [status](docs/status.md) with
  supplied draft `09fb6191e9`, finished `2026-11-02T12:45:15`: clean
  226-second build `943fc4631acf2c13`; OFF selftest 6000 wall / 5106
  logical frames, 202 good restores, zero bad, 447 comparisons with zero
  mismatches and 101/101 wrong-input divergences. OFF same-PC pair: 6000
  live/logical frames, 199 hashes each, zero mismatches/NETDESYNC,
  FPS 47.7/47.8, stalls 0/138 (0/6526 ms), displayed-frame p99
  175.1/120.7 ms, delay 3. Supplied, not reproduced here. Versus
  `628d969cdd`, both FPS values fell, both p99 values rose, and join stalls
  and stall time rose. No cause or usable pacing is established.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Pad navigation remains absent;
fullscreen inheritance and offline spawn-failure cleanup are unexecuted
source observations. Failed scanner termination, interruption inside one
write and unobserved descendants remain unproved. Another ordinary fixture
or source audit would not close these gates. Existing long aggregates and
the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices, then follow
[actual launcher acceptance](docs/RELEASE_PATH_B.md) in the authorized
environment: responsive App/process identity, exit/reopen/settings, licence
cancel/accept and portable build/play/return. Python alone is insufficient.
GUI, Python suites, packagers, build, game and network helpers stayed **UNRUN
here**. A same-PC pair does not replace two PCs.

Area agents: `launcher_entry_09fb`, `tests_catalogs_09fb`,
`supplied_verify_09fb`, `portable_candidate_09fb`, `python_tk_09fb`,
`settings_process_09fb`, `controller_ui_09fb`, `offline_flow_09fb`,
`licence_inputs_09fb`, `source_privacy_09fb`, `player_payload_09fb`,
`corresponding_source_09fb`, `effective_profile_09fb`, `two_pc_pacing_09fb`,
`scanner_gaps_09fb`, `integrated_launcher_09fb`. All read AGENTS.md; only
starter and tests/catalog agents ran entries. Root owns all four document
changes; editing ownership was exclusive. Originals and a 351-file baseline
are retained under `logs/release-09fb-6a0519e72efe495f82ff8cb2f39f441e/`.
Combined readiness evidence belongs in `combined-entry-checked/` there; its
summary records the actual result and input hashes. The initial checker
capture in `combined-entry/` returned BLOCKED, but its wrapper treated the
baseline array as one nested record and failed its difference check. A first
correction failed validation before checker execution. Neither supports a
hash claim. The corrected run uses the saved 351 records explicitly.
Separate reviewer
`final_diff_review_09fb` owns `final-review/` there; consult its report for
the final diff review and independent entry outcome. Neither check can
establish App acceptance. No Git command, deletion, outside-tree read,
build, game, forbidden helper, server, push or release ran here.

## Current blocker and supplied verification 628d969cdd

Release remains **NO-GO**. Actual App startup and portable first-run are
still the most valuable open item. Sixteen area agents checked its separate
prerequisites. No complete candidate, private Python/Tk, dependencies,
reviewed locks/notices or portable marker appeared. Actual App initialization
also discovers locations outside this permitted tree. No production or test
code changed: no App fix could receive the required real-entry proof here.
Another source audit or ordinary scanner fixture would not close this gate.

Done:

- Actual [starter test](tools/test_launcher_entry.ps1): test exit 0, real
  `Tekken4.cmd` exit 1 for missing private Python. Empty stderr; three input
  hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-628d-301069ecce18420484519a22ae6dfc50/summary.json`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both exited 0, empty
  stderr; both 23-tool catalogs and three root inputs checked. Three actual
  checker subprocess cases passed; normal readiness remains 2 / BLOCKED.
  Twelve input hashes unchanged. Evidence:
  `logs/tests-catalogs-628d-81bf4a2e10694e4e9ceb400d1edca5f0/summary.json`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md),
  [decision sheet](docs/BETA_GO_NO_GO.md) and [status](docs/status.md) with
  supplied draft `628d969cdd`, finished `2026-11-02T12:29:14`: clean
  188-second build `943fc4631acf2c13`; OFF selftest 6000 wall / 5106
  logical frames, 202 good restores, zero bad, 447 comparisons with zero
  mismatches and 101/101 wrong-input divergences. OFF same-PC pair: 6000
  live/logical frames, 199 hashes each, zero mismatches/NETDESYNC,
  FPS 48.0/48.1, stalls 0/109 (0/5444 ms), displayed-frame p99
  169.3/117.8 ms, delay 3. Supplied, not reproduced here. Versus
  `19c0d67e5a`, FPS and both p99 values rose; join stalls and total stall
  time fell. Delay stayed 3. No cause or usable pacing is established.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Launcher pad navigation remains
absent. Fullscreen inheritance and offline spawn-failure cleanup remain
unexecuted source observations. Failed scanner termination, interruption
inside one write and unobserved descendants remain unproved. Existing long
aggregates and the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices, then follow
[actual launcher acceptance](docs/RELEASE_PATH_B.md) in the authorized
environment: responsive App/process identity, exit/reopen/settings, licence
cancel/accept and portable build/play/return. Python alone is insufficient.
GUI, Python suites, packagers, build, game and network helpers stayed **UNRUN
here**. A same-PC pair does not replace two PCs.

Area agents: `launcher_entry_628d`, `tests_catalogs_628d`,
`supplied_verify_628d`, `portable_candidate_628d`, `python_tk_628d`,
`settings_process_628d`, `controller_ui_628d`, `offline_flow_628d`,
`licence_inputs_628d`, `source_privacy_628d`, `player_payload_628d`,
`corresponding_source_628d`, `effective_profile_628d`, `two_pc_pacing_628d`,
`scanner_gaps_628d`, `integrated_launcher_628d`. Each read AGENTS.md;
only the starter and tests/catalog agents ran entries, the others reviewed
their assigned area without edits. Root owns all four document changes.
Originals and a 347-file baseline are retained under
`logs/release-628d-eaa4c7d81ac44206b99db89e70042498/`.
Combined actual readiness checked all four changed documents / 259 local
links, 12 required inputs and seven parses, then ran catalogs and actual
starter refusal: exit 2 / BLOCKED, empty stderr, all 347 baseline hashes
unchanged during the run. Exactly four documents differ from their originals.
Evidence is `combined-entry-checked/summary.json` under that folder. The first
capture in `combined-entry/` ran the checker with the same result but its
wrapper misread the baseline as one nested array; its hash summary is invalid.
Only the corrected capture supports the hash statements above.
Separate reviewer `final_diff_review_628d` owns `final-review/` under that
folder; consult its report for the final review and independent entry outcome.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Current blocker and supplied verification 19c0d67e5a

Release remains **NO-GO**. The most valuable open item is actual App startup
and portable first-run. Sixteen area agents checked its independent gates.
The complete candidate, private Python/Tk, dependencies, reviewed locks/notices
and portable marker remain absent. App initialization also discovers locations
outside this permitted tree. No production or test code changed: no App fix
could receive the required real-entry proof here. Another source audit or
ordinary scanner fixture would not close this acceptance gate.

Done:

- Real [starter test](tools/test_launcher_entry.ps1): test exit 0, actual
  `Tekken4.cmd` exit 1 for missing private Python. Empty stderr; three input
  hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-19c0-b2d81c54d4cf4f07a44c89f226f7058a/summary.json`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): exit 0 each, empty
  stderr, both 23-tool catalogs and three root inputs checked. Three real
  checker subprocess cases passed; normal readiness remains 2 / BLOCKED.
  Twelve source hashes unchanged. Evidence:
  `logs/tests-catalogs-19c0-61d12e7dcef246b587a7da9b005e4ab9/summary.json`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md),
  [decision sheet](docs/BETA_GO_NO_GO.md) and [status](docs/status.md) with
  supplied draft `19c0d67e5a`, finished `2026-11-02T12:07:05`: clean
  190-second build `943fc4631acf2c13`; OFF selftest 6000 wall / 5106
  logical frames, 202 good restores, zero bad, 447 comparisons with zero
  mismatches, 101/101 wrong-input divergences. OFF same-PC pair: 6000
  live/logical frames, 199 hashes each, zero mismatches/NETDESYNC,
  FPS 47.7/47.8, stalls 0/130 (0/5997 ms), displayed-frame p99
  164.2/116.8 ms, delay 3. Supplied, not reproduced here. Versus
  `06c5b8013e`, FPS and both p99 values fell; join stalls and stall time
  rose. Delay stayed 3. No cause or usable pacing is established.
  Real readiness checked the two evidence documents / 18 links: exit
  2 / BLOCKED, empty stderr, 14 hashes unchanged. Evidence:
  `logs/supplied-19c0-ef60170247994380a44249e47a4f3d7a/summary-clean.json`.
  The initial capture had module-progress stderr; only the clean rerun is used.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile, and two
physical PCs with sound-on usable pacing. Pad navigation remains absent.
Fullscreen inheritance and offline spawn-failure cleanup remain unexecuted
source observations. Failed scanner termination, interruption inside one write
and unobserved descendants remain unproved. Unchanged long aggregates and
the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices, then follow
[actual launcher acceptance](docs/RELEASE_PATH_B.md) in the authorized
environment: responsive App/process identity, exit/reopen/settings, licence
cancel/accept, portable build/play/return. Python alone is insufficient.
GUI, Python suites, packagers, build, game and network helpers stayed **UNRUN
here**. A same-PC pair does not replace two PCs.

Area agents: `launcher_entry_19c0`, `tests_catalogs_19c0`,
`supplied_verify_19c0`, `portable_candidate_19c0`, `python_tk_19c0`,
`settings_process_19c0`, `controller_ui_19c0`, `offline_flow_19c0`,
`licence_inputs_19c0`, `source_privacy_19c0`, `player_payload_19c0`,
`corresponding_source_19c0`, `effective_profile_19c0`, `two_pc_pacing_19c0`,
`scanner_gaps_19c0`, `integrated_launcher_19c0`.
Root owns this record and `docs/status.md`; editing ownership was exclusive.
Originals and a 351-file baseline are saved under
`logs/release-19c0-bce86a8e869f4e1ebca2885b4e8ef314/`.
Combined real readiness checked all four changed documents / 252 local links,
12 required inputs and seven parses, then catalogs and actual starter refusal:
exit 2 / BLOCKED, empty stderr, all 351 baseline hashes unchanged during the run.
Exactly four documents differ from their originals. Evidence is
`combined-entry-clean/summary.json` under that root evidence folder.
The initial wrapper failed to propagate the checker's exit code and returned
1; its output is retained in `combined-entry/`. The corrected wrapper explicitly
propagates the real checker exit. No acceptance pass is inferred from either.
Separate reviewer `final_diff_review_19c0` checks the final document changes;
its report and independent entry evidence are retained in `final-review/`
under the same root evidence folder. See that report for its actual outcome.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Current blocker and supplied verification 06c5b8013e

Release remains **NO-GO**. The most valuable open item is actual App startup
and portable first-run. Sixteen area agents checked independent prerequisites;
the complete candidate, private Python/Tk, dependencies, reviewed locks/notices
and portable marker remain absent. App initialization also discovers locations
outside this permitted tree. No production or test code changed: no such fix
could receive the required real App proof here. More ordinary scanner fixtures
would not close App acceptance or the remaining scanner conditions.

Done:

- Actual [starter test](tools/test_launcher_entry.ps1): test exit 0; real
  `Tekken4.cmd` exit 1, missing private Python. Empty stderr and three input
  hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-06c5-8dba919f44cc483d81e2f32b91e69ff3/summary.json`.
- Actual [catalogs](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both 23-tool catalogs,
  three root inputs and three actual checker subprocess cases passed.
  Normal readiness remains 2 / BLOCKED. Empty stderr; 11 source hashes
  unchanged. Evidence:
  `logs/tests-catalogs-06c5-503dd8bc5c2c4b5289d6f992a6b5bb0e/summary.json`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `06c5b8013e`,
  finished `2026-11-02T11:52:50`: clean 190-second build
  `943fc4631acf2c13`; OFF selftest 6000 wall / 5106 logical frames,
  202 good restores, zero bad, 447 comparisons with zero mismatches,
  101/101 wrong-input divergences. OFF same-PC pair: 6000 live/logical
  frames, 199 hashes each, zero mismatches/NETDESYNC, FPS 48.0/48.0,
  stalls 0/126 (0/5357 ms), displayed-frame p99 165.5/118.8 ms, delay 3.
  Supplied, not reproduced here. Versus `71de043320`, FPS rose and p99
  fell; join stalls and stall time fell. Delay stayed 3. These uncontrolled
  summaries establish neither cause nor usable pacing.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Pad navigation remains absent.
Fullscreen inheritance and offline spawn-failure cleanup remain unexecuted
source observations. Failed scanner termination, interruption inside one write
and unobserved descendants remain unproved. Unchanged long aggregates and
the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices, then run
[actual launcher acceptance](docs/RELEASE_PATH_B.md) in the authorized
environment: responsive App/process identity, exit/reopen/settings, licence
cancel/accept, portable build/play/return. Python alone is insufficient.
GUI, Python suites, packagers, build, game and network helpers stayed **UNRUN
here**. A same-PC pair does not replace two PCs.

Area agents: `launcher_entry_06c5`, `tests_catalogs_06c5`,
`supplied_verify_06c5`, `portable_candidate_06c5`, `python_tk_06c5`,
`settings_process_06c5`, `controller_ui_06c5`, `offline_flow_06c5`,
`licence_inputs_06c5`, `source_privacy_06c5`, `player_payload_06c5`,
`corresponding_source_06c5`, `effective_profile_06c5`, `two_pc_pacing_06c5`,
`scanner_gaps_06c5`, `integrated_launcher_06c5`.
Root owns this record and `docs/status.md`; source editing ownership was
exclusive. Originals and a 351-file baseline are saved under
`logs/release-06c5-c34c877329a94057a03569f64b5d3f4a/`.
Actual readiness checked the two supplied-evidence documents / 18 links:
exit 2 / BLOCKED, empty stderr and 14 hashes unchanged. Evidence:
`logs/supplied-06c5-654117d3bc054b7a816b1c19f3fdea3e/summary.json`.
Combined actual readiness checked all four changed documents / 245 local
links, 12 required inputs and seven parses, then catalogs and actual starter
refusal: exit 2 / BLOCKED, empty stderr, all 351 baseline hashes unchanged
during the run. Exactly four documents differ from their saved originals.
Evidence is `combined-entry/` under the root evidence folder above. Two
initial wrapper attempts failed before checker execution (array handling,
then child-command quoting); neither supplies a passing result.
Separate reviewer `final_diff_review_06c5` found no blocking issue in these
four document changes: no source additions/deletions, earlier progress history
preserved, supplied metrics match the report. Independent actual readiness
repeated all 245 links: exit 2 / BLOCKED, empty stderr, all 351 hashes
unchanged during the run. Evidence is
`final-review-c1fec0c6006447dfb0ef6fcd18e27039/summary.json` under the root
evidence folder. A limited added-line check found no machine paths, mailboxes
or IPv4 addresses; it is not a complete privacy review. This review does not
close actual App/portable acceptance. No Git command, deletion, outside-tree
read, build, game, forbidden helper, server, push or release ran here.

## Current blocker and supplied verification 71de043320

Release remains **NO-GO**. The most valuable open item is actual App startup
and portable first-run. Sixteen independent area agents found no permitted
local fix that could receive real App proof. Private Python/Tk, dependencies,
reviewed locks/notices and the portable marker are absent. App initialization
also discovers locations outside this permitted tree. Repeating source audits
does not advance that acceptance gate; no production or test code changed.

Done this session:

- Actual [starter test](tools/test_launcher_entry.ps1): test exit 0, real
  `Tekken4.cmd` exit 1 for missing private Python. Empty stderr, three hashes
  unchanged. **The App never started.** Evidence:
  `logs/launcher-71de-9349a19e114b4805bdeafc9d7a246004/`.
- Actual [catalogs](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both 23-tool catalogs,
  three root inputs and three subprocess cases passed. Normal readiness is
  still 2 / BLOCKED. Empty stderr; 14 hashes unchanged. Evidence:
  `logs/tests-catalogs-71de-d322e94e0f214250ae99f3236d0f70f6/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `71de043320`,
  finished `2026-11-02T11:34:35`: clean 188-second build
  `943fc4631acf2c13`; OFF selftest 202 good restores, zero bad, 447 resim
  comparisons with zero mismatches, 101/101 wrong-input divergences. OFF
  same-PC pair: 6000 frames, 199 hashes each, zero mismatches/NETDESYNC,
  FPS 47.5/47.6, stalls 0/130 (0/5584 ms), displayed-frame p99
  167.1/122.8 ms, delay 3. Supplied, not reproduced here. Relative to
  `e93f58a43b`, FPS fell and both p99 values rose; join stalls fell but
  stall time rose, and delay changed from 2 to 3. No cause or usable pacing
  is established. Real readiness checked both documents / 18 links:
  exit 2 / BLOCKED, empty stderr, 14 hashes unchanged. Evidence:
  `logs/supplied-71de-0ce441fae5ea40f28f87fcee28eea766/summary-clean.json`.
  The first capture had module-progress stderr; only the clean rerun is used.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Pad navigation remains absent.
Fullscreen inheritance and offline spawn-failure cleanup remain unexecuted
source observations. Scanner termination failure, interruption inside one
write and unobserved descendants remain unproved; another ordinary fixture
would not establish those conditions. Unchanged long aggregates and the
whole-tree beta checker were not rerun.

Owner-only next step: supply the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices, then follow
[actual launcher acceptance](docs/RELEASE_PATH_B.md) in the authorized
environment: responsive App/process identity, normal exit/reopen/settings,
licence cancel/accept, portable build/play/return. Python alone is insufficient.
GUI, Python suites, packagers, build, game and network helpers stayed **UNRUN
here**. A same-PC pair does not replace two PCs.

Area agents: `launcher_entry_71de`, `tests_catalogs_71de`,
`supplied_verify_71de`, `portable_candidate_71de`, `python_tk_71de`,
`settings_process_71de`, `controller_ui_71de`, `offline_flow_71de`,
`licence_inputs_71de`, `source_privacy_71de`, `player_payload_71de`,
`corresponding_source_71de`, `effective_profile_71de`, `two_pc_pacing_71de`,
`scanner_gaps_71de`, `integrated_launcher_71de`.
Root owns this record and `docs/status.md`; editing ownership was exclusive.
Combined actual readiness checked all four changed documents / 239 local
links, 12 required inputs and seven parses, then ran catalogs and starter
refusal: exit 2 / BLOCKED, empty stderr, all 350 source hashes unchanged
during the run. Exactly four documents differ from their saved originals.
Evidence: `logs/release-71de-6f858b2485ab4fe8ae0efcdfecc4fb17/combined-entry/`.
An initial baseline-array setup failed before checker execution; it supplies
no test result. Separate reviewer `final_diff_review_71de` found no blocking
issue in the four document changes: no added/deleted source files, prior
progress history preserved. Its independent actual readiness repeated 239
links: exit 2 / BLOCKED, empty stderr, all 350 hashes unchanged during the run.
Evidence is `final-review/` under the same root evidence folder. A limited
check of changed text found no machine paths, mailboxes or IPv4 addresses;
this is not a complete privacy scan and review does not close acceptance.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification e93f58a43b

Release remains **NO-GO**. Actual App startup and portable first-run remain
the most valuable open item. Sixteen area agents checked its independent
prerequisites. Private Python, reviewed input locks, dependencies and the
portable toolchain marker are absent. App discovery also leaves this permitted
tree. No production or test change could receive real App proof here, and no
duplicate scanner test was added to substitute for it.

Done:

- Actual [starter-refusal entry](tools/test_launcher_entry.ps1): test exit 0
  for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr; three
  input hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-e93f-326d0ac3623c47deaeaefff8a48b25d2/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both 23-tool catalogs,
  three root inputs and three real subprocess cases passed. Normal readiness
  remains 2 / BLOCKED. Empty stderr; 14 input hashes unchanged. Evidence:
  `logs/tests-catalogs-e93f-ce9c88b6289a4868af405c55d605edd7/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `e93f58a43b`:
  clean 188-second build `943fc4631acf2c13`, finished `2026-11-02T11:22:07`.
  OFF selftest: 202 good restores, zero bad; 447 resim comparisons, zero
  mismatches; all 101 wrong-input passes diverged. OFF same-PC pair: 6000
  live/logical frames and 199 hashes each, zero mismatches/NETDESYNC,
  47.9/47.9 FPS, stalls 0/147 (0/5478 ms), displayed-frame p99
  156.8/118.8 ms. Actual delay was 2. Supplied, not reproduced here.
  Versus the preceding report FPS fell; host p99 fell and join p99 rose;
  join stalls and total stall time increased. Delay changed from 3 to 2.
  These are not controlled comparisons and establish neither cause nor
  usable pacing. Actual readiness checked both documents / 18 links:
  exit 2 / BLOCKED, empty stderr, eight input hashes unchanged. Evidence:
  `logs/supplied-e93f-9ce020e0b7d84ee89c82538d21940449/`.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Launcher-pad navigation remains
unimplemented. Fullscreen inheritance and offline spawn-failure log cleanup
remain unexecuted source observations. Scanner gaps remain failed termination,
interruption inside one write and unobserved descendants. Unchanged long
aggregates and the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices. Run its actual
`Tekken4.cmd` in the authorized validation environment using the existing
[checklist](docs/RELEASE_PATH_B.md): responsive App/process identity, normal
exit/reopen/settings, licence cancel/accept, then portable build/play/return.
Python alone is insufficient. Exact build/game, shared-launcher integration,
enabled GUI profile and two-PC acceptance still need real proof. GUI, Python
suites, packagers, build, game and network helpers stayed **UNRUN here**.
A same-PC pair does not replace two PCs.

Sixteen area agents: `launcher_entry_e93f`, `tests_catalogs_e93f`,
`supplied_verify_e93f`, `portable_candidate_e93f`, `python_tk_e93f`,
`settings_process_e93f`, `controller_ui_e93f`, `offline_flow_e93f`,
`licence_inputs_e93f`, `source_privacy_e93f`, `player_payload_e93f`,
`corresponding_source_e93f`, `effective_profile_e93f`, `two_pc_pacing_e93f`,
`scanner_gaps_e93f`, `integrated_launcher_e93f`.
Root owns this record and `docs/status.md`; file ownership is exclusive.
Baseline: 350 files outside logs/Git, with four original documents in
`logs/release-e93f-36007e09d73442718f051d950d8752d7/`.
Combined actual readiness checked all four changed documents / 233 local
links, 12 required inputs and seven parses, then catalogs and starter refusal:
exit 2 / BLOCKED, empty stderr, all 350 source hashes unchanged during the run.
Evidence: `combined-entry/` under the root folder above. Its original summary
mis-enumerated the deserialized baseline array; `summary-corrected.json`
records exactly four changed documents. Production, tests and patches remain
unchanged. Separate reviewer `final_diff_review_e93f` found no blocking issue:
exactly four documents edited, no added/deleted source files, earlier progress
history preserved. Its independent actual readiness repeated all 233 links:
exit 2 / BLOCKED, empty stderr, all 350 hashes unchanged during the run.
Evidence: `final-review/` under the same root folder. A limited check of new
authored evidence found no machine paths or address matches; this is not a
complete content/privacy scan. Review does not close App/portable acceptance.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification 418a01983c

Release remains **NO-GO**. The most valuable open item is actual App startup
and portable first-run through the exact complete candidate. Sixteen area
agents checked independent prerequisites. Private Python, reviewed locks,
dependencies and the portable toolchain marker remain absent. Actual App
initialization also searches outside this permitted tree. No production or
test change could receive the required real-entry proof here. No duplicate
scanner test was added to stand in for App acceptance.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): test exit 0
  for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr; three
  source hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-418a-8bbb1475a51b435ebd866c695b45fb85/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both 23-tool catalogs,
  three root inputs and three real subprocess cases passed. Normal readiness
  remains 2 / BLOCKED. Empty stderr; 14 input hashes unchanged. Evidence:
  `logs/tests-catalogs-418a-2193b5d4eefb425fbc3b7b0a04d14c43/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `418a01983c`:
  clean 191-second build `943fc4631acf2c13`, finished `2026-11-02T11:09:21`.
  OFF selftest: 202 good restores, zero bad; 447 resim comparisons, zero
  mismatches; all 101 wrong-input passes diverged. OFF same-PC pair: 6000
  live/logical frames and 199 hashes each, zero mismatches/NETDESYNC,
  48.6/48.6 FPS, stalls 0/117 (0/5111 ms), displayed-frame p99
  158.2/115.6 ms. Supplied, not reproduced here. Versus the preceding report,
  FPS rose; host p99 rose and join p99 fell. Join had fewer stalls but more
  total stall time. No cause or usable pacing is established. Actual readiness
  checked both documents / 18 links: exit 2 / BLOCKED, empty stderr,
  eight input hashes unchanged. Evidence:
  `logs/supplied-418a-ff92c3c109c8408197184dec0d57d452/`.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Launcher-pad navigation remains
unimplemented. Fullscreen inheritance and offline spawn-failure log cleanup
remain unexecuted source observations. Scanner gaps remain failed termination,
interruption inside one write and unobserved descendants. Unchanged long
aggregates and the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices. Run its actual
`Tekken4.cmd` in the authorized validation environment using the existing
[checklist](docs/RELEASE_PATH_B.md): responsive App/process identity, normal
exit/reopen/settings, licence cancel/accept, then portable build/play/return.
Python alone is insufficient. Exact build/game, shared-launcher integration,
enabled GUI profile and two-PC acceptance still need real proof. GUI, Python
suites, packagers, build, game and network helpers stayed **UNRUN here**.
A same-PC pair does not replace two PCs.

Sixteen area agents: `launcher_entry_418a`, `tests_catalogs_418a`,
`supplied_verify_418a`, `portable_candidate_418a`, `python_tk_418a`,
`settings_process_418a`, `controller_ui_418a`, `offline_flow_418a`,
`licence_inputs_418a`, `source_privacy_418a`, `player_payload_418a`,
`corresponding_source_418a`, `effective_profile_418a`, `two_pc_pacing_418a`,
`scanner_gaps_418a`, `integrated_launcher_418a`.
Root owns this record and `docs/status.md`; file ownership is exclusive.
Baseline inventory: 351 files outside logs/Git, with four original documents
in `logs/release-418a-c778facd2a7249a4ac4b85aa31360d52/`.
Combined actual readiness checked all four changed documents / 227 local
links, 12 required inputs and seven parses, then catalogs and starter refusal:
exit 2 / BLOCKED, empty stderr, all 351 source hashes unchanged during the run.
Completed evidence is `combined-entry-completed/` under the root evidence
folder above. Initial `combined-entry/` array setup failed before execution;
`combined-entry-rerun/` failed in child command parsing. Neither is passing
evidence. Production, tests and patches remain unchanged. Separate final
diff reviewer `final_diff_review_418a` found no blocking issue: exactly four
documents changed, no added/deleted source files, earlier history preserved.
Its independent actual readiness repeated all 227 links: exit 2 / BLOCKED,
empty stderr, all 351 hashes unchanged during the run. Evidence is under
`final-review/` in the same root folder. Review does not close actual
App/portable or release acceptance.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification ca749414b0

Release remains **NO-GO**. Actual App startup and portable first-run through
the exact complete candidate remain the most valuable open item. Sixteen
area agents checked its independent prerequisites. Private Python, reviewed
locks, dependencies and the portable toolchain marker remain absent. Actual
App discovery also accesses locations outside this permitted tree. No
production or test change was justified that could receive real-entry proof
here. No duplicate scanner test was added to stand in for App acceptance.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): test exit 0
  for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr; three
  source hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-ca74-906526f1573642f9abc50462dbc1f4bf/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both 23-tool catalogs,
  three root inputs and three real subprocess cases passed. Normal readiness
  remains 2 / BLOCKED. Empty stderr; ten input hashes unchanged. Evidence:
  `logs/tests-catalogs-ca74-c578161907594aaa8b525252d801f2a2/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `ca749414b0`:
  clean 184-second build `943fc4631acf2c13`, finished `2026-11-02T10:54:33`.
  OFF selftest: 202 good restores, zero bad; 447 resim comparisons, zero
  mismatches; all 101 wrong-input passes diverged. OFF same-PC pair: 6000
  live/logical frames and 199 hashes each, zero mismatches/NETDESYNC,
  47.9/47.9 FPS, stalls 0/125 (0/4838 ms), displayed-frame p99
  153.0/120.9 ms. Supplied, not reproduced here. Host p99 fell and join p99
  rose versus the preceding report; no cause or usable pacing is established.
  Actual readiness checked both documents / 18 links: exit 2 / BLOCKED,
  empty stderr, eight input hashes unchanged. Evidence:
  `logs/supplied-ca74-597e17bdd2954b04894f71bef5f91e3e/`.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Launcher-pad navigation remains
unimplemented. Fullscreen inheritance and offline spawn-failure log cleanup
remain unexecuted source observations. Scanner gaps remain failed termination,
interruption inside one write and unobserved descendants. Unchanged long
aggregates and the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices. Run its actual
`Tekken4.cmd` in the authorized validation environment using the existing
[checklist](docs/RELEASE_PATH_B.md): responsive App/process identity, normal
exit/reopen/settings, licence cancel/accept, then portable build/play/return.
Python alone is insufficient. Exact build/game, shared-launcher integration,
enabled GUI profile and two-PC acceptance still need real proof. GUI, Python
suites, packagers, build, game and network helpers stayed **UNRUN here**.
A same-PC pair does not replace two PCs.

Sixteen area agents: `launcher_entry_ca74`, `tests_catalogs_ca74`,
`supplied_verify_ca74`, `portable_candidate_ca74`, `python_tk_ca74`,
`settings_process_ca74`, `controller_ui_ca74`, `offline_flow_ca74`,
`licence_inputs_ca74`, `source_privacy_ca74`, `player_payload_ca74`,
`corresponding_source_ca74`, `effective_profile_ca74`, `two_pc_pacing_ca74`,
`scanner_gaps_ca74`, `integrated_launcher_ca74`.
Root owns this record and `docs/status.md`; file ownership is exclusive.
Baseline inventory of 350 files outside logs/Git and four original documents:
`logs/release-ca74-de1e2e1be9f94d30985d9e15a51a95de/`.
Combined actual readiness checked all four changed documents / 221 local
links, 12 required files and seven parses, then catalogs and starter refusal:
exit 2 / BLOCKED, empty stderr, all 350 source hashes unchanged during the
run. Completed capture: `strict-rerun/` under the root evidence folder above.
An initial baseline-array setup failed before execution; `strict-final/`
then mishandled exit propagation and emitted module-progress stderr. Neither
is passing evidence. Only the corrected capture supplies the completed check.
Production, tests and patches remain unchanged. Separate final reviewer
`final_diff_review_ca74` found no blocking issue: exactly four documents
changed, no added/deleted source files, earlier progress history preserved.
Its independent actual readiness repeated all 221 links: exit 2 / BLOCKED,
empty stderr, all 350 hashes unchanged during the run. Evidence is under
`final-review/` in the same root folder. Review does not close App/portable
or release acceptance. No Git command, deletion, outside-tree read, build,
game, forbidden helper, server, push or release ran.

## Release gate and supplied verification ab64c85901

Release remains **NO-GO**. The most valuable open item is actual App startup
and portable first-run through the exact complete candidate. Sixteen area
agents checked its independent prerequisites. Private Python, reviewed locks
and the portable toolchain marker remain absent; App discovery also leaves
this permitted tree. No production or test change could be justified and
exercised here. Another scanner pass cannot prove App startup.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): test exit 0
  for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr; three
  source hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-ab64-90577a2137274924ae099799f5219bff/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both 23-tool catalogs,
  three root inputs and three real subprocess cases passed. Normal readiness
  remains 2 / BLOCKED. Empty stderr; ten source hashes unchanged. Evidence:
  `logs/tests-catalogs-ab64-59d8328859c04a88b114ae3ebead1639/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `ab64c85901`:
  clean 187-second build `943fc4631acf2c13`, finished `2026-11-02T10:31:53`.
  OFF selftest: 202 good restores, zero bad; 447 resim comparisons, zero
  mismatches; all 101 wrong-input passes diverged. OFF same-PC pair: 6000
  live/logical frames and 199 hashes each, zero mismatches/NETDESYNC,
  47.9/47.9 FPS, stalls 0/128 (0/5136 ms), displayed-frame p99
  166.4/118.4 ms. Supplied, not reproduced here. These summaries establish
  neither a pacing cause nor usable pacing, actual App startup, enabled GUI
  profile or two-PC acceptance.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Launcher-pad navigation remains
unimplemented. Fullscreen inheritance and offline spawn-failure log cleanup
remain unexecuted source observations. Scanner gaps remain failed termination,
interruption inside one write and unobserved descendants. No duplicate test
was added. Unchanged long aggregates and whole-tree beta checker were not rerun.

Owner-only next step: supply the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices. Run its actual
`Tekken4.cmd` in the authorized validation environment using the existing
[checklist](docs/RELEASE_PATH_B.md): responsive App/process identity, normal
exit/reopen/settings, licence cancel/accept, then portable build/play/return.
Python alone is insufficient. Exact build/game, shared-launcher integration,
enabled GUI profile and two-PC acceptance still need real proof. GUI, Python
suites, packagers, build, game and network helpers stayed **UNRUN here**.
A same-PC pair does not replace two PCs.

Sixteen area agents: `launcher_entry_ab64`, `tests_catalogs_ab64`,
`supplied_verify_ab64`, `portable_candidate_ab64`, `python_tk_ab64`,
`settings_process_ab64`, `controller_ui_ab64`, `offline_flow_ab64`,
`licence_inputs_ab64`, `source_privacy_ab64`, `player_payload_ab64`,
`corresponding_source_ab64`, `effective_profile_ab64`, `two_pc_pacing_ab64`,
`scanner_gaps_ab64`, `integrated_launcher_ab64`.
Root owns this record and `docs/status.md`; file ownership is exclusive.
Baseline inventory of 350 files outside logs/Git (including three existing
archives) and four original documents:
`logs/release-ab64-e8d8f4ac6cd24ad0a7f3c60bca590035/`.
Combined actual readiness checked all four changed documents / 215 local
links, 12 required files and seven parses, then catalogs and starter refusal:
exit 2 / BLOCKED, empty stderr; all 350 baseline hashes unchanged during the
run. Completed capture: `strict-rerun/` under the root evidence folder above.
The initial `strict-final/` hash comparison mishandled a JSON array; only the
corrected capture supplies the completed hash check. Exactly four documents
changed from baseline. Production, tests and patches remain unchanged.
Separate final reviewer: `final_diff_review_ab64`; its independent result is
recorded under `final-review/` in the same evidence folder. Review and source
checks cannot close App/portable or release acceptance.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification e1da2bebeb

Release remains **NO-GO**. Actual App startup and portable first-run through
the exact complete candidate remain the most valuable open item. Sixteen
area agents found no new fix that could be justified and exercised here.
Private Python, reviewed locks and the portable toolchain marker are absent;
App initialization also searches outside this permitted tree. No production
or test code changed. Repeating scanner suites cannot prove App startup.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): test exit 0
  for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr; three
  source hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-e1-f36a1bc17f384babb9629da89911b406/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both 23-tool catalogs,
  three root inputs and three real subprocess cases passed. Normal readiness
  remains 2 / BLOCKED. Empty stderr; ten source hashes unchanged. Evidence:
  `logs/tests-catalogs-e1-7654e943fb1e4376a3cf7c90b2848414/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `e1da2bebeb`:
  clean 199-second build `943fc4631acf2c13`, finished `2026-11-02T10:16:49`.
  OFF selftest: 202 good restores, zero bad; 447 resim comparisons, zero
  mismatches; all 101 wrong-input passes diverged. OFF same-PC pair: 6000
  live/logical frames and 199 hashes each, zero mismatches/NETDESYNC,
  47.8/47.8 FPS, stalls 0/121 (0/5199 ms), displayed-frame p99
  155.7/114.9 ms. Supplied, not reproduced here. These summaries establish
  neither a pacing cause nor usable pacing, actual App startup, enabled GUI
  profile or two-PC acceptance. Actual readiness checked both documents and
  18 local links: exit 2 / BLOCKED, empty stderr; eight hashes unchanged.
  Evidence and original bytes: `logs/supplied-e1-78762e9ae6354670b368abbe69a09a13/`.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Launcher-pad navigation remains
unimplemented. Fullscreen inheritance and offline spawn-failure log cleanup
remain unexecuted source observations. Scanner gaps remain failed termination,
interruption inside one write and unobserved descendants. No duplicate test
was added. Unchanged long aggregates and whole-tree beta checker were not rerun.

Owner-only next step: supply the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices. Run its actual
`Tekken4.cmd` in the authorized validation environment using the existing
[checklist](docs/RELEASE_PATH_B.md): responsive App/process identity, normal
exit/reopen/settings, licence cancel/accept, then portable build/play/return.
Python alone is insufficient. Exact build/game, shared-launcher integration,
enabled GUI profile and two-PC acceptance still need real proof. GUI, Python
suites, packagers, build, game and network helpers stayed **UNRUN here**.
A same-PC pair does not replace two PCs.

Sixteen area agents: `launcher_entry_e1`, `tests_catalogs_e1`,
`supplied_verify_e1`, `portable_candidate_e1`, `python_tk_e1`,
`settings_process_e1`, `controller_ui_e1`, `offline_flow_e1`,
`licence_inputs_e1`, `source_privacy_e1`, `player_payload_e1`,
`corresponding_source_e1`, `effective_profile_e1`, `two_pc_pacing_e1`,
`scanner_gaps_e1`, `integrated_launcher_e1`.
Root owns this record and `docs/status.md`; file ownership is exclusive.
Source inventory and root document originals:
`logs/release-e1-4765cf4bd4b44beca50d110237e1edb3/`.
Combined actual readiness checked all four changed documents / 209 local
links, 12 required files and seven parses, then catalogs and starter refusal:
exit 2 / BLOCKED, empty stderr, all 347 source hashes unchanged during the run.
Completed capture: `strict-final/` under the root evidence folder above.
Separate final reviewer `final_diff_review_e1` found no blocking issue:
exactly four changed documents, no added/deleted source files, earlier progress
history and production/tests/patches unchanged. Independent actual readiness
repeated the 209-link check: exit 2 / BLOCKED, empty stderr, all 347 hashes
unchanged during the run. Completed evidence is under `final-review/` in the
same root folder. The baseline JSON has a `value` wrapper containing its 347
records; independent review unpacked it. Failed baseline setup commands are
not passing test evidence. Final review does not close release acceptance.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification d8b2714632

Release remains **NO-GO**. The most valuable open item is actual App startup
and portable first-run through the exact complete candidate. Sixteen area
agents checked the independent prerequisites. Private Python, reviewed locks
and the portable toolchain marker are still absent; actual App initialization
also searches outside this permitted tree. No new production fix could be
justified and exercised here. Another scanner pass cannot prove App startup.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): test exit 0
  for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr; three
  source hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-d8-4fea54d46b2f43b4acb2fb3afdd8d108/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both 23-tool catalogs,
  three root inputs and three real subprocess cases passed. Normal readiness
  remains 2 / BLOCKED. Empty stderr; ten source hashes unchanged. Evidence:
  `logs/tests-catalogs-d8-6b811e073ef6415a8dbe6f4cb26c78b6/`.
- Recorded supplied draft `d8b2714632` in the
  [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and
  [decision sheet](docs/BETA_GO_NO_GO.md): clean 181-second build
  `943fc4631acf2c13`, finished `2026-11-02T10:02:57`. OFF selftest:
  202 good restores, zero bad; 447 resim comparisons, zero mismatches;
  all 101 wrong-input passes diverged. OFF same-PC pair: 6000 live/logical
  frames and 199 hashes each, zero mismatches/NETDESYNC, 48.0/48.1 FPS,
  stalls 0/120 (0/5208 ms), displayed-frame p99 160.9/113.8 ms. Supplied,
  not reproduced here. These summaries establish neither a pacing cause nor
  usable pacing, actual App startup, enabled GUI profile or two-PC acceptance.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Launcher-pad navigation remains
unimplemented. Fullscreen inheritance and offline spawn-failure log cleanup
remain unexecuted source observations. Scanner limits remain failed
termination, interruption inside one write and unobserved descendants.
No production or test code changed. Unchanged long aggregates and the
whole-tree beta checker were not rerun.

Owner-only next step: supply the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices. Run its actual
`Tekken4.cmd` in the authorized validation environment using the existing
[checklist](docs/RELEASE_PATH_B.md): responsive App/process identity, normal
exit/reopen/settings, licence cancel/accept, then portable build/play/return.
Python alone is insufficient. Exact build/game, shared-launcher integration,
enabled GUI profile and two-PC acceptance still need real proof. GUI, Python
suites, packagers, build, game and network helpers stayed **UNRUN here**.
A same-PC pair does not replace two PCs.

Sixteen area agents: `launcher_entry_d8`, `tests_catalogs_d8`,
`supplied_verify_d8`, `portable_candidate_d8`, `python_tk_d8`,
`settings_process_d8`, `controller_ui_d8`, `offline_flow_d8`,
`licence_inputs_d8`, `source_privacy_d8`, `player_payload_d8`,
`corresponding_source_d8`, `effective_profile_d8`, `two_pc_pacing_d8`,
`scanner_gaps_d8`, `integrated_launcher_d8`.
Root owns this record and `docs/status.md`; file ownership is exclusive.
Original bytes and the 347-file source inventory are in
`logs/release-d8-792ddb8a410b479abf2dc9877dfde003/`.
Combined actual readiness checked all four changed documents / 203 local
links, 12 required files and seven parses, then catalogs and starter refusal:
exit 2 / BLOCKED, empty stderr, all 347 source hashes unchanged during the run.
Evidence is under `strict-final/`. The initial supplied-document capture
mishandled exit propagation; its completed `strict-rerun/` is the valid capture:
`logs/supplied-d8-c36b3f169d0f46ffb9faa3d6c5966cc1/strict-rerun/`.
The initial inline inventory comparison mishandled the JSON array; the corrected
comparison confirmed exactly four changed documents. Only completed captures
count as proof. Separate final reviewer `final_diff_review_d8` found no
blocking issue: exactly four changed documents; production/tests/patches and
earlier progress history unchanged. Independent final readiness repeated the
203-link check: exit 2 / BLOCKED, empty stderr, all 347 hashes unchanged during
the run. Its completed capture is under `final-review/`.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification 4b6cea90c2

Release remains **NO-GO**. The most valuable open item is actual App startup
and portable first-run through the exact complete candidate. Sixteen area
agents checked its independent prerequisites. No new executable local fix
was found. Private Python, reviewed locks and the portable toolchain marker
are absent; actual App initialization also searches outside this tree.
Another scanner test cannot supply that missing acceptance evidence.

Done:

- Ran the actual [starter-refusal test](tools/test_launcher_entry.ps1):
  test exit 0 for real `Tekken4.cmd` exit 1, missing private Python. Empty
  stderr; four source hashes unchanged. **The App never started.** Evidence:
  `logs/launcher-4b6-2f4cd58b010f422ab541c7ea794f2cb8/`.
- Ran the actual [catalog checker](tools/check_online_catalogs.ps1) and
  [readiness tests](tools/test_online_readiness.ps1): both 23-tool catalogs,
  three root inputs and three real subprocess cases passed. Normal readiness
  stayed 2 / BLOCKED. Empty stderr; ten source hashes unchanged. Evidence:
  `logs/tests-catalogs-4b6-c2649877256a46c6b9637e2a07a7867b/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `4b6cea90c2`:
  clean 226-second build `943fc4631acf2c13`, finished `2026-11-02T09:49:16`.
  OFF selftest: 202 good restores, zero bad; 447 resim comparisons, zero
  mismatches; all 101 wrong-input passes diverged. OFF same-PC pair: 6000
  live/logical frames and 199 hashes each, zero mismatches/NETDESYNC,
  47.6/47.7 FPS, stalls 0/117 (0/5326 ms), displayed-frame p99
  163.2/119.6 ms. Supplied, not reproduced here. These summaries establish
  neither cause nor usable pacing, actual App startup or two-PC acceptance.
  Actual readiness checked both documents / 18 links: exit 2 / BLOCKED,
  empty stderr; eight source/doc hashes unchanged. Evidence:
  `logs/supplied-4b6-306c5b808eed426e8f5f68581509a120/`.

Open: actual App/portable acceptance, Python suites, complete source/player
content and privacy/licence review, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Launcher-pad navigation remains
unimplemented. Fullscreen inheritance and offline spawn-failure log cleanup
remain unexecuted source observations. Scanner limits remain failed
termination, interruption inside one write and unobserved descendants.
No production or test code changed; unchanged long aggregates and the
whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices. Run its actual
`Tekken4.cmd` in the authorized validation environment using the existing
[checklist](docs/RELEASE_PATH_B.md): responsive App/process identity, normal
exit/reopen/settings, licence cancel/accept, then portable build/play/return.
Python alone is insufficient. Exact build/game, shared-launcher integration,
enabled GUI profile and two-PC acceptance still need real proof. GUI, Python
suites, packagers, build, game and network helpers stayed **UNRUN here**.
A same-PC pair does not replace two PCs.

Sixteen area agents: `launcher_entry_4b6`, `tests_catalogs_4b6`,
`supplied_verify_4b6`, `portable_candidate_4b6`, `python_tk_4b6`,
`settings_process_4b6`, `controller_ui_4b6`, `offline_flow_4b6`,
`licence_inputs_4b6`, `source_privacy_4b6`, `player_payload_4b6`,
`corresponding_source_4b6`, `effective_profile_4b6`, `two_pc_pacing_4b6`,
`scanner_gaps_4b6`, `integrated_launcher_4b6`.
Separate final reviewer: `final_diff_review_4b6`. File ownership was exclusive.
Root owns this record and `docs/status.md`. Original bytes and the 347-file
source inventory are in `logs/release-4b6-0f96940f6e2b411dbe3f4d2112691a93/`.
Combined actual readiness checked all four changed documents / 197 local
links, 12 required files and seven parses, then catalogs and starter refusal:
exit 2 / BLOCKED, empty stderr, all 347 source hashes unchanged during the run.
Its evidence is under `strict-final/`; separate review is under `final-review/`.
The initial `final-entry/` capture mishandled the inventory array; it is
retained as invalid, not passing proof. Only completed captures count.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification e6b8a2550c

Release remains **NO-GO**. Actual App startup and portable first-run through
an exact complete candidate remain the most valuable open item. Sixteen
area agents found no justified fix that can be exercised here. Private
Python, reviewed locks and the portable toolchain marker are absent; App
initialization discovers ISO candidates outside this permitted tree. No
production or test code changed. More source checks cannot prove startup.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): test exit 0
  for real `Tekken4.cmd` exit 1, missing private Python; empty stderr and
  four source hashes unchanged. App never started. Evidence:
  `logs/launcher-e6-d4b39fff61694596bfbe262c607e9b5e/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1): both 23-tool
  catalogs and three root files passed. Actual
  [readiness tests](tools/test_online_readiness.ps1): three real subprocess
  cases passed; normal readiness stayed 2 / BLOCKED. Empty stderr and ten
  source hashes unchanged. Evidence:
  `logs/tests-catalogs-e6-1a25d926dfb846cb87f2ed55422bae1f/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `e6b8a2550c`:
  clean 193-second build `943fc4631acf2c13`, finished `2026-11-02T09:33:49`.
  OFF selftest: 202 good restores, zero bad; 447 resim comparisons, zero
  mismatches; all 101 wrong-input passes diverged. OFF same-PC pair: 6000
  live/logical frames and 199 hashes each, zero mismatches/NETDESYNC,
  47.7/47.7 FPS, stalls 0/150 (0/6526 ms), displayed-frame p99
  172.2/122.3 ms. Supplied, not reproduced here; no App, enabled GUI-profile
  or two-PC acceptance. The summaries establish no cause or usable pacing.
  Actual readiness checked both documents / 18 links: exit 2 / BLOCKED,
  empty stderr, eight source hashes unchanged. Strict evidence and originals:
  `logs/supplied-e6-5e7a4838de9042ce822cabcd4a9374f4/`.
- Independent area reviews confirmed the existing
  [owner checklist](docs/RELEASE_PATH_B.md) already requires the real App's
  responsiveness/process identity, normal exit/reopen/settings, licence
  cancel/accept and build/play/return. Launcher-pad navigation remains
  unimplemented. The three old incomplete ZIPs are not complete candidates.
  No duplicate scanner suite or speculative production fix was added.

Open: actual App/portable acceptance, complete source/player content and
privacy/licence review, Python suites, enabled GUI Host/Join profile and two
physical PCs with sound-on usable pacing. Fullscreen inheritance and offline
spawn-failure log cleanup remain source observations, not reproduced defects.
Scanner limits remain failed termination, interruption inside one write and
unobserved descendants. Retained fixture findings and incomplete archives
remain failures. Unchanged long aggregates and whole-tree beta checker were
not rerun.

Owner-only next step: supply the exact reviewed complete candidate and ZIP
hash, matching complete source and reviewed locks/notices; run its actual
`Tekken4.cmd` with the existing checklist in the authorized validation
environment. Observe responsive App, normal exit/reopen/settings and licence
cancel/accept, then portable first-run/build/play/return. Python alone is
insufficient. Exact build/game, shared-launcher integration, enabled GUI
profile and two-PC acceptance still need real proof. GUI, Python suites,
packagers, build, game and network helpers stayed **UNRUN here**. A same-PC
pair does not replace two PCs.

Sixteen area agents: `launcher_entry_e6`, `tests_catalogs_e6`,
`supplied_verify_e6`, `portable_candidate_e6`, `python_tk_e6`,
`settings_process_e6`, `controller_ui_e6`, `offline_flow_e6`,
`licence_inputs_e6`, `source_privacy_e6`, `player_payload_e6`,
`corresponding_source_e6`, `effective_profile_e6`, `two_pc_pacing_e6`,
`scanner_gaps_e6`, `integrated_launcher_e6`.
Separate final reviewer: `final_diff_review_e6`. File ownership was exclusive.
Root owns this record and `docs/status.md`; original bytes and 347-file scoped
inventory are in `logs/release-e6-8d77018f623f4469bc8bfb35be9f5007/`.
Combined readiness capture and independent review belong under that folder's
`strict-final/` and `final-review/`; only their completed results count as proof.
Initial combined capture failed inventory-array handling after the checker ran;
its `final-entry/` is retained as invalid. Launcher harness filename failure
and supplied-document setup/exit
capture failures are retained as invalid evidence, never passing proof.

No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification c7f83cf8a0

Release remains **NO-GO**. The most valuable open item is still actual App
startup and portable first-run through the exact complete candidate. Sixteen
area agents found no new justified fix that can be run here. Private Python,
reviewed input locks and the portable toolchain marker are absent; App
initialization searches outside this permitted tree. No production or test
code changed. Repeating source checks cannot establish App acceptance.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): exit 0 only
  for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr; starter
  and test hashes unchanged. The App never started. Evidence:
  `logs/launcher-c7-681437fb07bc4f9aa16d4dd3b95ab0b2/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1): both 23-tool
  catalogs and three root files passed. Actual
  [readiness tests](tools/test_online_readiness.ps1): three real checker
  subprocess cases passed; normal readiness stayed 2 / BLOCKED. Empty stderr;
  ten source hashes unchanged. Evidence:
  `logs/tests-catalogs-c7-93c13aabd00647ba9fb04c9cb64fd1f7/`.
- Recorded the latest supplied draft `c7f83cf8a0` in the
  [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and
  [decision sheet](docs/BETA_GO_NO_GO.md): clean 189-second build
  `943fc4631acf2c13`, finished `2026-11-02T09:21:01`. OFF selftest: 202 good
  restores, zero bad, 447 resim comparisons with zero mismatches, all 101
  wrong-input passes diverged. OFF same-PC pair: 6000 live/logical frames and
  199 hashes each, zero mismatches/NETDESYNC, 48.2/48.2 FPS, stalls 0/146
  (0/6403 ms), displayed-frame p99 162.8/117.3 ms. Supplied, not reproduced
  here. Negotiated delay changed from 2 to 3; these summaries do not establish
  a cause for pacing changes or prove usable pacing.
- Independent portable, Python/Tk, settings/process, controller, offline,
  licence, privacy, player-payload, corresponding-source, effective-profile,
  two-PC, scanner-gap and integrated-launcher reviews found no executable
  local acceptance fix. Existing [owner checks](docs/RELEASE_PATH_B.md)
  already require responsive actual App/process identity, exit/reopen/settings,
  licence cancel/accept and build/play/return. Launcher-pad navigation remains
  unimplemented; in-game controls cannot prove it. The three old incomplete
  ZIPs are not complete candidates. No duplicate scanner suite was added.

Open: actual App/portable acceptance, complete source/player content and
privacy/licence review, Python suites, enabled GUI Host/Join profile and two
physical PCs. Fullscreen inheritance and offline spawn-failure log cleanup
remain source observations, not reproduced fixes. Scanner limits still include
failed termination, interruption inside one write and unobserved descendants.
Retained fixture findings and incomplete archives remain failures. Unchanged
long aggregates and the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate, ZIP hash,
matching complete source and reviewed locks/notices; run its actual
`Tekken4.cmd` using the existing checklist in the authorized validation
environment. Observe responsive App, normal exit/reopen/settings and licence
cancel/accept, then portable first-run/build/play/return. Python alone is
insufficient. Exact build/game, shared-launcher integration, enabled GUI
profile, sound-on usable pacing and two physical PCs still need real proof.
GUI, Python suites, packagers, build, game and network helpers stayed **UNRUN
here**. The supplied same-PC run does not replace two PCs.

Sixteen area agents: `launcher_entry_c7`, `tests_catalogs_c7`,
`supplied_verify_c7`, `portable_candidate_c7`, `python_tk_c7`,
`settings_process_c7`, `controller_ui_c7`, `offline_flow_c7`,
`licence_inputs_c7`, `source_privacy_c7`, `player_payload_c7`,
`corresponding_source_c7`, `effective_profile_c7`, `two_pc_pacing_c7`,
`scanner_gaps_c7`, `integrated_launcher_c7`.
Separate final reviewer: `final_diff_review_c7`. File ownership was exclusive.
Root owns this record and `docs/status.md`. Original bytes and the 347-file
scoped inventory are in
`logs/release-c7-a4376efcd7d04aa0b7ee23b34ac3dedd/`.
Actual readiness verification for all four changed documents is captured in
that folder's `strict-final/`; independent review is in `final-review/`.
The initial `final-entry/` ran the checker (exit 2, empty stderr) but its
inventory array handling was invalid; that capture is retained as failed
evidence. The supplied-document agent also retained an initial invalid exit
capture, followed by its strict rerun at
`logs/supplied-c7-a1ddd9dfd0ec4b2aa341476c0a5db89f/strict-rerun/`.
Readiness remains BLOCKED; neither check establishes App acceptance.

No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification f74cffb3f8

Release remains **NO-GO**. The most valuable open item is the exact complete
package's actual App startup and portable first-run. Sixteen independent
areas found no justified fix that can be tested here. Private Python, reviewed
input locks and the portable toolchain marker are absent; App initialization
starts ISO discovery outside this permitted tree. No production or test code
changed. Another scanner pass cannot establish App acceptance.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): test exit 0
  solely for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr;
  four source hashes unchanged. The App never started. Evidence:
  `logs/launcher-f74-138b5e96f27448f681f59fd198dce247/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1): both 23-tool
  catalogs and three root files passed. Actual
  [readiness tests](tools/test_online_readiness.ps1): three real checker
  subprocess cases passed; normal readiness stayed 2 / BLOCKED. Empty stderr;
  ten checked hashes unchanged. Evidence:
  `logs/tests-catalogs-f74-dc61840f53f04bc691622b7f61341689/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `f74cffb3f8`:
  clean 251-second build `943fc4631acf2c13`, finished `2026-11-02T09:03:54`.
  OFF selftest: 202 good restores, zero bad, 447 resim comparisons with zero
  mismatches, all 101 wrong-input passes diverged. OFF same-PC pair: 6000
  live/logical frames and 199 hashes each, zero mismatches/NETDESYNC,
  47.6/47.6 FPS, stalls 0/144 (0/6256 ms), displayed-frame p99 162.5/123.3 ms.
  Supplied, not reproduced here. FPS rose from the preceding supplied report;
  host p99 rose while join p99 fell. These summaries establish neither cause
  nor usable pacing. Actual readiness checked both changed documents / 18
  local links: exit 2 / BLOCKED, empty stderr, eight checked hashes unchanged.
  Originals and evidence:
  `logs/supplied-f74-4a82181afa3d4006b0191c30d00ade91/`.
- Independent portable, Python/Tk, settings/process, controller, offline flow,
  licence, privacy, player payload, corresponding-source, effective-profile,
  two-PC, scanner-gap and integrated-launcher reviews found no new executable
  local fix. Existing [owner acceptance](docs/RELEASE_PATH_B.md) already
  requires actual responsive App/process identity, exit/reopen/settings,
  licence cancel/accept and build/play/return. In-game controls do not prove
  launcher-pad navigation, which remains unimplemented. Old incomplete ZIPs
  and name inspection cannot establish content safety or portable acceptance.

Open: actual App/portable acceptance, complete source/player content and
privacy/licence review, Python suites, enabled GUI Host/Join profile and two
physical PCs. Fullscreen inheritance and offline spawn-failure log cleanup
remain source observations, not reproduced fixes. Scanner limits remain failed
termination, interruption inside one write and unobserved descendants. Retained
fixture findings and incomplete archives remain failures. Unchanged long
aggregates and the whole-tree beta checker were not rerun.

Owner-only next step: supply the exact reviewed complete candidate, ZIP hash,
matching complete source and reviewed locks/notices; run its actual
`Tekken4.cmd` in the authorized validation environment using the existing
checklist. Observe responsive App, normal exit/reopen/settings, then portable
first-run/build/play/return. Python alone is insufficient. Exact build/game,
shared-launcher integration, enabled GUI profile, sound-on usable pacing and
two physical PCs still need real proof. GUI, Python suites, packagers, build,
game and network helpers stayed **UNRUN here**.

Sixteen area agents: `launcher_entry_f74`, `tests_catalogs_f74`,
`supplied_verify_f74`, `portable_candidate_f74`, `python_tk_f74`,
`settings_process_f74`, `controller_ui_f74`, `offline_flow_f74`,
`licence_inputs_f74`, `source_privacy_f74`, `player_payload_f74`,
`corresponding_source_f74`, `effective_profile_f74`, `two_pc_pacing_f74`,
`scanner_gaps_f74`, `integrated_launcher_f74`.
Separate final reviewer: `final_diff_review_f74`. File ownership was exclusive.
Root owns this record and `docs/status.md`; saved original bytes/hashes and
the 347-file scoped inventory are in
`logs/release-f74-9e7f6ffe13394aa585c099d4aa2d5bec/`.
Root's actual readiness entry checked four documents / 179 local links,
12 required files and seven parses, then catalogs and real starter refusal:
exit 2 / BLOCKED, empty stderr, all 347 scoped hashes unchanged.
The root's strict readiness capture is under that folder's `strict-final/`;
the separate review capture is under `final-review/`. These are source and
starter-refusal checks, never App acceptance. The initial `final-entry/`
capture had invalid inventory array handling and module progress on stderr;
it is retained as failed capture evidence, not passing proof. A later harness
attempt stopped at an existing evidence directory before the checker ran.

No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification 323f76204d

Release remains **NO-GO**. The most valuable open item is the exact complete
package's actual App startup and portable first-run. Sixteen independent
areas found no safely executable local fix that closes it. Private Python,
reviewed input locks and the portable toolchain marker are absent; App
construction starts ISO discovery outside this permitted tree. No production
or test code changed. More scanner passes cannot establish App acceptance.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): test exit 0
  only for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr;
  four source hashes unchanged. The App never started. Evidence:
  `logs/launcher-323-1117b3ab150c4f70a77f86e15db60458/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1): both 23-tool
  catalogs and three root files passed. Actual
  [readiness tests](tools/test_online_readiness.ps1): three checker subprocess
  cases passed; normal readiness stayed 2 / BLOCKED. Empty stderr; ten source
  hashes unchanged. Evidence:
  `logs/tests-catalogs-323-12d201ca23474456b6ba79b2d321bcf2/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `323f76204d`:
  clean 165-second build `943fc4631acf2c13`, finished `2026-11-02T08:45:55`.
  OFF selftest: 202 good restores, zero bad, 447 comparisons with zero
  mismatches, all 101 wrong-input passes diverged. OFF same-PC pair: 6000
  frames and 199 hashes each, zero mismatches/NETDESYNC, 43.6/43.6 FPS,
  stalls 209/0 (4757/0 ms), displayed-frame p99 129.8/126.7 ms.
  Supplied, not reproduced here. Run-average FPS fell from the preceding
  supplied 52.3/52.3 and p99 rose; the summaries do not establish why or
  identify a code regression. Clean sampled hashes do not prove usable pacing.
  Actual readiness checked both documents / 18 links: exit 2 / BLOCKED,
  empty stderr, eight source hashes unchanged. Originals and strict evidence:
  `logs/supplied-323-52c281bb665845b28aac5ddbd033b0c7/strict-rerun/`.
  The parent's initial capture failed exit forwarding and is explicitly invalid.
- Independent portable, Python/Tk, settings/process, controller, offline flow,
  licence, privacy, payload, corresponding-source, effective-profile, two-PC,
  scanner-gap and shared-launcher reviews found no justified executable fix.
  Existing [owner acceptance](docs/RELEASE_PATH_B.md) already requires the
  responsive actual App, process identity, close/reopen, retained settings,
  licence cancel/accept and build/play/return. Launcher pad navigation remains
  unimplemented; in-game controller testing cannot establish it. Old incomplete
  ZIP member-name inspection proves neither content safety nor App acceptance.

Open: actual App/portable acceptance, complete source/player content and
privacy/licence review, Python suites, enabled GUI Host/Join profile and two
physical PCs. Fullscreen inheritance and offline spawn-failure log cleanup
remain source observations, not reproduced fixes. Scanner limits remain failed
termination, interruption within one write and unobserved descendants. Retained
fixture findings and incomplete archives remain failures. Unchanged long
aggregates and the whole-tree beta checker were not rerun.

Owner-only next step: supply the exact reviewed complete candidate, ZIP hash,
matching corresponding source and reviewed locks/notices; run its actual
`Tekken4.cmd` in the authorized validation environment. Observe a responsive
App and normal exit/reopen/settings, then prove portable first-run and
build/play/return. Supplying only Python is insufficient. Exact build/game,
shared-launcher integration, enabled GUI profile, sound-on usable pacing and
two physical PCs still need real proof. GUI, Python suites, packagers, build,
game and network helpers stayed **UNRUN here**.

Sixteen area agents: `launcher_entry_323`, `tests_catalogs_323`,
`portable_candidate_323`, `python_tk_runtime_323`, `settings_core_323`,
`ui_controller_323`, `offline_play_return_323`, `licence_inputs_323`,
`source_privacy_323`, `player_payload_323`, `corresponding_source_323`,
`effective_profile_323`, `supplied_verify_323`, `two_pc_acceptance_323`,
`scanner_entry_gaps_323`, `integrated_launcher_323`.
Separate final reviewer: `final_diff_review_323`. File ownership was exclusive.
Root owns this record and `docs/status.md`; root originals/hashes and the
347-file scoped source inventory are in
`logs/release-323-1a77d0ef1c9749fd9f4fed11045049ad/`.
Root's actual readiness entry checked all four changed documents / 173 local
links, 12 required source files and seven PowerShell parses, then catalogs
and real starter refusal: exit 2 / BLOCKED, empty stderr, all 347 scoped
source hashes unchanged. Evidence: `final-entry/result.json` and `stdout.txt`
in the root session folder above. Two preliminary root captures failed
argument parsing or inventory serialization; both are retained as invalid.
They are not passing proof. The final capture validates only source/refusal
behavior and supplies no App acceptance.

Separate reviewer `final_diff_review_323` found no blocking issue in the four
changed documents. All four saved-original hashes matched; historical tails
were preserved exactly. Independent enumeration found 347 unchanged source
names and only expected progress/status edits since the post-evidence snapshot.
Its actual readiness entry checked four documents / 173 links, 12 required
files and seven parses, then catalogs and real starter refusal: exit 2 /
BLOCKED, empty stderr, all 347 source hashes unchanged. Evidence:
`logs/final-review-323-621c3e9befef4ef5adc81088dfe81f10/`.

No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification c3dc860555

Release remains **NO-GO**. The most valuable open item is actual App startup
and portable first-run through the exact complete package. This copy lacks
private Python, reviewed input locks and the portable toolchain marker.
App construction starts ISO discovery outside this tree. No production or
test code changed; another source-only pass cannot close that gate.

Done:

- Actual [starter-refusal entry](tools/test_launcher_entry.ps1): test exit 0
  solely for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr;
  four checked source hashes unchanged. The App never started. Evidence:
  `logs/launcher-c3-670dd393fdce489eb15fd18967fdacfb/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) passed both
  23-tool catalogs and three root files. Actual
  [readiness tests](tools/test_online_readiness.ps1) passed three checker
  subprocess cases; normal readiness remains 2 / BLOCKED. Empty stderr;
  ten checked hashes unchanged. Evidence:
  `logs/tests-catalogs-c3-bbbc34b8c70e4165b75714c0646458db/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `c3dc860555`:
  clean 208-second build `943fc4631acf2c13`, finished `2026-11-02T08:32:52`;
  OFF selftest 202 good restores, zero bad, 447 resim comparisons with zero
  mismatches, all 101 wrong-input passes diverged. OFF same-PC pair: 6000
  frames, 199 hashes each, zero mismatches/NETDESYNC, 52.3/52.3 FPS,
  stalls 0/84 (0/2556 ms), displayed-frame p99 107.9/97.7 ms.
  Supplied, not reproduced here; no App, enabled GUI-profile or two-PC proof.
  Actual readiness checked both documents / 18 links: exit 2 / BLOCKED,
  empty stderr, eight checked hashes unchanged. Evidence:
  `logs/verify-c3-4412e954cbfe4e0f8e9f92a661333bf9/strict-rerun/`.
  The initial capture used one absent hash-list filename; it is retained as
  a preliminary capture, superseded by the strict rerun.
- Independent portable, privacy/source, licence, effective-profile and entry
  coverage reviews found no justified executable local fix. The three old
  ZIPs lack the actual App/private Python; member-name inspection alone
  proves no content safety. The existing [owner checklist](docs/RELEASE_PATH_B.md)
  already requires responsive App, process identity, normal exit/reopen,
  settings retention, licence cancel/accept and build/play/return.

Open: complete source/player content and privacy/licence review, Python
suites, actual App/portable acceptance, enabled GUI Host/Join profile and two
physical PCs. Scanner limits remain failed termination, interruption within
one write and unobserved descendants. Retained fixture findings and incomplete
archives remain failures. Unchanged aggregates and whole-tree beta checks
were not rerun. No GUI, Python suite, packager, build, game or network helper ran.

Owner-only next step: supply the exact reviewed complete candidate, ZIP hash,
matching corresponding source and reviewed input locks/notices, then run its
actual `Tekken4.cmd` using the checklist in the authorized validation
environment. Supplying only Python cannot establish portable acceptance.
Then prove integrated launcher, exact build/game, selected GUI profile and
sound-on play on two physical PCs.

Eight area agents: `launcher_entry_c3`, `portable_candidate_c3`,
`tests_catalogs_c3`, `supplied_verify_c3`, `source_privacy_c3`,
`licence_inputs_c3`, `effective_profile_c3`, `entry_gap_c3`.
Separate final reviewer: `final_diff_review_c3`. File ownership was exclusive.
Root's actual readiness entry checked all four changed documents / 167 local
links, 12 required files and seven PowerShell parses, then catalogs and real
starter refusal: exit 2 / BLOCKED, empty stderr, eight source hashes unchanged.
Evidence: `entry-result.json` and `entry-stdout.txt` in the root folder below.
Root owns this record and `docs/status.md`; saved originals/source inventory
and final review evidence are under
`logs/release-c3-a6feda85fa234984ab36984c68be6e41/`.
No Git command, deletion, outside-tree read, build, game, forbidden helper,
server, push or release ran here.

## Release gate and supplied verification 5b921f859f, current session

Release remains **NO-GO**. The most valuable open item is the exact complete
package's actual App startup and portable first-run. It cannot run in this
copy: private Python, reviewed input lock and portable toolchain marker are
absent. App construction also starts ISO discovery outside this tree. Only
the owner can supply the reviewed complete candidate and run it in the
authorized validation environment. No production or test code changed.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): test exit 0
  solely for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr;
  five source hashes unchanged. The App never started. Evidence:
  `logs/launcher-gate-5b9-6519dc44494a4d01a9317e66d1a8cf17/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1) passed both
  23-tool catalogs and three root files. Actual
  [readiness tests](tools/test_online_readiness.ps1) passed three checker
  subprocess cases; normal readiness stayed 2 / BLOCKED. Empty stderr;
  ten source hashes unchanged. Evidence:
  `logs/release-tests-catalogs-5b9-d77163f5d5604b94b26529918d13acbf/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `5b921f859f`:
  clean 165-second build `943fc4631acf2c13`, finished `2026-11-02T08:17:22`;
  OFF selftest 202 good restores, zero bad, 447 resim comparisons with zero
  mismatches, all 101 wrong-input passes diverged. OFF same-PC pair: 6,000
  frames, 199 hashes each, zero mismatches/NETDESYNC, 52.0/52.0 FPS,
  stalls 0/69 (0/2195 ms), displayed-frame p99 105.5/99.7 ms. Supplied,
  not reproduced here; no complete-package, enabled GUI-profile or two-PC proof.
  Actual readiness checked these two documents / 18 links, then catalogs and
  starter refusal: exit 2 / BLOCKED, empty stderr, eight source hashes unchanged.
  Originals and evidence:
  `logs/latest-verify-5b9-f55af6dabd5b46038b905f6f005b15fd/`.
- Independent portable, source/privacy, licence, effective-profile and remaining
  scanner-gap reviews found no justified executable local fix. The existing
  [owner checklist](docs/RELEASE_PATH_B.md) already requires the actual
  responsive App, normal exit/reopen, retained settings, licence cancel/accept
  and build/play/return. No duplicate scanner suite or mock App proof was added.

Open: complete source/player/privacy/licence review, Python suites, actual
App/portable acceptance and scanner limitations (failed termination,
interruption within one write and unobserved descendants). Retained fixture
findings and incomplete archives remain failures. Long unchanged aggregates
and the whole-tree beta checker were not rerun.

Owner-only next step: provide the exact reviewed complete candidate, zip hash,
matching corresponding source and input locks/notices; run its actual
`Tekken4.cmd` using the checklist. Then prove the integrated launcher, exact
build/game, enabled GUI Host/Join profile and two physical PCs. Supplying only
Python cannot close portable acceptance. No GUI, Python suite, build, game,
network helper or packager ran here.

Eight area agents: `launcher_gate`, `portable_candidate`, `tests_catalogs`,
`latest_verify`, `source_privacy_scope`, `licence_inputs`, `effective_profile`,
`remaining_entry_gaps`. Separate final reviewer: `final_diff_review_5b9`.
File ownership was exclusive. Root owns this record and `docs/status.md`;
original root bytes/hashes and the 347-file scoped source inventory are in
`logs/release-gate-5b9-3f9a7532b2ee4fdfad597eb7b3bd4d3a/`.
Root's actual readiness entry checked all four changed documents / 161 local
links, 12 required files and seven PowerShell parses, then catalogs and actual
starter refusal. Exit 2 / BLOCKED, empty stderr, eight source hashes unchanged.
Evidence: `entry-result.json` and `entry-stdout.txt` in the root folder above.
Separate reviewer `final_diff_review_5b9` found no blocking issue in the four
document changes. All four saved-original hashes matched; the 347-file scoped
inventory had unchanged names and only the expected root progress/status edits
since the post-evidence snapshot. Historical progress/status tails were
preserved. Its independent actual readiness entry checked four documents /
161 local links, 12 required files and seven parses, then catalogs and actual
starter refusal: exit 2 / BLOCKED, empty stderr, all 347 source hashes unchanged.
Evidence: `logs/final-review-5b9-8fd7d67d4e2748419b86dc50cb1a078e/`.

A preliminary launcher capture did not record its exit code; it is retained
as a failed capture, not passing proof. The evidence agent's preliminary
encoded invocation had module-preparation progress on stderr; its direct-file
rerun above had empty stderr. No Git command, deletion, build, game, forbidden
helper, outside-tree read, server, push or release ran here.


## Launcher gate recheck and supplied verification 363433d330, current session

Release remains **NO-GO**. The most valuable open item is still the exact
complete package's actual App startup and portable first-run. The real
starter refused missing private Python again; the GUI never started. This
copy cannot close that item: reviewed portable inputs are absent, and App
startup searches outside the permitted tree. No production or test code
changed. No new passing scanner test is presented as launcher evidence.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1): exit 0 only
  for real `Tekken4.cmd` exit 1, missing private Python. Empty stderr; five
  source hashes unchanged. Evidence:
  `logs/launcher-gate-proof-7c125f2836554db7a47a8778ba21e8aa/`.
- Actual [catalog checker](tools/check_online_catalogs.ps1): both 23-tool
  catalogs and three root files passed. Actual
  [readiness tests](tools/test_online_readiness.ps1): three checker subprocess
  cases passed; normal readiness remains 2 / BLOCKED. Empty stderr; ten
  source hashes unchanged. Evidence:
  `logs/release-tests-catalogs-current-33deffc4557549d2a03bd33f2ff99225/`.
- Actual readiness link-boundary entries: clean local link returned
  2 / BLOCKED after catalog/starter entries; missing and outside-tree local
  links returned 1 before child entries. All three stderr streams were empty;
  eight source hashes stayed unchanged. No source defect was found. Evidence:
  `logs/readiness-link-boundary-8432ef7523cb4dcd85fd3cee37c6fc6f/direct-file/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `363433d330`:
  clean 165-second build `943fc4631acf2c13`, finished `2026-11-02T08:02:46`;
  OFF selftest 232 good restores, zero bad, 514 comparisons with zero
  mismatches, all 116 wrong-input passes diverged. OFF same-PC pair: 6,000
  frames, 199 hashes each, zero mismatches/NETDESYNC, 52.1/52.2 FPS,
  stalls 0/79 (0/2843 ms), displayed-frame p99 119.6/100.0 ms. Supplied,
  not reproduced here; no exact package, enabled GUI profile or two-PC proof.
  Actual readiness checked these two documents / 18 links, then catalogs and
  starter refusal: exit 2 / BLOCKED, empty stderr, edited hashes unchanged.
  Originals and evidence:
  `logs/latest-verify-363-4636b2c90ce548b0b8285383050a4cc7/`.
- Independent tree/ZIP reviews found no justified new watchdog test. Actual
  deadlines and worker death already have entry coverage. The outer watchdog
  belongs to the test harness; forcing it would not prove launcher startup.
  Failed termination, interruption inside one write and unobserved descendants
  remain unproved. No duplicate suite or production instrumentation was added.

Open: actual App/portable acceptance, complete source/player/privacy/licence
review, Python suites and the scanner gaps above. Long unchanged aggregates
and the whole-tree beta checker were not rerun. Retained fixture findings and
incomplete archives remain failures.

Root's actual readiness entry checked all four changed documents / 155 local
links, 12 required source files and seven PowerShell parses, then ran catalogs
and actual starter refusal. Exit 2 / BLOCKED, empty stderr, eight checked
hashes unchanged. Evidence: the root session's `entry-result.json` and
`entry-stdout.txt` below. This verifies document links and source/refusal
checks only; it supplies no App acceptance.

Only the owner can supply the exact reviewed complete candidate and run its
actual `Tekken4.cmd` in the authorized validation environment: observe a
responsive App, normal close/reopen and retained settings, then licence
cancel/accept and portable build/play/return. Exact build/game, integrated
launcher, enabled GUI Host/Join profile and two physical PCs still need proof.
No GUI, Python suite, build, game or network helper ran here.

Eight area agents: `tree_watchdog_entry`, `zip_watchdog_entry`,
`launcher_gate_proof`, `portable_candidate_scope`, `tests_catalogs_current`,
`latest_verify_evidence`, `readiness_boundary_entry`, `licence_source_release`.
Separate final reviewer: `final_diff_review_363` found no blocker in the four
document changes. All four saved original hashes matched. The scoped 348-file
inventory had unchanged names and only the two expected root-owned documents
differed from the post-evidence snapshot; the historical progress tail was
unchanged. Its independent actual readiness entry checked four documents /
155 links, 12 required files and seven parses, then catalogs and starter
refusal: exit 2 / BLOCKED, empty stderr, all 348 source hashes unchanged.
Evidence: `logs/final-review-363-2651acf06a3340ac9c30b31a4d4ed047/`.
File ownership was exclusive. Root owns this record and `docs/status.md`;
originals and the 348-file source snapshot are in
`logs/release-gate-363-b189dd9bc7fd47199c206e64178f991b/`.
No Git command, deletion, build, game, forbidden helper, server, push or
release ran here.

## Earlier concrete launcher acceptance handoff

Release remains **NO-GO**. Actual complete-package App startup and portable
first-run are still the most valuable open item. This copy lacks private
Python and reviewed portable inputs. App startup also discovers ISO files
outside this copy, so it must run in the owner's authorized validation
environment. No production or test code was changed without execution proof.

Done:

- Made the existing [clean-PC checklist](docs/RELEASE_PATH_B.md) explicit:
  identify the exact candidate, observe a visible responsive App through its
  actual `Tekken4.cmd`, identify its process, close normally and reopen, then
  verify settings retention. Licence cancel/accept and offline play/return
  have separate observations. Standalone and integrated-launcher results
  remain separate. This procedure is **UNRUN**, not a new passing test.
- Actual [starter-refusal test](tools/test_launcher_entry.ps1) exited 0
  solely for real `Tekken4.cmd` exit 1, missing private Python. Stderr was
  empty and three checked source hashes stayed unchanged. GUI never started.
  Evidence: `logs/launcher-entry-release-a2614f1b6d6e44d497eb42a5eadc8267/`.
- Actual [catalog check](tools/check_online_catalogs.ps1) passed both
  23-tool catalogs and three source root files. Actual
  [readiness tests](tools/test_online_readiness.ps1) passed three checker
  subprocess cases; normal readiness remained 2 / BLOCKED. Both stderr
  streams were empty and ten checked source hashes stayed unchanged.
  Evidence: `logs/release-tests-catalogs-11ee7aed570149988e5186e5f40714b9/`.
- Actual [readiness entry](tools/check_online_readiness.ps1) checked all five
  changed documents / 156 local links, 12 required files and seven PowerShell
  parses, then ran catalogs and actual starter refusal. Exit 2 / BLOCKED,
  empty stderr and nine checked source hashes unchanged. Evidence:
  `logs/release-owner-handoff-1e2248f447684977a0ad69e52b2bdc6a/document-entry-encoded/`.
  Two earlier root capture invocations mishandled PowerShell exit forwarding
  or quoting; they remain preliminary failures. No source fix was needed.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `a3a7ec6862`:
  clean 165-second build `943fc4631acf2c13`, finished `2026-11-02T07:45:38`;
  OFF selftest 202 good restores, zero bad, 447 comparisons with zero
  mismatches and all 101 wrong-input passes diverged. OFF same-PC pair:
  6,000 frames, 199 hashes each, zero mismatches/NETDESYNC, 52.1/52.2 FPS,
  stalls 0/94 (0/3439 ms), displayed-frame p99 118.8/99.0 ms. Supplied,
  not reproduced here; no exact package, GUI profile or two-PC proof.

Open: complete source/player content, privacy and licence review, Python
suites and existing scanner coverage gaps. Retained fixture findings and
incomplete archives remain failures. Unchanged tree/ZIP aggregates and the
whole-tree beta checker were not rerun; they cannot close App acceptance.
Separate reviewer `final_diff_review_handoff` found no blocker in the five
document changes. Its actual readiness entry checked five documents / 157
links, 12 required files and seven parses, then catalogs and starter refusal:
exit 2 / BLOCKED, empty stderr, all 235 checked hashes unchanged. All five
saved originals matched their recorded hashes; the scoped 347-file inventory
had unchanged names and only the three expected root documents differed
from the post-evidence snapshot. Evidence:
`logs/final-diff-review-handoff-42ce352ed3b74de3aa418a6e3e3004a2/`.

Only the owner can supply the exact reviewed complete candidate and run the
expanded App/portable checklist, the exact build/game, integrated launcher,
enabled GUI Host/Join profile and two physical PCs. A detached starter exit,
launcher `--selftest`, small Tk probe or mocked core suite proves no App.
No GUI, Python suite, build, game or network helper ran here.

Eight area agents: `launcher_entry_proof`, `portable_first_run`,
`tests_and_catalogs`, `latest_verify_evidence`, `effective_switch_profile`,
`release_licence_inputs`, `launcher_coverage_gap`, `candidate_scope_handoff`.
Separate final reviewer: `final_diff_review_handoff`. File ownership
was exclusive. Root owns this record, `docs/status.md` and the checklist.
Original root bytes/hashes: `logs/release-owner-handoff-1e2248f447684977a0ad69e52b2bdc6a/`;
evidence-doc originals: `logs/latest-verify-a3a-c3479aae1433405591c60d292e7eb060/`.
No Git command, deletion, build, game, forbidden helper, server, push or
release ran here.

## Earlier launcher acceptance gate and evidence completion

Release remains **NO-GO**. The most valuable open item is the exact complete
package's actual launcher App and portable first-run. This copy cannot prove
it: private Python and reviewed portable inputs are absent. No production or
test code was changed without execution proof. More scanner tests cannot
close the launcher gate.

Done:

- Actual [starter-refusal test](tools/test_launcher_entry.ps1) passed only
  for real `Tekken4.cmd` exit 1, missing private Python. Stderr was empty
  and five checked source hashes stayed unchanged. GUI never started.
  Evidence: `logs/launcher-gate-current-8d2e9892a2d349cbb61eeda181a639f3/`.
- Actual [readiness tests](tools/test_online_readiness.ps1) passed three
  subprocess cases. Direct readiness returned 2 / BLOCKED after checking
  12 required files, seven PowerShell parses, seven documents / 109 local
  links, catalogs and actual starter refusal. Both stderr streams were empty
  and eight source hashes stayed unchanged. Evidence:
  `logs/readiness-current-c75cb47c62a24ad8bd1733163057aa6b/`.
- Recovered the previous completed ZIP aggregate result, rather than treating
  the stale pending line below as unfinished execution: exit 0 in 523.412
  seconds, empty stderr, 27 sources parsed and 18 suites plus catalog.
  Its 155-assertion worker-interruption suite ran four actual scanner entries.
  All 226 tool/patch names and hashes matched before, between and after both
  aggregates, and still match the current source inventory. Evidence:
  `logs/tests-catalogs-current-e92bd13ca4964eccb139c870b240c4b7/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `59c7379771`:
  clean 218-second build `943fc4631acf2c13`, finished `2026-11-02T07:25:58`;
  OFF selftest 202 good restores, zero bad, 447 comparisons with zero
  mismatches and all 101 wrong-input passes diverged. OFF same-PC pair:
  6,000 frames, 199 hashes each, zero mismatches/NETDESYNC, 52.2/52.2 FPS,
  stalls 0/82 (0/2530 ms), displayed-frame p99 105.8/100.1 ms. This was not
  reproduced here and does not prove this edited tree, GUI profile or two PCs.

Open: complete source/player content, privacy and licence review and Python
suites remain unproved. Retained fixture findings and incomplete archives
remain failures. The prior scanner termination/watchdog/write/descendant
coverage gaps remain open; none substitutes for launcher acceptance.

Only the owner or authorized validation checkout can close the main gate:
start the exact complete package with its actual `Tekken4.cmd`, verify the
launcher App is visible and responsive, close normally and start again. Then
prove portable first-run, licence reject/accept, build/play/return and settings
retention. A starter exit alone is insufficient because it starts Python
asynchronously. Source inspection confirms `--selftest` returns before App
construction, the packager checks a small Tk window, and the Python launcher
suite mocks core processes. None proves App startup. Actual App startup also
starts automatic ISO discovery outside this copy, so it belongs in the
authorized validation environment. No personal folders were read here.

Exact build/game, enabled GUI Host/Join switches and two physical PCs still
need owner proof. No GUI, Python suite, build, game or network helper ran here.

Eight area agents: `launcher_gate_current`, `portable_acceptance_audit`,
`tests_catalogs_current`, `latest_verify_docs_current`,
`readiness_contract_current`, `prior_evidence_completion`,
`release_source_scope`, `launcher_test_coverage`. Separate reviewer:
`final_diff_review_acceptance`. File ownership was exclusive. Root owns this
record and `docs/status.md`. Original root bytes/hashes are saved without Git
in `logs/release-acceptance-session-02c0630993c84014a37023f39931f23f/`;
evidence-document originals are in
`logs/latest-verify-docs-59c-current-2308918758294eb589b10bf291074adf/`.
No Git command, deletion, build, game, forbidden helper, server, push or
release ran here.

## Earlier unexpected worker-exit follow-up

Release remains **NO-GO**. The most valuable release gate is still the exact
complete package's actual launcher App and portable first-run. Private Python
is absent here; the real starter refused it again and the GUI never started.
This session exercises the open unexpected-worker-exit path through the real
source scanner entries. No production scanner or launcher behavior changed.

Done:

- Added [tree worker-interruption tests](tools/test_public_tree_worker_interrupt.ps1).
  The frozen actual test passed 195 assertions through six real export/scan
  entries. Parent PID and UTC creation time identify the actual worker before
  a guarded kill; a no-op kill cannot count. Both interrupted entries naturally
  returned exit 1 with the static refusal, no completion claim and empty stderr.
  Scan/export controls passed before and after against the unchanged 101-file
  source. Five source/helper/test hashes stayed unchanged after every entry;
  two independent post-exit samples found observed supervisor/worker identities
  absent. Evidence: `logs/tree-worker-interrupt-54f5d74ed0df4504a7c567dc442f7412/`.
- Added [ZIP worker-interruption tests](tools/test_public_zip_worker_interrupt.ps1).
  The frozen actual test passed 155 assertions through four real scanner
  entries. Two independently identified workers were killed after observing
  the unchanged input ZIP's read lock. Both supervisors naturally refused with
  exit 1, empty stderr and no completion/partial/deadline claims. The same
  1,000-member harmless-text ZIP passed before and after; seven source/test
  hashes and fixture bytes/inventory stayed unchanged before, between and
  after entries. Three independent post-exit identity checks found each observed
  worker absent. Nothing was extracted. Evidence:
  `logs/zip-worker-interrupt-797170ff90d0448fbab8e1f7e71403ef/`.
- Registered both tests in their actual aggregate parse and execution lists.
  Actual tree aggregate exited 0 in 422.619 seconds with empty stderr:
  22 PowerShell sources parsed, 14 suites, including the new 189-assertion /
  six-entry rerun. All 226 recursive tool/patch names and hashes stayed
  unchanged. ZIP aggregate verification is still running serially.
  Evidence: `logs/tests-catalogs-current-e92bd13ca4964eccb139c870b240c4b7/`.
- Separate reviewer `final_diff_review` independently passed the actual new
  tree test (189 assertions / six entries), ZIP test (155 / four) and both
  23-tool catalogs, with three root files present. Stderr was empty and all
  230 checked source names/hashes stayed unchanged. Counts vary with process
  observations. Saved-original comparison found only the intended aggregate,
  progress and evidence-document edits; no code blocker was found. Final
  document review/checker is pending. Evidence:
  `logs/final-worker-interrupt-review-744452d7018a47f2a92387d7492850e2/`.
- Actual starter-refusal test passed only for real `Tekken4.cmd` exit 1,
  missing private Python. Stderr was empty and five source hashes stayed
  unchanged. Evidence: `logs/launcher-gate-current-b4862f8a14be4b6e9fdc1294d44b3f1f/`.
  Actual readiness tests passed three subprocess cases; direct readiness
  returned 2 / BLOCKED. Both stderr streams were empty and eight checked
  source hashes stayed unchanged. Evidence:
  `logs/readiness-current-ec63cd2ecc3f4a34818c8e1f04d6cfd6/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with supplied draft `47167233c6`:
  clean 168-second build `943fc4631acf2c13`, finished `2026-11-02T06:56:13`;
  OFF selftest 202 good restores, zero bad, 447 comparisons with zero
  mismatches and all 101 wrong-input passes diverged. OFF same-PC pair:
  6,000 frames, 199 hashes each, zero mismatches/NETDESYNC, 52.1/52.2 FPS,
  stalls 0/79 (0/2886 ms), displayed-frame p99 114.1/101.1 ms. This was not
  reproduced here and does not prove this edited tree, GUI profile or two PCs.

Open: failed termination and outer test-watchdog branches, interruption
inside a single write and unobserved descendants remain unproved. Tree
coverage proves premature worker death, not progress inside a write; ZIP
coverage additionally observes the input lock. Retained fixtures and incomplete
archives still fail whole-tree inspection. Complete source/player content,
privacy and licence review and Python suites remain open. No scanner test
establishes those approvals or actual launcher startup.

Only the owner or authorized validation checkout can prove the complete
private-Python/Tk App, portable first-run, exact build/game, enabled GUI switches
and two physical PCs. No GUI, build, game or network helper ran in this copy.

Eight area agents: `launcher_gate`, `tree_watchdog`, `zip_watchdog`,
`process_gap_audit`, `tests_catalogs`, `latest_verify_docs`,
`readiness_contract`, `release_priority`. Separate reviewer: `final_diff_review`.
File ownership was exclusive. Root owns this record, `docs/status.md` and
aggregate registration. Original bytes/hashes are saved without Git in
`logs/release-worker-interrupt-c351a09c1e5443558bb9545d708a3b9e/`;
evidence-doc originals are in
`logs/latest-verify-current-73a1c1ca6415486cbaa3cd15f9e080cc/`.
No Git command, deletion, build, game, forbidden helper, server, push or release
ran here.

## Earlier complete source-check inventory follow-up

Release remains **NO-GO**. The real complete-package launcher GUI and
portable first-run remain the main release gate. The actual starter again
refused missing private Python; the GUI never started. Builds, games and
network helpers remain forbidden here.

Done:

- Fixed [the source checker](tools/check_beta_source.ps1): a corrupt ZIP no
  longer aborts inspection of later files and archives. Open/read/dispose
  failures retain exit 1, use a static numbered finding and count incomplete
  archives separately. The final inventory and UNRUN/NO-GO statements now
  appear after these failures. No logs, fixtures or findings are excluded.
- Added [real-entry regressions](tools/test_beta_source_entry.ps1). The same
  test bytes first failed 12 of 26 assertions through two actual in-place
  checker subprocesses, then passed 34 assertions through two subprocesses.
  Both fixed checker runs retained exit 1 and empty stderr, inspected the
  later unsafe-member ZIP and reached the final inventory. Fixtures and both
  test/helper hashes stayed unchanged. No checker copy or archive extraction
  was used. Red evidence:
  `logs/beta-source-entry-dba210d7d70d456cb2acf4e2fa2c96b1/`;
  frozen green:
  `logs/beta-source-entry-2a8bffe055f547b9b82eedb6deb72f5a/`.
  The first green run inventoried 72,591 files, attempted 3,280 archives and
  counted 253,496 members; 70 incomplete archives and 158 findings kept it
  failed. These retained fixtures are not a reviewed public source output.
- Actual launcher entry test passed only for real `Tekken4.cmd` exit 1,
  missing private Python. Actual readiness exited 2 / BLOCKED; stderr was
  empty and seven source hashes stayed unchanged. Evidence:
  `logs/launcher-entry-gate-3e7ee85f64cd4922b8b0a23d092bc447/`.
- Actual readiness contract suite passed its three subprocess cases, empty
  stderr and eight unchanged source hashes. Both actual 23-tool catalogs
  passed with three root files present and unchanged checked source hashes.
  Evidence: `logs/readiness-contract-audit-fe0417101c8045f9ad9c5fd528b17c58/`
  and `logs/tests-catalogs-audit-b505634e2d744bd18cb483af988d1f6a/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) and the
  [decision sheet](docs/BETA_GO_NO_GO.md) with the supplied `caf985c7fd`
  verification: clean 167-second build `943fc4631acf2c13`, finished
  `2026-11-02T06:39:31`; OFF selftest 232 good restores, 514 comparisons,
  zero mismatches and 116 wrong-input divergences. Same-PC OFF pair: 6,000
  frames, 199 hashes each, zero mismatches/NETDESYNC, 52.1/52.1 FPS,
  stalls 0/79 (0/2368 ms), displayed-frame p99 103.0/100.4 ms. This was
  not reproduced here and does not prove this edited tree or GUI profile.
- Tree interruption and ZIP branch agents found no demonstrated production
  defect warranting another patch. Independent tree write-failure checks
  passed 85 assertions / eight real entries, empty stderr and unchanged
  checked source hashes; fixture ACLs were restored. ZIP path-alias probes
  ran eight actual entries but demonstrated no device-name bypass.

- Separate reviewer `final_diff_review_source_completion` found no blocker
  and independently passed the actual new regression (34 assertions / two
  in-place entries) and both catalogs (23 tools each, three root files).
  Its actual checker covered all four changed documents: 129 local links
  and 307 PowerShell parses, no document/link/syntax findings. The final
  inventory covered 72,616 files, 3,283 archive attempts and 253,498 members;
  71 incomplete archives and 160 retained findings kept exit 1. All stderr
  was empty and six changed-source hashes stayed unchanged during entries.
  Saved-byte comparison verified the intended edits and preserved history.
  Evidence:
  `logs/final-diff-review-source-completion-edf20994efe246edb2a3c1d5b51df2d7/`.
  Existing tree/ZIP aggregate suites were not rerun; their production
  scanners did not change.

Open: retained fixture findings and incomplete archives remain failures;
filename inspection is not content/privacy/licence approval. Python suites,
complete public source/player review, termination-error/watchdog branches,
interruption inside a single write and unobserved descendants remain open.
Only the owner or authorized validation checkout can prove the complete
private-Python/Tk App startup, portable first-run, exact build/game, enabled
GUI switches and two physical PCs. No build, game or GUI ran in this copy.

Eight area agents: `launcher_entry_gate`, `release_priority_audit`,
`tree_interruption_audit`, `zip_open_branch_audit`, `tests_catalogs_audit`,
`latest_verify_docs`, `source_checker_regressions`, `readiness_contract_audit`.
Separate final reviewer: `final_diff_review_source_completion`.
File ownership was exclusive. Root owns this record, `docs/status.md` and
`tools/check_beta_source.ps1`; baseline bytes/hashes are saved without Git in
`logs/release-source-completion-0e1380f430604d95b08db6469d06cd2b/`.
The evidence-doc originals are in
`logs/latest-verify-docs-53a7c736cec64335af1127d5cd8ffafa/`.
No Git command, build, game, network helper, server, push or release ran here.

## Earlier scanner process lifecycle follow-up

Release remains **NO-GO**. The exact complete package's real launcher GUI
and portable first-run remain the main gate. The actual starter again
refused missing private Python; the GUI never started. Builds, games and
network helpers remain forbidden here.

Done:

- Added [tree lifecycle tests](tools/test_public_tree_process_lifecycle.ps1).
  The frozen actual entry passed 550 assertions through eight real export/scan
  entries. The unchanged 1,001-file tree passed complete scan/export controls
  before and after two two-second scan and two export deadline refusals.
  Windows process counters independently linked every worker by parent PID;
  PID and UTC creation time guard identity reuse. Two fresh post-exit samples
  found each observed worker/supervisor identity absent and no live direct
  PowerShell worker. Source bytes/inventory and five test/helper hashes stayed
  unchanged; exports matched exactly and stderr was empty. Evidence:
  `logs/tree-process-lifecycle-80865a36bdde4ff783f24526783a9398/`.
- Added [ZIP lifecycle tests](tools/test_public_zip_process_lifecycle.ps1).
  The frozen actual entry passed 77 assertions through four real scanners.
  The same unchanged 1,000-member text ZIP passed before and after two genuine
  one-second deadlines. Every worker was independently linked by parent PID,
  PID and UTC creation time, then absent on three post-return identity checks;
  supervisors also exited. Seven source hashes and fixture bytes/inventory
  stayed unchanged, stderr was empty and nothing was extracted. Evidence:
  `logs/zip-process-lifecycle-8c27a8cac0c84716bd12f5d23454a022/`.
- Windows `Process` counters work here despite the earlier CIM denial. Missing
  counters or an unobserved worker fail the tests. A supervisor message or
  released file handle alone never counts as independent absence evidence.
  No production launcher, scanner, runtime or switch behavior changed.
- Actual starter test exited 0 solely for real `Tekken4.cmd` exit 1, missing
  private Python. Actual readiness exited 2 / BLOCKED, with seven source
  hashes unchanged and empty stderr. GUI never started. Evidence:
  `logs/launcher-real-gate-79ffcad5b717494fb70f7d0d8953af3a/`.
- Actual readiness tests passed three real checker subprocesses, exit 0,
  empty stderr and eight unchanged source hashes. Evidence:
  `logs/readiness-contract-current-40c18fdebe4f4bd5955dcccb5db1e7d4/`.
- Actual retained LICENSE/patch export and scan exited 0 with empty stderr:
  80 files, 2,025,621 bytes, 79 unchanged diff byte ranges; 84 input/helper
  snapshots stayed unchanged before, between and after. This subset is not
  complete corresponding source or a player candidate. Evidence:
  `logs/retained-export-current-20261102-r1/`.
- Actual [tree aggregate](tools/check_public_publish.ps1) exited 0 in
  397.566 seconds with empty stderr: 21 PowerShell files parsed, 13 suites /
  11,377 checks and assertions. Its lifecycle rerun passed 546 / eight entries;
  interruption passed 4,480 / six, retaining 777/699 of 1,501 files. Both
  23-tool catalogs passed with three source root files present. All 144
  recursive tool files and 79 patch names/hashes stayed unchanged before
  catalogs, after catalogs and after tree checks.
  Actual [ZIP aggregate](tools/check_public_zip.ps1) then exited 0 in
  503.322 seconds with empty stderr: 26 files parsed, 17 suites / 3,596
  assertions, including the 77 / four-entry ZIP lifecycle rerun. All 144 tool
  files and 79 patch names/hashes still matched after both serial aggregates.
  Counts vary with process observations and retained partial files checked.
  Evidence: `logs/lifecycle-catalogs-8048b512c07948b1ad32bf4517e86bfc/`.
- Separate reviewer `final_diff_review_lifecycle` found no remaining code
  blocker. Its independent real entries passed tree lifecycle 544 / eight,
  ZIP 77 / four and both 23-tool catalogs with three source root files.
  Stderr was empty and all 229 tool/patch/launcher/starter/AGENTS names and
  hashes stayed unchanged. All six existing changed files match their saved
  original-byte baselines after reversing only the intended edits; both new
  tests were reviewed in full. Evidence:
  `logs/final-diff-review-lifecycle-20261102/`.
- The reviewer's actual document checker covered all four changed documents:
  129 local links, 304 PowerShell parses, no missing document/link or syntax
  findings and empty stderr. Overall exit 1 remains on 36 retained text-only
  image-name fixtures and a corrupt ZIP; whole-tree checking did not complete.
  Nothing was deleted or weakened to make that check pass.

Eight area agents: `tree_process_lifecycle`, `zip_process_lifecycle`,
`launcher_real_gate`, `readiness_contract`, `tests_catalogs_current`,
`release_scope_current`, `retained_export_current`, `release_priority_current`.
File ownership is exclusive. Root owns this record and `docs/status.md`;
original bytes and hashes are saved without Git under
`logs/release-lifecycle-session-b4ae9cc5b3944229aa9a03d956a4f49f/`.
Separate reviewer: `final_diff_review_lifecycle`.

Preliminary runs caught a console-host child classification error in the
tests; review also required sanitized failure diagnostics. Only final frozen
runs count as evidence.

Open in source: termination-error/watchdog branches, interruption
inside a single write and unobserved descendants remain unproved.
Retained fixtures and a corrupt ZIP still obstruct the old whole-tree check.
Complete source/player/privacy/licence review and Python suites remain open.
Only the owner or authorized validation
checkout can prove real private-Python/Tk App startup, portable first-run,
exact build/game, enabled GUI switches and two physical PCs. The latest
owner-supplied verification remains recorded in the preceding session below;
it has not been reproduced here.

No Git command, build, game, network helper, server, push or release ran here.

## Earlier Windows ZIP device-name follow-up

Release remains **NO-GO**. The main gate is still the exact complete
package's real launcher GUI and portable first-run. Private Python is absent
here; builds, games and network helpers remain forbidden. This session takes
the open COM/LPT superscript-digit ZIP path bypass through the actual scanner
entry. No launcher, runtime or switch behavior changed.

Done:

- Eight area agents read AGENTS.md and the current progress record. File
  ownership is exclusive. Original changed-file bytes and hashes are saved
  in local logs without Git; root originals are in
  `logs/release-device-session-20261102/`.
- The [ZIP validator](tools/public_zip_scan.ps1) now refuses COM/LPT names
  with superscript digits 1, 2 and 3. An independent real-entry audit found
  a second route: an unflagged name byte meant superscript 2 in CP437 but
  decoded differently on this host. Raw non-ASCII member-name bytes now
  require the UTF-8 flag before decoded-name checks. Ordinary unflagged ASCII
  and explicit UTF-8 names still pass. No archive is extracted or rewritten.
- Added [actual-entry regressions](tools/test_public_zip_device_names.ps1)
  to the [ZIP aggregate](tools/check_public_zip.ps1). The original red run
  failed 72 of 306 assertions through 28 actual scanners: all 24 superscript
  cases passed unexpectedly. The expanded red run failed nine of 393
  assertions through 35 scanners: all three ambiguous-name cases still
  passed after the decoded-name fix. Final frozen green passed 393 / 35
  with zero failures and empty stderr. Seven tool hashes and all fixture
  bytes/inventory stayed unchanged before, between and after; controls pass
  before and after, refusals conceal names/content, and nothing is extracted.
  Final evidence:
  `logs/public-zip-device-names-8d4a145f110e4557a966856473f7629e/`.
  Red evidence:
  `logs/public-zip-device-names-b081df3fa64f41a0862a1c20c3502bfb/` and
  `logs/public-zip-device-names-e478330e9ac0435a8ff1b360c7e1f151/`.
- Independent final audit passed 21 actual scanner entries: 15 Windows
  path cases and six encoding controls. Reserved names and ambiguous
  non-ASCII names refused; ordinary ASCII, UTF-8 and lookalike controls
  passed. Input/scanner hashes and fixture inventory stayed unchanged,
  with empty stderr. Evidence:
  `logs/zip-windows-path-audit-20261102/d57e8b81b3e149488fa62977be41bc53/` and
  `logs/zip-windows-path-audit-20261102/encoding-1d72911c3815461bb55b1749b98d320b/`.
- Actual starter test passed only by observing real `Tekken4.cmd` exit 1 for
  missing private Python. GUI never started. Actual readiness tests passed
  three checker subprocesses; direct readiness still exits 2 / BLOCKED.
  Seven source hashes stayed unchanged, with empty stderr. Evidence:
  `logs/launcher-gate-devices-7b77d162d543454387e0e605bb949c3d/`.
- Actual retained LICENSE/patch export and scan exited 0 with empty stderr
  in 5.906 / 3.178 seconds: 80 files, 2,025,621 bytes, all 79 patch diff
  ranges unchanged. All 84 selected input/helper snapshots stayed unchanged
  before, between and after. This subset is not complete corresponding source
  or a player candidate. Evidence:
  `logs/retained-export-devices-738c949154b14dac82825bd37bcc76f7/`.
- Frozen actual [ZIP aggregate](tools/check_public_zip.ps1) exited 0 with
  empty stderr in 498.323 seconds: 25 PowerShell files parsed, 16 suites /
  3,519 assertions, including the 393 / 35 device suite and 440 / 47 privacy
  suite. Both 23-tool catalogs passed, with three source root files present.
  All 142 recursive tool-file and 79 patch names/hashes stayed unchanged
  before catalogs, between catalogs/aggregate and after. Evidence:
  `logs/zip-device-catalogs-2e3de32ff52b4a02b21823c728e10b8f/`.
- Updated ZIP/export scope, the go/no-go sheet and supplied switch evidence.
  Ordinary legacy non-ASCII ZIP names now refuse unless marked UTF-8; this
  compatibility limit is explicit. These source checks do not validate
  Windows extraction or the complete source/player package.
- Separate reviewer `final_diff_review_devices` found no code blocker and
  independently passed the actual device suite (393 assertions / 35 entries)
  and catalogs, with empty stderr. All 227 tool/patch/launcher/starter/AGENTS
  file names and hashes stayed unchanged. Eight saved originals matched
  their pre-edit hashes; the scanner and aggregate reconstruct exactly after
  reversing the intended edits. Evidence:
  `logs/release-device-review-20261102/`.
- The reviewer's actual document checker covered all six changed documents:
  161 local links and 297 PowerShell parses, with no missing document/link
  or syntax findings and empty stderr. Overall exit 1 remains on retained
  text-only image-name fixtures and a corrupt ZIP; whole-tree checking did
  not complete. Nothing was deleted or weakened for a pass.

Open in source: existing unforced interruption/termination/watchdog branches
and independent process absence remain unproved. Retained fixtures and the
corrupt ZIP still obstruct the old whole-tree checker. The full tree
aggregate was not rerun; the shared tree helper did not change, and the
actual retained export/scan above ran. Passing these limited scans does not
prove every privacy, provenance or Windows path issue was found.

Latest owner-supplied verification, not reproduced here: draft `38a164ddec`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`;
clean merge, 168-second build `943fc4631acf2c13`, finished
`2026-11-02T05:44:41`. Selftest OFF: 5400 wall / 4650 logical frames,
170 good restores, zero bad, 375 comparisons with zero mismatches and all
85 wrong-input passes diverged. OFF same-PC pair: 6000 frames, 199 hashes
each, zero mismatches/NETDESYNC, 52.1/52.2 FPS, stalls 0/68 (0/2385 ms),
displayed-frame p99 111.5/99.7 ms, restore-and-resim maximum 167.00/55.53 ms.
This does not prove this edited tree, the enabled GUI profile or two PCs.

Only the owner / authorized validation checkout can prove the exact complete
package's real private-Python/Tk App startup, portable first-run/build/play/
return, controllers, the enabled GUI profile and two physical PCs. Python
suites, full source/player/privacy/licence review and real build/game checks
remain unrun here. Existing unforced termination/watchdog branches and the
old whole-tree check's retained fixtures/corrupt ZIP remain open.

Area agents: `zip_device_regressions`, `zip_device_fix`,
`tests_catalogs_devices`, `zip_windows_path_audit`, `launcher_gate_devices`,
`retained_export_devices`, `zip_device_docs`, `latest_verify_devices`.
Root owns this record and `docs/status.md`. Separate final reviewer:
`final_diff_review_devices`. No Git command, build, game, network helper,
server, push or release ran here.

## Earlier path privacy follow-up

Release remains **NO-GO**. The main gate is still the actual complete
package's launcher GUI and portable first-run. Private Python is absent here;
builds, games and network helpers remain forbidden. The selected executable
source item was a demonstrated publication-path privacy bypass.
No launcher, runtime or switch behavior changed.

Done:

- Eight area agents read the instructions and audited independent areas.
  Actual export and scan accepted a synthetic mailbox filename; actual tree
  and ZIP scans accepted ordinary text inside private working directories.
  An actual ZIP containing an empty private directory also passed. Tree
  refusal diagnostics separately echoed a synthetic private-looking filename.
  All reproductions used harmless text, no real credentials or personal data.
- The [shared scanner](tools/public_tree_scan.ps1) now checks relative-name
  privacy with the existing credential, path, network and email rules. Staged
  scans refuse `.agents`, `.codex`, `.aws` and files named
  `CODEX_PROGRESS.md`; export already omits them. Tree and ZIP scans check
  empty directories without treating ordinary `.bin` or `.patch`
  directories as file contents. The pinned patch exception remains limited
  to its original diff digest, and still checks the filename and preamble.
- [Tree findings](tools/public_tree_worker.ps1) use a static file placeholder
  and category; ZIP findings keep numeric member indices. The same retained
  inputs now refuse by category without printing private-looking names.
  No input or source patch was rewritten.
- Added [real-entry regressions](tools/test_public_path_privacy.ps1) to both
  [tree](tools/check_public_publish.ps1) and
  [ZIP](tools/check_public_zip.ps1) aggregates. The original red run reached
  308 assertions / 37 actual subprocesses with 70 failures. The expanded,
  frozen suite passed 440 assertions / 47 actual export/tree/ZIP subprocesses,
  with zero failures and empty stderr. Clean controls passed before and
  after; export omissions, bytes/inventory, no staging on privacy refusal,
  no diagnostic disclosure and nine code hashes were checked.
  Evidence: `logs/public-path-privacy-8be01e10cd3b416980fda0b87f80839f/`.
  Original red evidence:
  `logs/public-path-privacy-b43c80ed7d724f28a673705a0c1bc3fc/`.
- Frozen retained-input export and scan exited 0 with empty stderr in
  5.858 / 3.124 seconds: 80 files, 2,025,621 bytes, all 79 patch diff ranges
  unchanged. All 87 input/code snapshots stayed unchanged before, between
  and after. This LICENSE/patch subset is not complete corresponding source
  or a player candidate. Evidence:
  `logs/retained-export-name-scan-d345795ab58f43e9810a6335fc23af14/`.
- Actual readiness tests passed three checker subprocesses; normal readiness
  still exits 2 / BLOCKED after catalogs and the actual starter refusal.
  Actual launcher refusal again proves only missing private Python, never GUI
  startup. Actual player wrapper checks refused missing inputs/interpreter;
  Python packaging and scanning never started. The packaging Tk probe and
  launcher selftest do not start the real App and cannot close that gate.
- Updated public scan documentation, the go/no-go sheet and switch evidence.
  Latest supplied verification is recorded below; it was not reproduced here.
- Frozen actual aggregates exited 0 with empty stderr: tree parsed 20
  PowerShell files and passed 12 suites / 10,555 checks/assertions in
  312.481 seconds; ZIP parsed 24 files and passed 15 suites / 3,126 assertions
  in 443.494 seconds. Both ran the 440-assertion / 47-entry privacy suite.
  Both 23-tool catalogs passed, with three source root files present.
  All 141 tool-file and 79 patch names/hashes stayed unchanged before,
  between and after. Evidence:
  `logs/release-name-scan-session-20261102/aggregate-9293f946bea9414fb66c65ee769bb125/`.
- Separate reviewer `final_diff_review_privacy` found no code blocker and
  independently passed the actual privacy suite (440 assertions / 47 entries)
  and catalogs, with empty stderr. All 224 tool/patch/launcher file names and
  hashes stayed unchanged. Saved originals matched the pre-edit hashes; root
  document edits reconstruct their exact original bytes without Git.
  Evidence: `logs/release-name-scan-review-20261102/`.
- The reviewer's actual document checker covered all six changed documents:
  153 local links checked and 288 PowerShell files parsed, with no missing
  document/link or syntax findings and empty stderr. Overall exit 1 remains
  on retained text-only image-name fixtures and a corrupt ZIP; whole-tree
  checking did not complete. Nothing was removed or weakened for a pass.
  Evidence is in the review directory above.

Original production bytes and baseline hashes are retained without Git in
`logs/release-name-scan-session-20261102/`; the switch-document original is
in `logs/latest-verify-evidence-5f7808afd50d482fb80fab7df4bb8a6b/`.
These are local audit evidence, not a public source selection.

Latest owner-supplied verification, not reproduced here: draft `7ecf7f2b8f`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`;
clean merge, 182-second build `943fc4631acf2c13`, finished
`2026-11-02T05:10:52`. Selftest OFF: 6000 wall / 5106 logical,
202 successful restores, zero bad, 447 comparisons with zero mismatches,
101/101 wrong-input divergences. OFF same-PC pair: 6000 frames, 199 hashes
each, zero mismatches/NETDESYNC, 52.1/52.1 FPS, stalls 0/83 (0/2496 ms),
displayed-frame p99 116.3/96.4 ms, restore-and-resim maximum 191.79/55.24 ms.
This does not prove this edited tree, the enabled GUI profile or two PCs.

Open in source:

- A separate actual ZIP audit accepted COM/LPT names containing superscript
  digits, while the ASCII-device control refused. No extraction occurred.
  This Windows path-validation issue is unfixed, outside the selected privacy
  change. Evidence: `logs/zip-name-audit-4ea3718b4a2f49b9a9bdcc7329b4615b/`.
- Existing unforced interruption/termination/watchdog branches and unproved
  independent process absence remain open. Retained intentional fixtures and
  a corrupt ZIP still obstruct the old whole-tree source checker. Nothing is
  deleted or weakened to manufacture a pass. Privacy rules are conservative
  checks, not proof that every private value or provenance issue was found.

Only the owner / authorized validation checkout:

- Run the exact reviewed complete package's real starter through private
  Python/Tk App startup, portable first-run/build/play/return and controller
  checks. A Tk import/probe, mocks or missing-Python refusal do not prove it.
- Run Python suites and complete source/player/privacy/licence review. Prove
  the exact build/game and enabled GUI switches on two physical PCs, including
  the advertised routes and recovery cases. This copy cannot close those gates.

Area agents: `export_preflight_audit`, `text_scan_audit`,
`zip_entry_audit`, `readiness_contract_audit`, `launcher_release_audit`,
`tests_catalogs_release`, `release_scope_audit`, `latest_verify_evidence`.
Separate final reviewer: `final_diff_review_privacy`. File ownership was
exclusive; root owns this record and `docs/status.md`.
No Git command, build, game, network helper, server, push or release ran here.

## Earlier write interruption follow-up

Release remains **NO-GO**. The highest release gate is still the actual
packaged launcher and portable first-run. This copy lacks private Python;
builds, games and network helpers remain forbidden. The bounded source-only
item selected here is the open timeout after export staging begins. No
production launcher, scanner, runtime or switch behavior changed.
Original bytes and hashes for this session are saved without Git under
`logs/release-interruption-session-20261102/original/` and `baseline.json`.

Done:

- Added [interruption tests](tools/test_public_tree_interruption.ps1) without
  worker hooks or production changes. The frozen actual suite passed 4,678
  assertions through six actual export processes. Two eight-second deadlines
  with confirmed worker termination retained 691 and 851 of 1,501 selected
  files. Every retained file matched a source prefix; retries refused without
  changing output. Complete before/after exports passed with identical bytes
  and inventory; the source and five code hashes stayed unchanged. This proves
  interruption in the write loop or its path checks, not inside a particular
  `stream.Write`. Evidence:
  `logs/public-tree-interruption-f9d0f173ace14c7397e7e604106e2600/`.
  The earlier 4,630-assertion run is preliminary for this revision.
- Actual `test_launcher_entry.ps1` exited 0 only because real `Tekken4.cmd`
  exited 1 for missing private Python. Actual readiness exited 2 / BLOCKED;
  both stderr streams were empty and six source hashes stayed unchanged.
  GUI never started. Evidence:
  `logs/release-interruption-session-20261102/launcher-gate-2f24f850683e48dd98e8acfba3f4c93d/`.
- Updated [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md) to the latest
  owner-supplied report below. No runtime switch was changed.
- Added [process-start failure tests](tools/test_public_tree_start_failure.ps1).
  The actual test entry passed 51 assertions through four actual exports:
  duplicate `Include` controls completed before and after two oversized
  worker-command refusals with no staging. A separate native probe observed
  error 206 and is not counted as an export entry. No production bytes changed.
  Evidence: `logs/public-tree-start-failure-91e94b3c664847d2af4cbb25120c4848/`.
- Independent retained-input export and scan completed with exit 0 and empty
  stderr in 5.582 and 2.915 seconds: 80 files, 2,025,621 bytes, 79 unchanged
  patch diff ranges. All 84 input/code snapshots stayed unchanged before,
  between and after. Evidence: `logs/retained-export-interruption-20261102/`.
  This subset is not complete corresponding source or a player candidate.
- The frozen actual [aggregate](tools/check_public_publish.ps1) and hash
  harness exited 0 with empty stderr: 19 PowerShell files parsed, 11 suites
  passed 11,429 checks/assertions. Interruption rerun: 5,518 assertions through
  six entries, 884/938 of 1,501 files retained at eight seconds. Start failures:
  51 assertions through four entries. Both 23-tool catalogs passed. All 116
  direct tool names/hashes and 79 patch names/hashes stayed unchanged. Evidence:
  `logs/release-interruption-session-20261102/catalog-agent/`.
  Assertion counts vary with the number of retained files checked. The full
  ZIP aggregate was not rerun; shared text tests ran both actual scanner routes.
- Separate reviewer `final_diff_review_interruption` independently passed the
  frozen interruption suite (4,864 assertions / six actual entries, 764/840
  files retained), start suite (51 / four) and actual catalogs (23 tools each,
  three root files). All 121 recursive tool-script names/hashes and 79 patch
  names/hashes stayed unchanged; stderr was empty. No code blocker was found.
  Evidence: `logs/release-interruption-review-20261102/`.
- The actual document checker covered all four changed documents: 111 local
  links resolved and 278 PowerShell files parsed. Overall exit 1 remains on
  retained text-only image-name fixtures and a corrupt ZIP; the whole-tree
  check did not complete. Stderr was empty. Nothing was deleted or weakened
  to manufacture a pass. Evidence:
  `logs/release-interruption-session-20261102/root-doc-check.txt`.

Latest owner-supplied verification, not reproduced here: draft `15b0d73c9c`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 167-second build `943fc4631acf2c13`, finished `2026-11-02T04:45:22`.
Selftest OFF: 6000 wall / 5106 logical, 202 successful restores, zero bad,
447 comparisons with zero mismatches, 101/101 wrong-input divergences.
OFF same-PC pair: 6000 frames, 199 hashes each, zero mismatches/NETDESYNC;
host/join FPS 52.1/52.1, stalls 0/60 (0/2102 ms), displayed-frame p99
101.3/94.6 ms, restore-and-resim maximum 266.48/55.40 ms. This does not prove
this edited tree, the enabled GUI profile or two physical PCs.

Open / owner-only:

- Interruption inside a single `stream.Write`, completed-attempt calibration
  fallback, termination-error and outer-watchdog failure branches are unforced.
  Independent process absence is unproved. Existing intentional fixture
  findings still prevent a completed whole-tree source check.
- The owner must run the exact reviewed complete package's real starter through
  private Python/Tk GUI startup and portable first-run/build/play/return in the
  authorized validation checkout. Python suites, complete source/player and
  licence review, enabled GUI switches and two physical PCs remain unproved.

Eight area agents: `write_interruption_test`, `failure_branch_review`,
`tests_catalogs_interruption`, `launcher_gate_interruption`,
`retained_export_interruption`, `export_interruption_docs`,
`latest_owner_evidence_interruption`, `release_priority_audit`.
Root owns this record and `docs/status.md`; file ownership is exclusive.
Separate final-diff reviewer: `final_diff_review_interruption`.
No Git command, build, game, network helper, server, push or release ran here.

## Earlier export failure coverage follow-up

Release remains **NO-GO**. The actual launcher is still the main release gate:
private Python is missing. The actionable source-only item selected here is
failure coverage after export staging begins and during worker/helper loading.
No production launcher, scanner, runtime, switch or server behavior changed.
Original bytes and hashes are saved without Git under
`logs/release-failure-session-20261102/original/` and `baseline.json`.

Done:

- Added [write-failure tests](tools/test_public_tree_write_failure.ps1) through
  the actual export/scan entry. Fixture-only directory permissions allow the
  root LICENSE write but deny creation of the next selected subdirectory.
  Original access rules are restored in finally; no account SID or ACL is saved.
  Retained partial output and source bytes are checked; export retries must
  refuse unchanged staging and fresh complete controls must pass. A content
  scan of a partial tree does not prove the selected export completed.
- Added [worker-load tests](tools/test_public_tree_worker_failure.ps1).
  An initial run passed 84 assertions through seven actual entry subprocesses.
  Exclusive read locks on the actual worker and shared helper caused four
  sanitized scan/export refusals without staging. The unchanged input scanned
  before and after and exported after the locks were released. All five code
  hashes and input inventory/bytes stayed unchanged. Evidence:
  `logs/public-tree-worker-failure-bd521583a43f49c6863c78c2fec0b7cc/`.
  These tests run serially; do not run other tree/ZIP scans while they hold locks.
- The [aggregate](tools/check_public_publish.ps1) now parses and executes both
  suites in addition to every existing suite. The frozen actual aggregate and
  hash harness exited 0: 17 PowerShell files parsed, nine suites passed 5,860
  checks/assertions. The revised write suite passed 85 assertions through eight
  actual export/scan processes; both partial trees passed content scans while
  export retries correctly refused their incomplete output. Worker-load suite:
  84 assertions / seven processes. Both 23-tool catalogs passed. All 114 direct
  PowerShell/Python tool names/hashes and all 79 patch names/hashes stayed
  unchanged. Evidence: `logs/release-failure-session-20261102/catalog-agent/`.
  The earlier 69 / six write-suite result is preliminary for this revision.
- Independent retained-input export and scan both exited 0 with empty stderr
  in 37.687 and 6.619 seconds: 80 files, 2,025,621 bytes, 79 byte-identical patch
  diff ranges; all 84 code/input snapshots stayed unchanged. The first harness
  retained a preliminary run with parent PowerShell progress on stderr; the
  corrected harness silenced progress and reran both actual entries. Evidence:
  `logs/retained-export-failure-followup-f5b9f9973ce1499b8f085f81b457013b/`.
  This subset is not complete corresponding source or a player candidate.
- Actual launcher refusal test exited 0 solely because real Tekken4.cmd exited
  1 for missing private Python. Actual readiness exited 2 / BLOCKED after its
  catalog and starter entries. Both stderr streams were empty; six source
  hashes stayed unchanged. GUI never started. Evidence:
  `logs/release-failure-session-20261102/launcher-agent-0ca0c13f8e2d4722955dc2ab4fa5b232/`.
- Updated [export scope](docs/PUBLIC_SOURCE_EXPORT.md) and latest supplied
  [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md). The actual document checker
  covered all four changed documents: 103 local links resolved and 197
  PowerShell files parsed. Overall exit 1 remains on retained image-name
  fixtures and a corrupt ZIP; the whole-tree check did not complete. Nothing
  was removed or weakened. Evidence:
  `logs/release-failure-session-20261102/root-doc-check-final.txt`.
- Separate reviewer `final_diff_review_failure` found no code blocker and
  independently passed both frozen new suites (85 / eight and 84 / seven)
  and actual catalogs (23 tools each, three root files). All 119 recursive
  PowerShell/Python tool hashes and all 79 patch names/hashes stayed unchanged.
  The production supervisor and worker match the saved baseline byte-for-byte.
  All source locks are released. Evidence: `logs/release-failure-review-20261102/`.

Latest owner-supplied verification, not reproduced here: draft `31924ed524`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 231-second build `943fc4631acf2c13`, finished `2026-11-02T04:27:40`.
Selftest OFF: 6600 wall / 5572 logical, 232 successful restores, zero bad,
514 comparisons with zero mismatches, 116/116 wrong-input divergences.
OFF same-PC pair: 6000 frames, 199 hashes each, zero mismatches/NETDESYNC;
host/join FPS 52.2/52.2, stalls 0/83 (0/2778 ms), displayed-frame p99
111.0/99.8 ms. This does not prove this edited tree, the enabled GUI profile
or two physical PCs. No personal worktree paths were copied here.

Open / owner-only:

- Timed interruption during writes, OS process-start failure, termination-error
  and outer test-watchdog failure branches remain unforced. Independent process
  inventory remains unavailable; no no-orphan claim is made. Whole-tree source
  checking still has retained intentional fixtures; nothing is deleted or
  weakened to manufacture a pass.
- Actual GUI and portable first-run, Python suites/payload checks, complete
  source/player/privacy/licence review, exact build/game, enabled GUI switches
  and two physical PCs remain unproved here. Builds, games and network helpers
  are forbidden in this copy. Scanner tests cannot close those release gates.

Eight area agents: `staging_failure_tests`, `worker_load_tests`,
`tests_catalogs`, `export_failure_docs`, `launcher_gate`, `owner_evidence`,
`retained_export_audit`, `failure_branch_audit`. Separate read-only reviewer:
`final_diff_review_failure`. All read AGENTS.md and this record;
file ownership is exclusive. Root owns this record and docs/status.md.
No Git command, build, game, network helper, server, push or release ran here.

## Earlier public-tree process deadline follow-up

Release remains **NO-GO**. The actual launcher is the main release gate;
its refusal-only recheck still finds private Python missing. The selected
actionable source-only item is the public-tree export/scan process deadline
left open below. No launcher, runtime, switch or server behavior changed.

The first frozen candidate failed the existing real-entry category suite:
the supervisor lost the sanitized text-limit message in serialized stderr.
Both aggregate and independent review reproduced it. The worker now emits
static sanitized refusal messages on stdout. The same unchanged failing
fixture reports the expected refusal through the corrected actual entry.
The results below apply to the corrected hashes; earlier runs are preliminary.

Original source, test and document bytes are saved without Git under
`logs/tree-deadline-session-7bc98726c4a04703b98966a5416cb65d/original/`;
`baseline.json` records their hashes. Root owns this record and `docs/status.md`.

Done:

- The actual [public-tree entry](tools/publish_public_tree.ps1) supervises an
  internal worker for export and scan. Default deadline: 120 seconds;
  `-TimeoutSeconds` accepts integers 1-600. Worker startup, operation and output
  collection share the deadline. Preflight and OS termination are outside it;
  this is not a hard wall-time bound for the entire command.
- Timeout exits 1 / REFUSED, discards worker output and warns that any staging
  remains unapproved and retained. Nothing is deleted or published. A static
  completion marker and expected completion text guard success. Completed
  refusals retain category findings and the existing sanitized regex failure
  message; arbitrary exception stderr is not forwarded.
- Arguments travel as Base64 Unicode JSON, preserving `Include` arrays. Root
  review caught native relative-path resolution changing when the child used
  the project root as its directory. The child now preserves the caller's
  native directory. The final compatibility suite proves nested-directory
  export and scan; no pre-fix runtime reproduction of that regression is claimed.
- New [deadline tests](tools/test_public_tree_deadline.ps1) passed 5,135
  assertions through 13 actual entry processes. The same unchanged 1,001-file
  tree passed before and after two genuine one-second scan refusals. Export
  also refused at one second, with no output directory created. The valid 600
  bound passed; six invalid values including empty refused. Input bytes and
  inventory, plus five source hashes, stayed unchanged. Exclusive reopening
  does not establish independent process absence. Evidence:
  `logs/public-tree-deadline-520d01320017482ab8cfea21c71fb5fc/`.
- New [compatibility tests](tools/test_public_tree_deadline_compat.ps1) passed
  78 assertions through eight actual entry processes, including all four smart
  quotes, ASCII shell punctuation, real Include arrays, patch diff and ordinary
  byte preservation, completed category refusal and invalid combined arguments.
  Evidence: `logs/public-tree-deadline-compat-d096a8e594c544da96b1d65eca9e207d/`.
- Independent retained-input export and scan both exited 0 with empty stderr,
  in 5.969 and 3.127 seconds. All 80 staged file hashes matched the original
  entry's baseline output: 2,025,621 bytes, 79 unchanged patch diff ranges and
  46 display attributions. All 84 input/code snapshots stayed unchanged during
  the final run. This LICENSE/patch test subset is not complete corresponding
  source or a player candidate. Evidence:
  `logs/tree-retained-audit-c6b61250ab0d4e0baae2b191f5864a1c/corrected-frozen/`.
- Actual `test_launcher_entry.ps1` exited 0 only because real `Tekken4.cmd`
  exited 1 for missing private Python. Actual readiness exited 2 / BLOCKED
  after catalog and starter-refusal entries. GUI never started. Six source
  hashes stayed unchanged; both stderr streams were empty. Evidence:
  `logs/launcher-gate-recheck-3e6c9583580047a6942e174b2365a3f7/`.
- Separate reviewer `final_diff_review_tree` independently passed the frozen
  new suites with the same 5,135 / 13 and 78 / 8 assertions / real processes,
  plus the existing category suite with 120 / 20. It reran the original failed
  fixture with the expected safe message and unchanged input hash.
  All 126 tool-script files and all 79 patch names/hashes stayed unchanged.
  It checked the saved originals and retained-input evidence; no code blocker
  was found. Evidence:
  `logs/tree-deadline-review-943cf98761554493900726944680b310/corrected/`.
- Corrected frozen [aggregate](tools/check_public_publish.ps1) and its hash
  harness exited 0: 15 PowerShell files parsed; seven suites passed 5,691
  checks/assertions. Both actual catalogs passed with 23 present unique tools
  each and three root files. All 112 PowerShell/Python tool hashes and all 79
  patch names/hashes stayed unchanged. The initial failed aggregate is retained
  one directory above the corrected evidence:
  `logs/tree-deadline-session-7bc98726c4a04703b98966a5416cb65d/catalog-agent/corrected/`.
  The full ZIP aggregate was not rerun; its entry is byte-identical to baseline.
  Shared tree/ZIP text suites ran in the changed tree aggregate.
- Root's actual document checker covered all five changed documents: 104
  local links resolved and PowerShell parsing completed. Overall exit 1
  remains on retained image-name fixtures and a corrupt ZIP; the whole-tree
  check did not complete. Nothing was removed or weakened to manufacture a
  pass. Evidence:
  `logs/tree-deadline-session-7bc98726c4a04703b98966a5416cb65d/root-doc-check-final.txt`.

Frozen supervisor SHA-256:
`e29af96d181eced776b3cd0161530d755a67031ce8dfb0b52e73ba164ca92623`;
worker `ea2b24e04024e3622678d33edfdeed1acb13ab8a5c3421807b37a1d54d97bb61`.
The worker's scan/export body matches the saved original before its catch,
apart from plain stdout replacing Write-Host. The catch now emits only static
safe messages. An internal-worker comment was added. Earlier encoded-harness
attempts, the first failed aggregate and the suite that correctly failed on
a concurrent code-hash change are preliminary, not final acceptance.

Eight area agents: `tree_deadline_entry`, `tree_deadline_tests`,
`tree_deadline_compat`, `tree_tests_catalogs`, `tree_deadline_docs`,
`tree_retained_audit`, `launcher_gate_recheck`, `latest_owner_evidence`.
Separate read-only reviewer: `final_diff_review_tree`. All read AGENTS.md and
this record. File ownership is exclusive.

Open / owner-only:

- Write-phase interruption, worker-start failure, termination-error and outer
  test-watchdog failure branches were not forced. Independent process inventory
  remains unavailable; no no-orphan claim is made. Whole-tree source checking
  remains red on retained fixtures; nothing was deleted or weakened.
- Actual launcher GUI and portable first-run, Python suites and payload checks,
  complete source/player/privacy/licence review, exact build/game, enabled GUI
  switches and two physical PCs remain unproved here. Builds, games and network
  helpers are forbidden in this copy. No source scanner test can close those gates.

Latest owner-supplied verification, not reproduced here: draft `23d21774fe`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 167-second build `943fc4631acf2c13`, finished `2026-11-02T03:59:55`.
Selftest: 6000 wall / 5106 logical, 202 successful restores, zero bad,
447 comparisons with zero mismatches, 101/101 wrong-input divergences.
OFF same-PC pair: 6000 frames, 199 hashes each, zero mismatches/NETDESYNC;
host/join FPS 52.1/52.1, stalls 0/77 (0/2698 ms), displayed-frame p99
110.3/99.4 ms. It proves neither this edited tree, enabled GUI profile nor two
physical PCs. See [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md).

No Git command, build, game, network helper, server, push or release ran here.

## Earlier ZIP process deadline follow-up

Release remains **NO-GO**. The actual launcher remains the more important
release gate, but an independent recheck confirms private Python is absent.
The selected actionable source-only item was the ZIP scanner process deadline.
No launcher, runtime, switch or server behavior changed.

Done:

- Read AGENTS.md and this record first. Original bytes are saved without Git
  under `logs/zip-deadline-session-8373762c1f6d47a8a2ab1ddb8b9b110b/original/`.
- The actual [ZIP scanner entry](tools/scan_public_zip.ps1) supervises an
  internal worker. Default deadline: 120 seconds; `-TimeoutSeconds` accepts
  integers 1 through 600. Timeout returns exit 1 / REFUSED and discards output
  without a hash, completed scan or pass. Worker startup, scan and output
  collection share the deadline. Wrapper preflight and OS termination are
  outside it; this is not a hard real-time bound for the entire command.
  Unconfirmed termination is reported. The worker's scan body is unchanged.
- Separate review reproduced a valid smart-apostrophe filename refusing in
  the supervisor while passing in the worker. Both paths now travel as
  Base64 Unicode values decoded by static child code. The same unchanged
  reproducer passes through the corrected actual entry; its SHA-256 is
  `149c0fad8aad0b5183924c6e23f915579b531e0217226d7418b5ca6d6d74fce8`.
  This proves the observed refusal was fixed; no injected action was run.
- The independent reviewer's corrected frozen suites passed 1,094 assertions
  through eight actual scanner processes and 63 through seven. Both actual
  catalogs passed: 23 unique present tools each and three root files. All
  five reviewed code hashes stayed unchanged. The same valid 1,000-member
  ZIP passed before and after two one-second refusals; every input could be
  reopened exclusively, with unchanged bytes/inventory. Compatibility covers
  all four smart quote characters and ASCII shell punctuation in filenames.
  Evidence: `logs/zip-deadline-review-a4934bee727c424a9ad986bd0eceb089/smart-fix-*`.
- Corrected frozen [aggregate](tools/check_public_zip.ps1) and hash harness
  both exited 0: 23 required PowerShell files parsed, 2,686 assertions through
  173 real ZIP/tree scanner processes, both actual catalogs passed. All 70
  tool-script hashes and all 79 patch names/hashes stayed unchanged. Evidence:
  `logs/zip-deadline-aggregate-smartquotes-final-b2efd0b09533404db9a84dc2a01c93fa/`.
- Corrected retained-input audit: three Sunday archives completed with the
  expected 123/124/124 files and 138 mail findings each, in
  49.455/51.285/50.880 seconds. The portable LICENSE/79-patch test subset
  passed: 80 files, 2,025,621 bytes, 23.761 seconds. All four input and six
  source hashes stayed unchanged before, between and after scans. Stderr
  was empty; no timeout counted as completed content inspection. Evidence:
  `logs/public-zip-deadline-audit-corrected-a7aeb1119ecd43bf9f474d16b8dcbff8/`.
  These are test inputs, not a complete source/player candidate.
- Independent `launcher_recheck` ran the actual starter-refusal test:
  `Tekken4.cmd` exited 1 for missing private Python. The actual readiness
  entry exited 2 / BLOCKED after catalog and starter-refusal entries. GUI
  never started; no interpreter was substituted. Evidence:
  `logs/launcher-recheck-9b744e36b44b48f48c58f97056e213ac/`.
- Separate reviewer `final_diff_review_deadline` reviewed all six saved
  originals and three new files. No blocking issue remains. It independently
  ran the corrected suites and catalogs, checked the full aggregate and
  retained-audit evidence, and confirmed the supplied verification figures.
- Root's actual document checker covered all four changed documents:
  96 local links resolved and 103 PowerShell files parsed. Overall exit 1
  remains on retained image-name fixtures and a corrupt-ZIP fixture; the
  whole-tree check did not complete. Nothing was removed or weakened to
  manufacture a pass. Evidence is under
  `logs/zip-deadline-session-8373762c1f6d47a8a2ab1ddb8b9b110b/root-doc-check-*.txt`.

Final supervisor SHA-256:
`71b85db2714597b5fdbc877ebe3aea0c96b094bdd01ef4497c4575d2dca4fe6c`;
worker `2c6cdb18883d5fdca6380fd0088d5a0fc5951081c67b6a85070b8f88e8a48a26`.
Runs before the cleanup-error wording and Unicode transport corrections are
preliminary, including the earlier directories called final. Only the
corrected evidence tied to these hashes applies to this code.

Open / owner-only:

- CIM process enumeration was denied: independent no-orphan proof remains
  unavailable. Handle release does not prove process absence. Termination-error
  and outer-test-watchdog failure branches were not forced. The public-tree
  export/scan entry still has no whole-process deadline. Whole-tree source
  checking remains red on retained test fixtures.
- Actual GUI/portable first-run, Python suites/payload checks, complete
  source/player/privacy/licence review, exact build/game, enabled GUI profile
  and two physical PCs remain owner-only and unrun here. Builds, games and
  network helpers are forbidden here. Scanner tests cannot close these gates.

Latest owner-supplied verification, not reproduced here: draft `d56a1ab337`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 164-second build `943fc4631acf2c13`, finished `2026-11-02T03:22:35`.
Selftest: 6000 wall / 5106 logical, 202 successful restores, zero bad,
447 resim comparisons with zero mismatches, 101/101 wrong-input divergences.
OFF same-PC pair: 6000 frames, 199 hashes each, zero mismatches/NETDESYNC;
host/join FPS 52.2/52.2, stalls 0/78 (0/2907 ms), displayed-frame p99
112.9/98.8 ms. This proves neither this edited tree, enabled GUI profile nor
two physical PCs. See [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md).

Eight area agents: `zip_deadline_entry`, `zip_deadline_tests`,
`zip_deadline_compat`, `zip_deadline_catalogs`, `zip_deadline_docs`,
`zip_deadline_retained`, `launcher_recheck`, `latest_verify_record`.
Separate read-only reviewer: `final_diff_review_deadline`. Root owns this
record and `docs/status.md`. All read AGENTS.md; file ownership was exclusive.
No Git command, build, game, network helper, server, push or release ran here.

## Earlier text scanner timeout follow-up

Release remains **NO-GO**. The selected open source-only item was the two
retained valid text inputs that exceeded 180 seconds through the actual ZIP
scanner. No launcher, runtime, switch or server behavior changed.

Done:

- Read AGENTS.md and this record first. Saved original bytes under
  `logs/text-scan-session-6e27f2655ec14235a54ccdf3e60f7dd9/original/`
  for review without Git.
- New actual-entry tests reproduced the old long-word and newline hangs:
  90-second and 60-second child deadlines failed. Neither timeout was counted
  as a refusal or pass. Supplemental old-pattern diagnosis confirmed regex
  timeouts; helper checks are not counted as entry acceptance.
- The shared text scanner now skips impossible dense-symbol searches and
  avoids repeatedly scanning LF runs in two line-start patterns. CR whitespace,
  comment continuation and the existing content categories are preserved.
- Full-content regex searches in that helper now have a two-second .NET
  timeout. Failures stop with sanitized errors. Lazy match collections are
  materialized inside the guard using explicit `get_Count()`; PowerShell's
  ordinary property getter could hide the timeout exception. This is not a
  deadline for a whole collection, scan, patch-header helper or process.
- Three new suites passed 383 assertions through 47 real ZIP/tree scanner
  processes: words 87/9, whitespace 176/18, categories 120/20. Clean controls
  pass; category refusals complete; immediate and lazy regex timeouts refuse
  without echoing input or claiming `SCANNED` or `PASS`. Child deadlines fail
  the tests. Fixtures remain unchanged and unextracted.
- Final scanner helper SHA-256 is
  `5e279f9372d63bc0cc97e0c1a2f20aa4a3bdde7fd4e44ee70dde60291cb83f7c`.
  The implementation agent ran both original timeout ZIPs against this
  helper: completed scans and passes, unchanged hashes. The independent final
  six-input audit confirmed them in 2.517/2.950 seconds. Three Sunday archives
  completed with the same 138 mail findings each (123/124/124 files); the
  portable subset passed (80 files, 2,025,621 bytes). All six input and five
  implementation hashes stayed unchanged. See [audit](docs/PUBLIC_ZIP_AUDIT.md)
  and `logs/public-text-audit-final-cfe1442fcf614b41a485116a3c3f4355/`.
- Frozen final independent aggregates both exited 0: ZIP checked 20 required
  PowerShell files and passed 1,529 assertions through 158 real scanner
  processes; public-tree checked 12 files and passed 478 checks/assertions.
  Both actual catalogs reported 23 unique present tools and three root files.
  All 67 tool-script hashes and all 79 patch names/hashes stayed unchanged
  across both aggregates. Evidence is under
  `logs/text-scan-review-final-f10dffaae7054f6082970a3da156d3f6/`.
- Separate reviewer `final_diff_review_text` reviewed the finished source,
  tests and documents against saved original bytes and found no blocking
  issue. Its independent real entries above are the final aggregate evidence.
  Earlier aggregate/audit attempts overlapped the `get_Count()` correction
  and are preliminary, never final proof. A redundant integration-agent
  sequence was already running; it supplies no extra acceptance gate.
- Updated scanner scope, status and latest supplied switch evidence. Root's
  actual document checker covered all six changed documents: local links
  resolved and PowerShell parsing completed; overall exit 1 remains on
  retained image-name and corrupt-ZIP fixtures. Nothing was deleted or the
  checker weakened to manufacture a pass. Evidence is
  `logs/text-scan-session-6e27f2655ec14235a54ccdf3e60f7dd9/root-doc-check.txt`.

Open / owner-only:

- There is no whole-process deadline. Difficult valid text may refuse for
  manual review. The scanner is a limited source-policy check, not complete
  payload/privacy/licence acceptance. Whole-tree source checking remains red
  on retained test fixtures.
- Exact complete source/player/privacy/licence review, Python suites/payload
  checks, actual launcher GUI/portable first-run, build/game, enabled GUI
  switches and two physical PCs remain open. Builds, games and network helpers
  are forbidden here. A scanner pass cannot close these acceptance gates.

Latest owner-supplied verification, not reproduced here: draft `87e585cc4f`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 162-second build `943fc4631acf2c13`, finished `2026-11-02T02:58:01`.
Selftest: 6600 wall / 5572 logical frames, 232 successful restores, zero bad,
514 resim comparisons with zero mismatches, 116/116 wrong-input divergences.
Switches-OFF same-PC pair: 6000 frames, 199 hashes per side, zero mismatches
and NETDESYNC lines; host/join run-average FPS 52.1/52.2, stalls 0/95
(0/3387 ms), displayed-frame p99 122.3/98.9 ms. It proves neither this edited
tree, the enabled GUI profile nor two-PC play. See
[switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md).

Eight area agents have exclusive files: `text_scan_fix`, `giant_word_tests`,
`newline_tests`, `text_category_tests`, `tests_catalogs_text`, `text_scan_docs`,
`retained_text_audit`, `latest_owner_evidence`. Separate read-only reviewer
`final_diff_review_text` owns finished-diff review. Root owns this record and
`docs/status.md`. All read AGENTS.md. No Git command, build, game, network
helper, server, push or release ran here.

## Earlier DEFLATE work-budget follow-up

Release remains **NO-GO**. The selected open source-only item is the scanner's
unbounded DEFLATE parser work. This session adds fixed archive-wide work
counters and proves them through the actual scanner entry. No launcher,
runtime, switch or server behavior changed.

Done:

- Read AGENTS.md and this progress record first. Saved original bytes under
  `logs/zip-budget-session-cdfb502b7eb94bad855b1f258365f296/` for review without Git.
- Added one shared budget per archive: 1,024 blocks, 2,097,152 decoded symbols
  and 1,048,576 allocated Huffman lookup slots. Exhaustion refuses even a
  structurally valid archive. The counters do not promise a wall-time bound.
- The actual valid and malformed DEFLATE entries passed 123/11 and 260/26
  assertions/scanner subprocesses on the changed implementation.
- New block-boundary tests passed 98 assertions through six real scanner
  processes, including cumulative member limits. A saved pre-fix scanner copy
  accepted the same unchanged over-budget input the current entry refuses.

- New [symbol](tools/test_public_zip_budget_symbols.ps1) and
  [table](tools/test_public_zip_budget_tables.ps1) suites passed 59/4 and
  185/5 assertions/real scanner subprocesses. All three new suites total
  342 assertions through 15 processes. Exact boundaries pass; over-budget
  cases refuse. Independent .NET reads validate the fixtures first.
- The first proposed 1,048,576-symbol allowance caused incomplete refusals
  on ordinary retained inputs. Supplemental helper diagnosis identified
  exhaustion; those early refusals were not accepted as content scans. The
  final 2,097,152 allowance restored completed scans on all four inputs.
- Final actual retained scans: expected exit 1 with the same 138 mail-category
  records for each Sunday archive; portable subset exit 0, 80 files and
  2,025,621 bytes. All input/helper/integration hashes stayed unchanged.
  Times were 41.919/40.759/40.959/19.112 seconds under concurrent load;
  no speed comparison is claimed. See [audit](docs/PUBLIC_ZIP_AUDIT.md).
- Final helper SHA-256 is
  `5f37e906109b081b622938c25f58f0908c56cfbd642b4c539563a7974eb508df`.
  Earlier implementation/budget attempts are preliminary evidence only.

- Frozen [aggregate](tools/check_public_zip.ps1) exited 0: 16 required source
  files parsed and kept identical hashes, both actual catalogs reported 23
  unique present tools plus three root files, and all 79 patch names/hashes
  stayed unchanged. Nine suites passed 1,146 assertions through 111 scanner
  processes, including completed retained-archive scans. Evidence is under
  `logs/zip-budget-aggregate-8b87c249237a49a7a9e1486c9ef36df8/`.
- Root independently reran the unchanged pre-fix block fixture through the
  current actual scanner: exit 1 / REFUSED, SHA-256
  `8ea07c713870b99b8eac70079c6db7309ef75f6edd0341df328d61e3e91a234b`.

- Separate reviewer `final_diff_review_budget` independently ran the frozen
  aggregate: exit 0, the same 1,146 assertions / 111 scanner processes,
  unchanged 16 required source hashes and all 79 patch names/hashes. Review
  against saved original bytes found no blocking code/test issue. Evidence is
  under `logs/zip-budget-review-0da92b7635d1445da6c2885f24869261/`.
- Root's real document checker covered all five changed documents. Local
  links resolved and PowerShell parsing completed; overall exit 1 remains on
  retained image-name/unsafe-name/corrupt-ZIP fixtures. No fixture was removed
  or checker weakened. See the final check output under
  `logs/zip-budget-session-cdfb502b7eb94bad855b1f258365f296/`.

Open / owner-only:

- A retained valid giant-word fixture exceeded a real scanner test's 180-second
  deadline. Its cause was not isolated; text-regex costs are a source-based
  suspicion, not a proven diagnosis. The unchanged fixture SHA-256 is
  `9adcb8e2df7445658ad78a7c4c766ab098b43e720c89ae83e773c6bd8d297bf1`,
  under `logs/public-zip-budget-symbols-002a5d4df9a6480aa3b0c6cab3667f0f/`.
  Timeout was a failed test, never counted as a scanner refusal or pass.
  A pure-newline fixture also timed out at 180 seconds; its cause likewise
  remains unisolated. SHA-256 is
  `6b19a98f6ac0d7fb98442a7d7398988697dd5151cb47aedfdacc8bc3976feaae`,
  under `logs/public-zip-budget-symbols-95f661108f6b4c7b9a440d90ab140444/`.
  Final budget fixtures use short lines and completed through the real entry.
- Parser work counters do not impose a hard process deadline or make scans fast.
  Whole-tree source checking remains red on retained test fixtures.
- Exact complete source/player/privacy/licence review, Python suites/payload
  checks, actual launcher GUI/portable first-run, build/game, enabled GUI
  switches and two physical PCs remain open. Builds, games and network helpers
  are forbidden here. A source scanner pass cannot close these acceptance gates.

Latest owner-supplied verification, not reproduced here: draft `8676b7430f`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 214-second build `943fc4631acf2c13`, finished `2026-11-02T02:35:39`.
Selftest: 6000 wall / 5106 logical frames, 202 successful restores, zero bad,
447 resim comparisons with zero mismatches, 101/101 wrong-input divergences.
Switches-OFF same-PC pair: 6000 frames, 199 hashes per side, zero mismatches
and NETDESYNC lines; host/join run-average FPS 52.1/52.1, stalls 0/70
(0/2298 ms), displayed-frame p99 106.3/97.9 ms. This supersedes older supplied
reports below; it proves neither this edited tree, the enabled GUI profile nor
two-PC play. See [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md).

Nine area agents have exclusive files: `deflate_work_budget`,
`zip_budget_integration`, `budget_block_tests`, `budget_symbol_tests`,
`budget_table_tests`, `tests_catalogs_budget`, `budget_scan_docs`,
`budget_retained_audit`, `latest_verify_evidence`. Separate read-only reviewer
`final_diff_review_budget` owns finished-diff review. Root owns this record
and `docs/status.md`. All read AGENTS.md. No Git command, build, game,
network helper, server, push or release ran here.

## Earlier DEFLATE completion follow-up

Release remains **NO-GO**. The selected source-only open item was the observed
truncated empty-DEFLATE false pass. No launcher, runtime, switch or server
behavior changed.

Done:

- Before the fix, the actual `scan_public_zip.ps1` accepted the retained
  truncated stream. It now exits 1 / REFUSED on the same unchanged input:
  SHA-256 `331d43c8da4a4e064ea2fec821a09c274957f3dc48352fef9ba4f478de0576ae`.
  Complete empty controls still pass. Root independently reran the refusal.
- Added [raw DEFLATE validation](tools/public_zip_deflate.ps1), wired through
  the real scanner's checked dependencies and bounded member regions. Stored,
  fixed and dynamic blocks must complete; Huffman trees, repeats, reserved
  symbols, output length and backreference history are checked. Only unused
  bits of the final byte may remain. Later .NET reads and CRC checks still run.
  No compilation, extraction, archive repair or member execution occurs.
- Added [valid stream tests](tools/test_public_zip_deflate_valid.ps1) and
  [malformed stream tests](tools/test_public_zip_deflate_invalid.ps1): actual
  scanner subprocesses, clean controls, unchanged hashes/inventory and output
  redaction. Final helper passed 123 assertions / 11 valid-suite processes,
  260 / 26 malformed-suite processes and 132 / 11 existing integrity processes.
  Root independently ran both final new suites: exit 0, 383 assertions through
  37 actual scanner subprocesses. Clean controls passed; malformed cases refused.
- The final reviewer caught malformed-distance fixtures whose zero declared
  length could cause an earlier refusal. The test agent gave them plausible
  declared lengths and reran the suite; no assertion was weakened.
- Both actual catalogs ran: 23 unique present tools each and three root files.
  The aggregate now parses 13 required files and invokes all six scanner
  suites plus the catalog entry. The separate reviewer ran the frozen aggregate:
  exit 0, 804 assertions through 96 scanner processes (60/10, 171/33, 58/5,
  132/11, 123/11, 260/26); all 79 patch names and hashes stayed unchanged.
- The final helper SHA-256 is
  `049b5972869e0d67e90aac14cc2a90c11123de58fdbbe4665d786c239a803656`.
  A hot-loop optimization landed during initial aggregate/audit runs. Those
  mixed-version runs are not final proof. The separate frozen aggregate and
  five retained-input scans completed with this helper hash unchanged before
  and after execution. No implementation edits followed the frozen checks.
- The final actual archive audit read all three Sunday inputs: expected exit 1,
  123/124/124 files and only the same 138 mail-category records per archive.
  The sanitized portable subset passed: exit 0, 80 files, 2,025,621 bytes.
  All input hashes stayed unchanged. Final concurrent-load wall times were
  42.351/41.485/39.920 seconds for Sunday inputs and 18.483 for the subset,
  materially slower than the earlier 4.2/2.6-second CRC-only reader. See
  [PUBLIC_ZIP_AUDIT.md](docs/PUBLIC_ZIP_AUDIT.md). This remains a test subset,
  not complete corresponding source or a player candidate.
- Updated [scanner scope](docs/PUBLIC_ZIP_SCAN.md) and
  [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md).
  Root's final real document check covered all five changed documents:
  70 local links resolved and 69 PowerShell files parsed, then exit 1 on
  retained image-name and corrupt-ZIP fixtures. No fixture was removed
  or checker relaxed to manufacture a pass.

Open / owner-only:

- The scanner is materially slower. It has byte/memory bounds, not a wall-time
  or work-budget bound; many-block adversarial inputs may take substantial
  time. This performance/resource limitation remains open. Whole-tree source
  checking also remains red on retained image-name/unsafe/corrupt fixtures.
- Exact complete source/player/privacy/licence review, Python suites/payload
  checks, actual launcher GUI/portable first-run, build/game, enabled GUI
  switches and two physical PCs remain open. Those routes are unrun here;
  builds, game and network helpers are forbidden in this copy.

Latest owner-supplied verification, not reproduced here: draft `8f27d7f6be`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 161-second build `943fc4631acf2c13`, finished `2026-11-02T02:17:42`.
Selftest: 6000 wall / 5106 logical frames, 202 successful restores, zero bad,
447 resim comparisons with zero mismatches, 101/101 wrong-input divergences.
Switches-OFF same-PC pair: 6000 frames, 199 hashes per side, zero mismatches
and NETDESYNC lines; host/join run-average FPS 52.0/52.0, stalls 0/88
(0/3052 ms), displayed-frame p99 109.4/102.0 ms. This supersedes the older
supplied reports below; it proves neither this edited tree, the enabled GUI
profile nor two-PC play.

Eight area agents have exclusive files: `deflate_validator`, `zip_integration`,
`deflate_valid_tests`, `deflate_invalid_tests`, `tests_catalogs`, `deflate_docs`,
`retained_archive_audit`, `verify_evidence`. Separate `final_diff_review_deflate`
reviewed the finished code against original bytes saved under
`logs/deflate-session-9e5a0645172b4663abda18faada7015c/` and reran real entries.
Final code and document review completed; no blocking issue was found.
All read AGENTS.md. Root owns this record, `docs/status.md` and the scanner
entry dependency list. No Git command, build, game, network helper, server,
push or release ran here.

## Earlier ZIP integrity follow-up

Release remains **NO-GO**. The selected open source-only item was actual ZIP
member CRC verification. Matching header fields alone did not check the bytes
read. No production launcher, runtime, switch or server behavior changed.

Done:

- The real `scan_public_zip.ps1` accepted a harmless stored text fixture with
  matching but incorrect local/central CRC fields before the fix. The exact
  same retained input now exits 1 / REFUSED, unchanged SHA-256
  `2f7ef08e9f2edfd56ff206d77701dd111ac619bbb8ace69ac311431b2611ebae`.
- [public_zip_scan.ps1](tools/public_zip_scan.ps1) recomputes each safe member's
  CRC from the uncompressed bytes read, including empty files/directories,
  using a bounded in-memory .NET writer. It checks stored-member length
  consistency. No compilation, extraction, archive repair or execution occurs.
- Added [known-vector tests](tools/test_public_zip_crc.ps1) and
  [corruption tests](tools/test_public_zip_integrity.ps1), all through actual
  `scan_public_zip.ps1` subprocesses. Literal standard CRC vectors, stored and
  deflated text, empty members, per-member reset, multiple buffers, wrong
  CRCs, changed content and both stored-length mismatch directions ran.
  Clean controls must pass; archive hashes, inventory and redaction are checked.
- The area agent ran the real [aggregate](tools/check_public_zip.ps1): exit 0,
  ten syntax parses; both actual catalogs, 23 unique present tools each and
  three root files; 421 assertions through 59 scanner subprocesses across
  four suites (60/10, 171/33, 58/5, 132/11). All 79 patch names and SHA-256
  hashes stayed unchanged. Catalogs did not need developer-test entries.
- The actual scanner reread all three retained Sunday archives: expected
  exit 1, 123/124/124 files and 138 mail-category records each, about 4.2 s
  per archive. The existing sanitized portable LICENSE/patch subset passed:
  exit 0, 80 files, 2,025,621 bytes, 2.569 s. All hashes stayed unchanged.
  This subset is not a complete corresponding-source or player candidate.
  See [PUBLIC_ZIP_AUDIT.md](docs/PUBLIC_ZIP_AUDIT.md).
- Root and the separate final reviewer independently reran the finished
  aggregate: both exit 0, the same 421 assertions / 59 scanner subprocesses
  and unchanged 79 patch hashes. Review against saved original file bytes
  found no blocking issue in the scoped CRC/stored-length changes. It does
  not close the known compressed-format gap below or release acceptance.
- An independent read-only audit ran ten additional real scan subprocesses.
  It confirmed CRC/stored-size refusals and found the remaining DEFLATE
  limitation below. Root's final real source check covered all five changed
  documents: 57 local links resolved and 63 PowerShell files parsed, then
  exit 1 on retained image-name fixtures and an intentionally corrupt ZIP.
- Updated [ONLINE_SWITCH_EVIDENCE.md](docs/ONLINE_SWITCH_EVIDENCE.md) with the
  latest owner-supplied verification below. This documents supplied evidence,
  not a run of this tree.

Open / owner-only:

- A harmless truncated empty DEFLATE stream (one byte `01`, declared length
  and CRC zero, beside a clean member) still passes the actual scanner because
  .NET returns no bytes without reporting truncation. CRC validates returned
  bytes; it does not prove complete DEFLATE consumption or format validity.
  Reproducer SHA-256:
  `331d43c8da4a4e064ea2fec821a09c274957f3dc48352fef9ba4f478de0576ae`.
  Evidence is under `logs/zip-integrity-audit-fbce2d67a16346bbaef8f49f083017a1/`.
  This is an observed open limitation, not a fixed or passing safety case.
  See [PUBLIC_ZIP_SCAN.md](docs/PUBLIC_ZIP_SCAN.md).
- Whole-tree source checking remains red on retained text-only image-name,
  unsafe-name and corrupt ZIP fixtures. Document-specific real checker runs
  resolved their links and parsed PowerShell before the archive reader stopped.
  Nothing was deleted or the checker relaxed to manufacture a pass.
- Review the exact complete public source/player outputs and rights; run
  Python suites/payload checks, the actual complete launcher, exact build/game
  and two physical PCs in the authorized checkout. GUI startup, portable
  first-run, enabled switch profile, results, private protocol and licensing
  gates remain open. No Python, GUI, build, game or network helper ran here.
  CRC agreement cannot close those gates or authenticate a producer.

Latest owner-supplied verification, not reproduced here: draft `9cdebb4f93`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 167-second build `943fc4631acf2c13`, finished `2026-11-02T02:06:00`.
Selftest: 6000 wall / 5106 logical frames, 202 successful restores, zero bad,
447 resim comparisons with zero mismatches, 101/101 wrong-input divergences.
Switches-OFF same-PC pair: 6000 frames, 199 hashes per side, zero mismatches
and NETDESYNC lines; host/join run-average FPS 52.0/52.1, stalls 0/71
(0/2411 ms), displayed-frame p99 107.5/100.0 ms. This supersedes the older
supplied reports below; it proves neither this edited tree, the enabled GUI
profile nor two-PC play.

Agents with exclusive source-file ownership: `zip_crc_reader`,
`zip_crc_vectors`, `zip_crc_corruption`, `tests_catalogs`, `zip_crc_docs`,
`retained_zip_audit`, `verify_evidence`; `zip_integrity_audit` was a read-only
coverage audit. Separate `final_diff_review_crc` reviewed the finished diff.
All read AGENTS.md. Root owns this record and `docs/status.md`. No Git command,
compilation, build, game, network helper, server, push or release ran here.
## Earlier ZIP content scan follow-up

Release remains **NO-GO**. The most useful open source-only item selected here
is reading the retained ZIP contents through an actual scanner entry, rather
than treating filename checks or a missing Python interpreter as a payload scan.
No production launcher, runtime, switch or server behavior changed.

Done:

- Added [scan_public_zip.ps1](tools/scan_public_zip.ps1) and its bounded,
  read-only ZIP helper. It refuses outside-tree paths, links, unsafe/colliding
  member names, unsupported metadata, oversized inputs and read failures.
  It never extracts or executes members. Findings print numeric positions and
  categories, not member names or matched values. SHA-256 identifies the exact
  locked archive snapshot checked. The existing source-content rules apply;
  this cannot approve legitimate binary player payloads.
- Real subprocess tests require clean text ZIPs to pass before checking
  refusals. The first aggregate run caught a fixture-writer error and failed;
  its owner fixed the fixture and reran it. Independent review reproduced two
  real false passes with harmless text ZIPs: mismatched local-header names and
  unindexed gaps. The helper now rejects inconsistent local/central headers
  and gaps/overlaps. The reviewer reran the same unchanged reproductions:
  clean still passes; both bypasses now refuse. No test was weakened.
- Ran [check_public_zip.ps1](tools/check_public_zip.ps1): eight syntax parses,
  actual catalogs (23 unique tools each, three root files), 60 positive-entry
  assertions / 10 subprocesses, and 171 safety assertions / 33 subprocesses.
  Root, the area agent and independent reviewer runs exited 0. All 79 patch
  names and SHA-256 hashes stayed unchanged.
- The actual command read all three retained source-test archives: 123, 124
  and 124 files; each exited 1 after scanning contents. Each has 46 members
  with email, patch-author mailbox and coauthor-mail categories (138 category
  records per archive). Archive hashes stayed unchanged. See
  [PUBLIC_ZIP_AUDIT.md](docs/PUBLIC_ZIP_AUDIT.md) for exact identities/results.
- Exercised the existing public-source export on `LICENSE` and all 79 patches:
  80 files, cleaned preambles, byte-identical diff parts, postwrite scan passed.
  The Windows convenience ZIP writer then produced backslash paths and the
  ZIP entry correctly refused them. A separate archive with explicit portable
  paths passed: 80 files, 2,025,621 bytes, SHA-256
  `fb80808520f464250cd13a548413f2d04771461251e8bdb03993599aae3d1f7d`.
  Both experiments remain under logs; neither is a complete source/player
  candidate. No retained input archive or source patch was rewritten.

Open / owner-only:

- The scan does not recompute CRCs, authenticate producers, inspect every
  possible hidden compressed representation, validate player manifests/locks
  or establish licences. Its restricted ordinary-ZIP support refuses ZIP64,
  comments, extra fields and data descriptors. See
  [PUBLIC_ZIP_SCAN.md](docs/PUBLIC_ZIP_SCAN.md) for scope and commands.
- Whole-tree source checking remains red: in addition to the 18 older text-only
  image-name fixtures, retained unsafe ZIP fixtures trigger name findings and
  intentionally corrupt ZIPs stop the old archive-name reader. Document links
  and PowerShell parses run before that stop: the final six-document check
  resolved 51 local links and parsed 58 PowerShell files, then exited 1 on an
  intentionally corrupt ZIP. Nothing was deleted or the old checker weakened
  to manufacture a pass.
- Review and prepare the exact complete public source/player outputs. Run the
  Python suites and payload checks with a real interpreter, then prove the
  actual launcher, exact build, game and two-PC routes in the authorized
  checkout. GUI startup, Host/Join, results, private protocol and licensing
  gates elsewhere in this record remain open. No Python, GUI, build, game or network helper
  ran here; a source ZIP pass cannot close those gates.

Eight area agents read AGENTS.md and have separate file ownership:
`zip_reader`, `zip_entry`, `zip_entry_tests`, `zip_safety_tests`,
`zip_catalogs_tests`, `zip_docs`, `archive_audit`, `verify_evidence`.
Separate `final_diff_review` independently ran the aggregate checker, latest
archive scan and before/after bypass reproductions, and reviews the finished
diff against the saved original document bytes. Root owns this record and
`docs/status.md`. All work stays in this tree; no Git command,
build, game, network helper, server, push or release is authorized.

Latest owner-supplied verification, not reproduced here: draft `477105a109`,
merge base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean
merge; 164-second build `943fc4631acf2c13`. Selftest: 232 successful restores,
514 resim comparisons, zero mismatches, 116/116 deliberate wrong-input
divergences. Same-PC 6000-frame pair, experiment switches OFF: 199 hashes per
side, zero mismatches and NETDESYNC lines, run-average 52.3 FPS on both sides;
host/join stalls 0/78 (0/2862 ms). Finished `2026-11-02T01:50:45`.
This supersedes the supplied reports below. It does not prove this edited
tree, the GUI's enabled COALESCE/DIAG profile or two physical PCs.

## Package 5 online follow-up, latest session

Online acceptance remains **BLOCKED**. No production launcher, runtime, switch
or server behavior changed. The shared OpenRecomp-FGC launcher, private lobby
and T5DR launcher sources are absent from this copy. Python is unavailable;
builds, game runs and `tools/net_*` execution are forbidden here. A passing
source test cannot establish that online works.

Done:

- Put the current package-5 decisions above the historical proposals in
  [SERVER_HANDOFF_T4.md](SERVER_HANDOFF_T4.md) and [LOBBY.md](docs/LOBBY.md):
  lobby protocol stays 1, existing accounts carry over, T4 matches/ratings
  stay separate, and no server change is authorized now. Package 5 follows
  the planned 2026-11-03 reset; no reset is claimed to have happened.
- Recorded [accounts/kicked](docs/ONLINE_ACCOUNTS.md),
  [coexistence](docs/ONLINE_COEXISTENCE.md),
  [client rank text](docs/ONLINE_RANKS.md) and
  [switch evidence](docs/ONLINE_SWITCH_EVIDENCE.md), with concrete owner
  cases through the actual launchers. Today's supplied one-login takeover
  rule is distinct from the later target of concurrent per-game sessions.
- Found an existing optional diagnostic session report, not a usable ranked
  result: `winner` and `score` are null, `match_result_proven` is false, and
  there is no proven match-end detector. No ranked result was produced here.
- Added [check_online_readiness.ps1](tools/check_online_readiness.ps1).
  It checks source/docs, invokes actual catalog and starter-refusal entries,
  and exits **2 / BLOCKED** after successful source checks. Exit 1 means a
  source/input failure; exit 0 is unavailable. It is not a payload/privacy
  scanner and does not replace the existing beta/publication gates.
- Added [test_launcher_entry.ps1](tools/test_launcher_entry.ps1), which checks
  the exact starter hash and refuses private Python/reparse points before
  invoking the real `Tekken4.cmd`. Its observed missing-Python exit 1 proves
  only the refusal branch. The GUI never started. No interpreter or game was
  substituted to turn that result green.
- Added [check_online_catalogs.ps1](tools/check_online_catalogs.ps1): actual
  source catalogs contain 23 unique present tools each and three source root
  files; Host/Join dependencies are present. This is literal source inspection,
  not execution of Python suites, packagers or a complete player package.
- Added [test_online_readiness.ps1](tools/test_online_readiness.ps1), which
  invokes the actual checker three times: blocked readiness, missing document
  and outside-tree document refusal before child entries. All three cases ran.

Latest supplied verification, not reproduced here: draft `42c131551e`, merge
base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean merge;
163-second build `943fc4631acf2c13`. Selftest: 202 successful restores,
447 resim comparisons, zero mismatches, 101/101 wrong-input divergences.
Same-PC 6000-frame pair, switches OFF, RTT target 150 ms, jitter 5 ms, loss 3%:
199 hashes per side, zero mismatches and NETDESYNC lines, 52.2 FPS run average
on both sides; host/join stalls 0/73 (0/2411 ms). Finished
`2026-11-02T01:18:22`. This supersedes the older supplied reports below.

The latest pair covers the reported OFF experiment configuration only.
It proves no newly enabled experimental switch. Source inspection shows
ordinary GUI Host/Join clears inherited overrides, then the helper enables
COALESCE=1 and DIAG=1. That launcher profile remains unproved by the latest
pair. Existing baseline time sync/early/lazy controls are not all disabled
by the phrase "switches OFF"; full effective settings still need recording.
No switch was changed without its required real-entry proof.

Root verification ran the real readiness entry: 12 required files, seven
PowerShell parses, seven documents and 47 local links checked; both catalog
and actual starter-refusal entries ran; final exit 2 / BLOCKED. The real
readiness test entry passed all three subprocess cases (exit 0 for the tests,
not acceptance). The existing `check_beta_source.ps1` also ran on all eight
changed documents: 48 local links and 53 PowerShell parses passed; overall
exit 1 solely for the same 18 retained text-only `.png` fixture filenames
recorded previously. Nothing was deleted or weakened to remove that failure.

Open / owner-only:

- Provide/review the shared-launcher and private protocol sources in their
  authorized lanes. Settle outgoing fields/caps, saved-login policy and a
  shared one-game-per-PC guard. Do not copy T5DR code into this GPL-3 tree.
- Start both actual launchers and prove login/search, then match/ready/result,
  then rooms/friends, then tournaments/spectating. Show `kicked` clearly and
  stop automatic login in both directions. Current takeover is supplied
  behavior, not a server test performed here. Account changes wait until after
  the T4 release; the later per-game session model needs its own acceptance.
- Build the exact reviewed candidate in the authorized checkout, prove the
  selected switches through actual GUI Host and Join, and repeat on two
  physical PCs, including direct/relay routes, rematch and disconnect recovery.
  Source tests and the supplied same-PC pair do not prove any of those routes.
- Prove winner, score and match end before ranked reporting. Rank names remain
  client text only; Tekken 8 names belong to Bandai Namco. No art was added.
- Python suites, GUI/Tk startup, Host/Join game launch, cross-launcher locking,
  server compatibility and all real build/game checks remain UNRUN here.
  Existing beta/publication NO-GO requirements below remain open.

Agents: `protocol_contract`, `accounts_kicked`, `rollback_evidence`,
`rank_text`, `coexistence`, `starter_entry`, `readiness_entry`,
`catalogs_tests`; separate `final_diff_review` completed with no blocking
issue found in these tools/docs. The reviewer independently reproduced all
three entry tests, readiness exit 2 and the existing source check's 18 fixture
findings. Review used current files and recorded text edits; a complete
original-byte/Git baseline was unavailable. This does not close online acceptance.
All read AGENTS.md; file ownership was exclusive. Root owns this record and
`docs/status.md`. No Git command, server, push or release was used.

## Earlier public-tree preparation

Publication remains **NO-GO** for the full source/player trees. The new
PowerShell path runs here without Python. It stages files only; it does not
publish, use Git, build or start a game. The earlier Python attempts below
remain historical failures, not executed Python scans.

Done:

- Added [publish_public_tree.ps1](tools/publish_public_tree.ps1), with separate
  patch-header and content-scan helpers. Fresh staging omits image files,
  removes patch author mailboxes, mail transport metadata and coauthor trailers,
  and compares every byte from the first `diff --git` line through EOF before
  and after writing. Display-name attribution and diff notices remain.
- Scans refuse images, disguised image/binary signatures, private mail metadata,
  secrets, machine paths, nonpublic network addresses and unreviewed URLs.
  Export preflights all selected bytes, then scans the written tree again.
  Scan-only checks every staged file without applying export exclusions.
- Ran the real entry with `-Include @('LICENSE','patches')` into a fresh folder
  under `logs/public-publish-tests`: exit 0, 80 files, all 79 patches checked,
  zero image files, postwrite scan passed. There are 78 top-level patches and
  one debug patch; 46 source preambles contain mailboxes/coauthor trailers.
  Source patches were not rewritten or renumbered.
- Ran a broader real selection (runtime, config, launcher, tools, README and
  selected docs): exit 1 before staging. Findings remain in README, launcher
  core and several tools. These need owner scope/content review; no broad
  source-tree pass is claimed. No images exist in this clean input copy;
  omission/refusal is tested with harmless text filenames and in-memory bytes.
- Added entry-point tests and [check_public_publish.ps1](tools/check_public_publish.ps1).
  Tests caught a real PowerShell default-argument failure, which was fixed and
  rerun. Header tests passed 63 checks, including three actual exports and six
  actual scans; safety tests passed 32 assertions through actual subprocesses
  and in-memory signature checks. Both existing 23-tool catalogs have present,
  unique entries. Catalog inspection does not execute the Python packagers.
- Final independent review found a compressed-IPv6 scan bypass. The scanner
  was fixed; real scan regressions now refuse it without echoing the address.
  Root and reviewer ran the finished `check_public_publish.ps1`: exit 0,
  63 patch checks, 32 safety assertions, six syntax parses, both catalogs and
  unchanged names/SHA-256 hashes for all 79 source patches. The reviewer also
  independently exported and compared all 79 diff byte ranges. No remaining
  blocking issue was found in these tool changes; full publication stays NO-GO.
- Documented the workflow in [PUBLIC_SOURCE_EXPORT.md](docs/PUBLIC_SOURCE_EXPORT.md)
  and the remaining permission/notice questions in
  [THIRD_PARTY.md](docs/THIRD_PARTY.md). Document/link checks passed for these
  pages and RELEASING. The older whole-tree filename checker now refuses the
  intentional text-only `.png` test fixtures retained under logs; this is not
  a clean whole-tree checker pass. Nothing was deleted to make it green.
  Final real checker run covered all four changed documents and 27 local links,
  with 49 PowerShell syntax parses; exit 1 solely on those 18 retained fixture
  filenames. The old filename checker was not weakened.

Open / owner-only:

- Review the exact complete public source and player outputs. The successful
  LICENSE/patch export is a test subset, not complete corresponding source.
  Old Python publishers/packagers do not call the new PowerShell sanitizer;
  their outputs must separately pass the new scan and their existing checks.
  Python suites, payload/zip scans and full player output remain unrun here.
- Resolve the VU1 generator grant, PS2SDK reverb/FXAA and imported-code notice
  chains, SCE/game-derived map publication scope, quoted pricing material,
  exact FFmpeg LGPL/source obligations, dependency notices and Microsoft terms.
  Header cleanup proves no rights and cannot replace author-notice review.
- Build and run the exact reviewed candidate in the authorized real checkout,
  validate the actual launcher and portable path, and test two physical PCs.
  No build, launcher GUI or game was run in this copy. No network service,
  Git write, history rewrite or release was performed.

An earlier supplied verification identified draft `21d1fbb4b6`, merge
base `8b15202341` (branch base `7992837fc3`), onto `c17fd979ca`; clean merge;
174-second build `943fc4631acf2c13`. Selftest: 232 successful restores,
514 compared resim frames and zero mismatches. Same-PC 6000-frame pair with
switches off: 199 hash comparisons per side, zero mismatches and zero NETDESYNC
lines; run-average 49.8 fps on both sides, join 122 stalls / 3169 ms. Finished
2026-11-02T01:05:32. The package-5 section above records the newer report.
It was not reproduced here and does not prove the edited tree, launcher profile
or two-PC internet play. No personal worktree paths are copied into this record.

Agents this session: `patch_headers`, `public_scanner`, `publish_entry`,
`patch_entry_tests`, `publish_safety_tests`, `tests_catalogs`,
`licence_questions`, `publish_docs`; separate `final_diff_review` reviewed the
finished files and independently ran the checker. Root owns this record and
integration checks. Each agent read AGENTS.md; file ownership was exclusive.

## Earlier beta audit record

Decision: **NO-GO**. The Sunday target was 2026-11-01. Missing acceptance
evidence moves the release date. No build or game was started in this copy.
This file was absent when this session began; there was no earlier progress
record to resume. Read [AGENTS.md](AGENTS.md) before continuing.

## Done in this source-only copy

- Read the existing beta checklist and source audit. Split independent work
  among eight area agents and a tests/catalog agent. A separate final reviewer
  reviewed the final diff and independently ran the named source checker;
  no blocking issue was found in those changes. This does not close the
  production audit findings or supply missing acceptance evidence.
- Updated README, release notes and announcement drafts with current NO-GO,
  offline/direct-IP/VPN scope, pending player tooling and controller checks.
  No lobby, ranked, login/server deployment or T5DR 1.2.0 is included.
- Compared effective switch sources. No switches were changed: the supplied
  all-switches-off measurement does not validate the launcher's COALESCE=1,
  DIAG=1 profile. The remaining experimental switches and AUTO_VS stay off.
- Inspected the three existing Sunday archives without extraction. They have
  123, 124 and 124 members; none has an artifact/image filename detected by
  the limited name check. They omit the launcher and private Python and are
  old source-test payloads, not current player candidates. Content scans
  remain unrun. Latest existing archive SHA-256:
  `eb00046c520efb4bc3f6cfdba12803fb25cbec321f985609093de1880a5c8391`.
- Added [check_beta_source.ps1](tools/check_beta_source.ps1) for local document
  links, PowerShell syntax and artifact/image filenames in this tree and zip
  directories. It explicitly leaves beta acceptance NO-GO. It does not run
  the Python scanners or prove a launcher, build or playable game.

## Real entry-point evidence from this session

Windows PowerShell was available. Python, Python 3, py and a bundled Python
were not found. A missing interpreter means the Python code never started.

| Entry point | Result | Meaning |
|---|---|---|
| `cmd.exe /d /c "call .\Tekken4.cmd < nul"` | Exit 1: private Python missing | Starter executed; GUI never started. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File tools/make_player_zip.ps1` | Exit 1: reviewed inputs/version required | Argument refusal, no package made. |
| Same wrapper with `-ScanOnly` and the existing latest Sunday zip | Exit 1: Python 3.12+ unavailable | Wrapper ran; payload scan never started. |
| `python -B tools/make_public_repo.py --out logs/beta-public-repo-20261102` | Exit 1: interpreter missing | No script code ran; no staging output. This tool has no dry-run flag. |
| `python -B tools/publish_source.py --scan-only .` | Exit 1: interpreter missing | No source scan ran; no publication. |
| `python -B tools/package_release.py --scan-only dist/sunday/tekken4-sunday-test-20261031-205628-895451.zip` | Exit 1: interpreter missing | No payload content scan ran. |
| `python -B -m unittest discover -s tools -p test_launcher_online.py -v` | Exit 1: interpreter missing | Zero tests executed; suite mocks core behavior, never starts GUI. |
| Same unittest entry with `test_publish_source.py` | Exit 1: interpreter missing | Zero tests executed. |
| Same unittest entry with `test_release_catalogs.py` | Exit 1: interpreter missing | Zero tests executed. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_beta_source.ps1` | Exit 0: 7 docs, 43 local links, 43 PowerShell syntax parses; 299 file names, 3 archives / 371 member names | Source checks only; cannot pass beta acceptance. |
| Same checker with `-Docs docs/DOES_NOT_EXIST.md` | Exit 1: missing document | Negative entry test; missing input cannot pass. |
| Same checker with `-Docs ../DOES_NOT_EXIST.md` | Exit 1: outside-tree document refused before read | Boundary negative entry test. |

Additional inline PowerShell checks found both 23-name tool catalogs present
and unique, the starter/beta files present, announcement tweet within 280
characters, and the updated communication documents' local links resolving.
These are limited checks, not passes of the Python suites.

## Open in source; no untested production fixes

- Static core review found fullscreen environment inheritance when unchecked
  and an unclosed offline log if process creation fails. Neither was reproduced;
  both remain open. Do not label the audit closed. No production Python was
  changed without execution proof.
- The UI source has no gamepad navigation implementation. Its controls table
  describes in-game controls. The by-pad launcher requirement is unresolved.
- The supplied 2026-11-02 report identifies draft `8f1aa94684`, build
  `943fc4631acf2c13`, a successful selftest and 6000-frame same-PC pair with
  zero mismatches in 199 hash comparisons per side. Run-average speed was
  50.4 fps; displayed-frame p99 was 136.9/104.8 ms and join had 96 stalls.
  This was supplied evidence, not reproduced here, and does not validate the
  edited tree, advertised launcher profile, internet route or physical PCs.
- Python scanner dry-runs and content/privacy scans remain open. Historical
  maintainer docs still need a reviewed public set. Do not weaken scanners to
  turn this tree green. The Git pointer leads outside this copy; no Git export
  was attempted. No Git writes, downloads, server work or release occurred.

## Only the owner or an authorized real validation checkout

1. Resolve the provenance/licence and reviewed pinned payload inputs in
   [THIRD_PARTY.md](docs/THIRD_PARTY.md) and
   [RELEASE_PATH_B.md](docs/RELEASE_PATH_B.md). Choose the exact candidate,
   source revision, matching source export, locks, build IDs and zip hash.
2. Run `make_public_repo.py` into fresh staging and `publish_source.py` scans
   on the reviewed outputs with Python. Run `package_release.py` on the exact
   staged player folder and zip. Review content, secrets/privacy and notices;
   filename inspection here cannot prove their absence.
3. Run the three Python suites. Then start the complete actual launcher;
   GUI/Tk and first-run install/build/play/return, settings and controller
   navigation need a hands-on check. Core mocks cannot replace this.
4. On both PCs, build the exact zip from each player's own supported ISO.
   Prove path B with installed Python, Git and Visual Studio hidden, or state
   the actual needed tools in the beta. No build is permitted in this copy.
5. Play at least 15 minutes of real internet Versus with zero mismatches,
   usable pacing/input/sound, rematch and role-swap/disconnect recovery. Collect
   both logs and send to Main. Check the measured switches match the candidate.
6. Complete [BETA_GO_NO_GO.md](docs/BETA_GO_NO_GO.md). Only the owner checks
   VirusTotal, publishes the draft, chooses latest and posts on Discord. No
   release action is authorized by passing a source check.

## Agents

`launcher_core`, `launcher_ui`, `public_export`, `source_publish`,
`payload_scan`, `portable_path_b`, `player_comms`, `candidate_gate`,
`tests_catalogs`; separate `final_diff_review` completed. Each read AGENTS.md;
file ownership was exclusive. Root owns this record and the source checker.
