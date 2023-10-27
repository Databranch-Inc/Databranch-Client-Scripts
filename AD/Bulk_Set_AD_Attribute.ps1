<#Set AD Accounts
This script imports a list of users run and sets the desired AD Accounts Company Attribute
Josh Britton
8/12/29
1.1
===================================================================================
1.1 Update
Import Module for Active Directory. Test C Drive path, fix order of changes

===================================================================================
#>

Import-Module ActiveDirectory

#Run a special AD user export to .CSV to only gather enabled non-admin and non-service accounts

GET-ADUSER -filter * -properties * | Where-Object {($_.Admincount -ne "1") -and ($_.enabled -eq "True")} | select-object name,SAMAccountname,lastlogondate,enabled,primarygroup | Export-Csv "C:\Databranch\userstoresetAD.csv" -NoTypeInformation -Encoding UTF8


#Get the users AD .csv file and set the options to force a password change and remove the restriction on changing passwords

$users = Import-Csv "C:\Databranch\O365_users.csv" | Select-Object -ExpandProperty SAMAccountname
$Company = "Mazza"

ForEach ($user in $users)
{
    Set-ADUser -Identity $user -Company $Company
}