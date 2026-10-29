# pal-us-map

Tool: tools/pal_us_map.py. Map: config/pal_us_map.csv (addresses and sizes only). Stdlib, python -I. US tree read-only (TEKKEN4_US else ../tekken4-recomp_usa). No game run. check_fail=0 this session.

## What it does

Function lists: config/function_map.csv both trees. Unique non-FUN_ names of equal size are anchors. Between anchors, difflib.SequenceMatcher on sizes (autojunk off). Instruction: US_start + (addr - PAL_start) when sizes match. A short run (not named, run < 3) whose PAL-US delta equals both nearest solid matches (named or run>=3) with gaps <= 0x20 gets conf max(existing, 0.90) and method suffix +nbr (tools/pal_us_map.py:193-221). srand is that case.

Data: lockstep both copies of each structurally equal function; lui+addiu/ori and gp or live-lui load/store. Majority vote per PAL address. Same non-.text section, delta not 0 when the section moved, delta inside the section edge window. Exact hit = code-ref. Between two same-delta anchors = section-delta. Head/tail extension only when the neighbour delta equals the section start/end delta or the neighbour is within 0x200 of that edge. .text holes map only when prev and next mapped functions share start delta and span (text-gap).

64K-aligned literals below kseg are refused only by overrides and by check's override scan (length / RAM window). addr still maps them when they fall in a function or data section. US function start 0x00280000 is a real function (PAL 0x00280c30, run1, conf 0.42). kseg (>=0x80000000) stays "kseg or integer constant".

csv columns: pal,us,size,method,conf. LF. No names, no code bytes. conf in the csv is alignment only; addr lowers it past a structural divergence (insn:...:shifted, conf 0.55).

Commands: addr, func, csv, patches (pnach or [patches] only; switch= kept; values not rewritten; EE address rewritten; extended type keeps the top nibble; unmapped EE lines commented; exit 1 if any), overrides, check. --help documents methods and the 64K rule (tools/pal_us_map.py:992-1020).

## Coverage (python -I tools\pal_us_map.py check, exit 0)

name_anchors_disagree=0
functions pal=4811 us=4813 mapped=4757 unmapped_pal=54 unmapped_us=56 clashes=0 conf>=0.85 4744 conf>=0.75 4744 low 13
func_roundtrip_fail=0
listed_pairs 7/7
pnach_ee_lines pal=8 us=8
pnach_exact=7 off4=1 other=0
code_pointer_agree=120 disagree=0 struct_diverged=4 data_anchors=2608
tekken4_overrides mapped=66 unmapped=20
check_fail=0

csv (logs/grok/pal_us_stats.py): rows=4757 cols=pal,us,size,method,conf long_fields=0 +nbr rows=80 low=13. Same 4757 / low 13 as check, so the csv on disk is the post-boost map. srand row: 0x002a3168,0x002a2528,16,run1+nbr,0.90.

## Widescreen pairs (all exact)

0x002177e0 -> 0x00216ea0 insn:run125
0x001f7028 -> 0x001f6bf8 insn:run128
0x0018d408 -> 0x0018d408 insn:run140
0x002015d4 -> 0x00200d84 insn:run463
0x002015d8 -> 0x00200d88 insn:run463
0x002015e4 -> 0x00200d94 insn:run463
0x00292424 -> 0x002917e4 insn:name sceIpuStopDMA

8th pnach EE line is not a map error. pal 0x00292628 (sceIpuSync) pnach US 0x002919e4, structural map 0x002919e8. word_eq_mapped=True word_eq_pnach=False. The US pnach nops one instruction earlier. Do not force the tool onto 0x002919e4.

patches config/ghidra_export.toml (exit 0, stdout only, toml not written): the six widescreen addresses became 0x00216EA0, 0x001F6BF8, 0x0018D408, 0x00200D84, 0x00200D88, 0x00200D94. switch = "widescreen" unchanged. Values unchanged.

Zip members: external/pcsx2/resources/patches.zip SCES-50878_2251E14D.pnach and SLUS-20328_833FE0A4.pnach. 8 EE word lines, values paired.

## Data anchors check requires

