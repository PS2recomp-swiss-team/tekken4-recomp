@echo off
rem Rollback phase 3 (netplay) build: PS2Recomp worktree D:\tekken4-fork-net (branch t4-net), output out\net.
rem Stages the generated code, the COMMITTED shared overrides (HEAD of D:\tekken4-us, so other agents'
rem uncommitted edits stay out) and the working copy of the rollback/netplay driver and the netplay transport,
rem then builds with tools\build_runtime.cmd.
setlocal
set TEKKEN4_SRC=D:\tekken4-fork-net
set TEKKEN4_BUILD_DIR=net
call D:\tekken4-us\tools\stage_generated.cmd
if errorlevel 1 exit /b 1
set "RUN=D:\tekken4-fork-net\ps2xRuntime\src\runner"
set "STG=D:\tekken4-fork-net\out\netstage"
if not exist "%STG%" mkdir "%STG%"
for %%F in (tekken4_overrides.cpp tekken4_frameshot_overrides.cpp tekken4_profiler_overrides.cpp tekken4_testseed_overrides.cpp) do (
  git -C D:\tekken4-us show HEAD:runtime/%%F > "%STG%\%%F"
  fc /b "%STG%\%%F" "%RUN%\%%F" >nul || copy /y "%STG%\%%F" "%RUN%\%%F" >nul
)
for %%F in (D:\tekken4-us\runtime\tekken4_rollback_overrides.cpp D:\tekken4-us\runtime\tekken4_net*.cpp D:\tekken4-us\runtime\tekken4_net*.h) do (
  fc /b "%%F" "%RUN%\%%~nxF" >nul 2>&1 || copy /y "%%F" "%RUN%\%%~nxF" >nul
)
call D:\tekken4-us\tools\build_runtime.cmd
if errorlevel 1 exit /b 1
rem The build id both peers must share (TEKKEN4_NET_BUILD; tools\net_pair.ps1 reads it from here).
python -I D:\tekken4-us\tools\t4_buildid.py --src D:\tekken4-fork-net --out D:\tekken4-fork-net\out\net\ps2xRuntime
