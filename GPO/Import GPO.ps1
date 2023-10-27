<#
Import GPO Settings
This script imports the GPO settings to enable the Windows Remote Management Service on Computers in a client Domain
Josh Britton
8/13/19
1.1

=====================================================================================================================
1.1 Update

Replaced most hard coded mentions to a GPO with the variable $Name. This will allow for the script to be more modular and able to import other GPOs

Added additional notes for steps of Script
=====================================================================================================================
#>

#Import-modules
Import-Module ActiveDirectory
Import-Module GroupPolicy

#Set Variables
$Name = "Enable WinRM"
$RootDomain = Get-ADDomain | Select-Object -ExpandProperty DistinguishedName

#Import GPO from C:\Databranch\GPO Backup path on local PC
Import-GPO -Path "C:\Databranch\GPO Backup\$Name" -BackupGpoName $Name -TargetName $Name -CreateIfNeeded

#Link GPO to root of Domain, and enable enforcement.
New-GPLink -Name $Name -Target "$RootDomain" -LinkEnabled Yes -Enforced no Ena