<#
MFA Enrollment Counts
This Script connects to MSOnline, gathers a list of users and their by user MFA status, and generates a quick report with numbers of users in Enabled, Enforced, and Disabled statuses.
========================================================================================================================================================================================
Josh Britton

8-23-23

1.0

Bmurphy - modified to split enabled and enforced counts from table
=========================================================================================================================================================================================
#>

#connect to MSOnline
Connect-MsolService  

#Gather Table of Users and MFA Per-User Status
$Table = Get-MsolUser -All | Select-Object DisplayName,UserPrincipalName,@{Name = "MFA Status"; E = {if( $_.StrongAuthenticationRequirements.State -ne $null){ $_.StrongAuthenticationRequirements.State} else { "Disabled"}}}


Write-Host "Below is the table of users for this tenant:" -ForegroundColor Green
$Table | Sort-Object -Property DisplayName

#Generate at count of users in each Status
#Enabled/Enforced Users

$Enabled = $Table | Where-Object {$_."MFA Status" -eq "Enabled"} | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "There are $Enabled users in the tenant with MFA Status of Enabled " -ForegroundColor Green

$Enforced = $Table | Where-Object {$_."MFA Status" -eq "Enforced"} | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "There are $Enforced users in the tenant with MFA Status of Enforced" -ForegroundColor Green

#Disabled
$Disabled = $Table | Where-Object {$_."MFA Status" -eq "Disabled"} | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "There are $Disabled users in the tenant with MFA Status Disabled" -ForegroundColor Red
