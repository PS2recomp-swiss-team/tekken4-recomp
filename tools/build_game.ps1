<#
.SYNOPSIS
  One unattended pipeline from a player's own Tekken 4 (US) ISO to a runnable native game.

.DESCRIPTION
  Steps (each is skipped when already done and up to date; state in logs\build_game_state.json):
    prereq   Python 3, Git, VS 2022 Build Tools (C++), CMake, Ninja are present (prints what is missing and how to get it)
    verify   the ISO's SYSTEM.CNF says BOOT2 = cdrom0:\SLUS_203.28;1 and the ELF's SHA-1 is a4b7dde2...5815
    extract  SYSTEM.CNF, SLUS_203.28, IRX\IOPRP243.IMG, TEKKEN\DATA.BIN -> game\disc\  (tools\iso_extract.py)
    fork     clone ran-j/PS2Recomp at eb8688b into ..\tekken4-fork-ps2recomp (or %TEKKEN4_SRC%) and commit patches\*.patch
             one by one (only when that tree does not exist)
    tools    tools\build_ps2recomp_tools.cmd (only when out\tools\ps2xRecomp\ps2_recomp.exe is missing / the tree moved on)
    recomp   ps2_recomp.exe config\ghidra_export.toml  (-> generated\)
    stage    tools\stage_generated.cmd
    runtime  tools\build_runtime.cmd
  Then it prints the line that starts the game. Everything is logged with timings to logs\build_game.log; the
  first failing step stops the run and is named. The function map, jump tables and overrides are committed config,
  so no Ghidra and no BIOS are needed.

.PARAMETER Iso
  Path to the game's ISO. Default: the first *.iso in the repo root.
.PARAMETER Force
  Ignore the up-to-date checks and redo every step (the PS2Recomp tree is never re-cloned).
.PARAMETER WhatIf
  Dry run: do the read-only checks (prerequisites, ISO verification), print which steps would run, change nothing.
.PARAMETER Steps
  Run only these steps (names above), e.g. -Steps fork. Default: all.
