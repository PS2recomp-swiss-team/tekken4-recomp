# Online switch evidence, 2026-11-02

The latest supplied pair proves covered rollback state checks for its reported
switches-off configuration on one PC. It does not prove this source tree, the
launcher's effective profile, two physical PCs or shared-server online play.
No switch was changed here. Builds, games and `tools/net_*` execution are
forbidden in this copy by [AGENTS.md](../AGENTS.md).

## Actual Host/Join path in this source

The standalone [launcher](../launcher/t4_launcher.pyw) calls `core.OnlineRun`.
In [t4core.py](../launcher/t4core.py), `online_command` (line 609) selects the
local runtime and calls [net_play.ps1](../tools/net_play.ps1) with mandatory
identity/UDP preflight, `-Delay auto` and `-Sound 1`. `OnlineRun.start` calls
`game_env` (line 502), which removes inherited `TEKKEN4_NET*`, `TEKKEN4_RB_*`
and `TEKKEN4_RAND_SEED` settings before starting that helper.

The helper's default profile (lines 82-114) therefore supplies these values
for ordinary GUI Host/Join:

| Setting | Effective value from source | Latest supplied pair coverage |
|---|---|---|
| `TEKKEN4_NET_COALESCE` | `1` | Reported switches OFF, `coalesced 0`; this enabled launcher setting is unproved by that pair. |
| `TEKKEN4_NET_DIAG` | `1` | Reported switches OFF; this enabled launcher setting is unproved by that pair. |
| `TEKKEN4_NET_STRICT_HELLO`, `TEKKEN4_NET_DELAY_MATCH` | `0` | Covered only as part of the reported OFF configuration; no enabled-policy proof. |
| `TEKKEN4_RB_AUDIO_TIMELINE` | `0` | Covered only as part of the reported OFF configuration; audible correctness is unproved. |
| `TEKKEN4_NET_COST_PROFILE`, `TEKKEN4_NET_HASH_PROFILE` | `0` | Covered only as part of the reported OFF configuration; no enabled instrumentation proof. |
| `TEKKEN4_NET_SIM_SAFE_WAIT`, `TEKKEN4_NET_REFRESH_RC` | `0` | Covered only as part of the reported OFF configuration; no enabled-fix proof. |
| `TEKKEN4_NET_AUTO_VS` | `1` (since 2026-11-04) | 13 passing state-driven pairs, docs/DIRECTFIGHT_T4.md "Online boot". |
| `TEKKEN4_NET_TIMESYNC`, `TEKKEN4_NET_EARLY`, `TEKKEN4_NET_LAZY`, `TEKKEN4_NET_LOCALPAD` | `1` | Baseline settings, separate from experimental switches OFF. The supplied summary records time sync, early rollbacks and lazy captures, but is not the complete effective environment. |
| `TEKKEN4_NET_MAXPRED` | `8` | Source profile; require both actual parameter/activation records to establish the measured value. |
| `TEKKEN4_NET_DELAY`, `TEKKEN4_SOUND` | `auto`, `1` | Pair summary reports actual delay `3`; sound quality was not reported. |
| simulator, fixed seed, forced end, shots/dumps, rollback harness overrides | cleared | Latest pair used a simulator; ordinary GUI Host/Join is a different route. |

Setting COALESCE or DIAG to `0` in the shell launching the GUI does not establish
an OFF comparison: `game_env` removes it. The helper supports explicit OFF
settings when invoked directly, but that does not test the GUI path. Its
`-UseInheritedProfile` is an experiment option, not an acceptance profile.

[net_preflight.ps1](../tools/net_preflight.ps1) compares build, compiler, ISO,
ELF, net version, strict-hello and delay-policy identities. It does not compare
every switch above. A successful probe does not establish game startup or a
successful match. An exit-zero helper only tells the GUI to consult the log.

The [game wire header](../runtime/tekken4_net.h) uses base version `1`, strict
version `2`, delay-policy version `3`, their combination `4`, and an AUTO_VS
offset of `4`. These game-wire policies are distinct from the lobby protocol
version. The [transport](../runtime/tekken4_net.cpp) enables strict hello,
coalescing, diagnostics and simulator safe wait only for value `1`.

