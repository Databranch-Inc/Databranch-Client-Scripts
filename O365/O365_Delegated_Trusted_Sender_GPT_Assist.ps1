<##>

#Import Partner Center module
Import-Module PartnerCenter

# Connect to Partner Center
Connect-PartnerCenter

# Get list of customer tenants
$customerTenants = Get-PartnerCustomer

# Loop through each tenant and run PowerShell command
foreach ($tenant in $customerTenants) {
    $customerContext = Connect-AzureAD -TenantId $tenant.DefaultDomainName
    # Run your PowerShell command here

    #Gather user Mailboxes
    $mailboxes = Get-EXOMailbox  -ResultSize Unlimited | Select-Object userprincipalname -ExpandProperty userprincipalname

    #Loop through Safe Sender Addition

    foreach($mailbox in $mailboxes)
        {
        Write-Host "Attempting to add help@databranch.com as a trusted sender on $mailbox" -ForegroundColor Yellow
        Set-MailboxJunkEmailConfiguration -TrustedSendersAndDomains @{Add='help@gdatabranch.com'}
        }

  Disconnect-MsolService -Session $customerContext
}