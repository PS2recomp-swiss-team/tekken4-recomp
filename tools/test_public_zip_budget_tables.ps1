# Huffman allocation limits through the real ZIP scanner. Harmless text only.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-budget-tables-' + [guid]::NewGuid().ToString('N'))
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

function Write-Bits($State, [int]$Value, [int]$Count) {
    for ($bit = 0; $bit -lt $Count; $bit++) {
        $State.Byte = $State.Byte -bor ((($Value -shr $bit) -band 1) -shl $State.Count)
        $State.Count++
        if ($State.Count -eq 8) {
            $State.Stream.WriteByte([byte]$State.Byte)
            $State.Byte = 0
            $State.Count = 0
        }
    }
}

function New-DynamicMember([string]$Name, [int[]]$Widths) {
    # Independent RFC 1951 writer. A complete skew literal tree has one code
    # at lengths 1..N-1 and two at N. Only the all-ones EOB code is emitted.
    # Code-length symbols 0..15 each have length 4; distance tree is empty.
    # Each block therefore allocates 16 + 2^N + 1 lookup slots in the scanner.
    $memory = New-Object IO.MemoryStream
    $state = [pscustomobject]@{Stream=$memory; Byte=0; Count=0}
    try {
        $order = @(16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15)
        for ($block = 0; $block -lt $Widths.Length; $block++) {
            $width = $Widths[$block]
            Assert-True ($width -ge 1 -and $width -le 15) 'Fixture tree width outside RFC bounds.'
            Write-Bits $state ([int]($block -eq $Widths.Length-1)) 1
            Write-Bits $state 2 2
            Write-Bits $state 0 5
            Write-Bits $state 0 5
            Write-Bits $state 15 4
            foreach ($symbol in $order) { Write-Bits $state $(if ($symbol -lt 16) { 4 } else { 0 }) 3 }
            for ($symbol = 0; $symbol -lt 258; $symbol++) {
                $length = if ($symbol -lt $width) { [Math]::Min($symbol+1,$width) } elseif ($symbol -eq 256) { $width } else { 0 }
                $reverse = 0
                for ($bit = 0; $bit -lt 4; $bit++) { $reverse = ($reverse -shl 1) -bor (($length -shr $bit) -band 1) }
                Write-Bits $state $reverse 4
            }
            Write-Bits $state ((1 -shl $width)-1) $width
        }
        if ($state.Count) { $memory.WriteByte([byte]$state.Byte) }
        return [pscustomobject]@{Name=$Name; Method=8; Raw=$memory.ToArray(); Data=(New-Object byte[] 0); Crc=[uint32]0}
    } finally { $memory.Dispose() }
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
            foreach ($value in @(20,0,$member.Method,0,0)) { $writer.Write([uint16]$value) }
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
            foreach ($value in @(20,20,0,$member.Method,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]$member.Crc)
            $writer.Write([uint32]$member.Raw.Length)
            $writer.Write([uint32]$member.Data.Length)
            $writer.Write([uint16]$record.NameBytes.Length)
            foreach ($value in @(0,0,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]0)
            $writer.Write([uint32]$record.Offset)
            $writer.Write([byte[]]$record.NameBytes)
        }
        $centralSize = [uint32]($file.Position-$central)
        $writer.Write([uint32]0x06054b50)
        foreach ($value in @(0,0,$Members.Count,$Members.Count)) { $writer.Write([uint16]$value) }
        $writer.Write([uint32]$centralSize)
        $writer.Write([uint32]$central)
        $writer.Write([uint16]0)
    } finally { $writer.Dispose() }
    return $path
}

function Assert-IndependentRead([string]$Path, [object[]]$Members) {
    $file = [IO.File]::OpenRead($Path)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file,[IO.Compression.ZipArchiveMode]::Read,$true)
        try {
            Assert-True ($zip.Entries.Count -eq $Members.Count) 'Independent ZIP entry count differs.'
            for ($index = 0; $index -lt $Members.Count; $index++) {
                $stream = $zip.Entries[$index].Open()
                $memory = New-Object IO.MemoryStream
                try {
                    $stream.CopyTo($memory)
                    Assert-True ([Convert]::ToBase64String($memory.ToArray()) -ceq [Convert]::ToBase64String($Members[$index].Data)) 'Independent framework decompression differs.'
                } finally { $memory.Dispose(); $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
}

function Get-Inventory {
    return [string]::Join("`n",[string[]]@(Get-ChildItem -LiteralPath $script:work -Recurse -Force |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:work.Length) }))
}

