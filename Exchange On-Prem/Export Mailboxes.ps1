<#Export Mailboxes
This script exports all of the found mailboxes as .PST files. This allows Datanbranch to complete an Exchange decommission project.

Josh Britton

 9-22-20

1.0
#>

#Get all user mailboxes and set as a variable.
$Mailboxes =  Get-Mailbox | Select-Object Name

#
foreach ($mailbox in $mailboxes){
    New-MailboxExportRequest -Mailbox $mailbox -FilePath "\\ce-fileserv\Public\Exchange On Prem Backup 9-22-20\$mailbox.pst"
}


foreach ($Mailbox in (Get-Mailbox)) { New-MailboxExportRequest -Mailbox $Mailbox -FilePath "\\<server FQDN>\<shared folder name>\$($Mailbox.Alias).pst" }