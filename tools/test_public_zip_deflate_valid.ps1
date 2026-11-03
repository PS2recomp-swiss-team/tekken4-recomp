# Valid raw DEFLATE vectors through the real scanner. Harmless text only.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-deflate-valid-' + [guid]::NewGuid().ToString('N'))
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

function New-Vector([string]$Name, [string]$Text, [string]$Raw, [string]$Crc) {
    $bytes = [byte[]]@($Raw.Split('-') | ForEach-Object { [Convert]::ToByte($_,16) })
    return [pscustomobject]@{Name=$Name; Data=$script:ascii.GetBytes($Text); Raw=$bytes; Crc=[Convert]::ToUInt32($Crc,16)}
}

function New-VectorZip([string]$Name, [object[]]$Members) {
    # Literal compressed bytes and CRCs are independent of the scanner helper.
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
            foreach ($value in @(20,0,8,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]$member.Crc)
            $writer.Write([uint32]$member.Raw.Length)
            $writer.Write([uint32]$member.Data.Length)
            $writer.Write([uint16]$nameBytes.Length)
            $writer.Write([uint16]0)
            $writer.Write([byte[]]$nameBytes)
            $writer.Write([byte[]]$member.Raw)
        }
        $central = [uint32]$stream.Position
        foreach ($record in $records) {
            $member = $record.Member
            $writer.Write([uint32]0x02014b50)
            foreach ($value in @(20,20,0,8,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]$member.Crc)
            $writer.Write([uint32]$member.Raw.Length)
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

function Get-Inventory {
    return [string]::Join("`n",[string[]]@(Get-ChildItem -LiteralPath $script:work -Recurse -Force |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:work.Length) }))
}

