<#Set AD Accounts
This script imports a list of users run and updates common fields to prep for Entra ID Sync

Josh Britton
2/26/25

Current Version - 1.0
Fork from other Bulk Update Scripts designed to be run on Domain Controllers
===================================================================================
1.0

Uploads a users.csv file to get desired usernames. Sets the UPN to 

===================================================================================
#>
Function Update-ADUserEntraID{
#Import AD Module
Import-Module ActiveDirectory

#Variable Set

$UPN = @upn@
$CompanyID = @CompanyID@


#Get the users AD .csv file and clear the login script field to prevent this non-existant file from running. Should save set the options to force a password change and remove the restriction on changing passwords

$users = Import-Csv "C:\Databranch\users.csv" | Select-Object -ExpandProperty SAMAccountname

ForEach ($user in $users)
{
    Set-ADUser -Identity $user -Clear Email
    Set-ADUser -Identity $user -UserPrincipalName $UPN
    Set-ADUser -Identity $user -Company $CompanyID
}
}