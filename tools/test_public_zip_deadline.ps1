# Real ZIP entry deadline tests. All members are harmless source text.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-deadline-' + [guid]::NewGuid().ToString('N'))
$fixtures = Join-Path $work 'fixtures'
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
        if ((Test-Path -LiteralPath $current) -and
            ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Linked test input refused.'
        }
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function New-StoredZip([string]$Name, [int]$Count) {
    # Each stored member is abc, whose standard CRC-32 is 352441c2.
    # Many ordinary members exercise real directory/content work, not a sleep.
    $path = Join-Path $script:fixtures $Name
    Assert-LocalNoLink $path
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = New-Object IO.BinaryWriter($stream)
    $records = New-Object 'Collections.Generic.List[object]'
    try {
        for ($index = 0; $index -lt $Count; $index++) {
            $nameBytes = [Text.Encoding]::ASCII.GetBytes(('deadline-member-{0:d4}.txt' -f $index))
            $records.Add([pscustomobject]@{ Name=$nameBytes; Offset=[uint32]$stream.Position })
            $writer.Write([uint32]0x04034b50)
            foreach ($value in @(20,0,0,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]0x352441c2)
            $writer.Write([uint32]3)
            $writer.Write([uint32]3)
            $writer.Write([uint16]$nameBytes.Length)
            $writer.Write([uint16]0)
            $writer.Write([byte[]]$nameBytes)
            $writer.Write([byte[]]@(97,98,99))
        }
        $central = [uint32]$stream.Position
        foreach ($record in $records) {
            $writer.Write([uint32]0x02014b50)
            foreach ($value in @(20,20,0,0,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]0x352441c2)
            $writer.Write([uint32]3)
            $writer.Write([uint32]3)
            $writer.Write([uint16]$record.Name.Length)
            foreach ($value in @(0,0,0,0)) { $writer.Write([uint16]$value) }
            $writer.Write([uint32]0)
            $writer.Write([uint32]$record.Offset)
            $writer.Write([byte[]]$record.Name)
        }
        $centralSize = [uint32]($stream.Position - $central)
        $writer.Write([uint32]0x06054b50)
        $writer.Write([uint16]0)
        $writer.Write([uint16]0)
        $writer.Write([uint16]$Count)
        $writer.Write([uint16]$Count)
        $writer.Write([uint32]$centralSize)
        $writer.Write([uint32]$central)
        $writer.Write([uint16]0)
    } finally { $writer.Dispose() }
    return $path
}

function Assert-FrameworkRead([string]$Path, [int]$Count) {
    $file = [IO.File]::OpenRead($Path)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Read, $true)
        try {
            Assert-True ($zip.Entries.Count -eq $Count) 'Independent ZIP entry count differs.'
            foreach ($member in $zip.Entries) {
                $stream = $member.Open()
                $memory = New-Object IO.MemoryStream
                try {
                    $stream.CopyTo($memory)
                    Assert-True ([Text.Encoding]::ASCII.GetString($memory.ToArray()) -ceq 'abc') 'Independent ZIP member bytes differ.'
                } finally { $memory.Dispose(); $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
}

function Get-Inventory {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $script:fixtures -Recurse -Force |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:fixtures.Length) }))
}

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-Entry([string]$Path, [string]$Limit, [string]$Label) {
    $beforeHash = Get-Hash $Path
    $beforeInventory = Get-Inventory
    $command = "`$ProgressPreference = 'SilentlyContinue'; & '" + $script:entry.Replace("'", "''") + "' -Archive '" + $Path.Replace("'", "''") + "'"
    if ($Limit) { $command += " -TimeoutSeconds '" + $Limit.Replace("'", "''") + "'" }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-True ($proc.Start()) 'Real scanner supervisor did not start.'
        $script:runs++
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        while (-not $proc.WaitForExit(100)) {
            if ($watch.Elapsed.TotalSeconds -ge 150) {
                $proc.Kill()
                $null = $proc.WaitForExit(5000)
                throw 'Test watchdog expired; this is a failed test, never a scanner refusal.'
            }
        }
        $watch.Stop()
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stdout.txt')), $out)
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '.stderr.txt')), $err)
        Assert-True (-not $err.Trim()) 'Real scanner wrote unexpected stderr.'
        Assert-True (-not $out.Contains($script:root)) 'Real scanner disclosed the working-copy path.'
        Assert-True (-not $out.Contains('deadline-member-')) 'Real scanner disclosed a member name.'
        Assert-True ($out -notmatch '(?m)^abc\r?$') 'Real scanner disclosed member content.'
        Assert-True ((Get-Hash $Path) -ceq $beforeHash) 'Real scanner changed its input archive.'
        Assert-True ((Get-Inventory) -ceq $beforeInventory) 'Real scanner extracted or changed fixture inventory.'
        # An exclusive reopen checks that completed/refused scans released input handles.
        $exclusive = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $exclusive.Dispose()
        Assert-True $true 'Exclusive archive reopen completed.'
        return [pscustomobject]@{ Code=$proc.ExitCode; Text=$out; Seconds=$watch.Elapsed.TotalSeconds; Hash=$beforeHash }
    } finally { $watch.Stop(); $proc.Dispose() }
}

