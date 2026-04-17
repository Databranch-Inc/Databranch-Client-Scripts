#Requires -Version 7.0
<#
.SYNOPSIS
    CIPP v10.3.0 Native Custom Script - Malicious Email Remediation with
    Safety Gates. Paste into CIPP UI: Tools > Custom Scripts > Add Script.

.DESCRIPTION
    Uses CIPP's native New-GraphGetRequest / New-GraphPostRequest helpers,
    which handle per-tenant token acquisition automatically via CIPP's SAM
    infrastructure. No credentials, no App Registrations, no file deployment.

    Workflow:
      1. Validate parameters (pre-flight)
      2. Discover tenant verified domains (internal-sender safeguard)
      3. Enumerate all mailbox users in the tenant (paged via CIPP helpers)
      4. Build OData search filter from provided criteria
      5. Search ALL mailboxes and collect the full result set - no action yet
      6. Run safety checks against the complete result set:
           - Multiple matches per mailbox  (hard stop or warning)
           - Internal sender domain match  (hard stop or warning)
           - Total match count vs MaxDeletions cap (hard stop, unbypassable)
      7. Act on results per RemediationMode and AllowDelete switch
      8. Emit structured summary via Write-LogMessage

    SAFETY GATES:
      - AllowDelete must be 'true' for any deletion to occur. When 'false',
        the script always runs in ReportOnly mode regardless of RemediationMode.
        Forces a deliberate two-step workflow: run to see what would be hit,
        then re-run with AllowDelete = 'true'.
      - Multiple matches per mailbox: hard stop in delete modes unless
        AllowOverrideSafeguards = 'true'.
      - Internal sender domain: hard stop if the From address domain matches
        any of the tenant's verified domains. Overridable via
        AllowOverrideSafeguards = 'true'.
      - MaxDeletions cap: hard stop if total matches exceed the cap.
        AllowOverrideSafeguards does NOT bypass this - raise MaxDeletions.

    CIPP CONTEXT:
      $TenantFilter is injected automatically by the CIPP Scheduler/Custom
      Scripts engine. Do not set it in the Parameters JSON - select the tenant
      in the Run or Scheduler UI. When 'AllTenants' is selected, CIPP calls
      this script once per tenant, injecting each tenant's filter individually.

.PARAMETER TenantFilter
    Injected automatically by CIPP. Tenant domain, ID, or 'AllTenants'.
    Do not include in the Parameters JSON block.

.PARAMETER SearchSubject
    Subject line keyword to match (partial, case-insensitive contains).
    At least one of SearchSubject, SearchSender, or SearchMessageId required.

.PARAMETER SearchSender
    Sender email address to match (exact).
    At least one of SearchSubject, SearchSender, or SearchMessageId required.

.PARAMETER SearchMessageId
    Internet Message-ID header value to match (exact). Angle brackets optional.
    At least one of SearchSubject, SearchSender, or SearchMessageId required.

.PARAMETER RemediationMode
    ReportOnly  - Finds and logs matches without taking any action. (Default)
    SoftDelete  - Moves message to Deleted Items (recoverable ~30 days).
    HardDelete  - Permanently deletes via Graph permanentDelete (irreversible).

.PARAMETER AllowDelete
    Must be 'true' to enable SoftDelete or HardDelete. Defaults to 'false'.
    When 'false', the script always runs ReportOnly regardless of
    RemediationMode. Forces a deliberate two-step workflow.

.PARAMETER MaxMailboxes
    Safety cap on number of mailboxes to process per tenant. Default 5000.

.PARAMETER MaxDeletions
    Safety cap on total messages to delete across the tenant. Hard stop if
    match count exceeds this value. Cannot be bypassed by AllowOverrideSafeguards.
    Default 15.

.PARAMETER AllowOverrideSafeguards
    Set to 'true' to bypass the multiple-matches-per-mailbox and internal-
    sender-domain safety gates. Does NOT override MaxDeletions or AllowDelete.
    Default 'false'.

