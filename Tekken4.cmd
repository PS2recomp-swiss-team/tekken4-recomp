@echo off
setlocal
cd /d "%~dp0"
if exist "python\pythonw.exe" (
  start "" "python\pythonw.exe" -I "launcher\t4_launcher.pyw"
  exit /b 0
)
rem A player release (toolchain\toolchain.json) or a Git checkout needs its private Python.
if exist "toolchain\toolchain.json" goto :missing
if exist ".git" goto :missing
rem Source test zip (tools\test_zip.py): the installed Python 3 with Tk, the tools TEST_ONLINE_DE.txt lists, and
rem the PS2Recomp tree inside this folder (deps\ps2recomp, cloned by the first BUILD GAME).
if not defined TEKKEN4_SRC set "TEKKEN4_SRC=%~dp0deps\ps2recomp"
if not defined TEKKEN4_BUILD_DIR set "TEKKEN4_BUILD_DIR=runtime"
set "T4_PYW="
where /q pyw && pyw -3 -I -c "import tkinter" >nul 2>nul && set "T4_PYW=pyw -3"
if not defined T4_PYW where /q pythonw && pythonw -I -c "import tkinter" >nul 2>nul && set "T4_PYW=pythonw"
if not defined T4_PYW (
  echo Python 3 with tkinter was not found. Install Python 3 from python.org ^(tick tcl/tk and "Add python.exe to PATH"^), then start Tekken4.cmd again.
  pause
  exit /b 1
)
start "" %T4_PYW% -I "launcher\t4_launcher.pyw"
exit /b 0
:missing
echo Private Python is missing. Extract the complete player release zip first.
pause
exit /b 1
