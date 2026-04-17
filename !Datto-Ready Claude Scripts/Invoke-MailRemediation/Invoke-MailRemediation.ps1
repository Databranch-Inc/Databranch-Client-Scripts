#Requires -Version 5.1
<#
.SYNOPSIS
    Searches and remediates malicious emails across all mailboxes in an M365
    tenant via Microsoft Graph API, using credentials retrieved from IT Glue.

.DESCRIPTION
    Designed to run as a DattoRMM component or interactively. Accepts email
    search parameters (Subject, Sender, MessageID) as DattoRMM input variables
    or standard PowerShell parameters.

    Workflow:
      1. Retrieve the client App Registration secret from IT Glue via REST API
      2. Authenticate to Microsoft Graph using OAuth2 client_credentials flow
      3. Query tenant for verified domains (used by internal-sender safeguard)
      4. Enumerate all licensed mailbox users in the tenant (paged)
      5. Search ALL mailboxes and collect the full result set before any action
      6. Run safety checks against the complete result set:
           - Multiple matches per mailbox (hard stop or flagged warning)
           - Internal sender domain match (hard stop or flagged warning)
           - Total deletion count exceeds MaxDeletions cap
      7. Delete or report per RemediationMode and AllowDelete switch

    SAFETY GATES (all require AllowOverrideSafeguards to bypass except cap):
      - Multiple matches per mailbox: hard stop in delete modes; ReportOnly
        flags heavily but continues.
      - Internal sender: stops if the From address domain matches any of the
        tenant's verified domains. Protects against accidentally deleting
        legitimate internal mail.
      - MaxDeletions cap: hard stop if total matches exceed the cap. Requires
        raising -MaxDeletions to proceed - AllowOverrideSafeguards does not
        bypass this one.

    DEFAULT BEHAVIOR:
      RemediationMode defaults to ReportOnly. Deletion additionally requires
      AllowDelete to be explicitly set to 'true'. This forces a deliberate
      two-step workflow: run to see what would be hit, then re-run with
      AllowDelete enabled.

    No external modules required - all API calls use Invoke-RestMethod.

.PARAMETER ITGlueApiKey
    IT Glue API key with Read access to Passwords.
    DattoRMM env var: ITGlueApiKey

