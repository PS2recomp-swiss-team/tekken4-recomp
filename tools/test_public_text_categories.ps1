# Content-category regressions through both real public scan entries.
# Retained synthetic text only; no game data, images or private values.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-text-categories-' + [guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
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
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Snapshot([string]$Directory) {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $Directory -Force -Recurse |
        Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($Directory.Length)
            if ($_.PSIsContainer) { 'DIR ' + $relative } else { $relative + ' ' + (Get-Hash $_.FullName) }
        }))
}

function Invoke-Entry([string]$Name, [string]$Parameter, [string]$InputPath, [string]$Label) {
    $entry = Join-Path $PSScriptRoot $Name
    Assert-LocalNoLink $entry
    foreach ($value in @($entry, $InputPath)) {
        if ($value.Contains('"')) { throw 'Unsupported quote in test path.' }
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $entry + '" -' + $Parameter + ' "' + $InputPath + '"'
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw 'Real scanner subprocess did not start.' }
        $script:runs++
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(45000)) {
            $process.Kill()
            $process.WaitForExit()
            throw ($Label + ': real scanner exceeded 45 seconds; timeout is a test failure.')
        }
        $text = $stdout.Result + $stderr.Result
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.output.txt')), $text, $script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.result.txt')),
            ('exit {0}; elapsed {1:F3} seconds' -f $process.ExitCode, $watch.Elapsed.TotalSeconds), $script:utf8)
        return [pscustomobject]@{Code=$process.ExitCode; Text=$text}
    } finally { $watch.Stop(); $process.Dispose() }
}

function New-TextZip([string]$Path, [byte[]]$Data) {
    $file = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            $entry = $zip.CreateEntry('fixture.txt', [IO.Compression.CompressionLevel]::NoCompression)
            $stream = $entry.Open()
            try { $stream.Write($Data, 0, $Data.Length) } finally { $stream.Dispose() }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
    # Check that fixture bytes survive the independent framework reader.
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        Assert-True ($zip.Entries.Count -eq 1) 'Fixture ZIP member count differs.'
        $stream = $zip.Entries[0].Open()
        $decoded = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($decoded)
            Assert-True ([Convert]::ToBase64String($decoded.ToArray()) -ceq [Convert]::ToBase64String($Data)) 'Fixture ZIP text differs.'
        } finally { $decoded.Dispose(); $stream.Dispose() }
    } finally { $zip.Dispose() }
}

function Test-Case([string]$Label, [string]$Text, [string]$Reason = '', [string]$Canary = '') {
    $directory = Join-Path $script:work $Label
    [void][IO.Directory]::CreateDirectory($directory)
    $tree = Join-Path $directory 'tree'
    [void][IO.Directory]::CreateDirectory($tree)
    $data = $script:utf8.GetBytes($Text)
    [IO.File]::WriteAllBytes((Join-Path $tree 'fixture.txt'), $data)
    $archive = Join-Path $directory 'fixture.zip'
    New-TextZip $archive $data
    $before = Get-Snapshot $directory
    foreach ($mode in @('tree','zip')) {
        if ($mode -eq 'tree') {
            $result = Invoke-Entry 'publish_public_tree.ps1' 'ScanOnly' $tree ($Label + '-tree')
        } else {
            $result = Invoke-Entry 'scan_public_zip.ps1' 'Archive' $archive ($Label + '-zip')
        }
        if ($Reason) {
            Assert-True ($result.Code -eq 1) ($Label + '/' + $mode + ': expected refusal exit 1.')
            Assert-True ($result.Text.Contains($Reason)) ($Label + '/' + $mode + ': expected content category was not reached.')
            Assert-True (-not $result.Text.Contains('PASS: limited public-source')) ($Label + '/' + $mode + ': refusal contained scanner pass.')
        } else {
            Assert-True ($result.Code -eq 0) ($Label + '/' + $mode + ': clean control refused.')
            Assert-True ($result.Text -match 'scan passed|PASS: limited public-source') ($Label + '/' + $mode + ': clean control did not reach completed scan.')
        }
        if ($mode -eq 'zip') {
            Assert-True ($result.Text -match 'SCANNED: entries 1; files 1; bytes') ($Label + ': ZIP content scan did not complete.')
        }
        if ($Canary) { Assert-True (-not $result.Text.Contains($Canary)) ($Label + '/' + $mode + ': content canary was echoed.') }
        Assert-True ((Get-Snapshot $directory) -ceq $before) ($Label + '/' + $mode + ': scanner changed fixture bytes or inventory.')
    }
    Write-Output ('PASS: ' + $Label + '; both real entries completed; fixture bytes unchanged.')
}

