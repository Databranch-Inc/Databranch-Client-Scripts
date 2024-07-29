<#
Function - Set Logging

This function is designed to standardized logging across Databranch PowerShell scripts.

Josh Britton
7-23-24

Version 1.0
#>
function Write-Log {
    param (
        [string]$LogPath,
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $Message"
    Add-Content -Path $LogPath -Value $logEntry
}

#Additional Varaible Set
$RunningScript = return split-path $MyInvocation.PSCommandPath -Leaf
$LogPath = "C:\Databranch\$Runningscript.log"