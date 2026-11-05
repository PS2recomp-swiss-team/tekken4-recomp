# Tekken 4 Recomp v0.1.1 (pre-release) - release notes

Tekken 4 USA v1.00 (SLUS-20328), static recompilation for Windows, built on your PC from your own ISO.
No game data, BIOS or built game program is in the download. Project code is GPL-3.0.

This is a pre-release. It is the first T4 version with ranked play through the OpenRecomp-FGC launcher.
Direct IP / VPN play still works without a lobby.

## What is new

**Ranked and casual online (through the OpenRecomp-FGC launcher)**
- Ranked uses the same 37 ranks as Tekken 5 Dark Resurrection Online (T5DR). Your rank comes from the shared
  OpenRecomp account; T4 only draws it.
- A match is first to 3 rounds. Three round markers per side are shown under the life bars.
- Player names replace the fighter names on the VS select and in the fight, drawn in the game's own font
  (printable ASCII, up to 16 characters, shortened to fit).
- A rank badge sits next to each name. If T5DR is installed, you see its real rank plate; otherwise a drawn badge.
  Guests have a name and no badge. The plates are only read from your own T5DR files, never copied or shipped.
- The game reports the result itself (winner, round score, fighters, stage). Nobody types in who won.
- Online games boot straight to the VS character select, so you only pick your fighter.
  Set `TEKKEN4_NET_AUTO_VS=0` for the old manual menus (both players must use the same setting).
- Online play outside the VS flow (title, mode select, movies) runs in lockstep, never in rollback. This fixes a
  desync when a scene change started inside a rolled-back frame (docs/MOVIE_ROLLBACK_T4.md).

**Speed (aimed at 60 fps in fights)**
- VU1 / VU0 microprograms are recompiled to native code at build time from your own game files. Covered paths run
  without the VU interpreter. Paths not covered still use the exact engine, so this is not an interpreter-free game.
- The IOP (sound driver CPU) skips idle time cheaply, with the same state bit for bit.
- VU1 and the GS front end run on their own threads (on by default).
- On a fast PC, 9 of 10 test stages held a steady 60 fps (the worst reached 57); see docs/PERF.md. This is not a
  promise for slow PCs.

**Intro movie sound**
- The stereo decoding was wrong (channels were interleaved at the wrong size) and the movie audio queue ran dry.
  Both are fixed: no audio gaps over 5 ms in a 119-second capture, and the level matches the original game.
- Audio-to-picture offset of the intro was not measured.

**Older PCs**
- BUILD GAME makes an SSE2-only program on a CPU without SSSE3 / SSE4.1 (Phenom II, Athlon II, first Core 2).
  Online results stay identical to the normal build, so mixed pairs can play each other.
- A graphics card with OpenGL 4.3 is still required (GeForce GTX 400 or newer, Radeon HD 5000/6000 or HD 7000 and
  newer; Intel HD 4600 probably). Intel HD 2000-4000 cannot run it. 4 GB RAM.
- 4 cores / 4 threads of about 2012 or newer are recommended for 60 fps in fights. 2 cores run the game but drop
  below 60 in fights. In Settings, choose Internal resolution "Low" (480p) on a weak PC.
- No Core 2 or 2-core old PC has been tested; the figures come from one fast PC with stand-ins.

**Linux / Steam Deck (Proton)**
- The build and play steps use Python, not PowerShell, so they can run inside a Wine / Proton prefix.
  See docs/LINUX_STEAM_DECK.md. This has not been validated on a real Steam Deck or Linux PC yet.
  Tell us what happens if you try it.

## How it was checked

- A build from a fresh ISO in a folder with spaces and non-ASCII characters passed.
- Online pairs ran on one PC with two game instances and a simulated network of about 150 ms round trip, 3 % loss:
  ranked set, guest account with both sides, whole-session lockstep. 0 mismatching frames, same result on both sides.
- A pair of physical PCs over the internet was NOT part of this check. Direct IP / VPN between two real PCs
  is the part we most need your reports on.

## Known issues

- **Frame time in fights:** on a quiet PC the median is 16.6 ms, but up to about 10 frames per minute take longer
  than 20 ms. You may see short stutters. Not fixed in this release.
- **Widescreen is not in this release.** The picture is 4:3 content with your chosen internal resolution.
- Intro movie: sound is fixed, but sync with the picture is unmeasured.
- Online still starts a fresh game per match; there is no instant rematch.
- Startup and loading can pause for a moment. Bright dots can show on the beach stage at high resolution.
- Replay recording and playback are not supported.
- Both players need a reachable UDP path and the same build. Details: docs/KNOWN_ISSUES.md.

## Reporting a problem

Tell us your PC (CPU, GPU), Windows version, whether you played direct IP, VPN or the lobby, and what happened.
Keep both players' `logs` folders. Check them for personal details before you share them. Never share your ISO.
