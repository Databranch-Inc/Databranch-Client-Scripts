<#
Get SAM Account Names from Local Exchange 
Josh Britton
2/19/19
Version 1.0
From https://support.skykick.com/hc/en-us/articles/115004538114-SAM-Account-Name-CSV-Upload
#>

import-module activedirectory
$filepath=[Environment]::GetFolderPath("Desktop") + "\SAMAccountNames.csv"
$a=@{Expression={$_.EmailAddress};Label="SourceEmailAddress"}, `
@{Expression={$_.SamAccountName};Label="SourceSAMAccountName"}
get-aduser –filter * -properties * | where-object {$_.EmailAddress -ne $null -and $_.EmailAddress -NotLike "*.local" -and $_.Enabled -eq $True -and $_.msExchWhenMailboxCreated -ne $null -and $_.msExchHideFromAddressLists -ne $true} | select $a | export-csv -path $filepath –notypeinformation