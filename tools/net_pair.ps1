# Two Tekken 4 netplay instances on this PC (rollback phase 3, docs/ROLLBACK_PHASE3.md): a host (P1) and a joiner (P2)
# over loopback UDP, each with its own run dir (memory cards mc0/mc1 live there), window title and environment,
# and the in-process network simulator on both sides' sends (one-way = RTT/2). The pair holds logs\run.lock as ONE run.
#
#   powershell -File tools\net_pair.ps1 -Name n150 -Rtt 150 -Jitter 5 -Loss 3 -End 9000 -Env "TEKKEN4_SOUND=1;..."
#
# -Env: "K=V;K=V" for both; -HostEnv / -JoinEnv for one side. -End: logical frame both stop at (TEKKEN4_NET_END);
# the script closes both once both logs say NETEND (or -Seconds passed). -Shots: logical frames for net_shot_f*.bmp.
# Output: logs\net\<Name>\{host,join}\ (rb_frames.log, net.log, stdout/stderr, shots) and a summary on stdout.
param([string]$Name = "", [int]$Rtt = 0, [double]$Jitter = 0, [double]$Loss = 0, [int]$End = 9000, [int]$Seconds = 1800,
      [string]$Env = "", [string]$HostEnv = "", [string]$JoinEnv = "", [string]$Shots = "", [int]$Port = 7400,
      [string]$Src = "D:\tekken4-fork-net", [string]$BuildDir = "net", [switch]$NoLock)
