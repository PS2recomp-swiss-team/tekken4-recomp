# Runs the sibling input worktree build (tekken4-fork-input, out\input; docs\INPUT.md) through tools\run_capture.ps1,
# like docs\rollback\rb_run.ps1 does for the rollback tree. Sound off unless -Env sets it.
#   powershell -File tools\input_rb_run.ps1 -Name chainA -Shots 50,75 -Env "TEKKEN4_RB_MODE=measure;..."
param([string]$Name, [string]$Shots = "40", [string]$Env = "", [string]$BuildDir = $env:TEKKEN4_BUILD_DIR, [string]$Src = $env:TEKKEN4_SRC)
$root = Split-Path -Parent $PSScriptRoot
if (-not $Src) { $Src = Join-Path (Split-Path -Parent $root) "tekken4-fork-input" }
if (-not $BuildDir) { $BuildDir = "input" }
$env:TEKKEN4_SRC = $Src; $env:TEKKEN4_BUILD_DIR = $BuildDir
if (-not $env:TEKKEN4_SOUND) { $env:TEKKEN4_SOUND = '0' }
foreach ($kv in ($Env -split ';')) { if ($kv) { $k, $v = $kv -split '=', 2; Set-Item -Path "env:$k" -Value $v } }
$dir = Join-Path $root "logs\input\$Name"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_capture.ps1") -RunDir $dir -Shots $Shots
