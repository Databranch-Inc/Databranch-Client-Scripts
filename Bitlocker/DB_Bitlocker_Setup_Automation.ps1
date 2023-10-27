<#Databranch Bitlocker Setup Automation

This script runs when the ThirdWall Machine not Encrypted Monitor triggers on a PC 
The script will check for the proper AD Group Membership, push a machine reboot, send the Manage Bitlocker Encryption Commands, and loop while the machine encrypts. 

Josh Britton

3-15-21
========================================================================================================
#>
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
 
    [pscustomobject]@{
        Time = (Get-Date -f g)
        Message = $Message
        Severity = $Severity
    } | Export-Csv -Path "C:\Temp\Bitlocker_Encryption_DB.csv" -Append -NoTypeInformation
 }


#Module import
#Install-Module -Name AD -Force
#Install-Module -Name GroupPolicy -Force


#Variable Set
<#
$SAM = $env:computername +"$"
$DC = Get-ADDomainController | ForEach-Object { $_.Name }
$ADGroup = "Bitlocker Encrypted Machines"
$DomainAdmin = "%computeruserdomain%"
$DomainPW = "%computerpassword%"
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DomainAdmin, $DomainPW
#>

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
    [pscustomobject]$h
}

#Verify AD Group Membership

if(Select-Object -InputObject $h | Where-Object -Property Name -EQ $env:COMPUTERNAME) {
    Write-Log -Message "$env:COMPUTERNAME is in Bitlocker Encrypted Machines AD Group"
    Enable-Bitlocker -MountPoint C: -UsedSpaceOnly -SkipHardwareTest -RecoveryPasswordProtector
    }
    Else{
        Write-Log -Message "$env:COMPUTERNAME is NOT in Bitlocker Encrypted Machines AD Group. Attempting to add to group" -Severity Error
    
    }

<##Test Connection to AD
if (Test-ComputerSecureChannel -Server $DC) {
    Write-Log -Message "PC able to connect to Domain Controller. Testing Group Membership" -Severity Information

    #test group membership
    if(Get-ADGroupMember -Identity $ADGroup | Where-Object { $_.Name -eq $env:COMPUTERNAME}){
        Write-Log -Message "$env:computername is a member of the $ADGroup AD Group. Attempting to update policy and start encryption"
    }

    else{
        Write-Log -Message "$env:computername is NOT a member of the $ADGroup AD Group. Attempting to add to group"
        
        Add-ADGroupMember -Identity $ADGroup -Members $SAM -Credential $Credential
    }
 
Invoke-GPUpdate

Enable-Bitlocker -MountPoint C: -UsedSpaceOnly -SkipHardwareTest -RecoveryPasswordProtector

}
else {
    Write-Log -message "Connection to Domain is BAD" -Severity Error
}#>