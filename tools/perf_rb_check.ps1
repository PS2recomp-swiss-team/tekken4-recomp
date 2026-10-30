# Rollback self-test (p2c, sound off; s2a, sound on) and live-frame state comparison (perf switches on vs off) with the
# perf build (docs\PERF.md). Results: logs\perf\rb_selftest*.txt and rb_compare*.txt (rb_compare.py output).
# rb_selftest2*.txt, rb_compare*.txt (rb_compare.py output).
$t = $PSScriptRoot
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force (Join-Path $root "logs\perf") | Out-Null
$s = 'TEKKEN4_RAND_SEED=1;TEKKEN4_RB_INPUT=500:Start,800:Start,1040:Start,1280:Cross,1580:Start;TEKKEN4_RB_FUZZ=2100'
$off = 'PS2X_GS_SYNC_DRAIN=1;PS2X_GL_STATE_CACHE=0;PS2X_GL_BATCH_KEY=0;PS2X_GL_VERTEX_RING=0;PS2X_GL_UPLOAD_SAME=0;PS2X_GL_TEX_VERSIONS=0;PS2X_GL_PARTIAL_ROWS=0;PS2X_GS_DIRECT_PRESENT=0'
# rollback self-test, sound off, all cuts (as p2c in docs/ROLLBACK_PHASE2.md), perf build
& powershell -NoProfile -ExecutionPolicy Bypass -File "$t\perf_rb_run.ps1" -Name p2c_perf2 -Shots "60,100" -Env "$s;TEKKEN4_RB_MODE=test;TEKKEN4_RB_TEST=start=2100,every=30,depth=8,mispredict=1" | Out-File -Append -Encoding utf8 (Join-Path $root "logs\perf\chain_rb2.log")
# live-frame state hashes: perf changes on vs all off (same exe)
& powershell -NoProfile -ExecutionPolicy Bypass -File "$t\perf_rb_run.ps1" -Name mref_on2 -Shots "60,100" -Env "$s;TEKKEN4_RB_MODE=measure" | Out-File -Append -Encoding utf8 (Join-Path $root "logs\perf\chain_rb2.log")
& powershell -NoProfile -ExecutionPolicy Bypass -File "$t\perf_rb_run.ps1" -Name mref_off2 -Shots "60,100" -Env "$s;$off;TEKKEN4_RB_MODE=measure" | Out-File -Append -Encoding utf8 (Join-Path $root "logs\perf\chain_rb2.log")
python -I (Join-Path $root "docs\rollback\rb_compare.py") (Join-Path $root "logs\perf\rb\mref_off2\rb_frames.log") (Join-Path $root "logs\perf\rb\mref_on2\rb_frames.log") | Out-File -Encoding utf8 (Join-Path $root "logs\perf\rb_compare2.txt")
Select-String (Join-Path $root "logs\perf\rb\p2c_perf2\rb_frames.log") -Pattern 'SUMMARY|mismatch' | Select-Object -Last 5 | ForEach-Object { $_.Line } | Out-File -Encoding utf8 (Join-Path $root "logs\perf\rb_selftest2.txt")
python -I (Join-Path $root "docs\rollback\rb_compare.py") (Join-Path $root "logs\perf\rb\mref_on\rb_frames.log") (Join-Path $root "logs\perf\rb\mref_on2\rb_frames.log") | Out-File -Encoding utf8 (Join-Path $root "logs\perf\rb_compare_builds.txt")
# self-test with sound on (as s2a)
& powershell -NoProfile -ExecutionPolicy Bypass -File "$t\perf_rb_run.ps1" -Name s2a_perf2 -Shots "60,100" -Env "$s;TEKKEN4_SOUND=1;TEKKEN4_RB_MODE=test;TEKKEN4_RB_TEST=start=2100,every=30,depth=8,mispredict=1" | Out-File -Append -Encoding utf8 (Join-Path $root "logs\perf\chain_rb2.log")
Select-String (Join-Path $root "logs\perf\rb\s2a_perf2\rb_frames.log") -Pattern 'SUMMARY' | Select-Object -Last 1 | ForEach-Object { $_.Line } | Out-File -Encoding utf8 (Join-Path $root "logs\perf\rb_selftest2_sound.txt")
