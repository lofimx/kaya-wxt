#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the Save Button native host on Windows.

.DESCRIPTION
    This script builds and installs the Save Button native messaging host
    for all supported browsers. It installs the binary to Program Files and
    uses the --install flag to register native messaging manifests.

.NOTES
    Requires Administrator privileges.
    Requires Rust/Cargo to be installed for building from source.
#>

$ErrorActionPreference = "Stop"

$BinaryName = "savebutton-nativehost.exe"
$InstallDir = "$env:ProgramFiles\Save Button"
$KayaDataDir = "$env:USERPROFILE\.kaya"

Write-Host "Building Save Button native host..." -ForegroundColor Cyan
Push-Location $PSScriptRoot
try {
    cargo build --release
    if ($LASTEXITCODE -ne 0) {
        throw "Cargo build failed"
    }
} finally {
    Pop-Location
}

Write-Host "Creating installation directory..." -ForegroundColor Cyan
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

Write-Host "Installing binary..." -ForegroundColor Cyan
$BinarySource = Join-Path $PSScriptRoot "target\release\$BinaryName"
$BinaryDest = Join-Path $InstallDir $BinaryName
Copy-Item -Path $BinarySource -Destination $BinaryDest -Force

Write-Host "Creating data directories..." -ForegroundColor Cyan
$AngaDir = Join-Path $KayaDataDir "anga"
$MetaDir = Join-Path $KayaDataDir "meta"
if (-not (Test-Path $AngaDir)) {
    New-Item -ItemType Directory -Path $AngaDir -Force | Out-Null
}
if (-not (Test-Path $MetaDir)) {
    New-Item -ItemType Directory -Path $MetaDir -Force | Out-Null
}

Write-Host "Installing native messaging manifests for all browsers..." -ForegroundColor Cyan
& $BinaryDest --install

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Binary installed to: $BinaryDest" -ForegroundColor White
Write-Host "Data directory: $KayaDataDir" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Install the browser extension from your browser's extension store"
Write-Host "2. Configure the extension with your Save Button server credentials"
