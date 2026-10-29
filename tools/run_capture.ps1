param([string]$RunDir = "", [string[]]$Shots = @("20"), [string[]]$Keys = @(), [string]$StagePick = "")
# powershell -File passes a list like 9,20 or "10:Down","12:Cross" as one comma-joined string: split it here.
$Shots = @($Shots | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { [double]$_ })
$Shots = @($Shots | Sort-Object { [double]$_ } -Unique)  # the runtime takes frame shots in list order ($Shots is string[])
$Keys = @($Keys | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
# Runs ps2EntryRunner on the Tekken 4 ELF, hides the runtime's debug panel (F1), presses pad buttons at given
# times, saves window captures at the given second marks, then closes it. Output: stdout.txt, stderr.txt and
# shot_NNs.png in $RunDir (default logs\run_<time>).
# Keys are "<seconds>:<key>" with key = Up, Down, Left, Right, Start, Select, Cross, Circle, Square, Triangle, posted
# to the window as key presses (held ~250 ms) that the runtime maps to pad 1 (D-pad WASD, Enter, Tab, X, C, Z, V; patch 29).
# Always pick PAL60 on the display-mode menu (user's request):
#   powershell -File tools\run_capture.ps1 -Keys "10:Down","12:Cross" -Shots 9,11,16,25
# -StagePick <name> (tools\run_fixed_fight.ps1): after the timed keys, wait until the stage card is really on screen,
# read it (on-demand frame shot), press Left/Right until it is <name>, then Cross. Sets TEKKEN4_FRAME_SHOT_POLL=1.
# On failure sets $global:TekkenStagePickExit = 2 and prints "stage pick failed: ...".
$root = Split-Path -Parent $PSScriptRoot
if (-not $RunDir) { $RunDir = Join-Path $root ("logs\run_" + (Get-Date -Format "yyyyMMdd_HHmmss")) }
$script:ring = @("arena", "airport", "building", "mall_a", "mall_b", "shinjuku", "beach", "laboratory", "parking", "underground")
if ($StagePick -and $script:ring -notcontains $StagePick) { "unknown stage $StagePick (one of: $($script:ring -join ', '))"; exit 1 }
if ($StagePick) { $env:TEKKEN4_FRAME_SHOT_POLL = "1"; $global:TekkenStagePickExit = 0 }
$vk = @{ Up = 0x57; Down = 0x53; Left = 0x41; Right = 0x44; Start = 0x0D; Select = 0x09; Cross = 0x58; Circle = 0x43; Square = 0x5A; Triangle = 0x56 }
$scan = @{ Up = 0x11; Down = 0x1F; Left = 0x1E; Right = 0x20; Start = 0x1C; Select = 0x0F; Cross = 0x2D; Circle = 0x2E; Square = 0x2C; Triangle = 0x2F }
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class RunCaptureWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowText(IntPtr h, string s);
}
"@
# Window title names the run (user, 2026-10-28): "TEKKEN 4 - Grok: <run>" / "TEKKEN 4 - Claude: <run>", or
# TEKKEN4_WINDOW_TITLE when set. Re-applied at every event.
$runLabel = Split-Path -Leaf $RunDir
$windowTitle = if ($env:TEKKEN4_WINDOW_TITLE) { $env:TEKKEN4_WINDOW_TITLE }
               elseif ($RunDir -match '(^|[\\/])logs[\\/]grok[\\/]') { "TEKKEN 4 - Grok: $runLabel" } else { "TEKKEN 4 - Claude: $runLabel" }
