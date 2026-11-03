# Run compatibility cases through the real supervised ZIP scanner entry.
# Harmless text fixtures remain under logs; no archive member is extracted.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-deadline-compat-' + [Guid]::NewGuid().ToString('N'))
$checks = 0
$runs = 0
$failure = 'Preflight or scanner subprocess failed.'
$utf8 = New-Object Text.UTF8Encoding($false)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failure = $Message; throw 'Compatibility assertion failed.' }
    $script:checks++
}

function ConvertTo-ValueExpression([string]$Value) {
    # Only ASCII base64 becomes PowerShell source. Smart quote characters in
    # input are PowerShell delimiters too; ASCII quote doubling is insufficient.
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Value))
    return "([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('" + $encoded + "')))"
}

function New-TextZip([string]$Name, [string]$Text) {
    $path = Join-Path $script:work $Name
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            $member = $zip.CreateEntry('notes.txt', [IO.Compression.CompressionLevel]::NoCompression)
            $target = $member.Open()
            try {
                $bytes = $script:utf8.GetBytes($Text)
                $target.Write($bytes, 0, $bytes.Length)
            } finally { $target.Dispose() }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
    return $path
}

function Get-FixtureSnapshot {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $script:work -Force -Recurse |
        Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($script:work.Length)
            if ($_.PSIsContainer) { 'DIR ' + $relative }
            else { $relative + ' ' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }))
}

function Invoke-RealEntry([string[]]$Arguments) {
    # Encode each value before making EncodedCommand source. Encoding the whole
    # command alone would still allow quote delimiters in an input path.
    $command = '$ProgressPreference = ''SilentlyContinue''; & ' + (ConvertTo-ValueExpression $script:entry)
    for ($index = 0; $index -lt $Arguments.Count; $index += 2) {
        $option = $Arguments[$index]
        if ($option -notin @('-Archive', '-TimeoutSeconds') -or $index + 1 -ge $Arguments.Count) {
            throw 'Unexpected compatibility test argument.'
        }
        $command += ' ' + $option + ' ' + (ConvertTo-ValueExpression $Arguments[$index + 1])
    }
    $command += '; exit $LASTEXITCODE'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    try {
        if (-not $proc.Start()) { throw 'Scanner subprocess did not start.' }
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        # The entry's default worker budget is 120 seconds. Leave cleanup time
        # before the test watchdog; watchdog expiry is always a failed test.
        if (-not $proc.WaitForExit(150000)) {
            $script:failure = 'Compatibility case exceeded the test deadline; this is a test failure.'
            try {
                # Capture only this test process's direct children before
                # stopping it. Never search by name or guess a worker PID.
                foreach ($record in @(Get-CimInstance Win32_Process -Filter ('ParentProcessId = ' + $proc.Id) -ErrorAction Stop)) {
                    $child = $null
                    try {
                        $child = [Diagnostics.Process]::GetProcessById([int]$record.ProcessId)
                        if (-not $child.HasExited) { $child.Kill(); $null = $child.WaitForExit(10000) }
                    } catch [ArgumentException] {
                        # It already exited between inventory and handle open.
                    } finally { if ($child) { $child.Dispose() } }
                }
            } catch {
                # Some source-only environments deny CIM inventory. The outer
                # timeout still fails; descendant cleanup cannot be proved.
                $script:failure = 'Compatibility test timed out; worker cleanup inventory was unavailable.'
            } finally {
                if (-not $proc.HasExited) { $proc.Kill(); $null = $proc.WaitForExit(10000) }
            }
            throw 'Compatibility case exceeded the test deadline; this is a test failure.'
        }
        $script:runs++
        return [pscustomobject]@{
            Code = $proc.ExitCode
            Text = $outTask.GetAwaiter().GetResult()
            ErrorText = $errTask.GetAwaiter().GetResult()
        }
    } finally { $proc.Dispose() }
}

function Assert-NoDisclosure($Result) {
    Assert-True ([string]::IsNullOrWhiteSpace($Result.ErrorText)) 'Scanner wrote unexpected stderr.'
    Assert-True (-not $Result.Text.Contains($script:root)) 'Scanner disclosed the working-copy path.'
    Assert-True (-not $Result.Text.Contains('notes.txt')) 'Scanner disclosed an archive member name.'
    Assert-True (-not $Result.Text.Contains('Compatibility control text.')) 'Scanner disclosed archive content.'
}

