# Bounded, read-only source ZIP content checks. Never extract members.
# Producer identity, licences and player-package completeness are unproved.

function Get-PublicZipContentCrc32 {
    param([AllowEmptyCollection()][byte[]]$Content)

    # Use the existing ZIP writer's CRC implementation, without compiling code
    # or writing a file. The seekable, single-member buffer has its CRC at 14.
    # Content is already bounded to 32 MiB; this temporary buffer is bounded too.
    $memory = New-Object IO.MemoryStream
    $zip = $null
    $stream = $null
    try {
        $zip = New-Object IO.Compression.ZipArchive($memory, [IO.Compression.ZipArchiveMode]::Create, $true)
        $member = $zip.CreateEntry('crc', [IO.Compression.CompressionLevel]::NoCompression)
        $stream = $member.Open()
        $stream.Write($Content, 0, $Content.Length)
        $stream.Dispose()
        $stream = $null
        $zip.Dispose()
        $zip = $null
        return [BitConverter]::ToUInt32($memory.GetBuffer(), 14)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $zip) { $zip.Dispose() }
        $memory.Dispose()
    }
}

function Invoke-PublicZipScan {
    param([Parameter(Mandatory=$true)][string]$ArchivePath)

    $workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
    $path = [IO.Path]::GetFullPath($ArchivePath)
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Archive path outside this working copy refused.'
    }
    $current = $path
    while ($current.Length -ge $workspace.Length) {
        if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
            if ([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Archive reparse point refused.'
            }
        }
        if ($current.Equals($workspace, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    if (-not [IO.File]::Exists($path)) { throw 'Archive input must be an existing file.' }
    $null = [Reflection.Assembly]::LoadWithPartialName('System.IO.Compression')
    $file = $null
    $memory = $null
    $archive = $null
    try {
        # Deny writers/deletion for the exact bytes being hashed and scanned.
        $file = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ($file.Length -lt 22 -or $file.Length -gt 128MB) { throw 'Archive size limit or minimum ZIP size refused.' }
        $data = New-Object byte[] ([int]$file.Length)
        $read = 0
        while ($read -lt $data.Length) {
            $count = $file.Read($data, $read, $data.Length - $read)
            if (-not $count) { throw 'Archive read ended early.' }
            $read += $count
        }
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $digest = [BitConverter]::ToString($hasher.ComputeHash($data)).Replace('-','').ToLowerInvariant() }
        finally { $hasher.Dispose() }

        # A narrow ordinary-ZIP envelope avoids unbounded central-directory
        # parsing. ZIP64, split ZIPs, comments, descriptors and extra fields
        # need manual review. Every byte before the directory must belong to
        # one matching local header and its declared compressed member data.
        $end = $data.Length - 22
        if ([BitConverter]::ToUInt32($data,$end) -ne 0x06054b50 -or
            [BitConverter]::ToUInt16($data,$end+4) -ne 0 -or
            [BitConverter]::ToUInt16($data,$end+6) -ne 0 -or
            [BitConverter]::ToUInt16($data,$end+20) -ne 0) { throw 'Unsupported or malformed ZIP envelope.' }
        $entries = [int][BitConverter]::ToUInt16($data,$end+10)
        if ($entries -eq 0 -or $entries -gt 10000 -or
            [BitConverter]::ToUInt16($data,$end+8) -ne $entries) { throw 'ZIP entry count limit or split archive refused.' }
        $centralSize = [long][BitConverter]::ToUInt32($data,$end+12)
        $central = [long][BitConverter]::ToUInt32($data,$end+16)
        if ($central + $centralSize -ne $end) { throw 'Unsupported or malformed ZIP directory.' }
        $cursor = $central
        $regions = New-Object 'Collections.Generic.List[object]'
        $memberCrcs = New-Object 'Collections.Generic.List[uint32]'
        $declaredBytes = [long]0
        for ($index = 0; $index -lt $entries; $index++) {
            if ($cursor -lt 0 -or $cursor + 46 -gt $end -or
                [BitConverter]::ToUInt32($data,[int]$cursor) -ne 0x02014b50) { throw 'Malformed ZIP directory entry.' }
            $nameLength = [int][BitConverter]::ToUInt16($data,[int]$cursor+28)
            $extraLength = [int][BitConverter]::ToUInt16($data,[int]$cursor+30)
            $commentLength = [int][BitConverter]::ToUInt16($data,[int]$cursor+32)
            $flags = [int][BitConverter]::ToUInt16($data,[int]$cursor+8)
            $method = [int][BitConverter]::ToUInt16($data,[int]$cursor+10)
            $local = [long][BitConverter]::ToUInt32($data,[int]$cursor+42)
            if ($extraLength -or $commentLength -or ($flags -band 0xf7f9) -or $method -notin @(0,8) -or
                [BitConverter]::ToUInt16($data,[int]$cursor+34) -ne 0) { throw 'Unsupported ZIP metadata or encryption.' }
            if ($local + 30 -gt $central -or [BitConverter]::ToUInt32($data,[int]$local) -ne 0x04034b50 -or
                [BitConverter]::ToUInt16($data,[int]$local+28) -ne 0) { throw 'Unsupported or malformed ZIP local header.' }
            if ([BitConverter]::ToUInt16($data,[int]$local+26) -ne $nameLength -or
                $local + 30 + $nameLength -gt $central -or $cursor + 46 + $nameLength -gt $end) {
                throw 'ZIP local and central member names do not match.'
            }
            # Version, flags, method, timestamps, CRC and both lengths must
            # agree. Member bytes are checked against this CRC after reading.
            for ($field = 0; $field -lt 22; $field++) {
                if ($data[[int]$local+4+$field] -ne $data[[int]$cursor+6+$field]) {
                    throw 'ZIP local and central member metadata do not match.'
                }
            }
            for ($character = 0; $character -lt $nameLength; $character++) {
                if ($data[[int]$local+30+$character] -ne $data[[int]$cursor+46+$character]) {
                    throw 'ZIP local and central member names do not match.'
                }
            }
            $compressedSize = [long][BitConverter]::ToUInt32($data,[int]$cursor+20)
            $uncompressedSize = [long][BitConverter]::ToUInt32($data,[int]$cursor+24)
            if ($method -eq 0 -and $compressedSize -ne $uncompressedSize) {
                throw 'ZIP stored member lengths do not match.'
            }
            $memberCrcs.Add([BitConverter]::ToUInt32($data,[int]$cursor+16))
            $declaredBytes += $uncompressedSize
            if ($uncompressedSize -gt 32MB -or $declaredBytes -gt 128MB) {
                throw 'ZIP declared uncompressed size limit exceeded.'
            }
            $regionEnd = $local + 30 + $nameLength + $compressedSize
            if ($regionEnd -gt $central) { throw 'ZIP compressed member exceeds local bounds.' }
            $regions.Add([pscustomobject]@{Start=$local;End=$regionEnd})
            $cursor += 46 + $nameLength + $extraLength + $commentLength
            if ($cursor -gt $end) { throw 'Malformed ZIP directory bounds.' }
        }
        if ($cursor -ne $end) { throw 'ZIP directory count does not match its bounds.' }
        $covered = [long]0
        foreach ($region in @($regions | Sort-Object Start)) {
            if ($region.Start -ne $covered) { throw 'ZIP preamble, gap or overlapping members refused.' }
            $covered = $region.End
        }
        if ($covered -ne $central) { throw 'ZIP local members do not cover the archive prefix.' }

        $memory = New-Object IO.MemoryStream(,$data)
        $archive = New-Object IO.Compression.ZipArchive($memory, [IO.Compression.ZipArchiveMode]::Read, $true)
        if ($archive.Entries.Count -ne $entries) { throw 'ZIP directory count mismatch.' }
        $findings = New-Object 'Collections.Generic.List[object]'
        $paths = @{}
        $explicitPaths = @{}
        $files = 0
        $bytes = [long]0
        $index = 0
        foreach ($member in $archive.Entries) {
            $index++
            $name = $member.FullName
            $directory = $name.EndsWith('/')
            $relative = if ($directory) { $name.Substring(0,$name.Length-1) } else { $name }
            $parts = $relative.Split('/')
            if ([string]::IsNullOrWhiteSpace($relative) -or $name.StartsWith('/') -or $name.Contains('\') -or
                @($parts | Where-Object { $_ -in @('','.','..') -or $_ -match '[:<>"|?*\x00-\x1f]|[ .]$|^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)' }).Count) {
                $findings.Add([pscustomobject]@{Entry=$index;Reason='unsafe ZIP member path'})
                continue
            }
            $key = $relative.ToLowerInvariant()
            if ($explicitPaths.ContainsKey($key)) { throw 'Duplicate or case-colliding ZIP member.' }
            $explicitPaths[$key] = $true
            $prefix = ''
            for ($partIndex = 0; $partIndex -lt $parts.Length; $partIndex++) {
                if ($prefix) { $prefix += '/' }
                $prefix += $parts[$partIndex]
                $prefixKey = $prefix.ToLowerInvariant()
                $isDirectory = $directory -or $partIndex -lt $parts.Length-1
                if ($paths.ContainsKey($prefixKey)) {
                    $previous = $paths[$prefixKey]
                    if ($previous.Name -cne $prefix -or $previous.Directory -ne $isDirectory) {
                        throw 'Case collision or file-directory conflict in ZIP paths.'
                    }
                } else { $paths[$prefixKey] = [pscustomobject]@{Name=$prefix;Directory=$isDirectory} }
            }
            $attributes = [long]$member.ExternalAttributes -band 0xffffffffL
            $unixType = ($attributes -shr 16) -band 0xf000
            if (($attributes -band 0x400) -or $unixType -notin @(0,0x4000,0x8000) -or
                ($unixType -eq 0x4000 -and -not $directory) -or ($unixType -eq 0x8000 -and $directory)) {
                throw 'Linked or nonregular ZIP member refused.'
            }
            if ($directory) {
                if ($member.Length -ne 0) { throw 'ZIP directory contains unexpected data.' }
            } else {
                $files++
            }
            if ($member.Length -gt 32MB -or $member.Length -lt 0 -or $bytes + $member.Length -gt 128MB) {
                throw 'ZIP uncompressed size limit exceeded.'
            }
            $stream = $null
            $content = $null
            try {
                $stream = $member.Open()
                $content = New-Object IO.MemoryStream
                $buffer = New-Object byte[] 65536
                $actual = [long]0
                while (($count = $stream.Read($buffer,0,$buffer.Length)) -gt 0) {
                    $actual += $count
                    if ($actual -gt $member.Length -or $actual -gt 32MB -or $bytes + $actual -gt 128MB) {
                        throw 'ZIP actual uncompressed size limit exceeded.'
                    }
                    $content.Write($buffer,0,$count)
                }
                if ($actual -ne $member.Length) { throw 'ZIP member length mismatch.' }
                $memberBytes = $content.ToArray()
                if ((Get-PublicZipContentCrc32 $memberBytes) -ne $memberCrcs[$index-1]) {
                    throw 'ZIP member content CRC mismatch.'
                }
                $bytes += $actual
                if (-not $directory) {
                    foreach ($reason in @(Get-PublicFileFindings $relative $memberBytes)) {
                        $findings.Add([pscustomobject]@{Entry=$index;Reason=$reason})
                    }
                }
            } finally {
                if ($null -ne $content) { $content.Dispose() }
                if ($null -ne $stream) { $stream.Dispose() }
            }
        }
        if (-not $files) { throw 'ZIP contains no regular files.' }
        return [pscustomobject]@{Entries=$entries;Files=$files;Bytes=$bytes;Findings=$findings.ToArray();Sha256=$digest}
    } finally {
        if ($null -ne $archive) { $archive.Dispose() }
        if ($null -ne $memory) { $memory.Dispose() }
        if ($null -ne $file) { $file.Dispose() }
    }
}
