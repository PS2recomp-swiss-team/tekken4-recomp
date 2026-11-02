# Exercise the real ZIP scan entry. Fixtures contain harmless text only.
# Nothing is extracted, published, built or run from the scanned archives.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$entry = Join-Path $PSScriptRoot 'scan_public_zip.ps1'
$shell = Join-Path $PSHOME 'powershell.exe'
$work = Join-Path $root ('logs/public-zip-tests/entry-' + [Guid]::NewGuid().ToString('N'))
$checks = 0
$runs = 0
$retained = 0
$utf8 = New-Object Text.UTF8Encoding($false)

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}

function New-TextZip([string]$Name, [bool]$Nested) {
    $path = Join-Path $script:work $Name
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            $names = @('LICENSE', 'README.md')
            if ($Nested) {
                $null = $zip.CreateEntry('docs/')
                $null = $zip.CreateEntry('docs/nested/')
                $names += 'docs/nested/notes.txt'
            }
            foreach ($name in $names) {
                $member = $zip.CreateEntry($name)
                $memberStream = $member.Open()
                try {
                    $data = $script:utf8.GetBytes("Harmless public source test text.`n")
                    $memberStream.Write($data, 0, $data.Length)
                } finally { $memberStream.Dispose() }
            }
        } finally { $zip.Dispose() }
    } finally { $stream.Dispose() }
    return $path
}

function Invoke-ZipEntry([string[]]$Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $script:shell -NoProfile -ExecutionPolicy Bypass -File $script:entry @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    $script:runs++
    return [pscustomobject]@{ Code = $code; Text = (($output | ForEach-Object { $_.ToString() }) -join "`n") }
}

function Get-FileHashText([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FixtureInventory {
    return [string]::Join("`n", [string[]]@(Get-ChildItem -LiteralPath $script:work -Recurse -Force |
        Sort-Object FullName | ForEach-Object { $_.FullName.Substring($script:work.Length) }))
}

function Assert-NoDisclosure([string]$Text) {
    Assert-True (-not $Text.Contains($script:root)) 'ZIP scan printed the working-copy path.'
    Assert-True (-not $Text.Contains('README.md')) 'ZIP scan printed a member name.'
    Assert-True (-not $Text.Contains('Harmless public source test text.')) 'ZIP scan printed member content.'
}

try {
    if (-not [IO.File]::Exists($entry) -or -not [IO.File]::Exists($shell)) {
        throw 'ZIP scan entry and Windows PowerShell must exist before the tests run.'
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [void][IO.Directory]::CreateDirectory($work)

    foreach ($nested in @($false, $true)) {
        $name = if ($nested) { 'nested.zip' } else { 'plain.zip' }
        $archive = New-TextZip $name $nested
        $beforeHash = Get-FileHashText $archive
        $beforeInventory = Get-FixtureInventory
        $result = Invoke-ZipEntry @('-Archive', $archive)
        Assert-True ($result.Code -eq 0) ('Harmless text ZIP was refused: ' + $result.Text)
        Assert-True ($result.Text -match 'PASS: limited public-source ZIP content scan only') 'Pass output omitted the limited scan scope.'
        Assert-True ($result.Text -match 'UNRUN:.*Python.*launcher GUI.*build.*game.*two-PC') 'Pass output omitted unrun release checks.'
        Assert-True ($result.Text -match ('SHA256:\s*' + $beforeHash)) 'Pass output did not identify the scanned archive bytes.'
        $entries = if ($nested) { 5 } else { 2 }
        $files = if ($nested) { 3 } else { 2 }
        Assert-True ($result.Text -match ('SCANNED: entries ' + $entries + '; files ' + $files + '; bytes \d+\.')) 'Scanned entry/file counts differ from the fixture.'
        Assert-True ((Get-FileHashText $archive) -ceq $beforeHash) 'ZIP scan changed the input archive.'
        Assert-True ((Get-FixtureInventory) -ceq $beforeInventory) 'ZIP scan created, removed or extracted fixture entries.'
        Assert-NoDisclosure $result.Text
    }

    $badZip = Join-Path $work 'invalid.zip'
    [IO.File]::WriteAllText($badZip, "Harmless text, not a ZIP container.`n", $utf8)
    $badHash = Get-FileHashText $badZip
    $result = Invoke-ZipEntry @('-Archive', $badZip)
    Assert-True ($result.Code -eq 1 -and $result.Text -match 'REFUSED:') 'Invalid ZIP text was accepted.'
    Assert-True ((Get-FileHashText $badZip) -ceq $badHash) 'Invalid-input refusal changed the input.'
    Assert-NoDisclosure $result.Text

    $wrongExtension = Join-Path $work 'plain.txt'
    [IO.File]::WriteAllText($wrongExtension, "Harmless non-archive text.`n", $utf8)
    foreach ($argument in @($wrongExtension, (Join-Path $work 'missing.zip'))) {
        $result = Invoke-ZipEntry @('-Archive', $argument)
        Assert-True ($result.Code -eq 1 -and $result.Text -match 'REFUSED:') 'Missing/non-ZIP input was accepted.'
        Assert-NoDisclosure $result.Text
    }
    $result = Invoke-ZipEntry @('-Archive', '../DOES_NOT_EXIST_PUBLIC_ZIP.zip')
    Assert-True ($result.Code -eq 1 -and $result.Text -match 'archive must stay inside this working copy') 'Outside-tree archive was not refused by the boundary check.'
    Assert-True ($result.Text -notmatch 'SCANNED:|SHA256:') 'Outside-tree refusal reached archive scanning.'
    Assert-NoDisclosure $result.Text

    $result = Invoke-ZipEntry @()
    Assert-True ($result.Code -eq 1 -and $result.Text -match 'REFUSED:') 'Absent archive argument was not refused.'
    Assert-NoDisclosure $result.Text

    # These retained historical source-test ZIPs are optional, not release payloads.
    $archiveDirectory = Join-Path $root 'dist/sunday'
    if ([IO.Directory]::Exists($archiveDirectory)) {
        foreach ($archive in @(Get-ChildItem -LiteralPath $archiveDirectory -Filter 'tekken4-sunday-test-*.zip' -File)) {
            $beforeHash = Get-FileHashText $archive.FullName
            $result = Invoke-ZipEntry @('-Archive', $archive.FullName)
            Assert-True ($result.Code -eq 1 -and $result.Text -match 'REFUSED: member \d+:') 'Historical source-test ZIP no longer produced the expected content refusal; review it before changing this expectation.'
            Assert-True ($result.Text -match 'SCANNED:') 'Historical source-test ZIP content scan did not complete.'
            Assert-True ((Get-FileHashText $archive.FullName) -ceq $beforeHash) 'Historical ZIP scan changed the archive.'
            Assert-NoDisclosure $result.Text
            $retained++
        }
    }
    Write-Output ("PASS: public ZIP entry; {0} assertions, {1} subprocesses, {2} retained source-test archives refused. Harmless fixtures retained under logs/public-zip-tests." -f $checks, $runs, $retained)
    Write-Output 'UNRUN: Python release tools, launcher GUI, build, game and two-PC play. These tests do not approve a release.'
    exit 0
} catch {
    Write-Output ('FAIL: public ZIP entry tests: ' + $_.Exception.Message)
    exit 1
}
