param([string[]]$DumpAt = @("62","68","74","80"), [string]$OutDir = "")
# PCSX2 ground truth for the fight camera. Same fields as [camlive] (runtime/tekken4_camera_overrides.cpp).
# Fight starts ~59 s with the keys below (PAL60). Shots at each dump second show the HUD clock (00:0x:xx).
# Heap addresses differ from the recomp, so this walks pointers instead of hardcoding 0x947b30:
#   p = u32[0x2AA0D0|0x2AA0D4], cam = u32[p+0xF08], dir = u32[cam+0x198] (0x90 bytes), target = p+0x660 (16 bytes),
#   slot = 0x01CE2270 + u32[cam+0x174]*0xC0 (the 4x4 FUN_00244fc8 copies into the VU1 packet at 0x2454c4),
#   basis vec4s at 0x2D27D0 (look-at inputs; FUN_00193800 writes only the Y of each).
# a2 of the eye call is u32[cam+0x180] (logged as w180). Look-at a2/a3 are stale GPRs, not read by FUN_00193800.
$DumpAt = @($DumpAt | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { [int]$_ })
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $root "logs\pcsx2_camera_probe" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
# Last dump races pcsx2_capture tearing the process down. Hold one extra shot past it.
$shots = (($DumpAt + @($DumpAt[-1] + 8)) -join ",")
$job = Start-Job -ScriptBlock {
    param($root, $out, $shots)
    & (Join-Path $root "tools\pcsx2_capture.ps1") -OutDir $out -Shots $shots `
        -Keys "12:Down","14:Cross","16:Left","17:Cross","30:Start","36:Cross","40:Down","41.5:Cross","50:Cross"
} -ArgumentList $root, $OutDir, $shots
$snap = Join-Path $root "logs\grok\camera_live_snap.py"
# pcsx2_capture may first wait for logs\run.lock: time the dumps from this PCSX2's own start.
$launched = Get-Date
$t0 = $null
while (-not $t0) {
    $p = Get-Process pcsx2-qt -ErrorAction SilentlyContinue | Where-Object { $_.StartTime -ge $launched.AddSeconds(-2) } |
        Select-Object -First 1
    if ($p) { $t0 = $p.StartTime } else { Start-Sleep -Milliseconds 250 }
    if (((Get-Date) - $launched).TotalMinutes -gt 35) { throw "PCSX2 did not start" }
}
$probeLog = Join-Path $OutDir "probe.log"
"pcsx2 started $($t0.ToString('HH:mm:ss')) dumps $($DumpAt -join ',')" | Set-Content -Encoding utf8 $probeLog
Push-Location $root
try {
    foreach ($at in $DumpAt) {
        while (((Get-Date) - $t0).TotalSeconds -lt $at) { Start-Sleep -Milliseconds 200 }
        $out = Join-Path $OutDir ("snap_{0}.txt" -f $at)
        $ok = $false
        for ($try = 1; $try -le 8 -and -not $ok; $try++) {
            & python -I $snap $out "pcsx2-t$at" 2>&1 | Out-File -Encoding utf8 -Append $probeLog
            if ($LASTEXITCODE -eq 0 -and (Test-Path $out) -and ((Get-Item $out).Length -gt 64)) { $ok = $true }
            else { Start-Sleep -Milliseconds 500 }
        }
        if (-not $ok) { "PINE snap failed at $at s" | Out-File -Encoding utf8 -Append $probeLog }
        else { "snap $at ok at {0:N1} s" -f ((Get-Date) - $t0).TotalSeconds | Out-File -Encoding utf8 -Append $probeLog }
    }
}
finally { Pop-Location }
Wait-Job $job | Out-Null
Receive-Job $job
Remove-Job $job
Get-ChildItem $OutDir | Select-Object Name, Length | Format-Table -AutoSize | Out-String
