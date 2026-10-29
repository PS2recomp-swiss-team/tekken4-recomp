@echo off
rem Runs the recompiled game (build it first with tools\build_runtime.cmd). cdrom0: maps to game\disc\.
rem Close the game window to stop it; the console output is then complete in logs\run.log.
rem The line to look at is usually the last "[guest-branch:...]" or crash line near the end.
setlocal
set "ROOT=%~dp0.."
if not defined TEKKEN4_BUILD_DIR set "TEKKEN4_BUILD_DIR=runtime"
call "%~dp0us_tree.cmd" || exit /b 1
set "TREE=%TEKKEN4_SRC%"
set "EXE=%TREE%\out\%TEKKEN4_BUILD_DIR%\ps2xRuntime\ps2EntryRunner.exe"
if not exist "%EXE%" (echo ps2EntryRunner.exe not built: run tools\build_runtime.cmd & exit /b 1)
if not exist "%ROOT%\logs" mkdir "%ROOT%\logs"
rem GPU (OpenGL) GS renderer by default since 2026-10-28 (fight at 60 fps); set PS2X_GS_BACKEND=cpu for the software one.
if not defined PS2X_GS_BACKEND set "PS2X_GS_BACKEND=gl"
rem The software renderer draws on several threads; set PS2X_GS_THREADS=0 to draw on one.
if not defined PS2X_GS_THREADS set "PS2X_GS_THREADS=auto"
rem Real game sound by default since 2026-10-28 (user's choice; experimental: some crackling, ~20 s of silence at
rem character select; needs the game ISO in the project root or TEKKEN4_ISO). Set TEKKEN4_SOUND=0 for the silent stand-in.
if not defined TEKKEN4_SOUND set "TEKKEN4_SOUND=1"
rem The window title says whose game it is (Grok/Claude test runs title theirs): TEKKEN4_WINDOW_TITLE overrides it.
if not defined TEKKEN4_WINDOW_TITLE set "TEKKEN4_WINDOW_TITLE=TEKKEN 4 - YOUR GAME"
start "" /b powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0set_window_title.ps1" -Title "%TEKKEN4_WINDOW_TITLE%"
"%EXE%" "%ROOT%\game\disc\SLUS_203.28" > "%ROOT%\logs\run.log" 2>&1
echo exit code %errorlevel%, log in logs\run.log
