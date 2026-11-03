<#
.SYNOPSIS
  Prepare the path-B player zip from reviewed local inputs. No Git or game build.
.DESCRIPTION
  Uses package_release.py, including its input locks, private Python/Tk check,
  folder/zip scans and checksums. It does not fetch missing inputs or replace a
  failed portable package with a source zip. Packaging starts the supplied
  Python/Tk for its isolation check; it never starts the game.

  Without prepared path-B inputs, use make_test_zip.ps1 explicitly for a source
  test zip. Players then need Python 3.8+, Git, CMake 3.20+, Ninja and Visual
  Studio 2022 Build Tools (Desktop development with C++, MSVC v143 x64/x86 and
  Windows SDK). Both online players need the same compiler version and source.
  That fallback is not the portable player release or proof of launcher support.
.PARAMETER Inputs
  Owner-reviewed input-lock JSON; see docs/RELEASE_DOWNLOADS.md.
.PARAMETER Version
  Unique beta version, for example 0.1.0-beta.1.
.PARAMETER Stage
  New staging folder. Defaults to release-output/T4-<Version> in this tree.
.PARAMETER Zip
  New archive path. Defaults to release-output/T4-<Version>.zip in this tree.
.PARAMETER ScanOnly
  Scan an existing staged folder or zip without packaging. Cannot be combined
  with Inputs, Version, Stage or Zip.
.EXAMPLE
  .\tools\make_player_zip.ps1 -Inputs release-inputs\inputs.json -Version 0.1.0-beta.1
.EXAMPLE
  .\tools\make_player_zip.ps1 -ScanOnly release-output\T4-0.1.0-beta.1.zip
#>
param(
    [string]$Inputs = '',
    [string]$Version = '',
    [string]$Stage = '',
    [string]$Zip = '',
    [string]$ScanOnly = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$Root = Split-Path -Parent $PSScriptRoot

if ($ScanOnly) {
    if ($Inputs -or $Version -or $Stage -or $Zip) {
        throw '-ScanOnly cannot be combined with packaging arguments.'
    }
    if (-not (Test-Path -LiteralPath $ScanOnly)) {
        throw "Scan target does not exist: $ScanOnly. Supply an existing staged folder or zip."
    }
} else {
    if (-not $Inputs -or -not $Version) {
        throw @'
Path B needs -Inputs <reviewed inputs.json> and -Version <unique beta version>.
Prepare the payloads, hashes and licence texts in docs/RELEASE_DOWNLOADS.md first.
No portable zip has been made. No automatic fallback or download was attempted.
For a source test zip only: tools\make_test_zip.ps1
That route requires Python 3.8+, Git, CMake 3.20+, Ninja and VS 2022 Build Tools:
Desktop development with C++, MSVC v143 x64/x86 and Windows SDK.
Use the same compiler version on both online PCs. See TEST_ONLINE_DE.txt.
'@
    }
    if ($Version -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw 'Version must contain only letters, numbers, dots, underscores and hyphens.'
    }
    if (-not (Test-Path -LiteralPath $Inputs -PathType Leaf)) {
        throw "Reviewed input-lock JSON not found: $Inputs. See docs/RELEASE_DOWNLOADS.md."
    }
    if (-not $Stage) { $Stage = Join-Path $Root ("release-output\T4-" + $Version) }
    if (-not $Zip) { $Zip = Join-Path $Root ("release-output\T4-" + $Version + '.zip') }
}

$PackageScript = Join-Path $PSScriptRoot 'package_release.py'
if (-not (Test-Path -LiteralPath $PackageScript -PathType Leaf)) {
    throw 'Missing tools/package_release.py. Use a complete source checkout; no package or scan was attempted.'
}

$Python = $null
$Prefix = @()
foreach ($Name in @('py', 'python', 'python3')) {
    $Command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $Command) { continue }
    $CandidatePrefix = if ($Name -eq 'py') { @('-3') } else { @() }
    try {
        & $Command.Source @CandidatePrefix -I -B -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' 2>$null
        if ($LASTEXITCODE -eq 0) {
            $Python = $Command.Source
            $Prefix = @($CandidatePrefix)
            break
        }
    } catch { }
}
if (-not $Python) { throw 'Path-B packaging requires Python 3.12+ on the maintainer PC; see docs/RELEASE_DOWNLOADS.md.' }

$Arguments = @($Prefix) + @('-I', '-B', $PackageScript)
if ($ScanOnly) {
    $Arguments += @('--scan-only', $ScanOnly)
} else {
    $Arguments += @('--inputs', $Inputs, '--version', $Version, '--stage', $Stage, '--zip', $Zip)
}
& $Python @Arguments
if ($LASTEXITCODE -ne 0) {
    throw 'Path-B packaging/scan refused. Review the error and any retained partial outputs. No source fallback was substituted.'
}
if (-not $ScanOnly) {
    Write-Output 'Path-B candidate prepared. Review checksums and licences; clean-PC, shared-launcher and two-PC game tests still gate release.'
}
