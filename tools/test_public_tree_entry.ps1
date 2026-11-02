# Real publish entry tests. Retained synthetic fixtures only; no game data or images.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $PSScriptRoot 'publish_public_tree.ps1'
$scanner = Join-Path $PSScriptRoot 'public_tree_scan.ps1'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf) -or -not (Test-Path -LiteralPath $scanner -PathType Leaf)) {
    throw 'Publish entry and scanner must exist before this test can run.'
}
$work = Join-Path $root ('logs/public-publish-tests/safety-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$utf8 = New-Object Text.UTF8Encoding($false)
$checks = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Write-Text([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, $script:utf8)
}
function New-Source([string]$Name) {
    $path = Join-Path $script:work $Name
    [void][IO.Directory]::CreateDirectory($path)
    Write-Text (Join-Path $path 'LICENSE') "Synthetic author notice; GPL-3.0.`n"
    Write-Text (Join-Path $path 'README.md') "Synthetic public source fixture.`n"
    return $path
}
function Invoke-Publish([string[]]$Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:entry @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ Code = $code; Text = (($lines | ForEach-Object { $_.ToString() }) -join "`n") }
}

$source = New-Source 'clean-source'
Write-Text (Join-Path $source 'docs/placeholder.png') "Harmless text; no image content.`n"
Write-Text (Join-Path $source 'runtime/example.cpp') "// Synthetic source`nint value = 1;`n"
$out = Join-Path $work 'clean-output'
$result = Invoke-Publish @('-Source', $source, '-Out', $out)
Assert-True ($result.Code -eq 0) ('Clean export failed: ' + $result.Text)
Assert-True (Test-Path -LiteralPath (Join-Path $out 'LICENSE') -PathType Leaf) 'Clean export omitted LICENSE.'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $out 'docs/placeholder.png'))) 'Image suffix survived export.'
Assert-True ([IO.File]::ReadAllText((Join-Path $out 'runtime/example.cpp')) -eq [IO.File]::ReadAllText((Join-Path $source 'runtime/example.cpp'))) 'Ordinary source bytes changed.'
$result = Invoke-Publish @('-ScanOnly', $out)
Assert-True ($result.Code -eq 0) ('Clean staged scan failed: ' + $result.Text)

# A staged tree must be scanned without applying export omissions.
$imageScan = New-Source 'image-name-scan'
Write-Text (Join-Path $imageScan 'docs/placeholder.png') "Harmless text; no image content.`n"
$result = Invoke-Publish @('-ScanOnly', $imageScan)
Assert-True ($result.Code -ne 0) 'Scan accepted an image suffix.'

$secretSource = New-Source 'secret-source'
$fakeToken = 'gh' + 'p_' + ('a' * 36)
Write-Text (Join-Path $secretSource 'fixture.txt') ($fakeToken + "`n")
$secretOut = Join-Path $work 'secret-output'
$result = Invoke-Publish @('-Source', $secretSource, '-Out', $secretOut)
Assert-True ($result.Code -ne 0) 'Export accepted synthetic credential text.'
Assert-True (-not (Test-Path -LiteralPath $secretOut)) 'Failed credential preflight created output.'
Assert-True (-not $result.Text.Contains($fakeToken)) 'Error echoed credential-like input.'

$pathSource = New-Source 'path-source'
$fakePath = '/ho' + 'me/' + 'example/private'
Write-Text (Join-Path $pathSource 'fixture.txt') ($fakePath + "`n")
$result = Invoke-Publish @('-ScanOnly', $pathSource)
Assert-True ($result.Code -ne 0) 'Scan accepted a personal path.'
Assert-True (-not $result.Text.Contains($fakePath)) 'Error echoed path input.'

