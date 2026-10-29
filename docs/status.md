# Status

_Last updated: 2026-10-29 ~06:30 (US port + rollback night)_

## Resume here
- **OPEN (user, 2026-10-30): intro movie audio is garbage** (choppy/broken, as on PAL: "super flickery"). Separate path from
  the BGM fix: movie calls 0x3000/0x3100/0x3200 stay on the local HLE in runtime/tekken4_overrides.cpp, which decodes the
  interleaved SPU ADPCM itself ("movie audio: unit N -> 3584 stereo frames"); suspects: PCM added after the SPU clamp,
  unit pacing vs. 60 Hz, sample rate. Also open: upscale seams (64x32 page grid lines/steps), 480p mode (omode 0x50 path
  exists in the US ELF at 0x22a5c0), soft HUD at high scale. Offline test build: dist\T4-Offline-Test-2026-10-30 (local).
- **END OF THE US/ROLLBACK NIGHT (2026-10-29 ~06:30), RESTART HERE.** Main line = branch us-slus20328, patches 01-56
  (PS2Recomp branch t4-us in D:\tekken4-fork-ps2recomp = eb8688b + 01-56 as commits). All pushed. Done tonight:
  - QA (logs\qa\REPORT.md): Story, Arcade, Team, Survival, Practice, Training, Tekken Force, Options work; VS needs pad 2;
    7-min stability run clean.
  - Sound (docs\MUSIC_FIX.md, patches 33-36): BGM plays (SPU2 IRQ to libsd's handler; SIF cmd payloads to IOP RAM);
    banks/BGM from the right sectors (cdvd/ioman search the real ISO, DATA.BIN LBN 401): voices end, no clipping.
  - One-step build from the player's ISO, no BIOS: tools\build_game.ps1 (+ iso_extract.py, vu1_micro_from_elf.py:
    VU1 micro image rebuilt from .vudata, SHA-256 checked). Only dry-run tested end to end.
  - Rollback (docs\ROLLBACK_PLAN.md, ROLLBACK_PHASE01.md, PHASE2.md, PHASE3.md; patches 37-42; runtime\
    tekken4_rollback_overrides.cpp, tekken4_net.{h,cpp}): deterministic (no masks), snapshot/restore 1.2 ms, resim
    5.2 ms/frame with draw/VU1 cuts, whole IOP in the snapshot (sound-on deterministic), two-process UDP netplay with
    GGPO rollback, build-id handshake, input delay by ping, hash exchange every 30 frames: 0 desyncs at RTT 0/50/150 ms
    with 3 % loss (two instances on one PC). Human test: tools\net_play.ps1 (-Host / -Join <ip>, -Pad, -Sim).
  - Performance (docs\PERF.md, patches 43-56): 9 of 10 stages at 60 fps in Practice (Arena 30 -> 60); Building ~57
    (game-thread bound). Rollback self-test still 0 mismatches.
  Next: (1) a human test on two PCs / real WAN (tools\net_play.ps1); (2) phase 4 = lobby integration with the T5DR
  server (game id, T4 fighter/stage tables, separate ranking; touches TheWishin/T5DROnline-Source: only with the user's
  go-ahead); direct fight (skip menus), fixed online save; (3) Building stage to 60; (4) T5DR-level polish (replays,
  spectating, training rooms, launcher); (5) a real end-to-end run of tools\build_game.ps1 on a clean folder.
  Worktrees D:\tekken4-fork-rb / -music / -net / -perf hold the agents' branches (all merged into t4-us).