# Posted key messages reach the GLFW window without a focus change (lParam: repeat 1, scancode, extended flag).
function Send-Key([IntPtr]$h, [int]$vkCode, [int]$scanCode, [bool]$extended, [int]$holdMs) {
    $flags = [int64]1 -bor ([int64]$scanCode -shl 16)
    if ($extended) { $flags = $flags -bor (1 -shl 24) }
    [void][RunCaptureWin]::PostMessage($h, 0x0100, [IntPtr]$vkCode, [IntPtr]$flags)
    Start-Sleep -Milliseconds $holdMs
    [void][RunCaptureWin]::PostMessage($h, 0x0101, [IntPtr]$vkCode, [IntPtr]($flags -bor [int64]0xC0000000))
}
New-Item -ItemType Directory -Force $RunDir | Out-Null
# Record how this run was made (keys, shots, debug switches) so it can be repeated and compared later.
@("started  " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "commit   " + (git -C $root rev-parse --short HEAD 2>$null),
  "keys     " + ($Keys -join ','), "shots    " + ($Shots -join ',')) +
  @(Get-ChildItem env: | Where-Object { $_.Name -match '^(TEKKEN4_|GOW_|PS2X_)' } | Sort-Object Name |
    ForEach-Object { "env      $($_.Name)=$($_.Value)" }) | Set-Content -Encoding utf8 (Join-Path $RunDir "params.txt")
