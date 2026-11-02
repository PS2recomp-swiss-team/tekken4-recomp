# Conservative guards for the public staging tool. No files are changed here.
# A clean scan does not establish copyright permission or licence compliance.

# Each content regex has its own deadline. This is not a whole-scan deadline.
# Never include the exception message: it can contain private input text.
function Test-PublicTextMatch {
    param([string]$Text, [string]$Pattern)
    try {
        return [regex]::IsMatch($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(2))
    } catch { throw 'text scan limit or failure; manual review required' }
}

function Get-PublicTextMatch {
    param([string]$Text, [string]$Pattern)
    try {
        return [regex]::Match($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(2))
    } catch { throw 'text scan limit or failure; manual review required' }
}

function Get-PublicTextMatches {
    param([string]$Text, [string]$Pattern)
    try {
        $found = [regex]::Matches($Text, $Pattern, [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromSeconds(2))
        # MatchCollection evaluates lazily; force it inside the guarded call.
        # Call the getter explicitly: PowerShell can suppress property errors.
        $null = $found.get_Count()
        return ,$found
    } catch { throw 'text scan limit or failure; manual review required' }
}

function Test-PublicImageName {
    param([string]$Name)
    return [IO.Path]::GetExtension($Name).ToLowerInvariant() -in @(
        '.png','.jpg','.jpeg','.gif','.webp','.bmp','.dib','.ico','.svg','.svgz',
        '.tif','.tiff','.avif','.heic','.heif','.dds','.tga','.psd','.xcf','.icns',
        '.pnm','.pbm','.pgm','.ppm','.apng','.jfif','.jxl','.exr','.hdr','.ktx','.ktx2','.cur','.qoi')
}

function Assert-PublicNoLinks {
    param([string]$Path)
    $candidate = [IO.Path]::GetFullPath($Path)
    while ($candidate) {
        if ([IO.File]::Exists($candidate) -or [IO.Directory]::Exists($candidate)) {
            $attributes = [IO.File]::GetAttributes($candidate)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'links/reparse points are not public staging paths'
            }
        }
        $parent = [IO.Path]::GetDirectoryName($candidate)
        if ($parent -eq $candidate) { break }
        $candidate = $parent
    }
}

