# Assemble a Windows folder of the Tekken 4 PAL runner with no game file in it, then zip it.
# Copy only. Never deletes, never moves, never overwrites: each run is a new timestamped folder.
# The guard is the one in tools/console-skill/console-anywhere/targets.py (reference/guard.md), plus
# DATA*.BIN and VU1 micro-memory images (vu1_<16 hex>.bin, the GOW_VU1_CAPTURA dump).
#
#   powershell -File tools\package_game.ps1
#   powershell -File tools\package_game.ps1 -ProveGuard
#   powershell -File tools\package_game.ps1 -Guard logs\package\<name>
param(
    [string]$BuildDir = "H:\tekken4-fork-ps2recomp\out\runtime\ps2xRuntime",
    [string]$Name = "tekken4-pal",
    [string]$OutRoot = "",
    [string]$Guard = "",
    [switch]$ProveGuard
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $OutRoot) { $OutRoot = Join-Path $Root "logs\package" }

$script:MaxFile = 512MB
$script:Placeholder = "PUT-YOUR-GAME-HERE.txt"
$script:DiscExt = @{
    ".iso" = $true; ".bin" = $true; ".img" = $true; ".mdf" = $true; ".mds" = $true; ".nrg" = $true
    ".chd" = $true; ".cso" = $true; ".zso" = $true; ".ecm" = $true; ".cue" = $true; ".ccd" = $true
    ".sub" = $true; ".isz" = $true; ".dax" = $true
}
$script:SourceExt = @{ ".cpp" = $true; ".cc" = $true; ".cxx" = $true; ".c" = $true; ".h" = $true; ".hpp" = $true; ".hh" = $true }
$script:RecompNames = @{
    "register_functions.cpp" = $true; "ps2_recompiled_functions.h" = $true; "ps2_recompiled_stubs.h" = $true
}
$script:SerialName = [regex]'^[A-Za-z]{4}[_-]\d{3}\.?\d{2}(;\d+)?$'
$script:DataBin = [regex]'^DATA.*\.BIN$'
$script:Vu1Name = [regex]'^vu1_[0-9a-fA-F]{16}\.bin$'
$script:Markers = @(
    [Text.Encoding]::ASCII.GetBytes("ps2_recompiled_functions.h"),
    [Text.Encoding]::ASCII.GetBytes("g_ps2RecompiledFunctionTable")
)

function Read-FileHead([string]$Path, [int]$Count) {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $buf = New-Object byte[] $Count
        $got = $fs.Read($buf, 0, $Count)
        if ($got -eq $Count) { return ,$buf }
        $small = New-Object byte[] $got
        if ($got -gt 0) { [Array]::Copy($buf, $small, $got) }
        return ,$small
    } finally { $fs.Dispose() }
}

function Test-BytesAt([byte[]]$Buf, [int]$At, [byte[]]$Needle) {
    if ($Buf.Length -lt ($At + $Needle.Length)) { return $false }
    for ($i = 0; $i -lt $Needle.Length; $i++) {
        if ($Buf[$At + $i] -ne $Needle[$i]) { return $false }
    }
    return $true
}

function Test-Ps2Elf([byte[]]$Head) {
    if ($Head.Length -lt 20) { return $false }
    if ($Head[0] -ne 0x7F -or $Head[1] -ne 0x45 -or $Head[2] -ne 0x4C -or $Head[3] -ne 0x46) { return $false }
    if ($Head[4] -ne 1) { return $false }
    $mach = -1
    if ($Head[5] -eq 1) { $mach = [BitConverter]::ToUInt16($Head, 18) }
    elseif ($Head[5] -eq 2) { $mach = ($Head[18] * 256) + $Head[19] }
    return ($mach -eq 8)
}

