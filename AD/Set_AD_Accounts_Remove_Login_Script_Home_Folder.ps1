<#Set AD Accounts - Remove Login Script and Home Folder
This script will walk through a directory and remove items from the Login Scripts or Home Folder Attribute on the accounts


Josh Britton
12/17/24
1.0
==============================================
1. Creation
Initial Script Write
=============================================
#>

Function Clear-ADUSERLOGINSCRIPTHOMEDRIVE{

#import AD Module
Import-Module ActiveDirectory

$users = GET-ADUSER -filter * -properties * | select-object -ExpandProperty SAMAccountname 


#Get the users AD .csv file and set the options to force a password change and remove the restriction on changing passwords

ForEach ($user in $users)
{
    Set-ADUser -Identity $user -Clear HomeDirectory,HomeDrive,ScriptPath
    
}

}