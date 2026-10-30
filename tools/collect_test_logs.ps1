# Collect diagnostic text only. Never copy a run directory: it can contain memory cards and pictures.
# Run after closing the game: powershell -File tools\collect_test_logs.ps1
param([string]$RunDir = "", [string]$OutputDirectory = "")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $RunDir) { $RunDir = Join-Path $root "logs\net" }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root "test-results" }

function Assert-NoLinks([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    while ($item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Links/reparse points are not log sources." }
        $item = $item.Parent
    }
}
function Convert-SafeLogLine([string]$Line, [bool]$TransportLog = $false) {
    # Only netplay records, even when stdout/stderr also contain game or filesystem messages.
    if ($Line.Length -gt 16384 -or $Line -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') { return $null }
    if ($Line -notmatch '^\s*(?:NET[A-Z]*\b|\[t4net\]\s)' -and
        -not ($TransportLog -and $Line -match '^\[\s*\d+\.\d+\]\s')) { return $null }
    if ($Line -match '(?i)PRIVATE KEY|\b(?:password|secret|token|api[_-]?key|access[_-]?token|authorization)\b\s*[:=]') { return '[diagnostic record omitted: credential-like content]' }
    $Line = $Line -replace '(?i)(?:\b[a-z]:[\\/]|\\\\)[^\s"<>|]*', '[path]'
    $Line = $Line -replace '(?i)/(?:home|users)/[^\s"<>|]*', '[path]'
    $Line = $Line -replace '(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?(?![\w.])', '[address]'
    $Line = $Line -replace '(?i)\b(?:https?|wss?|udp|tcp)://[^\s"<>]*', '[endpoint]'
    $Line = $Line -replace '(?i)(?<![\w:])(?:[0-9a-f]{0,4}:){2,}[0-9a-f:.%]+', '[address]'
    return $Line
}
function Get-SafeIdentity($Value) {
    if ($null -eq $Value -or [string]$Value.build_id -notmatch '^[0-9a-fA-F]{16}$' -or
        [string]$Value.iso_sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        [string]$Value.elf_sha1 -notmatch '^[0-9a-fA-F]{40}$' -or
        [string]$Value.compiler -notmatch '^[a-zA-Z0-9_.+ (),=-]{1,160}$' -or
        [string]$Value.net -notmatch '^\d{1,6}$') { return $null }
    $safeIdentity = [ordered]@{ schema = 1; build_id = [string]$Value.build_id; compiler = [string]$Value.compiler;
        iso_sha256 = [string]$Value.iso_sha256; elf_sha1 = [string]$Value.elf_sha1; net = [int]$Value.net }
    foreach ($setting in @('strict_hello', 'delay_match')) {
        if ([string]$Value.$setting -match '^[01]$') { $safeIdentity[$setting] = [string]$Value.$setting }
    }
    return $safeIdentity
}
function Read-SmallJson([string]$Path) {
    Assert-NoLinks $Path
    if ((Get-Item -LiteralPath $Path).Length -gt 32768) { throw "Oversize diagnostic metadata." }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

Assert-NoLinks $RunDir
if (-not (Test-Path -LiteralPath $RunDir -PathType Container)) { throw "No netplay run directory. Run the online test first, or use -RunDir <run folder>." }
$entries = [ordered]@{}
$notes = New-Object 'System.Collections.Generic.List[string]'
$encoding = New-Object System.Text.UTF8Encoding($false, $true)
$totalBytes = 0L
$summaryCount = 0
$runCount = 0
$sourceCount = 0
function Add-TextEntry([string]$Name, [string]$Text) {
    $data = $encoding.GetBytes($Text)
    $script:totalBytes += $data.Length
    if ($script:totalBytes -gt 128MB) { throw "Diagnostic text exceeds 128 MiB. Select one run with -RunDir <run folder>." }
    $entries[$Name] = $data
}
function Add-JsonEntry([string]$Name, $Value) { Add-TextEntry $Name ($Value | ConvertTo-Json -Depth 6) }

# Walk explicitly so directory junctions cannot hide game folders outside the selected log tree.
$pending = New-Object 'System.Collections.Generic.Queue[string]'
$pending.Enqueue([IO.Path]::GetFullPath($RunDir))
while ($pending.Count -gt 0) {
    $dir = $pending.Dequeue()
    Assert-NoLinks $dir
    foreach ($child in @(Get-ChildItem -LiteralPath $dir -Directory -Force | Sort-Object Name)) {
        Assert-NoLinks $child.FullName
        $pending.Enqueue($child.FullName)
    }
    $files = @(Get-ChildItem -LiteralPath $dir -File -Force | Where-Object {
        $_.Name -in @('net.log', 'rb_frames.log', 'stdout.txt', 'stderr.txt', 'build_identity.json', 'preflight.json', 'run_info.json')
    })
    if ($files.Count -eq 0) { continue }
    $runCount++
    $prefix = 'runs/{0:D3}' -f $runCount
    foreach ($file in $files) {
        Assert-NoLinks $file.FullName
        if ($file.Name -like '*.json') {
            try {
                $value = Read-SmallJson $file.FullName
                $safe = $null
                if ($file.Name -eq 'build_identity.json') { $safe = Get-SafeIdentity $value }
                elseif ($file.Name -eq 'preflight.json') {
                    $local = Get-SafeIdentity $value.local
                    $peer = Get-SafeIdentity $value.peer
                    if ($local -and [string]$value.status -match '^(ok|failed)$' -and [string]$value.role -match '^(host|join)$') {
                        $reason = [string]$value.reason
                        if ($reason -notmatch '^[a-z_]{0,64}$') { $reason = 'details_omitted' }
                        $safe = [ordered]@{ schema = 1; role = [string]$value.role; status = [string]$value.status;
                            local = $local; peer = $peer; reason = $reason }
                        if ([string]$value.time_utc -match '^\d{4}-\d\d-\d\dT[0-9:.Z+-]{8,32}$') { $safe.time_utc = [string]$value.time_utc }
                        $safe.mismatch_fields = @($value.mismatch_fields | Where-Object {
                            [string]$_ -in @('build_id', 'compiler', 'iso_sha256', 'elf_sha1', 'net', 'strict_hello', 'delay_match')
                        } | ForEach-Object { [string]$_ })
                    }
                } elseif ($file.Name -eq 'run_info.json') {
                    if ([string]$value.side -match '^(host|join)$' -and [string]$value.port -match '^\d{1,5}$') {
                        $safe = [ordered]@{ side = [string]$value.side; port = [int]$value.port }
                        foreach ($key in @('pad', 'sound', 'exit_code')) {
                            if ([string]$value.$key -match '^-?\d{1,10}$') { $safe[$key] = [long]$value.$key }
                        }
                        if ([string]$value.delay -match '^(auto|\d{1,3})$') { $safe.delay = [string]$value.delay }
                        if ($value.diagnostics -is [bool]) { $safe.diagnostics = $value.diagnostics }
                        if ([string]$value.started_utc -match '^\d{4}-\d\d-\d\dT[0-9:.Z+-]{8,32}$') { $safe.started_utc = [string]$value.started_utc }
                    }
                }
                if ($safe) { Add-JsonEntry "$prefix/$($file.Name)" $safe; $sourceCount++ }
                else { $notes.Add("$prefix metadata omitted: invalid fields.") }
            } catch { $notes.Add("$prefix metadata omitted: unreadable or invalid JSON.") }
            continue
        }
        if ($file.Length -gt 64MB) { $notes.Add("$prefix/$($file.Name) omitted: exceeds 64 MiB; collect a shorter run."); continue }
        $reader = $null
        try {
            $reader = New-Object IO.StreamReader($file.FullName, $encoding, $true)
            $text = New-Object Text.StringBuilder
            while ($null -ne ($line = $reader.ReadLine())) {
                $safeLine = Convert-SafeLogLine $line ($file.Name -eq 'net.log')
                if ($null -ne $safeLine) {
                    [void]$text.AppendLine($safeLine)
                    if ($safeLine -match '^\s*NETSUMMARY\b') { $summaryCount++ }
                }
            }
            if ($text.Length -gt 0) { Add-TextEntry "$prefix/$($file.BaseName)_net.txt" $text.ToString(); $sourceCount++ }
        } catch { $notes.Add("$prefix/$($file.Name) omitted: unreadable diagnostic text.") }
        finally { if ($reader) { $reader.Dispose() } }
    }
}
if ($sourceCount -eq 0) { throw "No netplay records or valid build identity found. Select the test's run directory with -RunDir." }
if ($summaryCount -eq 0) { $notes.Add('No NETSUMMARY found. The game may have failed before play or not closed cleanly; send this zip anyway.') }

# No machine name, user name, network adapters, addresses, serial numbers or environment dump.
$facts = [ordered]@{ collected_utc = [DateTime]::UtcNow.ToString('o'); powershell = $PSVersionTable.PSVersion.ToString();
    os_version = [Environment]::OSVersion.VersionString; logical_processors = [Environment]::ProcessorCount;
    is_64bit_os = [Environment]::Is64BitOperatingSystem }
try {
    $facts.cpu = @(Get-CimInstance Win32_Processor | ForEach-Object { [ordered]@{ name = $_.Name; cores = $_.NumberOfCores; logical_processors = $_.NumberOfLogicalProcessors } })
    $facts.gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object { [ordered]@{ name = $_.Name; driver = $_.DriverVersion } })
    $facts.memory_kib = (Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize
} catch { $notes.Add('Some hardware facts unavailable; remaining facts and logs are included.') }
Add-JsonEntry 'pc_facts.json' $facts
Add-TextEntry 'collection.txt' (@("Tekken 4 online test diagnostics", "Source groups: $runCount", "NETSUMMARY records: $summaryCount",
    'Only selected diagnostic records and validated metadata included. Paths and network addresses are redacted.',
    'Raw stdout/stderr, memory cards, game data and pictures are never copied.') + @($notes) -join "`r`n")

if (-not (Test-Path -LiteralPath $OutputDirectory)) { New-Item -ItemType Directory -Path $OutputDirectory | Out-Null }
Assert-NoLinks $OutputDirectory
$zipPath = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('T4-test-logs-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6) + '.zip')
Add-Type -AssemblyName System.IO.Compression
$stream = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew)
$archive = $null
try {
    $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    foreach ($name in $entries.Keys) {
        $entry = $archive.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
        $entryStream = $entry.Open()
        try { $entryStream.Write($entries[$name], 0, $entries[$name].Length) } finally { $entryStream.Dispose() }
    }
} finally { if ($archive) { $archive.Dispose() }; $stream.Dispose() }
foreach ($note in $notes) { Write-Warning $note }
Write-Host ("Test logs: {0}" -f $zipPath)
Write-Host ("Size: {0:N0} bytes; {1} source groups, {2} NETSUMMARY records." -f (Get-Item -LiteralPath $zipPath).Length, $runCount, $summaryCount)
