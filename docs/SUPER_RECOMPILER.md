# Super recompiler

One toolchain and one host runtime for both Tekken 4 discs. Two guest images. Online play is same-disc only.

PAL is SCES-50878 v2.00 (`game/disc/SCES_508.78`). US is SLUS-20328 v1.00 (`game/disc/SLUS_203.28` in `H:\tekken4-recomp_usa`). The lines stay cousin projects: `master` and `us-iso` are never merged into each other (`CLAUDE.md` rules; `docs/HANDOFF_WISHIN.md` section 1). The super recompiler is a third line. It is built by replaying patches onto a new branch, not by `git merge`.

Measured this session unless a line says otherwise. Inventory: `logs/grok/super_recomp_scan.txt`. Mapper check: `logs/grok/super_recomp_check.txt` (`check_fail=0`).

## Decision

| Piece | One or per disc |
|---|---|
| PS2Recomp patches after the union below | one series, disc-agnostic |
| `ps2_recomp` run, `generated/`, the exe's guest code | per disc |
| `runtime/tekken4_overrides.cpp` logic | one file, compiled once per disc |
| guest addresses, `[patches]`, jump tables, stub addresses | generated from the PAL config + `tools/pal_us_map.py` + the other ELF |
| DATA.BIN LBN, size, row count, DATA2.BIN | per disc, from that ISO, not from the map |
| netplay | same disc. A PAL peer and a US peer are refused |

Do not link both `generated/` trees into one exe. 141 mapped functions start at the same address (`config/pal_us_map.csv`: `same_start=141`, `different_start=4616`). The generated symbol is `FUN_<addr>`. Those 141 collide. `ps2_recomp` also takes one ELF (`config/ghidra_export.toml` `input`).

## 1. Disc detection and per-disc data

### Identity

The runtime already selects overrides by ELF basename, entry, and full-file CRC32. `computeFileCrc32` is IEEE (poly `0xEDB88320`, init `0xFFFFFFFF`, final xor) in `H:\tekken4-fork-ps2recomp\ps2xRuntime\src\lib\ps2_runtime.cpp:118-156`. `applyMatching` requires all three when the descriptor sets them (`ps2xRuntime\src\lib\game_overrides.cpp:148-168`). `PS2_REGISTER_GAME_OVERRIDE` stores name, ELF, entry, CRC (`ps2xRuntime\include\game_overrides.h:40-49`).

Both discs use entry `0x00180088`, so entry does not tell them apart.

| | PAL | US |
|---|---|---|
| file | `SCES_508.78` | `SLUS_203.28` |
| size | 1966528 | 1956544 |
| SHA-1 | `24ced2b7f3a0a40b3cacec56a030701d6be8e5ce` | `a4b7dde20a2918c550badd127a245db155c36815` |
| CRC32 (runtime) | `0xBEFFF97A` | `0xB975F704` |
| SYSTEM.CNF | `BOOT2 = cdrom0:\SCES_508.78;1`, `VER = 2.00`, `VMODE = PAL` | `BOOT2 = cdrom0:\SLUS_203.28;1`, `VER = 1.00`, `VMODE = NTSC` |
| register | `runtime/tekken4_overrides.cpp:1414` | `H:\tekken4-recomp_usa\runtime\tekken4_overrides.cpp:1394` |

SHA-1 and CRC32 were recomputed on the two ELF files. They match `CLAUDE.md` and the US `CLAUDE.md`. PCSX2 pnach names use different CRCs: `SCES-50878_2251E14D.pnach` and `SLUS-20328_833FE0A4.pnach` (`tools/pal_us_map.py:900-901`, `docs/status.md:1147`). Those are not the runtime CRC. Do not put `0x2251E14D` in `PS2_REGISTER_GAME_OVERRIDE`.

The netplay build id hashes the ELF SHA-1, not the CRC (`H:\tekken4-recomp_usa\tools\t4_buildid.py:5-11`). Keep both in a `config/discs.toml` and check SHA-1 at startup as well as the CRC. CRC is what selects the override today. SHA-1 is what refuses a different disc in HELLO.

