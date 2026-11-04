# Windows compatibility entry point. Python owns the pipeline and us_tree selection.
param(
    [string]$Iso,
    [switch]$Force,
    [switch]$WhatIf,
    [string[]]$Steps,
    [string]$LogDir,
    [switch]$AcceptMicrosoftLicense
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'player_python.ps1')
Invoke-PlayerPython 'build_game.py' $PSBoundParameters
exit $LASTEXITCODE
