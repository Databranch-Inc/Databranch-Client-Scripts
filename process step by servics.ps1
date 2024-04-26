<#Automate Restart hung process tied to Service

This script will find the associated process to a hung service and force it stop, allowing a hung service to resetart.

Josh Britton 

Last Update 2-5-24
1.0
#>


#Variable Set

$Service = @service@
$ProcessExe = Get-Service -Name $Service | Select-Object -ExpandProperty BinaryPathName
$Processes = get-process | Where-Object {$_.CommandLine -eq $processexe}

#Stop all Processes related to service

Foreach ($process in $Processes){

Stop-Process -Name $process -Force

}

#Restart Service

Start-Service -Name $Service