@echo off
rem Builds and runs ps2xIOP's own tests (ps2_iop_emulator_tests, ps2_iop_import_tests, ps2_iop_compatibility_tests).
rem tools\build_tests.cmd only builds ps2x_tests; these sit behind PS2X_IOP_BUILD_TESTS=OFF, so nothing ran them before.
rem Configures the ps2xIOP subproject alone in <tree>\out\iop-test. TEKKEN4_SRC=<PS2Recomp tree> tests another checkout.
setlocal
for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR (echo MSVC not found & exit /b 1)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set "PATH=%ProgramFiles%\CMake\bin;%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
call "%~dp0us_tree.cmd" || exit /b 1
set "SRC=%TEKKEN4_SRC%"
set "BUILD=%SRC%\out\iop-test"
cmake -S "%SRC%\ps2xIOP" -B "%BUILD%" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=/Z7 /O2 /Ob1 /DNDEBUG" -DPS2X_IOP_BUILD_TESTS=ON || exit /b 1
cmake --build "%BUILD%" --target ps2_iop_emulator_tests ps2_iop_import_tests ps2_iop_compatibility_tests || exit /b 1
set "RC=0"
pushd "%SRC%"
for %%T in (ps2_iop_emulator_tests ps2_iop_import_tests ps2_iop_compatibility_tests) do call :run %%T
popd
echo IOP tests exit code %RC%
exit /b %RC%

:run
echo === %1
"%BUILD%\%1.exe"
if errorlevel 1 (echo FAILED: %1 & set "RC=1")
exit /b 0
