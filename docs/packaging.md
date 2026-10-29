# Packaging and saves

Two copy-only tools. Neither deletes, moves, or overwrites. A package never contains a game file.
Backups and restores never replace a save that is already on disk.

The guard and the card reader follow the vendored console-skill
(`tools/console-skill/console-anywhere/targets.py`, `reference/guard.md`,
`tools/console-skill/console-saves/memcard.py`). Those upstream commands delete or `os.replace`
files (`ORIGIN.md`). These scripts do not call `targets.py package` or `memcard.py export`,
`restore`, or `sync`.

## Package

```powershell
powershell -File tools\package_game.ps1
powershell -File tools\package_game.ps1 -ProveGuard
powershell -File tools\package_game.ps1 -Guard logs\package\<folder>
```

`-BuildDir` defaults to `H:\tekken4-fork-ps2recomp\out\runtime\ps2xRuntime`. Each run creates a new
folder `logs\package\tekken4-pal-<yyyyMMdd-HHmmss>\` (a free `-2` name if that folder already
exists) and a sibling zip with the same name. Nothing already there is replaced.

### What is inside

| path | what |
| --- | --- |
| `Play.bat`, `Play.ps1` | ask for or find the player's own ISO, then start the runner |
| `out\runtime\ps2xRuntime\ps2EntryRunner.exe` | the PAL runner (Windows PE). Same relative path as the build, so a capture script can point `TEKKEN4_SRC` at the package folder and `TEKKEN4_BUILD_DIR=runtime` |
| `out\runtime\ps2xRuntime\*.dll` | the DLLs next to that exe in the build: FFmpeg (`avcodec-61.dll` and the rest), SDL2, and the image libraries the renderer loads |
| `game\PUT-YOUR-GAME-HERE.txt` | the only file under `game\`. No disc file is placed there |
| `README.md`, `.package.json` | how to play, and the file list |

Left in the build directory on purpose: `ps2EntryRunner.pdb`, `*.lib`, `cmake_install.cmake`,
`CMakeFiles\`, and `vu1n_generated\*.cpp`.

### How the launcher finds the ISO

`Play.bat` runs `Play.ps1`. The ISO path is `-Iso`, or `TEKKEN4_ISO`, or the first path in
`my-iso.txt` next to `Play.bat`, or a prompt when a console is attached. The file must sit outside
the package. `Play.ps1` reads `SYSTEM.CNF` and requires `BOOT2 = cdrom0:\SCES_508.78;1`, then checks
the boot ELF SHA-1 `24ced2b7f3a0a40b3cacec56a030701d6be8e5ce` (PAL v2.00).

The runner still needs that ELF as `argv[1]` (`ps2xRuntime/src/main.cpp`). `Play.ps1` uses `-Elf`,
or `TEKKEN4_ELF`, or `<iso folder>\game\disc\SCES_508.78` when that extract already exists. Otherwise
it writes a new file under `%LOCALAPPDATA%\tekken4-pal\boot\`. An existing file is not replaced.
The ELF is never written into the package. `TEKKEN4_ISO` is set to the absolute ISO path before the
exe starts, which is what `findIsoPath()` in `runtime/tekken4_overrides.cpp` reads.

```powershell
powershell -File <package>\Play.ps1 -Iso <your.iso> -Elf <your SCES_508.78> -PrintOnly
```

`-PrintOnly` prints `BOOT2`, `ELF_SHA1`, `iso` and `elf` and does not start the game.

### The guard

Before the zip, every file is classified. A hit refuses the package. The folder and, if the zip was
already written, the zip are left on disk (nothing is deleted). Refused:

| check | how |
| --- | --- |
| disc images | extensions `.iso .bin .img .mdf .mds .nrg .chd .cso .zso .ecm .cue .ccd .sub .isz .dax`; content `CD001` at `0x8001` or `0x9319`, `MComprHD`, `CISO` / `ZISO` |
| `DATA*.BIN` | file name (`DATA.BIN`, `DATA2.BIN`, ...) |
| VU1 micro memory | `vu1_<16 hex digits>.bin`, the `GOW_VU1_CAPTURA` dump (`ps2_vu1_core.cpp`) |
| PS2 programs | `.irx`; a 32-bit ELF with machine 8 (MIPS); a name like `SCES_508.78` or `SLUS_203.28`; `SYSTEM.CNF` |
| recompiled source | `register_functions.cpp`, `ps2_recompiled_functions.h`, `ps2_recompiled_stubs.h`, any C/C++ under `runner\` or `vu1n_generated\`, `vu1n_*.cpp`, or a source file that references `g_ps2RecompiledFunctionTable` |
| `game\` | anything except `PUT-YOUR-GAME-HERE.txt` |
| size | any file over 512 MB |

`-ProveGuard` builds a synthetic folder of those names (not a real disc) under `logs\grok\` and
expects every one of them to be refused, and the placeholder plus a plain README to pass.

There is no allow-list. A disc file cannot be waved through.

### Generated C++ is compiled in

The recompiler writes C++ for the whole ELF, and the VU1 generator writes `vu1n_part*.cpp` from the
captured micro memory. `tools\build_runtime.cmd` compiles that into `ps2EntryRunner.exe`. The
package contains the exe, not those sources, and not `vu1_<hash>.bin`.

A player who builds from their own ISO follows the US tree's `tools\build_game.ps1`
(`H:\tekken4-recomp_usa\tools\build_game.ps1`): check the ISO (`SYSTEM.CNF` BOOT2 and the ELF
SHA-1), extract onto their machine, recompile, stage, build the runtime. On this PAL tree the last
step is `tools\build_runtime.cmd` after that extract and recompile exist locally. The prebuilt
package skips that only because the compile already happened on the build machine. The ISO is still
the player's, and it is still outside the zip.

The exe is derived from the game. It is for the owner of the disc, on their own machines. Do not
upload it. Not affiliated with Sony. PlayStation is a trademark of Sony Interactive Entertainment.

## Saves

Memory cards in the port are folders. Slot 1 is `<directory of the ELF>\mc0`, slot 2 is the sibling
`mc1` (`ps2xRuntime/src/lib/Kernel/Stubs/MemoryCard.cpp`, `getMcRootPath`). With the ELF at
`game\disc\SCES_508.78`, that is `game\disc\mc0` and `game\disc\mc1`. A run directory is scanned too
(`logs\`, a few levels down) for a folder named `mc0` or `mc1`. An empty `mc0`/`mc1` in a run
directory is skipped (`skip_empty_count`): the runtime creates those two folders in the working
directory of every run, and they are not saves. The cards next to the ELF are always zipped, even
when they are still empty.

Backups go to `%USERPROFILE%\tekken4-saves` unless `-To` is set. Names are
`<parent>-<mc0|mc1>-<UTC stamp>.zip`. A name that already exists gets `-2`, `-3`, ... The zip is a
copy of the files inside the card folder. A sidecar `.txt` records the source path. The card folder
is not modified.

```powershell
powershell -File tools\saves.ps1 backup
powershell -File tools\saves.ps1 backup -Cloud $env:USERPROFILE\tekken4-saves\cloud
powershell -File tools\saves.ps1 list
powershell -File tools\saves.ps1 restore -Zip $env:USERPROFILE\tekken4-saves\<file>.zip -Dest $env:USERPROFILE\tekken4-saves\restored-<stamp>
powershell -File tools\saves.ps1 copy -Cloud $env:USERPROFILE\tekken4-saves\cloud
powershell -File tools\saves.ps1 import -Card <card.ps2> -Dest $env:USERPROFILE\tekken4-saves\import-<stamp>
powershell -File tools\saves.ps1 import -MakeCard -Dest $env:USERPROFILE\tekken4-saves\import-<stamp>
```

`restore` and `import` require `-Dest` to be a folder that does not exist. The parent must exist.
They create that one new folder and write only there. They refuse `..` and absolute paths inside a
zip. They do not copy back onto `game\disc\mc0`.

`copy` and `backup -Cloud` copy zip files into the cloud folder. If the destination file already
exists, the file is skipped (`skip_exists`). The cloud folder's parent must already exist, so a
typo does not create a stray directory. Point `-Cloud` at a folder OneDrive, Dropbox, Google Drive
or Syncthing already syncs. The script does not talk to a cloud service. Keep that folder private.

`import` reads a PCSX2 `.ps2` (or a raw card of the same layout) through `memcard.py`'s read-only
`open_source` / `tree` / `_write_tree`. It does not run `memcard.py export` (that command deletes a
temporary directory and replaces an existing save). A card whose superblock is not
`Sony PS2 Memory Card Format ` is refused (stdout `import_refused`, process exit code 2) and `-Dest` is not created. `-MakeCard` writes a new
synthetic 8,650,752-byte card (the PCSX2 ECC size) with made-up saves, for a machine whose real
cards are blank. It refuses when `-Card` already exists.

The two real cards in `external\pcsx2\memcards` (`Mcd001.ps2`, `Mcd002.ps2`) are 8,650,752 bytes of
`0xFF` with no superblock, so they are not importable until a game has formatted them.

Close the game before backing up or importing. A save is yours: it does not go into git and it does
not go into a package.
