param([Parameter(Mandatory = $true)][string[]]$After, [Parameter(Mandatory = $true)][string]$Name,
      [Parameter(Mandatory = $true)][string]$PromptFile, [string]$Mode = "work", [string[]]$Owns = @(),
      [string]$Effort = "high", [int]$MaxTurns = 0, [int]$PollSeconds = 60)
# Starts a Grok task once the given Grok tasks have finished (user, 2026-10-28: Grok keeps working on its own while
# Claude is out of usage). Run it detached (it is token-free):
#   Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile -File tools\grok_chain.ps1 -After a,b -Name c -PromptFile docs\ai\prompts\c.md -Owns x'
# Log: logs\grok\chain-<Name>.log
$root = Split-Path -Parent $PSScriptRoot
$After = @($After | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$Owns = @($Owns | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$log = Join-Path $root "logs\grok\chain-$Name.log"
function Say([string]$m) { "{0:HH:mm:ss} $m" -f (Get-Date) | Add-Content -Encoding utf8 $log }
Say "waiting for: $($After -join ', ')"
while ($true) {
    $running = @(Get-CimInstance Win32_Process -Filter "Name = 'grok.exe'" | ForEach-Object { $_.CommandLine } |
        Where-Object { $cmd = $_; @($After | Where-Object { $cmd -match [regex]::Escape("logs\grok\$_" + "_") }).Count -gt 0 })
    if ($running.Count -eq 0) { break }
    Start-Sleep -Seconds $PollSeconds
}
Say "all finished; starting $Name"
$args2 = @("-NoProfile", "-File", (Join-Path $root "tools\grok_start.ps1"), "-Name", $Name, "-Mode", $Mode, "-Effort", $Effort,
           "-PromptFile", $PromptFile)
if ($Owns.Count) { $args2 += @("-Owns", ($Owns -join ",")) }
if ($MaxTurns -gt 0) { $args2 += @("-MaxTurns", "$MaxTurns") }
(& powershell @args2) | ForEach-Object { Say $_ }
