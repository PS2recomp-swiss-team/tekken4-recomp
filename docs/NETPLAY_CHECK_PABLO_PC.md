# US rollback netplay on this PC (2026-10-29)

Scope: read and run only. No source edits under H:\tekken4-recomp_usa or H:\tekken4-fork-ps2recomp_usa. Trees checked: game repo us-iso 1dcd9aa84deb7d80f55e09208b9e7f429efa89bc, PS2Recomp t4-us 543b91a794e93500f31cd8f0c47522ec22bead13. Exe: H:\tekken4-fork-ps2recomp_usa\out\runtime\ps2xRuntime\ps2EntryRunner.exe (49745408 bytes). Compiler recorded in that build: MSVC 14.44.35207 (out\runtime\CMakeCache.txt:33).

## 1. Measured pair

Command (US lock was empty; PAL lock was empty):

powershell -File H:\tekken4-recomp_usa\tools\net_pair.ps1 -Name grok-us-probe -Src H:\tekken4-fork-ps2recomp_usa -BuildDir runtime -End 300 -Seconds 90 -Rtt 0

Script result: "ran 91 s". Run dir H:\tekken4-recomp_usa\logs\net\grok-us-probe\{host,join}. Window title is set by the script to "TEKKEN 4 - Claude: grok-us-probe host|join (P1|P2)" (tools\net_pair.ps1:80). That title was not observed on screen.

params.txt (host): TEKKEN4_NET=host:7400, TEKKEN4_NET_END=300, TEKKEN4_SOUND=0, PS2X_GS_BACKEND=gl, no TEKKEN4_NET_BUILD. No t4net_build.txt next to the exe.

| run | RTT set (measured) | input delay | rollbacks host/join | resim frames | max depth | rollback ms p50/p90/max | stalls | time-sync | fps | displayed frame p50/p99 ms | hashes compared | desyncs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| grok-us-probe | 0 (no session) | none | none | none | none | none | none | none | none | none | 0 | not checked |

Both stdout.txt:50:

[rollback] unknown TEKKEN4_RB_MODE=net (measure|test|selfnet|net), rollback off

Both sides: no rb_frames.log (script printed "host: no rb_frames.log" / "join: no rb_frames.log").

Why a 12000-frame PHASE3 pair was not started: TEKKEN4_NET is rewritten to mode "net" (runtime\tekken4_rollback_overrides.cpp:1829-1831). Mode::Net is compiled only under TEKKEN4_NETPLAY (1840-1842). The else at 1844-1847 returns before rb_frames.log is opened (fopen at 1986). A longer -End cannot emit NETSUMMARY, NETHASH, or NETEND from this exe.