### What is per disc

`function_map.csv`: PAL 4811 rows (631 named), US 4813 rows (629 named). Ghidra's own count is lower because the csv is Ghidra plus `extra_functions.csv`: PAL toml `function_count = 4459` (`config/ghidra_export.toml:355`), US `4454` (`H:\tekken4-recomp_usa\config\ghidra_export.toml:342`).

`config/pal_us_map.csv`: 4757 pairs, 0 clashes, round-trip 0 failures. Confidence `>= 0.85` on 4744, low on 13 (all `run1`/`run2`). Unmapped: 54 PAL, 56 US (`logs/grok/super_recomp_check.txt` line 2). Opcode skeleton differs in 4 mapped functions only (`struct_diverged=4`). `same_op` ignores immediates and branch targets (`tools/pal_us_map.py:277-288`, `291-331`), so a mapped function is still not the same bytes and not the same generated C++.

The 4:

| PAL | US | diverges |
|---|---|---|
| `0x00198b98` | `0x00198a00` | +0x0 |
| `0x001ede38` | `0x001eda08` | +0x60 |
| `0x0022a3c8` | `0x00229a48` | +0x24 |
| `0x002497f8` | `0x00249150` | +0x4 |

A generator must not byte-offset an address at or past that point.

Jump tables: 40 in each toml. US block is labeled as carried by `tools/translate_jump_tables.py` (`H:\tekken4-recomp_usa\config\ghidra_export.toml:352`). That tool maps each PAL target through a function map, then finds the pointer run in the US ELF. It needs the US ELF. It is not `pal_us_map` alone. This session counted the tables. It did not rebuild them.

`[patches]` exists only on PAL (`config/ghidra_export.toml:344-352`): six `widescreen` words. US toml has no `[patches]` section. `pal_us_map.py patches` rewrites addresses and leaves the value and the `switch` name (`tools/pal_us_map.py:742-775`, epilog at 997). The recompiler emits both words under `PS2_SWITCH` (`H:\tekken4-fork-ps2recomp\ps2xRecomp\src\lib\function_emitter.cpp:208-219`).

The six map exactly (`logs/grok/super_recomp_check.txt`):

| PAL | US | method |
|---|---|---|
| `0x002177E0` | `0x00216EA0` | insn:run125 |
| `0x001F7028` | `0x001F6BF8` | insn:run128 |
| `0x0018D408` | `0x0018D408` | insn:run140 |
| `0x002015D4` | `0x00200D84` | insn:run463 |
| `0x002015D8` | `0x00200D88` | insn:run463 |
| `0x002015E4` | `0x00200D94` | insn:run463 |

PCSX2's pnach also has `0x00292424` / `0x00292628` (PAL) inside `sceIpuStopDMA` / `sceIpuSync`. The first maps to `0x002917E4`. The second is off by 4: pnach US `0x002919E4`, map `0x002919E8`, and the word at the pnach address does not match (`pnach OFF4` in the check). Status already leaves those two out (`docs/status.md:137-138`). Do not generate them.

Stub names: 312 on each side, 0 only-on-one-side. 306 of 307 single-address names agree with the map. The miss is `scePadStateIntToStr` (PAL `0x002944A8`, US `0x00293868`), and that function is one of the 54 unmapped (`size=52`). Five names occur more than once, in the same order on both discs: `AddDmacHandler` (2), `InitTLB` (3), `iWakeupThread` (2), `printf` (2), `sceSifSendCmd` (2). Pair those by order. The override hooks the second `sceSifSendCmd`: US `0x00281300` -> PAL `0x00281F40` (`insn:name`).

### DATA.BIN

Not a map product. Sectors are counted from the start of `TEKKEN/DATA.BIN` (`tools/databin.py:4-28`).

