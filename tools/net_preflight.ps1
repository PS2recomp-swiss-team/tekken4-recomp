# Dot-source compatibility API. The T4TEST1 implementation lives in net_preflight.py.
. (Join-Path $PSScriptRoot 'player_python.ps1')
function Invoke-T4PythonRequest($Request) {
    $py = Get-PlayerPython
    $savedEncoding = $OutputEncoding
    $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    try {
        $raw = ($Request | ConvertTo-Json -Depth 8 -Compress) | & $py.Exe @($py.Pre) -I -X utf8 (Join-Path $PSScriptRoot 'net_preflight.py') --request
    } finally { $OutputEncoding = $savedEncoding }
    $response = $raw | ConvertFrom-Json
    foreach ($line in $response.messages) { Write-Host $line }
    if ($response.error) { throw $response.error }
    return $response.result
}
function ConvertTo-T4NetIdentity {
    param($Value)
    Invoke-T4PythonRequest @{ operation = 'identity'; value = $Value }
}
function New-T4NetIdentity {
    param([Parameter(Mandatory=$true)][string]$BuildStampJson,
          [Parameter(Mandatory=$true)][string]$IsoPath)
    Invoke-T4PythonRequest @{ operation = 'new'; stamp = $BuildStampJson; iso = $IsoPath }
}
function Compare-T4NetIdentity {
    param($Local, $Peer)
    Invoke-T4PythonRequest @{ operation = 'compare'; local = $Local; peer = $Peer }
}
function Resolve-T4NetPeer {
    param([Parameter(Mandatory=$true)][string]$Peer)
    Invoke-T4PythonRequest @{ operation = 'resolve'; peer = $Peer }
}
function Invoke-T4NetPreflight {
    param([bool]$AsHost, [string]$Peer = '', [ValidateRange(1,65535)][int]$Port = 7400,
          [Parameter(Mandatory=$true)]$Identity,
          [ValidateRange(5,600)][int]$TimeoutSeconds = 90,
          [Parameter(Mandatory=$true)][string]$OutputPath)
    $null = Invoke-T4PythonRequest @{ operation = 'preflight'; as_host = $AsHost; peer = $Peer;
        port = $Port; identity = $Identity; timeout = $TimeoutSeconds; output = $OutputPath }
}
