# Real ZIP scan refusal tests. Retained ZIP containers hold harmless text only.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-safety-' + [guid]::NewGuid().ToString('N'))
$checks = 0
$cases = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function Assert-LocalNoLink([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not ($full.Equals($script:root, [StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($script:root + '\', [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Test fixture path outside this copy refused.'
    }
    $current = $full
    while ($current.Length -ge $script:root.Length) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Test fixture link refused.'
            }
        }
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function New-Member([string]$Name, [long]$Length = 28, [int]$Attributes = 0) {
    return [pscustomobject]@{Name=$Name; Length=$Length; Attributes=$Attributes}
}

function New-TextZip([string]$FileName, [object[]]$Members = @()) {
    $path = Join-Path $script:work $FileName
    Assert-LocalNoLink $path
    $file = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            $buffer = [Text.Encoding]::UTF8.GetBytes(('t' * 8192))
            foreach ($member in $Members) {
                $item = $zip.CreateEntry($member.Name, [IO.Compression.CompressionLevel]::Optimal)
                $item.ExternalAttributes = $member.Attributes
                $stream = $item.Open()
                try {
                    # Repeated ordinary text keeps size-limit fixtures small on disk.
                    $remaining = $member.Length
                    while ($remaining -gt 0) {
                        $count = [int][Math]::Min($remaining, $buffer.Length)
                        $stream.Write($buffer, 0, $count)
                        $remaining -= $count
                    }
                } finally { $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
    return $path
}

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Invoke-Scan([string]$Path) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $script:shell -NoProfile -ExecutionPolicy Bypass -File $script:entry -Archive $Path 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    $output = ($lines | ForEach-Object { $_.ToString() }) -join "`n"
    return [pscustomobject]@{Code=$code; Text=$output}
}

function Assert-Refused([string]$Path, [string]$CaseName, [string[]]$Canaries = @()) {
    $before = Get-Hash $Path
    $filesBefore = @([IO.Directory]::GetFiles($script:work, '*', [IO.SearchOption]::AllDirectories) | Sort-Object)
    $result = Invoke-Scan $Path
    Assert-True ($result.Code -eq 1) ($CaseName + ': expected refusal exit 1.')
    Assert-True ($result.Text -match '(?i)refus|fail') ($CaseName + ': missing refusal diagnostic.')
    Assert-True ((Get-Hash $Path) -ceq $before) ($CaseName + ': scan changed the archive.')
    $filesAfter = @([IO.Directory]::GetFiles($script:work, '*', [IO.SearchOption]::AllDirectories) | Sort-Object)
    Assert-True ([string]::Join("`n", $filesBefore) -ceq [string]::Join("`n", $filesAfter)) ($CaseName + ': scan wrote or extracted files in the fixture tree.')
    foreach ($canary in $Canaries) {
        Assert-True (-not $result.Text.Contains($canary)) ($CaseName + ': scan echoed a member-name canary.')
    }
    $script:cases++
    Write-Output ('PASS: ' + $CaseName + '; real scan entry refused; archive unchanged.')
}

try {
    Assert-LocalNoLink $entry
    Assert-LocalNoLink $work
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) {
        throw 'Real scan entry or Windows PowerShell is unavailable.'
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [void][IO.Directory]::CreateDirectory($work)

    # A broken or missing scanner must not make every refusal test green.
    $control = New-TextZip 'clean-control.zip' @((New-Member 'source.txt'))
    $controlHash = Get-Hash $control
    $controlResult = Invoke-Scan $control
    Assert-True ($controlResult.Code -eq 0) 'Clean control failed; refusal cases cannot establish a working scanner.'
    Assert-True ($controlResult.Text -match 'SCANNED:') 'Clean control did not reach the actual scan entry.'
    Assert-True ((Get-Hash $control) -ceq $controlHash) 'Clean control changed during scanning.'
    $cases++
    Write-Output 'PASS: clean control; real scan entry accepted harmless text.'

    $names = @(
        '../member-canary-traversal.txt',
        'folder\member-canary-backslash.txt',
        '/member-canary-absolute.txt',
        'NUL.member-canary-device.txt',
        'member-canary-dot.txt.',
        'member-canary-space.txt ',
        'member-canary-question?.txt',
        'member-canary-star*.txt'
    )
    $index = 0
    foreach ($name in $names) {
        $path = New-TextZip ('unsafe-' + $index + '.zip') @((New-Member $name))
        Assert-Refused $path ('unsafe member ' + $index) @('member-canary')
        $index++
    }

    # ZipArchive.CreateEntry refuses some Windows path characters itself.
    # Change only the two same-length filename fields of an ordinary ZIP.
    $controlName = 'member-canary-control_.txt'
    $nameBytes = [Text.Encoding]::ASCII.GetBytes($controlName)
    $characters = @(
        [pscustomobject]@{Name='tab'; Value=9},
        [pscustomobject]@{Name='pipe'; Value=124},
        [pscustomobject]@{Name='less-than'; Value=60},
        [pscustomobject]@{Name='greater-than'; Value=62},
        [pscustomobject]@{Name='quote'; Value=34}
    )
    foreach ($character in $characters) {
        $path = New-TextZip ('character-' + $character.Name + '.zip') @((New-Member $controlName))
        $data = [IO.File]::ReadAllBytes($path)
        $replaced = 0
        for ($i = 0; $i -le $data.Length - $nameBytes.Length; $i++) {
            $match = $true
            for ($j = 0; $j -lt $nameBytes.Length; $j++) {
                if ($data[$i + $j] -ne $nameBytes[$j]) { $match = $false; break }
            }
            if ($match) { $data[$i + $controlName.IndexOf('_')] = [byte]$character.Value; $replaced++ }
        }
        Assert-True ($replaced -eq 2) 'Unsafe-character fixture did not update exactly two filename fields.'
        [IO.File]::WriteAllBytes($path, $data)
        Assert-Refused $path ($character.Name + ' member character') @('member-canary')
    }

    $path = New-TextZip 'local-name-mismatch.zip' @((New-Member 'member-canary-local.txt'))
    $data = [IO.File]::ReadAllBytes($path)
    $data[30] = [byte][char]'x'
    [IO.File]::WriteAllBytes($path, $data)
    Assert-Refused $path 'local and central filename mismatch' @('member-canary')
    $path = New-TextZip 'local-flags-mismatch.zip' @((New-Member 'member-canary-flags.txt'))
    $data = [IO.File]::ReadAllBytes($path)
    $data[6] = $data[6] -bxor 1
    [IO.File]::WriteAllBytes($path, $data)
    Assert-Refused $path 'local and central flags mismatch' @('member-canary')
    $path = New-TextZip 'local-method-mismatch.zip' @((New-Member 'member-canary-method.txt'))
    $data = [IO.File]::ReadAllBytes($path)
    $data[8] = 0
    [IO.File]::WriteAllBytes($path, $data)
    Assert-Refused $path 'local and central method mismatch' @('member-canary')

    foreach ($prefixGap in @($true, $false)) {
        $fileName = if ($prefixGap) { 'prefix-gap.zip' } else { 'central-gap.zip' }
        $path = New-TextZip $fileName @((New-Member 'member-canary-gap.txt'))
        $data = [IO.File]::ReadAllBytes($path)
        $oldCentral = [int][BitConverter]::ToUInt32($data, $data.Length - 6)
        $position = if ($prefixGap) { 0 } else { $oldCentral }
        $gap = [Text.Encoding]::ASCII.GetBytes("unused`n")
        $changed = New-Object byte[] ($data.Length + $gap.Length)
        [Array]::Copy($data, 0, $changed, 0, $position)
        [Array]::Copy($gap, 0, $changed, $position, $gap.Length)
        [Array]::Copy($data, $position, $changed, $position + $gap.Length, $data.Length - $position)
        $newCentral = $oldCentral + $gap.Length
        [Array]::Copy([BitConverter]::GetBytes([uint32]$newCentral), 0, $changed, $changed.Length - 6, 4)
        if ($prefixGap) {
            [Array]::Copy([BitConverter]::GetBytes([uint32]$gap.Length), 0, $changed, $newCentral + 42, 4)
        }
        [IO.File]::WriteAllBytes($path, $changed)
        $caseName = if ($prefixGap) { 'unscanned prefix bytes' } else { 'unscanned bytes before central directory' }
        Assert-Refused $path $caseName @('member-canary', 'unused')
    }

    $path = New-TextZip 'descriptor-flag.zip' @((New-Member 'member-canary-descriptor.txt'))
    $data = [IO.File]::ReadAllBytes($path)
    $central = [int][BitConverter]::ToUInt32($data, $data.Length - 6)
    $data[6] = $data[6] -bor 8
    $data[$central + 8] = $data[$central + 8] -bor 8
    [IO.File]::WriteAllBytes($path, $data)
    Assert-Refused $path 'unsupported data-descriptor flag' @('member-canary')

    $path = New-TextZip 'duplicate.zip' @((New-Member 'member-canary-duplicate.txt'), (New-Member 'member-canary-duplicate.txt'))
    Assert-Refused $path 'duplicate member' @('member-canary')
    $path = New-TextZip 'case.zip' @((New-Member 'member-canary-case.txt'), (New-Member 'MEMBER-CANARY-CASE.TXT'))
    Assert-Refused $path 'case-colliding member' @('member-canary', 'MEMBER-CANARY')
    $path = New-TextZip 'ancestor-case.zip' @((New-Member 'Member-canary/one.txt'), (New-Member 'member-canary/two.txt'))
    Assert-Refused $path 'case-colliding ancestor' @('Member-canary', 'member-canary')
    $path = New-TextZip 'file-directory.zip' @((New-Member 'member-canary'), (New-Member 'member-canary/one.txt'))
    Assert-Refused $path 'file used as directory' @('member-canary')
    $path = New-TextZip 'directory-file.zip' @((New-Member 'member-canary/one.txt'), (New-Member 'member-canary'))
    Assert-Refused $path 'directory replaced by file' @('member-canary')
    $path = New-TextZip 'explicit-directory-file.zip' @((New-Member 'member-canary/' 0), (New-Member 'member-canary'))
    Assert-Refused $path 'explicit directory and file conflict' @('member-canary')

    $linkAttributes = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]2717843456), 0)
    $path = New-TextZip 'unix-link.zip' @((New-Member 'member-canary-link.txt' 28 $linkAttributes))
    Assert-Refused $path 'Unix link metadata' @('member-canary')
    $path = New-TextZip 'empty.zip'
    Assert-Refused $path 'empty archive'
    $path = New-TextZip 'directories-only.zip' @((New-Member 'member-canary/' 0))
    Assert-Refused $path 'archive without files' @('member-canary')
    $path = New-TextZip 'oversized-member.zip' @((New-Member 'member-canary-large.txt' (32MB + 1)))
    Assert-Refused $path 'member size limit' @('member-canary')

    $many = New-Object 'Collections.Generic.List[object]'
    for ($i = 0; $i -lt 10001; $i++) { $many.Add((New-Member ('member-canary-' + $i + '.txt') 0)) }
    $path = New-TextZip 'entry-limit.zip' $many.ToArray()
    Assert-Refused $path 'entry count limit' @('member-canary')
    $large = @()
    for ($i = 0; $i -lt 5; $i++) { $large += New-Member ('member-canary-total-' + $i + '.txt') 27MB }
    $path = New-TextZip 'total-size-limit.zip' $large
    Assert-Refused $path 'total member size limit' @('member-canary')

    $valid = New-TextZip 'truncate-source.zip' @((New-Member 'member-canary-truncated.txt'))
    $data = [IO.File]::ReadAllBytes($valid)
    $path = Join-Path $work 'truncated.zip'
    $short = New-Object byte[] ([Math]::Min(15, $data.Length))
    [Array]::Copy($data, $short, $short.Length)
    [IO.File]::WriteAllBytes($path, $short)
    Assert-Refused $path 'truncated archive' @('member-canary')

    Write-Output ('ZIP safety entry tests passed: {0} real subprocess cases; {1} assertions.' -f $cases, $checks)
    Write-Output 'Fixtures retained as ZIP containers of harmless text; no members extracted or executed.'
    Write-Output 'UNRUN: Python packagers, launcher GUI, build, game and two-PC play.'
    exit 0
} catch {
    Write-Output ('FAIL: ZIP safety test: ' + $_.Exception.Message)
    exit 1
}
