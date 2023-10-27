<#
O365 Set Strong Password Required

This Script is designed to take a list of users and set an O365 attribute to require Strong Passwords for cloud login. This Script is designed to resolve the Liongard Alert - Microsoft 365 | Exposure to Account(s) With Weak Password

Josh Britton  

Initial Script Date - 2-7-22
Last Script Update - 

Version 1.0
=======================================================================================================
1.0

Manually set users and 
========================================================================================================
#>


#Variable Set


#Access O365 Tenant


#Gather Acounts missing strong Password requirement

Get-MsolUser | Where-Object -Property StrongPasswordRequired -eq $false |Select-Object -Property UserPrincipalName

#Force Strong Password Requrement
Set-MsolUser -UserPrincipalName  -StrongPasswordRequired $true