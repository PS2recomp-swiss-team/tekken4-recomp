# stage-sweep 2026-10-28

Measure only. Claude default build via tools/run_fixed_fight.ps1. Practice, Kazuya vs CPU Yoshimitsu, TEKKEN4_SOUND=1. No press-plan edit: every pre-confirm card matched the asked stage (stage_card.py closest, gap to 2nd place >=30). Window = 30 perf seconds from the script's "fight from ~N s" (perf second N = wall N..N+1). Unstable rule: avg < 59.5 or more than 2 seconds with frames < 58. Only arena trips it.

Runs: logs/grok/sweep-<stage>. Until was fight+80..fight+176 so a killed process (CloseMainWindow + 8s then Kill, stdout block-buffered) still flushed the window. underground and arena were killed; the window is on disk (underground perf_lines=240, arena=156). Airport first try (sweep overwritten) stalled perf seconds 22-29 at 0 frames, Start missed the movie; the rerun is the row below.

| stage | avg | min | s<59 | GS ms | batches/frame | card dist | fight frame mean r/g/b blank=false |
| airport | 60.00 | 58 | 1 | 223.5 |  | 11.7 | frame_76 74.4/71.2/80.3 |
| building | 60.03 | 59 | 0 | 80.1 |  | 0.1 | frame_77 80.3/73.1/70.9 |
| mall_a | 60.03 | 60 | 0 | 123.2 |  | 0.0 | frame_78 111.7/92.5/71.9 |
| mall_b | 60.03 | 60 | 0 | 119.1 |  | 6.7 | frame_79 73.0/69.9/51.5 |
| shinjuku | 60.07 | 59 | 0 | 117.2 |  | 1.5 | frame_80 88.8/74.4/66.7 |
| beach | 60.03 | 59 | 0 | 75.9 |  | 12.4 | frame_80 127.0/118.5/133.0 |
| laboratory | 60.03 | 59 | 0 | 74.3 |  | 3.0 | frame_79 91.1/93.4/113.4 |
| parking | 60.07 | 59 | 0 | 96.1 |  | 0.5 | frame_78 94.6/86.1/67.7 |
| underground | 60.03 | 60 | 0 | 144.2 |  | 0.0 | frame_77 76.5/62.9/45.2 |
| arena | 37.27 | 37 | 30 | 605.4 | 1236 | 14.4 | frame_76 77.2/66.9/64.4 |

s<58 is 0 on every stage except arena (30). Airport's only dip is perf second 99: 58 frames, GS 241 ms (logs/grok/sweep-airport/stdout.txt).

## arena (only unstable)

Measurement logs/grok/sweep-arena, fight ~73, perf 73-102: every second 37 or 38 frames, GS 599-612 ms, avg 37.27 fps, GS avg 605.4. Card frame_59 arena dist 14.4 vs airport 61.8.

Profile logs/grok/sweep-arena-prof (same fight, avg 36.73 fps, GS 603.8). TEKKEN4_PROFILE=78:15 THREADS=all. stdout.txt:256 game thread 7536 samples: 56.5% NtWaitForAlertByThreadId, 3.1% SoundEngine::drainOutput, 2.8% RtlReleaseSRWLockExclusive, 1.7% PS2Memory::processVIF1Data, 1.6% VU1Interpreter::runNative, 1.3% ps2_vu_mac_apply, 1.1% RtlAcquireSRWLockExclusive, 1.1% PS2Memory::applyEeTimerTicks, 1.0% b2e30_ec9e8390, 1.0% VU1Interpreter::resetScheduler. stdout.txt:287 other threads 113040 samples of 15 threads: 26.7% NtWaitForWorkViaWorkerFactory, 26.6% ZwWaitForSingleObject, 13.3% ZwDelayExecution, 13.3% ZwWaitForMultipleObjects, 8.9% NtUserMsgWaitForMultipleObjectsEx, 4.4% NtWaitForAlertByThreadId, then GSMem::ReadIndexRun 2.9%, DrvPresentBuffers 0.5%, memmove 0.5%, GSHwBackend::Impl::hashBlocks 0.3%, GSMem::WriteRun 0.3%, GSTextureStore::LoadClut 0.2%. Waits dominate because 15 threads are summed; the first real GS work in that list is ReadIndexRun.

Batches: GOW_GS_HW_STATS "batch ends" state= on the steady fight windows (stderr, ~5 s each). Six windows state=228013,226778,226767,225545,226210,228555 (mean 226978). At this run's 36.73 fps that is 226978/(36.73*5) = 1236 state-change batches/frame. One window stderr.txt:369 state=228555 diffs: tex0=174980 clamp=160822 texsize=126812 alpha=100369 abe=81020 test=14803 type=1480 iip=740 scissor=925 frame=556. Same order as the known arena-perf cage (tex0/clamp/texsize/alpha/abe), counts a bit higher than the older ~165k/152k/120k/95k/77k per 5 s.

Other nine stages hold 60 fps with sound on. GS ms (fight window avg): beach 75.9, laboratory 74.3, building 80.1, parking 96.1, shinjuku 117.2, mall_b 119.1, mall_a 123.2, underground 144.2, airport 223.5, arena 605.4. Arena is the only stage under 59.5.
