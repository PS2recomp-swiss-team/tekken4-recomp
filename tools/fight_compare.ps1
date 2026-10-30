param(
    [string]$OutDir = "",
    [string]$Task = "fight-visuals",
    [double]$OurFightStart = 83,
    [double]$Pcsx2FightStart = 67,
    [string]$FightSeconds = "3,9,15,24",
    [string]$OurWalls = "86,92,107",
    [string]$Pcsx2Walls = "73,76,83",
    [string]$OurKeys = "10:Down,12:Cross,15:Left,16.5:Cross,30:Start,36:Cross,40:Down,41.5:Cross,46:Cross",
    [string]$Pcsx2Keys = "12:Down,14:Cross,16:Left,17:Cross,30:Start,36:Cross,40:Down,41.5:Cross,50:Cross",
    [string]$ExtraOurShots = "44",
    [string]$ExtraPcsx2Shots = "48",
    [string]$PerfSeconds = "120",
    [string]$GsDumpFrame = "",
    [switch]$SkipOurs,
    [switch]$SkipPcsx2,
    [switch]$NoPcsx2GsDump
)
# One command: our runtime and PCSX2 to the same round-clock moments, matching PNG pairs.
# Measured 2026-10-22 in logs/grok/fight-visuals-1 (HUD clock MM:SS:cc, third field is 00-99):
#   ours frame_86s 00:06:60 timer 53, frame_92s 00:09:10 timer 50, frame_107s 00:15:91 timer 44
#   PCSX2 pcsx2_73s 00:06:30 timer 53, pcsx2_76s 00:09:26 timer 50, pcsx2_83s 00:16:25 timer 43
# Our fight clock advances ~0.44 per wall second (~22-28 game frames/s). PCSX2 advances ~1.0.
# A shared FightSeconds offset cannot land both sides on the same clock, so -OurWalls and
# -Pcsx2Walls (equal length) are wall seconds zipped into pair/mNN_ours.png and pair/mNN_pcsx2.png.
# Pass -OurWalls "" -Pcsx2Walls "" to fall back to FightStart+FightSeconds (names tNN_*).
# Build first: cmd /c tools\grok_build.cmd fight-visuals
#   powershell -File tools\fight_compare.ps1
#   powershell -File tools\fight_compare.ps1 -OutDir logs\grok\fight-visuals-gs -GsDumpFrame 3691 -SkipPcsx2
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) {
    $n = 1
    do { $OutDir = Join-Path $root ("logs\grok\fight-visuals-{0}" -f $n); $n++ } while (Test-Path $OutDir)
}
$OutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $root $OutDir }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$logPath = Join-Path $OutDir "compare.log"
function Log([string]$m) {
    $line = "{0:HH:mm:ss} {1}" -f (Get-Date), $m
    Add-Content -Encoding utf8 -Path $logPath -Value $line
    Write-Output $line
}

function Split-List([string]$s) { @($s -split ',' | Where-Object { $_ -ne "" }) }
$fightSecs = @(Split-List $FightSeconds | ForEach-Object { [double]$_ })
$ourWallList = @(Split-List $OurWalls | ForEach-Object { [double]$_ })
$pcsxWallList = @(Split-List $Pcsx2Walls | ForEach-Object { [double]$_ })
$useWalls = ($ourWallList.Count -gt 0 -and $ourWallList.Count -eq $pcsxWallList.Count)
$ourKeyList = @(Split-List $OurKeys)
$pcsxKeyList = @(Split-List $Pcsx2Keys)
$ourShots = @()
foreach ($e in (Split-List $ExtraOurShots)) { $ourShots += [double]$e }
$pcsxShots = @()
foreach ($e in (Split-List $ExtraPcsx2Shots)) { $pcsxShots += [double]$e }
if ($useWalls) {
    foreach ($w in $ourWallList) { $ourShots += $w }
    foreach ($w in $pcsxWallList) { $pcsxShots += $w }
} else {
    foreach ($s in $fightSecs) { $ourShots += ($OurFightStart + $s) }
    foreach ($s in $fightSecs) { $pcsxShots += ($Pcsx2FightStart + $s) }
}
$ourShots = @($ourShots | Sort-Object -Unique)
$pcsxShots = @($pcsxShots | Sort-Object -Unique)

