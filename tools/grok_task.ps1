param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Prompt = "",
    [string]$PromptFile = "",
    [ValidateSet("ask", "work")][string]$Mode = "ask",
    [string[]]$Owns = @(),
    [string]$Model = "",
    [string]$Effort = "",
    [int]$MaxTurns = 150
)
# Hands one task to Grok (xAI's Grok Build CLI, `grok`) so it works in parallel with Claude. Grok <-> Claude exchanges
# are AI-to-AI: prompts are terse keyed blocks (TASK / CTX / FACTS / ASK / LIMITS) and Grok answers with a JSON object
# forced by --json-schema (verdict, conf, facts[{c,ref,v}], fix[{where,change}], checks[], open[]). Result:
# logs\grok\<Name>_<time>.json = {task, mode, answer, files_changed, turns, cost_usd, seconds, session}.
#   ask:  analysis in the project (second opinions, reviews, research): reads anything, runs commands, writes only
#         under logs\ (its scripts and notes in logs\grok\).
#   work: a change in the main project, limited to the files given with -Owns (Claude keeps off them meanwhile): it
#         builds into out\grok (TEKKEN4_BUILD_DIR=grok, so it never overwrites Claude's out\runtime) and runs the game
#         into logs\grok\. It never commits: Claude reviews the diff and commits.
# Permissions: Grok's auto mode (its own check approves safe commands; a headless run cannot ask), plus deny rules: no
# writes in top-level folders the task has no business in, no git command that changes a repository. A denied action
# is reported to Grok, which carries on. Run it in the background for parallel work, e.g.
#   powershell -File tools\grok_task.ps1 -Name pad2 -Mode work -Owns external/PS2Recomp/ps2xRuntime/src/lib/Kernel/Stubs/Pad.cpp -PromptFile <file>
$root = Split-Path -Parent $PSScriptRoot
$Owns = @($Owns | ForEach-Object { $_ -split ',' } | Where-Object { $_ })  # powershell -File joins lists with commas
$grok = (Get-Command grok -ErrorAction SilentlyContinue).Source
if (-not $grok) { $grok = Join-Path $env:USERPROFILE ".grok\bin\grok.exe" }
if (-not (Test-Path $grok)) { "grok not found (install Grok Build: irm https://x.ai/cli/install.ps1 | iex)"; exit 1 }
if ($PromptFile) { $Prompt = Get-Content -Raw -Encoding UTF8 $PromptFile }
if (-not $Prompt) { "no prompt (-Prompt or -PromptFile)"; exit 1 }
if ($Mode -eq "work" -and $Owns.Count -eq 0) { "work mode needs -Owns <files the task may modify>"; exit 1 }
# Grok does not load the project's CLAUDE.md until the project is trusted, so the rules come with every task.
$rules = "PROJECT: Tekken 4 PS2 PAL SCES-50878 static recomp (PS2Recomp). PEER: Claude works on other files now. FIRST: read " +
    "docs/ai/grok-brief.md (dense map, commands, facts, protocol A1-A6: obey) + CLAUDE.md; docs/status.md only the section " +
    "the task names. NEVER: commit/publish game files, Ghidra DBs, VU1 micro memories, " +
    "generated C++; send disc/ISO/BIOS anywhere; git commands that change a repo (Claude commits). TRUTH: PCSX2 behaviour. " +
    "PY: python -I. SCRATCH: logs/grok/. OUTPUT: read by an AI, not a human: max density, no narration, no pleasantries, " +
    "no markdown; only the final JSON object counts (interim turns discarded); every fact needs ref (file:line | addr | " +
    "url | log:line) and v=true only if you checked it yourself this session; conf = 0..1 for the verdict."