.PARAMETER ITGlueBaseUrl
    IT Glue API base URL. Defaults to US endpoint (https://api.itglue.com).
    Use https://api.eu.itglue.com for EU, https://api.au.itglue.com for AU.
    DattoRMM env var: ITGlueBaseUrl

.PARAMETER ITGlueOrgId
    IT Glue Organization ID for the target client.
    DattoRMM env var: ITGlueOrgId

.PARAMETER ITGluePasswordAssetName
    Name of the IT Glue Password asset holding the App Registration Client
    Secret. Defaults to 'M365 Graph App Registration'.
    DattoRMM env var: ITGluePasswordAssetName

.PARAMETER TenantId
    Azure AD Tenant ID (Directory ID) for the target M365 tenant.
    DattoRMM env var: TenantId

.PARAMETER ClientId
    Azure App Registration Client ID.
    DattoRMM env var: ClientId

.PARAMETER SearchSubject
    Subject line keyword(s) to match (partial, case-insensitive contains).
    DattoRMM env var: SearchSubject

.PARAMETER SearchSender
    Sender email address to match (exact).
    DattoRMM env var: SearchSender

.PARAMETER SearchMessageId
    Internet Message-ID header value to match (exact). Angle brackets optional.
    DattoRMM env var: SearchMessageId

.PARAMETER RemediationMode
    SoftDelete  - Moves message to Deleted Items (recoverable ~30 days).
    HardDelete  - Permanently deletes via Graph permanentDelete (irreversible).
    ReportOnly  - Finds and logs matches without taking any action. (Default)
    DattoRMM env var: RemediationMode

.PARAMETER AllowDelete
    Must be explicitly set to 'true' to enable SoftDelete or HardDelete.
    Defaults to 'false'. When false, the script always runs ReportOnly
    regardless of RemediationMode. Forces a deliberate two-step workflow.
    DattoRMM env var: AllowDelete

.PARAMETER MaxMailboxes
    Safety cap on number of mailboxes to process. Default 5000.
    DattoRMM env var: MaxMailboxes

.PARAMETER MaxDeletions
    Safety cap on total number of messages to delete across the entire tenant.
    Hard stop if the search result count would exceed this value. Default 15.
    Cannot be bypassed by AllowOverrideSafeguards - must raise this param.
    DattoRMM env var: MaxDeletions

.PARAMETER AllowOverrideSafeguards
    Set to 'true' to bypass the multiple-matches-per-mailbox and internal-
    sender-domain safety gates. Does NOT override MaxDeletions or AllowDelete.
    Default 'false'.
    DattoRMM env var: AllowOverrideSafeguards

.PARAMETER SiteName
    Client/site name for logging. Auto-populated by DattoRMM (CS_PROFILE_NAME).

.PARAMETER Hostname
    Machine hostname for logging. Auto-populated by DattoRMM (CS_HOSTNAME).

.EXAMPLE
    .\Invoke-MailRemediation.ps1 `
        -ITGlueApiKey "abc123" -ITGlueOrgId "123456" `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ClientId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -SearchSender "phisher@evil.com"
    Default ReportOnly scan. Safe first-pass - no deletion possible without
    AllowDelete 'true'.

.EXAMPLE
    .\Invoke-MailRemediation.ps1 `
        -ITGlueApiKey "abc123" -ITGlueOrgId "123456" `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ClientId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -SearchSender "phisher@evil.com" `
        -RemediationMode SoftDelete -AllowDelete 'true'
    Soft-delete matched messages after reviewing the ReportOnly run.

.EXAMPLE
    .\Invoke-MailRemediation.ps1 `
        -ITGlueApiKey "abc123" -ITGlueOrgId "123456" `
        -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -ClientId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy" `
        -SearchSubject "Payroll Update" -SearchSender "phisher@evil.com" `
        -RemediationMode SoftDelete -AllowDelete 'true' `
        -MaxDeletions 30 -AllowOverrideSafeguards 'true'
    Override safeguards and raise deletion cap for a broader campaign.

.NOTES
    File Name      : Invoke-MailRemediation.ps1
    Version        : 1.2.1.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-04-16
    Last Modified  : 2026-04-16
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM (DattoRMM) or Domain Admin (manual runs)
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : All clients (per-client IT Glue org ID required)

    Graph API Permissions Required (Application, not Delegated):
        Mail.ReadWrite   - Search and delete messages in any mailbox
        User.Read.All    - Enumerate all licensed users/mailboxes

    IT Glue Requirements:
        - API key with Read access to Passwords
        - Password asset in the client org containing the App Registration
          client secret (Password field). Asset name must match
          ITGluePasswordAssetName parameter.

    Exit Codes:
        0  - Completed successfully, including a clean zero-match result
        1  - Completed with one or more runtime errors (check log)
        2  - Fatal pre-flight failure, missing parameters, auth failure,
             or safety gate tripped - nothing was deleted

    WhatIf Support:
        SupportsShouldProcess is enabled. Use -WhatIf to simulate deletions.

.CHANGELOG
    v1.2.1.0 - 2026-04-16 - Sam Kirsch
        - Added TLS 1.2 enforcement. PowerShell 5.1 on older Windows defaults
          to TLS 1.0/1.1; IT Glue and Graph/Azure AD require TLS 1.2 minimum.

    v1.2.0.0 - 2026-04-16 - Sam Kirsch
        - Redesigned Stage 5: search ALL mailboxes first, collect full result
          set, then run all safety checks before any deletion occurs
        - Added AllowDelete parameter (default 'false') - deletion requires
          explicit opt-in; script always runs ReportOnly unless 'true'
        - Added multiple-matches-per-mailbox safeguard: hard stop in delete
          modes if any mailbox has >1 match; flags but continues in ReportOnly;
          overridable via AllowOverrideSafeguards
        - Added internal-sender-domain safeguard: queries Graph /domains for
          tenant verified domains; hard stop if From address domain is internal;
          overridable via AllowOverrideSafeguards. MessageId-only searches defer
          this check to post-collection against actual message data.
        - Added MaxDeletions parameter (default 15): hard stop if total match
          count exceeds cap; not overridable by AllowOverrideSafeguards
        - Added AllowOverrideSafeguards parameter: bypasses multiple-matches
          and internal-sender gates only
        - Added Get-TenantDomains helper (Graph /domains endpoint)
        - Added Stage 2.5 for tenant domain discovery
        - Added zero-match clean exit (exit 0, clear log message, no error)
        - RemediationMode now defaults to ReportOnly (was SoftDelete)
        - Safeguard flags ([MULTI-MATCH], [INTERNAL-SENDER]) written to match
          detail entries and surfaced in summary output
        - Log header updated to reflect new parameters

    v1.1.0.0 - 2026-04-16 - Sam Kirsch
        - Rebuilt to full Databranch standards
        - Dual-output pattern (Write-Log / Write-Console)
        - Write-Banner, Write-Section, Write-Separator helpers
        - Initialize-Logging with log rotation
        - Standard log header
        - SiteName and Hostname parameters
        - DEBUG severity in Write-Log
        - Script-scope parameters with splatted entry point
        - PS 5.1 compatibility fixes
        - Approved verb for filter builder function
        - Structured summary output replacing Format-Table
        - exit 2 for fatal pre-flight failures

    v1.0.0.0 - 2026-04-16 - Sam Kirsch
        - Initial release
#>

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# PowerShell 5.1 on older Windows (Server 2012 R2, early Win10 builds) defaults
# to TLS 1.0/1.1 for web requests. IT Glue and Microsoft Graph/Azure AD both
# require TLS 1.2 minimum and will reject older connections with errors that
# look like generic network failures. Force it explicitly.
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

# ==============================================================================
# PARAMETERS
# Script-level params with DattoRMM env var -> parameter -> default fallback.
# Boolean DattoRMM vars arrive as strings "true"/"false" - always compare with
# -eq 'true', never cast to [bool] or test truthiness directly.
# ==============================================================================
[CmdletBinding(SupportsShouldProcess)]
param (
    # --- IT Glue Connection ---
    [Parameter(Mandatory = $false)]
    [string]$ITGlueApiKey            = $env:ITGlueApiKey,

    [Parameter(Mandatory = $false)]
    [string]$ITGlueBaseUrl           = $(if ($env:ITGlueBaseUrl) { $env:ITGlueBaseUrl } else { 'https://api.itglue.com' }),

    [Parameter(Mandatory = $false)]
    [string]$ITGlueOrgId             = $env:ITGlueOrgId,

    [Parameter(Mandatory = $false)]
    [string]$ITGluePasswordAssetName = $(if ($env:ITGluePasswordAssetName) { $env:ITGluePasswordAssetName } else { 'M365 Graph App Registration' }),

    # --- Azure / Graph ---
    [Parameter(Mandatory = $false)]
    [string]$TenantId                = $env:TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId                = $env:ClientId,

    # --- Email Search Criteria (at least one required) ---
    [Parameter(Mandatory = $false)]
    [string]$SearchSubject           = $env:SearchSubject,

    [Parameter(Mandatory = $false)]
    [string]$SearchSender            = $env:SearchSender,

    [Parameter(Mandatory = $false)]
    [string]$SearchMessageId         = $env:SearchMessageId,

    # --- Remediation Behavior ---
    [Parameter(Mandatory = $false)]
    [ValidateSet('SoftDelete', 'HardDelete', 'ReportOnly')]
    [string]$RemediationMode         = $(if ($env:RemediationMode) { $env:RemediationMode } else { 'ReportOnly' }),

    # AllowDelete must be 'true' for any deletion to occur.
    # DattoRMM Boolean vars are strings - compare with -eq 'true', not [bool].
    [Parameter(Mandatory = $false)]
    [string]$AllowDelete             = $(if ($env:AllowDelete) { $env:AllowDelete } else { 'false' }),

    [Parameter(Mandatory = $false)]
    [int]$MaxMailboxes               = $(if ($env:MaxMailboxes) { [int]$env:MaxMailboxes } else { 5000 }),

    [Parameter(Mandatory = $false)]
    [int]$MaxDeletions               = $(if ($env:MaxDeletions) { [int]$env:MaxDeletions } else { 15 }),

    # Bypasses multiple-matches and internal-sender gates only.
    # Does NOT override MaxDeletions or AllowDelete.
    [Parameter(Mandatory = $false)]
    [string]$AllowOverrideSafeguards = $(if ($env:AllowOverrideSafeguards) { $env:AllowOverrideSafeguards } else { 'false' }),

    # --- DattoRMM Built-in Variables ---
    [Parameter(Mandatory = $false)]
    [string]$SiteName                = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { 'UnknownSite' }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname                = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Invoke-MailRemediation {
    <#
    .SYNOPSIS
        Internal master function. See script-level help for full documentation.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [string]$ITGlueApiKey,
        [string]$ITGlueBaseUrl,
        [string]$ITGlueOrgId,
        [string]$ITGluePasswordAssetName,
        [string]$TenantId,
        [string]$ClientId,
        [string]$SearchSubject,
        [string]$SearchSender,
        [string]$SearchMessageId,
        [ValidateSet('SoftDelete', 'HardDelete', 'ReportOnly')]
        [string]$RemediationMode,
        [string]$AllowDelete,
        [int]$MaxMailboxes,
        [int]$MaxDeletions,
        [string]$AllowOverrideSafeguards,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = 'Invoke-MailRemediation'
    $ScriptVersion = '1.2.1.0'
    $LogRoot       = 'C:\Databranch\ScriptLogs'
    $LogFolder     = Join-Path -Path $LogRoot -ChildPath $ScriptName
    $LogDate       = Get-Date -Format 'yyyy-MM-dd'
    $LogFile       = Join-Path -Path $LogFolder -ChildPath "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # ==========================================================================
    # WRITE-LOG  (Structured Output Layer)
    # Writes timestamped entries to log file AND DattoRMM stdout.
    # Uses Write-Output/Warning/Error - NOT Write-Host.
    # ==========================================================================
    function Write-Log {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = '',

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
            [string]$Severity = 'INFO'
        )

        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $LogEntry  = "[$Timestamp] [$Severity] $Message"

        switch ($Severity) {
            'INFO'    { Write-Output  $LogEntry }
            'WARN'    { Write-Warning $LogEntry }
            'ERROR'   { Write-Error   $LogEntry -ErrorAction Continue }
            'SUCCESS' { Write-Output  $LogEntry }
            'DEBUG'   { Write-Output  $LogEntry }
        }

        try {
            Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8
        }
        catch {
            Write-Warning "[$Timestamp] [WARN] Could not write to log file: $_"
        }
    }

    # ==========================================================================
    # WRITE-CONSOLE  (Presentation Layer)
    # Colored output for interactive runs. Uses Write-Host (display stream 6).
    # NOT captured by DattoRMM stdout. Safe alongside Write-Log at all times.
    # ==========================================================================
    function Write-Console {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = '',

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG', 'PLAIN')]
            [string]$Severity = 'PLAIN',

            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )

        $Prefix = '  ' * $Indent
        $SeverityColors = @{
            INFO    = 'Cyan'
            SUCCESS = 'Green'
            WARN    = 'Yellow'
            ERROR   = 'Red'
            DEBUG   = 'Magenta'
            PLAIN   = 'Gray'
        }
        $Color = $SeverityColors[$Severity]

        if ($Severity -eq 'PLAIN') {
            Write-Host "$Prefix$Message" -ForegroundColor $Color
        }
        else {
            Write-Host "$Prefix" -NoNewline
            Write-Host "[$Severity]" -ForegroundColor $Color -NoNewline
            Write-Host " $Message"   -ForegroundColor White
        }
    }

    # ==========================================================================
    # CONSOLE PRESENTATION HELPERS
    # ==========================================================================
    function Write-Banner {
        param (
            [Parameter(Mandatory = $true)]  [string]$Title,
            [Parameter(Mandatory = $false)] [string]$Color = 'Cyan'
        )
        $Line = '=' * 60
        Write-Host ''
        Write-Host $Line      -ForegroundColor $Color
        Write-Host "  $Title" -ForegroundColor White
        Write-Host $Line      -ForegroundColor $Color
        Write-Host ''
    }

    function Write-Section {
        param (
            [Parameter(Mandatory = $true)]  [string]$Title,
            [Parameter(Mandatory = $false)] [string]$Color = 'Cyan'
        )
        $TitleStr = "---- $Title "
        $Padding  = '-' * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ''
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    function Write-Separator {
        param ([Parameter(Mandatory = $false)] [string]$Color = 'DarkGray')
        Write-Host ('-' * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # LOG SETUP
    # ==========================================================================
    function Initialize-Logging {
        if (-not (Test-Path -Path $LogFolder)) {
            try   { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
            catch { Write-Warning "Could not create log folder '$LogFolder': $_" }
        }

        try {
            $ExistingLogs = Get-ChildItem -Path $LogFolder -Filter "$($ScriptName)_*.log" |
                            Sort-Object -Property LastWriteTime -Descending

            if ($ExistingLogs.Count -ge $MaxLogFiles) {
                $ExistingLogs | Select-Object -Skip ($MaxLogFiles - 1) | ForEach-Object {
                    Remove-Item -Path $_.FullName -Force
                }
            }
        }
        catch { Write-Warning "Log rotation failed: $_" }
    }

    # ==========================================================================
    # IT GLUE - PASSWORD RETRIEVAL
    # Two REST calls: search by name, then show-password to reveal the value.
    # ==========================================================================
    function Get-ITGluePasswordValue {
        param (
            [string]$ApiKey,
            [string]$BaseUrl,
            [string]$OrgId,
            [string]$AssetName
        )

        Write-Log "Querying IT Glue for password asset: '$AssetName' (Org: $OrgId)"
        Write-Console "Querying IT Glue: '$AssetName'" -Severity INFO

        $Headers = @{
            'x-api-key'    = $ApiKey
            'Content-Type' = 'application/vnd.api+json'
        }

        $EncodedName = [Uri]::EscapeDataString($AssetName)
        $SearchUri   = "$BaseUrl/passwords?filter[organization_id]=$OrgId&filter[name]=$EncodedName&page[size]=10"

        try {
            $SearchResponse = Invoke-RestMethod -Uri $SearchUri -Headers $Headers -Method GET -ErrorAction Stop
        }
        catch {
            throw "IT Glue API search call failed: $_"
        }

        if (-not $SearchResponse.data -or $SearchResponse.data.Count -eq 0) {
            throw "No IT Glue password asset found matching '$AssetName' in Org $OrgId. Verify OrgId and asset name."
        }

        $Asset = $SearchResponse.data |
                 Where-Object { $_.attributes.name -eq $AssetName } |
                 Select-Object -First 1

        if (-not $Asset) { $Asset = $SearchResponse.data[0] }

        Write-Log "Found IT Glue asset: '$($Asset.attributes.name)' (ID: $($Asset.id))" -Severity DEBUG

        $ShowUri = "$BaseUrl/passwords/$($Asset.id)?show_password=true"
        try {
            $ShowResponse = Invoke-RestMethod -Uri $ShowUri -Headers $Headers -Method GET -ErrorAction Stop
        }
        catch {
            throw "IT Glue show-password call failed for asset ID '$($Asset.id)': $_"
        }

        $PasswordValue = $ShowResponse.data.attributes.password
        if (-not $PasswordValue) {
            throw "IT Glue returned an empty password value for asset '$AssetName'. Verify the asset's Password field is populated."
        }

        Write-Log "Successfully retrieved credential from IT Glue." -Severity SUCCESS
        Write-Console "IT Glue credential retrieved." -Severity SUCCESS
        return $PasswordValue
    }

    # ==========================================================================
    # GRAPH - TOKEN ACQUISITION
    # OAuth2 client_credentials flow.
    # ==========================================================================
    function Get-GraphAccessToken {
        param (
            [string]$TenantId,
            [string]$ClientId,
            [string]$ClientSecret
        )

        Write-Log "Requesting OAuth2 token from Azure AD (tenant: $TenantId)..."
        Write-Console "Authenticating to Microsoft Graph..." -Severity INFO

        $TokenUri  = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        $TokenBody = @{
            grant_type    = 'client_credentials'
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = 'https://graph.microsoft.com/.default'
        }

        try {
            $TokenResponse = Invoke-RestMethod -Uri $TokenUri -Method POST -Body $TokenBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        }
        catch {
            throw "Graph token acquisition failed: $_"
        }

        if (-not $TokenResponse.access_token) {
            throw "Token response did not contain an access_token. Verify TenantId, ClientId, and ClientSecret."
        }

        Write-Log "Graph token acquired. Expires in $($TokenResponse.expires_in)s." -Severity SUCCESS
        Write-Console "Graph token acquired." -Severity SUCCESS
        return $TokenResponse.access_token
    }

    # ==========================================================================
    # GRAPH - PAGED GET HELPER
    # Follows @odata.nextLink pages and returns all results as a flat array.
    # $Script:GraphHeaders is set after token acquisition.
    # ==========================================================================
    function Invoke-GraphPagedGet {
        param ([string]$Uri)

        $Results  = @()
        $NextLink = $Uri

        do {
            $Page     = Invoke-RestMethod -Uri $NextLink -Headers $Script:GraphHeaders -Method GET -ErrorAction Stop
            if ($Page.value) { $Results += $Page.value }
            $NextLink = $Page.'@odata.nextLink'
        } while ($NextLink)

        return $Results
    }

    # ==========================================================================
    # GRAPH - TENANT DOMAIN DISCOVERY
    # Returns an array of lowercase verified domain name strings for the tenant.
    # Used by the internal-sender safeguard.
    # ==========================================================================
    function Get-TenantDomains {
        Write-Log "Querying tenant verified domains..." -Severity DEBUG

        try {
            $DomainsResponse = Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/domains' -Headers $Script:GraphHeaders -Method GET -ErrorAction Stop
        }
        catch {
            throw "Failed to retrieve tenant domains from Graph: $_"
        }

        $VerifiedDomains = $DomainsResponse.value |
                           Where-Object { $_.isVerified -eq $true } |
                           ForEach-Object { $_.id.ToLower() }

        if (-not $VerifiedDomains -or $VerifiedDomains.Count -eq 0) {
            throw "No verified domains returned for tenant. Verify Graph permissions."
        }

        Write-Log "Tenant verified domains: $($VerifiedDomains -join ', ')" -Severity DEBUG
        return $VerifiedDomains
    }

    # ==========================================================================
    # GRAPH - MAIL FILTER BUILDER
    # Builds an OData $filter expression. Multiple criteria joined with OR.
    # ==========================================================================
    function Get-MailFilterExpression {
        param (
            [string]$Subject,
            [string]$Sender,
            [string]$MessageId
        )

        $Filters = @()

        if ($Subject) {
            $EscapedSubject = $Subject.Replace("'", "''")
            $Filters += "contains(subject,'$EscapedSubject')"
        }

        if ($Sender) {
            $EscapedSender = $Sender.Replace("'", "''")
            $Filters += "from/emailAddress/address eq '$EscapedSender'"
        }

        if ($MessageId) {
            $CleanMsgId   = $MessageId.Trim().TrimStart('<').TrimEnd('>')
            $EscapedMsgId = $CleanMsgId.Replace("'", "''")
            $Filters     += "internetMessageId eq '<$EscapedMsgId>'"
        }

        if ($Filters.Count -eq 0) { return $null }
        return $Filters -join ' or '
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    # Resolve effective operating mode up front for use throughout
    # AllowDelete gates whether deletion actually runs, regardless of Mode
    $EffectivelyDeleting = ($AllowDelete -eq 'true') -and ($RemediationMode -ne 'ReportOnly')
    $OverrideSafeguards  = ($AllowOverrideSafeguards -eq 'true')

    # --------------------------------------------------------------------------
    # Script startup - log header + console banner
    # --------------------------------------------------------------------------
    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site                   : $SiteName"              -Severity INFO
    Write-Log "Hostname               : $Hostname"              -Severity INFO
    Write-Log "Run As                 : $RunAs"                 -Severity INFO
    Write-Log "Remediation Mode       : $RemediationMode"       -Severity INFO
    Write-Log "Allow Delete           : $AllowDelete"           -Severity INFO
    Write-Log "Effectively Deleting   : $EffectivelyDeleting"   -Severity INFO
    Write-Log "Max Deletions Cap      : $MaxDeletions"          -Severity INFO
    Write-Log "Override Safeguards    : $AllowOverrideSafeguards" -Severity INFO
    Write-Log "Tenant ID              : $TenantId"              -Severity INFO
    Write-Log "Client ID              : $ClientId"              -Severity INFO
    Write-Log "IT Glue Org ID         : $ITGlueOrgId"           -Severity INFO
    Write-Log "Search - Subject       : $(if ($SearchSubject)   { $SearchSubject }   else { '(not set)' })" -Severity INFO
    Write-Log "Search - Sender        : $(if ($SearchSender)    { $SearchSender }    else { '(not set)' })" -Severity INFO
    Write-Log "Search - MsgID         : $(if ($SearchMessageId) { $SearchMessageId } else { '(not set)' })" -Severity INFO
    Write-Log "Max Mailboxes          : $MaxMailboxes"          -Severity INFO
    Write-Log "Log File               : $LogFile"               -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site             : $SiteName"             -Severity PLAIN
    Write-Console "Hostname         : $Hostname"             -Severity PLAIN
    Write-Console "Run As           : $RunAs"                -Severity PLAIN
    Write-Console "Remediation Mode : $RemediationMode"      -Severity PLAIN
    Write-Console "Allow Delete     : $AllowDelete"          -Severity PLAIN
    Write-Console "Max Deletions    : $MaxDeletions"         -Severity PLAIN
    Write-Console "Override Gates   : $AllowOverrideSafeguards" -Severity PLAIN
    Write-Console "Log File         : $LogFile"              -Severity PLAIN
    Write-Separator

    try {

        # ----------------------------------------------------------------------
        # PRE-FLIGHT VALIDATION
        # ----------------------------------------------------------------------
        Write-Section 'Pre-flight Validation'
        Write-Log 'Validating required parameters...' -Severity INFO
        Write-Console 'Validating required parameters...' -Severity INFO

        $MissingParams = @()
        if (-not $ITGlueApiKey) { $MissingParams += 'ITGlueApiKey' }
        if (-not $ITGlueOrgId)  { $MissingParams += 'ITGlueOrgId' }
        if (-not $TenantId)     { $MissingParams += 'TenantId' }
        if (-not $ClientId)     { $MissingParams += 'ClientId' }

        if (-not $SearchSubject -and -not $SearchSender -and -not $SearchMessageId) {
            $MissingParams += 'SearchCriteria (at least one of: SearchSubject, SearchSender, SearchMessageId)'
        }

        if ($MissingParams.Count -gt 0) {
            foreach ($P in $MissingParams) {
                Write-Log "Missing required parameter: $P" -Severity ERROR
                Write-Console "Missing required parameter: $P" -Severity ERROR
            }
            Write-Banner 'FATAL - MISSING PARAMETERS' -Color 'Red'
            exit 2
        }

        # Warn if deletion was requested but AllowDelete not set
        if ($RemediationMode -ne 'ReportOnly' -and $AllowDelete -ne 'true') {
            Write-Log "RemediationMode is '$RemediationMode' but AllowDelete is not 'true'. Running as ReportOnly." -Severity WARN
            Write-Console "AllowDelete not set - running ReportOnly regardless of RemediationMode." -Severity WARN
        }

        Write-Log 'All required parameters present.' -Severity SUCCESS
        Write-Console 'All required parameters present.' -Severity SUCCESS

        # ----------------------------------------------------------------------
        # STAGE 1 - Retrieve client secret from IT Glue
        # ----------------------------------------------------------------------
        Write-Section 'Stage 1 - IT Glue Credential Retrieval'
        Write-Log 'Retrieving App Registration secret from IT Glue...' -Severity INFO

        $ClientSecret = Get-ITGluePasswordValue `
            -ApiKey    $ITGlueApiKey `
            -BaseUrl   $ITGlueBaseUrl `
            -OrgId     $ITGlueOrgId `
            -AssetName $ITGluePasswordAssetName

        # ----------------------------------------------------------------------
        # STAGE 2 - Authenticate to Microsoft Graph
        # ----------------------------------------------------------------------
        Write-Section 'Stage 2 - Microsoft Graph Authentication'

        $GraphToken = Get-GraphAccessToken `
            -TenantId     $TenantId `
            -ClientId     $ClientId `
            -ClientSecret $ClientSecret

        $Script:GraphHeaders = @{
            'Authorization' = "Bearer $GraphToken"
            'Content-Type'  = 'application/json'
        }

        # Clear secret from memory immediately after token is acquired
        $ClientSecret = $null

        # ----------------------------------------------------------------------
        # STAGE 2.5 - Tenant domain discovery
        # Query Graph for verified domains before anything else. Used by the
        # internal-sender safeguard in Stage 6. Runs even in ReportOnly so the
        # check is always active and visible in the report output.
        # ----------------------------------------------------------------------
        Write-Section 'Stage 2.5 - Tenant Domain Discovery'
        Write-Log 'Retrieving tenant verified domains for internal-sender check...' -Severity INFO
        Write-Console 'Retrieving tenant domains...' -Severity INFO

        $TenantDomains = Get-TenantDomains

        Write-Log "Verified tenant domains ($($TenantDomains.Count)): $($TenantDomains -join ', ')" -Severity SUCCESS
        Write-Console "Tenant domains ($($TenantDomains.Count)): $($TenantDomains -join ', ')" -Severity SUCCESS

        # Note if MessageId-only search - sender won't be known until we have
        # the actual messages, so we defer the check to post-collection
        if (-not $SearchSender -and -not $SearchSubject -and $SearchMessageId) {
            Write-Log 'Search is MessageId-only. Internal-sender check will run post-collection against actual message data.' -Severity WARN
            Write-Console 'MessageId-only search - internal-sender check runs post-collection.' -Severity WARN
        }

        # ----------------------------------------------------------------------
        # STAGE 3 - Enumerate tenant mailboxes
        # ----------------------------------------------------------------------
        Write-Section 'Stage 3 - Mailbox Enumeration'
        Write-Log 'Fetching all enabled users with mailboxes from tenant...' -Severity INFO
        Write-Console 'Enumerating tenant mailboxes...' -Severity INFO

        $UsersUri = "https://graph.microsoft.com/v1.0/users?`$select=id,userPrincipalName,displayName,mail&`$filter=accountEnabled eq true&`$top=999"

        try {
            $AllUsers = Invoke-GraphPagedGet -Uri $UsersUri
        }
        catch {
            throw "Failed to enumerate tenant users. Verify User.Read.All permission is granted: $_"
        }

        $MailboxUsers = $AllUsers | Where-Object { $_.mail -or $_.userPrincipalName -like '*@*' }

        if (-not $MailboxUsers -or $MailboxUsers.Count -eq 0) {
            throw "No mailbox users found in tenant. Verify User.Read.All application permission and admin consent."
        }

        Write-Log "Found $($MailboxUsers.Count) mailbox-enabled users in tenant." -Severity SUCCESS
        Write-Console "Found $($MailboxUsers.Count) mailbox users." -Severity SUCCESS

        if ($MailboxUsers.Count -gt $MaxMailboxes) {
            Write-Log "User count ($($MailboxUsers.Count)) exceeds MaxMailboxes cap ($MaxMailboxes). Processing first $MaxMailboxes only." -Severity WARN
            Write-Console "User count exceeds MaxMailboxes cap. Truncating to $MaxMailboxes." -Severity WARN
            $MailboxUsers = $MailboxUsers | Select-Object -First $MaxMailboxes
        }

        # ----------------------------------------------------------------------
        # STAGE 4 - Build OData search filter
        # ----------------------------------------------------------------------
        Write-Section 'Stage 4 - Building Message Search Filter'

        $ODataFilter = Get-MailFilterExpression `
            -Subject   $SearchSubject `
            -Sender    $SearchSender `
            -MessageId $SearchMessageId

        if (-not $ODataFilter) {
            throw "Could not build OData filter - no search criteria resolved."
        }

        Write-Log "OData filter: $ODataFilter" -Severity DEBUG
        Write-Console "OData filter: $ODataFilter" -Severity DEBUG

        # ----------------------------------------------------------------------
        # STAGE 5 - Search ALL mailboxes, collect full result set
        # No deletions happen in this stage. Every mailbox is searched and all
        # matches are collected so the safety checks in Stage 6 can evaluate
        # the complete picture before a single message is touched.
        # ----------------------------------------------------------------------
        Write-Section 'Stage 5 - Tenant-Wide Search (Collect All Results)'
        Write-Log 'Searching all mailboxes. No action taken until Stage 6 safety checks pass.' -Severity INFO
        Write-Console 'Searching all mailboxes...' -Severity INFO

        # PS 5.1-compatible list construction (avoid ::new() syntax)
        $AllMatches   = New-Object -TypeName 'System.Collections.Generic.List[PSObject]'
        $TotalErrors  = 0
        $MailboxIndex = 0

        foreach ($User in $MailboxUsers) {
            $MailboxIndex++
            $UPN = if ($User.userPrincipalName) { $User.userPrincipalName } else { $User.mail }

            Write-Log "[$MailboxIndex/$($MailboxUsers.Count)] Searching: $UPN" -Severity DEBUG
            Write-Console "[$MailboxIndex/$($MailboxUsers.Count)] $UPN" -Severity INFO

            $EncodedFilter = [Uri]::EscapeDataString($ODataFilter)
            $SearchUri     = "https://graph.microsoft.com/v1.0/users/$($User.id)/messages?`$filter=$EncodedFilter&`$select=id,subject,from,receivedDateTime,internetMessageId&`$top=50"

            try {
                $Messages = Invoke-GraphPagedGet -Uri $SearchUri
            }
            catch {
                Write-Log "Failed to search mailbox for '$UPN': $_" -Severity WARN
                Write-Console "Failed to search mailbox for '$UPN'" -Severity WARN -Indent 1
                $TotalErrors++
                continue
            }

            if (-not $Messages -or $Messages.Count -eq 0) { continue }

            Write-Log "Found $($Messages.Count) match(es) in $UPN" -Severity INFO
            Write-Console "Found $($Messages.Count) match(es)" -Severity INFO -Indent 1

            foreach ($Msg in $Messages) {
                # Extract sender domain for internal-sender check
                $FromAddress = $Msg.from.emailAddress.address
                $FromDomain  = ($FromAddress -split '@' | Select-Object -Last 1).ToLower()

                $AllMatches.Add([PSCustomObject]@{
                    UserPrincipalName = $UPN
                    UserId            = $User.id
                    DisplayName       = $User.displayName
                    MessageId         = $Msg.internetMessageId
                    Subject           = $Msg.subject
                    From              = $FromAddress
                    FromDomain        = $FromDomain
                    ReceivedDateTime  = $Msg.receivedDateTime
                    GraphId           = $Msg.id
                    Result            = 'Pending'
                    SafeguardFlags    = ''
                })
            }
        }

        Write-Log "Search complete. Total matches: $($AllMatches.Count) across $MailboxIndex mailboxes scanned." -Severity INFO
        Write-Console "Search complete. Total matches: $($AllMatches.Count)" -Severity INFO

        # ----------------------------------------------------------------------
        # ZERO MATCH - Clean exit, not an error
        # ----------------------------------------------------------------------
        if ($AllMatches.Count -eq 0) {
            Write-Log 'No matching messages found across all scanned mailboxes.' -Severity SUCCESS
            Write-Log 'Clean result - the email may already be deleted or search criteria did not match.' -Severity INFO
            Write-Console 'No matching messages found.' -Severity SUCCESS
            Write-Banner 'COMPLETED - NO MATCHES FOUND' -Color 'Cyan'
            exit 0
        }

        # ----------------------------------------------------------------------
        # STAGE 6 - SAFETY CHECKS
        # All checks evaluate the complete AllMatches collection. Any hard-stop
        # violation exits 2 without touching a single message.
        # ----------------------------------------------------------------------
        Write-Section 'Stage 6 - Safety Checks'
        Write-Log "Running safety checks against $($AllMatches.Count) match(es)..." -Severity INFO
        Write-Console "Running safety checks against $($AllMatches.Count) match(es)..." -Severity INFO

        # PS 5.1-compatible list construction
        $SafeguardViolations = New-Object -TypeName 'System.Collections.Generic.List[string]'
        $SafeguardWarnings   = New-Object -TypeName 'System.Collections.Generic.List[string]'

        # ------------------------------------------------------------------
        # CHECK 1 - Multiple matches per mailbox
        # Build a count per UPN. Any mailbox with >1 match is flagged.
        # In delete modes this is a hard stop unless overridden.
        # In ReportOnly it is a warning - the report continues.
        # ------------------------------------------------------------------
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
                $FlagMsg = "MULTI-MATCH: $($MB.Value) messages matched in mailbox $($MB.Key)"
                Write-Log $FlagMsg -Severity WARN
                Write-Console $FlagMsg -Severity WARN -Indent 1
            }

            # Tag the affected match entries
            $MatchIndex = 0
            foreach ($Match in $AllMatches) {
                if ($MatchesByMailbox[$Match.UserPrincipalName] -gt 1) {
                    $AllMatches[$MatchIndex].SafeguardFlags += '[MULTI-MATCH]'
                }
                $MatchIndex++
            }

            $MultiCount   = $MultiMatchMailboxes | Measure-Object | Select-Object -ExpandProperty Count
            $ViolationMsg = "$MultiCount mailbox(es) contain more than one matching message. Expected one match per mailbox for a targeted hunt."

            if ($EffectivelyDeleting -and -not $OverrideSafeguards) {
                $SafeguardViolations.Add($ViolationMsg)
            }
            else {
                # ReportOnly or explicitly overridden - warn but don't stop
                $SafeguardWarnings.Add($ViolationMsg)
            }
        }

        # ------------------------------------------------------------------
        # CHECK 2 - Internal sender domain
        # Compare each match's From domain against the tenant's verified
        # domains. Internal mail hitting the search criteria is almost always
        # a false positive or a misconfigured search.
        # ------------------------------------------------------------------
        $InternalMatches = $AllMatches | Where-Object { $TenantDomains -contains $_.FromDomain }

        if ($InternalMatches) {

            foreach ($IM in $InternalMatches) {
                $FlagMsg = "INTERNAL SENDER: '$($IM.From)' (domain '$($IM.FromDomain)') is a verified tenant domain - mailbox: $($IM.UserPrincipalName)"
                Write-Log $FlagMsg -Severity WARN
                Write-Console $FlagMsg -Severity WARN -Indent 1
            }

            # Tag the affected match entries
            $MatchIndex = 0
            foreach ($Match in $AllMatches) {
                if ($TenantDomains -contains $Match.FromDomain) {
                    $AllMatches[$MatchIndex].SafeguardFlags += '[INTERNAL-SENDER]'
                }
                $MatchIndex++
            }

            $InternalCount = $InternalMatches | Measure-Object | Select-Object -ExpandProperty Count
            $ViolationMsg  = "$InternalCount match(es) have a sender address from a verified tenant domain. Deleting internal mail requires AllowOverrideSafeguards."

            if ($EffectivelyDeleting -and -not $OverrideSafeguards) {
                $SafeguardViolations.Add($ViolationMsg)
            }
            else {
                $SafeguardWarnings.Add($ViolationMsg)
            }
        }

        # ------------------------------------------------------------------
        # CHECK 3 - MaxDeletions cap
        # Hard stop if match count exceeds the cap. Not bypassable with
        # AllowOverrideSafeguards - operator must raise MaxDeletions explicitly.
        # Only enforced when actually deleting.
        # ------------------------------------------------------------------
        if ($EffectivelyDeleting -and $AllMatches.Count -gt $MaxDeletions) {
            $ViolationMsg = "Total match count ($($AllMatches.Count)) exceeds MaxDeletions cap ($MaxDeletions). Raise -MaxDeletions to proceed."
            Write-Log $ViolationMsg -Severity ERROR
            Write-Console $ViolationMsg -Severity ERROR
            $SafeguardViolations.Add($ViolationMsg)
        }

        # ------------------------------------------------------------------
        # Evaluate - hard stop if any violations
        # ------------------------------------------------------------------
        if ($SafeguardViolations.Count -gt 0) {
            Write-Log '' -Severity INFO
            Write-Log '*** SAFETY GATE TRIPPED - NO MESSAGES DELETED ***' -Severity ERROR
            foreach ($V in $SafeguardViolations) {
                Write-Log "  VIOLATION: $V" -Severity ERROR
                Write-Console "VIOLATION: $V" -Severity ERROR
            }
            Write-Log 'Use -AllowOverrideSafeguards true to bypass multi-match and internal-sender checks.' -Severity ERROR
            Write-Log 'MaxDeletions cap can only be raised via the -MaxDeletions parameter.' -Severity ERROR
            Write-Banner 'HALTED - SAFETY GATE TRIPPED' -Color 'Red'
            exit 2
        }

        if ($SafeguardWarnings.Count -gt 0) {
            Write-Log '' -Severity INFO
            Write-Log '*** SAFEGUARD WARNINGS - PROCEEDING ***' -Severity WARN
            foreach ($W in $SafeguardWarnings) {
                Write-Log "  WARNING: $W" -Severity WARN
                Write-Console "WARNING: $W" -Severity WARN
            }
        }

        Write-Log 'All safety checks passed.' -Severity SUCCESS
        Write-Console 'Safety checks passed.' -Severity SUCCESS

        # ----------------------------------------------------------------------
        # STAGE 7 - Remediation
        # Safety checks passed. Now act on each match per mode.
        # ----------------------------------------------------------------------
        Write-Section 'Stage 7 - Remediation'

        $TotalDeleted = 0

        $MatchIndex = 0
        foreach ($Match in $AllMatches) {
            $FlagSuffix = if ($Match.SafeguardFlags) { " $($Match.SafeguardFlags)" } else { '' }

            # ReportOnly path (mode is ReportOnly, or AllowDelete was not set)
            if (-not $EffectivelyDeleting) {
                Write-Log "[REPORT ONLY]$FlagSuffix '$($Match.Subject)' | From: $($Match.From) | Mailbox: $($Match.UserPrincipalName)" -Severity INFO
                Write-Console "[REPORT]$FlagSuffix '$($Match.Subject)'" -Severity INFO -Indent 1
                $AllMatches[$MatchIndex].Result = 'ReportOnly'
                $MatchIndex++
                continue
            }

            # Build delete request based on mode
            if ($RemediationMode -eq 'HardDelete') {
                # POST to permanentDelete - irreversible, bypasses Recoverable Items
                $DeleteUri    = "https://graph.microsoft.com/v1.0/users/$($Match.UserId)/messages/$($Match.GraphId)/permanentDelete"
                $DeleteMethod = 'POST'
                $DeleteBody   = '{}'
            }
            else {
                # SoftDelete - HTTP DELETE moves to Deleted Items folder (~30 days recoverable)
                $DeleteUri    = "https://graph.microsoft.com/v1.0/users/$($Match.UserId)/messages/$($Match.GraphId)"
                $DeleteMethod = 'DELETE'
                $DeleteBody   = $null
            }

            if ($PSCmdlet.ShouldProcess($Match.UserPrincipalName, "$RemediationMode '$($Match.Subject)'")) {
                try {
                    $InvokeParams = @{
                        Uri     = $DeleteUri
                        Headers = $Script:GraphHeaders
                        Method  = $DeleteMethod
                    }
                    if ($DeleteBody) { $InvokeParams['Body'] = $DeleteBody }

                    Invoke-RestMethod @InvokeParams -ErrorAction Stop | Out-Null

                    $TotalDeleted++
                    $AllMatches[$MatchIndex].Result = 'Deleted'
                    Write-Log "[$RemediationMode]$FlagSuffix Deleted '$($Match.Subject)' in $($Match.UserPrincipalName)" -Severity SUCCESS
                    Write-Console "Deleted '$($Match.Subject)'" -Severity SUCCESS -Indent 1
                }
                catch {
                    $TotalErrors++
                    $AllMatches[$MatchIndex].Result = "Failed: $_"
                    Write-Log "Failed to delete '$($Match.Subject)' in $($Match.UserPrincipalName): $_" -Severity ERROR
                    Write-Console "Delete failed: $_" -Severity ERROR -Indent 1
                }
            }

            $MatchIndex++
        }

        # ----------------------------------------------------------------------
        # STAGE 8 - Summary
        # All output via Write-Log so it surfaces in the DattoRMM job log.
        # ----------------------------------------------------------------------
        Write-Section 'Stage 8 - Summary'

        Write-Log '----------- REMEDIATION SUMMARY -----------' -Severity INFO
        Write-Log "Remediation Mode     : $RemediationMode"     -Severity INFO
        Write-Log "Allow Delete         : $AllowDelete"         -Severity INFO
        Write-Log "Override Safeguards  : $AllowOverrideSafeguards" -Severity INFO
        Write-Log "Mailboxes Scanned    : $MailboxIndex"        -Severity INFO
        Write-Log "Messages Found       : $($AllMatches.Count)" -Severity INFO
        Write-Log "Messages Deleted     : $TotalDeleted"        -Severity $(if ($TotalDeleted -gt 0) { 'SUCCESS' } else { 'INFO' })
        Write-Log "Safeguard Violations : $($SafeguardViolations.Count)" -Severity INFO
        Write-Log "Safeguard Warnings   : $($SafeguardWarnings.Count)"   -Severity $(if ($SafeguardWarnings.Count -gt 0) { 'WARN' } else { 'INFO' })
        Write-Log "Search Errors        : $TotalErrors"         -Severity $(if ($TotalErrors -gt 0) { 'WARN' } else { 'INFO' })
        Write-Log '-------------------------------------------' -Severity INFO

        Write-Log 'Match Details:' -Severity INFO
        foreach ($Match in $AllMatches) {
            Write-Log "  UPN      : $($Match.UserPrincipalName)"  -Severity INFO
            Write-Log "  Subject  : $($Match.Subject)"            -Severity INFO
            Write-Log "  From     : $($Match.From)"               -Severity INFO
            Write-Log "  Received : $($Match.ReceivedDateTime)"   -Severity INFO
            Write-Log "  Flags    : $(if ($Match.SafeguardFlags) { $Match.SafeguardFlags } else { 'none' })" `
                      -Severity $(if ($Match.SafeguardFlags) { 'WARN' } else { 'INFO' })
            Write-Log "  Result   : $($Match.Result)" `
                      -Severity $(if ($Match.Result -eq 'Deleted') { 'SUCCESS' } elseif ($Match.Result -like 'Failed*') { 'ERROR' } else { 'INFO' })
            Write-Log '  ---' -Severity INFO
        }

        if ($TotalErrors -gt 0) {
            Write-Log "Completed with $TotalErrors search error(s). Review output above." -Severity WARN
            Write-Banner 'COMPLETED WITH ERRORS' -Color 'Yellow'
            exit 1
        }
        else {
            Write-Log 'Script completed successfully.' -Severity SUCCESS
            Write-Banner 'COMPLETED SUCCESSFULLY' -Color 'Green'
            exit 0
        }

    }
    catch {
        Write-Log "Unhandled exception: $_"             -Severity ERROR
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Banner 'SCRIPT FAILED' -Color 'Red'
        Write-Console "Error: $_" -Severity ERROR
        exit 1
    }

} # End function Invoke-MailRemediation

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    ITGlueApiKey            = $ITGlueApiKey
    ITGlueBaseUrl           = $ITGlueBaseUrl
    ITGlueOrgId             = $ITGlueOrgId
    ITGluePasswordAssetName = $ITGluePasswordAssetName
    TenantId                = $TenantId
    ClientId                = $ClientId
    SearchSubject           = $SearchSubject
    SearchSender            = $SearchSender
    SearchMessageId         = $SearchMessageId
    RemediationMode         = $RemediationMode
    AllowDelete             = $AllowDelete
    MaxMailboxes            = $MaxMailboxes
    MaxDeletions            = $MaxDeletions
    AllowOverrideSafeguards = $AllowOverrideSafeguards
    SiteName                = $SiteName
    Hostname                = $Hostname
}

Invoke-MailRemediation @ScriptParams
