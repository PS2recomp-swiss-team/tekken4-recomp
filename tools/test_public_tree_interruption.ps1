# Force the real export deadline during incomplete staging, without worker hooks.
# Timing is calibrated from a complete control; inability to force it fails.
# This locates interruption in the write loop or its path checks, not necessarily
# inside one stream.Write call. Small files may all have complete retained bytes.
[CmdletBinding()]
param()

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$relativeWork = 'logs/public-tree-interruption-' + [Guid]::NewGuid().ToString('N')
$work = Join-Path $root $relativeWork
$source = Join-Path $work 'source'
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = 0
$runs = 0
$failure = 'Interruption test preflight failed.'
$selectedCount = 1501

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failure = $Message; throw 'Interruption assertion failed.' }
    $script:checks++
}

function Assert-LocalNoLink([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($script:root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Outside test path refused.'
    }
    $current = $full
    while ($current.Length -ge $script:root.Length) {
        if ((Test-Path -LiteralPath $current) -and
                ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Linked test path refused.'
        }
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-TreeSnapshot([string]$Path) {
    Assert-LocalNoLink $Path
    $pending = New-Object 'Collections.Generic.Stack[string]'
    $pending.Push($Path)
    $items = New-Object 'Collections.Generic.List[object]'
    while ($pending.Count) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            # Check a directory before descending, and avoid repeatedly walking
            # unchanged fixture ancestors for every inventory/hash comparison.
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked fixture refused.' }
            $items.Add($item)
            if ($item.PSIsContainer) { $pending.Push($item.FullName) }
        }
    }
    return [string]::Join("`n", [string[]]@($items | Sort-Object FullName | ForEach-Object {
            $name = $_.FullName.Substring($Path.Length + 1).Replace('\', '/')
            if ($_.PSIsContainer) { 'DIR ' + $name }
            else { $name + ' ' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }))
}

function Get-CodeSnapshot {
    return [string]::Join("`n", [string[]]@(foreach ($name in @(
            'publish_public_tree.ps1', 'public_tree_worker.ps1', 'public_tree_scan.ps1',
            'public_patch_headers.ps1', 'test_public_tree_interruption.ps1')) {
        $path = Join-Path $PSScriptRoot $name
        Assert-LocalNoLink $path
        $name + ' ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }))
}

function Invoke-RealExport([string]$Out, [int]$Limit, [string]$Label) {
    Assert-LocalNoLink $Out
    $payload = @{ Entry=$script:entry; Source=$script:source; Out=$Out; Limit=$Limit } | ConvertTo-Json -Compress
    $data = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
    $command = "`$ProgressPreference='SilentlyContinue'; `$p=ConvertFrom-Json ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$data'))); & `$p.Entry -Source `$p.Source -Out `$p.Out -TimeoutSeconds `$p.Limit; exit `$LASTEXITCODE"
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    $started = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $firstWrite = $null
    $allWritten = $null
    try {
        if (-not $proc.Start()) { throw 'Entry did not start.' }
        $started = $true
        $script:runs++
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        while (-not $proc.WaitForExit(50)) {
            if ([IO.Directory]::Exists($Out)) {
                $count = [IO.Directory]::GetFiles($Out, '*', [IO.SearchOption]::AllDirectories).Length
                if ($count -gt 0 -and $null -eq $firstWrite) { $firstWrite = $watch.Elapsed.TotalSeconds }
                if ($count -eq $script:selectedCount -and $null -eq $allWritten) { $allWritten = $watch.Elapsed.TotalSeconds }
            }
            if ($watch.Elapsed.TotalSeconds -gt 330) {
                $script:failure = 'Outer watchdog expired; failed test, not a proven entry refusal. Descendant absence is unproved.'
                throw 'Entry watchdog expired.'
            }
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) {
            $script:failure = 'Outer output watchdog expired; no entry result accepted.'
            throw 'Output watchdog expired.'
        }
        $result = [pscustomobject]@{
            Code=$proc.ExitCode; Text=$stdout.GetAwaiter().GetResult(); ErrorText=$stderr.GetAwaiter().GetResult()
            Seconds=$watch.Elapsed.TotalSeconds; FirstWrite=$firstWrite; AllWritten=$allWritten; Limit=$Limit
        }
        $safeOutput = [regex]::Replace($result.Text, [regex]::Escape($script:root), '<working-copy>',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $safeError = ''
        if (-not [string]::IsNullOrWhiteSpace($result.ErrorText)) { $safeError = 'Nonempty stderr withheld.' }
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '-stdout.txt')), $safeOutput, $script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '-stderr.txt')), $safeError, $script:utf8)
        $result | Select-Object Code, Seconds, FirstWrite, AllWritten, Limit | ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $script:work ($Label + '-timing.json')) -Encoding UTF8
        Assert-True ([string]::IsNullOrWhiteSpace($result.ErrorText)) 'Actual entry emitted stderr.'
        Assert-True ($result.Text -notmatch [regex]::Escape($script:root)) 'Actual entry disclosed the working-copy path.'
        Assert-True ($result.Text.Contains('UNRUN: Python packagers')) 'Actual entry lost its unrun limitation.'
        return $result
    } finally {
        if ($started -and -not $proc.HasExited) {
            try { $proc.Kill(); $null = $proc.WaitForExit(5000) } catch { }
        }
        $watch.Stop()
        $proc.Dispose()
    }
}

function Assert-Control($Result, [string]$Out, [string]$Snapshot) {
    Assert-True ($Result.Code -eq 0) 'Fresh complete export did not exit zero.'
    Assert-True ($Result.Text.Contains(('Staged {0} files;' -f $script:selectedCount))) 'Fresh export lost its full selection count.'
    Assert-True ($Result.Text.Contains('Postwrite public scan passed.')) 'Fresh export did not complete its postwrite scan.'
    Assert-True ($Result.Text -notmatch 'REFUSED|process deadline') 'Fresh export reported refusal.'
    Assert-True ((Get-TreeSnapshot $Out) -ceq $Snapshot) 'Complete export changed selected bytes or inventory.'
}

function Assert-PartialBytes([string]$Out) {
    $files = @(Get-ChildItem -LiteralPath $Out -Recurse -Force -File)
    Assert-True ($files.Count -gt 0 -and $files.Count -lt $script:selectedCount) 'Deadline did not interrupt a nonempty incomplete write selection.'
    foreach ($file in $files) {
        Assert-LocalNoLink $file.FullName
        $name = $file.FullName.Substring($Out.Length + 1)
        $original = Join-Path $script:source $name
        Assert-True ([IO.File]::Exists($original)) 'Interrupted export created an unselected file.'
        [byte[]]$expected = [IO.File]::ReadAllBytes($original)
        [byte[]]$actual = [IO.File]::ReadAllBytes($file.FullName)
        Assert-True ($actual.Length -le $expected.Length) 'Interrupted file exceeds the selected source length.'
        $same = $true
        for ($index = 0; $index -lt $actual.Length; $index++) {
            if ($actual[$index] -ne $expected[$index]) { $same = $false; break }
        }
        Assert-True $same 'Retained interrupted bytes differ from the source prefix.'
    }
    return $files.Count
}

try {
    foreach ($path in @($entry, $work, $source)) { Assert-LocalNoLink $path }
    Assert-True ([IO.File]::Exists($shell)) 'Windows PowerShell is unavailable.'
    [void][IO.Directory]::CreateDirectory($source)
    [IO.File]::WriteAllText((Join-Path $source 'LICENSE'), "Synthetic source notice; GPL-3.0.`n", $utf8)
    # Separate harmless subdirectories widen the real write window. No sleeps,
    # replacement worker, process suspension or production fault hooks are used.
    for ($index = 0; $index -lt $selectedCount - 1; $index++) {
        $directory = Join-Path $source ('member-{0:d4}' -f $index)
        [void][IO.Directory]::CreateDirectory($directory)
        [IO.File]::WriteAllText((Join-Path $directory 'text.txt'), "Harmless export interruption fixture.`n", $utf8)
    }
    $sourceBefore = Get-TreeSnapshot $source
    $codeBefore = Get-CodeSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'source-before.txt'), $sourceBefore, $utf8)
    [IO.File]::WriteAllText((Join-Path $work 'code-before.txt'), $codeBefore, $utf8)
    $out = Join-Path $work 'control-before'
    $control = Invoke-RealExport $out 300 'control-before'
    Assert-Control $control $out $sourceBefore
    Assert-True ($null -ne $control.FirstWrite -and $null -ne $control.AllWritten) 'Control write window was not observed.'
    # Parent process startup precedes the supervisor clock. Bounded adjustment
    # below handles that offset and scheduling noise; only partial writes pass.
    $limit = [Math]::Max(1, [int][Math]::Floor(($control.FirstWrite + $control.AllWritten) / 2))
    $observations = @()
    foreach ($round in @(1, 2)) {
        $partial = $false
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            Assert-True ($limit -ge 1 -and $limit -le 300) 'Calibration deadline escaped its bounds.'
            $label = 'interruption-{0}-attempt-{1}' -f $round, $attempt
            $out = Join-Path $work $label
            $result = Invoke-RealExport $out $limit $label
            $count = 0
            if ([IO.Directory]::Exists($out)) { $count = [IO.Directory]::GetFiles($out, '*', [IO.SearchOption]::AllDirectories).Length }
            $observations += [pscustomobject]@{ Round=$round; Attempt=$attempt; Limit=$limit; Code=$result.Code; StagedFiles=$count }
            $observations | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $work 'attempts.json') -Encoding UTF8
            Assert-True ((Get-TreeSnapshot $source) -ceq $sourceBefore) 'Deadline changed source bytes or inventory.'
            # A faster completed calibration attempt is retained as a control,
            # never as interruption coverage. Try a shorter bounded deadline.
            if ($result.Code -eq 0) {
                Assert-Control $result $out $sourceBefore
                $limit--
                continue
            }
            Assert-True ($result.Code -eq 1 -and $result.Text.Contains('REFUSED: Public tree operation exceeded its process deadline.')) 'Calibrated export did not report a confirmed worker deadline.'
            Assert-True ($result.Text -notmatch '(?i)termination was not confirmed|scan passed|Staged [0-9]+ files|PUBLIC_TREE_WORKER_COMPLETED') 'Timed-out export claimed completion or unconfirmed termination.'
            Assert-True ($result.Text.Contains('Any staging output is unapproved and retained')) 'Deadline lost the retained-output warning.'
            if ($count -gt 0 -and $count -lt $selectedCount) { $partial = $true; break }
            if ($count -eq 0) { $limit++ } else { $limit-- }
        }
        Assert-True $partial 'Bounded calibration could not force a write-phase interruption; coverage remains unproved.'
        $retainedCount = Assert-PartialBytes $out
        $partialBefore = Get-TreeSnapshot $out
        $retry = Invoke-RealExport $out 30 ('retry-' + $round)
        Assert-True ($retry.Code -eq 1 -and $retry.Text.Contains('REFUSED: Public tree input or operation failed.')) 'Retry did not refuse retained incomplete staging.'
        Assert-True ($retry.Text -notmatch '(?i)scan passed|Staged [0-9]+ files|process deadline') 'Retry claimed completion or timed out.'
        Assert-True ((Get-TreeSnapshot $out) -ceq $partialBefore) 'Retry changed retained interrupted staging.'
        Write-Output ('Observed incomplete-staging deadline {0}: {1} of {2} files retained; deadline {3} seconds.' -f $round, $retainedCount, $selectedCount, $limit)
    }
    $out = Join-Path $work 'control-after'
    Assert-Control (Invoke-RealExport $out 300 'control-after') $out $sourceBefore
    Assert-True ((Get-TreeSnapshot $source) -ceq $sourceBefore) 'Final source bytes or inventory changed.'
    Assert-True ((Get-CodeSnapshot) -ceq $codeBefore) 'Implementation or test source changed during entry tests.'
    Write-Output ('PASS: export write interruption; {0} assertions through {1} real entry subprocesses.' -f $checks, $runs)
    Write-Output ('Evidence: ' + $relativeWork)
    Write-Output 'Partial output is retained and unapproved. Complete before/after exports used the same unchanged source.'
    Write-Output 'Not exercised by this suite: OS process-start failure, termination-error and outer-watchdog failure branches. Independent orphan-process absence is unproved.'
    Write-Output 'UNRUN: launcher GUI; Python release tools; build; game; two-PC play. Release remains NO-GO.'
    exit 0
} catch {
    Write-Output ('FAIL: export write interruption: ' + $failure)
    Write-Output ('Evidence: ' + $relativeWork)
    exit 1
}
