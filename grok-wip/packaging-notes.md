# packaging notes (2026-10-29)

Package: logs/package/tekken4-pal-20261029-183036 + sibling zip 31740885 bytes.
Guard this session: fixture logs/grok/packaging-guard-fixture-20261029-182909 refused 15 ok 2; package refused 0 ok 34.
Zip name scan: zip_entries 34 zip_bad 0 (logs/grok/packaging-zip-scan.ps1). Content guard is the folder scan.
exe SHA1 EB6351C52ACEEBEAA5F6C581091302920A3CA0C1 both package and H:\tekken4-fork-ps2recomp\out\runtime\ps2xRuntime\ps2EntryRunner.exe (49392128 bytes).
Play.ps1 -PrintOnly: BOOT2 SCES_508.78 ELF_SHA1 24ced2b7f3a0a40b3cacec56a030701d6be8e5ce iso and elf outside the package (inside_package iso=false elf=false).
Run logs/grok/packaging-1 via grok_run -Task packaging -Keys 10:Down,12:Cross -Shots 16,22 -Env TEKKEN4_SRC=<package>,TEKKEN4_BUILD_DIR=runtime,TEKKEN4_SOUND=1,PS2X_HOST_SHOTS=16.
params.txt: those env values. stdout.txt:1 Using argv boot path. stdout.txt:51 cdImage and stdout.txt:68 driver reads from H:\tekken4-recomp\Tekken 4 (Europe, Australia) (En,Fr,De,Es,It) (v2.00).iso.
stderr.txt:22 sceCdSearchFile \TEKKEN\DATA.BIN;1 LBN 1236 size 2694412288 (matches runtime/tekken4_overrides.cpp kDataBinLbn/kDataBinSize).
pressed Down 10.3 s, Cross 12.3 s, ran 22.3 s. host_16s.png present. frame_22s.bmp absent (last-second shot is not written).
frame_16s.bmp 640x448 r/g/b mean 13.79/13.79/2.27 max 255/255/255 pct_near_white 0.02 pct_near_black 83.05 blank false.
Saves: list_count 470 (logs/grok/packaging-list-20261029-184219.out.txt). 466+466 zips stamp 20261029T173145Z are empty run-dir cards from the backup before skip_empty; leave them for the user (open). 4 zips stamp 20261029T173304Z: disc-mc0, disc-mc1 (22 bytes, empty elf cards), fixture mc0 175, fixture mc1 133.
Restore this session into C:\Users\pablo\tekken4-saves\restored-fixture-mc0-20261029-b files 1, DATA.txt len 25 sha1 F92C354F6C60BA41AEE278FD81E78477E4E1ABA7 text fixture-not-a-game-save (matches fixture). Restore onto restored-fixture-mc0-20261029 threw "refusing to write into an existing folder".
copy_count 1 to cloud-packaging-proof (new file). copy_count 0 skip_exists on the already-copied cloud zip. No stray False (return $false removed).
Blank Mcd001 import: Start-Process wrap_exit 2, stdout import_refused, dest import-blank-mcd001 absent. The tool UI prints exit 1 for any nonzero powershell exit (probe3 exit 7 shown as exit 1; probe wrap_exit was 2).
MakeCard: card logs/grok/packaging-card-20261029-184220.ps2 8650752 bytes. Dest import-synth-20261029-184500: BASLUS-20312GAME/DATA 3000, icon.sys 964, icon.ico 100, BESLES-50001SAVE/BIG.DAT 2048, EMPTY 0. OLDSAVE absent. wrap_exit 0. import_saves 2 import_files 5.
live game\disc\mc0 files 0. packaging-1\mc0 files 0.
Did not run targets.py package or memcard.py export/restore/sync. Did not delete or move anything. Did not rebuild the runtime.
