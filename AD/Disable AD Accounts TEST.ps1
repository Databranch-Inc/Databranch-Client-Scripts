<#Disable AD Accounts
This script will disable a list of AD Accounts based of usernames from a .txt file
Josh Britton
10/1/18
1.0#>

#Input Function to create a log file - this can be added to by using Write-Log
Function Write-Log {
    [CmdletBinding()]
    Param(
    [Parameter(Mandatory=$False)]
    [ValidateSet("INFO","WARN","ERROR","FATAL","DEBUG")]
    [String]
    $Level = "INFO",

    [Parameter(Mandatory=$True)]
    [string]
    $Message,

    [Parameter(Mandatory=$False)]
    [string]
    $logfile
    )

    $Stamp = (Get-Date).toString("yyyy/MM/dd HH:mm:ss")
    $Line = "$Stamp $Level $Message"
    If($logfile) {
        Add-Content $logfile -Value $Line
    }
    Else {
        Write-Output $Line
    }
}

#Get user accounts to disable
$accounts = Get-Content C:\Databranch\Accounts_to_Disable.txt

Import-Module ActiveDirectory

#Loop and disable the noted account, write to log file
foreach ($account in $accounts){
    Disable-ADAccount -Identity $account
    
}