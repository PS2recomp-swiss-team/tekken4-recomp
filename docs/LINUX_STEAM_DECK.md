# Tekken 4 on Linux and the Steam Deck (Proton, Wine)

Short answer: **building Tekken 4 does not work under Wine or Proton today**, so Linux players cannot make the game
there. Playing a build might work. **Nothing of this was tried**: we have no Linux PC and no Steam Deck; it comes
from reading the code.

## Why the build does not work

The build (`tools\build_game.ps1`, portable: `tools\build_game_portable.ps1`), the online helper
(`tools\net_play.ps1`), the online check before a direct match and the log collection
(`tools\collect_test_logs.ps1`) are **PowerShell** scripts. Windows always has PowerShell. Wine and Proton ship only
a stand-in `powershell.exe` that does not run scripts. The launcher (T4's own `launcher\t4_launcher.pyw` and
OpenRecomp-FGC) therefore asks PowerShell once under Wine whether it answers, and if not it says so instead of
starting the script:

> This PC runs the launcher under Wine or Proton (Linux, Steam Deck). Tekken 4's build and online helper are
> PowerShell scripts, and Wine/Proton have no working PowerShell. ...

On Windows nothing is asked and nothing changed.

What would be needed for a Linux build (not done): the build steps written in Python instead of PowerShell (the
heavy parts are already plain programs: `iso_extract.py`, `ps2_recomp.exe`, CMake + Ninja + the bundled clang-cl and
lld-link, which are ordinary 64-bit Windows programs), and the Microsoft sysroot fetch (`tools\fetch_msvc_sysroot.py`
uses Windows' MSI database API and `expand.exe`; Wine has both, untested).

A player could try to install **PowerShell 7** into the prefix (for example `protontricks <id> powershell`, or the
PowerShell 7 MSI). The launcher then finds a PowerShell that answers and runs the scripts. Whether the scripts work
under PowerShell 7 in Wine is unknown. **(untested)**

## Playing (when a build exists)

The game itself is a plain Windows program: raylib (GLFW + **OpenGL**) for the window and picture, miniaudio
(WASAPI) for sound, XInput and raylib's gamepads for controllers, Winsock for netplay. Under Wine all of these exist:

| Part | Under Wine / Proton |
|---|---|
| Picture (OpenGL through WGL) | Wine passes OpenGL to the Linux driver: should work, no DXVK/vkd3d needed |
| Sound (miniaudio, WASAPI) | Wine's winepulse (PipeWire/PulseAudio) |
| Pads | Steam Input: an Xbox pad (the Deck's controls too) |
| Rollback snapshots (GetWriteWatch) | Wine emulates write watches with page faults: more CPU per online frame |
| Thread priorities, timer resolution | mostly ignored / fine |
| Direct online (Host/Join) | the PowerShell check before the match cannot run: refused with the message above |

A build is game data from your own disc and stays on your PC; copying one built under Windows on the same PC (dual
boot) to Linux is the only way to test playing today, and it is untested.

## Test checklist (for a player who tries)

| # | Step | Expected |
|---|---|---|
| 0 | Note: Linux / SteamOS version, Proton build, GPU | |
| 1 | Start the launcher (or OpenRecomp-FGC) through Steam with Proton | the window opens |
| 2 | Build | the PowerShell message, not a silent nothing |
| 3 | (only with PowerShell 7 installed) Build | how far it gets; send `logs\build_game.log` |
| 4 | (only with a build) Play offline | picture, sound, pad, fps |

Send the launcher's log folder (`logs\`) and, if asked, the Proton log (launch options `PROTON_LOG=1 %command%`,
file `~/steam-<number>.log`; it has your Linux user name in it: check before posting).