reent 0x003059d4 -> 0x00304b94 code-ref:mem n=16 (late .data, delta +0xe40)
file table 0x00314360 -> 0x00313380 code-ref:abs n=13 (delta +0xfe0, not the section-start delta)
disc done 0x0035a128 -> 0x00357a28 code-ref:gp n=5
movie result 0x0035a12c -> 0x00357a2c code-ref:gp n=3
sound client 0x01cccbc0 -> 0x01cca440 code-ref:abs n=24 (high .bss, delta +0x2780)
movie IPU tag 0x01ccd2b0 -> 0x01ccab30 code-ref:abs n=1
pad 0x00358754 -> 0x00356054 code-ref:gp n=18
Reverses passed (check_fail=0). code pointers that relocate: 120 agree, 0 disagree. Identical immediates on both discs are not counted.

## Section bounds (logs/grok/pal_us_stats.py, both ELFs)

gp PAL 0x0035f270 US 0x0035cb70 delta +0x2700 (.reginfo+20).

.text PAL 0x00180080 size 0x129178 end 0x002a91f8; US 0x00180080 size 0x128538 end 0x002a85b8. start delta 0, end delta +0xc40. PAL .text is 0xc40 longer.
.data PAL 0x002a9280 size 0x5cbc8 end 0x00305e48; US 0x002a8600 size 0x5ca08 end 0x00305008. start +0xc80, end +0xe40. PAL longer by 0x1c0.
.rodata PAL 0x0030a580 size 0x4cb98 end 0x00357118; US 0x00309700 size 0x4b328 end 0x00354a28. start +0xe80, end +0x26f0. PAL longer by 0x1870.
.gcc_except_table PAL 0x00357180 size 0xe4; US 0x00354a80 size 0xe4. Uniform +0x2700.
.lit4 PAL 0x00357280 size 0x1460 end 0x003586e0; US 0x00354b80 size 0x1414 end 0x00355f94. start +0x2700, end +0x274c. PAL longer by 0x4c.
.sdata PAL 0x00358700 size 0x1768 end 0x00359e68; US 0x00356000 size 0x1728 end 0x00357728. start +0x2700, end +0x2740. PAL longer by 0x40.
.sbss PAL 0x00359e80 size 0x53c; US 0x00357780 size 0x53c. Uniform +0x2700.
.bss PAL 0x0035a400 size 0x1ae6b84 end 0x01e40f84; US 0x00357d00 size 0x1ae6b04 end 0x01e3e804. start +0x2700, end +0x2780. PAL longer by 0x80.

US CLAUDE.md:27 says .data -0xe40, .sdata/.sbss -0x2700, .bss -0x2780, .rodata per jump-table anchor. Those are the late-edge PAL-US deltas (sign flipped for a PAL->US subtract), not a constant for the whole section. .data starts at +0xc80. Early .bss (gp window) is +0x2700; high .bss is +0x2780. A blanket -0xe40 or -0x2780 mis-maps the other end. Jump-table search was not added: code-ref anchors cover the file table (n=13) and the override data sites.

## US function-list overlaps (PAL overlaps 0)

US _doMC 0x0028cff8 end 0x0028dfc8 size 4048 overlaps _rix_000 0x0028d218 size 116.
US scePadStateIntToStr 0x00293868 end 0x002a2cc8 size 62560 overlaps scePadSetReqState 0x002938a0 size 100.
Name anchors require equal size, so PAL _doMC size 540 and PAL scePadStateIntToStr size 52 stay unmapped. Bisect uses the greatest start <= addr, so the inner function wins and the huge tail is shadowed.

## struct_diverged (prefix before the offset still used; data refs after it are not)

0x00198b98 -> 0x00198a00 at +0x0 FUN_00198b98
0x001ede38 -> 0x001eda08 at +0x60 FUN_001ede38
0x0022a3c8 -> 0x00229a48 at +0x24 FUN_0022a3c8
0x002497f8 -> 0x00249150 at +0x4 FUN_002497f8 (also a low-conf run1)

## low conf < 0.75 (13). Not neighbor-boosted.

