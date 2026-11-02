# Run the public-tree guard through its real PowerShell entry points.
# This does not build, start a game, use Git, publish, or approve a release.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failed = $false

function Get-PatchFiles([string]$Directory) {
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Patch link refused; source patch snapshot did not complete.'
        }
        if ($item.PSIsContainer) { Get-PatchFiles $item.FullName }
        elseif ($item.Extension -eq '.patch') { $item }
    }
}

function Get-PatchSnapshot {
    $records = @()
    $mailCount = 0
    $coauthorCount = 0
    $patchRoot = Join-Path $root 'patches'
    foreach ($file in @(Get-PatchFiles $patchRoot | Sort-Object FullName)) {
        $data = [IO.File]::ReadAllBytes($file.FullName)
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($hasher.ComputeHash($data)).Replace('-', '').ToLowerInvariant() }
        finally { $hasher.Dispose() }
        $records += $file.FullName.Substring($patchRoot.Length + 1).Replace('\', '/') + ' ' + $hash
        # Match only the preamble; a diff can legitimately contain these words.
        $text = [Text.Encoding]::ASCII.GetString($data)
        $boundary = [regex]::Match($text, '(?m)^diff --git ')
        if (-not $boundary.Success) { throw 'Patch without a Git diff boundary refused.' }
        $preamble = $text.Substring(0, $boundary.Index)
        if ($preamble -match '(?im)^From:[^\r\n]*@') { $mailCount++ }
        if ($preamble -match '(?im)^Co-Authored-By:') { $coauthorCount++ }
    }
    [pscustomobject]@{ Records = $records; Mail = $mailCount; Coauthor = $coauthorCount }
}

function Test-PythonCatalog([string]$Name) {
    $path = Join-Path $PSScriptRoot $Name
    $text = [IO.File]::ReadAllText($path)
    $catalog = [regex]::Match($text, '(?ms)^TOOLS\s*=\s*\((?<body>.*?)^\)')
    if (-not $catalog.Success) { throw "Missing TOOLS catalog in $Name." }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $count = 0
    foreach ($match in [regex]::Matches($catalog.Groups['body'].Value, '"(?<name>[^"\r\n]+)"')) {
        $tool = $match.Groups['name'].Value
        if ($tool -match '[/\\:]|^\.') { throw "Unsafe tool catalog name in $Name." }
        if (-not $seen.Add($tool)) { throw "Duplicate tool catalog name in $Name." }
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $tool) -PathType Leaf)) {
            throw "Missing catalog tool in $Name."
        }
        $count++
    }
    if (-not $count) { throw "Empty TOOLS catalog in $Name." }
    Write-Output "Catalog checked: $Name; $count unique tool files exist (not executed)."
}

try {
    $required = @(
        'publish_public_tree.ps1', 'public_tree_worker.ps1', 'public_patch_headers.ps1', 'public_tree_scan.ps1',
        'test_public_patch_headers.ps1', 'test_public_tree_entry.ps1',
        'test_public_tree_deadline.ps1', 'test_public_tree_deadline_compat.ps1',
        'test_public_tree_write_failure.ps1', 'test_public_tree_worker_failure.ps1',
        'test_public_tree_interruption.ps1', 'test_public_tree_start_failure.ps1',
        'test_public_text_words.ps1', 'test_public_text_lines.ps1', 'test_public_text_categories.ps1',
        'test_public_path_privacy.ps1',
        'public_zip_scan.ps1', 'public_zip_deflate.ps1', 'scan_public_zip.ps1',
        'check_public_publish.ps1'
    )
    foreach ($name in $required) {
        $path = Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required public-tree tool: $name." }
        $tokens = $null
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw "PowerShell syntax errors in $name." }
    }
    Write-Output "Public-tree PowerShell syntax parsed: $($required.Count) files."
    Test-PythonCatalog 'test_zip.py'
    Test-PythonCatalog 'package_release.py'
    $before = Get-PatchSnapshot
    Write-Output "Source patches before tests: $($before.Records.Count); From mailbox headers: $($before.Mail); Co-Authored-By preambles: $($before.Coauthor)."
    $shell = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $shell -PathType Leaf)) { throw 'Windows PowerShell executable unavailable; no entry-point tests ran.' }
    foreach ($suite in @('test_public_patch_headers.ps1', 'test_public_tree_entry.ps1',
            'test_public_tree_deadline.ps1', 'test_public_tree_deadline_compat.ps1',
            'test_public_tree_write_failure.ps1', 'test_public_tree_worker_failure.ps1',
            'test_public_tree_interruption.ps1', 'test_public_tree_start_failure.ps1',
            'test_public_text_words.ps1', 'test_public_text_lines.ps1', 'test_public_text_categories.ps1',
            'test_public_path_privacy.ps1')) {
        Write-Output "Running real test entry: tools/$suite"
        & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $suite)
        if ($LASTEXITCODE -ne 0) {
            $failed = $true
            Write-Output "FAIL: tools/$suite exited nonzero."
        }
    }
} catch {
    $failed = $true
    Write-Output "Public-tree checks stopped: $($_.Exception.Message)"
} finally {
    if (Get-Variable -Name before -Scope Script -ErrorAction SilentlyContinue) {
        try {
            $after = Get-PatchSnapshot
            if ([string]::Join("`n", [string[]]$before.Records) -cne [string]::Join("`n", [string[]]$after.Records)) {
                $failed = $true
                Write-Output 'FAIL: source patch names or byte hashes changed during tests.'
            } else {
                Write-Output "Source patches unchanged: $($after.Records.Count) names and SHA-256 hashes match."
            }
        } catch {
            $failed = $true
            Write-Output 'FAIL: source patch comparison could not complete.'
        }
    }
}
Write-Output 'Existing Python packagers do not call this public-tree entry; their Python tests and release payload scans remain separate and unrun by this checker.'
Write-Output 'UNRUN: build, launcher GUI, game, two-PC play, actual release payloads, upstream licence grants and owner publication review.'
if ($failed) { exit 1 }
Write-Output 'Public-tree entry-point checks passed. This does not approve a release.'
exit 0
