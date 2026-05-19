<#
.SYNOPSIS
    Authenticate as the Hub admin and write hub_admin.yaml so the
    neon-hub-config container can talk to HANA.

.DESCRIPTION
    The seeded Hub admin user (created by seed-users.ps1) already
    exists in users-service; this script authenticates against
    HANA's /auth/login, captures the refresh_token from the response,
    and writes ${NEON_HOME}/xdg/config/neon/hub_admin.yaml in the
    shape neon-hub-config expects.

    Mirrors debos/overlays/ansible/bootstrap-hub-admin.yaml. The
    Windows compose maps hana to host port 8082 (same as the Linux/macOS
    render), so the HTTP path is `http://localhost:8082/auth/login` --
    no cert dance needed.

    Idempotent. If `hub_admin.yaml` already contains a refresh_token
    for the same admin username, the script exits without re-hitting
    HANA -- rotating the named token on every installer run buys
    nothing and HANA's auth path has a real cost (users-service over
    MQ, DB write per call). Pass `-Force` to override, e.g. after a
    password change that invalidates the cached token.

    The hub_config container has `restart: unless-stopped`, so once
    hub_admin.yaml is correct the next restart cycle picks it up.
    On a non-skipped run the script issues an explicit
    `docker compose restart hub_config` for snappier feedback.

.PARAMETER AdminUsername
    Admin user's username. Prompted if omitted. Must match a user
    seeded by seed-users.ps1.

.PARAMETER AdminPassword
    Admin user's password as a SecureString. Prompted if omitted.

.PARAMETER HanaUrl
    Base URL for HANA. Defaults to http://localhost:8082.

.PARAMETER TimeoutSeconds
    How long to wait for HANA to become reachable before giving up.
    Default 120 seconds.

.PARAMETER Force
    Re-authenticate against HANA and overwrite hub_admin.yaml even
    when an existing refresh_token is already present for this admin.
    Use after a password change or if the cached token has expired.

.EXAMPLE
    .\bootstrap-hub-admin.ps1
    # Prompts for admin creds, hits http://localhost:8082.

.EXAMPLE
    .\bootstrap-hub-admin.ps1 -AdminUsername neon -AdminPassword (Read-Host -AsSecureString)
#>
[CmdletBinding()]
param(
    [string]$AdminUsername,
    [SecureString]$AdminPassword,
    [string]$HanaUrl = 'http://localhost:8082',
    [int]$TimeoutSeconds = 120,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Resolve repo-relative paths and parse NEON_HOME from windows\.env.
$repoRoot    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envFile     = Join-Path $repoRoot 'windows\.env'
$composeFile = Join-Path $repoRoot 'windows\docker-compose.yml'
foreach ($p in @($envFile, $composeFile)) {
    if (-not (Test-Path $p)) { Write-Error "Required file missing: $p" }
}
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_][A-Z_0-9]*)\s*=\s*(.+?)\s*$') {
        $envVars[$matches[1]] = $matches[2].Trim('"').Trim("'")
    }
}
$neonHome = $envVars['NEON_HOME']
if (-not $neonHome) { Write-Error "NEON_HOME missing from $envFile" }
$hubAdminFile = (Join-Path $neonHome 'xdg/config/neon/hub_admin.yaml') -replace '/', '\'

# Prompt for the username first so the idempotency check can compare
# against the existing hub_admin.yaml before we bother prompting for
# the password (which we won't need if we end up skipping the login).
if (-not $AdminUsername) { $AdminUsername = Read-Host -Prompt 'Hub admin username' }

# Skip the HANA round-trip when hub_admin.yaml already has a token
# for this admin. Pass -Force to override (e.g. after a password
# change that invalidated the cached token).
if (-not $Force.IsPresent -and (Test-Path $hubAdminFile)) {
    $existing      = Get-Content $hubAdminFile -Raw
    $existingUser  = if ($existing -match '(?m)^username:\s*(.+?)\s*$')      { $matches[1].Trim('"').Trim("'") } else { '' }
    $existingToken = if ($existing -match '(?m)^refresh_token:\s*(.+?)\s*$') { $matches[1].Trim('"').Trim("'") } else { '' }
    if ($existingUser -eq $AdminUsername -and $existingToken) {
        Write-Host "hub_admin.yaml already has a refresh_token for '$AdminUsername'; skipping login." -ForegroundColor DarkGray
        Write-Host '  (Pass -Force to mint a new token after a password change.)' -ForegroundColor DarkGray
        return
    }
}

