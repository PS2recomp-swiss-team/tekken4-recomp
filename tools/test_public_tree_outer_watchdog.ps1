# Force the lifecycle test's outer watchdog while its real scanner is observed.
# A child FAIL is expected; this test passes only after independent cleanup checks.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$lifecycle = Join-Path $PSScriptRoot 'test_public_tree_process_lifecycle.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$relativeWork = 'logs/tree-outer-watchdog-' + [guid]::NewGuid().ToString('N')
$work = Join-Path $root $relativeWork
$fixture = Join-Path $work 'control-source'
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = 0
$controls = 0
$failure = 'Setup or actual-entry evidence failed; raw diagnostics withheld.'
$category = New-Object Diagnostics.PerformanceCounterCategory('Process')
$observed = New-Object 'Collections.Generic.List[object]'
$proc = $null
$mainIdentity = $null
$result = $null
$childEvidence = ''
$codeNames = @('publish_public_tree.ps1', 'public_tree_worker.ps1',
    'public_tree_scan.ps1', 'public_patch_headers.ps1',
    'test_public_tree_process_lifecycle.ps1', 'test_public_tree_outer_watchdog.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failure=$Message; throw 'Outer-watchdog assertion failed.' }
    $script:checks++
}

function Assert-LocalNoLink([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($script:root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Test path outside this copy refused.'
    }
    $current=$full
    while ($current.Length -ge $script:root.Length) {
        if ((Test-Path -LiteralPath $current) -and
                ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Linked test path refused.'
        }
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current=[IO.Path]::GetDirectoryName($current)
    }
}

function Get-CodeSnapshot {
    $records=foreach ($name in $script:codeNames) {
        $path=Join-Path $PSScriptRoot $name
        Assert-LocalNoLink $path
        $name + ' ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return [string]::Join("`n", [string[]]$records)
}

function Get-TreeSnapshot([string]$Path) {
    Assert-LocalNoLink $Path
    $records=foreach ($file in Get-ChildItem -LiteralPath $Path -Force -Recurse -File | Sort-Object FullName) {
        Assert-LocalNoLink $file.FullName
        $file.FullName.Substring($Path.Length + 1).Replace('\','/') + ' ' +
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return [string]::Join("`n", [string[]]$records)
}

function Get-ProcessInventory {
    $data=$script:category.ReadCategory()
    $ids=$data['ID Process']; $parents=$data['Creating Process ID']
    if (-not $ids -or -not $parents) { throw 'Independent process counters unavailable.' }
    foreach ($key in $ids.Keys) {
        [pscustomobject]@{ Id=[int]$ids[$key].RawValue; Parent=[int]$parents[$key].RawValue }
    }
}

function Get-Identity([int]$ProcessId) {
    try { $item=[Diagnostics.Process]::GetProcessById($ProcessId) }
    catch [ArgumentException] { return $null }
    try { return [pscustomobject]@{ Id=$item.Id; Start=$item.StartTime.ToUniversalTime().Ticks; Name=$item.ProcessName } }
    catch [InvalidOperationException] { return $null }
    finally { $item.Dispose() }
}

function Stop-ObservedIdentity($Identity) {
    if (-not $Identity) { return }
    $current=Get-Identity $Identity.Id
    if ($current -and $current.Start -eq $Identity.Start) {
        try { $item=[Diagnostics.Process]::GetProcessById($Identity.Id) }
        catch [ArgumentException] { return }
        try {
            if ($item.StartTime.ToUniversalTime().Ticks -eq $Identity.Start -and -not $item.HasExited) {
                $item.Kill()
                if (-not $item.WaitForExit(5000)) { throw 'Observed test-process cleanup unconfirmed.' }
            }
        } finally { $item.Dispose() }
    }
}

function Observe-Descendants($Inventory) {
    # Retain only PID, creation time and parent identity of our own PowerShell
    # descendants. This is emergency cleanup evidence, never a name-based kill.
    $parents=@($script:mainIdentity) + $script:observed.ToArray()
    foreach ($parent in $parents) {
        $parentNow=Get-Identity $parent.Id
        if (-not $parentNow -or $parentNow.Start -ne $parent.Start) { continue }
        foreach ($record in @($Inventory | Where-Object { $_.Parent -eq $parent.Id })) {
            $identity=Get-Identity $record.Id
            if (-not $identity -or $identity.Name -ne 'powershell' -or $identity.Start -lt $parent.Start) { continue }
            if (@($script:observed | Where-Object { $_.Id -eq $identity.Id -and $_.Start -eq $identity.Start }).Count -eq 0) {
                $script:observed.Add([pscustomobject]@{ Id=$identity.Id; Start=$identity.Start; Name=$identity.Name;
                    Parent=$parent.Id; ParentStart=$parent.Start })
            }
        }
    }
}

function New-StartInfo([string]$Command) {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$script:shell
    $info.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
    $info.WorkingDirectory=$script:root
    $info.UseShellExecute=$false
    $info.CreateNoWindow=$true
    $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput=$true
    $info.RedirectStandardError=$true
    return $info
}

function Encode-Value([string]$Value) {
    return "([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('" +
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Value)) + "')))"
}

function Save-Streams([string]$Label, [string]$Text, [string]$ErrorText) {
    $safe=[regex]::Replace($Text, [regex]::Escape($script:root), '<working-copy>',
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stdout.txt')), $safe, $script:utf8)
    $safeError=''
    if ($ErrorText.Trim()) { $safeError='Nonempty stderr withheld; this case failed.' }
    [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stderr.txt')), $safeError, $script:utf8)
}

function Invoke-Control([string]$Label) {
    $command="`$ProgressPreference='SilentlyContinue'; & " + (Encode-Value $script:entry) +
        ' -ScanOnly ' + (Encode-Value $script:fixture) + ' -TimeoutSeconds 10; exit $LASTEXITCODE'
    $control=New-Object Diagnostics.Process
    $control.StartInfo=New-StartInfo $command
    $identity=$null
    try {
        Assert-True ($control.Start()) 'Actual clean scan control did not start.'
        $identity=Get-Identity $control.Id
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $stdout=$control.StandardOutput.ReadToEndAsync(); $stderr=$control.StandardError.ReadToEndAsync()
        $complete=$control.WaitForExit(30000)
        if ($complete) {
            $remaining=[Math]::Max(0,30000 - [int]$clock.ElapsedMilliseconds)
            $complete=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),$remaining)
        }
        Assert-True ($complete -and $clock.ElapsedMilliseconds -le 30000) 'Actual clean scan control exceeded its process/output watchdog.'
        $out=$stdout.GetAwaiter().GetResult(); $err=$stderr.GetAwaiter().GetResult()
        Save-Streams $Label $out $err
        Assert-True ($control.ExitCode -eq 0) 'Actual clean scan control did not exit zero.'
        Assert-True (-not $err.Trim()) 'Actual clean scan control emitted stderr.'
        Assert-True ($out.Contains('Public tree scan passed.')) 'Actual clean scan control did not complete its scan.'
        Assert-True ($out -notmatch '(?i)REFUSED|FAIL:|deadline') 'Actual clean scan control also reported failure.'
        Assert-True (-not $out.Contains($script:root)) 'Actual clean scan control disclosed the working-copy path.'
        Assert-True ((Get-TreeSnapshot $script:fixture) -ceq $script:fixtureBefore) 'Actual clean scan control changed fixture bytes or inventory.'
        Assert-True ((Get-CodeSnapshot) -ceq $script:codeBefore) 'Actual clean scan control changed implementation bytes.'
        $script:controls++
    } finally { Stop-ObservedIdentity $identity; $control.Dispose() }
}

try {
    foreach ($path in @($entry,$lifecycle,$work,$fixture)) { Assert-LocalNoLink $path }
    Assert-True ([IO.File]::Exists($shell)) 'Windows PowerShell is unavailable.'
    $warm=@(Get-ProcessInventory)
    Assert-True (@($warm | Where-Object { $_.Id -eq $PID }).Count -eq 1) 'Independent inventory cannot identify this test process.'
    [void][IO.Directory]::CreateDirectory($fixture)
    [IO.File]::WriteAllText((Join-Path $fixture 'LICENSE'), "Synthetic source notice; GPL-3.0.`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $fixture 'member.txt'), "Harmless outer watchdog control text.`n", $utf8)
    $fixtureBefore=Get-TreeSnapshot $fixture
    $codeBefore=Get-CodeSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'source-before.txt'),$fixtureBefore,$utf8)
    [IO.File]::WriteAllText((Join-Path $work 'code-before.txt'),$codeBefore,$utf8)
    Invoke-Control 'control-before'

    $command="`$ProgressPreference='SilentlyContinue'; & " + (Encode-Value $lifecycle) +
        ' -ExerciseOuterWatchdog; exit $LASTEXITCODE'
    $proc=New-Object Diagnostics.Process
    $proc.StartInfo=New-StartInfo $command
    Assert-True ($proc.Start()) 'Actual lifecycle child did not start.'
    $mainIdentity=Get-Identity $proc.Id
    Assert-True ($null -ne $mainIdentity) 'Actual lifecycle child identity was not captured.'
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $stdout=$proc.StandardOutput.ReadToEndAsync(); $stderr=$proc.StandardError.ReadToEndAsync()
    while (-not $proc.WaitForExit(50)) {
        Assert-True ($clock.ElapsedMilliseconds -lt 90000) 'Outer parent watchdog expired; no child result accepted.'
        Observe-Descendants @(Get-ProcessInventory)
    }
    $remaining=[Math]::Max(0,90000 - [int]$clock.ElapsedMilliseconds)
    Assert-True ([Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),$remaining)) 'Outer parent output watchdog expired; no child result accepted.'
    Assert-True ($clock.ElapsedMilliseconds -le 90000) 'Outer parent deadline expired; no child result accepted.'
    $out=$stdout.GetAwaiter().GetResult(); $err=$stderr.GetAwaiter().GetResult()
    Save-Streams 'expected-child-failure' $out $err
    Assert-True ($proc.ExitCode -eq 1) 'Forced outer-watchdog child did not exit one.'
    Assert-True (-not $err.Trim()) 'Forced outer-watchdog child emitted stderr.'
    Assert-True ($out -match '(?m)^FAIL:.*Outer test watchdog expired; no scanner result accepted\.') 'Forced child did not report the expected outer-watchdog failure.'
    Assert-True ($out -notmatch '(?m)^PASS:') 'Forced child incorrectly claimed a passing lifecycle test.'
    Assert-True (-not $out.Contains($root)) 'Forced child disclosed the working-copy path.'
    $evidenceMatch=[regex]::Match($out,'(?m)^Evidence retained: (logs/tree-process-lifecycle-[0-9a-f]{32})\s*$')
    Assert-True $evidenceMatch.Success 'Forced child omitted its bounded relative evidence path.'
    $childEvidence=$evidenceMatch.Groups[1].Value
    $childWork=Join-Path $root $childEvidence
    Assert-LocalNoLink $childWork
    foreach ($name in @('outer-watchdog.json','outer-watchdog-started.json','outer-watchdog-observed.json',
            'source-snapshot.txt','code-snapshot.txt','source-after.txt','code-after.txt')) {
        $path=Join-Path $childWork $name
        Assert-LocalNoLink $path
        Assert-True ([IO.File]::Exists($path)) 'Forced child omitted required observation or cleanup evidence.'
    }
    $proof=Get-Content -LiteralPath (Join-Path $childWork 'outer-watchdog.json') -Raw | ConvertFrom-Json
    $started=Get-Content -LiteralPath (Join-Path $childWork 'outer-watchdog-started.json') -Raw | ConvertFrom-Json
    $worker=Get-Content -LiteralPath (Join-Path $childWork 'outer-watchdog-observed.json') -Raw | ConvertFrom-Json
    Assert-True ($proof.Triggered -eq $true -and $proof.CleanupConfirmed -eq $true -and $proof.InputsUnchanged -eq $true) 'Forced child did not confirm trigger, cleanup and unchanged inputs.'
    Assert-True ($proof.RealEntries -eq 1 -and $proof.TriggerBudgetMilliseconds -eq 1 -and $proof.StandardBudgetSeconds -eq 150) 'Forced child did not isolate one real entry with its dedicated test budget.'
    Assert-True ($proof.SupervisorId -gt 0 -and $proof.WorkerId -gt 0 -and $proof.SupervisorId -ne $proof.WorkerId) 'Forced child did not record distinct real supervisor and worker identities.'
    Assert-True ($proof.SupervisorId -eq $started.SupervisorId -and $proof.SupervisorStart -eq $started.SupervisorStart) 'Supervisor identity records disagree.'
    Assert-True ($proof.WorkerId -eq $worker.WorkerId -and $proof.WorkerStart -eq $worker.WorkerStart -and $worker.Parent -eq $proof.SupervisorId) 'Actual worker observation or parent linkage is missing.'
    Assert-True ($proof.SupervisorStart -ge $mainIdentity.Start -and $proof.WorkerStart -ge $proof.SupervisorStart) 'Observed identities predate their test-owned parents.'
    foreach ($sample in @(1,2)) {
        $inventory=@(Get-ProcessInventory)
        foreach ($identity in @([pscustomobject]@{Id=$proof.SupervisorId;Start=$proof.SupervisorStart},
                [pscustomobject]@{Id=$proof.WorkerId;Start=$proof.WorkerStart})) {
            $current=Get-Identity $identity.Id
            Assert-True (-not $current -or $current.Start -ne $identity.Start) 'Independent parent sample still finds an observed real-entry identity.'
            if (-not $current) { Assert-True (@($inventory | Where-Object { $_.Id -eq $identity.Id }).Count -eq 0) 'Independent inventory still lists an observed real-entry PID.' }
        }
        if ($sample -eq 1) { Start-Sleep -Milliseconds 100 }
    }
    $childSource=Join-Path $childWork 'source'
    $childBefore=[IO.File]::ReadAllText((Join-Path $childWork 'source-snapshot.txt'))
    $childAfter=[IO.File]::ReadAllText((Join-Path $childWork 'source-after.txt'))
    Assert-True ($childBefore -ceq $childAfter -and (Get-TreeSnapshot $childSource) -ceq $childBefore) 'Independent child-source byte snapshot does not match before and after evidence.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $childWork 'code-snapshot.txt')) -ceq
        [IO.File]::ReadAllText((Join-Path $childWork 'code-after.txt'))) 'Child code evidence changed across the forced watchdog.'
    Assert-True ((Get-CodeSnapshot) -ceq $codeBefore) 'Entry or test implementation changed during the forced watchdog.'
    Invoke-Control 'control-after'
    [IO.File]::WriteAllText((Join-Path $work 'code-after.txt'),(Get-CodeSnapshot),$utf8)
    $result=[pscustomobject]@{ Passed=$true; Controls=$controls; ForcedChildExit=$proc.ExitCode;
        RealEntries=$proof.RealEntries; ChildEvidence=$childEvidence; IndependentAbsenceSamples=2;
        InputsUnchanged=$true; Assertions=$checks; ObservedDescendants=$observed.Count }
} catch {
    $result=[pscustomobject]@{ Passed=$false; Controls=$controls; Failure=$failure; ChildEvidence=$childEvidence; Assertions=$checks }
} finally {
    try {
        foreach ($identity in @($observed | Sort-Object Start -Descending)) { Stop-ObservedIdentity $identity }
        Stop-ObservedIdentity $mainIdentity
    } catch {
        $result=[pscustomobject]@{ Passed=$false; Controls=$controls; Failure='Test-owned process cleanup was not confirmed.'; ChildEvidence=$childEvidence; Assertions=$checks }
    } finally { if ($proc) { $proc.Dispose() } }
}

if ([IO.Directory]::Exists($work)) {
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $work 'summary.json') -Encoding UTF8
}
if (-not $result.Passed) {
    Write-Output ('FAIL: actual tree outer-watchdog regression; ' + $result.Failure)
    Write-Output ('Evidence retained: ' + $relativeWork)
    exit 1
}
Write-Output ('PASS: actual tree outer-watchdog regression; {0} assertions, two clean scan controls and one expected failing lifecycle child.' -f $checks)
Write-Output 'The child observed a real scanner before its forced outer watchdog; two independent parent samples found its recorded supervisor and worker absent.'
Write-Output ('Evidence retained: ' + $relativeWork)
Write-Output 'UNRUN: failed OS termination, interruption inside one write, unobserved descendants, launcher GUI, Python release tools, build, game and two-PC play. Release remains NO-GO.'
exit 0
