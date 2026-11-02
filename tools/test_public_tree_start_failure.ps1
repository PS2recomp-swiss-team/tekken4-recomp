# Exercise real OS worker-start refusal through the public-tree entry.
# Large Include arrays are built in the caller, never interpolated into code.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$relativeWork = 'logs/public-tree-start-failure-' + [Guid]::NewGuid().ToString('N')
$work = Join-Path $root $relativeWork
$checks = 0
$runs = 0
$failure = 'Worker-start test preflight failed.'
$utf8 = New-Object Text.UTF8Encoding($false)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failure = $Message; throw 'Worker-start assertion failed.' }
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
            throw 'Linked test path refused.'
        }
        if ($current.Equals($script:root, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-TreeSnapshot([string]$Path) {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $Path -Force -Recurse |
        Sort-Object FullName | ForEach-Object {
            Assert-LocalNoLink $_.FullName
            $relative = $_.FullName.Substring($Path.Length + 1).Replace('\', '/')
            if ($_.PSIsContainer) { 'DIR ' + $relative }
            else { $relative + ' ' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }))
}

function Get-CodeSnapshot {
    return [string]::Join("`n", [string[]]@(foreach ($name in @(
            'publish_public_tree.ps1', 'public_tree_worker.ps1', 'public_tree_scan.ps1',
            'public_patch_headers.ps1', 'test_public_tree_start_failure.ps1')) {
        $path = Join-Path $PSScriptRoot $name
        Assert-LocalNoLink $path
        $name + ' ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }))
}

function Assert-NativeCommandLimit {
    # Supporting OS probe only. The four production-entry cases below supply
    # acceptance evidence; a native probe alone would not exercise the wrapper.
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -Command exit 91 ' + ('x' * 40000)
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    $started = $false
    $nativeCode = 0
    try {
        try { $started = $proc.Start() }
        catch {
            $errorItem = $_.Exception
            while ($errorItem -and -not ($errorItem -is [ComponentModel.Win32Exception])) {
                $errorItem = $errorItem.InnerException
            }
            if ($errorItem) { $nativeCode = $errorItem.NativeErrorCode }
        }
        Assert-True (-not $started) 'Supporting oversized native command unexpectedly started.'
        Assert-True ($nativeCode -eq 206) 'Supporting OS probe did not refuse an oversized command with native error 206.'
        [IO.File]::WriteAllText((Join-Path $script:work 'native-probe.txt'),
            'Supporting native probe: command exceeded 40000 characters; Process.Start refused with error 206. No probe child started.', $script:utf8)
    } finally {
        if ($started -and -not $proc.HasExited) {
            try { $proc.Kill(); $null = $proc.WaitForExit(5000) } catch { }
        }
        $proc.Dispose()
    }
}

function Invoke-Entry([string]$Source, [string]$Out, [int]$Count, [string]$Label) {
    $payload = @{ Entry=$script:entry; Source=$Source; Out=$Out; Count=$Count } | ConvertTo-Json -Compress
    $data = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
    $command = "`$ProgressPreference='SilentlyContinue'; `$p=ConvertFrom-Json ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$data'))); [string[]]`$include=@('member.txt') + (@('LICENSE') * `$p.Count); & `$p.Entry -Source `$p.Source -Out `$p.Out -Include `$include -TimeoutSeconds 10; exit `$LASTEXITCODE"
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    Assert-True ($info.Arguments.Length -lt 10000) 'Caller command is too large to isolate worker startup.'
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    $started = $false
    try {
        if (-not $proc.Start()) { throw 'Entry process did not start.' }
        $started = $true
        $script:runs++
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $complete = $proc.WaitForExit(45000)
        if ($complete) {
            $remaining = [Math]::Max(0, 45000 - [int]$watch.ElapsedMilliseconds)
            $complete = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), $remaining)
        }
        if (-not $complete -or $watch.ElapsedMilliseconds -gt 45000) {
            $script:failure = 'Outer watchdog expired; no entry result accepted. Descendant absence is unproved.'
            throw 'Entry watchdog expired.'
        }
        $result = [pscustomobject]@{
            Code=$proc.ExitCode; Text=$stdout.GetAwaiter().GetResult(); ErrorText=$stderr.GetAwaiter().GetResult()
        }
        $safeOutput = [regex]::Replace($result.Text, [regex]::Escape($script:root), '<working-copy>',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $safeError = ''
        if (-not [string]::IsNullOrWhiteSpace($result.ErrorText)) { $safeError = 'Nonempty stderr withheld.' }
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '-stdout.txt')), $safeOutput, $script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '-stderr.txt')), $safeError, $script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '-exit.txt')), [string]$result.Code, $script:utf8)
        Assert-True ([string]::IsNullOrWhiteSpace($result.ErrorText)) 'Real entry wrote unexpected stderr.'
        Assert-True ($result.Text -notmatch [regex]::Escape($script:root)) 'Real entry disclosed the working-copy path.'
        Assert-True ($result.Text -notmatch '(?i)exception|member\.txt|Harmless') 'Real entry disclosed exception or fixture details.'
        Assert-True ($result.Text.Contains('UNRUN: Python packagers')) 'Real entry omitted its unrun limitations.'
        return $result
    } finally {
        if ($started -and -not $proc.HasExited) {
            try { $proc.Kill(); $null = $proc.WaitForExit(5000) } catch { }
        }
        $proc.Dispose()
    }
}