function Test-RegexLimit {
    param([bool]$Materialize = $false)
    $label = 'incomplete-reference-limit'
    $canary = 'category-canary-limit'
    $fragment = '!['
    $text = ($fragment * 131072) + $canary
    $pattern = '(?i)data:ima' + 'ge/|<im' + 'g(?:\s|>)|!\[[^\]\r\n]*\]\s*[\[(]'
    if ($Materialize) {
        $label = 'incomplete-symbol-limit'
        $canary = 'category-canary-symbol-limit'
        $fragment = 'A' * 128
        $text = ('A' * 131072) + "_0x`n" + $canary
        $pattern = '(?:func_[0-9a-fA-F]{6,8}|[A-Za-z_]\w*_0x[0-9a-fA-F]{6,8})'
    }
    # Supplemental diagnosis identifies the actual exception for this fixture.
    # The two entry subprocesses below, not this call, establish fail-closed behavior.
    $timedOut = $false
    try {
        if ($Materialize) {
            $found = [regex]::Matches($text, $pattern, [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(2))
            # PowerShell can suppress property-getter errors, so invoke it.
            $null = $found.get_Count()
        } else {
            $null = [regex]::IsMatch($text, $pattern, [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(2))
        }
    } catch {
        $exception = $_.Exception
        while ($exception.InnerException) { $exception = $exception.InnerException }
        if ($exception -is [Text.RegularExpressions.RegexMatchTimeoutException]) { $timedOut = $true }
        else { throw 'Timeout fixture diagnosis failed with an unexpected exception.' }
    }
    Assert-True $timedOut 'Near-miss fixture did not demonstrate the regex timeout branch.'

    $directory = Join-Path $script:work $label
    [void][IO.Directory]::CreateDirectory($directory)
    $tree = Join-Path $directory 'tree'
    [void][IO.Directory]::CreateDirectory($tree)
    $data = $script:utf8.GetBytes($text)
    [IO.File]::WriteAllBytes((Join-Path $tree 'fixture.txt'), $data)
    $archive = Join-Path $directory 'fixture.zip'
    New-TextZip $archive $data
    $before = Get-Snapshot $directory
    foreach ($mode in @('tree','zip')) {
        if ($mode -eq 'tree') {
            $result = Invoke-Entry 'publish_public_tree.ps1' 'ScanOnly' $tree ($label + '-tree')
            Assert-True ($result.Text -match 'text scan limit or failure;\s+manual review required') 'Tree entry did not report the sanitized text scan limit.'
        } else {
            $result = Invoke-Entry 'scan_public_zip.ps1' 'Archive' $archive ($label + '-zip')
            Assert-True ($result.Text.Contains('REFUSED: ZIP input or scan failed.')) 'ZIP entry did not report the sanitized scan failure.'
            Assert-True (-not $result.Text.Contains('SCANNED:')) 'Timeout refusal claimed a completed ZIP content scan.'
        }
        Assert-True ($result.Code -eq 1) ($label + '/' + $mode + ': expected scanner refusal exit 1.')
        Assert-True ($result.Text -notmatch 'PASS:|scan passed') ($label + '/' + $mode + ': timeout refusal claimed a pass.')
        Assert-True (-not $result.Text.Contains($canary)) ($label + '/' + $mode + ': exception echoed the content canary.')
        Assert-True (-not $result.Text.Contains($fragment)) ($label + '/' + $mode + ': exception echoed near-miss input.')
        Assert-True ((Get-Snapshot $directory) -ceq $before) ($label + '/' + $mode + ': scanner changed fixture bytes or inventory.')
    }
    Write-Output ('PASS: ' + $label + '; both real entries refused without content echo; fixture bytes unchanged.')
}

try {
    Assert-LocalNoLink $work
    if (-not [IO.File]::Exists($shell)) { throw 'Windows PowerShell is unavailable; no real entry ran.' }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [void][IO.Directory]::CreateDirectory($work)

    # Clean controls precede refusals so a broken scanner cannot make this green.
    Test-Case 'ordinary-source' "// Synthetic ordinary source`nint scoped::work() { return 1; }`n"
    Test-Case 'utf8-source' ("// Synthetic UTF-8 notice " + [char]0x00e9 + [char]0x03bb + "`nint value = 7;`n")
    Test-Case 'incomplete-image-reference' ('![' + ('q' * 4096) + "`nordinary public text`n")
    $symbols = @()
    for ($index = 0; $index -lt 64; $index++) { $symbols += ('func_' + $index.ToString('x6')) }
    Test-Case 'symbol-boundary-control' (($symbols[0..62] -join "`n") + "`n")

    $canary = 'category-canary-generated'
    Test-Case 'generated-marker' ("// automatically generated`n" + $canary + "`n") 'generated game code marker' $canary
    $canary = 'category-canary-dense'
    Test-Case 'dense-symbols' (($symbols -join "`n") + "`n" + $canary + "`n") 'dense lifted game function names' $canary
    $canary = 'category-canary-image'
    Test-Case 'image-reference' ('![' + $canary + "](fixture.txt)`n") 'embedded image or image reference' $canary
    $canary = 'category-canary-inline'
    Test-Case 'inline-image-marker' ('<im' + "g >`n" + $canary + "`n") 'embedded image or image reference' $canary
    Test-RegexLimit
    Test-RegexLimit $true

    Write-Output ('PASS: public text categories; {0} assertions through {1} real scanner subprocesses.' -f $checks, $runs)
    Write-Output ('EVIDENCE: ' + $work.Substring($root.Length + 1).Replace('\','/'))
    Write-Output 'UNRUN: Python suites and packagers; launcher GUI; build; game; two-PC play; licence and owner publication review.'
    exit 0
} catch {
    Write-Output ('FAIL: public text categories: ' + $_.Exception.Message)
    Write-Output ('EVIDENCE: ' + $work.Substring($root.Length + 1).Replace('\','/'))
    exit 1
}
