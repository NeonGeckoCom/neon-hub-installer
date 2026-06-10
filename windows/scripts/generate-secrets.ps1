<#
.SYNOPSIS
    Generate per-host Hub secrets and render config templates.

.DESCRIPTION
    Replaces the static `windows/seed/{diana.yaml,
    rabbitmq.json,neon.yaml}` placeholders (committed to the public
    repo with hardcoded `devXXX` passwords) with fresh random
    secrets and renders the Linux/macOS Jinja2 templates against
    them. Mirrors debos/overlays/ansible/generate-secrets.yaml.

    The actual work is in the sibling `generate-secrets.py` (matches
    Linux/macOS's reliance on Python for templating). This wrapper
    parses NEON_HOME out of windows\.env, resolves the real python.exe
    via sys.executable (handling pyenv-win shims), verifies the
    jinja2 + PyYAML modules are installed, and invokes the renderer.

    Idempotent -- re-runs reuse the secrets file at
    `${NEON_HOME}\neon_hub_secrets.yaml`. Pass -Rotate to force fresh
    generation. RabbitMQ persists its user database in a Docker volume
    on first launch, so rotating after the stack has come up at least
    once requires `docker compose down -v` to take effect.

.PARAMETER Hostname
    NEON_HOSTNAME (e.g. `neon-hub-win.local`). Plugged into Jinja's
    `common_name` variable when rendering.

.PARAMETER Rotate
    Force a fresh secrets file even if one already exists.

.EXAMPLE
    .\generate-secrets.ps1 -Hostname neon-hub-win.local
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Hostname,
    [switch]$Rotate
)

$ErrorActionPreference = 'Stop'

# Resolve repo-relative paths.
$repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envFile      = Join-Path $repoRoot 'windows\.env'
$templatesDir = Join-Path $repoRoot 'debos\overlays\ansible\templates'
$pyScript     = Join-Path $PSScriptRoot 'generate-secrets.py'
foreach ($p in @($envFile, $templatesDir, $pyScript)) {
    if (-not (Test-Path $p)) { Write-Error "Required path missing: $p" }
}

# Parse NEON_HOME out of windows\.env.
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_][A-Z_0-9]*)\s*=\s*(.+?)\s*$') {
        $envVars[$matches[1]] = $matches[2].Trim('"').Trim("'")
    }
}
$neonHome = $envVars['NEON_HOME']
if (-not $neonHome) { Write-Error "NEON_HOME missing from $envFile" }

# Use the Hub venv set up by setup-python.ps1. Stable absolute path,
# no shim resolution, jinja2 + PyYAML already pinned.
$python = (Join-Path $neonHome 'venv\Scripts\python.exe') -replace '/', '\'
if (-not (Test-Path $python)) {
    Write-Error @"
Hub venv interpreter not found at $python.

Run windows\scripts\setup-python.ps1 first to create the venv and
install jinja2 + PyYAML.
"@
}

$secretsFile = (Join-Path $neonHome 'neon_hub_secrets.yaml') -replace '/', '\'
$outDir      = $neonHome -replace '/', '\'

$pyArgs = @(
    '--hostname',      $Hostname,
    '--templates-dir', $templatesDir,
    '--secrets-file',  $secretsFile,
    '--output-dir',    $outDir
)
if ($Rotate) { $pyArgs += '--rotate' }

Write-Host "Rendering Hub config templates into $outDir ..." -ForegroundColor Cyan
& $python $pyScript @pyArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "generate-secrets.py exited with code $LASTEXITCODE"
}

Write-Host ""
Write-Host "Secrets file: $secretsFile" -ForegroundColor Green
Write-Host "Rendered:" -ForegroundColor Green
Write-Host "  $outDir\xdg\config\rabbitmq\rabbitmq.json"
Write-Host "  $outDir\xdg\config\neon\diana.yaml"
Write-Host "  $outDir\xdg\config\neon\neon.yaml"
Write-Host "  $outDir\compose\nginx.conf"