0x00249658 -> 0x00248c70 size 16 run2 0.62
0x00249668 -> 0x00248c80 size 20 run2 0.62
0x002497a0 -> 0x00248d88 size 84 run1 0.42
0x002497f8 -> 0x00249150 size 268 run1 0.42
0x0024c580 -> 0x0024ba98 size 16 run1 0.42
0x00280c30 -> 0x00280000 size 16 run1 0.42
0x00281a80 -> 0x00280e40 size 24 run1 0.42
0x00289760 -> 0x00288b20 size 64 run1 0.42
0x00293208 -> 0x002925c8 size 24 run1 0.42
0x0029f030 -> 0x0029e3f0 size 128 run2 0.62
0x0029f0b0 -> 0x0029e470 size 128 run2 0.62
0x002a7970 -> 0x002a6d30 size 12 run2 0.62
0x002a79b0 -> 0x002a6d70 size 36 run2 0.62

## unmapped PAL functions (54)

0x00196f98 size=708 FUN_00196f98
0x00197db8 size=12 FUN_00197db8
0x00197dc8 size=12 FUN_00197dc8
0x00198a60 size=208 FUN_00198a60
0x00198b30 size=100 FUN_00198b30
0x001a2740 size=7416 FUN_001a2740
0x001ac9a8 size=456 FUN_001ac9a8
0x001bd2b0 size=1068 FUN_001bd2b0
0x001bd6e0 size=1076 FUN_001bd6e0
0x001c15a8 size=5572 FUN_001c15a8
0x001e2210 size=140 FUN_001e2210
0x001edbe0 size=16 FUN_001edbe0
0x001edbf0 size=92 FUN_001edbf0
0x001edc50 size=164 FUN_001edc50
0x001edcf8 size=200 FUN_001edcf8
0x001eddc0 size=120 FUN_001eddc0
0x001f8728 size=1796 FUN_001f8728
0x001f8e30 size=1244 FUN_001f8e30
0x001f9310 size=644 FUN_001f9310
0x001f9598 size=956 FUN_001f9598
0x001f9958 size=492 FUN_001f9958
0x001f9b48 size=412 FUN_001f9b48
0x001f9ce8 size=596 FUN_001f9ce8
0x001f9f40 size=396 FUN_001f9f40
0x001fa0d0 size=968 FUN_001fa0d0
0x001fa498 size=940 FUN_001fa498
0x001fc508 size=436 FUN_001fc508
0x00211e40 size=1080 FUN_00211e40
0x00214fa0 size=716 FUN_00214fa0
0x002160f0 size=1696 FUN_002160f0
0x0021ef70 size=80 FUN_0021ef70
0x00228ec8 size=344 FUN_00228ec8
0x0022a018 size=120 FUN_0022a018
0x002494c8 size=400 FUN_002494c8
0x00249680 size=88 FUN_00249680
0x002496d8 size=200 FUN_002496d8
0x00249908 size=96 FUN_00249908
0x00249968 size=416 FUN_00249968
0x00249b08 size=164 FUN_00249b08
0x00249bb0 size=296 FUN_00249bb0
0x00249cd8 size=400 FUN_00249cd8
0x0024b208 size=4984 FUN_0024b208
0x0024c590 size=3140 FUN_0024c590
0x00263dc8 size=112 FUN_00263dc8
0x00265dd8 size=344 FUN_00265dd8
0x00265f30 size=736 FUN_00265f30
0x00276578 size=896 FUN_00276578
0x0027ffc8 size=984 FUN_0027ffc8
0x00280ca0 size=16 SetVCommonHandler
0x0028dc38 size=540 _doMC
0x0028eb48 size=92 FUN_0028eb48
0x0028eba8 size=96 FUN_0028eba8
0x002944a8 size=52 scePadStateIntToStr
0x002a37f4 size=276 FUN_002a37f4

## tekken4_overrides.cpp (86 literals/FUNs: 66 mapped, 20 unmapped)

Mapped PAL -> US. overrides stdout this session. srand is post-boost.

