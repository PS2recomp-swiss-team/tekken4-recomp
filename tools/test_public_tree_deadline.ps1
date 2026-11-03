# Exercise the actual tree scan entry with unchanged harmless source fixtures.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-tree-deadline-' + [guid]::NewGuid().ToString('N'))
$fixtures = Join-Path $work 'fixtures'
$checks = 0
$runs = 0

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
            throw 'Linked test input refused.'
        }
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function New-CleanTree([string]$Name, [int]$Count) {
    $path = Join-Path $script:fixtures $Name
    Assert-LocalNoLink $path
    [void][IO.Directory]::CreateDirectory($path)
    [IO.File]::WriteAllText((Join-Path $path 'LICENSE'), "Synthetic author notice; GPL-3.0.`n")
    for ($index = 0; $index -lt $Count; $index++) {
        $file = Join-Path $path ('deadline-member-{0:d4}.txt' -f $index)
        [IO.File]::WriteAllText($file, "Harmless source text for a real tree scan.`n")
    }
    return $path
}

function Get-Snapshot {
    $records = foreach ($file in Get-ChildItem -LiteralPath $script:fixtures -Recurse -Force -File | Sort-Object FullName) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked fixture refused.' }
        $relative = $file.FullName.Substring($script:fixtures.Length + 1).Replace('\', '/')
        $relative + ' ' + (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return [string]::Join("`n", [string[]]$records)
}

function Get-CodeSnapshot {
    $records = foreach ($name in @('publish_public_tree.ps1', 'public_tree_worker.ps1',
            'public_tree_scan.ps1', 'public_patch_headers.ps1', 'test_public_tree_deadline.ps1')) {
        $path = Join-Path $PSScriptRoot $name
        Assert-LocalNoLink $path
        if (-not [IO.File]::Exists($path)) { throw 'Required tree deadline source is missing.' }
        $name + ' ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return [string]::Join("`n", [string[]]$records)
}

function Assert-ReleasedInputs([string]$Path) {
    foreach ($file in Get-ChildItem -LiteralPath $Path -File -Recurse) {
        $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $stream.Dispose()
        Assert-True $true 'Exclusive input reopen completed.'
    }
}

function Invoke-Entry([string]$Path, [AllowNull()][object]$Limit, [string]$Label, [string]$ExportOut) {
    $before = Get-Snapshot
    # Values travel as data, including a deliberately empty deadline value.
    $payload = @{ Entry=$script:entry; Path=$Path; Limit=$Limit; HasLimit=($null -ne $Limit); ExportOut=$ExportOut } | ConvertTo-Json -Compress
    $data = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
    $command = "`$ProgressPreference='SilentlyContinue'; `$p=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$data'))|ConvertFrom-Json; `$a=@{}; if (`$p.ExportOut) { `$a.Source=`$p.Path; `$a.Out=`$p.ExportOut } else { `$a.ScanOnly=`$p.Path }; if (`$p.HasLimit) { `$a.TimeoutSeconds=`$p.Limit }; & `$p.Entry @a; exit `$LASTEXITCODE"
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
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-True ($proc.Start()) 'Real public-tree supervisor did not start.'
        $script:runs++
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        while (-not $proc.WaitForExit(100)) {
            if ($watch.Elapsed.TotalSeconds -ge 150) {
                $proc.Kill()
                $null = $proc.WaitForExit(5000)
                throw 'Test watchdog expired; this is a failed test, never a scanner refusal.'
            }
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 5000)) {
            throw 'Test output watchdog expired; no scanner result was accepted.'
        }
        $watch.Stop()
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        # A failed native entry can include host/account metadata in CLIXML.
        # Keep its presence as evidence without retaining that private text.
        $savedOut = $out.Replace($script:root, '<working-copy>')
        $savedErr = ''
        if ($err.Trim()) { $savedErr = 'Nonempty stderr withheld; this entry case failed.' }
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stdout.txt')), $savedOut)
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stderr.txt')), $savedErr)
        Assert-True (-not $err.Trim()) 'Real public-tree supervisor wrote unexpected stderr.'
        Assert-True (-not $out.Contains($script:root)) 'Real entry disclosed the working-copy path.'
        Assert-True (-not $out.Contains('deadline-member-')) 'Real entry disclosed a clean fixture name.'
        Assert-True (-not $out.Contains('Harmless source text')) 'Real entry disclosed fixture content.'
        Assert-True ((Get-Snapshot) -ceq $before) 'Real entry changed fixture bytes or inventory.'
        Assert-ReleasedInputs $Path
        return [pscustomobject]@{ Code=$proc.ExitCode; Text=$out; Seconds=$watch.Elapsed.TotalSeconds }
    } finally { $watch.Stop(); $proc.Dispose() }
}

try {
    foreach ($path in @($entry, $work, $fixtures)) { Assert-LocalNoLink $path }
    [void][IO.Directory]::CreateDirectory($fixtures)
    $codeSnapshot = Get-CodeSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'code-snapshot.txt'), $codeSnapshot)
    $clean = New-CleanTree 'clean' 1
    $many = New-CleanTree 'many' 1000
    $initial = Get-Snapshot
    [IO.File]::WriteAllText((Join-Path $work 'fixture-snapshot.txt'), $initial)
    foreach ($case in @(@($clean, 'clean-default'), @($many, 'many-default'))) {
        $result = Invoke-Entry $case[0] $null $case[1]
        Assert-True ($result.Code -eq 0 -and $result.Text -match 'Public tree scan passed\.') 'Valid default-budget scan did not complete and pass.'
    }
    foreach ($number in @(1, 2)) {
        $result = Invoke-Entry $many '1' ('timeout-' + $number)
        Assert-True ($result.Code -eq 1) 'Short process deadline did not refuse.'
        Assert-True ($result.Text -match '(?i)REFUSED:.*process deadline') 'Short deadline did not report a timeout refusal.'
        Assert-True ($result.Text -notmatch '(?i)scan passed|postwrite|staged \d|SHA256:|SCANNED:|PASS:') 'Timed-out scan claimed completion.'
        Assert-True ($result.Seconds -lt 15) 'One-second deadline took at least fifteen seconds through the actual entry.'
    }
    $result = Invoke-Entry $many $null 'many-after-timeouts'
    Assert-True ($result.Code -eq 0 -and $result.Text -match 'Public tree scan passed\.') 'The unchanged timed-out tree did not complete afterward.'
    $exportOut = Join-Path $work 'deadline-export'
    $result = Invoke-Entry $many '1' 'export-timeout' $exportOut
    Assert-True ($result.Code -eq 1 -and $result.Text -match '(?i)REFUSED:.*process deadline') 'Real export did not report the one-second timeout refusal.'
    Assert-True ($result.Text -notmatch '(?i)scan passed|postwrite|staged \d|SHA256:|SCANNED:|PASS:') 'Timed-out export claimed completion.'
    Assert-True ($result.Text -match '(?i)staging.*unapproved.*retained') 'Timed-out export omitted the retained staging warning.'
    Assert-True ($result.Seconds -lt 15) 'One-second export deadline took at least fifteen seconds.'
    # A deadline can interrupt preflight or a write. Never delete partial staging.
    # Any files it did write must match the unchanged clean source bytes.
    if ([IO.Directory]::Exists($exportOut)) {
        foreach ($file in Get-ChildItem -LiteralPath $exportOut -File -Recurse) {
            $relative = $file.FullName.Substring($exportOut.Length + 1)
            $sourceFile = Join-Path $many $relative
            Assert-True ([IO.File]::Exists($sourceFile)) 'Timed-out export created an unexpected file.'
            Assert-True ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ceq
                (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash) 'Timed-out export wrote differing bytes.'
        }
    }
    $result = Invoke-Entry $clean '600' 'upper-bound'
    Assert-True ($result.Code -eq 0 -and $result.Text -match 'Public tree scan passed\.') 'Valid upper-bound deadline did not scan clean content.'
    foreach ($case in @(@('0','zero'), @('601','over'), @('-1','negative'), @('1.5','fraction'), @('no','nonnumeric'), @('','empty'))) {
        $result = Invoke-Entry $clean $case[0] ('invalid-' + $case[1])
        Assert-True ($result.Code -eq 1) 'Invalid deadline was accepted.'
        Assert-True ($result.Text -match 'REFUSED:.*TimeoutSeconds.*1.*600') 'Invalid deadline omitted the sanitized bound refusal.'
        Assert-True ($result.Text -notmatch '(?i)scan passed|postwrite|staged \d|SHA256:|SCANNED:|PASS:') 'Invalid deadline reached scan completion.'
    }
    Assert-True ((Get-Snapshot) -ceq $initial) 'Final fixture bytes or inventory changed.'
    Assert-True ((Get-CodeSnapshot) -ceq $codeSnapshot) 'Deadline implementation changed during the entry tests.'
    Write-Output ('PASS: tree scan process deadline; {0} assertions through {1} real entry subprocesses.' -f $checks, $runs)
    Write-Output 'The same unchanged many-file tree passed before and after two genuine one-second deadline refusals.'
    Write-Output 'The real export route also refused at one second; write-phase interruption was not forced.'
    Write-Output ('Evidence: ' + $work.Substring($root.Length + 1).Replace('\', '/'))
    Write-Output 'Exclusive input reopen ran after every child. It does not prove independent orphan-process absence.'
    Write-Output 'UNRUN: outer-watchdog failure branches, launcher GUI, Python release tools, build, game and two-PC play. Release remains NO-GO.'
    exit 0
} catch {
    Write-Output ('FAIL: tree scan deadline tests: ' + $_.Exception.Message)
    exit 1
}
