param([int[]]$DumpAt = @(70, 80))
# (tools/mfifo) PCSX2 ground truth for the fight stall: runs to the first fight (PAL60, Yes, Start, Medium, Arcade, Kazuya) and, at
# the given seconds, dumps the VIF1 MFIFO ring (D_RBOR 0x100000, 512 KB), the scratchpad and the DMA registers.
$root = "F:\claude troubleshoot\tekken 4 recomp"
$out = Join-Path $root "logs\pcsx2_ring_probe"
New-Item -ItemType Directory -Force $out | Out-Null
$job = Start-Job -ScriptBlock {
    param($root, $out)
    & (Join-Path $root "tools\pcsx2_capture.ps1") -OutDir $out -Keys "12:Down","14:Cross","16:Left","17:Cross","30:Start","36:Cross","40:Down","41.5:Cross","50:Cross" -Shots 48,58,68,78,86
} -ArgumentList $root, $out
$pine = Join-Path $root "tools\pine.py"
$t0 = Get-Date
foreach ($at in $DumpAt) {
    while (((Get-Date) - $t0).TotalSeconds -lt $at) { Start-Sleep -Milliseconds 250 }
    python -I $pine read32 0x1000e000 0x1000e040 0x1000e050 0x10009000 0x10009010 0x10009020 0x10009030 0x1000d000 0x1000d010 0x1000d020 0x1000d080 2>&1 | Out-File -Encoding utf8 (Join-Path $out "regs_$at.txt")
    python -I $pine dump 0x100000 0x80000 --out (Join-Path $out "ring_$at.bin") 2>&1 | Out-File -Encoding utf8 (Join-Path $out "dump_$at.log")
    python -I $pine dump 0x70000000 0x4000 --out (Join-Path $out "spr_$at.bin") 2>&1 | Out-File -Encoding utf8 -Append (Join-Path $out "dump_$at.log")
}
Wait-Job $job | Out-Null
Receive-Job $job
Remove-Job $job
Get-ChildItem $out | Select-Object Name, Length | Format-Table -AutoSize | Out-String
