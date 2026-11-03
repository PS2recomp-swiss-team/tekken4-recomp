@echo off
setlocal
cd /d "%~dp0"
if not exist "python\pythonw.exe" (
  echo Private Python is missing. Extract the complete player release zip first.
  pause
  exit /b 1
)
start "" "python\pythonw.exe" -I "launcher\t4_launcher.pyw"
