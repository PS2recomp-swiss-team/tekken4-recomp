param([string]$RunDir = "", [string[]]$Shots = @(), [string[]]$Env = @(), [string]$Task = "", [string]$Stage = "arena",
      [double]$Until = 100)
# Repeatable test fight (user, 2026-10-28: tests never use Story/Arcade, they pick the opponent and the stage):
# PRACTICE, Kazuya (1P) vs CPU Yoshimitsu on -Stage (default arena = the cage; names as in tools\stage_card.py).
# Path (shown by the user in logs\user_path3, checked in logs\fixed_try4..8): PAL60 + main menu as usual; 4x Down =
# PRACTICE (VS BATTLE is greyed out and skipped), Cross; the 1P cursor starts on Kazuya: Cross; the CPU cursor starts on
# Kazuya too: Up, Up (Hwoarang), Right = Yoshimitsu, Cross. That Cross opens the stage card on the character-select
# screen (a corner card, random art, countdown). run_capture.ps1 -StagePick waits until that card is settled
# (stage_card.py dist<=22 and gap>=30), presses Left/Right until the art is -Stage, then Cross, then Start 11 s later
# (command-list help). The old fixed presses from 57 s confirmed whatever was up when the load was late
# (logs/grok/stage-pick-notes.md). Exit 2 if the card never settles on -Stage.
# TEKKEN4_FIXED_LATE=<seconds> delays only the CPU-confirm Cross, so the card opens that much later (late-screen test).
# -Shots are absolute seconds (frame_NNs.bmp); a shot is always taken at -Until (the run's end). The process stays
# ~2.5 s past -Until so the runtime's frame shot at that second is written.
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
$confirm = 57 + $n + 2
$late = 0.0
if ($env:TEKKEN4_FIXED_LATE) { $late = [double]$env:TEKKEN4_FIXED_LATE }
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$cpuCross = [string]::Format($inv, "{0:0.###}:Cross", (53.5 + $late))
$keys = @("10:Down", "12:Cross", "15:Left", "16.5:Cross", "30:Start", "36:Cross",   # PAL60, Start game: Yes, movie, menu
          "40:Down", "41:Down", "42:Down", "43:Down", "44.5:Cross",               # PRACTICE
          "48:Cross", "50:Up", "51:Up", "52:Right", $cpuCross)                    # Kazuya; CPU Yoshimitsu (opens the card)
$allShots = @($Shots | ForEach-Object { $_ -split ',' } | Where-Object { $_ }) + @("$Until")
"fixed fight: Kazuya vs CPU Yoshimitsu on $Stage ($n x $dir), fight from ~$($confirm + 13) s"
if ($late -ne 0.0) { "stage card opens late: CPU confirm Cross at {0}" -f $cpuCross }
& (Join-Path $PSScriptRoot "run_capture.ps1") -RunDir $RunDir -Keys ($keys -join ',') -Shots ($allShots -join ',') -StagePick $Stage
if ($global:TekkenStagePickExit) { exit $global:TekkenStagePickExit }