# Top-level entries the task may not write: everything but logs\ and the folders holding its own files.
$open = @("logs") + @($Owns | ForEach-Object { ($_ -replace '\\', '/').Split('/')[0] })
$deny = @()
foreach ($e in Get-ChildItem -Force $root | Where-Object { $_.Name -ne ".git" -and $open -notcontains $_.Name }) {
    $pattern = if ($e.PSIsContainer) { "$($e.Name)/**" } else { $e.Name }
    if ($pattern -match '[(),]') { $pattern = "*" + $e.Extension }  # e.g. the ISO: rule syntax has no quoting
    if ($deny -notcontains "Write($pattern)") { $deny += @("Write($pattern)", "Edit($pattern)") }
}
foreach ($c in "commit", "push", "reset", "checkout", "switch", "restore", "clean", "stash", "rebase", "merge", "apply",
    "am", "rm", "mv", "add", "tag", "branch -d", "branch -D", "worktree") { $deny += "Bash(git ${c}:*)" }
# No deletion at all (2026-10-22 09:55 the project folder was wiped during four parallel tasks): recursive/forced delete
# commands are denied and nothing may delete (user 2026-10-27: only the user deletes, per step; tools\grok_clean.ps1 is disabled).
foreach ($d in "Remove-Item", "ri", "rm", "rmdir", "rd", "del", "erase", "robocopy", "xcopy", "move", "mv", "Move-Item", "mi", "Clear-Content", "Set-Content", "Out-File", "format", "cmd /c rd", "cmd /c rmdir", "cmd /c del", "cmd /c rm", "powershell -Command Remove-Item", "powershell -NoProfile -Command Remove-Item", "pwsh -Command Remove-Item") { $deny += "Bash(${d}:*)" }
$deny += @('Bash(cmd /c *\"*)', 'Bash(cmd.exe /c *\"*)')  # the 2026-10-22 quoting bug (docs/status.md INCIDENT)
$deny += @("Bash(find:* -delete*)", "Bash(*Remove-Item*)", "Bash(*rmtree*)", "Bash(*rm -rf*)", "Bash(*rd /s*)", "Bash(*rmdir /s*)", "Bash(*[IO.Directory]::Delete*)", "Bash(*Directory.Delete*)")
# Lessons from the 2026-10-22 morning review of the night's 23 runs (docs/ai/grok-retro.md).
$rules += ' QUOTING: Windows PowerShell 5.1 does not treat backslash-quote as an escape: a cmd /c string with backslash-quote inside double quotes is split into extra arguments and runs on the wrong target (it once became rmdir of a drive root). Put cmd /c strings in SINGLE quotes, or use a .cmd/.ps1 file; never write backslash-quote inside a double-quoted argument.'
$rules += " NO DELETE: never delete or move files or folders (rm, rmdir, rd, del, Remove-Item, robocopy, rmtree, any language); not even your own scratch (tools\grok_clean.ps1 is disabled): if something should go, name the exact path in open[] for the user, who is the only one allowed to delete."
$rules += " FINAL: right before your final answer, also write the identical JSON to logs/grok/$Name-final.json " +
    "(the answer survives a hung exit). CHECKS: a check proves something only if it could have failed: before using a " +
    "counter or metric to show 'unchanged', show it is non-zero / moves in a baseline run; never cite a counter that " +
    "read 0 throughout. IMAGES: judge pictures from frame_NNs.bmp (python -I tools/bmp_to_png.py <run dir>), never " +
    "shot_NNs.png window captures (blank while the monitor is off or from a hidden process). Judge them by numbers: " +
    "python -I tools/frame_stats.py <frame> (blank flag, per-channel mean, % white/black) and --diff <ref> <frame> " +
    "(% pixels differing, PSNR; reference = a PCSX2 or earlier-run frame); report those numbers in checks[], never " +
    "'looks fine'. AUDIO: you cannot hear: judge WAVs with python -I tools/wav_stats.py <wav> (rms/peak per window, " +
    "clipped count, longest digital silence, flags); report clipped, longest_silence_s and per-window rms in checks[]; " +
    "compare with a baseline wav when the task is a change. LOW CONF: if conf < 0.6, " +
    "open[0] must name the single next observation that would settle it."
