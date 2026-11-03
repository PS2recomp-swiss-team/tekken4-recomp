# Symbol work limits through the real ZIP scanner. Harmless text fixtures only.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-budget-symbols-' + [guid]::NewGuid().ToString('N'))
$ascii = [Text.Encoding]::ASCII
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

function Get-BytesHash([byte[]]$Data) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Data)) }
    finally { $sha.Dispose() }
}

function New-LiteralMember([string]$Name, [int]$Count, [bool]$WithDistance = $false) {
    # RFC 1951 fixed codes for A/newline are 01110001/00111010 in
    # transmission order. The three-bit header shifts consecutive pairs
    # into e4/72 bytes after the first 73 byte. Short words and lines keep
    # later text checks separate from this DEFLATE accounting test.
    # An optional length-three/distance-one copy adds two decoded symbols.
    $pairs = [int][Math]::Floor($Count/2)
    $text = "A`n" * $pairs
    if ($Count -band 1) { $text += 'A' }
    if ($WithDistance) { $text += ([string]$text[$text.Length-1]) * 3 }
    $data = $script:ascii.GetBytes($text)
    $rawPair = ([string][char]228) + [char]114
    $rawText = ([string][char]115) + ($rawPair * [int][Math]::Floor(($Count-1)/2))
    $pending = 4
    if (-not ($Count -band 1)) { $rawText += [char]228; $pending = 2 }
    $tail = if ($WithDistance) { ([string][char]$pending) + [char]2 + [char]0 } else { ([string][char]$pending) + [char]0 }
    $rawText += $tail
    $raw = [Text.Encoding]::GetEncoding(28591).GetBytes($rawText)
    $memory = New-Object IO.MemoryStream
    $zip = $null
    $stream = $null
    try {
        # Framework writer supplies the expected content CRC independently.
        $zip = New-Object IO.Compression.ZipArchive($memory, [IO.Compression.ZipArchiveMode]::Create, $true)
        $member = $zip.CreateEntry('crc', [IO.Compression.CompressionLevel]::NoCompression)
        $stream = $member.Open()
        $stream.Write($data,0,$data.Length)
        $stream.Dispose()
        $stream = $null
        $zip.Dispose()
        $zip = $null
        $crc = [BitConverter]::ToUInt32($memory.GetBuffer(),14)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $zip) { $zip.Dispose() }
        $memory.Dispose()
    }
    return [pscustomobject]@{Name=$Name; Data=$data; Raw=$raw; Crc=$crc; Symbols=($Count + $(if ($WithDistance) { 3 } else { 1 }))}
}

function New-VectorZip([string]$Name, [object[]]$Members) {
    $path = Join-Path $script:work $Name
    Assert-LocalNoLink $path
    $file = [IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $writer = New-Object IO.BinaryWriter($file)
    $records = New-Object 'Collections.Generic.List[object]'
    try {
        foreach ($member in $Members) {
            $nameBytes = $script:ascii.GetBytes($member.Name)
            $records.Add([pscustomobject]@{Member=$member; Offset=[uint32]$file.Position; NameBytes=$nameBytes})
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
        $central = [uint32]$file.Position
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
        $centralSize = [uint32]($file.Position - $central)
        $writer.Write([uint32]0x06054b50)
        foreach ($value in @(0,0,$Members.Count,$Members.Count)) { $writer.Write([uint16]$value) }
        $writer.Write([uint32]$centralSize)
        $writer.Write([uint32]$central)
        $writer.Write([uint16]0)
    } finally { $writer.Dispose() }

    # Independently decode every fixture, including refused cases, with the
    # framework reader. Compare exact bytes and the header's content CRC.
    $file = [IO.File]::OpenRead($path)
    $zip = $null
    try {
        $zip = New-Object IO.Compression.ZipArchive($file,[IO.Compression.ZipArchiveMode]::Read,$true)
        Assert-True ($zip.Entries.Count -eq $Members.Count) 'Fixture entry count differs.'
        for ($index = 0; $index -lt $Members.Count; $index++) {
            $stream = $zip.Entries[$index].Open()
            $decoded = New-Object IO.MemoryStream
            try {
                $stream.CopyTo($decoded)
                Assert-True ((Get-BytesHash $decoded.ToArray()) -ceq (Get-BytesHash $Members[$index].Data)) 'Fixture did not independently decode to expected bytes.'
                Assert-True ($decoded.Length -eq $Members[$index].Data.Length) 'Fixture decoded length differs.'
            } finally { $decoded.Dispose(); $stream.Dispose() }
        }
    } finally {
        if ($null -ne $zip) { $zip.Dispose() }
        $file.Dispose()
    }
    return $path
}

function Get-Inventory {
    return [string]::Join("`n",[string[]]@(Get-ChildItem -LiteralPath $script:work -Recurse -Force |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:work.Length) }))
}

