param([string]$OutDir = "", [string[]]$Shots = @("20"), [string[]]$Keys = @(), [string]$Pcsx2 = "")
# powershell -File passes a list like 9,20 or "10:Down","12:Cross" as one comma-joined string: split it here.
$Shots = @($Shots | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { [double]$_ })
$Keys = @($Keys | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
# Ground truth: boots the Tekken 4 ISO in PCSX2, presses pad buttons at given times, saves captures of its game
# window at the given second marks, then stops PCSX2. Output: pcsx2_NNs.png in $OutDir (default logs\pcsx2_<time>).
# Default PCSX2: the portable 2.8.2 in external\pcsx2 (inis\PCSX2.ini: user's PAL BIOS, PINE on, pad 1 on the
# keyboard: arrows = D-pad, Enter = Start, X = Cross, Z = Circle, C = Square, V = Triangle). The user's 1.6 on E:
# (-Pcsx2 "E:\God Hand + Emulator\pcsx2.exe") boots in English but its LilyPad pad doesn't take our key presses.
# Keys are "<seconds>:<key>" with key = Up, Down, Left, Right, Start, Cross, Circle, Square, Triangle: real key
# presses with the PCSX2 window briefly brought to the front, then focus goes back.
# Always pick PAL60 on the display-mode menu (user's request):
#   powershell -File tools\pcsx2_capture.ps1 -Keys "12:Down","14:Cross" -Shots 13,20
$root = Split-Path -Parent $PSScriptRoot
if (-not $Pcsx2) { $Pcsx2 = Join-Path $root "external\pcsx2\pcsx2-qt.exe" }
if (-not $OutDir) { $OutDir = Join-Path $root ("logs\pcsx2_" + (Get-Date -Format "yyyyMMdd_HHmmss")) }
$iso = Join-Path $root "Tekken 4 (Europe, Australia) (En,Fr,De,Es,It) (v2.00).iso"
$vk = @{ Up = 0x26; Down = 0x28; Left = 0x25; Right = 0x27; Start = 0x0D; Cross = 0x58; Circle = 0x5A; Square = 0x43; Triangle = 0x56 }
$scan = @{ Up = 0x48; Down = 0x50; Left = 0x4B; Right = 0x4D; Start = 0x1C; Cross = 0x2D; Circle = 0x2C; Square = 0x2E; Triangle = 0x2F }
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class Pcsx2CaptureWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc f, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowText(IntPtr h, string s);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    // Real key press: PCSX2's window comes to the front for a moment, then the previous window gets focus back.
    public static bool Press(IntPtr target, byte vk, byte scan, bool extended) {
        IntPtr prev = GetForegroundWindow();
        uint me = GetCurrentThreadId(), fg = GetWindowThreadProcessId(prev, IntPtr.Zero);
        AttachThreadInput(me, fg, true);
        keybd_event(0x12, 0x38, 0, UIntPtr.Zero); keybd_event(0x12, 0x38, 2, UIntPtr.Zero); // Alt tap lifts the foreground lock
        BringWindowToTop(target); SetForegroundWindow(target);
        AttachThreadInput(me, fg, false);
        System.Threading.Thread.Sleep(200);
        bool focused = GetForegroundWindow() == target;
        uint ext = extended ? 1u : 0u;
        keybd_event(vk, scan, ext, UIntPtr.Zero); System.Threading.Thread.Sleep(150);
        keybd_event(vk, scan, ext | 2u, UIntPtr.Zero); System.Threading.Thread.Sleep(100);
        if (prev != IntPtr.Zero && prev != target) {
            uint t2 = GetWindowThreadProcessId(target, IntPtr.Zero);
            AttachThreadInput(me, t2, true); SetForegroundWindow(prev); AttachThreadInput(me, t2, false);
        }
        return focused;
    }
    public static List<IntPtr> Children(IntPtr parent) {
        var r = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) => { r.Add(h); return true; }, IntPtr.Zero);
        return r;
    }
    public static List<IntPtr> Visible(uint pid) {
        var r = new List<IntPtr>();
        EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) r.Add(h); return true; }, IntPtr.Zero);
        return r;
    }
}
"@
function Get-GsWindow($proc) {
    # With --nogui the only big visible window is the GS one; take the largest.
    $best = $null; $area = 0
    foreach ($h in [Pcsx2CaptureWin]::Visible([uint32]$proc.Id)) {
        $r = New-Object Pcsx2CaptureWin+RECT; [void][Pcsx2CaptureWin]::GetWindowRect($h, [ref]$r)
        $a = ($r.Right - $r.Left) * ($r.Bottom - $r.Top); if ($a -gt $area) { $area = $a; $best = @{ h = $h; r = $r } }
    }
    return $best
}
New-Item -ItemType Directory -Force $OutDir | Out-Null
# Window title names the run (user, 2026-10-28): "PCSX2 - Grok: <run>" / "PCSX2 - Claude: <run>"; re-applied at
# every event since PCSX2 sets its own title.
$runLabel = Split-Path -Leaf $OutDir
$windowTitle = if ($OutDir -match '(^|[\\/])logs[\\/]grok[\\/]') { "PCSX2 - Grok: $runLabel" } else { "PCSX2 - Claude: $runLabel" }
. (Join-Path $PSScriptRoot "run_lock.ps1")
Enter-RunLock $root "pcsx2_capture $OutDir"
$events = @($Shots | ForEach-Object { [pscustomobject]@{ t = [double]$_; kind = "shot"; key = "" } })
foreach ($k in $Keys) { $t, $name = $k -split ":", 2; $events += [pscustomobject]@{ t = [double]$t; kind = "key"; key = $name } }
$events = $events | Sort-Object t
# PCSX2 2.x (pcsx2-qt.exe, e.g. the portable one in external\pcsx2 with keyboard pad bindings) vs 1.6 (pcsx2.exe).
$pcsxArgs = if ($Pcsx2 -like "*pcsx2-qt.exe") { @("-batch", "-nogui", "-fastboot", "--", "`"$iso`"") } else { @("--nogui", "`"$iso`"") }
$p = Start-Process -FilePath $Pcsx2 -WorkingDirectory (Split-Path $Pcsx2) -ArgumentList $pcsxArgs -PassThru
$t0 = Get-Date
foreach ($e in $events) {
    while (((Get-Date) - $t0).TotalSeconds -lt $e.t -and -not $p.HasExited) { Start-Sleep -Milliseconds 100 }
    if ($p.HasExited) { "PCSX2 exited after {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds; break }
    $w = Get-GsWindow $p
    if (-not $w) { "no window at $($e.t) s"; continue }
    [void][Pcsx2CaptureWin]::SetWindowText($w.h, $windowTitle)
    if ($e.kind -eq "key") {
        if (-not $vk.ContainsKey($e.key)) { "unknown key $($e.key)"; continue }
        # Posted key messages don't reach LilyPad here, so send a real key press with PCSX2 briefly in front.
        $extended = @("Up", "Down", "Left", "Right") -contains $e.key
        $focused = [Pcsx2CaptureWin]::Press($w.h, [byte]$vk[$e.key], [byte]$scan[$e.key], $extended)
        "pressed $($e.key) at {0:N1} s (PCSX2 in front: $focused)" -f ((Get-Date) - $t0).TotalSeconds
        continue
    }
    $rw = $w.r.Right - $w.r.Left; $rh = $w.r.Bottom - $w.r.Top
    $bmp = New-Object System.Drawing.Bitmap $rw, $rh; $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc(); [void][Pcsx2CaptureWin]::PrintWindow($w.h, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
    $f = Join-Path $OutDir ("pcsx2_{0:D2}s.png" -f [int]$e.t); $bmp.Save($f, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    "captured $f ($rw x $rh)"
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
Exit-RunLock $root
"done, output in $OutDir"
