# Rollback asymmetry: one side falls behind

## 2026-11-02 follow-up: cause and proving run still missing

The supplied verify reports were read from the explicitly requested
`C:\OpenRecomp-work\reports\t4-verify` directory. No other checkout was opened.
The latest report is `away312043`, build `943fc4631acf2c13`, started
2026-10-31T20:43:20. It does not prove a cure:

| Configuration | Rollbacks H/J | Resim frames H/J | Prediction stalls H/J | Stall time H/J, ms |
|---|---|---|---|---|
| OFF | 248/979 | 523/4031 | 0/117 | 0/5421 |
| COALESCE + DIAG | 287/939 | 566/4093 | 0/113 | 0/4745 |

Both configurations reached live/logical 6000, with 199 hash comparisons and
zero mismatches at each endpoint. That supports the compared state, not pacing.
`sun0005-final` also retained join stalls with DIAG OFF and ON (97/116 stalls,
4270/3775 ms). The earlier zero-stall coalesce result did not reproduce in
`away312043`. None of the supplied reports contains the actual NETDIAG records.
There is no exact supplied run that proves the one-sided problem fixed.

Source review found no new demonstrated cause. The existing default-off
`TEKKEN4_NET_REFRESH_RC` corrects stale confirmation after time-sync sleep;
`TEKKEN4_NET_SIM_SAFE_WAIT` corrects the simulator deque-reference lifetime.
Neither can be claimed as the cause or cure from these summaries. Reordered
INPUT lead updates, capture/hash blocking before input publication, lost pacing
time after a hitch, and synchronous DIAG output under the transport mutex remain
possible contributors. INPUT batches contain at most 64 inputs, so their end can
lag the sender's actual frontier. It is not a reliable packet-generation sequence;
filtering it alone would not establish fresh peer lead. No speculative runtime fix
was added under the owner's rule that changed behavior must run through the real
entry point.

### Evidence needed from the next real verify

The external verifier must return its actual run name and build ID, effective
settings from both `params.txt` files, and both peers' full `net.log`,
`rb_frames.log`, stdout/stderr and process timing records. Locate the first local
hitch, input-progress gap, simulator lateness or correction before selecting a
fix. Keep the same DIAG setting and actual negotiated delay for an isolated
fix OFF/ON comparison. A proposed run name is not proof.

Use the real `tools/net_pair.ps1` entry in the maintainer's data-bearing copy.
`-TimingDiag` forces DIAG ON after environment overrides; omit that option and
set DIAG=0 for a diagnostic OFF reference. The GUI launcher scrubs inherited
NET/RB variables, so a shell setting alone does not establish switch activation.
Require both NETEND records at the requested frame, expected nonzero common
hash coverage, zero mismatches/NETDESYNC and no peer loss. Compare both endpoints'
stall duration, depth, correction/rebase time and boundary gaps; a balanced final
FPS window is insufficient. Repeat and swap roles, then check two physical PCs.

Do not accept wrapper exit status as proof: `net_pair.ps1` prints missing logs,
early exits and desync counts without a reliable failing result.
`docs/rollback/net_compare.py` also returns success for zero common hashes.
These are verification gaps, not evidence of a runtime cause; no verifier code
was changed without exercising its real entry point.

No build, launcher, game, network script or real verification was run here.
Existing mocked launcher and catalog tests could not start because Python was
unavailable on PATH; they would not prove real launch or rollback behavior.

