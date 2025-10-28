<#Registy Key Check Function

This PowerShell script defines a function to check for the existence of a specified registry key.

The Key is set as a parameter to the function and will be supplied via a CW Autoamte Variable.

Script generated with ChatGPT Assistance

Script Creation Date: 10-28-25
Last Modified Date: 10-28-25
Current Version: 1.0
Original Author: ChatGPT and Josh Britton
===============================================================
1.0 - Initial version created with ChatGPT assistance

===============================================================
#>

<#
.SYNOPSIS
Checks if a specified registry key exists at the given path.

.DESCRIPTION
The `Test-RegistryKeyExistence` function accepts a registry key path as input and determines whether the registry key exists at the specified location. 
It outputs a message indicating whether the registry key exists or not.

.PARAMETER RegistryKeyPath
The full path of the registry key to check. This parameter is mandatory.

.EXAMPLE
Test-RegistryKeyExistence -RegistryKeyPath "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion"

This example checks if the registry key exists at the specified path under HKEY_LOCAL_MACHINE.

.NOTES
- The function uses the `Test-Path` cmdlet to verify the existence of the registry key.
- The registry path should be provided in the format understood by PowerShell, e.g., "HKEY_LOCAL_MACHINE\SOFTWARE\..."
- If an error occurs during the check, an error message will be displayed.
#>
function Test-RegistryKeyExistence {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RegistryKeyPath
    )

    try {
        if (Test-Path "Registry::$RegistryKeyPath") {
            Write-Output "Registry key exists at path: $RegistryKeyPath"
        } else {
            Write-Output "Registry key does not exist at path: $RegistryKeyPath"
        }
    } catch {
        Write-Error "An error occurred while checking the registry key: $_"
    }
}