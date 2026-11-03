# Real ZIP entry regressions for member integrity. Fixtures contain harmless text.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-integrity-' + [guid]::NewGuid().ToString('N'))
$checks = 0
$runs = 0
$knownCrc = [Convert]::ToUInt32('cbf43926',16)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function Assert-LocalNoLink([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($script:root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Outside-tree test input refused.'
    }
    $current = $full
    while ($current.Length -ge $script:root.Length) {
        if ((Test-Path -LiteralPath $current) -and
            ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Linked test input refused.'
        }
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function New-Member([string]$Name, [byte[]]$Bytes, [uint32]$Crc, [int]$Method = 0, [int]$LengthDelta = 0) {
    return [pscustomobject]@{Name=$Name; Bytes=$Bytes; Crc=$Crc; Method=$Method; Length=($Bytes.Length + $LengthDelta)}
}

function New-Fixture([string]$FileName, [object[]]$Members) {
    $path = Join-Path $script:work $FileName
    Assert-LocalNoLink $path
    $file = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $writer = New-Object IO.BinaryWriter($file)
    $records = @()
    try {
        foreach ($member in $Members) {
            $name = [Text.Encoding]::ASCII.GetBytes($member.Name)
            $body = $member.Bytes
            if ($member.Method -eq 8) {
                $memory = New-Object IO.MemoryStream
                try {
                    $deflate = New-Object IO.Compression.DeflateStream($memory,[IO.Compression.CompressionLevel]::Optimal,$true)
                    try { $deflate.Write($body,0,$body.Length) } finally { $deflate.Dispose() }
                    $body = $memory.ToArray()
                } finally { $memory.Dispose() }
            }
            $offset = $file.Position
            $writer.Write([uint32]0x04034b50)
            $writer.Write([uint16]20)
            $writer.Write([uint16]0)
            $writer.Write([uint16]$member.Method)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint32]$member.Crc)
            $writer.Write([uint32]$body.Length)
            $writer.Write([uint32]$member.Length)
            $writer.Write([uint16]$name.Length)
            $writer.Write([uint16]0)
            $writer.Write($name)
            $writer.Write([byte[]]$body)
            $records += [pscustomobject]@{Member=$member; Name=$name; Size=$body.Length; Offset=$offset}
        }
        $central = $file.Position
        foreach ($record in $records) {
            $member = $record.Member
            $writer.Write([uint32]0x02014b50)
            $writer.Write([uint16]20)
            $writer.Write([uint16]20)
            $writer.Write([uint16]0)
            $writer.Write([uint16]$member.Method)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint32]$member.Crc)
            $writer.Write([uint32]$record.Size)
            $writer.Write([uint32]$member.Length)
            $writer.Write([uint16]$record.Name.Length)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint16]0)
            $writer.Write([uint32]0)
            $writer.Write([uint32]$record.Offset)
            $writer.Write([byte[]]$record.Name)
        }
        $centralSize = $file.Position - $central
        $writer.Write([uint32]0x06054b50)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)
        $writer.Write([uint16]$records.Count)
        $writer.Write([uint16]$records.Count)
        $writer.Write([uint32]$centralSize)
        $writer.Write([uint32]$central)
        $writer.Write([uint16]0)
    } finally { $writer.Dispose(); $file.Dispose() }
    return $path
}

function Get-Inventory {
    return [string]::Join("`n",[string[]]@(Get-ChildItem -LiteralPath $script:work -Force -Recurse |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:work.Length) }))
}

