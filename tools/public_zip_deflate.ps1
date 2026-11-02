# Raw DEFLATE framing checks for the bounded source ZIP reader.
# This counts output; ZipArchive still supplies and CRC-checks the actual bytes.

function Read-PublicDeflateBits {
    param($State, [int]$Count)

    if ($State.Bit + $Count -gt $State.EndBit) { throw 'Truncated ZIP DEFLATE stream.' }
    $value = 0
    for ($index = 0; $index -lt $Count; $index++) {
        $position = $State.Bit + $index
        $value = $value -bor ((($State.Data[$position -shr 3] -shr ($position -band 7)) -band 1) -shl $index)
    }
    $State.Bit += $Count
    return $value
}

function New-PublicDeflateTable {
    param([int[]]$Lengths, [bool]$AllowSingle, [bool]$AllowEmpty)

    $counts = New-Object int[] 16
    $maximum = 0
    foreach ($length in $Lengths) {
        if ($length -lt 0 -or $length -gt 15) { throw 'Invalid ZIP DEFLATE code length.' }
        if ($length) {
            $counts[$length]++
            if ($length -gt $maximum) { $maximum = $length }
        }
    }
    if (-not $maximum) {
        if (-not $AllowEmpty) { throw 'Empty ZIP DEFLATE code tree.' }
        return [pscustomobject]@{ Codes=(New-Object int[] 1); Mask=0; Maximum=0 }
    }
    $left = 1
    for ($length = 1; $length -le 15; $length++) {
        $left = ($left -shl 1) - $counts[$length]
        if ($left -lt 0) { throw 'Oversubscribed ZIP DEFLATE code tree.' }
    }
    if ($left -ne 0 -and -not ($AllowSingle -and $maximum -eq 1 -and $counts[1] -eq 1)) {
        throw 'Incomplete ZIP DEFLATE code tree.'
    }
    $next = New-Object int[] 16
    $code = 0
    for ($length = 1; $length -le 15; $length++) {
        $code = ($code + $counts[$length-1]) -shl 1
        $next[$length] = $code
    }
    $size = 1 -shl $maximum
    $codes = New-Object int[] $size
    for ($symbol = 0; $symbol -lt $Lengths.Length; $symbol++) {
        $length = $Lengths[$symbol]
        if (-not $length) { continue }
        $normal = $next[$length]
        $next[$length]++
        $reverse = 0
        for ($bit = 0; $bit -lt $length; $bit++) {
            $reverse = ($reverse -shl 1) -bor (($normal -shr $bit) -band 1)
        }
        $packed = ($length -shl 16) -bor ($symbol + 1)
        $step = 1 -shl $length
        for ($slot = $reverse; $slot -lt $size; $slot += $step) { $codes[$slot] = $packed }
    }
    return [pscustomobject]@{ Codes=$codes; Mask=($size-1); Maximum=$maximum }
}

function Read-PublicDeflateSymbol {
    param($State, $Table)

    # Peek at most three bytes. Zero padding the lookup is safe only when the
    # selected code's actual length still fits in the bounded member stream.
    $position = [int]$State.Bit
    $byte = $position -shr 3
    $last = ($State.EndBit -shr 3)
    $bits = 0
    if ($byte -lt $last) { $bits = [int]$State.Data[$byte] }
    if ($byte + 1 -lt $last) { $bits = $bits -bor ([int]$State.Data[$byte+1] -shl 8) }
    if ($byte + 2 -lt $last) { $bits = $bits -bor ([int]$State.Data[$byte+2] -shl 16) }
    $packed = $Table.Codes[($bits -shr ($position -band 7)) -band $Table.Mask]
    $length = $packed -shr 16
    if (-not $length -or $position + $length -gt $State.EndBit) { throw 'Invalid or truncated ZIP DEFLATE code.' }
    $State.Bit += $length
    return (($packed -band 0xffff) - 1)
}

