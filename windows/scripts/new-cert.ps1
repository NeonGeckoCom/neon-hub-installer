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

# Resolve openssl.exe: prefer PATH, then probe the well-known install dirs.
# ShiningLight and Git for Windows don't add openssl to PATH by default,
# so we try those locations explicitly before giving up.
$opensslExe = (Get-Command openssl -ErrorAction SilentlyContinue).Source
if (-not $opensslExe) {
    $candidates = @(
        "$env:ProgramFiles\OpenSSL-Win64\bin\openssl.exe",
        "$env:ProgramFiles\FireDaemon OpenSSL 3\bin\openssl.exe",
        "$env:ProgramFiles\Git\usr\bin\openssl.exe",
        "${env:ProgramFiles(x86)}\OpenSSL-Win32\bin\openssl.exe"
    )
    $opensslExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $opensslExe) {
    Write-Error @"
openssl.exe not found on PATH or in any well-known install dir.

Install one of (FireDaemon adds itself to PATH by default; the others
require either checking the "Add to PATH" option in the installer or
adding the bin dir manually):

  - winget install FireDaemon.OpenSSL
  - winget install ShiningLight.OpenSSL.Light
  - Git for Windows (https://gitforwindows.org/) — bundles openssl under usr\bin

Then re-run this script. (This script will find openssl whether or not
it's on PATH, as long as it's installed in a standard location.)
"@
}

Write-Host "Using $opensslExe" -ForegroundColor DarkGray
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$crt = Join-Path $OutDir "$Hostname.crt"
$key = Join-Path $OutDir "$Hostname.key"

& $opensslExe req -x509 -newkey rsa:4096 -nodes `
    -keyout $key -out $crt `
    -days $ValidDays `
    -subj "/CN=$Hostname/O=Neon Hub/OU=Dev" `
    -addext "subjectAltName=DNS:$Hostname,DNS:localhost,IP:127.0.0.1"

if ($LASTEXITCODE -ne 0) {
    Write-Error "openssl failed with exit code $LASTEXITCODE"
}

Write-Host "Wrote $crt" -ForegroundColor Green
Write-Host "Wrote $key" -ForegroundColor Green
