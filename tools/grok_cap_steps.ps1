param([string]$Notes = "logs\grok\gs-throughput-notes.md", [int]$Extra = 2, [int]$MaxHours = 3)
# Free watcher: exits once the notes file has $Extra more "## Step" sections than at start (user: "let it work for two extra runs, then wrap up"), or the task ends, or after $MaxHours.
$root = Split-Path -Parent $PSScriptRoot
$f = Join-Path $root $Notes
$base = @(Select-String -Path $f -Pattern '^## Step').Count
$start = Get-Date
while ($true) {
    Start-Sleep -Seconds 60
    $now = @(Select-String -Path $f -Pattern '^## Step').Count
    $running = @(Get-CimInstance Win32_Process -Filter "Name='grok.exe'" | Where-Object { $_.CommandLine -match 'gs-throughput' }).Count
    if ($now -ge $base + $Extra) { "$(Get-Date -f HH:mm) cap reached: $base -> $now steps"; break }
    if ($running -eq 0) { "$(Get-Date -f HH:mm) task ended at $now steps"; break }
    if (((Get-Date) - $start).TotalHours -ge $MaxHours) { "$(Get-Date -f HH:mm) max wait"; break }
}
