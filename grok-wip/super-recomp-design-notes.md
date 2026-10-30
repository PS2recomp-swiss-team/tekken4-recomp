# super-recomp-design

2026-10-30. Read-only on code. Product: docs/SUPER_RECOMPILER.md. Final object: logs/grok/super-recomp-design-final.json.

Verdict: one toolchain, one host runtime, two guest images, two exes. Third branch off the PAL fork at patches 01-32. Do not git-merge us-iso into master. Do not link both generated/ trees (same_start=141, symbol FUN_<addr>).

Music, one implementation: US 36 ISO9660 (drop PAL 35); PAL 36 SIF/IOP plus US 33 SIF.cpp, drop leave-enable; PAL 41 IRQ (drop US 34). Keep US 54's serviceSpu2Irq call on rebase. PAL 33/34/37-40/42 and US 35/37-56 are complementary. 14 files edited by both after patch 32 (scan lines 73-115). Merged numbers are doc section 2. gs_hw_backend.cpp and Pad.cpp are the two large rebases. Steps 5-7 may land as PAL-fork patches 43+ first; super branch starts when one series contains both.

Overrides: one apply(const DiscAddrs&), two PS2_REGISTER_GAME_OVERRIDE, disc_addrs_*.inc from pal_us_map.py overrides. Reject struct_diverged at/past mismatch and conf<0.85. kDataBinLbn/size stay hand-written. US comment file table 0x3133e0 is row 6, not the base (tools/databin.py:26); base is 0x313380. US camera runtime/pal/tekken4_camera_overrides.cpp registers SLUS/0xB975F704 but kBasis is still PAL 0x002D27D0. stage_generated.cmd PAL line 14 is not recursive; US line 19 copies tekken4_net*.

Netplay: PAL and US cannot meet. HELLO build_mismatch (tekken4_net.cpp:512-521). Build id hashes elf sha1 (t4_buildid.py:11). netHashOf hashes full RDRAM (rollback_overrides.cpp:1023-1034); IOP bytes only if PS2X_ROLLBACK_IOP_STATE, which US patch 41 defines as 1. Reent delta 0xE40, file-table delta 0xFE0. Same-disc online is the goal. HANDOFF "PAL too heavy" is not a bandwidth number; status fps is the other way (1142-1144).

Evidence (do not delete; user deletes):
- logs/grok/super_recomp_scan.py + super_recomp_scan.txt
- logs/grok/super_recomp_check.txt is UTF-16 LE (PowerShell redirect). open(..., encoding="utf-16"). check_fail=0 with mapped=4757, off4=1, struct_diverged=4, unmapped_pal=54.
- logs/grok/super_recomp_bins.py + super_recomp_bins.txt (VU1 both sha1 0fd1ba656b8e3c3ad372d9ced8a1edb343e644ea size 16384; US DATA.BIN sha1 5ab0b8ff65335bb13c63e222bee2ee6a890fb0fe size 2695536640; PAL DATA.BIN and both DATA2.BIN MISSING)
- logs/grok/super_recomp_low.py + super_recomp_low.txt (13 rows, conf 0.42 or 0.62)
- logs/grok/super_recomp_stubs.py

Not run: game build, ps2x tests, translate_jump_tables.py, PAL ISO walk, net_pair.ps1. DATA2 LBN 1316867 is docs/status.md:95 only. Archive hash counts are logs/grok/databin-notes.md:35 (identical 342, pal_only 533, us_only 140), not rehashed. US pair 12000/399/0 is docs/HANDOFF_WISHIN.md:25-27, not re-run.

Open: regenerate the 40 jump tables and diff; identify PAL60 among the 54 unmapped PAL functions; retest US 49 and US 55 on PAL when rebased; add compiler version to code_id before PAL netplay.