Why TEKKEN4_NETPLAY is off: the guard is __has_include("tekken4_net.h") && PS2X_ROLLBACK_IOP_STATE (rollback overrides 84-87). PS2X_ROLLBACK_IOP_STATE is 1 (ps2_rollback.h:25). tekken4_net.cpp and tekken4_net.h are not in ps2xRuntime\src\runner. CMake compiles src/runner/*_net*.cpp on their own and links ws2_32 only when that glob is non-empty (ps2xRuntime\CMakeLists.txt:475-484). Byte scan of the exe: NETDESYNC=-1, T4NP=-1, tekken4_net=-1, build_mismatch=-1. NETSUMMARY, NETHASH, rb_frames.log, TEKKEN4_NET are present because those strings exist outside the ifdef (phase-2 summary and the getenv at 1829).

TheWishin's PHASE3 table (docs\ROLLBACK_PHASE3.md:12-16, his D:\tekken4-fork-net out\net, not this exe, not remeasured here): n0b / n50b / n150b, 0 desyncs, fight fps ~36.8-38.2, displayed frame ~21-27 ms p50. His build id in SERVER_HANDOFF_T4.md:44 is 9e86181788650d64. This PC's id is different (section 2).

## 2. Forced desync

Not run. NETDESYNC is fprintf'd only inside TEKKEN4_NETPLAY (rollback overrides 1516) and that string is absent from the exe, so the transport never compares hashes and never writes net_desync_f*.bin.

Documented recipe (ROLLBACK_PHASE3.md:39-40): joiner with another srand pin. On a net-enabled build that is -Env TEKKEN4_RAND_SEED=1 plus -JoinEnv TEKKEN4_RAND_SEED=2 (net_pair.ps1:7, 56-57: JoinEnv is applied after the shared -Env). The pin is stored at the newlib rand word reent+88 (rollback overrides 1780-1790; reent read from guest 0x304b94). His ndesync named the differing word 0x304900 (_impure_ptr+88) 1 vs 2. Diff tool: python -I docs\rollback\net_desync_diff.py <host bin> <join bin> (docs\rollback\net_desync_diff.py:1-35). Tool not executed: no dumps.

## 3. Build id

python -I H:\tekken4-recomp_usa\tools\t4_buildid.py --src H:\tekken4-fork-ps2recomp_usa
(print only; no --out, so no t4net_build.txt was written)

3004bda9680abd51 elf a4b7dde20a2918c550badd127a245db155c36815 code ca21e8ad1751697d04cda57d79d3711274c74960 net 1

elf matches the SLUS-20328 v1.00 constant in SERVER_HANDOFF_T4.md:40 and t4_buildid.py:5. net = kNetVersion = 1 (tekken4_net.h:15).

Formula (t4_buildid.py:11, 68-82): build id = sha1("t4dr-build:<elf_sha1>:<code_id>:<net>")[:16]. code_id = sha1 of:

- commit: git rev-parse HEAD of the PS2Recomp tree (this PC: 543b91a...)
- diff: git diff HEAD of that tree excluding ps2xRuntime/src/runner. This PC: that diff is empty (git diff --shortstat exited 0 with no output).
- every patches\*.patch in the game repo, by basename + file sha1. git status --porcelain of patches, config, runtime was empty.
- every config\*.toml and config\*.csv, same way.
- runner modules matching *_overrides.cpp, tekken4_net*.cpp, tekken4_net*.h, by basename + file sha1. The net glob matches nothing here, so this id does not include a transport. Tracked rollback/overrides files are clean (git status --porcelain on those paths was empty).

Two players who each run tools\build_game.ps1 from their own ISO get the same id only when all of those bytes match: same SLUS_203.28, same PS2Recomp commit, empty (or identical) diff outside the runner, identical patch files, identical config, identical staged overrides and tekken4_net*. build_game.ps1 stages via tools\stage_generated.cmd (build_game.ps1:460-466) into the tree out\<BuildDir> (default runtime, line 64). It does not run t4_buildid.py. docs\rollback\net_build.cmd:24-25 is what writes the stamp, and that script is hardcoded to D:\tekken4-fork-net and D:\tekken4-us.

What changes the id: another ISO revision; another fork commit; any uncommitted edit outside the runner; a different patch or config byte; a different staged override or tekken4_net file (copying the transport in, which his net build does, changes code_id). What does not change the id, and can still desync two peers who pass the handshake: uncommitted edits under ps2xRuntime/src/runner other than the hashed module globs (generated FUN_*.cpp are excluded from the diff and are not in the module glob); the compiler and flags (CMakeLists.txt has no /fp: entry; this build is MSVC 14.44.35207; a peer on another MSVC gets the same id and a different binary). Handshake refusal when the ids differ is failLocked("build_mismatch") (tekken4_net.cpp:512-521, 579-582) and the game continues offline (rollback overrides 1382-1386). That path is source-only on this PC: build_mismatch is not in the exe.

## 4. Gaps for two PCs over the internet

Sizes are the work left, not the design text. "Wishin" = listed as his open / not-yet-tested item in SERVER_HANDOFF_T4.md. lobby\ is not on this PC (directory absent). The handoff says that tree is git-excluded and lived at D:\tekken4-us\lobby (SERVER_HANDOFF_T4.md:5-6).

| gap | size | Wishin | evidence |
|---|---|---|---|
| Lobby server + real game handoff | L | yes (open item, real game pending; coordinator checklist is the other owner's) | LOBBY.md:37-73 maps match_start to TEKKEN4_NET*. SERVER_HANDOFF_T4.md:124-127 stub-only on 127.0.0.1; 157 real game + two PCs still open. Coordinator ports/TLS/install: 142-153, not his code. lobby\ absent here. |
| NAT traversal | L | yes (real NAT/WAN not tested) | Game follows a peer that moves (tekken4_net.cpp:606-611), binds 127.0.0.1 when the peer is loopback (tekken4_net.cpp:894-895). TEKKEN4_NET_PEER is copied onto the host socket in tekken4_rollback_overrides.cpp:1562-1563. Punch/relay/bridge are lobby (LOBBY.md:43-47, 61-64). nat_fallback after 20 s with no "connected" restarts the process onto the relay (LOBBY.md:68-70). SERVER_HANDOFF_T4.md:129: no real NAT, WAN, or relay hop. |
| Input delay choice | S | no (implemented; not in his open list) | Host picks: setting, else 1/2/3/4 frames at RTT <=60 / <=150 / <=250 / above (tekken4_net.cpp:1007-1016). Joiner waits for that pick (1028-1030). Lobby writes TEKKEN4_NET_DELAY from the ticket (LOBBY.md:57). No in-game picker. Ranked table is T5DR's T5L_PING_DELAYS, named in PHASE3.md:200, not a T4 UI. |
| Reconnect | M | no (not named in the open list) | Silence of TEKKEN4_NET_TIMEOUT (default 20 s, tekken4_net.h:48) calls loseLocked("peer_timeout") (tekken4_net.cpp:785-786). A new HELLO is accepted only before either side has sent inputs (525-533); after that, peer_restarted (536-537). No reconnect of the same match. nat_fallback is a new process boot, and only if the first path never connected (LOBBY.md:68-70). |
| Spectators | L | no (day-one off, not an open work item) | Day one turns spectating off (SERVER_HANDOFF_T4.md:101). spectate.py is an unused T5 copy (LOBBY.md:32). Transport slot is host=0 or join=1 (tekken4_net.h:59). |
| Version-mismatch UX | S | no | Other kNetVersion or other build id: failLocked("build_mismatch") (tekken4_net.cpp:484-488, 512-521) and "the game runs offline" (rollback overrides 1382-1386). Strings go to net.log / rb_frames.log. No on-screen string in those paths. Server-side other-game refusal is version_mismatch (SERVER_HANDOFF_T4.md:18-19), lobby code not on this PC. |
| Cross-PC float determinism | M | yes, as part of "two physical PCs not tested" (129), not a separate code task | Compared hash is RDRAM + scratchpad + VU0 + IOP + EE cycle; VU1 data and GS are left out (rollback overrides 1005-1007). US patch 55 sets VU1 round-toward-zero with MXCSR and states x64 float is SSE-only; its "5940 frames identical" is his measure run, not this PC (patches\55-...patch:1-11). code_id does not hash the compiler (t4_buildid.py:68-82). No /fp flag in ps2xRuntime\CMakeLists.txt. |
| CPU / GPU differences | M | same two-PC gap | Vblank cycle step is constexpr microsecondsToEeCycles(16667) at EE clock 294912000 (EeScheduler.cpp:39-53, ee_scheduler.h:281). In rollback mode the earliest cycle-due event fires even if its host deadline is already past; the host clock only waits when the process is early (EeScheduler.cpp:1862-1898). A late schedule is shifted, not caught up by extra vblanks (rollback overrides 1297-1310, npPacingGuard). The guest vsync word written at 2009-2016 is the vblank counter, not a host timestamp. GPU internal scale / FXAA are host GL (section 5). Different CPU speed should not change the hash; different codegen can. Not measured on two PCs (SERVER_HANDOFF_T4.md:129). |
| Windows timer | S | done in source, absent from this exe | EcoQoS off + timeBeginPeriod(1) run inside t4net::start (tekken4_net.cpp:840-851). That function is not in this exe (T4NP absent). QPC in start() seeds the nonce and session id (859-867), not guest RAM. First vblank host deadline is steady_clock::now()+period (EeScheduler.cpp:149-150) and is pacing only. |
| Result file (ranked) | M | yes (158) | Game writes no result file (LOBBY.md:71-73, 124-125). Ranked stays off until it does (SERVER_HANDOFF_T4.md:99-100). |
| Direct fight / persistent session / online save / no-pause | L | yes (159-160) | PHASE3.md:204-208 and LOBBY.md:126-128. Each run dir starts from an empty memory card (PHASE3.md:106, 207). |
| Bandwidth accounting | S | yes (161) | NETSUMMARY prints packet counts, not bytes (rollback overrides 1358-1364). Stats.bytesOut exists (tekken4_net.h:100-103) and is not printed. His estimate ~150 pkt/s and ~250 kbit/s at 60 fps (SERVER_HANDOFF_T4.md:85-93). |

## 5. PAL fixes vs US netplay determinism

Question: if ported, does the fix read host state into guest memory (two PCs with the same build still diverge). A guest/IOP logic change that both peers run stays in sync; the hash already covers IOP (rollback overrides 1029-1033) once patch 41-US (IOP snapshot) is in the tree, which it is (PS2X_ROLLBACK_IOP_STATE).

Music 35 (PAL patches\35-ps2xIOP-cdsearchfile-iso9660.patch): sceCdSearchFile fills lsn, size, name from the ISO9660 image and leaves the date 0 (patch:23-24). Host path is only which file is opened (patch:31). Same ISO bytes => same guest record. A missing image fails the lookup and BGM stays off (patch comment 25-27): that is host file presence, not a clock. US already has this class of fix as patches\36-...cdvd-ioman...patch:1-14 (US DATA.BIN LBN 401 vs a hard-coded PAL 1236). Porting PAL 35 on top is a second implementation, not a new clock leak. Determinism impact if the US 36 behavior is kept: none beyond "both sides must open the same image".

Music 36 (PAL patches\36-ps2xIOP-spu2-irq-sif-user-cmds.patch): std::chrono is used only when TEKKEN4_IOP_DUMP is set, and it writes a host file of IOP RAM (patch:275-296). It does not store the clock in the guest. The SIF/IRQ path itself is IOP logic. US patches 33 (SIF payload) and 34 (SPU2 IRQ to libsd) already exist. Impact of the dump: none unless the env is set, and then still no guest write.

Music 41 (PAL patches\41-ps2xIOP-spu2-irq-libsd-ack.patch:21-23): sound engine clears ATTR bit 6 on IRQ and stops the sample loop for that IRQ. Deterministic from IOP state. US patch 34 already clears the enable via setCoreAttr(4, 0) before the handler (patches\34-...patch:122-124). Porting PAL 41's extra "break the mix loop" changes how far the IOP advances on an IRQ. Both peers with that patch stay synced; it does not read the host audio device. The host audio queue is outside the snapshot (PHASE3.md:60).

F2 settings 37 (PAL patches\37-ps2xRuntime-settings-window.patch): host ImGui window (m_settingsVisible, ps2_graphics_settings.cpp). No guest write in the added window. Impact: none by itself.

F2 38 internal resolution (PAL patches\38-...patch:97-106, 220-230): GL texture scale and, above 1x, host sprite-edge snap. Uploads stay PS2-sized and are blitted. Compared hash excludes GS. Two PCs on different scales should still match the hash. Not measured. Impact: none on the hash, S residual if some path read the scaled texture back (no glRead of the scaled target in that patch; the only "readback" hit is a comment at patch:419 about keys during present).

F2 39 widescreen (PAL patches\39-...patch:164, 208, 282-284): the F2 checkbox calls ps2_switches::set("widescreen"), and the recompiler emits PS2_SWITCH("widescreen") around a replacement instruction (patch:79-82). That is a host setting selecting which guest instruction runs. Two PCs with different checkbox values desync. Both off (the default bool widescreen = false) do not. This is the port that affects determinism. Size M. US needs its own instruction addresses; the PAL [patches] words are not the US ELF.

F2 40 FXAA/sharpen (PAL patches\40-...patch:139-179, 216): one fragment shader while the frame is drawn to the window. Frame shots keep the guest frame. Impact: none on the hash.

Controls (not a patch file yet; PAL fork ps2xRuntime\src\lib\ps2_pad.cpp:78-92 and ps2_input_latency.cpp:80-98): the keyboard becomes a pad button mask (published Snap vkMask OR GetAsyncKeyState). Those bits are what a net frame would sample (rollback overrides 1146-1159, axes quantized to 3 levels). QueryPerformanceCounter in that file feeds ps2_hud::noteSample (ps2_input_latency.cpp:71-76, 496-497), not guest RAM. Porting the remap does not put host state into guest memory beyond the pad word netplay already exchanges. Per-player key tables can differ; each side sends its own buttons.

## 6. What was not done

No rebuild, no file copied into either US tree, no 12000-frame pair, no ndesync dumps, no lobby process, no second PC. Probe logs left at H:\tekken4-recomp_usa\logs\net\grok-us-probe.
