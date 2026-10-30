# Rollback phase 2: fast re-simulation, sound across rollbacks, local two-player harness

Status 2026-10-29. Plan: `docs/ROLLBACK_PLAN.md` (phase 2), phases 0/1: `docs/ROLLBACK_PHASE01.md`. T5DR reference:
`docs/ROLLBACK.md` of T5DR Online ("T5 §n").

Summary (numbers below, evidence in `logs/rb/<run>`):

| | phase 1 | phase 2 |
|---|---|---|
| re-simulated frame, EE thread (`ee`, p50, Story fight) | 16.0 ms (= a live frame) | **5.2 ms** (p90 5.6); last frame of a pass (draws) 16.7 |
| 8-frame rollback (restore + 8 frames, p50) | ~129 ms | **54 ms** |
| self-test, sound off (`p2c`) | 0 / 1000 | **0 mismatches / 375** re-simulated frames, 170 rollbacks |
| self-test, sound on (`s2a`, `s2wav`) | 64 / 447 | **0 / 375**; WAV of the run with rollbacks bit-identical to a run without (85 s) |
| live frames of a rollback run vs a run without rollbacks | - | identical hashes at every frame (sound off 4845, sound on 5074) |
| selfnet, sound off (pad 2 remote, delay 4 + jitter 0..2, `vsnet2`) | - | **0 differing frames of 23 341** vs the on-time reference; 6524 rollbacks (depth 4-6), 31 810 re-simulated frames, several full VS matches |
| selfnet, sound on (`vssnet`) | - | game memory identical, but the sound page 0x1cca000 and the EE cycle (+8) differ from frame 2665 on (open, section 2) |

## What changed

PS2Recomp worktree `D:\tekken4-fork-rb`, branch `t4-rollback` (on top of t4-us = patches 01-36):

| commit | content |
|---|---|
| `0dc98d9` | phase 0/1: boundary hook, snapshot/restore, hash, pad provider (unchanged) |
| `fe83d7b` | `ps2_rollback_cuts.h`: re-simulation cuts (GS draw, GS upload, presenter, IOP freeze) and the IOP gate |
| `f06e269`, `e0eff21`, `ce2cf51`, `a79a3df` | cherry-picks of t4-us patches 33-36 (music: SIF send-cmd to the IOP, SPU2 IRQ, debug aids, cdvd/ioman in the ISO) |
| `0e3664b` | `sceSifSendCmd`'s DMA-id counter in the snapshot and hash; no EE->IOP SIF command while the IOP is frozen |
| `d5b233e` | VU1 cut, idle-loop skipping in the scheduler, host profile counters |

The four rollback commits are exported as `docs/rollback/patches/37..40-*.patch` (checked: t4-us 70580f0 + 37..40 gives
exactly the tree of `d5b233e`); move them to `patches/` to make them part of the normal build.

Driver `runtime/rollback/tekken4_rollback_overrides.cpp` (header lists every switch): cut selection
(`TEKKEN4_RB_CUT`, default `draw,iop,present,vu1`, `TEKKEN4_RB_CUT_TAIL`), the IOP gate (log on live frames, replay
when frozen, `TEKKEN4_RB_SND`, `TEKKEN4_RB_SNDTRACE`), the idle loop (`TEKKEN4_RB_IDLE`), pad 2 (`TEKKEN4_RB_PAD2`,
`TEKKEN4_RB_INPUT2`, `TEKKEN4_RB_FUZZ2`), `TEKKEN4_RB_MODE=selfnet` (`TEKKEN4_RB_NET`), per-frame cost columns
(`gs vif vu iop idle cut`) and `COST`/`PASSCOST`/`IOP`/`NETSUMMARY` lines in `rb_frames.log`.
`docs/rollback/rb_compare.py --last` compares the final run of each frame (selfnet).

With `TEKKEN4_RB_MODE` unset nothing is installed: no cut is ever set (one relaxed atomic load per GS kick / VIF
packet / IOP advance), no gate (null pointer test), no idle pcs (empty vector test), profiling off. Checked: `logs/rb/plain2` (no TEKKEN4_RB_MODE, keys as phase 1,
`TEKKEN4_PERF_LOG`): Story fight at 60 frames in every second 55..68, no `[rollback]` line.

## 1. Fast re-simulation

### Where the time of a re-simulated frame went (phase 1: same as a live frame)

Per-frame host time on the EE thread, `p2b` (draw cut only, profile on), Story fight, p50:

