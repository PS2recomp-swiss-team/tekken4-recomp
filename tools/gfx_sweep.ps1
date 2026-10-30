# Graphics check per internal resolution step (docs/GRAPHICS.md): for each step one run to a fight (menus, character
# select, fight; fps from TEKKEN4_PERF_LOG) and one run of the intro movie; frame shots and a sheet logs\gfx\res_<step>.png.
# Uses the graphics build (TEKKEN4_SRC=D:\tekken4-fork-gfx, TEKKEN4_BUILD_DIR=gfx unless set). Waits for
# C:\T5DROnline\build\int115\HEAVY.lock to go away before every run; run_capture.ps1 takes logs\run.lock.
#   powershell -File tools\gfx_sweep.ps1 [-Steps lowest,native,1080p,1440p,4k,auto] [-Env "TEKKEN4_AA=off"] [-Label x]
param([string]$Steps = "lowest,native,1080p,1440p,4k,auto", [string]$Env = "", [string]$Label = "", [switch]$NoMovie)
$root = Split-Path -Parent $PSScriptRoot
$py = Join-Path $root "external\pytools\Scripts\python.exe"
if (-not $env:TEKKEN4_SRC) { $env:TEKKEN4_SRC = "D:\tekken4-fork-gfx" }
if (-not $env:TEKKEN4_BUILD_DIR) { $env:TEKKEN4_BUILD_DIR = "gfx" }
$env:TEKKEN4_SOUND = "0"
$env:PS2X_DEBUG_PANEL = "0"
foreach ($kv in ($Env -split ',' | Where-Object { $_ })) { $k, $v = $kv -split '=', 2; Set-Item -Path "env:$k" -Value $v }
function Wait-Heavy { $n = 0; while ((Test-Path C:\T5DROnline\build\int115\HEAVY.lock) -and $n -lt 30) { "HEAVY.lock present, waiting"; Start-Sleep 60; $n++ } }
function Run([string]$dir, [string]$shots, [string]$keys) {
    Wait-Heavy
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_capture.ps1") -RunDir $dir -Shots $shots -Keys $keys | Select-Object -Last 1
    Get-ChildItem $dir -Filter frame_*.bmp | ForEach-Object { & $py -I (Join-Path $PSScriptRoot "bmp_to_png.py") $_.FullName | Out-Null }
}
foreach ($step in ($Steps -split ',')) {
    $env:TEKKEN4_INTERNAL_RES = $step
    $env:TEKKEN4_PERF_LOG = "75"
    $base = Join-Path $root ("logs\gfx\sweep{0}_{1}" -f $Label, $step)
    Run "$base`_fight" "12,20,24,40,56" "8:Start,13:Start,17:Start,21:Cross,23:Cross,25:Cross,27:Start,29:Start,62:Select"
    Remove-Item env:TEKKEN4_PERF_LOG
    if (-not $NoMovie) { Run "$base`_movie" "10,14" "16:Select" }
    & python (Join-Path $PSScriptRoot "gfx_sheet.py") $step "$base`_fight" "$base`_movie" (Join-Path $root ("logs\gfx\res{0}_{1}.png" -f $Label, $step))
}
