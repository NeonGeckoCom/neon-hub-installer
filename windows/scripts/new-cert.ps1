<#
.SYNOPSIS
    Generate a self-signed TLS cert + key for the Neon Hub.

.DESCRIPTION
    Shells out to openssl.exe to produce <Hostname>.crt and <Hostname>.key
    under -OutDir. The SAN covers the chosen hostname plus localhost and
    127.0.0.1 so the cert is valid for any access pattern a local Hub will
    see.

    This is a *development* cert. The key is unencrypted. Do not reuse it
    on anything reachable outside the local machine. For production-grade
    cert provisioning, replace with an ACME / mkcert / corporate-CA flow.

.PARAMETER Hostname
    DNS hostname the Hub will serve under. Becomes the cert CN and the
    primary SAN. Must match the entry the installer adds to the Windows
    hosts file and the NEON_HOSTNAME value in .env.

.PARAMETER OutDir
    Directory to write <Hostname>.crt and <Hostname>.key into. Created
    if it does not exist.

.PARAMETER ValidDays
    Cert validity in days. Defaults to 10 years for dev use.

.EXAMPLE
    .\new-cert.ps1 -Hostname neon-hub-win.local -OutDir $env:USERPROFILE\neon-hub
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Hostname,
    [Parameter(Mandatory)][string]$OutDir,
    [int]$ValidDays = 3650
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    Write-Error @"
openssl.exe not found on PATH.

Install one of:
  - Git for Windows  (https://gitforwindows.org/) — bundles openssl under usr\bin
  - winget install ShiningLight.OpenSSL.Light
  - winget install FireDaemon.OpenSSL

Then re-run this script.
"@
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$crt = Join-Path $OutDir "$Hostname.crt"
$key = Join-Path $OutDir "$Hostname.key"

& openssl req -x509 -newkey rsa:4096 -nodes `
    -keyout $key -out $crt `
    -days $ValidDays `
    -subj "/CN=$Hostname/O=Neon Hub/OU=Dev" `
    -addext "subjectAltName=DNS:$Hostname,DNS:localhost,IP:127.0.0.1"

if ($LASTEXITCODE -ne 0) {
    Write-Error "openssl failed with exit code $LASTEXITCODE"
}

Write-Host "Wrote $crt" -ForegroundColor Green
Write-Host "Wrote $key" -ForegroundColor Green