The VU1 generator origin and unresolved licence are recorded in
[THIRD_PARTY.md](THIRD_PARTY.md#vu1-generator-trace): GoW `main` at `b76921c`,
not the separately described GPL-3.0 runtime branch. No written grant resolving
the generator licence was found in this repository.

Area agents: `reports`, `net_timing`, `rollback_state`, `diag_trace`,
`verify_entry`, `tests_catalogs`, `vu1_provenance`, `transport_audit`.
All were read-only. Separate reviewer `final_diff_review` checked the final
documentation change; its batch-count wording correction was applied. Runtime
proof remains pending the external verify result.

## Maintainer's 2026-10-31 results and Sunday decision

Evidence: supplied `sun0005-1`, `-coalesce`, `-hello`, `-audio`, `-delay`, `-cost` and `-simsafe`
reports, draft `223c462541`, build ID `2ee2e293baa887af`. These are the maintainer's real-build results,
not runs in this copy. Each pair ran 6000 frames at simulated RTT 150 ms, jitter 5 ms and loss 3%, with
two games sharing one PC and GPU. Compare each switch with its own immediately preceding OFF pair.
The separate OFF pairs are not a stable common baseline. No build, game, pair, simulator, test executable
or patch application was run here.

**The one-sided problem remains, without evidence of a host/join policy defect or a determinism failure.**
The coalesce OFF pair had host/join rollback counts 193/958, resim 247/5008, maximum depth 4/9 and
prediction stalls 0/118 (0/2308 ms). In the delay OFF pair these were 174/956 rollbacks, 373/4435 resim,
depth 9/9, stalls 1/102 (292/3438 ms), and time sync 2/94 (33/5467 ms). The later cost and simsafe OFF
pairs again had join depth 9 and 6211/6746 ms of prediction waiting, versus zero host waits. Yet the
base, diagnostic, hello OFF and audio OFF pairs had zero fight stalls on both sides. Thus the same build
can become badly unequal or remain balanced. A low rollback count on one side is not success by itself.

The side doing more rollback, predicting deeply and yielding via time sync is usually ahead of a slow
input sender; it need not be the side that initiated the slowdown. For example cost OFF had host/join
rebase time 25137/13427 ms while join did 4340 resim frames and 6211 ms of prediction waiting. That is
consistent with lost local headroom and pacing time on the sender, followed by extra work on the peer.
It does not establish which event came first. All pairs still had large live-boundary p99 gaps (about
110-179 ms) and run averages 40.1-48.0 fps despite many final windows near 60 fps. Rebase time, prediction
wait time and requested time-sync time are different measurements; they must not be added as a stall total.
The summary's "displayed frame" samples are live-boundary gaps, not measured GPU presentation intervals.

All 14 supplied pair configurations reached live/logical 6000, reported peer OK, 199 hash comparisons per
endpoint, zero mismatches and zero NETDESYNC lines. The supplied OFF/ON self-tests also had zero bad restores
and zero resim mismatches: base 170 restores/375 comparisons/85 wrong-input passes; coalesce, hello and cost
202/447/101; audio and delay 140/309/70; simsafe 202/447/101. Every wrong-input pass diverged as intended.
This supports the covered state checks. Offline self-tests do not exercise network-only negotiation,
coalescing or simulator waits, and sparse hashes do not prove every frame or audible output correct.

In the table, H/J means host/join; arrows are that case's OFF -> ON. Times are milliseconds.

| Switch | Measured result | Decision |
|---|---|---|
| `TEKKEN4_NET_DIAG` | Run fps 44.7/44.7 -> 44.7/44.7; stalls 0/0 -> 0/0; rebase time 34045/34025 -> 34063/34088; gap p99 121.5/120.8 -> 121.9/120.2. Rollbacks 708/751 -> 643/630, but actual delay changed 2 -> 3. | No demonstrated speed or stall benefit. ON Sunday for timing evidence only; logging overhead is not proved zero. |
| `TEKKEN4_NET_COALESCE` | Packets 20744/20651 -> 10662/10671; payload bytes 3601893/3592294 -> 1847652/1851728, about 48% less on both peers. Resends rose 2668/2417 -> 3499/3590 but total traffic still fell. Join stalls 118/2308 ms -> 0/0, sync 87/5467 ms -> 0/0; resim H/J 247/5008 -> 1417/870. Run fps 45.3/45.4 -> 46.1/46.2; gap p99 117.2/125.6 -> 109.9/111.1. Delay stayed 3. | Clear traffic saving justifies ON. The better stall result is one observation, not a demonstrated cure. Keep an OFF reference on two PCs. |
| `TEKKEN4_NET_STRICT_HELLO` | Run fps 43.9 -> 41.9 both; join depth 4 -> 9, stalls 0 -> 1/13 ms, sync 1/17 ms -> 62/2133 ms; gap p99 H/J 131.3/132.6 -> 140.7/139.5. Delay stayed 3. | Observed worse pacing; OFF. Startup validation has separate purposes and is not a measured pacing fix. |
| `TEKKEN4_RB_AUDIO_TIMELINE` | Run fps 43.3 -> 40.1 both; gap p99 128.0/133.3 -> 155.5/153.8; rebase time 38542/38494 -> 49489/49531. Stalls stayed zero both. Delay stayed 3. | Observed slower, no stall benefit; OFF. One AUDIO_TIMELINE activation line and clean hashes do not validate sound quality or repeated-frame sample suppression. |
| `TEKKEN4_NET_DELAY_MATCH` | Both used delay 3. Join stalls 102/3438 ms -> 153/5188 ms, depth stayed 9, rollback p90 46.96 -> 51.44. Run fps 45.6/45.7 -> 47.3/47.3 and join gap p90 34.2 -> 26.4 improved; host gap p99 126.4 -> 141.4 worsened. | Mixed throughput, worse one-sided wait time (about 51%); OFF. Negotiation did not produce a different delay here. |
| `TEKKEN4_NET_COST_PROFILE` | Run fps 47.9/48.0 -> 47.8/47.8; join stalls 140/6211 ms -> 166/7967 ms, depth stayed 9, resim 4340 -> 4338, rollback p90 49.94 -> 51.61. Delay changed 3 -> 2. | No benefit; OFF except a separate component-cost investigation. No NETCOST records were supplied, so these summaries cannot identify the costly component. |
| `TEKKEN4_NET_SIM_SAFE_WAIT` | Run fps 47.9/47.9 -> 47.9/48.0; join stalls 152/6746 ms -> 131/6772 ms, depth stayed 9, sync 94/3767 ms -> 97/4900 ms. Host rollback p90 21.21 -> 12.59 improved but gap p99 168.3 -> 179.3 worsened. Delay changed 2 -> 3. | Fixes a source-level lifetime bug when enabled; no measured cure for the wait duration. OFF for Sunday with no simulator, where it has no effect. |

These are sequential, single comparisons with no repeat variance or raw event timeline. Even with the same
simulator seeds, changed send histories change random loss/jitter draws and arrival ordering. Auto delay
also crossed 2/3 in three comparisons. The summaries support "observed worse", "no measured gain" and
the direct traffic reduction; they cannot assign every difference to the switch. The detailed diagnostic
records described below were not supplied, so the initiating hitch, simulator lateness, scheduling
overshoot and stale estimator alternatives remain unresolved. Do not tune time-sync thresholds, remove
the pacing guard, raise prediction limits or force a delay on this evidence.

### Small source fix, default off

`TEKKEN4_NET_REFRESH_RC=1` now refreshes contiguous remote input immediately before the prediction-window
check and late rollback scan. Previously `rc` could still be the value from before `npTimeSync` slept.
Inputs arriving during that sleep could make `waitRemote` return immediately while still incrementing
the stall counter; the late scan could also use old confirmation progress. The guarded read uses the
transport mutex and the existing monotonic frontier. It changes no time-sync thresholds, wire format,
prediction cap, snapshot data or hash coverage. Unset/0 retains the old path.

This is a stale-read/accounting correction, not an explanation for seconds of measured waiting. It has
no supplied A/B or build result; leave it OFF Sunday. The existing default-off `SIM_SAFE_WAIT` correction
already copies the deque deadline while locked. The audio timeline correction is also already present
behind its own default-off switch. No patch files were changed. A maintainer build and an isolated
REFRESH_RC OFF/ON pair must check a correction sleep with inputs arriving during it, zero mismatches,
the wait counter/duration and prompt late rollback. It must also check ordinary waits still enforce the
same prediction limit and OFF preserves the old behavior. Do not claim a stall fix from this source audit.

### Exact Sunday settings: two physical PCs

Use the same maintainer-reviewed build on both PCs, independent displays and sound on. Close competing
games/builds and choose graphics settings with local rendering headroom. Use a real direct or VPN path,
recording direct/relay status. No simulated latency/jitter/loss. Two PCs remove the shared GPU/CPU
contention, and simulator OFF removes its queue/service-thread effects; unequal PCs, clocks, real paths
and endpoint throttling can still produce asymmetry. This evidence says nothing yet about those cases.

On BOTH PCs, in the PowerShell session used to start `tools/net_play.ps1`:

```powershell
$env:TEKKEN4_NET_COALESCE = '1'
$env:TEKKEN4_NET_DIAG = '1'
$env:TEKKEN4_NET_STRICT_HELLO = '0'
$env:TEKKEN4_RB_AUDIO_TIMELINE = '0'
$env:TEKKEN4_NET_DELAY_MATCH = '0'
$env:TEKKEN4_NET_COST_PROFILE = '0'
$env:TEKKEN4_NET_HASH_PROFILE = '0'
$env:TEKKEN4_NET_SIM_SAFE_WAIT = '0'
$env:TEKKEN4_NET_REFRESH_RC = '0'
$env:TEKKEN4_NET_SIM = ''
$env:TEKKEN4_NET_DELAY = 'auto'
$env:TEKKEN4_NET_TIMESYNC = '1'
$env:TEKKEN4_NET_MAXPRED = '8'
$env:TEKKEN4_NET_EARLY = '1'
$env:TEKKEN4_NET_LAZY = '1'
$env:TEKKEN4_NET_LOCALPAD = '1'
$env:TEKKEN4_SOUND = '1'
```

Use a fresh shell without scripted inputs/fuzz, fixed seed, end-frame, screenshot/dump or priority/affinity
experiments. After these settings, use the host/join commands in `TEST_ONLINE_DE.txt` with
`-Delay auto -Sound 1` and no `-Sim` or `-NoDiagnostics`. Empty SIM is explicit because omitting `-Sim` does not clear an
inherited simulator setting. Keep early timing, lockstep delay and other unlisted controls at defaults.
DIAG is an observation exception, supported by the base comparison's unchanged aggregate pace; it is not
a speed switch. COALESCE is the only behavior experiment recommended ON by these measurements. Code
defaults remain OFF for all experimental switches.

After the main sound-on session, restart BOTH games with only COALESCE changed to '0', using the same
route, graphics, stage/characters and similar duration; keep DIAG on for both runs. Keep each run's logs
separate and record actual negotiated delay (do not force 3 just because most simulated pairs picked it).
Compare both sides' depth distribution, rollback cost, prediction waits/duration, corrections, rebases,
boundary gaps, payload traffic and hashes. Note stutter/audio timestamps and whether symptoms follow the
PC after swapping host/join in another cold session. Retain net.log, rb_frames.log, stdout/stderr and
the guide's collected PC/build facts. Cross-PC steady-clock epochs cannot be aligned directly; record
UTC/time zones and game-frame context. A smooth final FPS window alone is insufficient.

The supplied successful builds apply to draft `223c462541`, not this edited source. A real build and
sound-on rollback self-test with zero mismatches remain necessary before using the new source. Two-PC
menu/Versus/rematch, audio and direct/relay runs must establish compatibility and pacing. Nothing here
proves that the one-sided stalls are fixed or that release acceptance is complete.

## Earlier source audit (2026-10-30)

The following ranked causes and diagnostic protocol are retained for investigation. The Sunday settings
above supersede the old next-run recommendation.
The reported 150 ms pair had about 3.5 times as many rollbacks on one side, depth 9, 80-96 prediction-window
waits (about 3 s) and about 90 time syncs. Another run of the same executable was nearly symmetric
(632/589 rollbacks, depth 5/3, no waits). These totals do not identify the initiating side or cause.
The original source audit did not evaluate coalescing or hash cost. The new measurements above cover
coalescing and the cost-profile A/B; they do not isolate hash cost.

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

## Earlier same-PC diagnostic protocol

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

The behavior fix added in the earlier audit was `TEKKEN4_NET_SIM_SAFE_WAIT=1`, default off. It copies the queue deadline while
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
