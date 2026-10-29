param([string]$RunDir = "", [string[]]$Shots = @("20"), [string[]]$Keys = @(), [string]$StagePick = "")
# powershell -File passes a list like 9,20 or "10:Down","12:Cross" as one comma-joined string: split it here.
$Shots = @($Shots | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { [double]$_ })
$Shots = @($Shots | Sort-Object { [double]$_ } -Unique)  # the runtime takes frame shots in list order ($Shots is string[])
$Keys = @($Keys | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
# Runs ps2EntryRunner on the Tekken 4 ELF with the runtime's debugger off (PS2X_DEBUG_PANEL=0), presses pad buttons at given
# times, saves window captures at the given second marks, then closes it. Output: stdout.txt, stderr.txt and
# shot_NNs.png in $RunDir (default logs\run_<time>).
# Keys are "<seconds>:<key>" with key = Up, Down, Left, Right, Start, Select, Cross, Circle, Square, Triangle, posted
# to the window as key presses (held ~250 ms) that the runtime maps to pad 1 (D-pad WASD, Enter, Tab, X, C, Z, V; patch 29).
# Always pick PAL60 on the display-mode menu (user's request):
#   powershell -File tools\run_capture.ps1 -Keys "10:Down","12:Cross" -Shots 9,11,16,25
# -StagePick <name> (tools\run_fixed_fight.ps1): sets TEKKEN4_FRAME_SHOT_POLL=1. With no -Keys, the menus up to the
# CPU confirm are closed-loop (tools\menu_screen.py on an on-demand frame before each press). Then wait until the
# stage card is settled, press Left/Right until it is <name>, then Cross. On failure sets
# $global:TekkenStagePickExit = 2 and prints "menu step failed: <step>" or "stage pick failed: ...".
# -Keys plus -StagePick keeps the old order: play those keys, then pick the card (no menu loop).
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
# The runtime debugger (F1) starts hidden since patch 39; =0 also ignores F1, so nothing covers the picture.
if (-not $env:PS2X_DEBUG_PANEL) { $env:PS2X_DEBUG_PANEL = "0" }
$p = Start-Process -FilePath $exe -ArgumentList "`"$elf`"" -WorkingDirectory $RunDir `
    -RedirectStandardOutput "$RunDir\stdout.txt" -RedirectStandardError "$RunDir\stderr.txt" -PassThru
$t0 = Get-Date
while (((Get-Date) - $t0).TotalSeconds -lt 3 -and -not $p.HasExited) { Start-Sleep -Milliseconds 250 }
$p.Refresh(); if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
    [void][RunCaptureWin]::SetWindowText($p.MainWindowHandle, $windowTitle)
}
function Send-Pad([string]$keyName) {
    # Success is $script:padOk. Printed lines stay on the output stream (a returned bool would mix with them).
    $script:padOk = $false
    $p.Refresh(); $h = $p.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { "stage pick: no window for $keyName"; return }
    [void][RunCaptureWin]::SetWindowText($h, $windowTitle)
    if (-not $script:vk.ContainsKey($keyName)) { "unknown key $keyName"; return }
    Send-Key $h $script:vk[$keyName] $script:scan[$keyName] $false 250
    Write-Host ("pressed $keyName at {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds)
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
function Fail-Menu([string]$step) {
    if ($script:phase -eq "fail" -or $script:phase -eq "done" -or $script:phase -eq "help" -or $script:phase -eq "seek") { return }
    $script:phase = "fail"
    $global:TekkenStagePickExit = 2
    "menu step failed: $step"
}
function Set-MenuStep([string]$step, [int]$seconds) {
    if ($script:menuStep -eq $step) { return }
    $script:menuStep = $step
    $script:menuPresses = 0
    $script:stepDeadline = (Get-Date).AddSeconds($seconds)
}
function Read-MenuFrame([string]$bmp) {
    $raw = & python -I $script:menuPy --json $bmp 2>&1
    if ($LASTEXITCODE -ne 0) { return $null }
    $line = @($raw) | Where-Object { $_ -match '^\{' } | Select-Object -First 1
    if (-not $line) { return $null }
    try { return ($line | ConvertFrom-Json) } catch { return $null }
}
function Press-Menu([string]$key, [int]$holdMs) {
    if ($script:menuPresses -ge $script:menuPressMax) { Fail-Menu $script:menuStep; return $false }
    # Same signature: the last press has not landed yet. A second Cross locks the next
    # cursor; a second Right on Hwoarang moves the stage card (menu-pick notes).
    if ($script:menuActSig -eq $script:menuSig -and $script:menuActAt) {
        if (((Get-Date) - $script:menuActAt).TotalMilliseconds -lt 1800) { return $false }
    }
    Send-Pad $key
    if (-not $script:padOk) { $script:menuWait = (Get-Date).AddMilliseconds(400); return $false }
    $script:menuPresses++
    $script:menuWait = (Get-Date).AddMilliseconds($holdMs)
    $script:menuActSig = $script:menuSig
    $script:menuActAt = Get-Date
    $script:menuSig = ""
    $script:menuN = 0
    return $true
}
function Press-Confirm([string]$tag, [string]$key, [int]$holdMs, [int]$retryMs) {
    if ($retryMs -le 0) { $retryMs = 2200 }
    if ($script:once.ContainsKey($tag)) {
        if (((Get-Date) - $script:once[$tag]).TotalMilliseconds -lt $retryMs) { return $false }
    }
    if (-not (Press-Menu $key $holdMs)) { return $false }
    $script:once[$tag] = Get-Date
    return $true
}
function Save-YoshimitsuRef([string]$bmp) {
    $dest = Join-Path (Split-Path -Parent $PSScriptRoot) "logs\grok\menupick-yoshi.bmp"
    Copy-Item -LiteralPath $bmp -Destination $dest
    & python -I $script:menuPy --make-refs | Out-Null
    "menu saved yoshimitsu nameplate from $bmp"
}
# Closed-loop menus. Act only after two reads of the same screen. Exit via Fail-Menu when the step's clock runs out.
function Update-Menu() {
    if ($script:phase -ne "menu" -and $script:phase -ne "late") { return }
    $elapsed = ((Get-Date) - $t0).TotalSeconds
    if ($script:phase -eq "late") {
        if ((Get-Date) -ge $script:lateUntil) {
            Send-Pad "Cross"
            if (-not $script:padOk) { $script:lateUntil = (Get-Date).AddMilliseconds(400); return }
            "menu cpu confirmed at {0:N1} s (late {1} s)" -f $elapsed, $script:lateSec
            $script:phase = "seek"
            $script:stableName = ""
            $script:stableCount = 0
            $script:cardSeenAt = $null
            $script:presses = 0
            $script:awaitingChange = $false
            $script:nextPollAt = (Get-Date).AddMilliseconds(400)
        }
        return
    }
    if ((Get-Date) -gt $script:stepDeadline -or $elapsed -gt $script:menuDeadline) { Fail-Menu $script:menuStep; return }
    if ($script:inflight -ne 0) {
        $ok = Join-Path $RunDir ("frame_req_{0:D8}.ok" -f $script:inflight)
        $bmp = Join-Path $RunDir ("frame_req_{0:D8}.bmp" -f $script:inflight)
        if (-not (Test-Path $ok)) {
            if (((Get-Date) - $script:reqSince).TotalSeconds -gt 3) {
                "menu {0:N1} s shot {1} timed out" -f $elapsed, $script:inflight
                $script:inflight = 0
                if ($elapsed -gt 8) { $script:shotTimeouts++ }
                if ($script:shotTimeouts -gt 6) { Fail-Menu $script:menuStep }
            }
            return
        }
        $id = $script:inflight
        $script:inflight = 0
        $script:shotTimeouts = 0
        $info = Read-MenuFrame $bmp
        if (-not $info) { "menu {0:N1} s menu_screen.py failed" -f $elapsed; $script:nextPollAt = (Get-Date).AddMilliseconds(300); return }
        "menu {0:N1} s {1} row {2} side {3} char {4} detail {5} dist {6} frame_req_{7:D8}" -f $elapsed, $info.screen, $info.row, $info.side, $info.char, $info.detail, $info.dist, $id
        $sig = "{0}|{1}|{2}|{3}|{4}" -f $info.screen, $info.row, $info.side, $info.char, $info.detail
        if ($sig -eq $script:menuSig) { $script:menuN++ } else { $script:menuSig = $sig; $script:menuN = 1 }
        $rank = @{ display = 0; startgame = 1; movie = 2; title = 3; difficulty = 4; mode = 5; fighter = 6 }
        if ($rank.ContainsKey([string]$info.screen) -and $rank[[string]$info.screen] -gt $rank[$script:menuStep]) {
            $secs = @{ movie = 40; difficulty = 18; mode = 22; fighter = 28; startgame = 18; title = 18 }
            Set-MenuStep ([string]$info.screen) $secs[[string]$info.screen]
        }
        if ($script:menuN -lt 2) { $script:nextPollAt = (Get-Date).AddMilliseconds(220); return }
        if ($script:menuWait -and (Get-Date) -lt $script:menuWait) { $script:nextPollAt = (Get-Date).AddMilliseconds(200); return }
        $screen = [string]$info.screen
        if ($screen -eq "display") {
            $script:menuPressMax = 6
            if ($info.detail -eq "pal60") { if (Press-Confirm "display-cross" "Cross" 500 2200) { Set-MenuStep "startgame" 18 } }
            elseif ($info.detail -eq "above") { [void](Press-Menu "Down" 400) }
            elseif ($info.detail -eq "below") { [void](Press-Menu "Up" 400) }
        } elseif ($screen -eq "startgame") {
            $script:menuPressMax = 4
            if ($info.detail -eq "yes") { if (Press-Confirm "startgame-cross" "Cross" 500 2200) { Set-MenuStep "movie" 40 } }
            elseif ($info.detail -eq "no") { [void](Press-Menu "Left" 400) }
        } elseif ($screen -eq "movie") {
            $script:menuPressMax = 8
            if (Press-Menu "Start" 1000) { $script:menuStarts++ }
            if ($script:menuStarts -gt 8) { Fail-Menu "movie" }
        } elseif ($screen -eq "title") {
            $script:menuPressMax = 3
            if (Press-Confirm "title-cross" "Cross" 600 2200) { Set-MenuStep "difficulty" 18 }
        } elseif ($screen -eq "other" -and $script:menuStarts -ge 1) {
            $script:menuPressMax = 4
            $script:menuStep = "title"
            if (Press-Confirm "title-cross" "Cross" 600 2200) { $script:titleCross++ }
            if ($script:titleCross -gt 3) { Fail-Menu "title" }
        } elseif ($screen -eq "difficulty") {
            $script:menuPressMax = 8
            if ($info.row -eq "medium") { if (Press-Confirm "difficulty-cross" "Cross" 500 2200) { Set-MenuStep "mode" 22 } }
            elseif ($info.row -eq "easy") { [void](Press-Menu "Down" 400) }
            elseif ($info.row -eq "hard" -or $info.row -eq "veryhard" -or $info.row -eq "ultrahard") { [void](Press-Menu "Up" 400) }
        } elseif ($screen -eq "mode") {
            $script:menuPressMax = 14
            $rows = @("story", "arcade", "vs", "team", "survival", "practice", "training", "tekken", "options")
            $i = [array]::IndexOf($rows, [string]$info.row)
            if ($i -ge 0 -and $info.row -eq "practice") { if (Press-Confirm "mode-cross" "Cross" 500 2200) { Set-MenuStep "fighter" 28 } }
            elseif ($i -ge 0 -and $i -lt 5) { [void](Press-Menu "Down" 400) }
            elseif ($i -gt 5) { [void](Press-Menu "Up" 400) }
        } elseif ($screen -eq "fighter") {
            $script:menuPressMax = 12
            if ($info.side -eq "1p" -and $info.char -eq "kazuya") {
                # 4.5 s: the 1P lock animation can still read as Kazuya. A second Cross locks CPU on Xiaoyu.
                if (Press-Confirm "fighter-cross" "Cross" 700 4500) { $script:picked1p = $true }
            } elseif ($info.side -eq "cpu" -and $info.char -eq "yoshimitsu") {
                $script:phase = "late"
                $script:lateUntil = (Get-Date).AddSeconds($script:lateSec)
                "menu yoshimitsu at {0:N1} s, CPU Cross in {1} s" -f $elapsed, $script:lateSec
            } elseif ($info.side -eq "cpu" -and ($info.char -eq "xiaoyu" -or $info.char -eq "kazuya")) {
                # Kazuya is directly below Xiaoyu, Xiaoyu below Hwoarang (strategywiki grid; menupick-1 CPU started on Kazuya).
                $script:expectYoshi = $false
                $script:yoshiSeen = 0
                [void](Press-Menu "Up" 450)
            } elseif ($info.side -eq "cpu" -and $info.char -eq "hwoarang") {
                # One Right. A second Right moves the stage card, not the cursor.
                if (-not $script:expectYoshi) {
                    if (Press-Menu "Right" 500) { $script:expectYoshi = $true; $script:yoshiSeen = 0 }
                }
            } elseif ($script:expectYoshi -and -not $info.char) {
                # Nameplate animation changes the crop hash every frame, so menuN does not climb. Count reads instead.
                $script:yoshiSeen++
                if ($script:yoshiSeen -ge 4 -and -not $script:yoshiSaved) {
                    $script:yoshiSaved = $true
                    Save-YoshimitsuRef $bmp
                    $again = Read-MenuFrame $bmp
                    if ($again -and $again.char -eq "yoshimitsu") {
                        $script:phase = "late"
                        $script:lateUntil = (Get-Date).AddSeconds($script:lateSec)
                        "menu yoshimitsu at {0:N1} s, CPU Cross in {1} s" -f $elapsed, $script:lateSec
                    }
                }
            } elseif ($script:picked1p -and -not $info.char -and -not $script:expectYoshi) {
                [void](Press-Menu "Up" 450)
            }
        }
        return
    }
    if ((Get-Date) -lt $script:nextPollAt) { return }
    $script:reqSeq++
    $idText = "$($script:reqSeq) $($script:reqSeq)`n"
    [System.IO.File]::WriteAllText((Join-Path $RunDir "frame_req.id"), $idText)
    $script:inflight = $script:reqSeq
    $script:reqSince = Get-Date
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
    $script:menuPy = Join-Path $PSScriptRoot "menu_screen.py"
    $script:vk = $vk
    $script:scan = $scan
    $script:menuStep = "display"
    $script:menuSig = ""
    $script:menuN = 0
    $script:menuPresses = 0
    $script:menuPressMax = 6
    $script:menuStarts = 0
    $script:titleCross = 0
    $script:picked1p = $false
    $script:expectYoshi = $false
    $script:yoshiSeen = 0
    $script:yoshiSaved = $false
    $script:once = @{}
    $script:menuActSig = ""
    $script:menuActAt = $null
    $script:menuWait = $null
    $script:lateSec = 0.0
    if ($env:TEKKEN4_FIXED_LATE) { $script:lateSec = [double]$env:TEKKEN4_FIXED_LATE }
    $script:lateUntil = $null
    $script:stepDeadline = (Get-Date).AddSeconds(40)
    $script:menuDeadline = $script:pickDeadline - 12.0
    $pendingKeys = @($events | Where-Object { $_.kind -eq "key" }).Count
    $ei = 0
    if ($pendingKeys -eq 0) { $script:phase = "menu"; $script:nextPollAt = (Get-Date).AddSeconds(4) }
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
        Update-Menu
        Update-StagePick
        if ($script:phase -eq "fail") { break }
        Start-Sleep -Milliseconds 50
    }
    if ($p.HasExited -and $script:phase -ne "done" -and $script:phase -ne "fail") {
        "exited early after {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds
        if ($script:phase -eq "menu" -or $script:phase -eq "late") { Fail-Menu $script:menuStep }
        else { Fail-StagePick "game exited before the stage was confirmed" }
    }
}
if (-not $p.HasExited) {
    $null = $p.CloseMainWindow()
    if (-not $p.WaitForExit(8000)) { "did not close, killing"; $p.Kill(); $null = $p.WaitForExit(5000) }
}
Exit-RunLock $root
"ran {0:N1} s, output in $RunDir" -f ((Get-Date) - $t0).TotalSeconds
