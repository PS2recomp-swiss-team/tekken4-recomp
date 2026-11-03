# Exercise a real export write error after LICENSE has been staged.
# Only fixture-directory ACLs change, and their original access rules are restored.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$relativeWork = 'logs/public-tree-write-failure-' + [Guid]::NewGuid().ToString('N')
$work = Join-Path $root $relativeWork
$checks = 0
$runs = 0
$failure = 'Write-failure test preflight failed.'
$utf8 = New-Object Text.UTF8Encoding($false)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $script:failure = $Message; throw 'Write-failure assertion failed.' }
    $script:checks++
}

function Assert-LocalNoLink([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($script:root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Fixture outside this copy refused.'
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
            'public_patch_headers.ps1', 'test_public_tree_write_failure.ps1')) {
        $path = Join-Path $PSScriptRoot $name
        Assert-LocalNoLink $path
        $name + ' ' + (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }))
}

function Invoke-RealExport([string]$Source, [string]$Out, [string]$Label, [switch]$ScanOnly) {
    # Reverse stack traversal intentionally stages LICENSE before the nested file.
    $payload = @{ Entry=$script:entry; Source=$Source; Out=$Out; Scan=[bool]$ScanOnly } | ConvertTo-Json -Compress
    $data = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
    $command = "`$ProgressPreference='SilentlyContinue'; `$p=ConvertFrom-Json ([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$data'))); if (`$p.Scan) { & `$p.Entry -ScanOnly `$p.Out -TimeoutSeconds 10 } else { & `$p.Entry -Source `$p.Source -Out `$p.Out -Include @('nested/member.txt','LICENSE') -TimeoutSeconds 10 }; exit `$LASTEXITCODE"
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:shell
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
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
            $script:failure = 'Outer watchdog expired; failed test, not a proven entry refusal. Descendant absence is unproved.'
            throw 'Entry watchdog expired.'
        }
        $result = [pscustomobject]@{
            Code=$proc.ExitCode; Text=$stdout.GetAwaiter().GetResult(); ErrorText=$stderr.GetAwaiter().GetResult()
        }
        # Assertions use the original streams. Retained diagnostics redact this
        # copy's path and withhold arbitrary stderr even when the test fails.
        $safeOutput = [regex]::Replace($result.Text, [regex]::Escape($script:root), '<working-copy>',
            [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $safeError = ''
        if (-not [string]::IsNullOrWhiteSpace($result.ErrorText)) { $safeError = 'Nonempty stderr withheld.' }
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '-stdout.txt')), $safeOutput, $script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '-stderr.txt')), $safeError, $script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($Label + '-exit.txt')), [string]$result.Code, $script:utf8)
        return $result
    } finally {
        if ($started -and -not $proc.HasExited) {
            try { $proc.Kill(); $null = $proc.WaitForExit(5000) } catch { }
        }
        $proc.Dispose()
    }
}

function Assert-Sanitized($Result) {
    Assert-True ([string]::IsNullOrWhiteSpace($Result.ErrorText)) 'Real export emitted stderr.'
    Assert-True ($Result.Text -notmatch [regex]::Escape($script:root)) 'Real export disclosed the working-copy path.'
    Assert-True (-not $Result.Text.Contains('Exception')) 'Real export disclosed exception details.'
    Assert-True ($Result.Text.Contains('UNRUN: Python packagers')) 'Real export lost its unrun limitation.'
}

function Assert-Refused($Result) {
    Assert-Sanitized $Result
    Assert-True ($Result.Code -eq 1) 'Write-failure export did not exit one.'
    Assert-True ($Result.Text.Contains('REFUSED: Public tree input or operation failed.')) 'Write-failure export lost its sanitized refusal.'
    Assert-True ($Result.Text.Contains('Any staging output is unapproved and retained for owner inspection. Nothing published.')) 'Write-failure export lost its retained-output warning.'
    Assert-True ($Result.Text -notmatch '(?i)scan passed|Staged [0-9]+ files|PUBLIC_TREE_WORKER_COMPLETED|deadline') 'Write-failure export claimed completion or a different failure.'
}

function Assert-CompleteExport($Result, [string]$Out, [string]$SourceSnapshot) {
    Assert-Sanitized $Result
    Assert-True ($Result.Code -eq 0) 'Fresh control export did not exit zero.'
    Assert-True ($Result.Text.Contains('Staged 2 files; omitted 0 image files; cleaned 0 patches with byte-identical diff parts.')) 'Fresh control lost its complete selection.'
    Assert-True ($Result.Text.Contains('Postwrite public scan passed.')) 'Fresh control did not finish its postwrite scan.'
    Assert-True ($Result.Text -notmatch '(?i)REFUSED|failed|exceeded') 'Fresh control also reported failure.'
    Assert-True ((Get-TreeSnapshot $Out) -ceq $SourceSnapshot) 'Fresh control changed source bytes or inventory.'
}

