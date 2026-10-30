param([Parameter(Mandatory = $true)][string]$Task, [switch]$Remove, [switch]$Diff)
# A long Grok work task gets its own clean PS2Recomp tree external\wt-<Task> so its builds do not compile other tasks'
# half-done edits. Run by the lead / grok-manager BEFORE starting the task (Grok itself may not run git worktree).
#   powershell -File tools\grok_tree.ps1 -Task <t>           create: external/PS2Recomp HEAD (detached) + patches\*.patch
#                                                            applied in name order, then one local "baseline" commit so
#                                                            `git diff HEAD` in the tree = only the task's edits
#   powershell -File tools\grok_tree.ps1 -Task <t> -Diff     task edits -> logs\grok\<t>-tree.patch (new files included)
#   powershell -File tools\grok_tree.ps1 -Task <t> -Remove   drop the tree (after the lead took the patch)
# tools\grok_build.cmd <t> and tools\grok_run.ps1 -Task <t> use the tree automatically when it exists.
# Task prompt: say "PS2Recomp tree: external/wt-<t>; edit files there, not in external/PS2Recomp" and give -Owns as
# external/wt-<t>/<file>. Game overrides (runtime/*_overrides.cpp) are still the shared ones, staged into the tree.
$root = Split-Path -Parent $PSScriptRoot
$main = Join-Path $root "external\PS2Recomp"
$tree = Join-Path $root "external\wt-$Task"
if ($Remove) {
    git -C $main worktree remove --force $tree
    git -C $main worktree prune
    "removed $tree"; exit 0
}
if ($Diff) {
    if (-not (Test-Path $tree)) { "no tree $tree"; exit 1 }
    git -C $tree add -N . 2>$null
    $d = git -C $tree diff HEAD
    $out = Join-Path $root "logs\grok\$Task-tree.patch"
    [System.IO.File]::WriteAllText($out, (($d -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
    "$out ({0} lines); lead: git -C external\PS2Recomp apply --check $out, then fold into patches\ or the owned file" -f $d.Count
    exit 0
}
if (Test-Path $tree) { "tree exists: $tree"; exit 0 }
git -C $main worktree add --detach $tree HEAD
if ($LASTEXITCODE) { "worktree add failed"; exit 1 }
# No submodules in PS2Recomp (checked 2026-10-22); if that changes: git -C $tree submodule update --init
foreach ($p in Get-ChildItem (Join-Path $root "patches") -Filter *.patch | Sort-Object Name) {
    git -C $tree apply --reverse --check $p.FullName 2>$null
    if ($LASTEXITCODE -eq 0) { continue }  # already in HEAD (patch 01 is the dmac-mfifo commit)
    git -C $tree apply $p.FullName
    if ($LASTEXITCODE) { "patch $($p.Name) does not apply on $tree"; exit 1 }
}
git -C $tree add -A
git -C $tree -c user.name=grok-tree -c user.email=grok-tree@localhost commit -q -m "baseline: upstream HEAD + patches" 
"tree ready: $tree (baseline $((git -C $tree rev-parse --short HEAD)))"