.EXAMPLE
    Parameters JSON (ReportOnly - safe first pass):
    {
      "SearchSender":          "phisher@evil.com",
      "RemediationMode":       "ReportOnly",
      "AllowDelete":           "false"
    }

.EXAMPLE
    Parameters JSON (SoftDelete after reviewing ReportOnly output):
    {
      "SearchSender":          "phisher@evil.com",
      "RemediationMode":       "SoftDelete",
      "AllowDelete":           "true",
      "MaxDeletions":          30
    }

.EXAMPLE
    Parameters JSON (Override safeguards for broad campaign):
    {
      "SearchSubject":         "Payroll Update",
      "SearchSender":          "phisher@evil.com",
      "RemediationMode":       "SoftDelete",
      "AllowDelete":           "true",
      "MaxDeletions":          50,
      "AllowOverrideSafeguards": "true"
    }

.NOTES
    File Name      : CIPP-MailRemediation.ps1
    Version        : 2.0.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-04-16
    Last Modified  : 2026-04-16
    Modified By    : Sam Kirsch

    Requires       : PowerShell 7.0+, CIPP v10.3.0+
    Run Context    : CIPP Azure Function App (Custom Scripts)
    DattoRMM       : Not applicable - CIPP native script
    Client Scope   : All clients (via CIPP multi-tenant SAM)

    Graph Permissions Required (via CIPP SAM app):
        Mail.ReadWrite   - Search and delete messages in any mailbox
        User.Read.All    - Enumerate all licensed users/mailboxes

    Deployment:
        CIPP UI > Tools > Custom Scripts > Add Script
        Paste entire script. Enable via toggle. Run via Custom Scripts UI
        (manual/immediate) or Tools > Scheduler (scheduled/recurring).

    Parameters JSON (Advanced mode in CIPP Scheduler):
        {
          "SearchSubject":          "",
          "SearchSender":           "",
          "SearchMessageId":        "",
          "RemediationMode":        "ReportOnly",
          "AllowDelete":            "false",
          "MaxMailboxes":           5000,
          "MaxDeletions":           15,
          "AllowOverrideSafeguards": "false"
        }

    RECOMMENDED INCIDENT RESPONSE WORKFLOW:
        Step 1: AllowDelete = 'false', RemediationMode = 'ReportOnly'
                -> Review matches in CIPP Custom Scripts results / Logbook
        Step 2: AllowDelete = 'true',  RemediationMode = 'SoftDelete'
                -> Recoverable removal (~30 days in Deleted Items)
        Step 3: AllowDelete = 'true',  RemediationMode = 'HardDelete'
                -> Only if compliance or legal requires permanent removal

.CHANGELOG
    v2.0.0.0 - 2026-04-16 - Sam Kirsch
        - Full safety gate architecture ported from Invoke-MailRemediation.ps1
          (DattoRMM version v1.2.1.0)
        - Added AllowDelete parameter (default 'false') - deletion requires
          explicit opt-in regardless of RemediationMode
        - Added AllowOverrideSafeguards parameter
        - Added MaxDeletions parameter (default 15, hard cap, unbypassable)
        - Added Stage 5: collect ALL matches before any action
        - Added Stage 6: three-gate safety check engine
            Gate 1: Multiple matches per mailbox (hard stop or warning)
            Gate 2: Internal sender domain vs tenant verified domains
                    (hard stop or warning; deferred to post-collect for
                    MessageId-only searches)
            Gate 3: MaxDeletions total count cap (hard stop always)
        - Added SafeguardFlags tagging on match entries ([MULTI-MATCH],
          [INTERNAL-SENDER])
        - Added zero-match clean exit with distinct log message
        - Warn if deletion mode selected but AllowDelete not set
        - AllowOverrideSafeguards does not bypass MaxDeletions or AllowDelete
        - Structured per-match detail output in summary
        - EffectivelyDeleting resolved at startup, used throughout
        - Get-TenantVerifiedDomains helper added
        - Get-MailFilterExpression helper renamed to match DattoRMM conventions
        - AllMatches collected as Generic List for O(1) Add operations

    v1.0.0.001 - 2026-04-16 - Sam Kirsch
        - Initial CIPP v10.3.0 Custom Scripts release
        - CIPP-native New-GraphGetRequest / New-GraphPostRequest auth
        - Write-LogMessage for CIPP log pipeline integration
        - $TenantFilter convention for CIPP tenant targeting
        - Paged mailbox enumeration via CIPP Graph helpers
        - OData filter: Subject / Sender / MessageId joined with OR
        - ReportOnly / SoftDelete / HardDelete modes
        - Per-mailbox error isolation
        - Grand summary returned as structured output
