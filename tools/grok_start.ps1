param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$PromptFile = "",
    [ValidateSet("ask", "work", "lead")][string]$Mode = "ask",
    [string[]]$Owns = @(),
    [string]$Effort = "high",
    [int]$MaxTurns = 0  # 0 = grok_task.ps1's default (150); deep IOP/driver tasks ran out of turns at 150
)
# The only way to start Grok (user rule 2026-10-22): an independent hidden Windows process, so a Claude session end, a
# terminal or PC restart never interrupts it. Returns at once with the PID; the result lands in logs\grok\<Name>_<time>.json
# and on branch grok/wip (tools\grok_task.ps1). Mode lead = the handoff driver (tools\grok_lead.ps1, docs/ai/handoff.md).
#   powershell -File tools\grok_start.ps1 -Name fight-camera -PromptFile docs\ai\prompts\fight-camera.md
#   powershell -File tools\grok_start.ps1 -Name x -Mode work -Owns runtime/tekken4_overrides.cpp -PromptFile docs\ai\prompts\x.md
#   powershell -File tools\grok_start.ps1 -Name lead -Mode lead
# Prompts live in docs/ai/prompts/ (committed), never in a temp folder.
$root = Split-Path -Parent $PSScriptRoot
& powershell -NoProfile -File "$root\tools\backup_local.ps1" | Out-Null  # additive copy of what git lacks (see backup_local.ps1)
if ($Mode -eq "lead") {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$root\tools\grok_lead.ps1`"", "-Effort", $Effort)
} else {
    if (-not $PromptFile) { "need -PromptFile (docs\ai\prompts\<task>.md)"; exit 1 }
    $prompt = if ([System.IO.Path]::IsPathRooted($PromptFile)) { $PromptFile } else { Join-Path $root $PromptFile }
    if (-not (Test-Path $prompt)) { "prompt file not found: $prompt"; exit 1 }
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$root\tools\grok_task.ps1`"", "-Name", $Name,
        "-Mode", $Mode, "-Effort", $Effort, "-PromptFile", "`"$prompt`"")
    if ($Owns.Count) { $argList += @("-Owns", ($Owns -join ",")) }
    if ($MaxTurns -gt 0) { $argList += @("-MaxTurns", "$MaxTurns") }
}
$p = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden -PassThru
"grok $Name ($Mode) started detached, pid $($p.Id); result: logs\grok\${Name}_<time>.json, branch grok/wip"
