#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls the Save Button native host from Windows.

.DESCRIPTION
    This script removes the Save Button native messaging host binary and
    manifests/registry entries for all browsers. It does NOT remove user data in ~/.kaya.

.NOTES
    Requires Administrator privileges.
#>

$ErrorActionPreference = "Stop"

$BinaryName = "savebutton-nativehost.exe"
$InstallDir = "$env:ProgramFiles\Save Button"
$BinaryPath = Join-Path $InstallDir $BinaryName

Write-Host "Uninstalling Save Button native host..." -ForegroundColor Cyan

# Remove native messaging manifests via --uninstall
if (Test-Path $BinaryPath) {
    Write-Host "Removing native messaging manifests..." -ForegroundColor Cyan
    try {
        & $BinaryPath --uninstall
        Write-Host "  Native messaging manifests removed" -ForegroundColor Gray
    } catch {
        Write-Host "  Warning: could not remove manifests: $_" -ForegroundColor Yellow
    }
}

# Remove installation directory
Write-Host "Removing installation directory..." -ForegroundColor Cyan
if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force
    Write-Host "  Directory removed: $InstallDir" -ForegroundColor Gray
} else {
    Write-Host "  Directory not found (already removed)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Uninstallation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Note: User data in $env:USERPROFILE\.kaya was NOT removed." -ForegroundColor Yellow
Write-Host "Delete it manually if you want to remove all Save Button data." -ForegroundColor Yellow
