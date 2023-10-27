<#
Export GPO Settings
This script exports the GPO settings to enable the Windows Remote Management Service on Computers in a client Domain
Josh Britton
10/4/18
1.0#>

#Import Module for Group Policy
Import-Module GroupPolicy

$Name = "Office 365 - Prevent Bing Default Search"
$Test = Test-Path "C:\Databranch\GPO Backup\$name"
if( $Test -eq "True"){
    Write-host - "GPO Backup folder for $Name found" -ForegroundColor Green
}
else{
    New-Item -Path "C:\Databranch\GPO Backup\$name" -ItemType Directory
    Write-host "GPO Backup folder for $Name was not found. Created folder for $Name" -ForegroundColor Yellow
}

#Export Policy via GPOBackup and set temp variable
$GPOBKP = Backup-GPO -Name "$Name" -Path "C:\Databranch\GPO Backup\$name"

#Set the variable to the folder for the GPO Backup
$GPODIR = $GPOBKP | Select-Object -ExpandProperty BackupDirectory
$TEMPID = $GPOBKP | Select-Object -ExpandProperty Id
$ID = "{" + $TEMPID + "}"

#Set .xml files attributes to unhidden (this needs to happen to allow the import of the GPO into another client enviornment)
Get-Item "$GPODIR\manifest.xml" -Force | Set-ItemProperty -Name Attributes -Value Normal
Get-Item "$GPODIR\$ID\bkupInfo.xml" -Force | Set-ItemProperty -Name Attributes -Value Normal