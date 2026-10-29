@echo off
rem Resolves the US project's PS2Recomp tree into TEKKEN4_SRC (when not set already) and checks it.
rem The PAL cousin project (branch master) uses ..\tekken4-fork-ps2recomp. Without TEKKEN4_SRC the US tree is
rem ..\tekken4-fork-ps2recomp_usa when it exists, or ..\tekken4-fork-ps2recomp when that one is free or on branch t4-us,
rem else ..\tekken4-fork-ps2recomp_usa (to be cloned by tools\build_game.ps1). An existing tree not on branch t4-us is
rem refused, so a US build never stages, builds or commits into the PAL tree.
rem Use from a script: call "%~dp0us_tree.cmd" || exit /b 1
set "US_TREE_PLAIN=%~dp0..\..\tekken4-fork-ps2recomp"
set "US_TREE_OWN=%~dp0..\..\tekken4-fork-ps2recomp_usa"
if defined TEKKEN4_SRC goto check
if exist "%US_TREE_OWN%" (set "TEKKEN4_SRC=%US_TREE_OWN%" & goto check)
set "TEKKEN4_SRC=%US_TREE_PLAIN%"
if not exist "%US_TREE_PLAIN%\.git" goto check
call :branch "%US_TREE_PLAIN%"
if /i not "%US_TREE_BRANCH%"=="t4-us" set "TEKKEN4_SRC=%US_TREE_OWN%"
:check
if not exist "%TEKKEN4_SRC%\.git" exit /b 0
call :branch "%TEKKEN4_SRC%"
if /i "%US_TREE_BRANCH%"=="t4-us" exit /b 0
echo %TEKKEN4_SRC% is on branch "%US_TREE_BRANCH%", not t4-us: that is not the US PS2Recomp tree (the PAL project's?).
echo Set TEKKEN4_SRC to the US tree, or let tools\build_game.ps1 clone ..\tekken4-fork-ps2recomp_usa.
exit /b 1
:branch
set "US_TREE_BRANCH="
for /f "delims=" %%b in ('git -C "%~1" rev-parse --abbrev-ref HEAD 2^>nul') do set "US_TREE_BRANCH=%%b"
exit /b 0
