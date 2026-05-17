<#
.SYNOPSIS
    One-shot installer for the Neon Hub on Windows.

.DESCRIPTION
    Wraps every script under `windows\scripts\` plus the small bits
    of glue (hosts-file edit, data tree, .env file, `docker compose up`)
    into a single Administrator-PowerShell run. Each step is
    idempotent, so re-running picks up where a prior run left off.

    Default behavior, in order:

      1. Append `127.0.0.1 <hostname> <subdomains...>` to the system
         hosts file (skipped if `-SkipHostsEdit` or already present).
      2. Generate a self-signed TLS cert via `new-cert.ps1` (skipped
         if `${NeonHome}\<hostname>.crt` already exists).
      3. Import the cert into LocalMachine\Root if `-TrustCert`.
      4. Lay down `${NeonHome}` and copy the static seed files.
      5. Write `windows\.env` if it doesn't already exist, populating
         NEON_HOME, NEON_HOSTNAME, and TZ.
      6. Create the Hub venv via `setup-python.ps1`.
      7. Render the templated configs via `generate-secrets.ps1`.
      8. `docker compose up -d` against `windows\docker-compose.yml`.
      9. Seed admin + neon_node users via `seed-users.ps1`.
     10. Bootstrap the Hub admin token via `bootstrap-hub-admin.ps1`.
     11. Register the mDNS publisher via `register-mdns.ps1` if
         `-EnableMdns`.

.PARAMETER Hostname
    NEON_HOSTNAME. Default `neon-hub-win.local`.

.PARAMETER NeonHome
    Where the Hub keeps its data. Default `%USERPROFILE%\neon-hub`.

.PARAMETER Timezone
    IANA timezone string baked into the `.env` as TZ. Default
    auto-detected from the system's Windows timezone via a built-in
    mapping table, falling back to `America/Chicago`.

.PARAMETER AdminUsername
    Hub admin user to seed into users-service. Prompted if missing.

.PARAMETER AdminPassword
    SecureString password for the admin user. Prompted if missing.

.PARAMETER TrustCert
    Import the freshly-generated cert into the LocalMachine root store
    so browsers don't prompt with a warning.

.PARAMETER EnableMdns
    Register the LAN mDNS publisher service (`NeonHubMdnsService`) so
    other devices on the LAN can resolve `hana.<hostname>` etc.
    without their own hosts-file edits.

.PARAMETER RotateSecrets
    Pass through to `generate-secrets.ps1` to mint fresh credentials.
    Requires `docker compose down -v` first if the stack has already
    initialised its RabbitMQ user database from a previous run.

.PARAMETER SkipHostsEdit
    Skip the hosts-file edit (useful when something else manages
    hostname resolution, e.g. a corporate DNS server).

.PARAMETER NonInteractive
    Fail if any required value (admin user/password) is missing
    instead of prompting. Useful for CI or scripted reinstalls.

.EXAMPLE
    .\installer.ps1
    # Prompts for admin creds, accepts defaults for everything else.

.EXAMPLE
    .\installer.ps1 -AdminUsername neon `
                    -AdminPassword (Read-Host -AsSecureString) `
                    -TrustCert `
                    -EnableMdns
#>
[CmdletBinding()]
param(
    [string]$Hostname = 'neon-hub-win.local',
    [string]$NeonHome,
    [string]$Timezone,
    [string]$AdminUsername,
    [SecureString]$AdminPassword,
    [switch]$TrustCert,
    [switch]$EnableMdns,
    [switch]$RotateSecrets,
    [switch]$SkipHostsEdit,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

# ───── Setup ──────────────────────────────────────────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error @"
installer.ps1 must run from an Administrator PowerShell — several steps
edit the hosts file or register Windows services. Right-click PowerShell ->
Run as administrator, then re-invoke.
"@
}

# Verify Docker Desktop is up before doing any work — fail fast if not.
& docker info 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker Desktop isn't running (`docker info` failed). Start it and re-run."
}

if (-not $NeonHome) { $NeonHome = Join-Path $env:USERPROFILE 'neon-hub' }
$NeonHome = $NeonHome.TrimEnd('\','/')

$windowsDir = $PSScriptRoot
$scriptsDir = Join-Path $windowsDir 'scripts'
$seedDir    = Join-Path $windowsDir 'seed'
$envFile    = Join-Path $windowsDir '.env'
$envExample = Join-Path $windowsDir '.env.example'

# Windows-TZ → IANA mapping for the most common North American + EU zones.
# Anything not in the table falls back to America/Chicago with a note;
# users can override with -Timezone.
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

# Prompt for missing admin creds. NonInteractive turns this into a hard error.
if (-not $AdminUsername) {
    if ($NonInteractive) { Write-Error "AdminUsername is required in -NonInteractive mode." }
    $AdminUsername = Read-Host -Prompt 'Hub admin username'
}
if (-not $AdminPassword) {
    if ($NonInteractive) { Write-Error "AdminPassword is required in -NonInteractive mode." }
    $AdminPassword = Read-Host -Prompt "Password for $AdminUsername" -AsSecureString
}

# ───── Plan summary ────────────────────────────────────────────────

Write-Host ""
Write-Host "═══ Neon Hub Installer ═══" -ForegroundColor Cyan
Write-Host "  Hostname        $Hostname"
Write-Host "  NEON_HOME       $NeonHome"
Write-Host "  Timezone        $Timezone"
Write-Host "  Admin user      $AdminUsername"
Write-Host "  Edit hosts file $(-not $SkipHostsEdit.IsPresent)"
Write-Host "  Trust TLS cert  $($TrustCert.IsPresent)"
Write-Host "  Register mDNS   $($EnableMdns.IsPresent)"
Write-Host "  Rotate secrets  $($RotateSecrets.IsPresent)"
Write-Host ""

if (-not $NonInteractive) {
    $reply = Read-Host "Proceed? [Y/n]"
    if ($reply -and $reply -notmatch '^[Yy]') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 1
    }
}

