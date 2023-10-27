<#Remove Offline File Sync Partnerships

This script is designed to disable offline file sync, copy the cache to a different folder as a a backup, then delete the local cache of synced files. 

This is a good script to run after perfroming a file sever migration, and mapped drives are now potining to a new server.

Josh Britton

11/6/2020

1.0
#>

#Set Variables

#Disable Offline File Sync Services
workflow Disable-offlinefiles {
    
    workflow set-regkeys {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\CSC" -Name "Start" -Value "4"
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\CSCService" -Name "Start" -Value "4"
            
        Restart-Computer -Wait
        }
    Set-regkeys

    New-Item -Path "c:\" -Name "csccopy" -ItemType "directory"
        
    robocopy "c:\windows\csc\v2.0.6\" "c:\csccopy" /mir

    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Csc\Parameters" -Name "FormatDatabase" -Value 1
    Restart-Computer -Wait
}

Disable-offlinefiles