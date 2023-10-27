<#
This script gathers Event Log information for the Application and System Event Logs for Error and Critical level events over the past 30 days. It then saves the output into C:\Databranch on the local server.
Josh Britton
8/13/18
1.1
#>

#Set Variables
$Lognames = @("Application" ,"System")
$Date = (Get-Date).AddDays(-30)
$Servers = Import-Csv C:\Databranch\serverAD.csv | Where-Object {$_.enabled -eq "True"} |Select-Object -ExpandProperty Name

#Test for C:\Databranch before continuing

If (Test-Path C:\Databranch)
    {Write-Host "C:\Databranch exists" -ForegroundColor Green
    }
Else
    {New-Item -ItemType Directory -Path C:\ -Name Databranch
    }
#Gather log info for the 2 event logs and save in C:\Databranch

foreach ($Server in $Servers)
    {
    foreach ($Logname in $Lognames)
        {
        Write-Host "Gathering $Logname Event Log on $Server"
        Get-WinEvent -ComputerName $Server -FilterHashtable @{Logname=$Logname;StartTime=$Date} | Where-Object {$_.LevelDisplayName -eq "Error" -or $_.LevelDisplayName -eq "Critical"} | Select-Object -Property LevelDisplayName,Message,Id,TimeCreated |  Export-Csv -Path "C:\Databranch\$Server $Logname Event Log.csv" -Force -NoTypeInformation -Encoding UTF8
        }
    }