| | PAL | US |
|---|---|---|
| table VA | `0x00314360` | `0x00313380` |
| rows | 1496 | 1122 |
| ISO LBN | 1236 | 401 |
| size | 2694412288 | 2695536640 |
| override | `runtime/tekken4_overrides.cpp:81-82` | `H:\tekken4-recomp_usa\runtime\tekken4_overrides.cpp:73-74` |

The table VA pair is a code reference (`data OK file table` in the check, `code-ref:abs`, n=13). LBN, size, and row count are not. The US override comment says the table is at `0x3133e0` (`H:\tekken4-recomp_usa\runtime\tekken4_overrides.cpp:66`). That address is row 6, not the base (`tools/databin.py:24-26`). Use `0x00313380`. Row counts 1496 and 1122 are that tool's table walk, not a constant in the override. US loose `game/disc/TEKKEN/DATA.BIN` is 2695536640 bytes, SHA-1 `5ab0b8ff65335bb13c63e222bee2ee6a890fb0fe`. PAL's loose `DATA.BIN` is not in the tree (the ISO is the source). US has no `DATA2.BIN` file. PAL's driver looks up `\TEKKEN\DATA2.BIN`; status records LBN 1316867 (`docs/status.md:92-95`, `patches/35-ps2xIOP-cdsearchfile-iso9660.patch:25-26`). This session did not re-walk the PAL ISO.

Archive contents differ. `logs/grok/databin-notes.md:33-36`: identical hashes 342, PAL-only 533, US-only 140, among loadable files PAL 1064 (29 bad checksums) and US 663 (0 bad).

VU1 micro memory is the same file on both trees: `vu1_62802e7b8abf4848.bin`, 16384 bytes, SHA-1 `0fd1ba656b8e3c3ad372d9ced8a1edb343e644ea`. One native-VU1 build input.

### Generated from one source + the map

| Data | Source | Tool | Needs the other ELF |
|---|---|---|---|
| function pairs | both `function_map.csv` | `pal_us_map.py csv` (already `config/pal_us_map.csv`) | no |
| `[patches]` addresses | PAL `[patches]` | `pal_us_map.py patches` | no (csv + the address) |
| `[patches]` values, `switch` names | PAL toml | copied | no |
| jump-table shape | PAL `[jump_tables]` | `translate_jump_tables.py` | yes, to find the pointer run |
| stub addresses | PAL stub list + map | pair by unique name, or by order when repeated | no |
| override EE addresses | PAL `runtime/*.cpp` literals | `pal_us_map.py overrides` | yes for data addresses |
| DATA.BIN LBN, size, N, DATA2 | that disc's ISO9660 + the id-walk in `tools/databin.py` | not the map | the ISO |
| generated C++ | that ELF | `ps2_recomp` | the ELF |
| the 54/56 unmapped functions | that ELF's Ghidra | none | stay per disc |
| the 13 `run1`/`run2` rows | map | do not auto-apply below conf 0.85 | hand check |

Low rows (conf 0.42 or 0.62): `0x00249658`, `0x00249668`, `0x002497A0`, `0x002497F8` (also struct-diverged), `0x0024C580`, `0x00280C30`, `0x00281A80`, `0x00289760`, `0x00293208`, `0x0029F030`, `0x0029F0B0`, `0x002A7970`, `0x002A79B0`.

## 2. One runtime

`patches/01` through `32` are byte-identical across the two trees (body from the first `diff --git` line, both sizes equal). `33` through `42` share a number and nothing else. US continues `43` through `56`. `patches/debug/` is not applied. `tools/build_runtime.cmd` applies `patches\*.patch` in name order, so the number is the order.

### Same fix, written twice

Music is three mechanisms. Each disc fixed them on its own fork. Applying both patches to one tree conflicts. Take one implementation.

**ISO9660 search.** Both replace the hard-coded `LBN 1236` / size `2694412288` answer for `TEKKEN/DATA.BIN`.

