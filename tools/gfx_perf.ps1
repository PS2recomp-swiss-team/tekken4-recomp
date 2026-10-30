# Graphics build checks (docs/GRAPHICS.md): fight fps per internal resolution on the heaviest stages (Practice,
# tools\perf_fight.ps1) and the rollback self-test (docs/ROLLBACK_PHASE2.md p2c: sound off, all cuts, mispredict).
# Waits for C:\T5DROnline\build\int115\HEAVY.lock before every run. Results: logs\gfx\perf\*, logs\gfx\perf\table.md.
#   powershell -ExecutionPolicy Bypass -File tools\gfx_perf.ps1 [-Runs "arena:native,arena:2,..."] [-NoRollback]
param([string]$Runs = "arena:native,building:native,arena:2,arena:3,arena:4,arena:1440p,arena:4k", [switch]$NoRollback,
      [string]$Env = "", [string]$Label = "")
$root = Split-Path -Parent $PSScriptRoot
$t = $PSScriptRoot
$src = "D:\tekken4-fork-gfx"; $build = "gfx"
function Wait-Heavy { $n = 0; while ((Test-Path C:\T5DROnline\build\int115\HEAVY.lock) -and $n -lt 30) { "HEAVY.lock present, waiting"; Start-Sleep 60; $n++ } }
$dirs = @()
foreach ($r in ($Runs -split ',')) {
    $stage, $res = $r -split ':', 2
    $dir = Join-Path $root "logs\gfx\perf\$Label$stage`_$res"
    Wait-Heavy
    $envs = @("TEKKEN4_SOUND=1", "PS2X_GS_HW_SCALE=$res") + @($Env -split ',' | Where-Object { $_ })
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$t\perf_fight.ps1" -Stage $stage -RunDir $dir -Src $src -Build $build -Env ($envs -join ',') | Select-Object -Last 1
    $dirs += $dir
}
& (Join-Path $root "external\pytools\Scripts\python.exe") -I "$t\perf_table.py" @dirs | Out-File -Encoding utf8 (Join-Path $root "logs\gfx\perf\${Label}table.md")
if (-not $NoRollback) {
    Wait-Heavy
    $s = 'TEKKEN4_RAND_SEED=1;TEKKEN4_RB_INPUT=500:Start,800:Start,1040:Start,1280:Cross,1580:Start;TEKKEN4_RB_FUZZ=2100'
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$t\perf_rb_run.ps1" -Name gfx_p2c -Shots "60,100" -Src $src -Build $build `
        -Env "$s;TEKKEN4_SOUND=0;TEKKEN4_RB_MODE=test;TEKKEN4_RB_TEST=start=2100,every=30,depth=8,mispredict=1" | Select-Object -Last 1
    Select-String (Join-Path $root "logs\perf\rb\gfx_p2c\rb_frames.log") -Pattern 'SUMMARY|mismatch' | Select-Object -Last 5 |
        ForEach-Object { $_.Line } | Out-File -Encoding utf8 (Join-Path $root "logs\gfx\perf\rb_selftest.txt")
}