function Assert-Accepted([string]$Path, [int]$Entries, [long]$Bytes, [string]$Label) {
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
    Assert-True ($code -eq 0) ($Label + ': valid stream refused.')
    Assert-True ($text -match 'PASS: limited public-source ZIP content scan only') ($Label + ': limited scan pass missing.')
    Assert-True ($text -match ('SCANNED: entries ' + $Entries + '; files ' + $Entries + '; bytes ' + $Bytes + '\.')) ($Label + ': scanned counts differ.')
    Assert-True ($text -match ('SHA256: ' + $hash)) ($Label + ': archive identity missing.')
    Assert-True ($text -match 'UNRUN:.*Python.*launcher GUI.*build.*game.*two-PC') ($Label + ': unrun evidence missing.')
    Assert-True (((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()) -ceq $hash) ($Label + ': input changed.')
    Assert-True ((Get-Inventory) -ceq $inventory) ($Label + ': scanner extracted or wrote files.')
    foreach ($canary in @($script:root,'deflate-valid-member','abcabcabcabcabcabc','Harmless independent deflater control.')) {
        Assert-True (-not $text.Contains($canary)) ($Label + ': output disclosed path, member or content.')
    }
    Write-Output ('PASS: ' + $Label + '; real scan accepted; unchanged; elapsed ' + $watch.ElapsedMilliseconds + ' ms.')
}

try {
    Assert-LocalNoLink $entry
    Assert-LocalNoLink $work
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) { throw 'Real entry or Windows PowerShell missing.' }
    Add-Type -AssemblyName System.IO.Compression
    [void][IO.Directory]::CreateDirectory($work)

    $stored = New-Vector 'deflate-valid-member-stored.txt' 'abc' '01-03-00-fc-ff-61-62-63' '352441c2'
    $fixed = New-Vector 'deflate-valid-member-fixed.txt' 'abc' '4b-4c-4a-06-00' '352441c2'
    $emptyStored = New-Vector 'deflate-valid-member-empty-stored.txt' '' '01-00-00-ff-ff' '00000000'
    $emptyFixed = New-Vector 'deflate-valid-member-empty-fixed.txt' '' '03-00' '00000000'
    # Same empty fixed stream; the six unused final-byte bits need not be zero.
    $padding = New-Vector 'deflate-valid-member-padding.txt' '' '03-fc' '00000000'
    # Nonfinal stored abc, then final empty fixed block; both padding sites nonzero.
    $multi = New-Vector 'deflate-valid-member-multi.txt' 'abc' 'f8-03-00-fc-ff-61-62-63-03-fc' '352441c2'
    $backref = New-Vector 'deflate-valid-member-backref.txt' 'abcabcabcabcabcabc' '4b-4c-4a-4e-44-45-00' 'dc26c004'
    $overlap = New-Vector 'deflate-valid-member-overlap.txt' ('a' * 40) '4b-4c-24-0e-00-00' 'c95b8a25'
    # Dynamic literal-only tree: A and end-of-block have length 1; distance
    # tree is empty. Code-length symbols 0 and 1 each have length 1. This is
    # an independent small dynamic vector with no code-length repeat symbols.
    $dynamic = New-Vector 'deflate-valid-member-dynamic.txt' 'A' '05-c0-01-04-00-00-00-00-10-00-00-00-00-00-00-00-00-01-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-80-04' 'd3d99e8b'

    $cases = @(
        @('stored-block.zip',$stored,'literal stored block'),
        @('fixed-block.zip',$fixed,'literal fixed block'),
        @('empty-stored.zip',$emptyStored,'empty stored block'),
        @('empty-fixed.zip',$emptyFixed,'empty fixed block'),
        @('padding.zip',$padding,'legal unused final padding'),
        @('multiblock.zip',$multi,'stored and fixed blocks with padding'),
        @('backref.zip',$backref,'fixed length-distance backreference'),
        @('overlap.zip',$overlap,'overlapping distance-one copy'),
        @('dynamic.zip',$dynamic,'dynamic literal-only tree')
    )
    foreach ($case in $cases) {
        $path = New-VectorZip $case[0] @($case[1])
        Assert-Accepted $path 1 $case[1].Data.Length $case[2]
    }
    $members = @($dynamic,$emptyStored,$backref,$emptyFixed,$stored,$overlap)
    $path = New-VectorZip 'member-reset.zip' $members
    Assert-Accepted $path $members.Count 62 'different block types and member state reset'

    # Independent framework encoder supplies a larger dynamic stream. The
    # literal vectors above do not depend on this encoder or scanner helpers.
    $path = Join-Path $work 'framework-dynamic.zip'
    $data = $ascii.GetBytes(('Harmless independent deflater control.' + "`n") * 3000)
    $file = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file,[IO.Compression.ZipArchiveMode]::Create,$true)
        try {
            $member = $zip.CreateEntry('deflate-valid-member-framework.txt',[IO.Compression.CompressionLevel]::Optimal)
            $stream = $member.Open()
            try { $stream.Write($data,0,$data.Length) } finally { $stream.Dispose() }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
    $zipBytes = [IO.File]::ReadAllBytes($path)
    $rawStart = 30 + [BitConverter]::ToUInt16($zipBytes,26)
    Assert-True ([BitConverter]::ToUInt16($zipBytes,8) -eq 8) 'Framework control is not method 8.'
    Assert-True ((($zipBytes[$rawStart] -shr 1) -band 3) -eq 2) 'Framework control does not exercise a dynamic block.'
    Assert-Accepted $path 1 $data.Length 'independent framework dynamic stream'

    Write-Output ("PASS: public ZIP valid DEFLATE; {0} assertions, {1} real scanner subprocesses. Harmless fixtures retained under logs." -f $checks,$runs)
    Write-Output 'UNRUN: Python packagers and payload checks; launcher GUI; build; game; two-PC play; owner licence/publication review.'
    exit 0
} catch {
    Write-Output ('FAIL: public ZIP valid DEFLATE: ' + $_.Exception.Message)
    exit 1
}
