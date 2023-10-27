# Get the drive letter of the system drive
$SystemDrive = (Get-WmiObject Win32_OperatingSystem).SystemDrive

# Enable BitLocker on the system drive
Enable-BitLocker -MountPoint $SystemDrive -RecoveryPasswordProtector

# Get the recovery key for system drive
$RecoveryKey = (Get-BitLockerVolume -MountPoint $SystemDrive).KeyProtector | Where-Object {$_.KeyProtectorType -eq 'RecoveryPassword'} | Select-Object -ExpandProperty RecoveryPassword

# Output the recovery key
Write-Host "The recovery key is: $RecoveryKey"

$obj = @{}
$obj.RecoveryKey = $RecoveryKey
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final