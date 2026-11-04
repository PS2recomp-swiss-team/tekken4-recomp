# Windows compatibility entry point. Python owns the pipeline and us_tree selection.
param([Alias("Host")][switch]$AsHost, [string]$Join = "", [ValidateRange(1,65535)][int]$Port = 7400,
      [int]$Pad = 0, [string]$Delay = "auto", [int]$Sound = 1, [string]$Sim = "", [string]$RunDir = "",
      [string]$Src = $env:TEKKEN4_SRC, [string]$BuildDir = $env:TEKKEN4_BUILD_DIR,
      [Alias("IsoPath")][string]$Iso = $env:TEKKEN4_ISO, [switch]$NoDiagnostics,
      [switch]$SkipPreflight, [ValidateRange(5,600)][int]$PreflightTimeoutSeconds = 90,
      [switch]$UseInheritedProfile)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'player_python.ps1')
Invoke-PlayerPython 'net_play.py' $PSBoundParameters
exit $LASTEXITCODE
