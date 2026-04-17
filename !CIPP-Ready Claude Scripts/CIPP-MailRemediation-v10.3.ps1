#Requires -Version 7.0
<#
.SYNOPSIS
    CIPP v10.3.0 Native Custom Script - Malicious Email Remediation
    Paste this into CIPP UI: Tools > Custom Scripts > Add Script

.DESCRIPTION
    Uses CIPP's native New-GraphGetRequest / New-GraphPostRequest helpers,
    which handle per-tenant token acquisition automatically via CIPP's SAM
    infrastructure. No credentials, no App Registrations, no file deployment.

    Supports three modes:
      ReportOnly  - Finds and logs matching messages. No changes made. DEFAULT.
      SoftDelete  - Moves matched messages to Deleted Items (recoverable ~30d).
      HardDelete  - Permanently deletes via Graph permanentDelete API.

    At least one search parameter must be provided:
      $SearchSubject   - Partial subject match (contains)
      $SearchSender    - Exact sender address match
      $SearchMessageId - Exact Internet Message-ID header match

    $TenantFilter is automatically provided by CIPP when the script is run
    via the Scheduler or Custom Scripts UI. Set to 'AllTenants' in the UI
    to run across every managed tenant.

.PARAMETER TenantFilter
    Injected by CIPP. Tenant domain, ID, or 'AllTenants'.

.PARAMETER SearchSubject
    Partial subject keyword. Case-insensitive contains match.

.PARAMETER SearchSender
    Exact sender email address to match.

.PARAMETER SearchMessageId
    Internet Message-ID header value to match exactly.

.PARAMETER RemediationMode
    ReportOnly (default) | SoftDelete | HardDelete

.PARAMETER MaxMailboxes
    Safety cap on mailboxes per tenant. Default 5000.

.NOTES
    Version    : 1.0.0.001
    CIPP Target: v10.3.0+ (The Fishbowl) - Custom Scripts feature
    Auth       : CIPP SAM via New-GraphGetRequest / New-GraphPostRequest
    Requires   : Mail.ReadWrite + User.Read.All (Application) on CIPP SAM app

    DEPLOYMENT
    ----------
    1. CIPP UI > Tools > Custom Scripts > Add Script
    2. Paste this entire script into the editor
    3. Save and use Enable/Disable toggle to activate
    4. Run via: Manual Run (immediate) or Scheduler (scheduled/recurring)
    5. In the run dialog, select tenant and set Parameters as needed

    SCHEDULER USAGE
    ---------------
    Tools > Scheduler > Add Task
      Command    : [Your Custom Script Name]
      Tenant     : All Tenants OR specific tenant
      Parameters : (Advanced JSON mode)
        {
          "SearchSubject"   : "Urgent Invoice",
          "SearchSender"    : "phisher@evil.com",
          "SearchMessageId" : "",
          "RemediationMode" : "ReportOnly",
          "MaxMailboxes"    : 5000
        }

    RECOMMENDED INCIDENT RESPONSE WORKFLOW
    ---------------------------------------
    Step 1: Run with RemediationMode = ReportOnly   - validate matches
    Step 2: Run with RemediationMode = SoftDelete   - recoverable removal
    Step 3: Run with RemediationMode = HardDelete   - only if required

    VERSION HISTORY
    ---------------
    1.0.0.001 - Initial release for CIPP v10.3.0+
                - CIPP-native New-GraphGetRequest / New-GraphPostRequest auth
                - Write-LogMessage for CIPP log pipeline integration
                - $TenantFilter convention for CIPP tenant targeting
                - Paged mailbox enumeration via CIPP Graph helpers
                - OData filter: Subject (contains) / Sender (eq) / MessageId (eq)
                  combined with OR - any match triggers action
                - ReportOnly / SoftDelete / HardDelete modes
                - Per-mailbox error isolation
                - Grand summary returned as structured output
#>

param(
    # CIPP injects TenantFilter automatically - do not remove
    [string]$TenantFilter    = 'AllTenants',

    # Search criteria - at least one required
    [string]$SearchSubject   = '',
    [string]$SearchSender    = '',
    [string]$SearchMessageId = '',

    # Remediation behavior
    [ValidateSet('ReportOnly', 'SoftDelete', 'HardDelete')]
    [string]$RemediationMode = 'ReportOnly',

    [int]$MaxMailboxes       = 5000
)

