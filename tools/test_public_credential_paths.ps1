# Credential path regressions through the real supervised public-tree entry.
# Fixtures contain harmless text only; no credentials or game data are used.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$work = Join-Path $root ('logs/public-credential-paths-' + [guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = 0
$runs = 0
$failures = New-Object 'Collections.Generic.List[string]'
$records = New-Object 'Collections.Generic.List[object]'
$toolNames = @('publish_public_tree.ps1','public_tree_worker.ps1','public_tree_scan.ps1',
    'public_patch_headers.ps1','scan_public_zip.ps1','public_zip_scan_worker.ps1',
    'public_zip_scan.ps1','public_zip_deflate.ps1','test_public_credential_paths.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) { $script:failures.Add($Message) }
}

function Assert-LocalNoLink([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($script:root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Test path outside this copy refused.'
    }
    $current = $full
    while ($current.Length -ge $script:root.Length) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Test path reparse point refused.'
            }
        }
        if ($current.Equals($script:root,[StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-Hash([string]$Path) {
    Assert-LocalNoLink $Path
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ToolSnapshot {
    return [string]::Join("`n",[string[]]@($script:toolNames | ForEach-Object {
        $_ + ' ' + (Get-Hash (Join-Path $PSScriptRoot $_))
    }))
}

function Get-TreeSnapshot([string]$Path) {
    return [string]::Join("`n",[string[]]@(Get-ChildItem -LiteralPath $Path -Recurse -Force |
        Sort-Object FullName | ForEach-Object {
            Assert-LocalNoLink $_.FullName
            $relative = $_.FullName.Substring($Path.Length).Replace('\','/')
            if ($_.PSIsContainer) { 'DIR ' + $relative } else { $relative + ' ' + (Get-Hash $_.FullName) }
        }))
}

function Write-Text([string]$Path) {
    Assert-LocalNoLink $Path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path,"Harmless public source text fixture.`n",$script:utf8)
}

function New-Case([string]$Label,[string]$Relative,[bool]$Empty = $false) {
    $source = Join-Path (Join-Path $script:work $Label) 'source'
    Write-Text (Join-Path $source 'LICENSE')
    $target = Join-Path $source $Relative.Replace('/','\')
    if ($Empty) { Assert-LocalNoLink $target; [void][IO.Directory]::CreateDirectory($target) }
    else { Write-Text $target }
    return [pscustomobject]@{Label=$Label;Source=$source;Relative=$Relative;
        Before=(Get-TreeSnapshot $source);Runs=0}
}

function Invoke-Entry($Case,[string]$Mode) {
    $output = ''
    $entryName = 'publish_public_tree.ps1'
    $archive = ''
    $archiveHash = ''
    $parameters = @{ScanOnly=$Case.Source}
    if ($Mode -in @('export','selected')) {
        $output = Join-Path ([IO.Path]::GetDirectoryName($Case.Source)) ('output-' + $Case.Runs)
        $parameters = @{Source=$Case.Source;Out=$output}
        if ($Mode -eq 'selected') { $parameters.Include = @('LICENSE',$Case.Relative) }
    }
    if ($Mode -eq 'zip') {
        $entryName = 'scan_public_zip.ps1'
        $archive = Join-Path ([IO.Path]::GetDirectoryName($Case.Source)) ('source-' + $Case.Runs + '.zip')
        $file = [IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            $zip = New-Object IO.Compression.ZipArchive($file,[IO.Compression.ZipArchiveMode]::Create,$true)
            try {
                foreach ($item in @(Get-ChildItem -LiteralPath $Case.Source -Recurse -Force)) {
                    Assert-LocalNoLink $item.FullName
                    $name = $item.FullName.Substring($Case.Source.Length + 1).Replace('\','/')
                    if ($item.PSIsContainer) { $null = $zip.CreateEntry($name + '/') }
                    else {
                        $member = $zip.CreateEntry($name,[IO.Compression.CompressionLevel]::NoCompression)
                        $stream = $member.Open()
                        try { $data = [IO.File]::ReadAllBytes($item.FullName); $stream.Write($data,0,$data.Length) }
                        finally { $stream.Dispose() }
                    }
                }
            } finally { $zip.Dispose() }
        } finally { $file.Dispose() }
        $archiveHash = Get-Hash $archive
        $parameters = @{Archive=$archive}
    }
    $inventoryBefore = Get-TreeSnapshot ([IO.Path]::GetDirectoryName($Case.Source))
    # Encode argument data, preserving Include arrays through the actual entry.
    $entryData = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Join-Path $PSScriptRoot $entryName)))
    $argumentData = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((ConvertTo-Json -InputObject $parameters -Compress)))
    $command = "`$ProgressPreference='SilentlyContinue'; `$entry=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$entryData')); `$values=ConvertFrom-Json ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$argumentData'))); `$parameters=@{}; foreach (`$p in `$values.PSObject.Properties) { if (`$p.Name -eq 'Include') { `$parameters[`$p.Name]=[string[]]`$p.Value } else { `$parameters[`$p.Name]=`$p.Value } }; & `$entry @parameters; exit `$LASTEXITCODE"
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $PSHOME 'powershell.exe'
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Actual publisher entry did not start.' }
        $script:runs++
        $Case.Runs++
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(45000)) {
            $process.Kill(); $null = $process.WaitForExit(5000)
            throw 'Publisher test watchdog expired; timeout is not a category refusal.'
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),5000)) {
            throw 'Publisher test output watchdog expired.'
        }
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        $label = $Case.Label + '-' + $Mode + '-' + $Case.Runs
        [IO.File]::WriteAllText((Join-Path $script:work ($label + '.stdout.txt')),$out,$script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($label + '.stderr.txt')),$err,$script:utf8)
        $sourceUnchanged = (Get-TreeSnapshot $Case.Source) -ceq $Case.Before
        $toolsUnchanged = (Get-ToolSnapshot) -ceq $script:toolBefore
        Assert-True (-not $err.Trim()) ($label + ': stderr was not empty.')
        Assert-True $sourceUnchanged ($label + ': source bytes or inventory changed.')
        Assert-True $toolsUnchanged ($label + ': tool bytes changed during the run.')
        if ($Mode -in @('scan','zip')) {
            Assert-True ((Get-TreeSnapshot ([IO.Path]::GetDirectoryName($Case.Source))) -ceq $inventoryBefore) ($label + ': scanner wrote or extracted fixture files.')
        }
        if ($Mode -eq 'zip') {
            Assert-True ((Get-Hash $archive) -ceq $archiveHash) ($label + ': archive bytes changed.')
        }
        $script:records.Add([pscustomobject]@{Label=$label;Exit=$process.ExitCode;EmptyStderr=(-not $err.Trim());
            SourceUnchanged=$sourceUnchanged;ToolsUnchanged=$toolsUnchanged})
        return [pscustomobject]@{Code=$process.ExitCode;Text=$out;Errors=$err;Output=$output}
    } finally { $process.Dispose() }
}

