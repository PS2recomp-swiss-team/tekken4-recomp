@echo off
rem Stages generated code + the COMMITTED shared overrides (HEAD of this checkout, so other agents' uncommitted
rem edits stay out) + the rollback override, then builds out\rb.
setlocal
set "ROOT=%~dp0..\.."
if not defined TEKKEN4_SRC set "TEKKEN4_SRC=%ROOT%\..\tekken4-fork-rb"
if not defined TEKKEN4_BUILD_DIR set "TEKKEN4_BUILD_DIR=rb"
call "%ROOT%\tools\stage_generated.cmd"
if errorlevel 1 exit /b 1
set "RUN=%TEKKEN4_SRC%\ps2xRuntime\src\runner"
set "STG=%TEKKEN4_SRC%\out\rbstage"
if not exist "%STG%" mkdir "%STG%"
for %%F in (tekken4_overrides.cpp tekken4_frameshot_overrides.cpp tekken4_profiler_overrides.cpp tekken4_testseed_overrides.cpp) do (
  git -C "%ROOT%" show HEAD:runtime/%%F > "%STG%\%%F"
  fc /b "%STG%\%%F" "%RUN%\%%F" >nul || copy /y "%STG%\%%F" "%RUN%\%%F" >nul
)
rem The rollback driver is a normal runtime\ override since patches 37-40 are in patches\ (stage_generated copies it).
call "%ROOT%\tools\build_runtime.cmd"
exit /b %errorlevel%