## Latest owner-supplied real verification

Draft `b13f80b4da`, merge base `8b15202341` (branch base `7992837fc3`),
onto `us-slus20328` at `c17fd979ca`; clean merge; build OK in 188 seconds,
build ID `943fc4631acf2c13`. Finished `2026-11-02T14:27:59`.
This supersedes the earlier supplied verification summaries retained below.

- Selftest, switches OFF: 6000 wall / 5106 logical frames, 202 successful
  restores, zero bad restores, 447 resim comparisons with zero mismatches;
  all 101 deliberate wrong-input passes diverged. Save average/maximum was
  0.20/4.86 ms; restore average/maximum was 0.28/0.50 ms.
- Same-PC pair, switches OFF: RTT target 150 ms, jitter 5 ms, loss 3%, both
  endpoints reached live/logical 6000, 199 hash comparisons per endpoint,
  zero mismatches, zero NETDESYNC lines and peer OK. Measured RTT was
  149/148 ms (host/join), with 32 samples and delay 3 on both endpoints.

| Pair measurement | Host | Join |
|---|---:|---:|
| Final FPS window / run average | 59.4 / 48.1 | 59.8 / 48.1 |
| Rollbacks / resim frames / maximum depth | 209 / 299 / 5 | 989 / 4382 / 9 |
| Depth counts, in depth order | 1:153, 2:31, 3:17, 4:7, 5:1 | 1:74, 2:177, 3:200, 4:123, 5:84, 6:139, 7:40, 8:40, 9:112 |
| Frames on predicted input / mispredicted | 2495 / 209 | 8174 / 989 |
| Restore-and-resim p50 / p90 / maximum, ms | 5.71 / 15.72 / 200.68 | 22.94 / 50.72 / 62.93 |
| Stalls / total ms | 0 / 0 | 136 / 5629 |
| Time sync / total ms | 0 / 0 | 93 / 5317 |
| Rebases / total ms | 224 / 24691 | 182 / 13757 |
| Displayed-frame p50 / p90 / p99, ms | 16.7 / 17.9 / 161.6 | 16.7 / 28.3 / 117.1 |
| Packets out / in / simulator-dropped | 19923 / 19426 / 589 | 20007 / 19314 / 571 |
| Resends / coalesced | 1855 / 0 | 1576 / 0 |
| Payload bytes out / in | 3488400 / 3404585 | 3505828 / 3381674 |
| Capture / restore / hash average, ms | 0.42 / 0.45 / 3.92 | 0.40 / 0.47 / 3.92 |
| Lockstep waits / total ms / lock delay | 1 / 74 / 7 | 0 / 0 / 7 |
| Early rollbacks / vblank wait ms | 206 / 10572 | 874 / 8839 |
| Lazy captures skipped | 55 | 426 |
| Frames over 20 ms / over 34 ms, of 5401 | 449 / 341 | 825 / 456 |
| RDRAM pages per capture / restore | 186 / 145 | 181 / 166 |

Against the preceding supplied report (`294b927b6f`), run-average FPS rose
from 47.8 to 48.1 on both sides. Displayed-frame p99 fell from 166.1/120.5
to 161.6/117.1 ms. Join stalls fell from 139 to 136, while total stall time
rose from 5619 to 5629 ms. Restore-and-resim maximum changed from
110.51/66.70 to 200.68/62.93 ms: host rose, join fell. Actual delay remained
3 on both endpoints. These summaries are not a controlled comparison and
do not establish a cause. Clean state checks do not establish usable pacing.

This is supplied evidence, not a run performed here. Full effective parameter
records and raw logs were not supplied in this prompt. "Switches OFF" must not
be expanded into a claim that baseline time sync, early rollback or lazy capture
were disabled. The latest report proves no newly enabled experimental switch,
actual App startup, enabled GUI profile or two-PC play. A pair on one PC does
not replace two physical PCs.

## Previous supplied verification 294b927b6f

