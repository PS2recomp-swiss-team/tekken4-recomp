# One Tekken 4 netplay instance for a human test.
#   host (P1): powershell -ExecutionPolicy Bypass -File tools\net_play.ps1 -Host -Port 7400
#   join (P2): powershell -ExecutionPolicy Bypass -File tools\net_play.ps1 -Join <HOST-IP> -Port 7400
# Preflight compares the two builds and checks UDP before launching the game.
# Each default run has its own logs/net directory; cards stay local and are never collected.
param([Alias("Host")][switch]$AsHost, [string]$Join = "", [ValidateRange(1,65535)][int]$Port = 7400,
      [int]$Pad = 0, [string]$Delay = "auto", [int]$Sound = 1, [string]$Sim = "", [string]$RunDir = "",
      [string]$Src = $env:TEKKEN4_SRC, [string]$BuildDir = $env:TEKKEN4_BUILD_DIR,
      [Alias("IsoPath")][string]$Iso = $env:TEKKEN4_ISO, [switch]$NoDiagnostics,
      [switch]$SkipPreflight, [ValidateRange(5,600)][int]$PreflightTimeoutSeconds = 90)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($AsHost -and $Join) { throw 'Give either -Host or -Join <host>, not both.' }
$side = if ($AsHost) { 'host' } elseif ($Join) { 'join' } else { throw 'Give -Host or -Join <host>.' }

# Keep the old fork-net/net setup when present; otherwise use build_game.ps1's output.
# Explicit parameters and environment settings still take precedence.
if (-not $Src) {
    $candidates = @(
        (Join-Path (Split-Path -Parent $root) 'tekken4-fork-net'),
        (Join-Path $root 'deps\ps2recomp'),
        (Join-Path (Split-Path -Parent $root) 'tekken4-fork-ps2recomp'))
    foreach ($candidate in $candidates) {
        $candidateBuild = if ($BuildDir) { $BuildDir } elseif ($candidate -eq $candidates[0]) { 'net' } else { 'runtime' }
        if (Test-Path -LiteralPath (Join-Path $candidate "out\$candidateBuild\ps2xRuntime\ps2EntryRunner.exe") -PathType Leaf) {
            $Src = $candidate
            if (-not $BuildDir) { $BuildDir = $candidateBuild }
            break
        }
    }
    if (-not $Src) {
        $Src = if (Test-Path -LiteralPath (Join-Path $root 'deps\ps2recomp\.t4-vendored.json')) {
            Join-Path $root 'deps\ps2recomp'
        } else { Join-Path (Split-Path -Parent $root) 'tekken4-fork-ps2recomp' }
    }
}
if (-not $BuildDir) {
    $BuildDir = if (Test-Path -LiteralPath (Join-Path $Src 'out\net\ps2xRuntime\ps2EntryRunner.exe') -PathType Leaf) { 'net' } else { 'runtime' }
}
$Src = [IO.Path]::GetFullPath($Src)
$exeDir = Join-Path $Src "out\$BuildDir\ps2xRuntime"
$exe = Join-Path $exeDir 'ps2EntryRunner.exe'
$elf = Join-Path $root 'game\disc\SLUS_203.28'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "Runner missing: $exe. Build locally from your own ISO with tools\build_game.ps1; check -Src and -BuildDir."
}
if (-not (Test-Path -LiteralPath $elf -PathType Leaf)) {
    throw 'Game ELF missing. Run tools\build_game.ps1 -Iso <your ISO> locally first.'
}
if (-not $RunDir) { $RunDir = Join-Path $root ("logs\net\play_{0}_{1}" -f $side, (Get-Date -Format 'yyyyMMdd_HHmmss_fff')) }
$RunDir = [IO.Path]::GetFullPath($RunDir)
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

# The runtime runs in RunDir, so pass the ISO explicitly rather than relying on its working directory.
if (-not $Iso) {
    $rootIsos = @(Get-ChildItem -LiteralPath $root -Filter '*.iso' -File)
    if ($rootIsos.Count -eq 1) { $Iso = $rootIsos[0].FullName }
    elseif ($rootIsos.Count -gt 1) { throw 'More than one ISO in the project folder. Choose yours with -Iso <path>.' }
}
if (-not $Iso) {
    $statePath = Join-Path $root 'logs\build_game_state.json'
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        try { $Iso = [string](Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).verify.iso } catch { }
    }
}
if ($Iso) { $Iso = [IO.Path]::GetFullPath($Iso); $env:TEKKEN4_ISO = $Iso }

