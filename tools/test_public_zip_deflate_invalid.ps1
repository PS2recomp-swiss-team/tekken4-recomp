# Malformed raw DEFLATE fixtures through the real ZIP scanner. No extraction.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-deflate-invalid-' + [guid]::NewGuid().ToString('N'))
$checks = 0
$runs = 0

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

# Independent literal bit fixtures. Headers/extras are LSB-first; Huffman
# symbols are the canonical code's MSB-first bits (RFC 1951 section 3.1.1).
function Add-Bits($Bits, [int]$Value, [int]$Count) {
    for ($i = 0; $i -lt $Count; $i++) { $Bits.Add(($Value -shr $i) -band 1) }
}

function Add-FixedSymbol($Bits, [int]$Symbol) {
    if ($Symbol -le 143) { $code = 48 + $Symbol; $width = 8 }
    elseif ($Symbol -le 255) { $code = 400 + $Symbol - 144; $width = 9 }
    elseif ($Symbol -le 279) { $code = $Symbol - 256; $width = 7 }
    else { $code = 192 + $Symbol - 280; $width = 8 }
    for ($i = $width - 1; $i -ge 0; $i--) { $Bits.Add(($code -shr $i) -band 1) }
}

function Convert-Bits($Bits) {
    $bytes = New-Object byte[] ([int][Math]::Ceiling($Bits.Count / 8.0))
    for ($i = 0; $i -lt $Bits.Count; $i++) {
        $bytes[[int][Math]::Floor($i / 8.0)] = $bytes[[int][Math]::Floor($i / 8.0)] -bor ($Bits[$i] -shl ($i % 8))
    }
    return ,$bytes
}

function New-FixedFixture([int[]]$Symbols, [int]$Distance = -1) {
    $bits = New-Object 'Collections.Generic.List[int]'
    Add-Bits $bits 3 3
    foreach ($symbol in $Symbols) { Add-FixedSymbol $bits $symbol }
    if ($Distance -ge 0) {
        for ($i = 4; $i -ge 0; $i--) { $bits.Add(($Distance -shr $i) -band 1) }
        Add-FixedSymbol $bits 256
    }
    return ,(Convert-Bits $bits)
}

function New-DynamicFixture([int[]]$CodeLengths, [int[]]$TailValues = @(), [int[]]$TailWidths = @(), [int]$Hlit = 0) {
    $bits = New-Object 'Collections.Generic.List[int]'
    Add-Bits $bits 5 3
    Add-Bits $bits $Hlit 5
    Add-Bits $bits 0 5
    Add-Bits $bits 0 4
    foreach ($length in $CodeLengths) { Add-Bits $bits $length 3 }
    for ($i = 0; $i -lt $TailValues.Length; $i++) { Add-Bits $bits $TailValues[$i] $TailWidths[$i] }
    return ,(Convert-Bits $bits)
}

