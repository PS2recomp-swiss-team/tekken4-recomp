param([int]$MinMinutes = 30, [switch]$Force)
# Additive backup of what git does not hold (user, 2026-10-22, after the 09:55 wipe): ghidra project, logs, the PS2Recomp
# tree with uncommitted work, generated sources are skipped (regenerable). Copies to C:\Users\<user>\tekken4-backup-us
# (another drive than the project; the PAL cousin project uses tekken4-backup). Never /MIR: a vanished source must not
# empty the backup. Throttled to one run per $MinMinutes (stamp file). Run by tools\grok_start.ps1 before every launch,
# and by hand.
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "us_tree.ps1")
$usTree = Resolve-UsTree $root
$dst = Join-Path $env:USERPROFILE "tekken4-backup-us"
$stamp = Join-Path $dst ".stamp"
New-Item -ItemType Directory -Force $dst | Out-Null
if (-not $Force -and (Test-Path $stamp) -and ((Get-Date) - (Get-Item $stamp).LastWriteTime).TotalMinutes -lt $MinMinutes) { "backup fresh"; exit 0 }
if (-not (Test-Path (Join-Path $root ".git"))) { "backup skipped: $root has no .git (project damaged?)"; exit 1 }
$src = @(
    @{ From = "ghidra"; To = "ghidra"; Xd = @() },
    @{ From = "game\vu1"; To = "game\vu1"; Xd = @() },  # captured VU1 micro memory: lost once, the fight dropped to 12 fps
    @{ From = "logs"; To = "logs"; Xd = @() },
    @{ From = "external\PS2Recomp"; To = "external\PS2Recomp"; Xd = @("out", "build", ".vs") },
    # Default build tree since 2026-10-28 (sibling clone, branches = committed patch stack, local-only commits)
    @{ From = $usTree; To = "fork-ps2recomp"; Xd = @("out", "build", ".vs") }
)
foreach ($s in $src) {
    $from = if ([IO.Path]::IsPathRooted($s.From)) { $s.From } else { Join-Path $root $s.From }
    if (-not (Test-Path $from)) { continue }
    $args = @($from, (Join-Path $dst $s.To), "/E", "/XO", "/R:1", "/W:1", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/MAX:300000000")
    if ($s.Xd.Count) { $args += "/XD"; $args += $s.Xd }
    robocopy @args | Out-Null
}
git -C $root bundle create (Join-Path $dst "repo.bundle") --all 2>$null | Out-Null
$fork = $usTree
if (Test-Path (Join-Path $fork ".git")) { git -C $fork bundle create (Join-Path $dst "fork-ps2recomp.bundle") --all 2>$null | Out-Null }
Set-Content $stamp (Get-Date -Format s)
"backup done -> $dst"
