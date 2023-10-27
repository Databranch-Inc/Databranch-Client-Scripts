<#
ComputerEase.PS1
This script will start Computer Ease, wait for 2 minutes, then close the Computer Ease Processes. This Script is designed to be run as admin so any ComputerEase Upgrades apply before end users without Admin Rights attempt to run the software.
This script is used on JME-RDP1 via a nightly task in Task Scheduler.
Josh Britton
Origional Date 9-6-2018
Last Edit 7-9-2019
Version 1.1
1.1 - Comment updates
#>

#Start the ComputerEase Appplication
Start-Process -FilePath "C:\LocalComputerEase\mm.exe"

#Wait 2 minutes (this will allow any updates to the application to apply)
Start-Sleep -Seconds 120

#Close ComputerEase processes so that users do not experience issues when attempting to open the app
Stop-Process -Name "mm"
Stop-Process -Name "mmr"