<#
Exchange Online - Set new Domain Alias to All accounts

This script will take a newly added/validated domain in O365, and create an alias to all found mailboxes using the new domain.

Author - Josh Britton
Origional Write - 3-3-25
Last Update - 3-3-25
Version 1.0

References

============================================================================================================
1.0


============================================================================================================
#>

Function Add-EmailDomain{

    <#
    .SYNOPSIS
        Adds an additional validated email domain to all users in an O365 tenant
    .DESCRIPTION
        
    .PARAMETER domain
        The new domain to add to all users
    .OUTPUTS
        
    .NOTES
        
    .EXAMPLE
        
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$domain

    )

#Connect to Exchange Online
Connect-ExchangeOnline

#Get the users 

$users = Get-Mailbox -ResultSize Unlimited

ForEach ($user in $users)
{
    $alias = $user.Alias + "@" + "$Domain"
    Set-Mailbox -Identity $user.Identity -EmailAddresses @{Add=$alias}
}
}