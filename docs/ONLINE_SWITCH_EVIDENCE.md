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
| `TEKKEN4_NET_AUTO_VS` | `0` | No supplied passing enabled AUTO_VS pair. |
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

Draft `323f76204d`, merge base `8b15202341` (branch base `7992837fc3`),
onto `us-slus20328` at `c17fd979ca`; clean merge; build OK in 165 seconds,
build ID `943fc4631acf2c13`. Finished `2026-11-02T08:45:55`.
This supersedes the earlier supplied verification summaries.

- Selftest, switches OFF: 6000 wall / 5106 logical frames, 202 successful
  restores, zero bad restores, 447 resim comparisons with zero mismatches;
  all 101 deliberate wrong-input passes diverged. Save average/maximum was
  0.21/4.56 ms; restore average/maximum was 0.29/0.41 ms.
- Same-PC pair, switches OFF: RTT target 150 ms, jitter 5 ms, loss 3%, both
  endpoints reached live/logical 6000, 199 hash comparisons per endpoint,
  zero mismatches, zero NETDESYNC lines and peer OK.
- Host/join rollbacks 920/214, resim frames 4849/332, maximum depth 9/3;
  prediction stalls 209/0 (4757/0 ms), time sync 72/1 (4433/17 ms).
  Run-average FPS 43.6/43.6; final FPS windows 59.5/59.9 do not erase the
  remaining pacing gaps. Displayed-boundary p99 was 129.8/126.7 ms.
  Restore-and-resim p50 was 32.95/8.91 ms, p90 54.14/12.20 ms and maximum
  131.32/116.99 ms.
  Rebases were 341/442 (28392/37583 ms).
  Coalesced packets were zero on both endpoints.

Run-average FPS fell from the preceding supplied 52.3/52.3 to 43.6/43.6,
and displayed-frame p99 rose from 107.9/97.7 to 129.8/126.7 ms. This is an
observed pacing regression between reports; the summaries do not establish
its cause or a controlled comparison. Clean state checks do not resolve it.

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
