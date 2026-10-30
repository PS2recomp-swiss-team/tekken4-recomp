<#
.SYNOPSIS
  Make the dated Sunday source test zip from this working tree. No Git or build.
.DESCRIPTION
  The explicit build/test catalog is scanned with tools/publish_source.py before
  anything is written. A finding refuses the zip; selected source is never edited.
  The zip contains source only, no installed tools or game files.
.PARAMETER OutDir
  Output folder inside this tree. Default: dist\sunday. Existing zips stay intact.
.PARAMETER CheckOnly
  Scan the exact source catalog without creating a zip or directory.
#>
param([string]$OutDir = '', [switch]$CheckOnly)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$Root = Split-Path -Parent $PSScriptRoot
$Python = $null
$Prefix = @()
foreach ($Name in @('py', 'python', 'python3')) {
    $Command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $Command) { continue }
    $CandidatePrefix = if ($Name -eq 'py') { @('-3') } else { @() }
    try {
        & $Command.Source @CandidatePrefix -I -B -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>$null
        if ($LASTEXITCODE -eq 0) {
            $Python = $Command.Source
            $Prefix = @($CandidatePrefix)
            break
        }
    } catch { }
}
if (-not $Python) { throw 'Python 3.8+ fehlt. Python 3 installieren, Terminal neu oeffnen und erneut versuchen.' }
$Arguments = @($Prefix) + @('-I', '-B', (Join-Path $PSScriptRoot 'test_zip.py'), '--root', $Root)
if ($OutDir) { $Arguments += @('--out-dir', $OutDir) }
if ($CheckOnly) { $Arguments += '--check-only' }
& $Python @Arguments
if ($LASTEXITCODE -ne 0) { throw 'Test-Zip verweigert. Die oben genannten Quelldateien pruefen; es wurde nichts ueberschrieben.' }