function Assert-Scan([string]$Path, [bool]$Accepted, [string]$Label) {
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $inventory = Get-Inventory
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:entry + '" -Archive "' + $Path + '"'
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
        while (-not $process.WaitForExit(1000)) {
            if ($watch.Elapsed.TotalSeconds -gt 180) {
                $process.Kill()
                $process.WaitForExit()
                throw 'Real scanner timed out; timeout is a test failure, never a refusal pass.'
            }
        }
        $text = $stdout.Result + $stderr.Result
        $code = $process.ExitCode
    } finally { $watch.Stop(); $process.Dispose() }
    $script:runs++
    Assert-True ($code -eq $(if ($Accepted) { 0 } else { 1 })) ($Label + ': unexpected exit code.')
    if ($Accepted) {
        Assert-True ($text -match 'PASS: limited public-source ZIP content scan only') ($Label + ': clean control did not pass.')
        Assert-True ($text -match ('SHA256: ' + $hash)) ($Label + ': archive identity missing.')
        Assert-True ($text -match 'SCANNED: entries \d+; files \d+; bytes \d+\.') ($Label + ': content scan did not complete.')
    } else {
        Assert-True ($text -match 'REFUSED: ZIP input or scan failed\.') ($Label + ': refusal missing.')
        Assert-True ($text -notmatch 'PASS:|SCANNED:') ($Label + ': over-budget scan reached content completion.')
    }
    Assert-True ($text -match 'UNRUN:.*Python.*launcher GUI.*build.*game.*two-PC') ($Label + ': unrun evidence missing.')
    Assert-True (((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()) -ceq $hash) ($Label + ': input changed.')
    Assert-True ((Get-Inventory) -ceq $inventory) ($Label + ': scanner wrote or extracted files.')
    foreach ($canary in @($script:root,'budget-symbol-member',('A' * 32))) {
        Assert-True (-not $text.Contains($canary)) ($Label + ': output disclosed path, member or content.')
    }
    Write-Output ('PASS: ' + $Label + '; real scanner exit ' + $code + '; unchanged SHA256 ' + $hash + '; elapsed ' + $watch.ElapsedMilliseconds + ' ms.')
}

try {
    Assert-LocalNoLink $entry
    Assert-LocalNoLink $work
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) { throw 'Real entry or Windows PowerShell missing.' }
    Add-Type -AssemblyName System.IO.Compression
    [void][IO.Directory]::CreateDirectory($work)
    $small = New-LiteralMember 'budget-symbol-member-small.txt' 32
    $exact = New-LiteralMember 'budget-symbol-member-exact.txt' 2097151
    $over = New-LiteralMember 'budget-symbol-member-over.txt' 2097150 $true
    $halfA = New-LiteralMember 'budget-symbol-member-half-a.txt' 1048576
    $halfB = New-LiteralMember 'budget-symbol-member-half-b.txt' 1048576
    Assert-True ($exact.Symbols -eq 2097152) 'Exact fixture symbol count differs.'
    Assert-True ($over.Symbols -eq 2097153) 'Over fixture symbol count differs.'
    Assert-True ($halfA.Symbols -lt 2097152 -and $halfB.Symbols -lt 2097152 -and $halfA.Symbols+$halfB.Symbols -gt 2097152) 'Cumulative fixture does not isolate shared symbol budget.'
    $control = New-VectorZip 'small-control.zip' @($small)
    $boundary = New-VectorZip 'exact-symbol-budget.zip' @($exact)
    $excess = New-VectorZip 'over-symbol-budget.zip' @($over)
    $shared = New-VectorZip 'shared-symbol-budget.zip' @($halfA,$halfB)
    Assert-Scan $control $true 'small literal control'
    Assert-Scan $boundary $true 'exact symbol budget including end code'
    Assert-Scan $excess $false 'one symbol over budget including distance and end code'
    Assert-Scan $shared $false 'shared symbol budget across members'
    Write-Output ("PASS: public ZIP symbol work budget; {0} assertions, {1} real scanner subprocesses. Harmless fixtures retained under logs." -f $checks,$runs)
    Write-Output 'UNRUN: Python packagers and payload checks; launcher GUI; build; game; two-PC play; owner licence/publication review.'
    exit 0
} catch {
    Write-Output ('FAIL: public ZIP symbol work budget: ' + $_.Exception.Message)
    exit 1
}
