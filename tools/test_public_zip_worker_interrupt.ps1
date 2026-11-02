# Interrupt the actual ZIP worker after observing its identity and input lock.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/zip-worker-interrupt-' + [guid]::NewGuid().ToString('N'))
$fixtures = Join-Path $work 'fixtures'
$checks = 0
$runs = 0
$failure = 'Operation failed; native diagnostic withheld.'
$identities = New-Object 'Collections.Generic.List[object]'
$category = New-Object Diagnostics.PerformanceCounterCategory('Process')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failure = $Message; throw 'Assertion failed.' }
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
            throw 'Linked test input refused.'
        }
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FixtureInventory {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $script:fixtures -Recurse -Force |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:fixtures.Length) }))
}

function New-StoredZip([string]$Name, [int]$Count) {
    # abc has standard CRC-32 352441c2. Members are ordinary harmless text.
    $path = Join-Path $script:fixtures $Name
    Assert-LocalNoLink $path
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = New-Object IO.BinaryWriter($stream)
    $records = New-Object 'Collections.Generic.List[object]'
    try {
        for ($index = 0; $index -lt $Count; $index++) {
            $nameBytes = [Text.Encoding]::ASCII.GetBytes(('interrupt-member-{0:d4}.txt' -f $index))
            $records.Add([pscustomobject]@{ Name=$nameBytes; Offset=[uint32]$stream.Position })
            $writer.Write([uint32]0x04034b50)
            foreach ($value in @(20,0,0,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]0x352441c2)
            $writer.Write([uint32]3)
            $writer.Write([uint32]3)
            $writer.Write([uint16]$nameBytes.Length)
            $writer.Write([uint16]0)
            $writer.Write([byte[]]$nameBytes)
            $writer.Write([byte[]]@(97,98,99))
        }
        $central = [uint32]$stream.Position
        foreach ($record in $records) {
            $writer.Write([uint32]0x02014b50)
            foreach ($value in @(20,20,0,0,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]0x352441c2)
            $writer.Write([uint32]3)
            $writer.Write([uint32]3)
            $writer.Write([uint16]$record.Name.Length)
            foreach ($value in @(0,0,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]0)
            $writer.Write([uint32]$record.Offset)
            $writer.Write([byte[]]$record.Name)
        }
        $centralSize = [uint32]($stream.Position - $central)
        $writer.Write([uint32]0x06054b50)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)
        $writer.Write([uint16]$Count)
        $writer.Write([uint16]$Count)
        $writer.Write([uint32]$centralSize)
        $writer.Write([uint32]$central)
        $writer.Write([uint16]0)
    } finally { $writer.Dispose() }
    return $path
}

function Get-Children([int]$ParentId) {
    # One bulk counter snapshot supplies numeric PID/parent pairs. No command
    # lines, executable paths or unrelated process details are recorded.
    $data = $script:category.ReadCategory()
    $ids = $data['ID Process']
    $parents = $data['Creating Process ID']
    foreach ($key in $ids.Keys) {
        if ([int]$parents[$key].RawValue -eq $ParentId) {
            [int]$ids[$key].RawValue
        }
    }
}

function Test-SameProcess([int]$ProcessId, [long]$StartTicks) {
    $candidate = $null
    try {
        try { $candidate = [Diagnostics.Process]::GetProcessById($ProcessId) }
        catch [ArgumentException] { return $false }
        if ($candidate.HasExited) { return $false }
        return $candidate.StartTime.ToUniversalTime().Ticks -eq $StartTicks
    } finally { if ($candidate) { $candidate.Dispose() } }
}

function Assert-ReviewedSources {
    foreach ($source in $script:sources) {
        Assert-True ((Get-Hash (Join-Path $PSScriptRoot $source)) -ceq $script:hashes[$source]) 'Reviewed source bytes changed between actual entry cases.'
    }
}

