# One Tekken 4 netplay instance for a human test (rollback phase 3, docs/ROLLBACK_PHASE3.md "Playing by hand").
#   host (P1):  powershell -ExecutionPolicy Bypass -File tools\net_play.ps1 -Host -Port 7400
#   join (P2):  powershell -ExecutionPolicy Bypass -File tools\net_play.ps1 -Join 192.168.1.20 -Port 7400
# Each instance gets its own run dir (logs\net\play_<side>: memory cards mc0/mc1, rb_frames.log, net.log); two on one
# PC need different -Pad (keyboard -1 / gamepad 1) so each player has a device. Not a timed run: no run lock.
param([Alias("Host")][switch]$AsHost, [string]$Join = "", [int]$Port = 7400, [int]$Pad = 0, [string]$Delay = "auto",
      [int]$Sound = 1, [string]$Sim = "", [string]$RunDir = "", [string]$Src = "D:\tekken4-fork-net", [string]$BuildDir = "net")
$root = Split-Path -Parent $PSScriptRoot
$side = if ($AsHost) { "host" } elseif ($Join) { "join" } else { throw "give -Host or -Join <ip>" }
if (-not $RunDir) { $RunDir = Join-Path $root "logs\net\play_$side" }
New-Item -ItemType Directory -Force $RunDir | Out-Null
$exeDir = Join-Path $Src "out\$BuildDir\ps2xRuntime"
$env:TEKKEN4_NET = if ($AsHost) { "host:$Port" } else { "join:${Join}:$Port" }
$env:TEKKEN4_NET_DELAY = $Delay
$env:TEKKEN4_NET_PAD = "$Pad"
$env:TEKKEN4_SOUND = "$Sound"
if ($Sim) { $env:TEKKEN4_NET_SIM = $Sim }
$stamp = Join-Path $exeDir "t4net_build.txt"
if (Test-Path $stamp) { $env:TEKKEN4_NET_BUILD = (Get-Content $stamp -TotalCount 1).Trim().Split(' ')[0] }
if (-not $env:PS2X_GS_BACKEND) { $env:PS2X_GS_BACKEND = "gl" }
"${side}: TEKKEN4_NET=$env:TEKKEN4_NET build $env:TEKKEN4_NET_BUILD, run dir $RunDir"
$p = Start-Process -FilePath (Join-Path $exeDir "ps2EntryRunner.exe") -ArgumentList "`"$(Join-Path $root 'game\disc\SLUS_203.28')`"" `
    -WorkingDirectory $RunDir -RedirectStandardOutput "$RunDir\stdout.txt" -RedirectStandardError "$RunDir\stderr.txt" -PassThru
$p.WaitForExit()
Select-String -Path (Join-Path $RunDir "rb_frames.log") -Pattern '^NETSUMMARY|^NETDESYNC' | Select-Object -Last 3 | ForEach-Object { $_.Line }
