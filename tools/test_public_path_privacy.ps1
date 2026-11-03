# Path privacy regressions through the real export, tree and ZIP entries.
# Retained fixtures contain ordinary text and a reserved synthetic mailbox only.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$work = Join-Path $root ('logs/public-path-privacy-' + [guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = 0
$runs = 0
$failures = New-Object 'Collections.Generic.List[string]'
$toolNames = @('publish_public_tree.ps1', 'public_tree_worker.ps1', 'public_tree_scan.ps1',
    'public_patch_headers.ps1', 'scan_public_zip.ps1', 'public_zip_scan_worker.ps1',
    'public_zip_scan.ps1', 'public_zip_deflate.ps1', 'test_public_path_privacy.ps1')

function Assert-True([bool]$Condition, [string]$Message) {
    $script:checks++
    if (-not $Condition) { $script:failures.Add($Message) }
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

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ToolSnapshot {
    return [string]::Join("`n", [string[]]@($script:toolNames | ForEach-Object {
        $path = Join-Path $PSScriptRoot $_
        Assert-LocalNoLink $path
        $_ + ' ' + (Get-Hash $path)
    }))
}

function Get-TreeSnapshot([string]$Path) {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $Path -Recurse -Force |
        Sort-Object FullName | ForEach-Object {
            Assert-LocalNoLink $_.FullName
            $relative = $_.FullName.Substring($Path.Length).Replace('\','/')
            if ($_.PSIsContainer) { 'DIR ' + $relative } else { $relative + ' ' + (Get-Hash $_.FullName) }
        }))
}

function Write-Text([string]$Path) {
    Assert-LocalNoLink $Path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, "Harmless public source test text.`n", $script:utf8)
}

function New-Case([string]$Label, [string]$Relative = '', [bool]$Directory = $false) {
    $folder = Join-Path $script:work $Label
    $source = Join-Path $folder 'source'
    Write-Text (Join-Path $source 'LICENSE')
    if ($Relative) {
        $target = Join-Path $source $Relative.Replace('/', '\')
        if ($Directory) { Assert-LocalNoLink $target; [void][IO.Directory]::CreateDirectory($target) }
        else { Write-Text $target }
    }
    $archive = Join-Path $folder 'source.zip'
    $file = [IO.File]::Open($archive, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            $names = @('LICENSE')
            if ($Relative) { $names += $(if ($Directory) { $Relative.TrimEnd('/') + '/' } else { $Relative }) }
            foreach ($name in $names) {
                $member = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::NoCompression)
                if (-not $name.EndsWith('/')) {
                    $stream = $member.Open()
                    try { $data = $script:utf8.GetBytes("Harmless public source test text.`n"); $stream.Write($data,0,$data.Length) }
                    finally { $stream.Dispose() }
                }
            }
        } finally { $zip.Dispose() }
    } finally { $file.Dispose() }
    return [pscustomobject]@{Label=$Label; Source=$source; Archive=$archive;
        Before=(Get-TreeSnapshot $source); ZipHash=(Get-Hash $archive); Runs=0}
}

function Invoke-Entry($Case, [string]$Mode) {
    $fixtureBefore = Get-TreeSnapshot ([IO.Path]::GetDirectoryName($Case.Source))
    $entryName = 'publish_public_tree.ps1'
    $parameters = @('-ScanOnly', $Case.Source)
    if ($Mode -eq 'export') { $parameters = @('-Source', $Case.Source, '-Out', (Join-Path ([IO.Path]::GetDirectoryName($Case.Source)) ('output-' + $Case.Runs))) }
    elseif ($Mode -eq 'zip') { $entryName = 'scan_public_zip.ps1'; $parameters = @('-Archive', $Case.Archive) }
    $entry = Join-Path $PSScriptRoot $entryName
    foreach ($value in @($entry) + $parameters) {
        if ($value.Contains('"')) { throw 'Unsupported quote in test argument.' }
    }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $PSHOME 'powershell.exe'
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $entry + '" ' +
        [string]::Join(' ', [string[]]@($parameters | ForEach-Object { '"' + $_ + '"' }))
    $info.WorkingDirectory = $script:root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw 'Real entry subprocess did not start.' }
        $script:runs++
        $Case.Runs++
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(45000)) {
            $process.Kill()
            $null = $process.WaitForExit(5000)
            throw 'Real entry exceeded the test watchdog; timeout is not a category refusal.'
        }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),5000)) {
            throw 'Real entry output collection exceeded the test watchdog.'
        }
        $out = $stdout.GetAwaiter().GetResult()
        $err = $stderr.GetAwaiter().GetResult()
        $label = $Case.Label + '-' + $Mode + '-' + $Case.Runs
        [IO.File]::WriteAllText((Join-Path $script:work ($label + '.stdout.txt')), $out, $script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($label + '.stderr.txt')), $err, $script:utf8)
        [IO.File]::WriteAllText((Join-Path $script:work ($label + '.result.txt')),
            ('exit {0}; elapsed {1:F3} seconds' -f $process.ExitCode,$clock.Elapsed.TotalSeconds), $script:utf8)
        Assert-True (-not $err.Trim()) ($label + ': stderr was not empty.')
        Assert-True ((Get-TreeSnapshot $Case.Source) -ceq $Case.Before) ($label + ': source bytes or inventory changed.')
        Assert-True ((Get-Hash $Case.Archive) -ceq $Case.ZipHash) ($label + ': archive bytes changed.')
        Assert-True ((Get-ToolSnapshot) -ceq $script:toolBefore) ($label + ': source tool names or bytes changed during this run.')
        if ($Mode -ne 'export') {
            Assert-True ((Get-TreeSnapshot ([IO.Path]::GetDirectoryName($Case.Source))) -ceq $fixtureBefore) ($label + ': scanner changed fixture inventory or extracted members.')
        }
        return [pscustomobject]@{Code=$process.ExitCode; Text=$out; Errors=$err;
            Output=$(if ($Mode -eq 'export') { $parameters[3] } else { '' })}
    } finally { $clock.Stop(); $process.Dispose() }
}

