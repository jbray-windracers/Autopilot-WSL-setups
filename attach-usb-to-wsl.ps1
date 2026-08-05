#!/usr/bin/env pwsh
# Run this from a Windows PowerShell (regular, non-admin is fine for attach;
# the one-time 'bind' step needs an elevated prompt - see SETUP.md).
# Usage: .\attach-usb-to-wsl.ps1 [-Filter "STLink"] [-Distro "Ubuntu-26.04"]
param(
    [string]$Filter = "STLink|ST-Link|STM32|CMSIS-DAP|Black Magic",
    [string]$Distro = "Ubuntu-26.04"
)

Write-Host "Available USB devices:" -ForegroundColor Cyan
usbipd list

$matches = usbipd list | Select-String -Pattern $Filter
if (-not $matches) {
    Write-Warning "No device matched filter '$Filter'. Copy the BUSID for your probe from the list above and run:"
    Write-Host "  usbipd bind --busid <BUSID>     (one-time, elevated prompt)"
    Write-Host "  usbipd attach --wsl --busid <BUSID> --distribution $Distro"
    exit 1
}

foreach ($m in $matches) {
    $busid = ($m -split '\s+')[0]
    Write-Host "Attaching busid $busid to $Distro ..." -ForegroundColor Green
    usbipd attach --wsl --busid $busid --distribution $Distro
}
