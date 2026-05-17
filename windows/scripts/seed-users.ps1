<#
.SYNOPSIS
    Seed initial users into the neon-users-service SQLite database.

.DESCRIPTION
    Bypasses HANA's /auth/register because users-service has no admin-
    bootstrap mechanism — registering through HANA only creates users
    with default permissions and there's no admin-promotion path. The
    installer is a privileged context, so we write the rows directly,
    matching the Linux/macOS path (debos/overlays/ansible/seed-hana-users.yaml).

    Two users are seeded:
      - <AdminUsername>  with full ADMIN permissions across every
        subsystem (klat, core, diana, users, node, hub, llm).
      - neon_node        with NODE permissions, used by the Neon Node
        web/mobile clients to authenticate against HANA. The default
        password is read from windows\seed\diana.yaml so the seed
        matches the credential HANA is configured to accept.

    Idempotent — re-running with the same username updates the row
    rather than duplicating it (see seed-user.py upsert logic).

    Requirements:
      - The Hub compose stack must have come up at least once so the
        users-service image is pulled and the SQLite DB exists at
        ${NEON_HOME}/xdg/share/neon/users-service/neon-users-db.sqlite.
      - Docker Desktop running.

    The script stops the users-service container before writing (so
    the running service doesn't hold the SQLite file locked) and
    restarts it afterwards in a finally block.

.PARAMETER AdminUsername
    Admin user's username. Prompted if omitted.

.PARAMETER AdminPassword
    Admin user's password as a SecureString. Prompted if omitted.
    Stored as a SHA-256 hash to match users-service's /auth/login.

.PARAMETER NodePassword
    Override the default neon_node password (the one in diana.yaml).
    SecureString. Usually you want the default so HANA's
    `node_password` setting still matches.

.EXAMPLE
    .\seed-users.ps1
    # Prompts for admin username + password, seeds neon_node with the
    # password from diana.yaml.

.EXAMPLE
    .\seed-users.ps1 -AdminUsername mike -AdminPassword (Read-Host -AsSecureString)
#>
[CmdletBinding()]
param(
    [string]$AdminUsername,
    [SecureString]$AdminPassword,
    [SecureString]$NodePassword
)

$ErrorActionPreference = 'Stop'

# Resolve repo-relative paths from $PSScriptRoot (windows\scripts\).
$repoRoot    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$seedScript  = Join-Path $repoRoot 'debos\overlays\ansible\files\seed-user.py'
$envFile     = Join-Path $repoRoot 'windows\.env'
$dianaYaml   = Join-Path $repoRoot 'windows\seed\diana.yaml'
$composeFile = Join-Path $repoRoot 'windows\docker-compose.yml'

foreach ($p in @($seedScript, $envFile, $dianaYaml, $composeFile)) {
    if (-not (Test-Path $p)) { Write-Error "Required file missing: $p" }
}

# Parse NEON_HOME and MQ_IMAGE_TAG out of windows\.env. Lightweight
# `KEY=VALUE` reader; no quoting edge cases since the example .env
# uses bare values.
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_][A-Z_0-9]*)\s*=\s*(.+?)\s*$') {
        $envVars[$matches[1]] = $matches[2].Trim('"').Trim("'")
    }
}
$neonHome = $envVars['NEON_HOME']
$imageTag = $envVars['MQ_IMAGE_TAG']
if (-not $neonHome) { Write-Error "NEON_HOME missing from $envFile" }
if (-not $imageTag) { Write-Error "MQ_IMAGE_TAG missing from $envFile" }
$image = "ghcr.io/neongeckocom/neon-users-service:$imageTag"

# Docker on Windows accepts both \ and / in bind-mount sources, but
# forward slashes are the lowest-friction choice and match how the
# rest of the install treats NEON_HOME.
$seedScriptDocker = $seedScript -replace '\\', '/'
$dbDir            = (Join-Path $neonHome 'xdg\share\neon\users-service') -replace '\\', '/'

# Prompt for any creds that weren't passed as parameters.
if (-not $AdminUsername) {
    $AdminUsername = Read-Host -Prompt 'Hub admin username'
}
if (-not $AdminPassword) {
    $AdminPassword = Read-Host -Prompt "Password for $AdminUsername" -AsSecureString
}

