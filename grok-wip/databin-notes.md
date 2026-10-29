# databin notes

## Table (this session)

- PAL loader FUN_002155d0 does not compare the file index to a length. It does `sll index,4` plus base `lui $s6,0x31; addiu ...,0x4360` = VA 0x314360. Accessors FUN_00215c78 / FUN_00215c90 (and the 0x215ca8 / 0x215cc8 sites) are the same address with no bounds check. FUN_00215270's `slti ...,0x30` is the 48-slot request queue, not N.
- A row is in the table while the u16 at +12 equals the row index. That run ends where the id jumps (PAL 1496 -> id 24972; US 1122 -> id 22644). After that, sector/size repeat as later .rodata (tool-scout's "no clean terminator").
- PAL: VA 0x314360, file off 0x195360, N=1496. key<0 = 349, key==index = 1147, key other = 0. Signed size<=0 (not loaded; bgtzl at 0x21575c): 432 (431 size 0 + entry 0 size -1).
- US: documented runtime comment 0x3133e0 is row 6 (same bytes as PAL row 7: size 12976 csum c89c988a). Walking the id field back lands on id 0 at VA 0x313380. US .text has addiu imm 0x3380 with lui 0x31 (proof: 15 sites, several rs with lui=49). N=1122. key<0=347, key==i=775, key other=0. size<=0: 459.
- Row: +0 u32 sector, +4 u32 size, +8 u32 checksum, +12 u16 index, +14 i16 key. Sectors are from the start of DATA.BIN.

## Decrypt and checksum (matches FUN_002155d0 0x215920-0x215a90)

- key < 0: leave bytes alone (bltz). Else for min(size>>2, 0x400) words: word = (~word + key) mod 2^32 (nor then addu).
- Then sum every size>>2 word mod 2^32 (trailing size%4 bytes ignored). OK iff sum XOR checksum == 0 (result 1, else -4).
- Proved this session, xor=0: PAL idx 3 (136640, key 3, larger than 4 KB), 5 (54272, key -1), 12, 13, 14, 17. US idx 2 (136640, key 2, same csum 6577b771 as PAL 3), 3 (1204352, key -1), 5, 6, 10. Alternate ~(w+key) on PAL 17 xors to 0x1e20, so it is not the game's formula.
- US loose game/disc/TEKKEN/DATA.BIN (2695536640) head 4096 equals US ISO LBN 401. PAL source is the project ISO, DATA.BIN LBN 1236, size 2694412288.

## Open

- Full-table bad count not run yet.
- 265 TIM2 / 46 MPEG-PS (tool-scout) are raw scans of DATA.BIN, including ciphertext. Recount after decrypt.

## Verify (manifests re-read 2026-10-29, python -I logs/grok/databin_summarize.py)

- PAL logs/databin/pal/manifest-2.json: rows 1496, loadable 1064, checksum-ok 1035, bad 29, seconds 27.397. coarse MPEG-ES 27, TIM2 1, data 1036 (27+1+1036=1064). Embedded TIM2 headers 456 in 165 ok files; MPEG-PS headers 47. Top fmt: data:02000000 235, data:05000000 167, data:11000000 115, data:d5003801 75, data:04000000 52, data:03000000 35, data:ff54494d 33, data:0f000000 28.
- US logs/databin/us/manifest.json: rows 1122, loadable 663, checksum-ok 663, bad 0, seconds 20.733. coarse MPEG-ES 27, TIM2 1, data 635. Embedded TIM2 headers 339 in 77 ok files; MPEG-PS headers 46. Top fmt: data:11000000 111, data:05000000 95, data:02000000 79, data:d5003801 75, data:ff54494d 33, MPEG-ES 27, data:04000000 20, data:0f000000 20.
- checksum_ok is null on non-loadable rows. PAL "not true" count 461 = 29 checksum + 432 size<=0. US 459 = size<=0. doc.bad is the checksum-fail count.
- logs/databin/pal/manifest.json is 0 bytes (first verify crashed before the body write). Do not delete. Loader skips it; manifest-2.json is the PAL data.
- PAL bad 29, every key -1, 29 distinct sha256, overlap with checksum-ok PAL hashes 0, overlap with PAL/US identical hashes 0. Indices: 2, 205-216, 218-232, 1495. For every one except 1495, size == (next bad sector - sector) * 2048. Idx 217 size 0 sector 394429 (same sector as 218), so 216's span reaches 218. Idx 1495 sector 864819 size 1308672 is the tail (no next). Idx 1 and idx 2 share sector 0 size 19068928 and checksum 0x91947e75; idx 1 key 1 checksum_ok, idx 2 key -1 sum 0x2490551b sha b7d7ed060d67235e fails. So idx 2 is the plain twin of an encrypted region that passes under key 1.
- Streaming is not the cause. python -I logs/grok/databin_streamcheck.py: 5242886-byte file key 7, one-shot sum 0x1c452403, process_file sum 0x1c452403, match. sum(array.array('I') of 1000000 x 0xFFFFFFFF) = 0xfff0bdc0 (nonzero). Game decrypt site: generated/FUN_002155d0_0x2155d0.cpp nor at 0x21595c then addu at 0x215960; bltz 0x21592c; window addiu 0x400 at 0x215938.
- The 29 stored checksums were not reduced to a second algorithm. They are not the word sum of the plain span.

## Compare (logs/databin/compare.json summary)

- pal_loadable 1064 bad 29 unique 875. us_loadable 663 bad 0 unique 482.
- identical_hashes 342 (pal rows 478, us rows 478). pal_only_hashes 533. us_only_hashes 140. same_size_no_shared_hash 69.
- 875 = 342+533. 482 = 342+140. Among checksum-ok PAL files, pal-only hashes = 533-29 = 504 (the 29 bad hashes sit in pal_only).
- Text table: logs/databin/compare.txt.

## TIM2

- python -I tools/databin_tim2.py wrote logs/databin/pal/tim2/. report.txt: 24 PNGs from indices 1385, 7, 1407, 1428. Directory listing: 26 PNGs. Contact logs/databin/pal/tim2/contact.png 25422 bytes, IHDR 656x656, magic 89 50 4e 47 0d 0a 1a 0a.
- Recomputed means: 00007.bin_00000010_0.png 881 bytes 96x96 mean 132,132,132. 01407.bin_00000020_0.png 1582 bytes 432x32 mean 255,255,255. 01407.bin_00000020_2.png 423 bytes 24x24 mean 52,77,79. White cells are pictures inside a blob that also has non-white cells.
- Tool-scout raw 265 TIM2 / 46 MPEG-PS is superseded by the post-decrypt header counts above. Header-valid is not a full picture parse.
- data:ff54494d is 33 files on each disc (bytes ff 54 49 4d). Not confirmed as a TIM2 prefix.

## CLI

- python -I tools/databin.py --help exit 0: list, verify, extract, compare. PAL VA 0x314360 N 1496 LBN 1236 size 2694412288. US VA 0x313380 N 1122 LBN 401 size 2695536640. Comment 0x3133e0 is US row 6.
- python -I tools/databin_tim2.py --help exit 0. sys.path insert is required under python -I.
- .gitignore line 22 ignores logs/; line 4 ignores *.bin. Extracts stay under logs/databin/.

## Late task 01a188bc

- The delayed `python -I tools/databin_tim2.py pal --count 24` (0.22s, exit 1) is the pre-fix run. Log call-1d15cac9: traceback at tools/databin_tim2.py:32 `import databin`, ModuleNotFoundError. Current file inserts sys.path before that import (line 33-34). `--help` this session imported databin and exited 0. It did not rewrite the PNGs.

