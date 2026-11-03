# Two Tekken 4 netplay games on this PC matched through a local lobby (docs/LOBBY.md "Local test"): a lobby server on
# 127.0.0.1 (lobby/run.py server, its own ports, in-memory DB) and two guest clients (lobby/run.py cli --quick), each
# starting the real T4 netplay build from its match_start with the TEKKEN4_NET* environment the lobby produced.
# A heavy run: holds logs\run.lock for the pair, and checks an optional explicit heavy lock.
#
#   powershell -ExecutionPolicy Bypass -File tools\net_lobby_pair.ps1 -Name lp1 -End 6000 -Env "TEKKEN4_RAND_SEED=1;..."
#   (-Relay: force the lobby's relay; -Sim "lat=25,jitter=5,loss=3": the netplay simulator on both games' sends)
param([string]$Name = "", [int]$End = 6000, [string]$Env = "", [switch]$Relay, [string]$Sim = "",
      [string]$GameDir = "", [int]$Seconds = 1800,
      [string]$HeavyLock = $env:T4_HEAVY_LOCK)
$root = Split-Path -Parent $PSScriptRoot
if ($HeavyLock -and (Test-Path -LiteralPath $HeavyLock)) { throw "$HeavyLock exists: no game runs now (try again later)" }
if (-not $Name) { $Name = "lobby_" + (Get-Date -Format "yyyyMMdd_HHmmss") }
$src = if ($env:TEKKEN4_SRC) { $env:TEKKEN4_SRC } else { Join-Path (Split-Path -Parent $root) "tekken4-fork-net" }
$build = if ($env:TEKKEN4_BUILD_DIR) { $env:TEKKEN4_BUILD_DIR } else { "net" }
if (-not $GameDir) { $GameDir = Join-Path $src "out\$build\ps2xRuntime" }
$e = @("TEKKEN4_SRC=$src", "TEKKEN4_BUILD_DIR=$build", "PS2X_GS_THREADS=auto")
if ($Env) { $e += $Env }
if ($Sim) { $e += "TEKKEN4_NET_SIM=$Sim" }
$envList = ($e -join ';')
. (Join-Path $PSScriptRoot "run_lock.ps1")
Enter-RunLock $root "net_lobby_pair $Name (lobby + host + join)"
try {
    $a = @("-I", (Join-Path $root "lobby\tools\t4_lobby_pair.py"), "--name", $Name, "--end", "$End", "--env", $envList,
           "--game-dir", $GameDir, "--seconds", "$Seconds")
    if ($Relay) { $a += "--relay" }
    & python @a
} finally {
    Exit-RunLock $root
}
