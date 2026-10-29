@echo off
rem Builds PS2Recomp's ps2EntryRunner (RelWithDebInfo) with MSVC + Ninja. Run tools\stage_generated.cmd first.
rem Output: <tree>\out\runtime\ps2xRuntime\ps2EntryRunner.exe, or out\<TEKKEN4_BUILD_DIR> when that is set
rem (Grok builds in out\grok so its builds and Claude's never overwrite each other; run_capture / run_game follow it).
rem Logs: per-function trace (AGRESSIVE_LOGS) off, it is what slowed the GoW port down; console runtime
rem logs and the IOP RPC trace stay on while we chase boot problems. Changing any of these rebuilds everything.
setlocal
for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR (echo MSVC not found & exit /b 1)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
set "PATH=%ProgramFiles%\CMake\bin;%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
rem Default PS2Recomp tree: the fork clone ..\tekken4-fork-ps2recomp (user, 2026-10-28: the only tree that holds
rem exactly the committed patches; external\PS2Recomp keeps Grok's uncommitted WIP). TEKKEN4_SRC=<tree> overrides it.
call "%~dp0us_tree.cmd" || exit /b 1
set "SRC=%TEKKEN4_SRC%"
if not defined TEKKEN4_BUILD_DIR set "TEKKEN4_BUILD_DIR=runtime"
set "BUILD=%SRC%\out\%TEKKEN4_BUILD_DIR%"
rem A Grok build is CPU-heavy side work: it waits while a timed game / PCSX2 run holds logs\run.lock
rem (docs/ai/collaboration.md, RESOURCES).
if /i "%TEKKEN4_BUILD_DIR:~0,4%"=="grok" powershell -NoProfile -Command "& { . '%~dp0run_lock.ps1'; Wait-RunLockFree '%~dp0..' }"
rem Our runtime patches (patches\*.patch, against the pinned PS2Recomp commit, applied in name order). They stack,
rem so when the last one is already in the tree they all are (an earlier one alone may not reverse any more, its
rem context changed by a later one); otherwise already-applied ones are skipped.
set "PATCHFAIL="
set "LASTPATCH="
for %%P in ("%~dp0..\patches\*.patch") do set "LASTPATCH=%%~fP"
git -C "%SRC%" apply --reverse --check "%LASTPATCH%" >nul 2>&1
if errorlevel 1 for %%P in ("%~dp0..\patches\*.patch") do call :apply "%%~fP"
if defined PATCHFAIL exit /b 1
rem Native VU1 blocks from the micro memories captured in game\vu1\micro (GOW_VU1_CAPTURA, see docs/status.md
rem "Native VU1 port"); none there, or TEKKEN4_VU1N=0, builds the interpreter only.
set "VU1DIR="
for %%D in ("%~dp0..\game\vu1\micro") do set "VU1DIR=%%~fD"
if not exist "%VU1DIR%\*.bin" set "VU1DIR=" & echo WARNING: no game\vu1\micro bin file - building the VU1 INTERPRETER only: the fight runs about 12 fps instead of 27. Restore the captured micro memory, see docs/status.md Native VU1 port.
if "%TEKKEN4_VU1N%"=="0" set "VU1DIR="
if defined VU1DIR set "VU1DIR=%VU1DIR:\=/%"
rem The generator path is passed explicitly: CMake's default (<tree>/../../tools) only fits external\PS2Recomp,
rem a TEKKEN4_SRC tree elsewhere silently built without native blocks (12 fps).
for %%G in ("%~dp0vu1\vu1n_gen.py") do set "VU1GEN=%%~fG"
set "VU1GEN=%VU1GEN:\=/%"
rem /Z7: debug info in each object, no shared mspdbsrv. With several builds at once (Grok tasks + Claude) /Zi
rem failed with C1090 "PDB API call failed" (0x6BA / 23) whenever one build's PDB server went away mid-compile.
rem RelWithDebInfo with full inlining (/Ob2 like Release; CMake's default /Ob1 kept the GS's per-pixel helpers as calls).
cmake -S "%SRC%" -B "%BUILD%" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo ^
  "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=/Z7 /O2 /Ob2 /DNDEBUG" "-DCMAKE_C_FLAGS_RELWITHDEBINFO=/Z7 /O2 /Ob2 /DNDEBUG" ^
  -DPS2X_BUILD_RECOMP=OFF -DPS2X_BUILD_ANALYZER=OFF -DPS2X_BUILD_TEST=OFF -DPS2X_BUILD_STUDIO=OFF ^
  -DPS2X_ENABLE_AGRESSIVE_LOGS=OFF -DPS2X_ENABLE_RUNTIME_LOGS=ON -DPS2X_ENABLE_IOP_RPC_TRACE=ON ^
  "-DPS2X_VU1_MICROCODE_DIR=%VU1DIR%" "-DPS2X_VU1N_GEN=%VU1GEN%"
if errorlevel 1 exit /b 1
cmake --build "%BUILD%" --target ps2EntryRunner
if errorlevel 1 exit /b 1
exit /b 0

rem Applies one patch unless it is already in the tree. If it neither reverses nor applies cleanly, the tree has
rem local edits on top of it (debugging): build what is there, but say so.
:apply
git -C "%SRC%" apply --reverse --check "%~1" >nul 2>&1
if not errorlevel 1 exit /b 0
git -C "%SRC%" apply --check "%~1" >nul 2>&1
if errorlevel 1 (
  echo WARNING: %~nx1 is neither applied nor applicable: building the PS2Recomp tree as it is ^(local edits?^)
  exit /b 0
)
git -C "%SRC%" apply "%~1"
if errorlevel 1 (
  echo patch %~nx1 failed to apply
  set "PATCHFAIL=1"
  exit /b 1
)
echo applied %~nx1
exit /b 0
