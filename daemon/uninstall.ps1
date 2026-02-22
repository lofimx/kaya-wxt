#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uninstalls the Save Button daemon from Windows.

.DESCRIPTION
    This script removes the Save Button daemon binary.
    It does NOT remove user data in ~/.kaya.

.NOTES
    Requires Administrator privileges.
#>

$ErrorActionPreference = "Stop"

$InstallDir = "$env:ProgramFiles\Save Button"

Write-Host "Uninstalling Save Button daemon..." -ForegroundColor Cyan

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
