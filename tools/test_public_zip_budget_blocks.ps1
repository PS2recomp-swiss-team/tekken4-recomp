# Archive-wide DEFLATE block limits through the real scanner. Harmless text only.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-budget-blocks-' + [guid]::NewGuid().ToString('N'))
$checks = 0
$runs = 0
$ascii = [Text.Encoding]::ASCII

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

function New-EmptyBlocks([int]$Count, [int]$Index) {
    # Each stored block is byte aligned: BFINAL/BTYPE, LEN=0, NLEN=ffff.
    $raw = New-Object byte[] ($Count * 5)
    for ($block = 0; $block -lt $Count; $block++) {
        $raw[$block*5+3] = 255
        $raw[$block*5+4] = 255
    }
    $raw[($Count-1)*5] = 1
    return [pscustomobject]@{Name=('budget-block-member-' + $Index + '.txt'); Method=8; Raw=$raw; Length=0; Crc=[uint32]0}
}

function New-BlockZip([string]$Name, [int[]]$Counts) {
    $members = New-Object 'Collections.Generic.List[object]'
    # A known CRC vector ensures every archive has ordinary source content.
    $members.Add([pscustomobject]@{Name='budget-block-control.txt'; Method=0; Raw=$script:ascii.GetBytes('abc'); Length=3; Crc=[uint32]0x352441c2})
    for ($index = 0; $index -lt $Counts.Length; $index++) { $members.Add((New-EmptyBlocks $Counts[$index] $index)) }
    $path = Join-Path $script:work $Name
    Assert-LocalNoLink $path
    $stream = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $writer = New-Object IO.BinaryWriter($stream)
    $records = New-Object 'Collections.Generic.List[object]'
    try {
        foreach ($member in $members) {
            $nameBytes = $script:ascii.GetBytes($member.Name)
            $records.Add([pscustomobject]@{Member=$member; Offset=[uint32]$stream.Position; NameBytes=$nameBytes})
            $writer.Write([uint32]0x04034b50)
            foreach ($value in @(20,0,$member.Method,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]$member.Crc)
            $writer.Write([uint32]$member.Raw.Length)
            $writer.Write([uint32]$member.Length)
            $writer.Write([uint16]$nameBytes.Length)
            $writer.Write([uint16]0)
            $writer.Write([byte[]]$nameBytes)
            $writer.Write([byte[]]$member.Raw)
        }
        $central = [uint32]$stream.Position
        foreach ($record in $records) {
            $member = $record.Member
            $writer.Write([uint32]0x02014b50)
            foreach ($value in @(20,20,0,$member.Method,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]$member.Crc)
            $writer.Write([uint32]$member.Raw.Length)
            $writer.Write([uint32]$member.Length)
            $writer.Write([uint16]$record.NameBytes.Length)
            foreach ($value in @(0,0,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]0)
            $writer.Write([uint32]$record.Offset)
            $writer.Write([byte[]]$record.NameBytes)
        }
        $centralSize = [uint32]($stream.Position - $central)
        $writer.Write([uint32]0x06054b50)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)
        $writer.Write([uint16]$members.Count)
        $writer.Write([uint16]$members.Count)
        $writer.Write([uint32]$centralSize)
        $writer.Write([uint32]$central)
        $writer.Write([uint16]0)
    } finally { $writer.Dispose() }
    return $path
}

function Assert-FrameworkRead([string]$Path, [int]$Entries) {
    $file = [IO.File]::OpenRead($Path)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file,[IO.Compression.ZipArchiveMode]::Read,$true)
        try {
            Assert-True ($zip.Entries.Count -eq $Entries) 'Framework entry count differs.'
            for ($index = 0; $index -lt $Entries; $index++) {
                $stream = $zip.Entries[$index].Open()
                $memory = New-Object IO.MemoryStream
                try { $stream.CopyTo($memory); $actual = $memory.ToArray() }
                finally { $memory.Dispose(); $stream.Dispose() }
                # The exact expected content has the literal CRCs written above:
                # abc=352441c2; empty=00000000. No scanner helper is used.
                if ($index -eq 0) { Assert-True ($script:ascii.GetString($actual) -ceq 'abc') 'Framework control differs.' }
                else { Assert-True ($actual.Length -eq 0) 'Framework empty member differs.' }
                # Independent bitwise CRC on the framework's returned bytes.
                # Small fixtures keep this reference calculation cheap.
                $crc = [uint32]::MaxValue
                $polynomial = [Convert]::ToUInt32('edb88320',16)
                foreach ($value in $actual) {
                    $crc = $crc -bxor [uint32]$value
                    for ($bit = 0; $bit -lt 8; $bit++) {
                        if ($crc -band 1) { $crc = ($crc -shr 1) -bxor $polynomial }
                        else { $crc = $crc -shr 1 }
                    }
                }
                $crc = $crc -bxor [uint32]::MaxValue
                $expectedCrc = if ($index -eq 0) { [uint32]0x352441c2 } else { [uint32]0 }
                Assert-True ($crc -eq $expectedCrc) 'Framework content CRC differs from the fixture headers.'
            }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
}

