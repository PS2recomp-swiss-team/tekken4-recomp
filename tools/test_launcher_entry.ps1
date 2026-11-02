# Exercise only the real starter's missing-private-Python refusal.
# Exit 0 proves this refusal test, never launcher or online readiness.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$prefix = $root.TrimEnd('\') + '\'
$starter = Join-Path $root 'Tekken4.cmd'
$expectedHash = '9239F2525A51803E6B99BAE66718E91FB3B118C5EAE557DFB0ADD00FAE7910B1'
$missing = 'Private Python is missing. Extract the complete player release zip first.'
$proc = $null

function Assert-LocalItem([string]$Path, [bool]$Directory) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -ne $root -and -not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Source-tree boundary refused.'
    }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Reparse point refused.'
    }
    if ($item.PSIsContainer -ne $Directory) { throw 'Unexpected source-tree item type.' }
}

try {
    Assert-LocalItem $root $true
    Assert-LocalItem $PSScriptRoot $true
    Assert-LocalItem $PSCommandPath $false
    Assert-LocalItem $starter $false
    $privatePython = Join-Path $root 'python'
    if (Test-Path -LiteralPath $privatePython) {
        Assert-LocalItem $privatePython $true
        foreach ($name in @('python.exe', 'pythonw.exe')) {
            $interpreter = Join-Path $privatePython $name
            if (Test-Path -LiteralPath $interpreter) {
                Assert-LocalItem $interpreter $false
                throw 'Private Python exists; this refusal-only test will not launch it.'
            }
        }
    }
    # Pin the actual starter before executing it. Changed starters need a fresh
    # safety review; this check must never fall through into the GUI branch.
    if ((Get-FileHash -LiteralPath $starter -Algorithm SHA256).Hash -ne $expectedHash) {
        throw 'Starter changed; refusal-only execution needs review.'
    }

    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'cmd.exe'
    $info.Arguments = '/d /c "call .\Tekken4.cmd < nul"'
    $info.WorkingDirectory = $root
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $info
    if (-not $proc.Start()) { throw 'Starter subprocess did not start.' }
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit(10000)) {
        $proc.Kill()
        throw 'Starter refusal timed out.'
    }
    $out = $stdout.GetAwaiter().GetResult()
    $err = $stderr.GetAwaiter().GetResult()
    if ($proc.ExitCode -ne 1 -or -not $out.Contains($missing) -or $err.Trim()) {
        throw 'Starter did not produce the expected missing-private-Python refusal.'
    }
    Write-Output 'PASS: real Tekken4.cmd returned exit 1 with the missing-private-Python message.'
    Write-Output 'STARTER_REFUSAL_OBSERVED'
    Write-Output 'GUI UNRUN; game UNRUN; online readiness BLOCKED.'
    Write-Output 'Exit 0 applies only to this negative entry-point test.'
    exit 0
} catch {
    # Do not echo native exception text: it can include a player's path.
    Write-Output 'FAIL: refusal-only starter test stopped; preflight or expected refusal was not satisfied.'
    Write-Output 'GUI UNRUN; game UNRUN; online readiness BLOCKED.'
    exit 1
} finally {
    if ($proc) { $proc.Dispose() }
}
