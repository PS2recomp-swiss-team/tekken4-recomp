param([string]$ProcessName = "ps2EntryRunner", [string]$Title = "TEKKEN 4 - YOUR GAME", [int]$WaitSeconds = 60)
# Names a game window (user, 2026-10-28: every window carries its task in the title). Waits for the first
# $ProcessName process started after this script with a window, sets its title, exits. Started hidden by
# tools\run_game.cmd just before the game; run_capture.ps1 / pcsx2_capture.ps1 title their own windows.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class SetWindowTitleWin {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool SetWindowText(IntPtr h, string s);
}
"@
$since = Get-Date
while (((Get-Date) - $since).TotalSeconds -lt $WaitSeconds) {
    $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
        Where-Object { $_.StartTime -ge $since.AddSeconds(-2) -and $_.MainWindowHandle -ne [IntPtr]::Zero } |
        Sort-Object StartTime | Select-Object -First 1
    if ($p) { [void][SetWindowTitleWin]::SetWindowText($p.MainWindowHandle, $Title); exit 0 }
    Start-Sleep -Milliseconds 200
}
exit 1
