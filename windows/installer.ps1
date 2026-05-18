<#
.SYNOPSIS
    One-shot installer for the Neon Hub on Windows.

.DESCRIPTION
    Wraps every script under `windows\scripts\` plus the small bits of
    glue (data tree, .env file, `docker compose up`, optional hosts-file
    edit) into a single Administrator-PowerShell run. Mirrors the macOS/
    Linux installer.sh / installer-macos.sh entry-points.

    Two ways to run:

      .\installer.ps1
          Interactive wizard. Walks every setting with a default in
          [brackets]; press Enter to accept.

      .\installer.ps1 -AdminUsername neon -AdminPassword (SecureString)
          Non-prompt mode. Once admin creds are supplied, every other
          setting falls back to its default unless explicitly overridden.

    Default behavior, in order:

      1. Generate a self-signed TLS cert via `new-cert.ps1` (skipped
         if `${NeonHome}\<hostname>.crt` already exists).
      2. Import the cert into LocalMachine\Root if `-TrustCert`.
      3. Lay down `${NeonHome}` and copy the static seed files.
      4. Write `windows\.env` if it doesn't already exist, populating
         NEON_HOME, NEON_HOSTNAME, and TZ.
      5. Create the Hub venv via `setup-python.ps1`.
      6. Render the templated configs via `generate-secrets.ps1`.
      7. `docker compose up -d`.
      8. Seed admin + neon_node users via `seed-users.ps1`.
      9. Bootstrap the Hub admin token via `bootstrap-hub-admin.ps1`.
     10. Register the LAN mDNS publisher via `register-mdns.ps1`
         (default on; skip with `-NoMdns`).
     11. Append a 127.0.0.1 entry for the Hub hostname + subdomains
         to the system hosts file (default OFF; opt in with
         `-AddHostsEntry` if Windows mDNS resolution is unreliable
         on your machine).

.PARAMETER Hostname
    NEON_HOSTNAME. Default `neon-hub-win.local`.

.PARAMETER NeonHome
    Where the Hub keeps its data. Default `%USERPROFILE%\neon-hub`.

.PARAMETER Timezone
    IANA timezone string baked into the `.env` as TZ. Auto-detected
    from the system's Windows timezone via a built-in mapping table,
    falling back to `America/Chicago`.

.PARAMETER AdminUsername
    Hub admin user to seed into users-service. Prompted if missing.

.PARAMETER AdminPassword
    SecureString password for the admin user. Prompted if missing.

.PARAMETER TrustCert
    Import the freshly-generated cert into the LocalMachine root store
    so browsers don't warn.

.PARAMETER NoMdns
    Skip the mDNS publisher registration. mDNS is on by default since
    it publishes A records for every Hub subdomain to the whole LAN,
    so other devices don't need their own hosts-file edits.

.PARAMETER AddHostsEntry
    Append a `127.0.0.1` entry for the Hub hostname + subdomains to
    the system hosts file. Off by default. Use this if Windows mDNS
    can't resolve `.local` names reliably on your machine.

.PARAMETER RotateSecrets
    Pass through to `generate-secrets.ps1` to mint fresh credentials.
    Requires `docker compose down -v` first if the stack has already
    initialised its RabbitMQ user database from a previous run.

.PARAMETER NonInteractive
    Fail if any required value is missing instead of prompting and
    skip the proceed-confirmation prompt. Required for CI / scripted
    reinstalls.

.EXAMPLE
    .\installer.ps1
    # Interactive wizard.

.EXAMPLE
    .\installer.ps1 -AdminUsername neon `
                    -AdminPassword (Read-Host -AsSecureString) `
                    -TrustCert `
                    -NonInteractive