function Assert-Scan([string]$Path, [bool]$Accepted, [int]$Entries, [string]$Label) {
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
        [void]$process.Start()
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'Real scanner timed out; no completed scan proof.'
        }
        $text = $outTask.Result + $errTask.Result
        $code = $process.ExitCode
    } finally { $watch.Stop(); $process.Dispose() }
    $script:runs++
    Assert-True ($code -eq $(if ($Accepted) { 0 } else { 1 })) ($Label + ': unexpected scanner exit.')
    if ($Accepted) {
        Assert-True ($text -match 'PASS: limited public-source ZIP content scan only') ($Label + ': pass missing.')
        Assert-True ($text -match ('SCANNED: entries ' + $Entries + '; files ' + $Entries + '; bytes 3\.')) ($Label + ': scan counts differ.')
        Assert-True ($text -match ('SHA256: ' + $hash)) ($Label + ': input identity missing.')
    } else {
        Assert-True ($text -match 'REFUSED: ZIP input or scan failed\.') ($Label + ': refusal missing.')
        Assert-True ($text -notmatch 'PASS:|SCANNED:') ($Label + ': failed scan advertised completion.')
    }
    Assert-True ($text -match 'UNRUN:.*Python.*launcher GUI.*build.*game.*two-PC') ($Label + ': unrun evidence missing.')
    Assert-True (((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()) -ceq $hash) ($Label + ': input changed.')
    Assert-True ((Get-Inventory) -ceq $inventory) ($Label + ': scanner wrote files.')
    foreach ($canary in @($script:root,'table-budget-canary')) {
        Assert-True (-not $text.Contains($canary)) ($Label + ': output disclosed a path or member.')
    }
    Write-Output ('PASS: ' + $Label + '; actual scanner; unchanged; elapsed ' + $watch.ElapsedMilliseconds + ' ms.')
}

try {
    Assert-LocalNoLink $entry
    Assert-LocalNoLink $work
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) { throw 'Real entry or Windows PowerShell missing.' }
    Add-Type -AssemblyName System.IO.Compression
    [void][IO.Directory]::CreateDirectory($work)
    $control = [pscustomobject]@{Name='table-budget-canary-control.txt'; Method=0; Raw=$ascii.GetBytes('abc'); Data=$ascii.GetBytes('abc'); Crc=[uint32]0x352441c2}
    # 31*(32768+17) + (8+16+64+256+1024+2048+4096+8192+16384) + 9*17
    # is exactly 1048576. All cases are far below block and symbol budgets.
    $widths = [int[]](@(15) * 31 + @(3,4,6,8,10,11,12,13,14))
    $slots = [long]0
    foreach ($width in $widths) { $slots += (1 -shl $width) + 17 }
    Assert-True ($slots -eq 1048576) 'Exact table-allocation fixture arithmetic differs.'

    $small = New-DynamicMember 'table-budget-canary-small.txt' @(15)
    $exact = New-DynamicMember 'table-budget-canary-exact.txt' $widths
    $over = New-DynamicMember 'table-budget-canary-over.txt' ([int[]]($widths + @(1)))
    $first = New-DynamicMember 'table-budget-canary-first.txt' ([int[]]$widths[0..19])
    $second = New-DynamicMember 'table-budget-canary-second.txt' ([int[]]$widths[20..39])
    $last = New-DynamicMember 'table-budget-canary-last.txt' @(1)
    $cases = @(
        @('clean.zip',@($control,$small),$true,'small valid dynamic control'),
        @('exact-single.zip',@($control,$exact),$true,'exact table slots within one member'),
        @('over-single.zip',@($control,$over),$false,'table slots exceed within one member'),
        @('exact-multiple.zip',@($control,$first,$second),$true,'exact table slots across members'),
        @('over-multiple.zip',@($control,$first,$second,$last),$false,'table slots cumulative across members')
    )
    foreach ($case in $cases) {
        $members = [object[]]$case[1]
        $path = New-VectorZip $case[0] $members
        Assert-IndependentRead $path $members
        Assert-Scan $path $case[2] $members.Count $case[3]
    }
    Write-Output ("PASS: public ZIP table budget; {0} assertions, {1} real scanner subprocesses. Harmless fixtures retained under logs." -f $checks,$runs)
    Write-Output 'UNRUN: Python packagers and payload checks; launcher GUI; build; game; two-PC play; owner licence/publication review.'
    exit 0
} catch {
    Write-Output ('FAIL: public ZIP table budget: ' + $_.Exception.Message)
    exit 1
}