# =============================================================================
# SCRIPT METADATA
# =============================================================================
$ScriptVersion = '1.0.0.001'
$ScriptName    = 'CIPP-MailRemediation'

# =============================================================================
# INPUT VALIDATION
# =============================================================================
if (-not $SearchSubject -and -not $SearchSender -and -not $SearchMessageId) {
    throw 'At least one search criterion must be provided: SearchSubject, SearchSender, or SearchMessageId.'
}

Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Starting v$ScriptVersion | Mode: $RemediationMode | Subject: '$SearchSubject' | Sender: '$SearchSender' | MsgId: '$SearchMessageId'" -Sev Info

if ($RemediationMode -eq 'HardDelete') {
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'WARNING: HardDelete mode - matched messages will be PERMANENTLY deleted.' -Sev Warn
}

# =============================================================================
# HELPER: Build OData $filter string
# =============================================================================
function Build-MailFilter {
    param(
        [string]$Subject,
        [string]$Sender,
        [string]$MessageId
    )
    $clauses = [System.Collections.Generic.List[string]]::new()

    if ($Subject) {
        $escaped = $Subject.Replace("'", "''")
        $clauses.Add("contains(subject,'$escaped')")
    }
    if ($Sender) {
        $escaped = $Sender.Replace("'", "''")
        $clauses.Add("from/emailAddress/address eq '$escaped'")
    }
    if ($MessageId) {
        $mid = $MessageId.Trim().Trim('<', '>')
        $mid = $mid.Replace("'", "''")
        $clauses.Add("internetMessageId eq '<$mid>'")
    }

    return ($clauses -join ' or ')
}

$ODataFilter = Build-MailFilter -Subject $SearchSubject -Sender $SearchSender -MessageId $SearchMessageId
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "OData filter: $ODataFilter" -Sev Info

# =============================================================================
# HELPER: Enumerate all pages from a Graph list endpoint via CIPP helpers
# Wraps New-GraphGetRequest in a paging loop
# =============================================================================
function Get-GraphAllPages {
    param(
        [string]$Uri,
        [string]$Tenant
    )
    $results  = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri

    do {
        $page = New-GraphGetRequest -uri $nextLink -tenantid $Tenant -ErrorAction Stop
        if ($page) { $results.AddRange([object[]]@($page)) }
        # New-GraphGetRequest returns the .value array directly and handles
        # nextLink internally in newer CIPP versions. If not, handle manually:
        $nextLink = $null
    } while ($nextLink)

    return $results
}

# =============================================================================
# MAIN: Enumerate mailboxes and search / remediate
# =============================================================================
$totalMailboxes = 0
$totalFound     = 0
$totalDeleted   = 0
$totalErrors    = 0

Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'Enumerating mailbox users...' -Sev Info

