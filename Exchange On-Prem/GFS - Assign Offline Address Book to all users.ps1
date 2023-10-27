<#
GFS - Assign Offline Address Book to all users

This script is set to manually set the OAB_2022 offline address book to all the user mailboxes for GFS

Created Date 2-21-22
Josh Britton

1.0
#>

#Import Modules
Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn

#Variable Set
$AddressBook = "OAB_2022"

#Gather list of all user based mailboxes
$mbxs = Get-Mailbox | where-Object OfflineAddressBook -eq $null | select-object -expandproperty name

#Set the OAB_2022 Address book to each mailbox

foreach ($mbx in $mbxs){
    Set-Mailbox -Identity $mbx -OfflineAddressBook $AddressBook
}