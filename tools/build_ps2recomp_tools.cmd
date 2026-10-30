@echo off
rem Builds PS2Recomp's host tools (ps2_recomp, ps2_analyzer) in Release with MSVC + Ninja.
rem Output: <tree>\out\tools (default tree: the fork clone, TEKKEN4_SRC overrides, see build_runtime.cmd)
setlocal
for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR (echo MSVC not found & exit /b 1)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set "PATH=%ProgramFiles%\CMake\bin;%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
if defined TEKKEN4_SRC (set "SRC=%TEKKEN4_SRC%") else set "SRC=%~dp0..\..\tekken4-fork-ps2recomp"
cmake -S "%SRC%" -B "%SRC%\out\tools" -G Ninja -DCMAKE_BUILD_TYPE=Release ^
  -DPS2X_BUILD_RUNTIME=OFF -DPS2X_BUILD_TEST=OFF -DPS2X_BUILD_STUDIO=OFF || exit /b 1
cmake --build "%SRC%\out\tools" || exit /b 1