function New-Fixture([string]$FileName, [byte[]]$Compressed, [int]$Length = 0, [uint32]$Crc = 0) {
    $path = Join-Path $script:work $FileName
    Assert-LocalNoLink $path
    $file = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $writer = New-Object IO.BinaryWriter($file)
    $records = @()
    $members = @(
        [pscustomobject]@{Name='format-canary.txt'; Body=$Compressed; Method=8; Length=$Length; Crc=$Crc},
        [pscustomobject]@{Name='control-canary.txt'; Body=[Text.Encoding]::ASCII.GetBytes('123456789'); Method=0; Length=9; Crc=[Convert]::ToUInt32('cbf43926',16)}
    )
    try {
        foreach ($member in $members) {
            $name = [Text.Encoding]::ASCII.GetBytes($member.Name)
            $offset = $file.Position
            $writer.Write([uint32]0x04034b50)
            $writer.Write([uint16]20); $writer.Write([uint16]0); $writer.Write([uint16]$member.Method)
            $writer.Write([uint16]0); $writer.Write([uint16]0)
            $writer.Write([uint32]$member.Crc); $writer.Write([uint32]$member.Body.Length); $writer.Write([uint32]$member.Length)
            $writer.Write([uint16]$name.Length); $writer.Write([uint16]0)
            $writer.Write($name); $writer.Write([byte[]]$member.Body)
            $records += [pscustomobject]@{Member=$member; Name=$name; Offset=$offset}
        }
        $central = $file.Position
        foreach ($record in $records) {
            $member = $record.Member
            $writer.Write([uint32]0x02014b50)
            $writer.Write([uint16]20); $writer.Write([uint16]20)
            $writer.Write([uint16]0); $writer.Write([uint16]$member.Method)
            $writer.Write([uint16]0); $writer.Write([uint16]0)
            $writer.Write([uint32]$member.Crc); $writer.Write([uint32]$member.Body.Length); $writer.Write([uint32]$member.Length)
            $writer.Write([uint16]$record.Name.Length); $writer.Write([uint16]0); $writer.Write([uint16]0)
            $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint32]0)
            $writer.Write([uint32]$record.Offset); $writer.Write([byte[]]$record.Name)
        }
        $size = $file.Position - $central
        $writer.Write([uint32]0x06054b50)
        $writer.Write([uint16]0); $writer.Write([uint16]0)
        $writer.Write([uint16]$records.Count); $writer.Write([uint16]$records.Count)
        $writer.Write([uint32]$size); $writer.Write([uint32]$central); $writer.Write([uint16]0)
    } finally { $writer.Dispose(); $file.Dispose() }
    return $path
}

function Get-Inventory {
    return [string]::Join("`n",[string[]]@(Get-ChildItem -LiteralPath $script:work -Force -Recurse |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:work.Length) }))
}

function Assert-Scan([string]$Path, [int]$Expected, [string]$Case) {
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
        Assert-True ($output -match 'PASS: limited public-source ZIP content scan only') ($Case + ': clean control did not pass.')
        Assert-True ($output -match ('SHA256: ' + $hash.ToLowerInvariant())) ($Case + ': archive identity missing.')
    } else {
        Assert-True ($output -match 'REFUSED:') ($Case + ': refusal missing.')
        Assert-True ($output -notmatch 'PASS:|SCANNED:') ($Case + ': malformed member reached completed scan.')
    }
    Assert-True ($output -match 'UNRUN:.*launcher GUI.*build.*game.*two-PC') ($Case + ': unrun scope missing.')
    Assert-True ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ceq $hash) ($Case + ': archive changed.')
    Assert-True ((Get-Inventory) -ceq $inventory) ($Case + ': scanner changed fixture inventory.')
    foreach ($canary in @($script:root,'format-canary.txt','control-canary.txt','123456789')) {
        Assert-True (-not $output.Contains($canary)) ($Case + ': scanner disclosed path, member or content.')
    }
    Write-Output ('PASS: ' + $Case + '; actual scan exit ' + $code + '; input unchanged.')
}

