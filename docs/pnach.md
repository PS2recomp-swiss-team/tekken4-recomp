# PCSX2 .pnach to runtime switches

`tools/pnach_to_switch.py` reads a PCSX2 `.pnach` (or one entry of a zip) and prints a `[patches]` block in the form the recompiler already consumes: `{ address, value, switch = "<name>" }`. Patch 39 emits `if (PS2_SWITCH("<name>")) { patched } else { original }`. A switch is stored beside the original word (`ps2_recompiler.cpp` records `switchName` / `switchRaw` and does not replace the decoded instruction). The emitter rejects a switch whose patched word is a branch or jump, and it throws if the switch sits in a delay slot (`function_emitter.cpp`).

## Use

From the repo root. `python -I`. The default `--config` is `config/ghidra_export.toml`: its `input` is the ELF, its `ghidra_output` is the function map, and its `stubs` / `skip` lists decide what is recompiled.

```
python -I tools/pnach_to_switch.py --entry SCES-50878_2251E14D.pnach external/pcsx2/resources/patches.zip
python -I tools/pnach_to_switch.py --elf game/disc/SCES_508.78 game.pnach
python -I tools/pnach_to_switch.py --section "No-Interlacing" --ignore-crc --entry SCES-50878_F48F994A.pnach external/pcsx2/resources/patches.zip
```

