param([int]$PollMinutes = 5, [int]$IdleMinutes = 60, [int]$MaxHours = 8, [switch]$Each)
# Token-free watcher for the lead's batch review: checks the running Grok tasks every $PollMinutes, prints one line per
# check, and exits when no Grok task is running any more, or when every one still running has touched no file
# (notes / logs/grok/<task>* / run dirs) for $IdleMinutes (stuck), or after $MaxHours. Run it in the background; its exit
# wakes the lead once for the review (user, 2026-10-22: "check every 15 minutes, then after all tasks finished do the
# reviews").
# Modes (user, 2026-10-22: the script is free, so watching never costs Claude tokens):
#   low-burn: powershell -File tools\grok_wait_all.ps1                 (every 5 min, wake when all are done)
#   normal:   powershell -File tools\grok_wait_all.ps1 -PollMinutes 1 -Each (every minute, wake per finished task)
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $root "logs\grok"
$start = Get-Date
$seen = @{}
$prev = $null
while ($true) {
    $running = @()
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='grok.exe'")) {
        if ($p.CommandLine -match 'grok.([a-z0-9-]+)_[0-9]{8}_[0-9]{6}[.]prompt') {
            $task = $Matches[1]
            $seen[$task] = $true
            $last = Get-ChildItem $logs -Recurse -File -Filter "$task*" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $idle = if ($last) { [int]((Get-Date) - $last.LastWriteTime).TotalMinutes } else { 0 }
            $running += [pscustomobject]@{ Task = $task; Idle = $idle }
        }
    }
    $stamp = Get-Date -Format "HH:mm"
    if ($Each -and $prev) {
        $gone = @($prev | Where-Object { @($running.Task) -notcontains $_ })
        if ($gone.Count) { "$stamp finished: " + ($gone -join ', ') + "; still running: " + (@($running.Task) -join ', '); break }
    }
    $prev = @($running.Task)
    if ($running.Count -eq 0) { "$stamp all Grok tasks finished ($($seen.Keys -join ', '))"; break }
    $active = @($running | Where-Object { $_.Idle -lt $IdleMinutes })
    "$stamp running: " + (($running | ForEach-Object { "$($_.Task) (idle $($_.Idle) min)" }) -join ', ')
    if ($active.Count -eq 0) { "$stamp every running task idle >= $IdleMinutes min: stuck, review now"; break }
    if (((Get-Date) - $start).TotalHours -ge $MaxHours) { "$stamp max wait reached"; break }
    Start-Sleep -Seconds ($PollMinutes * 60)
}
