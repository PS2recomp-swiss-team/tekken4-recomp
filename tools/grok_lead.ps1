param([string]$Handoff = "", [int]$MaxSteps = 8, [string]$Effort = "high", [string]$WaitFor = "")
# -WaitFor <task>: first wait until that running Grok task (its grok.exe) has finished. Start it detached so it
# outlives Claude's session: Start-Process powershell -ArgumentList "-NoProfile -File tools\grok_lead.ps1 -WaitFor x" -WindowStyle Hidden
# Runs the steps of docs/ai/handoff.md through tools\grok_task.ps1 while Claude is unavailable (usage limit), one at a
# time, and stops at the first step that fails: no parsed JSON, a non-empty contra[], or files changed outside the
# step's Owns. Grok never commits; every change stays in the working tree for Claude to review, keep or restore.
# Journal: logs\grok\lead_journal.json (one entry per step: task, result json path, verdict, conf, files, status).
# Handoff step format (one per "### STEP" heading):
#   ### STEP <name> | <ask|work> | <owned file>, <owned file>
#   <the prompt: TASK / CTX / FACTS / ASK / LIMITS / DOD blocks>
$root = Split-Path -Parent $PSScriptRoot
if ($WaitFor) { while (Get-CimInstance Win32_Process -Filter "Name = 'grok.exe'" | Where-Object { $_.CommandLine -match [regex]::Escape("logs\grok\$WaitFor" + "_") }) { Start-Sleep -Seconds 30 } }
if (-not $Handoff) { $Handoff = Join-Path $root "docs\ai\handoff.md" }
if (-not (Test-Path $Handoff)) { "no handoff file: $Handoff"; exit 1 }
$text = Get-Content -Raw -Encoding UTF8 $Handoff
$parts = [regex]::Split($text, '(?m)^### STEP ') | Select-Object -Skip 1
$journalPath = Join-Path $root "logs\grok\lead_journal.json"
$journal = @()
$n = 0
foreach ($part in $parts) {
    if (++$n -gt $MaxSteps) { break }
    $lines = $part -split "`r?`n", 2
    $head = $lines[0].Split('|') | ForEach-Object { $_.Trim() }
    $name = $head[0]; $mode = $head[1]
    $owns = @(); if ($head.Count -gt 2 -and $head[2]) { $owns = @($head[2].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $prompt = $lines[1].Trim()
    $taskArgs = @{ Name = "lead-$name"; Mode = $mode; Prompt = $prompt; Effort = $Effort }
    if ($owns.Count) { $taskArgs.Owns = $owns }
    $line = & (Join-Path $PSScriptRoot "grok_task.ps1") @taskArgs | Select-Object -Last 1
    $res = Get-ChildItem (Join-Path $root "logs\grok") -Filter "lead-${name}_*.json" | Sort-Object LastWriteTime | Select-Object -Last 1
    $status = "ok"; $j = $null
    if (-not $res) { $status = "no result file" }
    else {
        $j = Get-Content -Raw -Encoding UTF8 $res.FullName | ConvertFrom-Json
        if ($j.answer -is [string]) { $status = "answer not parsed" }
        elseif (@($j.answer.contra).Count -gt 0) { $status = "contradictions: " + (@($j.answer.contra) -join " | ") }
        elseif ($mode -eq "work" -and @($j.files_changed).Count -eq 0) { $status = "work step changed no owned file" }
    }
    $journal += [ordered]@{ step = $n; task = $name; mode = $mode; result = $(if ($res) { $res.FullName }); status = $status
        verdict = $(if ($j -and $j.answer.verdict) { $j.answer.verdict }); conf = $(if ($j) { $j.answer.conf })
        files = $(if ($j) { $j.files_changed }); cost_usd = $(if ($j) { $j.cost_usd }); wrapper = $line }
    [System.IO.File]::WriteAllText($journalPath, ($journal | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding $false))
    "step $n $name -> $status"
    if ($status -ne "ok") { "stopping: step $n did not pass"; break }
}
"journal: $journalPath"
