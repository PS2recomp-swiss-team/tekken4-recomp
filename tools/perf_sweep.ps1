param([string]$Label = "base", [string[]]$Stages = @(), [double]$Fight = 32, [string[]]$Env = @(),
      [string]$Build = "perf", [string]$Src = "D:\tekken4-fork-perf")
# Stage sweep (docs\PERF.md): tools\perf_fight.ps1 for every stage (or -Stages a,b), runs in logs\perf\<Label>_<stage>,
# then the table of tools\perf_table.py into logs\perf\<Label>_table.md.
#   powershell -ExecutionPolicy Bypass -File tools\perf_sweep.ps1 -Label base1
# Never pipe this script's output through Select-Object -First: the stopped pipe blocks run_capture and the game
# window is never closed.
$root = Split-Path -Parent $PSScriptRoot
$all = @("airport", "building", "mall_a", "mall_b", "shinjuku", "beach", "laboratory", "parking", "underground", "arena")
$list = @($Stages | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if (-not $list) { $list = $all }
$dirs = @()
foreach ($s in $list) {
    $dir = Join-Path $root "logs\perf\${Label}_$s"
    $envArg = @(); if ($Env) { $envArg = @("-Env", ($Env -join ',')) }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "perf_fight.ps1") -Stage $s -RunDir $dir `
        -Fight $Fight -Build $Build -Src $Src @envArg | Out-File -Encoding utf8 (Join-Path $root "logs\perf\${Label}_sweep.log") -Append
    $dirs += $dir
}
python -I (Join-Path $PSScriptRoot "perf_table.py") @dirs | Tee-Object -FilePath (Join-Path $root "logs\perf\${Label}_table.md")
