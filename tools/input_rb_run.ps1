# Runs the input worktree build (D:\tekken4-fork-input, out\input; docs\INPUT.md) through tools\run_capture.ps1,
# like docs\rollback\rb_run.ps1 does for the rollback tree. Sound off unless -Env sets it.
#   powershell -File tools\input_rb_run.ps1 -Name chainA -Shots 50,75 -Env "TEKKEN4_RB_MODE=measure;..."
param([string]$Name, [string]$Shots = "40", [string]$Env = "", [string]$BuildDir = "input")
$env:TEKKEN4_SRC = 'D:\tekken4-fork-input'; $env:TEKKEN4_BUILD_DIR = $BuildDir
if (-not $env:TEKKEN4_SOUND) { $env:TEKKEN4_SOUND = '0' }
foreach ($kv in ($Env -split ';')) { if ($kv) { $k, $v = $kv -split '=', 2; Set-Item -Path "env:$k" -Value $v } }
$dir = "D:\tekken4-us\logs\input\$Name"
& powershell -NoProfile -ExecutionPolicy Bypass -File D:\tekken4-us\tools\run_capture.ps1 -RunDir $dir -Shots $Shots
