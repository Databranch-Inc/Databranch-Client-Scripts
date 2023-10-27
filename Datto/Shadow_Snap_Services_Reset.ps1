<#Shadow Snap Services Reset
This script will enusre that the needed services for Datto Shadow Snap Agents exist, are set to the poper startup method, and reset them as well as the associated processes.
This is useful for issues capturing backup with these agents. 
Reference KB - https://kb.datto.com/hc/en-us/articles/360020165552-Error-Backup-failed-because-the-agent-was-unable-to-initiate-the-backup-job

NEW KB - https://help.datto.com/s/article/Troubleshooting-ShadowSnap-Backups
Josh Britton
3/11/20
1.0#>

<#Steps:
Stop StorageCraft ImageReady and set to manual startup
Stop StorageCraft Raw Agent, StorageCraft Shadow Copy Provider, and ShadowProtect Services 
Stop following processes:
    raw_agent_svc.exe
    ShadowProtect.exe
    ShadowProtectSvc.exe
    vsnapvss.exe
Restart StorageCraft Raw Agent, StorageCraft Shadow Copy Provider, and ShadowProtect Service
#>

#Variable Set
$services = "StorageCraft Raw Agent","StorageCraft Shadow Copy Provider","ShadowProtect Service"
$processes = "raw_agent_svc","ShadowProtect","ShadowProtect","ShadowProtect"


#Stop StorageCraft ImageReady and set to manual startup
Get-Service "StorageCraft Imageready" | Stop-Service
Set-Service  "StorageCraft Imageready" -StartupType Manual

#Stop processes to ensure services can stop properly
foreach ($process in $processes){
    if (Get-Process -Name $process) -eq $true{
        Stop-Process
        Write-Host "$process has been stopped" -ForegroundColor Green
    }
    else{
        Write-Host "$process is not present on this machine. Trying next process"
    }
}

#Bounce Services
foreach ($service in $services){
    Get-Service $service | Stop-Service
    Start-Sleep 10
    Get-Service $service | Start-Service
    Write-Host "$Service has been restarted on server." -ForegroundColor Green
}