. (Join-Path $PSScriptRoot 'net_preflight.ps1')
if ($Join) { $Join = Resolve-T4NetPeer -Peer $Join }
$stampJson = Join-Path $exeDir 't4net_build.json'
$identity = $null
try {
    if (-not $Iso) { throw 'ISO missing. Pass -Iso <your US SLUS-20328 v1.00 ISO>, set TEKKEN4_ISO, or use the ISO saved by build_game.ps1.' }
    $identity = New-T4NetIdentity -BuildStampJson $stampJson -IsoPath $Iso
    $actualElf = (Get-FileHash -LiteralPath $elf -Algorithm SHA1).Hash.ToLowerInvariant()
    if ($actualElf -ne $identity.elf_sha1) {
        throw 'The extracted ELF differs from the build identity. Rebuild locally from the intended US v1.00 ISO, then regenerate the build identity.'
    }
    $identity | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $RunDir 'build_identity.json') -Encoding UTF8
    $env:TEKKEN4_NET_BUILD = $identity.build_id
    Write-Host "Build id: $($identity.build_id)"
    Write-Host "Compiler / MSVC version: $($identity.compiler)"
    Write-Host "ISO SHA-256: $($identity.iso_sha256)"
} catch {
    if (-not $SkipPreflight) {
        Write-Host 'Build identity missing/stale? After the local runtime build, regenerate it with:'
        Write-Host "  python -I tools\t4_buildid.py --src `"$Src`" --out `"$exeDir`""
        throw
    }
    Write-Warning "Identity could not be checked: $($_.Exception.Message)"
    # Explicit legacy opt-out still supports the original text-only stamp.
    $stamp = Join-Path $exeDir 't4net_build.txt'
    $env:TEKKEN4_NET_BUILD = ''
    if (Test-Path -LiteralPath $stamp -PathType Leaf) {
        $env:TEKKEN4_NET_BUILD = (Get-Content -LiteralPath $stamp -TotalCount 1).Trim().Split(' ')[0]
    }
}

# These diagnostics add host timing/logging only; they never alter the wire or simulation state.
# A pre-existing TEKKEN4_NET_DIAG=0 or -NoDiagnostics disables them for a comparison run.
if ($NoDiagnostics) { $env:TEKKEN4_NET_DIAG = '0' }
elseif (-not $env:TEKKEN4_NET_DIAG) { $env:TEKKEN4_NET_DIAG = '1' }
$env:TEKKEN4_NET = if ($AsHost) { "host:$Port" } else { "join:${Join}:$Port" }
$env:TEKKEN4_NET_DELAY = $Delay
$env:TEKKEN4_NET_PAD = "$Pad"
$env:TEKKEN4_SOUND = "$Sound"
if ($Sim) { $env:TEKKEN4_NET_SIM = $Sim }
if (-not $env:PS2X_GS_BACKEND) { $env:PS2X_GS_BACKEND = 'gl' }
$runInfo = [ordered]@{
    started_utc = (Get-Date).ToUniversalTime().ToString('o'); side = $side; port = $Port
    pad = $Pad; delay = $Delay; sound = $Sound; diagnostics = ($env:TEKKEN4_NET_DIAG -eq '1'); exit_code = $null
}
$runInfo | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $RunDir 'run_info.json') -Encoding UTF8
Write-Host "${side}: build $env:TEKKEN4_NET_BUILD, diagnostics=$env:TEKKEN4_NET_DIAG, logs: $RunDir"
if ($SkipPreflight) {
    Write-Warning 'Preflight skipped explicitly: build/compiler/ISO comparison and UDP reachability have NOT been verified.'
} else {
    Write-Host 'Both PCs must run this command now. Waiting for matching build/compiler/ISO and a two-way UDP reply.'
    Write-Host 'Firewall: allow this PowerShell UDP check AND ps2EntryRunner.exe, or configure the UDP port rule yourself.'
    Invoke-T4NetPreflight -AsHost ([bool]$AsHost) -Peer $Join -Port $Port -Identity $identity `
        -TimeoutSeconds $PreflightTimeoutSeconds -OutputPath (Join-Path $RunDir 'preflight.json')
}
foreach ($name in @('TEKKEN4_NET_END','TEKKEN4_NET_SHOTS','TEKKEN4_NET_DESYNC_DUMP','TEKKEN4_NET_SIM')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ($value) { Write-Warning ("Inherited {0}={1}. For an ordinary Sunday test, use a fresh shell without harness settings." -f $name, $value) }
}
Write-Host 'Starting the game. Close its window when done; then collect the logs on both PCs.'
$p = Start-Process -FilePath $exe -ArgumentList "`"$elf`"" -WorkingDirectory $RunDir `
    -RedirectStandardOutput (Join-Path $RunDir 'stdout.txt') -RedirectStandardError (Join-Path $RunDir 'stderr.txt') -PassThru
$p.WaitForExit()
$runInfo.exit_code = $p.ExitCode
$runInfo | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $RunDir 'run_info.json') -Encoding UTF8
$rbLog = Join-Path $RunDir 'rb_frames.log'
if (Test-Path -LiteralPath $rbLog) {
    Select-String -LiteralPath $rbLog -Pattern '^NETSUMMARY|^NETDESYNC' | Select-Object -Last 3 | ForEach-Object { Write-Host $_.Line }
} else { Write-Warning 'No rb_frames.log was written. Check net.log and the startup/error output.' }
Write-Host "Game exit code: $($p.ExitCode). Logs: $RunDir"
if ($p.ExitCode -ne 0) { exit $p.ExitCode }
