# Connect to AD
Import-Module ActiveDirectory

# OU of user objects - EX "OU=Accounts,OU=Managed,DC=froqr,DC=com"
$OU = 

$users = Get-ADUser -SearchBase $OU -Filter *

foreach ($user in $users){
  Set-ADUser -Identity $user -Clear HomeDirectory,HomeDrive, ProfilePath
}