try {
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) {
        throw 'Real scanner entry and Windows PowerShell must exist.'
    }
    Add-Type -AssemblyName System.IO.Compression
    [void][IO.Directory]::CreateDirectory($work)
    $cleanText = "Compatibility control text.`n"
    $specialName = "space ' & ; % ! ( ) [ ] dollar-" + [char]36 + '-tick-' + [char]96 + '-unicode-' + [char]0xfc + '.zip'
    $smartName = 'smart-' + [char]0x2019 + '; harmless ' + [char]0x2018 + [char]0x201c + [char]0x201d + " ' dollar-" + [char]36 + '-tick-' + [char]96 + '-unicode-' + [char]0xfc + '.zip'
    $clean = New-TextZip 'plain.zip' $cleanText
    $special = New-TextZip $specialName $cleanText
    $smart = New-TextZip $smartName $cleanText
    $refusal = New-TextZip 'content-refusal.zip' ("# automatically" + " generated harmless fixture text.`n")
    $malformed = Join-Path $work 'malformed.zip'
    [IO.File]::WriteAllText($malformed, "Not a ZIP; harmless text only.`n", $utf8)
    $before = Get-FixtureSnapshot

    # Omitted timeout and an explicit generous timeout must keep clean output.
    foreach ($case in @(
            [pscustomobject]@{ Path = $clean; Arguments = @('-Archive', $clean) },
            [pscustomobject]@{ Path = $special; Arguments = @('-Archive', $special, '-TimeoutSeconds', '120') },
            [pscustomobject]@{ Path = $smart; Arguments = @('-Archive', $smart) })) {
        $result = Invoke-RealEntry $case.Arguments
        Assert-True ($result.Code -eq 0) 'Clean compatibility archive did not pass.'
        $hash = (Get-FileHash -LiteralPath $case.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        Assert-True ($result.Text -match ('(?m)^SHA256: ' + $hash + '\s*$')) 'Completed scan did not preserve the archive hash output.'
        $bytes = $utf8.GetByteCount($cleanText)
        Assert-True ($result.Text -match ('SCANNED: entries 1; files 1; bytes ' + $bytes + '\.')) 'Completed scan did not preserve entry/file/byte counts.'
        Assert-True ($result.Text -match '(?m)^PASS: limited public-source ZIP content scan only\.') 'Completed clean scan lost its limited pass message.'
        Assert-True ($result.Text -notmatch '(?m)^REFUSED:') 'Completed clean scan also claimed refusal.'
        Assert-True ($result.Text -match 'UNRUN:.*Python.*launcher GUI.*build.*game.*two-PC') 'Completed scan lost its unrun acceptance statement.'
        Assert-NoDisclosure $result
        Assert-True ((Get-FixtureSnapshot) -ceq $before) 'Clean scanner execution changed or extracted fixtures.'
    }

    $result = Invoke-RealEntry @('-Archive', $refusal)
    Assert-True ($result.Code -eq 1) 'Content refusal did not preserve exit 1.'
    Assert-True ($result.Text -match 'SCANNED: entries 1; files 1; bytes \d+\.') 'Content refusal did not complete scanning.'
    Assert-True ($result.Text -match 'REFUSED: member 1: generated game code marker') 'Content refusal lost the existing category.'
    Assert-True ($result.Text -notmatch '(?m)^PASS:') 'Content refusal printed a pass.'
    Assert-NoDisclosure $result
    Assert-True ((Get-FixtureSnapshot) -ceq $before) 'Content refusal changed or extracted fixtures.'

    foreach ($arguments in @(
            [pscustomobject]@{ Value = @('-Archive', $malformed) },
            [pscustomobject]@{ Value = @('-Archive', (Join-Path $work 'missing.zip')) },
            [pscustomobject]@{ Value = @() })) {
        $result = Invoke-RealEntry $arguments.Value
        Assert-True ($result.Code -eq 1 -and $result.Text -match '(?m)^REFUSED:') 'Malformed or absent archive did not refuse.'
        Assert-True ($result.Text -notmatch '(?m)^(?:PASS|SCANNED|SHA256):') 'Input refusal claimed a completed scan.'
        Assert-NoDisclosure $result
        Assert-True ((Get-FixtureSnapshot) -ceq $before) 'Input refusal changed or extracted fixtures.'
    }

    Write-Output ('PASS: supervised ZIP compatibility; {0} assertions through {1} real scanner subprocesses; fixtures retained under logs.' -f $checks, $runs)
    Write-Output 'UNRUN: launcher GUI, Python release tools, build, game and two-PC play; no release acceptance is claimed.'
    exit 0
} catch {
    # Do not print native exception details, which may contain local paths.
    Write-Output ('FAIL: supervised ZIP compatibility tests: ' + $failure)
    exit 1
}