try {
    # New-GraphGetRequest handles paging and per-tenant auth automatically.
    # $TenantFilter is passed as-is; CIPP resolves AllTenants internally
    # when the script is triggered via the Custom Scripts / Scheduler engine.
    $users = New-GraphGetRequest `
        -uri      "https://graph.microsoft.com/v1.0/users?`$select=id,userPrincipalName,displayName,mail&`$filter=accountEnabled eq true&`$top=999" `
        -tenantid $TenantFilter `
        -ErrorAction Stop
}
catch {
    $errMsg = "Failed to enumerate users for tenant '$TenantFilter': $_"
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message $errMsg -Sev Error
    throw $errMsg
}

if (-not $users -or @($users).Count -eq 0) {
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'No mailbox users found. Verify User.Read.All permission on CIPP SAM app.' -Sev Warn
    return
}

# Filter to users with a mailbox
$mailboxUsers = @($users) | Where-Object { $_.mail -or ($_.userPrincipalName -like '*@*') }

if ($mailboxUsers.Count -gt $MaxMailboxes) {
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Mailbox count ($($mailboxUsers.Count)) exceeds MaxMailboxes cap ($MaxMailboxes). Truncating." -Sev Warn
    $mailboxUsers = $mailboxUsers | Select-Object -First $MaxMailboxes
}

Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Processing $($mailboxUsers.Count) mailbox(es)." -Sev Info

$encodedFilter = [Uri]::EscapeDataString($ODataFilter)
$mbxIndex      = 0

foreach ($user in $mailboxUsers) {
    $mbxIndex++
    $upn = if ($user.userPrincipalName) { $user.userPrincipalName } else { $user.mail }
    $totalMailboxes++

    # Search this mailbox
    try {
        $messages = New-GraphGetRequest `
            -uri      "https://graph.microsoft.com/v1.0/users/$($user.id)/messages?`$filter=$encodedFilter&`$select=id,subject,from,receivedDateTime,internetMessageId&`$top=50" `
            -tenantid $TenantFilter `
            -ErrorAction Stop
    }
    catch {
        Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "[$mbxIndex/$($mailboxUsers.Count)] Search failed for $upn : $_" -Sev Warn
        $totalErrors++
        continue
    }

    if (-not $messages -or @($messages).Count -eq 0) { continue }

    $msgList = @($messages)
    $totalFound += $msgList.Count

    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "[$mbxIndex/$($mailboxUsers.Count)] MATCH: $($msgList.Count) message(s) in $upn" -Sev Warn

    foreach ($msg in $msgList) {
        $subjectDisplay = if ($msg.subject) { $msg.subject } else { '(no subject)' }
        $senderDisplay  = $msg.from.emailAddress.address
        $rcvd           = $msg.receivedDateTime

        # --- ReportOnly: log and skip ---
        if ($RemediationMode -eq 'ReportOnly') {
            Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "[REPORT] Mailbox: $upn | Subject: '$subjectDisplay' | From: $senderDisplay | Received: $rcvd" -Sev Info
            continue
        }

        # --- Delete ---
        try {
            if ($RemediationMode -eq 'HardDelete') {
                # permanentDelete is a POST action with no body
                $null = New-GraphPostRequest `
                    -uri      "https://graph.microsoft.com/v1.0/users/$($user.id)/messages/$($msg.id)/permanentDelete" `
                    -tenantid $TenantFilter `
                    -body     '{}' `
                    -ErrorAction Stop
            }
            else {
                # SoftDelete: HTTP DELETE moves message to Deleted Items
                # New-GraphGetRequest doesn't do DELETE; use Invoke-RestMethod
                # with the CIPP-managed token acquired via Get-GraphToken helper
                $token = Get-GraphToken -tenantid $TenantFilter -ErrorAction Stop
                $deleteUri = "https://graph.microsoft.com/v1.0/users/$($user.id)/messages/$($msg.id)"
                Invoke-RestMethod -Uri $deleteUri -Method DELETE -Headers @{ Authorization = "Bearer $token" } -ErrorAction Stop
            }

            $totalDeleted++
            Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "[$RemediationMode] Deleted '$subjectDisplay' from $upn (Received: $rcvd)" -Sev Info

        }
        catch {
            $totalErrors++
            Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Failed to delete '$subjectDisplay' from $upn : $_" -Sev Error
        }
    }
}

# =============================================================================
# SUMMARY
# =============================================================================
$summaryMsg = "COMPLETE | Tenant: $TenantFilter | Mode: $RemediationMode | Mailboxes: $totalMailboxes | Found: $totalFound | Deleted: $totalDeleted | Errors: $totalErrors"
$summarySev = if ($totalErrors -gt 0) { 'Warn' } else { 'Info' }

Write-LogMessage -API $ScriptName -tenant $TenantFilter -message $summaryMsg -Sev $summarySev

# Return structured result - displayed in CIPP Custom Scripts results panel
[PSCustomObject]@{
    Tenant           = $TenantFilter
    RemediationMode  = $RemediationMode
    MailboxesScanned = $totalMailboxes
    MessagesFound    = $totalFound
    MessagesDeleted  = $totalDeleted
    Errors           = $totalErrors
    SearchSubject    = $SearchSubject
    SearchSender     = $SearchSender
    SearchMessageId  = $SearchMessageId
}