$ourDir = Join-Path $OutDir "ours"
$pcsxDir = Join-Path $OutDir "pcsx2"
$pairDir = Join-Path $OutDir "pair"
New-Item -ItemType Directory -Force $pairDir | Out-Null
$paramsPath = Join-Path $OutDir "params.txt"
if (-not ($SkipOurs -and $SkipPcsx2 -and (Test-Path $paramsPath))) {
@(
    "started " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
    "ourFightStart $OurFightStart pcsx2FightStart $Pcsx2FightStart",
    "useWalls $useWalls ourWalls " + ($ourWallList -join ',') + " pcsx2Walls " + ($pcsxWallList -join ','),
    "fightSeconds " + ($fightSecs -join ','),
    "ourShots " + (($ourShots | ForEach-Object { "{0:g}" -f $_ }) -join ','),
    "pcsxShots " + (($pcsxShots | ForEach-Object { "{0:g}" -f $_ }) -join ','),
    "ourKeys $OurKeys",
    "pcsxKeys $Pcsx2Keys",
    "perf $PerfSeconds gsDump $GsDumpFrame"
) | Set-Content -Encoding utf8 $paramsPath
}

if (-not $SkipOurs) {
    $envList = @()
    if ($GsDumpFrame) { $envList = @("TEKKEN4_GS_DUMP=$GsDumpFrame") }
    elseif ($PerfSeconds) { $envList = @("TEKKEN4_PERF_LOG=$PerfSeconds") }
    $shotArgs = @($ourShots | ForEach-Object { "{0:g}" -f $_ })
    Log "ours -> $ourDir shots $($shotArgs -join ',') env $($envList -join ',')"
    & (Join-Path $PSScriptRoot "grok_run.ps1") -Task $Task -RunDir $ourDir -Keys $ourKeyList -Shots $shotArgs -Env $envList
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Log "grok_run exit $LASTEXITCODE" }
    Log "bmp_to_png"
    & python -I (Join-Path $PSScriptRoot "bmp_to_png.py") $ourDir
}

