<#
ScreenConnect_File_Delete_Hash.ps1

This script searches user folders for files with a specific MD5 hash and deletes them if found.

Original Author: Josh Britton
Original Date: 7-28-25
Modified by: 
Modified Date:
version: 1.0
=====================================================================
Version 1.0

Original creation
=====================================================================
#>

Function remove-ScreenConnectFile {

    <#
    .SYNOPSIS
    Searches user folders for files with a specific MD5 hash and deletes them if found.

    .DESCRIPTION
    This script iterates through user directories, checks for files with a specific MD5 hash,
    and removes them if they match.

    .PARAMETER None

    .EXAMPLE
    PS> .\ScreenConnect_File_Delete_Hash.ps1

    .NOTES
    #>

#Set Transcription Date for Logging
$TranscriptDate = Get-Date -Format "MM-dd-yyyy_hhmmsstt"

#Create log file
$logfile = New-Item -Path "C:\Databranch\Logs" -Name "ScreenConnect_File_Delete_Hash_$TranscriptDate.txt" -ItemType File -Force | Out-Null

#Find user accounts
$UserFolders = get-childitem -path "C:\users"  -Exclude "Public", "Default", "Default User", "Protected Account", "TEMP", "defaultuser0"  -Directory | Select-Object -ExpandProperty Name

#Search each user folder for Hash equalling a specific value

foreach ($UserFolder in $UserFolders) {

    Get-ChildItem -Path "C:\Users\$UserFolder\AppData\Local\apps\2.0" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $hash = (Get-FileHash $_.FullName -Algorithm MD5).Hash
        if ($hash -eq "9562334DD9A47EC1239A8667DDC1F01C") {
            $filefound = "True"
            Out-File -FilePath $logfile -String "Match found: $($_.FullName)" -Append -Encoding utf8
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}


# Check if any files were found and deleted
if (-not $filefound) {
    $filefound = "False"
    Out-File -FilePath $logfile -String "No files matching hash have been found. Exiting script" -Append -Encoding utf8
}

#Create Array of variables that can be pulled into CW Automate

$obj = @{}
$obj.filefound = $filefound
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final

}