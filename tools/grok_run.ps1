param([Parameter(Mandatory = $true)][string]$Task, [string]$RunDir = "", [string[]]$Keys = @(), [string[]]$Shots = @("20"),
      [string[]]$Env = @())
# Grok work tasks: run the game from <tree>\out\grok-<task> as ONE simple command (headless permission checks refuse
# compound lines). -Env takes NAME=VALUE pairs (debug switches such as TEKKEN4_CAMERA_LOG=40). Same output as run_capture.ps1.
# <tree> = external\wt-<task> when tools\grok_tree.ps1 made one (as tools\grok_build.cmd), else the default tree.
#   powershell -File tools\grok_run.ps1 -Task camera-live -RunDir logs\grok\camera-live-1 -Keys "10:Down","12:Cross" -Shots 95 -Env TEKKEN4_CAMERA_LOG=40
$env:TEKKEN4_BUILD_DIR = "grok-$Task"
$taskTree = Join-Path (Split-Path -Parent $PSScriptRoot) "external\wt-$Task"
if (Test-Path (Join-Path $taskTree "ps2xRuntime")) { $env:TEKKEN4_SRC = $taskTree }
foreach ($pair in @($Env | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) {
    $name, $value = $pair -split '=', 2
    Set-Item -Path "env:$name" -Value $value
}
if (-not $RunDir) { $RunDir = Join-Path (Split-Path -Parent $PSScriptRoot) ("logs\grok\{0}-{1}" -f $Task, (Get-Date -Format "HHmmss")) }
& (Join-Path $PSScriptRoot "run_capture.ps1") -RunDir $RunDir -Keys $Keys -Shots $Shots
