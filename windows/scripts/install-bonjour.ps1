<#
.SYNOPSIS
    Ensure Bonjour Print Services for Windows is installed.

.DESCRIPTION
    Bonjour ships dns-sd.exe (the mDNS publisher we use for Hub LAN
    advertisement) and the mDNSResponder service (which lets Windows
    resolve other devices' .local hostnames as well). This script
    detects an existing install via the "Bonjour Service" Windows
    service; if absent, downloads BonjourPSSetup.exe from Apple and
    runs it silently.

    Idempotent — safe to re-run on a machine that already has Bonjour.

.PARAMETER InstallerUrl
    Override the download URL. Defaults to Apple's current public link
    for Bonjour Print Services. Worth overriding only if Apple moves
    the file and you've found the new location.

.PARAMETER CacheDir
    Where to drop the downloaded installer. Defaults to the user's temp
    dir; the file is left in place after install so re-runs don't re-
    download.

.EXAMPLE
    .\install-bonjour.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallerUrl = 'https://download.info.apple.com/Mac_OS_X/061-7495.20120907.Brrtb/BonjourPSSetup.exe',
    [string]$CacheDir = $env:TEMP
)

$ErrorActionPreference = 'Stop'

if (Get-Service -Name 'Bonjour Service' -ErrorAction SilentlyContinue) {
    Write-Host "Bonjour Service is already installed." -ForegroundColor Green
    return
}

$installerPath = Join-Path $CacheDir 'BonjourPSSetup.exe'
if (-not (Test-Path $installerPath)) {
    Write-Host "Downloading Bonjour Print Services from $InstallerUrl ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $installerPath -UseBasicParsing
}

Write-Host "Running Bonjour installer silently ..." -ForegroundColor Cyan
$proc = Start-Process -FilePath $installerPath `
    -ArgumentList '/quiet', '/norestart' `
    -PassThru -Wait
if ($proc.ExitCode -ne 0) {
    Write-Error "Bonjour installer exited with code $($proc.ExitCode)"
}

# Verify dns-sd.exe landed where we expect
$dnsSd = "$env:ProgramFiles\Bonjour\dns-sd.exe"
if (-not (Test-Path $dnsSd)) {
    Write-Error "Bonjour appears installed but dns-sd.exe is missing from $dnsSd"
}

Write-Host "Bonjour installed. dns-sd.exe at $dnsSd" -ForegroundColor Green
