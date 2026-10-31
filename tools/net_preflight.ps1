# Dot-sourced by net_play.ps1. No game packets, paths or PC names go over this probe.
# The runner starts a fresh socket and has its own firewall rule after this probe.

function ConvertTo-T4NetIdentity {
    param($Value)
    if ($null -eq $Value) { throw 'invalid_identity: missing build identity' }
    $rules = @{
        build_id = '^[0-9a-f]{16}$'; compiler = '^[A-Za-z0-9_.+ -]{1,100}$'
        iso_sha256 = '^[0-9a-f]{64}$'; elf_sha1 = '^[0-9a-f]{40}$'; net = '^[0-9]{1,3}$'
        strict_hello = '^[01]$'; delay_match = '^[01]$'
    }
    $safe = [ordered]@{ schema = 1 }
    foreach ($name in $rules.Keys) {
        $property = $Value.PSObject.Properties[$name]
        if ($null -eq $property -or [string]$property.Value -cnotmatch $rules[$name]) {
            throw "invalid_identity: invalid $name"
        }
        $safe[$name] = [string]$property.Value
    }
    return [pscustomobject]$safe
}

function New-T4NetIdentity {
    param([Parameter(Mandatory = $true)][string]$BuildStampJson,
          [Parameter(Mandatory = $true)][string]$IsoPath)
    if (-not (Test-Path -LiteralPath $BuildStampJson -PathType Leaf)) {
        throw 'invalid_identity: t4net_build.json is missing. Rebuild the same runtime on both PCs; do not reuse an old build stamp.'
    }
    if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) {
        throw 'invalid_identity: ISO missing. Pass -Iso with your own US SLUS-20328 v1.00 ISO.'
    }
    try { $stamp = Get-Content -LiteralPath $BuildStampJson -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'invalid_identity: unreadable t4net_build.json. Rebuild the runtime.' }
    $compilerId = @($stamp.toolchain | Where-Object { $_ -cmatch '^CXX_ID=' })
    $compilerVersion = @($stamp.toolchain | Where-Object { $_ -cmatch '^CXX_VERSION=' })
    if ($compilerId.Count -ne 1 -or $compilerVersion.Count -ne 1) {
        throw 'invalid_identity: compiler version missing in t4net_build.json. Rebuild the runtime.'
    }
    $compiler = $compilerId[0].Substring(7) + ' ' + $compilerVersion[0].Substring(12)
    Write-Host "Compiler: $compiler. Windows SDK and MSVC headers/library versions are not recorded in this build stamp."
    Write-Host 'Hashing your ISO (SHA-256); this can take a few minutes.'
    $identity = [pscustomobject][ordered]@{
        schema = 1; build_id = [string]$stamp.id; compiler = $compiler
        iso_sha256 = (Get-FileHash -LiteralPath $IsoPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        elf_sha1 = [string]$stamp.elf; net = [string]$stamp.net
        strict_hello = $(if ($env:TEKKEN4_NET_STRICT_HELLO -eq '1') { '1' } else { '0' })
        delay_match = $(if ($env:TEKKEN4_NET_DELAY_MATCH -eq '1') { '1' } else { '0' })
    }
    return (ConvertTo-T4NetIdentity $identity)
}

function Compare-T4NetIdentity {
    param($Local, $Peer)
    $remedies = [ordered]@{
        build_id = 'Use the same test zip and build configuration, then rebuild both runtimes.'
        compiler = 'Install/select the same exact MSVC C++ toolset (or the same portable compiler), then rebuild both.'
        iso_sha256 = 'Use matching, verified US SLUS-20328 v1.00 disc images. Each player supplies their own ISO.'
        elf_sha1 = 'Re-extract and rebuild from the matching verified US ISO.'
        net = 'Use the same test zip and rebuild both runtimes.'
        strict_hello = 'Use the same TEKKEN4_NET_STRICT_HELLO setting on both PCs, or clear it on both.'
        delay_match = 'Use the same TEKKEN4_NET_DELAY_MATCH setting on both PCs, or clear it on both.'
    }
    $different = @()
    foreach ($name in $remedies.Keys) {
        if ([string]$Local.$name -cne [string]$Peer.$name) {
            Write-Host "DIFFERENT ${name}: local=$($Local.$name); peer=$($Peer.$name)"
            Write-Host $remedies[$name]
            $different += $name
        }
    }
    return $different
}