# Compressed IPv6 must not escape the privacy guard; safe scope operators stay usable.
$ipCases = @(
    ('2001:' + 'db8::42'),
    ('2001:' + 'db8::42' + '.'),
    ('fe80:' + ':42%eth0')
)
$ipIndex = 0
foreach ($value in $ipCases) {
    $ipSource = New-Source ('ipv6-source-' + $ipIndex)
    Write-Text (Join-Path $ipSource 'fixture.txt') ('remote = ' + $value + "`n")
    $result = Invoke-Publish @('-ScanOnly', $ipSource)
    Assert-True ($result.Code -ne 0) 'Scan accepted compressed nonloopback IPv6.'
    Assert-True (-not $result.Text.Contains($value)) 'Error echoed IPv6 input.'
    $ipIndex++
}
$safeNetworkSource = New-Source 'safe-network-source'
Write-Text (Join-Path $safeNetworkSource 'fixture.txt') ((('::' + '1') + "`n") + ('::' + "`n") + 'void scope::work() {}' + "`n")
$result = Invoke-Publish @('-ScanOnly', $safeNetworkSource)
Assert-True ($result.Code -eq 0) ('Loopback or source scope operator was refused: ' + $result.Text)
$rawPatchSource = New-Source 'raw-patch-source'
$address = 'synthetic' + '@' + 'example.invalid'
$rawPatch = "From: Synthetic <$address>`nSubject: [PATCH] fixture`n`nCo-Authored-By: Synthetic <$address>`n`ndiff --git a/a.txt b/a.txt`n--- a/a.txt`n+++ b/a.txt`n@@ -0,0 +1 @@`n+safe fixture`n"
Write-Text (Join-Path $rawPatchSource 'patches/01-fixture.patch') $rawPatch
$result = Invoke-Publish @('-ScanOnly', $rawPatchSource)
Assert-True ($result.Code -ne 0) 'Scan accepted raw patch mail metadata.'
Assert-True (-not $result.Text.Contains($address)) 'Error echoed patch address.'

$keep = Join-Path $out 'README.md'
$keepBytes = [IO.File]::ReadAllBytes($keep)
$result = Invoke-Publish @('-Source', $source, '-Out', $out)
Assert-True ($result.Code -ne 0) 'Existing nonempty output was accepted.'
Assert-True ([Convert]::ToBase64String($keepBytes) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($keep))) 'Existing output changed on refusal.'

$badOut = Join-Path $work 'unsafe-output'
$result = Invoke-Publish @('-Source', $source, '-Out', $badOut, '-Include', '../outside')
Assert-True ($result.Code -ne 0) 'Parent traversal include was accepted.'
Assert-True (-not (Test-Path -LiteralPath $badOut)) 'Unsafe include created output.'
$result = Invoke-Publish @('-Source', $source, '-Out', (Join-Path $work 'git-output'), '-Include', '.git')
Assert-True ($result.Code -ne 0) 'Git metadata include was accepted.'

$result = Invoke-Publish @('-Source', (Join-Path $work 'missing-source'), '-Out', (Join-Path $work 'missing-output'))
Assert-True ($result.Code -ne 0) 'Missing source was accepted.'
$noLicense = Join-Path $work 'no-license'
Write-Text (Join-Path $noLicense 'README.md') "Synthetic fixture only.`n"
$result = Invoke-Publish @('-Source', $noLicense, '-Out', (Join-Path $work 'no-license-output'))
Assert-True ($result.Code -ne 0) 'Source without root LICENSE was accepted.'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $work 'no-license-output'))) 'Missing LICENSE created output.'

$nestedSource = New-Source 'nested-source'
$nestedOut = Join-Path $nestedSource 'logs/staged'
$result = Invoke-Publish @('-Source', $nestedSource, '-Out', $nestedOut)
if ($result.Code -eq 0) {
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $nestedOut 'logs/staged'))) 'Nested output recursively included itself.'
    $result = Invoke-Publish @('-ScanOnly', $nestedOut)
    Assert-True ($result.Code -eq 0) 'Nested staging did not pass its scan.'
} else {
    Assert-True (-not (Test-Path -LiteralPath $nestedOut)) 'Nested-output refusal created output.'
}

# Signature checks stay in memory: no image or game bytes are written to this tree.
. $scanner
$magic = [byte[]](137,80,78,71,13,10,26,10)
$findings = @(Get-PublicFileFindings -Name 'renamed.txt' -Data $magic)
Assert-True ($findings.Count -gt 0) 'Scanner accepted a renamed PNG signature in memory.'
$magic = [byte[]](127,69,76,70,0,0,0,0)
$findings = @(Get-PublicFileFindings -Name 'renamed.txt' -Data $magic)
Assert-True ($findings.Count -gt 0) 'Scanner accepted a renamed ELF signature in memory.'
Write-Output ("PASS: public tree entry, {0} assertions. Synthetic fixtures retained under logs/public-publish-tests." -f $checks)
