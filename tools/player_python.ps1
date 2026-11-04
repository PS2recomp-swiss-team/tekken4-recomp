# Interpreter selection shared by the thin Windows compatibility wrappers.
function Get-PlayerPython {
    $bundled = Join-Path $PSScriptRoot '..\python\python.exe'
    if (Test-Path -LiteralPath $bundled -PathType Leaf) { return @{ Exe = $bundled; Pre = @() } }
    if ($env:T4_PYTHON -and (Test-Path -LiteralPath $env:T4_PYTHON -PathType Leaf)) {
        return @{ Exe = $env:T4_PYTHON; Pre = @() }
    }
    foreach ($name in @('python', 'py', 'python3')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) {
            $pre = @(); if ($name -eq 'py') { $pre = @('-3') }
            $savedPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                & $cmd.Source @pre -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>$null
            } finally { $ErrorActionPreference = $savedPreference }
            if ($LASTEXITCODE -eq 0) { return @{ Exe = $cmd.Source; Pre = $pre } }
        }
    }
    throw 'Python 3.8+ not found. Install Python or extract the complete release zip.'
}

function Invoke-PlayerPython([string]$Script, [hashtable]$Parameters) {
    $py = Get-PlayerPython
    $argv = @($py.Pre) + @('-I', '-u', (Join-Path $PSScriptRoot $Script))
    foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $argv += "-$key" }
        } elseif ($null -ne $value) {
            $argv += "-$key"
            if ($key -eq 'Steps') { $argv += ($value -join ',') } else { $argv += [string]$value }
        }
    }
    $savedConsoleEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        & $py.Exe @argv
    } finally { [Console]::OutputEncoding = $savedConsoleEncoding }
}
