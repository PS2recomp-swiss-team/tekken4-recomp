<#
.SYNOPSIS
Read a local public-source ZIP without extracting or executing its members.
.DESCRIPTION
This is a conservative source/privacy check, not a player-package validator.
The archive must be inside this working copy. Nothing is written or published.
A child scanner has a 120-second deadline by default. Timeout refuses without
printing partial scan output. This does not bound supervisor startup or cleanup.
#>
[CmdletBinding()]
param(
    [string]$Archive,
    [string]$TimeoutSeconds = '120'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$prefix = $workspace + [IO.Path]::DirectorySeparatorChar
$failure = 'ZIP input or scan failed.'
$proc = $null
$started = $false

function Assert-LocalRegularFile([string]$Path) {
    if (-not $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Outside working copy.'
    }
    $current = $workspace
    $relative = $Path.Substring($prefix.Length)
    foreach ($part in @('') + $relative.Split([IO.Path]::DirectorySeparatorChar)) {
        if ($part) { $current = Join-Path $current $part }
        if (-not (Test-Path -LiteralPath $current)) { throw 'Missing input.' }
        $item = Get-Item -LiteralPath $current -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point.' }
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Not a file.' }
}

try {
    $seconds = 0
    if (-not [int]::TryParse($TimeoutSeconds, [ref]$seconds) -or $seconds -lt 1 -or $seconds -gt 600) {
        $failure = '-TimeoutSeconds must be an integer from 1 through 600.'
        throw 'Invalid deadline.'
    }
    if ([string]::IsNullOrWhiteSpace($Archive)) {
        $failure = '-Archive is required.'
        throw 'Missing archive.'
    }
    $archivePath = [IO.Path]::GetFullPath($Archive)
    if (-not $archivePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        $failure = 'archive must stay inside this working copy.'
        throw 'Outside working copy.'
    }
    if ([IO.Path]::GetExtension($archivePath) -ine '.zip') { throw 'Not a ZIP filename.' }
    Assert-LocalRegularFile $archivePath
    $worker = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'public_zip_scan_worker.ps1'))
    Assert-LocalRegularFile $worker
    $shell = Join-Path $PSHOME 'powershell.exe'
    $shellItem = Get-Item -LiteralPath $shell -Force
    if ($shellItem.PSIsContainer -or ($shellItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Unavailable shell.'
    }
    # Transport paths as Base64 values, never PowerShell source literals.
    # PowerShell recognizes Unicode quotation marks as delimiters too.
    $workerData = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($worker))
    $archiveData = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($archivePath))
    $command = "`$ProgressPreference = 'SilentlyContinue'; `$worker = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$workerData')); `$archive = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$archiveData')); & `$worker -Archive `$archive; exit `$LASTEXITCODE"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $shell
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
    $info.WorkingDirectory = $workspace
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    $clock = [Diagnostics.Stopwatch]::StartNew()
    if (-not $proc.Start()) { throw 'Worker did not start.' }
    $started = $true
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    $remaining = [Math]::Max(0, $seconds * 1000 - [int]$clock.ElapsedMilliseconds)
    $completed = $proc.WaitForExit($remaining)
    if ($completed) {
        $remaining = [Math]::Max(0, $seconds * 1000 - [int]$clock.ElapsedMilliseconds)
        $completed = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), $remaining)
    }
    # A zero wait can report an already finished worker after startup or
    # scheduling used the budget. Completion still has to meet the deadline.
    $completed = $completed -and ($clock.ElapsedMilliseconds -le $seconds * 1000)
    if (-not $completed) {
        $failure = 'ZIP scan exceeded its process deadline; worker termination was not confirmed.'
        if (-not $proc.HasExited) { $proc.Kill() }
        if ($proc.WaitForExit(5000)) {
            $failure = 'ZIP scan exceeded its process deadline.'
        }
        throw 'Worker deadline.'
    }
    $out = $stdout.GetAwaiter().GetResult()
    $err = $stderr.GetAwaiter().GetResult()
    if ($proc.ExitCode -notin @(0, 1) -or $err.Trim()) { throw 'Worker failed.' }
    # A worker launch failure or incomplete output must never become success.
    if (-not $out.Contains('UNRUN: Python packagers and release payload checks; launcher GUI; build; game; two-PC play.') -or
        ($proc.ExitCode -eq 0 -and (-not $out.Contains('SHA256: ') -or -not $out.Contains('SCANNED: ') -or
            -not $out.Contains('PASS: limited public-source ZIP content scan only.')))) {
        throw 'Worker output incomplete.'
    }
    Write-Output $out.TrimEnd("`r", "`n")
    exit $proc.ExitCode
} catch {
    # Exception text can contain an untrusted member name, path or private value.
    Write-Output ('REFUSED: ' + $failure)
    Write-Output 'UNRUN: Python packagers and release payload checks; launcher GUI; build; game; two-PC play.'
    exit 1
} finally {
    if ($proc) {
        if ($started -and -not $proc.HasExited) {
            try { $proc.Kill(); $null = $proc.WaitForExit(5000) } catch { }
        }
        $proc.Dispose()
    }
}
