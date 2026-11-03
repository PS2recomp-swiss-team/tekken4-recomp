@echo off
rem Rollback phase 3 (netplay) build: sibling worktree tekken4-fork-net (branch t4-net), output out\net.
rem TEKKEN4_SRC and TEKKEN4_BUILD_DIR override the worktree and output subdirectory, like tools\build_runtime.cmd.
rem Stages the generated code, the COMMITTED shared overrides (HEAD of this project, so other agents'
rem uncommitted edits stay out) and the working copy of the rollback/netplay driver and the netplay transport,
rem then builds with tools\build_runtime.cmd.
setlocal
for %%D in ("%~dp0..\..") do set "ROOT=%%~fD"
if not defined TEKKEN4_SRC set "TEKKEN4_SRC=%ROOT%\..\tekken4-fork-net"
if not defined TEKKEN4_BUILD_DIR set "TEKKEN4_BUILD_DIR=net"
call "%ROOT%\tools\stage_generated.cmd"
if errorlevel 1 exit /b 1
set "RUN=%TEKKEN4_SRC%\ps2xRuntime\src\runner"
set "STG=%TEKKEN4_SRC%\out\netstage"
if not exist "%STG%" mkdir "%STG%"
for %%F in (tekken4_overrides.cpp tekken4_frameshot_overrides.cpp tekken4_profiler_overrides.cpp tekken4_testseed_overrides.cpp) do (
  git -C "%ROOT%" show HEAD:runtime/%%F > "%STG%\%%F"
  fc /b "%STG%\%%F" "%RUN%\%%F" >nul || copy /y "%STG%\%%F" "%RUN%\%%F" >nul
)
for %%F in ("%ROOT%\runtime\tekken4_rollback_overrides.cpp" "%ROOT%\runtime\tekken4_net*.cpp" "%ROOT%\runtime\tekken4_net*.h") do (
  fc /b "%%~fF" "%RUN%\%%~nxF" >nul 2>&1 || copy /y "%%~fF" "%RUN%\%%~nxF" >nul
)
call "%ROOT%\tools\build_runtime.cmd"
if errorlevel 1 exit /b 1
rem The build id both peers must share (TEKKEN4_NET_BUILD; tools\net_pair.ps1 reads it from here).
python -I "%ROOT%\tools\t4_buildid.py" --src "%TEKKEN4_SRC%" --out "%TEKKEN4_SRC%\out\%TEKKEN4_BUILD_DIR%\ps2xRuntime"
