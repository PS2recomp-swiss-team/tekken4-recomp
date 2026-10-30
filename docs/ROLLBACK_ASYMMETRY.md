# Rollback asymmetry: one side falls behind

Source audit, 2026-10-30. No build, game, pair, simulator or patch application was run in this copy.
The reported 150 ms pair had about 3.5 times as many rollbacks on one side, depth 9, 80-96 prediction-window
waits (about 3 s) and about 90 time syncs. Another run of the same executable was nearly symmetric
(632/589 rollbacks, depth 5/3, no waits). These totals do not identify the initiating side or cause.
Coalescing and hash cost are outside this investigation, per the owner's evidence.

## Causes, ranked

1. **Unequal local headroom, then lost pacing time.** This is the strongest measured precedent.
   `ROLLBACK_PHASE3B.md` reports two games saturating one RTX 3090, 35-200 ms GS vertex-fence waits concentrated
   on one side, and the other side predicting deeper and time-syncing. The pacing guard shifts deadlines by
   the full lateness once the next deadline is over 50 ms late. It deliberately gives up catch-up time;
   repeated hitches can keep that side slow. The ahead peer's extra rollback work consumes more headroom.
   This explains either role becoming the troubled side and a balanced run of the same executable.
   It does not prove that GPU stalls caused this particular pair.
   The side with more rollbacks, deeper prediction and positive time-sync corrections is usually the
   ahead side waiting for the slow sender's inputs, not necessarily the side that first fell behind.
2. **Time-sync estimator delay and scheduling overshoot.** `npTimeSync` compares 20 samples of local lead
   with the latest received peer lead, sorts their differences, trims four from each end and halves the
   mean. An advantage of at least one frame gives up one frame, or up to four above 2.5 frames. It then
   holds sampling for the correction plus a measured RTT and two frames and must collect a new window.
   It does not speed up a slow peer. Packet transit, gaps in contiguous input and stale peer-lead samples
   can bias that estimate temporarily; neither estimate is a direct measurement of the other game's
   current execution frame. Peer lead is replaced by each arriving INPUT, including reordered packets;
   input/ACK progress cannot regress but the advertised lead may be stale. The wait may also overshoot
   its requested time under load. Repeated local
   hitches can outlast this deliberately slow response. No host-only/join-only time-sync branch or clear
   correction-sign bug was found. Changing thresholds or disabling the guard would be a tuning experiment,
   not a justified release fix.
3. **Simulator scheduling and a queue access bug.** Both directions receive the requested latency, jitter
   and loss, but use different random streams (harness seeds 11/22, plus the runtime role offset). Their
   send histories differ, so identical parameters do not mean identical loss or arrival schedules.
   Delayed-send deadlines are serviced by a CPU thread; a late simulator wake adds real delay beyond the
   configured path. A reference to the front of its deque is read after unlocking the queue mutex while
   another thread may insert in the ordered deque. That access is not safe; insertion can invalidate the
   reference. The optional fix described below copies the deadline while locked. It does not establish
   that this bug occurred in the reported pair.
4. **OS scheduling, focus and priority.** The earlier phase-3 pairs measured a background game taking
   27 ms versus 19 ms for the foreground game, with the ahead side taking most rollbacks. The transport
   now requests process EcoQoS off and a 1 ms timer, and logs whether the power request succeeded.
   This is a mitigation, not a guarantee about CPU placement, driver policy or available time. RX and
   simulator threads request Highest, the tick thread AboveNormal; the GS worker's patch requests
   AboveNormal. These are relative to process priority. Busy-yield waits and competing runnable workers
   can consume CPU time under contention. `PS2X_THREAD_PRIORITY=0` controls the GS helper, not the direct
   network thread priority requests. The current pair harness does not set process priority or affinity;
   phase 3b's AboveNormal and disjoint eight-CPU masks were a separately controlled setup.
5. **Delay boundary and ordinary path variation.** Auto delay changes from 2 to 3 above measured 150 ms.
   Phase 3b observed either result around this boundary. Record the actual negotiated value before
   comparing runs. This can change prediction depth, but does not by itself explain persistent unequal
   local speeds or identify a role defect. More input delay did not cure the GPU-bound phase-3b pairs.
   RTT is the median of up to 32 PING samples. PINGs are frequent during startup, then sent only during
   outgoing silence; an active fight can retain old samples. A steady summary RTT does not prove that
   current delivery latency is steady, and the correction hold can be based on those older samples.

## What this code rules out, and what it does not

- There is no role-specific pacing guard or time-sync correction policy in the inspected game override.
  The host measures/picks auto delay; both peers use the negotiated session delay. A fixed host-versus-join
  speed defect is not supported by these paths or by the role reversal, but totals alone cannot exclude
  every role-dependent startup or transport effect.
