# One game or PCSX2 run at a time: Claude and Grok share the CPU (docs/ai/collaboration.md, RESOURCES).
# Dot-sourced by run_capture.ps1 and pcsx2_capture.ps1: Enter-RunLock before starting, Exit-RunLock at the end.
# logs\run.lock holds "<pid> <what>"; a lock whose process is gone is stale and taken over.
function Enter-RunLock([string]$Root, [string]$What)
{
    $lock = Join-Path $Root "logs\run.lock"
    New-Item -ItemType Directory -Force (Split-Path $lock) | Out-Null
    $waited = 0
    while (Test-Path $lock)
    {
        $holder = Get-Content $lock -ErrorAction SilentlyContinue | Select-Object -First 1
        $holderPid = 0
        if (-not $holder -or -not [int]::TryParse(($holder -split ' ')[0], [ref]$holderPid) -or
            -not (Get-Process -Id $holderPid -ErrorAction SilentlyContinue)) { break }
        if ($waited -eq 0) { "waiting for the run lock: $holder" }
        Start-Sleep -Seconds 5
        $waited += 5
        if ($waited -ge 1800) { throw "run lock still held after 30 min: $holder" }
    }
    "$PID $What" | Set-Content -Encoding ascii $lock
}

# Waits (without taking it) until no run holds the lock: CPU-heavy side work (Grok builds, big scans) uses this so a
# timed game run is not slowed down.
function Wait-RunLockFree([string]$Root)
{
    $lock = Join-Path $Root "logs\run.lock"
    $waited = 0
    while (Test-Path $lock)
    {
        $holder = Get-Content $lock -ErrorAction SilentlyContinue | Select-Object -First 1
        $holderPid = 0
        if (-not $holder -or -not [int]::TryParse(($holder -split ' ')[0], [ref]$holderPid) -or
            -not (Get-Process -Id $holderPid -ErrorAction SilentlyContinue)) { return }
        if ($waited -eq 0) { "a run holds the lock, waiting before starting: $holder" }
        Start-Sleep -Seconds 5
        $waited += 5
        if ($waited -ge 1800) { "run lock still held after 30 min, going ahead: $holder"; return }
    }
}

function Exit-RunLock([string]$Root)
{
    $lock = Join-Path $Root "logs\run.lock"
    $holder = Get-Content $lock -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($holder -and ($holder -split ' ')[0] -eq "$PID") { "" | Set-Content -Encoding ascii $lock }  # released = emptied, never deleted (no deletes allowed)
}
