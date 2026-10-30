# Two Tekken 4 netplay games on this PC matched through a local lobby (docs/LOBBY.md "Local test"): a lobby server on
# 127.0.0.1 (lobby/run.py server, its own ports, in-memory DB) and two guest clients (lobby/run.py cli --quick), each
# starting the real T4 netplay build from its match_start with the TEKKEN4_NET* environment the lobby produced.
# A heavy run: holds logs\run.lock for the pair, and refuses to start while T5DR's build lock exists.
#
#   powershell -ExecutionPolicy Bypass -File tools\net_lobby_pair.ps1 -Name lp1 -End 6000 -Env "TEKKEN4_RAND_SEED=1;..."
#   (-Relay: force the lobby's relay; -Sim "lat=25,jitter=5,loss=3": the netplay simulator on both games' sends)
param([string]$Name = "", [int]$End = 6000, [string]$Env = "", [switch]$Relay, [string]$Sim = "",
      [string]$GameDir = "D:\tekken4-fork-net\out\net\ps2xRuntime", [int]$Seconds = 1800,
      [string]$HeavyLock = "C:\T5DROnline\build\int115\HEAVY.lock")
$root = Split-Path -Parent $PSScriptRoot
if (Test-Path $HeavyLock) { throw "$HeavyLock exists: no game runs now (try again later)" }
if (-not $Name) { $Name = "lobby_" + (Get-Date -Format "yyyyMMdd_HHmmss") }
$e = @("TEKKEN4_SRC=D:\tekken4-fork-net", "TEKKEN4_BUILD_DIR=net", "PS2X_GS_THREADS=auto")
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
