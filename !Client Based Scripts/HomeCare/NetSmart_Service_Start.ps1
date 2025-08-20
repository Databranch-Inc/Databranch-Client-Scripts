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
do{
    $service = Get-Service -Name "NHC_Homecareservices" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        Write-Host "NHC_Homecareservices is running."
        break
    } else {
        Write-Host "NHC_Homecareservices is not running. Waiting for it to start..."
        Start-Service -Name "NHC_Homecareservices"
        Start-Sleep -Seconds 30
    }
} while ($service.Status -ne 'Running')


# Check for other NHC_ services that are not running
do{
    $otherServices = Get-Service -Name "NHC_*" | Where-Object { $_.Status -ne 'Running' -and $_.Name -ne "NHC_Homecareservices" }
    if ($otherServices.Count -eq 0) {
        Write-Host "All NHC_* services are running."
        break
    } else {
        Write-Host "Found non-running NHC_* services. Attempting to start them..."
    }
    
    foreach ($svc in $otherServices) {
        try {
            Start-Service -Name $svc.Name
            Write-Host "Started service: $($svc.Name)"
        } catch {
            Write-Host "Error starting service $($svc.Name): $_"
        }
    }
    
    Start-Sleep -Seconds 30
} while ($true)
