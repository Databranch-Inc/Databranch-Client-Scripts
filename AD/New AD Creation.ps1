<#
=======================================================================================================
New AD Creation
This script will take create new OUs in the root level OU, then will create sub OUs for client accounts, service account, and computers. Then, data from .csv files will be used to create users and service accounts. 


This script will then take the created passwords and output them to a file for first logon.

Josh Britton

Last  update - 11-26-19

Version 1.0

Future Notes - Add user checks, description fields, service account information
====================================================================================================#>

#Import AD Module
Import-Module ActiveDirectory

#Variable set
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
$domain = Get-ADDomain | Select-Object -Property DistinguishedName | ForEach-Object {$_.distinguishedname}
$CompanyName = Read-Host "What is the name of the compuany root OU? This is the field Databranch uses to create AD objects"     



#Create new Company level OU
New-ADOrganizationalUnit -Name $CompanyName -Path $domain

#Build new sub-OUs under company OU

$New_User_OU = "OU=User Accounts,"+"OU=$CompanyName"+","+"$domain"
$New_Service_Acct_OU = "OU=Service Accounts,"+"OU=$CompanyName"+","+"$domain"
#$Service_Account_List = Import-Csv $dir\New_AD_Service_Accounts.csv


#Convert DC Domain from $domain to @domain.com address for UserPrincipalName
$step1 = $domain -replace "DC=", "@"
$UserPrincipalName = $step1 -replace ",@", "."

#Create user accounts from AD List
Import-Csv $dir\New_AD_Users.csv|foreach{
    $Name = $_.firstname + " " + $_.lastname
    $GivenName = $_.firstname
    $SurName = $_.lastname
    $UserName = $_.username
    $Password = $_.password

    New-ADUser -Name $Name -GivenName $GivenName -Surname $SurName -DisplayName $Name -SamAccountName $UserName -UserPrincipalName $UserName$UserPrincipalName -Path $New_User_OU -AccountPassword (convertto-securestring $Password -AsPlainText -Force) -ChangePasswordAtLogon $true -Enabled $true
    }
