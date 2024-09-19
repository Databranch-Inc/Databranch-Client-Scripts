<#
Function - Set Logging

This function is designed to standardized logging across Databranch PowerShell scripts.

Josh Britton
7-23-24

Version 1.0
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message,
        [Parameter(Mandatory = $false)]
        [string] $LogFilePath = "C:\Databranch\Logs\$($MyInvocation.MyCommand).log"
    )

    # Create the log file if it doesn't exist
    if (!(Test-Path $LogFilePath)) {
        New-Item -Path $LogFilePath -ItemType File -Force
    }

    # Get the current date and time
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Write the message to the log file
    Add-Content -Path $LogFilePath -Value "$timestamp - $Message"
}
<#function Write-Log {
    param (
        [string]$LogPath,
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $Message"
    Add-Content -Path $LogPath -Value $logEntry
}

#Additional Varaible Set
$RunningScript = $MyInvocation.ScriptName
#$RunningScript = return split-path $MyInvocation.PSCommandPath -Leaf
#$LogPath = "C:\Databranch\$Runningscript.log"


$RunningScript

Start-sleep  #> 