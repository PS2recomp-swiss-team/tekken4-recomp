# Source-only checks. This does not build, launch, publish or approve a beta.
[CmdletBinding()]
param(
    [string[]]$Docs = @(
        'CODEX_PROGRESS.md',
        'README.md',
        'docs/BETA_GO_NO_GO.md',
        'docs/BETA_RELEASE_NOTES.md',
        'docs/BETA_ANNOUNCEMENTS.md',
        'docs/RELEASE_PATH_B.md',
        'docs/PUBLIC_BETA_AUDIT.md'
    )
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$prefix = $root.TrimEnd('\') + '\'
$failures = 0

function Report-Failure([string]$Message) {
    Write-Output "FAIL: $Message"
    $script:failures++
}

function Get-SourceFiles([string]$Directory) {
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        # Do not follow this copy's Git pointer or any links outside the tree.
        if ($item.Name -eq '.git') { continue }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Reparse point refused; source check did not complete.'
        }
        if ($item.PSIsContainer) {
            Get-SourceFiles $item.FullName
        } else {
            $item
        }
    }
}

try {
    $files = @(Get-SourceFiles $root)
    $docCount = 0
    $linkCount = 0
    foreach ($doc in $Docs) {
        $path = [IO.Path]::GetFullPath((Join-Path $root $doc))
        if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Document outside the source tree refused.'
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Report-Failure "Missing document: $doc"
            continue
        }
        $docCount++
        $body = [IO.File]::ReadAllText($path)
        foreach ($match in [regex]::Matches($body, '\[[^\]]*\]\((?<target>[^)]+)\)')) {
            $target = $match.Groups['target'].Value.Trim()
            if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $target.StartsWith('#')) { continue }
            $target = $target.Split('#')[0].Trim('<', '>')
            if (-not $target) { continue }
            $linked = [IO.Path]::GetFullPath((Join-Path (Split-Path $path -Parent) $target))
            if (-not $linked.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                Report-Failure "Local link outside source tree in $doc"
                continue
            }
            $linkCount++
            if (-not (Test-Path -LiteralPath $linked)) {
                Report-Failure "Missing local link in ${doc}: $target"
            }
        }
    }
    Write-Output "Documents checked: $docCount; local links checked: $linkCount (no external URLs or anchors checked)."

    $psCount = 0
    foreach ($file in $files | Where-Object { $_.Extension -eq '.ps1' }) {
        $tokens = $null
        $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        $psCount++
        if ($errors.Count) {
            $relative = $file.FullName.Substring($prefix.Length)
            Report-Failure "PowerShell syntax errors in $relative"
        }
    }
    Write-Output "PowerShell files parsed: $psCount (not executed)."

    # Filename checks only: these do not replace the Python payload/content scans.
    $forbidden = '(?i)\.(iso|elf|bin|bios|ps2|p2s|pem|key|pfx|png|jpe?g|gif|webp|bmp|tga|dds|ico|svg)$'
    $zipCount = 0
    $incompleteZipCount = 0
    $memberCount = 0
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($prefix.Length)
        if ($relative -match $forbidden) {
            Report-Failure "Forbidden source artifact/image filename: $relative"
        }
        if ($file.Extension -ne '.zip') { continue }
        $zipCount++
        try {
            $zip = $null
            try {
                $zip = [IO.Compression.ZipFile]::OpenRead($file.FullName)
                foreach ($entry in $zip.Entries) {
                    $memberCount++
                    $name = $entry.FullName.Replace('\', '/')
                    if ($name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)|:') {
                        Report-Failure "Unsafe member path in $relative"
                    }
                    if ($name -match $forbidden) {
                        Report-Failure "Forbidden artifact/image filename in $relative"
                    }
                }
            } finally {
                if ($null -ne $zip) { $zip.Dispose() }
            }
        } catch {
            $incompleteZipCount++
            Report-Failure "Archive filename inspection failed; archive #$zipCount was not completely inspected."
        }
    }
    Write-Output "Filename inspection: $($files.Count) files; $zipCount archives attempted; $memberCount members; $incompleteZipCount incomplete archives (no extraction/content scan)."
    Write-Output 'UNRUN: Python launcher/catalog/source/payload tests and scans; GUI first-run; private-Python/Tk; hidden-tools build; offline play; two-PC internet Versus.'
    Write-Output 'Beta acceptance remains NO-GO pending the required real candidate evidence.'
    if ($failures) {
        Write-Output "Source check failed: $failures finding(s)."
        exit 1
    }
    Write-Output 'Source checks completed. Exit 0 applies only to the checks listed above.'
    exit 0
} catch {
    Write-Output "Source check stopped: $($_.Exception.Message)"
    exit 1
}