- PAL 35 walks the image inside `iop_cdvd.cpp` (`patches/35-ps2xIOP-cdsearchfile-iso9660.patch:23-148`). `cdvd` only.
- US 36 does the same lookup in `iop_iso9660.h` and uses it from `cdvd` and from `ioman` (`H:\tekken4-recomp_usa\patches\36-ps2xIOP-cdvd-ioman-search-files-in-the-real-image.patch:4-21`, the deleted `1236u` at lines 70-75). Its commit text: the virtual ISO had DATA.BIN at LBN 1106, and 1106-401=705, which is the "705 sectors" figure. The PAL constant 1236 is a second wrong answer (1236-401=835). US has no DATA2.BIN; the walker still has to answer `\TEKKEN\DATA2.BIN` on PAL.

Take US 36's shared walker (it covers `ioman` and any name, including DATA2). Do not also apply PAL 35.

**SIF user commands.** EE `sceSifSendCmd` passes the extra payload in `$t0`/`$t1`. The IOP HLE dropped `sceSifAddCmdHandler`.

- PAL 36: `RPC.cpp`, `iop_rpc.cpp` cases 8 and 10, `deliverEeUserSifCmd` (`patches/36-ps2xIOP-spu2-irq-sif-user-cmds.patch:318-374`, `486`). No `SIF.cpp`.
- US 33: the same payload bug, and the `SIF.cpp` stub now calls `ps2_syscalls::sceSifSendCmd` (`H:\tekken4-recomp_usa\patches\33-...patch:7-10`, `279-280`). `docs/MUSIC_FIX.md:22-30` is the US write-up. PAL status `docs/status.md:172-176` is the PAL one.

Take both halves as one patch: PAL 36's IOP user-command path plus US 33's stub delegation. The two `sceSifSendCmd` copies in the stub list are why the stub file matters.

**SPU2 IRQ.** zsiopdrv refills BGM from libsd's handler. Two stages exist.

- US 34 latches IRQA, clears the core IRQ enable with `setCoreAttr(4|core, 0)`, calls the handler once per mixer advance (`H:\tekken4-recomp_usa\patches\34-...patch:109-146`). It does not run ready IOP threads until the driver re-arms.
- PAL 36 first left the enable bit set (`patches/36` lines 108-111 of the sound-engine hunk, the "Leave SD_ENABLE_IRQ set" comment). PAL 41 removes that. Sony libsd clears ATTR bit 6 before the user handler, and `serviceSpu2Irq` runs ready threads until the core is re-armed (`patches/41-ps2xIOP-spu2-irq-libsd-ack.patch:15-23`, `docs/status.md:117-121`).

Take PAL 41. Do not apply US 34, and do not stop at PAL 36 without 41. US 54 skips `drainOutput` when the mixer did not advance and still calls `serviceSpu2Irq` (`H:\tekken4-recomp_usa\patches\54-...patch:6-11`). Keep that call when 54 is rebased onto 41's function.

### Complementary

PAL only, host or recompiler, not on the US tree:

| PAL | What | Guest determinism |
|---|---|---|
| 33 | HUD (`patches/33-ps2xRuntime-hud.patch`) | no |
| 34 | indexed coverage hash, Arena 60 fps (`patches/34-ps2xRuntime-gs-indexed-coverage-hash.patch`, `docs/status.md:73-81`) | no |
| 37 | F2 settings (`patches/37-ps2xRuntime-settings-window.patch`) | no |
| 38 | internal resolution 1x-4x (`patches/38-ps2xRuntime-internal-resolution.patch`) | no |
| 39 | `PS2_SWITCH` + widescreen (`patches/39-ps2xRecomp-switch-patches-widescreen.patch`) | yes, the six words. Both peers must use the same switch (`docs/HANDOFF_WISHIN.md:36-38`) |
| 40 | filter / FXAA / sharpen (`patches/40-ps2xRuntime-filtering-fxaa-sharpen.patch`) | no |
| 42 | controls (`patches/42-ps2xRuntime-controls.patch`) | pad word only |

