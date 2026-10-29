# netplay-hash notes (US re-scope, 2026-10-29)

Read-only on both US trees. Report: logs/grok/netplay-us-report.md.

Trees: H:\tekken4-recomp_usa us-iso 1dcd9aa84deb7d80f55e09208b9e7f429efa89bc; H:\tekken4-fork-ps2recomp_usa t4-us 543b91a794e93500f31cd8f0c47522ec22bead13. Both run.lock files were a single newline (no live holder).

Exe out\runtime\ps2xRuntime\ps2EntryRunner.exe size 49745408. Python byte scan: NETDESYNC -1, T4NP -1, tekken4_net -1, build_mismatch -1; NETSUMMARY, NETHASH, rb_frames.log, TEKKEN4_NET present. tekken4_net.cpp/.h not in the runner. lobby\ absent. t4net_build.txt absent. MSVC 14.44.35207 (CMakeCache.txt:33).

t4_buildid.py --src that tree, no --out: 3004bda9680abd51 elf a4b7dde20a2918c550badd127a245db155c36815 code ca21e8ad1751697d04cda57d79d3711274c74960 net 1. git diff --shortstat HEAD excluding runner: empty. git status --porcelain patches config runtime: empty. Runner override paths: clean. His stamp id 9e86181788650d64 is SERVER_HANDOFF_T4.md:44, other tree, not recomputed.

Probe: powershell -File H:\tekken4-recomp_usa\tools\net_pair.ps1 -Name grok-us-probe -Src H:\tekken4-fork-ps2recomp_usa -BuildDir runtime -End 300 -Seconds 90 -Rtt 0. Script: ran 91 s. Both stdout.txt:50 unknown TEKKEN4_RB_MODE=net, rollback off. No rb_frames.log either side. No NETSUMMARY, no RTT sample, no desync count. Cause: TEKKEN4_NETPLAY requires __has_include("tekken4_net.h") (tekken4_rollback_overrides.cpp:84-87, 1840-1847 returns before fopen at 1986).

ndesync not run (string absent from exe). Full End 12000 pair not started: same early return.

Next, only with TheWishin's OK: copy runtime\tekken4_net.cpp and tekken4_net.h into the runner (his net_build.cmd:19-20, paths are D:\), rebuild, stamp, rerun net_pair with the PHASE3 env, then -JoinEnv TEKKEN4_RAND_SEED=2 and net_desync_diff.py.

Probe logs left at H:\tekken4-recomp_usa\logs\net\grok-us-probe. Not deleted.