function Get-GameDataReason([string]$Path, [string]$Rel, [int64]$Size) {
    $rel = ($Rel -replace '\\', '/')
    $name = [IO.Path]::GetFileName($rel)
    $lower = $name.ToLowerInvariant()
    $ext = [IO.Path]::GetExtension($lower)
    $parts = $rel.Split('/')
    if ($parts[0] -eq "game" -and $parts.Length -gt 1 -and $name -ne $script:Placeholder) {
        return "inside game/: that folder ships empty, the player supplies their own disc"
    }
    if ($Size -gt $script:MaxFile) { return "over 512 MB: only disc images and dumps are that big" }
    if ($script:Vu1Name.IsMatch($name) -or ($lower.StartsWith("vu1_") -and $ext -eq ".bin" -and $Size -eq 16384)) {
        return "a VU1 micro memory image (game code, GOW_VU1_CAPTURA vu1_<fnv>.bin)"
    }
    if ($script:DataBin.IsMatch($name)) { return "a disc archive DATA*.BIN" }
    if ($script:DiscExt.ContainsKey($ext)) { return "a disc image file ($ext)" }
    if ($ext -eq ".irx") { return "an IOP module (.IRX) from the disc" }
    if ($lower -eq "system.cnf") { return "the disc's SYSTEM.CNF" }
    if ($script:SerialName.IsMatch($name)) { return "named like a disc's main ELF ($name)" }
    if ($script:RecompNames.ContainsKey($name)) { return "recompiled game code ($name)" }
    $parents = @()
    if ($parts.Length -gt 1) { $parents = $parts[0..($parts.Length - 2)] }
    $parentLower = @($parents | ForEach-Object { $_.ToLowerInvariant() })
    if ($script:SourceExt.ContainsKey($ext) -and ($parentLower -contains "runner" -or $parentLower -contains "vu1n_generated")) {
        return "recompiled game source under $($parentLower -join '/')"
    }
    if ($script:SourceExt.ContainsKey($ext) -and $lower.StartsWith("vu1n_")) {
        return "generated VU1 C++ ($name): it is compiled into the runner, not shipped"
    }
    $head = Read-FileHead $Path 0x9320
    if (Test-Ps2Elf $head) { return "a PS2 ELF or IRX (32-bit MIPS)" }
    if ($head.Length -ge 8 -and (Test-BytesAt $head 0 ([Text.Encoding]::ASCII.GetBytes("MComprHD")))) { return "a CHD disc image" }
    if ($head.Length -ge 4) {
        $magic4 = [Text.Encoding]::ASCII.GetString($head, 0, 4)
        if ($magic4 -eq "CISO" -or $magic4 -eq "ZISO") { return "a compressed ISO (CSO/ZSO)" }
    }
    $cd = [Text.Encoding]::ASCII.GetBytes("CD001")
    if ((Test-BytesAt $head 0x8001 $cd) -or (Test-BytesAt $head 0x9319 $cd)) { return "an ISO 9660 disc image" }
    if ($script:SourceExt.ContainsKey($ext)) {
        $blob = Read-FileHead $Path (256 * 1024)
        foreach ($marker in $script:Markers) {
            if (Test-BytesAt $blob 0 $marker) { return "recompiled game code (references the generated function table)" }
            $found = $false
            for ($i = 0; $i -le $blob.Length - $marker.Length; $i++) {
                $ok = $true
                for ($j = 0; $j -lt $marker.Length; $j++) {
                    if ($blob[$i + $j] -ne $marker[$j]) { $ok = $false; break }
                }
                if ($ok) { $found = $true; break }
            }
            if ($found) { return "recompiled game code (references the generated function table)" }
        }
    }
    return $null
}

function Invoke-PackageGuard([string]$Folder) {
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw "not a folder: $Folder" }
    $rootFull = [IO.Path]::GetFullPath($Folder)
    $refused = New-Object System.Collections.Generic.List[object]
    $ok = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($rootFull.Length).TrimStart('\')
        $reason = Get-GameDataReason $_.FullName $rel $_.Length
        if ($reason) {
            $refused.Add([pscustomobject]@{ Path = ($rel -replace '\\', '/'); Reason = $reason })
        } else {
            $ok.Add(($rel -replace '\\', '/'))
        }
    }
    return [pscustomobject]@{ Refused = @($refused.ToArray()); Ok = @($ok.ToArray()) }
}

