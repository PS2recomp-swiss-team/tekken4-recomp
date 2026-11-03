# Exercise the actual source checker in place, including retained bad archives.
# Fixtures contain harmless text; no archive member is extracted.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$work = Join-Path $root ('logs/beta-source-entry-' + [guid]::NewGuid().ToString('N'))
$fixtures = Join-Path $work 'fixtures'
$entry = Join-Path $PSScriptRoot 'check_beta_source.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = 0
$runs = 0
$failures = New-Object 'Collections.Generic.List[string]'

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
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-Hash([string]$Path) {
    Assert-LocalNoLink $Path
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FixtureSnapshot {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $script:fixtures -Force -Recurse |
        Sort-Object FullName | ForEach-Object {
            Assert-LocalNoLink $_.FullName
            $relative = $_.FullName.Substring($script:fixtures.Length).Replace('\','/')
            if ($_.PSIsContainer) { 'DIR ' + $relative } else { $relative + ' ' + (Get-Hash $_.FullName) }
        }))
}

function New-TextZip([string]$Name, [string[]]$Members) {
    $path = Join-Path $script:fixtures $Name
    Assert-LocalNoLink $path
    $file = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($name in $Members) {
                $member = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::NoCompression)
                $stream = $member.Open()
                try {
                    $data = $script:utf8.GetBytes("Harmless source-check regression text.`n")
                    $stream.Write($data, 0, $data.Length)
                } finally { $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
    return $path
}

function Invoke-Checker([string]$Label, [string]$Doc) {
    $stdout = Join-Path $script:work ($Label + '.stdout.txt')
    $stderr = Join-Path $script:work ($Label + '.stderr.txt')
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    # All paths are generated below this tree; reject quotes rather than interpret them.
    if (($script:entry + $Doc).Contains('"')) { throw 'Quoted test path refused.' }
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:entry + '" -Docs "' + $Doc + '"'
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Actual source checker did not start.' }
        $script:runs++
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'Actual source checker exceeded the test deadline.'
        }
        $text = $outTask.GetAwaiter().GetResult()
        $errorText = $errTask.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($stdout, $text, $script:utf8)
        [IO.File]::WriteAllText($stderr, $errorText, $script:utf8)
        return [pscustomobject]@{ Code=$process.ExitCode; Text=$text; ErrorText=$errorText }
    } finally { $process.Dispose() }
}

try {
    Assert-LocalNoLink $work
    Assert-LocalNoLink $entry
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) {
        throw 'Actual source checker or Windows PowerShell is unavailable.'
    }
    [void][IO.Directory]::CreateDirectory($fixtures)
    Add-Type -AssemblyName System.IO.Compression
    [IO.File]::WriteAllText((Join-Path $fixtures 'README.md'), "Harmless source-check fixture.`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $fixtures '00-corrupt.zip'), "Harmless text, deliberately not a ZIP archive.`n", $utf8)
    $later = New-TextZip '90-later-traversal.zip' @('../blocked-source-check-canary.txt')
    $null = New-TextZip '91-later-clean.zip' @('notes.txt')
    [IO.File]::WriteAllText((Join-Path $fixtures '99-later-note.txt'), "Harmless later inventory text.`n", $utf8)
    $doc = (Join-Path $fixtures 'README.md').Substring($root.Length + 1)
    $laterRelative = $later.Substring($root.Length + 1)
    $before = Get-FixtureSnapshot
    $entryHash = Get-Hash $entry
    $selfHash = Get-Hash $PSCommandPath
    [IO.File]::WriteAllText((Join-Path $work 'fixtures-before.txt'), $before, $utf8)
    [IO.File]::WriteAllText((Join-Path $work 'tools-before.txt'),
        ('check_beta_source.ps1 ' + $entryHash + "`n" + 'test_beta_source_entry.ps1 ' + $selfHash), $utf8)

    foreach ($label in @('first', 'repeat')) {
        $result = Invoke-Checker $label $doc
        Assert-True ($result.Code -eq 1) ($label + ': incomplete archive inspection did not retain exit 1.')
        Assert-True ($result.ErrorText.Length -eq 0) ($label + ': actual checker wrote stderr.')
        Assert-True ($result.Text -match 'FAIL: Archive filename inspection failed; archive #\d+ was not completely inspected\.') ($label + ': missing sanitized archive failure.')
        Assert-True ($result.Text.Contains('FAIL: Unsafe member path in ' + $laterRelative)) ($label + ': later unsafe archive member was not inspected.')
        $summary = [regex]::Match($result.Text, 'Filename inspection: (\d+) files; (\d+) archives attempted; (\d+) members; (\d+) incomplete archives \(no extraction/content scan\)\.')
        Assert-True $summary.Success ($label + ': complete inventory summary was not reached.')
        if ($summary.Success) {
            Assert-True ([int]$summary.Groups[1].Value -ge 5) ($label + ': file inventory omitted fixture files.')
            Assert-True ([int]$summary.Groups[2].Value -ge 3) ($label + ': archive attempts omitted fixture archives.')
            Assert-True ([int]$summary.Groups[3].Value -ge 2) ($label + ': later fixture members were not counted.')
            Assert-True ([int]$summary.Groups[4].Value -ge 1) ($label + ': incomplete archive count was lost.')
        }
        Assert-True ($result.Text.Contains('UNRUN:')) ($label + ': missing unrun limitations.')
        Assert-True ($result.Text.Contains('Beta acceptance remains NO-GO')) ($label + ': missing acceptance gate.')
        Assert-True ($result.Text -notmatch 'Source check stopped:|Source checks completed\. Exit 0') ($label + ': checker stopped early or claimed success.')
        Assert-True (-not $result.Text.Contains('00-corrupt.zip')) ($label + ': malformed archive diagnostic disclosed its name.')
        Assert-True (-not $result.Text.Contains('Harmless text, deliberately')) ($label + ': malformed archive diagnostic disclosed content.')
        Assert-True ((Get-FixtureSnapshot) -ceq $before) ($label + ': fixture bytes or inventory changed.')
        Assert-True ((Get-Hash $entry) -ceq $entryHash) ($label + ': actual checker bytes changed during execution.')
        Assert-True ((Get-Hash $PSCommandPath) -ceq $selfHash) ($label + ': test bytes changed during execution.')
    }
    [IO.File]::WriteAllText((Join-Path $work 'failures.txt'), [string]::Join("`n", $failures.ToArray()), $utf8)
    $summary = 'Source checker entry tests: {0} assertions; {1} real subprocesses; {2} failures.' -f $checks,$runs,$failures.Count
    [IO.File]::WriteAllText((Join-Path $work 'summary.txt'), $summary, $utf8)
    Write-Output $summary
    Write-Output ('Evidence: logs/' + [IO.Path]::GetFileName($work))
    Write-Output 'UNRUN: Python release tools, launcher GUI, build, game, two-PC play and complete player/source validation.'
    if ($failures.Count) {
        foreach ($failure in $failures) { Write-Output ('FAIL: ' + $failure) }
        exit 1
    }
    Write-Output 'PASS: actual source checker continues after archive failures, retains findings and leaves inputs unchanged.'
    exit 0
} catch {
    Write-Output ('FAIL: source checker entry test stopped: ' + $_.Exception.Message)
    exit 1
}
