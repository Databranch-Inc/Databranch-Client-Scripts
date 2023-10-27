<#
Download Folder Cleanup
This script will check the Download Folder of all the user profiles on a machine, and purge all files older than 1 week.

Josh Britton
5/18/22
1.0#>

#Set users as variables in an array
$Users = Get-ChildItem -Path "C:\Users" | Where-Object Mode -eq "d-----" | Select-Object name -ExpandProperty name


#Variable Set
$FolderDest = "C:\Databranch\Logs"
$Date = get-date
$Days = 7


#Test for Parent folder of log file, and cretae one if it does not exist.
If(Test-Path $FolderDest){
    Write-Host "$FolderDest exists. Checking for Deleted Item Log File." -ForegroundColor Green
}
Else{
    Write-Host "$FolderDest was not found. Creating new folder and log file." -ForegroundColor Yellow
    New-Item -Path $FolderDest -ItemType Directory
}

#Test for log file. Create if not found, and enter line for today's date
If (Test-Path $FolderDest\User_Download_Folder_Deleted_Log.txt)
    {
    Write-Host "$FolderDest\User_Download_Folder_Deleted_Log.txt"-ForegroundColor Green
    Add-Content -path "$FolderDest\User_Download_Folder_Deleted_Log.txt"  -Value "`nScript Started $Date"
    }
Else
    {
    New-Item -ItemType File -Path $FolderDest -Name "User_Download_Folder_Deleted_Log.txt" -Value "Script first run $Date"
    }

#Delete files older than 1 Week, log results
foreach($User in $Users){
    $FolderSource = "C:\Users\"+$user+"\Downloads"
    Get-ChildItem -Path $FolderSource -Recurse -Force -ea 0 | Where-Object {!$_.PsIsContainer -and $_.LastWriteTime -lt $Date.AddDays(-$days)} | ForEach-Object {
        $_ | del -Force
        $_.FullName | Out-File $Folderdest\User_Download_Folder_Deleted_Log.txt -Append
     }
} 

#Delete empty folders and subfolders
foreach ($user in $users){
    $FolderSource = "C:\Users\"+$user+"\Downloads"
    Get-ChildItem $FolderSource -Recurse -Force -ea 0 | Where-Object {$_.PsIsContainer -eq $True} | Where-Object {$_.getfiles().count -eq 0} |
    ForEach-Object {
        $_ | del -Force
        $_.FullName | Out-File $Folder\User_Download_Folder_Deleted_Log.txt -Append
    }
}