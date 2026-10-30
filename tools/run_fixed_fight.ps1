param([string]$RunDir = "", [string[]]$Shots = @(), [string[]]$Env = @(), [string]$Task = "", [string]$Stage = "arena",
      [double]$Until = 100)
# Repeatable test fight (user, 2026-10-28: tests never use Story/Arcade, they pick the opponent and the stage):
# PRACTICE, Kazuya (1P) vs CPU Yoshimitsu on -Stage (default arena = the cage; names as in tools\stage_card.py).
# Path (shown by the user in logs\user_path3, checked in logs\fixed_try4..8): PAL60 + main menu as usual; 4x Down =
# PRACTICE (VS BATTLE is greyed out and skipped), Cross; the 1P cursor starts on Kazuya: Cross; the CPU cursor starts on
# Kazuya too: Up, Up (Hwoarang), Right = Yoshimitsu, Cross. The stage select opens on a RANDOM slot (shows a random
# card; confirming it picks that one). From it Right goes airport, building, mall_a, mall_b, shinjuku, beach,
# laboratory, parking, underground, arena, then back to the random slot; Left goes the other way (Left once = arena).
# Then "Get Ready", VS, the command-list help (closed with Start) and the fight, from ~74 s for arena.
# -Shots are absolute seconds (frame_NNs.bmp); a shot is always taken at -Until (the run's end).
#   powershell -File tools\run_fixed_fight.ps1 -RunDir logs\fixed_x -Shots 85,95 -Env TEKKEN4_PERF_LOG=100,TEKKEN4_SOUND=1
#   -Task <grok task>: run that task's build (out\grok-<task>, its tree external\wt-<task> when present)
$root = Split-Path -Parent $PSScriptRoot
if (-not $RunDir) { $RunDir = Join-Path $root ("logs\fixed_" + (Get-Date -Format "yyyyMMdd_HHmmss")) }
foreach ($pair in @($Env | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) {
    $name, $value = $pair -split '=', 2
    Set-Item -Path "env:$name" -Value $value
}
if ($Task) {
    $env:TEKKEN4_BUILD_DIR = "grok-$Task"
    $taskTree = Join-Path $root "external\wt-$Task"
    if (Test-Path (Join-Path $taskTree "ps2xRuntime")) { $env:TEKKEN4_SRC = $taskTree }
}
$order = @("airport", "building", "mall_a", "mall_b", "shinjuku", "beach", "laboratory", "parking", "underground", "arena")
$k = [array]::IndexOf($order, $Stage) + 1
if ($k -lt 1) { "unknown stage $Stage (one of: $($order -join ', '))"; exit 1 }
$dir, $n = if ($k -le 11 - $k) { "Right", $k } else { "Left", (11 - $k) }
$stageKeys = @(0..($n - 1) | ForEach-Object { "$(57 + $_):$dir" })
$confirm = 57 + $n + 2
$keys = @("10:Down", "12:Cross", "15:Left", "16.5:Cross", "30:Start", "36:Cross",   # PAL60, Start game: Yes, movie, menu
          "40:Down", "41:Down", "42:Down", "43:Down", "44.5:Cross",               # PRACTICE
          "48:Cross", "50:Up", "51:Up", "52:Right", "53.5:Cross") +               # Kazuya; CPU Yoshimitsu
        $stageKeys + @("${confirm}:Cross", "$($confirm + 11):Start")             # stage; close the command-list help
$check = $confirm - 1
$allShots = @($Shots | ForEach-Object { $_ -split ',' } | Where-Object { $_ }) + @("$check", "$Until")
"fixed fight: Kazuya vs CPU Yoshimitsu on $Stage ($n x $dir), fight from ~$($confirm + 13) s"
& (Join-Path $PSScriptRoot "run_capture.ps1") -RunDir $RunDir -Keys ($keys -join ',') -Shots ($allShots -join ',')
$frame = Join-Path $RunDir "frame_${check}s.bmp"
if ((Test-Path $frame) -and (Test-Path (Join-Path $root "logs\stage_refs"))) {
    "stage card before the confirm: $(python -I (Join-Path $PSScriptRoot 'stage_card.py') $frame) (index name distance)"
}