- The supplied runtime and patch text contains no unfocused-window simulation pause. Keyboard sampling
  is focus-dependent; the scripted next run disables local-pad sampling. Phase 3b's foreground experiment
  did not cure the GPU stalls, and GPU priority HIGH moved the stalled side. Neither observation rules
  out all Windows or driver focus effects on a new build/machine.
- A prediction-window wait counts missing contiguous input, not a GPU fence wait. `NETSUMMARY` separates
  lockstep waits from these fight waits. Depth 9 is possible with the default max prediction 8: `rc` is the
  first missing frame, and the check permits `rc == f - 8`, leaving frames `rc` through `f` unconfirmed.
  It is not evidence that a configured cap was ignored.
  `rc` is not refreshed immediately after the time-sync sleep, so a stale pre-sleep gap can increment
  the stall count even if the wait returns immediately. Inspect wait duration: this cannot explain
  three seconds of measured wait time by itself.
- Patch 82's `PS2X_PACING_SPIN_US` change is for normal-play waits; its text explicitly leaves cycle-ordered
  rollback/netplay waits unchanged. Changing that setting is not an established fix for this path.
- A later single-game 60 fps Practice sweep in `PERF.md` does not establish two-game GPU headroom, VS
  rollback headroom or two-PC time-sync fairness. The symmetric same-executable run likewise proves only
  that the severe imbalance is not inevitable.

## Next run

Use the maintainer's data-bearing working copy and newly built executable containing these changes.
Do not run this command in the source-only review copy. Keep the first diagnostic run's behavior unchanged:
no priority/affinity tuning, delay override, coalescing change, hash experiment or simulator fix.
The following PowerShell command uses the phase-3 scripted match, sound on and no screenshot/dump output.
Set `$runtimeSource` to the maintainer's PS2Recomp checkout containing `out\net`; this audit did not inspect it.

```powershell
$runtimeSource = Read-Host 'PS2Recomp checkout containing the diagnostic out\net executable'
$v = 'TEKKEN4_RAND_SEED=1;TEKKEN4_RB_INPUT=500:Start,800:Start,960:Down,1020:Down,1080:Cross,1320:Cross,1560:Cross,1800:Cross;TEKKEN4_RB_INPUT2=1320:Cross,1560:Cross,1800:Cross;TEKKEN4_RB_FUZZ=2400;TEKKEN4_RB_FUZZ2=2400;TEKKEN4_SOUND=1;TEKKEN4_NET_LOCALPAD=0;PS2X_PERF_STATS=1;PS2X_PERF_STATS_VU=0;PS2X_PERF_HITCH_MS=34'
$name = 'asym150_diag_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
powershell -ExecutionPolicy Bypass -File tools\net_pair.ps1 -Name $name -Src $runtimeSource -BuildDir net -Rtt 150 -Jitter 5 -Loss 3 -End 12000 -TimingDiag -Env $v
```

Keep each side's `params.txt`, `net.log`, `rb_frames.log`, `stdout.txt`, `stderr.txt` and
`timing_process.log`. Confirm both reached `NETEND`, no peer loss or hash mismatch, and the actual delay is
recorded. Compare the fight from frame 2400 onward separately from boot/loads. Keep the whole timeline:
the first hitch and subsequent seconds matter more than final totals. Observe GPU utilization during the
same run if available. Existing `[perf]` GS queue/worker measurements can implicate renderer backpressure;
they cannot alone distinguish a GPU fence wait from CPU descheduling. Phase 3b's `PS2X_GS_SLOW_LOG` was
optional renderer instrumentation and is absent from the current patch set; silence from an unsupported
switch would prove nothing.

`-TimingDiag` enables `TEKKEN4_NET_DIAG=1` on both peers and samples process metadata about every two seconds.
Without the switch, the added diagnostics are off. Process metadata records UTC, elapsed time, PID,
cumulative CPU time, process priority, affinity, foreground PID, window existence and minimized state.
It also records window visibility (not occlusion). It observes these values and does not change priority,
affinity or focus. Process sampling is too coarse to prove a short thread scheduling delay.

`rb_frames.log` adds a `NETDIAG` line at most once per second at a completed live boundary:

- `steady_ms` is the steady-clock epoch; align the two logs on this PC, not across different PCs.
- `f`, `rc`, `mine`, `peer`, `adv`, `samples`, `hold`: local frame, first missing remote input, current
  local/advertised peer leads, last trimmed estimate, sample count and hold-until frame. `adv` remains the
  last computed value while holding or warming up; it is not a fresh estimate every line.
- `gap_max_ms`, `debt_max_ms`, `sync_over_max_ms`, `wait_max_ms`, `rb_max_ms`: interval maxima for live
  boundary gap, lateness before the guard, correction sleep overshoot, input wait, restore plus resim.
  Rebase/sync/stall/rollback totals are cumulative. Requested and actual cumulative sync time separate
  algorithmic yielding from scheduling overshoot. `wait_rc`/`need` describe the last wait, possibly older
  than the current report interval; `wait_need` is the target contiguous-input count and `wait_rc` shows
  the before/after counts.