function Get-Inventory {
    return [string]::Join("`n",[string[]]@(Get-ChildItem -LiteralPath $script:work -Recurse -Force |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:work.Length) }))
}

function Assert-Scan([string]$Path, [bool]$Accepted, [int]$Entries, [string]$Label) {
    Assert-FrameworkRead $Path $Entries
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $inventory = Get-Inventory
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $script:shell
    $start.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:entry + '" -Archive "' + $Path + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-True ($process.Start()) ($Label + ': scanner did not start.')
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill()
            $process.WaitForExit()
            throw ($Label + ': scanner exceeded test timeout; no scan result proved.')
        }
        $text = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        $code = $process.ExitCode
    } finally { $watch.Stop(); $process.Dispose() }
    $script:runs++
    if ($Accepted) {
        Assert-True ($code -eq 0) ($Label + ': valid boundary stream refused.')
        Assert-True ($text -match 'PASS: limited public-source ZIP content scan only') ($Label + ': limited pass missing.')
        Assert-True ($text -match ('SCANNED: entries ' + $Entries + '; files ' + $Entries + '; bytes 3\.')) ($Label + ': scanned counts differ.')
        Assert-True ($text -match ('SHA256: ' + $hash)) ($Label + ': identity missing.')
    } else {
        Assert-True ($code -eq 1) ($Label + ': over-budget stream accepted.')
        Assert-True ($text -match '^REFUSED:' -and $text -notmatch 'PASS:') ($Label + ': refusal missing.')
    }
    Assert-True ($text -match 'UNRUN:.*Python.*launcher GUI.*build.*game.*two-PC') ($Label + ': unrun evidence missing.')
    Assert-True (((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()) -ceq $hash) ($Label + ': input changed.')
    Assert-True ((Get-Inventory) -ceq $inventory) ($Label + ': scanner extracted or wrote files.')
    foreach ($canary in @($script:root,'budget-block-member','budget-block-control')) {
        Assert-True (-not $text.Contains($canary)) ($Label + ': output disclosed path or member.')
    }
    Write-Output ('PASS: ' + $Label + '; real scan exit ' + $code + '; unchanged; elapsed ' + $watch.ElapsedMilliseconds + ' ms.')
}

try {
    Assert-LocalNoLink $entry
    Assert-LocalNoLink $work
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) { throw 'Real entry or Windows PowerShell missing.' }
    Add-Type -AssemblyName System.IO.Compression
    [void][IO.Directory]::CreateDirectory($work)
    foreach ($case in @(
        @('below.zip',@(1023),$true,'single member below block limit'),
        @('exact.zip',@(1024),$true,'single member at block limit'),
        @('over.zip',@(1025),$false,'single member above block limit'),
        @('shared-below.zip',@(511,512),$true,'two members below shared block limit'),
        @('shared-exact.zip',@(512,512),$true,'two members at shared block limit'),
        @('shared-over.zip',@(512,513),$false,'two members above shared block limit')
    )) {
        $path = New-BlockZip $case[0] $case[1]
        Assert-Scan $path $case[2] ($case[1].Count+1) $case[3]
    }
    Write-Output ('PASS: public ZIP block budget; {0} assertions, {1} real scanner subprocesses. Harmless fixtures retained under logs.' -f $checks,$runs)
    Write-Output 'UNRUN: Python packagers and payload checks; launcher GUI; build; game; two-PC play; owner licence/publication review.'
    exit 0
} catch {
    Write-Output ('FAIL: public ZIP block budget: ' + $_.Exception.Message)
    exit 1
}
