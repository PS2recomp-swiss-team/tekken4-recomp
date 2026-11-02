# Internal worker for publish_public_tree.ps1. Use the supervised entry.
<#
.SYNOPSIS
Stage or scan a public source tree. Never publish or change the input tree.
.DESCRIPTION
PowerShell 5.1 entry point. Images are omitted, patch mail headers are cleaned,
and all selected content must pass the public scanner before anything is written.
Use -Include with reviewed relative files/directories when the full working tree
contains private maintainer records. A passing scan does not settle licences.
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$Out,
    [string[]]$Include,
    [string]$ScanOnly
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\', '/')
$maximumFileSize = 32MB

function Get-LocalPath([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'A path is required.' }
    $absolute = [IO.Path]::GetFullPath($Value).TrimEnd('\', '/')
    if (-not ($absolute.Equals($workspace, [StringComparison]::OrdinalIgnoreCase) -or
            $absolute.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Paths must stay inside this working copy.'
    }
    return $absolute
}

function Assert-NoLocalLink([string]$Value) {
    $current = $Value
    while ($current.Length -ge $workspace.Length) {
        if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
            if (([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Links and reparse points are not public tree inputs or outputs.'
            }
        }
        if ($current.Equals($workspace, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-RelativeName([string]$Base, [string]$Value) {
    if (-not $Value.StartsWith($Base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'An input escaped its source directory.'
    }
    return $Value.Substring($Base.Length + 1).Replace('\', '/')
}

function Assert-PublicName([string]$Name) {
    if ([string]::IsNullOrEmpty($Name) -or $Name.Contains('\') -or $Name.StartsWith('/')) { throw 'Unsafe relative source path.' }
    foreach ($part in $Name.Split('/')) {
        if ($part -in @('', '.', '..') -or $part -match '[:\x00-\x1f]' -or $part.TrimEnd(' ', '.') -cne $part -or
                $part -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)') {
            throw 'Unsafe relative source path.'
        }
    }
}

function Test-OmittedPath([string]$Name, [bool]$Directory) {
    $parts = $Name.ToLowerInvariant().Split('/')
    $omittedDirectories = @('.git', '.agents', '.codex', '.aws', 'logs', 'log', 'dist', 'build', 'out', 'external',
        'node_modules', 'generated', 'ghidra', 'lobby', '__pycache__', '.pytest_cache')
    $count = $parts.Length
    if (-not $Directory) { $count-- }
    for ($i = 0; $i -lt $count; $i++) { if ($parts[$i] -in $omittedDirectories) { return $true } }
    if ($parts.Length -ge 2 -and (($parts[0] -eq 'docs' -and $parts[1] -eq 'img') -or
            ($parts[0] -eq 'config' -and $parts[1] -eq 'output'))) { return $true }
    return (-not $Directory -and ($parts[-1] -in @('claude.md', '.mcp.json', 'codex_progress.md') -or
        $parts[-1] -match '(?i)(?:\.py[co]$|\.log(?:\.|$)|^(?:log|debug)\.txt$)'))
}

function Get-DiffOffset([byte[]]$Data) {
    $text = [Text.Encoding]::GetEncoding(28591).GetString($Data)
    $match = [regex]::Match($text, '(?m)^diff --git ')
    if (-not $match.Success) { throw 'A patch has no diff boundary.' }
    return $match.Index
}

function Assert-EqualPatchDiff([byte[]]$Original, [byte[]]$Clean) {
    $originalOffset = Get-DiffOffset $Original
    $cleanOffset = Get-DiffOffset $Clean
    if ($Original.Length - $originalOffset -ne $Clean.Length - $cleanOffset) { throw 'Patch diff bytes changed.' }
    for ($i = 0; $i -lt $Original.Length - $originalOffset; $i++) {
        if ($Original[$originalOffset + $i] -ne $Clean[$cleanOffset + $i]) { throw 'Patch diff bytes changed.' }
    }
}

try {
    . (Join-Path $PSScriptRoot 'public_patch_headers.ps1')
    . (Join-Path $PSScriptRoot 'public_tree_scan.ps1')
    if ($ScanOnly) {
        if ($PSBoundParameters.ContainsKey('Source') -or $PSBoundParameters.ContainsKey('Out') -or
                $PSBoundParameters.ContainsKey('Include')) { throw '-ScanOnly cannot be combined with export arguments.' }
        $scanRoot = Get-LocalPath $ScanOnly
        Assert-NoLocalLink $scanRoot
        if (-not [IO.Directory]::Exists($scanRoot)) { throw 'Scan input must be an existing directory.' }
        $findings = @(Get-PublicTreeFindings $scanRoot)
        if ($findings.Count) {
            foreach ($finding in $findings) { Write-Output ('REFUSED: {0}: {1}' -f $finding.Path, $finding.Reason) }
            throw 'Public tree scan refused the staged content.'
        }
        Write-Output 'Public tree scan passed. Owner content and licence review is still required. Nothing published.'
        exit 0
    }
    if (-not $Out) { throw 'Export requires -Out with a new or empty staging directory.' }
    if (-not $Source) { $Source = $workspace }
    $sourceRoot = Get-LocalPath $Source
    $outputRoot = Get-LocalPath $Out
    Assert-NoLocalLink $sourceRoot
    Assert-NoLocalLink $outputRoot
    if (-not [IO.Directory]::Exists($sourceRoot)) { throw 'Source must be an existing directory.' }
    if ($outputRoot.Equals($sourceRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $sourceRoot.StartsWith($outputRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Output must not contain or replace the source.'
    }
    if ($outputRoot.StartsWith($sourceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        $outputRelative = Get-RelativeName $sourceRoot $outputRoot
        if ($outputRelative.Split('/')[0] -ne 'logs') { throw 'Output inside source is allowed only under excluded logs.' }
    }
    if ($outputRoot -match '(?i)(?:^|[\\/])\.git(?:[\\/]|$)') { throw 'Output cannot be Git metadata.' }
    if ([IO.File]::Exists($outputRoot) -or ([IO.Directory]::Exists($outputRoot) -and
            @(Get-ChildItem -LiteralPath $outputRoot -Force).Count)) { throw 'Output must be a new or empty directory.' }

    $pending = New-Object 'Collections.Generic.Stack[string]'
    if ($Include) {
        foreach ($name in $Include) {
            Assert-PublicName $name
            $path = Get-LocalPath (Join-Path $sourceRoot $name.Replace('/', [IO.Path]::DirectorySeparatorChar))
            if (-not $path.StartsWith($sourceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Include paths must be relative to source.'
            }
            $pending.Push($path)
        }
    } else { $pending.Push($sourceRoot) }
    $selected = New-Object 'Collections.Generic.List[object]'
    $seenFiles = @{}
    $seenNames = @{}
    $imageCount = 0
    $patchCount = 0
    $refusals = New-Object 'Collections.Generic.List[string]'
    while ($pending.Count) {
        $path = $pending.Pop()
        $name = ''
        if (-not $path.Equals($sourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $name = Get-RelativeName $sourceRoot $path
            Assert-PublicName $name
        }
        $directory = [IO.Directory]::Exists($path)
        if ($name -and (Test-OmittedPath $name $directory)) { continue }
        Assert-NoLocalLink $path
        if ($directory) {
            foreach ($child in @(Get-ChildItem -LiteralPath $path -Force)) { $pending.Push($child.FullName) }
            continue
        }
        if (-not [IO.File]::Exists($path)) { throw 'A selected input is missing or is not a regular file.' }
        if ($seenFiles.ContainsKey($name)) { continue }
        $seenFiles[$name] = $true
        $prefix = ''
        foreach ($part in $name.Split('/')) {
            if ($prefix) { $prefix += '/' }
            $prefix += $part
            if ($seenNames.ContainsKey($prefix) -and $seenNames[$prefix] -cne $prefix) { throw 'Case-colliding source paths.' }
            $seenNames[$prefix] = $prefix
        }
        if (Test-PublicImageName $name) { $imageCount++; continue }
        if (([IO.FileInfo]$path).Length -gt $maximumFileSize) { throw 'A selected input is oversized; manual review required.' }
        [byte[]]$data = [IO.File]::ReadAllBytes($path)
        $original = $null
        if ([IO.Path]::GetExtension($name) -ieq '.patch') {
            $original = $data
            [byte[]]$data = ConvertTo-PublicPatch $data
            Assert-EqualPatchDiff $original $data
            $patchCount++
        }
        foreach ($reason in @(Get-PublicFileFindings $name $data)) { $refusals.Add(('{0}: {1}' -f $name, $reason)) }
        $selected.Add([pscustomobject]@{ Name = $name; Data = $data; OriginalPatch = $original })
    }
    if (-not ($selected | Where-Object { $_.Name -ceq 'LICENSE' })) { throw 'The selected tree must retain root LICENSE.' }
    if ($refusals.Count) {
        foreach ($finding in $refusals) { Write-Output ('REFUSED: ' + $finding) }
        throw 'Public export refused before staging. Review the selected source content.'
    }
    [void][IO.Directory]::CreateDirectory($outputRoot)
    Assert-NoLocalLink $outputRoot
    foreach ($entry in $selected) {
        $target = Join-Path $outputRoot $entry.Name.Replace('/', [IO.Path]::DirectorySeparatorChar)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        Assert-NoLocalLink $target
        $stream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($entry.Data, 0, $entry.Data.Length) } finally { $stream.Dispose() }
    }
    $findings = @(Get-PublicTreeFindings $outputRoot)
    if ($findings.Count) { throw 'Postwrite scan failed. Staging retained for owner inspection; do not publish it.' }
    foreach ($entry in $selected) {
        if ($null -ne $entry.OriginalPatch) {
            Assert-EqualPatchDiff $entry.OriginalPatch ([IO.File]::ReadAllBytes((Join-Path $outputRoot $entry.Name)))
        }
    }
    Write-Output ('Staged {0} files; omitted {1} image files; cleaned {2} patches with byte-identical diff parts.' -f $selected.Count, $imageCount, $patchCount)
    Write-Output 'Postwrite public scan passed. Owner content and licence review is still required. Nothing published.'
    exit 0
} catch {
    # Never echo arbitrary exception text: it can contain a private path or value.
    if ($_.Exception.Message -eq 'text scan limit or failure; manual review required') {
        Write-Output 'REFUSED: Public tree refused: text scan limit or failure; manual review required'
    } else { Write-Output 'REFUSED: Public tree input or operation failed.' }
    exit 1
}
