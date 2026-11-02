# Run the ZIP scanner tests through real PowerShell entries. Nothing is published.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$prefix = $root + [IO.Path]::DirectorySeparatorChar
$failed = $false
$before = $null

function Get-CheckedPath([string]$Relative) {
    $path = [IO.Path]::GetFullPath((Join-Path $root $Relative))
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Outside-tree input refused.'
    }
    $current = $root
    foreach ($part in @('') + $path.Substring($prefix.Length).Split('\')) {
        if ($part) { $current = Join-Path $current $part }
        $item = Get-Item -LiteralPath $current -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Linked input refused before reading.'
        }
    }
    return $path
}

function Get-PatchRecords([string]$Directory) {
    foreach ($item in @(Get-ChildItem -LiteralPath $Directory -Force | Sort-Object Name)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Linked patch input refused before reading.'
        }
        if ($item.PSIsContainer) {
            Get-PatchRecords $item.FullName
        } elseif ($item.Extension -ieq '.patch') {
            $stream = [IO.File]::OpenRead($item.FullName)
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
            finally { $stream.Dispose(); $sha.Dispose() }
            $item.FullName.Substring($prefix.Length).Replace('\', '/') + ' ' + $hash
        }
    }
}

function Get-PatchSnapshot {
    $path = Get-CheckedPath 'patches'
    if (-not [IO.Directory]::Exists($path)) { throw 'Patch directory missing.' }
    $records = @(Get-PatchRecords $path | Sort-Object)
    if (-not $records.Count) { throw 'No source patches found.' }
    return $records
}

try {
    $required = @(
        'public_patch_headers.ps1', 'public_tree_scan.ps1', 'public_zip_scan.ps1',
        'scan_public_zip.ps1', 'test_public_zip_entry.ps1', 'test_public_zip_safety.ps1',
        'test_public_zip_crc.ps1', 'test_public_zip_integrity.ps1',
        'check_public_zip.ps1', 'check_online_catalogs.ps1'
    )
    foreach ($name in $required) {
        $path = Get-CheckedPath ('tools/' + $name)
        if (-not [IO.File]::Exists($path)) { throw 'Required ZIP check source missing.' }
        $tokens = $null
        $parseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw 'PowerShell syntax check failed.' }
    }
    Write-Output "SOURCE: $($required.Count) PowerShell files parsed; parsing is not execution."
    $before = @(Get-PatchSnapshot)
    Write-Output "SOURCE: $($before.Count) patch names and SHA-256 hashes captured before child entries."
    $shell = Join-Path $PSHOME 'powershell.exe'
    if (-not [IO.File]::Exists($shell)) { throw 'Windows PowerShell unavailable; child entries did not run.' }
    foreach ($entry in @('check_online_catalogs.ps1', 'test_public_zip_entry.ps1', 'test_public_zip_safety.ps1',
            'test_public_zip_crc.ps1', 'test_public_zip_integrity.ps1')) {
        Write-Output "ENTRY: tools/$entry"
        & $shell -NoProfile -ExecutionPolicy Bypass -File (Get-CheckedPath ('tools/' + $entry))
        if ($LASTEXITCODE -ne 0) {
            $failed = $true
            Write-Output "FAIL: tools/$entry exited nonzero."
        }
    }
} catch {
    $failed = $true
    Write-Output 'FAIL: ZIP checks stopped; required source, syntax, path or subprocess check failed.'
} finally {
    if ($null -ne $before) {
        try {
            $after = @(Get-PatchSnapshot)
            if ([string]::Join("`n", [string[]]$before) -cne [string]::Join("`n", [string[]]$after)) {
                $failed = $true
                Write-Output 'FAIL: source patch names or byte hashes changed during checks.'
            } else {
                Write-Output "SOURCE: $($after.Count) patch names and SHA-256 hashes unchanged."
            }
        } catch {
            $failed = $true
            Write-Output 'FAIL: source patch comparison could not complete.'
        }
    }
}
Write-Output 'UNRUN: Python suites and packagers; complete player payload validation; launcher GUI; build; game; two-PC play; licence and owner publication review.'
Write-Output 'Release remains NO-GO. Scanner tests and source catalogs do not establish player acceptance.'
if ($failed) { exit 1 }
Write-Output 'ZIP scanner entry tests passed; exit 0 covers these checks only.'
exit 0
