# US tree compatibility API; all selection and branch checks live in us_tree.py.
. (Join-Path $PSScriptRoot 'player_python.ps1')
function Get-UsTreeBranch([string]$Tree) {
    $py = Get-PlayerPython
    & $py.Exe @($py.Pre) -I (Join-Path $PSScriptRoot 'us_tree.py') -Branch $Tree
}
function Resolve-UsTree([string]$Root) {
    $py = Get-PlayerPython
    $savedConsoleEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $tree = & $py.Exe @($py.Pre) -I (Join-Path $PSScriptRoot 'us_tree.py') -Root $Root
    } finally { [Console]::OutputEncoding = $savedConsoleEncoding }
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the US PS2Recomp tree (see error above).' }
    return $tree
}
