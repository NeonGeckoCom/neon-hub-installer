<#
.SYNOPSIS
    Register the Neon Hub mDNS publisher as a Windows service.

.DESCRIPTION
    Creates a Windows service named NeonHubMdnsService that runs the
    sibling `mdns-publisher.py` (python-zeroconf) under Shawl. The
    publisher advertises:

      - one `_neon-hub._tcp.local.` service record (Hub discovery,
        matching the macOS launchd plist's intent)
      - one A record per Hub subdomain (config, hana, iris, ...) so
        a browser on another LAN client can resolve `hana.<hostname>`
        without a hosts-file entry.

    Why python-zeroconf instead of Bonjour or Windows-native mDNS:
    Apple's Bonjour-for-Windows `dns-sd -P` fails with -65563 because
    its register-record IPC isn't implemented. Microsoft's built-in
    `DnsServiceRegister` succeeds and broadcasts the SRV/TXT/PTR but
    silently drops the A record (known Win10/11 bug, still present on
    26100). python-zeroconf speaks mDNS directly over UDP 5353 and
    sidesteps both.

    Idempotent -- re-running the script reinstalls the service with
    current parameters.

.PARAMETER Hostname
    NEON_HOSTNAME (e.g. `neon-hub-win.local`).

.PARAMETER Ip
    LAN IP to advertise. If omitted, the script picks the first
    non-loopback / non-APIPA / non-Docker-bridge IPv4 address.

.PARAMETER ServiceName
    Name of the Windows service to create. Defaults to
    NeonHubMdnsService.

.EXAMPLE
    .\register-mdns.ps1 -Hostname neon-hub-win.local
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Hostname,
    [string]$Ip,
    [string]$ServiceName = 'NeonHubMdnsService'
)

$ErrorActionPreference = 'Stop'

# Resolve shawl.exe
$shawlExe = (Get-Command shawl -ErrorAction SilentlyContinue).Source
if (-not $shawlExe) {
    Write-Error @"
shawl.exe not found on PATH.

Install with:
  winget install -e --id mtkennerly.shawl

Then re-run this script.
"@
}

# Use the Hub venv set up by setup-python.ps1. Baking the absolute path
# into the service's binPath lets Shawl launch the publisher under
# LocalSystem without any PATH or shim dance.
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envFile  = Join-Path $repoRoot 'windows\.env'
if (-not (Test-Path $envFile)) { Write-Error "windows\.env not found; run README step 4 first" }
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_][A-Z_0-9]*)\s*=\s*(.+?)\s*$') {
        $envVars[$matches[1]] = $matches[2].Trim('"').Trim("'")
    }
}
$neonHome = $envVars['NEON_HOME']
if (-not $neonHome) { Write-Error "NEON_HOME missing from $envFile" }
$python = (Join-Path $neonHome 'venv\Scripts\python.exe') -replace '/', '\'
if (-not (Test-Path $python)) {
    Write-Error @"
Hub venv interpreter not found at $python.

Run windows\scripts\setup-python.ps1 first to create the venv and
install zeroconf.
"@
}

# Resolve the publisher script next to this one.
$publisher = Join-Path $PSScriptRoot 'mdns-publisher.py'
if (-not (Test-Path $publisher)) {
    Write-Error "mdns-publisher.py not found next to register-mdns.ps1 (expected at $publisher)"
}

# Auto-detect LAN IP if not passed. Filters out loopback, APIPA, and
# Docker's default 172.16/12 bridge so we don't advertise an address
# only the host or its containers can reach.
if (-not $Ip) {
    $candidate = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            $_.IPAddress -ne '127.0.0.1' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.IPAddress -notlike '172.1[6-9].*' -and
            $_.IPAddress -notlike '172.2[0-9].*' -and
            $_.IPAddress -notlike '172.3[0-1].*' -and
            $_.PrefixOrigin -in @('Dhcp', 'Manual')
        } |
        Select-Object -First 1
    if (-not $candidate) {
        Write-Error "Could not auto-detect a LAN IPv4 address. Pass -Ip explicitly."
    }
    $Ip = $candidate.IPAddress
    Write-Host "Auto-detected LAN IP: $Ip (interface $($candidate.InterfaceAlias))" -ForegroundColor Cyan
}

# Build the ImagePath the SCM will store. Final form:
#   "<shawl>" run --name <X> -- "<python>" -u "<publisher>" --hostname <H> --ip <IP>
# `python -u` forces unbuffered stdout/stderr so Shawl's log file
# captures the publisher's progress in real time, which is useful when
# diagnosing service-side failures.
# New-Service forwards -BinaryPathName to the SCM as a single string
# and avoids the PS-5.1 -> sc.exe quoting footgun.
$binPath = "`"$shawlExe`" run --name $ServiceName -- `"$python`" -u `"$publisher`" --hostname $Hostname --ip $Ip"

# If the service already exists, recreate it with current params.
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    Write-Host "Service $ServiceName already exists; removing for re-create." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    & sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 1
}

Write-Host "Creating service $ServiceName ..." -ForegroundColor Cyan
New-Service -Name $ServiceName `
    -BinaryPathName $binPath `
    -DisplayName 'Neon Hub mDNS Advertisement' `
    -StartupType Automatic | Out-Null

# Auto-restart on failure. sc.exe failure uses plain key=value args
# with no embedded quotes, so the PS-tokenizer issue doesn't apply.
& sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null

Write-Host "Starting service ..." -ForegroundColor Cyan
Start-Service -Name $ServiceName

Write-Host "Service $ServiceName is running." -ForegroundColor Green
Write-Host ""
Write-Host "Verify service discovery:" -ForegroundColor Cyan
Write-Host "  dns-sd -B _neon-hub._tcp local"
Write-Host "Verify A record publishing (from this machine or another LAN client):"
Write-Host "  dns-sd -G v4 hana.$Hostname"
