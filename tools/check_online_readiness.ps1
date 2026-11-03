# Source and refusal checks only. No builds, games, server or network tools run.
# Exit 0 is deliberately unavailable: this copy cannot prove online acceptance.
[CmdletBinding()]
param(
    [string[]]$Docs = @(
        'CODEX_PROGRESS.md', 'SERVER_HANDOFF_T4.md', 'docs/LOBBY.md',
        'docs/ONLINE_ACCOUNTS.md', 'docs/ONLINE_SWITCH_EVIDENCE.md',
        'docs/ONLINE_RANKS.md', 'docs/ONLINE_COEXISTENCE.md'
    )
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$prefix = $root.TrimEnd('\') + '\'

function Get-CheckedPath([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { throw 'Empty source path refused.' }
    $path = if ([IO.Path]::IsPathRooted($Name)) { [IO.Path]::GetFullPath($Name) }
            else { [IO.Path]::GetFullPath((Join-Path $root $Name)) }
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Source path outside this tree refused before access.'
    }
    $relative = $path.Substring($prefix.Length)
    $current = $root
    foreach ($part in $relative.Split('\')) {
        $current = Join-Path $current $part
        if (-not (Test-Path -LiteralPath $current)) { throw 'Required source input is missing.' }
        if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Source reparse point refused before reading.'
        }
    }
    return $path
}

try {
    if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Source root reparse point refused.'
    }
    $sources = @(
        'AGENTS.md', 'Tekken4.cmd', 'launcher/t4core.py', 'launcher/t4_launcher.pyw',
        'runtime/tekken4_online_result.h', 'tools/net_play.ps1', 'tools/net_preflight.ps1',
        'tools/run_lock.ps1', 'tools/check_online_readiness.ps1',
        'tools/test_online_readiness.ps1', 'tools/test_launcher_entry.ps1',
        'tools/check_online_catalogs.ps1'
    )
    $syntaxCount = 0
    foreach ($name in $sources) {
        $path = Get-CheckedPath $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Required source input is not a file.' }
        if ([IO.Path]::GetExtension($path) -eq '.ps1') {
            $tokens = $null
            $parseErrors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors.Count) { throw "PowerShell syntax errors in $name." }
            $syntaxCount++
        }
    }
    Write-Output "SOURCE: $($sources.Count) required files; $syntaxCount PowerShell files parsed, not executed."

    if (-not $Docs.Count) { throw 'At least one source document is required.' }
    $linkCount = 0
    foreach ($doc in $Docs) {
        $path = Get-CheckedPath $doc
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.Path]::GetExtension($path) -ne '.md') {
            throw 'Source document must be a Markdown file.'
        }
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText($path), '\[[^\]]*\]\((?<target>[^)]+)\)')) {
            $target = $match.Groups['target'].Value.Trim()
            if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $target.StartsWith('#')) { continue }
            $target = $target.Split('#')[0].Trim('<', '>')
            if (-not $target) { continue }
            $linked = [IO.Path]::GetFullPath((Join-Path (Split-Path $path -Parent) $target))
            $null = Get-CheckedPath $linked
            $linkCount++
        }
    }
    Write-Output "SOURCE: $($Docs.Count) documents; $linkCount local links checked (external URLs and anchors untested)."

    $shell = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $shell -PathType Leaf)) { throw 'Windows PowerShell unavailable; entry checks did not run.' }
    foreach ($entry in @('tools/check_online_catalogs.ps1', 'tools/test_launcher_entry.ps1')) {
        Write-Output "ENTRY: $entry"
        & $shell -NoProfile -ExecutionPolicy Bypass -File (Get-CheckedPath $entry)
        if ($LASTEXITCODE -ne 0) { throw "Entry check failed: $entry." }
    }
    Write-Output 'SOURCE checks completed; expected starter refusal is not a GUI launch.'
    Write-Output 'BLOCKED: online acceptance. Shared-launcher and private lobby integration are unavailable in this copy.'
    Write-Output 'UNRUN: Python suites; actual launcher GUI Host/Join; login/search/kicked; cross-launcher game guard; real game/result validation; two-PC direct/relay play.'
    Write-Output 'UNPROVEN: enabled COALESCE/DIAG launcher profile. Supplied switches-off same-PC pair evidence does not prove this tree or two-PC play.'
    Write-Output 'OWNER: validate the exact reviewed build and effective switches through both real launchers, then supply pair logs and authoritative results.'
    exit 2
} catch {
    Write-Output "FAIL: online source check stopped: $($_.Exception.Message)"
    Write-Output 'BLOCKED: online acceptance; no launcher/game success is claimed.'
    exit 1
}
