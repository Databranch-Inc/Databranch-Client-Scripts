<#
MFA Enrollment Counts
This Script connects to MSOnline, gathers a list of users and their by user MFA status, and generates a quick report with numbers of users in Enabled, Enforced, and Disabled statuses.
========================================================================================================================================================================================
Josh Britton

8-23-23

1.0
=========================================================================================================================================================================================
#>

#connect to MSOnline

#Gather Table of Users and MFA Per-User Status
$Table = Get-MsolUser -All | Select-Object DisplayName,UserPrincipalName,@{Name = "MFA Status"; E = {if( $_.StrongAuthenticationRequirements.State -ne $null){ $_.StrongAuthenticationRequirements.State} else { "Disabled"}}}


Write-Host "Below is the table of users for this tenant:" -ForegroundColor Green
$Table | Sort-Object -Property DisplayName

#Generate at count of users in each Status
#Enabled/Enforced Users

$EnabledorEnforced = $Table | Where-Object {$_."MFA Status" -ne "Disabled"} | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "There are $EnabledorEnforced users in the tenant with MFA Status of Enabled or Enforced" -ForegroundColor Green

#Disabled
$Disabled = $Table | Where-Object {$_."MFA Status" -eq "Disabled"} | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "There are $Disabled users in the tenant with MFA Status Disabled" -ForegroundColor Red
