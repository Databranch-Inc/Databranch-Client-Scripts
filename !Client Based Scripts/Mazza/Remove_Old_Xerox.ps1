<#
Remove_Old_Xerox.ps1

This script will remove the old server shared Xerox from a PC during Startup. If the printer is not found, the script will end.

Josh Britton

1/2/2020

1.0
#>

#Test for old printer
$Printertest = get-printer -Name "Xerox WorkCentre 7545 PCL6" -computername MAZZASBS2011 

if ($Printertest -eq $true){
    Remove-Printer -Name "Xerox WorkCentre 7545 PCL6" -computername MAZZASBS2011 
}
else {
    Write-Log "Printer is not installed at this time. Ending Script"
}