function Resolve-T4NetPeer {
    param([Parameter(Mandatory = $true)][string]$Peer)
    $address = $null
    if ([Net.IPAddress]::TryParse($Peer, [ref]$address)) {
        if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) { return $address.ToString() }
        throw 'invalid_peer: the game needs an IPv4 address; IPv6-only peers are not supported.'
    }
    try {
        $lookup = [Net.Dns]::GetHostAddressesAsync($Peer)
        if (-not $lookup.Wait(5000)) { throw 'DNS timeout' }
        $addresses = @($lookup.Result | Where-Object { $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork })
        if ($addresses.Count -gt 0) { return $addresses[0].ToString() }
    } catch { }
    throw 'invalid_peer: host name did not resolve to IPv4 within 5 seconds. Check the name and DNS connection, or use the host public/VPN IPv4 address.'
}

function Invoke-T4NetPreflight {
    param([bool]$AsHost, [string]$Peer = '', [ValidateRange(1, 65535)][int]$Port = 7400,
          [Parameter(Mandatory = $true)]$Identity,
          [ValidateRange(5, 600)][int]$TimeoutSeconds = 90,
          [Parameter(Mandatory = $true)][string]$OutputPath)
    $localIdentity = ConvertTo-T4NetIdentity $Identity
    $report = [ordered]@{
        schema = 1; time_utc = [DateTime]::UtcNow.ToString('o')
        role = $(if ($AsHost) { 'host' } else { 'join' }); status = 'failed'
        local = $localIdentity; peer = $null; reason = 'udp_timeout'; mismatch_fields = @()
    }
    $udp = $null
    try {
        $remote = $null
        if (-not $AsHost) {
            $report.reason = 'invalid_peer'
            $address = [Net.IPAddress]::Parse((Resolve-T4NetPeer -Peer $Peer))
            $remote = [Net.IPEndPoint]::new($address, $Port)
            $report.reason = 'udp_timeout'
        }
        $localPort = $(if ($AsHost) { $Port } else { 0 })
        if (-not $AsHost -and $env:TEKKEN4_NET_PORT) {
            $parsedPort = 0
            if (-not [int]::TryParse($env:TEKKEN4_NET_PORT, [ref]$parsedPort) -or $parsedPort -lt 0 -or $parsedPort -gt 65535) {
                $report.reason = 'invalid_local_port'
                throw 'invalid_local_port: TEKKEN4_NET_PORT must be 0 through 65535.'
            }
            $localPort = $parsedPort
        }
        $bindAddress = [Net.IPAddress]::Any
        if ($env:TEKKEN4_NET_BIND) {
            $bindAddress = $null
            if (-not [Net.IPAddress]::TryParse($env:TEKKEN4_NET_BIND, [ref]$bindAddress) -or
                $bindAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
                $report.reason = 'invalid_bind'
                throw 'invalid_bind: TEKKEN4_NET_BIND must be a local IPv4 address.'
            }
        }
        $udp = [Net.Sockets.UdpClient]::new([Net.Sockets.AddressFamily]::InterNetwork)
        $udp.ExclusiveAddressUse = $true
        try { $udp.Client.Bind([Net.IPEndPoint]::new($bindAddress, $localPort)) }
        catch {
            $report.reason = 'udp_bind_failed'
            throw "udp_bind_failed: local UDP port $localPort is unavailable. Close the previous test/game; check TEKKEN4_NET_BIND and TEKKEN4_NET_PORT."
        }
        Write-Host "UDP check: $($report.role), host port $Port. Start the other PC now; waiting up to $TimeoutSeconds seconds."
        $nonce = [Guid]::NewGuid().ToString('N')
        $peerNonce = ''; $seenOwnNonce = $false; $ready = $false; $peerReady = $false
        $different = @(); $finishAt = $null; $lastSend = -1000
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            $now = $timer.ElapsedMilliseconds
            if ($null -ne $remote -and $now - $lastSend -ge 150) {
                $packet = [ordered]@{ tag = 'T4TEST1'; nonce = $nonce; echo = $peerNonce; ready = $ready; identity = $localIdentity }
                $bytes = [Text.Encoding]::UTF8.GetBytes(($packet | ConvertTo-Json -Compress -Depth 5))
                try { [void]$udp.Send($bytes, $bytes.Length, $remote) }
                catch [Net.Sockets.SocketException] {
                    # ICMP port-unreachable is normal while the other player has not started.
                    if ($_.Exception.SocketErrorCode -notin @([Net.Sockets.SocketError]::ConnectionReset, [Net.Sockets.SocketError]::ConnectionRefused)) { throw }
                }
                $lastSend = $now
            }
            $available = 0
            try { $available = $udp.Available }
            catch [Net.Sockets.SocketException] {
                if ($_.Exception.SocketErrorCode -notin @([Net.Sockets.SocketError]::ConnectionReset, [Net.Sockets.SocketError]::ConnectionRefused)) { throw }
            }
            if ($available -gt 0) {
                $from = [Net.IPEndPoint]::new([Net.IPAddress]::Any, 0)
                try { $bytes = $udp.Receive([ref]$from) }
                catch [Net.Sockets.SocketException] { continue }
                if ($bytes.Length -gt 4096 -or $bytes.Length -lt 10) { continue }
                if ($null -ne $remote -and (-not $from.Address.Equals($remote.Address) -or $from.Port -ne $remote.Port)) { continue }
                try {
                    $packet = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
                    if ($packet.tag -cne 'T4TEST1' -or [string]$packet.nonce -cnotmatch '^[0-9a-f]{32}$' -or
                        [string]$packet.echo -cnotmatch '^([0-9a-f]{32})?$' -or $packet.ready -isnot [bool]) { continue }
                    $receivedIdentity = ConvertTo-T4NetIdentity $packet.identity
                } catch { continue }
                if ($peerNonce -and $packet.nonce -cne $peerNonce) { continue }
                if (-not $peerNonce) {
                    $remote = $from; $peerNonce = [string]$packet.nonce
                    $report.peer = $receivedIdentity
                    Write-Host "Peer build: $($receivedIdentity.build_id)"
                    Write-Host "Peer C++ compiler: $($receivedIdentity.compiler)"
                    Write-Host "Peer ISO SHA-256: $($receivedIdentity.iso_sha256)"
                    $different = @(Compare-T4NetIdentity $localIdentity $receivedIdentity)
                    $report.mismatch_fields = $different
                    if ($different.Count -gt 0) {
                        $report.reason = 'build_mismatch'
                        $finishAt = $now + 1500
                    }
                    $lastSend = -1000
                }
                if ($packet.echo -ceq $nonce) { $seenOwnNonce = $true }
                $ready = $seenOwnNonce -and $different.Count -eq 0
                if ($ready -and $packet.ready) { $peerReady = $true }
                # Repeat confirmations before releasing the port. Lost final packets can be retried.
                if ($ready -and $peerReady -and $null -eq $finishAt) { $finishAt = $now + 1500 }
            }
            if ($null -ne $finishAt -and $now -ge $finishAt) {
                if ($different.Count -gt 0) { throw 'build_mismatch: the values above differ. Fix them on both PCs and retry.' }
                $report.status = 'ok'; $report.reason = 'matched'
                Write-Host 'MATCH: build id, C++ compiler, ISO hash and protocol settings agree.'
                Write-Host 'UDP OK: both PCs exchanged and acknowledged packets on the host game port.'
                Write-Host 'Allow ps2EntryRunner.exe separately in Windows Firewall. This PowerShell probe cannot check its application rule.'
                return
            }
            Start-Sleep -Milliseconds 20
        }
        throw "udp_timeout: no complete two-way check within $TimeoutSeconds seconds. Both PCs must run this command. Check the host IPv4/UDP port, router forwarding or VPN, and the PowerShell firewall rule; then retry both."
    } finally {
        if ($null -ne $udp) { $udp.Close(); $udp.Dispose() }
        try {
            $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 -ErrorAction Stop
        } catch {
            $message = "Could not write the preflight report to ${OutputPath}: $($_.Exception.Message)"
            if ($report.status -eq 'ok') { throw $message }
            # Keep the network/identity failure as the terminating error.
            Write-Warning $message -WarningAction Continue
        }
    }
}
