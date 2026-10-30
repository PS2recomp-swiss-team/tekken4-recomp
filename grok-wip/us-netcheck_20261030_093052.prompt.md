OWNS: logs/grok/us-netcheck-report.md
TASK: us-netcheck. Work mode, high effort, 150 turns. RUN-ONLY checks of the US build's netplay on this PC (online focuses on US; TheWishin's netcode: no source edits).
NOTES: logs/grok/us-netcheck-notes.md; logs/grok/us-netcheck-final.json by turn 135.
FACTS: H:\tekken4-recomp_usa (branch us-iso); build H:\tekken4-fork-ps2recomp_usa\out\runtime (netplay in, build id 40f7094523f87dd6). Passing pair and command: H:\tekken4-recomp_usa\docs\NETPLAY_CHECK_PABLO_PC.md section 7 (pass -Src H:\tekken4-fork-ps2recomp_usa -BuildDir runtime -Seconds 900). Forced desync recipe: docs\ROLLBACK_PHASE3.md:39-40 (joiner TEKKEN4_RAND_SEED=2); diff: python -I docs\rollback\net_desync_diff.py.
ASK: 1. forced-desync pair: NETDESYNC at the expected frame, dumps written, the diff names the word (expect newlib rand state). 2. pairs at rtt 0, 60, 250 (jitter 5, loss 3) and one with loss 10: a table like section 7. 3. one 12000-frame pair with TEKKEN4_SOUND=1 and the HUD on. Report what degrades and where.
DOD: logs/grok/us-netcheck-report.md with the tables and the desync proof; notes + final JSON.
LIMITS: no source edits anywhere; no deletes/moves.