0x00180088 -> 0x00180088 conf=0.97 insn:name entry :1414
0x001969f8 -> 0x001969f8 conf=0.96 insn:run140 :71
0x002155d0 -> 0x00214cb8 conf=0.96 insn:run39 :73
0x002230d0 -> 0x00222788 conf=0.96 insn:run198 :52,:55
0x002230f0 -> 0x002227a8 conf=0.96 insn:run198 FUN_002230d0+0x20 :621
0x002232a0 -> 0x00222958 conf=0.96 insn:run198 :71
0x00224140 -> 0x002237f8 conf=0.96 insn:run198 FUN_002240c0+0x80 :52
0x002277d0 -> 0x00226e88 conf=0.96 insn:run198 :1111
0x00227be8 -> 0x002272a0 conf=0.96 insn:run198 :1114,:1117
0x00227cf8 -> 0x002273b0 conf=0.96 insn:run198 :1115
0x00227eb0 -> 0x00227568 conf=0.96 insn:run198 :1116,:1184
0x002281d0 -> 0x00227888 conf=0.96 insn:run198 :1072,:1079
0x00228520 -> 0x00227bd8 conf=0.96 insn:run198 :160,:1329
0x00229030 -> 0x002286d0 conf=0.96 insn:run34 :174
0x00229040 -> 0x002286e0 conf=0.96 insn:run34 :173
0x00229108 -> 0x002287a8 conf=0.96 insn:run34 :165,:1072
0x00229328 -> 0x002289c8 conf=0.96 insn:run34 :76
0x00229350 -> 0x002289f0 conf=0.96 insn:run34 :164
0x00229608 -> 0x00228ca8 conf=0.96 insn:run34 FUN_00229540+0xc8 :860
0x00229628 -> 0x00228cc8 conf=0.96 insn:run34 :861
0x002297b0 -> 0x00228e50 conf=0.96 insn:run34 :77
0x00232c20 -> 0x002322a0 conf=0.96 insn:run558 :1344
0x00232d20 -> 0x002323a0 conf=0.96 insn:run558 :1336
0x00233430 -> 0x00232ab0 conf=0.96 insn:run558 :1334
0x00233548 -> 0x00232bc8 conf=0.96 insn:run558 :1335
0x00233a38 -> 0x002330b8 conf=0.96 insn:run558 :1337
0x002344e0 -> 0x00233b60 conf=0.96 insn:run558 :1275
0x00281f40 -> 0x00281300 conf=0.97 insn:name sceSifSendCmd :63
0x00282808 -> 0x00281bc8 conf=0.97 insn:name sceSifBindRpc :60
0x002829d8 -> 0x00281d98 conf=0.97 insn:name sceSifCallRpc :61
0x00282bc8 -> 0x00281f88 conf=0.97 insn:name sceSifCheckStatRpc :62
0x0028bb40 -> 0x0028af00 conf=0.97 insn:name sceMpegGetPicture :1078
0x00292900 -> 0x00291cc0 conf=0.93 insn:run8 :938,:1274,:1338
0x00292970 -> 0x00291d30 conf=0.93 insn:run8 :1025,:1339
0x00292b28 -> 0x00291ee8 conf=0.97 insn:name sceGifPkCloseGifTag :1025,:1340
0x00292c18 -> 0x00291fd8 conf=0.86 insn:run6 :1278
0x002a3168 -> 0x002a2528 conf=0.90 insn:run1+nbr srand :974
0x002a3178 -> 0x002a2538 conf=0.97 insn:name rand :973,:978
0x003059d4 -> 0x00304b94 conf=0.99 code-ref:mem n=16 :977,:979
0x00314360 -> 0x00313380 conf=0.99 code-ref:abs n=13 :74
0x00358754 -> 0x00356054 conf=0.99 code-ref:gp n=18 :1235
0x00359f68 -> 0x00357868 conf=0.97 code-ref:gp n=2 :1235
0x0035a120 -> 0x00357a20 conf=0.99 code-ref:gp n=5 :1233
0x0035a128 -> 0x00357a28 conf=0.99 code-ref:gp n=5 :76,:79
0x0035a12c -> 0x00357a2c conf=0.97 code-ref:gp n=3 :164,:169
0x01ccc700 -> 0x01cc9f80 conf=0.99 code-ref:abs n=20 :53
0x01ccc780 -> 0x01cca000 conf=0.99 code-ref:abs n=14 :54
0x01ccc7c0 -> 0x01cca040 conf=0.99 code-ref:abs n=7 :54
0x01cccbc0 -> 0x01cca440 conf=0.99 code-ref:abs n=24 :53
0x01ccd184 -> 0x01ccaa04 conf=0.90 code-ref:mem n=1 :1120
0x01ccd188 -> 0x01ccaa08 conf=0.92 section-delta .bss d=+0x2780 gap=0x7c :1121
0x01ccd18c -> 0x01ccaa0c conf=0.92 section-delta .bss d=+0x2780 gap=0x7c :1116,:1122
0x01ccd198 -> 0x01ccaa18 conf=0.92 section-delta .bss d=+0x2780 gap=0x7c :1123
0x01ccd1ac -> 0x01ccaa2c conf=0.92 section-delta .bss d=+0x2780 gap=0x7c :1124
0x01ccd200 -> 0x01ccaa80 conf=0.99 code-ref:abs n=5 :1112,:1118
0x01ccd2b0 -> 0x01ccab30 conf=0.90 code-ref:abs n=1 :1074,:1080
0x01ccd2c0 -> 0x01ccab40 conf=0.99 code-ref:abs n=37 :1228,:1231
0x01ccd2c4 -> 0x01ccab44 conf=0.90 code-ref:mem n=1 :1236
0x01ccd2d8 -> 0x01ccab58 conf=0.92 section-delta .bss d=+0x2780 gap=0x64 :1231
0x01ccd358 -> 0x01ccabd8 conf=0.92 section-delta .bss d=+0x2780 gap=0x28 :1234
0x01ccd35c -> 0x01ccabdc conf=0.90 code-ref:mem n=1 :1233
0x01ccd364 -> 0x01ccabe4 conf=0.92 section-delta .bss d=+0x2780 gap=0x50 :1232
0x01ccd38c -> 0x01ccac0c conf=0.92 section-delta .bss d=+0x2780 gap=0x50 :1236
0x01ccd3a4 -> 0x01ccac24 conf=0.92 section-delta .bss d=+0x2780 gap=0x50 :1232
0x01ccd3d8 -> 0x01ccac58 conf=0.90 code-ref:mem n=1 :1237
0x01cda2c0 -> 0x01cd7b40 conf=0.90 code-ref:abs n=1 :906,:927,:1357

