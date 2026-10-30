@echo off
rem Decompiles/xrefs functions of the US ELF in the existing Ghidra project (headless, read-only, no analysis).
rem Usage: tools\ghidra_decomp.cmd <out.txt> <0xaddr | x:0xaddr | c:0xaddr> ...   (see tools\ghidra_scripts\DecompileFuncs.java)
setlocal
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "GHIDRA=%ROOT%\external\ghidra_12.1.4_PUBLIC"
for /d %%J in ("%ROOT%\external\jdk-21*") do set "JAVA_HOME=%%~fJ"
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "OUT=%~1"
shift
call "%GHIDRA%\support\analyzeHeadless.bat" "%ROOT%\ghidra" SLUS_203 -process SLUS_203.28 -noanalysis -readOnly ^
  -scriptPath "%ROOT%\tools\ghidra_scripts" -postScript DecompileFuncs.java "%OUT%" %1 %2 %3 %4 %5 %6 %7 %8 %9
exit /b %errorlevel%