function Write-GuardReport($Result, [string]$Folder) {
    "guard: $Folder"
    foreach ($f in @($Result.Refused)) { "REFUSED $($f.Path): $($f.Reason)" }
    foreach ($p in @($Result.Ok)) { "ok $p" }
    "guard_refused $(@($Result.Refused).Count)"
    "guard_ok $(@($Result.Ok).Count)"
}

function New-FreeDir([string]$Parent, [string]$Leaf) {
    if (-not (Test-Path -LiteralPath $Parent)) { New-Item -ItemType Directory -Path $Parent | Out-Null }
    $dest = Join-Path $Parent $Leaf
    $n = 2
    while (Test-Path -LiteralPath $dest) {
        $dest = Join-Path $Parent "$Leaf-$n"
        $n++
        if ($n -gt 100) { throw "no free folder name under $Parent for $Leaf" }
    }
    New-Item -ItemType Directory -Path $dest | Out-Null
    return $dest
}

function New-FreeFile([string]$Path) {
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
    throw "no free file name for $Path"
}

if ($ProveGuard) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fix = New-FreeDir (Join-Path $Root "logs\grok") "packaging-guard-fixture-$stamp"
    $game = Join-Path $fix "game"
    $runner = Join-Path $fix "runner"
    New-Item -ItemType Directory -Path $game | Out-Null
    New-Item -ItemType Directory -Path $runner | Out-Null
    [IO.File]::WriteAllText((Join-Path $fix "README.md"), "safe text`r`n")
    [IO.File]::WriteAllText((Join-Path $game $script:Placeholder), "empty on purpose`r`n")
    [IO.File]::WriteAllText((Join-Path $game "secret.txt"), "not shipped`r`n")
    [IO.File]::WriteAllBytes((Join-Path $fix "SCES_508.78"), [byte[]](1, 2, 3, 4))
    [IO.File]::WriteAllBytes((Join-Path $fix "DATA.BIN"), [byte[]](1, 2, 3, 4, 5, 6, 7, 8))
    [IO.File]::WriteAllBytes((Join-Path $fix "DATA2.BIN"), [byte[]](1, 2, 3, 4))
    [IO.File]::WriteAllBytes((Join-Path $fix "mod.irx"), [byte[]](1, 2, 3, 4))
    [IO.File]::WriteAllText((Join-Path $fix "SYSTEM.CNF"), "BOOT2 = cdrom0:\SCES_508.78;1`r`n")
    [IO.File]::WriteAllBytes((Join-Path $fix "disc.iso"), [byte[]](1, 2, 3, 4))
    [IO.File]::WriteAllBytes((Join-Path $fix "vu1_0123456789abcdef.bin"), (New-Object byte[] 16384))
    [IO.File]::WriteAllText((Join-Path $fix "register_functions.cpp"), "int x;`r`n")
    [IO.File]::WriteAllText((Join-Path $runner "game.cpp"), "extern int g_ps2RecompiledFunctionTable;`r`n")
    [IO.File]::WriteAllText((Join-Path $fix "ps2_recompiled_functions.h"), "/* generated */`r`n")
    [IO.File]::WriteAllText((Join-Path $fix "vu1n_part0.cpp"), "/* generated vu1 */`r`n")
    $elf = New-Object byte[] 20
    $elf[0] = 0x7F; $elf[1] = 0x45; $elf[2] = 0x4C; $elf[3] = 0x46; $elf[4] = 1; $elf[5] = 1; $elf[18] = 8
    [IO.File]::WriteAllBytes((Join-Path $fix "not-a-disc.dat"), $elf)
    $iso = New-Object byte[] 0x8006
    $iso[0x8000] = 1
    $cd = [Text.Encoding]::ASCII.GetBytes("CD001")
    [Array]::Copy($cd, 0, $iso, 0x8001, 5)
    [IO.File]::WriteAllBytes((Join-Path $fix "hidden.dat"), $iso)
    [IO.File]::WriteAllBytes((Join-Path $fix "image.dat"), [Text.Encoding]::ASCII.GetBytes("MComprHD"))
    $result = Invoke-PackageGuard $fix
    Write-GuardReport $result $fix
    $want = @(
        "SCES_508.78", "DATA.BIN", "DATA2.BIN", "mod.irx", "SYSTEM.CNF", "disc.iso",
        "vu1_0123456789abcdef.bin", "register_functions.cpp", "runner/game.cpp",
        "ps2_recompiled_functions.h", "vu1n_part0.cpp", "game/secret.txt", "not-a-disc.dat",
        "hidden.dat", "image.dat"
    )
    $got = @($result.Refused | ForEach-Object { $_.Path })
    $missing = @($want | Where-Object { $got -notcontains $_ })
    $safeHit = @($got | Where-Object { $_ -eq "README.md" -or $_ -eq "game/$($script:Placeholder)" })
    if ($missing.Count -gt 0 -or $safeHit.Count -gt 0 -or @($result.Refused).Count -lt 1) {
        "prove_guard FAIL missing=$($missing -join ',') safe_hit=$($safeHit -join ',')"
        exit 1
    }
    "prove_guard PASS refused=$(@($result.Refused).Count) ok=$(@($result.Ok).Count) fixture=$fix"
    if (-not $Guard) { exit 0 }
}

