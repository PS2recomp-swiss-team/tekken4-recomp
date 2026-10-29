# Back up the port's folder memory cards, list those backups, restore into a new folder, copy a
# backup into a cloud-synced folder, and import a PCSX2 .ps2 card. Copy only: never deletes, never
# moves, never overwrites an existing file or save folder.
#
# mc0/mc1 live next to the ELF (game\disc\mc0, and mc1 for slot 2) and, when a run used that layout,
# under logs\ (MemoryCard.cpp getMcRootPath). Card images are read through memcard.py's read API
# (_write_tree / open_source). memcard.py's own export, restore and sync delete files; this script
# does not call those commands.
#
#   powershell -File tools\saves.ps1 backup [-Cloud <folder>]
#   powershell -File tools\saves.ps1 list
#   powershell -File tools\saves.ps1 restore -Zip <backup.zip> -Dest <new folder>
#   powershell -File tools\saves.ps1 copy -Cloud <folder> [-Zip <one zip>]
#   powershell -File tools\saves.ps1 import -Card <card.ps2> -Dest <new folder> [-MakeCard]
param(
    [Parameter(Position = 0)]
    [ValidateSet("backup", "list", "restore", "import", "copy")]
    [string]$Action = "backup",
    [string]$Root = "",
    [string]$To = "",
    [string]$Zip = "",
    [string]$Dest = "",
    [string]$Card = "",
    [string]$Cloud = "",
    [switch]$MakeCard
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
if (-not $To) { $To = Join-Path $env:USERPROFILE "tekken4-saves" }
$McDir = Join-Path $Root "tools\console-skill\console-saves"

$script:McPy = @'
import os, struct, sys

MAGIC = b"Sony PS2 Memory Card Format "
DIRENT = struct.Struct("<HHL8sLL8sL28x448s")
TOD = struct.Struct("<xBBBBBH")
MODE_DIR, MODE_FILE = 0x8427, 0x8497
FREE, END = 0x7FFFFFFF, 0xFFFFFFFF


def tod(y, mo, d, h, mi, s):
    return TOD.pack(s, mi, h, d, mo, y)


def icon_sys(line1, line2):
    blob = bytearray(964)
    blob[0:4] = b"PS2D"
    t1, t2 = line1.encode("ascii"), line2.encode("ascii")
    struct.pack_into("<H", blob, 6, len(t1))
    title = t1 + t2
    blob[0xC0:0xC0 + len(title)] = title
    blob[0x104:0x104 + 8] = b"icon.ico"
    return bytes(blob)


def build():
    """A PCSX2-sized card (8 MB + ECC = 8650752) with two made-up saves. Not a real dump."""
    page, ppc, ppb, cs = 512, 2, 16, 1024
    clusters = 8192
    alloc_offset = 41
    backup2 = clusters // (ppb // ppc) - 2
    alloc_end = backup2 * (ppb // ppc) - alloc_offset
    t_save = tod(2004, 5, 6, 7, 8, 9)
    saves = [
        (b"BASLUS-20312GAME", t_save, [
            (b"icon.sys", icon_sys("TEST", "SAVE")),
            (b"DATA", bytes((i * 7 + 3) & 0xFF for i in range(3000))),
            (b"icon.ico", b"\x01" * 100),
        ]),
        (b"BESLES-50001SAVE", tod(2005, 12, 31, 23, 59, 58), [
            (b"BIG.DAT", bytes((i * 13) & 0xFF for i in range(2048))),
            (b"EMPTY", b""),
        ]),
    ]
    img = bytearray(clusters * cs)
    sb = bytearray(0x154)
    sb[0:28] = MAGIC
    sb[0x1C:0x23] = b"1.2.0.0"
    struct.pack_into("<HHHH", sb, 0x28, page, ppc, ppb, 0xFF00)
    struct.pack_into("<6I", sb, 0x30, clusters, alloc_offset, alloc_end, 0, backup2 + 1, backup2)
    nfat = -(-alloc_end // 256)
    struct.pack_into("<I", sb, 0x50, 8)
    sb[0xD0:0x150] = b"\xff" * 128
    sb[0x150], sb[0x151] = 2, 0x52
    img[0:len(sb)] = sb
    for i in range(nfat):
        struct.pack_into("<I", img, 8 * cs + 4 * i, 9 + i)
    fat = [FREE] * (nfat * 256)
    pool = list(range(1, alloc_end))
    pool = pool[::3] + pool[1::3] + pool[2::3]

    def alloc(n, first=None):
        got = [first] if first is not None else []
        while len(got) < n:
            got.append(pool.pop(0))
        for a, b in zip(got, got[1:]):
            fat[a] = 0x80000000 | b
        fat[got[-1]] = END
        return got

    def write(chain, blob):
        for i, c in enumerate(chain):
            piece = blob[i * cs:(i + 1) * cs]
            at = (alloc_offset + c) * cs
            img[at:at + len(piece)] = piece

    def dirent(mode, length, t, cluster, name):
        return DIRENT.pack(mode, 0, length, t, cluster, 0, t, 0, name)

    root_entries = [None, None]
    for name, t, files in saves:
        ents = [None, None]
        for fname, data in files:
            if data:
                ch = alloc(-(-len(data) // cs))
                write(ch, data)
                ents.append(dirent(MODE_FILE, len(data), t, ch[0], fname))
            else:
                ents.append(dirent(MODE_FILE, 0, t, FREE, fname))
        ch = alloc(-(-len(ents) // 2))
        ents[0] = dirent(MODE_DIR, len(ents), t, 0, b".")
        ents[1] = dirent(0xA426, 0, t, 0, b"..")
        write(ch, b"".join(ents))
        root_entries.append(dirent(MODE_DIR, len(ents), t, ch[0], name))
    root_entries.append(dirent(MODE_DIR & 0x7FFF, 2, t_save, 5, b"OLDSAVE"))
    root_entries[0] = dirent(MODE_DIR, len(root_entries), t_save, 0, b".")
    root_entries[1] = dirent(0xA426, 0, t_save, 0, b"..")
    rch = alloc(-(-len(root_entries) // 2), first=0)
    write(rch, b"".join(root_entries))
    for i, v in enumerate(fat):
        struct.pack_into("<I", img, (9 + i // 256) * cs + 4 * (i % 256), v)
    spare = b"\x5a" * 16
    return b"".join(img[p * page:(p + 1) * page] + spare for p in range(clusters * ppc))


def export(mcdir, card, dest):
    if os.path.exists(dest):
        sys.stderr.write("dest exists, refusing: %s\n" % dest)
        return 2
    sys.path.insert(0, mcdir)
    import memcard
    src = memcard.open_source(card)
    try:
        entries = [e for e in src.tree() if e.is_dir]
        os.makedirs(dest)
        warnings = []
        saves = 0
        files = 0
        for e in entries:
            try:
                name = memcard.host_name(e.raw_name)
            except memcard.ToolError as err:
                warnings.append(str(err))
                continue
            target = os.path.join(dest, name)
            if os.path.exists(target):
                warnings.append("exists, skipped " + name)
                continue
            n = memcard._write_tree(src, e, target, warnings)
            print("exported %s files %d -> %s" % (name, n, target))
            saves += 1
            files += n
        for base, dirs, names in os.walk(dest):
            for nm in sorted(names):
                p = os.path.join(base, nm)
                rel = os.path.relpath(p, dest).replace("\\", "/")
                print("file %s %d" % (rel, os.path.getsize(p)))
        print("import_saves %d" % saves)
        print("import_files %d" % files)
        for w in warnings:
            print("WARNING %s" % w)
        return 1 if warnings else 0
    finally:
        src.close()


def main():
    cmd = sys.argv[1]
    if cmd == "makecard":
        out = sys.argv[2]
        if os.path.exists(out):
            sys.stderr.write("exists, refusing to overwrite: %s\n" % out)
            return 2
        parent = os.path.dirname(os.path.abspath(out))
        if parent and not os.path.isdir(parent):
            os.makedirs(parent)
        data = build()
        with open(out, "wb") as fh:
            fh.write(data)
        print("card %s bytes %d" % (out, len(data)))
        return 0
    if cmd == "export":
        return export(sys.argv[2], sys.argv[3], sys.argv[4])
    sys.stderr.write("usage: makecard|export\n")
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        sys.stderr.write("error: %s\n" % exc)
        sys.exit(2)
'@

function Get-McTool {
    $dir = Join-Path $Root "logs\grok"
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $path = Join-Path $dir "saves_mc_ro.py"
    $utf8 = New-Object System.Text.UTF8Encoding $false
    if (Test-Path -LiteralPath $path) {
        $existing = [IO.File]::ReadAllText($path)
        if ($existing -eq $script:McPy) { return $path }
        $path = Join-Path $dir ("saves_mc_ro-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".py")
        $n = 2
        while (Test-Path -LiteralPath $path) {
            $path = Join-Path $dir ("saves_mc_ro-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-$n.py")
            $n++
            if ($n -gt 50) { throw "no free path for the memcard helper" }
        }
    }
    [IO.File]::WriteAllText($path, $script:McPy, $utf8)
    return $path
}

function Test-Inside([string]$Path, [string]$Folder) {
    $p = [IO.Path]::GetFullPath($Path)
    $r = [IO.Path]::GetFullPath($Folder).TrimEnd('\')
    return ($p.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase))
}

function Get-CardLabel([string]$Mc) {
    $full = [IO.Path]::GetFullPath($Mc)
    $leaf = Split-Path -Leaf $full
    $parent = Split-Path -Leaf (Split-Path -Parent $full)
    $raw = "$parent-$leaf"
    return ($raw -replace '[^A-Za-z0-9_.-]', '_')
}

function Find-PortCards([string]$Repo) {
    $list = New-Object System.Collections.Generic.List[string]
    $elf = Join-Path $Repo "game\disc"
    foreach ($n in @("mc0", "mc1")) {
        $p = Join-Path $elf $n
        if (Test-Path -LiteralPath $p -PathType Container) { $list.Add([IO.Path]::GetFullPath($p)) }
    }
    $logs = Join-Path $Repo "logs"
    if (Test-Path -LiteralPath $logs -PathType Container) {
        $queue = New-Object System.Collections.Generic.Queue[object]
        $queue.Enqueue(@($logs, 0))
        while ($queue.Count -gt 0) {
            $item = $queue.Dequeue()
            $dir = [string]$item[0]
            $depth = [int]$item[1]
            if ($depth -gt 3) { continue }
            foreach ($child in @(Get-ChildItem -LiteralPath $dir -Directory -Force -ErrorAction SilentlyContinue)) {
                if ($child.Name -eq "mc0" -or $child.Name -eq "mc1") { $list.Add($child.FullName) }
                else { $queue.Enqueue(@($child.FullName, $depth + 1)) }
            }
        }
    }
    $seen = @{}
    $out = @()
    foreach ($p in $list) {
        $key = $p.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $out += $p }
    }
    return $out
}

function New-FreePath([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $dir = Split-Path -Parent $Path
    $base = [IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [IO.Path]::GetExtension($Path)
    $n = 2
    while ($n -le 100) {
        $try = Join-Path $dir "$base-$n$ext"
        if (-not (Test-Path -LiteralPath $try)) { return $try }
        $n++
    }
    throw "no free path for $Path"
}

function Test-ZipName([string]$Name) {
    $n = ($Name -replace '\\', '/')
    if ($n.StartsWith('/') -or $n -match '^[A-Za-z]:') { return $false }
    foreach ($part in $n.Split('/')) {
        if ($part -eq ".." -or $part -eq "") { if ($part -eq "..") { return $false } }
    }
    if ($n.Split('/') -contains "..") { return $false }
    return $true
}

function Copy-NewOnly([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        "skip_exists $Destination"
        return
    }
    $parent = Split-Path -Parent $Destination
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $grand = Split-Path -Parent $parent
        if ($grand -and -not (Test-Path -LiteralPath $grand)) { throw "cloud parent does not exist (refusing to create a stray folder): $grand" }
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination
    "copied $Source -> $Destination"
    $script:Copied = $script:Copied + 1
}

function Write-CardZip([string]$Mc, [string]$ZipPath) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $files = @(Get-ChildItem -LiteralPath $Mc -Recurse -File -Force -ErrorAction SilentlyContinue)
    $zip = [IO.Compression.ZipFile]::Open($ZipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $files) {
            $rel = $f.FullName.Substring([IO.Path]::GetFullPath($Mc).Length).TrimStart('\') -replace '\\', '/'
            if (-not (Test-ZipName $rel)) { throw "refusing to store unsafe path $rel" }
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $rel, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $zip.Dispose() }
    $side = [IO.Path]::ChangeExtension($ZipPath, ".txt")
    $side = New-FreePath $side
    [IO.File]::WriteAllText($side, ("source $([IO.Path]::GetFullPath($Mc))`r`nfiles $($files.Count)`r`n"), (New-Object System.Text.UTF8Encoding $false))
    $script:LastZipFiles = $files.Count
    "backup $ZipPath files $($files.Count) from $Mc"
    "sidecar $side"
}

function Get-ZipFileCount([string]$ZipPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        return @($z.Entries | Where-Object { $_.FullName -and -not $_.FullName.EndsWith('/') }).Count
    } finally { $z.Dispose() }
}

if (-not (Test-Path -LiteralPath $To)) {
    $parent = Split-Path -Parent $To
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { throw "backup parent does not exist: $parent" }
    New-Item -ItemType Directory -Path $To | Out-Null
}

switch ($Action) {
    "list" {
        $zips = @(Get-ChildItem -LiteralPath $To -File -Filter "*.zip" -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($zips.Count -eq 0) { "list_empty $To"; exit 0 }
        foreach ($z in $zips) {
            $n = Get-ZipFileCount $z.FullName
            "zip $($z.Name) bytes $($z.Length) files $n"
        }
        "list_count $($zips.Count)"
        exit 0
    }
    "backup" {
        $cards = @(Find-PortCards $Root)
        if ($cards.Count -eq 0) { throw "no mc0/mc1 folders under $Root (next to game\disc or under logs)" }
        $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
        $made = @()
        $skipped = 0
        foreach ($mc in $cards) {
            $fullTo = [IO.Path]::GetFullPath($To)
            if ((Test-Inside $fullTo $mc)) { throw "backup folder is inside the card: $mc" }
            $nFiles = @(Get-ChildItem -LiteralPath $mc -Recurse -File -Force -ErrorAction SilentlyContinue).Count
            $elfCard = $mc -match '\\game\\disc\\mc[01]$'
            # The runtime creates an empty mc0 and mc1 in every run directory. Those are not saves.
            # The cards next to the ELF are always backed up, even when the player has not saved yet.
            if ($nFiles -eq 0 -and -not $elfCard) { $skipped++; continue }
            $label = Get-CardLabel $mc
            $zipPath = New-FreePath (Join-Path $To "$label-$stamp.zip")
            Write-CardZip $mc $zipPath
            $made += [pscustomobject]@{ Zip = $zipPath; Files = $script:LastZipFiles; Source = $mc }
        }
        "skip_empty_count $skipped"
        if ($Cloud) {
            $script:Copied = 0
            foreach ($m in $made) {
                $name = Split-Path -Leaf $m.Zip
                Copy-NewOnly $m.Zip (Join-Path $Cloud $name)
            }
            "copy_count $script:Copied"
        }
        "backup_count $($made.Count)"
        exit 0
    }
    "restore" {
        if (-not $Zip -or -not $Dest) { throw "restore needs -Zip and -Dest (a folder that does not exist yet)" }
        if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) { throw "zip not found: $Zip" }
        if (Test-Path -LiteralPath $Dest) { throw "refusing to write into an existing folder: $Dest" }
        $destParent = Split-Path -Parent $Dest
        if ($destParent -and -not (Test-Path -LiteralPath $destParent)) { throw "dest parent does not exist (refusing to create a stray folder): $destParent" }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead(([IO.Path]::GetFullPath($Zip)))
        try {
            $entries = @($z.Entries)
            foreach ($e in $entries) {
                if (-not (Test-ZipName $e.FullName)) { throw "backup contains an unsafe path $($e.FullName); refusing to restore" }
            }
            New-Item -ItemType Directory -Path $Dest | Out-Null
            $n = 0
            foreach ($e in $entries) {
                if (-not $e.FullName -or $e.FullName.EndsWith('/')) { continue }
                $target = Join-Path $Dest ($e.FullName -replace '/', '\')
                if (Test-Path -LiteralPath $target) { throw "refusing to overwrite $target" }
                $parent = Split-Path -Parent $target
                if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
                $inStream = $e.Open()
                try {
                    $outFs = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                    try { $inStream.CopyTo($outFs) } finally { $outFs.Dispose() }
                } finally { $inStream.Dispose() }
                $n++
                "restored_file $target $($e.Length)"
            }
            "restore $Dest files $n from $Zip"
        } finally { $z.Dispose() }
        exit 0
    }
    "copy" {
        if (-not $Cloud) { throw "copy needs -Cloud (a folder whose parent already exists)" }
        $sources = @()
        if ($Zip) { $sources = @(Get-Item -LiteralPath $Zip) }
        else { $sources = @(Get-ChildItem -LiteralPath $To -File -Filter "*.zip" -ErrorAction SilentlyContinue) }
        if ($sources.Count -eq 0) { throw "no zip to copy" }
        $script:Copied = 0
        foreach ($s in $sources) {
            Copy-NewOnly $s.FullName (Join-Path $Cloud (Split-Path -Leaf $s.Name))
        }
        "copy_count $script:Copied"
        exit 0
    }
    "import" {
        if (-not $Dest) { throw "import needs -Dest (a folder that does not exist yet)" }
        if (Test-Path -LiteralPath $Dest) { throw "refusing to write into an existing folder: $Dest" }
        $destParent = Split-Path -Parent $Dest
        if ($destParent -and -not (Test-Path -LiteralPath $destParent)) { throw "dest parent does not exist (refusing to create a stray folder): $destParent" }
        $py = Get-McTool
        $oldEa = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        if ($MakeCard) {
            if (-not $Card) {
                $Card = Join-Path (Join-Path $Root "logs\grok") ("packaging-card-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".ps2")
            }
            $Card = New-FreePath $Card
            & python -I $py makecard $Card
            if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = $oldEa; throw "makecard failed ($LASTEXITCODE)" }
        }
        if (-not $Card -or -not (Test-Path -LiteralPath $Card -PathType Leaf)) { $ErrorActionPreference = $oldEa; throw "import needs -Card, a PCSX2 .ps2 (or -MakeCard)" }
        & python -I $py export $McDir $Card $Dest
        $code = $LASTEXITCODE
        $ErrorActionPreference = $oldEa
        if ($code -eq 2) { "import_refused"; exit 2 }
        if ($code -eq 1) { "import_attention"; exit 1 }
        exit 0
    }
}
