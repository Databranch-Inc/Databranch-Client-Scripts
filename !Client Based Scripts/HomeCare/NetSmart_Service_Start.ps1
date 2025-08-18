<#
NetSmart Service Start Script

This script is designed to start any of the non-running NetSmart services for Homecare and Hospice.

The script will first check for "Netsmart Homecare Services Service" to be in a running state, then will loop though all the other Netsmart services and attempt to start them if they are not already running.

Version 1.0

Original Author - Josh Britton
Original Date - 7-24-25

=====================================================================================
Version 1.0

Original creation - JB
=====================================================================================
#>  

#Monitor for the NetSmart Homecare Services Service
try {
    $mainService = Get-Service -Name "NHC_Homecareservices" -ErrorAction Stop
    if ($mainService.Status -ne 'Running') {
        Write-Host "NHC_Homecareservices is not running. Attempting to start..."
        Start-Service -Name "NHC_Homecareservices"
        Start-Sleep -Seconds 120
    } else {
        Write-Host "NHC_Homecareservices is already running."
    }
} 

catch {
    Write-Host "Error retrieving or starting NHC_Homecareservices: $_"
}

# Check for other NHC_ services that are not running
$otherServices = Get-Service -Name "NHC_*" | Where-Object { $_.Status -ne 'Running' -and $_.Name -ne "NHC_Homecareservices" }
foreach ($svc in $otherServices) {
    Write-Host "Service $($svc.Name) is not running. Attempting to start..."
    try {
        Start-Service -Name $svc.Name
    } catch {
        Write-Host "Error starting service $($svc.Name): $_"
    }
}