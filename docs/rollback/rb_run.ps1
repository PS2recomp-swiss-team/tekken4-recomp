# usage: rb_run.ps1 <rundir-name> <keys or ""> <shots> then env already set by caller via -Env "A=B;C=D"
param([string]$Name, [string]$Keys = "", [string]$Shots = "40", [string]$Env = "")
$env:TEKKEN4_SRC = 'D:\tekken4-fork-rb'; $env:TEKKEN4_BUILD_DIR = 'rb'
if (-not $env:TEKKEN4_SOUND) { $env:TEKKEN4_SOUND = '0' }
foreach ($kv in ($Env -split ';')) { if ($kv) { $k, $v = $kv -split '=', 2; Set-Item -Path "env:$k" -Value $v } }
$dir = "D:\tekken4-us\logs\rb\$Name"
if ($Keys) { & powershell -NoProfile -File D:\tekken4-us\tools\run_capture.ps1 -RunDir $dir -Shots $Shots -Keys $Keys }
else { & powershell -NoProfile -File D:\tekken4-us\tools\run_capture.ps1 -RunDir $dir -Shots $Shots }
