<#
Exchange Online - Set new Domain Alias to All accounts - Azure AD

This script will take a newly added/validated domain in O365, and create an alias to all found mailboxes using the new domain. This script is designed for users who have Entra ID/Azure AD Sync enabled. Work here will be done against AD

Author - Josh Britton
Origional Write - 3-4-25
Last Update - 3-3-25
Version 1.0

References



============================================================================================================
1.0


============================================================================================================
#>
Function Update-ADUserEntraID{
    <#
    .SYNOPSIS
        Resets a Domain Admin Password
    .DESCRIPTION
        Checks the account is a Domain Admin, generates a secure password if needed and resets the password
    .PARAMETER UPN
        The Domain's UPN
    .PARAMETER 
        The password to set which is optional
    .OUTPUTS
        
    .NOTES
        
    .EXAMPLE
        
    #>





    
    #Module Upload
    Import-Module ActiveDirectory


    #Account Gather
    $users = Import-Csv "C:\Databranch\users.csv" | Select-Object -ExpandProperty SAMAccountname


    #Loop through accoutns to add alias domain

    ForEach ($user in $users)
    {
        Set-ADUser -Identity $user
        Set-ADUser -Identity $user -UserPrincipalName $UPN
        Set-ADUser -Identity $user -Company $CompanyID
    }
    }