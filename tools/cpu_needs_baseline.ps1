# Prints 1 when this PC's processor lacks SSSE3 or SSE4.1 (AMD Phenom II / Athlon II, Core 2 65 nm): the runtime is
# then built with PS2X_SIMD_BASELINE=ON (SSE2 only, same game state, docs/PERF.md "Old PCs"). Prints 0 otherwise.
# Windows reports both features since Windows 10; where it cannot say, the answer is 1 (the baseline runs everywhere).
try {
    Add-Type -Namespace T4Cpu -Name Features -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(int feature);' -ErrorAction Stop
    $ssse3 = [T4Cpu.Features]::IsProcessorFeaturePresent(36)   # PF_SSSE3_INSTRUCTIONS_AVAILABLE
    $sse41 = [T4Cpu.Features]::IsProcessorFeaturePresent(37)   # PF_SSE4_1_INSTRUCTIONS_AVAILABLE
    if ($ssse3 -and $sse41) { '0' } else { '1' }
} catch { '1' }