function Get-PublicFileFindings {
    param([string]$Name, [byte[]]$Data, [switch]$Directory)
    $reasons = New-Object 'Collections.Generic.List[string]'
    $parts = $Name.Replace('\','/').Split('/')
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.StartsWith('/') -or $Name.Contains('\') -or
        @($parts | Where-Object { $_ -in @('','.','..') -or $_.Contains(':') -or $_ -match '[ .]$|[\x00-\x1f]' }).Count) {
        $reasons.Add('unsafe tree path')
    }
    foreach ($part in $parts) {
        if ($part -match '^(?i:con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)') {
            $reasons.Add('Windows device path'); break
        }
    }
    $suffix = [IO.Path]::GetExtension($Name).ToLowerInvariant()
    $leaf = $parts[-1].ToLowerInvariant()
    $directoryParts = if ($Directory) { $parts } else { @($parts | Select-Object -SkipLast 1) }
    if (-not $Directory -and (Test-PublicImageName $Name)) { $reasons.Add('image filename or content') }
    if ((-not $Directory -and ($suffix -in @('.iso','.elf','.bin','.img','.cso','.chd','.mdf','.nrg','.vob','.pss','.adx',
            '.vag','.irx','.ps2','.mcr','.psu','.zip','.7z','.rar','.gz','.tar','.exe','.dll','.pyd',
            '.o','.obj','.a','.lib','.so','.dat','.sav','.save','.mcd','.vmc','.gpr','.rep','.rom','.pkg') -or
        $leaf -in @('data.bin','system.cnf','rom0','rom1','rom2') -or
        $leaf -match '^(?:slus|sles|sces|slps|scps)[_-]\d')) -or
        @($directoryParts | Where-Object { $_ -in @('game','bios','saves','save','memcards') }).Count) {
        $reasons.Add('game data or binary/archive filename')
    }
    if ((-not $Directory -and ($suffix -in @('.key','.keys','.pem','.p12','.pfx','.kdbx') -or
        $leaf -in @('.env','id_rsa','id_ed25519','credentials'))) -or $parts -contains 'keys') {
        $reasons.Add('key or credential filename')
    }
    if ((-not $Directory -and $leaf -in @('.mcp.json','claude.md','codex_progress.md')) -or
        @($parts | Where-Object { $_ -in @('.git','.agents','.codex','.aws','lobby') }).Count) {
        $reasons.Add('private source path')
    }
    if (-not $Directory -and ($leaf -in @('register_functions.cpp','ps2_recompiled_functions.h','ps2_recompiled_stubs.h') -or
        $leaf -match '(?:func_[0-9a-f]{6,8}|_0x[0-9a-f]{6,8})\.(?:cpp|c|h|hpp)$|\.generated\.(?:cpp|h)$')) {
        $reasons.Add('generated game source filename')
    }
    if ($Data.Length -gt 32MB) { $reasons.Add('oversized input; manual review required'); return $reasons.ToArray() }
    $latin = [Text.Encoding]::GetEncoding(28591).GetString($Data)
    $magic = [BitConverter]::ToString($Data, 0, [Math]::Min(12,$Data.Length))
    if ($magic -match '^(?:89-50-4E-47-0D-0A-1A-0A|FF-D8-FF|47-49-46-38-37-61|47-49-46-38-39-61|42-4D|49-49-2A-00|4D-4D-00-2A|00-00-01-00|44-44-53-20)' -or
        ($latin.StartsWith('RIFF') -and $Data.Length -ge 12 -and $latin.Substring(8,4) -eq 'WEBP') -or
        (Test-PublicTextMatch $latin ('(?i)<sv' + 'g(?:\s|>)')) -or
        $latin.StartsWith('/* X' + 'PM */') -or (Test-PublicTextMatch $latin '(?i)^P[1-6][\r\n\t ]')) {
        $reasons.Add('image filename or content')
    }
    if ($magic -match '^(?:7F-45-4C-46|4D-5A|50-4B-03-04|50-4B-05-06|37-7A-BC-AF-27-1C|52-61-72-21|1F-8B)' -or
        ($Data.Length -ge 32774 -and $latin.Substring(32769,5) -eq 'CD001') -or
        ($Data.Length -ge 34822 -and $latin.Substring(34817,5) -eq 'CD001')) {
        $reasons.Add('game/executable/archive signature')
    }
    try { $text = (New-Object Text.UTF8Encoding($false,$true)).GetString($Data) }
    catch { $reasons.Add('non-UTF-8 or binary content; manual review required'); return @($reasons | Select-Object -Unique) }
    # Relative paths can disclose the same private values as file contents.
    # Content signatures and generated-code checks still inspect only bytes.
    $privacyText = $Name + "`n" + $text
    if (Test-PublicTextMatch $text '[\x00-\x08\x0b\x0e-\x1f]') { $reasons.Add('binary content; manual review required') }
    if (Test-PublicTextMatch $text ('(?i)data:ima' + 'ge/|<im' + 'g(?:\s|>)|!\[[^\]\r\n]*\]\s*[\[(]')) {
        $reasons.Add('embedded image or image reference; manual review required')
    }
    $secretPattern = '-----BEGIN (?:[A-Z0-9 ]*PRIVATE KEY|PGP PRIVATE KEY BLOCK)-----|' +
        '\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,})\b|' +
        '(?i:' + '\b(?:[a-z][a-z0-9_]*[_-])?(?:api[_-]?key|access[_-]?token|auth[_-]?token|password|private[_-]?key|signing[_-]?key|client[_-]?secret|secret|token)\b)["'']?\s*[:=]\s*(?:[rRuUbBfF]{0,2}["''](?![<{$])[^"''\r\n]{8,}["'']|[a-zA-Z0-9_/-]{20,})'
    # A blank prefix/suffix can be tested on the hash's own line. Crossing
    # newlines here would retry the same whitespace run from every blank line.
    if ((Test-PublicTextMatch $privacyText $secretPattern) -or
        (Test-PublicTextMatch $privacyText '(?m)^[^\S\n]*[0-9a-fA-F]{64}[^\S\n]*$')) {
        $reasons.Add('credential or private key content')
    }
    $personalPattern = '(?i)(?:\b[a-z]:[\\/]|(?<![a-z0-9_.\\/])\\\\[a-z0-9_.-]+[\\/]|/(?:home|Users)/[a-z0-9_.-]+|~[\\/])'
    $personalText = $privacyText
    # This exact diff is the reviewed guest CD-path example already pinned by
    # publish_source.py. Only this category is excepted, never the mail preamble.
    $diff = Get-PublicTextMatch $latin '(?m)^diff --git '
    if (-not $Directory -and $suffix -eq '.patch' -and $diff.Success) {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = [BitConverter]::ToString($sha.ComputeHash($Data,$diff.Index,$Data.Length-$diff.Index)).Replace('-','').ToLowerInvariant() }
        finally { $sha.Dispose() }
        if ($digest -eq '6e7e0b546efbde481c48910bf893cdc8b340475dc4d458f3e4094e9e2b276381') {
            $personalText = $Name + "`n" + [Text.Encoding]::UTF8.GetString($Data,0,$diff.Index)
        }
    }
    if (Test-PublicTextMatch $personalText $personalPattern) { $reasons.Add('personal or machine-specific path') }
    # Require the end of the token so C++ ::Block is not read as IPv6 ::B.
    # Compressed addresses are still checked even when they have few colons.
    $ipMatches = Get-PublicTextMatches $privacyText '(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])|(?<![\w:])(?:[0-9a-fA-F]{0,4}:){2,}[0-9a-fA-F:.]+(?:%[A-Za-z0-9_.-]+)?(?![\w:])'
    foreach ($match in $ipMatches) {
        $literal = $match.Value.Split('%')[0].TrimEnd('.')
        $address = $null
        if ([Net.IPAddress]::TryParse($literal,[ref]$address) -and
            -not [Net.IPAddress]::IsLoopback($address) -and
            -not $address.Equals([Net.IPAddress]::Any) -and -not $address.Equals([Net.IPAddress]::IPv6Any)) {
            $reasons.Add('literal network address'); break
        }
    }
    $publicHosts = @('github.com','www.github.com','api.github.com','raw.githubusercontent.com',
        'objects.githubusercontent.com','release-assets.githubusercontent.com','gnu.org','www.gnu.org',
        'fsf.org','www.fsf.org','ps2recomp.com','pcsx2.net','www.pcsx2.net','python.org','www.python.org',
        'docs.python.org','llvm.org','releases.llvm.org','cmake.org','aka.ms','download.visualstudio.microsoft.com',
        'go.microsoft.com','learn.microsoft.com','visualstudio.microsoft.com','www.microsoft.com','developer.microsoft.com',
        'virustotal.com','www.virustotal.com','docs.virustotal.com','spdx.org','opensource.org',
        'git-scm.com','www.git-scm.com','tailscale.com','www.tailscale.com')
    foreach ($match in (Get-PublicTextMatches $privacyText '(?i)\b(?:https?|wss?|tcp|udp)://[^\s<>"''`]+')) {
        $url = $null
        if (-not [Uri]::TryCreate($match.Value.TrimEnd('.,;)]}'.ToCharArray()), [UriKind]::Absolute, [ref]$url) -or
            $url.Scheme -notin @('http','https') -or $url.DnsSafeHost.ToLowerInvariant() -notin $publicHosts -or
            $url.UserInfo -or $url.Port -notin @(80,443)) {
            $reasons.Add('unreviewed server URL'); break
        }
    }
    foreach ($match in (Get-PublicTextMatches $privacyText '(?i)\b[A-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*\.)+[A-Z]{2,}\b')) {
        if (-not (Test-PublicTextMatch $match.Value '(?i)@(?:gnu|fsf)\.org$')) { $reasons.Add('email address; manual review required'); break }
    }
    if ((Test-PublicTextMatch $privacyText '(?i)(?:\b[a-z_]*(?:server|host|endpoint|lobby)[a-z_]*\b["'']?\s*[:=]\s*["'']?|--(?:server|host|lobby)(?:\s+|=))(?:[a-z0-9][a-z0-9.-]*\.[a-z]{2,}|localhost)(?=[:/\s"'']|$)') -or
        (Test-PublicTextMatch $privacyText '(?i)\b[a-z0-9](?:[a-z0-9-]*\.)+[a-z]{2,}:\d{1,5}\b')) {
        $reasons.Add('server hostname assignment')
    }
    if (-not $Directory -and $suffix -eq '.patch') {
        if (-not $diff.Success) { $reasons.Add('patch has no diff boundary') }
        if (Get-Command Get-PublicPatchHeaderFindings -ErrorAction SilentlyContinue) {
            foreach ($reason in @(Get-PublicPatchHeaderFindings $Data)) { $reasons.Add($reason) }
        } elseif ($diff.Success -and (Test-PublicTextMatch $latin.Substring(0,$diff.Index) '(?im)^[^\S\n]*Co-Authored-By\s*:')) {
            $reasons.Add('private patch mail header')
        }
    }
    # Both alternatives require one of these exact literals. Avoid repeatedly
    # searching every suffix of a long identifier when neither can match.
    $symbols = @()
    if ($text.Contains('func_') -or $text.Contains('_0x')) {
        $symbols = @((Get-PublicTextMatches $text '(?:func_[0-9a-fA-F]{6,8}|[A-Za-z_]\w*_0x[0-9a-fA-F]{6,8})') | ForEach-Object Value | Select-Object -Unique)
    }
    if ($symbols.Count -ge 64) {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = [BitConverter]::ToString($sha.ComputeHash($Data)).Replace('-','').ToLowerInvariant() }
        finally { $sha.Dispose() }
        if ($digest -ne 'c7cec562d2550f3e73f8a11f39b8b5bd9e3da28846bb7f6575424ccead034c91') {
            $reasons.Add('dense lifted game function names')
        }
    }
    # A comment may precede the marker across blank lines. Without a comment,
    # start on the marker's own line instead of retrying every earlier newline.
    if (Test-PublicTextMatch $text '(?im)^[^\S\n]*(?:(?://|/\*|#|\*)\s*)?(?:automatically generated|generated by (?:ps2recomp|ghidra))') {
        $reasons.Add('generated game code marker')
    }
    return @($reasons | Select-Object -Unique)
}

