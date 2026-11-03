# Run export and scan compatibility through the actual supervised tree entry.
# Harmless source fixtures stay under logs. Nothing is published or deleted.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$relativeWork = 'logs/public-tree-deadline-compat-' + [Guid]::NewGuid().ToString('N')
$work = Join-Path $root $relativeWork
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = 0
$runs = 0
$failure = 'Preflight or entry subprocess failed.'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failure = $Message; throw 'Compatibility assertion failed.' }
    $script:checks++
}

function ConvertTo-ValueExpression([string]$Value) {
    # Path values are data, including PowerShell's Unicode quote delimiters.
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Value))
    return "([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('" + $encoded + "')))"
}

function Write-Text([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, $script:utf8)
}

function Get-TreeSnapshot([string]$Path) {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $Path -Force -Recurse |
        Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($Path.Length)
            if ($_.PSIsContainer) { 'DIR ' + $relative }
            else { $relative + ' ' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }))
}

function Invoke-RealEntry([hashtable]$Arguments, [string]$WorkingDirectory = $script:root) {
    $command = '$ProgressPreference = ''SilentlyContinue''; & ' + (ConvertTo-ValueExpression $script:entry)
    foreach ($option in @('Source', 'Out', 'Include', 'ScanOnly', 'TimeoutSeconds')) {
        if (-not $Arguments.ContainsKey($option)) { continue }
        $values = @($Arguments[$option])
        $command += ' -' + $option + ' '
        if ($option -eq 'Include') {
            $command += '@(' + [string]::Join(',', [string[]]@($values | ForEach-Object { ConvertTo-ValueExpression $_ })) + ')'
        } else {
            if ($values.Count -ne 1) { throw 'Unexpected compatibility argument.' }
            $command += ConvertTo-ValueExpression $values[0]
        }
    }
    $command += '; exit $LASTEXITCODE'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
    # A real native working directory catches relative-path transport regressions.
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    try {
        if (-not $proc.Start()) { throw 'Entry subprocess did not start.' }
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $complete = $proc.WaitForExit(150000)
        if ($complete) {
            $remaining = [Math]::Max(0, 150000 - [int]$clock.ElapsedMilliseconds)
            $complete = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($outTask, $errTask), $remaining)
        }
        if (-not $complete -or $clock.ElapsedMilliseconds -gt 150000) {
            $script:failure = 'Compatibility test watchdog expired; this is a failed test, not an entry refusal.'
            try {
                foreach ($record in @(Get-CimInstance Win32_Process -Filter ('ParentProcessId = ' + $proc.Id) -ErrorAction Stop)) {
                    $child = $null
                    try {
                        $child = [Diagnostics.Process]::GetProcessById([int]$record.ProcessId)
                        if (-not $child.HasExited) { $child.Kill(); $null = $child.WaitForExit(5000) }
                    } catch [ArgumentException] {
                        # The direct child already exited.
                    } finally { if ($child) { $child.Dispose() } }
                }
            } catch {
                $script:failure = 'Compatibility watchdog expired; descendant cleanup inventory was unavailable.'
            } finally {
                if (-not $proc.HasExited) { $proc.Kill(); $null = $proc.WaitForExit(5000) }
            }
            throw 'Compatibility watchdog failure.'
        }
        $script:runs++
        return [pscustomobject]@{
            Code = $proc.ExitCode
            Text = $outTask.GetAwaiter().GetResult()
            ErrorText = $errTask.GetAwaiter().GetResult()
        }
    } finally { $proc.Dispose() }
}