function Assert-Control($Result, [string]$Out, [string]$Snapshot) {
    Assert-True ($Result.Code -eq 0) 'Small-array export control did not exit zero.'
    Assert-True ($Result.Text.Contains('Staged 2 files; omitted 0 image files; cleaned 0 patches with byte-identical diff parts.')) 'Small-array export did not complete its selection.'
    Assert-True ($Result.Text.Contains('Postwrite public scan passed.')) 'Small-array export did not finish its postwrite scan.'
    Assert-True ($Result.Text -notmatch '(?i)REFUSED|failed|deadline') 'Small-array control also reported failure.'
    Assert-True ((Get-TreeSnapshot $Out) -ceq $Snapshot) 'Small-array export changed selection bytes or inventory.'
}

try {
    foreach ($path in @($work, $entry)) { Assert-LocalNoLink $path }
    Assert-True ([IO.File]::Exists($shell)) 'Windows PowerShell is unavailable.'
    [void][IO.Directory]::CreateDirectory($work)
    $source = Join-Path $work 'source'
    [void][IO.Directory]::CreateDirectory($source)
    [IO.File]::WriteAllText((Join-Path $source 'LICENSE'), "Synthetic source notice; GPL-3.0.`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $source 'member.txt'), "Harmless source member.`n", $utf8)
    $sourceBefore = Get-TreeSnapshot $source
    $codeBefore = Get-CodeSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'source-before.txt'), $sourceBefore, $utf8)
    [IO.File]::WriteAllText((Join-Path $work 'code-before.txt'), $codeBefore, $utf8)
    Assert-NativeCommandLimit

    $out = Join-Path $work 'control-before'
    Assert-Control (Invoke-Entry $source $out 2 'control-before') $out $sourceBefore
    # JSON for these Include values alone exceeds the native command limit,
    # even before the actual entry adds paths, static child code and Base64.
    $include = [string[]](@('member.txt') + (@('LICENSE') * 5000))
    $includeJson = ConvertTo-Json -InputObject $include -Compress
    Assert-True ($includeJson.Length -gt 40000) 'Large Include fixture does not exceed the native command limit.'
    $encodedInclude = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($includeJson))
    $encodedWorkerLowerBound = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($encodedInclude)).Length
    Assert-True ($encodedWorkerLowerBound -gt 32767) 'Encoded worker-command lower bound fits the native command limit.'
    [IO.File]::WriteAllText((Join-Path $work 'argument-size.txt'),
        ('Include count: {0}; JSON characters: {1}; encoded worker-command lower bound: {2}; caller stays below 10000 characters.' -f
            $include.Count, $includeJson.Length, $encodedWorkerLowerBound), $utf8)
    foreach ($index in @(1, 2)) {
        $out = Join-Path $work ('start-refusal-' + $index)
        $result = Invoke-Entry $source $out 5000 ('start-refusal-' + $index)
        Assert-True ($result.Code -eq 1) 'Oversized worker command did not exit one.'
        Assert-True ($result.Text.Contains('REFUSED: Public tree input or operation failed.')) 'Oversized worker command lost its sanitized refusal.'
        Assert-True ($result.Text.Contains('Any staging output is unapproved and retained for owner inspection. Nothing published.')) 'Worker-start refusal lost its retained-output warning.'
        Assert-True ($result.Text -notmatch '(?i)scan passed|Staged [0-9]+ files|PUBLIC_TREE_WORKER_COMPLETED|deadline') 'Worker-start refusal claimed completion or a deadline failure.'
        Assert-True (-not [IO.Directory]::Exists($out) -and -not [IO.File]::Exists($out)) 'Worker-start refusal created staging.'
        Assert-True ((Get-TreeSnapshot $source) -ceq $sourceBefore) 'Worker-start refusal changed source bytes or inventory.'
        Assert-True ((Get-CodeSnapshot) -ceq $codeBefore) 'Worker-start refusal changed implementation bytes.'
    }
    $out = Join-Path $work 'control-after'
    Assert-Control (Invoke-Entry $source $out 2 'control-after') $out $sourceBefore
    Assert-True ((Get-TreeSnapshot $source) -ceq $sourceBefore) 'Final source bytes or inventory changed.'
    $codeAfter = Get-CodeSnapshot
    Assert-True ($codeAfter -ceq $codeBefore) 'Final implementation bytes changed.'
    [IO.File]::WriteAllText((Join-Path $work 'source-after.txt'), (Get-TreeSnapshot $source), $utf8)
    [IO.File]::WriteAllText((Join-Path $work 'code-after.txt'), $codeAfter, $utf8)
    Write-Output "PASS: public-tree worker-start failure tests; $checks assertions through $runs actual export entry processes."
    Write-Output 'Two oversized worker commands refused without staging; small-array controls exported identical bytes before and after.'
    Write-Output 'Supporting native Process.Start probe refused an overlong command with error 206; it is not counted as an entry process.'
    Write-Output ('Evidence retained: ' + $relativeWork.Replace('\', '/') + '/')
    Write-Output 'UNRUN: termination-error and outer-watchdog failure branches; independent process absence; launcher GUI; Python release tools; build; game; two-PC play. Release remains NO-GO.'
    exit 0
} catch {
    Write-Output ('FAIL: ' + $failure)
    Write-Output ('Evidence retained: ' + $relativeWork.Replace('\', '/') + '/')
    Write-Output 'No release acceptance claimed. Nothing deleted or published.'
    exit 1
}
