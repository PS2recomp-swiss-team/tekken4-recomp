param(
    [string]$Task = "input-lag",
    [string]$RunDir = "",
    [int]$Presses = 24,
    [ValidateSet("legacy", "fast")][string]$Mode = "fast",
    [ValidateSet("", "tick", "paced")][string]$Present = "",
    [string]$Exe = "",
    [ValidateSet("keyboard", "pad", "both")][string]$Source = "keyboard",
    [ValidateSet("direct", "raylib")][string]$Backend = "direct",
    [ValidateSet("dpad", "stick")][string]$What = "dpad",
    [string]$Env = ""
)
# pad_lag.ps1 = input_lag.ps1 plus -Source pad (docs\INPUT.md): the measured presses come from a scripted
# XInput pad inside the game (TEKKEN4_PAD_TEST, fake XInputGetState) instead of posted keys; t0 = t1 = the
# moment the fake pad changes. -Backend raylib = the old gamepad path (the pad becomes visible only when the
# window thread polls raylib, as GLFW does), direct = the new one. -Env "A=1;B=2" adds environment variables.
#   powershell -File tools\pad_lag.ps1 -Exe <runner> -Source pad -Backend raylib -RunDir logs\input\pad_raylib1
#   powershell -File tools\pad_lag.ps1 -Exe <runner> -Source keyboard -RunDir logs\input\kbd1
# Measure host input lag on the mode-select cursor. Reaches the menu with the
# usual PAL60 keys, then posts N (>=20) Down/Up taps at random sub-frame offsets.
# t0 is QueryPerformanceCounter immediately before PostMessage. The runtime
# (TEKKEN4_INPUT_LAG=1) logs t1..t5 as raw QPC on stderr.
#   powershell -File tools\input_lag.ps1 -Task input-lag -Mode legacy -RunDir logs\grok\input-lag-before
#   powershell -File tools\input_lag.ps1 -Task input-lag -Mode fast -Present paced -RunDir logs\grok\input-lag-after
if ($Presses -lt 20) { $Presses = 20 }
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $RunDir) { $RunDir = Join-Path $root ("logs\grok\input-lag-" + $Mode + "-" + (Get-Date -Format "HHmmss")) }
New-Item -ItemType Directory -Force $RunDir | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class InputLagWin {
    [DllImport("kernel32.dll")] public static extern bool QueryPerformanceCounter(out long c);
    [DllImport("kernel32.dll")] public static extern bool QueryPerformanceFrequency(out long f);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
}
"@

$vk = @{ Up = 0x57; Down = 0x53; Left = 0x41; Right = 0x44; Start = 0x0D; Cross = 0x58; Circle = 0x43; Square = 0x5A; Triangle = 0x56; F1 = 0x70 }
$scan = @{ Up = 0x11; Down = 0x1F; Left = 0x1E; Right = 0x20; Start = 0x1C; Cross = 0x2D; Circle = 0x2E; Square = 0x2C; Triangle = 0x2F; F1 = 0x3B }
$freq = [int64]0
[void][InputLagWin]::QueryPerformanceFrequency([ref]$freq)
$script:taps = New-Object System.Collections.Generic.List[object]

function Wait-Until([datetime]$when) {
    while ((Get-Date) -lt $when.AddMilliseconds(-2)) {
        $left = ($when - (Get-Date)).TotalMilliseconds
        if ($left -gt 20) { Start-Sleep -Milliseconds 10 } else { Start-Sleep -Milliseconds 1 }
    }
    while ((Get-Date) -lt $when) { }
}

function Send-Tap([IntPtr]$h, [string]$name, [int]$holdMs, [bool]$meas) {
    $vkCode = [int]$vk[$name]
    $scanCode = [int]$scan[$name]
    $flags = [int64]1 -bor ([int64]$scanCode -shl 16)
    $c = [int64]0
    [void][InputLagWin]::QueryPerformanceCounter([ref]$c)
    [void][InputLagWin]::PostMessage($h, 0x0100, [IntPtr]$vkCode, [IntPtr]$flags)
    $script:taps.Add([pscustomobject]@{ meas = $meas; name = $name; vk = $vkCode; qpc = [int64]$c })
    Start-Sleep -Milliseconds $holdMs
    [void][InputLagWin]::PostMessage($h, 0x0101, [IntPtr]$vkCode, [IntPtr]($flags -bor [int64]0xC0000000))
}

