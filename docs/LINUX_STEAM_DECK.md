# Tekken 4 on Linux and the Steam Deck (Proton, Wine)

The player build, direct-online preflight and Host/Join paths now use Python, including the release zip's private Windows Python under Wine/Proton. They no longer require PowerShell. A real Wine/Steam Deck build and game session has not been tested here; native Linux compilation is not implemented.

## Building inside a Wine/Proton prefix

Follow [Python player paths](PYTHON_PLAYER_PATHS.md). Use the release zip's Windows Python and bundled compiler, CMake and Ninja in the same prefix as the launcher. Start setup in Desktop mode and build locally from your own US SLUS-20328 ISO. Windows paths passed to the tools must be visible in that prefix.

```text
python\python.exe -I tools/build_game.py -Iso "your US disc.iso" -WhatIf
python\python.exe -I tools/build_game.py -Iso "your US disc.iso"
python\python.exe -I tools/net_play.py -Host -Iso "your US disc.iso" -Port 7400
python\python.exe -I tools/net_play.py -Join <host-IPv4> -Iso "your US disc.iso" -Port 7400
```

Launch the Windows interpreter through your chosen Wine/Proton environment. The repository's launcher selects its console Python automatically. Microsoft compiler/sysroot installation still requires its normal license acceptance; the fetcher's Windows MSI API and expand.exe support under Wine remains unverified. Do not treat passing mocked launcher tests as a real Deck validation.

## PowerShell tools that remain

The old build/net-play .ps1 entry points are compatibility wrappers around Python. Installing PowerShell in the prefix is no longer a prerequisite for the player workflow. Some maintainer tools, including `collect_test_logs.ps1`, remain PowerShell scripts; collect the run folders manually if those tools are unavailable.

The earlier Wine warning about nonfunctional powershell.exe described the previous player pipeline. It remains relevant to older launcher releases and unchanged maintainer scripts. External OpenRecomp launcher adapters must use a matching Python-capable player workflow; this integration changes only this repository.

## Playing and direct online

The game is a Windows program: raylib/GLFW and OpenGL for graphics, miniaudio/WASAPI for sound, XInput/raylib gamepads for controls and Winsock for netplay. The following are expectations from the code, not measured Linux results.

| Part | Expected under Wine / Proton |
|---|---|
| Picture | Wine passes OpenGL through WGL to the Linux driver; no DXVK/vkd3d path is required |
| Sound | WASAPI through Wine's audio backend |
| Pads | Steam Input can expose the Deck controls as an Xbox controller |
| Rollback snapshots | Wine emulates GetWriteWatch; its cost needs measurement |
| Direct online | Python performs build/ISO/compiler preflight, then launches the Windows game; real Wine validation remains pending |

Builds contain game data derived from your own disc and stay local. Both offline play and direct online need real validation in the intended prefix.

## Test checklist

1. Record Linux/SteamOS, Proton/Wine version and GPU.
2. Start the launcher in Desktop mode and run the Python dry build. Retain its log; a PowerShell refusal is not the expected new-player path.
3. Build from your own ISO and record compiler/sysroot setup and any failure.
4. Check offline picture, sound, controls and frame pacing.
5. Run the direct-online preflight and correctness tests on an authorized local/VPN peer, retaining both run folders.

Collect `logs/` and, if needed, a Proton log. Check logs for personal paths before sharing them.
