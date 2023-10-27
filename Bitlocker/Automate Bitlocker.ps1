<#Databranch Bitlocker Setup Automation

This script runs when the ThirdWall Machine not Encrypted Monitor triggers on a PC 
The script will check for the proper AD Group Membership, push a machine reboot, send the Manage Bitlocker Encryption Commands, and loop while the machine encrypts. 

Josh Britton

3-15-21
========================================================================================================
#>
$DBLogFolder = "C:\Databranch\Logs"

#Function Import
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
 
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information','Warning','Error')]
        [string]$Severity = 'Information'
    )
    if(Test-Path -Path $DBLogFolder){
    }
    Else{
    New-Item -Path "C:\Databranch" -Name "Logs" -ItemType Directory
    }
 
     [pscustomobject]@{
        Time = (Get-Date -f g)
        Message = $Message
        Severity = $Severity
    } | Export-Csv "$DBLogFolder\Bitlocker_Encryption_DB.log" -NoTypeInformation -Append
 }
 
$Group = [ADSI]"LDAP://CN=Bitlocker Encrypted Machines,OU=Groups,OU=Olean,DC=databranch,DC=com"
$group.member | ForEach-Object {
    [ADSI]$m = "LDAP://$_"
    $props = 'Name'
    $h = [ordered]@{}
    foreach ($item in $props) {
        if ($m.$item -is [System.Collections.CollectionBase]) {
			$h.Add($item,$m.$item.value)
        }
		else {
			$h.Add($item,$m.$item)
        }
 
    }
    #[pscustomobject]$h
}

#Verify AD Group Membership

if(Select-Object -InputObject $h | Where-Object -Property Name -EQ $env:COMPUTERNAME) {
    Write-Log -Message "$env:COMPUTERNAME is in Bitlocker Encrypted Machines AD Group"
    Enable-Bitlocker -MountPoint C: -UsedSpaceOnly -SkipHardwareTest -RecoveryPasswordProtector
}
    Else{
        Write-Log -Message "$env:COMPUTERNAME is NOT in Bitlocker Encrypted Machines AD Group. Attempting to add to group" -Severity Error   
    }
