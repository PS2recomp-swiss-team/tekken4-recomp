# Observe the actual tree entry's worker independently through process counters.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/tree-process-lifecycle-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $work 'source'
$checks = 0
$runs = 0
$failure = 'Setup or process observation failed; raw diagnostics withheld.'
$category = New-Object Diagnostics.PerformanceCounterCategory('Process')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failure=$Message; throw 'Lifecycle assertion failed.' }
    $script:checks++
}

function Assert-LocalNoLink([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($script:root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Test path outside this copy refused.'
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

function Get-ProcessInventory {
    # One independent bulk snapshot supplies PID and parent PID together. No
    # executable paths, command lines or unrelated process details are retained.
    $data = $script:category.ReadCategory()
    $ids = $data['ID Process']
    $parents = $data['Creating Process ID']
    if (-not $ids -or -not $parents) { throw 'Independent process counters unavailable.' }
    foreach ($key in $ids.Keys) {
        [pscustomobject]@{ Id=[int]$ids[$key].RawValue; Parent=[int]$parents[$key].RawValue }
    }
}

function Get-Identity([int]$ProcessId) {
    try { $observed = [Diagnostics.Process]::GetProcessById($ProcessId) }
    catch [ArgumentException] { return $null }
    try {
        return [pscustomobject]@{ Id=$observed.Id; Start=$observed.StartTime.ToUniversalTime().Ticks; Name=$observed.ProcessName }
    } catch [InvalidOperationException] { return $null
    } finally { $observed.Dispose() }
}

function Stop-ObservedIdentity($Identity) {
    if (-not $Identity) { return }
    $current = Get-Identity $Identity.Id
    if ($current -and $current.Start -eq $Identity.Start) {
        try { $observed = [Diagnostics.Process]::GetProcessById($Identity.Id) }
        catch [ArgumentException] { return }
        try {
            # Cleanup is confined to a process this test started or independently
            # observed as that process's child, with its creation time unchanged.
            if ($observed.StartTime.ToUniversalTime().Ticks -eq $Identity.Start -and -not $observed.HasExited) {
                $observed.Kill()
                if (-not $observed.WaitForExit(5000)) { throw 'Test-owned process cleanup unconfirmed.' }
            }
        } finally { $observed.Dispose() }
    }
}

function Get-CodeSnapshot {
    $records = foreach ($name in @('publish_public_tree.ps1', 'public_tree_worker.ps1',
            'public_tree_scan.ps1', 'public_patch_headers.ps1', 'test_public_tree_process_lifecycle.ps1')) {
        $path = Join-Path $PSScriptRoot $name
        Assert-LocalNoLink $path
        $name + ' ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return [string]::Join("`n", [string[]]$records)
}

function Get-TreeSnapshot([string]$Path) {
    $records = foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -Force -File | Sort-Object FullName) {
        Assert-LocalNoLink $file.FullName
        $file.FullName.Substring($Path.Length + 1).Replace('\', '/') + ' ' +
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return [string]::Join("`n", [string[]]$records)
}

function Get-LiveWorkerChildren($Inventory, $Supervisor) {
    foreach ($child in @($Inventory | Where-Object { $_.Parent -eq $Supervisor.Id })) {
        $identity = Get-Identity $child.Id
        if ($identity -and $identity.Name -eq 'powershell' -and $identity.Start -ge $Supervisor.Start) { $identity }
    }
}

function Assert-IndependentAbsence($Supervisor, $Worker) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $absent = $false
    do {
        $inventory = @(Get-ProcessInventory)
        $workerNow = Get-Identity $Worker.Id
        $supervisorNow = Get-Identity $Supervisor.Id
        $children = @(Get-LiveWorkerChildren $inventory $Supervisor)
        $absent = (-not $workerNow -or $workerNow.Start -ne $Worker.Start) -and
            (-not $supervisorNow -or $supervisorNow.Start -ne $Supervisor.Start) -and $children.Count -eq 0
        if (-not $absent) { Start-Sleep -Milliseconds 100 }
    } while (-not $absent -and $watch.Elapsed.TotalSeconds -lt 5)
    Assert-True $absent 'Independent inventory still finds an observed entry identity or direct worker.'
    # Repeat after a fresh sample. Handle release or a supervisor's own message
    # alone never counts as evidence of process absence.
    Start-Sleep -Milliseconds 100
    $inventory = @(Get-ProcessInventory)
    $workerNow = Get-Identity $Worker.Id
    $supervisorNow = Get-Identity $Supervisor.Id
    Assert-True (-not $workerNow -or $workerNow.Start -ne $Worker.Start) 'Observed worker identity reappeared.'
    Assert-True (-not $supervisorNow -or $supervisorNow.Start -ne $Supervisor.Start) 'Observed supervisor identity reappeared.'
    Assert-True (@(Get-LiveWorkerChildren $inventory $Supervisor).Count -eq 0) 'Independent second sample finds a direct worker.'
}

function Invoke-Entry([string]$Label, [bool]$Export, [bool]$Timeout) {
    $outPath = Join-Path $script:work ($Label + '-output')
    Assert-LocalNoLink $outPath
    $payload = @{ Entry=$script:entry; Source=$script:source; Out=$outPath; Export=$Export; Limit='120' }
    if ($Timeout) { $payload.Limit='2' }
    $data = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($payload | ConvertTo-Json -Compress)))
    $command = "`$ProgressPreference='SilentlyContinue'; `$p=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$data'))|ConvertFrom-Json; if (`$p.Export) { & `$p.Entry -Source `$p.Source -Out `$p.Out -Include @('LICENSE','members') -TimeoutSeconds `$p.Limit } else { & `$p.Entry -ScanOnly `$p.Source -TimeoutSeconds `$p.Limit }; exit `$LASTEXITCODE"
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
    $workerIdentity = $null
    $supervisorIdentity = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-True ($proc.Start()) 'Actual tree supervisor did not start.'
        $script:runs++
        $supervisorIdentity = Get-Identity $proc.Id
        Assert-True ($null -ne $supervisorIdentity) 'Actual supervisor identity was not captured.'
        [pscustomobject]@{ SupervisorId=$supervisorIdentity.Id; SupervisorStart=$supervisorIdentity.Start } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:work ($Label + '-started.json')) -Encoding UTF8
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        while (-not $proc.WaitForExit(50)) {
            if ($watch.Elapsed.TotalSeconds -ge 150) {
                $script:failure='Outer test watchdog expired; no scanner result accepted.'
                throw 'Lifecycle watchdog failed.'
            }
            $inventory = @(Get-ProcessInventory)
            foreach ($child in @($inventory | Where-Object { $_.Parent -eq $proc.Id })) {
                $identity = Get-Identity $child.Id
                if (-not $identity) { continue }
                # Windows may also create a console host. Scope this proof to
                # the independently parent-linked PowerShell scanner worker.
                if ($identity.Name -ne 'powershell') { continue }
                Assert-True ($identity.Start -ge $supervisorIdentity.Start) 'Child predates its observed supervisor identity.'
                if ($workerIdentity) {
                    Assert-True ($workerIdentity.Id -eq $identity.Id -and $workerIdentity.Start -eq $identity.Start) 'Actual supervisor started multiple worker identities.'
                } else {
                    $workerIdentity=$identity
                    [pscustomobject]@{ WorkerId=$workerIdentity.Id; WorkerStart=$workerIdentity.Start; Parent=$proc.Id } |
                        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:work ($Label + '-observed.json')) -Encoding UTF8
                }
            }
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) {
            $script:failure='Test output watchdog expired; no scanner result accepted.'
            throw 'Lifecycle output watchdog failed.'
        }
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stdout.txt')), $out.Replace($script:root, '<working-copy>'))
        $savedErr = ''
        if ($err.Trim()) { $savedErr='Nonempty stderr withheld; this case failed.' }
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stderr.txt')), $savedErr)
        Assert-True (-not $err.Trim()) 'Actual tree entry emitted unexpected stderr.'
        Assert-True (-not $out.Contains($script:root)) 'Actual tree entry disclosed a working-copy path.'
        Assert-True ($null -ne $workerIdentity) 'Independent inventory never observed the actual worker; absence is unproved.'
        Assert-IndependentAbsence $supervisorIdentity $workerIdentity
        if ($Timeout) {
            Assert-True ($proc.ExitCode -eq 1 -and $out -match 'REFUSED:.*process deadline') 'Actual tree entry did not report its deadline refusal.'
            Assert-True ($out -notmatch '(?i)termination was not confirmed|scan passed|postwrite|SCANNED:|PASS:|SHA256:|STAGED:') 'Timed-out entry claimed completion or unconfirmed termination.'
            Assert-True ($out -match 'staging.*unapproved.*retained') 'Timeout omitted retained-staging warning.'
        } else {
            Assert-True ($proc.ExitCode -eq 0 -and $out -match 'public scan passed|Public tree scan passed') 'Actual complete control did not pass.'
            if ($Export) { Assert-True ((Get-TreeSnapshot $outPath) -ceq $script:sourceSnapshot) 'Complete actual export differs from source bytes or inventory.' }
        }
        # Interrupted output is retained; no incomplete export is approved.
        if ($Timeout -and [IO.Directory]::Exists($outPath)) {
            foreach ($file in Get-ChildItem -LiteralPath $outPath -Recurse -File) {
                $relative = $file.FullName.Substring($outPath.Length + 1)
                $original = Join-Path $script:source $relative
                Assert-True ([IO.File]::Exists($original)) 'Partial export contains an unexpected file.'
                $originalBytes=[IO.File]::ReadAllBytes($original)
                $partialBytes=[IO.File]::ReadAllBytes($file.FullName)
                Assert-True ($partialBytes.Length -le $originalBytes.Length) 'Partial export is longer than its source.'
                $prefixMatches=$true
                for ($index=0; $index -lt $partialBytes.Length; $index++) {
                    if ($partialBytes[$index] -ne $originalBytes[$index]) { $prefixMatches=$false; break }
                }
                Assert-True $prefixMatches 'Partial export differs from its source byte prefix.'
            }
        }
        Assert-True ((Get-TreeSnapshot $script:source) -ceq $script:sourceSnapshot) 'Actual entry changed source inventory or bytes.'
        Assert-True ((Get-CodeSnapshot) -ceq $script:codeSnapshot) 'Lifecycle implementation or entry helpers changed during test.'
        [pscustomobject]@{ Label=$Label; Exit=$proc.ExitCode; SupervisorId=$supervisorIdentity.Id;
            SupervisorStart=$supervisorIdentity.Start; WorkerId=$workerIdentity.Id; WorkerStart=$workerIdentity.Start;
            WorkerParent=$supervisorIdentity.Id; IndependentAbsence=$true; Seconds=$watch.Elapsed.TotalSeconds } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:work ($Label + '.json')) -Encoding UTF8
    } finally {
        try { Stop-ObservedIdentity $workerIdentity } finally {
            try { Stop-ObservedIdentity $supervisorIdentity } finally { $proc.Dispose(); $watch.Stop() }
        }
    }
}

