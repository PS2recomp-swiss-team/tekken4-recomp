@echo off
rem Unattended Ghidra pass over the game ELF: import + auto-analysis (EE plugin), SDK names from the
rem ps2_analyzer seed, then ExportPS2Functions (TOML + CSV) and the function starts list for
rem postprocess_ghidra_export.py --starts. No GhidraMCP needed.
rem Usage: tools\ghidra_headless.cmd <elf> <analyzer_seed.toml> <out_dir>
rem Writes <out_dir>\ghidra_export.toml, ghidra_functions.csv, ghidra_starts.txt, ghidra_headless.log
setlocal
rem (resolved: Ghidra refuses a project path with a ".." element)
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "GHIDRA=%ROOT%\external\ghidra_12.1.4_PUBLIC"
for /d %%J in ("%ROOT%\external\jdk-21*") do set "JAVA_HOME=%%~fJ"
if not defined JAVA_HOME (echo JDK 21 not found in external\ & exit /b 1)
set "PATH=%JAVA_HOME%\bin;%PATH%"
call "%~dp0us_tree.cmd" || exit /b 1
set "PROJECT=%~n1"
call "%GHIDRA%\support\analyzeHeadless.bat" "%ROOT%\ghidra" "%PROJECT%" -import "%~f1" -overwrite ^
  -processor r5900:LE:32:default ^
  -scriptPath "%ROOT%\tools\ghidra_scripts;%TEKKEN4_SRC%\ps2xRecomp\tools\ghidra" ^
  -postScript ApplySdkNames.java "%~f2" ^
  -postScript ExportPS2Functions.java "%~f3\ghidra_export.toml" "%~f3\ghidra_functions.csv" ^
  -postScript DumpFunctionStarts.java "%~f3\ghidra_starts.txt" ^
  -log "%~f3\ghidra_headless.log" -scriptlog "%~f3\ghidra_script.log"
exit /b %errorlevel%
