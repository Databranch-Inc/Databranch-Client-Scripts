<#
Local Account Disable Expiration Script
This script disables password expiration for all local user accounts on the machine.

Josh Britton with Co-Pilot Assist

Original Script Date: 8-28-25
Current Version Date: 8-28-25
Version: 1.0

================================================================================================================================================
1.0 - Initial script creation

===============================================================================================================================================
#>

Function Disable-LocalAccountPasswordExpiration {
    <#
    .SYNOPSIS
    Disables password expiration for all local user accounts on the machine.

    .DESCRIPTION
    This script retrieves all local user accounts and sets their PasswordNeverExpires property to True, effectively disabling password expiration.

    .EXAMPLE
    PS C:\> Disable-LocalAccountPasswordExpiration
    Disables password expiration for all local user accounts on the machine.

    .NOTES
#>

# Get all local users on the running PC
$LocalUsers = Get-LocalUser

# Loop through each user and set the PasswordNeverExpires property to True
foreach ($User in $LocalUsers) {
    if (-not $User.PasswordNeverExpires) {
        try {
            Set-LocalUser -Name $User.Name -PasswordNeverExpires $true
            Write-Host "Password expiration disabled for user: $($User.Name)" -ForegroundColor Green
        } catch {
            Write-Host "Failed to update user: $($User.Name). Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Password expiration already disabled for user: $($User.Name)" -ForegroundColor Yellow
    }
}
}