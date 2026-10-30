# Tekken 4 (SLUS-20328) rollback netcode: design plan

Status: plan only, nothing implemented. Written 2026-10-29 from a read of the Tekken 5 DR rollback
(sister project, PS3 static recomp, shipped: docs/ROLLBACK.md, docs/NETPLAY.md, src/rollback/*,
src/netplay/*) and of this port plus the patched PS2Recomp fork (`D:\tekken4-fork-ps2recomp`, patches 01-32).
Nothing was built or run; every number about T4 below is an estimate that phase 0 must replace.

Notation: "T5 §n" = section n of T5DR docs/ROLLBACK.md; "T5 file" = path under T5DR `src/`.
"Fork" = `D:\tekken4-fork-ps2recomp\ps2xRuntime` (include/ and src/lib/).

Address caveat: `runtime/tekken4_overrides.cpp` carries the US (SLUS-20328) constants (rand 0x2a2538,
reent pointer 0x304b94, SifCallRpc 0x281d98, sound RPC fno 0x100 / 0x200, disc-read done flag 0x357a28), but
its comments and `docs/status.md` still use PAL (SCES-50878) `FUN_` names such as the main loop
`FUN_001969f8` and the ring state 0x1cda2c0. PAL numbers in this plan are marked (PAL) and must be mapped
with `tools/map_pal_to_us.py` or re-found in Ghidra before use.

## 0. Verdict

Rollback looks MORE feasible here than it was for T5DR, for four structural reasons, and harder for two.

Easier:
1. **All EE guest threads run cooperatively on ONE host thread** (`EeScheduler::run`, Kernel/EeScheduler.cpp:155).
   Generated code keeps every guest register in `R5900Context` (`SET_GPR_S32(ctx, ...)`), calls go through
   `dispatchGuestBranch`, a blocking syscall throws `EeDispatcherTransfer` (EeScheduler.cpp:1683) which unwinds the
   host stack, and a thread resumes by re-entering the function table at `ctx->pc` (`label_xxx: if (ctx->pc == ...) goto`).
   So at the dispatcher the whole EE machine is plain data: RDRAM + scratchpad + per-thread `R5900Context` +
   scheduler tables. T5's open worry (host stack copies of registers, `_cs_` locals) does not exist.
2. **Deterministic by construction**: time on the EE is counted in EE cycles (`accountCycles`), vblank/timer events
   have cycle deadlines (`kVBlankPeriodCycles`), the host clock only paces (`processDueDeadlines` waits for
   `hostDeadline` but fires at a fixed cycle). The IOP (R3000 interpreter + native SPU2 `SoundEngine`) is also advanced
   by EE cycles (`advanceIopEeCycles`). Nothing in the EE path is fed by a free-running host thread.
3. **Synchronous DMA/VIF/GIF/VU1**: transfers finish inside the CHCR write on the executor; only MFIFO can be "in flight"
   (`m_mfifoWaitingChannel`). The GS is a pure sink (async raster threads, no feedback except readbacks and CSR bits set
   synchronously by the frontend). So the draw cut can sit at the very end of the pipe (drop `Submit(batch)`), below all
   game-visible side effects, instead of T5's 21+18+5 indirect/direct call cuts.
4. **Game loads are synchronous HLE copies** (`discRead` in the override copies from the ISO into RDRAM and bumps
   0x357a28 in the same call), so loading is a function of EE cycles, not of loader-thread timing. T5's lockstep windows,
   loader drains and scene barriers (T5 §22, §30, §32) shrink to "start both peers from the same state".

Harder:
5. **32 MB RDRAM is allocated with `new uint8_t[]`** (src/lib/ps2_memory.cpp:421), not with a write-watch allocation;
   plus scratchpad, VU0/VU1 memories and PS2Memory/VU/DMA device state living in C++ members, not in guest memory.
6. **Sound is an emulated IOP** (zsiopdrv, SIF RPC 0x12345) with state outside RDRAM (IOP RAM 2 MB, SPU RAM 2 MB, voices,
   IOP threads/semaphores), and music is not even working yet in this port (status.md "music-3"). T5's sound-in-resim
   work (§20) maps onto one chokepoint (the per-frame RPC 0x100) but the IOP side must be treated carefully.

Recommended shape: snapshot/restore at an EE-scheduler quiescent point, undo-log via RDRAM write-watch, resim in
"virtual time" (cycle-driven, host deadlines ignored, IOP frozen) with the GS raster submit dropped, pad input replaced
per logical frame, T5's transport and GGPO loop ported. Everything else follows T5.

## 1. Where the state lives: T5DR vs T4

| | T5DR (PS3) | T4 on PS2Recomp |
|---|---|---|
| Guest RAM | ~104 MB state set, 6 ranges (T5 §1) | 32 MB RDRAM (`PS2_RAM_SIZE`), one range; 8192 pages |
| Other guest-visible memory | none | scratchpad 16 KB; VU0 code/data 4+4 KB; VU1 code/data 16+16 KB (`PS2Memory`) |
| CPU state | lifted ppu_context untouched, no regs needed | `R5900Context` per EE thread (incl. VU0 macro regs, FPU, COP0 count) |
| Kernel objects | lv2 semaphores etc. in the host runtime (the §30 token bug) | `EeScheduler` tables: threads, semaphores, event flags, alarms, IRQ handlers, ready queues, `m_eeCycle`, `m_vsyncTick`, deadlines |
| Device state | GCM ring (excluded), SPURS job pages | DMA regs[10], VIF0/1 regs, GIF arbiter, MFIFO, timers[4], `m_vif1Carry`, path2 cut state, pending transfer lists, completed-DMAC causes; VU1 interpreter pipelines; stub statics (SIF, CD, pad, memcard: ~90 `g_*` globals in Kernel/Stubs) |
| Output side (never rewound) | RSX, cellAudio | GS VRAM 4 MB + GS frontend/backend, GL/CPU raster threads, SoundEngine output queue, host audio device, presenter |
| Beside-the-frame state | file manager, geometry/draw managers, sound lib heap, music thread (T5 §32) | IOP + zsiopdrv + SPU2 (deterministic but outside RDRAM); host-side override state in tekken4_overrides.cpp (`g_frames`, movie/disc state) |
| Hot set per frame | ~330 hashed pages (1.3 MB), 700-880 dirty | unknown; expect MFIFO ring (0x100000, 512 KB = 128 pages, rewritten every frame), packet/display buffers, fighters, camera; measure in phase 0 |

## 2. T5DR mechanisms and their T4 mapping

For each: T5DR what/where, T4 mapping, easier/harder, files to touch. Fork paths relative to
`ps2xRuntime/`; game paths relative to `D:\tekken4-us`.

### M1. State set definition, exclusions, masks
- T5DR: `kSave` (6 ranges), `kExclude` (async-thread areas), `kHashExclude`, `kMask`, `kKeepLive` byte ranges
  (T5 §1, §32; src/rollback/rb_state.cpp). Every entry was found by per-page diffs.
- T4: state = RDRAM minus the MFIFO ring and packet/display scratch (restored not needed: consumed synchronously;
  hashing not wanted), plus an explicit serialized blob of non-RDRAM state (M4). Exclusions are fewer because no EE thread
  runs beside the frame. Probable hash masks: sound-reply words written by the IOP RPC (0x1cca000 area, PAL), wall-clock
  words (sceCdReadClock result buffer), vsync tick copies (`setVSyncFlag(flagAddress, tickAddress)` writes a 64-bit tick
  into RDRAM), render/debug counters.
- Easier: no byte-exact keep-live lists expected. Harder: none.
- Touch: new `runtime/tekken4_rollback_overrides.cpp` (ranges, masks, gameplay-hash regions); fork new
  `include/runtime/ps2_rollback.h` + `src/lib/ps2_rollback.cpp`.

### M2. Undo-log snapshots with write watch (T5 §7; rb_state.cpp `state_init/commit/rollback`)
- T5DR: shadow copy + `GetWriteWatch` per frame -> pre-images of dirty pages into an undo ring (1 ms/frame, 24k pages,
  ~32 frames); rollback applies logs newest-first; lazy variant for confirmed frames (T5 §33).
- T4: identical algorithm, one range. Needs RDRAM allocated with `VirtualAlloc(MEM_RESERVE|MEM_COMMIT|MEM_WRITE_WATCH)`
  instead of `new` (ps2_memory.cpp:421, free path ~333; gate by `TEKKEN4_RB_MODE` so normal runs are unchanged). Generated
  code writes RDRAM with direct stores (`FAST_WRITE32`), so hardware tracking is the only option.
  Scratchpad (16 KB), VU0/VU1 memory (40 KB) and the device blob are small: copy them whole each frame into the log.
  Ring size 8-12 frames is enough (T5 uses max prediction 8): ~12 x (dirty pages x 4 KB) = tens of MB.
- Cost fallback: full 32 MB memcpy is 3-4 ms per frame, too slow per frame, fine for the phase-1 prototype only.
- Touch: fork `src/lib/ps2_memory.cpp` (alloc), new `ps2_rollback.cpp` (port of rb_state.cpp: ~400 lines after dropping
  T5 ranges, job pages, keep-live, render-state experiments).

### M3. Frame-boundary hook (T5 §2; hook on `sys_semaphore_wait` of the frame semaphore)
- T4: hook in `EeScheduler::run()` at the moment the main thread (id 1) resumes from its per-frame wait
  (`running->resumeCompletion` has just run, or `wait.reason == VSync/Semaphore` was just cleared). At that point no guest
  function is on the host stack for any thread, so snapshot AND restore are both safe there. Requirement for a valid
  boundary: no `GuestThread::invocations` pending (an interrupt handler may be queued: defer to the next dispatcher turn,
  microseconds) and `m_completedDmacCauses` empty.
  Do NOT use the existing `sceSifCallRpc` override (per-frame RPC 0x100, `g_frames`) as the restore point: it runs on the
  host stack inside a guest function. It is good as a frame COUNTER and as the sound chokepoint (M12).
- Which wait the main loop uses (sceGsSyncV/WaitVSync stub vs a semaphore signalled by a vsync/DMA handler) and where in the
  loop it sits relative to input read / sim / draw kick: phase 0 question 1. The game's main loop is `FUN_001969f8` (PAL).
- Easier: the boundary is a real scheduler state, not a syscall wrapper with stack-shape assumptions.
- Touch: fork `Kernel/EeScheduler.cpp` (hook + `captureState/restoreState`), `include/runtime/ee_scheduler.h`.

### M4. Restoring state that is not guest memory (T5 §30 semaphore token, §32 threads beside the frame)
- T5DR pitfall: a kernel semaphore count is not guest memory; a restore left the count out of step -> loader task waited
  forever (found only at match end under heavy rollback). Same class: file manager request slots, fds, sound heap.
- T4: everything EE-side that corresponds is in `EeScheduler` (copyable value members, except `std::function` members
  `EeWaitState::completion` / `GuestThread::resumeCompletion` / `GuestInvocation::onComplete`, which capture by value
  `resumePc` and similar: copy is fine, audit each capture for references to mutable host objects). Snapshot list:
  `m_threads` (contexts, status, wait, wakeupCount, priorities), `m_readyQueues`, `m_semaphores`, `m_eventFlags`, `m_alarms`,
  IRQ handler tables, `m_currentThreadId`, `m_eeCycle`, `m_sliceEndCycle`, `m_vsyncTick`, vsync flag/tick addresses,
  GS vsync callback, scheduled deadlines (cycle part; rebase the host part to "now"), `m_pendingEeTimerInterrupts`,
  PS2Memory timers and DMA/VIF/GIF registers, MFIFO flags, `m_vif1Carry`, path2 cut state, pending transfer vectors,
  VU0/VU1 `VU1State` + pipelines (or force the VU1 programs to be idle at the boundary and assert it), VU0 macro regs
  (already in `R5900Context`). Plus stub statics: `ps2_stubs` SIF client table/handlers (Stubs/SIF.cpp `g_sif*`), CD
  stream position (`g_cdStreamingLbn`), pad port state (Pad.cpp `portState`), the override file's host state.
  Memory card (`MemoryCard.cpp`) and host file I/O are NOT rolled back: disable them in net mode (T5 does the same with a
  fixed online save, NETPLAY.md "One save for online play").
- Harder: more C++ state than T5 had to think about, scattered over Stubs. Mitigation: enumerate by grep of file-scope
  `g_*`, then verify with the full-state hash test (section 5) rather than by reading.
- Touch: `ee_scheduler.h/.cpp`, `ps2_memory.h/.cpp` (a `serializeDeviceState/restore`), Stubs/{SIF,CD,Pad,DMA}.cpp.

### M5. Re-simulation with waits bypassed (T5 §3; `set_bypass`, `[0x106D4D98]` pacing zeroed)
- T5DR: frame-semaphore wait returns at once, vblank posts swallowed, GCM flip waits no-ops.
- T4: "virtual time" mode in the scheduler. While `resimulating`:
  (a) `processDueDeadlines` / `waitForEvent` ignore `hostDeadline` and fire VBlankStart/End the moment `m_eeCycle`
      reaches the cycle deadline (the guest sees every vblank handler and `sceGsSyncV` wake exactly as live);
  (b) `accountCycles` skips `advanceIopEeCycles` (IOP frozen, no extra mixing/audio);
  (c) the presenter is left alone (GS got no new frame; see M6).
  The loop ends when the logical frame counter reaches the target; then the host deadlines are re-based.
  Because the EE is cycle-deterministic, a restored scheduler re-executes the same instruction stream as the original run
  for the same inputs. This is stronger than T5's "bypass" (which had to fake vblank and flip state).
- Touch: `EeScheduler.cpp` (`processDueDeadlines` ~1775, `waitForEvent` ~2000, `accountCycles` 391), `ps2_runtime.cpp`
  (`advanceIopEeCycles` 620).

### M6. Draw cut (T5 §6, §26, §33; rb_icall.cpp kDrawCut/kDetourCut, ps3recomp patch 0016)
- T5DR: 21 vtable targets + 18 draw-thread handlers + 5 direct-call detours stubbed during resim; hash differs by
  render bookkeeping, so only a hand-picked "gameplay hash" can arbitrate; one wrong cut desynced gameplay (0x264B04).
- T4: cut at the GS: drop `GSRasterBackend::Submit(batch)` while resimulating (GSThreadedBackend::Submit,
  src/lib/gs/gs_threaded_backend.cpp; or an inner no-draw wrapper), keep `LoadClut`, `BeginTransfer`, `UploadImage`,
  `TextureFlush` so GS memory and texture-cache state stay consistent (VRAM is not rewound, uploads are idempotent).
  Everything above the GS (VU1 programs, VIF/GIF parsing, DMA completion interrupts, the game's frame state machine at
  0x1cda2c0 (PAL)) runs unchanged, so RDRAM after a resim frame equals RDRAM after the live frame. That makes the
  **full RDRAM hash comparable between original and resim** (T5 could not). Expected cost: EE sim + VU1 (native, <1 %) + GIF
  parse; rasterization (GS ~700 ms/s of the fight, status.md) disappears.
  Second-stage cuts if phase 2 shows the parse is expensive: skip VIF1 geometry DMA payload but still raise the DMAC
  completion causes (`completeDmacChannel` / `queueCompletedDmacCause`, ps2_memory.cpp), keep texture-upload tags.
  Never cut: DMA completions (the game's flush spins until its ring state returns to 0, status.md "Why the flush hangs").
- Easier: one cut point, no per-title call-site archaeology. Harder: GS readbacks (`consumeLocalToHostBytes`) must still be
  served; check whether any fight code reads GS memory (character select does use IPU/readback paths).
- Touch: fork `gs/gs_threaded_backend.cpp`, `gs/gs_frontend.cpp` (flag), maybe `ps2_memory.cpp`.

### M7. Determinism fixes: RNG, wall-clock words, masks (T5 §4, §12, §21; rb_rand.cpp; NETPLAY.md "What had to be made deterministic")
- T5DR: Mersenne Twister seeded from the clock -> reseed at sync points; C `rand()` consumed by a side thread -> excluded;
  TLS generator split per call site; a dozen statistics words masked; cross-CPU FP audit (no libm, no FMA contraction,
  MXCSR checks).
- T4: RNG is the game's own LCG (`guestRand`, override at 0x2a2538: next = next*1103515245+12345 on the word at reent+88,
  reent = *0x304b94) and its state is in RDRAM, hence in the rollback state for free. Missing: the SEED. Find where the
  game calls its srand (PAL 0x2a3168 / US 0x2a2528) and from what (EE timer? `sceCdReadClock`, which returns `std::time()`
  in Kernel/Stubs/CD.cpp:520; cop0 count?). At the net sync point both peers write the same seed into reent+88 (and any other
  generators the game keeps; find with a "state differs between two cold boots" diff). Note `LibC.cpp:1085` `std::rand` is
  only a fallback for unstubbed paths; the override already replaces rand.
  FP: generated code is plain SSE on `float`; CPU-dependent results can only come from libm calls (recompiler emits
  `sqrtf` in VU translation helpers, ps2xRecomp/src/lib/vu_translation_helpers.cpp:98,105; sqrt is IEEE-exact, fine),
  FMA contraction (check compile flags: `-ffp-contract=off` for the generated code and runtime) and MXCSR (GSThreadedBackend
  propagates the game thread's MXCSR: confirm it is the same on both peers). Audit the same way as T5 `fp_audit.py`.
- Touch: `runtime/tekken4_overrides.cpp` (seed hook beside `guestRand`), fork `Kernel/Stubs/CD.cpp` (net-mode fixed clock).

### M8. State hash and desync detection (T5 §14, §21; `state_game_hash`, `np::rb_push_hash`, kGameSkip, dumps)
- T5DR: per-page 64-bit hash updated from dirty pages; a small "gameplay hash" (25 KB: pad blocks, input ring, RNG, round
  state, fighters) of CONFIRMED frames is exchanged and compared; desync dumps of the last 64 frames.
- T4: same two hashes. Full-state hash (all non-masked RDRAM pages + device blob) for the in-process self-test; gameplay
  hash for the peers (regions found in phase 0: fight block, both fighters, round timer/state, RNG state, pad buffers).
  Reuse the compare/ack/dump machinery unchanged.
- Touch: `ps2_rollback.cpp` (hash), `runtime/tekken4_rollback_overrides.cpp` (gameplay regions, skip list).

### M9. Input as a function of the logical frame (T5 §2 keyread parking; local_pad.cpp; netplay_core.cpp)
- T5DR: input thread parked, main thread ticks the pad once per frame, `cellPadGetData` answers for the logical frame.
- T4: simpler. The EE reads the pad itself in `scePadRead` (Stubs/Pad.cpp:710 -> `readPadPortData` -> `PSPadBackend::readState`,
  ps2_pad.cpp:29, which polls raylib/GetAsyncKeyState live). Add a pad provider hook: in net mode `scePadRead` for port 0/1
  returns `provider(port, logicalFrame)`; live sampling for the local player happens at the boundary (once per frame,
  `ps2_input_latency::sampleKeyboard` / gamepad) and is sent with input delay; a resimulated frame reads its stored input.
  The pad buffer the game sees is part of RDRAM, so it is restored and re-read consistently. Same 16-bit buttons + 4 analog
  bytes as T5 `PadInput`, which makes the wire format identical. Check that Tekken 4 reads each port exactly once per logical
  frame (multiple reads would need caching per frame) and which buttons carry pressure bytes (DualShock2).
- Touch: fork `Kernel/Stubs/Pad.cpp`, `ps2_pad.cpp`, `ps2_input_latency.cpp` (latency path must not run in net mode).

### M10. The GGPO-style loop (T5 §9, §15, §22, §33; rb_net.cpp `boundary`, `scan_mispredictions`, `start_rollback`)
- T5DR: per boundary: commit, sample local pad for f+delay, poll peer, find first mispredicted frame, rollback+resim,
  live frame; max prediction window 8; hash hand-off; stats; phase-based lockstep windows and warm-up were later mostly
  REMOVED (§22) once sound resim was right.
- T4: port the algorithm as is. Game-specific parts to rewrite: the "intro takes no input" rule (T5: phase word 0x1008F070 in
  7..12), the post-match scripted START rule, decided-byte, KO-undo handling (T5 §32 fix 5: do not act irreversibly on a
  predicted KO: pause/skip/result), scene barrier. Expect FEWER barriers than T5 (loads are cycle-deterministic), but
  still: both peers must reach "fight start" at the same logical frame with identical state (M13), and a menu-skip START
  online must be neutralised (T5 NETPLAY.md "No pause online").
- Touch: new `runtime/tekken4_rollback_net.cpp` (ported rb_net.cpp), `runtime/tekken4_netplay_core.cpp` (M14).

### M11. Time sync (T5 §24, §28, §34 `ts_correct`, ps3recomp patch 0080 `cellGcm_skip_ticks`)
- T5DR: exchange lead estimates in every packet, trimmed-mean advantage over 20 frames, give up a whole display refresh
  by skipping a vblank tick, not by sleeping (sleeps were absorbed by the pipeline and quantised by the OS timer).
- T4: the EE scheduler schedules vblank itself: "skip n ticks" = postpone the next VBlankStart event by one period
  (`scheduleEvent` in `processDueDeadlines`, EeScheduler.cpp ~1848). Trivial and exact. Input delay by ping: copy T5
  `proto.suggest_delay` / rollback delay 1-3 frames (T5 §24).
- Touch: `EeScheduler.cpp`, the ported loop.

### M12. Sound in re-simulated frames (T5 §20 rb_sound.cpp, rb_sndheap.cpp, §16-19 ATRAC stream)
- T5DR: sound library lives outside the rollback state; every play call is logged per frame and deduped in resim
  ("same sound starts once"), tick skipped in resim, stops not applied, music stream read from the archive instead of
  being re-fed; a 15-phase saga, the single longest item.
- T4 options:
  A (recommended, matches T5): IOP + SoundEngine stay LIVE and outside the state; IOP frozen in resim (M5b). The EE-side
  chokepoint is the one SIF RPC the override already intercepts: `sifCallRpc` for SID 0x12345, function 0x100 (per-frame,
  0x80-byte command queue sent from 0x1cca040, 8-word reply into 0x1cca000, PAL addresses). In resim: compare the frame's
  command queue with the first run's log; identical -> do not send, write the logged reply into the reply buffer;
  new/different commands -> send only the new ones (late start). Other functions (bank loads, 0x200 reads with mode != 0)
  are never repeated in resim; their replies are replayed from the log. Needs the command-queue format decoded from the
  EE sound library (0x222788-0x2237f8, PAL) and the zsiopdrv (the IOP image is on the ISO).
  B: roll the IOP back too (IOP RAM 2 MB + IOP CPU/threads/semaphores + SoundEngine voices; SPU RAM by hash-gated copy),
  mute the SoundEngine output queue in resim, and truncate the not-yet-played tail of the host `DeviceQueue` (patch 30,
  ~2048 frames = 43 ms) back to the rollback point so the corrected timeline replaces it. Sample-exact because IOP+SPU are
  cycle-deterministic; drawback: invalidates the idle-skip cache (patch 21, `schedEpoch`) and costs copies; sounds already
  played from a mispredicted timeline cannot be unheard in either option.
  Start with A in a "mute the sound RPC in resim" form (the T5 phase-9 equivalent) just to get gameplay hash clean; the
  T5 lesson is that skipping is NOT enough (the reply bytes written into game memory feed back into game state), so replay
  the logged reply.
- Risk: music. The port's BGM does not play yet (status.md: stream refill from IOP 0xc7000, SPU2 IRQ). A rollback must never
  touch the stream; keep disc/stream reads IOP-side (T5's "read it, don't re-feed it" lesson).
- Touch: `runtime/tekken4_overrides.cpp` (`sifCallRpc`, `kSoundFrameCall`), fork `ps2xIOP/src/iop_subsystem.cpp`
  (`runEeCycles` gate), `emulator/core/sound_engine.cpp` (mute / queue truncation).

### M13. Sessions, rematch, persistent game (T5 §31 `session_reset`, DIRECTFIGHT.md)
- T4: needs a "direct fight" analog: get both peers from boot to the same VS fight start without hand-driving menus.
  Two ways: (1) lockstep the whole menu path from boot (cheap: the runtime is deterministic from cold boot if input is
  exchanged per logical frame and wall-clock reads are fixed); (2) inject the menu path with scripted pad presses the way
  `tools\run_fixed_fight.ps1` does, then switch to rollback at the fight start. Same-state start is what matters: reseed
  the LCG at the sync frame. Rematch = repeat from the character select; a persistent process needs `session_reset`
  (drop undo logs, rebuild shadow).

### M14. Transport and negotiation (T5 netplay_core.cpp, NETPLAY.md, lobby buildid.py)
- Game-agnostic: UDP, HELLO/PING/INPUT/BYE packets, redundant input resend with ack, siphash packet auth, session id/nonce,
  RTT by ping echo, lead field for time sync, desync-hash exchange, stall/timeouts, relay/NAT in the lobby. Reuse almost
  verbatim; rename magic "T5NP" -> "T4NP", env prefix, replace `HostPadData` with the PS2 pad struct, drop costume/pick
  packets or keep the PICK mechanism for character select.
- Build identity (lobby/t5lobby/buildid.py): `sha1("t4dr-build:<elf_sha1>:<code_id>:<net>")[:16]` with elf_sha1 =
  SLUS_203.28 (CRC 0xB975F704 is already checked in `PS2_REGISTER_GAME_OVERRIDE`), code_id = hash of fork commit + patch
  stack (patches/01..N) + `config/*.toml` + `function_map.csv` + overrides + generated-code settings. Both peers must run
  bit-identical generated code AND runtime, as in T5.

### M15. Test tooling (T5 §1 measure, rb_test.cpp, rb_wft.cpp, rollback_net_test.py)
- T5DR: `T5_RB_MODE=measure|test|net`, `rb_frames.log` with MATCH/MISMATCH per re-simulated boundary and per-page word diffs,
  write-fault tracer to find who writes a page, a two-instance UDP proxy harness with RTT/jitter/loss and scripted attacks,
  audio checks.
- T4: `TEKKEN4_RB_MODE=measure|test|net`. Scripted input already exists (`tools\run_capture.ps1 -Keys`,
  `tools\run_fixed_fight.ps1`, `TEKKEN4_RAND_SEED`); the write-fault tracer is easy to rebuild with `VirtualProtect` on
  the RDRAM pages (vectored exception handler logs guest `ctx->pc` from `m_debugPc`). Port the UDP proxy harness and the
  frame-log diff tools as they are (Python).

### M16. Early rollback / frame-time work (T5 §27, §33)
- Later, optional. In T4 the main thread idles inside the vsync wait; because the EE is cycle-driven, resim of the late
  input can start at the frame's end and run inside the vblank wait with no special hook. Evaluate after phase 3.

## 3. T5DR pitfalls and their status in T4

| T5 pitfall (cost) | T5 § | T4 status |
|---|---|---|
| Kernel object not in memory (semaphore token) -> loader hang at match end | 30 | Eliminated by snapshotting `EeScheduler` tables (M4). Residual: IOP-side objects if option B in M12. |
| Threads beside the frame own pages (file manager, geometry/draw managers, music thread, sound heap) | 31, 32 | No EE thread runs beside the dispatcher. Residual: IOP/zsiopdrv state. Host threads (GS, audio, presenter) write no guest memory (phase 0 must prove it with a write-fault trace). |
| GCM command ring and draw lists in the state; restore re-played stale flips | 26, 33 | Analog = MFIFO ring 0x100000 (PAL) and GIF/VIF packet buffers: keep out of restore and hash, but DMA registers + ring state struct must be consistent. |
| Draw cut changes the hash, only a hand-picked gameplay hash arbitrates; a wrong cut desynced gameplay | 6 | Cut is below all game-visible effects (GS Submit drop): full RDRAM hash must match. |
| `rand()` consumed by a side thread -> timing-dependent word | 12 | Single executor; LCG state in RDRAM; only the seed needs a sync (M7). |
| Sound: duplicate starts, skip not enough, reply bytes feed state, music stream corruption, abort | 8-10, 16-20 | M12; the 0x100 RPC is a single chokepoint. Music not working yet in the port: design with it in mind. |
| Scene barriers, loader drains, lockstep windows crawled at RTT 150 | 15, 22, 30 | Loads are synchronous HLE copies; barrier reduces to the fight-start sync point. Keep a "lockstep until warm-up done" option anyway. |
| Predicted KO acted on irreversibly (driver pressed START / ended match) | 32 fix 5 | Same game-level rules must be re-implemented (result, skip, replay START only on confirmed frames). |
| Vblank handler race while copying state | 23 | N/A (vblank handler runs on the executor as a GuestInvocation, never concurrently). |
| Time-sync sleeps quantised by OS timer; display margin tuning | 28, 34 | Skip-vblank-event correction in the scheduler (M11); no display lock needed unless presenter jitter shows. |
| Autosave thread racing a memory container allocation -> heap shifted by 1 MB | 32 fix 4 | Memory card/save disabled in net mode; guest heap allocation order is a function of guest code only. |
| Cross-CPU FP differences | NETPLAY.md | Audit generated code + runtime flags (M7). |
| Pause (START) online, unlock state differing per save | NETPLAY.md | Same rules: neutralise START, fixed online save, same unlocks. |

## 4. Determinism risks specific to this port, and how to find them

1. **Host-timing influence on the EE.** In theory only pacing. Check: `postEvent` callers (only MPEG completions outside
   the executor today), `m_checkpointPending` set from other threads (events), EE timer IRQ ordering vs
   checkpoints, time slice (`kDefaultTimeSliceCycles = 65536` cycles, deterministic). Find: baseline test (below).
2. **GS threads (GSThreadedBackend worker, CPU/GL raster threads).** Sink only; feedback paths are readbacks
   (`consumeLocalToHostBytes`), GS CSR FINISH/SIGNAL (set synchronously in gs_frontend.cpp:1494,1506) and Drain-based
   back-pressure (timing only). Verify no EE-visible data depends on raster completion; MXCSR propagation (gs_threaded_backend.cpp:99).
3. **Audio device pull and the SoundEngine.** `drainMixedAudio` runs on the game thread from `accountCycles`; the device
   thread only drains a queue. State of SoundEngine/IOP depends only on IOP cycles. Risks: rate-control and
   `maxLatencyFrames` dropping must not alter engine state; IOP replies written into EE RAM (status words incl. host-set
   movie bits `kStatusMovieAudioReady`) differ between peers -> mask or replay (M12).
4. **IOP scheduler idle-skip cache (patch 21).** Deterministic by design (epoch bumps on any thread becoming ready, DMA
   start, timrman), but it must be invalidated on any IOP restore (option B) and it interacts with "IOP frozen in resim".
5. **Wall-clock and host randomness reachable from the guest:** `sceCdReadClock` (std::time), `LibC std::rand`
   fallback, memory card timestamps, `TEKKEN4_RAND_SEED` test hook, host `ps2_input_latency` timing. Find by grep (done:
   CD.cpp:520, LibC.cpp:1085, MemoryCard.cpp:266/767/814) and by the cold-boot A/B diff.
6. **Frame cadence semantic.** Does the game run exactly one logic step per vsync, or step multiple times / skip when late
   (frame-skip loops are common on PS2)? The port currently slows to 34-44 fps on the Arena stage (status.md); if logic
   runs one step per vsync the game just runs slow, which is fine; if it skips, peers diverge in logical frame number
   unless the loop is forced to 1 step per vsync. Phase 0 question.
7. **Uninitialised memory:** RDRAM, scratchpad, VU memories are zeroed (`std::memset` in `PS2Memory::initialize`): good. Stack
   garbage and padding bytes in hashed regions still need the usual masks.
8. **Host state in override code** (`g_frames`, `g_movieSize`, `g_gsDumpFrame`, `g_clientSid`...): define each as either
   logical-frame derived or part of the snapshot.
9. **Audio/IOP-fed game state** (sound handles in fighter blocks, T5 §19-21): will appear as hash diffs; mask as "output
   state" once proven unread by the fight.
10. **Floating point:** see M7. Different CPU vendors/builds only matter if libm or FMA enter; check once, then keep a
    cross-build test (T5 `tools/cross_build_test.py` idea).

How to find them (T5's method, adapted):
- **Baseline double-run** (phase 0, needs only write-watch + hash): boot twice with the same scripted pad file
  (`run_fixed_fight.ps1`, fixed `TEKKEN4_RAND_SEED`), hash every dirty page at every boundary, diff run A vs run B per
  frame. Any page that differs with no rollback involved is a host-nondeterminism source; the guest PC of the writer comes
  from the write-fault tracer.
- **Cold-start A/B**: same, but start run B 30 s later in wall time and/or with sound off/on, GS cpu/gl, different
  `PS2X_GS_THREADS`: pages that differ = coupling to host timing, audio, GS.
- **Rollback self-test** (`TEKKEN4_RB_MODE=test`, the T5 test mode): every N frames save, run K frames, restore, assert
  `hash == snapshot` (restore fidelity), re-run K frames with identical inputs and compare every boundary's full hash with
  the original pass (resim fidelity), both with and without the GS cut and with the sound RPC replay on.
- **Two-process lockstep with identical start state** (before any prediction): exchange gameplay hashes per frame.
- Per-page word diff output (`rb_frames.log` style: frame, page, first differing words) and `rb_desync_diff.py`-style dump
  of the last 64 boundaries, ported from T5.

## 5. Phased plan

Sizes are lines of new/ported C++ unless stated; effort assumes the person who wrote this document continues with the
fork and Ghidra at hand.

### Phase 0: measure, no behaviour change (about 1-2 days, ~400 lines)
- Fork patch 33 `rollback-hooks`: (a) RDRAM via `VirtualAlloc(... MEM_WRITE_WATCH)` when `TEKKEN4_RB_MODE` is set; (b) a
  boundary hook callback in `EeScheduler::run()` on the main thread's per-frame wake; (c) `getRollbackHooks()` registry.
- `runtime/tekken4_rollback_overrides.cpp`: `TEKKEN4_RB_MODE=measure`: per boundary log frame number, wait reason/id of
  thread 1, EE thread list (`EeKernelSnapshot`), vsync tick delta, dirty-page count and region histogram, per-page hash.
- Answers to produce: (1) what the main loop waits on and where the boundary sits; (2) logical frames per vsync in a fight
  incl. Arena and when the port runs below 60; (3) dirty pages per frame and the hot regions (expect the MFIFO ring);
  (4) EE-only cost per frame (executor busy time excluding GS/audio waits); (5) which host threads write RDRAM (write-fault
  trace via `VirtualProtect`); (6) baseline double-run diff; (7) where the game calls srand and with what; (8) how many EE
  threads Tekken 4 creates and which are alive during a fight; (9) any fight-time GS readback; (10) the sound RPC 0x100
  command-queue layout.
- Done: `docs/ROLLBACK_MEASURE.md` with those ten answers and the page lists; two scripted fights hash-identical per frame
  except a short, explained list of pages, or the list IS the work list for phase 1.

### Phase 1: save/restore + offline hash self-test (about 1-1.5 weeks, ~1500 lines)
- `EeScheduler::captureState/restoreState` (M4 list), `PS2Memory::serializeDeviceState`, stub-static snapshot helpers,
  `ps2_rollback.{h,cpp}` (port of rb_state: shadow, write-watch undo ring, page hash, masks, `state_reset`).
  Prototype first with full 32 MB copies (as T5's first prototype, T5 §2) to prove fidelity, then the undo-log.
- Test mode: save at frame F, run K=8 frames live (GS and sound normal), restore, `hash == snapshot`; then re-run K frames
  with the same recorded pad input and compare every boundary with the first pass. No cut, no virtual time yet (the re-run
  just takes real time with pacing).
- Done: restore fidelity and resim fidelity with 0 mismatching boundaries over a 10-minute scripted VS fight with a rollback
  of depth 8 every 60 frames, on 3 different stages, plus a round end and a KO; snapshot (commit) <= 1.5 ms/frame and restore
  of 8 frames <= 10 ms on the dev PC. Mismatches drive the mask list (document each with its evidence, T5 §21 style).

### Phase 2: re-simulation in virtual time + draw cut (about 1 week, ~700 lines)
- Scheduler `resimulating` mode (M5 a-b), GS `Submit` drop (M6), sound RPC log/replay (M12 option A, first version: replay
  logged reply, send nothing), presenter untouched, pad provider reading a per-frame input array (M9 offline).
- Done: same test as phase 1 but resim takes < 3 ms median per frame (target; if measured higher, decide between the
  second-stage cuts of M6 and a smaller max prediction window), 0 mismatching boundaries in 200 rollbacks (full RDRAM hash
  comparable), no audio dropouts attributable to resim, no hang across a round end/KO/match end, session_reset works.

### Phase 3: input and the netcode loop (about 2 weeks, ~2500 lines mostly ported)
- Port netplay_core (rename, strip PS3 pad types), rb_net loop (prediction, scan, start_rollback, history, trimmed-mean time
  sync with skip-vblank, input delay by ping, stats), HELLO negotiation, gameplay-hash exchange and desync dump, UDP proxy
  test harness. Game rules: neutral input during intro, post-match START rule, no pause, irreversible-action gating (M10).
  Start state: lockstep from boot over the menus (M13 option 1) or a scripted menu path, with LCG reseed at the fight
  start sync point.
- Done: two instances on one PC through the proxy at RTT 0/50/150 ms with 3 % loss: full 2-round match with scripted attacks,
  0 mismatching frames, same result hash on both, 60 fps median window at RTT 50 on the dev PC (the port's own fps cap,
  status.md: fights 60 except Arena), no stalls > 100 ms outside loads.

### Phase 4: lobby and build id (about 1 week, ~600 lines + Python)
- `buildid.py` clone for T4 (M14), launcher handing T4NP env to the game, result file (winner, score, hash, fps), rematch
  and session reset, relay reuse, fixed online save/unlocks, START/pause handling in menus, character-select exchange.
- Done: lobby pairs two machines, 3 matches + rematch in one session, results agree, graceful peer-quit/timeout handling like
  T5's NETPLAY.md "Connection problems", build mismatch refused.

### Phase 5: polish (open-ended)
- Sound in resim: decode the 0x100 command queue and dedupe by command identity (M12), late-start of new commands, stop
  handling, decide option B (queue truncation) for shallow rollbacks, music stream safe across rollbacks.
- Early rollback inside the vblank wait (M16), display/presenter jitter, frame-time p99 work.
- Replays (record per-frame pads + start seed; replay is exact because the EE is cycle-deterministic) and spectating (stream the
  confirmed inputs to a third instance running behind), input-display/ training extras, per-stage fps issues (Arena).
- Done criteria per item added when started; the audio check of T5 (`rollback_audio_check.py`) is the template.

## 6. What can be reused from T5DR, and what must be rewritten

Reuse as code (game-agnostic, port + rename; T5 file -> T4 target):
- `src/netplay/netplay_core.cpp` (2385 lines): UDP session, HELLO/PING/INPUT/BYE, ack/redundancy, RTT, lead, siphash, hash
  compare, stall/timeout, relay hooks. Strip: PS3 `HostPadData`, T5 env overlay for persistent game (keep if a persistent
  game is wanted), costume packets, T5 unlock/save specifics. -> `runtime/tekken4_netplay_core.cpp`.
- `src/netplay/netplay.h`, `net_bind.h`, `match_rules.h`, `match_score.h`: API and rules; keep the shape.
- `src/rollback/rb_net.cpp` core (history ring, prediction = repeat last confirmed, `scan_mispredictions`,
  `start_rollback`, trimmed-mean `ts_correct`, stats/report, frame-time bins). Strip all fixed T5 addresses (phase word,
  decided byte, reader semaphore, `kMinVblanks`, GCM hooks). -> `runtime/tekken4_rollback_net.cpp`.
- `src/rollback/rb_state.cpp` algorithm (write-watch commit, undo ring, lazy rollback, page hash, mask set). Strip ranges,
  keep-live lists, SPURS job pages, render-state experiments. -> fork `ps2_rollback.cpp`.
- `src/rollback/rb_test.cpp` and `rb_measure.cpp` structure, `rb_wft.cpp` (write-fault tracer), `rb_trace.cpp`.
- `src/netplay/replay.cpp` (input-log replays) after the format is adapted; `local_pad.cpp` ideas.
- Python: `lobby/t5lobby/*` (proto, match_driver, client, relay/NAT, rating, spectate) and `tools/rollback_net_test.py`,
  `rollback_frame_times.py`, `rb_desync_diff.py`, `cross_build_test.py`; `buildid.py` as the pattern.
- Docs as design reference: T5 §9 (loop), §14 (hash), §24 (delay/default), §28-34 (time sync, frame time).

Not needed (T5 workaround for PS3 specifics): `rb_detour.cpp` (x64 entry detours: PS2Recomp has `replaceFunction`/
`registerFunction` and every guest call is table-dispatched), `rb_icall.cpp` call cuts and patch 0016 icall hook,
`rb_ktrace.cpp`, `rb_sndheap.cpp` (guest sound heap pool), the ATRAC archive-backed stream (patch 0028), GCM/RSX patches
(0029, 0034, 0039, 0080 except the idea), `job_gate` SPURS pages, loader drains (`side_drain`), lockstep phase windows.

Must be rewritten / new for T4:
- The EE-scheduler quiescent hook and `captureState/restoreState`, device-state serialization (nothing like it in T5).
- Virtual-time resim and the IOP freeze; the GS submit cut; the pad provider.
- Game knowledge: state map, gameplay-hash regions, masks, phase detection (intro, fight, KO, result, select), pause/START
  rules, result detection, fight-start sync, RNG seed point, all from Ghidra on the US ELF.
- Sound RPC 0x100 dedupe and IOP policy; music stream safety.
- Direct-fight / menu driving for T4 (different menus, PS2 pad scripts).
- Build id inputs (fork commit, patch stack, ELF hash), launcher integration.

## 7. Open questions (phase 0 must answer; each changes the plan)

1. What does the main loop block on, and is one logical step always one vsync (frame skip/catch-up logic)?
2. Is any EE thread other than the main thread active during a fight (e.g. a sound or loader thread)?
3. Do both peers reach identical state from a cold boot with identical input (EE cycle determinism, srand source)?
4. Dirty pages per frame and EE-only frame cost: does a depth-4 resim fit in one 16.7 ms frame next to the live frame?
5. Which GS/IPU/MPEG paths read back into RDRAM in a fight (any: breaks the pure-sink assumption of the cut)?
6. Layout of RPC 0x100's command queue and reply, and which reply words the fight reads back (decides M12 A vs B).
7. How the game saves/loads hidden state in the memory card path during VS (disable cleanly?).
8. Whether the runtime's MXCSR/FP environment is identical across builds and CPUs (cross-vendor test).

## Appendix: pointers

- T4 EE scheduler: Kernel/EeScheduler.cpp `run` 155, `accountCycles` 391, `processDueDeadlines` 1775, `processEvent` 1862,
  `blockCurrent` 1683, `waitForEvent` ~2000; ee_scheduler.h (`GuestThread`, `EeSemaphore`, `EeEventFlag`, `EeKernelSnapshot`).
- Memory: ps2_memory.cpp:421 (RDRAM `new`), ps2_memory.h (`PS2Memory`: `dma_regs`, `vif1_regs`, `m_mfifoWaitingChannel`,
  `m_vif1Carry`, `m_pending*Transfers`, `m_completedDmacCauses`, `m_eeTimers`, VU memories).
- IOP/sound: ps2xIOP/src/emulator/core/sound_engine.{h,cpp}, iop_kernel.h (`schedEpoch`), iop_subsystem.cpp; ps2_audio.cpp; patch 30.
- Pad: Kernel/Stubs/Pad.cpp (`scePadRead` 710, `readPadPortData` ~346), ps2_pad.cpp, ps2_input_latency.cpp.
- GS: gs_threaded_backend.cpp (`Submit`, `Drain`, Export/ImportState), gs_frontend.cpp (CSR 1494/1506, display latch).
- Game: runtime/tekken4_overrides.cpp (`sifCallRpc` path ~600-800, `guestRand` 948, `discRead` 118, `apply` 1210), docs/status.md
  (ring state 0x1cda2c0 and flush spin, "Why the flush hangs"), tools/run_fixed_fight.ps1, run_capture.ps1.
- T5DR: ROLLBACK.md §1 (state), §7 (undo log), §9 (loop), §14 (hash), §20 (sound), §24 (delay), §26-27 (cut, early rollback),
  §28/§34 (time sync), §30/§32 (kernel/thread pitfalls), §33 (frame time); NETPLAY.md "What had to be made deterministic",
  "Same game state on every CPU"; rb.h, rb_state.h, rb_net.h; buildid.py.
