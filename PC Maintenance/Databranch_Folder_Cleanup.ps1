<#Databranch Folder Cleanup

This script reviews and cleans items over a month old in the C:\Databranch folder, along with its subfolders.

Origional Creation Date - 11-11-24
Josh Britton

Version 1.0
=========================================================================================================
Version 1.0

Origional Write
#>

#Variable SSet

#Set Date and target date to delete items

Function Cleanup-FolderDatabranch{

#Current Date set to format to match Get-Childitem output
$CurrentDate = get-date -Format "MM/dd/yyyy h:mm tt"

#Set Delete Date for 30 Days ago
$30DaysAgo =(Get-Date).AddDays(-30)
$RemoveDate = Get-Date -Date $30DaysAgo -Format "MM/dd/yyyy h:mm:ss tt"


#Set Transcription Date for Logging
$TranscriptDate = Get-Date -Format "MM-dd-yyyy_hhmmsstt"

#Parent Folder
$ParentFolder = "C:\Databranch"

#Start Transcript for Cleanup Actions:
Start-Transcript -Path "C:\Databranch\Logs\Databranch_Folder_Cleanup_Script_Logs_$TranscriptDate.txt" -NoClobber
$Transcript = "C:\Databranch\Logs\Databranch_Folder_Cleanup_Script_Logs_$TranscriptDate.txt"

$OldFiles = Get-ChildItem -Path $ParentFolder -Attributes A -Recurse | Where-Object -Property LastWriteTime -LT $RemoveDate | Select-Object -ExpandProperty FullName

foreach ($OldFile in $OldFiles){
    Remove-Item -Path $OldFile -Force
    Write-Host "$OldFile removed"
}

$EmptyFolders = Get-ChildItem -Path $ParentFolder -Directory | Where-Object { $_.GetFileSystemInfos().Count -eq 0 -and $_.Name -ne "Logs"}

Foreach ($EmptyFolder in $EmptyFolders){

    Remove-Item -path $EmptyFolder -Force
    Write-Host $EmptyFolder removed
}

#Stop Transcript of File Delete Actions
Stop-Transcript

}