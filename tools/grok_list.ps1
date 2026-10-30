# Lists the running Grok tasks: task name, pid, start time, and minutes since the task last touched a file
# (its notes, logs/grok/<task>* files or run dirs). Usage: powershell -File tools\grok_list.ps1
$root = Split-Path -Parent $PSScriptRoot
$logs = Join-Path $root "logs\grok"
Get-CimInstance Win32_Process -Filter "Name='grok.exe'" | ForEach-Object {
    if ($_.CommandLine -match 'grok.([a-z0-9-]+)_[0-9]{8}_[0-9]{6}[.]prompt') {
        $task = $Matches[1]
        $last = Get-ChildItem $logs -Recurse -File -Filter "$task*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $idle = if ($last) { [int]((Get-Date) - $last.LastWriteTime).TotalMinutes } else { -1 }
        "{0,-20} pid {1,-6} since {2:HH:mm}  last file {3} min ago" -f $task, $_.ProcessId, $_.CreationDate, $idle
    }
}
