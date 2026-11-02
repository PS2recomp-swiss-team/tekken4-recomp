<#
.SYNOPSIS
Stage or scan a public source tree. Never publish or change the input tree.
.DESCRIPTION
PowerShell 5.1 supervised entry point. The worker has a 120-second deadline by
default, including startup, operation and output collection. Wrapper preflight
and OS cleanup are outside that deadline. A timeout discards worker output;
any partial staging is retained, unapproved. Nothing is published.
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$Out,
    [string[]]$Include,
    [string]$ScanOnly,
    [string]$TimeoutSeconds = '120'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\', '/')
$prefix = $workspace + [IO.Path]::DirectorySeparatorChar
$failure = 'Public tree input or operation failed.'
$proc = $null
$started = $false
$unrun = 'UNRUN: Python packagers and release payload checks; launcher GUI; build; game; two-PC play.'
$retained = 'Any staging output is unapproved and retained for owner inspection. Nothing published.'
$marker = 'PUBLIC_TREE_WORKER_COMPLETED'

function Assert-LocalWorker([string]$Path) {
    if (-not $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Outside working copy.' }
    $current = $workspace
    foreach ($part in @('') + $Path.Substring($prefix.Length).Split([IO.Path]::DirectorySeparatorChar)) {
        if ($part) { $current = Join-Path $current $part }
        $item = Get-Item -LiteralPath $current -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Worker reparse point.' }
    }
    if ($item.PSIsContainer) { throw 'Worker is not a file.' }
}

try {
    $seconds = 0
    if (-not [int]::TryParse($TimeoutSeconds, [ref]$seconds) -or $seconds -lt 1 -or $seconds -gt 600) {
        $failure = '-TimeoutSeconds must be an integer from 1 through 600.'
        throw 'Invalid deadline.'
    }
    $worker = Join-Path $PSScriptRoot 'public_tree_worker.ps1'
    Assert-LocalWorker $worker
    $shell = Join-Path $PSHOME 'powershell.exe'
    $shellItem = Get-Item -LiteralPath $shell -Force
    if ($shellItem.PSIsContainer -or ($shellItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Unavailable shell.'
    }
    # Preserve bound argument names and Include arrays without source interpolation.
    # Base64 also keeps PowerShell's Unicode quote delimiters out of child code.
    $arguments = @{}
    foreach ($name in @('Source', 'Out', 'Include', 'ScanOnly')) {
        if ($PSBoundParameters.ContainsKey($name)) { $arguments[$name] = $PSBoundParameters[$name] }
    }
    $workerData = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($worker))
    $argumentData = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((ConvertTo-Json -InputObject $arguments -Compress -Depth 4)))
    $command = "`$ProgressPreference = 'SilentlyContinue'; [Console]::OutputEncoding = New-Object Text.UTF8Encoding(`$false); `$worker = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$workerData')); `$values = ConvertFrom-Json ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$argumentData'))); `$parameters = @{}; foreach (`$property in `$values.PSObject.Properties) { if (`$property.Name -eq 'Include') { `$parameters[`$property.Name] = [string[]]`$property.Value } else { `$parameters[`$property.Name] = `$property.Value } }; & `$worker @parameters; `$code = `$LASTEXITCODE; Write-Output '$marker'; exit `$code"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $shell
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
    # Match the original entry's native relative-path resolution.
    $info.WorkingDirectory = [IO.Path]::GetFullPath('.')
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
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
    $completed = $completed -and ($clock.ElapsedMilliseconds -le $seconds * 1000)
    if (-not $completed) {
        $failure = 'Public tree operation exceeded its process deadline; worker termination was not confirmed.'
        if (-not $proc.HasExited) { $proc.Kill() }
        if ($proc.WaitForExit(5000)) { $failure = 'Public tree operation exceeded its process deadline.' }
        throw 'Worker deadline.'
    }
    $output = $stdout.GetAwaiter().GetResult()
    $errors = $stderr.GetAwaiter().GetResult()
    if ($proc.ExitCode -notin @(0, 1) -or -not $output.EndsWith($marker + [Environment]::NewLine)) {
        throw 'Worker completion was not confirmed.'
    }
    $output = $output.Substring(0, $output.Length - $marker.Length - [Environment]::NewLine.Length).TrimEnd("`r", "`n")
    if ($proc.ExitCode -eq 0) {
        if ($errors.Trim() -or -not ($output.Contains('Public tree scan passed. Owner content and licence review is still required. Nothing published.') -or
                $output.Contains('Postwrite public scan passed. Owner content and licence review is still required. Nothing published.'))) {
            throw 'Worker success output incomplete.'
        }
        Write-Output $output
        Write-Output $unrun
        exit 0
    }
    # Only completed, handled refusals may supply findings. Worker exceptions
    # produce static stdout messages; arbitrary stderr is never forwarded.
    if ($errors.Trim() -or -not $output.Contains('REFUSED: ')) { throw 'Worker refusal output incomplete.' }
    Write-Output $output
    Write-Output $retained
    Write-Output $unrun
    exit 1
} catch {
    Write-Output ('REFUSED: ' + $failure)
    Write-Output $retained
    Write-Output $unrun
    exit 1
} finally {
    if ($proc) {
        if ($started -and -not $proc.HasExited) {
            try { $proc.Kill(); $null = $proc.WaitForExit(5000) } catch { }
        }
        $proc.Dispose()
    }
}