US only:

| US | What | Guest determinism |
|---|---|---|
| 35 | env-gated sound debug | no, when off |
| 37-41 | rollback snapshots, resim cuts, IOP in the snapshot | the snapshot must match the live frame |
| 42 | netplay hooks (schedule shift, host pad) | yes |
| 43, 47 | perf counters | no |
| 44-46, 48-50, 52, 53, 56 | GS/GL perf and present | retest. 49 changes how the window draws the GS picture |
| 51 | `TEKKEN4_SOUND_TRACE` read once | no |
| 54 | skip empty audio drain | patch text says output identical; rebase onto PAL 41 |
| 55 | VU1 rounding via MXCSR | patch text says state hashes matched for 5940 frames. Retest on PAL. Not a guest-format change |

Rollback and netplay are the part PAL does not have. Graphics, HUD, and controls are the part US does not have. Music is the overlap above, not a third feature.

### Files both sides edit after patch 32

14 files. A concatenated series does not apply.

| File | PAL | US |
|---|---|---|
| `ps2xIOP/include/ps2x/iop/iop_host.h` | 36 | 33 |
| `sound_engine.cpp` | 36, 41 | 34, 35, 41, 51 |
| `sound_engine.h` | 36, 41 | 34, 41, 54 |
| `iop_cdvd.cpp` | 35 | 36, 41 |
| `iop_emulator.cpp` | 36, 41 | 33, 34, 35, 41, 54 |
| `iop_emulator.h` | 36 | 41 |
| `iop_rpc.cpp` | 36 | 35 |
| `iop_rpc.h` | 36 | 41 |
| `ps2xRuntime/CMakeLists.txt` | 33, 37, 39 | 37, 42, 43, 46 |
| `Kernel/Stubs/Pad.cpp` | 42 | 37, 42 |
| `Kernel/Syscalls/RPC.cpp` | 36 | 33, 39 |
| `gs/gpu/gs_hw_backend.cpp` | 34, 38, 40 | 43, 45, 46, 48, 50, 52, 53, 56 |
| `gs/gs_frontend.cpp` | 38 | 38, 43, 49 |
| `ps2_runtime.cpp` | 33, 37, 38, 40 | 38, 40, 43, 49 |

US numbers on the right are the US patch numbers, not the merged numbers.

### Merged order

New numbers. Base is upstream `eb8688b` plus current `01-32` (already one commit series on `H:\tekken4-fork-ps2recomp` branch `gs-gl`).

| New | From | Note |
|---|---|---|
| 01-32 | either tree | identical |
| 33 | US 36 | ISO9660 walker. Supersedes PAL 35 |
| 34 | PAL 36 SIF/IOP part + US 33 `SIF.cpp` | one SIF patch. Drop PAL 36's "leave IRQ enable set" |
| 35 | PAL 41 | SPU2 IRQ ack + thread pump. Supersedes US 34 |
| 36 | US 35 | debug, env off by default |
| 37 | PAL 33 | HUD |
| 38 | PAL 34 | indexed hash |
| 39 | PAL 37 | F2 settings |
| 40 | PAL 38 | internal resolution. Touches `gs_frontend.cpp` before rollback cuts |
| 41 | PAL 39 | switchable patches. `[patches]` stays in the per-disc toml |
| 42 | PAL 40 | filter / FXAA / sharpen |
| 43 | PAL 42 | controls. Lands before rollback's `Pad.cpp` edits |
| 44-48 | US 37-41 | rollback, rebased onto 33-35 and onto 43's pad |
| 49 | US 42 | netplay hooks, rebased onto 43's pad |
| 50-63 | US 43-56 | perf / GL, rebased onto 38-42's `gs_hw_backend.cpp` |

`gs_hw_backend.cpp` is the large rebase (PAL 34/38/40 against US 43/45/46/48/50/52/53/56). `Pad.cpp` is the other one (controls, then rollback, then netplay).

## 3. Overrides written once