.PARAMETER LogDir
  Where build_game.log and build_game_state.json go (default: <repo>\logs).

  Environment: TEKKEN4_SRC (PS2Recomp tree, default ..\tekken4-fork-ps2recomp), TEKKEN4_FORK_URL (clone source,
  default https://github.com/ran-j/PS2Recomp), TEKKEN4_BUILD_DIR (default runtime).
#>
param(
    [string]$Iso,
    [switch]$Force,
    [switch]$WhatIf,
    [string[]]$Steps,
    [string]$LogDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$env:GIT_TERMINAL_PROMPT = '0'

$ExpectedElfSha1 = 'a4b7dde20a2918c550badd127a245db155c36815'
$PinnedCommit    = 'eb8688b'
$ForkBranch      = 't4-us'
$DefaultForkUrl  = 'https://github.com/ran-j/PS2Recomp'
$Root     = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path.TrimEnd('\')
$AllSteps = @('prereq', 'verify', 'extract', 'fork', 'tools', 'recomp', 'stage', 'runtime')
if (-not $Steps -or $Steps.Count -eq 0) { $Steps = $AllSteps }
$Steps = @($Steps -join ',' -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
foreach ($s in $Steps) { if ($AllSteps -notcontains $s) { Write-Host "Unknown step '$s'. Steps: $($AllSteps -join ', ')"; exit 2 } }

if (-not $LogDir) { $LogDir = Join-Path $Root 'logs' }
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
$LogPath   = Join-Path $LogDir 'build_game.log'
$StatePath = Join-Path $LogDir 'build_game_state.json'
$GameDisc  = Join-Path $Root 'game\disc'
$Tree = if ($env:TEKKEN4_SRC) { $env:TEKKEN4_SRC } else { Join-Path $Root '..\tekken4-fork-ps2recomp' }
$Tree = [IO.Path]::GetFullPath($Tree).TrimEnd('\')
$BuildDirName = if ($env:TEKKEN4_BUILD_DIR) { $env:TEKKEN4_BUILD_DIR } else { 'runtime' }
$RecompExe  = Join-Path $Tree 'out\tools\ps2xRecomp\ps2_recomp.exe'
$RunnerExe  = Join-Path $Tree "out\$BuildDirName\ps2xRuntime\ps2EntryRunner.exe"

# ---------------------------------------------------------------- log / console
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$LogWriter = New-Object System.IO.StreamWriter($LogPath, $true, $Utf8)
$LogWriter.AutoFlush = $true
$Script:LastLines = $null

function Log([string]$Msg) { $LogWriter.WriteLine(('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Msg)) }
function Say([string]$Msg) { Write-Host $Msg; Log $Msg }

function Fail([string]$Step, [string]$Msg) {
    Say ''
    Say "FAILED at step '$Step': $Msg"
    if ($Script:LastLines -and $Script:LastLines.Count -gt 0) {
        Say '--- last output ---'
        foreach ($l in $Script:LastLines) { Write-Host $l }
        Say '-------------------'
    }
    Say "Full log: $LogPath"
    $LogWriter.Dispose()
    exit 1
}

# Runs a program, appends every output line to the log, keeps the last 40 lines, returns the exit code.
function Invoke-Logged {
    param([string]$File, [string[]]$ArgList = @(), [string]$WorkDir = $Root, [string]$Echo = '', [string]$Label = '')
    $Script:LastLines = New-Object 'System.Collections.Generic.List[string]'
    Log ("> {0} {1}   (cwd {2})" -f $File, ($ArgList -join ' '), $WorkDir)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location -LiteralPath $WorkDir
    try {
        & $File @ArgList 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $s = $_.Exception.Message } else { $s = [string]$_ }
            $s = $s.TrimEnd()
            if ($s.Length -gt 0) {
                $LogWriter.WriteLine($s)
                $Script:LastLines.Add($s)
                if ($Script:LastLines.Count -gt 40) { $Script:LastLines.RemoveAt(0) }
                if ($Echo -and ($s -match $Echo)) { Write-Host "    $s" }
                if ($Label) { Write-Progress -Activity $Label -Status ($s.Substring(0, [Math]::Min(110, $s.Length))) }
            }
        }
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
        $ErrorActionPreference = $old
        if ($Label) { Write-Progress -Activity $Label -Completed }
    }
    Log "< exit code $code"
    return $code
}

# ---------------------------------------------------------------- state file
function ConvertTo-Hash($o) {
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hash $p.Value }
        return $h
    }
    return $o
}
$State = @{}
if (Test-Path -LiteralPath $StatePath) {
    try { $State = ConvertTo-Hash (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json) } catch { $State = @{}; Log "state file unreadable, starting fresh: $_" }
    if ($State -isnot [hashtable]) { $State = @{} }
}
function Save-State {
    if ($WhatIf) { return }
    $State['updated'] = (Get-Date).ToString('s')
    ($State | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $StatePath -Encoding UTF8
}
function Get-StateValue([string]$Step, [string]$Key) {
    if ($State.ContainsKey($Step) -and ($State[$Step] -is [hashtable]) -and $State[$Step].ContainsKey($Key)) { return $State[$Step][$Key] }
    return $null
}
function Set-StateValues([string]$Step, [hashtable]$Values) {
    if (-not ($State.ContainsKey($Step) -and ($State[$Step] -is [hashtable]))) { $State[$Step] = @{} }
    foreach ($k in $Values.Keys) { $State[$Step][$k] = $Values[$k] }
    Save-State
}

# ---------------------------------------------------------------- fingerprints
function Sha1Text([string]$Text) {
    $sha = [System.Security.Cryptography.SHA1]::Create()
    return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '').ToLower()
}
# name|size|mtime of each file (cheap; no content read)
function Get-StatFingerprint([string[]]$Paths) {
    $lines = foreach ($p in ($Paths | Sort-Object)) {
        if (Test-Path -LiteralPath $p -PathType Leaf) { $i = Get-Item -LiteralPath $p; '{0}|{1}|{2}' -f $i.Name, $i.Length, $i.LastWriteTimeUtc.Ticks }
    }
    return (Sha1Text ($lines -join "`n"))
}
function Get-ContentFingerprint([string[]]$Paths) {
    $lines = foreach ($p in ($Paths | Sort-Object)) {
        if (Test-Path -LiteralPath $p -PathType Leaf) { '{0}|{1}' -f (Split-Path -Leaf $p), (Get-FileHash -LiteralPath $p -Algorithm SHA1).Hash }
    }
    return (Sha1Text ($lines -join "`n"))
}
function Files([string]$Dir, [string]$Filter, [switch]$Recurse) {
    if (-not (Test-Path -LiteralPath $Dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $Dir -Filter $Filter -File -Recurse:$Recurse | ForEach-Object { $_.FullName })
}
function Get-TreeHead { $h = & git -C $Tree rev-parse HEAD 2>$null; if ($LASTEXITCODE -eq 0) { return "$h".Trim() }; return '' }

# ---------------------------------------------------------------- step runner
$Timings = New-Object System.Collections.ArrayList
$Changed = @{}      # step -> $true when it ran (or would run in a dry run); later steps depend on that
$Script:Tools = @{}
$StepNo = 0
function Step([string]$Name, [string]$Title, [scriptblock]$Body) {
    if ($Steps -notcontains $Name) { return }
    $Script:StepNo++
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Say ''
    Say ("[{0}/{1}] {2} - {3}" -f $Script:StepNo, $Steps.Count, $Name, $Title)
    $Script:LastLines = $null
    try {
        $r = @(& $Body)
        $result = if ($r.Count -gt 0) { [string]$r[-1] } else { 'done' }
    } catch {
        Fail $Name ($_.Exception.Message)
    }
    $sw.Stop()
    [void]$Timings.Add(('{0,-8} {1,-12} {2:N1}s' -f $Name, $result, $sw.Elapsed.TotalSeconds))
    Say ("    {0} ({1:N1}s)" -f $result, $sw.Elapsed.TotalSeconds)
}
function Plan([string]$Text) { Say "    [WhatIf] would $Text" }

# ================================================================ header
Say "=== build_game $(Get-Date -Format s)  root=$Root  steps=$($Steps -join ',')  force=$($Force.IsPresent)  whatif=$($WhatIf.IsPresent)"
$PipelineClock = [Diagnostics.Stopwatch]::StartNew()

# ================================================================ prereq
Step 'prereq' 'Python 3, Git, VS 2022 Build Tools (C++), CMake, Ninja' {
    $missing = New-Object System.Collections.ArrayList

    # Python 3 (the Microsoft Store stub in WindowsApps answers with an error, so test-run each candidate)
    $py = $null
    foreach ($cand in @(@('python'), @('py', '-3'), @('python3'))) {
        $cmd = Get-Command $cand[0] -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { continue }
        $pre = @(); if ($cand.Count -gt 1) { $pre = @($cand[1..($cand.Count - 1)]) }
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $v = & $cmd.Source @pre -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $old
        if ($ok -and "$v" -match '^3\.(\d+)$' -and [int]$Matches[1] -ge 8) { $py = @{ Exe = $cmd.Source; Pre = $pre; Version = "$v" }; break }
    }
    if ($py) { Say "    Python $($py.Version): $($py.Exe)" } else {
        [void]$missing.Add("Python 3.8+ (needed to read the ISO)`n      get it: winget install Python.Python.3.12   or https://www.python.org/downloads/ (tick 'Add python.exe to PATH'). The Microsoft Store 'python' stub does not count.")
    }
    $Script:Tools['py'] = $py

    if (Get-Command git -ErrorAction SilentlyContinue) { Say "    Git: $((Get-Command git).Source)" } else {
        [void]$missing.Add("Git (clones PS2Recomp and builds fetch their libraries with it)`n      get it: winget install Git.Git   or https://git-scm.com/download/win")
    }

    # Visual Studio 2022 Build Tools with the C++ x64 toolset (what build_*.cmd call through vswhere/vcvars64)
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $vs = $null
    if (Test-Path -LiteralPath $vswhere) {
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $vs = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1)
        $ErrorActionPreference = $old
    }
    if ($vs -and (Test-Path -LiteralPath (Join-Path "$vs" 'VC\Auxiliary\Build\vcvars64.bat'))) { Say "    MSVC C++ tools: $vs" } else {
        [void]$missing.Add("Visual Studio 2022 Build Tools with 'Desktop development with C++' (MSVC x64 + Windows SDK)`n      get it: winget install Microsoft.VisualStudio.2022.BuildTools --override `"--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended`"`n      or https://visualstudio.microsoft.com/downloads/ -> 'Build Tools for Visual Studio 2022' -> workload 'Desktop development with C++'")
    }

    # CMake / Ninja: PATH first, then the places the .cmd scripts add
    $extra = @((Join-Path $env:ProgramFiles 'CMake\bin'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'))
    if ($vs) {
        $extra += (Join-Path "$vs" 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin')
        $extra += (Join-Path "$vs" 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja')
    }
    foreach ($tool in @(@('cmake', 'CMake 3.20+', 'winget install Kitware.CMake   or https://cmake.org/download/ (choose "add to PATH")'),
                        @('ninja', 'Ninja', 'winget install Ninja-build.Ninja   or https://github.com/ninja-build/ninja/releases (put ninja.exe on PATH)'))) {
        $found = $null
        $c = Get-Command $tool[0] -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c) { $found = $c.Source } else {
            foreach ($d in $extra) { $p = Join-Path $d ($tool[0] + '.exe'); if (Test-Path -LiteralPath $p) { $found = $p; $env:PATH = "$d;$env:PATH"; break } }
        }
        if ($found) { Say "    $($tool[1]): $found" } else { [void]$missing.Add("$($tool[1])`n      get it: $($tool[2])") }
    }

    if ($missing.Count -gt 0) {
        Say ''
        Say 'Missing prerequisites:'
        $i = 1; foreach ($m in $missing) { Say "  $i. $m"; $i++ }
        Say ''
        Say 'Install them (a new terminal may be needed so PATH updates), then run this script again. The build also downloads'
        Say "its libraries (ELFIO, fmt, raylib, ...) from GitHub, so it needs an internet connection."
        throw "$($missing.Count) prerequisite(s) missing, see above"
    }
    'ok'
}

# ================================================================ ISO
function Invoke-Py([string[]]$PyArgs, [string]$Echo = '', [string]$Label = '') {
    $py = $Script:Tools['py']
    if (-not $py) {
        $c = Get-Command python, py -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $c) { throw 'Python 3 not found (run the prereq step)' }
        $py = @{ Exe = $c.Source; Pre = @() }; if ($c.Name -ieq 'py.exe') { $py.Pre = @('-3') }
        $Script:Tools['py'] = $py
    }
    $a = @($py.Pre) + @('-I', (Join-Path $PSScriptRoot 'iso_extract.py')) + $PyArgs
    return (Invoke-Logged -File $py.Exe -ArgList $a -Echo $Echo -Label $Label)
}

if (-not $Iso) {
    $first = Get-ChildItem -LiteralPath $Root -Filter '*.iso' -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
    if ($first) { $Iso = $first.FullName }
}
$IsoInfo = $null
if (($Steps -contains 'verify') -or ($Steps -contains 'extract')) {
    if (-not $Iso) { Fail 'verify' "no ISO given and no *.iso in $Root. Usage: powershell -ExecutionPolicy Bypass -File tools\build_game.ps1 -Iso `"C:\path\Tekken 4 (USA).iso`"" }
    if (-not (Test-Path -LiteralPath $Iso -PathType Leaf)) { Fail 'verify' "ISO not found: $Iso" }
    $IsoInfo = Get-Item -LiteralPath $Iso
    $IsoFp = '{0}|{1}|{2}' -f $IsoInfo.FullName.ToLower(), $IsoInfo.Length, $IsoInfo.LastWriteTimeUtc.Ticks
}
$IsoFiles = @{}   # path inside ISO -> size, filled by the verify step (or taken from the state)

Step 'verify' "ISO is Tekken 4 US (SLUS-20328): $Iso" {
    if (-not $Force -and (Get-StateValue 'verify' 'fingerprint') -eq $IsoFp -and (Get-StateValue 'verify' 'elfSha1') -eq $ExpectedElfSha1) {
        $f = Get-StateValue 'verify' 'files'
        foreach ($k in $f.Keys) { $IsoFiles[$k] = [int64]$f[$k] }
        return 'up to date'
    }
    $code = Invoke-Py @($IsoInfo.FullName, '--check')
    $out = $Script:LastLines.ToArray()
    if ($code -ne 0) {
        $err = ($out | Where-Object { $_ -like 'ERROR:*' } | Select-Object -First 1)
        if (-not $err) { $err = "iso_extract.py exited with code $code" }
        if ($code -eq 2 -or $code -eq 3) { throw "$Iso is not a supported disc image.`n    $err`n    Only Tekken 4 (USA), serial SLUS-20328, is supported." }
        throw $err
    }
    $sha = ($out | Where-Object { $_ -like 'ELF_SHA1 *' } | Select-Object -First 1)
    if (-not $sha -or $sha.Split(' ')[1] -ne $ExpectedElfSha1) { throw "ELF SHA-1 on the disc does not match $ExpectedElfSha1" }
    foreach ($l in $out) { if ($l -match '^FILE (\S+) (\d+)$') { $IsoFiles[$Matches[1]] = [int64]$Matches[2] } }
    if ($IsoFiles.Count -lt 4) { throw 'the disc is missing files the port needs' }
    Say "    BOOT2 = cdrom0:\SLUS_203.28;1, ELF SHA-1 $ExpectedElfSha1 - ok"
    if ($WhatIf) { return 'checked' }
    Set-StateValues 'verify' @{ fingerprint = $IsoFp; iso = $IsoInfo.FullName; elfSha1 = $ExpectedElfSha1; files = $IsoFiles }
    'verified'
}

Step 'extract' 'SYSTEM.CNF, SLUS_203.28, IRX\IOPRP243.IMG, TEKKEN\DATA.BIN -> game\disc' {
    if ($IsoFiles.Count -eq 0) {
        $f = Get-StateValue 'verify' 'files'
        if ($f) { foreach ($k in $f.Keys) { $IsoFiles[$k] = [int64]$f[$k] } }
        else {
            # verify was not part of this run: ask the ISO again (cheap)
            $code = Invoke-Py @($IsoInfo.FullName, '--check')
            if ($code -ne 0) { throw (($Script:LastLines | Where-Object { $_ -like 'ERROR:*' } | Select-Object -First 1)) }
            foreach ($l in $Script:LastLines) { if ($l -match '^FILE (\S+) (\d+)$') { $IsoFiles[$Matches[1]] = [int64]$Matches[2] } }
        }
    }
    $allThere = $true
    foreach ($k in $IsoFiles.Keys) {
        $p = Join-Path $GameDisc ($k -replace '/', '\')
        if (-not ((Test-Path -LiteralPath $p -PathType Leaf) -and ((Get-Item -LiteralPath $p).Length -eq $IsoFiles[$k]))) { $allThere = $false; break }
    }
    $elf = Join-Path $GameDisc 'SLUS_203.28'
    $elfOk = $allThere -and ((Get-FileHash -LiteralPath $elf -Algorithm SHA1).Hash.ToLower() -eq $ExpectedElfSha1)
    $recorded = Get-StateValue 'extract' 'fingerprint'
    # no record at all (files put there by hand or by an older setup): adopt them when sizes and the ELF SHA-1 match
    if (-not $Force -and $elfOk -and ((-not $recorded) -or $recorded -eq $IsoFp)) {
        if (-not $recorded -and -not $WhatIf) { Set-StateValues 'extract' @{ fingerprint = $IsoFp; adopted = $true } }
        return 'up to date'
    }
    if ($WhatIf) { Plan "extract 4 files ($([math]::Round(($IsoFiles.Values | Measure-Object -Sum).Sum / 1MB)) MB) into $GameDisc"; $Changed['extract'] = $true; return 'would run' }
    if (-not (Test-Path -LiteralPath $GameDisc)) { New-Item -ItemType Directory -Path $GameDisc | Out-Null }
    $a = @($IsoInfo.FullName, $GameDisc, '--files') + @($IsoFiles.Keys | Sort-Object { if ($_ -like '*DATA.BIN') { 1 } else { 0 } })
    $code = Invoke-Py $a -Echo '^\s+\S+ \d+%' -Label 'Extracting game files from the ISO'
    if ($code -ne 0) { throw (($Script:LastLines | Where-Object { $_ -like 'ERROR:*' } | Select-Object -First 1) + " (iso_extract.py exit $code)") }
    if ((Get-FileHash -LiteralPath $elf -Algorithm SHA1).Hash.ToLower() -ne $ExpectedElfSha1) { throw 'extracted SLUS_203.28 has the wrong SHA-1' }
    foreach ($k in $IsoFiles.Keys) {
        $p = Join-Path $GameDisc ($k -replace '/', '\')
        if (-not (Test-Path -LiteralPath $p) -or (Get-Item -LiteralPath $p).Length -ne $IsoFiles[$k]) { throw "$k was not extracted completely" }
    }
    Set-StateValues 'extract' @{ fingerprint = $IsoFp; adopted = $false }
    $Changed['extract'] = $true
    'extracted'
}

# ================================================================ PS2Recomp tree
Step 'fork' "PS2Recomp tree at $PinnedCommit + patches\*.patch ($Tree)" {
    $patches = @(Get-ChildItem -LiteralPath (Join-Path $Root 'patches') -Filter '*.patch' -File | Sort-Object Name)
    if ($patches.Count -eq 0) { throw 'patches\*.patch not found (incomplete checkout of this repo?)' }
    $inProgress = [bool](Get-StateValue 'fork' 'inProgress') -and ((Get-StateValue 'fork' 'tree') -eq $Tree)
    $exists = Test-Path -LiteralPath (Join-Path $Tree '.git')
    if ($exists -and -not $inProgress) {
        $subjects = @(& git -C $Tree log --format=%s 2>$null)
        $lastName = [IO.Path]::GetFileNameWithoutExtension($patches[-1].Name)
        if ($subjects -notcontains $lastName) {
            Say "    NOTE: $lastName is not committed in $Tree; tools\build_runtime.cmd will apply the missing patches to the working tree."
        }
        $head = Get-TreeHead
        Say "    using the existing tree, HEAD $($head.Substring(0, [Math]::Min(7, $head.Length)))"
        return 'exists'
    }
    $url = if ($env:TEKKEN4_FORK_URL) { $env:TEKKEN4_FORK_URL } else { $DefaultForkUrl }
    if ($WhatIf) { Plan "clone $url into $Tree, check out $PinnedCommit as branch $ForkBranch and commit $($patches.Count) patches"; $Changed['fork'] = $true; return 'would run' }

    Set-StateValues 'fork' @{ inProgress = $true; tree = $Tree }   # a half-cloned / half-patched tree is resumed next run
    if (-not $exists) {
        if (Test-Path -LiteralPath $Tree) {
            if (@(Get-ChildItem -LiteralPath $Tree -Force).Count -gt 0) { throw "$Tree exists but is not a git clone and is not empty; move it away or set TEKKEN4_SRC to another folder" }
        }
        $parent = Split-Path -Parent $Tree
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
        Say "    cloning $url (a few minutes)"
        $code = Invoke-Logged -File 'git' -ArgList @('-c', 'core.autocrlf=false', 'clone', $url, $Tree) -Label 'git clone PS2Recomp'
        if ($code -ne 0) { throw "git clone failed (exit $code); check the internet connection" }
        # the files must come out exactly as upstream has them: patches 01-32 were made against LF/CRLF as committed
        $code = Invoke-Logged -File 'git' -ArgList @('-C', $Tree, 'config', 'core.autocrlf', 'false')
        if ($code -ne 0) { throw 'git config core.autocrlf failed' }
    }
    # (a resumed run whose clone stopped before the checkout lands here too)
    if ("$(& git -C $Tree branch --show-current 2>$null)".Trim() -ne $ForkBranch) {
        $code = Invoke-Logged -File 'git' -ArgList @('-C', $Tree, 'checkout', '-B', $ForkBranch, $PinnedCommit)
        if ($code -ne 0) { throw "could not check out $PinnedCommit (does the upstream repository still have it?)" }
    }
    $committed = @(& git -C $Tree log --format=%s)
    $ident = @('-c', 'user.name=Tekken4 build', '-c', 'user.email=build@localhost', '-c', 'commit.gpgsign=false', '-c', 'core.autocrlf=false')
    $n = 0
    foreach ($p in $patches) {
        $name = [IO.Path]::GetFileNameWithoutExtension($p.Name)
        if ($committed -contains $name) { continue }
        # exact first; patches 18-23 and 30 only apply with --ignore-whitespace
        $mode = @()
        $code = Invoke-Logged -File 'git' -ArgList (@('-C', $Tree, '-c', 'core.autocrlf=false', 'apply', '--check') + $p.FullName)
        if ($code -ne 0) {
            $mode = @('--ignore-whitespace')
            $code = Invoke-Logged -File 'git' -ArgList (@('-C', $Tree, '-c', 'core.autocrlf=false', 'apply', '--check') + $mode + $p.FullName)
            if ($code -ne 0) { throw "$($p.Name) does not apply to the tree (not even with --ignore-whitespace)" }
        }
        $code = Invoke-Logged -File 'git' -ArgList (@('-C', $Tree, '-c', 'core.autocrlf=false', 'apply') + $mode + $p.FullName)
        if ($code -ne 0) { throw "git apply $($p.Name) failed" }
        $code = Invoke-Logged -File 'git' -ArgList @('-C', $Tree, 'add', '-A')
        if ($code -ne 0) { throw 'git add failed' }
        $code = Invoke-Logged -File 'git' -ArgList (@('-C', $Tree) + $ident + @('commit', '-q', '-m', $name))
        if ($code -ne 0) { throw "git commit for $($p.Name) failed" }
        $n++
        Say ("    applied {0}{1}" -f $p.Name, $(if ($mode.Count) { '  (--ignore-whitespace)' } else { '' }))
    }
    $head = Get-TreeHead
    Set-StateValues 'fork' @{ inProgress = $false; tree = $Tree; head = $head; patches = $patches.Count }
    $Changed['fork'] = $true
    "cloned, $n patches"
}

# ================================================================ PS2Recomp tools
Step 'tools' 'PS2Recomp host tools (ps2_recomp.exe)' {
    $head = Get-TreeHead
    $built = Get-StateValue 'tools' 'head'
    $haveExe = Test-Path -LiteralPath $RecompExe
    if (-not $Force -and -not $Changed.ContainsKey('fork') -and $haveExe -and ((-not $built) -or $built -eq $head)) {
        if (-not $built -and -not $WhatIf) { Set-StateValues 'tools' @{ head = $head; adopted = $true } }
        return 'up to date'
    }
    if ($WhatIf) { Plan 'run tools\build_ps2recomp_tools.cmd'; $Changed['tools'] = $true; return 'would run' }
    if (-not (Test-Path -LiteralPath (Join-Path $Tree 'CMakeLists.txt'))) { throw "$Tree is not a PS2Recomp tree" }
    $env:TEKKEN4_SRC = $Tree
    $code = Invoke-Logged -File (Join-Path $PSScriptRoot 'build_ps2recomp_tools.cmd') -Label 'Building PS2Recomp tools'
    if ($code -ne 0) { throw "tools\build_ps2recomp_tools.cmd failed (exit $code)" }
    if (-not (Test-Path -LiteralPath $RecompExe)) { throw "build finished but $RecompExe is missing" }
    Set-StateValues 'tools' @{ head = $head; adopted = $false }
    $Changed['tools'] = $true
    'built'
}

# ================================================================ recompile
Step 'recomp' 'ps2_recomp.exe config\ghidra_export.toml -> generated\' {
    $cfg = Files (Join-Path $Root 'config') '*' | Where-Object { $_ -match '\.(toml|csv)$' }
    $fp = Sha1Text ((Get-ContentFingerprint $cfg) + '|' + $ExpectedElfSha1 + '|' + (Get-StatFingerprint @($RecompExe)))
    $haveOut = Test-Path -LiteralPath (Join-Path $Root 'generated\register_functions.cpp')
    if (-not $Force -and -not $Changed.ContainsKey('tools') -and -not $Changed.ContainsKey('extract') -and $haveOut -and (Get-StateValue 'recomp' 'fingerprint') -eq $fp) { return 'up to date' }
    if ($WhatIf) { Plan 'run ps2_recomp.exe config\ghidra_export.toml (writes generated\)'; $Changed['recomp'] = $true; return 'would run' }
    if (-not (Test-Path -LiteralPath $RecompExe)) { throw "ps2_recomp.exe missing: $RecompExe" }
    if (-not (Test-Path -LiteralPath (Join-Path $GameDisc 'SLUS_203.28'))) { throw 'game\disc\SLUS_203.28 missing (extract step)' }
    $code = Invoke-Logged -File $RecompExe -ArgList @('config\ghidra_export.toml') -Label 'Recompiling the game (ps2_recomp)'
    if ($code -ne 0) { throw "ps2_recomp.exe exited with code $code" }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'generated\register_functions.cpp'))) { throw 'ps2_recomp finished but generated\register_functions.cpp is missing' }
    Set-StateValues 'recomp' @{ fingerprint = $fp }
    $Changed['recomp'] = $true
    'recompiled'
}

# ================================================================ stage
Step 'stage' 'tools\stage_generated.cmd' {
    $gen = (Files (Join-Path $Root 'generated') '*.cpp') + (Files (Join-Path $Root 'generated') '*.h')
    $fp = Sha1Text ((Get-StatFingerprint $gen) + '|' + (Get-StatFingerprint (Files (Join-Path $Root 'runtime') '*.cpp' -Recurse)) + '|' + (Get-TreeHead))
    if (-not $Force -and -not $Changed.ContainsKey('recomp') -and -not $Changed.ContainsKey('fork') -and (Get-StateValue 'stage' 'fingerprint') -eq $fp -and (Test-Path -LiteralPath (Join-Path $Tree 'ps2xRuntime\src\runner\register_functions.cpp'))) { return 'up to date' }
    if ($WhatIf) { Plan 'run tools\stage_generated.cmd'; $Changed['stage'] = $true; return 'would run' }
    $env:TEKKEN4_SRC = $Tree
    $code = Invoke-Logged -File (Join-Path $PSScriptRoot 'stage_generated.cmd') -Label 'Staging generated code'
    if ($code -ne 0) { throw "tools\stage_generated.cmd failed (exit $code)" }
    Set-StateValues 'stage' @{ fingerprint = $fp }
    $Changed['stage'] = $true
    'staged'
}

# ================================================================ runtime
Step 'runtime' "tools\build_runtime.cmd -> $RunnerExe" {
    $vu1 = @(Files (Join-Path $Root 'game\vu1\micro') '*.bin')   # @(): an empty result is $null and .Count then throws under StrictMode
    $fp = Sha1Text ((Get-StateValue 'stage' 'fingerprint') + '|' + (Get-StatFingerprint (Files (Join-Path $Root 'patches') '*.patch')) + '|' +
                    (Get-StatFingerprint $vu1) + '|' + (Get-StatFingerprint (Files (Join-Path $Root 'runtime') '*.cpp' -Recurse)) + '|' + (Get-TreeHead) + '|' + $BuildDirName)
    if (-not $Force -and -not $Changed.ContainsKey('stage') -and (Test-Path -LiteralPath $RunnerExe) -and (Get-StateValue 'runtime' 'fingerprint') -eq $fp) { return 'up to date' }
    if ($WhatIf) { Plan 'run tools\build_runtime.cmd (cmake + ninja, 10-40 minutes the first time)'; $Changed['runtime'] = $true; return 'would run' }
    if ($vu1.Count -eq 0) {
        # The VU1 micro memory image (native VU1 = full speed) is assembled from the player's own ELF.
        $py = $Script:Tools['py']
        if (-not $py) { $c = Get-Command python, py -ErrorAction SilentlyContinue | Select-Object -First 1; $py = @{ Exe = $c.Source; Pre = @() }; if ($c.Name -ieq 'py.exe') { $py.Pre = @('-3') } }
        $a = @($py.Pre) + @('-I', (Join-Path $PSScriptRoot 'vu1_micro_from_elf.py'), (Join-Path $Root 'game\disc\SLUS_203.28'), (Join-Path $Root 'game\vu1\micro'))
        $code = Invoke-Logged -File $py.Exe -ArgList $a -Label 'VU1 micro image from the ELF'
        if ($code -ne 0) {
            Say '    NOTE: the VU1 micro image could not be built: the runtime gets the VU1 interpreter only (about 12 fps in a fight).'
        }
    }
    $env:TEKKEN4_SRC = $Tree
    $env:TEKKEN4_BUILD_DIR = $BuildDirName
    Say '    this is the long step (several hundred C++ files); progress is in the log'
    $code = Invoke-Logged -File (Join-Path $PSScriptRoot 'build_runtime.cmd') -Label 'Building the game runtime (ninja)'
    if ($code -ne 0) { throw "tools\build_runtime.cmd failed (exit $code)" }
    if (-not (Test-Path -LiteralPath $RunnerExe)) { throw "build finished but $RunnerExe is missing" }
    Set-StateValues 'runtime' @{ fingerprint = $fp; exe = $RunnerExe }
    $Changed['runtime'] = $true
    'built'
}

# ================================================================ summary
$PipelineClock.Stop()
Say ''
Say '--- timings ---'
foreach ($t in $Timings) { Say "  $t" }
Say ('  total    {0:N1}s' -f $PipelineClock.Elapsed.TotalSeconds)
Say ''
if ($WhatIf) {
    Say 'Dry run only: nothing was changed (steps marked "would run" are what a real run does).'
} elseif ($Steps -contains 'runtime') {
    Say 'Ready. Start the game with:'
    Say ''
    $inRoot = $IsoInfo -and ($IsoInfo.DirectoryName.TrimEnd('\') -ieq $Root)
    $rootIso = @(Get-ChildItem -LiteralPath $Root -Filter '*.iso' -File -ErrorAction SilentlyContinue).Count -gt 0
    if ($IsoInfo -and -not $inRoot -and -not $rootIso) {
        Say "    set TEKKEN4_ISO=$($IsoInfo.FullName)"
        Say "    $(Join-Path $Root 'tools\run_game.cmd')"
        Say ''
        Say '(the runtime reads the game data and sound from the ISO: TEKKEN4_ISO points it at yours, or copy the ISO into the repo root)'
    } else {
        Say "    $(Join-Path $Root 'tools\run_game.cmd')"
    }
    Say ''
    Say 'Close the game window to stop it; the console output goes to logs\run.log.'
}
Log '=== build_game finished'
$LogWriter.Dispose()
exit 0
