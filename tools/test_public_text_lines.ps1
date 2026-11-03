# Whitespace regressions through both real public scanner entries.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-text-lines-' + [guid]::NewGuid().ToString('N'))
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

function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-Inventory {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $script:work -Recurse -Force |
        Sort-Object FullName | ForEach-Object {
            $name = $_.FullName.Substring($script:work.Length)
            if ($_.PSIsContainer) { $name + '/' }
            else { $name + ' ' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }))
}

function New-Fixture([string]$Label, [string]$Text) {
    $directory = Join-Path $script:work $Label
    [void][IO.Directory]::CreateDirectory($directory)
    $bytes = $script:utf8.GetBytes($Text)
    [IO.File]::WriteAllBytes((Join-Path $directory 'whitespace-fixture.txt'), $bytes)
    $path = Join-Path $script:work ($Label + '.zip')
    $file = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $zip = $null
    try {
        $zip = New-Object IO.Compression.ZipArchive($file,[IO.Compression.ZipArchiveMode]::Create,$true)
        $member = $zip.CreateEntry('whitespace-fixture.txt',[IO.Compression.CompressionLevel]::Optimal)
        $stream = $member.Open()
        try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
        $file.Dispose()
    }
    # Establish fixture validity independently before testing either scanner.
    $file = [IO.File]::OpenRead($path)
    $zip = $null
    try {
        $zip = New-Object IO.Compression.ZipArchive($file,[IO.Compression.ZipArchiveMode]::Read,$true)
        Assert-True ($zip.Entries.Count -eq 1) 'Fixture archive member count differs.'
        $stream = $zip.Entries[0].Open()
        $decoded = New-Object IO.MemoryStream
        try {
            $stream.CopyTo($decoded)
            Assert-True ($decoded.Length -eq $bytes.Length) 'Fixture decoded length differs.'
            Assert-True ((Get-BytesHash $decoded.ToArray()) -ceq (Get-BytesHash $bytes)) 'Fixture decoded bytes differ.'
        } finally { $decoded.Dispose(); $stream.Dispose() }
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
        $file.Dispose()
    }
    return [pscustomobject]@{ Directory=$directory; Archive=$path }
}

function Assert-Scan([object]$Fixture, [string]$Kind, [bool]$Accepted, [string]$Label) {
    $entryName = if ($Kind -eq 'ZIP') { 'scan_public_zip.ps1' } else { 'publish_public_tree.ps1' }
    $parameter = if ($Kind -eq 'ZIP') { '-Archive' } else { '-ScanOnly' }
    $path = if ($Kind -eq 'ZIP') { $Fixture.Archive } else { $Fixture.Directory }
    $entry = Join-Path $PSScriptRoot $entryName
    Assert-LocalNoLink $entry
    $before = Get-Inventory
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $entry + '" ' + $parameter + ' "' + $path + '"'
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-True ($process.Start()) 'Real scanner subprocess did not start.'
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        while (-not $process.WaitForExit(500)) {
            if ($watch.Elapsed.TotalSeconds -gt 60) {
                $process.Kill()
                $process.WaitForExit()
                throw 'Real scanner exceeded 60 seconds; a killed process is a test failure, never a refusal pass.'
            }
        }
        $output = $stdout.Result + $stderr.Result
        $code = $process.ExitCode
    } finally { $watch.Stop(); $process.Dispose() }
    $script:runs++
    Assert-True ($code -eq $(if ($Accepted) { 0 } else { 1 })) ($Label + ': unexpected real entry exit.')
    if ($Accepted) {
        $success = if ($Kind -eq 'ZIP') { 'PASS: limited public-source ZIP content scan only' } else { 'Public tree scan passed.' }
        Assert-True ($output.Contains($success)) ($Label + ': clean scan did not complete.')
        if ($Kind -eq 'ZIP') {
            Assert-True ($output -match 'SCANNED: entries 1; files 1; bytes \d+\.') ($Label + ': ZIP content scan did not complete.')
        }
    } else {
        Assert-True ($output.Contains('generated game code marker')) ($Label + ': generated marker detection did not complete.')
        Assert-True ($output -notmatch 'PASS: limited|Public tree scan passed') ($Label + ': refused content passed.')
    }
    Assert-True ((Get-Inventory) -ceq $before) ($Label + ': scanner changed or extracted fixture files.')
    foreach ($canary in @('automatically generated', 'generated by ghidra')) {
        Assert-True (-not $output.Contains($canary)) ($Label + ': output disclosed a path or fixture content.')
    }
    if ($Kind -eq 'ZIP') {
        Assert-True (-not $output.Contains($script:root)) ($Label + ': ZIP output disclosed the working path.')
        Assert-True (-not $output.Contains('whitespace-fixture.txt')) ($Label + ': ZIP output disclosed the member name.')
        Assert-True ($output -match 'UNRUN:.*Python.*launcher GUI.*build.*game.*two-PC') ($Label + ': ZIP unrun evidence missing.')
    }
    Write-Output ('PASS: ' + $Label + '; ' + $Kind + ' real entry exit ' + $code + '; elapsed ' + $watch.ElapsedMilliseconds + ' ms.')
}

try {
    Assert-LocalNoLink $work
    Assert-True ([IO.File]::Exists($shell)) 'Windows PowerShell unavailable.'
    Add-Type -AssemblyName System.IO.Compression
    [void][IO.Directory]::CreateDirectory($work)
    $cases = @(
        [pscustomobject]@{Name='ordinary'; Text="Synthetic source fixture.`nint value = 1;`n"; Accepted=$true},
        [pscustomobject]@{Name='pure-newlines'; Text=("`n" * 2097151); Accepted=$true},
        [pscustomobject]@{Name='crlf-lines'; Text=("`r`n" * 131072); Accepted=$true},
        [pscustomobject]@{Name='cr-only-space'; Text=("`r" * 131072); Accepted=$true},
        [pscustomobject]@{Name='horizontal-space'; Text=(' ' * 131072); Accepted=$true},
        [pscustomobject]@{Name='marker-after-lines'; Text=(("`n" * 65536) + "# automatically generated`n"); Accepted=$false},
        [pscustomobject]@{Name='marker-after-indentation'; Text=((" `t" * 65536) + "generated by ghidra`n"); Accepted=$false},
        [pscustomobject]@{Name='marker-after-cr'; Text="`r# automatically generated"; Accepted=$false},
        [pscustomobject]@{Name='marker-after-comment-blank-lines'; Text="#`n`n generated by ghidra`n"; Accepted=$false}
    )
    foreach ($case in $cases) {
        $fixture = New-Fixture $case.Name $case.Text
        foreach ($kind in @('ZIP','TREE')) { Assert-Scan $fixture $kind $case.Accepted $case.Name }
    }
    Write-Output ('PASS: public text whitespace; {0} assertions, {1} real scanner subprocesses. Harmless fixtures retained under logs.' -f $checks,$runs)
    Write-Output 'UNRUN: Python suites and packagers; complete player payload checks; launcher GUI; build; game; two-PC play; owner licence/publication review.'
    exit 0
} catch {
    Write-Output ('FAIL: public text whitespace: ' + $_.Exception.Message)
    exit 1
}
