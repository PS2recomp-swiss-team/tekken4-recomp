# handoff (Claude -> Grok while Claude is out of usage; AI-facing, dense)
Run: `powershell -File tools\grok_start.ps1 -Name lead -Mode lead` (detached driver) (steps below, in order; stops at the first step whose JSON has contra[],
fails to parse, or a work step that changes no owned file). Journal: logs\grok\lead_journal.json.
Base state: origin/master + external/PS2Recomp = patches 01-13 applied, clean. Every task is checkpointed on grok/wip.
Grok never commits, pushes, opens PRs or publishes; all changes stay uncommitted for Claude to review.
Each step reads docs/ai/grok-brief.md + docs/ai/collaboration.md first.

## DONE (not rerun)
- cnt-qwc (logs/grok/cnt-qwc_20261021_221410.json, conf 0.5): CNT qwc=4 = FUN_00292c18 ADDs ((cur-tag)>>4)-1 onto a
  qwc the PS2Recomp stubs sceVif1PkAddGsAD / closePacketGifTag already SET to 2 (refreshPacketBuilderPendingCount,
  Stubs/GS.cpp); builder FUN_002344e0; our override closeDmaTag (SET instead of ADD) is registered only at 0x292900.

- stall-fix: done by Claude 2026-10-22 (closeDmaTag also at 0x292c18; logs/stallfix_fight1). No steps pending.
