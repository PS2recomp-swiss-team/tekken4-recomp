# zero-copy notes

## mechanism
Host present was glReadPixels of the composed picture plus three CPU copies (GS pixels -> scratch -> upload buffer -> UpdateTexture). GSGL::PublishSharedTexture / GSSharedPresent::Acquire / GSThreadedBackend::Present already copy the present texture on the GPU and skip the pixel return when the GS context is shared and forceReadback is false. Nothing called CaptureHostContext, and PS2Runtime::initialize ran syncCoreSubsystems (GS context) before InitWindow, so there was no host context to share.

## change
- initialize: InitWindow, CaptureHostContext (releases the window context), syncCoreSubsystems, RestoreHostContext, then audio. PS2X_GS_DIRECT_PRESENT=0 returns before the capture, so the readback path stays.
- UploadFrame: when GSSharedPresent::Active and not TEKKEN4_INPUT_LAG, latch (async publish) and draw the shared texture. 12 ms wait for a newer sequence, then the previous picture. 90 missed latches -> stderr and the readback path.
- F2: SetTextureFilter on the texture actually drawn (smooth scaling; slots differ). FXAA/sharpen texel is 1/that texture. Aspect still uses the frame width/height.
- copyLatchedHostPresentationFrame: if shared stored no pixels, Present with forceReadback (frame shots, present log). Input-lag hashing stays on the readback path.
- PublishSharedTexture creates the texture with NEAREST (readback default). The host sets bilinear when smooth is on.

## measure
Before = PS2X_GS_DIRECT_PRESENT=0. After = default. Scales PS2X_GS_HW_SCALE=1|2|4. Fight = run_fixed_fight -Task zero-copy. HUD TEKKEN4_HUD_LOG, GS ms TEKKEN4_PERF_LOG=<seconds> (the value is a duration, not a flag), frame time [present] interval_avg_us / upload_avg_us.

## smoke (this session)
- Build grok_build.cmd zero-copy exit 0. ps2x_tests TEKKEN4_SRC=external\wt-zero-copy: Total 489 Passed 489 Failed 0, exit 0.
- Share works on RTX 5090: stderr "[gs-present] shared GPU textures active" and "[present] drawing shared texture 640x512". 3.3 core host (stdout GL version 3.3.0) shared with GS 4.6. No WGL sharing failure.
- Orientation: frame_16s vs host_16s corr 0.966, corr_flip -0.207 (logs/grok/zero-copy-orient.py). No flip.
- frame_16s.bmp blank false (mean r 13.79, 83% near-black menu). host_16s.png blank false.
- Menu HUD latency on the shared path: input_ms 16.1 avg_ms 16.6 n=2 (Down+Cross). readback=0 blank=0.
- Until 25 closed-loop dies immediately: menuDeadline = Until-30, so Until must stay >= ~100. Not a present bug.
- b1 readback 1x airport Until 105 (PERF_LOG=1, only second 0): fight s>=70 game=60 host=60, present mode readback upload_avg 3666 us interval 16668 us, frames 90/100/105 blank false means ~74. Official rows are the PERF_LOG=120 reruns in zero-copy-report.md.
- 2x/4x from t=0 makes menu_screen.py return size 1280x1024 (or 2560). SCALE_AT after the menus: airport 72, beach 84. Fight window airport s>=80, beach s>=90. Frame size proves the switch (2560x1792 at 4x).
- All eight fight runs and both F2 runs: stage confirmed, exit 0. FPS stays 60. GS ms and upload drop on the shared path (airport 4x s=100: GS 167->96, upload 6548->550 us; beach 4x: GS 254->74, upload 9440->94). HUD avg_ms overlaps; n=10 menu samples, late Cross did not add one.
- F2: 16:9 host bottom40 mean 0.00 vs 4:3 bottom40 57.08. row corr 0.976. Orientation corr 0.966 vs flip -0.207.