Draft `294b927b6f`, merge base `8b15202341` (branch base `7992837fc3`),
onto `us-slus20328` at `c17fd979ca`; clean merge; build OK in 185 seconds,
build ID `943fc4631acf2c13`. Finished `2026-11-02T13:53:59`.
This supersedes the earlier supplied verification summaries.

- Selftest, switches OFF: 6000 wall / 5106 logical frames, 202 successful
  restores, zero bad restores, 447 resim comparisons with zero mismatches;
  all 101 deliberate wrong-input passes diverged. Save average/maximum was
  0.21/4.44 ms; restore average/maximum was 0.29/0.49 ms.
- Same-PC pair, switches OFF: RTT target 150 ms, jitter 5 ms, loss 3%, both
  endpoints reached live/logical 6000, 199 hash comparisons per endpoint,
  zero mismatches, zero NETDESYNC lines and peer OK. Measured RTT was
  149/149 ms (host/join), with delay 3 on both endpoints.
- Host/join rollbacks 201/992, resim frames 275/4322, maximum depth 5/9;
  prediction stalls 0/139 (0/5619 ms), time sync 0/97 (0/5150 ms).
  Run-average FPS 47.8/47.8; final FPS windows 59.3/59.9 do not erase the
  remaining pacing gaps. Displayed-frame p50 was 16.7/16.7 ms, p90
  17.8/27.8 ms and p99 166.1/120.5 ms.
  Restore-and-resim p50 was 5.69/22.41 ms, p90 13.62/50.72 ms and maximum
  110.51/66.70 ms.
  Rebases were 234/189 (25443/14684 ms).
  Coalesced packets were zero on both endpoints.

Host run-average FPS stayed at 47.8; join fell from 47.9 in the preceding
supplied report (`d1a2bb15db`) to 47.8. Displayed-frame p99 fell from
174.8/126.0 to 166.1/120.5 ms on both sides. Join stalls rose from
130 to 139, while total stall time fell from 6593 to 5619 ms. Restore-and-resim
maximum changed from 255.16/63.22 to 110.51/66.70 ms: host fell, join rose.
Actual delay remained 3 on both endpoints. These summaries are not a controlled comparison
and do not establish a cause. Clean state checks do not establish usable pacing.

This is supplied evidence, not a run performed here. Full effective parameter
records and raw logs were not supplied in this prompt. "Switches OFF" must not
be expanded into a claim that baseline time sync, early rollback or lazy capture
were disabled. The latest report proves no newly enabled experimental switch.

Earlier supplied ON/OFF comparisons in
[ROLLBACK_ASYMMETRY.md](ROLLBACK_ASYMMETRY.md) remain historical evidence:
COALESCE reduced traffic, but its apparent stall cure did not reproduce. Those
runs are not proof that the current launcher started or that its full profile
passed. The older recommendation to enable COALESCE and DIAG still describes
the helper's source behavior; it is not a new acceptance result.

## Owner-only proof still required

Use the authorized data-bearing checkout to build the exact reviewed source.
Start the actual complete launcher, exercise both Host and Join, and capture
the effective environment and activation records from each resulting game.
Require expected nonzero common hash coverage, completed target frames, peer
OK, zero mismatches and zero NETDESYNC; wrapper success alone is insufficient.

Record the actual launcher version, build ID, negotiated delay, switch values,
roles and route with both peers' logs. Compare the candidate's exact enabled
profile with its OFF reference without assuming inherited GUI settings survive.
Repeat after swapping roles, then use two physical PCs with sound and human
play, rematch and disconnect recovery. Shared-server login/match/relay tests
also need the private launcher/server sources and owner coordination.

Source-only entry checks passed: `tools/test_online_readiness.ps1` (three
subprocess cases), `tools/check_online_catalogs.ps1`, and
`tools/test_launcher_entry.ps1`. The last ran real `Tekken4.cmd`, which refused
missing private Python as expected. No Python suite, GUI, network helper,
preflight UDP exchange, build, selftest, pair or game ran here. These source
checks and the starter refusal cannot close the runtime requirements.