$env:TEKKEN4_INPUT_LAG = "1"
$env:TEKKEN4_INPUT_LEGACY = $(if ($Mode -eq "legacy") { "1" } else { "0" })
if ($Present) { $env:TEKKEN4_INPUT_PRESENT = $Present } else { $env:TEKKEN4_INPUT_PRESENT = "paced" }
if (-not $env:PS2X_GS_BACKEND) { $env:PS2X_GS_BACKEND = "gl" }
if (-not $env:PS2X_GS_THREADS) { $env:PS2X_GS_THREADS = "auto" }
$env:TEKKEN4_FRAME_SHOTS = "38"
$env:TEKKEN4_PAD_BACKEND = $Backend
$env:TEKKEN4_PAD_STATS = "1"
# both: keys at 40 + 0.8 i s, pad presses 0.4 s later, in one run (same guest/present phase for both).
$step = $(if ($Source -eq "both") { 0.80 } else { 0.40 })
$padStart = $(if ($Source -eq "both") { 40.4 } else { 40.0 })
if ($Source -ne "keyboard") { $env:TEKKEN4_PAD_TEST = "start=$padStart,count=$Presses,period=$([int]($step * 1000)),hold=70,what=$What" } else { $env:TEKKEN4_PAD_TEST = "" }
foreach ($kv in ($Env -split ';')) { if ($kv -match '^([^=]+)=(.*)$') { Set-Item -Path ("env:" + $Matches[1]) -Value $Matches[2] } }

if (-not $Exe) {
    $env:TEKKEN4_BUILD_DIR = "grok-$Task"
    $taskTree = Join-Path $root "external\wt-$Task"
    if (Test-Path (Join-Path $taskTree "ps2xRuntime")) { $env:TEKKEN4_SRC = $taskTree }
    $srcTree = $env:TEKKEN4_SRC
    $Exe = Join-Path $srcTree "out\$($env:TEKKEN4_BUILD_DIR)\ps2xRuntime\ps2EntryRunner.exe"
}
$elf = Join-Path $root "game\disc\SLUS_203.28"
if (-not (Test-Path $Exe)) { throw "runner not built: $Exe" }

$events = @(
    [pscustomobject]@{ t = 0.6; name = "F1"; meas = $false; hold = 80 },
    [pscustomobject]@{ t = 10.0; name = "Down"; meas = $false; hold = 180 },
    [pscustomobject]@{ t = 12.0; name = "Cross"; meas = $false; hold = 180 },
    [pscustomobject]@{ t = 15.0; name = "Left"; meas = $false; hold = 180 },
    [pscustomobject]@{ t = 16.5; name = "Cross"; meas = $false; hold = 180 },
    [pscustomobject]@{ t = 30.0; name = "Start"; meas = $false; hold = 180 },
    [pscustomobject]@{ t = 36.0; name = "Cross"; meas = $false; hold = 180 }
)
$rng = New-Object System.Random
for ($i = 0; ($Source -ne "pad") -and ($i -lt $Presses); $i++) {
    $name = $(if (($i % 2) -eq 0) { "Down" } else { "Up" })
    $jitter = $rng.Next(0, 16667) / 1000000.0
    $events += [pscustomobject]@{ t = (40.0 + $i * $step + $jitter); name = $name; meas = $true; hold = 70 }
}
$events = $events | Sort-Object t
$endAt = ([double]($events[-1].t)) + 2.5
if ($Source -ne "keyboard") { $endAt = [math]::Max($endAt, $padStart + $Presses * $step + 2.5) }

. (Join-Path $PSScriptRoot "run_lock.ps1")
Enter-RunLock $root "pad_lag $Source $Backend $RunDir"
$p = Start-Process -FilePath $Exe -ArgumentList "`"$elf`"" -WorkingDirectory $RunDir `
    -RedirectStandardOutput "$RunDir\stdout.txt" -RedirectStandardError "$RunDir\stderr.txt" -PassThru
$t0 = Get-Date
$h = [IntPtr]::Zero
foreach ($e in $events) {
    Wait-Until ($t0.AddSeconds($e.t))
    if ($p.HasExited) { "exited early at $((Get-Date) - $t0)"; break }
    $p.Refresh()
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $h = $p.MainWindowHandle }
    if ($h -eq [IntPtr]::Zero) { "no window for $($e.name) at $($e.t)"; continue }
    Send-Tap $h $e.name $e.hold $e.meas
    "tap $($e.name) meas=$($e.meas) at {0:N3}s" -f (((Get-Date) - $t0).TotalSeconds)
}
if (-not $p.HasExited) {
    Wait-Until ($t0.AddSeconds($endAt))
    $null = $p.CloseMainWindow()
    if (-not $p.WaitForExit(8000)) { $p.Kill(); $null = $p.WaitForExit(5000) }
} else { $null = $p.WaitForExit(1000) }
Exit-RunLock $root

$lines = @()
$presentMode = if ($Present) { $Present } else { "paced" }
$lines += "freq $freq"
$lines += "mode $Mode"
$lines += "present $presentMode"
foreach ($pr in $script:taps) { $lines += ("t0 {0} {1} {2} {3}" -f $(if ($pr.meas) { "meas" } else { "nav" }), $pr.vk, $pr.qpc, $pr.name) }
$log = @()
if (Test-Path "$RunDir\stderr.txt") { $log = Get-Content "$RunDir\stderr.txt" }
foreach ($row in $log) { if ($row -match '^\[input-lag\]') { $lines += $row } }
$lines | Set-Content -Encoding ascii (Join-Path $RunDir "lag_raw.txt")

