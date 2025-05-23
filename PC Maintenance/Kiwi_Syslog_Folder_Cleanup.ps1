<#Databranch Folder Cleanup

This script reviews and cleans items over 6 months old in the D:\Kiwi Syslog, along with its subfolders.

Origional Creation Date - 5-19-25
Josh Britton

Version 1.0
=========================================================================================================
Version 1.0

Origional Write. Copy from Databranch Folder Cleanup Script and update to 180 day check
#>

#Variable Set


Function Cleanup-FolderKiwiSyslog{

#Set Delete Date for 30 Days ago
$180DaysAgo =(Get-Date).AddDays(-180)
$RemoveDate = Get-Date -Date $180DaysAgo -Format "MM/dd/yyyy h:mm:ss tt"


#Set Transcription Date for Logging
$TranscriptDate = Get-Date -Format "MM-dd-yyyy_hhmmsstt"

#Parent Folder
$ParentFolder = "D:\Kiwi Syslog"

#Start Transcript for Cleanup Actions:
Start-Transcript -Path "C:\Databranch\Logs\Kiwi_Syslog_Folder_Cleanup_Script_Logs_$TranscriptDate.txt" -NoClobber
$Transcript = "C:\Databranch\Logs\Kiwi_Syslog_Folder_Cleanup_Script_Logs_$TranscriptDate.txt"


$OldFiles = Get-ChildItem -Path $ParentFolder -Attributes A -Recurse | Where-Object -Property LastWriteTime -LT $RemoveDate | Select-Object -ExpandProperty FullName

foreach ($OldFile in $OldFiles){
    Remove-Item -Path $OldFile -Force
    Write-Host "$OldFile removed"
}

$EmptyFolders = Get-ChildItem -Path $ParentFolder -Directory | Where-Object { $_.GetFileSystemInfos().Count -eq 0 -and $_.Name -ne "Logs"} | Select-Object -ExpandProperty FullName

Foreach ($EmptyFolder in $EmptyFolders){

    Remove-Item -path $EmptyFolder -Force
    Write-Host $EmptyFolder removed
}

#Stop Transcript of File Delete Actions
Stop-Transcript

#Create Array of variables that can be pulled into CW Automate

$obj = @{}
$obj.transcript = $Transcript
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final

}