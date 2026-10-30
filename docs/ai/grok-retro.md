# Grok morning retro (procedure + log)

User (2026-10-22): "Every morning after leaving all the work to grok, you need to make it work more efficiently so
every time it's more efficient and less buggy." / "If fixing grok issues each morning require it, I want a new Claude
session to handle it. So you do not get interrupted. You can dedicate it to it."

## Who
A dedicated Claude subagent, **grok-retro**, started by the lead each morning after a night of Grok work (or any long
Grok-only stretch). The lead keeps working on the game meanwhile and only gets the retro's summary.

## Procedure
1. Measure the night: `python -I tools/grok_retro.py --since "<YYYY-MM-DD HH:MM>"` (runs, finished with a parsed answer,
   hung exits, refused tools, early exits, mean conf, cost, task minutes; per task). Compare with the previous entry.
2. Find each failure's root cause from evidence, not guesses: logs/grok/<task>_*.json, the notes, the run dirs, and
   Grok's own event log `~/.grok/logs/unified.jsonl` (by pid: `shell.handle_prompt.done`, `shell.tool.exec_done`,
   refusals). Digests in logs/grok/digest.md.
3. Fix the cause in the tooling, not by hand: tools/grok_task.ps1 (wrapper, rules), tools/grok_start.ps1,
   tools/grok_build.cmd, tools/grok_run.ps1, tools/*.py helpers, docs/ai/grok-brief.md, docs/ai/grok-manager.md,
   docs/ai/collaboration.md. Prompts under docs/ai/prompts/ only as examples. Never change Grok's permission mode or
   deny lists without the lead (live tasks keep their old wrapper).
4. Test every fix (parse check for .ps1; a cheap smoke task through tools/grok_start.ps1 for wrapper changes).
5. Commit only the retro's own files (`git commit -- <paths>`; retry on index.lock), push, append an entry below.
6. Send the lead a summary of at most 8 lines: metrics vs last time, fixes, what still needs the lead.

## Log

### 2026-10-22 (night 2026-10-21 22:00 - 2026-10-22 07:00)
Metrics: 23 runs, 15 with a parsed answer, 8 without (6 "stuck", 1 refused compound command, 1 premature "reading"
answer); ~$68; ~1370 task-minutes. Mean conf of answered runs ~0.75.
Root causes and fixes:
- "Stuck" tasks were finished: Grok CLI 1.0.62 logged shell.handle_prompt.done, then never exited, so the wrapper
  waited forever and the answer was lost (pids 95988, 73448, 61040). FIX (lead): grok_task.ps1 runs Grok as a job,
  watches unified.jsonl for its pid's handle_prompt.done and ends it 90 s later (hung_exit in the result json); rule
  FINAL makes Grok also write logs/grok/<task>-final.json, which the wrapper reads when stdout has no answer.
- Refused compound PowerShell commands (camera-live run 1): FIX (lead): tools/grok_build.cmd + tools/grok_run.ps1,
  one simple command per call (rules + TOOLS line).
- Premature final answer ("reading", 6 turns): FIX: PACING block in work prompts; the manager relaunches < 15 turns +
  non-final verdict as mechanical.
- Blind results: window screenshots blank all night (monitor off, hidden process) -> FIX (lead): frame shots from
  the runtime (runtime/tekken4_frameshot_overrides.cpp, run_capture.ps1 sets TEKKEN4_FRAME_SHOTS) + tools/bmp_to_png.py;
  rule IMAGES. Vacuous checks (an IRQ counter at 0 before and after "proved" the timer batching safe; it broke 2 tests)
  -> rule CHECKS (a check must be able to fail) + rule TESTS (build_tests after any runtime/recompiler change).
- Edits outside OWNS (iop_ioman.h) and file lists missing files -> rule OWNS IS HARD.
- Several work tasks shared out\grok -> per-task out\grok-<task> (wrapper rules, grok_build.cmd).
Still open (for grok-retro): Grok cannot *judge* its own images/audio beyond "file exists": numeric frame and WAV
checks it can run (non-blank, diff vs a reference frame, PSNR; WAV RMS/peak/clipping per window); a metrics script
(tools/grok_retro.py); verify the watchdog on a real hang; per-task clean source trees so work tasks stop sharing
(and confounding) one PS2Recomp tree.

Retro-Claude additions (2026-10-22):
- Also fixed by the lead: parallel MSVC builds failed with C1090 "PDB API call failed" (0x6BA / 23) when one build's
  mspdbsrv went away; build_runtime.cmd / build_tests.cmd now use /Z7 (commit 813ac0f); each build folder rebuilds fully once.
- DONE, tested on real files: tools/frame_stats.py (stats + --diff + diff PNG; BMP and PNG agree on frame_40s), tools/wav_stats.py
  (sound-run-11/out.wav: clipped 1219, longest silence 9.6 s); wired as rules IMAGES (numbers) + AUDIO in grok_task.ps1 (parse ok)
  and in grok-brief.md COMMANDS. tools/grok_retro.py: night 2026-10-21 22:00-07:00 = 27 result files (lead counted 23), 19 answered,
  8 not, 6 pids done-without-exit, 84.77 $, 1459 min, mean conf 0.74, 3949 tool execs (53 failed), 11 inference retries.
  Next retro: `python -I tools/grok_retro.py --since "<start>" --until "<end>"` and compare these totals.
- PARTLY: tools/grok_tree.ps1 (-Task t | -Diff | -Remove) creates external/wt-<t> = PS2Recomp HEAD + patches/*.patch (skips ones already in
  HEAD) + baseline commit; tested create/diff/remove. NOT done: wiring into grok_build.cmd / grok_run.ps1 (set TEKKEN4_SRC when the tree
  exists), checkpoint of the tree diff in grok_task.ps1, switching tasks. Lead turns a task's tree into a patch with -Diff.
- Still open: watchdog verified on a real hang; tree wiring above.
