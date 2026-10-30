# Rollback self-test / measure runs with the sibling tekken4-fork-perf build, out\perf.
# usage: perf_rb_run.ps1 -Name <run dir under logs\perf\rb> [-Keys ""] [-Shots 40] -Env "A=B;C=D"
param([string]$Name, [string]$Keys = "", [string]$Shots = "40", [string]$Env = "",
      [string]$Src = $env:TEKKEN4_SRC, [string]$Build = $env:TEKKEN4_BUILD_DIR)
$root = Split-Path -Parent $PSScriptRoot
if (-not $Src) { $Src = Join-Path (Split-Path -Parent $root) "tekken4-fork-perf" }
if (-not $Build) { $Build = 'perf' }
$env:TEKKEN4_SRC = $Src; $env:TEKKEN4_BUILD_DIR = $Build
if (-not $env:TEKKEN4_SOUND) { $env:TEKKEN4_SOUND = '0' }
foreach ($kv in ($Env -split ';')) { if ($kv) { $k, $v = $kv -split '=', 2; Set-Item -Path "env:$k" -Value $v } }
$dir = Join-Path $root "logs\perf\rb\$Name"
if ($Keys) { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_capture.ps1") -RunDir $dir -Shots $Shots -Keys $Keys }
else { & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_capture.ps1") -RunDir $dir -Shots $Shots }
