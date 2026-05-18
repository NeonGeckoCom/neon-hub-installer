<#
.SYNOPSIS
    Create the Hub's Python venv and install its dependencies.

.DESCRIPTION
    The Hub's helper scripts (`mdns-publisher.py`,
    `generate-secrets.py`) need a handful of pip packages
    (zeroconf, jinja2, PyYAML). Rather than installing them into the
    user's system Python -- which would pollute pyenv shims and force
    the LocalSystem-run mDNS service to use a path-dependent
    interpreter -- this script creates an isolated venv under
    `${NEON_HOME}\venv` and pip-installs `windows\requirements.txt`
    into it.

    Sibling scripts that need Python then point at
    `${NEON_HOME}\venv\Scripts\python.exe` directly, which:

      - is a stable absolute path the user controls (no PATH
        guessing, no pyenv shim resolution)
      - is readable by LocalSystem when Shawl runs
        `mdns-publisher.py` as the NeonHubMdnsService

    Idempotent: re-running upgrades existing packages but doesn't
    re-create the venv.

.PARAMETER PythonPath
    Path to the base python.exe used to create the venv. Defaults
    to `python` on PATH; resolved through `sys.executable` so pyenv-win
    or other shims unwrap to the real interpreter.

.EXAMPLE
    .\setup-python.ps1
#>
[CmdletBinding()]
param(
    [string]$PythonPath
)

$ErrorActionPreference = 'Stop'

# Resolve repo-relative paths and parse NEON_HOME.
$repoRoot     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$envFile      = Join-Path $repoRoot 'windows\.env'
$requirements = Join-Path $repoRoot 'windows\requirements.txt'
foreach ($p in @($envFile, $requirements)) {
    if (-not (Test-Path $p)) { Write-Error "Required path missing: $p" }
}
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([A-Z_][A-Z_0-9]*)\s*=\s*(.+?)\s*$') {
        $envVars[$matches[1]] = $matches[2].Trim('"').Trim("'")
    }
}
$neonHome = $envVars['NEON_HOME']
if (-not $neonHome) { Write-Error "NEON_HOME missing from $envFile" }

# Resolve the base python.exe. Unwrap pyenv-win and similar shims via
# sys.executable so the venv we create is built off the actual binary.
if (-not $PythonPath) {
    $shim = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $shim) {
        Write-Error @"
python.exe not found on PATH.

Install Python from python.org or via winget:
  winget install -e --id Python.Python.3.12
"@
    }
    $PythonPath = (& $shim -c "import sys; print(sys.executable)" 2>$null).Trim()
}
if (-not (Test-Path $PythonPath)) { Write-Error "Base Python not found at $PythonPath" }
Write-Host "Base interpreter: $PythonPath" -ForegroundColor DarkGray

$venvDir = (Join-Path $neonHome 'venv') -replace '/', '\'
$venvPython = Join-Path $venvDir 'Scripts\python.exe'

if (-not (Test-Path $venvPython)) {
    Write-Host "Creating venv at $venvDir ..." -ForegroundColor Cyan
    & $PythonPath -m venv $venvDir
    if ($LASTEXITCODE -ne 0) { Write-Error "venv creation failed (exit $LASTEXITCODE)" }
} else {
    Write-Host "Reusing existing venv at $venvDir" -ForegroundColor DarkGray
}

Write-Host "Upgrading pip + installing dependencies ..." -ForegroundColor Cyan
& $venvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { Write-Error "pip upgrade failed (exit $LASTEXITCODE)" }
& $venvPython -m pip install -r $requirements
if ($LASTEXITCODE -ne 0) { Write-Error "pip install failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "Hub venv ready: $venvPython" -ForegroundColor Green
Write-Host "Installed:" -ForegroundColor DarkGray
& $venvPython -m pip list --disable-pip-version-check --format=columns | Where-Object {
    $_ -match '^(zeroconf|Jinja2|PyYAML)\s'
}
