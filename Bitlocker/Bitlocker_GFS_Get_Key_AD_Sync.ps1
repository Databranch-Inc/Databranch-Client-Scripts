<#
Get Bitlocker Key and save to AD

This script will get the recovery keys from a machine, save to a variable and attempt a sync to AD. 

The saved variable will save to a Autoamte EDF.

Josh Britton 
5-6-24

===============================================================================
1.0

Initial write
===============================================================================
#>

#Get Key from System Drive and Save as Variable
#Get the System Drive Letter
$SystemDrive = (Get-WmiObject Win32_OperatingSystem).SystemDrive

# Get the recovery key for system drive
$RecoveryKey = (Get-BitLockerVolume -MountPoint $SystemDrive).KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'} | Select-Object -ExpandProperty RecoveryPassword

$KeyProtectorID = (Get-BitLockerVolume -MountPoint $SystemDrive).KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'} | Select-Object -ExpandProperty KeyProtectorID

#Send Bitlocker Key to AD
Backup-BitLockerKeyProtector -MountPoint $SystemDrive -KeyProtectorId $KeyProtectorID | Out-Null

#Create variable Array for CW Automate
$obj = @{}
$obj.RecoveryKey = $RecoveryKey
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final