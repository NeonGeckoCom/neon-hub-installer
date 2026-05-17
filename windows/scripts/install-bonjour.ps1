<#
.SYNOPSIS
    Ensure Bonjour Print Services for Windows is installed.

.DESCRIPTION
    Bonjour ships dns-sd.exe (the mDNS publisher we use for Hub LAN
    advertisement) and the mDNSResponder service (which lets Windows
    resolve other devices' .local hostnames as well). This script
    detects an existing install via the "Bonjour Service" Windows
    service; if absent, installs Apple.BonjourPrintServices from
    winget.

    Apple retired the standalone BonjourPSSetup.exe download some time
    after the original Phase 2.2 commit was written (the previous
    direct-URL strategy now 302s to a 404). winget's
    Apple.BonjourPrintServices is the current Apple-published vehicle.

    Idempotent — safe to re-run on a machine that already has Bonjour.

.EXAMPLE
    .\install-bonjour.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if (Get-Service -Name 'Bonjour Service' -ErrorAction SilentlyContinue) {
    Write-Host "Bonjour Service is already installed." -ForegroundColor Green
    return
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error @"
winget is not available on this machine.

winget ships with Windows 10/11 via the "App Installer" package. If
it's missing, install it from the Microsoft Store ("App Installer") or
from https://aka.ms/getwinget, then re-run this script.
"@
}

Write-Host "Installing Apple.BonjourPrintServices via winget ..." -ForegroundColor Cyan
& winget install -e --id Apple.BonjourPrintServices `
    --accept-source-agreements `
    --accept-package-agreements
if ($LASTEXITCODE -ne 0) {
    Write-Error "winget install failed with exit code $LASTEXITCODE"
}

# Verify dns-sd.exe is callable. Modern Bonjour Print Services puts
# dns-sd.exe in C:\Windows\System32\ (which is always on PATH); older
# versions kept it in C:\Program Files\Bonjour\ alongside
# mDNSResponder.exe. Resolve via Get-Command so either layout works.
$dnsSd = (Get-Command dns-sd -ErrorAction SilentlyContinue).Source
if (-not $dnsSd) {
    Write-Error "Bonjour appears installed but dns-sd.exe is not on PATH or in C:\Program Files\Bonjour\"
}

Write-Host "Bonjour installed. dns-sd.exe at $dnsSd" -ForegroundColor Green
