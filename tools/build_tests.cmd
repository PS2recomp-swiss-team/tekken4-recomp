@echo off
rem Builds and runs PS2Recomp's own test suite (ps2x_tests, with our patches) in <tree>\out\test.
rem Default PS2Recomp tree: the fork clone ..\tekken4-fork-ps2recomp (user, 2026-10-28: the only tree that holds
rem exactly the committed patches; external\PS2Recomp keeps Grok's uncommitted WIP). TEKKEN4_SRC=<tree> overrides it.
rem Runs from the PS2Recomp root: the VU0 macro test reads instructions.h relative to the working directory.
setlocal
for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR (echo MSVC not found & exit /b 1)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set "PATH=%ProgramFiles%\CMake\bin;%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
call "%~dp0us_tree.cmd" || exit /b 1
set "SRC=%TEKKEN4_SRC%"
cmake -S "%SRC%" -B "%SRC%\out\test" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=/Z7 /O2 /Ob1 /DNDEBUG" "-DCMAKE_C_FLAGS_RELWITHDEBINFO=/Z7 /O2 /Ob1 /DNDEBUG" -DPS2X_BUILD_STUDIO=OFF ^
  -DPS2X_ENABLE_AGRESSIVE_LOGS=OFF -DPS2X_ENABLE_RUNTIME_LOGS=OFF -DPS2X_ENABLE_IOP_RPC_TRACE=OFF || exit /b 1
cmake --build "%SRC%\out\test" --target ps2x_tests || exit /b 1
set "TESTEXE="
for /r "%SRC%\out\test" %%e in (ps2x_tests.exe) do if exist "%%e" set "TESTEXE=%%e"
if not defined TESTEXE (echo ps2x_tests.exe not found & exit /b 1)
pushd "%SRC%"
"%TESTEXE%"
set "RC=%errorlevel%"
popd
exit /b %RC%
