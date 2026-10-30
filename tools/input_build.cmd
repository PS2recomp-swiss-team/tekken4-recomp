@echo off
rem Gamepad/input-latency work (docs\INPUT.md): stages generated code + the COMMITTED runtime overrides
rem (HEAD of D:\tekken4-us, so other agents' uncommitted edits stay out, like docs\rollback\rb_build.cmd)
rem into the input worktree D:\tekken4-fork-input (branch t4-input) and builds out\input there.
rem Waits while C:\T5DROnline\build\int115\HEAVY.lock exists (poll 60 s, max 30 min).
setlocal
set /a WAITED=0
:waitlock
if not exist "C:\T5DROnline\build\int115\HEAVY.lock" goto go
if %WAITED% GEQ 1800 (echo HEAVY.lock still there after 30 min, not building & exit /b 1)
echo HEAVY.lock present, waiting 60 s
timeout /t 60 /nobreak >nul
set /a WAITED+=60
goto waitlock
:go
if not defined TEKKEN4_SRC set "TEKKEN4_SRC=D:\tekken4-fork-input"
if not defined TEKKEN4_BUILD_DIR set "TEKKEN4_BUILD_DIR=input"
set "GEN=%~dp0..\generated"
set "RT=%TEKKEN4_SRC%\ps2xRuntime"
robocopy "%GEN%" "%RT%\src\runner" *.cpp /E /XF *_overrides.cpp /NJH /NJS /NFL /NDL /NP
if errorlevel 8 (echo copying .cpp files failed & exit /b 1)
robocopy "%GEN%" "%RT%\include" ps2_recompiled_functions.h ps2_recompiled_stubs.h /NJH /NJS /NFL /NDL /NP
if errorlevel 8 (echo copying headers failed & exit /b 1)
set "STG=%TEKKEN4_SRC%\out\inputstage"
if not exist "%STG%" mkdir "%STG%"
for %%F in (tekken4_overrides.cpp tekken4_frameshot_overrides.cpp tekken4_profiler_overrides.cpp tekken4_testseed_overrides.cpp tekken4_rollback_overrides.cpp) do (
  git -C "%~dp0.." show HEAD:runtime/%%F > "%STG%\%%F"
  fc /b "%STG%\%%F" "%RT%\src\runner\%%F" >nul 2>&1 || copy /y "%STG%\%%F" "%RT%\src\runner\%%F" >nul
)
rem Untracked overrides another agent staged in here earlier would be compiled too: they are moved out by hand
rem (tools\to_clean.ps1), never deleted.
call "%~dp0build_runtime.cmd"
exit /b %errorlevel%
