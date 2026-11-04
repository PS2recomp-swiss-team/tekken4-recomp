@echo off
rem US tree compatibility API: Python owns the rule; no PowerShell required.
set "US_TREE_PY=python"
set "US_TREE_PRE="
if defined T4_PYTHON set "US_TREE_PY=%T4_PYTHON%"
if exist "%~dp0..\python\python.exe" set "US_TREE_PY=%~dp0..\python\python.exe"
"%US_TREE_PY%" -c "import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)" >nul 2>nul
if errorlevel 1 (
  set "US_TREE_PY=py"
  set "US_TREE_PRE=-3"
)
set "US_TREE_RESULT="
rem Only an ASCII choice crosses the pipe; cmd must retain Unicode paths itself.
for /f "usebackq delims=" %%T in (`""%US_TREE_PY%" %US_TREE_PRE% -I "%~dp0us_tree.py" -Root "%~dp0.." --cmd-choice"`) do set "US_TREE_RESULT=%%T"
if not defined US_TREE_RESULT exit /b 1
if "%US_TREE_RESULT%"=="plain" for %%I in ("%~dp0..\..\tekken4-fork-ps2recomp") do set "TEKKEN4_SRC=%%~fI"
if "%US_TREE_RESULT%"=="own" for %%I in ("%~dp0..\..\tekken4-fork-ps2recomp_usa") do set "TEKKEN4_SRC=%%~fI"
if "%US_TREE_RESULT%"=="environment" for %%I in ("%TEKKEN4_SRC%") do set "TEKKEN4_SRC=%%~fI"
exit /b 0