function Assert-Scan([string]$Path, [int]$Expected, [string]$Case) {
    Assert-LocalNoLink $Path
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $inventory = Get-Inventory
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $script:shell -NoProfile -ExecutionPolicy Bypass -File $script:entry -Archive $Path 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    $script:runs++
    $output = ($lines | ForEach-Object { $_.ToString() }) -join "`n"
    Assert-True ($code -eq $Expected) ($Case + ': wrong actual scanner exit.')
    if ($Expected -eq 0) {
        Assert-True ($output -match 'PASS: limited public-source ZIP content scan only') ($Case + ': clean control did not reach successful scan.')
        Assert-True ($output -match ('SHA256: ' + $hash.ToLowerInvariant())) ($Case + ': archive identity missing.')
    } else {
        Assert-True ($output -match 'REFUSED:') ($Case + ': refusal diagnostic missing.')
        Assert-True ($output -notmatch 'PASS:|SCANNED:') ($Case + ': corrupt member reached completed content scan.')
    }
    Assert-True ($output -match 'UNRUN:.*launcher GUI.*build.*game.*two-PC') ($Case + ': missing unrun scope.')
    Assert-True ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ceq $hash) ($Case + ': input archive changed.')
    Assert-True ((Get-Inventory) -ceq $inventory) ($Case + ': scan extracted or changed fixture inventory.')
    foreach ($canary in @($script:root,'integrity-canary.txt','empty-canary.txt','directory-canary','123456789','123456788')) {
        Assert-True (-not $output.Contains($canary)) ($Case + ': scanner disclosed private path, member name or content.')
    }
    Write-Output ('PASS: ' + $Case + '; actual scan exit ' + $code + '; input unchanged.')
}

try {
    Assert-LocalNoLink $entry
    Assert-LocalNoLink $work
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) { throw 'Actual scanner or Windows PowerShell unavailable.' }
    Add-Type -AssemblyName System.IO.Compression
    [void][IO.Directory]::CreateDirectory($work)
    $text = [Text.Encoding]::ASCII.GetBytes('123456789')
    $changed = [Text.Encoding]::ASCII.GetBytes('123456788')
    $empty = New-Object byte[] 0
    $clean = New-Member 'integrity-canary.txt' $text $knownCrc
    Assert-Scan (New-Fixture 'clean-stored.zip' @($clean)) 0 'clean stored CRC control'
    Assert-Scan (New-Fixture 'clean-deflate.zip' @((New-Member 'integrity-canary.txt' $text $knownCrc 8))) 0 'clean deflate CRC control'
    Assert-Scan (New-Fixture 'clean-empty.zip' @((New-Member 'empty-canary.txt' $empty 0))) 0 'clean empty-file CRC control'
    Assert-Scan (New-Fixture 'clean-directory.zip' @((New-Member 'directory-canary/' $empty 0),$clean)) 0 'clean empty-directory CRC control'

    Assert-Scan (New-Fixture 'wrong-stored-crc.zip' @((New-Member 'integrity-canary.txt' $text 1))) 1 'matching wrong stored header CRCs'
    Assert-Scan (New-Fixture 'changed-stored-content.zip' @((New-Member 'integrity-canary.txt' $changed $knownCrc))) 1 'stored content changed under intact CRC metadata'
    Assert-Scan (New-Fixture 'wrong-deflate-crc.zip' @((New-Member 'integrity-canary.txt' $text 1 8))) 1 'valid deflate content with matching wrong CRCs'
    Assert-Scan (New-Fixture 'wrong-empty-crc.zip' @((New-Member 'empty-canary.txt' $empty 1))) 1 'empty file with nonzero CRC'
    Assert-Scan (New-Fixture 'wrong-directory-crc.zip' @((New-Member 'directory-canary/' $empty 1),$clean)) 1 'empty directory with nonzero CRC'
    Assert-Scan (New-Fixture 'stored-length-short.zip' @((New-Member 'integrity-canary.txt' $text $knownCrc 0 -1))) 1 'stored declared length shorter than stored bytes'
    Assert-Scan (New-Fixture 'stored-length-long.zip' @((New-Member 'integrity-canary.txt' $text $knownCrc 0 1))) 1 'stored declared length longer than stored bytes'
    Write-Output ('PASS: public ZIP integrity; {0} assertions; {1} real scanner subprocesses. Harmless text fixtures retained under logs.' -f $checks,$runs)
    Write-Output 'UNRUN: Python suites, packagers, launcher GUI, build, game and two-PC play; no release acceptance.'
    exit 0
} catch {
    Write-Output ('FAIL: public ZIP integrity tests: ' + $_.Exception.Message)
    exit 1
}
