param([Parameter(Mandatory = $true)][string[]]$Path)
# The ONLY sanctioned way for Claude/Grok to clear something away (user, 2026-10-28): it MOVES the item into
# "<project>\to clean\" so the user can inspect it and decide; nothing is ever deleted or overwritten.
# Refuses: anything outside the project root, the root itself, .git, "to clean" itself, existing-name collisions (gets a timestamp suffix).
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path.TrimEnd('\')
$dest = Join-Path $root "to clean"
if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
$log = Join-Path $root "logs\to_clean.log"
foreach ($p in ($Path -join "," -split ",")) {
    if (-not (Test-Path -LiteralPath $p)) { "missing: $p"; continue }
    $full = (Resolve-Path -LiteralPath $p).Path.TrimEnd('\')
    $rel = $full.Substring([Math]::Min($full.Length, $root.Length))
    if (-not $full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { "refused (outside project): $full"; continue }
    if ($rel.StartsWith('\.git', [StringComparison]::OrdinalIgnoreCase) -or $rel.StartsWith('\to clean', [StringComparison]::OrdinalIgnoreCase)) { "refused (protected): $full"; continue }
    $name = Split-Path -Leaf $full
    $target = Join-Path $dest $name
    if (Test-Path -LiteralPath $target) { $target = Join-Path $dest ("{0}.{1}" -f $name, (Get-Date -Format yyyyMMdd_HHmmss)) }
    Move-Item -LiteralPath $full -Destination $target
    "moved: $full -> $target"
    Add-Content -Path $log -Value ("{0} {1} -> {2}" -f (Get-Date -Format s), $full, $target)
}
