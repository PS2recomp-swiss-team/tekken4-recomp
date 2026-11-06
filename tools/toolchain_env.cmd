@echo off
rem Compiler environment for the "no Visual Studio" build (release zip, docs\RELEASE_PLAN_T4.md).
rem Call it from build_*_portable.cmd. Layout it expects, next to tools\ (all of it ships in / is fetched into the zip):
rem   toolchain\toolchain.json         marker + pinned versions
rem   toolchain\llvm\bin\              clang-cl, lld-link, llvm-lib, llvm-rc, llvm-mt, (llvm-profdata)
rem   toolchain\llvm\lib\clang\N\include   clang's own headers
rem   toolchain\cmake\bin\cmake.exe, toolchain\ninja\ninja.exe
rem   toolchain\msvc\include , toolchain\msvc\lib\x64      MSVC STL + CRT (fetched on the player's PC, see the plan)
rem   toolchain\winsdk\include\{ucrt,um,shared}, toolchain\winsdk\lib\{ucrt,um}\x64     Windows SDK (same)
rem   deps\fetch\<name>               vendored FetchContent sources (raylib, imgui, rlimgui, sse2neon), no Git/network
rem Sets: PATH INCLUDE LIB CC CXX T4_TOOLCHAIN_FILE T4_PORTABLE. Exit code 2 = this folder has no toolchain (use Visual Studio).
set "T4_TC=%~dp0..\toolchain"
for %%I in ("%T4_TC%") do set "T4_TC=%%~fI"
if not exist "%T4_TC%\toolchain.json" exit /b 2
for %%F in ("%T4_TC%\llvm\bin\clang-cl.exe" "%T4_TC%\llvm\bin\lld-link.exe" "%T4_TC%\llvm\bin\llvm-lib.exe" "%T4_TC%\llvm\bin\llvm-rc.exe" "%T4_TC%\llvm\bin\llvm-mt.exe" "%T4_TC%\cmake\bin\cmake.exe" "%T4_TC%\ninja\ninja.exe" "%T4_TC%\..\python\python.exe") do (
  if not exist %%F (echo toolchain: missing %%F - extract the whole release zip again & exit /b 1)
)
"%T4_TC%\..\python\python.exe" -I "%~dp0fetch_msvc_sysroot.py" --check --root "%T4_TC%\.."
if errorlevel 1 exit /b 1
rem Microsoft's files live in the PC's shared cache (0.1.3): %LOCALAPPDATA%\OpenRecomp\cache\msvc-<lock>
set "T4_SR="
for /f "usebackq delims=" %%S in (`""%T4_TC%\..\python\python.exe" -I "%~dp0fetch_msvc_sysroot.py" --print-sysroot --root "%T4_TC%\..""`) do set "T4_SR=%%S"
if not defined T4_SR set "T4_SR=%T4_TC%"
set "PATH=%T4_TC%\..\python;%T4_TC%\llvm\bin;%T4_TC%\cmake\bin;%T4_TC%\ninja;%SystemRoot%\System32;%SystemRoot%;%PATH%"
rem The MSVC STL/CRT and the Windows SDK are only needed when the sources include <vector>, <windows.h> ...
set "INCLUDE="
set "LIB="
if exist "%T4_SR%\msvc\include" set "INCLUDE=%T4_SR%\msvc\include;"
if exist "%T4_SR%\msvc\lib\x64" set "LIB=%T4_SR%\msvc\lib\x64;"
if exist "%T4_SR%\winsdk\include\ucrt" set "INCLUDE=%INCLUDE%%T4_SR%\winsdk\include\ucrt;%T4_SR%\winsdk\include\um;%T4_SR%\winsdk\include\shared"
if exist "%T4_SR%\winsdk\include\winrt" set "INCLUDE=%INCLUDE%;%T4_SR%\winsdk\include\winrt"
if exist "%T4_SR%\winsdk\lib\ucrt\x64" set "LIB=%LIB%%T4_SR%\winsdk\lib\ucrt\x64;%T4_SR%\winsdk\lib\um\x64"
set "CC=%T4_TC%\llvm\bin\clang-cl.exe"
set "CXX=%T4_TC%\llvm\bin\clang-cl.exe"
set "T4_TOOLCHAIN_FILE=%~dp0t4_toolchain_clangcl.cmake"
rem clang-cl/lld-link must never look for an installed Visual Studio (its _MSC_VER, headers, libraries).
set "VCToolsInstallDir=%T4_SR%\msvc\"
set "T4_PORTABLE=1"
exit /b 0
