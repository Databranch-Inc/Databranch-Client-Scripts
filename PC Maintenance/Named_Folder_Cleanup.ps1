<#Named Folder Cleanup

This script reviews and cleans items over a specific date old in a named folder, along with its subfolders.

Origional Creation Date - 10-20-25
Josh Britton
Version 1.0

=============================================================================
Version 1.0

Original Write - forked from C:\Databranch folder cleanup script
============================================================================
#>

#Variable SSet

#Set Date and target date to delete items

Function Start-FolderCleanup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ParentFolder,

        [Parameter(Mandatory = $false)]
        [int]$DaysToCleanup = 30
    )
    

#Set Delete Date for the amount of days to cleanup (defaut 30 Days ago)
$DaysAgo =(Get-Date).AddDays(-"$daystocleanup")
$RemoveDate = Get-Date -Date $DaysAgo -Format "MM/dd/yyyy h:mm:ss tt"


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