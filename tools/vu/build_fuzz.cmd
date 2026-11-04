@echo off
rem Builds tools\vu\vulift_fuzz.exe (offline interpreter-vs-lifted check) into %1 (default repo build\vulift-fuzz) from the
rem PS2Recomp tree in TEKKEN4_SRC and the generated parts in %2 (vulift_part*.cpp of a vu_lift.py run).
setlocal
set "OUT=%~1"
if "%OUT%"=="" set "OUT=%~dp0..\..\build\vulift-fuzz"
set "GEN=%~2"
if not defined TEKKEN4_SRC set "TEKKEN4_SRC=%~dp0..\..\deps\ps2recomp"
set "RT=%TEKKEN4_SRC%\ps2xRuntime"
for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR (echo MSVC not found & exit /b 1)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
if errorlevel 1 exit /b 1
if not exist "%OUT%" mkdir "%OUT%"
cd /d "%OUT%"
set "FLAGS=/nologo /std:c++20 /O2 /Ob2 /EHsc /fp:fast /MP /W0 /DNDEBUG /I "%RT%\include" /I "%RT%\src\lib""
cl %FLAGS% /c "%RT%\src\lib\vu\ps2_vu1_core.cpp" "%RT%\src\lib\vu\ps2_vu1_upper.cpp" "%RT%\src\lib\vu\ps2_vu1_lower.cpp" "%RT%\src\lib\vu\ps2_vu_lift.cpp" "%~dp0vulift_fuzz.cpp" "%~dp0vulift_fuzz_stubs.cpp" "%GEN%\vulift_part0.cpp" "%GEN%\vulift_part1.cpp" "%GEN%\vulift_part2.cpp" "%GEN%\vulift_part3.cpp" || exit /b 1
link /nologo /OUT:vulift_fuzz.exe *.obj || exit /b 1
exit /b 0