`applyMatching` already runs every descriptor whose ELF name, entry, and CRC match. PAL and US descriptors can sit in one binary. The guest functions they call cannot: those symbols come from that disc's `generated/`.

`tools/stage_generated.cmd:14` copies `runtime\*_overrides.cpp` with no `/S`. `runtime/pal/` is not in the build. `H:\tekken4-recomp_usa\runtime\pal\tekken4_camera_overrides.cpp` is registered as `SLUS_203.28` / `0xB975F704` (`:869`) but its addresses are still the PAL ones (`kBasis = 0x002D27D0` at line 32, the same table as `runtime/tekken4_camera_overrides.cpp`). Do not treat that file as a port. US `stage_generated.cmd` also copies `tekken4_net*.cpp/.h` (line 19). PAL's script does not, because PAL has no net files.

`pal_us_map.py check` on PAL `runtime/tekken4_overrides.cpp`: 66 literals mapped, 20 unmapped. The 20 are lengths, IOP ids (`0x12345`, `0x4f4f4`), masks, and the CRC immediate `0xBEFFF97A`. Every EE address in that file has a US address.

Constants already ported by hand match the map (this session, `pal_us_map.py addr --from us`):

| Use | PAL | US | conf |
|---|---|---|---|
| `sceSifSendCmd` | `0x00281F40` | `0x00281300` | 0.97 name |
| `rand` | `0x002A3178` | `0x002A2538` | 0.97 name |
| `srand` | `0x002A3168` | `0x002A2528` | 0.90 |
| disc-done flag | `0x0035A128` | `0x00357A28` | 0.99 gp |
| movie result | `0x0035A12C` | `0x00357A2C` | 0.97 gp |
| reent | `0x003059D4` | `0x00304B94` | 0.99 |
| file table | `0x00314360` | `0x00313380` | 0.99 |
| pad | `0x00358754` | `0x00356054` | 0.99 |
| IPU image step | `0x00227BE8` | `0x002272A0` | 0.96 |
| movie nodata | `0x002281D0` | `0x00227888` | 0.96 |
| VIF1 end | `0x00233430` | `0x00232AB0` | 0.96 |
| rollback idle PC | `0x0022AAD0` | `0x0022A150` | 0.96 |

The idle PC is `setIdleLoopPcs({0x0022a150})` (`H:\tekken4-recomp_usa\runtime\tekken4_rollback_overrides.cpp:2040`). It maps into `FUN_0022aac0+0x10`, not into the struct-diverged function at `0x0022a3c8`. `loggedSrand` is `0x002A2528` (line 2032), which is PAL `kSrand` (`runtime/tekken4_testseed_overrides.cpp:17`).

`kDataBinLbn` / `kDataBinSize` stay hand-written per disc. The US file still says a read past the end continues into DATA2 (`tekken4_overrides.cpp:136`). That sentence was copied from PAL. The US size is the US DATA.BIN, and there is no US DATA2 file.

Shape to compile twice, once per generated header:

```cpp
struct DiscAddrs {
    uint32_t sifSendCmd, rand, srand, reent, discDone, movieResult;
    uint32_t ipuImages, movieNodata, vif1End;
    uint32_t idleLoopPc;
    uint32_t dataBinLbn;
    uint64_t dataBinSize;
    bool hasData2;
};
```

PAL is the source of the logic. `python -I tools/pal_us_map.py overrides runtime/tekken4_overrides.cpp` prints the US column. Reject a hit whose function is in `struct_diverged` at or past the mismatch, or whose conf is under 0.85. Ship `disc_addrs_pal.inc` and `disc_addrs_us.inc`. One `PS2_REGISTER_GAME_OVERRIDE` per disc calls the same `apply(const DiscAddrs &)`.

Struct offsets (`cam+0xF08`, `reent+88`) are not addresses. The map does not move them. They stay if the struct layout is the same. That is true for reent+88 (both sides use it for the LCG seed: PAL `docs/status.md:282-286`, US `docs/ROLLBACK_PLAN.md:159`). It is not proven for every struct.