if ($Mode -eq "ask") {
    # Game / PCSX2 runs hold the run lock and the CPU: only work tasks (and Claude) run them.
    foreach ($s in "tools\run_capture.ps1", "tools/run_capture.ps1", "tools\pcsx2_capture.ps1", "tools/pcsx2_capture.ps1") {
        $deny += @("Bash(powershell -File ${s}:*)", "Bash(powershell -NoProfile -File ${s}:*)", "Bash(& ${s}:*)")
    }
    $deny += @("Bash(python -I tools\pine.py:*)", "Bash(python -I tools/pine.py:*)", "Bash(cmd /c tools\run_game.cmd:*)")
}
if ($Mode -eq "work") {
    $rules += " MODE: work. EDIT ONLY: " + ($Owns -join ", ") + " (+ logs/grok/). BUILD: cmd /c tools\build_runtime.cmd " +
        "-> prefer `cmd /c tools\grok_build.cmd $Name` (stage + build into your own out\grok-$Name) and " +
        "`powershell -File tools\grok_run.ps1 -Task $Name -RunDir ... -Keys ... -Shots ... -Env NAME=VALUE`; one simple " +
        "command per tool call, never chain with ; or && or set `$env: inline (headless checks refuse it). " +
        "Otherwise: RUN: powershell -File tools\run_capture.ps1 -RunDir " +
        "logs\grok\$Name-<n> -Keys ... -Shots ... (same build; display-mode menu: always PAL60 = 10:Down,12:Cross). " +
        "files_changed + checks must list what you changed and how you tested. TESTS: after any change to " +
        "ps2xRuntime/ps2xRecomp/ps2xIOP source run `cmd /c tools\build_tests.cmd` and report total/passed/failed; a " +
        "failure in a file you do not own: name it, do not fix it. OWNS IS HARD: if the change needs a file not in " +
        "OWNS, stop and put it in open[] (file + exact change) instead of editing it."
} else {
    $rules += " MODE: ask. No repository edits."
}
# The answer shape, forced by --json-schema (compact keys: c = claim, v = verified by you).
$schema = '{"type":"object","properties":{' +
    '"verdict":{"type":"string"},"conf":{"type":"number"},' +
    '"facts":{"type":"array","items":{"type":"object","properties":{"c":{"type":"string"},"ref":{"type":"string"},"v":{"type":"boolean"}},"required":["c","ref","v"]}},' +
    '"fix":{"type":"array","items":{"type":"object","properties":{"where":{"type":"string"},"change":{"type":"string"}},"required":["where","change"]}},' +
    '"contra":{"type":"array","items":{"type":"string"}},' +
    '"checks":{"type":"array","items":{"type":"string"}},"open":{"type":"array","items":{"type":"string"}},' +
    '"files_changed":{"type":"array","items":{"type":"string"}}},' +
    '"required":["verdict","conf","facts","fix","contra","checks","open","files_changed"]}'
# Prompt via a file and \" in the schema: Windows PowerShell mangles double quotes inside native-command arguments.
$logDir = Join-Path $root "logs\grok"
New-Item -ItemType Directory -Force $logDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$promptPath = Join-Path $logDir ("{0}_{1}.prompt.md" -f $Name, $stamp)
[System.IO.File]::WriteAllText($promptPath, $Prompt, (New-Object System.Text.UTF8Encoding $false))
$grokArgs = @("--prompt-file", $promptPath, "--cwd", $root, "--rules", $rules, "--json-schema", ($schema -replace '"', '\"'),
    "--max-turns", "$MaxTurns", "--permission-mode", "auto")
