<#Disable AD Accounts
This script will disable a list of AD Accounts based of usernames from a .txt file
Josh Britton
10/1/18
1.0#>

$accounts = Get-Content C:\Databranch\Accounts_to_Disable.txt

Import-Module ActiveDirectory

foreach ($account in $accounts){
    Disable-ADAccount -Identity $account
    Write-Host "$Account disabled" -ForegroundColor Green
}