try {
    foreach ($path in @($entry, $work, $source)) { Assert-LocalNoLink $path }
    # Prewarm the independent inventory before any timed real entry begins.
    $warm = @(Get-ProcessInventory)
    Assert-True (@($warm | Where-Object { $_.Id -eq $PID }).Count -eq 1) 'Independent inventory does not identify the test process.'
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'members'))
    [IO.File]::WriteAllText((Join-Path $source 'LICENSE'), "Synthetic author notice; GPL-3.0.`n")
    for ($number=0; $number -lt 1000; $number++) {
        [IO.File]::WriteAllText((Join-Path $source ('members/member-{0:d4}.txt' -f $number)), "Harmless source text for real entry lifecycle checks.`n")
    }
    $sourceSnapshot=Get-TreeSnapshot $source
    $codeSnapshot=Get-CodeSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'source-snapshot.txt'), $sourceSnapshot)
    [IO.File]::WriteAllText((Join-Path $work 'code-snapshot.txt'), $codeSnapshot)
    Invoke-Entry 'scan-before' $false $false
    Invoke-Entry 'export-before' $true $false
    Invoke-Entry 'scan-timeout-1' $false $true
    Invoke-Entry 'scan-timeout-2' $false $true
    Invoke-Entry 'export-timeout-1' $true $true
    Invoke-Entry 'export-timeout-2' $true $true
    Invoke-Entry 'scan-after' $false $false
    Invoke-Entry 'export-after' $true $false
    Assert-True ((Get-CodeSnapshot) -ceq $codeSnapshot) 'Final entry/helper hashes changed.'
    Write-Output ('PASS: actual tree process lifecycle; {0} assertions through {1} real entries.' -f $checks, $runs)
    Write-Output 'Independent parent-PID inventory observed every worker; two post-exit samples found each observed identity absent.'
    Write-Output 'This does not force termination errors or the outer watchdog, or prove absence of unobserved descendants.'
    Write-Output ('Evidence: logs/' + [IO.Path]::GetFileName($work))
    exit 0
} catch {
    Write-Output (('FAIL: actual tree process lifecycle after {0} assertions / {1} real entries; ' -f $checks, $runs) + $failure)
    Write-Output ('Evidence retained: logs/' + [IO.Path]::GetFileName($work))
    exit 1
}
