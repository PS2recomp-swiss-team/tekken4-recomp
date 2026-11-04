@echo off
rem Copies the recompiled game code from generated\ into PS2Recomp's runtime, where ps2EntryRunner's
rem CMake picks it up (*.cpp -> ps2xRuntime\src\runner, generated headers -> ps2xRuntime\include).
rem Rerun after every ps2_recomp run. Unchanged files keep their timestamps, so Ninja skips them.
rem This overwrites upstream's placeholder src\runner\register_functions.cpp (git checkout restores it).
rem Our game overrides (runtime\*_overrides.cpp) are copied in too; /XF keeps the mirror from deleting them.
setlocal
set "GEN=%~dp0..\generated"
rem A release bundle (toolchain\toolchain.json) carries its own tree; a checkout finds it through tools\us_tree.cmd.
if exist "%~dp0..\toolchain\toolchain.json" (set "RT=%~dp0..\deps\ps2recomp\ps2xRuntime" & goto :tree_found)
call "%~dp0us_tree.cmd" || exit /b 1
set "RT=%TEKKEN4_SRC%\ps2xRuntime"
:tree_found
if not exist "%GEN%\register_functions.cpp" (echo generated\ is empty: run ps2_recomp first & exit /b 1)
rem /E copies only and never purges (no tool in this project deletes: user rule 2026-10-27); stale files stay until the user removes them.
robocopy "%GEN%" "%RT%\src\runner" *.cpp /E /XF *_overrides.cpp /NJH /NJS /NFL /NDL /NP
if errorlevel 8 (echo copying .cpp files failed & exit /b 1)
robocopy "%~dp0..\runtime" "%RT%\src\runner" *_overrides.cpp /NJH /NJS /NFL /NDL /NP
if errorlevel 8 (echo copying overrides failed & exit /b 1)
rem The rollback netplay transport (runtime\tekken4_net.cpp/.h): CMake compiles src\runner\*_net*.cpp and links
rem ws2_32 when it is there; without it TEKKEN4_NETPLAY is off and TEKKEN4_NET is refused.
robocopy "%~dp0..\runtime" "%RT%\src\runner" tekken4_net*.cpp tekken4_net*.h /NJH /NJS /NFL /NDL /NP
if errorlevel 8 (echo copying the netplay transport failed & exit /b 1)
rem robocopy exit 1 = the transport was copied in now. The rollback overrides test __has_include("tekken4_net.h") inside
rem a unity batch whose dependency list never had that header: touch them so Ninja recompiles them with netplay on.
if errorlevel 1 powershell -NoProfile -Command "(Get-Item -LiteralPath '%RT%\src\runner\tekken4_rollback_overrides.cpp').LastWriteTime = Get-Date"
rem Header-only opt-in state discovery, match state and online result reporting (included by the rollback overrides),
rem and native online names / rank badges (tekken4_hud_overrides.cpp; badge art by OpenRecomp-FGC tools\make_rank_badges.py).
robocopy "%~dp0..\runtime" "%RT%\src\runner" tekken4_state_probe.h tekken4_online_result.h tekken4_match_state.h tekken4_rank_badges.h tekken4_badge_draw.h tekken4_rank_cache.h tekken4_rank_label.h tekken4_native_names.h tekken4_rounds.h /NJH /NJS /NFL /NDL /NP
if errorlevel 8 (echo copying the state probe and result headers failed & exit /b 1)
rem Touch the including translation unit when either header is first staged or changed (including unity builds).
if errorlevel 1 powershell -NoProfile -Command "(Get-Item -LiteralPath '%RT%\src\runner\tekken4_rollback_overrides.cpp').LastWriteTime = Get-Date"
robocopy "%GEN%" "%RT%\include" ps2_recompiled_functions.h ps2_recompiled_stubs.h /NJH /NJS /NFL /NDL /NP
if errorlevel 8 (echo copying headers failed & exit /b 1)
exit /b 0