if (-not $AdminPassword) { $AdminPassword = Read-Host -Prompt "Password for $AdminUsername" -AsSecureString }
$adminPwPlain = (New-Object PSCredential 'x', $AdminPassword).GetNetworkCredential().Password

# Wait for HANA to be ready. /docs is FastAPI's built-in OpenAPI page --
# always returns 200 once the app's listener is up.
Write-Host "Waiting for HANA at $HanaUrl ..." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$ready = $false
while ((Get-Date) -lt $deadline) {
    try {
        $r = Invoke-WebRequest -Uri "$HanaUrl/docs" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch {
        Start-Sleep -Seconds 5
    }
}
if (-not $ready) {
    Write-Error "HANA never returned 200 from $HanaUrl/docs within $TimeoutSeconds seconds. Is the stack up?"
}

# POST /auth/login. Retries cover users-service MQ warm-up -- HANA's
# login path validates against users-service over RabbitMQ, and that
# consumer may take 30-60s to start after `docker compose up`.
Write-Host "Authenticating as $AdminUsername ..." -ForegroundColor Cyan
$body = @{
    username   = $AdminUsername
    password   = $adminPwPlain
    token_name = 'hub-admin'
} | ConvertTo-Json -Compress

$loginResp = $null
$attempts  = 12
for ($i = 1; $i -le $attempts; $i++) {
    try {
        $loginResp = Invoke-RestMethod -Uri "$HanaUrl/auth/login" -Method POST `
            -ContentType 'application/json' -Body $body -TimeoutSec 10
        break
    } catch {
        if ($i -eq $attempts) {
            Write-Error "Login failed after $attempts attempts: $($_.Exception.Message)"
        }
        Write-Host "  attempt $i failed; retrying in 10s ..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 10
    }
}
$refreshToken = $loginResp.refresh_token
if (-not $refreshToken) {
    Write-Error "Login succeeded but the response had no refresh_token field."
}

# Write hub_admin.yaml. JSON-encode each value so passwords / tokens
# with quotes or backslashes survive into YAML cleanly -- JSON's string
# encoding is a valid YAML string literal.
$usernameYaml = $AdminUsername | ConvertTo-Json -Compress
$passwordYaml = $adminPwPlain  | ConvertTo-Json -Compress
$tokenYaml    = $refreshToken  | ConvertTo-Json -Compress

$content = @"
# Generated by windows\scripts\bootstrap-hub-admin.ps1.
# refresh_token expires per HANA's refresh_token_ttl setting; rerun
# this script to obtain a fresh token if hub_config starts failing
# its HANA auth.
username: $usernameYaml
password: $passwordYaml
refresh_token: $tokenYaml
"@

$dir = Split-Path -Parent $hubAdminFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllText($hubAdminFile, $content)
Write-Host "Wrote $hubAdminFile" -ForegroundColor Green

# Restart hub_config so it picks up the new token without waiting for
# its `restart: unless-stopped` retry cycle. Tolerated if the service
# is currently down or compose can't find it.
#
# docker compose writes its progress to stderr; PowerShell 5.1 escalates
# any native-exe stderr to a NativeCommandError under
# $ErrorActionPreference = 'Stop', which would mistakenly abort the
# script after a successful restart. Redirecting 2>&1 and piping to
# Out-Null routes everything through the success stream so $LASTEXITCODE
# is the only signal that matters.
Write-Host "Restarting hub_config container ..." -ForegroundColor Cyan
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& docker compose -p neon -f $composeFile --env-file $envFile restart hub_config 2>&1 | Out-Null
$dockerExit = $LASTEXITCODE
$ErrorActionPreference = $prev
if ($dockerExit -ne 0) {
    Write-Host '  (hub_config was not running yet -- that is fine, it will come up on the next docker compose up -d.)' -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done. neon-hub-config should now reach HANA with the refresh token." -ForegroundColor Green
Write-Host "Verify with: https://config.neon-hub-win.local/" -ForegroundColor Cyan
