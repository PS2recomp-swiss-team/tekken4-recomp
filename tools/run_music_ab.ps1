# Music (BGM) evidence runs, docs/MUSIC_FIX.md. Builds nothing: runs the exe of TEKKEN4_SRC / TEKKEN4_BUILD_DIR
# (defaults: D:\tekken4-fork-music, music) through the standard key path (movie skip, MEDIUM, Story Battle, Kazuya,
# skip prologue, fight from ~32 s) once per variant, each writing logs\<prefix>_<variant>\mix.wav:
#   fix_full    the fix, full mix (TEKKEN4_PERF_LOG=70: frames per second)
#   base_full   TEKKEN4_BGM=0 (no EE->IOP payload, no SPU2 interrupt = before the fix), full mix
#   fix_stream  the fix, only core 1 voices 16-17 + 20-23 (the driver's stream voices) in the mix
#   base_stream TEKKEN4_BGM=0, same voices only
#   fix_fx      the fix, every voice except the stream voices (effects and voices only)
# Then: python -I tools\wav_sections.py logs\<prefix>_<variant>\mix.wav <sections>
param([string]$Prefix = "music_ab", [string[]]$Only = @(), [string]$Shots = "12,20,28,40,50,60")
$root = Split-Path -Parent $PSScriptRoot
if (-not $env:TEKKEN4_SRC) { $env:TEKKEN4_SRC = "D:\tekken4-fork-music" }
if (-not $env:TEKKEN4_BUILD_DIR) { $env:TEKKEN4_BUILD_DIR = "music" }
$variants = [ordered]@{
    fix_full    = @{ TEKKEN4_BGM = "1"; TEKKEN4_SOUND_SOLO = ""; TEKKEN4_PERF_LOG = "70" }
    base_full   = @{ TEKKEN4_BGM = "0"; TEKKEN4_SOUND_SOLO = ""; TEKKEN4_PERF_LOG = "70" }
    fix_stream  = @{ TEKKEN4_BGM = "1"; TEKKEN4_SOUND_SOLO = "0,f30000"; TEKKEN4_PERF_LOG = "" }
    base_stream = @{ TEKKEN4_BGM = "0"; TEKKEN4_SOUND_SOLO = "0,f30000"; TEKKEN4_PERF_LOG = "" }
    fix_fx      = @{ TEKKEN4_BGM = "1"; TEKKEN4_SOUND_SOLO = "ffffff,0cffff"; TEKKEN4_PERF_LOG = "" }
}
$env:TEKKEN4_SOUND = "1"
foreach ($name in $variants.Keys)
{
    if ($Only.Count -gt 0 -and $Only -notcontains $name) { continue }
    $dir = Join-Path $root "logs\${Prefix}_$name"
    foreach ($kv in $variants[$name].GetEnumerator())
    {
        if ($kv.Value) { Set-Item "env:$($kv.Key)" $kv.Value } else { Remove-Item "env:$($kv.Key)" -ErrorAction SilentlyContinue }
    }
    $env:TEKKEN4_SOUND_WAV = Join-Path $dir "mix.wav"
    "== $name"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_capture.ps1") -RunDir $dir -Shots $Shots `
        -Keys "8:Start,13:Start,17:Start,21:Cross,26:Start" | Select-Object -Last 1
}
