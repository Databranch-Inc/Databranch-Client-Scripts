<#
This script will 

#>

#Connect to EOL
Connect-ExchangeOnline

#Gather user Mailboxes
$mailboxes = Get-EXOMailbox | Select-Object userprincipalname -ExpandProperty userprincipalname

#Loop through Safe Sender Addition

foreach($mailbox in $mailboxes)
    {
    Write-Host "Attempting to add help@databranch.com as a trusted sender on $mailbox" -ForegroundColor Yellow
    Set-MailboxJunkEmailConfiguration $mailbox  -TrustedSendersAndDomains @{Add='help@databranch.com'}
    }