# Kill the independently observed real worker, then require a safe refusal.
# This tests abnormal worker exit, not failed termination or a test watchdog.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/tree-worker-interrupt-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $work 'source'
$checks = 0
$runs = 0
$failure = 'Setup or independent process observation failed; raw diagnostics withheld.'
$category = New-Object Diagnostics.PerformanceCounterCategory('Process')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failure=$Message; throw 'Worker-interruption assertion failed.' }
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
    if (-not $Identity) { return $false }
    $current = Get-Identity $Identity.Id
    if ($current -and $current.Start -eq $Identity.Start) {
        $observed = [Diagnostics.Process]::GetProcessById($Identity.Id)
        try {
            if ($observed.StartTime.ToUniversalTime().Ticks -eq $Identity.Start -and -not $observed.HasExited) {
                $observed.Kill()
                if (-not $observed.WaitForExit(5000)) { throw 'Observed process termination was not confirmed.' }
                return $true
            }
        } finally { $observed.Dispose() }
    }
    return $false
}

function Get-CodeSnapshot {
    $records = foreach ($name in @('publish_public_tree.ps1', 'public_tree_worker.ps1',
            'public_tree_scan.ps1', 'public_patch_headers.ps1', 'test_public_tree_worker_interrupt.ps1')) {
        $path = Join-Path $PSScriptRoot $name
        Assert-LocalNoLink $path
        $name + ' ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return [string]::Join("`n", [string[]]$records)
}

function Get-TreeSnapshot([string]$Path) {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $Path -Recurse -Force |
        Sort-Object FullName | ForEach-Object {
            Assert-LocalNoLink $_.FullName
            $name = $_.FullName.Substring($Path.Length + 1).Replace('\', '/')
            if ($_.PSIsContainer) { 'DIR ' + $name }
            else { $name + ' ' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }))
}

function Invoke-Entry([string]$Label, [bool]$Export, [bool]$Interrupt) {
    $outPath = Join-Path $script:work ($Label + '-output')
    Assert-LocalNoLink $outPath
    $payload = @{ Entry=$script:entry; Source=$script:source; Out=$outPath; Export=$Export }
    $data = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($payload | ConvertTo-Json -Compress)))
    $command = "`$ProgressPreference='SilentlyContinue'; `$p=ConvertFrom-Json ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$data'))); if (`$p.Export) { & `$p.Entry -Source `$p.Source -Out `$p.Out -TimeoutSeconds 30 } else { & `$p.Entry -ScanOnly `$p.Source -TimeoutSeconds 30 }; exit `$LASTEXITCODE"
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
    $supervisor = $null
    $worker = $null
    $killed = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-True ($proc.Start()) 'Actual supervisor did not start.'
        $script:runs++
        $supervisor = Get-Identity $proc.Id
        Assert-True ($null -ne $supervisor) 'Supervisor creation identity was not captured.'
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        while (-not $proc.WaitForExit(25)) {
            if ($watch.Elapsed.TotalSeconds -gt 45) { throw 'Test watchdog expired; no result accepted.' }
            foreach ($child in @(Get-ProcessInventory | Where-Object { $_.Parent -eq $supervisor.Id })) {
                $identity = Get-Identity $child.Id
                if (-not $identity -or $identity.Name -ne 'powershell') { continue }
                Assert-True ($identity.Start -ge $supervisor.Start) 'Observed worker predates supervisor.'
                if ($worker) {
                    Assert-True ($worker.Id -eq $identity.Id -and $worker.Start -eq $identity.Start) 'Supervisor started multiple workers.'
                } else { $worker=$identity }
                if ($Interrupt -and -not $killed) {
                    # Both parent linkage and creation identity are observed
                    # before terminating this test-owned direct child only.
                    $killed = Stop-ObservedIdentity $worker
                    Assert-True $killed 'Observed worker exited or changed before actual termination.'
                }
            }
        }
        Assert-True ([Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) 'Output watchdog expired.'
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stdout.txt')), $out.Replace($script:root, '<working-copy>'))
        $savedErr = ''
        if ($err.Trim()) { $savedErr='Nonempty stderr withheld; this case failed.' }
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stderr.txt')), $savedErr)
        Assert-True (-not $err.Trim()) 'Actual entry wrote unexpected stderr.'
        Assert-True (-not $out.Contains($script:root)) 'Actual entry disclosed its working-copy path.'
        Assert-True ($null -ne $worker) 'Independent counters did not observe a worker; absence is unproved.'
        foreach ($sample in @(1, 2)) {
            $inventory = @(Get-ProcessInventory)
            $workerNow = Get-Identity $worker.Id
            $supervisorNow = Get-Identity $supervisor.Id
            Assert-True (-not $workerNow -or $workerNow.Start -ne $worker.Start) 'Observed worker remains alive.'
            Assert-True (-not $supervisorNow -or $supervisorNow.Start -ne $supervisor.Start) 'Observed supervisor remains alive.'
            $liveChildren = @($inventory | Where-Object { $_.Parent -eq $supervisor.Id } | ForEach-Object {
                $childNow = Get-Identity $_.Id
                if ($childNow -and $childNow.Name -eq 'powershell' -and $childNow.Start -ge $supervisor.Start) { $childNow }
            })
            Assert-True ($liveChildren.Count -eq 0) 'A direct PowerShell worker remains alive.'
            Start-Sleep -Milliseconds 100
        }
        if ($Interrupt) {
            Assert-True $killed 'Worker interruption was not performed.'
            Assert-True ($proc.ExitCode -eq 1) 'Abnormal worker exit did not refuse with exit 1.'
            Assert-True ($out.Contains('REFUSED: Public tree input or operation failed.')) 'Abnormal worker exit lost its static refusal.'
            Assert-True ($out.Contains('Any staging output is unapproved and retained for owner inspection. Nothing published.')) 'Refusal omitted retained-staging warning.'
            Assert-True ($out.Contains('UNRUN: Python packagers')) 'Refusal omitted unrun limits.'
            Assert-True ($out -notmatch '(?i)scan passed|postwrite|SCANNED:|SHA256:|PUBLIC_TREE_WORKER_COMPLETED|process deadline|exception|worker-interrupt-canary') 'Abnormal worker exit leaked details or claimed completion/deadline.'
        } else {
            Assert-True ($proc.ExitCode -eq 0 -and $out -match 'public scan passed|Public tree scan passed') 'Complete control failed.'
            if ($Export) { Assert-True ((Get-TreeSnapshot $outPath) -ceq $script:sourceSnapshot) 'Complete export changed selected bytes or inventory.' }
        }
        Assert-True ((Get-TreeSnapshot $script:source) -ceq $script:sourceSnapshot) 'Source bytes or inventory changed.'
        Assert-True ((Get-CodeSnapshot) -ceq $script:codeSnapshot) 'Test, supervisor or helper bytes changed.'
        [pscustomobject]@{ Label=$Label; Exit=$proc.ExitCode; SupervisorId=$supervisor.Id;
            SupervisorStart=$supervisor.Start; WorkerId=$worker.Id; WorkerStart=$worker.Start;
            WorkerParent=$supervisor.Id; ExternalTermination=$killed; IndependentAbsence=$true } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:work ($Label + '.json')) -Encoding UTF8
    } finally {
        try { $null = Stop-ObservedIdentity $worker } finally {
            try { $null = Stop-ObservedIdentity $supervisor } finally { $proc.Dispose(); $watch.Stop() }
        }
    }
}