#>

# ==============================================================================
# PARAMETERS
# TenantFilter is injected by CIPP - do not include in Parameters JSON.
# AllowDelete and AllowOverrideSafeguards are passed as strings from the CIPP
# Parameters JSON block and compared with -eq 'true' (never cast to [bool]).
# ==============================================================================
param(
    # Injected by CIPP - do not set in Parameters JSON
    [string]$TenantFilter            = 'AllTenants',

    # Search criteria - at least one required
    [string]$SearchSubject           = '',
    [string]$SearchSender            = '',
    [string]$SearchMessageId         = '',

    # Remediation behavior
    [ValidateSet('ReportOnly', 'SoftDelete', 'HardDelete')]
    [string]$RemediationMode         = 'ReportOnly',

    # Explicit deletion gate - must be 'true' for any deletion to occur.
    # Compared as string: -eq 'true'. Never cast to [bool].
    [string]$AllowDelete             = 'false',

    # Safety caps
    [int]$MaxMailboxes               = 5000,
    [int]$MaxDeletions               = 15,

    # Override multi-match and internal-sender gates only.
    # Does NOT bypass MaxDeletions or AllowDelete.
    [string]$AllowOverrideSafeguards = 'false'
)

# ==============================================================================
# SCRIPT METADATA
# ==============================================================================
$ScriptName    = 'CIPP-MailRemediation'
$ScriptVersion = '2.0.0.0'

# ==============================================================================
# RESOLVE EFFECTIVE OPERATING MODE
# Determined once at the top - used throughout to keep logic clean.
# AllowDelete gates whether deletion actually runs, regardless of Mode.
# ==============================================================================
$EffectivelyDeleting = ($AllowDelete -eq 'true') -and ($RemediationMode -ne 'ReportOnly')
$OverrideSafeguards  = ($AllowOverrideSafeguards -eq 'true')

# ==============================================================================
# PRE-FLIGHT VALIDATION
# ==============================================================================
if (-not $SearchSubject -and -not $SearchSender -and -not $SearchMessageId) {
    $Msg = 'PRE-FLIGHT FAILED: At least one search criterion must be provided: SearchSubject, SearchSender, or SearchMessageId.'
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message $Msg -Sev Error
    throw $Msg
}

# Log startup header
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "===== $ScriptName v$ScriptVersion =====" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Remediation Mode       : $RemediationMode" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Allow Delete           : $AllowDelete" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Effectively Deleting   : $EffectivelyDeleting" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Max Deletions Cap      : $MaxDeletions" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Override Safeguards    : $AllowOverrideSafeguards" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Max Mailboxes          : $MaxMailboxes" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Search - Subject       : $(if ($SearchSubject)   { $SearchSubject }   else { '(not set)' })" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Search - Sender        : $(if ($SearchSender)    { $SearchSender }    else { '(not set)' })" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Search - MsgID         : $(if ($SearchMessageId) { $SearchMessageId } else { '(not set)' })" -Sev Info

# Warn if deletion mode was selected but AllowDelete was not set
if ($RemediationMode -ne 'ReportOnly' -and $AllowDelete -ne 'true') {
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "RemediationMode is '$RemediationMode' but AllowDelete is not 'true'. Running as ReportOnly." -Sev Warn
}

