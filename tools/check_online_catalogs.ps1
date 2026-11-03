# Source catalog inspection only. No Python, packaging, build or game execution.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$prefix = $root.TrimEnd('\') + '\'

function Get-CheckedFile([string]$Relative) {
    if ($Relative -notmatch '^[A-Za-z0-9_./-]+$' -or
        $Relative -match '(^|/)\.\.?(/|$)' -or $Relative.StartsWith('/')) {
        throw 'Unsafe catalog path refused.'
    }
    $path = [IO.Path]::GetFullPath((Join-Path $root $Relative))
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Outside-tree catalog path refused.'
    }
    # Check each component before opening the file. Do not follow directory links.
    $current = $root
    foreach ($part in @('') + $Relative.Split('/')) {
        if ($part) { $current = Join-Path $current $part }
        $item = Get-Item -LiteralPath $current -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Reparse point refused.'
        }
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Missing catalog input.'
    }
    return $path
}

function Read-LiteralCatalog([string]$Relative, [string]$Name) {
    $body = [IO.File]::ReadAllText((Get-CheckedFile $Relative))
    $declarations = [regex]::Matches($body, '(?m)^' + $Name + '\s*=')
    $catalog = [regex]::Matches($body, '(?m)^' + $Name + ' = \((?<items>[^)]*)\)[ \t]*\r?$')
    if ($declarations.Count -ne 1 -or $catalog.Count -ne 1) {
        throw 'Expected one simple literal tuple catalog.'
    }
    $items = $catalog[0].Groups['items'].Value
    # This deliberately supports the current string-only tuples, not Python.
    # Expressions, comments, escapes or new forms require explicit review.
    $literal = '(?:"[A-Za-z0-9_./-]+"|''[A-Za-z0-9_./-]+'')'
    if ($items -notmatch ',' -or
        $items -notmatch ('\A\s*' + $literal + '(?:\s*,\s*' + $literal + ')*\s*,?\s*\z')) {
        throw 'Unsupported catalog syntax refused.'
    }
    $names = @([regex]::Matches($items, $literal) | ForEach-Object { $_.Value.Substring(1, $_.Value.Length - 2) })
    if (@($names | Sort-Object -Unique).Count -ne $names.Count) {
        throw 'Duplicate catalog names refused.'
    }
    return $names
}

try {
    $dependencies = @('net_play.ps1', 'net_preflight.ps1', 'collect_test_logs.ps1', 't4_buildid.py')
    foreach ($source in @('tools/package_release.py', 'tools/test_zip.py')) {
        $names = @(Read-LiteralCatalog $source 'TOOLS')
        foreach ($name in $names) {
            if ($name.Contains('/')) { throw 'Tool catalog must contain basenames only.' }
            $null = Get-CheckedFile ('tools/' + $name)
        }
        foreach ($name in $dependencies) {
            if ($names -cnotcontains $name) { throw 'Host/Join dependency missing from a tool catalog.' }
        }
        if ($source -eq 'tools/test_zip.py' -and $names -contains 'make_player_zip.ps1') {
            throw 'Source-only catalog contains the incomplete player wrapper.'
        }
        Write-Output "SOURCE: $source TOOLS: $($names.Count) unique existing files; Host/Join dependencies present."
    }

    $rootFiles = @(Read-LiteralCatalog 'tools/test_zip.py' 'ROOT_FILES')
    foreach ($name in $rootFiles) { $null = Get-CheckedFile $name }
    foreach ($name in @('LICENSE', 'TEST_ONLINE_DE.txt', 'docs/THIRD_PARTY.md')) {
        if ($rootFiles -cnotcontains $name) { throw 'Required source-only root input missing.' }
    }
    Write-Output "SOURCE: test_zip.py ROOT_FILES: $($rootFiles.Count) unique existing files."

    foreach ($name in @('Tekken4.cmd', 'launcher/t4core.py', 'launcher/t4_launcher.pyw',
        'tools/test_launcher_online.py', 'tools/test_release_catalogs.py',
        'docs/BETA_RELEASE_NOTES.md', 'docs/KNOWN_ISSUES.md', 'docs/BETA_GO_NO_GO.md')) {
        $null = Get-CheckedFile $name
    }
    Write-Output 'SOURCE: starter, launcher, Python test sources and beta documents exist.'
    Write-Output 'UNRUN: Python suites and packagers, staged payload scans, launcher GUI, Host/Join and game.'
    Write-Output 'Catalog inspection passed. Exit 0 covers source catalogs only; online readiness remains BLOCKED.'
    exit 0
} catch {
    Write-Output 'FAIL: Catalog inspection stopped. Missing, unsafe, duplicate or unsupported catalog input.'
    exit 1
}
