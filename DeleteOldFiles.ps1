<#
Delete Old Files
This script will enusre that the needed services for Datto Shadow Snap Agents exist, are set to the poper startup method, and reset them as well as the associated processes.
Josh Britton
7/24/20
1.0#>

$Folder = "C:\users\jbritton\Downloads"
$Days = 90


#Delete files older than 3 months
Get-ChildItem $Folder -Recurse -Force -ea 0 | Where-Object {!$_.PsIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-$days)} |ForEach-Object {
   $_ | del -Force
   $_.FullName | Out-File $Folder\deletedlog.txt -Append
}

#Delete empty folders and subfolders
Get-ChildItem $Folder -Recurse -Force -ea 0 | Where-Object {$_.PsIsContainer -eq $True} | Where-Object {$_.getfiles().count -eq 0} |
ForEach-Object {
    $_ | Remove-Item -Force
    $_.FullName | Out-File $Folder\deletedlog.txt -Append
}