if ($EffectivelyDeleting -and $RemediationMode -eq 'HardDelete') {
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'WARNING: HardDelete mode - matched messages will be PERMANENTLY deleted and are not recoverable.' -Sev Warn
}

# ==============================================================================
# HELPER: Get-MailFilterExpression
# Builds an OData $filter expression from the provided search criteria.
# Multiple criteria joined with OR so any match qualifies.
# ==============================================================================
function Get-MailFilterExpression {
    param (
        [string]$Subject,
        [string]$Sender,
        [string]$MessageId
    )

    $Filters = [System.Collections.Generic.List[string]]::new()

    if ($Subject) {
        $EscapedSubject = $Subject.Replace("'", "''")
        $Filters.Add("contains(subject,'$EscapedSubject')")
    }

    if ($Sender) {
        $EscapedSender = $Sender.Replace("'", "''")
        $Filters.Add("from/emailAddress/address eq '$EscapedSender'")
    }

    if ($MessageId) {
        $CleanMsgId   = $MessageId.Trim().TrimStart('<').TrimEnd('>')
        $EscapedMsgId = $CleanMsgId.Replace("'", "''")
        $Filters.Add("internetMessageId eq '<$EscapedMsgId>'")
    }

    if ($Filters.Count -eq 0) { return $null }
    return $Filters -join ' or '
}

# ==============================================================================
# HELPER: Get-TenantVerifiedDomains
# Queries Graph /domains for the tenant's verified domain list.
# Used by the internal-sender safety gate.
# New-GraphGetRequest handles per-tenant auth via CIPP SAM automatically.
# ==============================================================================
function Get-TenantVerifiedDomains {
    param ([string]$TenantId)

    Write-LogMessage -API $ScriptName -tenant $TenantId -message 'Retrieving tenant verified domains for internal-sender check...' -Sev Info

    try {
        $DomainsResult = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains' -tenantid $TenantId -ErrorAction Stop
    }
    catch {
        throw "Failed to retrieve tenant domains from Graph: $_"
    }

    $VerifiedDomains = @($DomainsResult) |
                       Where-Object { $_.isVerified -eq $true } |
                       ForEach-Object { $_.id.ToLower() }

    if (-not $VerifiedDomains -or $VerifiedDomains.Count -eq 0) {
        throw 'No verified domains returned for tenant. Verify Mail.ReadWrite and User.Read.All permissions on CIPP SAM app.'
    }

    Write-LogMessage -API $ScriptName -tenant $TenantId -message "Tenant verified domains ($($VerifiedDomains.Count)): $($VerifiedDomains -join ', ')" -Sev Info
    return $VerifiedDomains
}

# ==============================================================================
# STAGE 2 - Tenant Domain Discovery
# Runs even in ReportOnly so the internal-sender check is always active.
# ==============================================================================
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '--- Stage 2: Tenant Domain Discovery ---' -Sev Info

try {
    $TenantDomains = Get-TenantVerifiedDomains -TenantId $TenantFilter
}
catch {
    $Msg = "Stage 2 failed - could not retrieve tenant domains: $_"
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message $Msg -Sev Error
    throw $Msg
}

# Note deferred sender check for MessageId-only searches
if (-not $SearchSender -and -not $SearchSubject -and $SearchMessageId) {
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'Search is MessageId-only. Internal-sender check will run post-collection against actual message data.' -Sev Warn
}

# ==============================================================================
# STAGE 3 - Mailbox Enumeration
# New-GraphGetRequest handles paging and per-tenant auth automatically.
# ==============================================================================
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '--- Stage 3: Mailbox Enumeration ---' -Sev Info

