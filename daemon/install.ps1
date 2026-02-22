#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the Save Button daemon on Windows.

.DESCRIPTION
    This script builds and installs the Save Button daemon.
    It installs the binary to Program Files and creates the data directories.

.NOTES
    Requires Administrator privileges.
    Requires Rust/Cargo to be installed for building from source.
#>

$ErrorActionPreference = "Stop"

$BinaryName = "savebutton-daemon.exe"
$InstallDir = "$env:ProgramFiles\Save Button"
$KayaDataDir = "$env:USERPROFILE\.kaya"

Write-Host "Building Save Button daemon..." -ForegroundColor Cyan
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

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Binary installed to: $BinaryDest" -ForegroundColor White
Write-Host "Data directory: $KayaDataDir" -ForegroundColor White
Write-Host ""
Write-Host "To start the daemon:" -ForegroundColor Yellow
Write-Host "  & '$BinaryDest'"
Write-Host ""
Write-Host "The daemon listens on localhost:21420 and writes files to $KayaDataDir"
