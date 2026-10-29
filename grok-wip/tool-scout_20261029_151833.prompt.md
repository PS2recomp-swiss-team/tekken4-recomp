TASK: tool-scout. Ask mode (read-only analysis), high effort. Answer with a ranked list, not code.
QUESTION (user, 2026-10-29): which tools do we NOT have that would be useful for the Tekken 4 recomp (PAL project
H:\tekken4-recomp on master, US cousin project H:\tekken4-recomp_usa on us-iso)? Two parts:
  A. The vendored toolkit tools/console-skill/ (Jakeschincariol/console-skill a508929, MIT; read tools/console-skill/ORIGIN.md
     first). EVALUATE ONLY: console-graphics/tim2.py + gspacket.py, console-sound/vag.py, console-levels/datascan.py,
     console-physics/tune.py, console-mod/pnach.py + override.py, console-controller/padmap.py, console-saves/memcard.py,
     console-anywhere/targets.py. SKIP (we already do these better, user's instruction): console-reverse (iso/elf/state),
     console-backend/stubs.py, console-tester (run/triage/abdiff), console-graphics/widescreen.py.
  B. Tools missing entirely (not in console-skill, not in our tools/): what would speed up or improve this project now
     (PAL: 60 fps, music, F2 graphics settings, closed-loop test fight done; US: TheWishin's port + rollback netplay;
     end goal one recompiler for both ISOs with online play on both).
FOR EACH candidate: what it would do for Tekken 4 specifically (name the files/formats/addresses it would touch:
  e.g. which TIM2/VAG data exists in TEKKEN/DATA.BIN, what tune.py could find, what pnach.py would say about the
  SCES-50878 pnach in external\pcsx2\resources\patches.zip), what it needs adapted (paths, our mc0 layout, our pad code
  in ps2xRuntime/src/lib/ps2_pad.cpp and Kernel/Stubs/Pad.cpp, our patches/[patches] switch format), effort (S/M/L),
  risk, and a verdict: use now / later / not useful. Cite file:line for every claim about our code or theirs.
CONTEXT: docs/status.md (session 7 section) and CLAUDE.md for the project state; tools/ for our own tools; the US
  branch's tools via `git show origin/us-iso:tools/<file>` in H:\tekken4-recomp or the folder H:\tekken4-recomp_usa.
LIMITS: read-only. Do NOT execute anything under tools/console-skill/ (external code, not yet approved to run) and do
  not run the game. No edits, no deletes, no moves. Final answer as JSON: verdicts[] {tool, use_now|later|no, why,
  adapt, effort, risk, refs[]}, missing[] {idea, why, effort}, top3 (what to do first).