function Assert-Clean($Result, [string]$Label) {
    Assert-True ($Result.Code -eq 0) ($Label + ': clean control refused.')
    Assert-True ($Result.Text -match 'scan passed|PASS: limited public-source') ($Label + ': clean control did not complete its actual scan.')
}

function Test-CleanControl($Case, [string]$Mode, [string]$Label) {
    $result = Invoke-Entry $Case $Mode
    Assert-Clean $result $Label
    if ($Mode -eq 'export' -and [IO.Directory]::Exists($result.Output)) {
        Assert-True ((Get-TreeSnapshot $result.Output) -ceq $Case.Before) ($Label + ': clean export bytes or inventory differ from the input.')
    }
    if ($Mode -eq 'zip') {
        Assert-True ($result.Text.Contains('SCANNED:')) ($Label + ': ZIP scan completion missing.')
        Assert-True ($result.Text.Contains('SHA256: ' + $Case.ZipHash)) ($Label + ': ZIP input identity differs.')
    }
}

function Assert-Refused($Result, [string]$Label, [string]$Reason, [string[]]$Canaries) {
    Assert-True ($Result.Code -eq 1) ($Label + ': expected refusal exit 1.')
    Assert-True ($Result.Text.Contains($Reason)) ($Label + ': expected path category was not reached.')
    Assert-True ($Result.Text -notmatch 'Public tree scan passed|Postwrite public scan passed|PASS: limited public-source') ($Label + ': refusal included a scanner pass.')
    $combined = $Result.Text + $Result.Errors
    foreach ($canary in @($Canaries) + @($script:root)) {
        Assert-True (-not $combined.Contains($canary)) ($Label + ': diagnostic disclosed a path canary.')
    }
}

