#Requires -Modules ExchangeOnlineManagement

<#
.SYNOPSIS
    Searches the Microsoft 365 Unified Audit Log to identify who created a specific
    calendar event on a shared mailbox calendar.

.DESCRIPTION
    Connects to Exchange Online and queries the Unified Audit Log for calendar item
    creation events (Set-Mailbox / Create operations) on a specified shared mailbox.
    Filters by event subject and an optional date range, then returns creator identity,
    timestamps, and client information.

    Audit log retention:
        - Audit Standard (E3):   90 days
        - Audit Standard (E5):   180 days
        - Audit Premium:         1 year (up to 10 years with add-on)

.PARAMETER SharedMailbox
    The UPN or primary SMTP address of the shared mailbox (e.g., vacation@contoso.com).

.PARAMETER EventSubject
    The subject/title of the calendar event to search for. Supports partial matches.

.PARAMETER StartDate
    The start of the audit log search window. Defaults to 90 days ago.

.PARAMETER EndDate
    The end of the audit log search window. Defaults to now.

.PARAMETER ExportPath
    Optional. If specified, exports results to a CSV at this path.

.PARAMETER ResultSize
    Maximum number of raw audit records to retrieve per page. Default is 5000.

.EXAMPLE
    Search-CalendarEventAudit -SharedMailbox "vacation@contoso.com" -EventSubject "Sam Out of Office"

