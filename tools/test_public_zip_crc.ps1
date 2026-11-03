# Positive CRC vectors through the real ZIP scanner entry. Harmless text only.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-crc-vectors-' + [guid]::NewGuid().ToString('N'))
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

function New-Vector([string]$Name, [string]$Text, [string]$Crc) {
    return [pscustomobject]@{Name=$Name; Data=$script:ascii.GetBytes($Text); Crc=[Convert]::ToUInt32($Crc,16)}
}

function New-StoredZip([string]$Name, [object[]]$Members) {
    # Literal published CRC-32 vectors supply the headers; no scanner helper is used.
    $path = Join-Path $script:work $Name
    Assert-LocalNoLink $path
    $stream = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $writer = New-Object IO.BinaryWriter($stream)
    $records = New-Object 'Collections.Generic.List[object]'
    try {
        foreach ($member in $Members) {
            $nameBytes = $script:ascii.GetBytes($member.Name)
            $records.Add([pscustomobject]@{Member=$member; Offset=[uint32]$stream.Position; NameBytes=$nameBytes})
            $writer.Write([uint32]0x04034b50)
            foreach ($value in @(20,0,0,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]$member.Crc)
            $writer.Write([uint32]$member.Data.Length)
            $writer.Write([uint32]$member.Data.Length)
            $writer.Write([uint16]$nameBytes.Length)
            $writer.Write([uint16]0)
            $writer.Write([byte[]]$nameBytes)
            $writer.Write([byte[]]$member.Data)
        }
        $central = [uint32]$stream.Position
        foreach ($record in $records) {
            $member = $record.Member
            $writer.Write([uint32]0x02014b50)
            foreach ($value in @(20,20,0,0,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]$member.Crc)
            $writer.Write([uint32]$member.Data.Length)
            $writer.Write([uint32]$member.Data.Length)
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
        $writer.Write([uint16]$Members.Count)
        $writer.Write([uint16]$Members.Count)
        $writer.Write([uint32]$centralSize)
        $writer.Write([uint32]$central)
        $writer.Write([uint16]0)
    } finally { $writer.Dispose() }
    return $path
}

function New-DeflatedZip([string]$Name, [object[]]$Members) {
    $path = Join-Path $script:work $Name
    Assert-LocalNoLink $path
    $file = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file,[IO.Compression.ZipArchiveMode]::Create,$true)
        try {
            foreach ($member in $Members) {
                $item = $zip.CreateEntry($member.Name,[IO.Compression.CompressionLevel]::Optimal)
                $stream = $item.Open()
                try { $stream.Write($member.Data,0,$member.Data.Length) }
                finally { $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
    return $path
}

function Get-Inventory {
    return [string]::Join("`n",[string[]]@(Get-ChildItem -LiteralPath $script:work -Recurse -Force |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:work.Length) }))
}

function Assert-Accepted([string]$Path, [int]$Entries, [int]$Files, [long]$Bytes, [string]$Label) {
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $inventory = Get-Inventory
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $script:shell -NoProfile -ExecutionPolicy Bypass -File $script:entry -Archive $Path 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous; $watch.Stop() }
    $script:runs++
    $text = ($lines | ForEach-Object { $_.ToString() }) -join "`n"
    Assert-True ($code -eq 0) ($Label + ': clean archive refused.')
    Assert-True ($text -match 'PASS: limited public-source ZIP content scan only') ($Label + ': limited scan pass missing.')
    Assert-True ($text -match ('SCANNED: entries ' + $Entries + '; files ' + $Files + '; bytes ' + $Bytes + '\.')) ($Label + ': scanned counts differ.')
    Assert-True ($text -match ('SHA256: ' + $hash)) ($Label + ': exact archive identity missing.')
    Assert-True ($text -match 'UNRUN:.*Python.*launcher GUI.*build.*game.*two-PC') ($Label + ': unrun evidence missing.')
    Assert-True (((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()) -ceq $hash) ($Label + ': input changed.')
    Assert-True ((Get-Inventory) -ceq $inventory) ($Label + ': extracted or wrote files.')
    foreach ($canary in @($script:root,'crc-vector-member','123456789','Harmless CRC vector line.')) {
        Assert-True (-not $text.Contains($canary)) ($Label + ': output disclosed a path, member or content.')
    }
    Write-Output ('PASS: ' + $Label + '; real scan accepted; unchanged; elapsed ' + $watch.ElapsedMilliseconds + ' ms.')
}

try {
    Assert-LocalNoLink $entry
    Assert-LocalNoLink $work
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) { throw 'Real entry or Windows PowerShell missing.' }
    Add-Type -AssemblyName System.IO.Compression
    [void][IO.Directory]::CreateDirectory($work)
    $numbers = New-Vector 'crc-vector-member-numbers.txt' '123456789' 'cbf43926'
    $letters = New-Vector 'crc-vector-member-letters.txt' 'abc' '352441c2'
    $empty = New-Vector 'crc-vector-member-empty.txt' '' '00000000'
    $directory = New-Vector 'crc-vector-member-directory/' '' '00000000'

    $path = New-StoredZip 'stored-known.zip' @($numbers)
    Assert-Accepted $path 1 1 9 'stored standard vector'
    $path = New-StoredZip 'stored-second.zip' @($letters)
    Assert-Accepted $path 1 1 3 'stored second vector'
    $path = New-StoredZip 'stored-empty-and-reset.zip' @($directory,$empty,$numbers,$letters)
    Assert-Accepted $path 4 3 12 'stored empty members and CRC reset'

    $path = New-DeflatedZip 'deflated-known.zip' @($numbers)
    $data = [IO.File]::ReadAllBytes($path)
    Assert-True ([BitConverter]::ToUInt16($data,8) -eq 8) 'Deflated fixture did not use method 8.'
    Assert-True ([BitConverter]::ToUInt32($data,14) -eq [Convert]::ToUInt32('cbf43926',16)) 'Independent deflater disagreed with standard CRC vector.'
    Assert-Accepted $path 1 1 9 'deflated standard vector'

    # More than three 64 KiB scanner reads, followed by empty and different data.
    $largeText = ('Harmless CRC vector line.' + "`n") * 9000
    $large = New-Vector 'crc-vector-member-large.txt' $largeText '00000000'
    $path = New-DeflatedZip 'deflated-multiple-buffers.zip' @($large,$empty,$directory,$letters)
    Assert-True ($large.Data.Length -gt 3 * 65536) 'Multi-buffer fixture is too short.'
    Assert-Accepted $path 4 3 ($large.Data.Length + 3) 'deflated multiple buffers and CRC reset'

    Write-Output ("PASS: public ZIP CRC vectors; {0} assertions, {1} real scanner subprocesses. Harmless fixtures retained under logs." -f $checks,$runs)
    Write-Output 'UNRUN: Python packagers and payload checks; launcher GUI; build; game; two-PC play; owner licence/publication review.'
    exit 0
} catch {
    Write-Output ('FAIL: public ZIP CRC vectors: ' + $_.Exception.Message)
    exit 1
}
