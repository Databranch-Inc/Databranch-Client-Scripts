<#
This script gathers Event Log information for the Application and System Event Logs for Error and Critical level events over the past 30 days. It then saves the output into C:\Databranch on the local server.
Josh Britton
6/26/19
1.2 Update - Clearing out .csv files in C:\Databranch, extending script time to 31 days, and adding user facing notifications for creating new C:\Databranch folder
1.1
#>

#Set Variables
$Lognames = @("Application" ,"System")
$Date = (Get-Date).AddDays(-31)
$Servers = Import-Csv C:\Databranch\serverAD.csv | Where-Object {$_.enabled -eq "True"} |Select-Object -ExpandProperty Name

#Test for C:\Databranch before continuing

If (Test-Path C:\Databranch)
    {
    Write-Host "C:\Databranch exists" -ForegroundColor Green
    
    foreach ($Server in $Servers)
    {    
        foreach ($Logname in $Lognames)
        {
         Write-Host "Removing old $Server $Logname Event Log.csv file." -ForegroundColor Green
         Remove-Item -path "C:\Databranch\$Server $Logname Event Log.csv"
         Write-Host "Gathering $Logname Event Log on $Server"
         Get-WinEvent -ComputerName $Server -FilterHashtable @{Logname=$Logname;StartTime=$Date} | Where-Object {$_.LevelDisplayName -eq "Error" -or $_.LevelDisplayName -eq "Critical"} | Select-Object -Property LevelDisplayName,Message,Id,TimeCreated |  Export-Csv -Path "C:\Databranch\$Server $Logname Event Log.csv" -Force -NoTypeInformation -Encoding UTF8
        }
    }

    }
Else
    {Write-Host "C:\Databranch does not exist. Creating folder at this time" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path C:\ -Name Databranch
    Write-Host "C:\Databranch folder created. Please run inventory script to gather active servers, then run this script again" -ForegroundColor Yellow
    Start-Sleep 15
    }