| | live frame (`1`) | re-simulated, draw cut (`R`) |
|---|---|---|
| total `ee` | 23.0 ms (profiling overhead incl.) | 11.6 ms |
| VIF1 processing (incl. VU1 and the GS packets it feeds) | 12.1 | 6.3 |
| VU1 microprograms (MSCAL, native VU1 + its XGKICK) | 10.6 | 5.4 |
| GS packet processing on the EE thread | 6.1 | 0.8 |

A stack profile (`p2prof`, `TEKKEN4_STACKPROF`) of the same mix: 17 % of the EE thread waits in
`GSThreadedBackend::PublishLocked` (GS worker ring full: live frames), VU1 native blocks + `VU1Interpreter` timing
~15 %, `processVIF1Data` 4 %, EE timers (`applyEeTimerTicks` per checkpoint) 3 %, game code spread over many
`FUN_*`; the main thread's vsync wait `FUN_0022a140` (0x22a150: `while (*(u8*)0x1ccafb7 == 1)`) and the timer
work it causes ~3-4 %.

### The cuts (`ps2_rollback::Cut`, set by the driver for the frames of a W/R pass or a selfnet rollback)

- **draw**: `GS::vertexKick` does not build/submit the primitive batch. Registers (incl. CSR SIGNAL/FINISH/LABEL,
  DISPFB), transfers and local->host readbacks still run, so every GS effect the EE can see is unchanged.
- **iop**: the IOP is not advanced (`advanceIopEeCycles`), RPCs and EE->IOP writes go to the gate (section 2).
- **present**: the presenter does not latch a new picture on a vsync tick while re-simulating.
- **vu1**: MSCAL does not run the VU1 microprogram. What VU1 can change: VU1 data memory, its own registers,
  VPU-STAT D/T bits (0 here), and the GS through XGKICK (PATH1). It cannot write RDRAM, scratchpad, DMA/VIF
  registers or the scheduler. So with vu1 cut the VU1 data memory becomes output state and is left out of the hash
  (`HostProfile::hashVu1Data`, default when vu1 is cut). Evidence that nothing the EE reads depends on it: (a) `p2vu`
  and `p2c`, 0 mismatches of RDRAM + scratchpad + VU0 + scheduler + all device registers (incl. GS privileged
  registers, i.e. no SIGNAL/FINISH lost) in 375 re-simulated frames each; (b) `p2c` (170 rollbacks with all cuts)
  vs `mref0` (no rollback): RDRAM hash identical at every one of 4845 frames, also in the live frames after each
  rollback, where the VU1 memory left by the cut frames is used again.
- **upload** (off by default): host->local image data dropped; measured cost of uploads in a cut frame is below
  0.1 ms, not worth the risk.
- **tail** (`TEKKEN4_RB_CUT_TAIL=1`): the last re-simulated frame runs with draw and VU1 (T5's cut tail): the game
  flips to the picture drawn in the previous frame, so the first live frame after a rollback shows the corrected
  timeline. Without it the mispredicted picture would stay one frame.

### Idle loop

70 % of a fight frame's EE cycles (3.4 of 4.9 M, column `idle`) are the vsync wait at 0x22a150 (one iteration = a
32-cycle checkpoint, ~100 k iterations per frame). `EeScheduler::setIdleLoopPcs` lets the driver register it:
when a backward-edge checkpoint is at that pc (no interrupt handler running, nothing pending), all iterations up to
just before the next deadline / EE timer interrupt / slice end are accounted in one `accountCycles`. Result:
`p2c` vs `mref0` (`TEKKEN4_RB_IDLE=0`): RDRAM identical at all frames; the boundary EE cycle differs by up to
24 cycles at some frames (the loop's real per-iteration cost is not exactly the 32-cycle checkpoint), so
scheduler/timer digests differ from the idle-off mode. That is only a difference between two modes; within the
rollback modes (always idle on, both peers alike) it is deterministic. It saved only ~0.5 ms per re-simulated frame
(the loop was already cheap), and nothing measurable on live frames.

### Result

| run | cuts | `R` p50 / p90 | tail frame | 8-frame rollback p50 (restore + frames) |
|---|---|---|---|---|
| `final` (phase 1) | none | 16.0 / 19.3 | - | ~129 ms |
| `p2a` | draw, iop, present | 10.9 / 12.7 | 15.3 | 93.0 |
| `p2vu` | + vu1 | 5.7 / 6.1 | 17.2 | 58.0 |
| `p2c` | + vu1, idle skip | **5.2 / 5.6** | 16.7 | **53.8** (1: 16.6, 2: 23.2, 4: 34.0) |

Target "an 8-frame rollback well under 16.7 ms on top of the live frame" is **not reached**. Best: 5.2 ms per cut
frame, i.e. ~7 frames of a 8-frame pass cost 36 ms, the tail ~17 ms. What dominates now:
- **The game's own EE code**: ~4.3 ms for the ~1.5 M non-idle guest cycles of a fight frame (VIF1 0.7, GS register
  work 0.07, VU1 0). Cutting further means T5-style game-level draw cuts (the EE builds the VIF/GIF packets itself:
  matrix/skinning work in FUN_* code); unlike the GS/VU1 cuts these change RDRAM (packet buffers), so they need a
  gameplay hash instead of the full hash (T5 §6). Not done.
