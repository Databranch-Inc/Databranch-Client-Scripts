<##>

#Import Exchange Online module
Import-Module ExchangeOnlineManagement

# Connect to Partner Center
Connect-ExchangeOnline

#Gather user Mailboxes
$mailboxes = Get-EXOMailbox  -ResultSize Unlimited | Select-Object userprincipalname -ExpandProperty userprincipalname

#Loop through Safe Sender Addition

foreach($mailbox in $mailboxes)
   {
    Write-Host "Attempting to add help@databranch.com as a trusted sender on $mailbox" -ForegroundColor Yellow
    Set-MailboxJunkEmailConfiguration -Identity $mailbox -TrustedSendersAndDomains @{Add='help@databranch.com'}
   }