$runtime = @()
foreach ($row in $log) {
    if ($row -match 'seq=(\d+) vk=(\d+) t1=(\d+) t2=(\d+) t3=(\d+) t4=(\d+) t5=(\d+)') {
        $rd = [uint64]0
        if ($row -match 'read=(\d+)') { $rd = [uint64]$Matches[1] }
        $null = $row -match 'seq=(\d+) vk=(\d+) t1=(\d+) t2=(\d+) t3=(\d+) t4=(\d+) t5=(\d+)'
        $runtime += [pscustomobject]@{ rd = $rd;
            seq = [int]$Matches[1]; vk = [int]$Matches[2]
            t1 = [uint64]$Matches[3]; t2 = [uint64]$Matches[4]; t3 = [uint64]$Matches[5]
            t4 = [uint64]$Matches[6]; t5 = [uint64]$Matches[7]
        }
    }
}
$used = @{}
$samples = @()
foreach ($ev in $runtime) {
    if ($ev.vk -ge 65536) {
        # scripted pad press: t0 = t1 (the fake XInput pad changed state)
        $samples += [pscustomobject]@{ t0 = [uint64]$ev.t1; name = ("pad" + ($ev.vk - 65536)); ev = $ev }
        continue
    }
    $best = $null
    foreach ($pr in $script:taps) {
        if (-not $pr.meas) { continue }
        if ($pr.vk -ne $ev.vk) { continue }
        if ($used.ContainsKey($pr.qpc)) { continue }
        if ($ev.t1 -le $pr.qpc) { continue }
        $dt = [double]($ev.t1 - $pr.qpc)
        if ($dt -gt ($freq * 0.25)) { continue }
        if ($null -eq $best -or $pr.qpc -gt $best.qpc) { $best = $pr }
    }
    if ($null -eq $best) { continue }
    $used[$best.qpc] = $true
    $samples += [pscustomobject]@{ t0 = [uint64]$best.qpc; name = $best.name; ev = $ev }
}

function Quantile($vals, [double]$q) {
    $s = @($vals | Sort-Object)
    if ($s.Count -eq 0) { return $null }
    $idx = [int][math]::Ceiling($q * $s.Count) - 1
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $s.Count) { $idx = $s.Count - 1 }
    return [double]$s[$idx]
}
function Summarize($name, $vals) {
    $v = @($vals | Where-Object { $_ -ne $null })
    if ($v.Count -eq 0) { return ("{0} n=0" -f $name) }
    $med = Quantile $v 0.50
    $p95 = Quantile $v 0.95
    $frame = 16.6667
    return ("{0} n={1} median_ms={2:N2} p95_ms={3:N2} median_frames={4:N2} p95_frames={5:N2}" -f `
            $name, $v.Count, $med, $p95, ($med / $frame), ($p95 / $frame))
}
function StageMs($sample, $field) {
    $t = [uint64]$sample.ev.$field
    if ($t -eq 0) { return $null }
    return ([double]($t - $sample.t0) / [double]$freq) * 1000.0
}

$report = @()
$report += "presses $Presses source $Source backend $Backend mode $Mode present $presentMode freq $freq"
$groups = @()
if ($Source -ne "pad") { $groups += [pscustomobject]@{ name = "keyboard"; s = @($samples | Where-Object { $_.ev.vk -lt 65536 }) } }
if ($Source -ne "keyboard") { $groups += [pscustomobject]@{ name = "pad-$Backend"; s = @($samples | Where-Object { $_.ev.vk -ge 65536 }) } }
foreach ($g in $groups) {
    $gs = $g.s
    $report += "== $($g.name): samples $($gs.Count)"
    $report += (Summarize "t2-t0" @($gs | ForEach-Object { StageMs $_ "t2" }))
    $report += (Summarize "t3-t0" @($gs | ForEach-Object { StageMs $_ "t3" }))
    $report += (Summarize "t5-t0" @($gs | ForEach-Object { StageMs $_ "t5" }))
    # Input path alone: delay after the first pad read that followed the press (0 = seen by that read).
    $late = @($gs | ForEach-Object { if ($_.ev.rd -ne 0 -and $_.ev.t2 -ge $_.ev.rd) { ([double]($_.ev.t2 - $_.ev.rd) / [double]$freq) * 1000.0 } })
    $report += (Summarize "t2-read" $late)
    $report += ("missed_reads {0} of {1} (picked up one or more pad reads late)" -f @($late | Where-Object { $_ -gt 1.0 }).Count, $late.Count)
    $report += (Summarize "t5-t2" @($gs | ForEach-Object { if ($_.ev.t2 -ne 0 -and $_.ev.t5 -ne 0) { ([double]($_.ev.t5 - $_.ev.t2) / [double]$freq) * 1000.0 } }))
    $report += (Summarize "t4-t3" @($gs | ForEach-Object { if ($_.ev.t3 -ne 0 -and $_.ev.t4 -ne 0) { ([double]($_.ev.t4 - $_.ev.t3) / [double]$freq) * 1000.0 } }))
}
foreach ($row in $log) { if ($row -match '^\[pad') { $report += $row } }
$report | Set-Content -Encoding ascii (Join-Path $RunDir "lag_summary.txt")
$report | ForEach-Object { $_ }
"output $RunDir"