#>
[CmdletBinding()]
param(
    [string]$Hostname = 'neon-hub-win.local',
    [string]$NeonHome,
    [string]$Timezone,
    [string]$AdminUsername,
    [SecureString]$AdminPassword,
    [switch]$TrustCert,
    [switch]$NoMdns,
    [switch]$AddHostsEntry,
    [switch]$RotateSecrets,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

# ---- helpers ----------------------------------------------------------

function Read-Default {
    param([string]$Prompt, [string]$Default)
    $shown = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    $reply = Read-Host -Prompt $shown
    if (-not $reply) { return $Default }
    return $reply
}

function Read-YesNo {
    param([string]$Prompt, [bool]$DefaultYes)
    $hint = if ($DefaultYes) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $reply = Read-Host -Prompt "$Prompt $hint"
        if (-not $reply) { return $DefaultYes }
        switch -Regex ($reply) {
            '^[Yy]' { return $true }
            '^[Nn]' { return $false }
            default { Write-Host 'Please enter y or n.' -ForegroundColor Yellow }
        }
    }
}

function Write-Step {
    param([string]$Title)
    Write-Host ''
    Write-Host "--- $Title ---" -ForegroundColor Cyan
}

# ---- preflight --------------------------------------------------------

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error @"
installer.ps1 must run from an Administrator PowerShell -- several steps
register Windows services or edit system files. Right-click PowerShell ->
Run as administrator, then re-invoke.
"@
}

# docker info writes WSL2 capability warnings to stderr; under PS 5.1's
# Stop policy that's a NativeCommandError. Toggle to Continue for the
# probe and rely on $LASTEXITCODE alone.
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& docker info 2>&1 | Out-Null
$dockerInfoExit = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($dockerInfoExit -ne 0) {
    Write-Error "Docker Desktop is not running (`docker info` exited $dockerInfoExit). Start it and re-run."
}

# ---- defaults ---------------------------------------------------------

