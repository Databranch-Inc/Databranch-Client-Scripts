<#
O365 Bulk Username Update
Used to update a group of user's usernames in O365
Josh Britton
1.0
7-15-22#>

#Variable Set
$O365Admin = Read-Host "What is the the global admin name in the tenant?"
$NewDomainName = Read-Host ""

Import-Module msonline

Connect-EXOPSSession -UserPrincipalName $O365Admin