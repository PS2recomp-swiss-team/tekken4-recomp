param([string]$Tree = "external\ps2recomp-p15check")
# Builds the runtime from a clean PS2Recomp worktree (upstream + only the committed patches applied there) with only
# the COMMITTED game overrides (runtime/*_overrides.cpp at HEAD), so unmerged Grok edits in the shared tree or in
# runtime\ never take part. Run the result with TEKKEN4_SRC set to the same tree:
#   powershell -File tools\clean_build.ps1
#   $env:TEKKEN4_SRC = "<root>\external\ps2recomp-p15check"; powershell -File tools\run_capture.ps1 -RunDir logs\x ...
# Keep the tree's patch stack current: `git -C <tree> apply ../../patches/NN-*.patch` for each newly committed patch.
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root $Tree
if (-not (Test-Path (Join-Path $src "ps2xRuntime"))) { "no PS2Recomp tree at $src"; exit 1 }
$env:TEKKEN4_SRC = $src
& cmd /c "`"$(Join-Path $root 'tools\stage_generated.cmd')`""
if ($LASTEXITCODE) { "staging failed"; exit 1 }
$runner = Join-Path $src "ps2xRuntime\src\runner"
$committed = @(git -C $root ls-tree --name-only HEAD runtime/ | Where-Object { $_ -like '*_overrides.cpp' } | ForEach-Object { Split-Path -Leaf $_ })
$stale = @(Get-ChildItem $runner -Filter *_overrides.cpp | Where-Object { $committed -notcontains $_.Name })
if ($stale.Count) { "stale overrides in $runner (not in HEAD): " + (($stale | ForEach-Object Name) -join ', ') + " - deleting is not allowed; ask the user to remove them"; exit 1 }
foreach ($f in @(git -C $root ls-tree --name-only HEAD runtime/ | Where-Object { $_ -like '*_overrides.cpp' })) {
    $text = (git -C $root show "HEAD:$f") -join "`n"
    [System.IO.File]::WriteAllText((Join-Path $runner (Split-Path -Leaf $f)), $text + "`n", (New-Object System.Text.UTF8Encoding $false))
    "staged committed $f"
}
& cmd /c "`"$(Join-Path $root 'tools\build_runtime.cmd')`""
exit $LASTEXITCODE