- **US BUILD SLUS-20328 (2026-10-29, branch us-slus20328), RESTART HERE.** User switched to the US game (frame
  data; simpler build). Ported without the PAL ELF: headless Ghidra (tools\ghidra_headless.cmd, 4454 functions; PAL had
  4459), find_missing_functions adds 359; tools\map_pal_to_us.py aligns PAL/US function lists by size (4405 matched,
  code delta 0 .. -0xc40); all 40 jump tables carried over (31 exact, 9 read from the US ELF); overrides rewritten by
  tools\port_overrides_us.py (data deltas from US code via tools\us_site.py: .data -0xe40, .sdata/.sbss -0x2700 (gp
  0x35cb70), .bss -0x2780); DATA.BIN LBN 401; CRC 0xB975F704. Camera log parked in runtime\pal\ (9 functions unmatched).
  PS2Recomp tree D:\tekken4-fork-ps2recomp branch t4-us = eb8688b + patches 01-32 (core.autocrlf=false; 18-23 and 30
  need --ignore-whitespace). Verified (logs\us_boot1, us_menu1, us_fight1, us_fight2): boot, intro movie, difficulty,
  mode select, char select, Story prologue, fight Kazuya vs Paul at full speed with native VU1 (same micro hash as PAL).
  US key path: 8:Start (skip movie), 13:Start (MEDIUM), 17:Start (STORY BATTLE), 21:Cross (Kazuya), 26:Start (skip
  prologue) -> fight ~32 s. Open: host audio device failed to open in the night run ("Failed to initialize playback
  device") although the driver streams; QA of all modes; build-from-ISO script; rollback (docs/ROLLBACK_PLAN.md).
To continue, open Claude Code in this folder and say: "read docs/status.md and continue".
- Done in session 1: toolchain installed, PS2Recomp tools built, analyzer seed + full recompile with 0 errors,
  Ghidra project (`ghidra/Tekken4`, non-shared) analysed with SDK names applied, Ghidra export recompiled.
- Done in session 2: Ghidra MCP tools approved and working in Claude Code. **Runtime base decided: upstream
  ps2xRuntime** (cherry-pick from the GoW fork at GS/VU1 time). ps2EntryRunner builds and runs; first stop found
  (see "First run"); 350 missing functions added (4 constructors + 346 vtable/callback targets) (see "Missing
  functions fix"); silent sound-driver override (see "Sound driver override"); MFIFO + D_ENABLE runtime
  patch (see "MFIFO + D_ENABLE patch"). Milestone 4 published (see "Publishing").
- Done in session 3 (stopped at the user's 80% usage report): milestone 5 (menu with all text, PAL60 picked as controller 1, Namco logo); the DMA/VIF1
  fixes upstreamed as PR #373 (PATH2 continuation redone to keep upstream's tests passing), pk stub issue #374,
  milestone 5 page (see "Publishing"). Display fixed: interlaced FRAME mode now shows the half-height buffer
  line-doubled, full screen like PCSX2 (patch 03 = PR #375, see "Display line repeat").
  The intro movie now plays (see "Intro movie").
  Strip gaps fixed (patch 05, see "Sprite strip gaps").
  Vibrating picture fixed (patch 06, see "Field offset").
  After the movie (Start skips it) the first-run difficulty screen works (see "Difficulty screen").
  Its dashed lines are fixed too (patch 08).
  **Milestone 6 reached:** Cross on MEDIUM opens the main menu (MODE SELECT: STORY BATTLE .. OPTIONS), as in PCSX2.
  Frame rate fixed: 60 fps on every screen so far (patch 09, see "GS speed").
  Character select works (IPU images decoded through FFmpeg, see "Character select").
  A fight loads and renders (Stage 1, Kazuya vs Law) but at ~7 fps: the VU1 interpreter (see "First fight").
  Native VU1 port started (stopped at the user's 95% usage report): the GoW VU1 engine is in (patch 11, 465/465
  tests), no native blocks generated yet (see "Native VU1 port").
- **INCIDENT 2026-10-22 09:54-09:56:** the project folder was wiped while 4 Grok tasks ran (cause unproven; Grok auto mode had no delete deny rule). Lost: game/, ghidra/ project, generated/, logs/, external/ trees (PS2Recomp, p15check, pr10, pcsx2, God-Of-War) and all uncommitted Grok work (sound-run, iop-sched, gs-review-fixes, jump-tables-merge, fight_compare). Code restored from the remote at 0500d03. Fixes: delete deny rules + tools/grok_clean.ps1, tools/backup_local.ps1 (~/tekken4-backup), push after every commit. TO REBUILD: external/PS2Recomp (clone ran-j/PS2Recomp at the commit pinned below, apply patches 02-18 by tools/build_runtime.cmd), game/ from the ISO, ghidra project (config/function_map.csv is in git), generated/ via the recompiler, worktrees p15check/pr10 only if needed. The four wave-3 Grok tasks lost their work and must be re-run from their prompts after the rebuild.
- **Fight fps after the recovery (2026-10-27 23:4x):** merged state (patch 19 + 40 jump tables + native VU1) = 24.7 / 26.1 / 26.8 fps (fight sec 60-119, GS 590-700 ms/s, TEKKEN4_PERF_LOG). A first measurement gave 12 fps: game/vu1/micro/vu1_62802e7b8abf4848.bin (captured VU1 micro memory, game data, gitignored) had been lost in the wipe and build_runtime.cmd silently builds the VU1 interpreter only without it (profile: 65% VU1Interpreter). Restored from the recovery; build_runtime.cmd now prints a WARNING and backup_local.ps1 copies game/vu1. Bisect proved jump tables and patch 19 are not the cause. Test harness lessons: run_capture.ps1 -Keys takes ONE comma-joined string; write toml with git show > file (PowerShell Set-Content adds a BOM that breaks ps2_recomp: exit 1); use python with chr(92) for backslashes in generated scripts.
- **IOP-SCHED-3 DONE (2026-10-28, session 5), RESTART HERE.** Idle-skip cache fixed and tested = **patch 21**
  (`patches/21-ps2xIOP-idle-skip-cache.patch`; fork clone H:\tekken4-fork-ps2recomp branch `iop-sched-3` = wave3-merge + 21,
  commit bf61916). The cache itself was sound; Grok's TEST was broken: its hand-written sleeper branched on t3 right after
  `lw t3` (R3000 load delay: the IOP CPU emulates it, so the branch saw 0 and the thread never slept) and lost ra across its
  own jal (looped forever), so no idle step ever happened and nothing could seal. Fixed the sleeper (nop + stack frame), the
  probe (two runEeCycles calls: the seal happens on a call's last idle step, the skip on the next call), and moved the
  schedule epoch into `IopKernel::insertReady` (every way a thread becomes runnable) instead of 9 scattered notes.
  Mutation check: removing the epoch bump, the DMA-start invalidation or the timrman invalidation each fails the test
  (CD completion callbacks have no test case). `TEKKEN4_IOP_IDLE_SKIP=0` turns the cache off (A/B with one exe).
  New `tools\build_iop_tests.cmd` (TEKKEN4_SRC honoured) builds and runs ps2_iop_emulator/import/compatibility tests:
  all pass; ps2x_tests 481/481 on the fork tree.
  **Fight A/B (one exe, fork tree = patches 01-21 + native VU1, keys as usual, alternating runs, fight sec 60-100):**
  cache on 27.85 / 28.22 fps, off 27.15 / 27.07 -> **+0.9 fps (~3%)**, same sign in both pairs and both halves of the
  window (logs\iop-sched-3-on1/off1/on2/off2, stats script idea: mean of "perf second N: F frames"). Picture unchanged
  (frame_70s Kazuya vs Law, frame_stats equal), no error lines. The fork build first came out WITHOUT native VU1:
  CMake's default vu1n_gen path is <tree>/../../tools, wrong outside external\; build_runtime.cmd now passes
  PS2X_VU1N_GEN explicitly (commit 6cfa64e).
  **Build trees:** the fork clone (TEKKEN4_SRC=H:\tekken4-fork-ps2recomp, branch iop-sched-3, generated code staged,
  out\runtime built) is the only tree that matches the committed patch stack 01-21 exactly. external\PS2Recomp still
  holds 01-20 + Grok's uncommitted iop-sched-2 WIP on top (checked: 20 reverses; 19 and 21 neither apply nor reverse),
  so build_runtime there warns and builds it as it is. Nobody resets it (no-delete rule). Decision for the user: make the
  fork clone the default build tree (scripts default SRC + backup_local), or keep setting TEKKEN4_SRC.
  Next goals, in order: (1) sound: clipping (movie PCM added after the SPU clamp) and the char-select silence
  (driver stops issuing libsd/cdvd calls after a 3.26 s one-shot); (2) fps toward 60 (GS ~700 ms/s, game thread
  ~13-18 ms/frame); (3) a CD-completion-callback case for the idle-skip test.
- **NEXT SESSION STARTS HERE (saved 2026-10-28 22:25, Claude at 74 % usage; user: "stop here, Grok works on
  its own until the usage reset at 12 am").** Running detached: Grok **arena-perf** (tree wt-arena-perf), **music-3**
  (wt-music, 300 turns), **hud** (wt-hud); **tools\grok_chain.ps1** (pid 81124, log logs\grok\chain-stage-sweep.log)
  UPDATE 22:45: **hud finished** (logs/grok/hud-final.json, conf 0.86: GAME/HOST/INPUT counters top-left, F3,
  fps unchanged; review + merge); **music-3 finished: hypothesis refuted** (conf 0.88; the zsiopdrv sifcmd handler
  cid 0 only stores a size at 0x52200; the first 10240 B stream block is filled, the refills are not; next lead:
  which IOP code refills 0xc7000 after 0x49620 consumes it; look at the EE send at 0x2296ac; no music task queued);
  arena-perf was at step 139/150 (may end without a result).
  starts Grok **stage-sweep** (docs/ai/prompts/stage-sweep.md: each stage 30 s in Practice, sound on, fps table +
  profile of unstable stages; measures only) when those three have finished. TO DO next session, in order:
  (1) `powershell -File tools\grok_list.ps1`; read logs\grok\<task>_<time>.json + <task>-notes.md for each;
  (2) review each code task: `tools\grok_tree.ps1 -Task <t> -Diff` (exclude ps2xRuntime/src/runner/register_functions.cpp,
  = generated game code), check its numbers, build + test in its tree (TEKKEN4_SRC=external\wt-<t>,
  TEKKEN4_BUILD_DIR=grok-<t>, tools\build_runtime.cmd / build_tests.cmd), run tools\run_fixed_fight.ps1 -Task <t>,
  then apply to the fork (author Pablo), export patches/NN, commit + push; music touches runtime/tekken4_overrides.cpp
  (its uncommitted edits sit in the main working tree: commit only the final, reviewed version);
  (3) rebuild the default build so tools\run_game.cmd gets them; ask the user to play;
  (4) stage-sweep table -> the next 60 fps work; user goals: perfect 60 in fights (movie is a perfect 30), HUD,
  then "completely control the graphics".
- **WAVE RESULTS (2026-10-28 ~21:50, session 6).**
  - **Input lag: patch 31** (fork 0df63e0, from Grok input-lag, reviewed + 2 fixes): key -> first changed frame
    median 29.8 -> 14.8 ms (tools\input_lag.ps1 -Task <t> -Mode fast -Present paced; logs\input_lag_claude1),
    fight 60 fps, 482/482. TEKKEN4_INPUT_LAG=1 logs per press; TEKKEN4_INPUT_LEGACY=1 = old path. User played
    (logs\user_path4, Practice Shinjuku 60 fps, Arena 38-44): "inputs feel snappier".
  - **Fixed test fight: tools\run_fixed_fight.ps1** (user's request): Practice, Kazuya vs CPU Yoshimitsu, -Stage
    (default arena), -Task <grok task>, -Env. The stage select opens on a RANDOM slot (shows a random card);
    Right from it = airport .. arena, Left once = arena (logs\fixed_try4..8). tools\stage_card.py checks the card
    (refs in logs\stage_refs, game imagery, not in git). run_capture.ps1: Select key (Tab), shots sorted
    numerically. TEKKEN4_RAND_SEED=<n> (runtime\tekken4_testseed_overrides.cpp) pins srand but does NOT fix the
    stage card (timing-dependent).
  - **User's "lag" in Practice:** (a) the Arena stage itself: 34 fps, ~1250 GL batches/frame (cage: TEX0/CLAMP
    per prim; airport 60 fps) -> Grok task arena-perf (prompt docs/ai/prompts/arena-perf.md); (b) runs during
    Grok builds stall (H: is a USB HDD shared by builds, ISO, game data, and an elevated python copying
    ~115 MB/s since 19:34 that is not ours).
  - **Music:** Grok music ran out of turns ($12): stream = VoiceTrans iop 0xc7000 -> spu 0x1b8000, SPU2 IRQ
    refills 256 B but the source is all zeros; IOP cdvdman HLE has no sceCdSt*. Continue: docs/ai/prompts/music-2.md
    (tree external\wt-music keeps its diagnostics; runtime/tekken4_overrides.cpp has its +38 uncommitted lines:
    do not stage into the fork until music lands).
  - music-2 also ran out of 150 turns ($11.6). Its lead: IOP sifcmd ordinal 10 (sceSifAddCmdHandler) is dropped
    (iop_rpc.cpp dispatchSifCmdImport -> setV0(0)), so EE sceSifSendCmd data may never reach zsiopdrv. **music-3**
    started 22:1x with 300 turns (docs/ai/prompts/music-3.md; grok_start.ps1 -MaxTurns now exists).
  - **User goals (22:2x):** (1) fps + input-latency counters in a corner -> Grok **hud** running (tree
    external\wt-hud, prompt docs/ai/prompts/hud.md; F3 toggles, TEKKEN4_HUD=0 hides); (2) a perfect 60 fps
    (user's last session averaged 57 incl. movie/loading; fights 60 except Arena -> arena-perf), then a
    per-stage fixed-fight sweep (run_fixed_fight.ps1 -Stage each) to find remaining dips; (3) later:
    "completely control the graphics" (graphics options; ask the user what that covers).
  - Escape no longer quits the game: patch 32 (fork, SetExitKey(KEY_NULL)); only the window X closes it.
- **GROK WAVE (2026-10-28 ~20:30, session 6).** User: "fix all of those at the same time by using grok".
  Running detached (tools\grok_list.ps1): **music** (tree external\wt-music, owns IOP sound files +
  runtime/tekken4_overrides.cpp), **input-lag** (tree external\wt-input-lag, owns pad/present files + new
  tools/input_lag.ps1), **test-mode** (no build, owns new tools/run_fixed_fight.ps1: fixed CPU opponent + stage).
  Prompts in docs/ai/prompts/{music,input-lag,test-mode}.md; brief docs/ai/grok-brief.md updated to today.
  grok_build.cmd / grok_run.ps1 now use external\wt-<task> automatically. Watcher: tools\grok_wait_all.ps1 -Each.
  Review per task: results logs\grok\<task>_<time>.json + <task>-notes.md; diff = tools\grok_tree.ps1 -Task <t>
  -Diff -> logs\grok\<t>-tree.patch; check the numbers, commit into the fork (author Pablo), export patch NN, push.
  Deferred until music lands (same files): moving the IOP/SPU mixing off the game thread (fps headroom).
  Also to do once test-mode is done (it runs Claude's out\runtime build): Escape quits the game (raylib's default
  exit key; the user hit it 3x by mistake) -> SetExitKey(KEY_NULL) after InitWindow, only the window X closes it.
  The user plays to show the fixed-fight menu path: scratchpad user_play.ps1 holds the run lock, frame_<s>.bmp
  every second into logs\user_path<n>.
- **SOUND PLAYBACK FIXED + FPS WITH SOUND (2026-10-28, session 6).** User: "sound is much better
  now!". Cause of the choppy sound: raylib's UpdateAudioStream pads every write up to the stream sub-buffer
  (48000/30 = 1600 frames) with silence; we wrote 1024-frame pieces = ~36 % silence in 12 ms gaps, and the queue
  fell behind until it dropped whole seconds (the WAV was written before that step, so it never showed). **Patch 30**
  (fork 7108444): DeviceQueue, filled by the game thread, drained by raylib's audio thread (SetAudioStreamCallback),
  +-5 % rate control around 2048 frames, re-prime after an underrun; TEKKEN4_AUDIO_STATS=1 logs
  missing/dropped/level/rate every ~5 s. logs\audio_fix1: steady state missing=0 dropped=0; short underruns only
  during loads (game thread stalls, up to ~130 ms per 5 s).
  FPS: before patch 30, sound on cost the fight its headroom (logs\perf_sound1: 51-58 fps, 27/38 s below 58;
  sound off logs\perf_nosound1: 60 every second). Profile (logs\prof_sound2, TEKKEN4_PROFILE=60:25, needs ~15 s
  after the window for symbols): game thread idle 15.6 % vs 29 % without sound; SoundEngine::drainOutput 5.1 %,
  SRW locks ~6 %, IopEmulator::runCycles 1.5 %, memmove 3.1 %: the IOP + SPU mixer run on the game thread from
  EeScheduler::accountCycles (drainMixedAudio). After patch 30: logs\audio_fix1 fight 60.1 avg, 1/45 s below 58
  (different stage per run, so confirm on a fixed stage).
  **Next, in order:** (1) the user's test mode: NO Story/Arcade for tests; use a CPU mode where we choose the
  opponent and the stage (Practice or VS vs CPU: find the key path, then fixed-stage fps runs sound on/off);
  (2) **music is missing** (user): effects + voices play, BGM doesn't (the driver stops streaming after the
  3.26 s one-shot, see sound-merge findings); (3) **input lag** (user request): measure raw Windows key event ->
  guest pad read -> first presented frame that reacts, then cut it (raylib polls input once per host frame;
  pad read happens on the game thread; GS thread + swap add frames); (4) fps headroom with sound: move IOP/SPU
  mixing off the game thread or cut its lock traffic.
- **USER PLAYTEST + KEYBOARD LAYOUT (2026-10-28, session 6).** The user is playing with
  tools\run_game.cmd. At their request the keyboard is now (patch 29, fork eed3828): D-pad = WASD,
  Cross/Circle/Square/Triangle = Down/Right/Left/Up arrows (X/C/Z/V still work), Start = Enter, L1/R1 = Q/E,
  L2/R2 = LeftShift/RightShift, Select = Tab. The keyboard now also works with a gamepad plugged in (before, the
  pad backend ignored it then). tools\run_capture.ps1 presses W/A/S/D for Up/Left/Down/Right (key names unchanged).
  PCSX2's own keyboard config (arrows = D-pad) is unchanged. Next: go through what the user reports.
  Sound: on by default in tools\run_game.cmd (TEKKEN4_SOUND=1, user's choice 2026-10-28; =0 for the silent
  stand-in). tools\run_capture.ps1 stays silent until one capture with sound is checked against the standard
  fight key path (timing, fps with GL, no crash); the last sound run (2026-10-27, CPU renderer) reached the fight.
  **User report with sound on:** intro movie audio "super flickery", much of it missing, unintelligible, voices
  not heard; Story Battle character select: the narrator's voice line plays. Matches the open items (movie PCM
  after the SPU clamp; WAV shorter than wall clock = fewer samples than real time -> gaps). Not worked on yet.
  **FREEZE after winning a Story Battle fight: FIXED, confirmed by the user** (win -> replay plays, Story
  continues; generated/ regenerated, built 19:45, no missing-target in the log). logs\playtest4_story_freeze.log
  ends with [guest-branch:missing-target] DirectJump 0x268c30. FUN_00268bf8 is a switch on a1 (1..5 via the jump
  table at 0x32f350 -> 0x268c20/0x268c28); its default case 0x268c30 (return 0) had no function entry. The
  finder ignored branches leaving a function: tools\find_missing_functions.py --escapes now seeds them
  (map = --data-pointers --escapes --write). It adds exactly 2: FUN_00268c30 and FUN_002914d8 (libmpeg tail-jump
  target of _dispRefImage/_dispRefImageField, a latent movie freeze). No branch lands mid-function.
  function_map.csv merged by hand (same merge as postprocess_ghidra_export.py, which needs Ghidra running).
- **PCSX2 COMPARISONS + GUEST RAND (2026-10-28, session 6), RESTART HERE.** Our CPU opponents never varied (arcade
  always Law, story always Steve, at any key timing) while PCSX2 picked Christie, Marduk, Paul. Cause: the recompiler
  maps the game's libc rand (0x2a3178) by name to the runtime stub (host std::rand), but the game's srand
  (0x2a3168) runs as game code and seeds the guest state (reent + 88, reent = *0x3059d4) that the stub never reads;
  the host generator was never seeded. **Fixed by an override** (runtime\tekken4_overrides.cpp guestRand, commit
  1ff344e): the game's own routine, disassembled from the ELF: 32-bit LCG next * 1103515245 + 12345, result
  & 0x7fffffff. Also drives the CPU fighters' AI decisions. Now opponents vary (Law, Yoshimitsu, Hwoarang, ...).
  Upstream: reported as https://github.com/ran-j/PS2Recomp/issues/406 (2026-10-28; suggested fix = stop
  stubbing rand/srand so the guest code runs). Drop our override once upstream fixes it.
  Story Battle is a handy test path: our keys ...,36:Cross,41.5:Cross (STORY BATTLE = default entry),
  46:Cross (Kazuya), 51:Start (skips the prologue; Circle = next, Cross does nothing); PCSX2: 38, 43.5, 48, 54.
  **Side by side with PCSX2, same stages:** mall interior (logs\gl_rand2 vs logs\pcsx2_story1\pcsx2_74s.png), beach
  (gl_rand5 vs pcsx2_story2), airport (gl_rand4 vs pcsx2_fight1): sky, lights, billboards, floors, characters, HUD
  all match; no rendering difference found beyond the name plates (patch 28). Tools: scratchpad dump_mips.py
  (ELF disassembly of a few words) was handy; GhidraMCP was not connected this session.
- **PCSX2 BACK + NAME PLATES (2026-10-28, session 6).** PCSX2 2.8.2 portable re-installed in external\pcsx2
  (official GitHub release asset pcsx2-v2.8.2-windows-x64-Qt.7z, sha256 7dfc829c...b4 checked; download kept in
  external\pcsx2_download). Config written by hand: portable.ini + inis\PCSX2.ini (BIOS folder E:\God Hand + Emulator\bios,
  SCPH-70004_BIOS_V12_PAL_200.BIN, used in place, not copied; PINE slot 28011; fast boot; 1x; keyboard pad 1:
  arrows, Return = Start, X = Cross, Z = Circle, C = Square, V = Triangle). tools\pcsx2_capture.ps1 drives it again;
  the game text is German (BIOS language), irrelevant for pictures. PCSX2 keys = ours + 2 s:
  12:Down,14:Cross,17:Left,18.5:Cross,32:Start,38:Cross,42:Down,43.5:Cross,48:Cross -> fight (logs\pcsx2_fight1:
  Kazuya vs Christie, airport stage; arcade opponents are random, so stages differ between runs). The user's PCSX2
  1.6 on E: has pad bindings only for an XInput controller (no keyboard), so neither of us can drive it.
  **Patch 28** (fork gs-gl f4220d3): GL fight name plates. Both plates are drawn from one area (0x3b60, rows 0-17,
  re-uploaded per name); the partial row re-decode (patch 23) kept the hash of the last full decode (patch 24), so
  after the next invalidation the texture was revalidated holding the other name: player 1 showed "LAW" instead of
  "KAZUYA" in every GL fight. The hash is now refreshed after a row re-decode (logs\gl_names2: KAZUYA vs LAW).
  Found by comparing with PCSX2/CPU frames. **Next:** more side-by-side checks against PCSX2 (other stages via the
  attract demo or later arcade stages), then a longer play session by the user.
- **GL IS THE DEFAULT RENDERER (2026-10-28, session 6).** tools\run_game.cmd and tools\run_capture.ps1
  now set PS2X_GS_BACKEND=gl unless it is already set (PS2X_GS_BACKEND=cpu = the software renderer). Full pass with GL
  (logs\gl_full1\contact.png, standard fight keys): PAL60 dialog, namco logo, **intro movie**, difficulty, mode select,
  character select, fight with the textured stage, **fight 60 fps** (43 of 44 s at 60). ps2x_tests 482/482.
  **Intro movie fixed = patch 27** (fork gs-gl eed6f72, `patches/27-ps2xRuntime-gs-gl-rt-uploads.patch`): the movie
  player uploads each picture straight into the back buffer (CT32, 40 columns of 16x448 at block 0, found with the new
  "[gs-hw] transfers" summary of GOW_GS_HW_STATS). The GL backend wrote uploads only into its memory image, so the back
  buffer target stayed black. Now a host->local transfer to a target's base in the target's format (width up to the
  target's, like draws) is also written into the target's GL texture at the next flush (applyRtUpload, "rtUploads=" in
  the stats) and its blocks no longer count as newer in memory; uploadedSinceDraw uses only the per-block record.
  Also: "[gs-hw] rt texture tbp=.. -> target|store" log, tools\contact_sheet.py (half-size grid of a run's
  frame_NNs.bmp -> contact.png, no Pillow). Key timing note: heavy logging (GOW_GS_HW_XFERRANGE, big dumps) slows the
  boot and the "Start game? Yes/No" keys then land wrong ("Starting game under normal display mode" = PAL50, which
  waits there); use the stats summaries instead.
  **GL stability (logs\gl_stability1, 430 s, standard keys):** no crash, no GL error: fight, game over, GREATEST
  SURVIVORS ranking, attract demo fight, intro movie replay from 375 s (30 fps = movie rate); 326 s at 60 fps. Whole
  intro movie with GL: logs\gl_moviefull1\contact.png (the black frame ~15 s in is the movie's own cut, same in both runs).
  **Next:** (1) PCSX2 side by side of the fight (the user's PCSX2 1.6 on E: runs the game; they drive it, we capture
  its window read-only); (2) remaining GL differences (unsupportedBlend ~2,400/s in the fight, the frame-copy strips'
  abe toggling = ~280 tiny batches/frame); (3) play-test longer runs with GL (stability like logs\stability1);
  (4) sound only if it crashes.
- **GL STAGE FIXED (2026-10-28, session 6).** Patch 26 (fork gs-gl, `patches/26-ps2xRuntime-gs-gl-stage-textures.patch`):
  the GL fight now shows the textured stage (mall, palm trees, "AQUA GARDEN" sign, lit shops) like the CPU renderer,
  without its white speckles, still a steady 60 fps (logs\gl_stage3\frame_60s/90s.png). Cause: every stage texture
  (T4/T8 pages at blocks 0x2440-0x3300) was sampled through findReinterpretSource from render target fbp 290 (a
  640x448 CT32 target of the menus whose memory the stage textures were later uploaded into). uploadedSinceDraw
  could not see those uploads: the upload log keeps the last 2048-4096 records and the per-frame character uploads
  had pushed the stage-load ones out. Now each target keeps the writeSeq of the last upload into each of its blocks
  (RenderTarget::blockUploadSeq, filled in BeginTransfer), which never forgets. Also in patch 26: GS CLAMP region
  modes in the shader (REGION_CLAMP / REGION_REPEAT with MINU/MAXU/MINV/MAXV, like gs_cpu_backend's
  wrapTextureCoordinate; the stage atlases use them on ~95% of draws; GoW treated them as clamp), and debug output
  under GOW_GS_HW_STATS / GOW_GS_HW_DUMP: "[gs-hw] reinterpret tbp=.. from fbp=.." (first sighting of each pair),
  "[gs-hw-dump-tex]" (CLAMP, TEX1, texel range per batch), GOW_GS_HW_RTDUMPSTEP=<n> (every n-th batch of the RT dump).
  Tools: scratchpad-style ppm->png converter not in git (bmp_to_png.py handles BMP only).
  PCSX2: the user's 1.6 on E: (GSdx D3D11) runs the game; PrintWindow(PW_RENDERFULLCONTENT) captures its window
  read-only, but its LilyPad pad ignores our posted keys, so the user drives it. The portable 2.8.2 in
  external\pcsx2 was lost in the 2026-10-22 wipe.
  **Next, in order:** (1) check menus / character select / intro movie with GL after patch 26 (the movie was black;
  the same uploadedSinceDraw bug may have caused it); (2) PCSX2 side by side of the fight; (3) make GL the default in
  run_capture/run_game; (4) sound only if it crashes (user, 2026-10-28).
- **GL FIGHT AT 60 FPS (2026-10-28, session 6).** Patch 25 (fork gs-gl ee03022,
  `patches/25-ps2xRuntime-gs-gl-clut-batching.patch`): with PS2X_GS_BACKEND=gl the fight runs a **steady 60 fps at full
  game speed** (in-game clock 30 s per 30 real s; logs\gl_why2, fight sec 51-103 all 60, GS ~130 ms/s on the game
  thread; was ~35 fps / ~0.6x). Cause found with the new GOW_GS_HW_STATS "batch ends" line (why each GL batch ended,
  which state fields differed): Tekken writes the same TEX0 with CLD=1 before every strip and the backend flushed the
  pending batch on every LoadClut = 92% of ~120k batches/s. Now a batch resolves its palette when it starts
  (pendingPalette, also used by the render-target reinterpret path) and ends only when the next indexed draw sees a
  different CLUT; GSTextureStore::LoadClut returns whether it wrote CLUT memory (hash only recomputed then).
  ps2x_tests 482/482. Batches now ~1300/frame, ended by real state changes (tex0, clamp, texsize, abe, alpha).
  **Open (picture):** the GL stage is darker and flatter than the CPU renderer's (compare logs\gl_why2\frame_90s.png
  with logs\stability1\frame_150s.png: CPU shows the bright "Aqua Garden" mall, palm trees, lit windows; GL a dark
  blue night-like hall with flat colours). Already so before patch 25 (logs\gl_fight8\frame_90s.png), so not caused
  by it. Characters and HUD look right. The CPU shots have white speckles on the fighters (CPU renderer bug?).
  **Next, in order:** (1) the GL stage picture: PCSX2 side by side for ground truth, then find which passes are wrong
  (unsupportedBlend ~2,400/s, stage lighting / multi-pass blends, CLUTs at cbp 0); (2) intro movie black with GL;
  (3) make GL the default in run_capture/run_game; (4) menus/char select at 60 fps already with GL.
- **GL FIGHT SPEED (2026-10-28 ~10:40, session 5), superseded by patch 25 above.** Patch 24 (fork gs-gl 156eca7): fight with
  PS2X_GS_BACKEND=gl ~32.5 -> ~35-36 fps. The limit is the GL thread (GSThread): the game thread blocks in
  GSThreadedBackend::PublishLocked (queue backpressure, 52% of its time), not in sync points. GL thread profile
  (TEKKEN4_PROFILE=80:10 TEKKEN4_PROFILE_THREADS=GSThread, new: thread-name filter in runtime/tekken4_overrides.cpp):
  NVIDIA driver ~30% (DrvPresentBuffers/DDI escapes: ~120k GL batches/s = ~3500 per frame, each with its own state +
  draw call), index decodes ~8%, CLUT ~10%, findReinterpretSource 10% (fixed after that profile).
  Done: hash revalidation of re-uploaded identical textures (~60% of refreshes), upload-log tail scan, range/drawn-area
  tests before the depth check, 64-bit CLUT hash. **Biggest open lever found:** ~3 synchronous GPU readbacks per frame
  from clutFromTarget: CT32 16-entry CLUTs at cbp 0 (the back buffer's first block, drawn area) for T4 textures.
  **Fixed (fork cdc3ad2, in patch 24): CLUTs now come from the uploaded bytes by default** (TEKKEN4_GL_CLUT_RT=1 = GoW's
  readback): those readbacks gave wrong palettes, which is why **the stage was invisible**; with the fix the stage
  draws (floor, hall, pillars, spectators: logs\gl_fight7_clut0, gl_fight8) and the fight runs **36.6 fps** (33-40,
  logs\gl_fight8; CPU renderer ~28). Game speed ~0.6x until 60 fps.
  **Next, in order:** (1) cut GL batches per frame (~3500/frame, ~5 draws per batch: sameState too strict? uniforms
  re-sent per batch?) = the driver's ~30% of the GL thread, the fight's limit now; (2) compare the GL fight picture
  with the CPU renderer / PCSX2 side by side (same characters: the key timing picked Law vs Law once); (3) intro
  movie black with GL; (4) then make GL the default in run_capture/run_game. Game speed is frame-locked: 60 fps is
  needed for full speed.
- **GPU RENDERER (2026-10-28, session 5).** Patch 22 = God of War port's OpenGL GS renderer
  (GSThreadedBackend(GSHwBackend), GPL-3.0, copied unchanged + ~150 lines glue) behind **PS2X_GS_BACKEND=gl**; the CPU
  renderer stays default. Patch 23 = Tekken fixes: Present scale 1 / DH+1 lines / interlaced line repeat + field
  offset in the present shader, index-texture dirty-row re-decode (font glyph uploads re-decoded the whole font page),
  table-based GSMem::ReadIndexRun (+ test, ps2x_tests 482/482), render target format takeover (PAL60 makes the
  16-bit display buffer fbp 210 a 32-bit one; GoW skipped every draw there = black). Fork branch gs-gl (b954d09).
  **Results with GL (logs\gl_fight2, RTX 5090):** first menu 60 fps (CPU 60), char select 60 (CPU 48), fight
  30-34 fps (CPU ~28) with the game thread still ~600 ms/s inside GS calls. Picture: menus, logo, difficulty, main
  menu, fighters and HUD correct and sharp; **the stage (floor, hall, palms) is missing (black)**, only far
  spectators show; the intro movie is black; unsupportedBlend ~2000/s in the fight. PS2X_GS_HW_SCALE=2 repeats the
  frame copy horizontally (keep 1). Next: (1) stage geometry missing (GOW_GS_HW_DUMP / RTLOG / NODEPTH / NOATEST
  switches to bisect: depth? blend? a Z-format target?); (2) where the game thread waits in the fight with GL
  (TEKKEN4_PROFILE + TEKKEN4_PROFILE_THREADS=all: GSThreadedBackend sync points, LoadClut, FINISH); (3) movie.
  Run it: set PS2X_GS_BACKEND=gl (run_capture / run_game inherit it), GOW_GS_HW_STATS=1 for counters.
- **Playability check (2026-10-28, user: make the game playable, sound only if it crashes):** default build tree is now
  the fork clone (commit 80512fe). Stability (logs\stability1, 430 s, usual keys then hands off): no crash, no error
  line; fight -> CPU wins -> game over -> attract (Greatest Survivors at 390 s). **Game speed is frame-locked:** the
  in-game clock went 00:01.93 (70 s) -> 01:06.56 (230 s) = 65 game s in 160 wall s (~0.4x) at 25-31 fps, so the
  fight plays at under half speed until it renders 60 fps. Fight game thread (Grok stackprof iop-sched-2-after):
  ~37% waiting for GS drawing threads (LoadClut ~20%, Submit page conflicts ~16%), texture uploads ~11%
  (writeImageTransfer<PSMT8>), VU1/VIF/IOP <= 2% each. Plan: port the God of War port's OpenGL GS renderer
  (GSThreadedBackend(GSHwBackend), same GSRasterBackend interface as ours; machine has an RTX 5090 and 8 logical
  CPUs) behind a switch, CPU renderer stays default until the GL one matches it. GoW repo re-cloned into
  external\God-Of-War-Native-Port (lost in the wipe).
- **WAVE 3 MERGED (2026-10-28).** Working copy is H:\tekken4-recomp (F: is never touched). Clean merge done on a fork
  clone H:\tekken4-fork-ps2recomp (branches: wave3-merge = base eb8688b + patches 01-19 + patch 20; wave3 = raw Grok output incl. the
  unfinished iop-sched-2). Tests on the fork: ps2x_tests 481/481. patches/20-ps2xRuntime-gs-review-fixes-and-sound-merge.patch = gs-review-fixes
  (self-overlap serial draw, truncating PageId stride, CLAMP/REGION texel marks, each with a test) + sound-merge (IOP heap top-down gated on
  TEKKEN4_SOUND=1, sceCdRead FAIL log, TEKKEN4_SOUND_TRACE, heap-direction test). NOT merged: iop-sched-2 (iop_kernel.*, iop_emulator.*,
  iop_emulator_tests.cpp in the fork branch wave3): its idle-skip cache test FAILS ("cache never sealed", ps2_iop_emulator_tests, built with
  -DPS2X_IOP_BUILD_TESTS=ON, which tools/build_tests.cmd does not do). Grok ended with verdict pending ($11.6, 150 turns).
  sound-merge findings: char-select silence = driver issues no further libsd/cdvd call after a 3.26 s one-shot (LSN 1045690); short WAV = guest IOP
  time; 1184 clipped samples = movie PCM added after the SPU clamp (not fixed). Next: (1) relaunch or do iop-sched-3 (make the idle-skip cache
  seal, run ps2_iop_emulator_tests, then paired fight fps); (2) fix sound clipping + silence; (3) fps toward 60 (GS depth-pass pixels, game-thread
  ~13-18 ms/frame); (4) apply patch 20 to the main external/PS2Recomp via build_runtime (its tree already holds those edits plus iop-sched-2 WIP:
  leave it, nobody deletes). Safety: no deletes by anyone, push after every commit, tools/backup_local.ps1 (fixed 2026-10-28: grok_start had a
  tab/backspace in its path so it never ran). Usage meter needs recalibration (ask the user for the 5 h %).
- **RECOVERY 2026-10-27 (after the F: wipe, see INCIDENT):** project now lives in H:\tekken4-recomp (F: stays untouched; the other session recovered the old folder into H:\Recovered, user-owned: copy from it, never modify). PS2Recomp rebuilt at eb8688b + patches 01-18; game/ re-extracted from the ISO (ELF sha1 ok); generated/ regenerated. Recovered Grok work merged: (a) jump tables: 40 validated [jump_tables] in config/ghidra_export.toml (unresolved JR sites 159 -> 146 per Grok; 212 warning lines now); (b) patch 19 = iop-sched (kernel scheduling cache: Grok measured fight 24.8 -> 27.4 fps, leaf 9% -> 3%) + sound-run (TEKKEN4_SOUND=1: real zsiopdrv audio, IOP heap bumps top-down from 0x1F0000 fixing ps2_sif_dma_tests:203, mixer clamp), and runtime/tekken4_overrides.cpp (sound hook, only with TEKKEN4_SOUND=1). Verified: build_tests 478/478; run with all 9 keys (keys must be ONE comma-joined string: run_capture.ps1 -Keys "10:Down,12:Cross,..."; an array through -File binds only the first key) reaches the fight (Kazuya vs Law, Aqua Garden), no-sound and sound runs both non-blank. Not recovered: iop-sched-2, sound-merge, gs-review-fixes (had just started). Still open: character-select 20 s silence, WAV shorter than wall clock, no TEKKEN4_SOUND-unset capture of the heap change beyond this smoke run, fight fps not re-measured.
- **Resume at (2026-10-22 ~10:00, after the batch review):** patch 18 (GS throughput) is committed, fight ~26-30 fps; PR #383 (patch 17) is open upstream. Four Grok tasks run in parallel (prompts docs/ai/prompts/): gs-review-fixes (patch-14 review fixes), jump-tables-merge (validated [jump_tables] into config/ghidra_export.toml, local only), iop-sched-2 (kernel idle cache; owns iop_emulator.cpp) -> logs/grok/iop-sched-2.patch, sound-merge (heap/silence/clipping, no iop_emulator.cpp) -> logs/grok/sound-merge.patch + sound-merge-overrides.patch. When they finish: batch review by a Sonnet subagent (tools/grok_wait_all.ps1 -PollMinutes 5): turn iop-sched-2 into patch 19, then sound-merge into patch 20 (+ override commit), retest on a clean tree (tools/build_tests.cmd honours TEKKEN4_SRC now), regenerate after the jump-tables merge, fight run numbers-first. fight-visuals: Kazuya 1P vs PCSX2 2P after Cross on character select = pad-input difference, not renderer (open). Known: frame shots later than ~75 s are not written. Duplicate commits 135577e/caeaced both carry patch 18 (same content). Uncommitted on purpose: runtime/tekken4_overrides.cpp (sound-run WIP, breaks clean builds until sound-merge lands).
- **Resume at (2026-10-22 ~07:50, low-burn mode, weekly 90% = info only, weekly resets Mon 2026-10-26 07:00):**
  grok-manager stopped; no Claude polling. Grok tasks running at 07:50 (results land in logs/grok/<task>_*.json,
  hung exits are ended by the wrapper watchdog): gs-throughput, sound-run, fight-visuals, iop-sched, fpu-pr.
  BATCH REVIEW, in order: (1) fpu-pr -> push branch ee-fpu-vu0-macro-semantics + gh pr create (notes
  logs/grok/fpu-pr-notes.md); (2) gs-throughput -> patch 18 from the clean baseline (external/ps2recomp-p15check
  has 01-17 applied), clean_build + fight frame shots, then launch gs-review-fixes (docs/ai/prompts/), then merge
  jump-tables (logs/grok/jump_tables.toml into config/ghidra_export.toml, regenerate); (3) sound-run -> its test
  fix (ps2_sif_dma_tests:203) must pass, then patch the sound changes (IOP/audio files + runtime/tekken4_overrides.cpp);
  (4) iop-sched -> patch if tests pass and fps improves; (5) fight-visuals -> read the difference list.
  Tools: tools/grok_list.ps1 (running tasks), tools/clean_build.ps1, tools/frame_stats.py, tools/wav_stats.py,
  tools/grok_retro.py, tools/usage_meter.py. Grok retro procedure: docs/ai/grok-retro.md.
- **Overnight 2026-10-22 (user asleep, wants uninterrupted work):** session-only cron jobs: hourly check at :17, resume at 05:52 after the usage window reset (53% at 01:46). 9 Grok tasks run detached (sound-run, review-patch14, qwc-pr in worktree external/ps2recomp-pr6, jump-tables, memcard, gs-throughput, game-thread done -> game-thread-fixes, usage-meter); grok-manager subagent watches them (digests in logs/grok/digest.md). Camera compare in flight: logs/camera_ours2 (TEKKEN4_CAMERA_LOG) vs logs/pcsx2_camera_probe (tools/pcsx2_camera_probe.ps1). PC power plan: sleep/hibernate never.
- **Usage meter (2026-10-22):** `python -I tools/usage_meter.py --status` (estimate from transcript token counts,
  calibrated to /usage: `--calibrate PCT --resets HH:MM`). Hooks installed in .claude/settings.local.json
  (UserPromptSubmit + PostToolUse, one context line per threshold 50/60/70/75/78/85/90/95); live (the 70% notice
  arrived on its own at ~04:30). Recalibrate after each /usage reading.
  jump-tables (Grok, logs/grok/jump_tables.toml: 41 tables, unresolved JR 159 -> 142) waits to be merged into
  config/ghidra_export.toml until no Grok work task is building (regenerates generated/ for everyone).
- **Resume at (2026-10-22 ~01:40, session 4):** fight 18-21 fps after patch 14 (was 9-13, see "GS drawing threads
  without stop-and-go"). Start the **grok-manager** subagent first (docs/ai/grok-manager.md, model sonnet; it watches
  Grok and sends digests, digests also in logs/grok/digest.md). Grok **sound-run** (work, real zsiopdrv audio behind
  TEKKEN4_SOUND=1, prompt docs/ai/prompts/sound-run.md, OWNS line at its top) was relaunched 01:3x; if it finished,
  review its diff + listen to its WAV. Done by Grok, not acted on yet: **fight-camera**
  (logs/grok/fight-camera_20261022_005358.json: camera = FUN_00182430 -> FUN_0018e1e0 eye=base+dir*1000 ->
  FUN_00193800 look-at; compare plan: u32 0x2AA0D0/0x2AA0D4 -> cam = p+0xF08 -> idx = *(cam+0x174) -> 4x4 at
  0x01CE2270 + idx*0xC0, 0x40 bytes + f32 slot+0x74, PCSX2 via tools/pine.py vs ours) and **upstream-qwc**
  (logs/grok/upstream-qwc_20261022_005358.json: drop refreshPacketBuilderPendingCount, ADD the qwc once in
  terminatePacketBuilderState, rewrite the live-qwc test, add a stub+game-close test; conf 0.5, contra listed).
  Next: (1) camera live compare; (2) more GS speed (profile the drawing threads now that they run); (3) qwc PR.
- **Main config is now `config/ghidra_export.toml`**, reading `config/function_map.csv` (Ghidra functions + `extra_functions.csv`). The analyzer seed is kept for reference.
- Build loop: `ps2_recomp config/ghidra_export.toml` -> `tools\stage_generated.cmd` -> `tools\build_runtime.cmd`
  (~3.5 min clean; applies `patches\*.patch` first) -> `tools\run_game.cmd` (close the window to stop; output in `logs\run.log`).
- Look at it: `powershell -File tools\run_capture.ps1 -Shots 8,25` (our build: hides the debug panel, screenshots +
  stdout in `logs\run_<time>\`), `powershell -File tools\pcsx2_capture.ps1 -Shots 15` (same in the user's PCSX2,
  the ground truth). Runtime tests: `tools\build_tests.cmd` (PS2Recomp's ps2x_tests with all patches, 465/465).
- Not in git (rebuild/re-extract if lost): `external/` (clones + Ghidra + PCSX2 + MCP venv, see Pinned
  dependencies), `game/disc/` (7-Zip from the ISO), `generated/` (rerun `ps2_recomp config/analyzer_seed.toml`).

## Milestones
- [x] 0. Project scaffold, disc files extracted, ELF inspected
- [x] 1. Toolchain installed: VS 2022 Build Tools 17.14 (MSVC), CMake 4.4.4, Ninja 1.13.2, Temurin JDK 21.0.12
      (JAVA_HOME set), Ghidra 12.1.4 + EE plugin v2.1.38 + GhidraMCP 2.0, PCSX2 2.8.2 portable
- [x] 2. PS2Recomp host tools build from source (`tools\build_ps2recomp_tools.cmd`)
- [x] 3. Ghidra analysis + function map exported, recompiled output compiles and links into ps2EntryRunner
- [x] 4. Boots past startup without crashing (main loop runs at ~47 fps, 2026-10-21)
- [x] 5. Something on screen (Namco logo / first menu) (2026-10-21: the display-mode menu renders, PAL60 picked
      as controller 1, confirmation answered, Namco logo shows; vertical scaling still off)
- [x] 6. Menus and controller input (2026-10-21: boot -> PAL60 -> movie -> difficulty -> main menu, matching PCSX2)
- [ ] 7. A fight: two characters on a stage, correct rendering, steady frame rate
- [ ] 8. Sound, saves, PC features

## Pinned dependencies
| Repo | Commit | Date |
|---|---|---|
| ran-j/PS2Recomp | eb8688b (local branch `dmac-mfifo` = eb8688b + PR #372) | 2026-10-14 |
| Waffle565/God-Of-War-Native-Port | 514f891 | 2026-10-18 |
| chaoticgd/ghidra-emotionengine-reloaded | v2.1.38 (asset for Ghidra 12.1.4) | 2026-10-04 |

## ELF findings (SCES_508.78)
- Stripped: no symbol table and no source-file strings, so names come from Ghidra analysis plus
  PS2Recomp's embedded SCE SDK symbol database (`ps2_analyzer` can match SDK functions).
- Section headers are intact, so section boundaries are reliable.
- 22 `.DVP.overlay` sections = VU microcode uploaded at runtime, so VU1 is heavily used (expected hard part).
- `libmpeg` + `libipu` present: FMVs are decoded through the IPU.
- No `libsd`/`libsdr` version strings: sound is probably a Namco IOP driver loaded from DATA.BIN.
- `.bss` is ~27 MB: the game statically claims most of EE RAM.
- PAL build: check whether a 60 Hz mode exists; frame timing is critical for a fighting game.

## First pass: analyzer seed + recompile (2026-10-20)
- `ps2_analyzer game/disc/SCES_508.78 config/analyzer_seed.toml` (1 s): 4513 functions, 567 SCE SDK
  matches from the embedded DB (399 renamed, 168 added), 224 stubs with runtime handlers, 339 SDK functions
  without handlers, **0 instruction patches** (so the GoW "SMC NOP patch" problem doesn't apply), only 1 jump table found.
- Entry `0x180088` calls `_InitSys`, `sub_00281260`, `sub_001969F8`.
- Seed TOML's `output` changed from `config/output/` to `generated/` (gitignored).
- `ps2_recomp config/analyzer_seed.toml` (3 s): 4372 recompiled + 141 stubs, 0 decode failures,
  0 unhandled instructions, 0 errors. 4527 files / 89 MB in `generated/`.
- 232 warnings, all "unresolved JR/JALR" in 116 functions (mostly switch tables), handled by fallback
  entries (27156). Ghidra's jump-table recovery should cut these down.
- Recompiler reports `gp=0x0`; crt0 presumably sets $gp at runtime. Check this if small-data accesses look wrong.

## Ghidra pass (2026-10-20)
- Ghidra 12.1.4 + EE plugin, Standard Defaults analysis (Decompiler Switch Analysis on, Aggressive Instruction
  Finder off): 4388 functions, all `FUN_` (Function ID named nothing).
- SDK names: `tools/ghidra_apply_sdk_names.py --apply` (via GhidraMCP HTTP) renamed 494 + 3; then
  `tools/ghidra_scripts/ApplySdkNames.java` (run from Script Manager) created 71 functions Ghidra had missed
  (kernel handlers, unused SDK code, C++ runtime). Now 4459 functions, 563/567 SDK names applied.
- 4 SDK functions sit inside other Ghidra functions and need a manual split check:
  `_initSeq` 0x0028c840, `_markOutput` 0x002914d8, `__eh_rtime_match` 0x0029be10, `__cp_exception_info` 0x0029ebb8.
- The export was taken before the last 3 renames: re-export (and rerun the post-process) next time in Ghidra.
- After each export run `python -I tools/postprocess_ghidra_export.py` (repo-relative paths, output to
  generated/, writes the functions-only CSV).

| Function map | Functions | Stubs | Unique unresolved JR sites | Output |
|---|---|---|---|---|
| analyzer seed | 4513 | 141 | 169 | 89 MB |
| Ghidra export incl. 23.5k code labels | 28004 | 273 | 312 | 286 MB |
| **Ghidra functions only (current)** | 4459 | 273 | 155 | ~80 MB |

- Correction to an earlier assumption: the export CSV has no jump-table data, so Ghidra's switch analysis does
  not resolve JR sites for the recompiler. The extra warnings with labels came from case/entry labels that
  start mid-function (131 of 152 only appear under `entry_*`, the rest under `caseD_*`/`default`).
  Unresolved JR sites still run via fallback dispatch. Real fix later: feed jump tables into `[jump_tables]`.

## Lessons from the God of War port (Waffle565)
Their runtime is a full PS2Recomp fork on the repo's `origin/runtime` branch (read with
`git -C external/God-Of-War-Native-Port show origin/runtime:<path>`); `main` holds docs, tools and GoW overrides.
- They don't use Ghidra for the function map: `tools/find_functions.py` (capstone heuristic) writes the CSV.
- Drop ps2_analyzer's "self-modifying code" NOP patches: all 73 in GoW were ordinary stores into
  writable+executable .data, and one broke loading. (Tekken's .text segment is also RWX.)
- Turn off `PS2X_ENABLE_AGRESSIVE_LOGS` and the other log options (default ON): 44% of time was spent in WriteFile.
- Upstream puts RPC/TLS pools inside the game heap and corrupts it: they moved them via `GuestReservedLayout`.
  Tekken's ~27 MB .bss makes this even more likely to bite.
- Recompiler bugs they hit (diffing vs PCSX2): 64-bit compares in BLTZ/BGEZ family, SQRT.S/RSQRT.S operands,
  DIV.S by zero = FLT_MAX, CVT.W.S truncation, MMI PMULTH, 15-bit `rand` stub. Check whether upstream has these.
- Disc extraction must be sector-exact: streaming IRX modules read raw sectors (their `tools/iso_extract.py --layout`).
- VU1: PCSX2 VU1 interpreter as reference + `tools/vu1/vu1n_gen.py` compiling captured micro-memory to C++
  per basic block. MAC/clip flags have 4-cycle latency across blocks. Reusable for our 22 overlays.
- IOP: `tools/iop/iopn_gen.py` AOT-compiles the game's IRX modules; SPU2 replaced at the libsd export boundary.
  Only carries over if Tekken's sound driver goes through libsd.
- GS: OpenGL 4.3 hardware renderer (raylib/GLFW window). MPEG: vendored libmpeg2 behind sceMpeg* stubs.
- Timing: VBlank host-paced at 60 Hz; guest time drifting from host time in poll loops slowed their FMVs.
- Never run two builds at once; touching a precompiled header costs a 20-40 min rebuild.
- Licensing: PS2Recomp and their runtime are GPL-3.0; PCSX2 VU code GPL-3.0+, libmpeg2 GPL-2+.

## Open questions
- Which IRX modules does the game load, and from where (IOPRP243.IMG vs DATA.BIN)?
- DATA.BIN / DATA2.BIN archive format (needed for the file I/O layer).
- How the PAL build handles 50/60 Hz.

## Runtime build + first run (session 2, 2026-10-20)
- Upstream ps2xRuntime at eb8688b, built by `tools\build_runtime.cmd` into `external/PS2Recomp/out/runtime`
  (RelWithDebInfo, so no /GL or LTCG; unity build + PCH; 259 Ninja steps, ~3.5 min on 8 cores). Downloads raylib 5.5,
  imgui, rlImGui and a prebuilt LGPL FFmpeg on first configure. Output: 47 MB exe + 191 MB pdb.
- Logs: `AGRESSIVE_LOGS` OFF (per-function trace with flush, the GoW slowdown); `RUNTIME_LOGS` and
  `IOP_RPC_TRACE` ON while chasing boot problems. Turn them off for speed later (full rebuild).
- Upstream expects the generated code inside its tree: `tools\stage_generated.cmd` mirrors `generated\*.cpp`
  into `ps2xRuntime/src/runner` (overwrites upstream's placeholder `register_functions.cpp`) and the two
  `ps2_recompiled_*.h` headers into `ps2xRuntime/include`.
- Paths: cdrom0:, host: and the ELF dir all map to `game/disc/`; mc0 is `game/disc/mc0/`. Raw `sceCdRead`
  LBNs only resolve inside files first found via `sceCdSearchFile` (pseudo-LBNs), unless `IoPaths::cdImage`
  points at an ISO (nothing sets it upstream; would need a game override).
- **First stop:** the game thread ends at `[guest-branch:missing-target] JALR source=0x29b27c target=0x26e078`.
  `FUN_0029b1f0` walks a table of code pointers at ~0x2a9840 backwards (0x27cec0, 0x27a318, 0x274218, 0x270b08
  ran, then 0x26e078). That is the C++ static-constructor list (`.ctors`, `__do_global_ctors`). 0x26e078 has no
  function in Ghidra: constructors only reached through that table were never discovered. The window stays up
  after the game thread dies. Startup before that was fine: _InitSys, sub_281260, sub_1969F8 -> ctors.

## Missing functions fix (session 2, 2026-10-20)
- There is no `.ctors` section: ee-gcc's lists are in `.data` as `[count, ptr * count, 0]`. Constructors at
  0x2a9830 (12 entries), destructors at 0x2a9868 (1). 4 constructors had no function (0x1fe8e8, 0x23dda0,
  0x2492e0, 0x26e078): small leaf loops that zero static arrays.
- `tools/find_missing_functions.py --data-pointers --write` finds those plus every aligned pointer in
  .data/.rodata/.sdata that lands in .text no function covers (vtable methods; many are 8-byte `jr ra; nop`).
  It traces each one through its branches to find the end and stops at the next known function.
  350 found; all 350 start right after a return/jump (+ padding) or a non-returning call, so none is the
  tail of a neighbour. Writes `config/extra_functions.csv` (committed).
- `tools/postprocess_ghidra_export.py` now writes `config/function_map.csv` = Ghidra functions + extras, and
  the TOML's `ghidra_output` points at it. `ghidra_functions_only.csv` stays Ghidra-only so the finder's
  input doesn't change when extras are added. These functions don't exist in Ghidra yet (no MCP endpoint
  creates functions); a Ghidra script could import extra_functions.csv later.
- Recompile: 4809 functions (4536 recompiled + 273 stubs), 0 errors, 218 unresolved-JR warnings. Rebuild ~3 min.
- **Second run:** constructors pass. `SifInitRpc`, one `sceSifSendCmd cid=0x80000001`, then the game thread
  sits in `FUN_002230d0` (0x2230f0): `while (sceSifBindRpc(&cd@0x1cccbc0, 0x12345, 0) >= 0 && cd.server == 0)
  sceGsSyncV(0);`. Caller `FUN_00223418` then calls RPC function 0x8000 and sets up 4 channels and volumes:
  this is **Namco's sound driver** (IOP side, SID 0x12345). Not a crash: a wait for an IOP server that never appears.
- Why it never binds: upstream `SifBindRpc` only binds when `PS2IopTransport::canBindRpc(sid)` says so, i.e.
  `ps2xIOP`'s `IopSubsystem` has an HLE route for the SID or its emulated IOP has an IRX that registered it
  (`ps2xIOP/src/iop_subsystem.cpp:188`). Neither knows 0x12345.
- The ELF has no `.IRX` file names except `cdrom:\IRX\IOPRP243.IMG;1` (0x3141f0) and SDK version strings
  for padman/mcman/mcserv, so the game's own modules are probably loaded from buffers (likely from DATA.BIN).

## Sound driver override (session 2, 2026-10-20)
- `runtime/tekken4_overrides.cpp`: first game override (`PS2_REGISTER_GAME_OVERRIDE`, matched on
  `SCES_508.78` + entry 0x180088 + CRC32 0xBEFFF97A). Staged into `ps2xRuntime/src/runner` by
  `tools\stage_generated.cmd`, which skips `*_overrides.cpp` when it mirrors generated/.
- Upstream has no API for a game to add an IOP HLE route, so the override replaces this ELF's
  `sceSifBindRpc` (0x282808), `sceSifCallRpc` (0x2829d8, `ps2_syscalls::`) and `sceSifCheckStatRpc` (0x282bc8,
  `ps2_stubs::`) via `runtime.registerFunction`. SID 0x12345 binds (client.server = the client's own address,
  never dereferenced), every call returns at once with a zeroed reply, status is never busy. Everything else
  is passed to the runtime. Calls go through `dispatchGuestBranch` -> function table, so the replacement is
  seen by all callers.
- Sound protocol (EE library 0x2230d0-0x224140, client 0x1cccbc0, all mode 0, args in a0-a3/t0-t3 + stack):
  send 0x1ccc700 (4 words), reply 0x1ccc780 (0x20). 0x8000 init (FUN_00223418), 0x100 per-frame (sends the
  0xf0-terminated command queue at 0x1ccc7c0, 0x80 bytes; reply words 1-7 go to globals, word 3 = flags),
  0x1100 and 0x3300 return reply[0] (no direct callers), 0x200/0x600/0x2100/0x2200/0x3000/0x3100/0x3200 commands.
- **Third run:** override applied, bind OK, calls 0x8000 and 0x2100 answered. Boot moves on and then spins in
  `FUN_001803b0` (PC 0x1803f0, called from `FUN_0022ae10`, which builds a GS packet in scratchpad).

## MFIFO stop (session 2, 2026-10-20)
- `FUN_001803b0(spr_addr, qwc)` kicks DMA channel 8 (fromSPR, 0x1000d000) into the MFIFO ring: the
  `.mfifo` section at 0x100000 (0x80040 bytes). Before each kick it waits for free ring space:
  `free = (drain.TADR - fromSPR.MADR) mod (1 << *(u8*)0x7000002f)`, with the drain channel's register block
  address at scratchpad 0x70000034 (+0x30 = TADR) and the cached free count at 0x70000030.
- Upstream runtime: `PS2Memory::tryProcessScratchpadDma` copies fromSPR linearly to MADR (no wrap at
  RBOR/RBSR) and nothing drains the ring as a GIF/VIF1 MFIFO source, so TADR never moves and the wait never ends.
  `Kernel/Stubs/DMA.cpp` only stores RBOR/RBSR. The GoW fork doesn't implement MFIFO either.
- This is hardware behaviour, not a Tekken quirk: the fix belongs in the runtime (keep it as a patch in this
  repo, offer it upstream), not in the game override.

## MFIFO + D_ENABLE patch (session 2, 2026-10-21)
- The game's setup, from Ghidra: `FUN_00232e48(idx)` picks the drain from a table at 0x2d1c20
  (8 bytes each: channel regs, two thresholds, MFD, ?): entries 0 and 1 = **VIF1 (0x10009000), MFD 2**,
  entry 2 = GIF (0x1000a000), MFD 0, so GIF gets ordinary DMA. Ring: RBOR 0x100000, RBSR 0x7fff0 (512 KB),
  fromSPR MADR and VIF1 TADR both start at 0x100000. `FUN_00180270(ch, tadr)` starts VIF1 chain (CHCR 0x105,
  TTE kept from `FUN_00233690`). VIF1's end interrupt (`FUN_00233430`, AddDmacHandler 1) steps a per-frame
  state machine (restart drain / hand over to GIF). `FUN_00232c30`/`FUN_00232c88` suspend/resume all DMA via
  D_ENABLEW and poll D_ENABLER. `FUN_002332a0` switches MFIFO off (MFD = 0) while VIF1 keeps STR.
- `patches/ps2xRuntime-dmac-mfifo.patch` (ps2_memory.cpp/.h), applied by `tools\build_runtime.cmd`:
  - fromSPR with MFD 2/3 writes into the ring, MADR wraps (`RBOR + (addr & RBSR)`), then drains;
  - the drain channel (VIF1 for MFD 2, GIF for MFD 3) started in chain mode is no longer walked at once:
    `drainMfifo()` consumes tags only while the ring has data (a tag + its following data must be complete),
    TADR wraps, CNT/NEXT/END data comes from the ring, REF/REFS/REFE data from anywhere (wrapped if inside the
    ring); END/REFE/IRQ+TIE complete the channel (D_STAT + DMAC handler), an empty ring leaves STR set.
    Data goes to `processVIF1Data` (or GIF PATH3). CALL/RET in the ring are reported and end the chain.
  - D_ENABLEW (0x1000F590) writes are mirrored to D_ENABLER (0x1000F520).
  - CHCR reads: upstream's `readIORegister` clears STR on every channel CHCR read (transfers are synchronous
    there). That silently stopped the MFIFO drain whenever the game polled VIF1, so later packets were skipped
    when the game restarted VIF1 further along the ring. Reads now leave STR alone on an active MFIFO drain
    channel (it ends on END/REFE/IRQ).
  - Not modelled: D_STAT MEIS (bit 14, the runtime only keeps bits 0-9), DMA suspension itself
    (transfers are synchronous anyway).
  - Tests added to upstream's `ps2xTest/src/ps2_memory_tests.cpp` (ring wrap + drain as data arrives, END
    completes VIF1, D_ENABLER readback); they're part of the patch. Upstream suite: 448/448 pass (run
    `ps2x_tests.exe` from the PS2Recomp root; the VU0 macro test reads `instructions.h` relative to the cwd).
- **PCSX2 comparison** (user's PCSX2 on E: and portable 2.8.2): the first screen is the display-mode menu
  ("Caution: Selecting Progressive Mode..." / PAL50 / PAL60 / Progressive Scan) on a brown box built from the
  same **10 vertical sprite strips** our runtime draws. So the ring -> VIF1 -> GS packet path carries the right
  geometry; colour (grey vs brown), text and vertical placement (top half vs centred) are milestone 5 issues.
  PINE can't read hardware registers (they come back 0), so the register setup was taken from the game code.
- **Result:** boot reaches the main loop `FUN_001969f8` and stays there: about **47 frames/s** (PAL wants 50),
  1000+ frames in 21 s (frame counter = the per-frame sound call 0x100, logged by the override at 1/10/100/...).
  Sound command 0x200 shows up. The window shows only a grey 560x224 block made of 10 vertical strips
  (a framebuffer clear?) in the top half, unchanged from 6 s to 45 s.
- The runtime's debug panel covers the picture: F1 toggles it.

## Milestone 5 investigation (session 2/3, 2026-10-21)
- Tools: `TEKKEN4_GS_DUMP=<frame>` (env var, read by the override) records two frames of the GS debug history
  and every GIF packet raw, then writes `gs_dump_frame<N>.txt` (display regs, contexts, CD snapshot, events)
  and `gif_packets_frame<N>.txt` into the run directory. `tools/pine.py dump <addr> <size>` reads PCSX2 RAM.
  `PS2X_MFIFO_LOG=<file>` is a LOCAL debug print in drainMfifo (not in the patch file; remove before export).
- Display: PMODE 0x66 (circuit 2 only), SMODE2 3 (interlaced, field mode), DISPFB2 = PSMCT16 at block 0xd2,
  640 wide, DISPLAY2 640x512 (DH 511, MAGH 3). The **10 strips are the game's frame copy**: 64-px sprites
  copying the 32-bit render buffer (block 0, read as CT24) into the 16-bit display buffer, then 10 untextured
  sprites clear the render buffer. They are not the menu box.
- Per frame the VIF1 ring carries only: GS setup (REF 0x320df0), a small CNT packet (A+D: RGBAQ, TEST_2),
  the clear (REF 0x320f40), two more static packets, padding (REF 0x321040 = 16 x "XYZ3 = 0", sent 3x per
  frame on purpose), and the font CLUT upload (16-colour grey/alpha ramp to block 0x3fe1). No menu draws.
- **Root cause found:** the CNT packet in our ring is stale bytes. The game builds such packets with
  `FUN_0022a748(&p, idx)` -> `FUN_00180320`: **toSPR (channel 9) in source-chain mode with TTE** (CHCR 0x145,
  tags from the table at 0x2cea10), then `FUN_0022a720` patches the copied tag to CNT. The runtime only did
  normal-mode SPR DMA, so chain mode copied nothing and the game sent old scratchpad contents. PCSX2's ring
  (read over PINE) has the correct CNT qwc 3 packet.
- **Fixed:** `patches/ps2xRuntime-dma-chain.patch` (was spr-chain) (`processSprToChain`: all tag types, TTE copies the whole tag
  qword, SADR wraps in 16 KB; applied after the MFIFO patch). Our ring's first block now matches PCSX2's exactly
  (REF 9, CNT 3 "FLUSHE; DIRECT 3", REF 16, REF 7, REF 7, REF 17, END). Not upstreamed yet (no test yet; add one
  and send it with the next milestone).
- **Now:** the screen is black (the grey came from the stale packet) and the loop runs at ~59.5 fps.
  - Second ring block: ours = REF 0x312900 (8), REF 0x312980 (2), CNT 12 (font CLUT upload), padding.
    PCSX2's (menu on screen) = the same two REFs, then CNT 5 "DIRECTHL" (BITBLTBUF...), an IMAGE of 0x1d7d qwords
    from **0x373820** (REF, DIRECTHL: the menu texture, ~120 KB), CNT 5 (TEX0_2 etc.) and a **0x152-qword draw
    list**. So the game is still waiting for the menu's data: 0x373820 has to be filled first (disc read through
    an IOP module, or decompression). Next: find who writes 0x373820 (Ghidra xrefs / PCSX2 memory compare) and
    what our build is waiting on.
  - 59.5 fps: a PAL game should run at 50. The runtime paces VSync at 60 Hz; check how it picks the rate
    (SMODE1/SMODE2 PAL) before trusting frame timing.
- **Ground truth with input:** `tools/pcsx2_capture.ps1 -Keys "12:Down","14:Cross" -Shots 13,20` boots the
  portable PCSX2 (pad 1 on the keyboard, see the script) and picks **PAL60** on the display-mode menu (the user
  wants 60 Hz chosen on every run); the Namco logo follows ~6 s later. The user's PCSX2 1.6 on E: ignores our
  key presses (LilyPad), its config was restored unchanged.
- **Data never loads in our build:** EE RAM 0x373000-0x395000 (menu texture at 0x373820) and 0x39d000-0x500000
  are filled in PCSX2 at the menu but all zero in ours. The game binds no RPC service other than the sound
  driver (0x12345) and makes no other SIF calls, so the loader is probably that same Namco IOP driver: the
  silent override answers its calls (0x200, 0x2100, ...) with zeros and nothing ever arrives. Next: decode the
  0x200/0x3000-family calls (FUN_00223ca8 etc.) as load requests, or run the real driver (it is embedded in
  the ELF at 0x2e4900).
- **Disc loader decoded (2026-10-21):** `FUN_002155d0` (main loop, every frame) runs a queue of 48 load
  requests at 0x1ccb700. Request: [0] result (1 ok, -4 bad checksum), [1] state (1 start, 2 waiting, 4 done),
  [2] type, [3] file index, [4] EE destination, [5] size override, [7] bytes. File table at **0x314360**,
  16 bytes per file: +0 disc sector, +4 size, +8 checksum, +0xe decrypt key (short, <0 = none).
  Start: `FUN_002297c0(0)` clears the done flag, then **driver call 0x200 = read from disc**:
  `FUN_00223ca8(sector, dest, size, mode)` (mode 0/6/7 by type), busy flag 0x1ccb7cc = 1.
  Wait: `FUN_002297b0()` returns the done flag (gp-0x5148 = **0x35a128**). Done: first 4 KB decrypted
  (`word = ~word + key`), then the sum of all words XOR the table checksum must be 0.
  Our silent override swallows 0x200, so nothing ever loads.
  **Next:** (1) find who sets 0x35a128 (xrefs; likely `FUN_00225ae0(flags)`, called by the per-frame sound
  call with reply word 3; `FUN_00229030`/`040` (flags 0x100/0x200) set 0x1ccd35c/0x1ccd360 instead);
  (2) HLE 0x200 in the override: read `size` bytes at `sector * 2048` of the ISO (project root, local only)
  into EE `dest`, then report completion the way (1) shows; (3) check against PCSX2 that 0x373820 and
  0x39d000+ fill the same, then look at the screen (pick PAL60 when the menu shows).
- **Disc-read HLE works (override, call 0x200):** the done flag 0x35a128 is bumped by callback `0x229328`
  (`flag += 1`), reached only through a table at .data 0x2ce490 of driver event callbacks (0x229290 ring
  read pointer, 0x2292d0, 0x229318, 0x229328, 0x229340); we apply its effect directly after each read.
  **Sectors count from the start of DATA.BIN** (disc LBN 1236): with that base every checksum matches
  (decrypt first 4 KB `~w + key`, key = the table's short at +0xe, -1 = plain). game/disc has no DATA.BIN
  (only the ELF, SYSTEM.CNF, IOPRP were extracted), so the override reads the ISO in the project root at
  (1236 + sector) * 2048 (TEKKEN4_ISO overrides the path). The ISO is always preferred (it also has DATA2.BIN
  after DATA.BIN); a loose game/disc/TEKKEN/DATA.BIN is only a fallback when no ISO is found. No need to extract.
  Mode 6/7 requests (e.g. sector 9378, 1.2 MB -> 0x5010) target sound/IOP memory: logged, not copied.
  Result: the first file loads and passes its checksum, the sound bank request follows, then the main loop
  stops after frame 1 and a few garbled coloured pixels appear at the bottom left.
- **Current stop:** game thread in `FUN_002331f8` (PC 0x233210), the MFIFO flush: it spins until the ring
  state (struct from FUN_00232c20) has state[4] == 0 and state[0] == 0. Those are updated only by the
  VIF1/GIF DMA end handlers (0x233430 via AddDmacHandler 1, 0x233548 via AddDmacHandler 2) as they step
  the per-frame state machine (FUN_00233030/00233130/00233188). With real data the frame now has more
  stages (texture upload through GIF = table entry 2, MFD 0), and one completion never arrives.
  Next: dump state[0..0x14] when stuck, check that the GIF channel's completion queues DMAC cause 2 and that
  the handler runs, compare with PCSX2's ring (texture upload + 0x152-qword draw list).
- **Why the flush hangs (found):** ring state at **0x1cda2c0**: [0] pending paths, [1] active, [2] VIF1 end
  count, [3] GIF end count, [4] frames pending. Per frame: `FUN_00232d20` (loop start) zeroes it,
  `FUN_00233a38` (end of frame, via FUN_00233360) does [4] += 1 and sends a 2-qword closing packet. GIF end
  handler 0x233548: [3]++; 1 -> restart VIF1 path 0; 2 -> [4]-- then paths 2/1; else DisableDmac(2). VIF1
  end handler 0x233430: [2]++; 1 -> path 1; 2 -> paths 1/2; 3 and [4] != 0 -> [3]--, [2]-- (another round).
  Watchdog (`TEKKEN4_WATCH_MS=9000`) while stuck: [0]=0 [1]=1 [2]=2 [3]=2 **[4]=-38**: once [4] goes
  negative every VIF1+GIF end pair drives it lower, and the flush (`FUN_002331f8`) waits for 0 forever. So we
  deliver more VIF1/GIF end interrupts per frame than the hardware, or in another order. Next: log every DMAC
  cause the runtime queues (channel, why: MFIFO END, chain end, normal transfer) for one frame and work out
  the hardware order from the game's packets; suspects: GIF completions from upstream's
  processPendingTransfers (one per call), VIF1 END completions in drainMfifo, the new empty-chain completion.
- **Surplus interrupts traced (TEKKEN4_IRQ_LOG=<n> wraps the VIF1/GIF end handlers and frame start/end):**
  frames 0-3 are balanced (start, GIF end, VIF1 end, frame end +1, VIF1 end, GIF end -1, VIF1 end stop).
  In frame 4 (first frame with the loaded menu data) path 1 ends early: our ring has REF 0x312900 (8),
  REF 0x312980 (2), then **CNT qwc 0xa** where PCSX2 has **CNT qwc 5** (FLUSHE; DIRECTHL 5 = BITBLTBUF..
  TRXDIR), CNT 1 (IMAGE giftag), REF 0x373820 qwc 0x1d7d (the texture), CNT 5, CNT 0x152 draw lists...
  The 10 qwords swallow the next tags, VIF1 lands on garbage that decodes as REFE (addr 0x12340) and ends
  path 1 before the frame-end +1; the handlers then loop and drive the counter negative.
  So the EE code that builds the texture-upload CNT computes qwc 10 instead of 5 (EE-side bug or another
  missing runtime feature, like the toSPR one). Builders that emit DIRECTHL (lui 0x5100): FUN_001eec80,
  FUN_001feef8, FUN_0020cb68, FUN_00227f80, FUN_002344e0 (the last uses sceVif1Pk* and emits REF tags, so
  not it). Next: find which one builds this CNT (its qwc comes from the GIF part it opens), compare its
  inputs/outputs with PCSX2 (PINE: dump scratchpad/ring right after it), fix the cause.
- **Fixed: doubled DMA tag counts (override, 0x292900).** The game's VIF packet library close-tag function
  (0x292900, not recognised as SDK code, so it runs as game code) ADDS (cur - tag)/16 - 1 to the open tag.
  The runtime's stubs for the recognised calls (sceGifPkAddGsAD, sceGifPkCloseGifTag, ...) already keep that
  qwc current as they write (`refreshPacketBuilderPendingCount` in Stubs/GS.cpp), so mixed tags got qwc x2
  (image-upload CNT 10 instead of 5). The override replaces 0x292900 with the same function that SETS the
  qwc. Upstream issue to report: live qwc refresh in the pk stubs + a game's own (unstubbed) close = double.
  Found by logging pk state around open (0x292970), sceGifPkCloseGifTag and close (TEKKEN4_IRQ_LOG).
- **Result: the menu draws.** All 24 files load once, the main loop runs (~44 fps over 1000+ frames) and the
  display-mode menu appears: brown panel in its real colour, "Caution:" readable, but most glyphs missing,
  the panel in the top half (field not scaled to the full picture) and three garbled squares at the bottom
  left. Screenshot: docs/img/m5_first_menu_partial.png (our build's output).
- **Fixed: PATH2 as one GIF stream (patch 02).** The game cuts its GIF stream into fixed CNT 0x152 / DIRECT
  0x152 chunks regardless of packet boundaries (e.g. a glyph IMAGE upload of 15 qwords spans two chunks).
  Upstream's VIF1 interpreter only tracked a pending IMAGE count and resumed it at the VIF level, eating the
  next chunk's TTE VIFcodes (NOP; DIRECT) as image data: everything after was misaligned by 8 bytes and
  became garbage GIF tags (stray points, psm 0x15). Now each DIRECT appends to `m_path2Stream` and only
  complete GIF packets (any format) go to the GS; the tail waits for the next DIRECT (cleared on VIF1 reset).
- **Redone for upstream (session 3):** the stream buffer broke upstream tests that expect each DIRECT payload to
  reach the GIF callback as it is (one feeds a lone garbage qword). Now `forwardPath2Payload` forwards every
  payload unchanged and remembers the packet cut at its end (`m_path2Cut*`). `continuePath2Packet` sends the rest
  from the next DIRECT under new tags: IMAGE as a shorter IMAGE; PACKED/REGLIST with REGS rotated to the register
  the cut stopped at (full loops, then a leftover tag), REGLIST padding rebuilt. Raw-qword continuation stays for
  IMAGE only, and not when the next VIFcodes lead to a DIRECT. An intermediate "hold PACKED/REGLIST until
  complete" version also drew the menu but crashed that test. Same picture in the game (logs/cont1).
- **Result: the whole display-mode menu renders** (docs/img/m5_menu_text.png): panel, all text lines, arrow
  on PAL50. Remaining for milestone 5: the picture is squashed into the top half (field mode not scaled to
  the full PAL frame), three garbled squares at the bottom left, ~44 fps, then the Namco logo after PAL60.
- Patches renamed so they apply in order: 01-ps2xRuntime-dmac-mfifo.patch (= PR #372), 02-ps2xRuntime-dma-
  fixes.patch (= PR #373 plus its tests: toSPR chain, empty-chain completion, PATH2 continuation). Checked on a
  clean upstream worktree. `build_runtime.cmd` treats them as a stack: if the last one reverses, all are in.
- **Milestone 5 reached (2026-10-21).** `tools/run_capture.ps1 -Keys "10:Down","12:Cross","15:Left","16.5:Cross"`
  (posted key presses, runtime maps arrows/X/Enter to pad 1): Down -> PAL60, Cross -> "Display mode changed to
  [PAL60 / 60Hz]. Start game? Yes/No" (No preselected), Left + Cross = Yes -> **Namco logo** at ~20 s, then a
  white screen at ~34 s (next scene; check against PCSX2). Screenshots: docs/img/m5_menu_pal60.png,
  m5_confirm_yes.png, m5_namco_logo.png. Still off: only the top half of the picture is used and the rest
  shows other GS memory (field-mode display scaling), stray texture blocks, ~38-44 fps.
- Also in the dma-chain patch: a chain that ends without data (lone END/REFE/IRQ tag) now completes its
  channel (upstream left STR set and raised no interrupt). Correct per hardware, but didn't fix the hang.
- Side findings: the menu text isn't in the ELF; the IOP module package is embedded LZ-compressed and
  bit-inverted at 0x2e4900 (`FUN_00197dd8` = LZ decoder, `FUN_00214fa0` = IOP boot + module loading), so the
  real sound driver ships inside the ELF. `tools/build_runtime.cmd` exit codes now propagate (an error inside a
  bracketed block used to be reported as success) and `.cmd` files are kept CRLF.

## Display line repeat (session 3, 2026-10-21)
- Display registers on the menu: PMODE 0x66 (CRT2 only), SMODE2 3 (INT=1, FFMD=1), DISPFB2 FBP 0xd2 FBW 10 PSMCT16,
  DISPLAY2 DX 636 DY 50 MAGH 3 MAGV 0 DW 2559 DH 511. The game draws 640x256 per field.
- PCSX2 shows the menu box twice as tall as we did, in the middle of the screen: in interlaced FRAME mode
  (FFMD=1) each field reads every buffer line while DH counts both fields' lines, so the display shows
  (DH+1)/2 = 256 buffer lines, each twice. Upstream read DH+1 = 512 lines in every mode (picture in the top half,
  other VRAM below, which was the "three garbled squares"); it only special-cased FFMD=0 (bob of one parity).
- **Fixed (patch 03 = PR #375):** `gs_cpu_backend.cpp` reads ceil(height / repeat) lines, repeat = (MAGV+1),
  x2 in interlaced FRAME mode, and repeats them to DH+1 (`decodeDisplayLineRepeat`, `repeatPresentationLines`),
  for both circuits. New test in ps2_gs_tests.cpp. Menu, PAL60 confirmation and logo now sit where PCSX2 puts
  them (docs/img/disp_menu_full_height.png, disp_pal60_confirm.png, disp_namco_logo.png). The PCSX2 shots in
  logs/pcsx2_pal60e are in German (portable PCSX2's language), so its menu box is wider: the text is longer.
- After the logo (logs/after_logo1, PAL60 + Yes): black from ~24 s, then a near-white screen (mean 244/255) from
  ~36 s to at least 56 s.

## Intro movie (session 3, 2026-10-21)
- PCSX2 (logs/pcsx2_after_logo): logo 18-22 s, then the intro movie from ~24 s. Ours: black, then white: the
  player (FUN_00228520, states 2 init, 3 buffer, 4 play, 5/6 stop) gave up.
- **Stream.** Movies are files in the table at 0x314360 (movie table 0x31fdd0: file, first/last frame; the intro is
  file 1 = entry 0xb2, sector 58196, 129 MB). They interleave 0x27 sectors of MPEG-2 video (ES, 640x448) with 2
  sectors of SPU ADPCM audio. Driver call 0x3000 (sector, size, file, mode) opens the stream, 0x3200 (EE dest,
  sectors) reads the next video sectors into the player's ring (0xea000 bytes = 12 x 0x13800), 0x3100 closes.
  The driver answers a read with SIF command 4: handler 0x229350 stores the byte count at 0x35a12c (handlers set
  up in FUN_00229540: cid 1 = disc read done, 4 = stream read). PCSX2's ring (PINE, logs/pcsx2_movie_probe) is
  the video units back to back. The override now serves 0x3000/0x3200/0x3100 from the ISO.
- **Decoder input.** sceMpegGetPicture is the runtime's FFmpeg stub, fed by sceMpegAddBs or PSS demuxing. The game
  feeds the IPU itself: libmpeg calls its no-data callback (0x2281d0), which points a toIPU DMA (ch 4, REFE tag at
  0x1ccd2b0) at the next 0x9c00 ring bytes. The override's GetPicture runs that callback (a nested guest call)
  and passes each transfer to sceMpegAddBs until a picture is decoded.
- **End flag.** The game's own sceMpegIsEnd (0x28bc58) returns the first word of mp->sys, which the runtime's
  sceMpegCreate never cleared: the movie "ended" after one picture. Patch 04 clears it (generic libmpeg behaviour).
- **Display start.** The picture is shown by the vsync handler (FUN_002280d0) only after the player started the
  movie audio, which waits for status bit 0x200 in the driver's per-frame reply (0x100 call, word 3; 0x100 =
  stream ended). The override reports 0x200 while a movie is open and 0x100 when its file runs out.
- Result: the intro plays (docs/img/movie_intro_volcano.png, movie_intro_scene.png), no sound. Thin vertical lines
  every 64 px are gaps between the picture's sprite strips (the menu box has them too); PCSX2 has none.

## Sprite strip gaps (session 3, 2026-10-21)
- The display buffer (FBP 0xd2) is filled each frame by a copy of the 640x448 back buffer (FBP 0) into a 224-line
  field: ~280 bilinear sprites (REGLIST PRIM/UV/XYZ2/UV/XYZ2, 64-px columns of 16-row bands, a second 50%-blended
  pass one texel row lower). Each column runs from X 64k to 64k+63.5 (0x6ff8 - 0x6c00 = 63.5).
- DrawSprite truncated the vertex X to int, so 63.5 became 63 and column 63 of every strip was never written:
  the black line every 64 px on the menu box and the movie. GS rule: a sprite covers X0 <= x < X1, so 63.5
  covers column 63. **Patch 05** computes the covered pixels as ceil(X0) .. ceil(X1)-1 and maps the texture over
  the exact (fractional) width; integer-aligned sprites are unchanged. Tests 454/454; docs/img/movie_no_strip_gaps.png.
  Not upstreamed yet (PR + a test with a 63.5-wide sprite to do).

## Field offset (session 3, 2026-10-21)
- User report: the whole game vibrates. In interlaced FRAME mode the game draws one field per frame: its vsync
  handler (0x22aaf8) reads CSR.FIELD and copies the even or odd lines of the 448-line back buffer into the
  224-line display buffer (the copy's V starts at 0 or 1). A TV shows the odd field one line lower; patch 03
  line-doubled both at the same place, so the picture moved by a line whenever the field changed (~40 times a
  second, the game's frame rate).
- **Patch 06:** the GS frontend records CSR.FIELD whenever a draw targets a displayed buffer (FRAME.FBP ==
  DISPFB1/2.FBP) and passes it in the presentation request (`displayField`); in interlaced FRAME mode an odd
  field is shown one display line lower. Keyed to the field the picture was drawn for, not the current vsync,
  because below 60 fps a picture stays up for several fields. New test; 455/455.
- Measured with TEKKEN4_PRESENT_LOG=<s> (override debug aid: brightness-weighted vertical centre of the presented
  frame, min..max per second): menu 0.79 line of motion per frame without the offset, 0.21 with it (edges still
  flicker by a line between fields, as on a TV); PAL60 dialog 0.01-0.06; logo 0 (logs/field_off, field_on,
  field_final). A blend of the last two fields would remove the edge flicker too, if it is still visible.

## Difficulty screen (session 3, 2026-10-21)
- PCSX2 and ours, same input (PAL60, Yes, Start at 30 s to skip the movie): the first-run screen "MODE SELECT /
  SET GAME DIFFICULTY" (EASY .. ULTRA HARD, MEDIUM selected; PCSX2's copy is in German). logs/pcsx2_title,
  logs/title1..4.
- The menu titles and the TEKKEN 4 logo were upside down: DrawSprite sorted the corners but not their UVs, so a
  sprite sent bottom-right first was mirrored. **Patch 07** swaps U/V with X/Y (also PR #377, second commit, with
  a test). docs/img/difficulty_screen.png.
- Tried and dropped: making a zero-size sprite draw nothing (GS behaviour). 8 upstream tests draw sprites with
  both corners on one point and expect a pixel, and it did not remove the dashed lines.
- Thin dashed lines along the panels' edges (not in PCSX2): `tools/gif_sprites.py` (new; lists the sprites in a
  TEKKEN4_GS_DUMP GIF log with UV, texture, CLAMP, filtering) showed the UI drawn as 64-px strips from X -0.5 to
  63.5 over U 0..64 (Y the same way, given bottom-up). The GS samples u = u0 + (x - X0) * du/dx = x + 0.5 (texel
  x); DrawSprite added half a pixel more, so it read texel x+1 and, at each image's right/bottom edge, the GS
  memory beside the image. **Patch 08** takes UV at the pixel position and keeps FST UV fractions (they were
  >> 4). Integer-aligned point sampling is unchanged; PR #377 third commit + test, 448/448. The screen now
  matches PCSX2 (docs/img/difficulty_screen.png).

## Main menu = milestone 6 (session 3, 2026-10-21)
- Input: `run_capture.ps1 -Keys "10:Down","12:Cross","15:Left","16.5:Cross","30:Start","36:Cross"` (PCSX2:
  12/14/16/17/30/36). Both show MODE SELECT with STORY BATTLE selected, the character portrait and the help text
  (docs/img/m6_main_menu.png; PCSX2 logs/pcsx2_menu, German).
- Differences: VS BATTLE is greyed out in PCSX2 (only pad 1 plugged in) but enabled in ours, so the runtime
  probably reports pad 2 as connected. At 55 s PCSX2 has gone to the attract demo (VS screen); ours is still on
  the menu (its idle timer likely counts frames and we run at ~36 fps).

## GS speed (session 3, 2026-10-21)
- Measured with two new debug aids in the override: TEKKEN4_PERF_LOG=<s> (game frames and host time in GS
  packet processing per second) and TEKKEN4_PROFILE=<start s>:<s> (samples the game thread's instruction pointer
  every ms, names the hottest functions from the PDB via dbghelp; windows.h needs NOGDI/NOUSER next to raylib in
  the unity build). The game thread spent 860-930 ms of every second drawing in the software GS: ~40 fps on the
  first menus, 17 fps on the main menu.
- Fixes, in order (first menu / main menu fps): C-runtime rounding in bilinear filtering (lround/floor are calls
  without /arch:AVX, a fifth of the time) replaced by exact inline arithmetic 46/22; RelWithDebInfo with /Ob2
  (tools/build_runtime.cmd; CMake's /Ob1 kept the per-pixel helpers as calls) 52/24; forced inlining of the
  per-pixel helpers 55/26; bilinear skips texels with weight 0 (the screen copy samples on texel columns) 60/28;
  WritePixel's per-primitive part computed once (PixelPipeline) 60/29; then **drawing threads**: 60/60.
- **Drawing threads** (PS2X_GS_THREADS=<n>|auto, off by default in the runtime; tools/run_game.cmd and
  run_capture.ps1 set auto = logical CPUs - 2): every primitive is queued for all workers, each draws the rows of
  its own 16-row bands (no two threads share a byte in any format). Everything else that touches GS memory or
  the CLUT (uploads, CLUT loads, TEXFLUSH, readbacks, presentation, reset) first waits until the queue is drawn,
  and all texture page caches are invalidated there. A primitive that samples pages a queued one draws into, or
  draws into pages a queued one samples, also waits (the bands run ahead of each other). Without the cache
  invalidation and that check the main menu had black rectangles. New test: the same sequence (40 blended
  bilinear sprites, a sprite sampling the frame just drawn, a full-screen fill) gives identical GS memory with 0
  and 4 threads; 456/456.
- All of it is patch 09 (not upstreamed yet: it builds on PR #377's DrawSprite). The movie plays at 30 fps (the
  player shows a picture every second vsync), every other screen at 60.

## Character select (session 3, 2026-10-21)
- The stall after Arcade (and in the attract loop): game thread in FUN_00227eb0 (0x227eb8), spinning until
  0x1ccd18c reaches -1. The game decodes animated images with the IPU itself: FUN_002277d0 makes one job per image
  of an image file (resource 0x77, or 0x8a in mode 6) at 0x1ccd200 (0x54 bytes each), FUN_00227be8(step) advances
  each animation every frame and starts the decodes (FUN_002278f0: FDEC 8 bits = IPU_CTRL flags, IDEC to RGB32 via
  toIPU/fromIPU DMA), the channel-3 DMA handler 0x227cf8 starts the next image and counts 0x1ccd18c down. The
  runtime has no IPU, so the count never moved.
- PCSX2 at the select screen (PINE, logs/pcsx2_ipu_probe): one image, 15x11 macroblocks (240x176, the cloud
  background), 75 frames, output RGB32 at 0xf4a380. Image file: count, (offset, size) per image; image: u16 mb
  width, height, frames, speed, 4 x 0; then a frame table (offset, size). Each frame is the IPU flags byte (0x60:
  MPEG-2 intra VLC, non-linear quantiser), the macroblocks, 00 00 01 B0, 00 00 01 B1: FFmpeg's "ipu" format.
  Some frames have a stuffing byte before B0 that FFmpeg rejects (it wants exactly the end code after the
  picture).
- **Patch 10** (runtime, MPEG.cpp): `ps2_stubs::decodeIpuIntraPicture(data, size, mbw, mbh, out)` decodes one
  IPU intra picture with FFmpeg's ipu codec (retrying with up to 8 stuffing bytes dropped) and writes the IPU's
  RGB32 output (16x16 macroblocks in raster order, the IPU's fixed-point BT.601 conversion, alpha 0x80).
  **Override:** FUN_00227be8 replaced: same animation step, then the current frame of each image decoded at once
  and 0x1ccd18c set to -1. Formats 1/2 (RGB16, dithered) are not handled yet (logged).
- Result: CHOOSE YOUR FIGHTER as in PCSX2 (docs/img/character_select.png): animated clouds, Kazuya's portrait,
  the grid, the countdown. Ours shows PRESS P2 START where PCSX2 has CREDIT 0 (pad 2 reported as connected, the
  same as VS BATTLE being enabled). The countdown went 24 -> 19 in 7 s, so check the frame rate here.

## First fight (session 3, 2026-10-21)
- Keys `...,"40:Down","41.5:Cross","46:Cross"` (Arcade, Kazuya with the cursor's default). The select screen runs
  at 48-49 fps; after the pick the game loads Stage 1 and shows the fight: HUD (STAGE 1, timer 60, KAZUYA / LAW
  health bars), the 3D stage (palms, glass hall), Kazuya's intro animation (docs/img/first_fight.png,
  first_fight_stage.png). PCSX2 not compared yet.
- **~7 fps** in the fight (TEKKEN4_PERF_LOG, logs/fight1). Profile (TEKKEN4_PROFILE=62:10, logs/fightprof1): ~65 %
  of the game thread in the VU1 interpreter (commitReadyPipelines 22 %, normalizeOperand 8 %, run 8 %,
  calculatePairReadyCycle 6 %, execUpper 5 %, FMAC flags/results ~8 %), 18 % waiting (NtWaitForAlertByThreadId:
  the GS worker barriers or the vsync wait), little GS.
- The God of War port hit the same wall (docs/performance.md there: VU1 61 % of a frame) and reached 60 fps in
  gameplay with: native VU1 code generated ahead of time from captured micro-memories (tools/vu1/vu1n_gen.py,
  bit-exact replay check), VIF1 + VU1 on a worker thread pipelined with the GS frontend, and a VIF1 UNPACK fast path.
  Those live in their fork, not upstream. Tekken's ELF has 22 .DVP.overlay sections (its VU1 micro-programs).

## Native VU1 port (session 3, 2026-10-21)
Goal: the fight at full speed. Port of the God of War native port's lean VU1 backend (Waffle565/God-Of-War-Native-Port,
branch `runtime`, GPL-3.0 like PS2Recomp and this repo). Done so far = **patch 11** (`patches/11-native-vu1.patch`):
- Whole-file copies from GoW `origin/runtime` (our VU files were identical to their base c5a9d02 apart from line
  endings): `ps2_vu1.h`, `ps2_vu1_native.h`, `ps2_perf.h` (diagnostics, header only), `ps2_vu1_core.cpp`,
  `ps2_vu1_lower.cpp`, `ps2_vu1_upper.cpp`, `ps2_vu1_step.inl`, `ps2_vu1_native.inl`, and their `ps2_vu1_tests.cpp`.
  Their `ps2_vu_tests.cpp` changes were left out (they test GoW's EE FPU / VU0 helpers we don't have).
- `ps2_runtime.cpp`: `m_vu1.setDirectRegisterWrites(true)` like GoW (no register write queues, faster; needed by the
  capture, which lives in `compiledProgramFor`); `GOW_VU1_COLAS=1` goes back to the queued model.
- `ps2xRuntime/CMakeLists.txt`: `PS2X_VU1_MICROCODE_DIR` (folder of captured `.bin` micro memories, empty = interpreter
  only) and `PS2X_VU1N_GEN` (default `<project>/tools/vu1/vu1n_gen.py`); generates `vu1n_part0..5.cpp` in the build
  folder (`vu1n_heads.txt` next to the micro-memory folder = extra block heads) and links them into ps2EntryRunner.
- With no blocks linked the engine is the interpreter (each pair first misses the native table). Tests 465/465.
Next, in order:
1. **The generator's licence (deferred by the user).** `tools/vu1/vu1n_gen.py` (copied unchanged from GoW's `main`
   branch, which has no LICENSE file; only `runtime` is GPL-3.0) is committed at the user's request; the user made the
   GitHub repo private (2026-10-21). Settle the licence (ask Waffle565) before making the repo public again.
2. **Capture:** run to the fight with `GOW_VU1_NATIVE_OFF=1` and `GOW_VU1_CAPTURA=<existing folder>` (use
   `game/vu1/micro`, gitignored: the micro memories are game code). Writes `vu1_<fnv64>.bin` per distinct micro memory.
3. Configure `-DPS2X_VU1_MICROCODE_DIR=<that folder>` (add it to `tools/build_runtime.cmd` when the folder exists),
   build, run with `GOW_VU1N_DIAG=1` to list `[vu1n-miss]` pcs, put them in `game/vu1/vu1n_heads.txt`, rebuild.
4. Verify: `GOW_VU1N_VERIFY=<runs>` (tolerance compare against the interpreter); bit-exact: record with a build
   without blocks (`GOW_VU1N_RECORD=<file>`, `GOW_XGKICK_IMMEDIATE=1`), replay with the native build
   (`GOW_VU1N_REPLAY=<file>`), expect "0 differ". Risks for Tekken: Q/P have no latency in native code, status flags
   not modelled, missing heads. `GOW_VU1_STATS=1` prints VU1 time and interpreted steps every 5 s.
5. Measure the fight (`TEKKEN4_PERF_LOG=200` = seconds to log, `TEKKEN4_PROFILE`), compare with PCSX2, then milestone 7.

Progress (2026-10-21, commits a31b778, fda9e02):
- Capture done: **one** micro memory (`game/vu1/micro/vu1_62802e7b8abf4848.bin`, 0x0-0x3e88 = the 18-overlay group):
  Tekken uploads its whole VU1 set once. 220 blocks, 0 unsupported. `tools\build_runtime.cmd` now links them.
- Fixed with `GOW_VU1N_VERIFY` + `GOW_VU1N_BISECT=1` + `GOW_VU1N_DUMP=1` (new: bisect any mismatch):
  (1) vf0 corrupted: Tekken's backface test is `OPMULA.xyz ACC,vf21,vf22` + `OPMSUB.xyz vf0,vf22,vf21` (flags only);
  native callouts skipped the interpreter's per-pair vf0/vi0 restore. (2) OPMULA/OPMSUB generated natively so FMAND
  sees their MAC flags (it read an older MUL's).
- Left in verify: "mac"-only end-state differences, and single ADC words where the interpreter recomputes a nearly
  cancelling MSUB from the unrounded product while native subtracts the rounded one (edge-on triangles; harmless).
- Fight with native VU1: 11-25 fps (interpreter: 7-9), stage and both fighters drawn (logs/vu1n_fight4).
- **The stall is not native VU1.** About 4 s into the fight (clock 00:03:68, timer 56) the program at 0x32a0 runs to its
  65536-cycle budget every time (`GOW_VU1_LONGRUNS=40000` prints `[vu1-long] startPc=32a0 ... budget`), then garbage
  XGKICKs follow (the runaway loop writes over VU memory: "[VU1 reserved lower] ... 0xfffffffb/8" = rejected GIF tags).
  `GOW_VU1N_CHECKLONG=1` re-runs each such run with the exact engine from the same entry state: it loops too. And the
  interpreter-only build (`GOW_VU1_NATIVE_OFF=1`, logs/vu1_interp_long) stalls the same way at the same fight time
  (134 s there, it is slower). The loop counter is `vi8 = vi5 & vi12` (pc 0x3390; vi5 = count from the packet header,
  vi12 = mask, normally 0x7fff), decremented per pass until 0: in the stalled runs vi12 is 0 at entry (VI registers
  carry over between VU1 programs), so the count is 0 and the loop wraps 65535 times.
- **Cause traced (2026-10-21, late), not fixed yet.** The garbage header comes from the VIF1 stream, not VU1:
  1. VIF1 runs in MFIFO mode (ring D_RBOR 0x100000, D_RBSR 0x7FFF0, filled by fromSPR copies of SPR packets). A
     frame's list ends with REF qwc=0 at 0x13d330 + REFE at 0x13d340; the fromSPR copy that carried them (qwc 0x18 from
     SPR 0x0050, ring 0x13d310-0x13d490) also put 20 more qwords after the REFE.
  2. The game (FUN_00180270, per Grok) restarts VIF1 with TADR = 0x13d350 (qword after the REFE). The "tag" there is
     NEXT qwc=0x3000 (192 KB, more than ever arrives), so our drain waits there forever while new packets arrive behind
     it (ring write pos 0x13d490 -> 0x142f70).
  3. The game's recovery path (FUN_002332a0): D_ENABLEW suspend, VIF1 CHCR STR off, resume, D_CTRL.MFD = 0, VIF1 CHCR
     start: a normal chain at 0x13d350 reads NEXT 0x3000 = 192 KB of ring memory as VIF data; its DMA tags parse as VIF
     codes and one of them is STMOD 2 (difference mode), which corrupts the next UNPACKs (the 0x32a0 header).
  On a real PS2 that path cannot be taken this way, so the open question is what sits at 0x13d350 on hardware when
  VIF1 restarts (is our SPR packet tail different, or does hardware treat that NEXT differently: PCSX2's
  mfifoVIF1transfer streams a tag's data as it arrives instead of waiting for the whole packet like our drainMfifo).
  Next: read ring 0x13d300-0x13d4a0 in PCSX2 (tools/pine.py) at the same point of the fight and compare; then fix
  drainMfifo (stream partial CNT/NEXT data, see PCSX2 Vif1_MFIFO.cpp) or the SPR packet source.
- **STALL FIXED (2026-10-22):** the CNT qwc=4 is a double count: PS2Recomp's stubs sceVif1PkAddGsAD / closePacketGifTag
  SET the open DMA tag's qwc (refreshPacketBuilderPendingCount) and the game's own close FUN_00292c18 then ADDs
  ((cur-tag)>>4)-1 (found by Grok, logs/grok/cnt-qwc_20261021_221410.json). Fix: the existing closeDmaTag override
  (SET instead of ADD, until now only at 0x292900 for the menus) is also registered at 0x292c18. Verified
  (logs/stallfix_fight1): fps never drops to 0 (7-9 to 168 s), no [vu1-long] budget runs, fight at 00:11:85 timer 48,
  menus and VS screen fine. Generic upstream fix (stubs should not touch the DMA tag qwc) = Grok task upstream-qwc.
  NEW: in the fight the camera is far too close (fighters fill the screen; PCSX2 at the same time shows them full-body).
  Fight profile after the fix (TEKKEN4_PROFILE=75:15, logs/fight_profile2, 14-15 fps): native VU1 <1%; the game thread
  waits on the GS drawing threads 56% (NtWaitForAlertByThreadId) + 8% waking them, memcpy 8.6%, UploadImage/CLUT ~3%;
  "GS 830 ms" per second. The CPU GS is now the limit (huge close-up triangles make it worse: fixing the camera
  should help); next levers: the camera, then GS speed (SIMD rasterizer / GPU renderer).
- **Root cause found one level up (2026-10-21, PCSX2 ring dump):** the "REF qwc=0 / REFE" that ended the list are UNPACK
  data, not tags. The game's own packet is wrong in our run: `CNT qwc=4` with `DIRECT 2` in its tag-hi (2 qwords of GIF
  data: TEXFLUSH) also counts the next two REF texture-upload tags (`REF qwc=0x26 addr=0x6c2220` FLUSHE;DIRECTHL,
  `REF qwc=0xa addr=0x6c2480`), so our drain sends those tags to the VIF as data and loses its place; the matrix packet
  `CNT qwc=0x17` (FLUSH;MSCAL 0x2b; STCYCL; UNPACK V4-32 num=0x15) is then read as data, its UNPACK data as tags.
  PCSX2 (logs/pcsx2_ring_probe/ring_70.bin, 11 s into the fight, past our stall) has the same packet kind as
  `CNT qwc=2` (FLUSH;DIRECT 2) followed by real REF tags. So the EE-side builder put the texture-upload REFs inside an
  open CNT and counted them; hypothesis: the texture-upload writer runs at a moment hardware never allows (an
  interrupt / DMA callback our runtime runs earlier, since our DMAs complete inside the CHCR store). Grok task
  "cnt-qwc" (logs/grok/cnt-qwc_*.json) is finding the writer functions. Our ring dump: logs/ringdump_fight1/stderr.txt
  ("[vif1-bad]   ring"); the debug patch now prints it.
- **Patch 12** (`patches/12-ps2xRuntime-vif1-carry-and-mfifo-wait.patch`, tests 466/466): (a) a VIF1 command whose
  payload runs past the end of a DMA transfer (UNPACK / MPG / STROW / STCOL / STMASK) is kept and finished with the next
  transfer, like PCSX2 (before: the rest was parsed as VIF codes; Tekken does this when a drain ends mid-command); (b) a
  CHCR write to the MFIFO channel while it waits is ignored unless it clears STR or the DMAC is suspended (PCSX2
  DmaExec). Neither fixes the stall by itself.
- Debug instrumentation used to find it: `patches/debug/vif1-dma-trace.patch` (not applied by build_runtime; apply on
  top of 01-12 with `git -C external/PS2Recomp apply ../../patches/debug/vif1-dma-trace.patch`): with
  GOW_VU1N_CHECKLONG=1 it prints, at the first invalid VIF1 code ("[vif1-bad]"), the last VIF1 codes, the DMA tags
  read (chain walker c / MFIFO drain m), drain ends with the tag at TADR, fromSPR ring copies, VIF1 CHCR / TADR /
  D_CTRL / D_ENABLEW writes, plus VU1 run history and the input header at TOP for runs that hit the budget.
- New debug switches in patch 11: `GOW_VU1_LONGRUNS=<cycles>` (log runs longer than that), `GOW_VU1N_CHECKLONG=1`.

## GS drawing threads without stop-and-go (session 4, 2026-10-22)
- Profiler: `TEKKEN4_PROFILE_THREADS=all` samples every thread (second list "profile-threads"). Fight before
  (logs/fight_threads1, 9-13 fps): the drawing threads drew in only ~12% of their samples; the game thread waited on
  them 50% and spent 11% waking them (`notify_all` per primitive).
- `PS2X_GS_DRAIN_STATS=1` (patch 14) prints once a second how many primitives were queued and why the queue had to be
  drained. With patch 14's first version the fight still drained ~60k times a second for "sample" conflicts: every
  primitive marked the whole frame + Z up to the scissor bottom, in 32-line pages even for 64-line 16-bit pages.
- **Patch 14** (`patches/14-ps2xRuntime-gs-threads-async.patch`, tests 467/467, new test: uploads + TEXFLUSH + CLUT
  reloads under queued primitives give the serial bytes, twice):
  - lock-free queue (chunk table, generation<<32|count, per-worker progress), workers spin briefly then sleep; the
    submitter wakes them every 16 primitives and at every wait;
  - exact page tracking: frame / Z pages under each primitive's bounding box, whole texture, format page sizes
    (64x32, 64x64 16-bit, 128x64 T8, 128x128 T4), 512-bit masks;
  - uploads, CLUT loads and TEXFLUSH wait only on real page overlap; texture caches are refreshed per worker through an
    epoch stamped on each job; CLUT loads under queued primitives write a copy (tables dropped at the next wait);
  - shutdown drops queued primitives (no drawing after GS memory is gone).
- Result (logs/fight_drains2, same keys): drains per second sample 60k -> ~120, clut 3-7k -> ~19, upload ~300,
  write ~90; **fight 18-21 fps** (GS 560 ms per second, was 800); main menu and stage render as before.
- Not upstreamed yet (builds on patch 09, which is not upstream either).

## Game-thread copies (patch 15, session 4, 2026-10-22)
- Grok game-thread (analysis, logs/grok/game-thread_20261022_013250.json) -> game-thread-fixes (work,
  logs/grok/game-thread-fixes-notes.md): GIF packets drained immediately without the arbiter's heap copy, VIF1
  UNPACK V4-32 / 32-bit memcpy fast path, fromSPR span memcpy + drainMfifo reusing its buffer. Fight s50-94 mean fps
  20.33 -> 22.42 -> 22.91 -> 22.93 (Grok runs; shared tree, gs-throughput was editing at the same time).
- Its 4th fix (EE timer batching up to the next compare/overflow) broke 2 tests ("EE Timer2 compare and overflow
  flags raise INTC_TIM2 ...", "EE Timer2 compare IRQ wakes a DelayThread-style semaphore wait") on a clean 01-15
  worktree; Grok's IRQ counters read 0 before and after, so its own check could not see it. Timer ticks are applied
  on every call again (the batching scaffolding stays, inert).
- **Patch 15** (`patches/15-ps2xRuntime-game-thread-copies.patch`): 467/467 on a clean worktree
  (`external/ps2recomp-p15check`: upstream HEAD + patches 01-15; reverse-apply / apply there to validate a patch
  stack without the other tasks' in-progress edits; its build_pr_tests.cmd is local).

## Fight camera fixed: SQRT.S operand (patch 16, session 4, 2026-10-22)
- Grok camera-live (logs/grok/camera-live_20261022_053728.json, logs/grok/camera-live-notes.md): PS2Recomp translated EE
  SQRT.S as sqrt(fs); the EE encodes SQRT.S fd, ft (radicand in ft, fs = 0). FUN_00253ad0 turned the identity parent
  into quaternion (0.5,0.5,0.5,0.5), cancelling the camera's bind permutation and leaving its 717-unit boom on world X.
- **Patch 16** (`patches/16-ps2xRecomp-sqrt-s-uses-ft.patch`, recompiler + translation test): 467/467 on the clean
  01-16 worktree. Regenerated: 78 files hold SQRT.S, 53 changed (the rest sqrt'd f0 either way).
- **Verified** (logs/camera_sqrtfix_clean2, clean tree + committed overrides, frame shot frame_92s): normal side view,
  both fighters full-body (docs/img/fight_camera_fixed.png). Fight 23-28 fps on the shared tree run (was 20-23).
- Open: Kazuya's suit looks white / very bright: alternate costume or over-bright lighting? Compare with PCSX2.
- Window captures were blank all night (monitor off, hidden Grok processes): use frame_NNs.bmp
  (runtime/tekken4_frameshot_overrides.cpp, set by run_capture.ps1) + `python -I tools/bmp_to_png.py <run dir>`.

## EE FPU / VU0 macro semantics (patch 17, session 4, 2026-10-22)
- Grok fpu-audit (logs/grok/fpu-audit_20261022_062059.json) -> fpu-fixes (logs/grok/fpu-fixes_20261022_065037.json):
  CVT.W.S chops toward zero with EE saturation (was nearbyintf; 497 sites), macro VCLIP side bits in PCSX2 order (35 vclipw,
  21 CFC2.CLIP reads), macro FMAC ops write vu0_mac_flags (4 CFC2.MAC reads), VFTOI0/4/12/15 saturate.
- **Patch 17** (`patches/17-ps2xRecomp-ee-fpu-vu0-macro-semantics.patch`): 471/471 on the clean 01-17 worktree. Regenerated
  (148 files changed). Fight (logs/fpufix_fight1): 26-29 fps, picture as before (frame_92s.png). No visible change was
  expected; these fix logic/culling edge cases (float->int truncation everywhere).

## 60 fps budget (session 4, 2026-10-22)
- gs-throughput (logs/grok/gs-throughput-notes.md): at 24 fps a fight frame is ~41.7 ms = ~23 ms GS wait + ~18.5 ms of
  other game-thread work. A 60 fps frame is 16.7 ms, so even a zero GS wait caps the fight at ~54 fps: both must go
  (GS fully overlapped AND non-GS game-thread work < 16.7 ms).
- Non-GS shares (stack profile logs/grok/stack-profiler-3): IOP kernel scheduling ~9% (beginNextReady 5.1, nextWakeCycle
  2.4, runCycles + serviceDue 1.4) -> Grok iop-sched; texture upload writeImageTransfer<19> 7.4% (GS side, gs-throughput);
  EE timers ~2%; VIF / VU1 / recompiled game code each ~1% or less.

## Grok in the pipeline (from 2026-10-21)
The user added Grok (xAI Grok Build CLI 1.0.62, `C:\Users\pablo\.grok\bin\grok.exe`, signed in with the user's
grok.com account, default model grok-4.7) as a parallel worker, second opinion and reviewer; it may see everything that
is not personal (never the disc files, ISO or BIOS). Heavy analysis / coding jobs go to it too (`-Effort high`).
- `tools\grok_task.ps1 -Name <n> -Mode ask|work [-Owns <files>] [-Effort high] (-Prompt <text> | -PromptFile <file>)`,
  run in the background; result in `logs\grok\<n>_<time>.md` (answer + files changed in both repos), prompt in
  `.prompt.md`. The prompt goes through `--prompt-file` (PowerShell 5.1 breaks double quotes in native arguments).
  Project rules are passed with `--rules` (Grok does not load the project's CLAUDE.md: the project is not "trusted").
- A headless run cannot approve anything, and a refused tool ends it without a final answer, so each mode allows
  exactly what its tasks need (`--allow` rules; `--always-approve` is refused by Claude Code's auto mode):
  - ask (analysis, reviews, research): reads anything, writes only `logs/grok/**`, runs `python -I` and read-only git.
  - work (a change, in the main project): edits only the `-Owns` files and `logs/grok/**`, runs
    `cmd /c tools\build_runtime.cmd` and `powershell -File tools\run_capture.ps1` with `TEKKEN4_BUILD_DIR=grok`
    (build in `external\PS2Recomp\out\grok`, never Claude's `out\runtime`), plus python and read-only git; never
    commits. Claude keeps off the owned files meanwhile, reviews the diff and commits.
- The build/run scripts take `TEKKEN4_BUILD_DIR` (default `runtime`). Both builds compile the same PS2Recomp source
  tree, so an owned file Grok is mid-way through editing also lands in Claude's next build.
- **Mutual review (2026-10-21):** Claude reviewed Grok (logs/grok/review_claude_on_grok.json), Grok reviewed Claude
  (logs/grok/review-claude_20261021_215022.json, 25 facts with refs, 24 rules). Result: docs/ai/collaboration.md (roles,
  handoff, verification, run lock, limits, disagreement) + docs/ai/grok-brief.md (what Grok reads first). Wrapper: JSON
  answers with contra[], ask mode cannot start the game/PCSX2/pine, files_changed only the -Owns files, tools\grok_stop.ps1
  kills a task's grok.exe; run scripts share logs\run.lock (tools\run_lock.ps1).
- Findings so far: the pad-2 bug is `scePadGetState` (external/PS2Recomp/.../Kernel/Stubs/Pad.cpp:453) returning
  "stable" for any opened port without checking that a pad is connected, so port 2 looks plugged in (PRESS P2 START,
  VS BATTLE). **Fixed by Grok = patch 13** (`patches/13-ps2xRuntime-pad-empty-port-disconnected.patch`, Pad.cpp only):
  port 0 = keyboard + first host gamepad as before; port 1+ connected only with another host gamepad; an empty open
  port reads scePadStateDiscon, scePadRead returns 0 (data 0xFF), info/req calls 0. Verified (logs/grok/pad2-fix-notes.md):
  VS BATTLE greyed and skipped by the cursor, character select CREDIT 0 like PCSX2; tests 466/466. Not run with a
  second physical gamepad.
- Grok "vu1-vi12" (cut off by a refused write before the modes above, partial): vi12 is used as the count mask once
  (0x3390) and then overwritten inside the same program, so the mask at the next start of 0x32a0 is whatever an
  earlier run left. Rerun it with the new ask mode.

## Publishing (from 2026-10-21)
The user pre-authorized publishing every successful milestone on three channels:
- **Project repo (private since 2026-10-21, the user's choice; was public):** https://github.com/Lautreck/tekken4-recomp (`origin`, branch `master`). Commits use
  `Pablo <8440795+Lautreck@users.noreply.github.com>` (set in this repo's git config; history was rewritten to it
  before the first push). Never push game files, Ghidra DBs, generated C++, BIOS or disc data.
- **Upstream PRs:** fork https://github.com/Lautreck/PS2Recomp (remote `fork` in `external/PS2Recomp`).
  PR #372 https://github.com/ran-j/PS2Recomp/pull/372 = `patches/ps2xRuntime-dmac-mfifo.patch` (branch
  `dmac-mfifo`, commit 38d6396). `external/PS2Recomp` now sits on that branch (eb8688b + the patch), so
  `build_runtime.cmd` finds the patch already applied. If the PR is merged, move back to upstream `main` and
  drop the patch file. Upstream PR style: plain title, problem / per-file changes / found while / verified with,
  "Made by Pablo and assisted with Claude Code."
- PR #373 https://github.com/ran-j/PS2Recomp/pull/373 = patch 02 without MFIFO (branch `dma-vif1-fixes`, commit
  8e97bf7, built and tested in the worktree `external/ps2recomp-pr2`, 450/450; its `build_pr_tests.cmd` is local
  only, never commit it). Issue #374 https://github.com/ran-j/PS2Recomp/issues/374 = the pk stubs' live QWC
  doubling the count when a game's own close runs (our `closeDmaTag` override works around it).
- PR #375 https://github.com/ran-j/PS2Recomp/pull/375 = patch 03, display line repeat (branch `display-line-repeat`,
  commit d030383, worktree `external/ps2recomp-pr3`, 446/446).
- PR #376 https://github.com/ran-j/PS2Recomp/pull/376 = patch 04 + a test, sceMpegCreate clears mp->sys word 0
  (branch `mpeg-create-clears-end`, commit ccaa06f, worktree `external/ps2recomp-pr4`, 446/446).
- PR #375 also carries patch 06 (second commit d9141f2, field offset; title and description updated, 447/447).
- PR #377 https://github.com/ran-j/PS2Recomp/pull/377 = patches 05 + 07 + 08 with tests (three commits) (two strips 0..63.5 and 64..127.5),
  branch `sprite-edge-coverage`, worktree `external/ps2recomp-pr5`, 446/446. The test is only in the PR branch.
- PR #378 https://github.com/ran-j/PS2Recomp/pull/378 = generic qwc fix for issue #374 (stubs no longer SET the open
  DMA tag qwc; terminate ADDs it once), implemented by Grok (qwc-pr) from its upstream-qwc design, branch
  `qwc-close-once`, commit 792f431, worktree `external/ps2recomp-pr6`, 449/449. When merged, drop the closeDmaTag
  override registrations at 0x292900 / 0x292c18 in runtime/tekken4_overrides.cpp (redundant then).
  Memcard (Grok memcard, logs/grok/memcard_20261022.json): no stub bug; saves only run after a menu asks to save
  (UI opcode 16), which no test run reached yet.
- PR #380 https://github.com/ran-j/PS2Recomp/pull/380 = patch 15 upstream (GIF pass-through on an empty arbiter
  queue + 32-bit UNPACK memcpy), ported by Grok (copies-pr) without MFIFO span reuse / timer scaffold, branch
  `game-thread-copies`, worktree `external/ps2recomp-pr7`, 448/448.
- PR #381 https://github.com/ran-j/PS2Recomp/pull/381 = patch 13 upstream (open pad port without a controller
  reads as disconnected), ported by Grok (pad-pr), branch `pad-empty-port-disconnected`, worktree
  `external/ps2recomp-pr8`, 447/447.
- PR #382 https://github.com/ran-j/PS2Recomp/pull/382 = patch 16 (EE SQRT.S reads ft), branch `sqrt-s-uses-ft`,
  worktree `external/ps2recomp-pr9`, 445/445. Fixes the Tekken 4 fight camera.
- **Milestone pages** (private until the user shares them from the page's Share menu): milestone 4 at
  https://claude.ai/artifact/BTDUfBQqwaDsn83wdRh2gf (our runtime screenshot next to PCSX2's), milestone 5 at
  https://claude.ai/artifact/CoN3nkpepFjyn5LSbPEQ7j (menu, PAL60 confirmation, Namco logo; four fixes). Milestone 6 at
  https://claude.ai/artifact/CGjVKCtqc6WGA2aat476gt (boot to main menu, ours next to PCSX2; PRs #375-#377).
  A session-3 progress page for the user: https://claude.ai/artifact/Y2iCxSTrfwM5mY5rWZxWK2.

## Next steps
1. Upstream patch 09 (GS speed + drawing threads) once PR #377 is in, as a follow-up PR.
2. Milestone 7, a fight: it loads and renders (see "First fight") at ~7 fps, VU1-bound. Options, cheapest
   first (now doing (c), see "Native VU1 port"): (a) speed up the VU1 interpreter's hot paths (pipeline bookkeeping per pair); (b) VIF1 + VU1 on a worker
   thread (the GoW port's PS2X_GS_WORKER); (c) native VU1: translate Tekken's 22 micro-program overlays ahead of
   time (the GoW port's vu1n_gen.py approach, with a bit-exact replay check). Then compare the fight with PCSX2,
   test fight input (pad 1 moves), and look at pad 2 being reported as connected (PRESS P2 START, VS BATTLE).
3. Sound for real (milestone 8): find how the game loads its IOP modules (sceSifRebootIop with
   IOPRP243.IMG, then module buffers probably from DATA.BIN), extract the sound IRX and run it on ps2xIOP's
   emulated IOP. Then the override's sound part goes away.
4. Watch PRs #372/#373/#375/#376/#377 and issue #374: when merged, move `external/PS2Recomp` back to upstream main and drop the
   patch files.
5. Re-export from Ghidra (3 late SDK renames) whenever Ghidra is next used for an export; rerun post-process.
6. Later: export Ghidra's switch tables into `[jump_tables]` to cut the unresolved JR sites.
7. Watch: upstream keeps its RPC server pool at guest 0x01F10000, above the game's stack top (sp starts
   ~0x1f00000). If a heap ever lives there, see the GoW `GuestReservedLayout` lesson.

## Batch review 2026-10-22 (grok-review)
- fpu-pr: committed the 5 files in external/ps2recomp-pr10, pushed Lautreck:ee-fpu-vu0-macro-semantics, opened upstream PR https://github.com/ran-j/PS2Recomp/pull/383 (notes said ready; 449/449 on rerun, 1 flaky Timer2 150 ms wait on the first run).
- gs-throughput: patches/18-ps2xRuntime-gs-throughput.patch (6 GS files: gs_cpu_backend.h/.cpp, gs_texture_page_cache.h, ps2_gs_memory.h/.cpp, ps2_gs_tests.cpp; gs_frontend unchanged vs p15check) applies clean to external/ps2recomp-p15check (now has 18 applied, uncommitted like 01-17). ps2x_tests 478/478; clean_build + fight run logs/batch18: frame non-blank, fight sec 110-139 avg 27.6 fps, GS ~610-660 ms/s (before ~25-27 fps, GS ~636). Note tools/build_tests.cmd ignores TEKKEN4_SRC (always external\PS2Recomp). Next: gs-review-fixes, then jump-tables merge.
- sound-run (report only): changes still unmerged in external/PS2Recomp (IOP heap now top-down from HeapLimit so ps2_sif_dma_tests:203 passes, 478/478; sound_engine reverb + movie PCM; overrides hook). Open: char-select 20 s digital silence, WAV shorter than wall clock, heap direction is process-wide and untested without TEKKEN4_SOUND.
- iop-sched (report only): patch logs/grok/iop-sched_20261022_070303.patch, 477 tests pass, fight 24.8 -> 27.4 fps paired, kernel leaf cost 9% -> ~3%. Open: "no ready thread until cycle X" cache in iop_emulator.cpp (runCycles ~1e7/s kernel entries). Not merged.
- fight-visuals (report only): Kazuya difference is mostly costume: ours stays 1P (white gi) after Cross while PCSX2 switches to 2P (blue shirt); our pad Cross may not reach the costume select. GS dump shows body prims MODULATE PSMT8, no global blowout (dark groups mean ~58). No renderer bug proven.

## Patch 18: GS throughput (Grok gs-throughput, reviewed 2026-10-22 by grok-review)
- patches/18-ps2xRuntime-gs-throughput.patch (tight texture pages, 512-slot CLUT pool, Q-ratio cut, depth-reject before
  sample, no second Z read, no drain on UploadImage without pixels). Files: gs_cpu_backend.{cpp,h}, ps2_gs_memory.{cpp,h},
  gs_texture_page_cache.h, ps2_gs_tests.cpp. Applies on HEAD + patches 02-17 (p15check was rebuilt that way; patch 01 is upstream now).
- Clean tests (external/ps2recomp-p15check, logs/review_p18_tests.txt): 478/478. Clean game run (logs/review_gs3): fight frame at 70s
  is Kazuya vs Law, normal (frame_stats not blank); fight fps 26 steady (was ~22.9), menu 60. Shots later than ~75 s are not
  written by the capture (run ends first): use -Shots <= 70.
- Next: gs-review-fixes (docs/ai/prompts/), then merge jump-tables.