# Pull node_password out of diana.yaml unless overridden.
if (-not $NodePassword) {
    $nodePwLine = (Get-Content $dianaYaml | Select-String -Pattern '^\s*node_password:').Line
    if (-not $nodePwLine) { Write-Error "node_password not found in $dianaYaml" }
    $nodePwPlain = ($nodePwLine -split ':', 2)[1].Trim().Trim('"').Trim("'")
} else {
    $nodePwPlain = (New-Object PSCredential 'x', $NodePassword).GetNetworkCredential().Password
}
$adminPwPlain = (New-Object PSCredential 'x', $AdminPassword).GetNetworkCredential().Password

# Permission maps mirror debos/overlays/ansible/seed-hana-users.yaml.
$adminPerms = '{"klat": 20, "core": 30, "diana": 30, "users": 30, "node": 20, "hub": 30, "llm": 20}'
$nodePerms  = '{"klat": -1, "core": -1, "diana": -1, "users": -1, "node": -1, "hub": -1, "llm": -1}'

# Write a tiny POSIX-shell wrapper to disk that pulls the seed values
# out of env vars at runtime. We can't pass an inline `sh -c "..."`
# string from PowerShell 5.1 to docker because PS's native-exe arg
# tokenizer splits the command on the embedded double quotes around
# the env-var refs, so docker only receives the head of the script.
# A wrapper file dodges that entirely.
$wrapperPath = Join-Path $env:TEMP "neon-seed-wrapper.sh"
# Force LF line endings — sh inside the container reads `command\r`
# tokens literally and fails with "command not found" on CRLF scripts.
# PowerShell's here-strings on Windows otherwise embed CRLF.
$wrapperContent = (@'
#!/bin/sh
exec python3 /tmp/seed-user.py /data/neon-users-db.sqlite "$SEED_USER_NAME" "$SEED_USER_PASS" "$SEED_USER_PERMS"
'@).Replace("`r`n", "`n")
[System.IO.File]::WriteAllText($wrapperPath, $wrapperContent)
$wrapperDocker = $wrapperPath -replace '\\', '/'

function Invoke-Seed {
    param(
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][string]$Perms
    )
    Write-Host "Seeding $Username ..." -ForegroundColor Cyan
    # `docker run -e VAR` (no =) inherits the host's value verbatim;
    # values pass through the environment, never through argv, so the
    # JSON's internal quotes survive intact.
    $env:MSYS_NO_PATHCONV = '1'
    $env:SEED_USER_NAME  = $Username
    $env:SEED_USER_PASS  = $Password
    $env:SEED_USER_PERMS = $Perms
    try {
        & docker run --rm `
            -e SEED_USER_NAME -e SEED_USER_PASS -e SEED_USER_PERMS `
            -v "${seedScriptDocker}:/tmp/seed-user.py:ro" `
            -v "${wrapperDocker}:/tmp/seed.sh:ro" `
            -v "${dbDir}:/data" `
            --entrypoint sh `
            $image `
            /tmp/seed.sh
        if ($LASTEXITCODE -ne 0) { Write-Error "Seed failed for $Username (exit $LASTEXITCODE)" }
    }
    finally {
        Remove-Item env:SEED_USER_NAME, env:SEED_USER_PASS, env:SEED_USER_PERMS -ErrorAction SilentlyContinue
    }
}

Write-Host "Stopping users-service so the SQLite file isn't locked ..." -ForegroundColor Cyan
& docker compose -p neon -f $composeFile --env-file $envFile stop users-service | Out-Null

try {
    Invoke-Seed -Username $AdminUsername -Password $adminPwPlain -Perms $adminPerms
    Invoke-Seed -Username 'neon_node'    -Password $nodePwPlain  -Perms $nodePerms
}
finally {
    Write-Host "Restarting users-service ..." -ForegroundColor Cyan
    & docker compose -p neon -f $composeFile --env-file $envFile start users-service | Out-Null
}

Write-Host ""
Write-Host "Seeded users: $AdminUsername (admin), neon_node (node)." -ForegroundColor Green
Write-Host "The Node app can now log in with neon_node / <node_password from diana.yaml>."