try {
    Assert-LocalNoLink $work
    [void][IO.Directory]::CreateDirectory($work)
    Add-Type -AssemblyName System.IO.Compression
    $toolBefore = Get-ToolSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'tools-before.txt'), $toolBefore, $utf8)
    $control = New-Case 'clean-control' 'docs/notes.txt'
    foreach ($mode in @('export','tree','zip')) { Test-CleanControl $control $mode ('before-' + $mode) }

    $privateNames = @('.agents/ordinary.txt', '.codex/ordinary.txt', '.aws/ordinary.txt', 'CODEX_PROGRESS.md',
        'nested/.CoDeX/ordinary.txt', 'docs/codeX_progress.MD')
    $index = 0
    foreach ($relative in $privateNames) {
        $case = New-Case ('private-file-' + $index) $relative
        # The whole relative path and its private component must stay out of diagnostics.
        $privateComponent = @($relative.Split('/') | Where-Object { $_ -match '(?i)^\.(?:agents|codex|aws)$|^codex_progress\.md$' })[0]
        foreach ($mode in @('tree','zip')) {
            Assert-Refused (Invoke-Entry $case $mode) ($case.Label + '-' + $mode) 'private source path' @($privateComponent)
        }
        $result = Invoke-Entry $case 'export'
        Assert-Clean $result ($case.Label + '-omission-export')
        if ([IO.Directory]::Exists($result.Output)) {
            $retained = @(Get-ChildItem -LiteralPath $result.Output -Recurse -Force)
            Assert-True ($retained.Count -eq 1 -and $retained[0].Name -ceq 'LICENSE') ($case.Label + ': private source path was not omitted.')
            Assert-True ((Get-Hash (Join-Path $result.Output 'LICENSE')) -ceq (Get-Hash (Join-Path $case.Source 'LICENSE'))) ($case.Label + ': export changed retained LICENSE bytes.')
        } else { Assert-True $false ($case.Label + ': clean omission export did not stage.') }
        $index++
    }

    foreach ($relative in @('.agents', '.codex', '.aws', 'nested/.CoDeX')) {
        $case = New-Case ('private-directory-' + $index) $relative $true
        $privateComponent = $relative.Split('/')[-1]
        foreach ($mode in @('tree','zip')) {
            Assert-Refused (Invoke-Entry $case $mode) ($case.Label + '-' + $mode) 'private source path' @($privateComponent)
        }
        $index++
    }
    # A safe empty directory whose suffix resembles a binary filename remains usable.
    foreach ($relative in @('ordinary.bin','ordinary.patch')) {
        $safeDirectory = New-Case ('safe-directory-' + $index) $relative $true
        foreach ($mode in @('tree','zip')) { Test-CleanControl $safeDirectory $mode ('safe-directory-' + $index + '-' + $mode) }
        $index++
    }

    $mailbox = 'contact' + '@' + 'example.invalid' + '.txt'
    $mailCase = New-Case 'mailbox-path' $mailbox
    foreach ($mode in @('tree','zip','export')) {
        $result = Invoke-Entry $mailCase $mode
        Assert-Refused $result ('mailbox-' + $mode) 'email address; manual review required' @($mailbox, ('contact' + '@'))
        if ($mode -eq 'export') { Assert-True (-not (Test-Path -LiteralPath $result.Output)) 'Mailbox export created staging before refusal.' }
    }

    $mailDirectory = New-Case 'mailbox-directory' ('contact' + '@' + 'example.invalid') $true
    foreach ($mode in @('tree','zip')) {
        Assert-Refused (Invoke-Entry $mailDirectory $mode) ('mailbox-directory-' + $mode) 'email address; manual review required' @(('contact' + '@'))
    }

    # These are explicitly artificial text samples, never credentials or endpoints.
    $nameCases = @(
        [pscustomobject]@{Label='synthetic-token-name'; Name=('token=' + 'ordinarypublicsample00000' + '.txt');
            Reason='credential or private key content'; Canary='ordinarypublicsample00000'},
        [pscustomobject]@{Label='reserved-host-name'; Name=('host=' + 'service.example.invalid' + '.txt');
            Reason='server hostname assignment'; Canary='service.example.invalid'}
    )
    foreach ($nameCase in $nameCases) {
        $case = New-Case $nameCase.Label $nameCase.Name
        foreach ($mode in @('tree','zip','export')) {
            $result = Invoke-Entry $case $mode
            Assert-Refused $result ($nameCase.Label + '-' + $mode) $nameCase.Reason @($nameCase.Canary)
            if ($mode -eq 'export') { Assert-True (-not (Test-Path -LiteralPath $result.Output)) ($nameCase.Label + ': export created staging before refusal.') }
        }
    }

    foreach ($mode in @('export','tree','zip')) { Test-CleanControl $control $mode ('after-' + $mode) }
    $toolAfter = Get-ToolSnapshot
    [IO.File]::WriteAllText((Join-Path $work 'tools-after.txt'), $toolAfter, $utf8)
    Assert-True ($toolAfter -ceq $toolBefore) 'Final tool snapshot differs from the frozen input.'
    [IO.File]::WriteAllLines((Join-Path $work 'failures.txt'), [string[]]$failures, $utf8)
    Write-Output ('Path privacy entry tests: {0} assertions; {1} actual entry subprocesses; {2} failures.' -f $checks,$runs,$failures.Count)
    Write-Output ('Evidence: logs/' + [IO.Path]::GetFileName($work) + '/')
    foreach ($failure in $failures) { Write-Output ('FAIL: ' + $failure) }
    Write-Output 'UNRUN: Python packagers, launcher GUI, build, game and two-PC play. No release approval.'
    if ($failures.Count) { exit 1 }
    exit 0
} catch {
    Write-Output 'FAIL: path privacy tests stopped; required fixture, source or actual entry operation failed.'
    Write-Output ('Evidence: logs/' + [IO.Path]::GetFileName($work) + '/')
    Write-Output 'UNRUN: Python packagers, launcher GUI, build, game and two-PC play. No release approval.'
    exit 1
}