try {
    foreach ($path in @($entry, $work, $source)) { Assert-LocalNoLink $path }
    Assert-True (@(Get-ProcessInventory | Where-Object { $_.Id -eq $PID }).Count -eq 1) 'Independent inventory cannot identify this test.'
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'members'))
    [IO.File]::WriteAllText((Join-Path $source 'LICENSE'), "Synthetic author notice; GPL-3.0.`n")
    for ($number=0; $number -lt 100; $number++) {
        [IO.File]::WriteAllText((Join-Path $source ('members/member-{0:d3}.txt' -f $number)), "Harmless worker-interrupt-canary source text.`n")
    }
    $sourceSnapshot=Get-TreeSnapshot $source
    $codeSnapshot=Get-CodeSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'source-snapshot.txt'), $sourceSnapshot)
    [IO.File]::WriteAllText((Join-Path $work 'code-snapshot.txt'), $codeSnapshot)
    Invoke-Entry 'scan-before' $false $false
    Invoke-Entry 'export-before' $true $false
    Invoke-Entry 'scan-interrupted' $false $true
    Invoke-Entry 'export-interrupted' $true $true
    Invoke-Entry 'scan-after' $false $false
    Invoke-Entry 'export-after' $true $false
    Write-Output ('PASS: actual tree abnormal worker exit; {0} assertions through {1} real entries.' -f $checks, $runs)
    Write-Output 'Independent parent-PID/creation identities scoped worker termination; scan/export refused and unchanged controls passed before and after.'
    Write-Output 'Two post-exit samples found observed supervisor/worker identities absent; unobserved descendants remain unproved.'
    Write-Output ('Evidence: logs/' + [IO.Path]::GetFileName($work))
    Write-Output 'UNRUN: failed termination and outer test watchdog branches; Python release tools; launcher GUI; build; game; two-PC play. Release remains NO-GO.'
    exit 0
} catch {
    Write-Output (('FAIL: actual tree worker interruption after {0} assertions / {1} real entries; ' -f $checks, $runs) + $failure)
    Write-Output ('Evidence retained: logs/' + [IO.Path]::GetFileName($work))
    exit 1
}