function Test-Control($Case,[string]$Mode) {
    $result = Invoke-Entry $Case $Mode
    Assert-True ($result.Code -eq 0) ($Case.Label + ': clean control refused.')
    Assert-True ($result.Text -match 'scan passed|PASS: limited public-source') ($Case.Label + ': clean control did not complete the actual scan.')
    if ($Mode -eq 'zip') {
        Assert-True ($result.Text.Contains('SCANNED:')) ($Case.Label + ': ZIP scan completion marker missing.')
    }
    if ($Mode -eq 'export' -and [IO.Directory]::Exists($result.Output)) {
        Assert-True ((Get-TreeSnapshot $result.Output) -ceq $Case.Before) ($Case.Label + ': clean staged bytes or inventory differ.')
    }
}

function Test-Refusal($Case,[string]$Mode,[string]$Canary) {
    $result = Invoke-Entry $Case $Mode
    Assert-True ($result.Code -eq 1) ($Case.Label + '-' + $Mode + ': expected refusal exit 1.')
    Assert-True ($result.Text.Contains('key or credential filename')) ($Case.Label + '-' + $Mode + ': credential path category was not reached.')
    Assert-True ($result.Text -notmatch 'scan passed|PASS: limited public-source') ($Case.Label + '-' + $Mode + ': refused entry claimed a scan pass.')
    foreach ($private in @($Canary,$Case.Source,$script:root)) {
        Assert-True (-not ($result.Text + $result.Errors).Contains($private)) ($Case.Label + '-' + $Mode + ': diagnostic disclosed a path canary.')
    }
    if ($Mode -in @('export','selected')) {
        Assert-True (-not (Test-Path -LiteralPath $result.Output)) ($Case.Label + '-' + $Mode + ': export created staging before refusing.')
    }
}

