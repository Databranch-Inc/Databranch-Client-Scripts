<#
AD Gather All Users Script
This script gathers all enabled Active Directory users and exports their details to a CSV file.

Josh Britton
4-21-26
Version 1.0

============================================================================
1.0 - Initial script creation
============================================================================
#>

# Requires: ActiveDirectory module
# Check for the ActiveDirectory module and install if needed
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "ActiveDirectory module not found. Attempting to install..."
    try {
        Install-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction Stop
        Import-Module ActiveDirectory
        Write-Host "ActiveDirectory module installed and imported."
    } catch {
        Write-Error "Failed to install the ActiveDirectory module. Please install RSAT manually."
        exit 1
    }
} else {
    Import-Module ActiveDirectory
    Write-Host "ActiveDirectory module imported."
}

# Output CSV file path
$outputPath = ".\Enabled_AD_Users.csv"

# Gather enabled AD users
$users = Get-ADUser -Filter 'Enabled -eq $true' -Properties SamAccountName, Name, UserPrincipalName, Enabled, EmailAddress

# Select desired properties
$users | Select-Object SamAccountName, Name, UserPrincipalName, EmailAddress | Export-Csv -Path $outputPath -NoTypeInformation

Write-Host "Enabled AD users exported to $outputPath"