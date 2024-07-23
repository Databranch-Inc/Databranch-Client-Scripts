<#
Temporary Process Start

This script is designed to check for and stop a specific processes, call the process to launch, allow time for the app to open run if needed, then re-close the processes to be ready for end users.

This is a more variable centric approach to the ComputerEase method of updating, specifically designed to target force opening a Browser to 

Josh Britton
7-22-24
1.0
=======================================================================================================
1.0 Notes

This script is a fork of a specific script designed for Computer Ease, but including variables that will be set from different ConnectWise scripts. 
========================================================================================================
#>

#Variable Set

#$ProcessName = 
#$ProcessLaunchPath = 


#ProcessCheck and Stop if detected - pre update
$ProcessList = ()

foreach ($Process in $ProcessList)
{
    if(Get-Process -Name $process -ErrorAction SilentlyContinue)
    {
        Stop-Process -Name $Process -Force
    }
    else {
        <# Action when all if and elseif conditions are false #>
        Write-host "$Process is not running on machine, moving to next process or step"
    }
}

#Run ComputerEase client and allow time for client to pull update from server and install if neceeded.
Start-Process -FilePath $ProcessLaunchPath
Start-Sleep -Seconds 120

#ProcessCheck and Stop if detected - post update
$ProcessList = ()

foreach ($Process in $ProcessList)
{
    if(Get-Process -Name $process -ErrorAction SilentlyContinue)
    {
        Stop-Process -Name $Process -Force
    }
    else {
        <# Action when all if and elseif conditions are false #>
        Write-host "$Process is not running on machine, moving to next process or step"
    }
}

Exit