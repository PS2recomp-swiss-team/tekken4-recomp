# Exercise the actual supervisor with unreadable, byte-unchanged worker sources.
# Run serially: the failure cases briefly hold an exclusive read lock on a tool.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-tree-worker-failure-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $work 'source'
$checks = 0
$runs = 0
$codeNames = @('publish_public_tree.ps1', 'public_tree_worker.ps1',
    'public_tree_scan.ps1', 'public_patch_headers.ps1', 'test_public_tree_worker_failure.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
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

function Get-CodeSnapshot {
    $records = foreach ($name in $script:codeNames) {
        $path = Join-Path $PSScriptRoot $name
        Assert-LocalNoLink $path
        $name + ' ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return [string]::Join("`n", [string[]]$records)
}

function Get-FixtureSnapshot {
    $records = foreach ($file in Get-ChildItem -LiteralPath $script:fixture -Recurse -Force -File | Sort-Object FullName) {
        Assert-LocalNoLink $file.FullName
        $file.FullName.Substring($script:fixture.Length + 1).Replace('\', '/') + ' ' +
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return [string]::Join("`n", [string[]]$records)
}

function Invoke-Entry([string]$Label, [string]$ExportOut) {
    $payload = @{ Entry=$script:entry; Fixture=$script:fixture; Out=$ExportOut } | ConvertTo-Json -Compress
    $data = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
    $command = "`$ProgressPreference='SilentlyContinue'; `$p=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$data'))|ConvertFrom-Json; if (`$p.Out) { & `$p.Entry -Source `$p.Fixture -Out `$p.Out -TimeoutSeconds 10 } else { & `$p.Entry -ScanOnly `$p.Fixture -TimeoutSeconds 10 }; exit `$LASTEXITCODE"
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
    try {
        Assert-True ($proc.Start()) 'Actual public-tree supervisor did not start.'
        $started = $true
        $script:runs++
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit(25000)) {
            throw 'Test watchdog expired; no refusal or pass was accepted.'
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) {
            throw 'Test output watchdog expired; no result was accepted.'
        }
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        $watch.Stop()
        # Unexpected native errors can contain account or machine metadata.
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stdout.txt')), $out.Replace($script:root, '<working-copy>'))
        $savedErr = ''
        if ($err.Trim()) { $savedErr = 'Nonempty stderr withheld; this entry case failed.' }
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stderr.txt')), $savedErr)
        Assert-True (-not $err.Trim()) 'Actual entry wrote unexpected stderr.'
        Assert-True (-not $out.Contains($script:root)) 'Actual entry disclosed the working-copy path.'
        Assert-True (-not $out.Contains('worker-failure-clean-member')) 'Actual entry disclosed a clean fixture name.'
        Assert-True (-not $out.Contains('Synthetic worker-load fixture')) 'Actual entry disclosed fixture content.'
        Assert-True (-not $out.Contains('PUBLIC_TREE_WORKER_COMPLETED')) 'Internal completion marker escaped the supervisor.'
        Assert-True ((Get-FixtureSnapshot) -ceq $script:fixtureSnapshot) 'Fixture bytes or inventory changed.'
        return [pscustomobject]@{ Code=$proc.ExitCode; Text=$out; Seconds=$watch.Elapsed.TotalSeconds }
    } finally {
        $watch.Stop()
        if ($started -and -not $proc.HasExited) {
            try { $proc.Kill(); $null = $proc.WaitForExit(5000) } catch { }
        }
        $proc.Dispose()
    }
}

function Assert-Refusal($Result) {
    Assert-True ($Result.Code -eq 1) 'Unreadable source did not cause exit 1.'
    Assert-True ($Result.Text.Contains('REFUSED: Public tree input or operation failed.')) 'Unreadable source did not produce the static safe refusal.'
    Assert-True ($Result.Text.Contains('Any staging output is unapproved and retained for owner inspection. Nothing published.')) 'Refusal omitted the staging warning.'
    Assert-True ($Result.Text -notmatch '(?i)scan passed|postwrite|staged \d|SHA256:|SCANNED:|PASS:|process deadline') 'Load failure claimed completion or was only a timeout.'
    Assert-True ($Result.Text -notmatch '(?i)public_tree_worker|public_tree_scan|sharing violation|Access.*denied|exception') 'Load failure exposed native error details.'
}

try {
    foreach ($path in @($entry, $work, $fixture)) { Assert-LocalNoLink $path }
    [void][IO.Directory]::CreateDirectory($fixture)
    [IO.File]::WriteAllText((Join-Path $fixture 'LICENSE'), "Synthetic author notice; GPL-3.0.`n")
    [IO.File]::WriteAllText((Join-Path $fixture 'worker-failure-clean-member.txt'), "Synthetic worker-load fixture with harmless source text.`n")
    $codeSnapshot = Get-CodeSnapshot
    $fixtureSnapshot = Get-FixtureSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'code-snapshot.txt'), $codeSnapshot)
    [IO.File]::WriteAllText((Join-Path $work 'fixture-snapshot.txt'), $fixtureSnapshot)

    $before = Invoke-Entry 'scan-before' ''
    Assert-True ($before.Code -eq 0 -and $before.Text.Contains('Public tree scan passed.')) 'Clean fixture did not scan before load failures.'

    foreach ($name in @('public_tree_worker.ps1', 'public_tree_scan.ps1')) {
        $lockedPath = Join-Path $PSScriptRoot $name
        Assert-LocalNoLink $lockedPath
        $lock = [IO.File]::Open($lockedPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            # A second real open must fail, proving this is an active OS share lock.
            $blocked = $false
            try {
                $probe = [IO.File]::OpenRead($lockedPath)
                $probe.Dispose()
            } catch [IO.IOException] { $blocked = $true }
            Assert-True $blocked 'Exclusive source lock was not effective.'
            $label = [IO.Path]::GetFileNameWithoutExtension($name)
            $scan = Invoke-Entry ($label + '-locked-scan') ''
            Assert-Refusal $scan
            $output = Join-Path $work ($label + '-locked-export')
            $export = Invoke-Entry ($label + '-locked-export') $output
            Assert-Refusal $export
            Assert-True (-not [IO.Directory]::Exists($output) -and -not [IO.File]::Exists($output)) 'Load failure created export staging.'
        } finally { $lock.Dispose() }
        Assert-True ((Get-CodeSnapshot) -ceq $codeSnapshot) 'Source bytes changed during the failure cases.'
    }

    $after = Invoke-Entry 'scan-after' ''
    Assert-True ($after.Code -eq 0 -and $after.Text.Contains('Public tree scan passed.')) 'Unchanged fixture did not scan after source locks were released.'
    $output = Join-Path $work 'export-after'
    $export = Invoke-Entry 'export-after' $output
    Assert-True ($export.Code -eq 0 -and $export.Text.Contains('Postwrite public scan passed.')) 'Unchanged fixture did not export after source locks were released.'
    foreach ($file in Get-ChildItem -LiteralPath $fixture -File) {
        $target = Join-Path $output $file.Name
        Assert-True ([IO.File]::Exists($target)) 'Clean export omitted a source file.'
        Assert-True ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ceq
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) 'Clean export changed source bytes.'
    }
    Assert-True ((Get-CodeSnapshot) -ceq $codeSnapshot) 'Final source hashes changed.'
    Assert-True ((Get-FixtureSnapshot) -ceq $fixtureSnapshot) 'Final input bytes or inventory changed.'
    Write-Output ('PASS: tree worker-load failures; {0} assertions through {1} real entry subprocesses.' -f $checks, $runs)
    Write-Output 'Actual worker/helper read locks caused sanitized scan/export refusals without staging. The unchanged fixture passed before and after.'
    Write-Output ('Evidence: ' + $work.Substring($root.Length + 1).Replace('\', '/'))
    Write-Output 'UNRUN: OS process-start failure, termination-error and outer-watchdog failure branches; independent orphan-process inventory; launcher GUI; Python release tools; build; game; two-PC play. Release remains NO-GO.'
    exit 0
} catch {
    # Do not retain arbitrary native exception text or a machine-specific path.
    Write-Output 'FAIL: tree worker-load failure tests stopped; expected real-entry behavior or unchanged bytes were not proved.'
    Write-Output ('Evidence: ' + $work.Substring($root.Length + 1).Replace('\', '/'))
    exit 1
}
