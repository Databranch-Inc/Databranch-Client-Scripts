<#
This PC will check an array of GUIDs based on different versions of PC Matic. Once found, it will update 2 registry keys to allow for a silent MSI Uninstall. Once complete, the uninstall command specific to the MSI GUID will run.

The script will then look for the STUNNEL applicaiton, and run a silent uninstall if found


Script is called in the Following RMM Script:
*** JB - Potter County - Remove PC Matic and STunnel applications

Josh Britton
5-3-24
========================================================================================================
1.0

Initial Build

========================================================================================================
#>
function Uninstall-HPWolfSecurity {

#Variable Set
$Keys = @(
    '4968D06D-9600-4AF0-AF8A-B8CE49D8FD44'
    '536168B6-DCAF-41C2-99BC-051C44BC814F'
    '303DF2DA-35A4-11F0-B44B-000C29910851'
)

#Test for version via Regkey and GUID path, update keys when proper version found.

foreach ($key in $keys){

    #64 Bit Installer Path Check

    $Regpath = Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{$key}"

    if ($Regpath -eq $true){

        #Set variables for uninstall
        $uninstall = "msiexec.exe"
        $arguments = "/X{$key} /quiet /norestart"

        #Run Uninstall
        Start-Process $uninstall -Wait -ArgumentList $arguments

    }
    else {
        Write-host "Guid $key does not exist in the 64 bit hive on this machine. Checking next version" -ForegroundColor Yellow
    }
    
    #32 Bit Installer Path Check

    $32Regpath = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{$key}"

    if ($32Regpath -eq $true){

        #Set variables for uninstall
        $uninstall = "msiexec.exe"
        $arguments = "/X{$key} /quiet /norestart"

        #Run Uninstall
        Start-Process $uninstall -Wait -ArgumentList $arguments

    }
    else {
        Write-host "Guid $key does not exist in the 32 bit hive on this machine. Checking next version" -ForegroundColor Yellow
    }

}


#Allow time for uninstall actions to complete before refreshing software list in Automate
Start-Sleep 300

}