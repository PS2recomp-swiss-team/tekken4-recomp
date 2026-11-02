# URI privacy regressions through the real tree, export and ZIP entries.
# Fixtures contain reserved synthetic hostnames and ordinary text only.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$work = Join-Path $root ('logs/public-uri-schemes-' + [guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = 0
$runs = 0
$failures = New-Object 'Collections.Generic.List[string]'
$records = New-Object 'Collections.Generic.List[object]'
$toolNames = @('publish_public_tree.ps1','public_tree_worker.ps1','public_tree_scan.ps1',
    'public_patch_headers.ps1','scan_public_zip.ps1','public_zip_scan_worker.ps1',
    'public_zip_scan.ps1','public_zip_deflate.ps1','test_public_uri_schemes.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) { $script:failures.Add($Message) }
}

function Assert-LocalNoLink([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($script:root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'URI test path outside this copy refused.'
    }
    $current = $full
    while ($current.Length -ge $script:root.Length) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'URI test reparse point refused.'
            }
        }
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ToolSnapshot {
    return [string]::Join("`n", [string[]]@($script:toolNames | ForEach-Object {
        $path = Join-Path $PSScriptRoot $_
        Assert-LocalNoLink $path
        $_ + ' ' + (Get-Hash $path)
    }))
}

function Write-Text([string]$Path, [string]$Text) {
    Assert-LocalNoLink $Path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, $script:utf8)
}

function Write-Archive([string]$Source, [string]$Archive) {
    Assert-LocalNoLink $Archive
    $file = [IO.File]::Open($Archive, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($name in @('LICENSE','fixture.txt')) {
                $member = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::NoCompression)
                $stream = $member.Open()
                try {
                    $data = [IO.File]::ReadAllBytes((Join-Path $Source $name))
                    $stream.Write($data,0,$data.Length)
                } finally { $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
}

function Invoke-Entry([string]$Source, [string]$Archive, [string]$Label, [string]$Mode) {
    $entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
    $parameters = @('-ScanOnly', $Source)
    $output = Join-Path $script:work ($Label + '-output')
    if ($Mode -eq 'export') { $parameters = @('-Source', $Source, '-Out', $output) }
    elseif ($Mode -eq 'zip') {
        $entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
        $parameters = @('-Archive', $Archive)
    }
    foreach ($value in @($entry) + $parameters) {
        if ($value.Contains('"')) { throw 'Unsupported quote in URI test argument.' }
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $PSHOME 'powershell.exe'
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $entry + '" ' +
        [string]::Join(' ', [string[]]@($parameters | ForEach-Object { '"' + $_ + '"' }))
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Real publisher entry did not start.' }
        $script:runs++
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(45000)) {
            $process.Kill()
            $null = $process.WaitForExit(5000)
            throw 'URI test watchdog expired; this is not a scanner refusal.'
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),5000)) {
            throw 'URI test output collection expired.'
        }
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        Write-Text (Join-Path $script:work ($Label + '.stdout.txt')) $out
        Write-Text (Join-Path $script:work ($Label + '.stderr.txt')) $err
        $script:records.Add([pscustomobject]@{label=$Label; mode=$Mode; exitCode=$process.ExitCode; stderrEmpty=(-not $err.Trim())})
        return [pscustomobject]@{Code=$process.ExitCode; Text=$out; Errors=$err; Output=$output}
    } finally { $process.Dispose() }
}

