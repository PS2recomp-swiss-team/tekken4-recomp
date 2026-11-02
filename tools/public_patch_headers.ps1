# Patch mail metadata only. The first diff line and every following byte stay intact.

function Get-PublicPatchParts {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Data)
    $marker = [Text.Encoding]::ASCII.GetBytes('diff --git ')
    $boundary = -1
    for ($i = 0; $i -le $Data.Length - $marker.Length; $i++) {
        if ($i -gt 0 -and $Data[$i - 1] -ne 10) { continue }
        $match = $true
        for ($j = 0; $j -lt $marker.Length; $j++) {
            if ($Data[$i + $j] -ne $marker[$j]) { $match = $false; break }
        }
        if ($match) { $boundary = $i; break }
    }
    if ($boundary -lt 0) { throw 'patch has no diff boundary' }
    # Latin-1 gives an exact byte-to-character map. Do not decode/re-encode the diff.
    $encoding = [Text.Encoding]::GetEncoding(28591)
    [pscustomobject]@{
        Boundary = $boundary
        Preamble = $encoding.GetString($Data, 0, $boundary)
        Encoding = $encoding
    }
}

function Get-PublicPatchHeaderFindings {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Data)
    try { $parts = Get-PublicPatchParts -Data $Data }
    catch { return 'patch has no diff boundary' }
    if ($parts.Preamble -match '(?im)^[\t ]*Co-Authored-By\s*:') {
        'patch coauthor mail trailer'
    }
    if ($parts.Preamble -match '(?im)^(?:Reply-To|Sender|Return-Path|Message-ID|Resent-[A-Za-z-]+|X-[A-Za-z-]+|Received|To|Cc|Bcc)\s*:') {
        'patch mail transport header'
    }
    foreach ($header in [regex]::Matches($parts.Preamble, '(?im)^(?:From|Author)\s*:[^\r\n]*(?:\r?\n[\t ][^\r\n]*)*')) {
        if ($header.Value -match '[<>@]') {
            'patch author mailbox'
            break
        }
    }
}

function ConvertTo-PublicPatch {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Data)
    $parts = Get-PublicPatchParts -Data $Data
    $builder = New-Object Text.StringBuilder
    $skipContinuation = $false
    $mailHeaders = $false
    $first = $true
    foreach ($match in [regex]::Matches($parts.Preamble, '[^\n]*(?:\n|$)')) {
        $line = $match.Value
        if ($line.Length -eq 0) { continue }
        $content = $line.TrimEnd([char[]]"`r`n")
        $ending = $line.Substring($content.Length)
        if ($first) {
            $mailHeaders = $content -match '(?i)^From(?: [0-9a-f]+ |\s*:)'
            $first = $false
        }
        if ($content -match '(?i)^[\t ]*Co-Authored-By\s*:') {
            $skipContinuation = $true
            continue
        }
        if ($content -match '^\s' -and $skipContinuation) { continue }
        $skipContinuation = $false
        if ($mailHeaders -and $content.Length -eq 0) { $mailHeaders = $false }
        if ($mailHeaders -and $content -match '(?i)^(?:Reply-To|Sender|Return-Path|Message-ID|Resent-[A-Za-z-]+|X-[A-Za-z-]+|Received|To|Cc|Bcc)\s*:') {
            $skipContinuation = $true
            continue
        }
        if ($mailHeaders -and $content -match '(?i)^(From|Author)\s*:\s*(.*)$') {
            $field = $matches[1]
            $display = $matches[2] -replace '<[^>]*>', ''
            $display = ($display -replace '\S*@\S*', '').Trim([char[]]' "')
            if (-not $display) { $display = 'T4 contributors' }
            [void]$builder.Append($field + ': ' + $display + $ending)
            # A folded From field can contain the mailbox too.
            $skipContinuation = $true
            continue
        }
        [void]$builder.Append($line)
    }
    $preamble = $parts.Encoding.GetBytes($builder.ToString())
    $result = New-Object byte[] ($preamble.Length + $Data.Length - $parts.Boundary)
    [Array]::Copy($preamble, 0, $result, 0, $preamble.Length)
    [Array]::Copy($Data, $parts.Boundary, $result, $preamble.Length, $Data.Length - $parts.Boundary)
    return ,$result
}
