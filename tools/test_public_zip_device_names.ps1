# Windows device-name regressions through the real ZIP scanner entry.
# Retained archives contain harmless text only. No member is extracted.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$work = Join-Path $root ('logs/public-zip-device-names-' + [guid]::NewGuid().ToString('N'))
$fixtures = Join-Path $work 'fixtures'
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = 0
$runs = 0
$failures = New-Object 'Collections.Generic.List[string]'
$toolNames = @('scan_public_zip.ps1', 'public_zip_scan_worker.ps1', 'public_zip_scan.ps1',
    'public_zip_deflate.ps1', 'public_tree_scan.ps1', 'public_patch_headers.ps1',
    'test_public_zip_device_names.ps1')

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

function Get-ToolSnapshot {
    return [string]::Join("`n", [string[]]@($script:toolNames | ForEach-Object {
        $_ + ' ' + (Get-Hash (Join-Path $PSScriptRoot $_))
    }))
}

function Get-FixtureSnapshot {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $script:fixtures -Recurse -Force |
        Sort-Object FullName | ForEach-Object {
            Assert-LocalNoLink $_.FullName
            $relative = $_.FullName.Substring($script:fixtures.Length).Replace('\','/')
            if ($_.PSIsContainer) { 'DIR ' + $relative } else { $relative + ' ' + (Get-Hash $_.FullName) }
        }))
}

function New-TextZip([string]$Label, [string[]]$Names) {
    $path = Join-Path $script:fixtures ($Label + '.zip')
    Assert-LocalNoLink $path
    $file = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($name in @('LICENSE') + $Names) {
                $member = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::NoCompression)
                if (-not $name.EndsWith('/')) {
                    $stream = $member.Open()
                    try {
                        $data = $script:utf8.GetBytes("Harmless device-name regression text.`n")
                        $stream.Write($data, 0, $data.Length)
                    } finally { $stream.Dispose() }
                }
            }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
    return [pscustomobject]@{Label=$Label; Path=$path; Names=$Names; Hash=(Get-Hash $path)}
}

function New-UnflaggedNameZip([string]$Label, [string]$Name, [byte]$Replacement) {
    $case = New-TextZip $Label @($Name)
    $data = [IO.File]::ReadAllBytes($case.Path)
    $nameBytes = [Text.Encoding]::ASCII.GetBytes($Name)
    $replaced = 0
    # Match both the local and central filename fields, preserving lengths,
    # unflagged metadata and the CRC of the harmless file content.
    for ($i = 0; $i -le $data.Length - $nameBytes.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $nameBytes.Length; $j++) {
            if ($data[$i + $j] -ne $nameBytes[$j]) { $match = $false; break }
        }
        if ($match) {
            $data[$i + $Name.IndexOf('_')] = $Replacement
            $replaced++
        }
    }
    Assert-True ($replaced -eq 2 -and $Name.IndexOf('_') -ge 0) 'Unflagged fixture did not update exactly two name fields.'
    [IO.File]::WriteAllBytes($case.Path, $data)
    $central = [int][BitConverter]::ToUInt32($data, $data.Length - 6)
    $entries = [int][BitConverter]::ToUInt16($data, $data.Length - 12)
    for ($i = 0; $i -lt $entries; $i++) {
        $local = [int][BitConverter]::ToUInt32($data, $central + 42)
        Assert-True ([BitConverter]::ToUInt16($data, $central + 8) -eq 0 -and
            [BitConverter]::ToUInt16($data, $local + 6) -eq 0) 'Unflagged fixture unexpectedly has name-encoding flags.'
        $central += 46 + [BitConverter]::ToUInt16($data, $central + 28)
    }
    $case.Hash = Get-Hash $case.Path
    $case.Names = @('member-canary')
    return $case
}

