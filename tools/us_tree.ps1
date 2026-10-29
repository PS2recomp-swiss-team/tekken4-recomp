# Same rule as tools\us_tree.cmd for PowerShell scripts: dot-source it, then Resolve-UsTree <repo root> gives the US
# PS2Recomp tree. TEKKEN4_SRC wins; else ..\tekken4-fork-ps2recomp_usa when it exists, or ..\tekken4-fork-ps2recomp when
# that one is free or on branch t4-us, else ..\tekken4-fork-ps2recomp_usa (to be cloned: the plain name holds the PAL
# cousin project's tree). An existing tree not on branch t4-us is refused (never build into the PAL tree).
function Get-UsTreeBranch([string]$Tree)
{
    return (git -C $Tree rev-parse --abbrev-ref HEAD 2>$null)
}

function Resolve-UsTree([string]$Root)
{
    $parent = Split-Path -Parent $Root
    $plain = Join-Path $parent "tekken4-fork-ps2recomp"
    $own = Join-Path $parent "tekken4-fork-ps2recomp_usa"
    $tree = if ($env:TEKKEN4_SRC) { $env:TEKKEN4_SRC }
            elseif (Test-Path $own) { $own }
            elseif (-not (Test-Path (Join-Path $plain ".git")) -or (Get-UsTreeBranch $plain) -eq "t4-us") { $plain }
            else { $own }
    $tree = [IO.Path]::GetFullPath($tree).TrimEnd('\')
    if (Test-Path (Join-Path $tree ".git")) {
        $branch = Get-UsTreeBranch $tree
        if ($branch -ne "t4-us") {
            throw "$tree is on branch '$branch', not t4-us: not the US PS2Recomp tree. Set TEKKEN4_SRC to the US tree."
        }
    }
    return $tree
}