foreach ($d in $deny) { $grokArgs += @("--deny", $d) }
if ($Model) { $grokArgs += @("--model", $Model) }
if ($Effort) { $grokArgs += @("--reasoning-effort", $Effort) }  # heavy analysis / coding tasks: -Effort high
$repos = @($root, (Join-Path $root "external\PS2Recomp"))
$before = @{}
foreach ($r in $repos) { $before[$r] = @(git -C $r status --short 2>$null) }
$t0 = Get-Date
# Grok CLI 1.0.62 sometimes finishes (unified log: shell.handle_prompt.done) but never exits, which left tasks "stuck"
# for hours with their answers lost (2026-10-22 morning review). Run it as a job and watch its log: once its own pid
# logged handle_prompt.done, give it 90 s to exit, then end it; the answer is also in logs\grok\<Name>-final.json.
$job = Start-Job -ScriptBlock { param($exe, $argv) (& $exe @argv 2>&1 | ForEach-Object { "$_" }) -join "`n" } -ArgumentList $grok, $grokArgs
$unified = Join-Path $env:USERPROFILE ".grok\logs\unified.jsonl"
$grokPid = $null; $doneAt = $null; $hungExit = $false
while ($job.State -eq 'Running') {
    Start-Sleep -Seconds 15
    if (-not $grokPid) {
        $proc = Get-CimInstance Win32_Process -Filter "Name='grok.exe'" | Where-Object { $_.CommandLine -like "*$promptPath*" } | Select-Object -First 1
        if ($proc) { $grokPid = $proc.ProcessId }
    }
    if ($grokPid -and -not $doneAt -and (Test-Path $unified)) {
        try {
            $fs = [System.IO.File]::Open($unified, 'Open', 'Read', 'ReadWrite')
            try {
                $take = [int][Math]::Min(524288, $fs.Length)
                [void]$fs.Seek(-$take, 'End'); $buf = New-Object byte[] $take; [void]$fs.Read($buf, 0, $take)
            } finally { $fs.Close() }
            $tail = [System.Text.Encoding]::UTF8.GetString($buf)
            if ($tail -match ('"pid":\s*' + $grokPid + '\b[^\n]*shell\.handle_prompt\.done')) { $doneAt = Get-Date }
        } catch { }
    }
    if ($doneAt -and ((Get-Date) - $doneAt).TotalSeconds -ge 90 -and (Get-Process -Id $grokPid -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $grokPid -Force -ErrorAction SilentlyContinue
        $hungExit = $true
    }
}
$raw = [string](Receive-Job $job -Wait)
Remove-Job $job -Force
# text holds one JSON object per assistant turn: the last complete one is the answer.
$answer = $null; $meta = $null
try {
    $meta = $raw.Substring($raw.IndexOf('{'), $raw.LastIndexOf('}') - $raw.IndexOf('{') + 1) | ConvertFrom-Json
    $text = [string]$meta.text
    $depth = 0; $start = -1; $last = $null; $inStr = $false; $esc = $false
    for ($i = 0; $i -lt $text.Length; $i++) {
        $ch = $text[$i]
        if ($inStr) { if ($esc) { $esc = $false } elseif ($ch -eq '\') { $esc = $true } elseif ($ch -eq '"') { $inStr = $false }; continue }
        if ($ch -eq '"') { $inStr = $true } elseif ($ch -eq '{') { if ($depth -eq 0) { $start = $i }; $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0 -and $start -ge 0) { $last = $text.Substring($start, $i - $start + 1) } }
    }
    if ($last) { $answer = $last | ConvertFrom-Json }
} catch { }
# No answer on stdout (a hung exit, or a crash): take the copy Grok wrote before answering, if it is from this run.
$finalPath = Join-Path $logDir ("{0}-final.json" -f $Name)
if (-not $answer -and (Test-Path $finalPath) -and (Get-Item $finalPath).LastWriteTime -ge $t0) {
    try { $answer = Get-Content -Raw $finalPath | ConvertFrom-Json } catch { }
}
$changed = @()
foreach ($r in $repos) {
    $rel = if ($r -eq $root) { "" } else { "external/PS2Recomp/" }
    $changed += @(git -C $r status --short 2>$null | Where-Object { $before[$r] -notcontains $_ } | ForEach-Object { $rel + $_.Substring(3) })
}
# Grok's changes = its -Owns files; anything else that changed meanwhile is most likely Claude's own work.
$ownsNorm = @($Owns | ForEach-Object { $_ -replace '\\', '/' })
$mine = @($changed | Where-Object { $ownsNorm -contains $_ })
$other = @($changed | Where-Object { $ownsNorm -notcontains $_ })
$result = [ordered]@{
    task = $Name; mode = $Mode; answer = $(if ($answer) { $answer } else { $raw }); files_changed = $mine
    other_tree_changes = $other
    turns = $(if ($meta) { $meta.num_turns }); cost_usd = $(if ($meta) { $meta.total_cost_usd })
    seconds = [int]((Get-Date) - $t0).TotalSeconds; session = $(if ($meta) { $meta.sessionId })
    hung_exit = $hungExit
}
$log = Join-Path $logDir ("{0}_{1}.json" -f $Name, $stamp)
[System.IO.File]::WriteAllText($log, ($result | ConvertTo-Json -Depth 12 -Compress), (New-Object System.Text.UTF8Encoding $false))

# Checkpoint on branch grok/wip (pushed to origin), without touching the checkout, the index or master: the task's
# result json, its notes (logs/grok/<Name>*.md), its owned repo files, and its PS2Recomp changes as a patch file.
# Grok itself never runs git; Claude reviews with `git log master..grok/wip` and merges what holds.
$tmpIndex = Join-Path $env:TEMP ("grok-wip-index-" + $stamp)
$OutputEncoding = New-Object System.Text.UTF8Encoding $false  # no BOM in what is piped to git (the commit message)
try {
    $files = @(@{ path = "grok-wip/" + (Split-Path -Leaf $log); file = $log })
    $files += @{ path = "grok-wip/" + (Split-Path -Leaf $promptPath); file = $promptPath }
    Get-ChildItem $logDir -Filter "$Name*.md" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $t0 } |
        ForEach-Object { $files += @{ path = "grok-wip/" + $_.Name; file = $_.FullName } }
    foreach ($f in $mine) {
        $full = Join-Path $root $f
        if ($f -notlike "external/PS2Recomp/*" -and (Test-Path $full)) { $files += @{ path = $f; file = $full } }
    }
    $ps2 = @($mine | Where-Object { $_ -like "external/PS2Recomp/*" } | ForEach-Object { $_.Substring(19) })
    if ($ps2.Count) {
        $patch = Join-Path $logDir ("{0}_{1}.patch" -f $Name, $stamp)
        $diff = git -C (Join-Path $root "external\PS2Recomp") diff HEAD -- @ps2
        [System.IO.File]::WriteAllText($patch, (($diff -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
        $files += @{ path = "grok-wip/" + (Split-Path -Leaf $patch); file = $patch }
    }
    $parent = git -C $root rev-parse --verify -q refs/heads/grok/wip
    if (-not $parent) { $parent = git -C $root rev-parse master }
    $env:GIT_INDEX_FILE = $tmpIndex
    git -C $root read-tree $parent
    foreach ($x in $files) {
        $blob = git -C $root hash-object -w -- $x.file
        git -C $root update-index --add --cacheinfo "100644,$blob,$($x.path)"
    }
    $tree = git -C $root write-tree
    Remove-Item Env:GIT_INDEX_FILE
    $verdict = if ($answer -and $answer.verdict) { [string]$answer.verdict } else { "no parsed answer" }
    if ($verdict.Length -gt 180) { $verdict = $verdict.Substring(0, 180) }
    $commit = "grok $Name ($Mode): $verdict" | git -C $root commit-tree $tree -p $parent
    git -C $root update-ref refs/heads/grok/wip $commit
    git -C $root push -q origin grok/wip 2>$null
    "checkpoint grok/wip $($commit.Substring(0, 7)) ($($files.Count) files)"
} catch { "checkpoint failed: $_" } finally {
    Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
}
"grok $Name done {0}s parsed={1}: $log" -f $result.seconds, [bool]$answer
