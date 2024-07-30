<#
Get Bitlocker Key and save to EDF

This script will get the recovery keys from a machine, save to a variable and prep for Autoamat attempt a sync to AD. 

The saved variable will save to a Autoamte EDF.

1.1

Josh Britton 
7-30-24
===============================================================================
1.1

Removing AD push to focus capturing key to RMM EDF - JB 7-30-24
===============================================================================
1.0

Initial write
===============================================================================
#>
Function Set-BitlockerEDF{
#Get Key from System Drive and Save as Variable

#Get the System Drive Letter
$SystemDrive = (Get-WmiObject Win32_OperatingSystem).SystemDrive

#Check for encryption on the System Drive
$DriveEncrpytionStatus = (Get-BitLockerVolume -MountPoint $SystemDrive).VolumeStatus

If ($DriveEncrpytionStatus -eq "FullyDecrypted"){

    $DriveEncrpytionStatus    
}

else {
    
    #Test for a Recovery Key, add if not found

    #Get the recovery key for system drive
    $RecoveryKey = (Get-BitLockerVolume -MountPoint $SystemDrive).KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'} | Select-Object -ExpandProperty RecoveryPassword

    if ($RecoveryKey -ne $null){

        #Get the Key Protector ID for matching the recovery key

        $KeyProtectorID = (Get-BitLockerVolume -MountPoint $SystemDrive).KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'} | Select-Object -ExpandProperty KeyProtectorID

    }
    Else{
        #Add Recovery Key
        Add-BitLockerKeyProtector -MountPoint $SystemDrive -RecoveryKeyProtector

        #Gather Recovery Key and KeyProtecor ID
        $RecoveryKey = (Get-BitLockerVolume -MountPoint $SystemDrive).KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'} | Select-Object -ExpandProperty RecoveryPassword

        $KeyProtectorID = (Get-BitLockerVolume -MountPoint $SystemDrive).KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'} | Select-Object -ExpandProperty KeyProtectorID
    }
}

#Create variable Array for CW Automate
$obj = @{}
$obj.DriveEncrpytionStatus = $DriveEncrpytionStatus
$obj.RecoveryKey = $RecoveryKey
$obj.KeyProtectorID = $KeyProtectorID
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final
}