if (-not $SkipPcsx2) {
    $pcsxExe = Join-Path $root "external\pcsx2\pcsx2-qt.exe"
    $iso = Join-Path $root "Tekken 4 (Europe, Australia) (En,Fr,De,Es,It) (v2.00).iso"
    $snapDir = Join-Path $root "external\pcsx2\snaps"
    $dumpDir = Join-Path $root "external\pcsx2\dumps"
    New-Item -ItemType Directory -Force $pcsxDir | Out-Null
    Add-Type -AssemblyName System.Drawing
    Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class FightCompareWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    public static bool Focus(IntPtr target) {
        ShowWindow(target, 9);
        SetWindowPos(target, new IntPtr(-1), 0, 0, 0, 0, 3u);
        IntPtr prev = GetForegroundWindow();
        uint me = GetCurrentThreadId(), fg = GetWindowThreadProcessId(prev, IntPtr.Zero);
        AttachThreadInput(me, fg, true);
        keybd_event(0x12, 0x38, 0, UIntPtr.Zero); keybd_event(0x12, 0x38, 2, UIntPtr.Zero);
        BringWindowToTop(target); SetForegroundWindow(target);
        AttachThreadInput(me, fg, false);
        System.Threading.Thread.Sleep(120);
        return GetForegroundWindow() == target;
    }
    public static bool Press(IntPtr target, byte vk, byte scan, bool extended) {
        bool focused = false;
        for (int i = 0; i < 8 && !focused; i++) focused = Focus(target);
        if (!focused) return false;
        uint ext = extended ? 1u : 0u;
        keybd_event(vk, scan, ext, UIntPtr.Zero); System.Threading.Thread.Sleep(150);
        keybd_event(vk, scan, ext | 2u, UIntPtr.Zero); System.Threading.Thread.Sleep(60);
        SetWindowPos(target, new IntPtr(-2), 0, 0, 0, 0, 3u);
        return true;
    }
    public static bool Chord(IntPtr target, byte[] vk, byte[] scan) {
        Focus(target);
        bool focused = GetForegroundWindow() == target;
        for (int i = 0; i < vk.Length; i++) keybd_event(vk[i], scan[i], 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(150);
        for (int i = vk.Length - 1; i >= 0; i--) keybd_event(vk[i], scan[i], 2, UIntPtr.Zero);
        System.Threading.Thread.Sleep(80);
        return focused;
    }
    public static List<IntPtr> Visible(uint pid) {
        var r = new List<IntPtr>();
        EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero);
        return r;
    }
}
"@
    function Get-GsWindow($proc) {
        $best = $null; $area = 0
        foreach ($h in [FightCompareWin]::Visible([uint32]$proc.Id)) {
            $r = New-Object FightCompareWin+RECT; [void][FightCompareWin]::GetWindowRect($h, [ref]$r)
            $a = ($r.Right - $r.Left) * ($r.Bottom - $r.Top)
            if ($a -gt $area) { $area = $a; $best = @{ h = $h; r = $r } }
        }
        return $best
    }
    function Get-WatchFiles() {
        $out = @()
        foreach ($d in @($snapDir, $dumpDir)) {
            if (Test-Path $d) { $out += @(Get-ChildItem $d -File -ErrorAction SilentlyContinue) }
        }
        return $out
    }
    $vk = @{ Up = 0x26; Down = 0x28; Left = 0x25; Right = 0x27; Start = 0x0D; Cross = 0x58; Circle = 0x5A; Square = 0x43; Triangle = 0x56 }
    $scan = @{ Up = 0x48; Down = 0x50; Left = 0x4B; Right = 0x4D; Start = 0x1C; Cross = 0x2D; Circle = 0x2C; Square = 0x2E; Triangle = 0x2F }
    $events = @($pcsxShots | ForEach-Object { [pscustomobject]@{ t = [double]$_; kind = "shot" } })
    foreach ($k in $pcsxKeyList) {
        $t, $name = $k -split ":", 2
        $events += [pscustomobject]@{ t = [double]$t; kind = "key"; key = $name }
    }
    $events = @($events | Sort-Object t, kind)
    . (Join-Path $PSScriptRoot "run_lock.ps1")
    Enter-RunLock $root "fight_compare pcsx2 $pcsxDir"
    $before = @(Get-WatchFiles | ForEach-Object { $_.FullName })
    Log "pcsx2 -> $pcsxDir"
    $p = Start-Process -FilePath $pcsxExe -WorkingDirectory (Split-Path $pcsxExe) -PassThru -ArgumentList @("-batch", "-nogui", "-fastboot", "--", "`"$iso`"")
    $t0 = Get-Date
    $gsDumpDone = $false
    foreach ($e in $events) {
        while (((Get-Date) - $t0).TotalSeconds -lt $e.t -and -not $p.HasExited) { Start-Sleep -Milliseconds 100 }
        if ($p.HasExited) { Log ("PCSX2 exited after {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds); break }
        $w = Get-GsWindow $p
        if (-not $w) { Log "no window at $($e.t) s"; continue }
        $now = ((Get-Date) - $t0).TotalSeconds
        if ($e.kind -eq "key") {
            if (-not $vk.ContainsKey($e.key)) { Log "unknown key $($e.key)"; continue }
            $extended = @("Up", "Down", "Left", "Right") -contains $e.key
            $focused = [FightCompareWin]::Press($w.h, [byte]$vk[$e.key], [byte]$scan[$e.key], $extended)
            Log ("pressed $($e.key) at {0:N1} s focused=$focused" -f $now)
            continue
        }
        $rw = $w.r.Right - $w.r.Left; $rh = $w.r.Bottom - $w.r.Top
        $wall = [int]$e.t
        $winPng = Join-Path $pcsxDir ("pcsx2_{0:00}s.png" -f $wall)
        if ($rw -gt 0 -and $rh -gt 0) {
            $bmp = New-Object System.Drawing.Bitmap $rw, $rh
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $hdc = $g.GetHdc(); [void][FightCompareWin]::PrintWindow($w.h, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
            $bmp.Save($winPng, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
            Log "window $winPng ${rw}x${rh}"
        }
        $stamp = Get-Date
        $focused = [FightCompareWin]::Press($w.h, [byte]0x77, [byte]0x42, $false)
        $hot = $null
        for ($i = 0; $i -lt 5 -and -not $hot; $i++) {
            Start-Sleep -Milliseconds 120
            $hot = @(Get-WatchFiles | Where-Object { $_.LastWriteTime -gt $stamp.AddSeconds(-1) -and $_.Extension -match '^\.(png|jpg|jpeg|bmp)$' -and $before -notcontains $_.FullName } | Select-Object -First 1)
            if ($hot) { break }
        }
        if ($hot) {
            $hotPng = Join-Path $pcsxDir ("pcsx2_f8_{0:00}s.png" -f $wall)
            Copy-Item $hot[0].FullName $hotPng -Force
            Log "F8 focused=$focused -> $hotPng ($($hot[0].Name))"
            $before += $hot[0].FullName
        } else { Log "F8 focused=$focused no new snap" }
        $dumpWall = -1
        if ($useWalls -and $pcsxWallList.Count -gt 1) { $dumpWall = [int]$pcsxWallList[1] }
        elseif ($fightSecs.Count -gt 1) { $dumpWall = [int]($Pcsx2FightStart + $fightSecs[1]) }
        if ($wall -eq $dumpWall -and -not $NoPcsx2GsDump -and -not $gsDumpDone) {
            $stamp2 = Get-Date
            $focused2 = [FightCompareWin]::Chord($w.h, [byte[]](0x10, 0x77), [byte[]](0x2A, 0x42))
            Start-Sleep -Seconds 2
            $dumps = @(Get-WatchFiles | Where-Object { $_.LastWriteTime -gt $stamp2.AddSeconds(-1) -and $_.Name -notmatch '\.(png|jpg|jpeg)$' -and $before -notcontains $_.FullName })
            foreach ($d in $dumps) {
                Copy-Item $d.FullName (Join-Path $pcsxDir $d.Name) -Force
                Log "GS dump focused=$focused2 $($d.Name) $($d.Length) bytes"
                $before += $d.FullName
            }
            if (-not $dumps) { Log "Shift+F8 focused=$focused2 no dump file" }
            $gsDumpDone = $true
        }
    }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Exit-RunLock $root
}

function Copy-OurFrame([int]$wall, [string]$dstName) {
    $src = Join-Path $ourDir ("frame_{0}s.png" -f $wall)
    $dst = Join-Path $pairDir $dstName
    if (Test-Path $src) { Copy-Item $src $dst -Force; Log "pair $dst" } else { Log "MISSING $src" }
}
function Copy-PcsxFrame([int]$wall, [string]$dstName) {
    $f8 = Join-Path $pcsxDir ("pcsx2_f8_{0:00}s.png" -f $wall)
    $win = Join-Path $pcsxDir ("pcsx2_{0:00}s.png" -f $wall)
    $src = if (Test-Path $f8) { $f8 } elseif (Test-Path $win) { $win } else { "" }
    $dst = Join-Path $pairDir $dstName
    if ($src) { Copy-Item $src $dst -Force; Log "pair $dst from $src" } else { Log "MISSING pcsx2 wall $wall" }
}
if ($useWalls) {
    $map = @()
    for ($i = 0; $i -lt $ourWallList.Count; $i++) {
        $tag = "m{0:00}" -f $i
        Copy-OurFrame ([int]$ourWallList[$i]) ($tag + "_ours.png")
        Copy-PcsxFrame ([int]$pcsxWallList[$i]) ($tag + "_pcsx2.png")
        $map += ("{0} ours {1} pcsx2 {2}" -f $tag, [int]$ourWallList[$i], [int]$pcsxWallList[$i])
    }
    $map | Set-Content -Encoding utf8 (Join-Path $pairDir "pairs.txt")
} else {
    foreach ($s in $fightSecs) {
        Copy-OurFrame ([int]($OurFightStart + $s)) ("t{0:00}_ours.png" -f [int]$s)
        Copy-PcsxFrame ([int]($Pcsx2FightStart + $s)) ("t{0:00}_pcsx2.png" -f [int]$s)
    }
}
foreach ($e in (Split-List $ExtraOurShots)) {
    Copy-OurFrame ([int][double]$e) ("select_{0}s_ours.png" -f [int][double]$e)
}
foreach ($e in (Split-List $ExtraPcsx2Shots)) {
    Copy-PcsxFrame ([int][double]$e) ("select_{0}s_pcsx2.png" -f [int][double]$e)
}
Log "done $OutDir"
Get-ChildItem $pairDir -ErrorAction SilentlyContinue | ForEach-Object { Log ("pairfile {0} {1}" -f $_.Name, $_.Length) }
