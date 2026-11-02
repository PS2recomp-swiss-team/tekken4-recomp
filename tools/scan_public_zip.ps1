<#
.SYNOPSIS
Read a local public-source ZIP without extracting or executing its members.
.DESCRIPTION
This is a conservative source/privacy check, not a player-package validator.
The archive must be inside this working copy. Nothing is written or published.
#>
[CmdletBinding()]
param([string]$Archive)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$prefix = $workspace + [IO.Path]::DirectorySeparatorChar
$failure = 'ZIP input or scan failed.'

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
    foreach ($name in @('public_patch_headers.ps1', 'public_tree_scan.ps1', 'public_zip_deflate.ps1', 'public_zip_scan.ps1')) {
        $dependency = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $name))
        Assert-LocalRegularFile $dependency
        . $dependency
    }
    $result = Invoke-PublicZipScan -ArchivePath $archivePath
    if ($result.Sha256 -notmatch '^[0-9a-f]{64}$') { throw 'Missing archive identity.' }
    Write-Output ('SHA256: {0}' -f $result.Sha256)
    Write-Output ('SCANNED: entries {0}; files {1}; bytes {2}.' -f $result.Entries, $result.Files, $result.Bytes)
    if (@($result.Findings).Count) {
        foreach ($finding in @($result.Findings)) {
            Write-Output ('REFUSED: member {0}: {1}' -f $finding.Entry, $finding.Reason)
        }
        Write-Output 'REFUSED: public-source ZIP content requires review.'
        Write-Output 'UNRUN: Python packagers and release payload checks; launcher GUI; build; game; two-PC play.'
        exit 1
    }
    Write-Output 'PASS: limited public-source ZIP content scan only. Owner content/licence review remains required.'
    Write-Output 'UNRUN: Python packagers and release payload checks; launcher GUI; build; game; two-PC play.'
    exit 0
} catch {
    # Exception text can contain an untrusted member name, path or private value.
    Write-Output ('REFUSED: ' + $failure)
    Write-Output 'UNRUN: Python packagers and release payload checks; launcher GUI; build; game; two-PC play.'
    exit 1
}
