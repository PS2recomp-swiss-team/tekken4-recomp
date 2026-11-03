# Giant-word resource regressions through the actual ZIP and tree entries.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-text-words-' + [guid]::NewGuid().ToString('N'))
$checks = 0
$runs = 0
$utf8 = New-Object Text.UTF8Encoding($false)

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
                throw 'Test reparse point refused.'
            }
        }
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-Inventory {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $script:work -Recurse -Force |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:work.Length) }))
}

function New-TextFixture([string]$Name, [string]$Text) {
    $directory = Join-Path $script:work $Name
    Assert-LocalNoLink $directory
    [void][IO.Directory]::CreateDirectory($directory)
    $path = Join-Path $directory 'fixture.txt'
    [IO.File]::WriteAllText($path, $Text, $script:utf8)
    $archive = Join-Path $script:work ($Name + '.zip')
    $file = [IO.File]::Open($archive, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $zip = $null
    try {
        $zip = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Create, $true)
        $member = $zip.CreateEntry('fixture.txt', [IO.Compression.CompressionLevel]::NoCompression)
        $stream = $member.Open()
        $bytes = $script:utf8.GetBytes($Text)
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
        $zip.Dispose()
        $zip = $null
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
        $file.Dispose()
    }
    # The framework reader validates fixture contents independently of the scanner.
    $file = [IO.File]::OpenRead($archive)
    $zip = $null
    try {
        $zip = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Read, $true)
        Assert-True ($zip.Entries.Count -eq 1) 'Fixture entry count differs.'
        $stream = $zip.Entries[0].Open()
        $reader = New-Object IO.StreamReader($stream, $script:utf8)
        try { Assert-True ($reader.ReadToEnd() -ceq $Text) 'Fixture text differs after independent ZIP read.' }
        finally { $reader.Dispose(); $stream.Dispose() }
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
        $file.Dispose()
    }
    return [pscustomobject]@{ Directory=$directory; File=$path; Archive=$archive }
}

function Assert-Entry([string]$Kind, [string]$Path, [string]$InputFile, [string]$Label) {
    $zip = $Kind -eq 'ZIP'
    $entry = Join-Path $PSScriptRoot $(if ($zip) { 'scan_public_zip.ps1' } else { 'publish_public_tree.ps1' })
    Assert-LocalNoLink $entry
    Assert-LocalNoLink $Path
    Assert-LocalNoLink $InputFile
    $hash = (Get-FileHash -LiteralPath $InputFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $inventory = Get-Inventory
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $parameter = if ($zip) { '-Archive' } else { '-ScanOnly' }
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $entry + '" ' + $parameter + ' "' + $Path + '"'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-True ($process.Start()) 'Actual entry did not start.'
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(1000)) {
            if ($watch.Elapsed.TotalSeconds -gt 90) {
                $process.Kill()
                $process.WaitForExit()
                throw 'Actual entry timed out; timeout is a test failure, never a refusal pass.'
            }
        }
        $output = $stdout.Result + $stderr.Result
        $code = $process.ExitCode
    } finally { $watch.Stop(); $process.Dispose() }
    $script:runs++
    Assert-True ($code -eq 0) ($Label + ': clean control refused.')
    Assert-True ($output -match $(if ($zip) { 'PASS: limited public-source ZIP content scan only' } else { 'Public tree scan passed\.' })) ($Label + ': completed pass missing.')
    if ($zip) {
        Assert-True ($output -match ('SHA256: ' + $hash)) ($Label + ': archive identity missing.')
        Assert-True ($output -match 'SCANNED: entries \d+; files 1; bytes \d+\.') ($Label + ': content completion missing.')
    }
    Assert-True (((Get-FileHash -LiteralPath $InputFile -Algorithm SHA256).Hash.ToLowerInvariant()) -ceq $hash) ($Label + ': input changed.')
    Assert-True ((Get-Inventory) -ceq $inventory) ($Label + ': entry wrote or extracted files.')
    Assert-True (-not $output.Contains(('A' * 64))) ($Label + ': output disclosed input content.')
    Assert-True (-not $output.Contains(('_' * 64))) ($Label + ': output disclosed input content.')
    if ($zip) { Assert-True (-not $output.Contains($script:root)) ($Label + ': output disclosed local path.') }
    Write-Output ('PASS: ' + $Label + '; actual ' + $Kind + ' exit ' + $code + '; unchanged SHA256 ' + $hash + '; elapsed ' + $watch.ElapsedMilliseconds + ' ms.')
}

try {
    Assert-LocalNoLink $work
    if (-not [IO.File]::Exists($shell)) { throw 'Windows PowerShell unavailable; no real entry ran.' }
    Add-Type -AssemblyName System.IO.Compression
    [void][IO.Directory]::CreateDirectory($work)
    $small = New-TextFixture 'small-control' "Synthetic ordinary source control.`n"
    $ordinary = New-TextFixture 'large-short-line-control' (("Synthetic ordinary source line with a bounded word.`n") * 20000)
    $word = New-TextFixture 'giant-word' ('A' * 1048575)
    $underscores = New-TextFixture 'giant-underscores' ('_' * 262144)
    foreach ($case in @(
        [pscustomobject]@{Fixture=$small; Label='small control'},
        [pscustomobject]@{Fixture=$ordinary; Label='large ordinary short-line control'},
        [pscustomobject]@{Fixture=$word; Label='giant word'},
        [pscustomobject]@{Fixture=$underscores; Label='giant underscore word'}
    )) {
        Assert-Entry 'ZIP' $case.Fixture.Archive $case.Fixture.Archive ($case.Label + ' ZIP')
        Assert-Entry 'tree' $case.Fixture.Directory $case.Fixture.File ($case.Label + ' tree')
    }
    $retained = Join-Path $root 'logs/public-zip-budget-symbols-002a5d4df9a6480aa3b0c6cab3667f0f/exact-symbol-budget.zip'
    Assert-LocalNoLink $retained
    # Generated fixtures above are mandatory; the old session archive is optional
    # so this suite also works when copied without retained test logs.
    if ([IO.File]::Exists($retained)) {
        Assert-True (((Get-FileHash -LiteralPath $retained -Algorithm SHA256).Hash.ToLowerInvariant()) -ceq '9adcb8e2df7445658ad78a7c4c766ab098b43e720c89ae83e773c6bd8d297bf1') 'Retained giant-word reproducer differs.'
        Assert-Entry 'ZIP' $retained $retained 'unchanged retained giant-word reproducer'
    } else { Write-Output 'UNRUN: optional retained giant-word archive is absent; generated equivalent text fixtures still ran.' }
    Write-Output ('PASS: public text words; {0} assertions, {1} real entry subprocesses. Harmless fixtures retained under logs.' -f $checks,$runs)
    Write-Output 'UNRUN: Python packagers and payload checks; launcher GUI; build; game; two-PC play; owner licence/publication review.'
    exit 0
} catch {
    Write-Output ('FAIL: public text words: ' + $_.Exception.Message)
    exit 1
}