function Get-PublicTreeFindings {
    param([string]$Root)
    $full = [IO.Path]::GetFullPath($Root)
    Assert-PublicNoLinks $full
    if (-not [IO.Directory]::Exists($full)) { throw 'scan root must be an existing directory' }
    $prefix = $full.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $queue = New-Object 'Collections.Generic.Queue[string]'
    $queue.Enqueue($full)
    $seen = @{}
    while ($queue.Count) {
        $directory = $queue.Dequeue()
        foreach ($path in @([IO.Directory]::EnumerateFileSystemEntries($directory) | Sort-Object)) {
            Assert-PublicNoLinks $path
            $name = $path.Substring($prefix.Length).Replace('\','/')
            $key = $name.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { throw 'case-colliding staged paths' }
            $seen[$key] = $true
            if ([IO.Directory]::Exists($path)) {
                foreach ($reason in @(Get-PublicFileFindings -Name $name -Data ([byte[]]@()) -Directory)) {
                    [pscustomobject]@{Path=$name; Reason=$reason}
                }
                $queue.Enqueue($path)
                continue
            }
            if (-not [IO.File]::Exists($path)) { throw 'nonregular staged entry' }
            $info = New-Object IO.FileInfo($path)
            if ($info.Length -gt 32MB) {
                [pscustomobject]@{Path=$name; Reason='oversized input; manual review required'}
                continue
            }
            $data = [IO.File]::ReadAllBytes($path)
            foreach ($reason in @(Get-PublicFileFindings $name $data)) {
                [pscustomobject]@{Path=$name; Reason=$reason}
            }
        }
    }
}
