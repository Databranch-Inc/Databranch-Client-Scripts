<#Set AD Accounts
This script imports a list of users run and sets the desired AD Accounts login script info Attribute
Josh Britton
2/1/21
1.1.1
===================================================================================
1.1.1 Update
Modifing script to clear attribute for login script field. This is to cleanup users at CHPC
===================================================================================
1.1 Update
Import Module for Active Directory. Test C Drive path, fix order of changes
===================================================================================
#>

Import-Module ActiveDirectory


#Get the users AD .csv file and clear the login script field to prevent this non-existant file from running. Should save set the options to force a password change and remove the restriction on changing passwords

$users = Import-Csv "C:\Databranch\users.csv" | Select-Object -ExpandProperty SAMAccountname

ForEach ($user in $users)
{
    Set-ADUser -Identity $user  -Clear scriptpath
}