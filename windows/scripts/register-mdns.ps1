<#
.SYNOPSIS
    Register the Neon Hub mDNS advertisement as a Windows service.

.DESCRIPTION
    Creates a Windows service named NeonHubMdnsService that runs
    `dns-sd.exe -R` to advertise `_neon-hub._tcp.local.` on port 443
    with TXT records describing the Hub. The service is wrapped in
    Shawl so dns-sd.exe (a plain console program) speaks the Windows
    Service Control Manager protocol.

    Parallels the launchd plist used on macOS
    (debos/overlays/ansible/templates/com.neongecko.neon-hub-mdns.plist.j2)
    so a Node app or Apple-flavored discovery client browsing for
    `_neon-hub._tcp` finds a Windows Hub the same way it finds a Mac
    Hub.

    Idempotent — re-running the script reinstalls the service with the
    current parameters. Useful when the hostname changes.

    KNOWN LIMITATION — multi-device hostname resolution. This script
    advertises the Hub service, not custom A records. Apple's Bonjour
    for Windows lets `dns-sd -R` register a service successfully but
    `dns-sd -P` (proxy mode, the only way to publish arbitrary A
    records from the CLI) fails immediately with
    `DNSServiceCreateConnection returned -65563`
    (kDNSServiceErr_ServiceNotRunning) — the Windows port doesn't
    implement the connection-based register-record IPC.

    So discovery clients find the Hub, but a browser on another LAN
    device still can't resolve `hana.<hostname>` without a hosts-file
    entry on that device. macOS Hubs sidestep this because
    mDNSResponder auto-publishes `<computer>.local`, which clients
    use directly.

    Phase 2.3 plan: replace dns-sd with a small python-zeroconf-based
    publisher that talks the mDNS protocol directly, side-stepping
    Bonjour-for-Windows entirely.

.PARAMETER Hostname
    NEON_HOSTNAME — appears in the host= TXT record so discovery
    clients know which name to resolve.

.PARAMETER ServiceName
    Name of the Windows service to create. Defaults to
    NeonHubMdnsService.

.EXAMPLE
    .\register-mdns.ps1 -Hostname neon-hub-win.local
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Hostname,
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

# Resolve dns-sd.exe (Bonjour for Windows). Modern Bonjour Print
# Services installs it into C:\Windows\System32\ (on PATH); older
# versions kept it in C:\Program Files\Bonjour\. Prefer the PATH
# lookup so either layout works.
$dnsSd = (Get-Command dns-sd -ErrorAction SilentlyContinue).Source
if (-not $dnsSd) {
    Write-Error @"
dns-sd.exe not found on PATH or in C:\Program Files\Bonjour\.

Run .\install-bonjour.ps1 first, then re-run this script.
"@
}

# Bonjour Service (mDNSResponder) must be running — every dns-sd call
# (including the one our service runs) returns -65563 / ServiceNotRunning
# without it. Catching it here is cheap and prevents the install from
# crash-looping NeonHubMdnsService silently.
$bonjour = Get-Service -Name 'Bonjour Service' -ErrorAction SilentlyContinue
if (-not $bonjour) {
    Write-Error "Bonjour Service is not installed. Run .\install-bonjour.ps1 first."
}
if ($bonjour.Status -ne 'Running') {
    Write-Error @"
Bonjour Service is installed but currently $($bonjour.Status). Start it before
running this script:

  Start-Service 'Bonjour Service'

(Bonjour is set to Automatic startup, so this is usually only needed after a
clean install or if something stopped the service after boot.)
"@
}

# Build the dns-sd -R arguments. These mirror the macOS launchd plist.
$serviceLabel = "Neon Hub on $env:COMPUTERNAME"
$dnsSdArgs = @(
    '-R'
    "`"$serviceLabel`""
    '_neon-hub._tcp'
    'local'
    '443'
    'scheme=https'
    "host=hana.$Hostname"
) -join ' '

# Construct the ImagePath the SCM will store. Final form:
#   "<shawl>" run --name <X> -- "<dns-sd>" -R "Neon Hub on HOST" _neon-hub._tcp local 443 scheme=https host=hana.<NEON_HOSTNAME>
# New-Service forwards -BinaryPathName to the SCM as a single string,
# so we avoid the PS-5.1 -> sc.exe quoting footgun (sc.exe create
# rejects the call with exit 1639 / "Invalid command line" when
# embedded quotes get mangled by PowerShell's native-exe tokenizer).
$binPath = "`"$shawlExe`" run --name $ServiceName -- `"$dnsSd`" $dnsSdArgs"

# If the service already exists, recreate it with current params
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
Write-Host "Verify with: dns-sd -B _neon-hub._tcp local"