function Write-Step {
    param([string]$Title)
    Write-Host ""
    Write-Host "─── $Title ───" -ForegroundColor Cyan
}

# ───── 1. Hosts file ───────────────────────────────────────────────

if (-not $SkipHostsEdit) {
    Write-Step "Hosts file"
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

# ───── 2. TLS cert ─────────────────────────────────────────────────

Write-Step "TLS certificate"
$crtPath = Join-Path $NeonHome "$Hostname.crt"
if (Test-Path $crtPath) {
    Write-Host "Cert already at $crtPath; skipping." -ForegroundColor DarkGray
} else {
    & (Join-Path $scriptsDir 'new-cert.ps1') -Hostname $Hostname -OutDir $NeonHome
}

# ───── 3. Trust cert (optional) ────────────────────────────────────

if ($TrustCert) {
    Write-Step "Trust TLS cert"
    Import-Certificate -FilePath $crtPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Write-Host "Imported into LocalMachine\Root." -ForegroundColor Green
}

# ───── 4. Data tree + static files ─────────────────────────────────

Write-Step "Hub data tree"
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
Copy-Item (Join-Path $seedDir 'nginx.conf')        "$NeonHome\compose\"             -Force
Copy-Item (Join-Path $seedDir 'skill-config.json') "$NeonHome\compose\"             -Force
Copy-Item (Join-Path $seedDir 'neon-logo.png')     "$NeonHome\compose\"             -Force
Write-Host "Tree ready at $NeonHome." -ForegroundColor Green

# ───── 5. .env ─────────────────────────────────────────────────────

Write-Step ".env file"
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

# ───── 6. Python venv ──────────────────────────────────────────────

Write-Step "Python venv"
& (Join-Path $scriptsDir 'setup-python.ps1')

# ───── 7. Render Hub config templates ─────────────────────────────

Write-Step "Render Hub config templates"
$secretsArgs = @('-Hostname', $Hostname)
if ($RotateSecrets) { $secretsArgs += '-Rotate' }
& (Join-Path $scriptsDir 'generate-secrets.ps1') @secretsArgs

# ───── 8. docker compose up ────────────────────────────────────────

Write-Step "Bring up the container stack"
$composeFile = Join-Path $windowsDir 'docker-compose.yml'

# docker compose writes its progress to stderr; same dance as
# bootstrap-hub-admin.ps1 to keep the NativeCommandError from
# masking a successful run.
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& docker compose -p neon -f $composeFile --env-file $envFile up -d 2>&1 | Write-Host
$dockerExit = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($dockerExit -ne 0) { Write-Error "docker compose up failed (exit $dockerExit)" }

# ───── 9. Seed users ───────────────────────────────────────────────

Write-Step "Seed admin + neon_node users"
& (Join-Path $scriptsDir 'seed-users.ps1') `
    -AdminUsername $AdminUsername `
    -AdminPassword $AdminPassword

# ───── 10. Bootstrap admin token ───────────────────────────────────

Write-Step "Bootstrap Hub admin token"
& (Join-Path $scriptsDir 'bootstrap-hub-admin.ps1') `
    -AdminUsername $AdminUsername `
    -AdminPassword $AdminPassword

# ───── 11. mDNS (optional) ─────────────────────────────────────────

if ($EnableMdns) {
    Write-Step "Register mDNS publisher"
    & (Join-Path $scriptsDir 'register-mdns.ps1') -Hostname $Hostname
}

# ───── Done ────────────────────────────────────────────────────────

Write-Host ""
Write-Host "═══ Installation complete ═══" -ForegroundColor Green
Write-Host "  Hub Config UI   https://config.$Hostname/"
Write-Host "  HANA OpenAPI    https://hana.$Hostname/docs"
Write-Host "  RabbitMQ admin  https://rmq-admin.$Hostname/"
if (-not $TrustCert.IsPresent) {
    Write-Host ""
    Write-Host "  (Browsers will warn about the self-signed cert. Re-run with -TrustCert"
    Write-Host "   or import $crtPath into LocalMachine\Root to silence the warning.)" -ForegroundColor DarkGray
}