.EXAMPLE
    Search-CalendarEventAudit -SharedMailbox "vacation@contoso.com" -EventSubject "PTO" `
        -StartDate "2025-01-01" -EndDate "2025-03-01" -ExportPath "C:\Temp\audit_results.csv"

.NOTES
    Version History:
        v1.0.1.0 - 2026-03-23 - Fixed null-conditional operator (?.) incompatibility with PowerShell 5.1
                               - Replaced $auditData.Item?.ItemClass / ?.Subject with PS 5.1-safe if/else guards
        v1.0.0.0 - 2026-03-23 - Initial release
                               - UAL search for calendar Create events on shared mailbox
                               - Subject filtering (partial match)
                               - Date range support
                               - CSV export
                               - Auto-connect to Exchange Online if not already connected
                               - Rich output object with UserId, ClientIP, Timestamp, Subject

    Author:      Databranch / Sam Kirsch
    Requires:    ExchangeOnlineManagement module
                 Audit log enabled on tenant (default for E3/E5)
                 Global Admin or Compliance Admin role
#>

function Search-CalendarEventAudit {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, HelpMessage = "UPN or SMTP of the shared mailbox, e.g. vacation@contoso.com")]
        [ValidateNotNullOrEmpty()]
        [string]$SharedMailbox,

        [Parameter(Mandatory, HelpMessage = "Subject/title of the calendar event (partial match supported)")]
        [ValidateNotNullOrEmpty()]
        [string]$EventSubject,

        [Parameter()]
        [datetime]$StartDate = (Get-Date).AddDays(-90),

        [Parameter()]
        [datetime]$EndDate = (Get-Date),

        [Parameter()]
        [string]$ExportPath,

        [Parameter()]
        [ValidateRange(1, 5000)]
        [int]$ResultSize = 5000
    )

    #region --- Version Info ---
    $ScriptVersion = "1.0.1.0"
    $ScriptName    = "Search-CalendarEventAudit"
    #endregion

    #region --- Banner ---
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $ScriptName  v$ScriptVersion" -ForegroundColor Cyan
    Write-Host "  Calendar Event Audit - M365 UAL" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Mailbox  : $SharedMailbox"
    Write-Host "  Subject  : $EventSubject"
    Write-Host "  Range    : $($StartDate.ToString('yyyy-MM-dd')) → $($EndDate.ToString('yyyy-MM-dd'))"
    Write-Host ""
    #endregion

    #region --- Module & Connection Check ---
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Error "ExchangeOnlineManagement module not found. Install with: Install-Module ExchangeOnlineManagement -Scope CurrentUser"
        return
    }

    # Check for active EXO session
    try {
        $null = Get-OrganizationConfig -ErrorAction Stop
        Write-Verbose "Already connected to Exchange Online."
    }
    catch {
        Write-Host "  [~] Connecting to Exchange Online..." -ForegroundColor Yellow
        try {
            Connect-ExchangeOnline -ShowProgress $true -ShowBanner:$false
            Write-Host "  [+] Connected." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to connect to Exchange Online: $_"
            return
        }
    }
    #endregion

    #region --- Audit Log Search ---
    Write-Host "  [~] Searching Unified Audit Log..." -ForegroundColor Yellow
    Write-Host "      This may take a moment for large date ranges." -ForegroundColor DarkGray

    $allRecords  = [System.Collections.Generic.List[object]]::new()
    $sessionId   = [System.Guid]::NewGuid().ToString()
    $pageCommand = 'ReturnLargeSet'
    $pageNumber  = 1

    do {
        try {
            $searchParams = @{
                StartDate    = $StartDate
                EndDate      = $EndDate
                UserIds      = $SharedMailbox
                Operations   = 'Set-Mailbox', 'Create', 'MoveToDeletedItems', 'HardDelete', 'Update'
                ResultSize   = $ResultSize
                SessionId    = $sessionId
                SessionCommand = $pageCommand
                ErrorAction  = 'Stop'
            }

            $results = Search-UnifiedAuditLog @searchParams

            if ($results) {
                $allRecords.AddRange($results)
                Write-Host "      [Page $pageNumber] Retrieved $($results.Count) records..." -ForegroundColor DarkGray
                $pageNumber++
            }
        }
        catch {
            Write-Warning "Audit log search error on page $pageNumber`: $_"
            break
        }
    } while ($results -and $results.Count -eq $ResultSize)

    Write-Host "  [+] Total raw records retrieved: $($allRecords.Count)" -ForegroundColor Green
    #endregion

    #region --- Filter & Parse ---
    Write-Host "  [~] Filtering for calendar Create events matching subject..." -ForegroundColor Yellow

    $findings = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($record in $allRecords) {
        try {
            $auditData = $record.AuditData | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            Write-Verbose "Could not parse AuditData for record: $($record.Identity)"
            continue
        }

        # Only care about calendar item creation
        $operation = $auditData.Operation
        if ($operation -notin @('Create', 'Set-Mailbox')) { continue }

        # Look for calendar item type
        $itemClass = if ($auditData.Item) { $auditData.Item.ItemClass } else { $null }
        if ($itemClass -notlike "IPM.Appointment*") { continue }

        # Subject filter (partial, case-insensitive)
        $subject = if ($auditData.Item) { $auditData.Item.Subject } else { $null }
        if ($subject -notlike "*$EventSubject*") { continue }

        $finding = [PSCustomObject]@{
            CreatedBy         = $auditData.UserId
            CreationTimestamp = $record.CreationDate
            EventSubject      = $subject
            Operation         = $operation
            ClientIP          = $auditData.ClientIPAddress
            ClientApp         = $auditData.ClientInfoString
            Workload          = $auditData.Workload
            MailboxOwner      = $auditData.MailboxOwnerUPN
            RecordId          = $record.Identity
            ResultStatus      = $auditData.ResultStatus
        }

        $findings.Add($finding)
    }
    #endregion

    #region --- Output ---
    Write-Host ""
    if ($findings.Count -eq 0) {
        Write-Host "  [!] No matching calendar creation events found." -ForegroundColor Yellow
        Write-Host "      Suggestions:" -ForegroundColor DarkGray
        Write-Host "        - Expand your date range (event may have been created outside the window)" -ForegroundColor DarkGray
        Write-Host "        - Verify the shared mailbox UPN is correct" -ForegroundColor DarkGray
        Write-Host "        - Confirm mailbox auditing is enabled: Get-Mailbox '$SharedMailbox' | Select AuditEnabled" -ForegroundColor DarkGray
        Write-Host "        - Try a shorter or broader subject keyword" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  [+] Found $($findings.Count) matching event(s):" -ForegroundColor Green
        Write-Host ""
        $findings | Format-Table -AutoSize -Property CreatedBy, CreationTimestamp, EventSubject, ClientIP, ClientApp

        if ($ExportPath) {
            try {
                $findings | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
                Write-Host "  [+] Results exported to: $ExportPath" -ForegroundColor Green
            }
            catch {
                Write-Warning "Export failed: $_"
            }
        }
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Search complete." -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    #endregion

    # Return findings for pipeline use
    return $findings
}
