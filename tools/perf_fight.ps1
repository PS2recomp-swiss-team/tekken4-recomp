param([string]$RunDir = "", [string]$Stage = "arena", [double]$Fight = 32, [string[]]$Shots = @(), [string[]]$Env = @(),
      [string]$Build = "perf", [string]$Src = "D:\tekken4-fork-perf")
# US (SLUS-20328) fixed Practice fight for perf work (docs\PERF.md): Kazuya (1P) vs CPU Yoshimitsu on -Stage, then
# -Fight seconds of the fight. Copy of run_fixed_fight.ps1 (PAL timings) with the US menu path checked in
# logs\perf\cal1: 8 Start (skip movie), 13 Start (MEDIUM), MODE SELECT on STORY BATTLE: 4x Down = PRACTICE (VS BATTLE
# is greyed out and skipped), Cross 21.5; char select: Cross 25 (Kazuya), CPU: Up, Up, Right = Yoshimitsu, Cross 30.5.
# Stage select from ~31.5 on the RANDOM slot; Right n times = airport .. arena, Left from the random slot the other way.
# Per-second counters: PS2X_PERF_STATS ("[perf]" lines, runtime) and TEKKEN4_PERF_LOG ("perf second" lines, game
# frames from the per-frame sound call) in stdout.txt; tools\perf_table.py summarises the fight window.
#   powershell -ExecutionPolicy Bypass -File tools\perf_fight.ps1 -Stage underground -RunDir logs\perf\base_underground
$root = Split-Path -Parent $PSScriptRoot
if (-not $RunDir) { $RunDir = Join-Path $root ("logs\perf\fight_" + $Stage + "_" + (Get-Date -Format "yyyyMMdd_HHmmss")) }
$env:TEKKEN4_SRC = $Src
$env:TEKKEN4_BUILD_DIR = $Build
if (-not $env:TEKKEN4_SOUND) { $env:TEKKEN4_SOUND = "1" }
$env:PS2X_PERF_STATS = "400"
$env:TEKKEN4_PERF_LOG = "400"
$env:PS2X_PERF_STATS_VU = "1"
foreach ($pair in @($Env | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) {
    $name, $value = $pair -split '=', 2
    Set-Item -Path "env:$name" -Value $value
}
$order = @("airport", "building", "mall_a", "mall_b", "shinjuku", "beach", "laboratory", "parking", "underground", "arena")
$k = [array]::IndexOf($order, $Stage) + 1
if ($k -lt 1) { "unknown stage $Stage (one of: $($order -join ', '))"; exit 1 }
$dir, $n = if ($k -le 11 - $k) { "Right", $k } else { "Left", (11 - $k) }
$stageKeys = @(0..($n - 1) | ForEach-Object { "$(34 + $_):$dir" })
$confirm = 34 + $n + 2
$keys = @("8:Start", "13:Start",                                              # skip movie, MEDIUM
          "17:Down", "18:Down", "19:Down", "20:Down", "21.5:Cross",            # PRACTICE
          "25:Cross", "27:Up", "28:Up", "29:Right", "30.5:Cross") +            # Kazuya; CPU Yoshimitsu
        $stageKeys + @("${confirm}:Cross", "$($confirm + 11):Start")          # stage; close the command-list help
$check = $confirm - 1
$start = $confirm + 13
$until = [math]::Ceiling($start + $Fight)
$allShots = @($Shots | ForEach-Object { $_ -split ',' } | Where-Object { $_ }) + @("$check", "$($start + 5)", "$until")
"perf fight: Kazuya vs CPU Yoshimitsu on $Stage ($n x $dir), fight from ~$start s to $until s"
New-Item -ItemType Directory -Force $RunDir | Out-Null
"fight $start $until $Stage" | Set-Content -Encoding ascii (Join-Path $RunDir "window.txt")
# CPU contention (another agent's build or game instances skew the numbers): wait until no compiler runs for 20 s
# (at most 40 min), then sample every 2 s during the run: contention.txt "<s> <cl+link count> <other games>".
$quiet = 0; $waited = 0
while ($quiet -lt 20 -and $waited -lt 2400) {
    $busy = @(Get-Process cl, link -ErrorAction SilentlyContinue).Count
    if ($busy -eq 0) { $quiet += 5 } else { $quiet = 0; if ($waited % 60 -eq 0) { "waiting for $busy compiler processes to finish" } }
    Start-Sleep 5; $waited += 5
}
$exePath = Join-Path $Src "out\$Build\ps2xRuntime\ps2EntryRunner.exe"
$job = Start-Job -ArgumentList (Join-Path $RunDir "contention.txt"), $exePath -ScriptBlock {
    param($out, $exe)
    $t0 = Get-Date
    while ($true) {
        $cl = @(Get-Process cl, link -ErrorAction SilentlyContinue).Count
        $games = @(Get-Process ps2EntryRunner, pcsx2-qt -ErrorAction SilentlyContinue | Where-Object { $_.Path -ne $exe }).Count
        "{0} {1} {2}" -f [int]((Get-Date) - $t0).TotalSeconds, $cl, $games | Add-Content -Encoding ascii $out
        Start-Sleep 2
    }
}
try { & (Join-Path $PSScriptRoot "run_capture.ps1") -RunDir $RunDir -Keys ($keys -join ',') -Shots ($allShots -join ',') }
finally { Stop-Job $job; Remove-Job $job -Force }