try {
    Assert-LocalNoLink $entry
    Assert-LocalNoLink $work
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) { throw 'Actual scanner or Windows PowerShell unavailable.' }
    [void][IO.Directory]::CreateDirectory($work)
    Assert-Scan (New-Fixture 'clean-fixed-empty.zip' ([byte[]]@(3,0))) 0 'complete fixed empty control'
    Assert-Scan (New-Fixture 'clean-stored-empty.zip' ([byte[]]@(1,0,0,255,255))) 0 'complete stored empty control'
    $fixedText = New-FixedFixture @(49,50,51,52,53,54,55,56,57,256)
    Assert-Scan (New-Fixture 'clean-fixed-text.zip' $fixedText 9 ([Convert]::ToUInt32('cbf43926',16))) 0 'complete literal fixed text control'

    $cases = @(
        @{Name='no-stream'; Bytes=[byte[]]@(); Case='missing compressed stream'},
        @{Name='observed-one-byte'; Bytes=[byte[]]@(1); Case='observed truncated empty stored block'},
        @{Name='stored-missing-nlen'; Bytes=[byte[]]@(1,0,0); Case='stored complement truncated'},
        @{Name='stored-bad-nlen'; Bytes=[byte[]]@(1,0,0,0,0); Case='stored complement mismatch'},
        @{Name='stored-missing-data'; Bytes=[byte[]]@(1,1,0,254,255); Length=1; Case='stored body truncated'},
        @{Name='missing-final'; Bytes=[byte[]]@(0,0,0,255,255); Case='complete nonfinal block without final block'},
        @{Name='reserved-block'; Bytes=[byte[]]@(7); Case='reserved block type'},
        @{Name='fixed-truncated'; Bytes=[byte[]]@(3); Case='fixed end-of-block truncated'},
        @{Name='fixed-reserved-literal'; Bytes=(New-FixedFixture @(286)); Case='reserved fixed literal-length symbol'},
        @{Name='distance-before-output'; Bytes=(New-FixedFixture @(257) 0); Length=3; Case='distance before any output'},
        @{Name='reserved-distance'; Bytes=(New-FixedFixture @(49,257) 30); Length=4; Case='reserved distance symbol'},
        @{Name='distance-too-far'; Bytes=(New-FixedFixture @(49,257) 1); Length=4; Case='distance exceeds output history'},
        @{Name='empty-code-tree'; Bytes=(New-DynamicFixture @(0,0,0,0)); Case='empty dynamic code-length tree'},
        @{Name='oversubscribed-code-tree'; Bytes=(New-DynamicFixture @(1,1,1,1)); Case='oversubscribed dynamic code-length tree'},
        @{Name='incomplete-code-tree'; Bytes=(New-DynamicFixture @(2,0,0,0)); Case='incomplete dynamic code-length tree'},
        @{Name='repeat-without-prior'; Bytes=(New-DynamicFixture @(1,0,0,1) @(1,0) @(1,2)); Case='repeat previous length without previous length'},
        @{Name='repeat-overflow'; Bytes=(New-DynamicFixture @(0,0,1,1) @(1,127,1,127) @(1,7,1,7)); Case='code-length repeat exceeds tree size'},
        @{Name='missing-end-code'; Bytes=(New-DynamicFixture @(0,0,1,1) @(1,127,1,109) @(1,7,1,7)); Case='dynamic tree lacks end-of-block code'},
        @{Name='reserved-hlit'; Bytes=(New-DynamicFixture @(0,0,0,0) @() @() 31); Case='reserved literal-length alphabet size'},
        @{Name='trailing-byte'; Bytes=[byte[]]@(3,0,0); Case='trailing compressed byte'},
        @{Name='concatenated-streams'; Bytes=[byte[]]@(3,0,3,0); Case='concatenated compressed streams'}
    )
    foreach ($case in $cases) {
        $declaredLength = if ($case.ContainsKey('Length')) { $case.Length } else { 0 }
        Assert-Scan (New-Fixture ($case.Name + '.zip') $case.Bytes $declaredLength) 1 $case.Case
    }
    Assert-Scan (New-Fixture 'empty-declared-one.zip' ([byte[]]@(3,0)) 1) 1 'complete empty stream declared nonempty'
    Assert-Scan (New-Fixture 'text-declared-eight.zip' $fixedText 8 ([Convert]::ToUInt32('cbf43926',16))) 1 'complete text exceeds declared output length'
    Write-Output ('PASS: public ZIP malformed DEFLATE; {0} assertions; {1} real scanner subprocesses. Harmless fixtures retained under logs.' -f $checks,$runs)
    Write-Output 'UNRUN: Python suites, packagers, launcher GUI, build, game and two-PC play; no release acceptance.'
    exit 0
} catch {
    Write-Output ('FAIL: public ZIP malformed DEFLATE tests: ' + $_.Exception.Message)
    exit 1
}
