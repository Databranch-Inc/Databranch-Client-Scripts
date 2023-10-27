<#
This script checks the E:/Reordings folder to ensure the daily recording folder has been created. If the folder is not found, This script will hand off to the Vivoteck Service Restart Script.

Josh Britton 5-12-23 
==============================================================================================================================================
v1.0

Initial version
===============================================================================================================================================
#>

#Variable Set

$Date = Get-Date -Format "yyyy-MM-dd"
$Source = "E:\Recordings"

#Check SubFolders in Recordings folder for matching Date

#Create Array
$FolderArray = @(Get-ChildItem -Path $Source | Select-Object -ExpandProperty name)

#Search Array of folder names for match with Date, capture a variable for Output to Automate
if ($FolderArray.Contains($date)){

    $testresult = "True"
}

else {
    $testresult = "False"
}

#Create Array of varabiles that can be pulled into CW Automate

$obj = @{}
$obj.TestResult = $testresult
$obj.Date = $Date
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final