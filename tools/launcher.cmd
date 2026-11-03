@echo off
rem Starts OpenRecomp-FGC (TheWishin's couch launcher, github.com/TheWishin/OpenRecomp-FGC, cloned to
rem ..\..\OpenRecomp-FGC or %OPENRECOMP_FGC%) with both cousin projects on its shelf:
rem   tools\openrecomp\t4.json    US  (H:\tekken4-recomp_usa: its launcher\t4core.py does Play / Build / Settings)
rem   tools\openrecomp\t4pal.json PAL (starts tools\run_game.cmd with the PAL tree pinned; F2 in the game = settings)
rem The manifests are copied into the launcher's user folder (%LOCALAPPDATA%\OpenRecomp\games; the same id replaces
rem its built-in t4.json). Nothing in the OpenRecomp-FGC folder is changed. Add --windowed for a window.
setlocal
set "FGC=%OPENRECOMP_FGC%"
if not defined FGC set "FGC=%~dp0..\..\OpenRecomp-FGC"
if not exist "%FGC%\run.cmd" (echo OpenRecomp-FGC is not in %FGC%: git clone https://github.com/TheWishin/OpenRecomp-FGC there & exit /b 1)
set "GAMES=%LOCALAPPDATA%\OpenRecomp\games"
if not exist "%GAMES%" mkdir "%GAMES%"
copy /y "%~dp0openrecomp\t4.json" "%GAMES%\t4.json" >nul || exit /b 1
copy /y "%~dp0openrecomp\t4pal.json" "%GAMES%\t4pal.json" >nul || exit /b 1
rem Each game finds its own PS2Recomp tree (US: t4core.py's rule, PAL: pinned in t4pal.json): no stray tree from here.
set "TEKKEN4_SRC="
call "%FGC%\run.cmd" %*