if ($Guard) {
    $result = Invoke-PackageGuard $Guard
    Write-GuardReport $result $Guard
    if (@($result.Refused).Count -gt 0) { exit 1 }
    exit 0
}

$exe = Join-Path $BuildDir "ps2EntryRunner.exe"
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "runner not found: $exe" }
$exeHead = Read-FileHead $exe 2
if ($exeHead.Length -lt 2 -or $exeHead[0] -ne 0x4D -or $exeHead[1] -ne 0x5A) { throw "$exe is not a Windows PE (MZ) runner" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$dest = New-FreeDir $OutRoot "$Name-$stamp"
$bin = Join-Path $dest "out\runtime\ps2xRuntime"
New-Item -ItemType Directory -Path $bin | Out-Null
Copy-Item -LiteralPath $exe -Destination (Join-Path $bin "ps2EntryRunner.exe")
$dlls = @(Get-ChildItem -LiteralPath $BuildDir -File -Filter "*.dll")
foreach ($d in $dlls) { Copy-Item -LiteralPath $d.FullName -Destination (Join-Path $bin $d.Name) }
$left = @(Get-ChildItem -LiteralPath $BuildDir -Force | Where-Object {
    -not ($_.Name -eq "ps2EntryRunner.exe" -or ($_.Extension -eq ".dll" -and -not $_.PSIsContainer))
} | ForEach-Object { $_.Name })
"left in the build dir (not packaged): $($left -join ', ')"

$gameDir = Join-Path $dest "game"
New-Item -ItemType Directory -Path $gameDir | Out-Null
[IO.File]::WriteAllText((Join-Path $gameDir $script:Placeholder), @"
This folder ships empty on purpose.
Do not put your ISO, your ELF, DATA.BIN or a memory card in this package.
Point Play.bat at the ISO of a disc you own. It stays outside this folder.
"@)

$play = @'
# Asks for, or finds, YOUR Tekken 4 PAL ISO and starts the runner. The ISO and the ELF stay
# outside this package. Copy only: a cached ELF is written to a new file under %LOCALAPPDATA%,
# never over an existing file, and never into this folder.
param(
    [string]$Iso = "",
    [string]$Elf = "",
    [switch]$PrintOnly
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2
$Package = $PSScriptRoot
$ExpectedBoot = "SCES_508.78"
$ExpectedSha1 = "24ced2b7f3a0a40b3cacec56a030701d6be8e5ce"
$Exe = Join-Path $Package "out\runtime\ps2xRuntime\ps2EntryRunner.exe"

function Test-Inside([string]$Path, [string]$Root) {
    $p = [IO.Path]::GetFullPath($Path)
    $r = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    return ($p.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase))
}

function Read-UserSector($Fs, [int64]$Ss, [int]$Off, [int64]$Lba) {
    $buf = New-Object byte[] 2048
    [void]$Fs.Seek(($Lba * $Ss) + $Off, [IO.SeekOrigin]::Begin)
    $got = 0
    while ($got -lt 2048) {
        $n = $Fs.Read($buf, $got, 2048 - $got)
        if ($n -le 0) { throw "ISO truncated at sector $Lba" }
        $got += $n
    }
    return ,$buf
}

function Read-IsoRootFile([string]$IsoPath, [string]$Want) {
    $fs = [IO.File]::Open($IsoPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $layouts = @(
            @{ Ss = 2048; Off = 0 }, @{ Ss = 2352; Off = 16 }, @{ Ss = 2352; Off = 24 }, @{ Ss = 2336; Off = 8 }
        )
        $ss = 0; $off = 0
        foreach ($L in $layouts) {
            $probe = New-Object byte[] 6
            [void]$fs.Seek((16L * $L.Ss) + $L.Off, [IO.SeekOrigin]::Begin)
            [void]$fs.Read($probe, 0, 6)
            if ($probe[0] -eq 1 -and $probe[1] -eq 0x43 -and $probe[2] -eq 0x44 -and $probe[3] -eq 0x30 -and $probe[4] -eq 0x30 -and $probe[5] -eq 0x31) {
                $ss = $L.Ss; $off = $L.Off; break
            }
        }
        if ($ss -eq 0) { throw "not an ISO 9660 image (no CD001 volume descriptor)" }
        $pvd = Read-UserSector $fs $ss $off 16
        $rootLba = [BitConverter]::ToUInt32($pvd, 158)
        $rootSize = [BitConverter]::ToInt32($pvd, 166)
        $dir = New-Object System.Collections.Generic.List[byte]
        $left = $rootSize
        $lba = [int64]$rootLba
        while ($left -gt 0) {
            $sec = Read-UserSector $fs $ss $off $lba
            $take = [Math]::Min(2048, $left)
            for ($i = 0; $i -lt $take; $i++) { $dir.Add($sec[$i]) }
            $left -= $take
            $lba++
        }
        $data = $dir.ToArray()
        $pos = 0
        $hitLba = [int64]-1
        $hitLen = 0
        while ($pos + 33 -le $data.Length) {
            $rec = $data[$pos]
            if ($rec -eq 0) { $pos = [int](($pos / 2048) + 1) * 2048; continue }
            if ($pos + $rec -gt $data.Length) { break }
            $nlen = $data[$pos + 32]
            $raw = ""
            if ($nlen -gt 0 -and ($pos + 33 + $nlen) -le $data.Length) {
                $raw = [Text.Encoding]::ASCII.GetString($data, $pos + 33, $nlen)
            }
            $semi = $raw.IndexOf(';')
            if ($semi -ge 0) { $raw = $raw.Substring(0, $semi) }
            if ($raw.EndsWith('.')) { $raw = $raw.Substring(0, $raw.Length - 1) }
            if ($raw -and $raw[0] -ne [char]0 -and $raw[0] -ne [char]1 -and $raw.Equals($Want, [StringComparison]::OrdinalIgnoreCase)) {
                $hitLba = [BitConverter]::ToUInt32($data, $pos + 2)
                $hitLen = [BitConverter]::ToInt32($data, $pos + 10)
                break
            }
            $pos += $rec
        }
        if ($hitLba -lt 0) { throw "$Want is not in the ISO root" }
        $out = New-Object byte[] $hitLen
        $filled = 0
        $cur = $hitLba
        while ($filled -lt $hitLen) {
            $sec = Read-UserSector $fs $ss $off $cur
            $take = [Math]::Min(2048, $hitLen - $filled)
            [Array]::Copy($sec, 0, $out, $filled, $take)
            $filled += $take
            $cur++
        }
        return ,$out
    } finally { $fs.Dispose() }
}

function Resolve-IsoPath {
    $candidates = @()
    if ($Iso) { $candidates += $Iso }
    if ($env:TEKKEN4_ISO) { $candidates += $env:TEKKEN4_ISO }
    $note = Join-Path $Package "my-iso.txt"
    if (Test-Path -LiteralPath $note -PathType Leaf) {
        foreach ($line in [IO.File]::ReadAllLines($note)) {
            $t = $line.Trim()
            if ($t -and -not $t.StartsWith('#')) { $candidates += $t; break }
        }
    }
    foreach ($c in $candidates) {
        $full = [IO.Path]::GetFullPath($c)
        if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
    }
    $interactive = [Environment]::UserInteractive
    try { if ([Console]::IsInputRedirected) { $interactive = $false } } catch { }
    if ($interactive -and -not $PrintOnly) {
        $typed = Read-Host "Path to your Tekken 4 (PAL, SCES-50878) ISO"
        if ($typed) {
            $full = [IO.Path]::GetFullPath($typed.Trim())
            if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
            throw "ISO not found: $full"
        }
    }
    throw "No ISO. Pass -Iso, set TEKKEN4_ISO, or put one path in my-iso.txt next to Play.bat. The ISO stays outside this folder."
}

function New-UnusedFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $dir = Split-Path -Parent $Path
    $base = [IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [IO.Path]::GetExtension($Path)
    $n = 2
    while ($n -le 100) {
        $try = Join-Path $dir ("{0}-{1}{2}" -f $base, (Get-Date -Format "yyyyMMdd-HHmmss"), $ext)
        if ($n -gt 2) { $try = Join-Path $dir ("{0}-{1}-{2}{3}" -f $base, (Get-Date -Format "yyyyMMdd-HHmmss"), $n, $ext) }
        if (-not (Test-Path -LiteralPath $try)) { return $try }
        $n++
    }
    throw "no free file name near $Path"
}

$isoFull = Resolve-IsoPath
if (Test-Inside $isoFull $Package) { throw "refusing: the ISO is inside the package ($isoFull). Keep your disc image outside this folder." }
$cnf = [Text.Encoding]::ASCII.GetString((Read-IsoRootFile $isoFull "SYSTEM.CNF"))
$m = [regex]::Match($cnf, 'BOOT2\s*=\s*cdrom0:\\?([^;\s\r\n]+)')
if (-not $m.Success) { throw "SYSTEM.CNF has no BOOT2 line. This package only runs a disc you own." }
$boot = $m.Groups[1].Value
"BOOT2 $boot"
if ($boot -ne $ExpectedBoot) { throw "this disc boots $boot; this package is the PAL recomp of $ExpectedBoot only." }
$elfBytes = Read-IsoRootFile $isoFull $ExpectedBoot
$sha = [BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash($elfBytes)).Replace('-', '').ToLower()
"ELF_SHA1 $sha"
if ($sha -ne $ExpectedSha1) { throw "ELF SHA-1 $sha does not match the PAL v2.00 disc ($ExpectedSha1). Refusing to start." }

$elfFull = ""
if ($Elf) { $elfFull = [IO.Path]::GetFullPath($Elf) }
elseif ($env:TEKKEN4_ELF) { $elfFull = [IO.Path]::GetFullPath($env:TEKKEN4_ELF) }
if ($elfFull -and -not (Test-Path -LiteralPath $elfFull -PathType Leaf)) { throw "ELF not found: $elfFull" }
if (-not $elfFull) {
    $beside = Join-Path (Split-Path -Parent $isoFull) ("game\disc\" + $ExpectedBoot)
    if (Test-Path -LiteralPath $beside -PathType Leaf) { $elfFull = [IO.Path]::GetFullPath($beside) }
}
if (-not $elfFull) {
    $cache = Join-Path $env:LOCALAPPDATA ("tekken4-pal\boot\" + $ExpectedBoot)
    if (Test-Path -LiteralPath $cache -PathType Leaf) {
        $have = (Get-FileHash -LiteralPath $cache -Algorithm SHA1).Hash.ToLower()
        if ($have -eq $ExpectedSha1) { $elfFull = [IO.Path]::GetFullPath($cache) }
    }
}
if (-not $elfFull) {
    $bootDir = Join-Path $env:LOCALAPPDATA "tekken4-pal\boot"
    $target = Join-Path $bootDir $ExpectedBoot
    if ($PrintOnly) {
        "would_extract $target"
        "iso $isoFull"
        "inside_package iso=false"
        "print_only"
        exit 0
    }
    if (-not (Test-Path -LiteralPath $bootDir)) { New-Item -ItemType Directory -Path $bootDir | Out-Null }
    $target = New-UnusedFile $target
    if (Test-Inside $target $Package) { throw "refusing to write the ELF inside the package" }
    $outFs = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $outFs.Write($elfBytes, 0, $elfBytes.Length) } finally { $outFs.Dispose() }
    $elfFull = [IO.Path]::GetFullPath($target)
    "extracted_elf $elfFull"
}
if (Test-Inside $elfFull $Package) { throw "refusing: the ELF is inside the package ($elfFull). The runner loads it from outside." }
"iso $isoFull"
"elf $elfFull"
"inside_package iso=false elf=false"
if ($PrintOnly) { "print_only"; exit 0 }
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "runner missing: $Exe" }
$env:TEKKEN4_ISO = $isoFull
if (-not $env:PS2X_GS_BACKEND) { $env:PS2X_GS_BACKEND = "gl" }
if (-not $env:PS2X_GS_THREADS) { $env:PS2X_GS_THREADS = "auto" }
if (-not $env:TEKKEN4_SOUND) { $env:TEKKEN4_SOUND = "1" }
if (-not $env:TEKKEN4_WINDOW_TITLE) { $env:TEKKEN4_WINDOW_TITLE = "TEKKEN 4 - YOUR GAME" }
& $Exe $elfFull
exit $LASTEXITCODE
'@
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText((Join-Path $dest "Play.ps1"), $play, $utf8)
$bat = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Play.ps1`" %*`r`n"
[IO.File]::WriteAllText((Join-Path $dest "Play.bat"), $bat, $utf8)

$readme = @"
# Tekken 4 PAL (SCES-50878) - Windows package

This folder is a native port built with PS2Recomp. It contains the runner and the libraries it loads.
It does not contain the game. There is no ISO, no ELF, no IRX module, no DATA.BIN, no VU1 micro-memory
image, and no generated C++ source.

The program was compiled from that recompiled code, so this folder is for the person who owns the disc,
on their own machines. Do not upload it or pass it on.

## Play

1. Dump the Tekken 4 PAL disc you own (v2.00, serial SCES-50878) to a plain .iso. Keep that file
   somewhere that is not this folder.
2. Double-click Play.bat. It asks for the ISO if it is not already in TEKKEN4_ISO or in my-iso.txt
   (one path, next to Play.bat).
3. Play.ps1 checks SYSTEM.CNF (BOOT2 = cdrom0:\SCES_508.78;1) and the ELF SHA-1
   24ced2b7f3a0a40b3cacec56a030701d6be8e5ce, then starts

   out\runtime\ps2xRuntime\ps2EntryRunner.exe

   with that ELF. The ELF is the one next to your ISO at game\disc\SCES_508.78 when you have already
   extracted it, otherwise a copy written under %LOCALAPPDATA%\tekken4-pal\boot\ (a new file; an
   existing file is never replaced). Neither file is copied into this package.
4. Saves are a folder memory card: mc0 next to the ELF (slot 2 is mc1). See docs/packaging.md
   in the project for tools\saves.ps1.

Needs: Windows 10 or 11, x64. The DLLs next to the exe (FFmpeg, SDL2, and the image libraries) are
part of the runner, not the game.

## What is in here

- Play.bat, Play.ps1: find your ISO and start the runner
- out\runtime\ps2xRuntime\ps2EntryRunner.exe and the DLLs it needs
- game\PUT-YOUR-GAME-HERE.txt: the only file in game\. Leave the folder empty.
- README.md, .package.json

## Why there is no generated C++

PS2Recomp turns the game ELF into C++ (register_functions.cpp, the recompiled function table, and the
VU1 blocks in vu1n_part*.cpp) and that C++ is compiled into ps2EntryRunner.exe. Those sources are the
game, so they are not in this zip. The captured VU1 micro memory (vu1_<hash>.bin) is not in here either;
the native blocks were compiled in on the machine that built the exe.

To build that exe yourself from a disc you own, the flow is the one in the US tree's
tools\build_game.ps1 (H:\tekken4-recomp_usa): check the ISO (SYSTEM.CNF BOOT2 and the ELF SHA-1),
extract only onto your machine, recompile, stage, then build the runtime. This PAL tree's
tools\build_runtime.cmd is the last step once your own extract and recompile are done. Each player
supplies their own disc. Nothing from the disc is in the package.

Not affiliated with or endorsed by Sony. PlayStation is a trademark of Sony Interactive Entertainment.
PS2Recomp (github.com/ran-j/PS2Recomp) is GPL-3.0.
"@
[IO.File]::WriteAllText((Join-Path $dest "README.md"), $readme, $utf8)

$result = Invoke-PackageGuard $dest
Write-GuardReport $result $dest
if (@($result.Refused).Count -gt 0) {
    "package REFUSED. The folder was left in place (nothing is deleted): $dest"
    exit 1
}

$copied = @($result.Ok)
$manifest = [ordered]@{
    tool = "tools/package_game.ps1"
    game = "Tekken 4"
    serial = "SCES-50878"
    region = "PAL"
    built_from = [IO.Path]::GetFullPath($BuildDir)
    created = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    files = @($copied)
    guard_refused = 0
    note = "Generated C++ and VU1 micro memories are compiled into ps2EntryRunner.exe. They are not in this folder. The player supplies their own ISO at launch (US tools/build_game.ps1 is the from-your-own-ISO build)."
}
[IO.File]::WriteAllText((Join-Path $dest ".package.json"), (($manifest | ConvertTo-Json -Depth 6) + "`r`n"), $utf8)
# The manifest is written after the guard. Scan it too; it is JSON and must not look like game data.
$manifestReason = Get-GameDataReason (Join-Path $dest ".package.json") ".package.json" (Get-Item -LiteralPath (Join-Path $dest ".package.json")).Length
if ($manifestReason) { "package REFUSED .package.json: $manifestReason"; exit 1 }
"ok .package.json"

$zipPath = New-FreeFile ($dest + ".zip")
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    $rootName = Split-Path -Leaf $dest
    Get-ChildItem -LiteralPath $dest -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($dest.Length).TrimStart('\') -replace '\\', '/'
        $entry = "$rootName/$rel"
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry, [IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $zip.Dispose() }

$zipCheck = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $badEntry = @()
    foreach ($e in $zipCheck.Entries) {
        $rel = $e.FullName
        $slash = $rel.IndexOf('/')
        if ($slash -ge 0) { $rel = $rel.Substring($slash + 1) }
        if (-not $rel -or $rel.EndsWith('/')) { continue }
        $reason = $null
        $leaf = [IO.Path]::GetFileName($rel)
        if ($script:Vu1Name.IsMatch($leaf) -or $script:DataBin.IsMatch($leaf) -or $script:SerialName.IsMatch($leaf)) { $reason = "name" }
        $ext = [IO.Path]::GetExtension($leaf.ToLowerInvariant())
        if ($script:DiscExt.ContainsKey($ext) -or $ext -eq ".irx" -or $script:RecompNames.ContainsKey($leaf)) { $reason = "name" }
        if ($script:SourceExt.ContainsKey($ext)) { $reason = "source" }
        if ($reason) { $badEntry += $e.FullName }
        else { "zip_ok $($e.FullName)" }
    }
} finally { $zipCheck.Dispose() }
if ($badEntry.Count -gt 0) {
    "zip REFUSED (left on disk, not deleted): $($badEntry -join ', ')"
    exit 1
}
"package $dest"
"zip $zipPath"
"dlls $($dlls.Count)"
"guard_refused 0"
exit 0
