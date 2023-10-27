<#
Force O365 Sign out

This script is designed to take the UPNs from a .CSV device, and loop them to force an account logout in O365. This is normally used in conjunction with mass password changes within a tenant. As of this writing,  the password change is being done in O365 GUI to randomize.

=======================================================================================================================================================================
Josh Britton
8/22/23

=======================================================================================================================================================================
1.0

=======================================================================================================================================================================
#>

#Module Test/Import
$Module = Get-Module -ListAvailable -Name AzureAD | Select-Object -ExpandProperty Name

if ($Module){
    Write-Host "$Module is found on this machine. Importing"
    Import-Module azuread
}
else{
    Write-host "$Module is not found on this machine. Installing and Importing"
    Install-Module AzureAD -Force
    Import-Module AzureAD
}

#Variable Set
$CSVPath = Read-Host "Where is the .CSV file for users to logout?"
$users = Import-Csv "$CSVPath"

#connect to Azure AD
Connect-AzureAD

Foreach ($user in $users){
    Get-AzureADUSer -searchstring $user | Revoke-AzureADUserAllRefreshToken
    Write-Host "$User has been scheduled for O365 logout"
}
