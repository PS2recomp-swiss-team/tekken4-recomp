# Synthetic patch tests through the actual publish entry point. No Git writes.
# Retain fixtures under logs; the owner decides their cleanup.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$helper = Join-Path $PSScriptRoot 'public_patch_headers.ps1'
$script:checks = 0
$encoding = [System.Text.Encoding]::GetEncoding(28591)

function Assert-PatchTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function Test-SameBytes {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Get-TestDiff {
    param([byte[]]$Data)
    $text = $encoding.GetString($Data)
    $match = [regex]::Match($text, '(?m)^diff --git ')
    if (-not $match.Success) { throw 'Test patch has no diff marker' }
    return ,$encoding.GetBytes($text.Substring($match.Index))
}

function Get-TestDigest {
    param([byte[]]$Data)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($sha.ComputeHash($Data)) }
    finally { $sha.Dispose() }
}

function Invoke-PublishEntry {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $entry @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String) }
}

try {
    if (-not (Test-Path -LiteralPath $entry -PathType Leaf) -or
        -not (Test-Path -LiteralPath $helper -PathType Leaf)) {
        throw 'Publish entry point and patch helper are required; no tests ran'
    }
    . $helper
    $fixtureRoot = Join-Path $repoRoot ('logs/public-publish-tests/patch-' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($fixtureRoot)
    $address = 'contributor' + '@' + 'example.invalid'
    $otherAddress = 'helper' + '@' + 'example.invalid'
    $cases = @(
        [pscustomobject]@{ Name = 'lf'; Newline = "`n"; Folded = $false },
        [pscustomobject]@{ Name = 'crlf-folded'; Newline = "`r`n"; Folded = $true },
        [pscustomobject]@{ Name = 'mixed'; Newline = "`n"; Folded = $false }
    )
    foreach ($case in $cases) {
        $nl = $case.Newline
        $from = 'From: Example Contributor <' + $address + '>'
        if ($case.Folded) { $from = 'From: Example Contributor' + $nl + ' <' + $address + '>' }
        $author = 'Author: Example Contributor <' + $address + '>'
        if ($case.Folded) { $author = 'Author: Example Contributor' + $nl + ' <' + $address + '>' }
        $coauthor = 'Co-Authored-By: Example Helper <' + $otherAddress + '>'
        if ($case.Folded) { $coauthor = '  co-authored-by: Example Helper <' + $otherAddress + '>' }
        $preamble = @(
            'From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001',
            $from,
            $author,
            'Date: Mon, 2 Nov 2026 00:00:00 +0000',
            'Subject: [PATCH] synthetic public export test',
            ('Reply-To: <' + $address + '>'),
            ('Message-ID: <synthetic-' + $address + '>'),
            ('X-Originating-Author: <' + $address + '>'),
            ' continued transport metadata',
            '',
            'Keep this explanatory paragraph and its copyright notice.',
            'Copyright Example Contributor; GPL-3.0.',
            $coauthor,
            ' continued synthetic trailer',
            '---',
            ' example.txt | 1 +',
            ''
        ) -join $nl
        $diffNl = $nl
        if ($case.Name -eq 'mixed') { $diffNl = "`r`n" }
        $diff = (@(
            'diff --git a/example.txt b/example.txt',
            'index 1111111..2222222 100644',
            '--- a/example.txt',
            '+++ b/example.txt',
            '@@ -0,0 +1,2 @@',
            '+Co-Authored-By: this is diff content, preserve it',
            '+From: this is also diff content',
            '-- ',
            '2.0.0'
        ) -join $diffNl) + $diffNl
        [byte[]]$original = $encoding.GetBytes($preamble + $nl + $diff)
        [byte[]]$originalCopy = $original.Clone()
        [byte[]]$cleaned = ConvertTo-PublicPatch -Data $original
        $cleanText = $encoding.GetString($cleaned)
        $head = $cleanText.Substring(0, [regex]::Match($cleanText, '(?m)^diff --git ').Index)
        Assert-PatchTest (Test-SameBytes $original $originalCopy) ($case.Name + ': helper mutated input')
        Assert-PatchTest (Test-SameBytes (Get-TestDiff $original) (Get-TestDiff $cleaned)) ($case.Name + ': diff bytes changed')
        Assert-PatchTest ((Get-TestDigest (Get-TestDiff $original)) -eq (Get-TestDigest (Get-TestDiff $cleaned))) ($case.Name + ': diff digest changed')
        Assert-PatchTest (-not $head.Contains($address) -and -not $head.Contains($otherAddress)) ($case.Name + ': address remains in header')
        Assert-PatchTest (-not [regex]::IsMatch($head, '(?im)^[\t ]*Co-Authored-By:')) ($case.Name + ': coauthor trailer remains')
        Assert-PatchTest (-not $head.Contains('continued synthetic trailer')) ($case.Name + ': folded coauthor trailer remains')
        Assert-PatchTest (-not [regex]::IsMatch($head, '(?im)^(?:Reply-To|Message-ID|X-Originating-Author):')) ($case.Name + ': transport header remains')
        Assert-PatchTest (-not $head.Contains('continued transport metadata')) ($case.Name + ': folded transport metadata remains')
        Assert-PatchTest ($head.Contains('From: Example Contributor')) ($case.Name + ': author display name lost')
        Assert-PatchTest ($head.Contains('Author: Example Contributor')) ($case.Name + ': Author field display name lost')
        Assert-PatchTest ($head.Contains('Copyright Example Contributor; GPL-3.0.')) ($case.Name + ': copyright notice changed')
        Assert-PatchTest (@(Get-PublicPatchHeaderFindings -Data $cleaned).Count -eq 0) ($case.Name + ': cleaned header is refused')
        Assert-PatchTest (@(Get-PublicPatchHeaderFindings -Data $original).Count -gt 0) ($case.Name + ': dirty header is accepted')

        $source = Join-Path $fixtureRoot ($case.Name + '/source')
        $stage = Join-Path $fixtureRoot ($case.Name + '/public')
        [void][System.IO.Directory]::CreateDirectory((Join-Path $source 'patches'))
        [System.IO.File]::WriteAllText((Join-Path $source 'LICENSE'), "Synthetic GPL-3.0 test notice.`n", [System.Text.UTF8Encoding]::new($false))
        $patchPath = Join-Path $source 'patches/01-synthetic.patch'
        [System.IO.File]::WriteAllBytes($patchPath, $original)
        $export = Invoke-PublishEntry -Arguments @('-Source', $source, '-Out', $stage)
        Assert-PatchTest ($export.ExitCode -eq 0) ($case.Name + ': real export entry failed')
        $publicPatch = Join-Path $stage 'patches/01-synthetic.patch'
        Assert-PatchTest ([System.IO.File]::Exists($publicPatch)) ($case.Name + ': patch missing from public tree')
        [byte[]]$written = [System.IO.File]::ReadAllBytes($publicPatch)
        Assert-PatchTest (Test-SameBytes (Get-TestDiff $original) (Get-TestDiff $written)) ($case.Name + ': staged diff bytes changed')
        Assert-PatchTest (Test-SameBytes $original ([System.IO.File]::ReadAllBytes($patchPath))) ($case.Name + ': source patch changed')
        Assert-PatchTest (Test-SameBytes $cleaned $written) ($case.Name + ': entry output differs from header helper')
        $scanClean = Invoke-PublishEntry -Arguments @('-ScanOnly', $stage)
        Assert-PatchTest ($scanClean.ExitCode -eq 0) ($case.Name + ': actual staged tree scan failed')
        $scanDirty = Invoke-PublishEntry -Arguments @('-ScanOnly', $source)
        Assert-PatchTest ($scanDirty.ExitCode -ne 0) ($case.Name + ': actual scan accepted private patch headers')
        Assert-PatchTest (-not $scanDirty.Output.Contains($address) -and -not $scanDirty.Output.Contains($otherAddress)) ($case.Name + ': refusal echoed address')
    }
    Write-Output ('PASS: {0} patch checks; three actual exports and six actual scans. Synthetic text fixtures retained under logs/public-publish-tests.' -f $script:checks)
    exit 0
}
catch {
    Write-Error ('Patch publication tests failed: ' + $_.Exception.Message) -ErrorAction Continue
    exit 1
}