## 4. Netplay across the two discs

A PAL player and a US player cannot meet on this protocol. Same-disc online is the goal that the code can support.

The transport is game-agnostic (`H:\tekken4-recomp_usa\runtime\tekken4_net.h:1-7`): frames, pad words, hashes. `kNetVersion = 1` (line 15). HELLO carries a build id. A different id is `build_mismatch` (`tekken4_net.cpp:512-521`). The id is `SHA-1("t4dr-build:<elf_sha1>:<code_id>:<net>")` first 16 hex digits (`tools/t4_buildid.py:11`). The two ELF SHA-1s differ, so the ids differ even if `code_id` and `net` match. That refusal is the right behavior. Do not strip `elf_sha1` out to force a handshake.

The hash those peers would compare is the whole machine, not a character struct. `netHashOf` mixes RDRAM, scratchpad, VU0 data, the IOP (RAM, SPU2 RAM, CPU/kernel), and the EE cycle (`tekken4_rollback_overrides.cpp:1005-1034`). VU1 data and GS state are left out. `kBuiltinMasks` is empty (lines 121-122).

Those images are not the same machine:

- Code: 4616 functions sit at different addresses. 54 PAL functions and 56 US functions have no partner. Four partners diverge in opcode. Immediates differ even when the skeleton matches. `.text` ends at `0x002A91F8` (PAL `CLAUDE.md`) and `0x002A85B8` (US `CLAUDE.md`).
- Data: `_impure_ptr` `0x003059D4` vs `0x00304B94` (delta `0xE40`). The file table delta is `0xFE0`. One subtract does not slide a snapshot.
- Assets: DATA.BIN hashes are not the same set (section 1). PAL streams music from DATA2.BIN. US has one DATA.BIN.
- Boot: `VMODE = PAL` plus a PAL60 menu, vs `VMODE = NTSC` and no PAL60 menu (US `CLAUDE.md:19`). A lockstep from frame 0 diverges at the first different instruction. PAL60 is a guest choice on PAL only. A PAL-PAL match has to pin it the way widescreen is pinned, or the two boots take different paths.
- Widescreen: the six words change guest code. `docs/HANDOFF_WISHIN.md:36-38`. Same disc, different switch, is already a desync. The lobby forces one value.
- `code_id` does not hash the compiler (`docs/HANDOFF_WISHIN.md:31-32`, `t4_buildid.py:68-81`). Two MSVC versions can share an id and still desync. Fix that before PAL netplay, on the US id too.

US pair evidence stays US-only: 12000 frames, 399 hashes, 0 mismatches (`docs/HANDOFF_WISHIN.md:25-27`). Nothing in this tree has run that loop on PAL. `docs/ROLLBACK_PLAN.md:73` mentions a PAL mask at `0x1cca000`. The code's mask list is empty. The plan was written against PAL addresses; the implementation landed on US.

A later "rules" match (translated gameplay hash, different ELFs) is a new protocol (`kNetVersion` bump) and needs proof the fight state is the same schema. That proof is not in the maps. The 54 unmapped functions and the archive diff are evidence against it. Do not build it in the first migration.

"Online on both" means: the same runtime, PAL exe vs PAL exe, US exe vs US exe. US is the disc that already has the loop. HANDOFF says PAL is too heavy to be the online focus (`docs/HANDOFF_WISHIN.md:15`). The measured fps note in status is the other way: PAL fights hold 60, US seconds jump 44-75 (`docs/status.md:1142-1144`). This design does not treat that sentence as a bandwidth measurement. Porting netplay to PAL is still in the plan, after the US loop still passes on the merged runtime.

## 5. Migration

Each step is one test. S is mechanical, one session. M is one subsystem and a game run. L is a rebase across the 14 shared files, or the first PAL netplay run. Claude creates the branch and commits. Nobody merges `us-iso` into `master`.

