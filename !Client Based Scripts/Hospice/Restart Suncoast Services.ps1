<#
Restart Sun Coast Services
This script will stop and restart the 2 necessary SunCoast Services. This can be run if any of the agents (outside of the Progress Adapter for Training) are in an error or unknown state.
If the service is not running, this script will only start it without reporting an error message.
#>

Write-Host "Stopping and starting 'Solutions Service - Production' and 'Solutions Service - Training'" -ForegroundColor Green

Get-Service | Where-Object {$_.Name -like "Solutions*"} | Restart-Service

Start-Sleep 5