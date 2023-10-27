	
# This is the cmdlet you'll need to edit with your own domain name or email address
 
$ScriptBlock = {get-Mailbox -ResultSize Unlimited | Set-MailboxJunkEmailConfiguration -TrustedSendersAndDomains @{Add='help@gdatabranch.com'}}
 
# Establish a Windows PowerShell session with Office 365. You'll be prompted for your Delegated Admin credentials
 
$Cred = Get-Credential
Import-Module MSOnline
Connect-MsolService
 
$customers= Get-MsolPartnerContract -All
 
Write-Host "Found $($customers.Count) customers for this Partner."
 
# For each of the contracts (customers), run the specified report and output the information.


foreach ($customer in $customers) { 
 
    # Get the initial domain for the customer.
 
    $InitialDomain = Get-MsolDomain -TenantId $customer.TenantId | Where {$_.IsInitial -eq $true}
 
    # Construct the URL with the DelegatedOrg parameter.
 
    $DelegatedOrgURL = "https://ps.outlook.com/powershell-liveid?DelegatedOrg=" + $InitialDomain.Name
 
    Write-Host "Changing setting for $($InitialDomain.Name)"
 
    # Connect to your customers tenant and run the script block
 
    Invoke-Command -ConnectionUri $DelegatedOrgURL -Credential $Cred -Authentication Basic -ConfigurationName Microsoft.Exchange -AllowRedirection -ScriptBlock $ScriptBlock -HideComputerName
 
}
