param([string]$Name='before',[int]$Seconds=140,[switch]$Fight,[string]$Catchup='2',
      [string]$Iso=$env:TEKKEN4_ISO,[string]$Elf='', [string]$Exe='',
      [string]$HeavyRoot=$env:TEKKEN4_HEAVY_ROOT)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
if($Name -notmatch '^[A-Za-z0-9_-]+$'){throw 'Name must use letters, digits, underscore or hyphen'}
if(-not $Iso){throw 'Pass -Iso or set TEKKEN4_ISO'}
if(-not $HeavyRoot){throw 'Pass -HeavyRoot (the coordination lock directory) or set TEKKEN4_HEAVY_ROOT'}
if(-not $Elf){$Elf=Join-Path $root 'game\disc\SLUS_203.28'}
if(-not $Exe){$Exe=Join-Path $root 'deps\ps2recomp\out\runtime\ps2xRuntime\ps2EntryRunner.exe'}
$dir=Join-Path $root "build\movaudio\$Name"
if(Test-Path -LiteralPath (Join-Path $dir 'params.txt')){throw "Run already exists: $dir; choose a new -Name"}
New-Item -ItemType Directory -Force $dir | Out-Null
$locks=@()
$game=$null
$realConfig=Join-Path $env:LOCALAPPDATA 'OpenRecomp\config.json'
function ConfigHash { if(Test-Path -LiteralPath $realConfig) { (Get-FileHash -LiteralPath $realConfig -Algorithm SHA256).Hash } else { 'absent' } }
$before=ConfigHash
try {
  foreach($n in @('HEAVY.lock','HEAVY2.lock','HEAVY3.lock')) {
    $path=Join-Path $HeavyRoot $n
    try { $s=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read); $w=New-Object IO.StreamWriter($s); $w.WriteLine("movaudio $(Get-Date -Format o) $Name audio timing capture"); $w.Dispose(); $locks+=$path } catch [IO.IOException] {}
    if($locks.Count -eq 2) { break }
  }
  if($locks.Count -lt 2){throw 'Two heavy slots unavailable for timing capture'}
  Get-ChildItem env: | Where-Object Name -Match '^TEKKEN4_(NET|RB|SOUND|MOVIE|AUDIO|PAD|TEST|FRAME)' | ForEach-Object { Remove-Item "env:$($_.Name)" }
  $env:PS3_AUDIO_MUTE='1'; $env:PS3_WINDOW_BACKGROUND='1'
  $env:OPENRECOMP_HOME=Join-Path $dir 'profile'; $env:APPDATA=Join-Path $dir 'profile\roaming'; $env:LOCALAPPDATA=Join-Path $dir 'profile\local'
  New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA | Out-Null
  $env:TEKKEN4_ISO=(Resolve-Path -LiteralPath $Iso).Path
  $env:TEKKEN4_SOUND='1'; $env:TEKKEN4_SOUND_WAV=Join-Path $dir 'mix.wav'; $env:TEKKEN4_AUDIO_DEVICE_WAV=Join-Path $dir 'device.wav'
  $env:PS2X_VBLANK_CATCHUP=$Catchup; $env:TEKKEN4_AUDIO_TEST_CLOCK='1'; $env:TEKKEN4_MOVIE_SYNC='1'; $env:TEKKEN4_AUDIO_STATS='1'; $env:PS2X_GS_BACKEND='gl'; $env:PS2X_DEBUG_PANEL='0'; $env:TEKKEN4_FULLSCREEN='0'
  $env:TEKKEN4_PERF_LOG="$Seconds"
  if($Fight){$env:TEKKEN4_FRAME_SHOTS='35,50,60'}
  $exe=(Resolve-Path -LiteralPath $Exe).Path
  $elf=(Resolve-Path -LiteralPath $Elf).Path
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class MovieAudioWindow {
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a,int x,int y,int w,int z,uint f);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
}
"@
  $game=Start-Process -FilePath $exe -ArgumentList "`"$elf`"" -WorkingDirectory $dir -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $dir 'stdout.txt') -RedirectStandardError (Join-Path $dir 'stderr.txt')
  "exe=$exe iso=$($env:TEKKEN4_ISO) elf=$elf seconds=$Seconds fight=$Fight catchup=$Catchup nullDeviceClock=1" | Set-Content (Join-Path $dir 'params.txt')
  $null=$game.Handle
  $game.PriorityClass='BelowNormal'
  $clock=[Diagnostics.Stopwatch]::StartNew()
  $keys=@()
  if($Fight){$keys=@(@(8,13,0x1c),@(13,13,0x1c),@(17,13,0x1c),@(21,0x58,0x2d),@(26,13,0x1c),@(38,0x58,0x2d),@(39,0x5a,0x2c),@(41,0x58,0x2d),@(43,0x56,0x2f),@(45,0x5a,0x2c),@(47,0x58,0x2d))}
  $keyIndex=0
  while($clock.Elapsed.TotalSeconds -lt $Seconds -and -not $game.HasExited){
    $game.Refresh(); $h=$game.MainWindowHandle
    if($h -ne [IntPtr]::Zero){
      [void][MovieAudioWindow]::SetWindowPos($h,[IntPtr]1,0,0,0,0,0x0013)
      if($keyIndex -lt $keys.Count -and $clock.Elapsed.TotalSeconds -ge $keys[$keyIndex][0]){
        $k=$keys[$keyIndex]; $lp=1 -bor ($k[2] -shl 16)
        [void][MovieAudioWindow]::PostMessage($h,0x100,[IntPtr]$k[1],[IntPtr]$lp)
        Start-Sleep -Milliseconds 150
        [void][MovieAudioWindow]::PostMessage($h,0x101,[IntPtr]$k[1],[IntPtr]([int64]$lp -bor [int64]0xc0000000))
        $keyIndex++
      }
    }
    Start-Sleep -Milliseconds 200
  }
  if(-not $game.HasExited){ [void]$game.CloseMainWindow(); if(-not $game.WaitForExit(8000)){ $game.Kill(); $game.WaitForExit(); 'forced termination' | Add-Content (Join-Path $dir 'result.txt') } }
  $game.Refresh()
  "exit=$($game.ExitCode) elapsed=$($clock.Elapsed.TotalSeconds) keys=$keyIndex configBefore=$before configAfter=$(ConfigHash)" | Add-Content (Join-Path $dir 'result.txt')
  Get-Content (Join-Path $dir 'result.txt')
} finally {
  if($game -and -not $game.HasExited){$game.Kill();$game.WaitForExit()}
  foreach($path in $locks){Remove-Item -LiteralPath $path}
}