`net.log` adds `NETDIAG` roughly once per second and records startup/worker scheduling requests/results:

- `local_age_ms`/`local_gap_ms`: age/max gap of local input sampling; `input_age_ms`/`input_gap_ms`: age/max
  gap of any received INPUT, including resends; `progress_age_ms`: age of contiguous remote-input progress.
- `lead_end`, `lead_end_max`, `lead_back`, `lead_end_age_ms`: last received batch end, its high-water mark,
  batches below that mark in the interval and age since that mark advanced. A batch is capped at 64
  inputs, so this is not necessarily the sender's real frontier. An unchanged/resend batch can carry a
  newly computed lead. These fields suggest reorder/backlog; they do not timestamp lead generation.
- `rx_lock_ms`: maximum receiver wait for the state mutex; `tick_gap_ms`: maximum tick-loop gap
  (normally about 5 ms); `sim_late_ms`, `sim_late_n`, `sim_depth`: maximum due-to-send lateness, count at
  least 2 ms late and approximate peak delayed-send queue. Maxima/counts reset each report; unobserved
  ages are -1. Simulator lateness is separate from the configured outgoing delay.

Existing `[perf]` and `[hitch]` lines are in `stdout.txt`. `PS2X_PERF_STATS=1` remains enabled to exit in
the current patch set; hitch logging starts at 34 ms. EE/worker times are wall time and can include
blocking or descheduling. Keep this instrumentation identical for any A/B comparison.

### What the run must show

Follow the first loss of balance, then test these alternatives against both sides' logs:

| Candidate | Evidence required in the same time window |
|---|---|
| Local renderer/CPU hitch initiates lag | A long live interval and rebase on the slow sender precede the peer's increased input gap, depth, waits and corrections. `[perf]` queue/worker cost or reduced CPU progress supports the local cause; high GPU utilization supports shared-GPU contention. |
| Simulator service adds path delay | Configured due times are missed and queue age/lateness rises before remote-input gaps, without a preceding local live-frame hitch. Separate enqueue delay from actual due-to-send lateness. |
| Estimator is stale or correction ineffective | Lead difference requests a correction; requested/actual wait, hold and subsequent samples show the response. Input/progress ages and smaller received batch ends can suggest stale delivery; lead generation age cannot be measured by this wire format. Separate scheduler overshoot from continued slow-peer hitches. |
| Focus or priority correlates | Foreground/minimized/priority/affinity or requested/effective thread-priority evidence changes before the imbalance. Correlation is a candidate, not proof that focus caused it; two-second harness samples can miss brief changes. |
| Ordinary loss/delay boundary | Input gaps follow path variation with prompt simulator service, comparable local frame cost and the recorded delay. Role and total rollback counts alone are insufficient. |

One run can separate observed timing mechanisms if the imbalance occurs. A balanced diagnostic run does not
reproduce or explain the earlier failure. Repeat the same settings if necessary before drawing a cause claim.
The one-second interval maxima do not establish ordering within that second; use boundary/hitch records
and ages together, and report an unresolved cause where they cannot separate it. Simulator lateness alone
cannot distinguish OS descheduling from the unsafe deque access.

The only behavior fix added is `TEKKEN4_NET_SIM_SAFE_WAIT=1`, default off. It copies the queue deadline while
locked instead of reading a deque element after unlocking. After the unchanged diagnostic run, repeat
the same command with a new unique name and `-Env ($v + ';TEKKEN4_NET_SIM_SAFE_WAIT=1')`. Both peers must use
the switch. This is a controlled simulator A/B, not a time-sync or rendering fix. The safe branch still
yields at Highest priority for up to 1.5 ms and can be scheduled late. One better run does not prove the
unsafe access caused the original failure; require repeated evidence and a real build before enabling it.

## Two physical PCs and release proof

Yes, persistent unequal speed can happen between real PCs: one renderer/CPU can lack headroom, one endpoint
can be throttled or descheduled, a real path can have unequal delay/loss, and each display has its own clock.
The same guard and time-sync policies still apply. Two PCs remove the pair's shared GPU/CPU contention;
with the simulator off they also remove its queue bug and service-thread delay. They do not guarantee
balanced frame costs or independently validate the time-sync estimator.

Required before release claims: a real build; rollback self-test with zero mismatches; the diagnostic pair;
then a two-PC run with sound, independent displays, rendering headroom and the simulator off, recording
delay, depth distribution, live/present intervals, waits, corrections and hashes. The source audit and
default-off diagnostics do not prove a performance improvement or that the reported asymmetry is fixed.
