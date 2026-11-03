# Exercise the real readiness entry in subprocesses. No launcher is substituted.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$shell = Join-Path $PSHOME 'powershell.exe'
$entry = Join-Path $PSScriptRoot 'check_online_readiness.ps1'

function Invoke-Readiness([string[]]$Arguments = @()) {
    $output = @(& $shell -NoProfile -ExecutionPolicy Bypass -File $entry @Arguments 2>&1)
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($output -join "`n") }
}

try {
    $result = Invoke-Readiness
    if ($result.Code -ne 2 -or $result.Text -notmatch 'SOURCE checks completed' -or
        $result.Text -notmatch 'BLOCKED: online acceptance' -or $result.Text -notmatch 'UNRUN:') {
        Write-Output $result.Text
        throw 'Real readiness entry did not report checked sources and blocked acceptance.'
    }
    Write-Output 'PASS: real readiness entry exits 2 after source/catalog/starter checks; acceptance stays BLOCKED.'
    foreach ($doc in @('docs/DOES_NOT_EXIST_ONLINE.md', '../AGENTS.md')) {
        $result = Invoke-Readiness @('-Docs', $doc)
        if ($result.Code -ne 1 -or $result.Text -notmatch 'FAIL: online source check stopped' -or
            $result.Text -match 'ENTRY:') {
            throw 'Invalid document was not refused before child entry execution.'
        }
        Write-Output 'PASS: real readiness entry refuses missing/outside-tree document before child entry execution.'
    }
    Write-Output 'Readiness entry tests passed: 3 subprocesses. GUI, game, Python suites and online play remain UNRUN.'
    exit 0
} catch {
    Write-Output "FAIL: readiness entry tests stopped: $($_.Exception.Message)"
    exit 1
}