$root = Split-Path -Parent $PSScriptRoot
if (-not $Name) { $Name = "pair_" + (Get-Date -Format "yyyyMMdd_HHmmss") }
$base = Join-Path $root "logs\net\$Name"
$exe = Join-Path $Src "out\$BuildDir\ps2xRuntime\ps2EntryRunner.exe"
$elf = Join-Path $root "game\disc\SLUS_203.28"
if (-not (Test-Path $exe)) { throw "no build at $exe" }
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NetPairWin {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowText(IntPtr h, string s);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool repaint);
}
"@
function Set-EnvList([string]$list) {
    foreach ($kv in ($list -split ';')) { if ($kv) { $k, $v = $kv -split '=', 2; Set-Item -Path "env:$k" -Value $v } }
}
function Clear-NetEnv {
    Get-ChildItem env: | Where-Object { $_.Name -match '^(TEKKEN4_|PS2X_)' } | ForEach-Object { Remove-Item "env:$($_.Name)" }
}
$buildId = ""
$stamp = Join-Path (Split-Path $exe) "t4net_build.txt"
if (Test-Path $stamp) { $buildId = (Get-Content $stamp -TotalCount 1).Trim().Split(' ')[0] }
$oneWay = [double]$Rtt / 2.0
$sim = if ($Rtt -gt 0 -or $Loss -gt 0 -or $Jitter -gt 0) { "lat=$oneWay,jitter=$Jitter,loss=$Loss" } else { "" }
$sides = @(
    @{ side = "host"; net = "host:$Port"; extra = $HostEnv; seed = 11 },
    @{ side = "join"; net = "join:127.0.0.1:$Port"; extra = $JoinEnv; seed = 22 }
)
. (Join-Path $PSScriptRoot "run_lock.ps1")
if (-not $NoLock) { Enter-RunLock $root "net_pair $Name (host + join)" }
$saved = @(Get-ChildItem env: | Where-Object { $_.Name -match '^(TEKKEN4_|PS2X_)' } | ForEach-Object { @{ n = $_.Name; v = $_.Value } })
$procs = @()
$t0 = Get-Date
try {
    foreach ($s in $sides) {
        $dir = Join-Path $base $s.side
        New-Item -ItemType Directory -Force $dir | Out-Null
        Clear-NetEnv
        $env:TEKKEN4_SRC = $Src; $env:TEKKEN4_BUILD_DIR = $BuildDir
        $env:PS2X_GS_BACKEND = "gl"; $env:PS2X_GS_THREADS = "auto"
        $env:TEKKEN4_SOUND = "0"
        Set-EnvList $Env
        Set-EnvList $s.extra
        $env:TEKKEN4_NET = $s.net
        $env:TEKKEN4_NET_END = "$End"
        if ($sim) { $env:TEKKEN4_NET_SIM = "$sim,seed=$($s.seed)" }
        if ($Shots) { $env:TEKKEN4_NET_SHOTS = $Shots }
        if ($buildId -and -not $env:TEKKEN4_NET_BUILD) { $env:TEKKEN4_NET_BUILD = $buildId }
        @("started  " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "side     $($s.side)", "rtt      $Rtt jitter $Jitter loss $Loss",
          "exe      $exe") + @(Get-ChildItem env: | Where-Object { $_.Name -match '^(TEKKEN4_|PS2X_)' } | Sort-Object Name |
          ForEach-Object { "env      $($_.Name)=$($_.Value)" }) | Set-Content -Encoding utf8 (Join-Path $dir "params.txt")
        $p = Start-Process -FilePath $exe -ArgumentList "`"$elf`"" -WorkingDirectory $dir `
            -RedirectStandardOutput "$dir\stdout.txt" -RedirectStandardError "$dir\stderr.txt" -PassThru
        $procs += @{ side = $s.side; p = $p; dir = $dir; titled = $false }
        Start-Sleep -Milliseconds 500
    }
    Clear-NetEnv
    foreach ($e in $saved) { Set-Item -Path "env:$($e.n)" -Value $e.v }
    $ended = @{}
    while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
        Start-Sleep -Seconds 2
        $i = 0
        foreach ($x in $procs) {
            $x.p.Refresh()
            if (-not $x.titled -and $x.p.MainWindowHandle -ne [IntPtr]::Zero) {
                [void][NetPairWin]::SetWindowText($x.p.MainWindowHandle, "TEKKEN 4 - Claude: $Name $($x.side) ($(if ($x.side -eq 'host') {'P1'} else {'P2'}))")
                [void][NetPairWin]::MoveWindow($x.p.MainWindowHandle, 20 + 660 * $i, 40, 640, 520, $true)
                # F1 hides the runtime's debug panel (as tools\run_capture.ps1)
                [void][NetPairWin]::PostMessage($x.p.MainWindowHandle, 0x0100, [IntPtr]0x70, [IntPtr](1 -bor (0x3B -shl 16)))
                Start-Sleep -Milliseconds 100
                [void][NetPairWin]::PostMessage($x.p.MainWindowHandle, 0x0101, [IntPtr]0x70, [IntPtr]([int64]1 -bor (0x3B -shl 16) -bor [int64]0xC0000000))
                $x.titled = $true
            }
            $log = Join-Path $x.dir "rb_frames.log"
            if (-not $ended[$x.side] -and (Test-Path $log) -and (Select-String -Path $log -Pattern '^NETEND' -Quiet)) {
                $ended[$x.side] = ((Get-Date) - $t0).TotalSeconds
                "{0} reached NETEND after {1:N0} s" -f $x.side, $ended[$x.side]
            }
            $i++
        }
        if ($ended.Count -eq 2) { break }
        if (@($procs | Where-Object { $_.p.HasExited }).Count -gt 0) { "a game exited early"; break }
    }
} finally {
    foreach ($x in $procs) {
        if (-not $x.p.HasExited) {
            $null = $x.p.CloseMainWindow()
            if (-not $x.p.WaitForExit(8000)) { $x.p.Kill(); $null = $x.p.WaitForExit(5000) }
        }
    }
    Clear-NetEnv
    foreach ($e in $saved) { Set-Item -Path "env:$($e.n)" -Value $e.v }
    if (-not $NoLock) { Exit-RunLock $root }
}
"ran {0:N0} s, output in $base" -f ((Get-Date) - $t0).TotalSeconds
foreach ($x in $procs) {
    $log = Join-Path $x.dir "rb_frames.log"
    if (-not (Test-Path $log)) { "$($x.side): no rb_frames.log"; continue }
    $sum = Select-String -Path $log -Pattern '^NETSUMMARY' | Select-Object -Last 1
    "$($x.side): $($sum.Line)"
    $d = @(Select-String -Path $log -Pattern '^NETDESYNC').Count
    "$($x.side): NETDESYNC lines $d"
}