function Assert-CleanResult($Result, [bool]$Export) {
    Assert-True ($Result.Code -eq 0) 'Clean entry did not exit zero.'
    Assert-True ([string]::IsNullOrWhiteSpace($Result.ErrorText)) 'Clean entry wrote stderr.'
    Assert-True (-not $Result.Text.Contains($script:root)) 'Clean entry disclosed the working-copy path.'
    Assert-True (-not $Result.Text.Contains('TRANSPORT_EXECUTED')) 'A path value became executed command text.'
    Assert-True ($Result.Text -match 'Owner content and licence review is still required\. Nothing published\.') 'Clean entry lost its review limitation.'
    Assert-True ($Result.Text -notmatch '(?i)REFUSED|exceeded|failed') 'Clean entry also claimed failure.'
    if ($Export) {
        Assert-True ($Result.Text -match 'Staged 3 files; omitted 0 image files; cleaned 1 patches with byte-identical diff parts\.') 'Include array changed the exported selection.'
        Assert-True ($Result.Text -match 'Postwrite public scan passed\.') 'Export lost its postwrite scan claim.'
    } else {
        Assert-True ($Result.Text -match 'Public tree scan passed\.') 'Scan lost its completed scan claim.'
    }
}

try {
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) { throw 'Entry and Windows PowerShell must exist.' }
    [void][IO.Directory]::CreateDirectory($work)
    $special = "space ' & ; % ! ( ) [ ] dollar-" + [char]36 + '-tick-' + [char]96 + '-unicode-' + [char]0xfc
    $smart = 'smart-' + [char]0x2019 + '; harmless ' + [char]0x2018 + [char]0x201c + [char]0x201d
    $includeName = $special + ' ' + $smart + ' $(Write-Output TRANSPORT_EXECUTED).txt'
    $patchName = 'patches/01-fixture.patch'
    $source = Join-Path $work ('source ' + $smart + ' ' + $special)
    Write-Text (Join-Path $source 'LICENSE') "Synthetic compatibility notice; GPL-3.0.`n"
    Write-Text (Join-Path $source $includeName) "Harmless compatibility source text.`n"
    Write-Text (Join-Path $source 'excluded.txt') "This harmless file must not be included.`n"
    $diff = "diff --git a/fixture.txt b/fixture.txt`r`n--- a/fixture.txt`r`n+++ b/fixture.txt`r`n@@ -0,0 +1 @@`r`n+Harmless compatible patch.`r`n"
    $patch = "From: Synthetic Contributor`r`nX-Mailer: harmless transport fixture`r`nSubject: [PATCH] compatibility`r`n`r`n" + $diff
    Write-Text (Join-Path $source $patchName) $patch
    $before = Get-TreeSnapshot $source

    # Include is a real string array, with names containing delimiters and spaces.
    foreach ($case in @(
            [pscustomobject]@{ Name = 'default'; Timeout = $null },
            [pscustomobject]@{ Name = ('explicit ' + $smart + ' ' + $special); Timeout = '120' })) {
        $output = Join-Path $work $case.Name
        $arguments = @{ Source = $source; Out = $output; Include = @('LICENSE', $includeName, $patchName) }
        if ($case.Timeout) { $arguments.TimeoutSeconds = $case.Timeout }
        $result = Invoke-RealEntry $arguments
        Assert-CleanResult $result $true
        foreach ($name in @('LICENSE', $includeName)) {
            Assert-True ([IO.File]::Exists((Join-Path $output $name))) 'Include array lost a selected file.'
            Assert-True ((Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA256).Hash -ceq
                (Get-FileHash -LiteralPath (Join-Path $output $name) -Algorithm SHA256).Hash) 'Export changed ordinary source bytes.'
        }
        Assert-True (-not [IO.File]::Exists((Join-Path $output 'excluded.txt'))) 'Include array became a full source export.'
        $cleanPatch = [IO.File]::ReadAllText((Join-Path $output $patchName), $utf8)
        Assert-True (-not $cleanPatch.Contains('X-Mailer:')) 'Export retained transport metadata.'
        Assert-True ($cleanPatch.Contains('From: Synthetic Contributor')) 'Export lost author attribution.'
        $boundary = $cleanPatch.IndexOf('diff --git ', [StringComparison]::Ordinal)
        Assert-True ($boundary -ge 0 -and $cleanPatch.Substring($boundary) -ceq $diff) 'Export changed patch diff bytes.'
        Assert-True ((Get-TreeSnapshot $source) -ceq $before) 'Export changed the input tree.'
        $outputBefore = Get-TreeSnapshot $output
        $result = Invoke-RealEntry @{ ScanOnly = $output }
        Assert-CleanResult $result $false
        Assert-True ((Get-TreeSnapshot $output) -ceq $outputBefore) 'Scan changed staged files.'
    }

    # Relative arguments must resolve in the caller's native cwd, including a
    # Source name with spaces and Unicode quotes. Include remains source-relative.
    $relativeOutput = 'relative-output'
    $result = Invoke-RealEntry @{
        Source = [IO.Path]::GetFileName($source)
        Out = $relativeOutput
        Include = @('LICENSE', $includeName, $patchName)
    } $work
    Assert-CleanResult $result $true
    $relativeOutputPath = Join-Path $work $relativeOutput
    Assert-True ([IO.File]::Exists((Join-Path $relativeOutputPath $includeName))) 'Relative output escaped its native caller directory.'
    Assert-True ((Get-TreeSnapshot $relativeOutputPath) -ceq (Get-TreeSnapshot (Join-Path $work 'default'))) 'Relative export changed selected names or bytes.'
    Assert-True ((Get-TreeSnapshot $source) -ceq $before) 'Relative export changed source files.'
    $relativeBefore = Get-TreeSnapshot $relativeOutputPath
    $result = Invoke-RealEntry @{ ScanOnly = $relativeOutput } $work
    Assert-CleanResult $result $false
    Assert-True ((Get-TreeSnapshot $relativeOutputPath) -ceq $relativeBefore) 'Relative scan changed staged files.'

    # Refusal must preserve content categories and never print source content.
    $refused = Join-Path $work 'content-refusal'
    Write-Text (Join-Path $refused 'LICENSE') "Synthetic compatibility notice; GPL-3.0.`n"
    Write-Text (Join-Path $refused 'fixture.txt') ("# automatically" + " generated harmless fixture text.`n")
    $refusedBefore = Get-TreeSnapshot $refused
    $result = Invoke-RealEntry @{ ScanOnly = $refused }
    Assert-True ($result.Code -eq 1) 'Content refusal did not preserve exit one.'
    Assert-True ($result.Text -match 'generated game code marker') 'Content refusal lost its category.'
    Assert-True ($result.Text -notmatch '(?i)scan passed|Staged \d+ files') 'Content refusal claimed completion success.'
    Assert-True (-not $result.Text.Contains('harmless fixture text.')) 'Content refusal disclosed source text.'
    Assert-True ((Get-TreeSnapshot $refused) -ceq $refusedBefore) 'Content refusal changed source files.'

    $invalidOutput = Join-Path $work 'invalid-output'
    $result = Invoke-RealEntry @{ ScanOnly = $source; Source = $source; Out = $invalidOutput }
    Assert-True ($result.Code -eq 1) 'Combined scan/export arguments did not refuse.'
    Assert-True ($result.Text -notmatch '(?i)scan passed|Staged \d+ files') 'Invalid arguments claimed success.'
    Assert-True (-not [IO.Directory]::Exists($invalidOutput)) 'Invalid arguments created staging.'
    Assert-True ((Get-TreeSnapshot $source) -ceq $before) 'Invalid arguments changed source files.'

    Write-Output ('PASS: supervised tree compatibility; {0} assertions through {1} real entry subprocesses.' -f $checks, $runs)
    Write-Output ('Evidence: ' + $relativeWork + '; harmless fixtures retained.')
    Write-Output 'UNRUN: launcher GUI, Python release tools, build, game and two-PC play; no release acceptance is claimed.'
    exit 0
} catch {
    Write-Output ('FAIL: supervised tree compatibility tests: ' + $failure)
    Write-Output ('Evidence: ' + $relativeWork + '; harmless fixtures retained.')
    exit 1
}