| Step | Effort | Do | Test |
|---|---|---|---|
| 1 | S | `config/discs.toml`: ELF name, entry, CRC32, SHA-1, LBN, size, `hasData2` | `python -I` recomputes SHA-1 and CRC32 of both ELFs and compares to the toml. Already matches section 1 |
| 2 | S | New branch off the PAL fork at the `01-32` tip. Do not replay `33+` yet | `patches/01-32` body hash equals both trees |
| 3 | S | Generate US `[patches]` (the six words only) into the US toml with `pal_us_map.py patches` | `pal_us_map.py check` stays `check_fail=0`. `listed_pairs 7/7`. The OFF4 word is absent |
| 4 | S | Rebuild US `[jump_tables]` with `translate_jump_tables.py` and diff against the current 40 | diff empty, or each mismatch explained. Not done this session |
| 5 | M | Patch 33: US ISO9660 walker, drop PAL 35 | PAL search: DATA.BIN LBN 1236, DATA2.BIN found. US search: DATA.BIN LBN 401. `ioman` `cdrom0:` uses the same walker |
| 6 | M | Patch 34+35: one SIF path, PAL 41 IRQ | PAL music continuous (the `logs/spu2irq_claude` bar). US BGM path from `docs/MUSIC_FIX.md` still refills. Tests of the fork |
| 7 | M | Patches 36-43: PAL HUD, hash, F2, resolution, switch, filter, controls, onto that tree | PAL fixed fight 60 fps, Arena 60, widescreen off by default, controls remap. US fight still reaches 60 with sound. `ps2x_tests` |
| 8 | S | `disc_addrs_*.inc` from `pal_us_map.py overrides`. One apply function. Two registers | Every EE literal in `tekken4_overrides.cpp` is in the inc or on the unmapped-constant list. No hit in `struct_diverged`. US idle `0x22A150` and srand `0x2A2528` are in the rollback inc |
| 9 | L | Rebase US rollback 37-41 and netplay 42 onto pad 43 and IRQ 35. Compile the US exe only | US `net_pair.ps1` 12000 frames, 0 hash mismatches, as in `docs/HANDOFF_WISHIN.md:25-27`. Build id changes. Both peers must use the new id |
| 10 | L | Rebase US 43-56 onto the new `gs_hw_backend.cpp`. Take 54's skip-drain and 55's MXCSR | PAL Arena 60 and a US fight. 55: one measure run, hashes unchanged vs the pre-55 US build, as that patch claims |
| 11 | M | `build_game.ps1 -Disc pal\|us` (or two configs) from one tree. Each run of `ps2_recomp` has one `input` | Two exes. Each applies one disc's overrides (`[game_overrides] applying` log). The other disc's CRC does not apply |
| 12 | L | PAL rollback self-test, then PAL pair, same disc, widescreen forced off, display mode pinned | PAL `TEKKEN4_RB_MODE=test` restored hashes match. Then a short pair, 0 mismatches. Not a PAL-vs-US pair |
| 13 | S | Put the compiler version into `code_id` | Two different cl.exe versions must not print the same id |

Steps 5-7 can land on the PAL fork as patches `43+` before the US rebase, if the US tree is left frozen until step 9. That matches "port by hand" in the handoff and keeps `us-iso` bootable. The super branch starts at step 9, when one series contains both.

Out of scope: one exe that contains both guests; a PAL-vs-US match; deleting either line; rewriting the 54 unmapped functions.

## Open

- Jump tables were counted, not regenerated.
- PAL DATA2 LBN 1316867 is from `docs/status.md:95`, not re-walked here.
- Whether any of the 54 unmapped PAL functions is the PAL60 menu is not identified.
- US 49 (shared present) and US 55 (MXCSR) need a PAL picture/hash check when they move. The patch texts claim no guest change. That claim is not re-run here.
- `code_id` vs compiler version is an open question to TheWishin (`docs/HANDOFF_WISHIN.md` section 5). The migration does it anyway before PAL netplay.