function Invoke-Scan($Case, [string]$Label) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $script:entry + '" -Archive "' + $Case.Path + '"'
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw 'Real ZIP scanner entry did not start.' }
        $script:runs++
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(45000)) {
            $process.Kill()
            $null = $process.WaitForExit(5000)
            throw 'Real scanner entry exceeded the test watchdog; timeout is not a device-name refusal.'
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),5000)) {
            throw 'Real scanner entry output collection exceeded the test watchdog.'
        }
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stdout.txt')), $out, $script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stderr.txt')), $err, $script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.result.txt')),
            ('exit {0}; elapsed {1:F3} seconds' -f $process.ExitCode,$clock.Elapsed.TotalSeconds), $script:utf8)
        Assert-True (-not $err.Trim()) ($Label + ': stderr was not empty.')
        Assert-True ((Get-Hash $Case.Path) -ceq $Case.Hash) ($Label + ': scanned archive bytes changed.')
        Assert-True ((Get-FixtureSnapshot) -ceq $script:fixtureBefore) ($Label + ': fixture bytes/inventory changed or a ZIP member was extracted.')
        Assert-True ((Get-ToolSnapshot) -ceq $script:toolBefore) ($Label + ': source tool bytes changed during the run.')
        $combined = $out + $err
        Assert-True (-not $combined.Contains($script:root)) ($Label + ': diagnostic disclosed the working-copy path.')
        Assert-True (-not $combined.Contains('Harmless device-name regression text.')) ($Label + ': diagnostic disclosed member contents.')
        foreach ($name in $Case.Names) {
            Assert-True (-not $combined.Contains($name)) ($Label + ': diagnostic disclosed a member name.')
        }
        return [pscustomobject]@{Code=$process.ExitCode; Text=$out}
    } finally { $clock.Stop(); $process.Dispose() }
}

function Test-Clean($Case, [string]$Label, [int]$Entries = 13, [int]$Files = 12) {
    $result = Invoke-Scan $Case $Label
    Assert-True ($result.Code -eq 0) ($Label + ': clean control refused.')
    Assert-True ($result.Text.Contains('PASS: limited public-source ZIP content scan only')) ($Label + ': actual content scan did not pass.')
    Assert-True ($result.Text.Contains('SHA256: ' + $Case.Hash)) ($Label + ': scan did not identify the archive bytes.')
    Assert-True ($result.Text -match ('SCANNED: entries ' + $Entries + '; files ' + $Files + '; bytes \d+\.')) ($Label + ': expected clean members did not reach scanning.')
}

