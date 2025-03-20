<#
#>


function New-SharedMailboxes {
 
# Import CSV file

$Datas = Import-Csv "C:\Databranch\sharedmailboxes.csv"

foreach ($Data in $Datas) {
    # Trim the Name property
    $MailboxName = $Data.Name.Trim()

    # Check if shared mailbox does not exist using -Filter
    $ExistingMailbox = Get-Mailbox -Filter "Name -eq '$MailboxName'" -ResultSize Unlimited -ErrorAction Stop

    if (-not $ExistingMailbox) {
        try {
            # Create shared mailbox
            $null = New-Mailbox -Name $MailboxName -PrimarySmtpAddress $Data.PrimarySMTPAddress -Shared -ErrorAction Stop
            Write-Host "Shared mailbox '$MailboxName' created successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to process mailbox '$MailboxName': $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "Shared Mailbox '$MailboxName' already exists." -ForegroundColor Cyan
    }
}

}