. (Join-Path $PSScriptRoot "run_lock.ps1")
Enter-RunLock $root "run_capture $RunDir"
$buildDir = if ($env:TEKKEN4_BUILD_DIR) { $env:TEKKEN4_BUILD_DIR } else { "runtime" }  # Grok: out\grok
$srcTree = if ($env:TEKKEN4_SRC) { $env:TEKKEN4_SRC } else { Join-Path (Split-Path -Parent $root) "tekken4-fork-ps2recomp" }  # see build_runtime.cmd
$exe = Join-Path $srcTree "out\$buildDir\ps2xRuntime\ps2EntryRunner.exe"
$elf = Join-Path $root "game\disc\SCES_508.78"
# GPU (OpenGL) GS renderer by default like tools\run_game.cmd (set PS2X_GS_BACKEND=cpu beforehand for the software one).
if (-not $env:PS2X_GS_BACKEND) { $env:PS2X_GS_BACKEND = "gl" }
# The software renderer draws on several threads (set PS2X_GS_THREADS=0 beforehand to draw on one).
if (-not $env:PS2X_GS_THREADS) { $env:PS2X_GS_THREADS = "auto" }
$events = @($Shots | ForEach-Object { [pscustomobject]@{ t = [double]$_; kind = "shot"; key = "" } })
foreach ($k in $Keys) { $t, $name = $k -split ":", 2; $events += [pscustomobject]@{ t = [double]$t; kind = "key"; key = $name } }
$events = @($events | Sort-Object t)
# Frame shots from the runtime's own presented frame (runtime/tekken4_frameshot_overrides.cpp): frame_NNs.bmp, valid
# even when the monitor is off or the run comes from a hidden process, where the window captures come back blank.
if (-not $env:TEKKEN4_FRAME_SHOTS) { $env:TEKKEN4_FRAME_SHOTS = ($Shots -join ',') }
$p = Start-Process -FilePath $exe -ArgumentList "`"$elf`"" -WorkingDirectory $RunDir `
    -RedirectStandardOutput "$RunDir\stdout.txt" -RedirectStandardError "$RunDir\stderr.txt" -PassThru
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 3 -and -not $p.HasExited) { Start-Sleep -Milliseconds 250 }
$p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
    [void][RunCaptureWin]::SetWindowText($p.MainWindowHandle, $windowTitle)
    Send-Key $p.MainWindowHandle 0x70 0x3B $false 100
}
function Send-Pad([string]$keyName) {
    # Success is $script:padOk. Printed lines stay on the output stream (a returned bool would mix with them).
    $script:padOk = $false
    $p.Refresh(); $h = $p.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { "stage pick: no window for $keyName"; return }
    [void][RunCaptureWin]::SetWindowText($h, $windowTitle)
    if (-not $script:vk.ContainsKey($keyName)) { "unknown key $keyName"; return }
    Send-Key $h $script:vk[$keyName] $script:scan[$keyName] $false 250
    "pressed $keyName at {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds
    $script:padOk = $true
}
function Get-StageDir([string]$current, [string]$target) {
    $i = [array]::IndexOf($script:ring, $current)
    $j = [array]::IndexOf($script:ring, $target)
    if ($i -lt 0 -or $j -lt 0) { return "Right" }
    $cw = ($j - $i + $script:ring.Count) % $script:ring.Count
    if ($cw -le [int]($script:ring.Count / 2)) { return "Right" }
    return "Left"
}
function Fail-StagePick([string]$why) {
    if ($script:phase -eq "fail" -or $script:phase -eq "done" -or $script:phase -eq "help") { return }
    $script:phase = "fail"
    $global:TekkenStagePickExit = 2
    "stage pick failed: $why"
}
# Settled card: dist<=22 and gap>=30 (logs/grok/stage-pick-notes.md). Two reads of the same name before a press or Cross.
function Update-StagePick() {
    if ($script:phase -ne "seek") { return }
    $elapsed = ((Get-Date) - $t0).TotalSeconds
    if ($script:inflight -ne 0) {
        $ok = Join-Path $RunDir ("frame_req_{0:D8}.ok" -f $script:inflight)
        $bmp = Join-Path $RunDir ("frame_req_{0:D8}.bmp" -f $script:inflight)
        if (-not (Test-Path $ok)) {
            if (((Get-Date) - $script:reqSince).TotalSeconds -gt 3) {
                "stage poll {0:N1} s shot {1} timed out" -f $elapsed, $script:inflight
                $script:inflight = 0
                $script:shotTimeouts++
                if ($script:shotTimeouts -gt 5) { Fail-StagePick "on-demand frame shots timed out (TEKKEN4_FRAME_SHOT_POLL)" }
            }
            return
        }
        $id = $script:inflight
        $script:inflight = 0
        $raw = & python -I $script:cardPy --json $bmp
        if ($LASTEXITCODE -ne 0) { "stage poll {0:N1} s stage_card.py failed on {1}" -f $elapsed, $bmp; return }
        $line = @($raw) | Where-Object { $_ -match '^\{' } | Select-Object -First 1
        try { $j = $line | ConvertFrom-Json } catch { "stage poll {0:N1} s bad json {1}" -f $elapsed, $line; return }
        $cardOk = ([double]$j.dist -le 22.0 -and [double]$j.gap -ge 30.0)
        if (-not $cardOk) {
            $script:stableName = ""
            $script:stableCount = 0
            "stage poll {0:N1} s not-card {1} dist {2:N1} gap {3:N1}" -f $elapsed, $j.name, [double]$j.dist, [double]$j.gap
            if ($elapsed -gt $script:pickDeadline) { Fail-StagePick ("no settled $($StagePick) card by {0:N1} s" -f $elapsed) }
            $script:nextPollAt = (Get-Date).AddMilliseconds(350)
            return
        }
        if ($j.name -eq $script:stableName) { $script:stableCount++ } else { $script:stableName = [string]$j.name; $script:stableCount = 1 }
        "stage poll {0:N1} s card {1} dist {2:N1} gap {3:N1} stable {4} frame_req_{5:D8}" -f $elapsed, $j.name, [double]$j.dist, [double]$j.gap, $script:stableCount, $id
        if ($script:stableCount -ge 2 -and -not $script:cardSeenAt) { $script:cardSeenAt = Get-Date }
        if ($script:stableCount -lt 2) { $script:nextPollAt = (Get-Date).AddMilliseconds(280); return }
        if ($script:awaitingChange -and $j.name -eq $script:sawName) {
            if (((Get-Date) - $script:lastPressAt).TotalSeconds -lt 1.2) { $script:nextPollAt = (Get-Date).AddMilliseconds(280); return }
            "stage poll {0:N1} s press missed (still {1})" -f $elapsed, $j.name
        } else {
            $script:awaitingChange = $false
        }
        if ($j.name -eq $StagePick) {
            # Cross in the first seconds of the card UI confirms the random stage, not the art
            # (stagepick-1: airport dist 0.7 at ~4 s, fight was laboratory; probe Cross at ~7 s was airport).
            $sinceCard = if ($script:cardSeenAt) { ((Get-Date) - $script:cardSeenAt).TotalSeconds } else { 0.0 }
            if ($sinceCard -lt 7.0) {
                "stage poll {0:N1} s hold {1} ({2:N1} s on the card UI)" -f $elapsed, $j.name, $sinceCard
                $script:nextPollAt = (Get-Date).AddMilliseconds(400)
                return
            }
            $pretty = & python -I $script:cardPy $bmp
            "stage card before the confirm: $pretty (index name distance)"
            Send-Pad "Cross"
            if (-not $script:padOk) { Fail-StagePick "no window for Cross"; return }
            $script:helpAt = (Get-Date).AddSeconds(11)
            $helpElapsed = ($script:helpAt - $t0).TotalSeconds
            if ($helpElapsed + 1 -gt $script:endT) { $script:endT = $helpElapsed + 1 }
            $script:phase = "help"
            "stage confirmed at {0:N1} s ({1} presses)" -f ((Get-Date) - $t0).TotalSeconds, $script:presses
            return
        }
        if ($script:presses -ge 12) { Fail-StagePick "12 presses did not reach $StagePick (last $($j.name))"; return }
        if ($elapsed -gt $script:pickDeadline) { Fail-StagePick ("no settled $($StagePick) card by {0:N1} s (last {1})" -f $elapsed, $j.name); return }
        $dir = Get-StageDir $j.name $StagePick
        Send-Pad $dir
        if (-not $script:padOk) { $script:nextPollAt = (Get-Date).AddMilliseconds(400); return }
        $script:presses++
        $script:lastPressAt = Get-Date
        $script:sawName = [string]$j.name
        $script:awaitingChange = $true
        $script:stableName = ""
        $script:stableCount = 0
        $script:nextPollAt = (Get-Date).AddMilliseconds(450)
        return
    }
    if ((Get-Date) -lt $script:nextPollAt) { return }
    $script:reqSeq++
    $idText = "$($script:reqSeq) $($script:reqSeq)`n"
    [System.IO.File]::WriteAllText((Join-Path $RunDir "frame_req.id"), $idText)
    $script:inflight = $script:reqSeq
    $script:reqSince = Get-Date
}
if (-not $StagePick) {
    foreach ($e in $events) {
        while (((Get-Date) - $t0).TotalSeconds -lt $e.t -and -not $p.HasExited) { Start-Sleep -Milliseconds 100 }
        if ($p.HasExited) { "exited early after {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds; break }
        $p.Refresh(); $h = $p.MainWindowHandle
        if ($h -ne [IntPtr]::Zero) { [void][RunCaptureWin]::SetWindowText($h, $windowTitle) }
        if ($e.kind -eq "key") {
            if (-not $vk.ContainsKey($e.key)) { "unknown key $($e.key)"; continue }
            Send-Key $h $vk[$e.key] $scan[$e.key] $false 250
            "pressed $($e.key) at {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds
            continue
        }
        $r = New-Object RunCaptureWin+RECT; [void][RunCaptureWin]::GetWindowRect($h, [ref]$r)
        $w = $r.Right - $r.Left; $hgt = $r.Bottom - $r.Top
        if ($w -le 0 -or $hgt -le 0) { "no window at $($e.t) s"; continue }
        $bmp = New-Object System.Drawing.Bitmap $w, $hgt
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $hdc = $g.GetHdc(); [void][RunCaptureWin]::PrintWindow($h, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
        $out = Join-Path $RunDir ("shot_{0:D2}s.png" -f [int]$e.t)
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        "captured $out"
    }
} else {
    $untilT = 0.0
    if ($events.Count -gt 0) { $untilT = [double]($events | Measure-Object -Property t -Maximum).Maximum }
    $script:endT = $untilT + 2.5
    $script:pickDeadline = $untilT - 18.0
    $script:phase = "hold"
    $script:reqSeq = 0
    $script:inflight = 0
    $script:nextPollAt = Get-Date
    $script:stableName = ""
    $script:stableCount = 0
    $script:presses = 0
    $script:awaitingChange = $false
    $script:sawName = ""
    $script:shotTimeouts = 0
    $script:cardSeenAt = $null
    $script:cardPy = Join-Path $PSScriptRoot "stage_card.py"
    $script:vk = $vk
    $script:scan = $scan
    $pendingKeys = @($events | Where-Object { $_.kind -eq "key" }).Count
    $ei = 0
    if ($pendingKeys -eq 0) { $script:phase = "seek"; $script:nextPollAt = (Get-Date).AddMilliseconds(400) }
    while (((Get-Date) - $t0).TotalSeconds -lt $script:endT -and -not $p.HasExited) {
        $elapsed = ((Get-Date) - $t0).TotalSeconds
        while ($ei -lt $events.Count -and $events[$ei].t -le $elapsed -and -not $p.HasExited) {
            $e = $events[$ei]; $ei++
            $p.Refresh(); $h = $p.MainWindowHandle
            if ($h -ne [IntPtr]::Zero) { [void][RunCaptureWin]::SetWindowText($h, $windowTitle) }
            if ($e.kind -eq "key") {
                $pendingKeys--
                if (-not $vk.ContainsKey($e.key)) { "unknown key $($e.key)" }
                else {
                    Send-Key $h $vk[$e.key] $scan[$e.key] $false 250
                    "pressed $($e.key) at {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds
                }
                if ($pendingKeys -le 0 -and $script:phase -eq "hold") {
                    $script:phase = "seek"
                    $script:nextPollAt = (Get-Date).AddMilliseconds(400)
                }
                $elapsed = ((Get-Date) - $t0).TotalSeconds
                continue
            }
            $r = New-Object RunCaptureWin+RECT; [void][RunCaptureWin]::GetWindowRect($h, [ref]$r)
            $w = $r.Right - $r.Left; $hgt = $r.Bottom - $r.Top
            if ($w -le 0 -or $hgt -le 0) { "no window at $($e.t) s"; continue }
            $bmpCap = New-Object System.Drawing.Bitmap $w, $hgt
            $g = [System.Drawing.Graphics]::FromImage($bmpCap)
            $hdc = $g.GetHdc(); [void][RunCaptureWin]::PrintWindow($h, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
            $out = Join-Path $RunDir ("shot_{0:D2}s.png" -f [int]$e.t)
            $bmpCap.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmpCap.Dispose()
            "captured $out"
        }
        if ($script:phase -eq "help" -and $script:helpAt -and (Get-Date) -ge $script:helpAt) {
            Send-Pad "Start"
            if ($script:padOk) { $script:phase = "done" }
            else { $script:helpAt = (Get-Date).AddMilliseconds(400) }
        }
        Update-StagePick
        if ($script:phase -eq "fail") { break }
        Start-Sleep -Milliseconds 50
    }
    if ($p.HasExited -and $script:phase -ne "done" -and $script:phase -ne "fail") {
        "exited early after {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds
        Fail-StagePick "game exited before the stage was confirmed"
    }
}
if (-not $p.HasExited) {
    $null = $p.CloseMainWindow()
    if (-not $p.WaitForExit(8000)) { "did not close, killing"; $p.Kill(); $null = $p.WaitForExit(5000) }
}
Exit-RunLock $root
"ran {0:N1} s, output in $RunDir" -f ((Get-Date) - $t0).TotalSeconds
