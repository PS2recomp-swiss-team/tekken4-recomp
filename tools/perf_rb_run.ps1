# Rollback self-test / measure runs with the perf build (copy of docs\rollback\rb_run.ps1 for D:\tekken4-fork-perf, out\perf).
# usage: perf_rb_run.ps1 -Name <run dir under logs\perf\rb> [-Keys ""] [-Shots 40] -Env "A=B;C=D"
param([string]$Name, [string]$Keys = "", [string]$Shots = "40", [string]$Env = "",
      [string]$Src = 'D:\tekken4-fork-perf', [string]$Build = 'perf')
$env:TEKKEN4_SRC = $Src; $env:TEKKEN4_BUILD_DIR = $Build
if (-not $env:TEKKEN4_SOUND) { $env:TEKKEN4_SOUND = '0' }
foreach ($kv in ($Env -split ';')) { if ($kv) { $k, $v = $kv -split '=', 2; Set-Item -Path "env:$k" -Value $v } }
$dir = "D:\tekken4-us\logs\perf\rb\$Name"
if ($Keys) { & powershell -NoProfile -ExecutionPolicy Bypass -File D:\tekken4-us\tools\run_capture.ps1 -RunDir $dir -Shots $Shots -Keys $Keys }
else { & powershell -NoProfile -ExecutionPolicy Bypass -File D:\tekken4-us\tools\run_capture.ps1 -RunDir $dir -Shots $Shots }
