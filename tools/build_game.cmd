@echo off
rem One-step PAL build: PS2Recomp host tools -> recompile -> stage -> runtime, each step announced as
rem "[n/4] name - text" (the progress lines OpenRecomp-FGC's Build tab reads; same format as the US build_game.ps1).
rem Every step is incremental, so a second run only redoes what changed. Needs game\disc\SCES_508.78 from your own
rem disc; game\vu1\micro\*.bin for full speed (tools\build_runtime.cmd warns without it). TEKKEN4_SRC = the PS2Recomp
rem tree (default ..\tekken4-fork-ps2recomp, the PAL tree).
setlocal
set "ROOT=%~dp0.."
if defined TEKKEN4_SRC (set "SRC=%TEKKEN4_SRC%") else set "SRC=%ROOT%\..\tekken4-fork-ps2recomp"
if not exist "%ROOT%\game\disc\SCES_508.78" (echo game\disc\SCES_508.78 is missing: copy it from your Tekken 4 PAL disc first & exit /b 1)
if not exist "%SRC%\.git" (echo The PS2Recomp tree %SRC% is missing ^(see docs\status.md^) & exit /b 1)

echo [1/4] tools - PS2Recomp host tools (ps2_recomp.exe)
call "%~dp0build_ps2recomp_tools.cmd"
if errorlevel 1 (echo Step tools failed & exit /b 1)

echo [2/4] recomp - ps2_recomp.exe config\ghidra_export.toml -^> generated\
pushd "%ROOT%"
"%SRC%\out\tools\ps2xRecomp\ps2_recomp.exe" config\ghidra_export.toml
set "RC=%errorlevel%"
popd
if not "%RC%"=="0" (echo Step recomp failed ^(exit %RC%^) & exit /b 1)

echo [3/4] stage - tools\stage_generated.cmd
call "%~dp0stage_generated.cmd"
if errorlevel 1 (echo Step stage failed & exit /b 1)

echo [4/4] runtime - tools\build_runtime.cmd
call "%~dp0build_runtime.cmd"
if errorlevel 1 (echo Step runtime failed & exit /b 1)
echo Build finished.
exit /b 0
