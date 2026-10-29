@echo off
rem Copies the recompiled game code from generated\ into PS2Recomp's runtime, where ps2EntryRunner's
rem CMake picks it up (*.cpp -> ps2xRuntime\src\runner, generated headers -> ps2xRuntime\include).
rem Rerun after every ps2_recomp run. Unchanged files keep their timestamps, so Ninja skips them.
rem This overwrites upstream's placeholder src\runner\register_functions.cpp (git checkout restores it).
rem Our game overrides (runtime\*_overrides.cpp) are copied in too; /XF keeps the mirror from deleting them.
setlocal
set "GEN=%~dp0..\generated"
call "%~dp0us_tree.cmd" || exit /b 1
set "RT=%TEKKEN4_SRC%\ps2xRuntime"
if not exist "%GEN%\register_functions.cpp" (echo generated\ is empty: run ps2_recomp first & exit /b 1)
rem /E copies only and never purges (no tool in this project deletes: user rule 2026-10-27); stale files stay until the user removes them.
robocopy "%GEN%" "%RT%\src\runner" *.cpp /E /XF *_overrides.cpp /NJH /NJS /NFL /NDL /NP
if errorlevel 8 (echo copying .cpp files failed & exit /b 1)
robocopy "%~dp0..\runtime" "%RT%\src\runner" *_overrides.cpp /NJH /NJS /NFL /NDL /NP
if errorlevel 8 (echo copying overrides failed & exit /b 1)
robocopy "%GEN%" "%RT%\include" ps2_recompiled_functions.h ps2_recompiled_stubs.h /NJH /NJS /NFL /NDL /NP
if errorlevel 8 (echo copying headers failed & exit /b 1)
exit /b 0
