<#
Delete Old Files
This script will search the folder listed as the $Folder variable and all sub folders, and delete any files older than the number of days set in the $Days Variable. The Script will then delete any sub folders in the location that are completly empty.
=====================================================================================================
Josh Britton
=====================================================================================================
7/24/20
=====================================================================================================
1.0#>

#Variable Set
$Folder = "C:\GMSVP\syslogs"
$Days = 90
$Date = Get-Date


#LogFile Check
If (Test-Path $Folder\deletedlog.txt){
    Add-Content -Path $Folder\deletedlog.txt -Value "Files Deleted on $Date"
    }
else {
    New-Item -ItemType File -Path $folder -Name deletedlog.txt
    Set-Content -Path $Folder\deletedlog.txt -Value "Files Deleted on $Date"
}

#Delete files older than 6 months
Get-ChildItem $Folder -Recurse -Force -ea 0 | Where-Object {!$_.PsIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-$days)} |ForEach-Object {
   $_ | Remove-Item -Force 
   Add-Content -Path $Folder\deletedlog.txt -Value $_.FullName
}

#Delete empty folders and subfolders
Get-ChildItem $Folder -Recurse -Force -ea 0 | Where-Object {$_.PsIsContainer -eq $True} | Where-Object {$_.getfiles().count -eq 0} |
ForEach-Object {
    $_ | Remove-Item -Force 
    Add-Content -Path $Folder\deletedlog.txt -Value $_.FullName
}