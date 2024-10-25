<#Monitor Network Profiles

This script is desiged to gather information regarding networking profiles on a machine. Specifically, this is looking for the network type to ensure that servers keep Domain Network Profiles.

Data from this can be exported/gathered into CW Automate, where we can alert as needed

Josh Britton

1.0

Initial Write 10-3-24
Last Update

=====================================================================================
1.0

Script Initial Write
=====================================================================================
#>


#Gather Network Info
$NetConnectionProfile = Get-NetConnectionProfile | Select-Object -Property Name,InterfaceAlias,NetworkCategory