The CRC in the file name (PCSX2's XOR of every little-endian ELF word) must match the ELF. A mismatch exits 2. `--ignore-crc` still classifies, and the header says the CRCs differ: same addresses on a different build are not guaranteed.

Each `[section]` is one switch. Aliases: `Widescreen 16:9` -> `widescreen`, `No-Interlacing` -> `no_interlace`. Any other title is a lowercase slug. Words are emitted in source-line order, not address order. CodeBreaker 8/16/32-bit writes are merged into the full instruction word (the vendored `tools/console-skill/console-mod/pnach.py`).

Flagged words are comments, not entries. Exit 0 either way. A word is flagged when:

- it is outside the function map, or the function is in `[general].skip` (not recompiled)
- the function is a configured stub whose name resolves in `PS2_STUB_LIST` / `PS2_SYSCALL_LIST` (the runtime replaces it; a configured stub with no handler is still recompiled and is not flagged)
- the original word is a branch or jump (the emitter emits that transfer and does not apply a switch on it)
- the patched word is a branch or jump (the emitter throws)
- the word is the delay slot of the previous instruction inside the same function (the emitter throws)
- the ELF already holds the patched value
- the line is `gsaspectratio` or `gsinterlacemode` (a PCSX2 display setting, not an EE write)

`author`, `description`, and `comment` lines are ignored. A missing `ps2_call_list.h` makes every configured stub look replaced; the header says so.

## PAL widescreen proof

`SCES-50878_2251E14D.pnach` against `game/disc/SCES_508.78` (CRC `2251E14D` matches). The tool's six accepted lines are the six `switch = "widescreen"` entries in `config/ghidra_export.toml`, same addresses, same values, same order (`logs/grok/pnach-pal.txt`, compared by `logs/grok/pnach_proof.py`):

```
{ address = "0x002177E0", value = "0x3C013F40", switch = "widescreen" },
{ address = "0x001F7028", value = "0x3C013F40", switch = "widescreen" },
{ address = "0x0018D408", value = "0x3C0143D5", switch = "widescreen" },
{ address = "0x002015D4", value = "0x3C013F40", switch = "widescreen" },
{ address = "0x002015D8", value = "0x44810000", switch = "widescreen" },
{ address = "0x002015E4", value = "0x46006303", switch = "widescreen" },
```

The other two EE words are flagged, which is why the hand port skipped them:

- `0x00292424` is inside `sceIpuStopDMA` (`0x002923B0`-`0x00292494`). The runtime stub replaces that function, and the original word is a branch (`bne`).
- `0x00292628` is inside `sceIpuSync` (`0x002925E8`-`0x00292650`). The runtime stub replaces it, it is the delay slot of the branch at `0x00292624`, and the ELF already holds `0x00000000` (the pnach word is a no-op on this disc).

`gsaspectratio=16:9` is flagged as a PCSX2 display setting. The trailing comment on `0x002015E4` says `cop1` because the vendored disassembler does not name that COP1 function; the value is the config's `0x46006303` (`div.s`, status session 7).

## US widescreen (not applied)

`SLUS-20328_833FE0A4.pnach` against the US tree's ELF `SLUS_203.28` (CRC `833FE0A4` matches) and that tree's function map. Read only. Nothing under `H:\tekken4-recomp_usa` was written. That config has no `[patches]` section. This block is for the US project once its recompiler has patch 39's switch support. Do not paste it into the PAL config: `0x0018D408` is the same address as PAL, the other five are not.

```
[patches]
instructions = [
  { address = "0x00216EA0", value = "0x3C013F40", switch = "widescreen" },
  { address = "0x001F6BF8", value = "0x3C013F40", switch = "widescreen" },
  { address = "0x0018D408", value = "0x3C0143D5", switch = "widescreen" },
  { address = "0x00200D84", value = "0x3C013F40", switch = "widescreen" },
  { address = "0x00200D88", value = "0x44810000", switch = "widescreen" },
  { address = "0x00200D94", value = "0x46006303", switch = "widescreen" },
]
```

Flagged, same reason as PAL: `0x002917E4` is a branch inside `sceIpuStopDMA` (`0x00291770`-`0x00291854`, stub at `0x00291770`); `0x002919E4` is a branch inside `sceIpuSync` (`0x002919A8`-`0x00291A10`, stub at `0x002919A8`). Full run: `logs/grok/pnach-us.txt`.

`tools/pal_us_map.py` was not on disk. It was not required: the US file was classified against the US ELF directly.

## F48F994A No-Interlacing (not added)

`SCES-50878_F48F994A.pnach` is a different PAL build (name CRC `F48F994A`, our v2.00 ELF is `2251E14D`). Without `--ignore-crc` the tool exits 2. With `--ignore-crc` the three code sites still decode on v2.00, and the original words are the ones in `generated/`:

| address | original on v2.00 | patched | tool |
| --- | --- | --- | --- |
| `0x0022B138` | `addiu a1, zero, 4` | `addiu a1, zero, 6` | delay slot of `jal FUN_0022af18` at `0x0022B134` |
| `0x001EDC24` | `addiu v0, zero, 2` | `addiu v0, zero, 9` | delay slot of `b` at `0x001EDC20` |
| `0x001E2254` | `addiu v0, zero, 1` | `addiu v0, zero, 2` | accepted as `switch = "no_interlace"` |

`gsinterlacemode=1` is PCSX2's `GSInterlaceMode::Off` (enum `Automatic=0`, `Off=1` in PCSX2 v2.8.2 `Config.h`). PCSX2 applies it only when the user's interlace mode is Automatic. This runtime never reads that setting. The one-row bob is `fieldOffset = round(scale)` in `gs_hw_backend.cpp` when `SMODE2` bit0 and bit1 are both set and the displayed field is odd. At internal scale 1 the offset is 1; above 1 it is `scale` present pixels (`docs/status.md` session 7 follow-up and the field-offset section).

What the three words actually do on v2.00:

- `FUN_0022b0c8` calls `FUN_0022af18(a0=0, a1=4)`. `a1` is the row index. The table is `.rodata` at `0x00321270`, stride 6. Row 4 is `01 03 02 00 d2 00`: interlace 1, omode `0x03` (`GS_MODE_PAL`). Row 6 is `00 50 02 00 d2 00`: interlace 0, omode `0x50` (`GS_MODE_DTV_480P`). `FUN_0022af18` calls the `sceGsResetGraph` stub with `a0=0`, `a1=row byte0`, `a2=row byte1`, `a3=1` (FFMD frame, not patched). The stub writes `SMODE2 = (interlace & 1) | ((ffmode & 1) << 1)`. Row 4 gives `SMODE2 = 3` (interlaced frame): `interlacedFrame` is true, so the odd field is shifted and lines are doubled. Row 6 gives `SMODE2 = 2` (frame, interlace clear): `fieldOffset` stays 0 and the extra line repeat drops. The same function then picks a height from omode: `s1 == 3` -> `0x100` (256), `s1 == 0x50` -> `0x1C0` (448). So the delay-slot word is the one that would remove the bob, and it also switches the boot mode from interlaced PAL to 480p and the height argument from 256 to 448.
- `0x001EDC24` stores 9 instead of 2 at a struct byte on the path where another byte is nonzero. It does not write `SMODE2`. It is a delay slot, so it cannot be a switch.
- `0x001E2254` is the only word the emitter can switch. It stores 2 instead of 1 at guest `0x0036E9ED` (`sb` after `lui s0, 0x37` / `addiu s0, s0, -0x1648`). A scan of `generated/*.cpp` found that address only in this writer. It does not write `SMODE2`.

Not cheap and not safe, so `config/ghidra_export.toml` was not given a `no_interlace` switch, and nothing was recompiled or shot:

- The bob-removing word is a delay slot. Shipping it needs a change in `function_emitter.cpp`, which this task does not own. The exact word, if that emitter change exists later, is `{ address = "0x0022B138", value = "0x24050006", switch = "no_interlace" }`.
- That word is a video-mode change (omode `0x03` -> `0x50`, height 256 -> 448), not a one-pixel present offset. The game's field copy (`docs/status.md` field-offset section, vsync handler `0x22aaf8`) was not re-tested against 480p. A later GIF packet that sets `SMODE2` back to 3 was not ruled out.
- Adding only `0x001E2254` would not clear the interlaced bit.

The same file's widescreen group, classified with `--ignore-crc` against v2.00, accepts the same six addresses as our patch except `0x0018D408` is `0x3C0143D6` (immediate `0x43D6`) rather than our `0x3C0143D5` (`0x43D5`). It has no IPU words. It was not applied. Source order in that file is not the PAL config order.