try {
    Assert-LocalNoLink $work
    Assert-LocalNoLink $entry
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) {
        throw 'Real ZIP scanner entry or Windows PowerShell is unavailable.'
    }
    [void][IO.Directory]::CreateDirectory($fixtures)
    Add-Type -AssemblyName System.IO.Compression
    $toolBefore = Get-ToolSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'tools-before.txt'), $toolBefore, $utf8)
    # U+00B9, U+00B2 and U+00B3 are Windows COM/LPT device digits too.
    # Keep the script ASCII so Windows PowerShell decodes the source consistently.
    $one = [string][char]0x00b9
    $four = [string][char]0x2074
    $cleanNames = @('COM0.txt','COM10.txt',('COM' + $four + '.txt'), ('xCOM' + $one + '.txt'),
        ('COM' + $one + 'suffix.txt'), 'LPT0.txt','LPT10.txt',('LPT' + $four + '.txt'),
        ('xLPT' + $one + '.txt'), ('LPT' + $one + 'suffix.txt'), 'ordinary/', 'ordinary/notes.txt')
    $control = New-TextZip 'clean-control' $cleanNames
    $utf8Control = New-TextZip 'utf8-control' @(('ordinary-' + [string][char]0x00e9 + '.txt'))
    $utf8Data = [IO.File]::ReadAllBytes($utf8Control.Path)
    $utf8Central = [int][BitConverter]::ToUInt32($utf8Data, $utf8Data.Length - 6)
    $utf8Central += 46 + [BitConverter]::ToUInt16($utf8Data, $utf8Central + 28)
    $utf8Local = [int][BitConverter]::ToUInt32($utf8Data, $utf8Central + 42)
    Assert-True (([BitConverter]::ToUInt16($utf8Data, $utf8Central + 8) -band 0x800) -ne 0 -and
        ([BitConverter]::ToUInt16($utf8Data, $utf8Local + 6) -band 0x800) -ne 0) 'UTF-8 control lacks matching explicit encoding flags.'
    $asciiControl = New-UnflaggedNameZip 'unflagged-ascii-control' 'ordinary_.member-canary.txt' ([byte][char]'x')
    $encodingCases = @(
        (New-UnflaggedNameZip 'oem-com-extension' 'COM_.member-canary.txt' 0xfd),
        (New-UnflaggedNameZip 'oem-lpt-ancestor' 'outer/LPT_/member-canary.txt' 0xfd),
        (New-UnflaggedNameZip 'unflagged-ordinary' 'ordinary_.member-canary.txt' 0xe9)
    )
    $badCases = New-Object 'Collections.Generic.List[object]'
    $index = 0
    foreach ($device in @('COM','LPT')) {
        foreach ($digit in @(0x00b9,0x00b2,0x00b3)) {
            $reserved = $device + [string][char]$digit
            foreach ($shape in @('bare','extension','ancestor','directory')) {
                $name = switch ($shape) {
                    'bare' { $reserved }
                    'extension' { $reserved.ToLowerInvariant() + '.member-canary.txt' }
                    'ancestor' { 'outer/' + $reserved + '/member-canary.txt' }
                    'directory' { 'outer/' + $reserved.ToLowerInvariant() + '/' }
                }
                $case = New-TextZip ('reserved-' + $index) @($name)
                $badCases.Add($case)
                $index++
            }
        }
    }
    $badCases.Add((New-TextZip 'ascii-com' @('COM1.member-canary.txt')))
    $badCases.Add((New-TextZip 'ascii-lpt' @('outer/lpt9/member-canary.txt')))
    $fixtureBefore = Get-FixtureSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'fixtures-before.txt'), $fixtureBefore, $utf8)
    Test-Clean $control 'clean-before'
    Test-Clean $utf8Control 'utf8-before' 2 2
    Test-Clean $asciiControl 'ascii-before' 2 2
    foreach ($case in $badCases) {
        $result = Invoke-Scan $case $case.Label
        Assert-True ($result.Code -eq 1) ($case.Label + ': expected device-path refusal exit 1.')
        Assert-True ($result.Text.Contains('REFUSED: member 2: unsafe ZIP member path')) ($case.Label + ': expected unsafe member path category was not reached.')
        Assert-True (-not $result.Text.Contains('PASS: limited public-source')) ($case.Label + ': refusal included a scanner pass.')
    }
    foreach ($case in $encodingCases) {
        $result = Invoke-Scan $case $case.Label
        Assert-True ($result.Code -eq 1) ($case.Label + ': expected ambiguous encoding refusal exit 1.')
        Assert-True ($result.Text.Contains('REFUSED: ZIP input or scan failed.')) ($case.Label + ': expected sanitized envelope refusal was not reached.')
        Assert-True ($result.Text -notmatch 'SHA256:|SCANNED:|PASS: limited public-source') ($case.Label + ': ambiguous name reached decoded-member scanning.')
    }
    Test-Clean $control 'clean-after'
    Test-Clean $utf8Control 'utf8-after' 2 2
    Test-Clean $asciiControl 'ascii-after' 2 2
    Assert-True ((Get-ToolSnapshot) -ceq $toolBefore) 'Final source tool snapshot changed.'
    Assert-True ((Get-FixtureSnapshot) -ceq $fixtureBefore) 'Final fixture snapshot changed.'
    [IO.File]::WriteAllText((Join-Path $work 'failures.txt'), [string]::Join("`n",$failures.ToArray()), $utf8)
    $summary = 'ZIP device-name entry tests: {0} assertions; {1} real subprocesses; {2} failures.' -f $checks,$runs,$failures.Count
    [IO.File]::WriteAllText((Join-Path $work 'summary.txt'), $summary, $utf8)
    Write-Output $summary
    Write-Output ('Evidence: logs/' + [IO.Path]::GetFileName($work))
    Write-Output 'UNRUN: Python release tools, launcher GUI, build, game, two-PC play and complete player/source validation.'
    if ($failures.Count) {
        foreach ($failure in $failures) { Write-Output ('FAIL: ' + $failure) }
        exit 1
    }
    Write-Output 'PASS: harmless near-name controls before/after; reserved file/directory names refused without extraction.'
    exit 0
} catch {
    Write-Output ('FAIL: ZIP device-name test stopped: ' + $_.Exception.Message)
    exit 1
}
