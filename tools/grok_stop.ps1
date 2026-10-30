param([Parameter(Mandatory = $true)][string]$Name)
# Stops a Grok task started by tools\grok_task.ps1 -Name <Name>: the grok.exe whose prompt file is
# logs\grok\<Name>_<time>.prompt.md (stopping the wrapper alone leaves grok.exe running).
$stopped = 0
Get-CimInstance Win32_Process -Filter "Name = 'grok.exe'" | Where-Object { $_.CommandLine -match [regex]::Escape("logs\grok\$Name" + "_") } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $stopped++ }
"stopped $stopped grok process(es) for task $Name"
