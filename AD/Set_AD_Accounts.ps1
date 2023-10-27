<#Set AD Accounts
This script imports the active listed users from a recent SCRIPTS run and sets the AD Accounts to force a password change at next logon
Josh Britton
9/10/19
1.1
==============================================
1.1 Update
Import Module for Active Directory. Test C Drive path, fix order of changes


===============================================
#>

Import-Module ActiveDirectory

#Run a special AD user export to .CSV to only gather enabled non-admin and non-service accounts

GET-ADUSER -filter * -properties * | Where-Object {($_.Admincount -ne "1") -and ($_.enabled -eq "True")} | select-object name,SAMAccountname,lastlogondate,enabled,primarygroup | Export-Csv "C:\Databranch\userstoresetAD.csv" -NoTypeInformation -Encoding UTF8


#Get the users AD .csv file and set the options to force a password change and remove the restriction on changing passwords

$users = Import-Csv "C:\Databranch\userstoresetAD.csv" | Select-Object -ExpandProperty SAMAccountname

ForEach ($user in $users)
{
    Set-ADUser -Identity $user -CannotChangePassword $false
    #Set-ADUser -Identity $user -ChangePasswordAtLogon $True
}