@echo off
rem Builds PS2Recomp's host tools (ps2_recomp, ps2_analyzer) in Release with MSVC + Ninja.
rem Output: <tree>\out\tools (default tree: the fork clone, TEKKEN4_SRC overrides, see build_runtime.cmd)
setlocal
rem PORTABLE COPY of build_ps2recomp_tools.cmd: when <root>\toolchain\toolchain.json exists (release zip) the bundled clang-cl/lld-link/
rem CMake/Ninja are used (tools\toolchain_env.cmd); otherwise it is the same Visual Studio build as the original.
set "T4_PORTABLE="
call "%~dp0toolchain_env.cmd"
if errorlevel 2 (
  for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
  if not defined VSDIR (echo MSVC not found, and this folder has no toolchain\ & exit /b 1)
  call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul
) else if errorlevel 1 (
  exit /b 1
)
set "PATH=%ProgramFiles%\CMake\bin;%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
if defined TEKKEN4_SRC (set "SRC=%TEKKEN4_SRC%") else set "SRC=%~dp0..\..\tekken4-fork-ps2recomp"
set "TCARG="
if defined T4_PORTABLE set "TCARG=-DCMAKE_TOOLCHAIN_FILE=%T4_TOOLCHAIN_FILE%"
cmake -S "%SRC%" -B "%SRC%\out\tools" -G Ninja %TCARG% -DCMAKE_BUILD_TYPE=Release ^
  -DPS2X_BUILD_RUNTIME=OFF -DPS2X_BUILD_TEST=OFF -DPS2X_BUILD_STUDIO=OFF || exit /b 1
cmake --build "%SRC%\out\tools" || exit /b 1