Unmapped, with reason:

0x00010000 64K-aligned literal :165,:933
0x00080000 64K-aligned literal :561
0x00100000 64K-aligned literal :559,:561,:925,:933
0x00110000 64K-aligned literal :925
0x00200000 64K-aligned literal :558
0x00300000 64K-aligned literal :556,:558
0x00500000 64K-aligned literal :556
0x00012345 below EE .text (IOP RPC id) :52,:59,:86,:613
0x0004c6b4 below EE .text :859
0x0004f4f4 below EE .text :862
0x00148000 below EE .text :862
0x80000000 kseg or integer constant :883
0x80000001 kseg or integer constant :64
0xbefff97a kseg or integer constant :1414
0xffff0000 kseg or integer constant :965
0x01fffffc not in a relocated ELF section :1129,:1135
0x01ffffff not in a relocated ELF section :139,:268,:1170,:1172
0x0ffffff0 not in a relocated ELF section :1202
0x1000b400 hardware or IOP register :1081
0x7fffffff integer constant, not an EE address :977,:995

check reason counts: 7 x 64K, 4 x below EE .text, 4 x kseg, 3 x not in a relocated section, 1 x hardware, 1 x integer constant.

camera_overrides.cpp, frameshot_overrides.cpp, profiler_overrides.cpp, testseed_overrides.cpp were not scanned. DOD names tekken4_overrides.cpp. overrides with no paths scans runtime/*_overrides.cpp (see the tool); this session passed the one file.

## Not in git

logs/grok/pal_us_probe.py, pal_us_probe2.py, pal_us_probe3.py, pal_us_rt.py, pal-ws.pnach, pal-us-overrides.txt (UTF-16 from a PowerShell redirect; do not treat as UTF-8), pal_us_stats.py. No code bytes. Do not delete them.
