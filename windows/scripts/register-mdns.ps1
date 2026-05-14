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

    Limitation: Windows' Bonjour port has a bug where DnsServiceRegister
    doesn't publish A/AAAA records reliably. So this script only
    publishes the service (SRV/TXT/PTR) record; resolution of
    `hana.<hostname>` from *other* devices on the LAN still requires
    a hosts-file entry on each client. For local-machine browser access
    via `https://hana.<hostname>` etc., the Windows installer's hosts-
    file edit covers it.

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

# Resolve dns-sd.exe (Bonjour for Windows)
$dnsSd = "$env:ProgramFiles\Bonjour\dns-sd.exe"
if (-not (Test-Path $dnsSd)) {
    Write-Error @"
dns-sd.exe not found at $dnsSd.

Run .\install-bonjour.ps1 first, then re-run this script.
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

# binPath= passed to sc.exe must be ONE token. Quotes around paths-with-
# spaces have to be escaped as \" so sc.exe parses them correctly. The
# whole thing becomes: shawl run --name <X> -- "<dnsSd>" <dnsSdArgs>
$binPath = "`"$shawlExe`" run --name $ServiceName -- `"$dnsSd`" $dnsSdArgs"

# If the service already exists, recreate it with current params
if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    Write-Host "Service $ServiceName already exists; removing for re-create." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    & sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 1
}

Write-Host "Creating service $ServiceName ..." -ForegroundColor Cyan
& sc.exe create $ServiceName binPath= $binPath start= auto DisplayName= "Neon Hub mDNS Advertisement"
if ($LASTEXITCODE -ne 0) {
    Write-Error "sc.exe create failed with exit code $LASTEXITCODE"
}

# Auto-restart on failure
& sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null

Write-Host "Starting service ..." -ForegroundColor Cyan
Start-Service -Name $ServiceName

Write-Host "Service $ServiceName is running." -ForegroundColor Green
Write-Host "Verify with: dns-sd -B _neon-hub._tcp local"