function Invoke-Entry([string]$Path, [int]$Limit, [string]$Label, [bool]$Interrupt) {
    Assert-ReviewedSources
    Assert-True ((Get-Hash $Path) -ceq $script:fixtureHash) 'Input archive changed between actual entry cases.'
    Assert-True ((Get-FixtureInventory) -ceq $script:fixtureInventory) 'Fixture inventory changed between actual entry cases.'
    $beforeHash = Get-Hash $Path
    $beforeInventory = Get-FixtureInventory
    $pathData = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Path))
    $entryData = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script:entry))
    $command = "`$ProgressPreference='SilentlyContinue'; `$entry=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$entryData')); `$archive=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$pathData')); & `$entry -Archive `$archive -TimeoutSeconds $Limit; exit `$LASTEXITCODE"
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    $observed = @{}
    $interrupted = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $started = $false
    try {
        Assert-True ($proc.Start()) 'Actual scanner supervisor did not start.'
        $started = $true
        $script:runs++
        $supervisorTicks = $proc.StartTime.ToUniversalTime().Ticks
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        while (-not $proc.HasExited) {
            foreach ($childId in @(Get-Children $proc.Id)) {
                if ($observed.ContainsKey($childId)) { continue }
                $child = $null
                try {
                    try { $child = [Diagnostics.Process]::GetProcessById($childId) }
                    catch [ArgumentException] { continue }
                    if ($child.HasExited) { continue }
                    # Windows may also create a console host. The production
                    # entry's scanner worker is its direct PowerShell child.
                    if ($child.ProcessName -ine 'powershell') { continue }
                    $ticks = $child.StartTime.ToUniversalTime().Ticks
                    Assert-True ($ticks -ge $supervisorTicks -and $ticks -le [DateTime]::UtcNow.Ticks) 'Worker identity is outside the supervisor creation window.'
                    $observed[$childId] = $ticks
                    $captured = @(foreach ($observedId in $observed.Keys) {
                        [pscustomobject]@{ SupervisorPid=$proc.Id; SupervisorStartTicks=$supervisorTicks
                            WorkerPid=$observedId; WorkerStartTicks=[long]$observed[$observedId]; ParentPid=$proc.Id }
                    })
                    [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.observed.json')), ($captured | ConvertTo-Json))
                } finally { if ($child) { $child.Dispose() } }
            }
            if ($Interrupt -and -not $interrupted -and $observed.Count -eq 1) {
                # The OS share violation proves the real worker has entered its
                # input read/scan, rather than merely having been created.
                $locked = $false
                $probe = $null
                try {
                    $probe = [IO.File]::Open($Path, [IO.FileMode]::Open,
                        [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                } catch [IO.IOException] { $locked = $true }
                finally { if ($probe) { $probe.Dispose() } }
                if ($locked) {
                    $workerId = [int]@($observed.Keys)[0]
                    $workerTicks = [long]$observed[$workerId]
                    Assert-True (Test-SameProcess $workerId $workerTicks) 'Observed worker exited before its real interruption.'
                    $worker = [Diagnostics.Process]::GetProcessById($workerId)
                    try {
                        Assert-True ($worker.StartTime.ToUniversalTime().Ticks -eq $workerTicks) 'Worker identity changed before interruption.'
                        $worker.Kill()
                        Assert-True ($worker.WaitForExit(5000)) 'Interrupted worker did not exit.'
                    } finally { $worker.Dispose() }
                    $interrupted = $true
                }
            }
            if ($watch.Elapsed.TotalSeconds -ge 150) {
                $script:failure = 'Test watchdog expired; never a scanner refusal or passing test.'
                throw 'Test watchdog expired.'
            }
            [void]$proc.WaitForExit(25)
        }
        $remaining = [Math]::Max(0, 150000 - [int]$watch.ElapsedMilliseconds)
        Assert-True ([Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), $remaining)) 'Test output watchdog expired; never a scanner refusal or passing test.'
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stdout.txt')), $out.Replace($script:root, '<working-copy>'))
        $savedError = ''
        if ($err.Trim()) { $savedError = 'Unexpected stderr withheld; test fails.' }
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stderr.txt')), $savedError)
        Assert-True ($observed.Count -eq 1) 'Exactly one actual worker was not independently observed.'
        Assert-True (-not $err.Trim()) 'Actual entry wrote unexpected stderr.'
        Assert-True (-not $out.Contains($script:root)) 'Actual entry disclosed the working-copy path.'
        Assert-True (-not $out.Contains('interrupt-member-')) 'Actual entry disclosed a member name.'
        if ($Interrupt) {
            Assert-True $interrupted 'Real worker input lock and interruption were not observed.'
            Assert-True ($proc.ExitCode -eq 1) 'Unexpected worker exit did not refuse.'
            Assert-True ($out.Contains('REFUSED: ZIP input or scan failed.')) 'Unexpected worker exit omitted its safe refusal.'
            Assert-True ($out.Contains('UNRUN: Python packagers and release payload checks; launcher GUI; build; game; two-PC play.')) 'Refusal omitted its limits.'
            Assert-True ($out -notmatch 'PASS:|SCANNED:|SHA256:|REFUSED: member|process deadline|termination') 'Unexpected worker exit claimed completion or only timed out.'
            Assert-True ($out -notmatch '(?i)public_zip_scan_worker|sharing violation|exception|access.*denied') 'Refusal exposed native details.'
        } else {
            Assert-True (-not $interrupted) 'Complete control worker was interrupted.'
            Assert-True ($proc.ExitCode -eq 0) 'Actual complete scan did not succeed.'
            Assert-True ($out -match 'PASS: limited public-source ZIP content scan only\.') 'Actual complete scan omitted its pass.'
            Assert-True ($out -match ('SHA256: ' + $beforeHash)) 'Actual scan omitted the exact archive identity.'
            Assert-True ($out -match 'SCANNED:') 'Actual complete scan omitted completion.'
        }
        # Check identity independently of the supervisor's termination message.
        foreach ($childId in @($observed.Keys)) {
            $ticks = [long]$observed[$childId]
            for ($attempt = 0; $attempt -lt 3; $attempt++) {
                Assert-True (-not (Test-SameProcess $childId $ticks)) 'Observed actual worker remains alive after its supervisor returned.'
                Start-Sleep -Milliseconds 100
            }
            $script:identities.Add([pscustomobject]@{
                Case=$Label; SupervisorPid=$proc.Id; SupervisorStartTicks=$supervisorTicks
                WorkerPid=$childId; WorkerStartTicks=$ticks; ParentPid=$proc.Id
                WorkerAbsentChecks=3; Interrupted=$interrupted; InputLockObserved=$interrupted; ExitCode=$proc.ExitCode
            })
        }
        Assert-True (-not (Test-SameProcess $proc.Id $supervisorTicks)) 'Actual supervisor remains alive after returning.'
        Assert-True ((Get-Hash $Path) -ceq $beforeHash) 'Actual entry changed its input archive.'
        Assert-True ((Get-FixtureInventory) -ceq $beforeInventory) 'Actual entry extracted or changed fixture inventory.'
        $exclusive = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $exclusive.Dispose()
        Assert-True $true 'Input archive exclusive reopen completed.'
        Assert-ReviewedSources
    } finally {
        # Cleanup is limited to observed PID/start-time identities belonging to
        # this test. A watchdog/cleanup failure still fails the test.
        foreach ($childId in @($observed.Keys)) {
            if (Test-SameProcess $childId ([long]$observed[$childId])) {
                $child = [Diagnostics.Process]::GetProcessById($childId)
                try {
                    if ($child.StartTime.ToUniversalTime().Ticks -eq [long]$observed[$childId]) {
                        $child.Kill(); [void]$child.WaitForExit(5000)
                    }
                } finally { $child.Dispose() }
            }
        }
        if ($started -and -not $proc.HasExited) { $proc.Kill(); [void]$proc.WaitForExit(5000) }
        $watch.Stop()
        $proc.Dispose()
    }
}

try {
    foreach ($path in @($entry, $work, $fixtures)) { Assert-LocalNoLink $path }
    [void][IO.Directory]::CreateDirectory($fixtures)
    $many = New-StoredZip 'many-members.zip' 1000
    $fixtureHash = Get-Hash $many
    $fixtureInventory = Get-FixtureInventory
    $sources = @('scan_public_zip.ps1','public_zip_scan_worker.ps1','public_zip_scan.ps1',
        'public_zip_deflate.ps1','public_tree_scan.ps1','public_patch_headers.ps1',
        'test_public_zip_worker_interrupt.ps1')
    $hashes = @{}
    foreach ($source in $sources) { $hashes[$source] = Get-Hash (Join-Path $PSScriptRoot $source) }
    [IO.File]::WriteAllText((Join-Path $work 'source-hashes.json'), ($hashes | ConvertTo-Json))
    # Warm the bulk counter API before the interruption cases start, and
    # prove that its parent relation identifies this test's real child later.
    $null = @(Get-Children $PID)
    Invoke-Entry $many 120 'complete-before' $false
    Invoke-Entry $many 120 'interrupt-one' $true
    Invoke-Entry $many 120 'interrupt-two' $true
    Invoke-Entry $many 120 'complete-after' $false
    foreach ($source in $sources) {
        Assert-True ((Get-Hash (Join-Path $PSScriptRoot $source)) -ceq $hashes[$source]) 'Reviewed source bytes changed during actual entry tests.'
    }
    [IO.File]::WriteAllText((Join-Path $work 'identities.json'), ($identities.ToArray() | ConvertTo-Json -Depth 4))
    [IO.File]::WriteAllText((Join-Path $work 'source-hashes.json'), ($hashes | ConvertTo-Json))
    Write-Output ('PASS: ZIP worker interruption; {0} assertions through {1} real scanner entries.' -f $checks, $runs)
    Write-Output 'Observed direct worker identities are absent after completion and two real mid-scan interruptions.'
    Write-Output 'Unchanged ordinary ZIP passed before and after; no extraction or source mutation.'
    Write-Output ('Evidence: ' + $work.Substring($root.Length + 1).Replace('\', '/'))
    Write-Output 'UNRUN: forced termination errors, outer watchdog failure, every possible descendant, launcher GUI, Python release tools, build, game and two-PC play. Release remains NO-GO.'
    exit 0
} catch {
    Write-Output ('FAIL: ZIP worker interruption: ' + $failure)
    exit 1
}
