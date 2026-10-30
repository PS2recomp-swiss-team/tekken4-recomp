OWNS: tools/usage_meter.py,docs/ai/usage-meter.md
TASK: anchor tools/usage_meter.py's 5-hour window to the reset time the user reads in /usage. Work mode, small task.
CTX: your logs/grok/usage-meter_*.json and docs/ai/usage-meter.md; logs/usage_readings.txt (user readings: 01:41 50% "resets in ~4 h" => reset ~05:45; 01:46 53%).
FACTS: `--status` now prints "5h ~53% (resets 02:35)" but /usage says the window resets ~05:45: the ccusage-style window start does not match Claude's. If the tool resets its estimate at 02:35 the lead under-counts for 3 h and misses the 78% handoff.
ASK: 1. `--calibrate PCT --resets HH:MM` (local time; next occurrence) stores the current window's end; until then the window = [end-5h, end); after it, the next window starts at the first assistant message after the end (Claude's rule as far as known; document it) and lasts 5 h. Same for `--weekly PCT --weekly-resets "YYYY-MM-DD HH:MM"` (optional). 2. recalibrate now with 53 and --resets 05:45 (state the reading time 01:46 in the calibration note). 3. --status shows the anchored reset; --hook thresholds 50/60/70/75/78/85/90/95 (one line each, once per window). 4. synthetic test proving the anchored window and the rollover.
LIMITS: OWNS files + logs/grok/ + logs/usage_*.json only; never print transcript content; no network.
PACING: finish the DOD before the final JSON.
DOD: real --status line showing "resets 05:45"; synthetic test output; final JSON.
