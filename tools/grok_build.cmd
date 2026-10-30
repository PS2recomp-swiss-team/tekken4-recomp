@echo off
rem Grok work tasks: stage + build into <tree>\out\grok-<task> as ONE simple command (headless permission
rem checks refuse compound lines like "$env:X=...; cmd ..."). Waits for logs\run.lock like build_runtime.cmd.
rem <tree> = the task's own tree external\wt-<task> when tools\grok_tree.ps1 made one, else the default tree.
rem   cmd /c tools\grok_build.cmd <task>
if "%~1"=="" (echo usage: grok_build.cmd ^<task^> & exit /b 1)
setlocal
set "TEKKEN4_BUILD_DIR=grok-%~1"
if exist "%~dp0..\external\wt-%~1\ps2xRuntime" set "TEKKEN4_SRC=%~dp0..\external\wt-%~1"
call "%~dp0stage_generated.cmd" || exit /b 1
call "%~dp0build_runtime.cmd"
