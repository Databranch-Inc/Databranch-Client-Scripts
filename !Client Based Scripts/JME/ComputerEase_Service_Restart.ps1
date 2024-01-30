<#
ComputerEase Service Restart

This script is designed to check for and stop running ComputerEase processes, call the process to launch the CommputerEase Application in an Admin Context, allow time for the app to open and auto update if needed, then re-close the processes to be ready for end users.

This is copied into CW Automate, and is scheduled to run every night in case there is a server side update.

Josh Britton
1-10-24
1.1
=======================================================================================================
1.1 Update

Previously, some parts of this automation were set to run in Connectwise Automate RMM, moving all items to PowerShell. Also adding a loop before and after the client lauch step to look for the processes and stop if needed.
========================================================================================================
#>

#ProcessCheck and Stop if detected - pre update
$ProcessList = ("mm", "mmr")

foreach ($Process in $ProcessList)
{
    ifif(Get-Process -Name $process -ErrorAction SilentlyContinue)
    {
        Stop-Process -Name $Process -Force
    }
    else {
        <# Action when all if and elseif conditions are false #>
        Write-host "$Process is not running on machine, moving to next process or step"
    }
}

#Run ComputerEase client and allow time for client to pull update from server and install if neceeded.
Start-Process -FilePath "C:\LocalComputerEase\mm.exe"
Start-Sleep -Seconds 120

#ProcessCheck and Stop if detected - post update
$ProcessList = ("mm", "mmr")

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