- **The tail frame** (a full frame with VU1 and GS, 16.7 ms).
- **The live frame itself**: 13 ms in the Story fight, ~30 ms on the VS stage "Underground" (`vsref`: the port runs
  that stage at ~33 fps without any rollback; GS worker back-pressure and VU1). With 13 ms live, 3.7 ms per frame
  are free: one cut frame. So any rollback costs at least one late frame until the live frame gets cheaper; T5's
  early rollback (T5 §27) has an idle window here too (the vsync wait = 70 % of the guest frame) but on the host
  that window is only the 3.7 ms left after the live work.

## 2. Sound in re-simulation (`TEKKEN4_SOUND=1`)

As T5 does (T5 §8, §20): the IOP (R3000, IOP RAM, zsiopdrv, SPU2) stays outside the rollback state and only runs on
live frames; what it does to the EE is logged per frame and replayed while re-simulating.

**Every path from the IOP to the EE** goes through `PS2IopHostAdapter` (`writeGuest`, `zeroGuest`,
`sendSifCommand`) or comes back from a synchronous RPC (`PS2Runtime::handleIopRpc`: the server function runs inside
the call and its reply is copied into EE RAM before it returns). The gate (`ps2_rollback::IopGate`, driver class
`Gate`) records on live frames: per RPC (in call order within the frame) sid, function, the send buffer, every
effect inside the call, and the `RpcResult`; effects outside a call ("async", e.g. the IOP's SIF commands to the EE)
with the EE cycle they happened at. Frozen (CutIop): `advanceIopEeCycles` replays the frame's async effects whose
cycle is reached; an RPC is answered from the record of the same frame and index (effects written, result
returned) without reaching the IOP; EE->IOP memory writes (`sceSifSetDma`, `sceSifSendCmd` payload) and EE->IOP SIF
commands are dropped (the live run sent them).

**Duplicate sounds**: none by construction: the IOP sees each live frame's command queue once. When the
re-simulated call's send buffer differs from the logged one (`D` lines in `rb_sound.log`: a corrected timeline),
the default `TEKKEN4_RB_SND=replay` writes the logged reply and sends nothing (a sound only the corrected timeline
has is missed if it starts in a re-simulated frame); `forward` sends it to the IOP (late start, but the queue is a
per-frame stream of parameter updates + starts, so forwarding a whole queue repeats the updates and starts that
were already sent). Per-command dedupe needs the queue format (below), phase 5.

**RPC 0x100 queue** (`rb_sound.log`, `s2a`): 128 bytes from 0x1cca040, a byte stream of commands `a0 <op> <args>`
(op 01: two 16-bit words, op 03: one 32-bit word, op 05: two 16-bit words then `f0`, ...), the same ~80 bytes every
frame with changing 16-bit values (positions/levels); replies 8 words at 0x1cca000 (word 2 low half changes per
frame, e.g. 0x01e7, 0x000d). Other calls in a fight: none; 0x200 (bank loads, 5 in the run), 0x2100 and 0x8000
at boot. Async IOP effects: 16 SIF commands in the whole run (boot and loads), none in fights.

**Fix found on the way**: `sceSifSendCmd` (new in patch 33) returned ids from a function-static counter: a
re-simulated frame got other ids than its live run. Now saved/restored/hashed (`0e3664b`).

Results:
- `s2a` (sound on, mispredict=1, 170 rollbacks): **0 mismatches in 375 re-simulated frames**, restores 170/170; IOP:
  4485 live RPCs, frozen: 737 replayed identical, 13 differed (all in wrong-input passes), 0 forwarded, 4 async
  replayed, 4 EE->IOP writes dropped.
- `s2wav` vs `s2ref` (same script with and without rollbacks, `TEKKEN4_SOUND_WAV`): live-frame hashes identical at
  all 5074 frames, and **the two WAVs are bit-identical** over their common 85 s (4 079 278 stereo frames, sound
  present: 21 844 of the probed samples non-zero) -- no doubled, missed or shifted sound.

Open (phase 3/5): the reply words written into EE RAM depend on the IOP's history. Two peers whose IOPs heard
different live command streams (one predicted wrong, the other not) can get different replies, and phase 1 saw a
reply difference reach game memory (0x357f98). The self-test cannot see this (it replays its own live run); selfnet
with sound on against a reference does (below). Fix options: find which reply words the game reads into match
state and make them a function of EE state (T5 §20 writes the first run's handle back), or exchange/mask them.

## 3. Local two-player harness (`TEKKEN4_RB_MODE=selfnet`)

Pad 2 is the remote player: its scripted input (`TEKKEN4_RB_INPUT2`, `TEKKEN4_RB_FUZZ2`) reaches the simulation late.
At every live boundary f, frames up to f - delay - jitter(f) become known (never more than `max` behind); a frame
not known yet uses the last known input (prediction = repeat, T5's rule). When a revealed frame's input differs from
what its run used, the machine is restored to the snapshot of that frame's boundary (a full snapshot is taken at
every boundary, ring of max+jitter+2) and frames are re-simulated with the corrected inputs (cuts on, tail drawn)
up to f, then the live frame runs. Each frame's LAST line in `rb_frames.log` is its final run; `rb_compare.py --last`
compares them with a `measure` run that has the true pad 2 input on time (`TEKKEN4_RB_PAD2=1`).

Pad 2 connection: the runtime reports port 2 through the pad provider (`hostControllerConnected` ->
provider(port 1) returns true), so VS BATTLE is selectable and both pads pick (`vs1`, `vs2`: mode select with
VS BATTLE enabled, Kazuya vs Paul, stage Underground).

Results:

| run | what | result |
|---|---|---|
| `vsnet2` vs `vsref2` | sound off, VS BATTLE (Kazuya vs Paul, Underground, then the fuzz input's own rematch picks: other stages, Kazuya vs Kazuya), `delay=4,jitter=2,max=8`, prediction from frame 2350, both pads fuzzed from 2400 | **0 differing frames of 23 341** compared (`--last`; selfnet reached 24 669, the reference 23 341); 6524 rollbacks of depth 4 (2218), 5 (2893), 6 (1413); 31 810 re-simulated frames; 9397 of 22 236 revealed remote frames mispredicted; snapshot 1.17 ms, restore 1.22 ms, rollback cost (restore + re-simulated frames) p50 29.3, p90 37.4 ms. Frame shots: round fought, KO replay, WIN 1, next matches (`vsnet2/contact.png`) |
| `vsnet` vs `vsref` | same, 150 s | 0 of 4563 confirmed frames; the 3 differing frames are the last 3 of the run (predictions not yet revealed when the run stopped) |
| `vssnet` vs `vssref` | same with `TEKKEN4_SOUND=1` | from frame 2665 on (first rollbacks ~2400) region 28 (sound page 0x1cca000) differs in every frame and the boundary EE cycle by 8 cycles (the sound library's EE code takes another path); no other RDRAM region differs except the run's last 4 (unrevealed) frames. The IOP heard the predicted timeline's command queues live (71 re-simulated calls differed from the log), so its replies differ from the reference's. A desync for netplay (the cycle difference reaches the EE timers, which seed srand at the next scene start); see section 2 "Open". |

The fight in VS runs at ~33 fps on "Underground" without any rollback (`vsref`: `ee` ~30 ms per fight frame, GS
and VU1), so the selfnet runs were slower than real time; the logical result does not depend on that.

## Reproduce

Build: `docs\rollback\rb_build.cmd` (stages generated code, the HEAD versions of the shared overrides, the
rollback driver; builds `D:\tekken4-fork-rb\out\rb`). Runs (PowerShell, run lock honoured):
```
$s = 'TEKKEN4_RAND_SEED=1;TEKKEN4_RB_INPUT=500:Start,800:Start,1040:Start,1280:Cross,1580:Start;TEKKEN4_RB_FUZZ=2100'
# self-test, sound off, all cuts (p2c); add ;TEKKEN4_SOUND=1;TEKKEN4_RB_SNDTRACE=1 for s2a
docs\rollback\rb_run.ps1 -Name p2c -Shots 60,100 -Env "$s;TEKKEN4_RB_MODE=test;TEKKEN4_RB_TEST=start=2100,every=30,depth=8,mispredict=1"
# no-rollback reference (mref0 also with TEKKEN4_RB_IDLE=0), then compare the live frames
docs\rollback\rb_run.ps1 -Name mref0 -Shots 60,100 -Env "$s;TEKKEN4_RB_MODE=measure"
python -I docs\rollback\rb_compare.py logs\rb\mref0\rb_frames.log logs\rb\p2c\rb_frames.log
# WAV check: s2ref (measure) and s2wav (test) with TEKKEN4_SOUND=1;TEKKEN4_SOUND_WAV=<absolute path in the run dir>
# (a relative path lands in the repo root), then compare the PCM after the 44-byte header.
# selfnet: VS BATTLE, Kazuya vs Paul
$v = 'TEKKEN4_RAND_SEED=1;TEKKEN4_RB_PAD2=1;TEKKEN4_RB_INPUT=500:Start,800:Start,960:Down,1020:Down,1080:Cross,1320:Cross,1560:Cross,1800:Cross;TEKKEN4_RB_INPUT2=1320:Cross,1560:Cross,1800:Cross;TEKKEN4_RB_FUZZ=2400;TEKKEN4_RB_FUZZ2=2400'
docs\rollback\rb_run.ps1 -Name vsref2 -Shots 60,120,180,240,300,360,420 -Env "$v;TEKKEN4_RB_MODE=measure"
docs\rollback\rb_run.ps1 -Name vsnet2 -Shots 100,200,300,400,500,600,700,800 -Env "$v;TEKKEN4_RB_MODE=selfnet;TEKKEN4_RB_NET=start=2350,delay=4,jitter=2,max=8"
python -I docs\rollback\rb_compare.py logs\rb\vsref2\rb_frames.log logs\rb\vsnet2\rb_frames.log --last
Select-String logs\rb\vsnet2\rb_frames.log -Pattern NETSUMMARY | Select-Object -Last 1
```
`rb_run.ps1` has to be started from a PowerShell with script execution allowed (the Bash tool's `powershell -File`
is refused by the execution policy here).

## Phase 3 plan: the UDP netcode loop

Reuse from T5DR (game-agnostic, port + rename, ~2500 lines as in the plan):
1. **Transport** `src/netplay/netplay_core.cpp` -> `runtime/rollback/tekken4_netplay_core.cpp`: UDP session,
   HELLO (session id, delay, build id, seed) / PING / INPUT / BYE, redundant unacknowledged inputs (+ last 8) in
   every packet with resend every 15 ms while stalled, per-process nonce + SipHash-2-4 tag, RTT by ping echo, lead
   field for time sync, last-8 state hashes per packet. Magic "T5NP" -> "T4NP", env prefix `TEKKEN4_NET_*`, the
   input payload = the PS2 pad state the provider already takes (16-bit buttons + 4 axes), costume/pick packets
   dropped (character select is played in lockstep instead).
2. **Loop** `src/rollback/rb_net.cpp` -> the selfnet code of this driver becomes the real thing: replace "reveal
   by script" with "received from the peer", keep prediction = repeat, the snapshot ring (then the write-watch
   undo log, plan M2, for ~0.4 ms snapshots instead of 1.2 ms full copies), `scan_mispredictions`, input delay by
   ping (T5 §24: 1-3 frames), max prediction 8, stall when the peer is further behind, trimmed-mean time sync
   (T5 §28) with skip-a-vblank correction (plan M11: postpone the VBlankStart event by one period in the
   scheduler).
3. **Desync check**: per confirmed frame a gameplay hash (to define: pad blocks, fighters, round state, RNG word
   at reent+88, timer) exchanged in the packets; the full-state hash is no longer comparable across peers once the
   VU1 cut and the IOP replies differ, so the gameplay regions must exclude VU1 memory and sound-reply words, and the
   reply words that reach match state must be made peer-independent first (section 2 "Open").
4. **Start state**: lockstep from boot over the menus (both peers fed the same pads per logical frame: the runtime
   is cycle-deterministic from cold boot, measured), rollback from the fight start; fixed seed (`TEKKEN4_RAND_SEED`
   path / srand override) and a fixed online memory card. Game rules as T5: neutral input during the intro, no
   pause (START) online, KO/result actions only on confirmed frames.
5. **Lobby/build id** (phase 4): `lobby/t5lobby/buildid.py` pattern, `sha1("t4dr-build:<SLUS_203.28 sha1
   a4b7dde2...>:<code_id>:<net version>")[:16]`, code_id = fork commit + patches 01..N + `config/*.toml` +
   `function_map.csv` + overrides + generated-code settings; peers with different ids are refused at HELLO.
6. **Test harness**: port `tools/rollback_net_test.py` (two instances through a UDP proxy with RTT/jitter/loss), done
   = full match at RTT 0/50/150 with 3 % loss, 0 gameplay-hash mismatches, same result on both.

Before or during phase 3 (blocking 60 fps online): the live frame cost (13 ms Story stage, ~30 ms Underground) leaves
little or no room for re-simulation; GS back-pressure and VU1 are the live-frame costs to attack.