if (-not $NeonHome) { $NeonHome = Join-Path $env:USERPROFILE 'neon-hub' }
$NeonHome = $NeonHome.TrimEnd('\','/')

$windowsDir  = $PSScriptRoot
$scriptsDir  = Join-Path $windowsDir 'scripts'
$seedDir     = Join-Path $windowsDir 'seed'
$envFile     = Join-Path $windowsDir '.env'
$envExample  = Join-Path $windowsDir '.env.example'
$composeFile = Join-Path $windowsDir 'docker-compose.yml'

# Windows-TZ -> IANA mapping. Anything not in the table falls back to
# America/Chicago with a note; user can override.
function Resolve-Timezone {
    param([string]$Override)
    if ($Override) { return $Override }
    $map = @{
        'Pacific Standard Time'           = 'America/Los_Angeles'
        'Mountain Standard Time'          = 'America/Denver'
        'US Mountain Standard Time'       = 'America/Phoenix'
        'Central Standard Time'           = 'America/Chicago'
        'Eastern Standard Time'           = 'America/New_York'
        'Atlantic Standard Time'          = 'America/Halifax'
        'Alaskan Standard Time'           = 'America/Anchorage'
        'Hawaiian Standard Time'          = 'Pacific/Honolulu'
        'UTC'                             = 'UTC'
        'GMT Standard Time'               = 'Europe/London'
        'W. Europe Standard Time'         = 'Europe/Berlin'
        'Central European Standard Time'  = 'Europe/Warsaw'
        'Romance Standard Time'           = 'Europe/Paris'
        'E. Europe Standard Time'         = 'Europe/Bucharest'
        'Tokyo Standard Time'             = 'Asia/Tokyo'
        'China Standard Time'             = 'Asia/Shanghai'
        'India Standard Time'             = 'Asia/Kolkata'
        'Singapore Standard Time'         = 'Asia/Singapore'
        'AUS Eastern Standard Time'       = 'Australia/Sydney'
        'New Zealand Standard Time'       = 'Pacific/Auckland'
    }
    $win = (Get-TimeZone).Id
    if ($map.ContainsKey($win)) { return $map[$win] }
    Write-Host "Unknown Windows timezone '$win'; defaulting to America/Chicago. Override with -Timezone <IANA-name>." -ForegroundColor Yellow
    return 'America/Chicago'
}
$Timezone = Resolve-Timezone -Override $Timezone

# Coerce switches into plain booleans so the interactive wizard can
# override them.
$trustCert      = $TrustCert.IsPresent
$registerMdns   = -not $NoMdns.IsPresent
$addHostsEntry  = $AddHostsEntry.IsPresent
$rotateSecrets  = $RotateSecrets.IsPresent

# ---- interactive wizard ---------------------------------------------

$interactive = -not $NonInteractive

if ($interactive) {
    Write-Host ''
    Write-Host '=== Neon Hub installer ===' -ForegroundColor Cyan
    Write-Host 'Press Enter to accept the [bracketed default].'
    Write-Host ''

    $Hostname       = Read-Default 'Hub hostname'                   $Hostname
    $NeonHome       = (Read-Default 'NEON_HOME (Hub data dir)'      $NeonHome).TrimEnd('\','/')
    $Timezone       = Read-Default 'Timezone (IANA name)'           $Timezone
    if (-not $AdminUsername) { $AdminUsername = Read-Default 'Hub admin username' 'neon' }
    if (-not $AdminPassword) { $AdminPassword = Read-Host  "Password for $AdminUsername" -AsSecureString }

    Write-Host ''
    $registerMdns   = Read-YesNo 'Register LAN mDNS publisher? (other devices can resolve hana.<hostname> without hosts edits)' $registerMdns
    $addHostsEntry  = Read-YesNo 'Also add a hosts file entry on this machine? (only needed if Windows mDNS does not resolve .local reliably here)' $addHostsEntry
    $trustCert      = Read-YesNo 'Trust the self-signed TLS cert in this machines LocalMachine\Root store?' $trustCert
    $rotateSecrets  = Read-YesNo 'Rotate Hub secrets? (needs docker compose down -v if the stack has already been started before)' $rotateSecrets
} else {
    if (-not $AdminUsername) { Write-Error 'AdminUsername is required in -NonInteractive mode.' }
    if (-not $AdminPassword) { Write-Error 'AdminPassword is required in -NonInteractive mode.' }
}

# ---- plan summary ----------------------------------------------------

Write-Host ''
Write-Host '=== Plan ===' -ForegroundColor Cyan
Write-Host "  Hostname         $Hostname"
Write-Host "  NEON_HOME        $NeonHome"
Write-Host "  Timezone         $Timezone"
Write-Host "  Admin user       $AdminUsername"
Write-Host "  Register mDNS    $registerMdns"
Write-Host "  Hosts file entry $addHostsEntry"
Write-Host "  Trust TLS cert   $trustCert"
Write-Host "  Rotate secrets   $rotateSecrets"
Write-Host ''

if (-not $NonInteractive) {
    if (-not (Read-YesNo 'Proceed?' $true)) {
        Write-Host 'Aborted.' -ForegroundColor Yellow
        exit 1
    }
}

# ---- 1. TLS cert ----------------------------------------------------

Write-Step 'TLS certificate'
$crtPath = Join-Path $NeonHome "$Hostname.crt"
$needRegen = $false
if (Test-Path $crtPath) {
    # Older Phase 1 certs only covered the bare hostname (DNS:<host>,
    # DNS:localhost, IP:127.0.0.1) so subdomain hits would warn even
    # after the cert was trusted. Force a regen if the SAN is missing
    # the wildcard `*.<host>` entry.
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $crtPath
    $sanExt = $cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' }
    $sanText = if ($sanExt) { $sanExt.Format($false) } else { '' }
    if ($sanText -notmatch "\*\.$([regex]::Escape($Hostname))") {
        Write-Host "Existing cert lacks `*.$Hostname` SAN; regenerating." -ForegroundColor Yellow
        $needRegen = $true
    } else {
        Write-Host "Cert already at $crtPath with wildcard SAN; skipping." -ForegroundColor DarkGray
    }
} else {
    $needRegen = $true
}
if ($needRegen) {
    & (Join-Path $scriptsDir 'new-cert.ps1') -Hostname $Hostname -OutDir $NeonHome
}

# ---- 2. Trust cert (optional) ---------------------------------------

if ($trustCert) {
    Write-Step 'Trust TLS cert'
    Import-Certificate -FilePath $crtPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-Host 'Imported into LocalMachine\Root.' -ForegroundColor Green
}

# ---- 3. Data tree + static files ------------------------------------

Write-Step 'Hub data tree'
@(
    "$NeonHome\compose",
    "$NeonHome\xdg\config\neon",
    "$NeonHome\xdg\config\rabbitmq",
    "$NeonHome\xdg\local\share\neon\users-service",
    "$NeonHome\xdg\share\neon"
) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

Copy-Item (Join-Path $seedDir 'rabbitmq.conf')     "$NeonHome\xdg\config\rabbitmq\" -Force
Copy-Item (Join-Path $seedDir 'enabled_plugins')   "$NeonHome\xdg\config\rabbitmq\" -Force
Copy-Item (Join-Path $seedDir 'hub_admin.yaml')    "$NeonHome\xdg\config\neon\"     -Force
Copy-Item (Join-Path $seedDir 'skill-config.json') "$NeonHome\compose\"             -Force
Copy-Item (Join-Path $seedDir 'neon-logo.png')     "$NeonHome\compose\"             -Force
# nginx.conf is rendered from the shared Jinja2 template by
# generate-secrets.ps1 (step 6), so no static copy here.
Write-Host "Tree ready at $NeonHome." -ForegroundColor Green

# ---- 4. .env ---------------------------------------------------------

Write-Step '.env file'
if (Test-Path $envFile) {
    Write-Host "$envFile already exists; leaving it. Delete it and re-run to regenerate." -ForegroundColor DarkGray
} else {
    $neonHomeForward = $NeonHome -replace '\\', '/'
    $envContent = (Get-Content $envExample -Raw) `
        -replace 'NEON_HOME=.*',     "NEON_HOME=$neonHomeForward" `
        -replace 'NEON_HOSTNAME=.*', "NEON_HOSTNAME=$Hostname" `
        -replace 'TZ=.*',            "TZ=$Timezone"
    [System.IO.File]::WriteAllText($envFile, $envContent)
    Write-Host "Wrote $envFile." -ForegroundColor Green
}

# ---- 5. Python venv -------------------------------------------------

Write-Step 'Python venv'
& (Join-Path $scriptsDir 'setup-python.ps1')

# ---- 6. Render Hub config templates ---------------------------------

Write-Step 'Render Hub config templates'
$gsScript = Join-Path $scriptsDir 'generate-secrets.ps1'
$gsSplat  = @{ Hostname = $Hostname }
if ($rotateSecrets) { $gsSplat['Rotate'] = $true }
& $gsScript @gsSplat

# ---- 7. docker compose up -------------------------------------------

Write-Step 'Bring up the container stack'
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& docker compose -p neon -f $composeFile --env-file $envFile up -d 2>&1 | Write-Host
$dockerExit = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($dockerExit -ne 0) { Write-Error "docker compose up failed (exit $dockerExit)" }

# Restart nginx so it re-reads the bind-mounted nginx.conf -- `compose up -d`
# doesn't notice bind-mount file changes when the service definition itself
# hasn't moved, so a fresh install on top of a previous one would otherwise
# keep serving the old config.
$ErrorActionPreference = 'Continue'
& docker compose -p neon -f $composeFile --env-file $envFile restart nginx 2>&1 | Out-Null
$ErrorActionPreference = $prev

# ---- 8. Seed users --------------------------------------------------

Write-Step 'Seed admin + neon_node users'
& (Join-Path $scriptsDir 'seed-users.ps1') `
    -AdminUsername $AdminUsername `
    -AdminPassword $AdminPassword

# ---- 9. Bootstrap admin token ---------------------------------------

Write-Step 'Bootstrap Hub admin token'
& (Join-Path $scriptsDir 'bootstrap-hub-admin.ps1') `
    -AdminUsername $AdminUsername `
    -AdminPassword $AdminPassword

# ---- 10. mDNS (default on) ------------------------------------------

if ($registerMdns) {
    Write-Step 'Register mDNS publisher'
    & (Join-Path $scriptsDir 'register-mdns.ps1') -Hostname $Hostname
}

# ---- 11. Hosts file entry (opt-in) ----------------------------------

if ($addHostsEntry) {
    Write-Step 'Hosts file entry'
    $hostsPath = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
    $subdomains = @(
        'config', 'hana', 'iris', 'iris-websat',
        'coqui', 'fasterwhisper', 'rmq-admin', 'skill-config'
    )
    $entry = "127.0.0.1   $Hostname " + (($subdomains | ForEach-Object { "$_.$Hostname" }) -join ' ')
    $hostsLines = Get-Content $hostsPath -ErrorAction SilentlyContinue
    $existing = $hostsLines | Where-Object { $_ -match "^\s*127\.0\.0\.1\s+.*\b$([regex]::Escape($Hostname))\b" }
    if ($existing) {
        Write-Host "Hosts already maps $Hostname; skipping." -ForegroundColor DarkGray
    } else {
        Add-Content -Path $hostsPath -Value "`n$entry"
        Write-Host "Added: $entry" -ForegroundColor Green
    }
}

# ---- done -----------------------------------------------------------

$secretsPath   = Join-Path $NeonHome 'neon_hub_secrets.yaml'
$dianaPath     = Join-Path $NeonHome 'xdg\config\neon\diana.yaml'
$hubAdminPath  = Join-Path $NeonHome 'xdg\config\neon\hub_admin.yaml'

Write-Host ''
Write-Host '=== Installation complete ===' -ForegroundColor Green
Write-Host ''
Write-Host 'URLs:' -ForegroundColor Cyan
Write-Host "  Hub Config UI       https://config.$Hostname/"
Write-Host "  HANA OpenAPI        https://hana.$Hostname/docs"
Write-Host "  RabbitMQ admin UI   https://rmq-admin.$Hostname/"
Write-Host ''
Write-Host 'Credentials:' -ForegroundColor Cyan
Write-Host "  Hub admin user      $AdminUsername"
Write-Host '  Hub admin password  (the password you provided; not stored in plaintext)'
Write-Host "  Service-user / HANA $secretsPath"
Write-Host "  Neon Node password  in $dianaPath (look for `node_password:`)"
Write-Host "  Hub-config token    $hubAdminPath"
Write-Host ''
Write-Host '  Treat the files above as sensitive -- they grant full Hub access.' -ForegroundColor Yellow
if (-not $trustCert) {
    Write-Host ''
    Write-Host '  Browsers will warn about the self-signed cert. Re-run with -TrustCert' -ForegroundColor DarkGray
    Write-Host "  or run Import-Certificate against $crtPath into LocalMachine\Root to silence the warning." -ForegroundColor DarkGray
} else {
    Write-Host ''
    Write-Host '  TLS cert is trusted in LocalMachine\Root. Edge/Chrome cache cert' -ForegroundColor DarkGray
    Write-Host '  decisions per-process -- fully restart your browser to pick it up.' -ForegroundColor DarkGray
    Write-Host '  Firefox uses its own cert store and ignores LocalMachine\Root; trust' -ForegroundColor DarkGray
    Write-Host '  the cert there manually if you use it.' -ForegroundColor DarkGray
}
