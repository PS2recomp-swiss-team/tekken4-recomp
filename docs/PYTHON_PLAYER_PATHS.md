The launcher builds and starts online games through Python 3.8+ (standard
library only). Release zips use their private Windows Python, compiler, CMake
and Ninja, including when run under Proton/Wine. This builds a Windows game
inside the Wine prefix; native Linux compilation is not implemented.

The entry points are:

```
python -I tools/build_game.py -Iso "your US disc.iso"
python -I tools/build_game.py -Iso "your US disc.iso" -WhatIf
python -I tools/net_play.py -Host -Iso "your US disc.iso" -Port 7400
python -I tools/net_play.py -Join <host-IPv4> -Iso "your US disc.iso" -Port 7400
```

In a player release use `python\python.exe` in place of `python`. On Linux,
start that Windows interpreter with the same Wine/Proton prefix as the
launcher. Windows paths passed to it must be visible in that prefix. The
launcher chooses this interpreter automatically. First setup on Steam Deck
should be in Desktop mode.

The original single-dash PowerShell arguments remain accepted (case
insensitive); Python also accepts `--iso`, `--steps`, `--force`, `--what-if`
or `--dry-run`, `--host`, `--join`, etc. Step order is always prereq, verify,
extract, fork, tools, recomp, stage, runtime. `-Steps` accepts comma-separated
or space-separated names. `-Force` rebuilds without re-cloning an existing
source tree. `-WhatIf` checks prerequisites and the ISO, writes the build log,
and does not extract, clone, fetch a sysroot, stage, compile or save state.
Licence acceptance is still explicit and is ignored during a dry run.

`build_game.ps1`, `build_game_portable.ps1` and `net_play.ps1` forward to the
Python entry points on Windows. `us_tree.ps1`/`.cmd` and the dot-sourced
`net_preflight.ps1` API delegate to the same Python logic. The pipeline does
not call the old batch build scripts, robocopy or PowerShell. A developer
checkout still imports Visual Studio's environment through `vcvars64.bat`;
the portable release does not need Visual Studio or Git.

Existing build state and output locations remain in use: `game/disc`,
`generated`, the selected source tree's `out/tools` and `out/<build>`,
`logs/build_game.log` and `logs/build_game_state.json`. The launcher still
receives `[n/total] step - title`, indented result/timing and extraction
percentage lines; its log follower still sees Ninja's counters. Staging
preserves unchanged timestamps and never purges files. VU1 generation and
`t4net_build.txt`/`.json` generation are included, even for an up-to-date
runtime's build identity.

Online runs retain `build_identity.json`, `run_info.json`, `preflight.json`,
`stdout.txt` and `stderr.txt` under `logs/net/play_<side>_<time>` (or `-RunDir`).
The `T4TEST1` UDP JSON format, nonce/echo/ready exchange, identity comparison,
timeout, bind/port overrides and explicit `-SkipPreflight` escape hatch remain
compatible. The Python probe and game executable need separate firewall
permission on Windows; UDP forwarding/VPN setup still belongs to the player.
Identity fields sent over UDP exclude paths and computer names.

Validation performed here uses synthetic fixtures, mocked sockets/processes
and an actual CLI dry run; no game build or live Linux test was performed.
The pre-existing public-source scanner IPv6 fixture failure in
`test_publish_source.ContentScanTests.test_server_addresses` was present
before this change and is outside this port.

Real validation still required:

1. Windows: build from a verified US SLUS-20328 v1.00 ISO in a fresh portable
   release, including explicit Microsoft licence acceptance, locked sysroot
   download/extraction, all eight steps, native VU1 output and build stamps.
   Repeat through the launcher and PowerShell wrapper; verify logs, visible
   progress, game boot/audio/input, no-change resume, forced rebuild and
   interrupted-build retry. Also build a source checkout with VS 2022.
2. Linux/Steam Deck: repeat the portable first build and no-change resume
   inside a real Wine/Proton prefix without working PowerShell. In particular
   validate Wine's MSI database reader and `expand.exe` during sysroot setup,
   bundled CMake/Ninja/clang-cl/lld-link, paths containing spaces/non-ASCII,
   launcher progress and cancellation, and offline game boot/audio/controls.
3. Two real peers: host/join Windows-to-Windows and Linux-to-Windows with the
   same portable release/compiler and independently supplied matching ISOs.
   Check identity/UDP success before game launch, a playable match, saved
   reports and game exit codes. Check mismatch, timeout, occupied port,
   firewall denial, both host roles and `TEKKEN4_NET_BIND`/`TEKKEN4_NET_PORT`.
   UDP preflight success does not by itself prove the game's firewall rule,
   NAT mapping or rollback performance under Wine.