try {
    foreach ($path in @($entry, $work, $fixtures)) { Assert-LocalNoLink $path }
    Add-Type -AssemblyName System.IO.Compression
    [void][IO.Directory]::CreateDirectory($fixtures)
    $clean = New-StoredZip 'clean.zip' 1
    $many = New-StoredZip 'many-members.zip' 1000
    Assert-FrameworkRead $clean 1
    Assert-FrameworkRead $many 1000

    foreach ($case in @(@($clean, 'clean'), @($many, 'many-default'))) {
        $result = Invoke-Entry $case[0] '' $case[1]
        Assert-True ($result.Code -eq 0 -and $result.Text -match 'PASS: limited public-source ZIP') 'Valid default-budget control did not complete and pass.'
        Assert-True ($result.Text -match ('SHA256: ' + $result.Hash)) 'Completed scan omitted the exact archive identity.'
        Assert-True ($result.Text -match 'SCANNED:') 'Completed control omitted scan completion.'
    }

    foreach ($number in @(1,2)) {
        $result = Invoke-Entry $many '1' ('timeout-' + $number)
        Assert-True ($result.Code -eq 1) 'Short process deadline did not refuse.'
        Assert-True ($result.Text -match 'REFUSED: ZIP scan exceeded its process deadline\.') 'Short process deadline did not report the timeout refusal.'
        Assert-True ($result.Text -notmatch 'PASS:|SCANNED:|SHA256:') 'Timed-out scan claimed completion or an archive identity.'
        Assert-True ($result.Seconds -lt 15) 'One-second worker deadline took at least fifteen seconds through the real entry.'
        Assert-True ($result.Text -match 'UNRUN:.*launcher GUI.*build.*game.*two-PC') 'Timeout omitted unrun acceptance routes.'
    }
    $result = Invoke-Entry $many '' 'many-after-timeouts'
    Assert-True ($result.Code -eq 0 -and $result.Text -match 'PASS: limited public-source ZIP') 'The unchanged timed-out ZIP did not complete afterward with the default budget.'
    Assert-True ($result.Text -match ('SHA256: ' + $result.Hash)) 'Post-timeout scan omitted the unchanged archive identity.'

    foreach ($limit in @('0','601','-1')) {
        $result = Invoke-Entry $clean $limit ('invalid-' + $limit.Replace('-','minus'))
        Assert-True ($result.Code -eq 1) 'Invalid deadline was accepted.'
        Assert-True ($result.Text -match 'REFUSED: -TimeoutSeconds must be an integer from 1 through 600\.') 'Invalid deadline did not produce the sanitized refusal.'
        Assert-True ($result.Text -notmatch 'PASS:|SCANNED:|SHA256:') 'Invalid deadline reached scan completion.'
    }
    Write-Output ('PASS: ZIP process deadline; {0} assertions through {1} real scanner subprocesses.' -f $checks, $runs)
    Write-Output 'Two genuine many-member scans timed out; the same unchanged ZIP completed with the default budget.'
    Write-Output 'Fixtures and subprocess output retained under logs/public-zip-deadline-*.'
    Write-Output 'Exclusive input reopen ran after each child; independent orphan-process enumeration is unavailable in this sandbox.'
    Write-Output 'UNRUN: launcher GUI, Python release tools, build, game and two-PC play. Release remains NO-GO.'
    exit 0
} catch {
    Write-Output ('FAIL: ZIP deadline tests: ' + $_.Exception.Message)
    exit 1
}