function Assert-PublicZipDeflate {
    param(
        [Parameter(Mandatory=$true)][byte[]]$Data,
        [Parameter(Mandatory=$true)][int]$Offset,
        [Parameter(Mandatory=$true)][int]$Length,
        [Parameter(Mandatory=$true)][long]$ExpectedLength
    )

    if ($Offset -lt 0 -or $Length -lt 1 -or [long]$Offset + $Length -gt $Data.Length -or
        $Data.Length -gt 128MB -or $ExpectedLength -lt 0 -or $ExpectedLength -gt 32MB) {
        throw 'ZIP DEFLATE bounds refused.'
    }
    $state = [pscustomobject]@{ Data=$Data; Bit=($Offset*8); EndBit=(($Offset+$Length)*8) }
    $produced = [long]0
    $fixedLiteral = $null
    $fixedDistance = $null
    $lengthBase = @(3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258)
    $lengthExtra = @(0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0)
    $distanceBase = @(1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577)
    $distanceExtra = @(0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13)
    # RFC 1951's nineteen code-length symbols in transmission order.
    $order = @(16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15)
    do {
        $final = Read-PublicDeflateBits $state 1
        $type = Read-PublicDeflateBits $state 2
        if ($type -eq 0) {
            $state.Bit = ($state.Bit + 7) -band -8
            $stored = Read-PublicDeflateBits $state 16
            $complement = Read-PublicDeflateBits $state 16
            if (($stored -bxor $complement) -ne 0xffff) { throw 'Invalid ZIP DEFLATE stored length.' }
            if ($state.Bit + $stored*8 -gt $state.EndBit) { throw 'Truncated ZIP DEFLATE stored block.' }
            $state.Bit += $stored*8
            $produced += $stored
        } elseif ($type -in @(1,2)) {
            if ($type -eq 1) {
                if ($null -eq $fixedLiteral) {
                    $lengths = New-Object int[] 288
                    for ($symbol = 0; $symbol -lt 288; $symbol++) {
                        $lengths[$symbol] = if ($symbol -le 143) { 8 } elseif ($symbol -le 255) { 9 } elseif ($symbol -le 279) { 7 } else { 8 }
                    }
                    $fixedLiteral = New-PublicDeflateTable $lengths $false $false
                    $lengths = New-Object int[] 32
                    for ($symbol = 0; $symbol -lt 32; $symbol++) { $lengths[$symbol] = 5 }
                    $fixedDistance = New-PublicDeflateTable $lengths $false $false
                }
                $literal = $fixedLiteral
                $distance = $fixedDistance
            } else {
                $literalCount = 257 + (Read-PublicDeflateBits $state 5)
                $distanceCount = 1 + (Read-PublicDeflateBits $state 5)
                $codeCount = 4 + (Read-PublicDeflateBits $state 4)
                if ($literalCount -gt 286) { throw 'Invalid ZIP DEFLATE literal count.' }
                $codeLengths = New-Object int[] 19
                for ($index = 0; $index -lt $codeCount; $index++) {
                    $codeLengths[$order[$index]] = Read-PublicDeflateBits $state 3
                }
                $codeTable = New-PublicDeflateTable $codeLengths $false $false
                $lengths = New-Object int[] ($literalCount+$distanceCount)
                $index = 0
                while ($index -lt $lengths.Length) {
                    $symbol = Read-PublicDeflateSymbol $state $codeTable
                    if ($symbol -lt 16) {
                        $lengths[$index] = $symbol
                        $index++
                    } else {
                        if ($symbol -eq 16) {
                            if (-not $index) { throw 'ZIP DEFLATE repeat lacks a previous length.' }
                            $value = $lengths[$index-1]
                            $repeat = 3 + (Read-PublicDeflateBits $state 2)
                        } elseif ($symbol -eq 17) {
                            $value = 0
                            $repeat = 3 + (Read-PublicDeflateBits $state 3)
                        } elseif ($symbol -eq 18) {
                            $value = 0
                            $repeat = 11 + (Read-PublicDeflateBits $state 7)
                        } else { throw 'Invalid ZIP DEFLATE length symbol.' }
                        if ($index + $repeat -gt $lengths.Length) { throw 'ZIP DEFLATE code-length repeat exceeds bounds.' }
                        for ($copy = 0; $copy -lt $repeat; $copy++) { $lengths[$index+$copy] = $value }
                        $index += $repeat
                    }
                }
                if (-not $lengths[256]) { throw 'ZIP DEFLATE end code missing.' }
                $literal = New-PublicDeflateTable $lengths[0..($literalCount-1)] $true $false
                $distance = New-PublicDeflateTable $lengths[$literalCount..($lengths.Length-1)] $true $true
            }
            # Keep the common literal path in this loop. Per-symbol PowerShell
            # function binding is expensive on ordinary source archives.
            $literalCodes = $literal.Codes
            $literalMask = $literal.Mask
            $position = [int]$state.Bit
            $endBit = [int]$state.EndBit
            $lastByte = $endBit -shr 3
            while ($true) {
                $byte = $position -shr 3
                $bits = 0
                if ($byte -lt $lastByte) { $bits = [int]$Data[$byte] }
                if ($byte + 1 -lt $lastByte) { $bits = $bits -bor ([int]$Data[$byte+1] -shl 8) }
                if ($byte + 2 -lt $lastByte) { $bits = $bits -bor ([int]$Data[$byte+2] -shl 16) }
                $packed = $literalCodes[($bits -shr ($position -band 7)) -band $literalMask]
                $codeLength = $packed -shr 16
                if (-not $codeLength -or $position + $codeLength -gt $endBit) { throw 'Invalid or truncated ZIP DEFLATE code.' }
                $position += $codeLength
                $symbol = ($packed -band 0xffff) - 1
                if ($symbol -eq 256) { break }
                if ($symbol -lt 256) { $produced++ }
                elseif ($symbol -le 285) {
                    $state.Bit = $position
                    $lengthIndex = $symbol-257
                    $run = $lengthBase[$lengthIndex] + (Read-PublicDeflateBits $state $lengthExtra[$lengthIndex])
                    $distanceSymbol = Read-PublicDeflateSymbol $state $distance
                    if ($distanceSymbol -gt 29) { throw 'Reserved ZIP DEFLATE distance symbol.' }
                    $back = $distanceBase[$distanceSymbol] + (Read-PublicDeflateBits $state $distanceExtra[$distanceSymbol])
                    if ($back -gt $produced) { throw 'ZIP DEFLATE distance exceeds output history.' }
                    $produced += $run
                    $position = [int]$state.Bit
                } else { throw 'Reserved ZIP DEFLATE literal symbol.' }
                if ($produced -gt $ExpectedLength) { throw 'ZIP DEFLATE output exceeds declared length.' }
            }
            $state.Bit = $position
        } else { throw 'Reserved ZIP DEFLATE block type.' }
        if ($produced -gt $ExpectedLength) { throw 'ZIP DEFLATE output exceeds declared length.' }
    } while (-not $final)
    # Only unused bits in the final byte are permitted, never trailing bytes.
    if ((($state.Bit + 7) -shr 3) -ne $Offset+$Length) { throw 'Trailing ZIP DEFLATE bytes refused.' }
    if ($produced -ne $ExpectedLength) { throw 'ZIP DEFLATE output length mismatch.' }
}