try {
    Assert-LocalNoLink $work
    Assert-LocalNoLink $entry
    Assert-True ([IO.File]::Exists($shell)) 'Windows PowerShell is unavailable.'
    [void][IO.Directory]::CreateDirectory($work)
    $source = Join-Path $work 'source'
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'nested'))
    [IO.File]::WriteAllText((Join-Path $source 'LICENSE'), "Synthetic source notice; GPL-3.0.`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $source 'nested/member.txt'), "Harmless source member.`n", $utf8)
    $sourceBefore = Get-TreeSnapshot $source
    $codeBefore = Get-CodeSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'source-before.txt'), $sourceBefore, $utf8)
    [IO.File]::WriteAllText((Join-Path $work 'code-before.txt'), $codeBefore, $utf8)

    $out = Join-Path $work 'control-before'
    Assert-CompleteExport (Invoke-RealExport $source $out 'control-before') $out $sourceBefore

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $user = $identity.User } finally { $identity.Dispose() }
    foreach ($index in @(1, 2)) {
        $out = Join-Path $work ('write-refusal-' + $index)
        Assert-LocalNoLink $out
        $directory = [IO.Directory]::CreateDirectory($out)
        $accessSection = [Security.AccessControl.AccessControlSections]::Access
        $security = $directory.GetAccessControl()
        $originalAccess = $security.GetSecurityDescriptorSddlForm($accessSection)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $user, [Security.AccessControl.FileSystemRights]::CreateDirectories,
            [Security.AccessControl.AccessControlType]::Deny)
        # Deny only new subdirectories: LICENSE remains writable in the empty root.
        # No production file or ACL changes. Never persist the user's SID or ACL.
        try {
            $null = $security.AddAccessRule($rule)
            $directory.SetAccessControl($security)
            $result = Invoke-RealExport $source $out ('write-refusal-' + $index)
        } finally {
            $restore = $directory.GetAccessControl()
            $restore.SetSecurityDescriptorSddlForm($originalAccess, $accessSection)
            $directory.SetAccessControl($restore)
        }
        Assert-True ($directory.GetAccessControl().GetSecurityDescriptorSddlForm($accessSection) -ceq $originalAccess) 'Fixture ACL was not restored.'
        Assert-Refused $result
        Assert-True ([IO.File]::Exists((Join-Path $out 'LICENSE'))) 'Refusal happened before any selected file was staged.'
        Assert-True (-not [IO.Directory]::Exists((Join-Path $out 'nested'))) 'Denied directory unexpectedly exists.'
        Assert-True (@(Get-ChildItem -LiteralPath $out -Force).Count -eq 1) 'Write-failure staging inventory was unexpected.'
        Assert-True ((Get-FileHash -LiteralPath (Join-Path $out 'LICENSE') -Algorithm SHA256).Hash -ceq
            (Get-FileHash -LiteralPath (Join-Path $source 'LICENSE') -Algorithm SHA256).Hash) 'Retained LICENSE bytes changed.'
        Assert-True ((Get-TreeSnapshot $source) -ceq $sourceBefore) 'Write refusal changed the source tree.'
        $partialBefore = Get-TreeSnapshot $out
        # Run the actual content scanner to demonstrate its limited meaning:
        # clean LICENSE bytes pass, despite the missing selected nested member.
        $partialScan = Invoke-RealExport $source $out ('partial-scan-' + $index) -ScanOnly
        Assert-Sanitized $partialScan
        Assert-True ($partialScan.Code -eq 0) 'Retained LICENSE-only content scan did not exit zero.'
        Assert-True ($partialScan.Text.Contains('Public tree scan passed.')) 'Retained LICENSE-only scan did not report completed content inspection.'
        Assert-True ($partialScan.Text -notmatch '(?i)REFUSED|Staged [0-9]+ files|Postwrite|failed|exceeded') 'Partial content scan claimed export completion or failure.'
        Assert-True ((Get-TreeSnapshot $out) -ceq $partialBefore) 'Content scan changed partial staging.'
        # The actual export must still refuse retained nonempty staging.
        Assert-Refused (Invoke-RealExport $source $out ('retained-retry-' + $index))
        Assert-True ((Get-TreeSnapshot $out) -ceq $partialBefore) 'Retry changed retained partial staging.'
        Assert-True ((Get-TreeSnapshot $source) -ceq $sourceBefore) 'Retry changed the source tree.'
    }

    $out = Join-Path $work 'control-after'
    Assert-CompleteExport (Invoke-RealExport $source $out 'control-after') $out $sourceBefore
    Assert-True ((Get-TreeSnapshot $source) -ceq $sourceBefore) 'Final source inventory or bytes changed.'
    $codeAfter = Get-CodeSnapshot
    Assert-True ($codeAfter -ceq $codeBefore) 'Write-failure code hashes changed during tests.'
    [IO.File]::WriteAllText((Join-Path $work 'code-after.txt'), $codeAfter, $utf8)
    [IO.File]::WriteAllText((Join-Path $work 'source-after.txt'), (Get-TreeSnapshot $source), $utf8)
    Write-Output "PASS: public-tree write-failure tests; $checks assertions through $runs actual export/scan entry processes."
    Write-Output ('Evidence retained: ' + $relativeWork.Replace('\', '/') + '/')
    Write-Output 'Proved filesystem write-error refusal after LICENSE staging, retained-output retry refusal and fresh complete controls.'
    Write-Output 'Actual LICENSE-only partial scans passed content checks; they did not prove a complete selected export.'
    Write-Output 'UNRUN: timed write interruption, OS worker-start failure, termination-error and outer-watchdog failure; independent process absence; launcher GUI; build; game; two-PC play.'
    exit 0
} catch {
    Write-Output ('FAIL: ' + $failure)
    Write-Output ('Evidence retained: ' + $relativeWork.Replace('\', '/') + '/')
    Write-Output 'No release acceptance claimed. Nothing deleted or published.'
    exit 1
}