try {
    Assert-LocalNoLink $work
    [void][IO.Directory]::CreateDirectory($work)
    Add-Type -AssemblyName System.IO.Compression
    $before = Get-ToolSnapshot
    Write-Text (Join-Path $work 'tools-before.txt') $before
    $hostName = 'fixture' + '.invalid'
    # The baseline scanner accepts this size. Larger dotted text has a
    # separately retained, pre-existing regex-limit refusal; do not mask it.
    $longClean = ('a.' * 1000) + ('b-' * 1000)
    $cases = @(
        @{Name='https-approved'; Value=('https'+'://'+'www.gnu.org'+'/licenses/).'); Allowed=$true},
        @{Name='ftp'; Value=('f'+'tp'+'://'+$hostName+'/source'); Allowed=$false},
        @{Name='ftp-approved-host'; Value=('f'+'tp'+'://'+'www.gnu.org'+'/source'); Allowed=$false},
        @{Name='ftp-leading-dot'; Value=('.'+'f'+'tp'+'://'+$hostName+'/source'); Allowed=$false},
        @{Name='ssh-leading-plus'; Value=('+'+'s'+'sh'+'://'+$hostName+'/source'); Allowed=$false},
        @{Name='ssh-mixed'; Value=('S'+'sH'+'://'+$hostName+'/source'); Allowed=$false},
        @{Name='git-ssh'; Value=('git'+'+ssh'+'://'+$hostName+'/source'); Allowed=$false},
        @{Name='file'; Value=('fi'+'le'+'://'+$hostName+'/source'); Allowed=$false},
        @{Name='custom'; Value=('custom'+'-1.2'+'://'+$hostName+'/source'); Allowed=$false},
        @{Name='https-unreviewed'; Value=('https'+'://'+$hostName+'/source'); Allowed=$false},
        @{Name='long-clean'; Value=$longClean; Allowed=$true},
        @{Name='long-clean-uri'; Value=($longClean + "`n" + 'https'+'://'+'www.gnu.org'+'/licenses/'); Allowed=$true},
        @{Name='http-approved'; Value=('http'+'://'+'www.gnu.org'+'/licenses/'); Allowed=$true}
    )
    foreach ($case in $cases) {
        $source = Join-Path $work ($case.Name + '-source')
        Write-Text (Join-Path $source 'LICENSE') "Harmless public author notice; GPL-3.0.`n"
        Write-Text (Join-Path $source 'fixture.txt') ($case.Value + "`n")
        $licenseHash = Get-Hash (Join-Path $source 'LICENSE')
        $fixtureHash = Get-Hash (Join-Path $source 'fixture.txt')
        $archive = Join-Path $work ($case.Name + '-source.zip')
        Write-Archive $source $archive
        $archiveHash = Get-Hash $archive
        foreach ($mode in @('tree','export','zip')) {
            $label = $case.Name + '-' + $mode
            $result = Invoke-Entry $source $archive $label $mode
            Assert-True (-not $result.Errors.Trim()) ($label + ': stderr was not empty.')
            Assert-True ((Get-Hash (Join-Path $source 'LICENSE')) -ceq $licenseHash) ($label + ': input notice changed.')
            Assert-True ((Get-Hash (Join-Path $source 'fixture.txt')) -ceq $fixtureHash) ($label + ': URI input changed.')
            Assert-True ((Get-Hash $archive) -ceq $archiveHash) ($label + ': ZIP input changed.')
            Assert-True ((Get-ToolSnapshot) -ceq $before) ($label + ': publisher or test input changed during run.')
            if ($case.Allowed) {
                Assert-True ($result.Code -eq 0) ($label + ': clean control refused.')
                Assert-True ($result.Text -match 'Public tree scan passed|Postwrite public scan passed|PASS: limited public-source') ($label + ': actual scan completion missing.')
                if ($mode -eq 'zip') {
                    Assert-True ($result.Text.Contains('SCANNED:')) ($label + ': ZIP scan completion missing.')
                    Assert-True ($result.Text.Contains('SHA256: ' + $archiveHash)) ($label + ': ZIP scan input identity differs.')
                }
                if ($mode -eq 'export' -and [IO.Directory]::Exists($result.Output)) {
                    Assert-True ((Get-Hash (Join-Path $result.Output 'fixture.txt')) -ceq $fixtureHash) ($label + ': exported URI bytes differ.')
                }
            } else {
                Assert-True ($result.Code -eq 1) ($label + ': unreviewed URI accepted.')
                Assert-True ($result.Text.Contains('unreviewed server URL')) ($label + ': URI category refusal missing.')
                Assert-True ($result.Text -notmatch 'Public tree scan passed|Postwrite public scan passed|PASS: limited public-source') ($label + ': refused URI included a pass claim.')
                Assert-True (-not ($result.Text + $result.Errors).Contains($case.Value)) ($label + ': diagnostic disclosed the URI.')
                Assert-True (-not ($result.Text + $result.Errors).Contains($hostName)) ($label + ': diagnostic disclosed the hostname.')
                if ($mode -eq 'export') {
                    Assert-True (-not (Test-Path -LiteralPath $result.Output)) ($label + ': refused preflight created staging output.')
                }
            }
        }
    }
} catch {
    $failures.Add('URI regression did not complete: ' + $_.Exception.Message)
} finally {
    if (Test-Path -LiteralPath $work -PathType Container) {
        $summary = [pscustomobject]@{assertions=$checks; entries=$runs; passed=($failures.Count -eq 0);
            results=$records.ToArray(); failures=$failures.ToArray()}
        Write-Text (Join-Path $work 'summary.json') (ConvertTo-Json -InputObject $summary -Depth 5)
    }
}
if ($failures.Count) {
    foreach ($failure in $failures) { Write-Output ('FAIL: ' + $failure) }
    exit 1
}
Write-Output ('PASS: URI schemes, {0} assertions; {1} real tree/export/ZIP entries. Synthetic fixtures retained under logs/public-uri-schemes-*.' -f $checks,$runs)
Write-Output 'UNRUN: Python packagers, complete release payloads, launcher GUI, build, game and two-PC play.'
exit 0