try {
    Assert-LocalNoLink $work
    [void][IO.Directory]::CreateDirectory($work)
    Add-Type -AssemblyName System.IO.Compression
    $toolBefore = Get-ToolSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'tools-before.txt'),$toolBefore,$utf8)
    $control = New-Case 'clean-control' 'docs/ordinary.txt'
    foreach ($mode in @('scan','export','selected','zip')) { Test-Control $control $mode }
    $index = 0
    foreach ($component in @('sample.key','sample.keys','sample.pem','sample.p12','sample.pfx','sample.kdbx',
            '.env','id_rsa','id_ed25519','credentials','keys')) {
        $case = New-Case ('credential-directory-' + $index) ($component + '/ordinary.txt')
        foreach ($mode in @('scan','export')) { Test-Refusal $case $mode $component }
        $index++
    }
    # Selecting a descendant file must not bypass checks of its ancestors.
    $nested = New-Case 'selected-descendant' 'docs/CrEdEnTiAlS/deeper/ordinary.txt'
    foreach ($mode in @('scan','export','selected','zip')) { Test-Refusal $nested $mode 'CrEdEnTiAlS' }
    $nestedSuffix = New-Case 'nested-suffix' 'docs/sample.pem/deeper/ordinary.txt'
    Test-Refusal $nestedSuffix 'zip' 'sample.pem'
    foreach ($component in @('empty.pem','credentials')) {
        $case = New-Case ('empty-directory-' + $index) $component $true
        foreach ($mode in @('scan','zip')) { Test-Refusal $case $mode $component }
        $index++
    }
    # Ordinary binary-looking suffixes are still allowed for directories.
    $safe = New-Case 'safe-directory' 'ordinary.bin/ordinary.txt'
    foreach ($mode in @('scan','export')) { Test-Control $safe $mode }
    foreach ($mode in @('scan','export','selected','zip')) { Test-Control $control $mode }
    $toolAfter = Get-ToolSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'tools-after.txt'),$toolAfter,$utf8)
    Assert-True ($toolBefore -ceq $toolAfter) 'Final source tool snapshot changed.'
    $summary = [pscustomobject]@{Assertions=$checks;ActualEntryRuns=$runs;Failures=$failures.ToArray();
        Results=$records.ToArray();ToolsUnchanged=($toolBefore -ceq $toolAfter)}
    [IO.File]::WriteAllText((Join-Path $work 'summary.json'),(ConvertTo-Json -InputObject $summary -Depth 5),$utf8)
    [IO.File]::WriteAllLines((Join-Path $work 'failures.txt'),[string[]]$failures,$utf8)
    Write-Output ('Credential path entry tests: {0} assertions; {1} actual publisher/ZIP entries; {2} failures.' -f $checks,$runs,$failures.Count)
    Write-Output ('Evidence: logs/' + [IO.Path]::GetFileName($work) + '/')
    foreach ($failure in $failures) { Write-Output ('FAIL: ' + $failure) }
    Write-Output 'UNRUN: Python packagers, launcher GUI, build, game and two-PC play. No release approval.'
    if ($failures.Count) { exit 1 }
    exit 0
} catch {
    Write-Output 'FAIL: credential path tests stopped; required fixture, source or actual entry operation failed.'
    Write-Output ('Evidence: logs/' + [IO.Path]::GetFileName($work) + '/')
    Write-Output 'UNRUN: Python packagers, launcher GUI, build, game and two-PC play. No release approval.'
    exit 1
}
