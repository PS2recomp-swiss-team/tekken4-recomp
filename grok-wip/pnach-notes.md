# pnach notes (2026-10-29)

Tool: `tools/pnach_to_switch.py`. Docs: `docs/pnach.md`. Config not edited. US tree not edited. No recompile, no `PS2X_HOST_SHOTS`. `tools/pal_us_map.py` absent (`os.path.isfile` false). `external/wt-pnach` exists; unused because step 4 was not shipped.

## Proof

`python -I logs/grok/pnach_proof.py` exit 0.

- PAL: `PAL_MATCH True` n=6 against live `config/ghidra_export.toml` `[patches]` widescreen entries. Flags contain `0x00292424` `sceIpuStopDMA` and `0x00292628` `sceIpuSync`. Stdout `logs/grok/pnach-pal.txt`. CRC `2251E14D` matches `SCES_508.78`.
- `0x00292628` flag is three reasons: stub `sceIpuSync`, delay slot of `0x00292624`, ELF already `0x00000000`. Function range `config/function_map.csv:4367` `0x002925E8`-`0x00292650`. Stop range line 4365 `0x002923B0`-`0x00292494`.
- US: 6 accepted, CRC `833FE0A4` matches `SLUS_203.28` via `--config H:\tekken4-recomp_usa\config\ghidra_export.toml` (read). Block in `logs/grok/pnach-us.txt` and `docs/pnach.md`. IPU: `0x002917E4` inside `sceIpuStopDMA` `0x00291770`-`0x00291854` (`H:\tekken4-recomp_usa\config\function_map.csv:4368`, stub toml line 168); `0x002919E4` inside `sceIpuSync` `0x002919A8`-`0x00291A10` (csv line 4370, stub toml line 170). US toml grep: no `[patches]`, no `switch =`.
- F48 strict (no `--ignore-crc`) exit 2: name `F48F994A` vs ELF `2251E14D`.
- F48 `--ignore-crc --section No-Interlacing`: accepted only `0x001E2254` = `0x24020002` switch `no_interlace`. Flagged `gsinterlacemode=1`, `0x0022B138` delay slot of jump `0x0022B134`, `0x001EDC24` delay slot of branch `0x001EDC20`. `logs/grok/pnach-f48.txt`.

## No-Interlacing (not added)

`generated/FUN_0022b0c8_0x22b0c8.cpp:126-133`: `jal FUN_0022af18`, delay slot `addiu a1, zero, 4`, caller sets `a0=0` at line 123-125.

`generated/FUN_0022af18_0x22af18.cpp`: table `fp=0x32` + `0x1270` = `0x00321270`, stride 6 (lines 106-127). `s5=a1`. Row byte0 -> interlace arg, byte1 -> omode (`s1`). `jal sceGsResetGraph` `0x28A9D0` at lines 252-259 with `a0=0`, `a3=1` (ffmode). Height: `s1==3` -> `a3=0x100` (lines 306-395); `s1==0x50` -> `a3=0x1C0` plus `t0=0x28` `t1=0x10` (lines 341-409); `s1<4` otherwise -> `a3=0xE0` (lines 322-372).

Table (`python -I logs/grok/pnach_table.py`, section `.rodata`, CRC `2251E14D`): row4 `01030200d200` interlace=1 omode=0x03 half=0x0002; row6 `00500200d200` interlace=0 omode=0x50 half=0x0002. SDK names: `GS_MODE_NTSC=0x02`, next enumerator `GS_MODE_PAL` (=0x03), `GS_MODE_DTV_480P=0x50` (https://raw.githubusercontent.com/ps2dev/ps2sdk/master/ee/libgs/include/libgs.h lines 56-59). `GS_NONINTERLACED=0`, `GS_FFMD_FRAME=1` (same file lines 37, 43).

`sceGsResetGraph` is stub `config/ghidra_export.toml:153` `sceGsResetGraph@0x0028A9D0`. Handler `GS.cpp:786-806`: `smode2 = (interlace & 1) | ((ffmode & 1) << 1)`. Row4 -> SMODE2 3. Row6 -> SMODE2 2.

Bob: `gs_hw_backend.cpp:3155-3168`. `interlacedFrame` = SMODE2 bit0 and bit1. `fieldOffset = lround(scale)` when interlaced frame and `displayField==1`, else 0. `lineRepeat` includes `* 2` only when `interlacedFrame`. Status: `docs/status.md:170` (deinterlace follow-up), `:843-851` (field copy at vsync `0x22aaf8`, odd field one line lower).

`0x001E2254` store: `generated/FUN_001e2210_0x1e2210.cpp:100-112` writes `0x36E9ED`. Walk of `generated/*.cpp`: that literal only in this file (1 hit).

`0x001EDC24`: `generated/FUN_001edbf0_0x1edbf0.cpp:88-126`, delay slot, then `sb v0, 0(s0)` (2 -> 9). Other path stores 8. Not SMODE2.

PCSX2 `gsinterlacemode`: Config.h enum Automatic=0 Off=1 (saved fetch `web_fetch/2.txt:291-303`). Applied only if user mode is Automatic (`web_fetch/1.txt:831-836`, parser `:986-996`). No `gsinterlacemode` / `InterlaceMode` reader under `ps2xRuntime`.

F48 widescreen `--ignore-crc`: six accepts; `0x0018D408` value `0x3C0143D6` not our `0x3C0143D5`. No IPU flags. Not applied. Order is that file's source order (address order differs from PAL config).

## Emitter

`function_emitter.cpp:132` takes the delay-slot path and never reads `switchName` on the branch word. `:155-156` throws if the delay slot has a switch. `:208-213` throws if the patched word is branch/jump/hasDelaySlot. `ps2_recompiler.cpp:2141-2173`: non-switch patches replace `rawInstruction`; switch patches only set `switchName` and `switchRaw`.

## Scratch left for the user (not deleted)

`logs/grok/pnach_proof.py`, `pnach_table.py`, `pnach-pal.txt`, `pnach-pal.err`, `pnach-us.txt`, `pnach-f48.txt`. Older `pnach_dump.py` / `pnach_look.py` if still present were not removed.
