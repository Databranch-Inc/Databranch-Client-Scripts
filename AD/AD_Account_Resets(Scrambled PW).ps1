<#
=====================================================================================================
AD_Account_Resets(Scrambled PW)
This script will gather user accounts from AD, reset the passwords, and force a password change at next logon. Changed passwords will then write to a .CSV file for reference.
Josh Britton
9/22/23
1.1
======================================================================================================
1.1

Updated special characters that can be used in scrambling function. Also updated the output object that exports to the final .CSV file
JB 9-22-23
======================================================================================================
#>

#Module Import
Import-Module ActiveDirectory

#Variable set
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
$Date = Get-Date -UFormat %D
$Date = $Date -replace "/","-"

#Import Functions
function Get-RandomCharacters($length, $characters) {
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length }
    $private:ofs=""
    return [String]$characters[$random]
}
 
function Scramble-String([string]$inputString){     
    $characterArray = $inputString.ToCharArray()   
    $scrambledStringArray = $characterArray | Get-Random -Count $characterArray.Length     
    $outputString = -join $scrambledStringArray
    return $outputString 
}
 
#Run a special AD user export to .CSV to only gather enabled non-admin and non-service accounts
GET-ADUSER -filter * -properties * | Where-Object {($_.Admincount -ne "1") -and ($_.enabled -eq "True") -and ($_.SAMAccountname -notlike "*floor*") -and ($_.SAMAccountname -notlike "*iqs*")  -and ($_.SAMAccountname -notlike "*MSOL*") -and ($_.SAMAccountname -notlike "*AAD*")} | select-object name,SAMAccountname,lastlogondate,enabled,primarygroup | Export-Csv "$Dir\userstoresetAD.csv" -NoTypeInformation -Encoding UTF8

#Get the users AD .csv file 
$users = Import-Csv "$dir\userstoresetAD.csv" | Select-Object -ExpandProperty SAMAccountname

#Set each user with the following - set random password, force a password change at next login and remove the restriction on changing passwords

ForEach ($user in $users)
{
    Set-ADUser -Identity $user -CannotChangePassword $false

    $password = Get-RandomCharacters -length 5 -characters 'abcdefghiklmnoprstuvwxyz'
    $password += Get-RandomCharacters -length 1 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
    $password += Get-RandomCharacters -length 1 -characters '1234567890'
    $password += Get-RandomCharacters -length 1 -characters '!"%&/()=?}][{@#*+'     
    $password = Scramble-String $password

    Set-ADAccountPassword -Identity $user -NewPassword (ConvertTo-SecureString -AsPlainText $password -Force)
    Set-ADUser -Identity $user -ChangePasswordAtLogon $True

#Export username and temp password to new .CSV file

    $NewPW = New-Object -TypeName psobject
    $NewPW | Add-Member -MemberType NoteProperty -Name Username -Value $user
    $NewPW | Add-Member -MemberType NoteProperty -Name Password -Value $password
    $NewPW | Export-Csv -Path $dir\ChangedPasswords$Date.csv -NoTypeInformation -Encoding UTF8 -Append
}