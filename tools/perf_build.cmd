@echo off
rem Perf work build (docs\PERF.md): PS2Recomp worktree D:\tekken4-fork-perf (branch t4-perf), out\perf.
rem Same as tools\build_runtime.cmd but WITHOUT applying patches\*.patch (t4-perf already holds 01-40 as commits plus
rem the perf commits; build_runtime's "apply what does not reverse" check would re-apply additive patches there), and
rem the shared overrides are staged from HEAD of D:\tekken4-us (like docs\rollback\rb_build.cmd), so other
rem agents' uncommitted edits stay out.
rem   tools\perf_build.cmd            stage + build
rem   tools\perf_build.cmd nostage    build only
setlocal
if not defined TEKKEN4_SRC set "TEKKEN4_SRC=D:\tekken4-fork-perf"
if not defined TEKKEN4_BUILD_DIR set "TEKKEN4_BUILD_DIR=perf"
set "SRC=%TEKKEN4_SRC%"
set "BUILD=%SRC%\out\%TEKKEN4_BUILD_DIR%"
if /i "%~1"=="nostage" goto build
call "%~dp0stage_generated.cmd"
if errorlevel 1 exit /b 1
set "RUN=%SRC%\ps2xRuntime\src\runner"
set "STG=%SRC%\out\perfstage"
if not exist "%STG%" mkdir "%STG%"
for %%F in (tekken4_overrides.cpp tekken4_frameshot_overrides.cpp tekken4_profiler_overrides.cpp tekken4_testseed_overrides.cpp tekken4_rollback_overrides.cpp tekken4_net.cpp tekken4_net.h) do (
  git -C "%~dp0.." show HEAD:runtime/%%F > "%STG%\%%F"
  fc /b "%STG%\%%F" "%RUN%\%%F" >nul || copy /y "%STG%\%%F" "%RUN%\%%F" >nul
)
:build
for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR (echo MSVC not found & exit /b 1)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1
set "PATH=%ProgramFiles%\CMake\bin;%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
set "VU1DIR="
for %%D in ("%~dp0..\game\vu1\micro") do set "VU1DIR=%%~fD"
if not exist "%VU1DIR%\*.bin" (echo no game\vu1\micro bin file: refusing to build the interpreter-only perf build & exit /b 1)
set "VU1DIR=%VU1DIR:\=/%"
for %%G in ("%~dp0vu1\vu1n_gen.py") do set "VU1GEN=%%~fG"
set "VU1GEN=%VU1GEN:\=/%"
cmake -S "%SRC%" -B "%BUILD%" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo ^
  "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=/Z7 /O2 /Ob2 /DNDEBUG" "-DCMAKE_C_FLAGS_RELWITHDEBINFO=/Z7 /O2 /Ob2 /DNDEBUG" ^
  -DPS2X_BUILD_RECOMP=OFF -DPS2X_BUILD_ANALYZER=OFF -DPS2X_BUILD_TEST=OFF -DPS2X_BUILD_STUDIO=OFF ^
  -DPS2X_ENABLE_AGRESSIVE_LOGS=OFF -DPS2X_ENABLE_RUNTIME_LOGS=ON -DPS2X_ENABLE_IOP_RPC_TRACE=ON ^
  "-DPS2X_VU1_MICROCODE_DIR=%VU1DIR%" "-DPS2X_VU1N_GEN=%VU1GEN%"
if errorlevel 1 exit /b 1
cmake --build "%BUILD%" --target ps2EntryRunner
if errorlevel 1 exit /b 1
exit /b 0