try {
    $AllUsers = New-GraphGetRequest `
        -uri      "https://graph.microsoft.com/v1.0/users?`$select=id,userPrincipalName,displayName,mail&`$filter=accountEnabled eq true&`$top=999" `
        -tenantid $TenantFilter `
        -ErrorAction Stop
}
catch {
    $Msg = "Stage 3 failed - could not enumerate tenant users. Verify User.Read.All permission: $_"
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message $Msg -Sev Error
    throw $Msg
}

$MailboxUsers = @($AllUsers) | Where-Object { $_.mail -or ($_.userPrincipalName -like '*@*') }

if (-not $MailboxUsers -or $MailboxUsers.Count -eq 0) {
    $Msg = 'No mailbox users found in tenant. Verify User.Read.All application permission and admin consent on CIPP SAM app.'
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message $Msg -Sev Error
    throw $Msg
}

Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Found $($MailboxUsers.Count) mailbox-enabled users in tenant." -Sev Info

if ($MailboxUsers.Count -gt $MaxMailboxes) {
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "User count ($($MailboxUsers.Count)) exceeds MaxMailboxes cap ($MaxMailboxes). Processing first $MaxMailboxes only." -Sev Warn
    $MailboxUsers = $MailboxUsers | Select-Object -First $MaxMailboxes
}

# ==============================================================================
# STAGE 4 - Build OData Search Filter
# ==============================================================================
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '--- Stage 4: Building Search Filter ---' -Sev Info

$ODataFilter = Get-MailFilterExpression `
    -Subject   $SearchSubject `
    -Sender    $SearchSender `
    -MessageId $SearchMessageId

if (-not $ODataFilter) {
    $Msg = 'Stage 4 failed - could not build OData filter. No search criteria resolved.'
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message $Msg -Sev Error
    throw $Msg
}

Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "OData filter: $ODataFilter" -Sev Info

# ==============================================================================
# STAGE 5 - Tenant-Wide Search (Collect All Results)
# IMPORTANT: No deletions occur in this stage. Every mailbox is searched and
# all matches are collected so the safety checks in Stage 6 can evaluate the
# complete picture before a single message is touched.
# ==============================================================================
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '--- Stage 5: Tenant-Wide Search (No Action Yet) ---' -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'Searching all mailboxes. No action taken until Stage 6 safety checks pass.' -Sev Info

$AllMatches   = [System.Collections.Generic.List[PSObject]]::new()
$TotalErrors  = 0
$MailboxIndex = 0
$EncodedFilter = [Uri]::EscapeDataString($ODataFilter)

foreach ($User in $MailboxUsers) {
    $MailboxIndex++
    $UPN = if ($User.userPrincipalName) { $User.userPrincipalName } else { $User.mail }

    $SearchUri = "https://graph.microsoft.com/v1.0/users/$($User.id)/messages" +
                 "?`$filter=$EncodedFilter" +
                 "&`$select=id,subject,from,receivedDateTime,internetMessageId" +
                 "&`$top=50"

    try {
        $Messages = New-GraphGetRequest -uri $SearchUri -tenantid $TenantFilter -ErrorAction Stop
    }
    catch {
        Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "[$MailboxIndex/$($MailboxUsers.Count)] Search failed for '$UPN': $_" -Sev Warn
        $TotalErrors++
        continue
    }

    if (-not $Messages -or @($Messages).Count -eq 0) { continue }

    $MsgList = @($Messages)
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "[$MailboxIndex/$($MailboxUsers.Count)] Found $($MsgList.Count) match(es) in $UPN" -Sev Info

    foreach ($Msg in $MsgList) {
        $FromAddress = $Msg.from.emailAddress.address
        $FromDomain  = ($FromAddress -split '@' | Select-Object -Last 1).ToLower()

        $AllMatches.Add([PSCustomObject]@{
            UserPrincipalName = $UPN
            UserId            = $User.id
            DisplayName       = $User.displayName
            MessageId         = $Msg.internetMessageId
            Subject           = if ($Msg.subject) { $Msg.subject } else { '(no subject)' }
            From              = $FromAddress
            FromDomain        = $FromDomain
            ReceivedDateTime  = $Msg.receivedDateTime
            GraphId           = $Msg.id
            Result            = 'Pending'
            SafeguardFlags    = ''
        })
    }
}

Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Stage 5 complete. Total matches: $($AllMatches.Count) across $MailboxIndex mailboxes scanned." -Sev Info

# ------------------------------------------------------------------------------
# Zero-match clean exit - not an error condition
# ------------------------------------------------------------------------------
if ($AllMatches.Count -eq 0) {
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'No matching messages found across all scanned mailboxes. Clean result.' -Sev Info
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'The email may already be deleted or the search criteria did not match.' -Sev Info
    return [PSCustomObject]@{
        Tenant           = $TenantFilter
        RemediationMode  = $RemediationMode
        EffectivelyDeleting = $EffectivelyDeleting
        MailboxesScanned = $MailboxIndex
        MessagesFound    = 0
        MessagesDeleted  = 0
        SafeguardViolations = 0
        SafeguardWarnings   = 0
        SearchErrors     = $TotalErrors
        Result           = 'NoMatchesFound'
    }
}

# ==============================================================================
# STAGE 6 - Safety Checks
# All checks evaluate the complete AllMatches collection. Any hard-stop
# violation throws without touching a single message.
# ==============================================================================
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '--- Stage 6: Safety Checks ---' -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Running safety checks against $($AllMatches.Count) match(es)..." -Sev Info

$SafeguardViolations = [System.Collections.Generic.List[string]]::new()
$SafeguardWarnings   = [System.Collections.Generic.List[string]]::new()

# ------------------------------------------------------------------------------
# GATE 1 - Multiple matches per mailbox
# Build a count per UPN. Any mailbox with >1 match is flagged.
# In delete modes: hard stop unless OverrideSafeguards is set.
# In ReportOnly or override: warn and continue.
# ------------------------------------------------------------------------------
$MatchesByMailbox = @{}
foreach ($Match in $AllMatches) {
    if (-not $MatchesByMailbox.ContainsKey($Match.UserPrincipalName)) {
        $MatchesByMailbox[$Match.UserPrincipalName] = 0
    }
    $MatchesByMailbox[$Match.UserPrincipalName]++
}

$MultiMatchMailboxes = $MatchesByMailbox.GetEnumerator() | Where-Object { $_.Value -gt 1 }

if ($MultiMatchMailboxes) {

    foreach ($MB in $MultiMatchMailboxes) {
        Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "GATE 1 - MULTI-MATCH: $($MB.Value) messages matched in mailbox $($MB.Key)" -Sev Warn
    }

    # Tag the affected match entries
    $MatchIndex = 0
    foreach ($Match in $AllMatches) {
        if ($MatchesByMailbox[$Match.UserPrincipalName] -gt 1) {
            $AllMatches[$MatchIndex].SafeguardFlags += '[MULTI-MATCH]'
        }
        $MatchIndex++
    }

    $MultiCount   = ($MultiMatchMailboxes | Measure-Object).Count
    $ViolationMsg = "Gate 1: $MultiCount mailbox(es) contain more than one matching message. Expected one match per mailbox for a targeted hunt."

    if ($EffectivelyDeleting -and -not $OverrideSafeguards) {
        $SafeguardViolations.Add($ViolationMsg)
    }
    else {
        $SafeguardWarnings.Add($ViolationMsg)
    }
}

# ------------------------------------------------------------------------------
# GATE 2 - Internal sender domain
# Compare each match's From domain against the tenant's verified domains.
# Internal mail matching the search criteria is almost always a false positive.
# In delete modes: hard stop unless OverrideSafeguards is set.
# In ReportOnly or override: warn and continue.
# ------------------------------------------------------------------------------
$InternalMatches = $AllMatches | Where-Object { $TenantDomains -contains $_.FromDomain }

if ($InternalMatches) {

    foreach ($IM in $InternalMatches) {
        Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "GATE 2 - INTERNAL SENDER: '$($IM.From)' (domain '$($IM.FromDomain)') is a verified tenant domain - mailbox: $($IM.UserPrincipalName)" -Sev Warn
    }

    # Tag the affected match entries
    $MatchIndex = 0
    foreach ($Match in $AllMatches) {
        if ($TenantDomains -contains $Match.FromDomain) {
            $AllMatches[$MatchIndex].SafeguardFlags += '[INTERNAL-SENDER]'
        }
        $MatchIndex++
    }

    $InternalCount = ($InternalMatches | Measure-Object).Count
    $ViolationMsg  = "Gate 2: $InternalCount match(es) have a sender address from a verified tenant domain. Deleting internal mail requires AllowOverrideSafeguards = 'true'."

    if ($EffectivelyDeleting -and -not $OverrideSafeguards) {
        $SafeguardViolations.Add($ViolationMsg)
    }
    else {
        $SafeguardWarnings.Add($ViolationMsg)
    }
}

# ------------------------------------------------------------------------------
# GATE 3 - MaxDeletions cap
# Hard stop if match count exceeds the cap.
# AllowOverrideSafeguards does NOT bypass this gate - must raise MaxDeletions.
# Only enforced when actually deleting.
# ------------------------------------------------------------------------------
if ($EffectivelyDeleting -and $AllMatches.Count -gt $MaxDeletions) {
    $ViolationMsg = "Gate 3: Total match count ($($AllMatches.Count)) exceeds MaxDeletions cap ($MaxDeletions). Raise MaxDeletions to proceed. AllowOverrideSafeguards does not bypass this gate."
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "GATE 3 - MAX DELETIONS EXCEEDED: $ViolationMsg" -Sev Error
    $SafeguardViolations.Add($ViolationMsg)
}

# ------------------------------------------------------------------------------
# Evaluate - throw (hard stop) if any violations
# ------------------------------------------------------------------------------
if ($SafeguardViolations.Count -gt 0) {
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '*** SAFETY GATE TRIPPED - NO MESSAGES DELETED ***' -Sev Error
    foreach ($V in $SafeguardViolations) {
        Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "VIOLATION: $V" -Sev Error
    }
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'Set AllowOverrideSafeguards = true to bypass Gate 1 and Gate 2. Raise MaxDeletions to bypass Gate 3.' -Sev Error
    throw "Safety gate tripped - $($SafeguardViolations.Count) violation(s). No messages deleted. See log for details."
}

if ($SafeguardWarnings.Count -gt 0) {
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '*** SAFEGUARD WARNINGS - PROCEEDING ***' -Sev Warn
    foreach ($W in $SafeguardWarnings) {
        Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "WARNING: $W" -Sev Warn
    }
}

Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'All safety checks passed.' -Sev Info

# ==============================================================================
# STAGE 7 - Remediation
# Safety checks passed. Act on each match per mode.
# ==============================================================================
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '--- Stage 7: Remediation ---' -Sev Info

$TotalDeleted = 0
$MatchIndex   = 0

foreach ($Match in $AllMatches) {

    $FlagSuffix = if ($Match.SafeguardFlags) { " $($Match.SafeguardFlags)" } else { '' }

    # ReportOnly path (mode is ReportOnly, or AllowDelete was not 'true')
    if (-not $EffectivelyDeleting) {
        Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "[REPORT ONLY]$FlagSuffix '$($Match.Subject)' | From: $($Match.From) | Mailbox: $($Match.UserPrincipalName)" -Sev Info
        $AllMatches[$MatchIndex].Result = 'ReportOnly'
        $MatchIndex++
        continue
    }

    # Delete path
    try {
        if ($RemediationMode -eq 'HardDelete') {
            # POST to permanentDelete - irreversible, bypasses Recoverable Items
            $null = New-GraphPostRequest `
                -uri      "https://graph.microsoft.com/v1.0/users/$($Match.UserId)/messages/$($Match.GraphId)/permanentDelete" `
                -tenantid $TenantFilter `
                -body     '{}' `
                -ErrorAction Stop
        }
        else {
            # SoftDelete - HTTP DELETE moves to Deleted Items (~30 days recoverable)
            # New-GraphPostRequest only handles POST; use Get-GraphToken for the
            # raw DELETE call while still leveraging CIPP's SAM token infrastructure.
            $Token = Get-GraphToken -tenantid $TenantFilter -ErrorAction Stop
            $DeleteUri = "https://graph.microsoft.com/v1.0/users/$($Match.UserId)/messages/$($Match.GraphId)"
            Invoke-RestMethod -Uri $DeleteUri -Method DELETE -Headers @{ Authorization = "Bearer $Token" } -ErrorAction Stop
        }

        $TotalDeleted++
        $AllMatches[$MatchIndex].Result = 'Deleted'
        Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "[$RemediationMode]$FlagSuffix Deleted '$($Match.Subject)' in $($Match.UserPrincipalName)" -Sev Info
    }
    catch {
        $TotalErrors++
        $AllMatches[$MatchIndex].Result = "Failed: $_"
        Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Failed to delete '$($Match.Subject)' in $($Match.UserPrincipalName): $_" -Sev Error
    }

    $MatchIndex++
}

# ==============================================================================
# STAGE 8 - Summary
# Structured per-entry detail so each match is fully visible in the logbook.
# ==============================================================================
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '--- Stage 8: Summary ---' -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '----------- REMEDIATION SUMMARY -----------' -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Tenant                 : $TenantFilter" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Remediation Mode       : $RemediationMode" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Allow Delete           : $AllowDelete" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Override Safeguards    : $AllowOverrideSafeguards" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Mailboxes Scanned      : $MailboxIndex" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Messages Found         : $($AllMatches.Count)" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Messages Deleted       : $TotalDeleted" -Sev $(if ($TotalDeleted -gt 0) { 'Info' } else { 'Info' })
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Safeguard Violations   : $($SafeguardViolations.Count)" -Sev Info
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Safeguard Warnings     : $($SafeguardWarnings.Count)" -Sev $(if ($SafeguardWarnings.Count -gt 0) { 'Warn' } else { 'Info' })
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "Search Errors          : $TotalErrors" -Sev $(if ($TotalErrors -gt 0) { 'Warn' } else { 'Info' })
Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '-------------------------------------------' -Sev Info

Write-LogMessage -API $ScriptName -tenant $TenantFilter -message 'Match Details:' -Sev Info
foreach ($Match in $AllMatches) {
    $MatchSev = if ($Match.SafeguardFlags) { 'Warn' } else { 'Info' }
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "  UPN      : $($Match.UserPrincipalName)"  -Sev $MatchSev
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "  Subject  : $($Match.Subject)"            -Sev $MatchSev
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "  From     : $($Match.From)"               -Sev $MatchSev
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "  Received : $($Match.ReceivedDateTime)"   -Sev $MatchSev
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "  Flags    : $(if ($Match.SafeguardFlags) { $Match.SafeguardFlags } else { 'none' })" -Sev $MatchSev
    $ResultSev = if ($Match.Result -eq 'Deleted') { 'Info' } elseif ($Match.Result -like 'Failed*') { 'Error' } else { 'Info' }
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message "  Result   : $($Match.Result)" -Sev $ResultSev
    Write-LogMessage -API $ScriptName -tenant $TenantFilter -message '  ---' -Sev Info
}

# ==============================================================================
# RETURN STRUCTURED RESULT
# Displayed in CIPP Custom Scripts results panel and Scheduler task results.
# ==============================================================================
$FinalResult = if ($TotalErrors -gt 0) { 'CompletedWithErrors' } else { 'Success' }

[PSCustomObject]@{
    Tenant              = $TenantFilter
    RemediationMode     = $RemediationMode
    AllowDelete         = $AllowDelete
    EffectivelyDeleting = $EffectivelyDeleting
    MailboxesScanned    = $MailboxIndex
    MessagesFound       = $AllMatches.Count
    MessagesDeleted     = $TotalDeleted
    SafeguardViolations = $SafeguardViolations.Count
    SafeguardWarnings   = $SafeguardWarnings.Count
    SearchErrors        = $TotalErrors
    Result              = $FinalResult
}
