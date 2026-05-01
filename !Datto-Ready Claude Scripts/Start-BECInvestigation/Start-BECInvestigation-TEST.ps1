#Requires -Version 5.1
<#
.SYNOPSIS
    Initializes a BEC (Business Email Compromise) investigation workspace for a
    compromised Microsoft 365 user account.

.DESCRIPTION
    Start-BECInvestigation creates a complete, self-contained investigation workspace
    for a BEC incident. It generates a timestamped folder structure, an XML
    configuration file that tracks investigation state and all relevant paths, and
    three investigation scripts pre-configured with the victim's details:

        Invoke-BECDataCollection.ps1       - Collects Exchange + Graph forensic data
        Invoke-BECLogAnalysis.ps1          - Analyzes data and produces findings + timeline
        Invoke-BECMessageTraceRetrieval.ps1 - Retrieves completed historical traces

    This script is designed for interactive use by Databranch technicians on their
    local workstations. It does not connect to Exchange Online or Graph - all cloud
    work is handled by the generated scripts.

    The investigation workflow assumes remediation (account lockdown) is performed
    in the CIPP portal via Compromise Remediation, NOT by this script or its
    generated scripts. This tool focuses exclusively on forensic evidence collection
    and analysis.

    Workspace folder structure:
        BEC-Investigation_<alias>_<timestamp>/
            Investigation.xml                 (auto-managed config)
            Investigation-README.txt          (per-investigation quick reference)
            Scripts/
                Invoke-BECDataCollection.ps1
                Invoke-BECLogAnalysis.ps1
                Invoke-BECMessageTraceRetrieval.ps1
            RawData/                          (collected CSV files)
            Reports/                          (flagged suspicious artifacts)
            Analysis/                         (reports, timeline, evidence manifest)
            Logs/                             (per-run transcripts)

.PARAMETER VictimEmail
    Required. The full email address (UPN) of the compromised user.
    Must match the format user@domain.com.

.PARAMETER WorkingDirectory
    Optional. The root directory where the investigation workspace folder will be
    created. Defaults to C:\Databranch_BEC. The directory is created if it does
    not exist.

.PARAMETER IncidentTicket
    Optional. The ConnectWise Manage ticket number associated with this incident.
    Stored in Investigation.xml for reference and included in generated script headers.

.PARAMETER Technician
    Optional. Name of the technician running the investigation. Defaults to the
    current Windows username ($env:USERNAME). Stored in Investigation.xml.

.PARAMETER LookbackHours
    Optional. Default lookback window for the generated data collection script,
    in hours. Can be overridden when running Invoke-BECDataCollection.ps1.
    Default: 0 (means "use -Scope instead").

.PARAMETER Scope
    Optional. Default named lookback preset for the generated data collection script:
      Recent   = 72 hours (3 days)   - DEFAULT, matches Huntress-driven workflow
      Standard = 168 hours (7 days)
      Extended = 720 hours (30 days)
      Maximum  = 2160 hours (90 days)

.EXAMPLE
    .\Start-BECInvestigation.ps1 -VictimEmail "john.doe@clientdomain.com"
    Minimal invocation. Creates workspace under C:\Databranch_BEC with Recent (72h) default scope.

.EXAMPLE
    .\Start-BECInvestigation.ps1 -VictimEmail "john.doe@clientdomain.com" `
                                  -WorkingDirectory "D:\Investigations" `
                                  -IncidentTicket "INC-20458" `
                                  -Technician "Sam Kirsch" `
                                  -Scope "Extended"
    Full invocation with 30-day default scope.

.NOTES
    File Name      : Start-BECInvestigation.ps1
    Version        : 4.0.3.0
    Author         : Sam Kirsch
    Contributors   : Sam Kirsch
    Company        : Databranch
    Created        : 2024-02-15
    Last Modified  : 2026-04-18
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : Interactive - Technician workstation (local user context)
    DattoRMM       : Not applicable - interactive use only
    Client Scope   : All clients

    Exit Codes:
        0  - Workspace created successfully
        1  - Runtime failure (folder/XML/script generation failed)
        2  - Fatal pre-flight failure (bad parameters)

.CHANGELOG
    v4.0.3.0 - 2026-05-01 - Sam Kirsch
        - Auto-detect and recover from WAM (Web Account Manager) logon-session
          error 0x80070520 when calling Connect-ExchangeOnline. Microsoft Learn
          documents this exact failure mode for ANY Connect-ExchangeOnline
          call where the PowerShell process runs in a different Windows logon
          session than the interactive desktop user (Run-As elevation,
          Server Core, Task Scheduler with "Run whether logged on or not",
          ScreenConnect Backstage). The script now catches the specific error
          signature and auto-retries with -DisableWAM, eliminating the need
          for the tech to abort, change shell context, and start over.
        - New -DisableWAM switch on Invoke-BECDataCollection.ps1 and
          Invoke-BECMessageTraceRetrieval.ps1 to force WAM-disabled connect
          up front (skips initial WAM attempt).
        - When auto-fallback fires, an info banner reminds the tech that
          their PS context is mismatched with their Windows session and
          how to fix that for future runs.
        - Reference: Microsoft Learn "Resolve Issues in Exchange Online
          PowerShell Module after WAM Integration"

    v4.0.2.0 - 2026-04-18 - Sam Kirsch
        - Updated workflow instructions to reflect PowerShell 5.1 / PowerShell 7 split.
          Field testing confirmed Microsoft's official recommendation: PS7 is the
          recommended edition for the Microsoft Graph SDK. ExchangeOnlineManagement
          works fine in PS5.1; Graph SDK does not reliably.
        - README Step 1a now labeled [PowerShell 5.1], Step 1b [PowerShell 7] with
          winget install hint and "return to PS5 window" guidance
        - Invoke-BECGraphCollection.ps1 detects PSEdition at startup and warns
          loudly if running Desktop (5.1), recommending opening pwsh instead
        - Graph connect-failure error message now branches on PS edition
        - Master workspace-created banner shows 3-section Next Steps with shell
          switch instructions
        - NO LOGIC CHANGES - all updates are to instruction blocks / banners only

    v4.0.1.0 - 2026-04-18 - Sam Kirsch
        - Split Microsoft Graph collection into separate script (Invoke-BECGraphCollection.ps1)
          to work around the MSAL/WAM assembly conflict between ExchangeOnlineManagement
          and Microsoft.Graph.* modules documented in msgraph-sdk-powershell GitHub
          issue #3576. Microsoft's official workaround is "execute commands for one of
          these modules in a separate PowerShell session."
        - Invoke-BECDataCollection.ps1 now Exchange-only, force-disconnects EXO at end
        - Invoke-BECGraphCollection.ps1 defensively disconnects EXO at startup and warns
          user to open a fresh console if Graph auth fails anyway
        - XML schema: added <GraphCollection> sibling with Completed, CompletedDate fields
        - TLS 1.2 block moved below param() in all 4 generated scripts + master
          (fixes crash - CmdletBinding must be the first executable statement)
        - Template compliance bumped to v1.4.1.0 alongside Invoke-ScriptTemplate update
        - README (Investigation-README.txt) updated with new Step 1b for Graph collection

    v4.0.0.0 - 2026-04-18 - Sam Kirsch
        - MAJOR version bump - workflow and tooling overhaul

        WORKFLOW:
        - Repositioned as evidence-collection + analysis tool only
        - Remediation now handled via CIPP Compromise Remediation (NOT this script)
        - Investigation-README.txt rewritten with CIPP-first workflow (Step 0)

        NEW DATA SOURCES (Microsoft Graph):
        - Entra ID sign-in logs (interactive + non-interactive, with IP/location/risk)
        - Risky users and risk detections
        - User authentication methods (MFA)
        - Directory role memberships
        - OAuth permission grants and enterprise applications
        - Conditional Access policies

        NEW DATA SOURCES (Unified Audit Log):
        - Rule manipulation events (create/modify/delete with full history)
        - Send operations (outbound mail events)
        - MailItemsAccessed (best-effort, requires Purview Audit Standard+)
        - SharePoint/OneDrive file downloads (exfiltration indicator)
        - Login events (UserLoggedIn, UserLoginFailed)
        - MFA/auth method changes
        - Directory role add/remove events
        - Conditional Access policy changes
        - OAuth consent events

        NEW ANALYZER DETECTIONS:
        - Impossible travel (cross-country signins within impossibly short time)
        - Session ID reuse across IPs (AiTM / token theft indicator)
        - New MFA device registered during window
        - New OAuth consents granted by victim during window
        - Admin role assignments involving victim during window
        - Rule manipulation timeline (correlates create/modify/delete events)
        - Common attacker rule name patterns (single chars, financial keywords)
        - CA policy modifications during window
        - MailItemsAccessed Sync events (full mailbox download indicator)
        - MailItemsAccessed throttling (assume worst-case full exposure)
        - Bulk SharePoint/OneDrive file downloads
        - Service principals created during window (OAuth phishing indicator)
        - Risk detection correlation (AiTM, anomalous token, leaked credentials)

        NEW OUTPUTS:
        - Analysis\Timeline.csv - consolidated chronological event timeline
          across all data sources (UAL + Graph sign-ins + Risk + UAL ops)
        - Analysis\Evidence-Manifest.csv - SHA-256 hashes of every artifact
          plus Evidence-Manifest-README.txt explaining how to verify
        - Dual-timestamp columns (UTC + Eastern) on every CSV with time fields

        PARAMETER CHANGES:
        - New -LookbackHours parameter (custom hours) on all scripts
        - New -Scope parameter with Recent/Standard/Extended/Maximum presets
        - New -SkipGraph switch on data collection
        - XML DataCollection.DaysSearched replaced by LookbackHours + Window fields

        INFRASTRUCTURE:
        - Auto-update of ExchangeOnlineManagement to 3.7.0+ (required for V2 traces)
        - Auto-install of Microsoft.Graph.* submodules
        - Microsoft Graph interactive OAuth connection (browser popup)
        - Dropped Get-MessageTrace V1 fallback (Reporting Webservice EOL 2026-04-08)
        - Dropped Get-MessageTraceDetail (deprecated alongside V1)
        - Dynamic time-window compression on UAL 5000-record cap
        - Proper session paging with SessionCommand ReturnLargeSet
        - StartingRecipientAddress cursor pagination for Get-MessageTraceV2

        STANDARDS COMPLIANCE (template v1.4.0.0):
        - TLS 1.2 enforcement block on all four scripts
        - Exit codes standardized 0 (success) / 1 (runtime) / 2 (fatal preflight)
        - Dual-output pattern (Write-Log for file/stdout, Write-Console for display)
        - Standard Write-Banner / Write-Section / Write-Separator helpers
        - Full .NOTES blocks with Contributors and Modified By populated
        - ASCII-only (tree-drawing characters removed from descriptions)
        - Pre-flight validation with exit 2 on fatal failure

    v3.0.2.0 - 2026-02-21 - Sam Kirsch
        - Two-channel logging in all scripts: colorized Write-Host to console,
          structured entries captured by Start-Transcript in generated scripts
        - Write-Banner and Write-Section helpers for formatted console output
        - Analysis script: completion banner shows severity counts color-coded
        - Unified audit log collection: 7-day chunked windows with retry per chunk

    v3.0.1.0 - 2026-02-20 - Sam Kirsch
        - Fixed Add-XmlElement type check for [ordered]@{} sections
        - Added null-guard validation in all three generated scripts after XML read
        - Fixed Get-ConnectionInformation call for NotifyAddress
        - Made NotifyAddress optional in Start-HistoricalSearch via splatting
        - Moved Start-Transcript calls in generated scripts to after XML validation

    v3.0.0.0 - 2026-02-20 - Sam Kirsch
        - Renamed from Start-Investigation.ps1 to Start-BECInvestigation.ps1
        - Wrapped all logic in master function Start-BECInvestigation
        - Added #Requires -Version 5.1
        - Added full compliant .NOTES and .CHANGELOG header block
        - Generated scripts renamed to Verb-Noun format
        - Entry point converted to splatted parameter call

    v2.3.0.0 - 2024-02-15 - Sam Kirsch
        - Analysis script: detects MoveToFolder, DeleteMessage, MarkAsRead rules
        - Improved severity classification (CRITICAL/HIGH/MEDIUM/LOW)

    v2.0.0.0 - 2024-02-01 - Sam Kirsch
        - Redesigned as single-script deployment model
        - XML-based configuration management
        - All three investigation scripts auto-generated per investigation

    v1.0.0.0 - 2024-01-10 - Sam Kirsch
        - Initial release (manual multi-script workflow)
#>

# ==============================================================================
# PARAMETERS
# Interactive technician tool - no DattoRMM environment variable fallback.
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[^@]+@[^@]+\.[^@]+$")]
    [string]$VictimEmail,

    [Parameter(Mandatory = $false)]
    [string]$WorkingDirectory = "C:\Databranch_BEC",

    [Parameter(Mandatory = $false)]
    [string]$IncidentTicket = "",

    [Parameter(Mandatory = $false)]
    [string]$Technician = $env:USERNAME,

    [Parameter(Mandatory = $false)]
    [int]$LookbackHours = 0,

    [Parameter(Mandatory = $false)]
    [ValidateSet('', 'Recent', 'Standard', 'Extended', 'Maximum')]
    [string]$Scope = 'Recent'
)

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# Must be AFTER param() so CmdletBinding remains the first executable statement.
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Start-BECInvestigation {
    <#
    .SYNOPSIS
        Internal master function. See script-level help for full documentation.
    #>
    [CmdletBinding()]
    param (
        [string]$VictimEmail,
        [string]$WorkingDirectory,
        [string]$IncidentTicket,
        [string]$Technician,
        [int]$LookbackHours,
        [string]$Scope
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Start-BECInvestigation"
    $ScriptVersion = "4.0.3.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path -Path $LogRoot -ChildPath $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path -Path $LogFolder -ChildPath "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # Scope preset lookup (for README display only - generated scripts have their own copy)
    $ScopePresets = @{
        'Recent'   = 72
        'Standard' = 168
        'Extended' = 720
        'Maximum'  = 2160
    }

    # ==========================================================================
    # LOGGING FUNCTIONS (dual-output pattern)
    # ==========================================================================
    function Write-Log {
        param (
            [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Message = "",
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
            [string]$Severity = "INFO"
        )
        $Ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Entry = "[$Ts] [$Severity] $Message"
        switch ($Severity) {
            "INFO"    { Write-Output  $Entry }
            "WARN"    { Write-Warning $Entry }
            "ERROR"   { Write-Error   $Entry -ErrorAction Continue }
            "SUCCESS" { Write-Output  $Entry }
            "DEBUG"   { Write-Output  $Entry }
        }
        try {
            Add-Content -Path $LogFile -Value $Entry -Encoding UTF8
        }
        catch {
            Write-Warning "Could not write to log file: $_"
        }
    }

    function Write-Console {
        param (
            [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Message = "",
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG","PLAIN")]
            [string]$Severity = "PLAIN",
            [Parameter(Mandatory = $false)] [int]$Indent = 0
        )
        $Prefix = "  " * $Indent
        $Colors = @{ INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; DEBUG="Magenta"; PLAIN="Gray" }
        $Color  = $Colors[$Severity]
        if ($Severity -eq "PLAIN") {
            Write-Host "$Prefix$Message" -ForegroundColor $Color
        }
        else {
            Write-Host "$Prefix" -NoNewline
            Write-Host "[$Severity]" -ForegroundColor $Color -NoNewline
            Write-Host " $Message" -ForegroundColor White
        }
    }

    function Write-Banner {
        param ([string]$Title, [string]$Color = "Cyan")
        $Line = "=" * 60
        Write-Host ""
        Write-Host $Line -ForegroundColor $Color
        Write-Host "  $Title" -ForegroundColor White
        Write-Host $Line -ForegroundColor $Color
        Write-Host ""
    }

    function Write-Section {
        param ([string]$Title, [string]$Color = "Cyan")
        $TitleStr = "---- $Title "
        $Padding  = "-" * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ""
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    function Write-Separator {
        param ([string]$Color = "DarkGray")
        Write-Host ("-" * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # LOG INITIALIZATION
    # ==========================================================================
    function Initialize-Logging {
        if (-not (Test-Path -Path $LogFolder)) {
            try { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
            catch { Write-Warning "Could not create log folder '$LogFolder': $_" }
        }
        try {
            $Existing = Get-ChildItem -Path $LogFolder -Filter "$($ScriptName)_*.log" |
                        Sort-Object -Property LastWriteTime -Descending
            if ($Existing.Count -ge $MaxLogFiles) {
                $Existing | Select-Object -Skip ($MaxLogFiles - 1) | ForEach-Object {
                    Remove-Item -Path $_.FullName -Force
                }
            }
        }
        catch {
            Write-Warning "Log rotation failed: $_"
        }
    }

    # ==========================================================================
    # XML HELPER
    # ==========================================================================
    function Add-XmlElement {
        param (
            [System.Xml.XmlElement]$Parent,
            [System.Collections.IDictionary]$Data
        )
        foreach ($Key in $Data.Keys) {
            $Element = $XmlDoc.CreateElement($Key)
            if ($Data[$Key] -is [System.Collections.IDictionary]) {
                Add-XmlElement -Parent $Element -Data $Data[$Key]
            }
            else {
                $Element.InnerText = [string]$Data[$Key]
            }
            $Parent.AppendChild($Element) | Out-Null
        }
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    # Pre-flight validation
    $MissingParams = @()
    if (-not $VictimEmail) { $MissingParams += 'VictimEmail' }
    if ($MissingParams.Count -gt 0) {
        foreach ($P in $MissingParams) {
            Write-Log     "Missing required parameter: $P" -Severity ERROR
            Write-Console "Missing required parameter: $P" -Severity ERROR
        }
        Write-Banner -Title "FATAL - MISSING PARAMETERS" -Color Red
        exit 2
    }

    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Run As   : $RunAs"                       -Severity INFO
    Write-Log "Params   : VictimEmail='$VictimEmail' | WorkingDirectory='$WorkingDirectory' | Technician='$Technician' | IncidentTicket='$IncidentTicket' | Scope='$Scope' | LookbackHours=$LookbackHours" -Severity INFO
    Write-Log "Log File : $LogFile"                     -Severity INFO

    Write-Banner -Title "BEC INVESTIGATION - WORKSPACE INIT v$ScriptVersion" -Color Cyan
    Write-Console "Victim Email      : $VictimEmail" -Severity PLAIN
    Write-Console "Working Directory : $WorkingDirectory" -Severity PLAIN
    Write-Console "Technician        : $Technician" -Severity PLAIN
    if ($IncidentTicket) {
        Write-Console "Incident Ticket   : $IncidentTicket" -Severity PLAIN
    }
    if ($LookbackHours -gt 0) {
        Write-Console "Default Lookback  : $LookbackHours hours (override)" -Severity PLAIN
    }
    elseif ($Scope) {
        Write-Console "Default Scope     : $Scope ($($ScopePresets[$Scope]) hours)" -Severity PLAIN
    }
    Write-Console "Log File          : $LogFile" -Severity PLAIN
    Write-Separator

    # Derive investigation identifiers
    $UserAlias         = $VictimEmail.Split("@")[0]
    $Domain            = $VictimEmail.Split("@")[1]
    $Timestamp         = Get-Date -Format "yyyyMMdd-HHmmss"
    $InvestigationName = "BEC-Investigation_${UserAlias}_${Timestamp}"
    $InvestigationPath = Join-Path -Path $WorkingDirectory -ChildPath $InvestigationName

    Write-Log "Victim       : $VictimEmail" -Severity INFO
    Write-Log "Investigation: $InvestigationName" -Severity INFO
    Write-Log "Workspace    : $InvestigationPath" -Severity INFO

    try {
        # ======================================================================
        # STEP 1 - FOLDER STRUCTURE
        # ======================================================================
        Write-Section -Title "Creating Folder Structure"
        Write-Log "Creating investigation folder structure..." -Severity INFO

        try {
            New-Item -Path $InvestigationPath -ItemType Directory -Force | Out-Null
            $SubFolders = @("Logs", "RawData", "Reports", "Analysis", "Scripts")
            foreach ($Folder in $SubFolders) {
                New-Item -Path (Join-Path -Path $InvestigationPath -ChildPath $Folder) -ItemType Directory -Force | Out-Null
                Write-Log     "  Created subfolder: $Folder" -Severity DEBUG
                Write-Console "+ $Folder" -Severity SUCCESS -Indent 1
            }
            Write-Log "Folder structure created successfully." -Severity SUCCESS
        }
        catch {
            Write-Log     "Failed to create folder structure: $($_.Exception.Message)" -Severity ERROR
            Write-Console "Failed to create folder structure." -Severity ERROR -Indent 1
            exit 1
        }

        # ======================================================================
        # STEP 2 - INVESTIGATION.XML
        # ======================================================================
        Write-Section -Title "Creating Investigation.xml"
        Write-Log "Creating Investigation.xml configuration file..." -Severity INFO

        # Determine effective lookback for XML
        $EffectiveLookbackHours = if ($LookbackHours -gt 0) { $LookbackHours } else { $ScopePresets[$Scope] }

        $ConfigData = [ordered]@{
            Investigation = [ordered]@{
                InvestigationID = $InvestigationName
                ScriptVersion   = $ScriptVersion
                CreatedDate     = (Get-Date -Format "o")
                Technician      = $Technician
                IncidentTicket  = $IncidentTicket
            }
            Victim = [ordered]@{
                Email     = $VictimEmail
                UserAlias = $UserAlias
                Domain    = $Domain
            }
            Paths = [ordered]@{
                RootPath     = $InvestigationPath
                LogsPath     = Join-Path -Path $InvestigationPath -ChildPath "Logs"
                RawDataPath  = Join-Path -Path $InvestigationPath -ChildPath "RawData"
                ReportsPath  = Join-Path -Path $InvestigationPath -ChildPath "Reports"
                AnalysisPath = Join-Path -Path $InvestigationPath -ChildPath "Analysis"
                ScriptsPath  = Join-Path -Path $InvestigationPath -ChildPath "Scripts"
            }
            DataCollection = [ordered]@{
                Completed      = "false"
                CompletedDate  = ""
                LookbackHours  = $EffectiveLookbackHours.ToString()
                Scope          = $Scope
                WindowStartUtc = ""
                WindowEndUtc   = ""
            }
            GraphCollection = [ordered]@{
                Completed     = "false"
                CompletedDate = ""
            }
            MessageTraces = [ordered]@{
                SentTraceJobId      = ""
                SentTraceName       = ""
                ReceivedTraceJobId  = ""
                ReceivedTraceName   = ""
                TracesInitiated     = "false"
                TracesCompleted     = "false"
            }
            Analysis = [ordered]@{
                ImmediateAnalysisCompleted  = "false"
                ImmediateAnalysisDate       = ""
                CompleteAnalysisCompleted   = "false"
                CompleteAnalysisDate        = ""
                CriticalFindingsCount       = "0"
                HighFindingsCount           = "0"
            }
        }

        $ConfigPath = Join-Path -Path $InvestigationPath -ChildPath "Investigation.xml"

        try {
            $XmlDoc  = New-Object System.Xml.XmlDocument
            $XmlDecl = $XmlDoc.CreateXmlDeclaration("1.0", "UTF-8", $null)
            $XmlDoc.AppendChild($XmlDecl) | Out-Null
            $XmlRoot = $XmlDoc.CreateElement("BECInvestigation")
            $XmlDoc.AppendChild($XmlRoot) | Out-Null
            Add-XmlElement -Parent $XmlRoot -Data $ConfigData

            $XmlSettings              = New-Object System.Xml.XmlWriterSettings
            $XmlSettings.Indent       = $true
            $XmlSettings.IndentChars  = "  "
            $XmlSettings.NewLineChars = "`r`n"
            $XmlSettings.Encoding     = [System.Text.Encoding]::UTF8

            $XmlWriter = [System.Xml.XmlWriter]::Create($ConfigPath, $XmlSettings)
            $XmlDoc.Save($XmlWriter)
            $XmlWriter.Close()

            Write-Log     "Investigation.xml created: $ConfigPath" -Severity SUCCESS
            Write-Console "Investigation.xml created." -Severity SUCCESS -Indent 1
        }
        catch {
            Write-Log     "Failed to create Investigation.xml: $($_.Exception.Message)" -Severity ERROR
            Write-Console "Failed to create Investigation.xml." -Severity ERROR -Indent 1
            exit 1
        }

        # ======================================================================
        # STEP 3 - GENERATE SCRIPTS
        # ======================================================================
        $ScriptsPath = Join-Path -Path $InvestigationPath -ChildPath "Scripts"
        Write-Section -Title "Generating Investigation Scripts"
        Write-Log "Generating investigation scripts..." -Severity INFO

        # ----------------------------------------------------------------------
        # Invoke-BECDataCollection.ps1 body (embedded as single-quoted here-string
        # to prevent $var interpolation at master script parse time)
        # ----------------------------------------------------------------------
        $DataCollectionScript = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Collects forensic evidence from Exchange Online for a BEC investigation.

.DESCRIPTION
    Invoke-BECDataCollection connects to Exchange Online and collects all relevant
    forensic artifacts for a compromised M365 mailbox. All configuration (victim
    email, output paths, lookback window, scope) is read from Investigation.xml
    in the parent folder.

    IMPORTANT: This script is Exchange Online only. Microsoft Graph collection
    (sign-in logs, risky users, MFA methods, OAuth grants, Conditional Access,
    role memberships, service principals) is handled by a separate script,
    Invoke-BECGraphCollection.ps1, which must be run in its own PowerShell session.
    This split is required because ExchangeOnlineManagement and Microsoft.Graph
    modules have a long-standing MSAL/WAM assembly conflict (GitHub issue #3576)
    that prevents both from authenticating interactively in the same session.

    The script force-disconnects from Exchange Online at the end to leave a clean
    session state for the subsequent Graph collection script.

    Exchange Online data collected:
      - Inbox rules (with suspicious rule flagging to Reports folder)
      - Mail forwarding settings (mailbox-level and tenant-level)
      - Mailbox permissions (delegated, non-inherited)
      - Registered mobile devices
      - Unified audit logs - multiple scoped queries with dynamic window compression:
          * ExchangeItem (mailbox item operations)
          * Rule manipulation events (New/Set/Remove InboxRule)
          * Send operations
          * MailItemsAccessed (best-effort; requires Purview Audit Standard+)
          * SharePoint/OneDrive file downloads (exfiltration indicator)
          * Login events (UserLoggedIn, UserLoginFailed)
          * MFA method changes (Update user.)
          * Role membership adds
          * Conditional Access policy changes
      - Quick message traces (Get-MessageTraceV2, last 10 days)
      - Historical message traces (async job, always submitted)

    Dual-timestamp columns: every CSV with a time field gets a sibling _ET column
    showing the same time in America/New_York local time (handles EST/EDT DST).

    Evidence manifest: SHA-256 hash of every collected artifact is written to
    Analysis\Evidence-Manifest.csv for tamper detection and chain-of-custody.

    When a data file already exists (re-run scenario), the technician is prompted
    to Overwrite, Duplicate (versioned _v2, _v3...), or Skip each collection.

    Execution is logged to the investigation Logs folder via Start-Transcript.

.PARAMETER LookbackHours
    Optional. Overrides the lookback window from Investigation.xml. Specified in hours.
    Use this for custom windows not matching one of the Scope presets.

.PARAMETER Scope
    Optional. Named lookback preset. One of:
      Recent   = 72 hours (3 days)   - DEFAULT, matches Huntress-driven workflow
      Standard = 168 hours (7 days)
      Extended = 720 hours (30 days)
      Maximum  = 2160 hours (90 days) - UAL retention limit for Purview Audit Standard
    If both -LookbackHours and -Scope are specified, -LookbackHours wins.

.PARAMETER SkipHistoricalTraces
    Optional switch. If specified, the historical message trace submission is skipped.
    Useful when re-running data collection and traces are already in progress.

.PARAMETER DisableWAM
    Optional switch. If specified, connects to Exchange Online with -DisableWAM
    to bypass the Web Account Manager broker entirely. Use this when running
    PowerShell in a context that's NOT the same as your Windows logon session
    (Run-As to a different account, Server Core, Task Scheduler "Run whether
    user is logged on or not", ScreenConnect Backstage, etc.). The script
    auto-detects the WAM logon-session failure (error 0x80070520) and retries
    with -DisableWAM automatically, so this switch is rarely needed.

.EXAMPLE
    .\Invoke-BECDataCollection.ps1
    Standard run using default Scope=Recent (72 hours). Collects Exchange + Graph data.

.EXAMPLE
    .\Invoke-BECDataCollection.ps1 -Scope Extended
    Collects 30-day window.

.EXAMPLE
    .\Invoke-BECDataCollection.ps1 -LookbackHours 48
    Custom 48-hour window.

.NOTES
    File Name      : Invoke-BECDataCollection.ps1
    Version        : {SCRIPT_VERSION}
    Author         : Sam Kirsch
    Contributors   : Sam Kirsch
    Company        : Databranch
    Created        : {CREATED_DATE}
    Last Modified  : {CREATED_DATE}
    Modified By    : Sam Kirsch

    Investigation  : {INVESTIGATION_ID}
    Victim         : {VICTIM_EMAIL}

    Requires       : PowerShell 5.1+
                     ExchangeOnlineManagement 3.7.0+ (auto-updated if older)
    Run Context    : Interactive - Technician workstation (Global Admin)
    DattoRMM       : Not applicable
    Client Scope   : Per-investigation (generated script)

    Exit Codes:
        0  - Data collection completed successfully
        1  - Runtime failure during collection (partial data may exist)
        2  - Fatal pre-flight failure (XML not found, auth failed, module update failed)

.CHANGELOG
    v{SCRIPT_VERSION} - {CREATED_DATE} - Sam Kirsch
        - Generated by Start-BECInvestigation.ps1 v{SCRIPT_VERSION}
        - Auto-detects WAM logon-session failure (error 0x80070520) on
          Connect-ExchangeOnline and auto-retries with -DisableWAM.
          Fixes failure mode when PowerShell is running under a different
          user context than the interactive Windows logon session
          (Run-As elevation, Server Core, Task Scheduler, Backstage).
          Reference: Microsoft Learn "Resolve Issues in Exchange Online
          PowerShell Module after WAM Integration"
        - New -DisableWAM switch to force WAM-disabled connect from the
          start (bypasses initial WAM attempt)
        - Next Steps banner now directs tech to switch to PowerShell 7 for Graph
          collection (field experience shows Graph SDK flakiness in PS5.1 despite
          Microsoft claiming compatibility)
        - Split out Microsoft Graph collection to Invoke-BECGraphCollection.ps1
          (MSAL/WAM conflict - msgraph-sdk-powershell GitHub issue #3576)
        - Removed -SkipGraph parameter (no longer relevant)
        - Forced Exchange Online disconnect at end to leave clean session
        - TLS 1.2 block moved below param() - CmdletBinding must be first statement
        - Drops deprecated Get-MessageTrace V1 fallback (Reporting Webservice EOL 4/8/2026)
        - Requires ExchangeOnlineManagement 3.7.0+; auto-updates if older
        - Dynamic time-window compression for UAL when 5000-record cap is hit
        - Dual-timestamp columns (UTC + America/New_York ET) on all time-based CSVs
        - SHA-256 evidence manifest written to Analysis\Evidence-Manifest.csv
        - New UAL scoped queries: rule manipulation, Send ops, MailItemsAccessed,
          file downloads, logins, MFA changes, role adds, CA policy changes
        - New -LookbackHours and -Scope parameters (default: Recent = 72 hours)
        - Full template v1.4.1.0 compliance: TLS 1.2, dual-output pattern,
          exit codes 0/1/2, preflight validation, standard log header
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [int]$LookbackHours = 0,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Recent', 'Standard', 'Extended', 'Maximum')]
    [string]$Scope = '',

    [Parameter(Mandatory = $false)]
    [switch]$SkipHistoricalTraces,

    [Parameter(Mandatory = $false)]
    [switch]$DisableWAM
)

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# Must be AFTER param() so CmdletBinding remains the first executable statement.
# Required for all HTTPS calls (Exchange Online token endpoints).
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

function Invoke-BECDataCollection {
    [CmdletBinding()]
    param (
        [int]$LookbackHours,
        [string]$Scope,
        [switch]$SkipHistoricalTraces,
        [switch]$DisableWAM
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Invoke-BECDataCollection"
    $ScriptVersion = "{SCRIPT_VERSION}"

    # Required module versions - scripts will attempt to install/update if missing
    $MinExoVersion   = [Version]"3.7.0"
    $MinGraphVersion = [Version]"2.0.0"

    # Scope preset to hours mapping
    $ScopePresets = @{
        'Recent'   = 72      # 3 days - matches Huntress-driven workflow
        'Standard' = 168     # 7 days
        'Extended' = 720     # 30 days
        'Maximum'  = 2160    # 90 days - UAL retention limit for Standard audit
    }

    # Eastern timezone (handles EST/EDT DST automatically)
    $EasternTZ = [System.TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')

    # ==========================================================================
    # XML CONFIGURATION READ
    # ==========================================================================
    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\Investigation.xml"
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Host "[ERROR] Investigation.xml not found at: $ConfigPath" -ForegroundColor Red
        Write-Host "[ERROR] Ensure you are running this script from the Scripts subfolder." -ForegroundColor Red
        exit 2
    }

    try {
        [xml]$Config = Get-Content -Path $ConfigPath -Encoding UTF8
    }
    catch {
        Write-Host "[ERROR] Failed to parse Investigation.xml: $($_.Exception.Message)" -ForegroundColor Red
        exit 2
    }

    $VictimEmail  = $Config.BECInvestigation.Victim.Email
    $UserAlias    = $Config.BECInvestigation.Victim.UserAlias
    $RawDataPath  = $Config.BECInvestigation.Paths.RawDataPath
    $LogsPath     = $Config.BECInvestigation.Paths.LogsPath
    $ReportsPath  = $Config.BECInvestigation.Paths.ReportsPath
    $AnalysisPath = $Config.BECInvestigation.Paths.AnalysisPath
    $InvestigationID = $Config.BECInvestigation.Investigation.InvestigationID

    # Validate critical values from XML
    $XmlValidationErrors = @()
    if (-not $VictimEmail)  { $XmlValidationErrors += "Victim.Email" }
    if (-not $UserAlias)    { $XmlValidationErrors += "Victim.UserAlias" }
    if (-not $RawDataPath)  { $XmlValidationErrors += "Paths.RawDataPath" }
    if (-not $LogsPath)     { $XmlValidationErrors += "Paths.LogsPath" }
    if (-not $ReportsPath)  { $XmlValidationErrors += "Paths.ReportsPath" }
    if (-not $AnalysisPath) { $XmlValidationErrors += "Paths.AnalysisPath" }
    if ($XmlValidationErrors.Count -gt 0) {
        Write-Host "[ERROR] Investigation.xml is missing required fields: $($XmlValidationErrors -join ', ')" -ForegroundColor Red
        Write-Host "[ERROR] The XML may be corrupted. Re-run Start-BECInvestigation.ps1 to regenerate." -ForegroundColor Red
        exit 2
    }

    # ==========================================================================
    # DETERMINE LOOKBACK WINDOW
    # Priority: -LookbackHours (explicit override) > -Scope > XML default > Recent (72h)
    # ==========================================================================
    if ($LookbackHours -gt 0) {
        $EffectiveHours = $LookbackHours
        $ScopeSource    = "explicit -LookbackHours override"
    }
    elseif ($Scope) {
        $EffectiveHours = $ScopePresets[$Scope]
        $ScopeSource    = "-Scope $Scope preset"
    }
    elseif ($Config.BECInvestigation.DataCollection.LookbackHours -and
            [int]$Config.BECInvestigation.DataCollection.LookbackHours -gt 0) {
        $EffectiveHours = [int]$Config.BECInvestigation.DataCollection.LookbackHours
        $ScopeSource    = "XML DataCollection.LookbackHours"
    }
    else {
        $EffectiveHours = $ScopePresets['Recent']
        $ScopeSource    = "default (Recent = 72h)"
    }

    $EndDate   = Get-Date
    $StartDate = $EndDate.AddHours(-$EffectiveHours)
    $DaysBack  = [math]::Round($EffectiveHours / 24, 2)

    # ==========================================================================
    # LOGGING SETUP (transcript + dual-output Write-Log/Write-Console)
    # ==========================================================================
    $TranscriptTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $TranscriptPath      = Join-Path -Path $LogsPath -ChildPath "DataCollection_${TranscriptTimestamp}.log"
    Start-Transcript -Path $TranscriptPath -ErrorAction SilentlyContinue | Out-Null

    function Write-Log {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = "",
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
            [string]$Severity = "INFO"
        )
        $Ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Entry = "[$Ts] [$Severity] $Message"
        switch ($Severity) {
            "INFO"    { Write-Output  $Entry }
            "WARN"    { Write-Warning $Entry }
            "ERROR"   { Write-Error   $Entry -ErrorAction Continue }
            "SUCCESS" { Write-Output  $Entry }
            "DEBUG"   { Write-Output  $Entry }
        }
    }

    function Write-Console {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = "",
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG","PLAIN")]
            [string]$Severity = "PLAIN",
            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )
        $Prefix = "  " * $Indent
        $Colors = @{
            INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red";
            DEBUG="Magenta"; PLAIN="Gray"
        }
        $Color = $Colors[$Severity]
        if ($Severity -eq "PLAIN") {
            Write-Host "$Prefix$Message" -ForegroundColor $Color
        }
        else {
            Write-Host "$Prefix" -NoNewline
            Write-Host "[$Severity]" -ForegroundColor $Color -NoNewline
            Write-Host " $Message" -ForegroundColor White
        }
    }

    function Write-Banner {
        param ([string]$Title, [string]$Color = "Cyan")
        $Line = "=" * 60
        Write-Host ""
        Write-Host $Line -ForegroundColor $Color
        Write-Host "  $Title" -ForegroundColor White
        Write-Host $Line -ForegroundColor $Color
        Write-Host ""
    }

    function Write-Section {
        param ([string]$Title, [string]$Color = "Cyan")
        $TitleStr = "---- $Title "
        $Padding  = "-" * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ""
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    function Write-Separator {
        param ([string]$Color = "DarkGray")
        Write-Host ("-" * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # HELPER: Convert UTC datetime to Eastern time string
    # ==========================================================================
    function ConvertTo-EasternTime {
        param ($UtcDateTime)
        if (-not $UtcDateTime) { return "" }
        try {
            $Dt = if ($UtcDateTime -is [DateTime]) {
                $UtcDateTime
            }
            else {
                [DateTime]::Parse($UtcDateTime.ToString(), [System.Globalization.CultureInfo]::InvariantCulture,
                                  [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                                  [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            }
            if ($Dt.Kind -ne [DateTimeKind]::Utc) {
                $Dt = [DateTime]::SpecifyKind($Dt, [DateTimeKind]::Utc)
            }
            $Et = [System.TimeZoneInfo]::ConvertTimeFromUtc($Dt, $EasternTZ)
            $TzAbbr = if ($EasternTZ.IsDaylightSavingTime($Et)) { "EDT" } else { "EST" }
            return ("{0} {1}" -f $Et.ToString("yyyy-MM-dd HH:mm:ss"), $TzAbbr)
        }
        catch {
            return ""
        }
    }

    # ==========================================================================
    # HELPER: Add _ET column(s) to an array of PSCustomObjects for given time fields
    # ==========================================================================
    function Add-EasternTimeColumns {
        param (
            [Parameter(Mandatory = $true)]
            $Data,
            [Parameter(Mandatory = $true)]
            [string[]]$TimeFields
        )
        if (-not $Data) { return $Data }
        $Result = foreach ($Row in $Data) {
            $NewRow = [ordered]@{}
            foreach ($Prop in $Row.PSObject.Properties) {
                $NewRow[$Prop.Name] = $Prop.Value
                if ($TimeFields -contains $Prop.Name) {
                    $EtColName = $Prop.Name + "_ET"
                    $NewRow[$EtColName] = ConvertTo-EasternTime -UtcDateTime $Prop.Value
                }
            }
            [PSCustomObject]$NewRow
        }
        return $Result
    }

    # ==========================================================================
    # HELPER: SHA-256 hash a file and return hash string
    # ==========================================================================
    function Get-FileSha256 {
        param ([string]$Path)
        try {
            $Hash = Get-FileHash -Path $Path -Algorithm SHA256 -ErrorAction Stop
            return $Hash.Hash
        }
        catch {
            return ""
        }
    }

    # ==========================================================================
    # HELPER: Add entry to evidence manifest
    # ==========================================================================
    $script:EvidenceManifest = @()
    function Add-EvidenceManifestEntry {
        param (
            [string]$FilePath,
            [string]$Description,
            [string]$Source
        )
        if (-not (Test-Path -Path $FilePath)) { return }
        $FileInfo  = Get-Item -Path $FilePath
        $Hash      = Get-FileSha256 -Path $FilePath
        $UtcNow    = (Get-Date).ToUniversalTime()
        $Entry = [PSCustomObject]@{
            FileName            = $FileInfo.Name
            RelativePath        = $FilePath.Replace($Config.BECInvestigation.Paths.RootPath, '').TrimStart('\')
            Description         = $Description
            Source              = $Source
            SizeBytes           = $FileInfo.Length
            CollectedUtc        = $UtcNow.ToString("yyyy-MM-dd HH:mm:ss") + " UTC"
            CollectedEastern    = ConvertTo-EasternTime -UtcDateTime $UtcNow
            SHA256              = $Hash
        }
        $script:EvidenceManifest += $Entry
    }

    # ==========================================================================
    # HELPER: File conflict resolution (O/D/S prompt)
    # ==========================================================================
    function Get-OutputFileAction {
        param (
            [string]$BasePath,
            [string]$Description
        )
        if (Test-Path -Path $BasePath) {
            Write-Log     "File already exists: $(Split-Path -Path $BasePath -Leaf)" -Severity WARN
            Write-Console "File already exists: $(Split-Path -Path $BasePath -Leaf)" -Severity WARN
            $Choice = Read-Host "  [O]verwrite, [D]uplicate (versioned), or [S]kip $Description? [O/D/S]"
            switch ($Choice.ToUpper()) {
                "O" {
                    Write-Log     "  Overwriting existing file." -Severity INFO
                    return @{ Action = "Collect"; Path = $BasePath }
                }
                "D" {
                    $Dir     = Split-Path -Path $BasePath -Parent
                    $Name    = [System.IO.Path]::GetFileNameWithoutExtension($BasePath)
                    $Ext     = [System.IO.Path]::GetExtension($BasePath)
                    $Version = 2
                    while (Test-Path -Path (Join-Path -Path $Dir -ChildPath "${Name}_v${Version}${Ext}")) {
                        $Version++
                    }
                    $NewPath = Join-Path -Path $Dir -ChildPath "${Name}_v${Version}${Ext}"
                    Write-Log     "  Creating duplicate: $(Split-Path -Path $NewPath -Leaf)" -Severity INFO
                    return @{ Action = "Collect"; Path = $NewPath }
                }
                default {
                    Write-Log     "  Skipping $Description." -Severity INFO
                    return @{ Action = "Skip"; Path = $null }
                }
            }
        }
        return @{ Action = "Collect"; Path = $BasePath }
    }

    # ==========================================================================
    # HELPER: Export CSV with manifest entry + ET timestamp columns
    # ==========================================================================
    function Export-DataWithManifest {
        param (
            $Data,
            [string]$FilePath,
            [string]$Description,
            [string]$Source,
            [string[]]$TimeFields = @()
        )
        try {
            if ($Data) {
                if ($TimeFields.Count -gt 0) {
                    $Data = Add-EasternTimeColumns -Data $Data -TimeFields $TimeFields
                }
                $Data | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
                $Count = ($Data | Measure-Object).Count
                Add-EvidenceManifestEntry -FilePath $FilePath -Description $Description -Source $Source
                Write-Log     "  $Description : $Count record(s) -> $(Split-Path -Path $FilePath -Leaf)" -Severity SUCCESS
                Write-Console "$Description : $Count record(s)" -Severity SUCCESS -Indent 1
                return $true
            }
            else {
                Write-Log     "  $Description : No data found." -Severity INFO
                Write-Console "$Description : No data found." -Severity INFO -Indent 1
                return $false
            }
        }
        catch {
            Write-Log     "  $Description : Export failed - $($_.Exception.Message)" -Severity ERROR
            Write-Console "$Description : Export failed - $($_.Exception.Message)" -Severity ERROR -Indent 1
            return $false
        }
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = "Continue"  # Resilient collection - individual failures don't abort run

    Write-Banner -Title "BEC DATA COLLECTION v$ScriptVersion" -Color Cyan
    Write-Console "Investigation : $InvestigationID" -Severity PLAIN
    Write-Console "Victim        : $VictimEmail" -Severity PLAIN
    Write-Console "Lookback      : $EffectiveHours hours (~$DaysBack days) via $ScopeSource" -Severity PLAIN
    Write-Console "Window Start  : $($StartDate.ToString('yyyy-MM-dd HH:mm:ss'))  /  $(ConvertTo-EasternTime -UtcDateTime $StartDate.ToUniversalTime())" -Severity PLAIN
    Write-Console "Window End    : $($EndDate.ToString('yyyy-MM-dd HH:mm:ss'))  /  $(ConvertTo-EasternTime -UtcDateTime $EndDate.ToUniversalTime())" -Severity PLAIN
    Write-Console "Transcript    : $TranscriptPath" -Severity PLAIN
    Write-Separator

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Investigation : $InvestigationID" -Severity INFO
    Write-Log "Victim        : $VictimEmail" -Severity INFO
    Write-Log "Lookback      : $EffectiveHours hours via $ScopeSource" -Severity INFO
    Write-Log "Window        : $StartDate to $EndDate" -Severity INFO
    Write-Log "Transcript    : $TranscriptPath" -Severity INFO

    # Track whether any collection failed fatally
    $FatalError = $false

    try {
        # ======================================================================
        # PRE-FLIGHT: MODULE CHECKS AND AUTO-UPDATE
        # ======================================================================
        Write-Section -Title "Module Check"
        Write-Log     "Checking ExchangeOnlineManagement module (required: $MinExoVersion or later)..." -Severity INFO
        Write-Console "Checking ExchangeOnlineManagement module (required: $MinExoVersion or later)..." -Severity INFO

        $ExoMod = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
                  Sort-Object -Property Version -Descending |
                  Select-Object -First 1

        if (-not $ExoMod) {
            Write-Log     "ExchangeOnlineManagement not found. Installing latest from PSGallery..." -Severity WARN
            Write-Console "ExchangeOnlineManagement not found. Installing..." -Severity WARN -Indent 1
            try {
                Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                Write-Log     "ExchangeOnlineManagement installed." -Severity SUCCESS
                Write-Console "ExchangeOnlineManagement installed." -Severity SUCCESS -Indent 1
            }
            catch {
                Write-Log     "Failed to install ExchangeOnlineManagement: $($_.Exception.Message)" -Severity ERROR
                Write-Console "Failed to install ExchangeOnlineManagement: $($_.Exception.Message)" -Severity ERROR -Indent 1
                Write-Banner -Title "FATAL - MODULE INSTALL FAILED" -Color Red
                Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
                exit 2
            }
        }
        elseif ($ExoMod.Version -lt $MinExoVersion) {
            Write-Log     "ExchangeOnlineManagement v$($ExoMod.Version) is older than required v$MinExoVersion. Updating..." -Severity WARN
            Write-Console "Updating ExchangeOnlineManagement (current: $($ExoMod.Version), required: $MinExoVersion)..." -Severity WARN -Indent 1
            try {
                Update-Module -Name ExchangeOnlineManagement -Force -ErrorAction Stop
                Write-Log     "ExchangeOnlineManagement updated." -Severity SUCCESS
                Write-Console "ExchangeOnlineManagement updated." -Severity SUCCESS -Indent 1
            }
            catch {
                # Update-Module only works if originally installed via Install-Module.
                # If that failed, try Install-Module -Force which handles both cases.
                Write-Log     "Update-Module failed, attempting Install-Module -Force..." -Severity WARN
                try {
                    Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                    Write-Log     "ExchangeOnlineManagement reinstalled at current version." -Severity SUCCESS
                    Write-Console "ExchangeOnlineManagement reinstalled at current version." -Severity SUCCESS -Indent 1
                }
                catch {
                    Write-Log     "Failed to update/reinstall ExchangeOnlineManagement: $($_.Exception.Message)" -Severity ERROR
                    Write-Console "Failed to update ExchangeOnlineManagement: $($_.Exception.Message)" -Severity ERROR -Indent 1
                    Write-Banner -Title "FATAL - MODULE UPDATE FAILED" -Color Red
                    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
                    exit 2
                }
            }
        }
        else {
            Write-Log     "ExchangeOnlineManagement v$($ExoMod.Version) meets requirement." -Severity SUCCESS
            Write-Console "ExchangeOnlineManagement v$($ExoMod.Version) OK." -Severity SUCCESS -Indent 1
        }

        Import-Module -Name ExchangeOnlineManagement -Force -ErrorAction Stop

        # ======================================================================
        # CONNECT TO EXCHANGE ONLINE
        # WAM (Web Account Manager) is the default broker since EXO module 3.7.0.
        # WAM REQUIRES the PowerShell process to run in the same Windows logon
        # session as the interactive desktop user. If you Run-As'd into a
        # different account, are on Server Core, or running through Task
        # Scheduler with "Run whether user is logged on or not", WAM will fail
        # with error 0x80070520 ("specified logon session does not exist").
        # We try WAM first, detect that signature, and auto-retry with -DisableWAM.
        # The technician can also force -DisableWAM upfront to skip the first attempt.
        # ======================================================================
        Write-Section -Title "Connecting to Exchange Online"
        Write-Log     "Connecting to Exchange Online (REST API)..." -Severity INFO
        Write-Console "A browser window will prompt for Global Admin credentials..." -Severity INFO

        $ExoConnected   = $false
        $WamWasDisabled = $false

        if ($DisableWAM) {
            # Tech explicitly opted out of WAM up front
            Write-Log     "  -DisableWAM specified - connecting without WAM broker." -Severity INFO
            Write-Console "Connecting without WAM (forced via -DisableWAM)..." -Severity INFO -Indent 1
            try {
                Connect-ExchangeOnline -ShowBanner:$false -DisableWAM -ErrorAction Stop
                $ExoConnected   = $true
                $WamWasDisabled = $true
                Write-Log     "Connected to Exchange Online (WAM disabled)." -Severity SUCCESS
                Write-Console "Connected to Exchange Online (WAM disabled)." -Severity SUCCESS -Indent 1
            }
            catch {
                Write-Log     "Failed to connect to Exchange Online: $($_.Exception.Message)" -Severity ERROR
                Write-Console "Failed to connect to Exchange Online: $($_.Exception.Message)" -Severity ERROR -Indent 1
                Write-Banner -Title "FATAL - EXCHANGE ONLINE CONNECT FAILED" -Color Red
                Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
                exit 2
            }
        }
        else {
            # Standard path - try WAM first, auto-fallback to -DisableWAM on the
            # specific 0x80070520 / "logon session does not exist" failure mode.
            try {
                Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
                $ExoConnected = $true
                Write-Log     "Connected to Exchange Online." -Severity SUCCESS
                Write-Console "Connected to Exchange Online." -Severity SUCCESS -Indent 1
            }
            catch {
                $ErrMsg = $_.Exception.Message
                # Match the documented WAM logon-session signature
                $IsWamSessionError = ($ErrMsg -match '0x80070520') -or
                                     ($ErrMsg -match 'specified logon session does not exist') -or
                                     ($ErrMsg -match '0x21420087')
                if ($IsWamSessionError) {
                    Write-Log     "  WAM authentication failed (logon-session error 0x80070520)." -Severity WARN
                    Write-Log     "  Cause: PowerShell process is not in the interactive Windows logon session" -Severity WARN
                    Write-Log     "  (e.g. Run-As elevation, Server Core, scheduled task, Backstage)." -Severity WARN
                    Write-Log     "  Auto-retrying with -DisableWAM..." -Severity WARN
                    Write-Console "WAM error - auto-retrying with -DisableWAM..." -Severity WARN -Indent 1
                    try {
                        Connect-ExchangeOnline -ShowBanner:$false -DisableWAM -ErrorAction Stop
                        $ExoConnected   = $true
                        $WamWasDisabled = $true
                        Write-Log     "Connected to Exchange Online (WAM disabled, auto-fallback)." -Severity SUCCESS
                        Write-Console "Connected to Exchange Online (WAM disabled)." -Severity SUCCESS -Indent 1
                    }
                    catch {
                        Write-Log     "Auto-fallback also failed: $($_.Exception.Message)" -Severity ERROR
                        Write-Console "Auto-fallback also failed: $($_.Exception.Message)" -Severity ERROR -Indent 1
                        Write-Banner -Title "FATAL - EXCHANGE ONLINE CONNECT FAILED" -Color Red
                        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
                        exit 2
                    }
                }
                else {
                    # Non-WAM failure - surface the original error
                    Write-Log     "Failed to connect to Exchange Online: $ErrMsg" -Severity ERROR
                    Write-Console "Failed to connect to Exchange Online: $ErrMsg" -Severity ERROR -Indent 1
                    Write-Banner -Title "FATAL - EXCHANGE ONLINE CONNECT FAILED" -Color Red
                    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
                    exit 2
                }
            }
        }

        if ($WamWasDisabled) {
            Write-Console "" -Severity PLAIN
            Write-Console "NOTE: WAM was disabled for this session. This is fine for collection," -Severity INFO -Indent 1
            Write-Console "but indicates your PowerShell context is mismatched with the Windows" -Severity INFO -Indent 1
            Write-Console "logon session. To use WAM normally next time, run PowerShell as the" -Severity INFO -Indent 1
            Write-Console "same user that is logged in to the Windows desktop (no Run-As)." -Severity INFO -Indent 1
            Write-Console "" -Severity PLAIN
        }

        # Resolve notification address from active EXO session (used for historical trace submission)
        try {
            $ConnInfo = Get-ConnectionInformation |
                        Where-Object { $_.State -eq 'Connected' } |
                        Sort-Object -Property ConnectedAt -Descending |
                        Select-Object -First 1
            $NotifyAddress = $ConnInfo.UserPrincipalName
            if ($NotifyAddress) {
                Write-Log "Technician UPN resolved for trace notifications: $NotifyAddress" -Severity DEBUG
            }
            else {
                Write-Log "Could not resolve technician UPN from active session." -Severity WARN
            }
        }
        catch {
            $NotifyAddress = $null
            Write-Log "Could not resolve technician UPN: $($_.Exception.Message)" -Severity WARN
        }

        # ======================================================================
        # VERIFY VICTIM MAILBOX
        # ======================================================================
        Write-Section -Title "Verifying Victim Mailbox"
        try {
            $UserMailbox = Get-Mailbox -Identity $VictimEmail -ErrorAction Stop
            Write-Log     "User verified: $($UserMailbox.DisplayName) ($VictimEmail)" -Severity SUCCESS
            Write-Console "Display Name : $($UserMailbox.DisplayName)" -Severity PLAIN -Indent 1
            Write-Console "Mailbox Type : $($UserMailbox.RecipientTypeDetails)" -Severity PLAIN -Indent 1
        }
        catch {
            Write-Log     "Victim mailbox not found: $VictimEmail - $($_.Exception.Message)" -Severity ERROR
            Write-Console "Victim mailbox not found - check email address and try again." -Severity ERROR -Indent 1
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
            exit 2
        }

        # ======================================================================
        # EXCHANGE ONLINE COLLECTIONS
        # ======================================================================

        # ---- Inbox Rules (point-in-time) ----
        Write-Section -Title "Inbox Rules (current state)"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\InboxRules_${UserAlias}.csv" -Description "Inbox Rules"
        if ($FA.Action -eq "Collect") {
            try {
                $Rules = Get-InboxRule -Mailbox $VictimEmail -ErrorAction Stop
                if ($Rules) {
                    $RuleData = $Rules | Select-Object -Property Name, Description, Enabled, Priority,
                        MoveToFolder, MarkAsRead, DeleteMessage, ForwardTo, ForwardAsAttachmentTo,
                        RedirectTo, SentTo, From, SubjectContainsWords, SubjectOrBodyContainsWords,
                        BodyContainsWords, MailboxOwnerId
                    Export-DataWithManifest -Data $RuleData -FilePath $FA.Path `
                        -Description "Inbox Rules" -Source "Get-InboxRule"

                    # Suspicious rule detection (flag to Reports folder)
                    $Suspicious = $RuleData | Where-Object {
                        $_.DeleteMessage -or $_.MoveToFolder -or $_.MarkAsRead -or
                        $_.ForwardTo -or $_.RedirectTo -or $_.ForwardAsAttachmentTo
                    }
                    if ($Suspicious) {
                        $SuspPath = "$ReportsPath\SUSPICIOUS-Rules_${UserAlias}.csv"
                        if ($FA.Path -match "_v(\d+)\.csv$") {
                            $SuspPath = "$ReportsPath\SUSPICIOUS-Rules_${UserAlias}_v$($Matches[1]).csv"
                        }
                        Export-DataWithManifest -Data $Suspicious -FilePath $SuspPath `
                            -Description "Suspicious Rules (flagged)" -Source "Get-InboxRule filtered"
                        Write-Log     "  $($Suspicious.Count) suspicious rule(s) flagged." -Severity WARN
                        Write-Console "$($Suspicious.Count) suspicious rule(s) flagged." -Severity WARN -Indent 1
                    }
                    else {
                        Write-Log     "  No suspicious rules detected." -Severity SUCCESS
                    }
                }
                else {
                    Write-Log "  No inbox rules found." -Severity INFO
                }
            }
            catch {
                Write-Log     "Inbox rules collection failed: $($_.Exception.Message)" -Severity ERROR
                Write-Console "Inbox rules collection failed: $($_.Exception.Message)" -Severity ERROR -Indent 1
            }
        }

        # ---- Mail Forwarding (mailbox-level) ----
        Write-Section -Title "Mail Forwarding (mailbox-level)"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\MailForwarding_${UserAlias}.csv" -Description "Mail Forwarding"
        if ($FA.Action -eq "Collect") {
            try {
                $Fwd = Get-Mailbox -Identity $VictimEmail |
                    Select-Object -Property UserPrincipalName, DisplayName,
                        ForwardingAddress, ForwardingSmtpAddress, DeliverToMailboxAndForward,
                        @{N='ForwardingEnabled'; E={
                            $null -ne $_.ForwardingAddress -or $null -ne $_.ForwardingSmtpAddress
                        }}
                Export-DataWithManifest -Data $Fwd -FilePath $FA.Path `
                    -Description "Mail Forwarding (mailbox)" -Source "Get-Mailbox"

                if ($Fwd.ForwardingEnabled -eq $true) {
                    Write-Log     "  WARNING: Forwarding is ENABLED to $($Fwd.ForwardingSmtpAddress)" -Severity WARN
                    Write-Console "Forwarding is ENABLED to $($Fwd.ForwardingSmtpAddress)" -Severity WARN -Indent 1
                }
                else {
                    Write-Log "  Forwarding is not enabled." -Severity SUCCESS
                }
            }
            catch {
                Write-Log "Mail forwarding collection failed: $($_.Exception.Message)" -Severity ERROR
            }
        }

        # ---- Transport Rules (tenant-level forwarding via mail flow rules) ----
        Write-Section -Title "Transport Rules (tenant-level, forwarding only)"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\TransportRules_ForwardingOnly.csv" -Description "Transport Rules"
        if ($FA.Action -eq "Collect") {
            try {
                $TRs = Get-TransportRule -ErrorAction Stop |
                    Where-Object {
                        $_.RedirectMessageTo -or $_.BlindCopyTo -or $_.CopyTo -or
                        $_.AddToRecipients -or $_.SetHeaderName
                    } |
                    Select-Object -Property Name, State, Priority, WhenChanged, LastModifiedBy,
                        RedirectMessageTo, BlindCopyTo, CopyTo, AddToRecipients,
                        FromScope, SentToScope, SubjectContainsWords, From, SentTo
                if ($TRs) {
                    Export-DataWithManifest -Data $TRs -FilePath $FA.Path `
                        -Description "Transport Rules (forwarding)" -Source "Get-TransportRule" `
                        -TimeFields @('WhenChanged')
                    Write-Log     "  $($TRs.Count) transport rule(s) involve forwarding - REVIEW." -Severity WARN
                    Write-Console "$($TRs.Count) transport rule(s) involve forwarding - REVIEW." -Severity WARN -Indent 1
                }
                else {
                    Write-Log "  No forwarding-related transport rules found." -Severity SUCCESS
                }
            }
            catch {
                Write-Log "Transport rule collection failed: $($_.Exception.Message)" -Severity ERROR
            }
        }

        # ---- Mailbox Permissions (delegated, non-inherited) ----
        Write-Section -Title "Mailbox Permissions"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\MailboxPermissions_${UserAlias}.csv" -Description "Mailbox Permissions"
        if ($FA.Action -eq "Collect") {
            try {
                $Perms = Get-MailboxPermission -Identity $VictimEmail |
                    Where-Object { $_.User -notlike "*SELF*" -and $_.IsInherited -eq $false }
                if ($Perms) {
                    Export-DataWithManifest -Data $Perms -FilePath $FA.Path `
                        -Description "Mailbox Permissions" -Source "Get-MailboxPermission"
                    Write-Log     "  $(($Perms | Measure-Object).Count) delegated permission(s) - review." -Severity WARN
                    Write-Console "$(($Perms | Measure-Object).Count) delegated permission(s) - review." -Severity WARN -Indent 1
                }
                else {
                    Write-Log "  No delegated permissions found (normal)." -Severity SUCCESS
                }
            }
            catch {
                Write-Log "Mailbox permissions collection failed: $($_.Exception.Message)" -Severity ERROR
            }
        }

        # ---- Mobile Devices ----
        Write-Section -Title "Mobile Devices"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\MobileDevices_${UserAlias}.csv" -Description "Mobile Devices"
        if ($FA.Action -eq "Collect") {
            try {
                $Devs = Get-MobileDevice -Mailbox $VictimEmail -ErrorAction Stop
                if ($Devs) {
                    $DevData = $Devs | Select-Object -Property DeviceId, DeviceOS, DeviceType,
                        DeviceUserAgent, FriendlyName, FirstSyncTime, WhenCreatedUTC, WhenChangedUTC,
                        DeviceAccessState, DeviceAccessStateReason, ClientType, UserDisplayName
                    Export-DataWithManifest -Data $DevData -FilePath $FA.Path `
                        -Description "Mobile Devices" -Source "Get-MobileDevice" `
                        -TimeFields @('FirstSyncTime', 'WhenCreatedUTC', 'WhenChangedUTC')
                    Write-Log     "  $(($Devs | Measure-Object).Count) device(s) registered - review for unrecognized." -Severity WARN
                    Write-Console "$(($Devs | Measure-Object).Count) device(s) registered - review." -Severity WARN -Indent 1
                }
                else {
                    Write-Log "  No mobile devices registered." -Severity INFO
                }
            }
            catch {
                Write-Log "Mobile device collection failed: $($_.Exception.Message)" -Severity ERROR
            }
        }

        # ======================================================================
        # UNIFIED AUDIT LOG - DYNAMIC WINDOW COMPRESSION HELPER
        # Search-UnifiedAuditLog caps at 5000 per query. If we hit the cap,
        # split the window in half recursively until each sub-window returns
        # under 5000 records or we hit a minimum chunk size.
        # ======================================================================
        function Invoke-UalChunkedQuery {
            param (
                [datetime]$ChunkStart,
                [datetime]$ChunkEnd,
                [string[]]$UserIds = @(),
                [string]$RecordType = '',
                [string[]]$Operations = @(),
                [int]$MinMinutes = 15,
                [int]$MaxAttempts = 3
            )
            $Results = @()
            $DurationHours = ($ChunkEnd - $ChunkStart).TotalHours
            $DurationMinutes = ($ChunkEnd - $ChunkStart).TotalMinutes

            # Build parameter splat
            $UalParams = @{
                StartDate    = $ChunkStart
                EndDate      = $ChunkEnd
                ResultSize   = 5000
                SessionCommand = 'ReturnLargeSet'
                Formatted    = $true
                ErrorAction  = 'Stop'
            }
            if ($UserIds.Count -gt 0)    { $UalParams['UserIds']    = $UserIds }
            if ($RecordType)             { $UalParams['RecordType'] = $RecordType }
            if ($Operations.Count -gt 0) { $UalParams['Operations'] = $Operations }

            $Attempt     = 0
            $QueryDone   = $false
            $SessionId   = [guid]::NewGuid().ToString()
            $AllPages    = @()

            while ($Attempt -lt $MaxAttempts -and -not $QueryDone) {
                $Attempt++
                try {
                    # Use SessionId to page through large result sets
                    $UalParams['SessionId'] = $SessionId
                    $Page = Search-UnifiedAuditLog @UalParams
                    if ($Page) {
                        $AllPages += $Page
                        # Continue paging if the last page returned a full 5000 records (more may follow)
                        while ($Page.Count -ge 5000) {
                            $Page = Search-UnifiedAuditLog @UalParams
                            if ($Page) { $AllPages += $Page }
                            else { break }
                        }
                    }
                    $QueryDone = $true
                }
                catch {
                    if ($Attempt -lt $MaxAttempts) {
                        Write-Log "    UAL chunk attempt $Attempt failed, retrying in 10s: $($_.Exception.Message)" -Severity WARN
                        Start-Sleep -Seconds 10
                    }
                    else {
                        Write-Log "    UAL chunk failed after $MaxAttempts attempts: $($_.Exception.Message)" -Severity ERROR
                        return $null
                    }
                }
            }

            # Deduplicate by Identity (unsorted paged results may have overlap)
            $Unique = $AllPages | Sort-Object -Property Identity -Unique

            # If we hit the 5000-per-window cap, split and recurse
            # (Even with paging, individual sub-queries can silently truncate on very busy windows)
            if ($Unique.Count -ge 4900 -and $DurationMinutes -gt $MinMinutes) {
                Write-Log "    Window $($ChunkStart.ToString('MM-dd HH:mm'))-$($ChunkEnd.ToString('MM-dd HH:mm')) likely capped at 5000. Splitting..." -Severity WARN
                $Midpoint = $ChunkStart.AddMinutes([math]::Floor($DurationMinutes / 2))
                $FirstHalf  = Invoke-UalChunkedQuery -ChunkStart $ChunkStart -ChunkEnd $Midpoint `
                    -UserIds $UserIds -RecordType $RecordType -Operations $Operations -MinMinutes $MinMinutes
                $SecondHalf = Invoke-UalChunkedQuery -ChunkStart $Midpoint   -ChunkEnd $ChunkEnd `
                    -UserIds $UserIds -RecordType $RecordType -Operations $Operations -MinMinutes $MinMinutes
                $Results = @($FirstHalf) + @($SecondHalf)
            }
            else {
                $Results = $Unique
            }
            return $Results
        }

        # ---- UAL COLLECTION: ExchangeItem for victim ----
        # Overall collection uses fixed 7-day-or-less outer chunks, then each
        # outer chunk goes through Invoke-UalChunkedQuery which compresses
        # further if the 5000 cap is hit.
        function Invoke-UalCollection {
            param (
                [string]$Label,
                [string]$OutputPath,
                [string[]]$UserIds = @(),
                [string]$RecordType = '',
                [string[]]$Operations = @(),
                [datetime]$QueryStart,
                [datetime]$QueryEnd
            )
            Write-Log     "UAL Collection: $Label" -Severity INFO
            Write-Console "UAL Collection: $Label" -Severity INFO
            $OuterChunkHours = 24 * 7   # 7 days outer
            $AllRecords      = @()
            $Ptr = $QueryStart
            $Num = 0
            $TotalOuter = [math]::Ceiling(($QueryEnd - $QueryStart).TotalHours / $OuterChunkHours)

            while ($Ptr -lt $QueryEnd) {
                $Num++
                $OuterEnd = $Ptr.AddHours($OuterChunkHours)
                if ($OuterEnd -gt $QueryEnd) { $OuterEnd = $QueryEnd }
                Write-Log "  Outer chunk $Num/$TotalOuter : $($Ptr.ToString('yyyy-MM-dd HH:mm')) to $($OuterEnd.ToString('yyyy-MM-dd HH:mm'))" -Severity INFO

                $ChunkData = Invoke-UalChunkedQuery -ChunkStart $Ptr -ChunkEnd $OuterEnd `
                    -UserIds $UserIds -RecordType $RecordType -Operations $Operations
                if ($ChunkData) {
                    $AllRecords += $ChunkData
                    Write-Log "    Retrieved $($ChunkData.Count) record(s)." -Severity SUCCESS
                }
                else {
                    Write-Log "    No records in this window." -Severity DEBUG
                }
                $Ptr = $OuterEnd
            }

            if ($AllRecords.Count -gt 0) {
                # Project to a flat CSV-friendly shape with ET columns for CreationDate
                $Flat = $AllRecords | Select-Object -Property `
                    @{N='CreationDate'; E={ $_.CreationDate }},
                    RecordType, Operations, UserIds, UserType, ClientIP, UserAgent,
                    @{N='ObjectId'; E={ $_.ObjectId }},
                    ResultStatus, Identity, AuditData
                Export-DataWithManifest -Data $Flat -FilePath $OutputPath `
                    -Description $Label -Source "Search-UnifiedAuditLog" `
                    -TimeFields @('CreationDate')
            }
            else {
                Write-Log "  No records returned for $Label across all chunks." -Severity INFO
                # Still write an empty marker file? Yes - so the analyzer knows the collection ran.
                [PSCustomObject]@{ Note = "No records found in window"; QueryStart = $QueryStart; QueryEnd = $QueryEnd } |
                    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
                Add-EvidenceManifestEntry -FilePath $OutputPath -Description "$Label (empty)" -Source "Search-UnifiedAuditLog"
            }
        }

        Write-Section -Title "Unified Audit Log - ExchangeItem"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\UAL-ExchangeItem_${UserAlias}.csv" -Description "UAL ExchangeItem"
        if ($FA.Action -eq "Collect") {
            Invoke-UalCollection -Label "ExchangeItem" -OutputPath $FA.Path `
                -UserIds @($VictimEmail) -RecordType "ExchangeItem" `
                -QueryStart $StartDate -QueryEnd $EndDate
        }

        # ---- UAL: Rule manipulation events ----
        Write-Section -Title "Unified Audit Log - Rule Manipulation"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\UAL-RuleManipulation_${UserAlias}.csv" -Description "UAL Rule Manipulation"
        if ($FA.Action -eq "Collect") {
            Invoke-UalCollection -Label "Rule Manipulation" -OutputPath $FA.Path `
                -UserIds @($VictimEmail) `
                -Operations @('New-InboxRule','Set-InboxRule','Remove-InboxRule','Disable-InboxRule','Enable-InboxRule','UpdateInboxRules') `
                -QueryStart $StartDate -QueryEnd $EndDate
        }

        # ---- UAL: Send operations ----
        Write-Section -Title "Unified Audit Log - Send Operations"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\UAL-SendOperations_${UserAlias}.csv" -Description "UAL Send Operations"
        if ($FA.Action -eq "Collect") {
            Invoke-UalCollection -Label "Send Operations" -OutputPath $FA.Path `
                -UserIds @($VictimEmail) `
                -Operations @('Send','SendAs','SendOnBehalf') `
                -QueryStart $StartDate -QueryEnd $EndDate
        }

        # ---- UAL: MailItemsAccessed (best effort - requires Purview Audit Standard+) ----
        Write-Section -Title "Unified Audit Log - MailItemsAccessed (best-effort)"
        Write-Log     "Attempting MailItemsAccessed collection (requires E3/Business Premium/Purview Audit Standard+)" -Severity INFO
        Write-Console "Requires E3/Business Premium/Purview Audit Standard+ - may return no data on Business Standard or lower." -Severity INFO
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\UAL-MailItemsAccessed_${UserAlias}.csv" -Description "UAL MailItemsAccessed"
        if ($FA.Action -eq "Collect") {
            Invoke-UalCollection -Label "MailItemsAccessed" -OutputPath $FA.Path `
                -UserIds @($VictimEmail) `
                -Operations @('MailItemsAccessed') `
                -QueryStart $StartDate -QueryEnd $EndDate
        }

        # ---- UAL: SharePoint/OneDrive File Downloads (exfiltration indicator) ----
        Write-Section -Title "Unified Audit Log - File Downloads (SharePoint/OneDrive)"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\UAL-FileDownloads_${UserAlias}.csv" -Description "UAL File Downloads"
        if ($FA.Action -eq "Collect") {
            Invoke-UalCollection -Label "File Downloads" -OutputPath $FA.Path `
                -UserIds @($VictimEmail) `
                -Operations @('FileDownloaded','FileSyncDownloadedFull','FileAccessed','FileSyncUploadedFull') `
                -QueryStart $StartDate -QueryEnd $EndDate
        }

        # ---- UAL: Login events ----
        Write-Section -Title "Unified Audit Log - Login Events"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\UAL-Logins_${UserAlias}.csv" -Description "UAL Login Events"
        if ($FA.Action -eq "Collect") {
            Invoke-UalCollection -Label "Login Events" -OutputPath $FA.Path `
                -UserIds @($VictimEmail) `
                -Operations @('UserLoggedIn','UserLoginFailed') `
                -QueryStart $StartDate -QueryEnd $EndDate
        }

        # ---- UAL: MFA method changes (tenant-wide; filter for victim in analyzer) ----
        Write-Section -Title "Unified Audit Log - MFA / Auth Method Changes"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\UAL-MfaChanges.csv" -Description "UAL MFA Changes"
        if ($FA.Action -eq "Collect") {
            Invoke-UalCollection -Label "MFA / Auth Method Changes" -OutputPath $FA.Path `
                -Operations @('Update user.','Change user password.','Reset user password.','Set force change user password.','User registered security info','User changed default security info','User started security info registration','User deleted security info') `
                -QueryStart $StartDate -QueryEnd $EndDate
        }

        # ---- UAL: Role membership changes (tenant-wide) ----
        Write-Section -Title "Unified Audit Log - Role Membership Changes"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\UAL-RoleChanges.csv" -Description "UAL Role Changes"
        if ($FA.Action -eq "Collect") {
            Invoke-UalCollection -Label "Role Membership Changes" -OutputPath $FA.Path `
                -Operations @('Add member to role.','Remove member from role.','Add eligible member to role.','Remove eligible member from role.') `
                -QueryStart $StartDate -QueryEnd $EndDate
        }

        # ---- UAL: Conditional Access policy changes (tenant-wide) ----
        Write-Section -Title "Unified Audit Log - Conditional Access Changes"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\UAL-CAChanges.csv" -Description "UAL CA Changes"
        if ($FA.Action -eq "Collect") {
            Invoke-UalCollection -Label "Conditional Access Changes" -OutputPath $FA.Path `
                -Operations @('Add conditional access policy.','Update conditional access policy.','Delete conditional access policy.') `
                -QueryStart $StartDate -QueryEnd $EndDate
        }

        # ---- UAL: OAuth consent / app registration events ----
        Write-Section -Title "Unified Audit Log - OAuth Consents & App Registrations"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\UAL-OAuthConsents.csv" -Description "UAL OAuth Events"
        if ($FA.Action -eq "Collect") {
            Invoke-UalCollection -Label "OAuth Consents & App Events" -OutputPath $FA.Path `
                -Operations @('Consent to application.','Add OAuth2PermissionGrant.','Add delegated permission grant.','Add service principal.','Update service principal.','Add application.','Update application.') `
                -QueryStart $StartDate -QueryEnd $EndDate
        }

        # ======================================================================
        # MESSAGE TRACES
        # Quick trace via Get-MessageTraceV2 (0-10 days)
        # Historical trace via Start-HistoricalSearch (async, up to 90 days)
        # V1 fallback removed - legacy Reporting Webservice retires 2026-04-08
        # ======================================================================

        # ---- Quick traces: Get-MessageTraceV2 (last 10 days regardless of lookback) ----
        Write-Section -Title "Quick Message Traces (Get-MessageTraceV2, last 10 days)"
        $QuickStart = (Get-Date).AddDays(-10)
        $QuickEnd   = Get-Date
        $WarningPreference = "SilentlyContinue"

        # Verify Get-MessageTraceV2 is available
        $V2Available = $false
        try {
            $null = Get-Command -Name Get-MessageTraceV2 -ErrorAction Stop
            $V2Available = $true
        }
        catch {
            Write-Log     "Get-MessageTraceV2 not found. Update ExchangeOnlineManagement to 3.7.0+." -Severity ERROR
            Write-Console "Get-MessageTraceV2 not available. Skipping quick traces." -Severity ERROR -Indent 1
        }

        if ($V2Available) {
            # Paginated loop using StartingRecipientAddress cursor
            function Get-AllMessageTraceV2 {
                param (
                    [string]$Direction,  # 'Sent' or 'Received'
                    [string]$Email,
                    [datetime]$Start,
                    [datetime]$End
                )
                $All = @()
                $Cursor = $null
                $PageNum = 0
                do {
                    $PageNum++
                    $Params = @{
                        StartDate  = $Start
                        EndDate    = $End
                        ResultSize = 5000
                    }
                    if ($Direction -eq 'Sent') {
                        $Params['SenderAddress'] = $Email
                    }
                    else {
                        $Params['RecipientAddress'] = $Email
                    }
                    if ($Cursor) {
                        $Params['StartingRecipientAddress'] = $Cursor
                    }
                    try {
                        $Page = Get-MessageTraceV2 @Params -ErrorAction Stop
                    }
                    catch {
                        Write-Log "  Trace page $PageNum failed: $($_.Exception.Message)" -Severity ERROR
                        break
                    }
                    if ($Page) {
                        $All += $Page
                        if ($Page.Count -ge 5000) {
                            # Need another page - use the last recipient address as cursor
                            $Cursor = $Page[$Page.Count - 1].RecipientAddress
                        }
                        else {
                            $Cursor = $null
                        }
                    }
                    else {
                        $Cursor = $null
                    }
                } while ($Cursor)
                return $All
            }

            # Sent
            $FA = Get-OutputFileAction -BasePath "$RawDataPath\QuickTrace-Sent_${UserAlias}.csv" -Description "Quick Trace - Sent"
            if ($FA.Action -eq "Collect") {
                try {
                    $Sent = Get-AllMessageTraceV2 -Direction 'Sent' -Email $VictimEmail -Start $QuickStart -End $QuickEnd
                    if ($Sent) {
                        Export-DataWithManifest -Data $Sent -FilePath $FA.Path `
                            -Description "Quick Trace Sent (10d)" -Source "Get-MessageTraceV2" `
                            -TimeFields @('Received')
                    }
                    else {
                        Write-Log "  No sent messages in last 10 days." -Severity INFO
                    }
                }
                catch {
                    Write-Log "Quick trace (sent) failed: $($_.Exception.Message)" -Severity ERROR
                }
            }

            # Received
            $FA = Get-OutputFileAction -BasePath "$RawDataPath\QuickTrace-Received_${UserAlias}.csv" -Description "Quick Trace - Received"
            if ($FA.Action -eq "Collect") {
                try {
                    $Recv = Get-AllMessageTraceV2 -Direction 'Received' -Email $VictimEmail -Start $QuickStart -End $QuickEnd
                    if ($Recv) {
                        Export-DataWithManifest -Data $Recv -FilePath $FA.Path `
                            -Description "Quick Trace Received (10d)" -Source "Get-MessageTraceV2" `
                            -TimeFields @('Received')
                    }
                    else {
                        Write-Log "  No received messages in last 10 days." -Severity INFO
                    }
                }
                catch {
                    Write-Log "Quick trace (received) failed: $($_.Exception.Message)" -Severity ERROR
                }
            }
        }
        $WarningPreference = "Continue"

        # ---- Historical traces via Start-HistoricalSearch (always submitted per project spec) ----
        if (-not $SkipHistoricalTraces) {
            Write-Section -Title "Historical Message Traces (async submission)"
            Write-Log     "Submitting historical message trace jobs for full lookback window..." -Severity INFO
            Write-Console "Jobs take 15-30 minutes. Run Invoke-BECMessageTraceRetrieval.ps1 when ready." -Severity INFO
            try {
                # Historical search accepts up to 90 days. Cap StartDate if we exceed that.
                $HistMaxStart = (Get-Date).AddDays(-90)
                $HistStart = if ($StartDate -lt $HistMaxStart) { $HistMaxStart } else { $StartDate }
                $HistEnd   = $EndDate

                $Ts = Get-Date -Format 'yyyyMMdd-HHmmss'
                $SentName = "BEC-Sent-${UserAlias}-${Ts}"
                $RecvName = "BEC-Received-${UserAlias}-${Ts}"

                $SentParams = @{
                    ReportType    = "MessageTrace"
                    StartDate     = $HistStart
                    EndDate       = $HistEnd
                    ReportTitle   = $SentName
                    SenderAddress = $VictimEmail
                }
                if ($NotifyAddress) { $SentParams['NotifyAddress'] = $NotifyAddress }
                $SentTrace = Start-HistoricalSearch @SentParams

                $RecvParams = @{
                    ReportType       = "MessageTrace"
                    StartDate        = $HistStart
                    EndDate          = $HistEnd
                    ReportTitle      = $RecvName
                    RecipientAddress = $VictimEmail
                }
                if ($NotifyAddress) { $RecvParams['NotifyAddress'] = $NotifyAddress }
                $RecvTrace = Start-HistoricalSearch @RecvParams

                if ($SentTrace -and $RecvTrace) {
                    Write-Log     "Historical traces submitted." -Severity SUCCESS
                    Write-Console "Sent job    : $SentName" -Severity SUCCESS -Indent 1
                    Write-Console "Received job: $RecvName" -Severity SUCCESS -Indent 1
                    Write-Log "  Sent job ID: $($SentTrace.JobId)" -Severity DEBUG
                    Write-Log "  Recv job ID: $($RecvTrace.JobId)" -Severity DEBUG

                    [xml]$ConfigUpdate = Get-Content -Path $ConfigPath -Encoding UTF8
                    $ConfigUpdate.BECInvestigation.MessageTraces.SentTraceJobId     = $SentTrace.JobId.ToString()
                    $ConfigUpdate.BECInvestigation.MessageTraces.SentTraceName      = $SentName
                    $ConfigUpdate.BECInvestigation.MessageTraces.ReceivedTraceJobId = $RecvTrace.JobId.ToString()
                    $ConfigUpdate.BECInvestigation.MessageTraces.ReceivedTraceName  = $RecvName
                    $ConfigUpdate.BECInvestigation.MessageTraces.TracesInitiated    = "true"
                    $ConfigUpdate.Save($ConfigPath)
                }
            }
            catch {
                Write-Log     "Historical trace submission failed: $($_.Exception.Message)" -Severity ERROR
                Write-Console "Historical trace submission failed: $($_.Exception.Message)" -Severity ERROR -Indent 1
            }
        }
        else {
            Write-Log "Historical trace submission skipped (-SkipHistoricalTraces)." -Severity INFO
        }


        # ======================================================================
        # WRITE EVIDENCE MANIFEST
        # ======================================================================
        Write-Section -Title "Evidence Manifest"
        if ($script:EvidenceManifest.Count -gt 0) {
            $ManifestPath   = Join-Path -Path $AnalysisPath -ChildPath "Evidence-Manifest.csv"
            $ManifestReadme = Join-Path -Path $AnalysisPath -ChildPath "Evidence-Manifest-README.txt"
            try {
                $script:EvidenceManifest | Export-Csv -Path $ManifestPath -NoTypeInformation -Encoding UTF8
                Write-Log     "Evidence manifest written: $ManifestPath ($($script:EvidenceManifest.Count) artifacts)" -Severity SUCCESS
                Write-Console "Evidence manifest written ($($script:EvidenceManifest.Count) artifacts)." -Severity SUCCESS -Indent 1

                # README explaining what the manifest is and how to verify
                $ReadmeContent = @"
EVIDENCE MANIFEST - README
===========================
Investigation : $InvestigationID
Victim        : $VictimEmail
Generated     : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") / $(ConvertTo-EasternTime -UtcDateTime (Get-Date).ToUniversalTime())

PURPOSE
-------
The Evidence-Manifest.csv file records a SHA-256 hash of every artifact
collected during this BEC investigation. A SHA-256 hash is a unique
cryptographic fingerprint of the file contents. If any byte of an
artifact file is modified after collection, the hash will change.

The manifest supports:
  - Chain of custody documentation
  - Tamper detection (re-hash any file and compare to this manifest)
  - Evidence integrity claims in incident reports, insurance submissions,
    and law enforcement referrals

VERIFYING A FILE HASH
---------------------
From PowerShell on any workstation:

    Get-FileHash -Path <FullPathToFile> -Algorithm SHA256

Compare the returned hash to the SHA256 column in Evidence-Manifest.csv.
If they match, the file has not been altered since collection.

MANIFEST FIELDS
---------------
FileName         : Base filename of the artifact
RelativePath     : Path relative to the investigation root folder
Description      : Plain description of what the artifact contains
Source           : Cmdlet or API endpoint used to collect it
SizeBytes        : File size at collection time
CollectedUtc     : UTC timestamp when the hash was computed
CollectedEastern : Same timestamp in US Eastern time (handles DST)
SHA256           : 64-character hex SHA-256 hash

NOTES
-----
- Hashes are computed after each file is written. If a technician
  manually modifies a collected CSV, the hash will no longer match.
- The manifest itself is not hashed (it changes as collections are added).
  Consider hashing the manifest externally after collection completes
  if chain of custody is being asserted formally.
"@
                $ReadmeContent | Out-File -FilePath $ManifestReadme -Encoding UTF8
                Write-Log "Manifest README written." -Severity DEBUG
            }
            catch {
                Write-Log "Failed to write evidence manifest: $($_.Exception.Message)" -Severity ERROR
            }
        }
        else {
            Write-Log "No evidence artifacts collected (nothing to manifest)." -Severity WARN
        }

        # ======================================================================
        # UPDATE XML - MARK COLLECTION COMPLETE
        # ======================================================================
        try {
            [xml]$CFinal = Get-Content -Path $ConfigPath -Encoding UTF8
            $CFinal.BECInvestigation.DataCollection.Completed     = "true"
            $CFinal.BECInvestigation.DataCollection.CompletedDate = (Get-Date -Format "o")
            $CFinal.BECInvestigation.DataCollection.LookbackHours = $EffectiveHours.ToString()
            $CFinal.BECInvestigation.DataCollection.WindowStartUtc = $StartDate.ToUniversalTime().ToString("o")
            $CFinal.BECInvestigation.DataCollection.WindowEndUtc   = $EndDate.ToUniversalTime().ToString("o")
            $CFinal.Save($ConfigPath)
        }
        catch {
            Write-Log "Failed to update Investigation.xml: $($_.Exception.Message)" -Severity WARN
        }

        # Force-disconnect Exchange Online to leave a clean session state.
        # This is REQUIRED so that Invoke-BECGraphCollection.ps1 can authenticate
        # to Microsoft Graph without the MSAL/WAM assembly conflict that occurs
        # when both modules are loaded in the same session (GitHub msgraph-sdk-powershell#3576).
        Write-Log "Force-disconnecting Exchange Online to leave clean session for Graph collection." -Severity INFO
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

        Write-Banner -Title "DATA COLLECTION COMPLETE" -Color Green
        Write-Console "RawData : $RawDataPath" -Severity PLAIN -Indent 1
        Write-Console "Analysis: $AnalysisPath" -Severity PLAIN -Indent 1
        Write-Console "" -Severity PLAIN
        Write-Console "Next Steps:" -Severity INFO
        Write-Console "1. Open a NEW PowerShell 7 (pwsh) window - Graph SDK works best in PS7" -Severity WARN -Indent 1
        Write-Console "2. cd `"$($Config.BECInvestigation.Paths.ScriptsPath)`"" -Severity PLAIN -Indent 1
        Write-Console "3. pwsh>  .\Invoke-BECGraphCollection.ps1        (PS7 session)" -Severity PLAIN -Indent 1
        Write-Console "4. Return to THIS PowerShell 5 window for remaining steps:" -Severity INFO -Indent 1
        Write-Console "   .\Invoke-BECLogAnalysis.ps1 -SkipMessageTraces   (immediate triage)" -Severity PLAIN -Indent 1
        Write-Console "5. Wait ~30 min for historical traces to complete" -Severity PLAIN -Indent 1
        Write-Console "6. .\Invoke-BECMessageTraceRetrieval.ps1" -Severity PLAIN -Indent 1
        Write-Console "7. .\Invoke-BECLogAnalysis.ps1                      (full analysis)" -Severity PLAIN -Indent 1

        Write-Log "Data collection completed successfully." -Severity SUCCESS
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 0

    }
    catch {
        Write-Log "Unhandled exception: $_" -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Banner -Title "SCRIPT FAILED" -Color Red
        Write-Console "Error : $_" -Severity ERROR
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }

} # End function Invoke-BECDataCollection

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    LookbackHours        = $LookbackHours
    Scope                = $Scope
    SkipHistoricalTraces = $SkipHistoricalTraces
    DisableWAM           = $DisableWAM
}

Invoke-BECDataCollection @ScriptParams
'@

        # ----------------------------------------------------------------------
        # Invoke-BECGraphCollection.ps1 body (split from data collection;
        # PS7 recommended - see GitHub msgraph-sdk-powershell#3576)
        # ----------------------------------------------------------------------
        $GraphCollectionScript = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Collects Microsoft Graph (Entra ID) forensic evidence for a BEC investigation.

.DESCRIPTION
    Invoke-BECGraphCollection connects to Microsoft Graph and collects forensic
    artifacts that complement the Exchange Online data gathered by the separate
    Invoke-BECDataCollection.ps1 script. All configuration (victim email, output
    paths, lookback window, scope) is read from Investigation.xml in the parent folder.

    IMPORTANT: This script is deliberately separate from Invoke-BECDataCollection.ps1
    because ExchangeOnlineManagement and Microsoft.Graph modules have a long-standing
    MSAL/WAM assembly conflict (msgraph-sdk-powershell GitHub issue #3576) that
    prevents both from authenticating interactively in the same PowerShell session.
    Splitting the collection by module boundary is Microsoft's own recommended
    workaround.

    The script defensively calls Disconnect-ExchangeOnline at startup to clean any
    stale session. If it cannot authenticate to Graph, the most likely cause is a
    lingering ExchangeOnlineManagement assembly in the current process - close the
    PowerShell window and open a fresh one.

    Data collected:
      - Entra ID sign-in logs (interactive + non-interactive) with IP/location/risk
      - Risky users (Entra ID Protection)
      - Risk detections (AiTM, anomalous token, leaked credentials, malicious IP)
      - Current MFA / authentication methods per victim user
      - Directory role memberships for victim
      - Enterprise apps / service principals (flags CreatedInWindow=TRUE)
      - OAuth permission grants (delegated consents)
      - Conditional Access policies (point-in-time snapshot)

    Dual-timestamp columns: every CSV with a time field gets a sibling _ET column
    showing the same time in America/New_York local time (handles EST/EDT DST).

    Evidence manifest: SHA-256 hash of every collected artifact is appended to
    Analysis\Evidence-Manifest.csv (created by Invoke-BECDataCollection.ps1).

    Execution is logged to the investigation Logs folder via Start-Transcript.

.PARAMETER LookbackHours
    Optional. Overrides the lookback window from Investigation.xml. Specified in hours.

.PARAMETER Scope
    Optional. Named lookback preset: Recent (72h) / Standard (168h) / Extended (720h) / Maximum (2160h).
    If both -LookbackHours and -Scope are specified, -LookbackHours wins.
    Normally this script inherits the window that Invoke-BECDataCollection.ps1 used
    from Investigation.xml, but you can override here if needed.

.EXAMPLE
    .\Invoke-BECGraphCollection.ps1
    Collects Graph data using window previously set by Invoke-BECDataCollection.ps1.

.EXAMPLE
    .\Invoke-BECGraphCollection.ps1 -Scope Extended
    Overrides with 30-day window.

.NOTES
    File Name      : Invoke-BECGraphCollection.ps1
    Version        : {SCRIPT_VERSION}
    Author         : Sam Kirsch
    Contributors   : Sam Kirsch
    Company        : Databranch
    Created        : {CREATED_DATE}
    Last Modified  : {CREATED_DATE}
    Modified By    : Sam Kirsch

    Investigation  : {INVESTIGATION_ID}
    Victim         : {VICTIM_EMAIL}

    Requires       : PowerShell 5.1+
                     Microsoft.Graph.Authentication 2.0+ (auto-installed if missing)
    Run Context    : Interactive - Technician workstation (Global Admin)
    DattoRMM       : Not applicable
    Client Scope   : Per-investigation (generated script)

    Exit Codes:
        0  - Graph collection completed successfully
        1  - Runtime failure during collection (partial data may exist)
        2  - Fatal pre-flight failure (XML not found, Graph auth failed)

.CHANGELOG
    v{SCRIPT_VERSION} - {CREATED_DATE} - Sam Kirsch
        - Generated by Start-BECInvestigation.ps1 v{SCRIPT_VERSION}
        - Detects PowerShell edition at startup - warns if running Desktop (5.1)
          and recommends opening PowerShell 7 (pwsh) instead
        - Graph connect failure message tailored to PS5.1 vs PS7 context
        - Completion banner directs tech back to PowerShell 5 window for remaining steps
        - Initial release as separate script (split from Invoke-BECDataCollection.ps1)
        - Split required due to MSAL/WAM conflict between ExchangeOnlineManagement
          and Microsoft.Graph.* modules (msgraph-sdk-powershell GitHub issue #3576)
        - Defensive Disconnect-ExchangeOnline at startup to clear stale sessions
        - Interactive OAuth with Connect-MgGraph (browser popup)
        - 8 Graph collections: sign-ins, risky user, risk detections, MFA methods,
          role memberships, service principals (with CreatedInWindow flag),
          OAuth grants, Conditional Access policies
        - Dual-timestamp _ET columns on every time-bearing CSV
        - SHA-256 hashes appended to Evidence-Manifest.csv
        - Full template v1.4.1.0 compliance
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [int]$LookbackHours = 0,

    [Parameter(Mandatory = $false)]
    [ValidateSet('', 'Recent', 'Standard', 'Extended', 'Maximum')]
    [string]$Scope = ''
)

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# Must be AFTER param() so CmdletBinding remains the first executable statement.
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

function Invoke-BECGraphCollection {
    [CmdletBinding()]
    param (
        [int]$LookbackHours,
        [string]$Scope
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Invoke-BECGraphCollection"
    $ScriptVersion = "{SCRIPT_VERSION}"

    $MinGraphVersion = [Version]"2.0.0"

    $ScopePresets = @{
        'Recent'   = 72
        'Standard' = 168
        'Extended' = 720
        'Maximum'  = 2160
    }

    $EasternTZ = [System.TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')

    # ==========================================================================
    # XML CONFIGURATION READ
    # ==========================================================================
    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\Investigation.xml"
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Host "[ERROR] Investigation.xml not found at: $ConfigPath" -ForegroundColor Red
        Write-Host "[ERROR] Ensure you are running this script from the Scripts subfolder." -ForegroundColor Red
        exit 2
    }

    try {
        [xml]$Config = Get-Content -Path $ConfigPath -Encoding UTF8
    }
    catch {
        Write-Host "[ERROR] Failed to parse Investigation.xml: $($_.Exception.Message)" -ForegroundColor Red
        exit 2
    }

    $VictimEmail     = $Config.BECInvestigation.Victim.Email
    $UserAlias       = $Config.BECInvestigation.Victim.UserAlias
    $RawDataPath     = $Config.BECInvestigation.Paths.RawDataPath
    $LogsPath        = $Config.BECInvestigation.Paths.LogsPath
    $AnalysisPath    = $Config.BECInvestigation.Paths.AnalysisPath
    $InvestigationID = $Config.BECInvestigation.Investigation.InvestigationID

    $XmlErr = @()
    if (-not $VictimEmail)  { $XmlErr += "Victim.Email" }
    if (-not $UserAlias)    { $XmlErr += "Victim.UserAlias" }
    if (-not $RawDataPath)  { $XmlErr += "Paths.RawDataPath" }
    if (-not $LogsPath)     { $XmlErr += "Paths.LogsPath" }
    if (-not $AnalysisPath) { $XmlErr += "Paths.AnalysisPath" }
    if ($XmlErr.Count -gt 0) {
        Write-Host "[ERROR] Investigation.xml is missing required fields: $($XmlErr -join ', ')" -ForegroundColor Red
        exit 2
    }

    # ==========================================================================
    # DETERMINE LOOKBACK WINDOW
    # Priority: -LookbackHours > -Scope > XML > Recent default
    # ==========================================================================
    if ($LookbackHours -gt 0) {
        $EffectiveHours = $LookbackHours
        $ScopeSource    = "explicit -LookbackHours override"
    }
    elseif ($Scope) {
        $EffectiveHours = $ScopePresets[$Scope]
        $ScopeSource    = "-Scope $Scope preset"
    }
    elseif ($Config.BECInvestigation.DataCollection.LookbackHours -and
            [int]$Config.BECInvestigation.DataCollection.LookbackHours -gt 0) {
        $EffectiveHours = [int]$Config.BECInvestigation.DataCollection.LookbackHours
        $ScopeSource    = "XML DataCollection.LookbackHours (inherited from Exchange collection)"
    }
    else {
        $EffectiveHours = $ScopePresets['Recent']
        $ScopeSource    = "default (Recent = 72h)"
    }

    $EndDate   = Get-Date
    $StartDate = $EndDate.AddHours(-$EffectiveHours)

    # ==========================================================================
    # LOGGING SETUP
    # ==========================================================================
    $TranscriptTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $TranscriptPath      = Join-Path -Path $LogsPath -ChildPath "GraphCollection_${TranscriptTimestamp}.log"
    Start-Transcript -Path $TranscriptPath -ErrorAction SilentlyContinue | Out-Null

    function Write-Log {
        param (
            [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Message = "",
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
            [string]$Severity = "INFO"
        )
        $Ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Entry = "[$Ts] [$Severity] $Message"
        switch ($Severity) {
            "INFO"    { Write-Output  $Entry }
            "WARN"    { Write-Warning $Entry }
            "ERROR"   { Write-Error   $Entry -ErrorAction Continue }
            "SUCCESS" { Write-Output  $Entry }
            "DEBUG"   { Write-Output  $Entry }
        }
    }

    function Write-Console {
        param (
            [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Message = "",
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG","PLAIN")]
            [string]$Severity = "PLAIN",
            [Parameter(Mandatory = $false)] [int]$Indent = 0
        )
        $Prefix = "  " * $Indent
        $Colors = @{ INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; DEBUG="Magenta"; PLAIN="Gray" }
        $Color  = $Colors[$Severity]
        if ($Severity -eq "PLAIN") {
            Write-Host "$Prefix$Message" -ForegroundColor $Color
        }
        else {
            Write-Host "$Prefix" -NoNewline
            Write-Host "[$Severity]" -ForegroundColor $Color -NoNewline
            Write-Host " $Message" -ForegroundColor White
        }
    }

    function Write-Banner {
        param ([string]$Title, [string]$Color = "Cyan")
        $Line = "=" * 60
        Write-Host ""
        Write-Host $Line -ForegroundColor $Color
        Write-Host "  $Title" -ForegroundColor White
        Write-Host $Line -ForegroundColor $Color
        Write-Host ""
    }

    function Write-Section {
        param ([string]$Title, [string]$Color = "Cyan")
        $TitleStr = "---- $Title "
        $Padding  = "-" * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ""
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    function Write-Separator {
        param ([string]$Color = "DarkGray")
        Write-Host ("-" * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # HELPERS: Eastern time conversion + CSV column enrichment
    # ==========================================================================
    function ConvertTo-EasternTime {
        param ($UtcDateTime)
        if (-not $UtcDateTime) { return "" }
        try {
            $Dt = if ($UtcDateTime -is [DateTime]) {
                $UtcDateTime
            }
            else {
                [DateTime]::Parse($UtcDateTime.ToString(), [System.Globalization.CultureInfo]::InvariantCulture,
                                  [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                                  [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            }
            if ($Dt.Kind -ne [DateTimeKind]::Utc) {
                $Dt = [DateTime]::SpecifyKind($Dt, [DateTimeKind]::Utc)
            }
            $Et = [System.TimeZoneInfo]::ConvertTimeFromUtc($Dt, $EasternTZ)
            $TzAbbr = if ($EasternTZ.IsDaylightSavingTime($Et)) { "EDT" } else { "EST" }
            return ("{0} {1}" -f $Et.ToString("yyyy-MM-dd HH:mm:ss"), $TzAbbr)
        }
        catch {
            return ""
        }
    }

    function Add-EasternTimeColumns {
        param (
            [Parameter(Mandatory = $true)] $Data,
            [Parameter(Mandatory = $true)] [string[]]$TimeFields
        )
        if (-not $Data) { return $Data }
        $Result = foreach ($Row in $Data) {
            $NewRow = [ordered]@{}
            foreach ($Prop in $Row.PSObject.Properties) {
                $NewRow[$Prop.Name] = $Prop.Value
                if ($TimeFields -contains $Prop.Name) {
                    $EtColName = $Prop.Name + "_ET"
                    $NewRow[$EtColName] = ConvertTo-EasternTime -UtcDateTime $Prop.Value
                }
            }
            [PSCustomObject]$NewRow
        }
        return $Result
    }

    # ==========================================================================
    # EVIDENCE MANIFEST HELPERS (append mode since manifest pre-exists)
    # ==========================================================================
    function Get-FileSha256 {
        param ([string]$Path)
        try { return (Get-FileHash -Path $Path -Algorithm SHA256 -ErrorAction Stop).Hash }
        catch { return "" }
    }

    function Add-ManifestEntry {
        param (
            [string]$FilePath,
            [string]$Description,
            [string]$Source
        )
        $ManifestPath = Join-Path -Path $AnalysisPath -ChildPath "Evidence-Manifest.csv"
        if (-not (Test-Path -Path $FilePath)) { return }
        try {
            $FileInfo = Get-Item -Path $FilePath
            $Hash     = Get-FileSha256 -Path $FilePath
            $UtcNow   = (Get-Date).ToUniversalTime()
            $Entry = [PSCustomObject]@{
                FileName         = $FileInfo.Name
                RelativePath     = $FilePath.Replace($Config.BECInvestigation.Paths.RootPath, '').TrimStart('\')
                Description      = $Description
                Source           = $Source
                SizeBytes        = $FileInfo.Length
                CollectedUtc     = $UtcNow.ToString("yyyy-MM-dd HH:mm:ss") + " UTC"
                CollectedEastern = ConvertTo-EasternTime -UtcDateTime $UtcNow
                SHA256           = $Hash
            }
            if (Test-Path -Path $ManifestPath) {
                $Existing = @(Import-Csv -Path $ManifestPath)
                $Existing = $Existing | Where-Object { $_.FileName -ne $FileInfo.Name }
                $Combined = @($Existing) + @($Entry)
                $Combined | Export-Csv -Path $ManifestPath -NoTypeInformation -Encoding UTF8
            }
            else {
                @($Entry) | Export-Csv -Path $ManifestPath -NoTypeInformation -Encoding UTF8
            }
        }
        catch {
            Write-Log "Could not update manifest for $FilePath : $($_.Exception.Message)" -Severity WARN
        }
    }

    # ==========================================================================
    # FILE CONFLICT HANDLER + CSV EXPORTER
    # ==========================================================================
    function Get-OutputFileAction {
        param ([string]$BasePath, [string]$Description)
        if (Test-Path -Path $BasePath) {
            Write-Log     "File already exists: $(Split-Path -Path $BasePath -Leaf)" -Severity WARN
            Write-Console "File already exists: $(Split-Path -Path $BasePath -Leaf)" -Severity WARN
            $Choice = Read-Host "  [O]verwrite, [D]uplicate (versioned), or [S]kip $Description? [O/D/S]"
            switch ($Choice.ToUpper()) {
                "O" {
                    return @{ Action = "Collect"; Path = $BasePath }
                }
                "D" {
                    $Dir     = Split-Path -Path $BasePath -Parent
                    $Name    = [System.IO.Path]::GetFileNameWithoutExtension($BasePath)
                    $Ext     = [System.IO.Path]::GetExtension($BasePath)
                    $Version = 2
                    while (Test-Path -Path (Join-Path -Path $Dir -ChildPath "${Name}_v${Version}${Ext}")) {
                        $Version++
                    }
                    return @{ Action = "Collect"; Path = (Join-Path -Path $Dir -ChildPath "${Name}_v${Version}${Ext}") }
                }
                default {
                    return @{ Action = "Skip"; Path = $null }
                }
            }
        }
        return @{ Action = "Collect"; Path = $BasePath }
    }

    function Export-DataWithManifest {
        param (
            $Data,
            [string]$FilePath,
            [string]$Description,
            [string]$Source,
            [string[]]$TimeFields = @()
        )
        try {
            if ($Data) {
                if ($TimeFields.Count -gt 0) {
                    $Data = Add-EasternTimeColumns -Data $Data -TimeFields $TimeFields
                }
                $Data | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
                $Count = ($Data | Measure-Object).Count
                Add-ManifestEntry -FilePath $FilePath -Description $Description -Source $Source
                Write-Log     "  $Description : $Count record(s) -> $(Split-Path -Path $FilePath -Leaf)" -Severity SUCCESS
                Write-Console "$Description : $Count record(s)" -Severity SUCCESS -Indent 1
                return $true
            }
            else {
                Write-Log     "  $Description : No data found." -Severity INFO
                Write-Console "$Description : No data found." -Severity INFO -Indent 1
                return $false
            }
        }
        catch {
            Write-Log     "  $Description : Export failed - $($_.Exception.Message)" -Severity ERROR
            Write-Console "$Description : Export failed - $($_.Exception.Message)" -Severity ERROR -Indent 1
            return $false
        }
    }

    function Get-AllGraphPages {
        param ([string]$Uri, [int]$MaxPages = 50)
        $All = @()
        $Pages = 0
        $CurrentUri = $Uri
        while ($CurrentUri -and $Pages -lt $MaxPages) {
            $Pages++
            try {
                $Resp = Invoke-MgGraphRequest -Method GET -Uri $CurrentUri -ErrorAction Stop
                if ($Resp.value) {
                    $All += $Resp.value
                }
                elseif ($Resp -and -not $Resp.PSObject.Properties['value']) {
                    $All += $Resp
                }
                $CurrentUri = $Resp.'@odata.nextLink'
            }
            catch {
                Write-Log "  Graph pagination error on page $Pages`: $($_.Exception.Message)" -Severity WARN
                break
            }
        }
        return $All
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = "Continue"

    Write-Banner -Title "BEC GRAPH COLLECTION v$ScriptVersion" -Color Cyan
    Write-Console "Investigation : $InvestigationID" -Severity PLAIN
    Write-Console "Victim        : $VictimEmail" -Severity PLAIN
    Write-Console "Lookback      : $EffectiveHours hours via $ScopeSource" -Severity PLAIN
    Write-Console "Transcript    : $TranscriptPath" -Severity PLAIN
    Write-Console "PS Edition    : $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)" -Severity PLAIN
    Write-Separator

    # Warn if running in PowerShell 5.1 - Graph SDK is officially compatible but
    # field experience shows assembly-loading flakiness there. PS7 is Microsoft's
    # recommended edition for the Graph SDK.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        Write-Console "" -Severity PLAIN
        Write-Console "NOTE: You are running Windows PowerShell 5.1 (Desktop edition)." -Severity WARN
        Write-Console "Microsoft recommends PowerShell 7 (pwsh) for the Graph SDK." -Severity WARN
        Write-Console "If authentication fails below, close this window, open PowerShell 7" -Severity WARN
        Write-Console "(search 'pwsh' in Start Menu), and re-run this script there." -Severity WARN
        Write-Console "" -Severity PLAIN
        Write-Log "PowerShell 5.1 detected - Graph SDK may exhibit assembly-loading issues. PS7 recommended." -Severity WARN
    }

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Investigation : $InvestigationID" -Severity INFO
    Write-Log "Victim        : $VictimEmail" -Severity INFO
    Write-Log "Lookback      : $EffectiveHours hours via $ScopeSource" -Severity INFO
    Write-Log "PS Edition    : $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)" -Severity INFO

    try {
        # ======================================================================
        # DEFENSIVE: FORCE-DISCONNECT EXCHANGE ONLINE IF PRESENT
        # Graph and ExchangeOnlineManagement share assemblies (MSAL/WAM). Even if
        # you ran Invoke-BECDataCollection.ps1 previously and it disconnected
        # cleanly, this belt-and-suspenders step ensures nothing is lingering.
        # If this is a fresh PowerShell session, the cmdlet won't exist and the
        # call silently no-ops.
        # ======================================================================
        Write-Section -Title "Clearing Stale Exchange Online Sessions"
        try {
            if (Get-Command -Name Disconnect-ExchangeOnline -ErrorAction SilentlyContinue) {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                Write-Log     "Disconnect-ExchangeOnline invoked as defensive measure." -Severity DEBUG
                Write-Console "Defensive EXO disconnect done." -Severity INFO -Indent 1
            }
            else {
                Write-Log "No Exchange Online cmdlet present in session (clean start)." -Severity DEBUG
                Write-Console "Clean session - no EXO module loaded." -Severity SUCCESS -Indent 1
            }
        }
        catch {
            Write-Log "Defensive disconnect raised non-fatal error: $($_.Exception.Message)" -Severity DEBUG
        }

        # ======================================================================
        # MODULE CHECK - Microsoft.Graph.Authentication
        # ======================================================================
        Write-Section -Title "Module Check"
        Write-Log     "Checking Microsoft.Graph.Authentication module (required: $MinGraphVersion or later)..." -Severity INFO
        Write-Console "Checking Microsoft.Graph.Authentication..." -Severity INFO

        $GraphMod = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication |
                    Sort-Object -Property Version -Descending |
                    Select-Object -First 1

        if (-not $GraphMod) {
            Write-Log     "Microsoft.Graph.Authentication not found. Installing..." -Severity WARN
            Write-Console "Installing Microsoft.Graph.Authentication (this may take a moment)..." -Severity WARN -Indent 1
            try {
                Install-Module -Name Microsoft.Graph.Authentication -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                Write-Log     "Microsoft.Graph.Authentication installed." -Severity SUCCESS
            }
            catch {
                Write-Log     "Failed to install Microsoft.Graph.Authentication: $($_.Exception.Message)" -Severity ERROR
                Write-Console "Failed to install Graph module - cannot continue." -Severity ERROR -Indent 1
                Write-Banner -Title "FATAL - MODULE INSTALL FAILED" -Color Red
                Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
                exit 2
            }
        }
        else {
            Write-Log     "Microsoft.Graph.Authentication v$($GraphMod.Version) found." -Severity SUCCESS
            Write-Console "Microsoft.Graph.Authentication v$($GraphMod.Version) OK." -Severity SUCCESS -Indent 1
        }

        # Supporting submodules - install individually if missing
        $GraphSubmodules = @(
            'Microsoft.Graph.Reports',
            'Microsoft.Graph.Identity.SignIns',
            'Microsoft.Graph.Identity.DirectoryManagement',
            'Microsoft.Graph.Applications',
            'Microsoft.Graph.Users'
        )
        foreach ($SubMod in $GraphSubmodules) {
            if (-not (Get-Module -ListAvailable -Name $SubMod)) {
                Write-Log     "Installing $SubMod..." -Severity INFO
                Write-Console "Installing $SubMod..." -Severity INFO -Indent 1
                try {
                    Install-Module -Name $SubMod -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                    Write-Log "  Installed: $SubMod" -Severity SUCCESS
                }
                catch {
                    Write-Log     "  Failed to install $SubMod : $($_.Exception.Message)" -Severity WARN
                    Write-Console "Failed to install $SubMod - some collections may be skipped." -Severity WARN -Indent 2
                }
            }
        }

        # ======================================================================
        # CONNECT TO MICROSOFT GRAPH
        # ======================================================================
        Write-Section -Title "Connecting to Microsoft Graph"
        Write-Log     "Connecting to Microsoft Graph (read-only scopes)..." -Severity INFO
        Write-Console "A browser window will prompt for consent to read-only Graph scopes..." -Severity INFO

        $GraphScopes = @(
            'AuditLog.Read.All',
            'Directory.Read.All',
            'IdentityRiskyUser.Read.All',
            'IdentityRiskEvent.Read.All',
            'Application.Read.All',
            'UserAuthenticationMethod.Read.All',
            'Policy.Read.All',
            'RoleManagement.Read.Directory'
        )
        try {
            Import-Module -Name Microsoft.Graph.Authentication -ErrorAction Stop
            Connect-MgGraph -Scopes $GraphScopes -NoWelcome -ErrorAction Stop
            $GraphContext = Get-MgContext
            if ($GraphContext) {
                Write-Log     "Connected to Microsoft Graph as: $($GraphContext.Account)" -Severity SUCCESS
                Write-Log     "  Tenant: $($GraphContext.TenantId)" -Severity DEBUG
                Write-Console "Connected to Graph as $($GraphContext.Account)" -Severity SUCCESS -Indent 1
            }
        }
        catch {
            Write-Log     "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -Severity ERROR
            Write-Console "Graph connection failed: $($_.Exception.Message)" -Severity ERROR -Indent 1
            Write-Console "" -Severity PLAIN
            if ($PSVersionTable.PSEdition -eq 'Desktop') {
                Write-Console "You are in Windows PowerShell 5.1. The Graph SDK is flaky there." -Severity WARN
                Write-Console "FIX: Close this window, open PowerShell 7 (search 'pwsh' in Start Menu)," -Severity WARN
                Write-Console "     cd to this Scripts folder, then re-run:  .\Invoke-BECGraphCollection.ps1" -Severity WARN
            }
            else {
                Write-Console "If you just ran Invoke-BECDataCollection.ps1 in this same PowerShell window," -Severity WARN
                Write-Console "the Exchange Online assemblies may still be loaded in the process and are" -Severity WARN
                Write-Console "blocking Graph authentication. FIX: Close this window, open a fresh PS7" -Severity WARN
                Write-Console "window (pwsh), and re-run this script." -Severity WARN
            }
            Write-Console "This is a known limitation - GitHub issue msgraph-sdk-powershell#3576." -Severity PLAIN
            Write-Banner -Title "FATAL - GRAPH CONNECT FAILED" -Color Red
            Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
            exit 2
        }

        # Resolve victim user ID for /users/{id}/... calls
        $VictimUserId = $null
        try {
            $VictimUser = Invoke-MgGraphRequest -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/users/$VictimEmail" -ErrorAction Stop
            $VictimUserId = $VictimUser.id
            Write-Log "Victim Graph object ID resolved: $VictimUserId" -Severity DEBUG
        }
        catch {
            Write-Log     "Could not resolve victim user in Graph: $($_.Exception.Message)" -Severity WARN
            Write-Console "Could not resolve victim user in Graph - user-specific collections will be skipped." -Severity WARN -Indent 1
        }

        Write-Banner -Title "MICROSOFT GRAPH COLLECTIONS" -Color Cyan

        # ---- Sign-in logs (last 30 days max per Graph retention) ----
        Write-Section -Title "Graph - Sign-In Logs"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\Graph-SignIns_${UserAlias}.csv" -Description "Graph Sign-In Logs"
        if ($FA.Action -eq "Collect") {
            try {
                $GraphSignInStart = if ($StartDate -lt (Get-Date).AddDays(-30)) {
                    (Get-Date).AddDays(-30)
                } else {
                    $StartDate
                }
                $FilterStart = $GraphSignInStart.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                $SafeEmail = $VictimEmail -replace "'", "''"
                $Filter = "userPrincipalName eq '$SafeEmail' and createdDateTime ge $FilterStart"
                $EncodedFilter = [System.Net.WebUtility]::UrlEncode($Filter)
                $Uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=$EncodedFilter&`$top=1000"

                $SignIns = Get-AllGraphPages -Uri $Uri
                if ($SignIns) {
                    $SIData = $SignIns | ForEach-Object {
                        [PSCustomObject]@{
                            createdDateTime      = $_.createdDateTime
                            userPrincipalName    = $_.userPrincipalName
                            userDisplayName      = $_.userDisplayName
                            appDisplayName       = $_.appDisplayName
                            clientAppUsed        = $_.clientAppUsed
                            ipAddress            = $_.ipAddress
                            location_city        = $_.location.city
                            location_state       = $_.location.state
                            location_country     = $_.location.countryOrRegion
                            deviceDetail_browser = $_.deviceDetail.browser
                            deviceDetail_os      = $_.deviceDetail.operatingSystem
                            deviceDetail_display = $_.deviceDetail.displayName
                            status_errorCode     = $_.status.errorCode
                            status_failureReason = $_.status.failureReason
                            conditionalAccessStatus = $_.conditionalAccessStatus
                            riskDetail           = $_.riskDetail
                            riskLevelAggregated  = $_.riskLevelAggregated
                            riskLevelDuringSignIn = $_.riskLevelDuringSignIn
                            riskState            = $_.riskState
                            riskEventTypes_v2    = ($_.riskEventTypes_v2 -join '|')
                            correlationId        = $_.correlationId
                            sessionId            = $_.sessionId
                            isInteractive        = $_.isInteractive
                            authenticationRequirement = $_.authenticationRequirement
                        }
                    }
                    Export-DataWithManifest -Data $SIData -FilePath $FA.Path `
                        -Description "Graph Sign-In Logs" -Source "Graph /auditLogs/signIns" `
                        -TimeFields @('createdDateTime')
                }
                else {
                    Write-Log "  No sign-in events returned in window." -Severity INFO
                }
            }
            catch {
                Write-Log     "Sign-in log collection failed: $($_.Exception.Message)" -Severity ERROR
                Write-Console "Sign-in log collection failed: $($_.Exception.Message)" -Severity ERROR -Indent 1
            }
        }

        # ---- Risky users ----
        Write-Section -Title "Graph - Risky Users"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\Graph-RiskyUser_${UserAlias}.csv" -Description "Graph Risky User"
        if ($FA.Action -eq "Collect") {
            try {
                $SafeEmail = $VictimEmail -replace "'", "''"
                $Filter = "userPrincipalName eq '$SafeEmail'"
                $EncodedFilter = [System.Net.WebUtility]::UrlEncode($Filter)
                $Uri = "https://graph.microsoft.com/v1.0/identityProtection/riskyUsers?`$filter=$EncodedFilter"
                $RiskyUsers = Get-AllGraphPages -Uri $Uri
                if ($RiskyUsers) {
                    $Flat = $RiskyUsers | Select-Object -Property id, userPrincipalName, userDisplayName,
                        isDeleted, isProcessing, riskLevel, riskState, riskDetail,
                        riskLastUpdatedDateTime
                    Export-DataWithManifest -Data $Flat -FilePath $FA.Path `
                        -Description "Risky User (victim)" -Source "Graph /identityProtection/riskyUsers" `
                        -TimeFields @('riskLastUpdatedDateTime')
                }
                else {
                    Write-Log "  Victim not present in risky users list." -Severity INFO
                }
            }
            catch {
                Write-Log "Risky user collection failed: $($_.Exception.Message)" -Severity WARN
            }
        }

        # ---- Risk detections for victim ----
        Write-Section -Title "Graph - Risk Detections"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\Graph-RiskDetections_${UserAlias}.csv" -Description "Graph Risk Detections"
        if ($FA.Action -eq "Collect") {
            try {
                $SafeEmail = $VictimEmail -replace "'", "''"
                $FilterStart = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                $Filter = "userPrincipalName eq '$SafeEmail' and detectedDateTime ge $FilterStart"
                $EncodedFilter = [System.Net.WebUtility]::UrlEncode($Filter)
                $Uri = "https://graph.microsoft.com/v1.0/identityProtection/riskDetections?`$filter=$EncodedFilter"
                $RiskDetections = Get-AllGraphPages -Uri $Uri
                if ($RiskDetections) {
                    $Flat = $RiskDetections | Select-Object -Property id, requestId, correlationId,
                        riskType, riskEventType, riskState, riskLevel, riskDetail,
                        source, detectionTimingType, activity, tokenIssuerType,
                        ipAddress, activityDateTime, detectedDateTime, lastUpdatedDateTime,
                        userId, userDisplayName, userPrincipalName,
                        @{N='location_city';    E={ $_.location.city }},
                        @{N='location_state';   E={ $_.location.state }},
                        @{N='location_country'; E={ $_.location.countryOrRegion }},
                        additionalInfo
                    Export-DataWithManifest -Data $Flat -FilePath $FA.Path `
                        -Description "Risk Detections (victim)" -Source "Graph /identityProtection/riskDetections" `
                        -TimeFields @('activityDateTime','detectedDateTime','lastUpdatedDateTime')
                }
                else {
                    Write-Log "  No risk detections for victim in window." -Severity INFO
                }
            }
            catch {
                Write-Log "Risk detection collection failed: $($_.Exception.Message)" -Severity WARN
            }
        }

        # ---- MFA Authentication Methods ----
        Write-Section -Title "Graph - MFA / Authentication Methods"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\Graph-MfaMethods_${UserAlias}.csv" -Description "Graph MFA Methods"
        if ($FA.Action -eq "Collect" -and $VictimUserId) {
            try {
                $Uri = "https://graph.microsoft.com/v1.0/users/$VictimUserId/authentication/methods"
                $Methods = Get-AllGraphPages -Uri $Uri
                if ($Methods) {
                    $Flat = $Methods | ForEach-Object {
                        [PSCustomObject]@{
                            id                  = $_.id
                            methodType          = ($_.'@odata.type' -replace '#microsoft.graph.', '')
                            displayName         = $_.displayName
                            deviceTag           = $_.deviceTag
                            phoneNumber         = $_.phoneNumber
                            phoneType           = $_.phoneType
                            emailAddress        = $_.emailAddress
                            createdDateTime     = $_.createdDateTime
                            clientAppName       = $_.clientAppName
                            smsSignInState      = $_.smsSignInState
                        }
                    }
                    Export-DataWithManifest -Data $Flat -FilePath $FA.Path `
                        -Description "MFA / Auth Methods (current)" -Source "Graph /users/{id}/authentication/methods" `
                        -TimeFields @('createdDateTime')
                }
                else {
                    Write-Log "  No auth methods returned." -Severity INFO
                }
            }
            catch {
                Write-Log "MFA method collection failed: $($_.Exception.Message)" -Severity WARN
            }
        }

        # ---- Directory role memberships for victim ----
        Write-Section -Title "Graph - Role Memberships"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\Graph-RoleMemberships_${UserAlias}.csv" -Description "Graph Role Memberships"
        if ($FA.Action -eq "Collect" -and $VictimUserId) {
            try {
                $Uri = "https://graph.microsoft.com/v1.0/users/$VictimUserId/memberOf"
                $Memberships = Get-AllGraphPages -Uri $Uri
                if ($Memberships) {
                    $Flat = $Memberships | ForEach-Object {
                        [PSCustomObject]@{
                            id          = $_.id
                            type        = ($_.'@odata.type' -replace '#microsoft.graph.', '')
                            displayName = $_.displayName
                            description = $_.description
                            roleTemplateId = $_.roleTemplateId
                        }
                    }
                    Export-DataWithManifest -Data $Flat -FilePath $FA.Path `
                        -Description "Directory/Role Memberships (victim)" -Source "Graph /users/{id}/memberOf"
                    $DirRoles = $Flat | Where-Object { $_.type -eq 'directoryRole' }
                    if ($DirRoles) {
                        Write-Log     "  WARNING: Victim is a member of $($DirRoles.Count) directory role(s) - review." -Severity WARN
                        Write-Console "Victim has $($DirRoles.Count) directory role membership(s) - review." -Severity WARN -Indent 1
                    }
                }
                else {
                    Write-Log "  No memberships returned." -Severity INFO
                }
            }
            catch {
                Write-Log "Role membership collection failed: $($_.Exception.Message)" -Severity WARN
            }
        }

        # ---- Enterprise Apps / Service Principals (flag new ones) ----
        Write-Section -Title "Graph - Enterprise Apps / Service Principals"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\Graph-ServicePrincipals.csv" -Description "Graph Service Principals"
        if ($FA.Action -eq "Collect") {
            try {
                $Uri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$top=999&`$select=id,appId,displayName,createdDateTime,servicePrincipalType,accountEnabled,appOwnerOrganizationId,homepage,signInAudience,publisherName,verifiedPublisher,tags"
                $SPs = Get-AllGraphPages -Uri $Uri -MaxPages 20
                if ($SPs) {
                    $Flat = $SPs | ForEach-Object {
                        [PSCustomObject]@{
                            id                     = $_.id
                            appId                  = $_.appId
                            displayName            = $_.displayName
                            servicePrincipalType   = $_.servicePrincipalType
                            accountEnabled         = $_.accountEnabled
                            appOwnerOrganizationId = $_.appOwnerOrganizationId
                            homepage               = $_.homepage
                            signInAudience         = $_.signInAudience
                            publisherName          = $_.publisherName
                            verifiedPublisher      = $_.verifiedPublisher.displayName
                            createdDateTime        = $_.createdDateTime
                            tags                   = ($_.tags -join '|')
                            CreatedInWindow        = if ($_.createdDateTime -and ([DateTime]$_.createdDateTime) -ge $StartDate) { "TRUE" } else { "FALSE" }
                        }
                    }
                    Export-DataWithManifest -Data $Flat -FilePath $FA.Path `
                        -Description "Service Principals / Enterprise Apps" -Source "Graph /servicePrincipals" `
                        -TimeFields @('createdDateTime')
                    $NewSPs = $Flat | Where-Object { $_.CreatedInWindow -eq "TRUE" }
                    if ($NewSPs) {
                        Write-Log     "  WARNING: $($NewSPs.Count) service principal(s) created in investigation window - review for OAuth phishing." -Severity WARN
                        Write-Console "$($NewSPs.Count) service principal(s) created during window - review." -Severity WARN -Indent 1
                    }
                }
                else {
                    Write-Log "  No service principals returned." -Severity INFO
                }
            }
            catch {
                Write-Log "Service principal collection failed: $($_.Exception.Message)" -Severity WARN
            }
        }

        # ---- OAuth permission grants ----
        Write-Section -Title "Graph - OAuth Permission Grants"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\Graph-OAuthGrants.csv" -Description "Graph OAuth Grants"
        if ($FA.Action -eq "Collect") {
            try {
                $Uri = "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$top=999"
                $Grants = Get-AllGraphPages -Uri $Uri -MaxPages 20
                if ($Grants) {
                    $Flat = $Grants | Select-Object -Property id, clientId, consentType, principalId,
                        resourceId, scope, startTime, expiryTime
                    Export-DataWithManifest -Data $Flat -FilePath $FA.Path `
                        -Description "OAuth Permission Grants" -Source "Graph /oauth2PermissionGrants" `
                        -TimeFields @('startTime','expiryTime')
                }
                else {
                    Write-Log "  No OAuth grants returned." -Severity INFO
                }
            }
            catch {
                Write-Log "OAuth grant collection failed: $($_.Exception.Message)" -Severity WARN
            }
        }

        # ---- Conditional Access policies (snapshot) ----
        Write-Section -Title "Graph - Conditional Access Policies"
        $FA = Get-OutputFileAction -BasePath "$RawDataPath\Graph-ConditionalAccess.csv" -Description "Graph CA Policies"
        if ($FA.Action -eq "Collect") {
            try {
                $Uri = "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"
                $Policies = Get-AllGraphPages -Uri $Uri
                if ($Policies) {
                    $Flat = $Policies | ForEach-Object {
                        [PSCustomObject]@{
                            id                  = $_.id
                            displayName         = $_.displayName
                            state               = $_.state
                            createdDateTime     = $_.createdDateTime
                            modifiedDateTime    = $_.modifiedDateTime
                            includeUsers        = ($_.conditions.users.includeUsers -join '|')
                            excludeUsers        = ($_.conditions.users.excludeUsers -join '|')
                            includeGroups       = ($_.conditions.users.includeGroups -join '|')
                            excludeGroups       = ($_.conditions.users.excludeGroups -join '|')
                            includeApplications = ($_.conditions.applications.includeApplications -join '|')
                            grantControls       = ($_.grantControls.builtInControls -join '|')
                            clientAppTypes      = ($_.conditions.clientAppTypes -join '|')
                        }
                    }
                    Export-DataWithManifest -Data $Flat -FilePath $FA.Path `
                        -Description "Conditional Access Policies" -Source "Graph /identity/conditionalAccess/policies" `
                        -TimeFields @('createdDateTime','modifiedDateTime')
                    $RecentlyModified = $Flat | Where-Object {
                        $_.modifiedDateTime -and ([DateTime]$_.modifiedDateTime) -ge $StartDate
                    }
                    if ($RecentlyModified) {
                        Write-Log     "  WARNING: $($RecentlyModified.Count) CA policy(ies) modified in window - review." -Severity WARN
                        Write-Console "$($RecentlyModified.Count) CA policy(ies) modified in window - review." -Severity WARN -Indent 1
                    }
                }
                else {
                    Write-Log "  No CA policies returned." -Severity INFO
                }
            }
            catch {
                Write-Log "CA policy collection failed: $($_.Exception.Message)" -Severity WARN
            }
        }

        # ======================================================================
        # UPDATE XML
        # ======================================================================
        try {
            [xml]$CFinal = Get-Content -Path $ConfigPath -Encoding UTF8
            $CFinal.BECInvestigation.GraphCollection.Completed     = "true"
            $CFinal.BECInvestigation.GraphCollection.CompletedDate = (Get-Date -Format "o")
            $CFinal.Save($ConfigPath)
        }
        catch {
            Write-Log "Failed to update Investigation.xml: $($_.Exception.Message)" -Severity WARN
        }

        # Disconnect Graph
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

        Write-Banner -Title "GRAPH COLLECTION COMPLETE" -Color Green
        Write-Console "RawData : $RawDataPath" -Severity PLAIN -Indent 1
        Write-Console "" -Severity PLAIN
        Write-Console "Next Steps:" -Severity INFO
        Write-Console "Close this PowerShell 7 window and RETURN to your PowerShell 5 window" -Severity WARN -Indent 1
        Write-Console "(the one where you ran Invoke-BECDataCollection.ps1). Then:" -Severity PLAIN -Indent 1
        Write-Console "  1. .\Invoke-BECLogAnalysis.ps1 -SkipMessageTraces   (immediate triage)" -Severity PLAIN -Indent 1
        Write-Console "  2. Wait ~30 min for historical traces to complete" -Severity PLAIN -Indent 1
        Write-Console "  3. .\Invoke-BECMessageTraceRetrieval.ps1" -Severity PLAIN -Indent 1
        Write-Console "  4. .\Invoke-BECLogAnalysis.ps1                      (full analysis)" -Severity PLAIN -Indent 1

        Write-Log "Graph collection completed successfully." -Severity SUCCESS
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 0
    }
    catch {
        Write-Log "Unhandled exception: $_" -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Banner -Title "GRAPH COLLECTION FAILED" -Color Red
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }

} # End function Invoke-BECGraphCollection

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    LookbackHours = $LookbackHours
    Scope         = $Scope
}

Invoke-BECGraphCollection @ScriptParams
'@

        # ----------------------------------------------------------------------
        # Invoke-BECLogAnalysis.ps1 body
        # ----------------------------------------------------------------------
        $AnalysisScript = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Analyzes collected BEC investigation data and produces a severity-ranked findings report.

.DESCRIPTION
    Invoke-BECLogAnalysis reads all CSV files from the investigation RawData folder
    and analyzes them for indicators of compromise. All configuration is read from
    Investigation.xml in the parent folder.

    Point-in-time analysis:
      - Inbox rules: forwarding/redirect (CRITICAL), deletion (HIGH), move-to-folder (MEDIUM),
        mark-as-read (LOW), common attacker rule name patterns (HIGH)
      - Mail forwarding: SMTP forwarding enabled (CRITICAL)
      - Transport rules: tenant-level forwarding rules (HIGH)
      - Mailbox permissions: delegated access (MEDIUM)
      - Mobile devices: review for unrecognized (INFO)
      - Directory role memberships: victim is admin (HIGH)
      - Service principals created in window (HIGH)
      - Conditional Access policies modified in window (HIGH)

    Timeline / event-based analysis (from UAL and Graph):
      - Impossible travel (sign-ins from geographically distant IPs in short time window)
      - Session ID reuse across IPs (AiTM / token theft indicator)
      - Risk detections (atypical travel, anonymous IP, malicious IP, leaked credentials)
      - New MFA device registered during window (CRITICAL)
      - New OAuth consents granted during window (HIGH)
      - New admin role assignments during window (CRITICAL)
      - Rule manipulation timeline (create/modify/delete correlation)
      - Mass email volume spikes (HIGH)
      - External recipient ratio anomalies (MEDIUM)
      - MailItemsAccessed Sync events (CRITICAL - full mailbox download indicator)
      - MailItemsAccessed throttling (CRITICAL - assume full mailbox access)
      - Bulk file downloads (HIGH - data exfiltration)

    Consolidated Timeline view:
      All notable events across all data sources are merged into a single
      chronological timeline in Analysis\Timeline.csv.

    Output:
      - ANALYSIS-REPORT.txt    - Human-readable ranked findings with recommendations
      - All-Findings.csv       - Machine-readable findings
      - Timeline.csv           - Chronological consolidated event timeline

    Run with -SkipMessageTraces immediately after data collection for fast triage.
    Re-run without the switch after Invoke-BECMessageTraceRetrieval.ps1 for full analysis.

    Supports versioned CSV files (_v2, _v3...) created by re-runs of data collection.

.PARAMETER SkipMessageTraces
    Optional switch. If specified, message trace CSV analysis is skipped.
    Use for immediate triage while historical traces are still processing.

.EXAMPLE
    .\Invoke-BECLogAnalysis.ps1 -SkipMessageTraces
    Immediate triage - analyzes all data except message traces.

.EXAMPLE
    .\Invoke-BECLogAnalysis.ps1
    Full analysis including message trace data.

.NOTES
    File Name      : Invoke-BECLogAnalysis.ps1
    Version        : {SCRIPT_VERSION}
    Author         : Sam Kirsch
    Contributors   : Sam Kirsch
    Company        : Databranch
    Created        : {CREATED_DATE}
    Last Modified  : {CREATED_DATE}
    Modified By    : Sam Kirsch

    Investigation  : {INVESTIGATION_ID}
    Victim         : {VICTIM_EMAIL}

    Requires       : PowerShell 5.1+
    Run Context    : Interactive - Technician workstation
    DattoRMM       : Not applicable
    Client Scope   : Per-investigation (generated script)

    Exit Codes:
        0  - Analysis completed (findings may or may not exist)
        1  - Runtime failure during analysis
        2  - Fatal pre-flight failure (XML not found, RawData empty)

.CHANGELOG
    v{SCRIPT_VERSION} - {CREATED_DATE} - Sam Kirsch
        - Generated by Start-BECInvestigation.ps1 v{SCRIPT_VERSION}
        - TLS 1.2 block moved below param() - CmdletBinding must be first statement
        - Now reads Graph-* CSVs from Invoke-BECGraphCollection.ps1 (split from DataCollection)
        - Adds timeline analysis and modern BEC detection logic
        - New detections: impossible travel, session reuse (AiTM), new MFA device,
          new OAuth consents, admin role adds, rule manipulation timeline,
          common attacker rule name patterns, CA policy modifications,
          MailItemsAccessed Sync/throttling, bulk file downloads
        - Consolidated chronological Timeline.csv across all data sources
        - Full template v1.4.1.0 compliance
        - Eastern time display in report
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch]$SkipMessageTraces
)

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# Must be AFTER param() so CmdletBinding remains the first executable statement.
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

function Invoke-BECLogAnalysis {
    [CmdletBinding()]
    param (
        [switch]$SkipMessageTraces
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Invoke-BECLogAnalysis"
    $ScriptVersion = "{SCRIPT_VERSION}"

    $EasternTZ = [System.TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')

    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\Investigation.xml"
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Host "[ERROR] Investigation.xml not found at: $ConfigPath" -ForegroundColor Red
        exit 2
    }

    try {
        [xml]$Config = Get-Content -Path $ConfigPath -Encoding UTF8
    }
    catch {
        Write-Host "[ERROR] Failed to parse Investigation.xml: $($_.Exception.Message)" -ForegroundColor Red
        exit 2
    }

    $VictimEmail     = $Config.BECInvestigation.Victim.Email
    $UserAlias       = $Config.BECInvestigation.Victim.UserAlias
    $VictimDomain    = $Config.BECInvestigation.Victim.Domain
    $RawDataPath     = $Config.BECInvestigation.Paths.RawDataPath
    $AnalysisPath    = $Config.BECInvestigation.Paths.AnalysisPath
    $ReportsPath     = $Config.BECInvestigation.Paths.ReportsPath
    $LogsPath        = $Config.BECInvestigation.Paths.LogsPath
    $InvestigationID = $Config.BECInvestigation.Investigation.InvestigationID

    # Window info if available (from v4+ collection)
    $WindowStartUtc = $null
    $WindowEndUtc   = $null
    if ($Config.BECInvestigation.DataCollection.WindowStartUtc) {
        try {
            $WindowStartUtc = [DateTime]::Parse($Config.BECInvestigation.DataCollection.WindowStartUtc,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
                [System.Globalization.DateTimeStyles]::AssumeUniversal)
        }
        catch {
            $WindowStartUtc = $null
        }
    }
    if ($Config.BECInvestigation.DataCollection.WindowEndUtc) {
        try {
            $WindowEndUtc = [DateTime]::Parse($Config.BECInvestigation.DataCollection.WindowEndUtc,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor
                [System.Globalization.DateTimeStyles]::AssumeUniversal)
        }
        catch {
            $WindowEndUtc = $null
        }
    }

    # Validate XML
    $XmlErr = @()
    if (-not $VictimEmail)  { $XmlErr += "Victim.Email" }
    if (-not $RawDataPath)  { $XmlErr += "Paths.RawDataPath" }
    if (-not $AnalysisPath) { $XmlErr += "Paths.AnalysisPath" }
    if (-not $LogsPath)     { $XmlErr += "Paths.LogsPath" }
    if ($XmlErr.Count -gt 0) {
        Write-Host "[ERROR] Investigation.xml missing required fields: $($XmlErr -join ', ')" -ForegroundColor Red
        exit 2
    }

    if (-not (Test-Path -Path $RawDataPath)) {
        Write-Host "[ERROR] RawData folder not found: $RawDataPath" -ForegroundColor Red
        Write-Host "[ERROR] Run Invoke-BECDataCollection.ps1 first." -ForegroundColor Red
        exit 2
    }

    # ==========================================================================
    # LOGGING (transcript + dual-output)
    # ==========================================================================
    $TranscriptTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $TranscriptPath      = Join-Path -Path $LogsPath -ChildPath "Analysis_${TranscriptTimestamp}.log"
    Start-Transcript -Path $TranscriptPath -ErrorAction SilentlyContinue | Out-Null

    function Write-Log {
        param (
            [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Message = "",
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
            [string]$Severity = "INFO"
        )
        $Ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Entry = "[$Ts] [$Severity] $Message"
        switch ($Severity) {
            "INFO"    { Write-Output  $Entry }
            "WARN"    { Write-Warning $Entry }
            "ERROR"   { Write-Error   $Entry -ErrorAction Continue }
            "SUCCESS" { Write-Output  $Entry }
            "DEBUG"   { Write-Output  $Entry }
        }
    }

    function Write-Console {
        param (
            [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Message = "",
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG","PLAIN")]
            [string]$Severity = "PLAIN",
            [Parameter(Mandatory = $false)] [int]$Indent = 0
        )
        $Prefix = "  " * $Indent
        $Colors = @{ INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; DEBUG="Magenta"; PLAIN="Gray" }
        $Color = $Colors[$Severity]
        if ($Severity -eq "PLAIN") {
            Write-Host "$Prefix$Message" -ForegroundColor $Color
        }
        else {
            Write-Host "$Prefix" -NoNewline
            Write-Host "[$Severity]" -ForegroundColor $Color -NoNewline
            Write-Host " $Message" -ForegroundColor White
        }
    }

    function Write-Banner {
        param ([string]$Title, [string]$Color = "Cyan")
        $Line = "=" * 60
        Write-Host ""
        Write-Host $Line -ForegroundColor $Color
        Write-Host "  $Title" -ForegroundColor White
        Write-Host $Line -ForegroundColor $Color
        Write-Host ""
    }

    function Write-Section {
        param ([string]$Title, [string]$Color = "Cyan")
        $TitleStr = "---- $Title "
        $Padding  = "-" * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ""
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    function Write-Separator {
        param ([string]$Color = "DarkGray")
        Write-Host ("-" * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # TIME HELPERS
    # ==========================================================================
    function ConvertTo-EasternTime {
        param ($UtcDateTime)
        if (-not $UtcDateTime) { return "" }
        try {
            $Dt = if ($UtcDateTime -is [DateTime]) {
                $UtcDateTime
            }
            else {
                [DateTime]::Parse($UtcDateTime.ToString(), [System.Globalization.CultureInfo]::InvariantCulture,
                                  [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                                  [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            }
            if ($Dt.Kind -ne [DateTimeKind]::Utc) {
                $Dt = [DateTime]::SpecifyKind($Dt, [DateTimeKind]::Utc)
            }
            $Et = [System.TimeZoneInfo]::ConvertTimeFromUtc($Dt, $EasternTZ)
            $TzAbbr = if ($EasternTZ.IsDaylightSavingTime($Et)) { "EDT" } else { "EST" }
            return ("{0} {1}" -f $Et.ToString("yyyy-MM-dd HH:mm:ss"), $TzAbbr)
        }
        catch {
            return ""
        }
    }

    function ConvertTo-UtcDateTime {
        param ($Value)
        if (-not $Value) { return $null }
        try {
            if ($Value -is [DateTime]) {
                if ($Value.Kind -eq [DateTimeKind]::Utc) { return $Value }
                return [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc)
            }
            $Parsed = [DateTime]::Parse($Value.ToString(), [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            return $Parsed
        }
        catch {
            return $null
        }
    }

    # ==========================================================================
    # FILE HELPERS
    # ==========================================================================
    function Get-AllVersionedFiles {
        param ([string]$Pattern)
        $Files = @(Get-ChildItem -Path $RawDataPath -Filter $Pattern -ErrorAction SilentlyContinue)
        if ($Files.Count -eq 0) { return @() }
        $BaseFile     = $Files | Where-Object { $_.Name -notmatch "_v\d+\.csv$" }
        $VersionFiles = $Files | Where-Object { $_.Name -match "_v\d+\.csv$" } | Sort-Object -Property Name
        $All = @()
        if ($BaseFile) { $All += $BaseFile }
        $All += $VersionFiles
        return $All
    }

    # ==========================================================================
    # FINDING + TIMELINE DATA STRUCTURES
    # ==========================================================================
    $script:AllFindings = @()
    $script:Timeline    = @()

    function New-Finding {
        param (
            [Parameter(Mandatory = $true)]
            [ValidateSet("CRITICAL","HIGH","MEDIUM","LOW","INFO")]
            [string]$Severity,
            [string]$Category,
            [string]$Finding,
            [string]$Evidence       = "",
            [string]$Recommendation = ""
        )
        $LogSev = switch ($Severity) {
            "CRITICAL" { "WARN" }
            "HIGH"     { "WARN" }
            "MEDIUM"   { "INFO" }
            "LOW"      { "INFO" }
            "INFO"     { "INFO" }
        }
        Write-Log     "[$Severity] $Category - $Finding" -Severity $LogSev
        if ($Evidence)       { Write-Log "  Evidence       : $Evidence"       -Severity DEBUG }
        if ($Recommendation) { Write-Log "  Recommendation : $Recommendation" -Severity DEBUG }

        $FindingObj = [PSCustomObject]@{
            Timestamp      = Get-Date
            Severity       = $Severity
            Category       = $Category
            Finding        = $Finding
            Evidence       = $Evidence
            Recommendation = $Recommendation
        }
        $script:AllFindings += $FindingObj
        return $FindingObj
    }

    function Add-TimelineEvent {
        param (
            [DateTime]$UtcTime,
            [string]$Source,
            [string]$EventType,
            [string]$Actor,
            [string]$IpAddress,
            [string]$Details,
            [string]$Severity = "INFO"
        )
        if (-not $UtcTime -or $UtcTime -eq [DateTime]::MinValue) { return }
        $script:Timeline += [PSCustomObject]@{
            Timestamp_UTC     = $UtcTime.ToString("yyyy-MM-dd HH:mm:ss") + " UTC"
            Timestamp_Eastern = ConvertTo-EasternTime -UtcDateTime $UtcTime
            Source            = $Source
            EventType         = $EventType
            Severity          = $Severity
            Actor             = $Actor
            IpAddress         = $IpAddress
            Details           = $Details
        }
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = "Continue"

    Write-Banner -Title "BEC LOG ANALYSIS v$ScriptVersion" -Color Cyan
    Write-Console "Investigation : $InvestigationID" -Severity PLAIN
    Write-Console "Victim        : $VictimEmail" -Severity PLAIN
    Write-Console "Mode          : $(if ($SkipMessageTraces) { 'Immediate triage (traces excluded)' } else { 'Full analysis' })" -Severity PLAIN
    if ($WindowStartUtc -and $WindowEndUtc) {
        Write-Console "Window Start  : $($WindowStartUtc.ToString('yyyy-MM-dd HH:mm:ss')) UTC / $(ConvertTo-EasternTime -UtcDateTime $WindowStartUtc)" -Severity PLAIN
        Write-Console "Window End    : $($WindowEndUtc.ToString('yyyy-MM-dd HH:mm:ss')) UTC / $(ConvertTo-EasternTime -UtcDateTime $WindowEndUtc)" -Severity PLAIN
    }
    Write-Console "Transcript    : $TranscriptPath" -Severity PLAIN
    Write-Separator

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Investigation : $InvestigationID" -Severity INFO
    Write-Log "Victim        : $VictimEmail" -Severity INFO

    try {
        # ======================================================================
        # INBOX RULES
        # ======================================================================
        Write-Section -Title "Analyzing Inbox Rules"
        $RuleFiles = Get-AllVersionedFiles -Pattern "InboxRules_*.csv"
        if ($RuleFiles.Count -eq 0) {
            Write-Log "No inbox rules files found in RawData." -Severity WARN
        }
        else {
            foreach ($File in $RuleFiles) {
                Write-Log "  Reading: $($File.Name)" -Severity DEBUG
                $Rules = Import-Csv -Path $File.FullName
                if (-not $Rules) { continue }

                # Forwarding / redirect (CRITICAL)
                $Forwarders = $Rules | Where-Object {
                    ($_.ForwardTo           -and $_.ForwardTo           -ne "") -or
                    ($_.RedirectTo          -and $_.RedirectTo          -ne "") -or
                    ($_.ForwardAsAttachmentTo -and $_.ForwardAsAttachmentTo -ne "")
                }
                if ($Forwarders) {
                    $null = New-Finding -Severity "CRITICAL" -Category "Inbox Rules - Forwarding" `
                        -Finding "Email forwarding/redirect rules detected" `
                        -Evidence "$($Forwarders.Count) rule(s) forwarding to other addresses in $($File.Name)" `
                        -Recommendation "Flag for CIPP Compromise Remediation - this disables all inbox rules as part of the workflow"
                }

                # Deletion rules (HIGH)
                $Deleters = $Rules | Where-Object { $_.DeleteMessage -eq "True" }
                if ($Deleters) {
                    $null = New-Finding -Severity "HIGH" -Category "Inbox Rules - Deletion" `
                        -Finding "Email deletion rules detected" `
                        -Evidence "$($Deleters.Count) rule(s) automatically deleting messages in $($File.Name)" `
                        -Recommendation "Review - attackers use deletion rules to hide breach evidence"
                }

                # Move-to-folder rules (MEDIUM)
                $Movers = $Rules | Where-Object {
                    $_.MoveToFolder -and $_.MoveToFolder -ne "" -and
                    $_.MoveToFolder -notmatch "^(Inbox|Junk Email|Archive)$"
                }
                if ($Movers) {
                    $Folders = ($Movers | Select-Object -ExpandProperty MoveToFolder -Unique) -join ", "
                    $null = New-Finding -Severity "MEDIUM" -Category "Inbox Rules - Move to Folder" `
                        -Finding "Rules moving emails to non-standard folders" `
                        -Evidence "$($Movers.Count) rule(s) moving to: $Folders in $($File.Name)" `
                        -Recommendation "Review - may be legitimate filtering or malicious email hiding"
                }

                # Mark-as-read (LOW)
                $Readers = $Rules | Where-Object { $_.MarkAsRead -eq "True" }
                if ($Readers) {
                    $null = New-Finding -Severity "LOW" -Category "Inbox Rules - Mark As Read" `
                        -Finding "Rules automatically marking emails as read" `
                        -Evidence "$($Readers.Count) rule(s) in $($File.Name)" `
                        -Recommendation "Often combined with move/delete rules to hide attacker activity"
                }

                # Attacker rule name patterns (HIGH)
                # Common patterns: single/double punctuation, single chars, financial keywords
                $SuspiciousNamePatterns = @(
                    '^\.{1,3}$', '^,{1,3}$', '^_{1,3}$', '^-{1,3}$',
                    '^[a-z]$', '^[A-Z]$',
                    '^\s*$'
                )
                $FinancialKeywords = @('invoice', 'wire', 'payment', 'bank', 'ach', 'payroll', 'swift', 'iban', 'routing', 'vendor')
                $SuspNamed = foreach ($Rule in $Rules) {
                    $Name = [string]$Rule.Name
                    $MatchedPattern = $false
                    foreach ($Pat in $SuspiciousNamePatterns) {
                        if ($Name -match $Pat) { $MatchedPattern = $true; break }
                    }
                    $LowerName = $Name.ToLower()
                    $KeywordHit = $FinancialKeywords | Where-Object { $LowerName -match $_ }
                    if ($MatchedPattern -or $KeywordHit) {
                        [PSCustomObject]@{
                            Rule    = $Name
                            Reason  = if ($MatchedPattern) { "Matches common attacker rule name pattern" } else { "Contains financial keyword: $($KeywordHit -join ',')" }
                        }
                    }
                }
                if ($SuspNamed) {
                    $Evidence = ($SuspNamed | ForEach-Object { "'$($_.Rule)' ($($_.Reason))" }) -join '; '
                    $null = New-Finding -Severity "HIGH" -Category "Inbox Rules - Suspicious Naming" `
                        -Finding "Rules with names matching common attacker patterns" `
                        -Evidence "$Evidence in $($File.Name)" `
                        -Recommendation "These rule name patterns are frequently used by BEC actors to hide rules from casual inspection"
                }
            }
        }

        # ======================================================================
        # MAIL FORWARDING (MAILBOX)
        # ======================================================================
        Write-Section -Title "Analyzing Mail Forwarding"
        $FwdFiles = Get-AllVersionedFiles -Pattern "MailForwarding_*.csv"
        foreach ($File in $FwdFiles) {
            $Fwd = Import-Csv -Path $File.FullName
            if ($Fwd.ForwardingEnabled -eq "True") {
                $null = New-Finding -Severity "CRITICAL" -Category "Mail Forwarding" `
                    -Finding "SMTP mail forwarding enabled on mailbox" `
                    -Evidence "Forwarding to: $($Fwd.ForwardingSmtpAddress) in $($File.Name)" `
                    -Recommendation "Flag for CIPP Compromise Remediation - confirm forwarding is disabled manually post-remediation"
            }
        }

        # ======================================================================
        # TRANSPORT RULES (TENANT-WIDE)
        # ======================================================================
        Write-Section -Title "Analyzing Transport Rules"
        $TRFiles = Get-AllVersionedFiles -Pattern "TransportRules_ForwardingOnly.csv"
        foreach ($File in $TRFiles) {
            $TRs = Import-Csv -Path $File.FullName
            if ($TRs) {
                $RuleNames = ($TRs | Select-Object -ExpandProperty Name -First 5) -join ', '
                $null = New-Finding -Severity "HIGH" -Category "Transport Rules" `
                    -Finding "Tenant-level transport rules with forwarding actions" `
                    -Evidence "$(@($TRs).Count) rule(s): $RuleNames ... in $($File.Name)" `
                    -Recommendation "Tenant-wide rules are NOT touched by CIPP Compromise Remediation. Review manually in EAC Mail Flow."
            }
        }

        # ======================================================================
        # MAILBOX PERMISSIONS
        # ======================================================================
        Write-Section -Title "Analyzing Mailbox Permissions"
        $PermFiles = Get-AllVersionedFiles -Pattern "MailboxPermissions_*.csv"
        foreach ($File in $PermFiles) {
            $Perms = Import-Csv -Path $File.FullName
            if ($Perms) {
                $Users = ($Perms | Select-Object -ExpandProperty User -First 3) -join ', '
                $null = New-Finding -Severity "MEDIUM" -Category "Mailbox Permissions" `
                    -Finding "Delegated mailbox permissions detected" `
                    -Evidence "$(@($Perms).Count) permission(s) in $($File.Name). Users: $Users" `
                    -Recommendation "Verify these are legitimate business needs. Check if added during breach window."
            }
        }

        # ======================================================================
        # DIRECTORY ROLE MEMBERSHIPS (FROM GRAPH)
        # ======================================================================
        Write-Section -Title "Analyzing Role Memberships"
        $RoleFiles = Get-AllVersionedFiles -Pattern "Graph-RoleMemberships_*.csv"
        foreach ($File in $RoleFiles) {
            $Memberships = Import-Csv -Path $File.FullName
            $DirRoles = $Memberships | Where-Object { $_.type -eq 'directoryRole' }
            if ($DirRoles) {
                $RoleList = ($DirRoles | Select-Object -ExpandProperty displayName) -join ', '
                $null = New-Finding -Severity "HIGH" -Category "Directory Roles" `
                    -Finding "Victim account is a member of directory/admin roles" `
                    -Evidence "$(@($DirRoles).Count) role(s): $RoleList" `
                    -Recommendation "Admin accounts require heightened scrutiny. Review whether role membership was added recently (see UAL Role Changes)."
            }
        }

        # ======================================================================
        # SERVICE PRINCIPALS / ENTERPRISE APPS CREATED IN WINDOW
        # ======================================================================
        Write-Section -Title "Analyzing Service Principals / Enterprise Apps"
        $SPFiles = Get-AllVersionedFiles -Pattern "Graph-ServicePrincipals.csv"
        foreach ($File in $SPFiles) {
            $SPs = Import-Csv -Path $File.FullName
            $NewSPs = $SPs | Where-Object { $_.CreatedInWindow -eq "TRUE" }
            if ($NewSPs) {
                $Names = ($NewSPs | Select-Object -ExpandProperty displayName -First 5) -join ', '
                $null = New-Finding -Severity "HIGH" -Category "OAuth - New Enterprise Apps" `
                    -Finding "Service principals created during investigation window" `
                    -Evidence "$(@($NewSPs).Count) new SP(s): $Names ... in $($File.Name)" `
                    -Recommendation "OAuth consent phishing is a top 2026 BEC vector - review each new app; delete any not approved"
            }
        }

        # ======================================================================
        # CONDITIONAL ACCESS POLICIES MODIFIED IN WINDOW
        # ======================================================================
        Write-Section -Title "Analyzing Conditional Access Policies"
        $CAFiles = Get-AllVersionedFiles -Pattern "Graph-ConditionalAccess.csv"
        foreach ($File in $CAFiles) {
            $Policies = Import-Csv -Path $File.FullName
            $Modified = $Policies | Where-Object {
                $_.modifiedDateTime -and $WindowStartUtc -and
                (ConvertTo-UtcDateTime $_.modifiedDateTime) -ge $WindowStartUtc
            }
            if ($Modified) {
                $Names = ($Modified | Select-Object -ExpandProperty displayName -First 5) -join ', '
                $null = New-Finding -Severity "HIGH" -Category "Conditional Access - Policy Modified" `
                    -Finding "CA policies modified during investigation window" `
                    -Evidence "$(@($Modified).Count) policy(ies): $Names" `
                    -Recommendation "Attackers may weaken CA policies or add exclusions. Cross-reference with UAL CA Changes timeline."
            }
        }

        # ======================================================================
        # RISKY USER + RISK DETECTIONS (GRAPH)
        # ======================================================================
        Write-Section -Title "Analyzing Graph Risk Signals"
        $RUFiles = Get-AllVersionedFiles -Pattern "Graph-RiskyUser_*.csv"
        foreach ($File in $RUFiles) {
            $RU = Import-Csv -Path $File.FullName
            if ($RU -and $RU.riskLevel -and $RU.riskLevel -ne 'none') {
                $null = New-Finding -Severity "CRITICAL" -Category "Entra ID Protection - Risky User" `
                    -Finding "Victim is flagged as a risky user in Entra ID Protection" `
                    -Evidence "Risk Level: $($RU.riskLevel), State: $($RU.riskState), Detail: $($RU.riskDetail), Last Updated: $($RU.riskLastUpdatedDateTime)" `
                    -Recommendation "Entra ID Protection has high-confidence signals of compromise. Investigate immediately."
            }
        }

        $RDFiles = Get-AllVersionedFiles -Pattern "Graph-RiskDetections_*.csv"
        foreach ($File in $RDFiles) {
            $RDs = Import-Csv -Path $File.FullName
            if (-not $RDs) { continue }

            $HighRisk = $RDs | Where-Object { $_.riskLevel -in @('high','medium') -or $_.riskEventType -match 'adversaryInTheMiddle|anomalousToken|maliciousIPAddress|leakedCredentials|passwordSpray' }
            if ($HighRisk) {
                $Types = ($HighRisk | Select-Object -ExpandProperty riskEventType -Unique) -join ', '
                $null = New-Finding -Severity "CRITICAL" -Category "Entra ID Protection - Risk Detections" `
                    -Finding "High-confidence risk detections found for victim" `
                    -Evidence "$(@($HighRisk).Count) detection(s): $Types in $($File.Name)" `
                    -Recommendation "These Microsoft-generated signals indicate confirmed malicious activity - treat as CRITICAL"
            }

            # Add all risk detections to timeline
            foreach ($RD in $RDs) {
                $Dt = ConvertTo-UtcDateTime $RD.detectedDateTime
                if ($Dt) {
                    $Sev = switch ($RD.riskLevel) {
                        "high"   { "CRITICAL" }
                        "medium" { "HIGH" }
                        "low"    { "MEDIUM" }
                        default  { "INFO" }
                    }
                    Add-TimelineEvent -UtcTime $Dt -Source "Entra ID Risk" `
                        -EventType "RiskDetection-$($RD.riskEventType)" `
                        -Actor $RD.userPrincipalName `
                        -IpAddress $RD.ipAddress `
                        -Details "Level=$($RD.riskLevel) State=$($RD.riskState) Source=$($RD.source) Location=$($RD.location_city),$($RD.location_country)" `
                        -Severity $Sev
                }
            }
        }

        # ======================================================================
        # SIGN-IN LOGS (GRAPH) - impossible travel + session reuse + all to timeline
        # ======================================================================
        Write-Section -Title "Analyzing Sign-In Logs"
        $SIFiles = Get-AllVersionedFiles -Pattern "Graph-SignIns_*.csv"
        foreach ($File in $SIFiles) {
            $SignIns = Import-Csv -Path $File.FullName
            if (-not $SignIns) { continue }

            # Enrich with parsed timestamps
            $Enriched = foreach ($SI in $SignIns) {
                $Dt = ConvertTo-UtcDateTime $SI.createdDateTime
                [PSCustomObject]@{
                    Source  = $SI
                    UtcTime = $Dt
                    Ip      = $SI.ipAddress
                    Country = $SI.location_country
                    City    = $SI.location_city
                    Session = $SI.sessionId
                    AppName = $SI.appDisplayName
                    Success = ($SI.status_errorCode -eq '0')
                    Risk    = $SI.riskLevelDuringSignIn
                    IsInteractive = $SI.isInteractive
                }
            }

            # ---- Impossible travel detection ----
            # Group by user, sort by time, check for country changes with short time between
            $SortedSignIns = $Enriched | Where-Object { $_.UtcTime -and $_.Ip -and $_.Country } |
                             Sort-Object -Property UtcTime
            $ImpossibleTravelEvents = @()
            for ($i = 1; $i -lt $SortedSignIns.Count; $i++) {
                $Prev = $SortedSignIns[$i - 1]
                $Curr = $SortedSignIns[$i]
                if ($Prev.Country -and $Curr.Country -and $Prev.Country -ne $Curr.Country) {
                    $Gap = ($Curr.UtcTime - $Prev.UtcTime).TotalMinutes
                    # Cross-country travel in < 2 hours is very likely impossible travel
                    if ($Gap -lt 120) {
                        $ImpossibleTravelEvents += [PSCustomObject]@{
                            Time1    = $Prev.UtcTime
                            Country1 = $Prev.Country
                            Ip1      = $Prev.Ip
                            Time2    = $Curr.UtcTime
                            Country2 = $Curr.Country
                            Ip2      = $Curr.Ip
                            GapMin   = [math]::Round($Gap, 1)
                        }
                    }
                }
            }
            if ($ImpossibleTravelEvents) {
                $Examples = ($ImpossibleTravelEvents | Select-Object -First 3 | ForEach-Object {
                    "$($_.Country1)($($_.Ip1)) -> $($_.Country2)($($_.Ip2)) in $($_.GapMin) min"
                }) -join '; '
                $null = New-Finding -Severity "CRITICAL" -Category "Sign-Ins - Impossible Travel" `
                    -Finding "Sign-ins from geographically distant IPs within an impossible time window" `
                    -Evidence "$($ImpossibleTravelEvents.Count) impossible travel event(s): $Examples" `
                    -Recommendation "Classic compromise signal. The attacker is likely in a different country than the user."

                # Timeline entries
                foreach ($IT in $ImpossibleTravelEvents) {
                    Add-TimelineEvent -UtcTime $IT.Time2 -Source "Sign-In Analysis" `
                        -EventType "ImpossibleTravel" -Actor $VictimEmail -IpAddress $IT.Ip2 `
                        -Details "Travel from $($IT.Country1) ($($IT.Ip1)) to $($IT.Country2) in $($IT.GapMin) minutes" `
                        -Severity "CRITICAL"
                }
            }

            # ---- Session ID reuse across IPs (AiTM signal) ----
            # Same session ID appearing with multiple distinct IPs = token theft indicator
            $SessionGroups = $Enriched | Where-Object { $_.Session -and $_.Ip } |
                             Group-Object -Property Session
            $ReusedSessions = $SessionGroups | Where-Object {
                ($_.Group | Select-Object -ExpandProperty Ip -Unique).Count -gt 1
            }
            if ($ReusedSessions) {
                $Examples = ($ReusedSessions | Select-Object -First 3 | ForEach-Object {
                    $Ips = ($_.Group | Select-Object -ExpandProperty Ip -Unique) -join ','
                    "Session $($_.Name.Substring(0, [math]::Min(8, $_.Name.Length)))... seen from IPs: $Ips"
                }) -join '; '
                $null = New-Finding -Severity "CRITICAL" -Category "Sign-Ins - Session ID Reuse (AiTM)" `
                    -Finding "Same session ID observed from multiple IP addresses" `
                    -Evidence "$($ReusedSessions.Count) session(s) reused across IPs: $Examples" `
                    -Recommendation "Classic AiTM / token theft indicator. Attacker replayed a stolen session cookie from a different IP than the user."
            }

            # ---- Risky or failed sign-ins to timeline ----
            foreach ($E in $Enriched) {
                if (-not $E.UtcTime) { continue }
                $IsNoteworthy = ($E.Risk -and $E.Risk -ne 'none') -or
                                (-not $E.Success) -or
                                $ImpossibleTravelEvents.Count -gt 0
                if ($IsNoteworthy) {
                    $Sev = if ($E.Risk -eq 'high') { "CRITICAL" }
                           elseif ($E.Risk -eq 'medium') { "HIGH" }
                           elseif (-not $E.Success) { "INFO" }
                           else { "MEDIUM" }
                    $StatusStr = if ($E.Success) { "Success" } else { "Failed (err $($E.Source.status_errorCode))" }
                    Add-TimelineEvent -UtcTime $E.UtcTime -Source "Sign-In Log" `
                        -EventType "SignIn-$StatusStr" -Actor $E.Source.userPrincipalName `
                        -IpAddress $E.Ip `
                        -Details "App=$($E.AppName) Location=$($E.City),$($E.Country) Risk=$($E.Risk) Session=$($E.Session)" `
                        -Severity $Sev
                }
            }

            # ---- Failed sign-in burst (brute force / password spray) ----
            $FailedSignIns = $Enriched | Where-Object { -not $_.Success }
            if ($FailedSignIns.Count -gt 20) {
                # Count unique IPs generating failures
                $UniqueFailIps = ($FailedSignIns | Select-Object -ExpandProperty Ip -Unique).Count
                $null = New-Finding -Severity "HIGH" -Category "Sign-Ins - Failed Login Volume" `
                    -Finding "Unusually high number of failed sign-in attempts" `
                    -Evidence "$($FailedSignIns.Count) failed sign-in(s) from $UniqueFailIps unique IP(s)" `
                    -Recommendation "Investigate for brute-force or password-spray activity targeting this account"
            }
        }

        # ======================================================================
        # UAL - RULE MANIPULATION TIMELINE
        # ======================================================================
        Write-Section -Title "Analyzing UAL Rule Manipulation Events"
        $RuleUalFiles = Get-AllVersionedFiles -Pattern "UAL-RuleManipulation_*.csv"
        foreach ($File in $RuleUalFiles) {
            $Events = Import-Csv -Path $File.FullName | Where-Object { $_.Operations }
            if (-not $Events) { continue }

            $NewRuleEvents    = $Events | Where-Object { $_.Operations -match 'New-InboxRule|UpdateInboxRules' }
            $RemovedRuleEvents = $Events | Where-Object { $_.Operations -match 'Remove-InboxRule' }

            if ($NewRuleEvents) {
                $null = New-Finding -Severity "HIGH" -Category "UAL - Inbox Rules Created" `
                    -Finding "Inbox rule creation events detected during window" `
                    -Evidence "$(@($NewRuleEvents).Count) creation event(s) in $($File.Name)" `
                    -Recommendation "Cross-reference with current inbox rules (SUSPICIOUS-Rules report) to see if these still exist or were deleted"
            }
            if ($RemovedRuleEvents) {
                $null = New-Finding -Severity "HIGH" -Category "UAL - Inbox Rules Deleted" `
                    -Finding "Inbox rule DELETION events detected during window" `
                    -Evidence "$(@($RemovedRuleEvents).Count) deletion event(s) - attacker may have removed rules to hide tracks" `
                    -Recommendation "Deletions during a compromise window are highly suspicious. Review AuditData for original rule details."
            }

            # Add to timeline
            foreach ($Ev in $Events) {
                $Dt = ConvertTo-UtcDateTime $Ev.CreationDate
                if (-not $Dt) { continue }
                $Sev = if ($Ev.Operations -match 'Remove') { "HIGH" } else { "MEDIUM" }
                Add-TimelineEvent -UtcTime $Dt -Source "UAL" `
                    -EventType "Rule-$($Ev.Operations)" -Actor $Ev.UserIds `
                    -IpAddress $Ev.ClientIP `
                    -Details "Object=$($Ev.ObjectId) UA=$($Ev.UserAgent)" `
                    -Severity $Sev
            }
        }

        # ======================================================================
        # UAL - MFA CHANGES
        # ======================================================================
        Write-Section -Title "Analyzing UAL MFA / Auth Method Changes"
        $MfaFiles = Get-AllVersionedFiles -Pattern "UAL-MfaChanges.csv"
        foreach ($File in $MfaFiles) {
            $Events = Import-Csv -Path $File.FullName | Where-Object {
                $_.Operations -and $_.ObjectId -match [regex]::Escape($VictimEmail)
            }
            if (-not $Events) { continue }

            $NewMfa = $Events | Where-Object { $_.Operations -match 'registered security info|security info registration' }
            $ChangedMfa = $Events | Where-Object { $_.Operations -match 'changed default security info|deleted security info' }
            $PwdReset = $Events | Where-Object { $_.Operations -match 'password' }

            if ($NewMfa) {
                $null = New-Finding -Severity "CRITICAL" -Category "MFA - New Device Registered" `
                    -Finding "New MFA device registered for victim during window" `
                    -Evidence "$(@($NewMfa).Count) registration event(s) - attacker may have added their own MFA method as persistence" `
                    -Recommendation "Flag for CIPP Compromise Remediation - CIPP removes ALL MFA methods as part of the workflow"
            }
            if ($ChangedMfa) {
                $null = New-Finding -Severity "HIGH" -Category "MFA - Methods Modified" `
                    -Finding "MFA method changes or deletions during window" `
                    -Evidence "$(@($ChangedMfa).Count) modification event(s)" `
                    -Recommendation "Review whether victim or attacker made the changes"
            }
            if ($PwdReset) {
                $null = New-Finding -Severity "MEDIUM" -Category "Password - Change/Reset" `
                    -Finding "Password change or reset events during window" `
                    -Evidence "$(@($PwdReset).Count) event(s)" `
                    -Recommendation "Confirm whether initiated by victim, admin, or attacker"
            }

            foreach ($Ev in $Events) {
                $Dt = ConvertTo-UtcDateTime $Ev.CreationDate
                if (-not $Dt) { continue }
                $Sev = if ($Ev.Operations -match 'registered|added') { "CRITICAL" } else { "HIGH" }
                Add-TimelineEvent -UtcTime $Dt -Source "UAL" `
                    -EventType "MFA-$($Ev.Operations)" -Actor $Ev.UserIds `
                    -IpAddress $Ev.ClientIP `
                    -Details "Target=$($Ev.ObjectId) UA=$($Ev.UserAgent)" `
                    -Severity $Sev
            }
        }

        # ======================================================================
        # UAL - ROLE CHANGES
        # ======================================================================
        Write-Section -Title "Analyzing UAL Role Changes"
        $RoleChangeFiles = Get-AllVersionedFiles -Pattern "UAL-RoleChanges.csv"
        foreach ($File in $RoleChangeFiles) {
            $Events = Import-Csv -Path $File.FullName | Where-Object {
                $_.Operations -and
                ($_.ObjectId -match [regex]::Escape($VictimEmail) -or $_.UserIds -match [regex]::Escape($VictimEmail))
            }
            if (-not $Events) { continue }

            $Adds = $Events | Where-Object { $_.Operations -match 'Add member to role|Add eligible member' }
            if ($Adds) {
                $null = New-Finding -Severity "CRITICAL" -Category "Roles - Admin Added" `
                    -Finding "Role membership additions involving the victim during window" `
                    -Evidence "$(@($Adds).Count) role-add event(s) - attacker may have escalated privilege" `
                    -Recommendation "Review each role addition. If malicious, remove via Entra admin portal."
            }

            foreach ($Ev in $Events) {
                $Dt = ConvertTo-UtcDateTime $Ev.CreationDate
                if (-not $Dt) { continue }
                Add-TimelineEvent -UtcTime $Dt -Source "UAL" `
                    -EventType "Role-$($Ev.Operations)" -Actor $Ev.UserIds `
                    -IpAddress $Ev.ClientIP -Details "Target=$($Ev.ObjectId)" `
                    -Severity "CRITICAL"
            }
        }

        # ======================================================================
        # UAL - CONDITIONAL ACCESS CHANGES
        # ======================================================================
        Write-Section -Title "Analyzing UAL Conditional Access Changes"
        $CAChangeFiles = Get-AllVersionedFiles -Pattern "UAL-CAChanges.csv"
        foreach ($File in $CAChangeFiles) {
            $Events = Import-Csv -Path $File.FullName | Where-Object { $_.Operations }
            if (-not $Events) { continue }

            $null = New-Finding -Severity "HIGH" -Category "Conditional Access - Changes in Window" `
                -Finding "Conditional Access policy add/modify/delete events during window" `
                -Evidence "$(@($Events).Count) CA change event(s) in $($File.Name)" `
                -Recommendation "CA policy changes during a compromise window may indicate attacker weakening controls. Review each change."

            foreach ($Ev in $Events) {
                $Dt = ConvertTo-UtcDateTime $Ev.CreationDate
                if (-not $Dt) { continue }
                Add-TimelineEvent -UtcTime $Dt -Source "UAL" `
                    -EventType "CA-$($Ev.Operations)" -Actor $Ev.UserIds `
                    -IpAddress $Ev.ClientIP -Details "Target=$($Ev.ObjectId)" `
                    -Severity "HIGH"
            }
        }

        # ======================================================================
        # UAL - OAUTH CONSENTS
        # ======================================================================
        Write-Section -Title "Analyzing UAL OAuth Consent Events"
        $OAuthFiles = Get-AllVersionedFiles -Pattern "UAL-OAuthConsents.csv"
        foreach ($File in $OAuthFiles) {
            $Events = Import-Csv -Path $File.FullName | Where-Object { $_.Operations }
            if (-not $Events) { continue }

            $ConsentEvents = $Events | Where-Object { $_.Operations -match 'Consent to application|OAuth2PermissionGrant|delegated permission grant' }
            if ($ConsentEvents) {
                $VictimConsents = $ConsentEvents | Where-Object { $_.UserIds -match [regex]::Escape($VictimEmail) }
                if ($VictimConsents) {
                    $null = New-Finding -Severity "CRITICAL" -Category "OAuth - Victim Granted Consent" `
                        -Finding "Victim granted OAuth consent to an application during window" `
                        -Evidence "$(@($VictimConsents).Count) consent event(s) by victim - likely OAuth phishing" `
                        -Recommendation "OAuth consent phishing creates persistent access that survives password reset. Revoke the app's permissions immediately."
                }
                else {
                    $null = New-Finding -Severity "HIGH" -Category "OAuth - Consent Events in Tenant" `
                        -Finding "OAuth consent events in tenant during window (not by victim)" `
                        -Evidence "$(@($ConsentEvents).Count) tenant consent event(s)" `
                        -Recommendation "Review whether consents are for legitimate business apps"
                }
            }

            foreach ($Ev in $Events) {
                $Dt = ConvertTo-UtcDateTime $Ev.CreationDate
                if (-not $Dt) { continue }
                $Sev = if ($Ev.Operations -match 'Consent to') { "CRITICAL" } else { "HIGH" }
                Add-TimelineEvent -UtcTime $Dt -Source "UAL" `
                    -EventType "OAuth-$($Ev.Operations)" -Actor $Ev.UserIds `
                    -IpAddress $Ev.ClientIP -Details "Target=$($Ev.ObjectId)" `
                    -Severity $Sev
            }
        }

        # ======================================================================
        # UAL - SEND OPERATIONS (outbound email)
        # ======================================================================
        Write-Section -Title "Analyzing UAL Send Operations"
        $SendFiles = Get-AllVersionedFiles -Pattern "UAL-SendOperations_*.csv"
        foreach ($File in $SendFiles) {
            $Events = Import-Csv -Path $File.FullName | Where-Object { $_.Operations }
            if (-not $Events) { continue }
            $VictimSends = $Events | Where-Object { $_.UserIds -match [regex]::Escape($VictimEmail) }
            if ($VictimSends) {
                # Send bursts per hour
                $SendsByHour = $VictimSends | ForEach-Object {
                    $Dt = ConvertTo-UtcDateTime $_.CreationDate
                    if ($Dt) { $Dt.ToString('yyyy-MM-dd HH:00') }
                } | Group-Object
                $Peak = $SendsByHour | Sort-Object Count -Descending | Select-Object -First 1
                if ($Peak -and $Peak.Count -gt 30) {
                    $null = New-Finding -Severity "HIGH" -Category "Email - Send Burst" `
                        -Finding "Unusually high send volume within a single hour" `
                        -Evidence "$($Peak.Count) sends in hour $($Peak.Name) UTC" `
                        -Recommendation "Likely outbound phishing from compromised account. Pull message traces to identify recipients."
                }

                # Timeline entries
                foreach ($Ev in $VictimSends) {
                    $Dt = ConvertTo-UtcDateTime $Ev.CreationDate
                    if (-not $Dt) { continue }
                    Add-TimelineEvent -UtcTime $Dt -Source "UAL" `
                        -EventType "Send-$($Ev.Operations)" -Actor $Ev.UserIds `
                        -IpAddress $Ev.ClientIP -Details "UA=$($Ev.UserAgent)" `
                        -Severity "INFO"
                }
            }
        }

        # ======================================================================
        # UAL - MAILITEMSACCESSED (sync + throttling detection)
        # ======================================================================
        Write-Section -Title "Analyzing UAL MailItemsAccessed"
        $MiaFiles = Get-AllVersionedFiles -Pattern "UAL-MailItemsAccessed_*.csv"
        foreach ($File in $MiaFiles) {
            $Events = Import-Csv -Path $File.FullName | Where-Object { $_.Operations -eq 'MailItemsAccessed' }
            if (-not $Events) { continue }

            # Parse AuditData JSON to find Sync events and OperationCount
            $SyncEvents = @()
            $TotalItemCount = 0
            $IsThrottled = $false
            foreach ($Ev in $Events) {
                if ($Ev.AuditData) {
                    try {
                        $Ad = $Ev.AuditData | ConvertFrom-Json
                        if ($Ad.OperationProperties) {
                            $AccessType = ($Ad.OperationProperties | Where-Object { $_.Name -eq 'MailAccessType' }).Value
                            $IsThrottledProp = ($Ad.OperationProperties | Where-Object { $_.Name -eq 'IsThrottled' }).Value
                            if ($AccessType -eq 'Sync') {
                                $SyncEvents += $Ev
                            }
                            if ($IsThrottledProp -eq 'True') {
                                $IsThrottled = $true
                            }
                        }
                        if ($Ad.OperationCount) {
                            $TotalItemCount += [int]$Ad.OperationCount
                        }
                    }
                    catch {
                        # AuditData might not be pure JSON - skip parse errors
                    }
                }
            }

            if ($SyncEvents) {
                $null = New-Finding -Severity "CRITICAL" -Category "MailItemsAccessed - Sync Detected" `
                    -Finding "MailItemsAccessed events with MailAccessType=Sync detected" `
                    -Evidence "$(@($SyncEvents).Count) sync event(s) - attacker performed bulk mailbox download" `
                    -Recommendation "Treat this as a data exfiltration incident. Assume the ENTIRE mailbox was copied."
            }

            if ($IsThrottled) {
                $null = New-Finding -Severity "CRITICAL" -Category "MailItemsAccessed - Throttling" `
                    -Finding "UAL logged IsThrottled=True for MailItemsAccessed" `
                    -Evidence "When >1000 MailItemsAccessed events occur in 24h, logging pauses for 24h. Activity during the pause is NOT logged." `
                    -Recommendation "You cannot accurately scope mailbox exposure. Assume WORST CASE: the entire mailbox was accessed during the gap."
            }

            # Timeline entries (summary per hour to avoid flooding)
            $ByHour = $Events | ForEach-Object {
                $Dt = ConvertTo-UtcDateTime $_.CreationDate
                if ($Dt) {
                    [PSCustomObject]@{ Hour = $Dt.ToString('yyyy-MM-dd HH:00'); Dt = $Dt; Ip = $_.ClientIP; User = $_.UserIds }
                }
            } | Group-Object -Property Hour
            foreach ($G in $ByHour) {
                $FirstEv = $G.Group[0]
                $Ips = ($G.Group | Select-Object -ExpandProperty Ip -Unique) -join ','
                Add-TimelineEvent -UtcTime $FirstEv.Dt -Source "UAL" `
                    -EventType "MailItemsAccessed-Hourly" -Actor $FirstEv.User -IpAddress $Ips `
                    -Details "$($G.Count) access event(s) in this hour" -Severity "MEDIUM"
            }
        }

        # ======================================================================
        # UAL - FILE DOWNLOADS (SharePoint/OneDrive exfiltration)
        # ======================================================================
        Write-Section -Title "Analyzing UAL File Downloads"
        $FileDlFiles = Get-AllVersionedFiles -Pattern "UAL-FileDownloads_*.csv"
        foreach ($File in $FileDlFiles) {
            $Events = Import-Csv -Path $File.FullName | Where-Object { $_.Operations -match 'FileDownloaded|FileSyncDownloadedFull' }
            if (-not $Events) { continue }

            if ($Events.Count -gt 50) {
                $null = New-Finding -Severity "HIGH" -Category "Data Exfiltration - File Downloads" `
                    -Finding "High volume of SharePoint/OneDrive file downloads" `
                    -Evidence "$(@($Events).Count) file download event(s) during window" `
                    -Recommendation "Review file names and destinations - potential bulk data exfiltration"
            }

            # Timeline entries (summary per hour)
            $ByHour = $Events | ForEach-Object {
                $Dt = ConvertTo-UtcDateTime $_.CreationDate
                if ($Dt) {
                    [PSCustomObject]@{ Hour = $Dt.ToString('yyyy-MM-dd HH:00'); Dt = $Dt; Ip = $_.ClientIP; User = $_.UserIds }
                }
            } | Group-Object -Property Hour
            foreach ($G in $ByHour) {
                $FirstEv = $G.Group[0]
                $Ips = ($G.Group | Select-Object -ExpandProperty Ip -Unique) -join ','
                Add-TimelineEvent -UtcTime $FirstEv.Dt -Source "UAL" `
                    -EventType "FileDownloads-Hourly" -Actor $FirstEv.User -IpAddress $Ips `
                    -Details "$($G.Count) file download(s) in this hour" -Severity "MEDIUM"
            }
        }

        # ======================================================================
        # UAL - LOGIN EVENTS (to timeline)
        # ======================================================================
        Write-Section -Title "Analyzing UAL Login Events"
        $LoginFiles = Get-AllVersionedFiles -Pattern "UAL-Logins_*.csv"
        foreach ($File in $LoginFiles) {
            $Events = Import-Csv -Path $File.FullName | Where-Object { $_.Operations }
            $FailedLogins = $Events | Where-Object { $_.Operations -eq 'UserLoginFailed' }
            if ($FailedLogins.Count -gt 20) {
                $null = New-Finding -Severity "MEDIUM" -Category "UAL - Failed Login Volume" `
                    -Finding "High number of failed login events in UAL" `
                    -Evidence "$(@($FailedLogins).Count) UserLoginFailed event(s)" `
                    -Recommendation "Cross-reference with Graph sign-in logs for full context (IPs, locations, apps)"
            }
        }

        # ======================================================================
        # MESSAGE TRACES (Quick + Historical) if not skipped
        # ======================================================================
        if (-not $SkipMessageTraces) {
            Write-Section -Title "Analyzing Message Traces"
            $SentFiles = @()
            $SentFiles += Get-AllVersionedFiles -Pattern "QuickTrace-Sent_*.csv"
            $SentFiles += Get-AllVersionedFiles -Pattern "MessageTrace-Sent_*.csv"

            foreach ($File in $SentFiles) {
                $Sent = Import-Csv -Path $File.FullName
                if (-not $Sent) { continue }

                # Daily volume spike
                $DailyCounts = $Sent | Where-Object { $_.Received } | ForEach-Object {
                    $Dt = ConvertTo-UtcDateTime $_.Received
                    if ($Dt) { $Dt.ToString('yyyy-MM-dd') }
                } | Group-Object
                $Peak = $DailyCounts | Sort-Object Count -Descending | Select-Object -First 1
                if ($Peak -and $Peak.Count -gt 50) {
                    $null = New-Finding -Severity "HIGH" -Category "Message Trace - Volume Spike" `
                        -Finding "Unusually high outbound email volume on a single day" `
                        -Evidence "$($Peak.Count) emails sent on $($Peak.Name) in $($File.Name)" `
                        -Recommendation "Likely phishing campaign from compromised account - review recipients"
                }

                # External recipient ratio
                $Total = $Sent.Count
                $External = $Sent | Where-Object {
                    $_.RecipientAddress -and $VictimDomain -and
                    $_.RecipientAddress -notmatch "@$([regex]::Escape($VictimDomain))$"
                }
                if ($External -and $Total -gt 0 -and ($External.Count / $Total) -gt 0.7) {
                    $Pct = [math]::Round(($External.Count / $Total) * 100)
                    $null = New-Finding -Severity "MEDIUM" -Category "Message Trace - External Ratio" `
                        -Finding "High proportion of outbound email to external domains" `
                        -Evidence "$($External.Count) of $Total ($Pct%) in $($File.Name)" `
                        -Recommendation "Review external recipients for signs of phishing or data exfiltration"
                }
            }
        }
        else {
            Write-Log "Message trace analysis skipped (-SkipMessageTraces)." -Severity INFO
        }

        # ======================================================================
        # GENERATE REPORTS
        # ======================================================================
        Write-Section -Title "Generating Reports"

        # Sort findings by severity then timestamp
        $SeverityOrder = @{ 'CRITICAL' = 1; 'HIGH' = 2; 'MEDIUM' = 3; 'LOW' = 4; 'INFO' = 5 }
        $SortedFindings = $script:AllFindings | Sort-Object -Property `
            @{E = { $SeverityOrder[$_.Severity] }; Ascending = $true},
            @{E = { $_.Timestamp }; Ascending = $true}

        $ReportPath   = Join-Path -Path $AnalysisPath -ChildPath "ANALYSIS-REPORT.txt"
        $TimelinePath = Join-Path -Path $AnalysisPath -ChildPath "Timeline.csv"
        $FindingsPath = Join-Path -Path $AnalysisPath -ChildPath "All-Findings.csv"

        # Sort timeline by time
        $SortedTimeline = $script:Timeline | Sort-Object -Property Timestamp_UTC

        # ---- Timeline CSV ----
        if ($SortedTimeline) {
            try {
                $SortedTimeline | Export-Csv -Path $TimelinePath -NoTypeInformation -Encoding UTF8
                Write-Log     "Timeline written: $TimelinePath ($($SortedTimeline.Count) events)" -Severity SUCCESS
                Write-Console "Timeline written: $($SortedTimeline.Count) events" -Severity SUCCESS -Indent 1
            }
            catch {
                Write-Log "Failed to write Timeline.csv: $($_.Exception.Message)" -Severity ERROR
            }
        }

        # ---- Findings CSV ----
        if ($script:AllFindings.Count -gt 0) {
            try {
                $SortedFindings | Export-Csv -Path $FindingsPath -NoTypeInformation -Encoding UTF8
                Write-Log "All-Findings.csv written." -Severity SUCCESS
            }
            catch {
                Write-Log "Failed to write All-Findings.csv: $($_.Exception.Message)" -Severity ERROR
            }
        }

        # ---- Analysis Report text ----
        $CritCount   = @($script:AllFindings | Where-Object { $_.Severity -eq 'CRITICAL' }).Count
        $HighCount   = @($script:AllFindings | Where-Object { $_.Severity -eq 'HIGH' }).Count
        $MediumCount = @($script:AllFindings | Where-Object { $_.Severity -eq 'MEDIUM' }).Count
        $LowCount    = @($script:AllFindings | Where-Object { $_.Severity -eq 'LOW' }).Count
        $InfoCount   = @($script:AllFindings | Where-Object { $_.Severity -eq 'INFO' }).Count

        $FindingsDetail = if ($SortedFindings) {
            ($SortedFindings | ForEach-Object {
                @"

[$($_.Severity)] $($_.Category)
  Finding        : $($_.Finding)
  Evidence       : $($_.Evidence)
  Recommendation : $($_.Recommendation)
"@
            }) -join "`n"
        } else { "" }

        $NoFindings = if ($script:AllFindings.Count -eq 0) {
@"

NO SUSPICIOUS ACTIVITY DETECTED
================================
All analyzed data appears normal. This may mean:
  - The account was not compromised (false alarm / precautionary check)
  - The compromise was minimal and left no obvious traces
  - Additional data sources are needed (ensure Graph collection ran)
  - Data collection failed or was incomplete - check Logs folder
"@
        } else { "" }

        # Top timeline events summary (for inline in report)
        $TopTimelineSummary = ""
        if ($SortedTimeline) {
            $NotableTimeline = $SortedTimeline | Where-Object {
                $_.Severity -in @('CRITICAL','HIGH')
            } | Select-Object -First 15
            if ($NotableTimeline) {
                $Rows = ($NotableTimeline | ForEach-Object {
                    "  $($_.Timestamp_Eastern)  [$($_.Severity.PadRight(8))]  $($_.EventType)  Actor=$($_.Actor)  IP=$($_.IpAddress)"
                }) -join "`n"
                $TopTimelineSummary = @"

TOP TIMELINE EVENTS (critical/high, earliest 15, Eastern time)
---------------------------------------------------------------
$Rows

Full chronological timeline in: Analysis\Timeline.csv
"@
            }
        }

        $AnalysisMode = if ($SkipMessageTraces) { "Immediate triage (message traces excluded)" } else { "Full analysis (message traces included)" }
        $AnalysisDateUtc = (Get-Date).ToUniversalTime()
        $WindowDesc = if ($WindowStartUtc -and $WindowEndUtc) {
            "$($WindowStartUtc.ToString('yyyy-MM-dd HH:mm')) to $($WindowEndUtc.ToString('yyyy-MM-dd HH:mm')) UTC  /  $(ConvertTo-EasternTime -UtcDateTime $WindowStartUtc) to $(ConvertTo-EasternTime -UtcDateTime $WindowEndUtc)"
        } else { "(window not recorded - older investigation format)" }

        $Report = @"
BEC INVESTIGATION ANALYSIS REPORT
==================================
Investigation    : $InvestigationID
Victim           : $VictimEmail
Analysis Date    : $($AnalysisDateUtc.ToString('yyyy-MM-dd HH:mm:ss')) UTC / $(ConvertTo-EasternTime -UtcDateTime $AnalysisDateUtc)
Analysis Mode    : $AnalysisMode
Investigation Window : $WindowDesc
Script Version   : $ScriptVersion

FINDINGS SUMMARY
================
Total Findings : $($script:AllFindings.Count)
  CRITICAL     : $CritCount
  HIGH         : $HighCount
  MEDIUM       : $MediumCount
  LOW          : $LowCount
  INFO         : $InfoCount

Timeline Events : $(@($script:Timeline).Count)

REMEDIATION REMINDER
====================
Containment for CRITICAL findings should be handled via the CIPP
Compromise Remediation workflow, NOT by manual PowerShell remediation.

  CIPP > Identity > Administration > Users > [select user] > Compromise Remediation
  
  CIPP's Compromise Remediation button performs the following in one action:
    - Block user sign-in
    - Reset user password  
    - Disconnect all active sessions
    - Remove all MFA methods (forces re-registration)
    - Disable all inbox rules

The following are NOT handled by CIPP and must be reviewed manually:
    - Tenant-level Transport Rules (EAC > Mail Flow > Rules)
    - OAuth consents granted to malicious apps (Entra > Enterprise Apps)
    - Conditional Access policy modifications
    - New service principals / app registrations created in the window
    - Directory role memberships

DETAILED FINDINGS (sorted by severity, then timestamp)
=======================================================
$FindingsDetail$NoFindings
$TopTimelineSummary

ADDITIONAL FILES
================
  All-Findings.csv        - Machine-readable findings (this report data)
  Timeline.csv            - Full chronological event timeline
  Evidence-Manifest.csv   - SHA-256 hashes of every collected artifact
"@
        try {
            $Report | Out-File -FilePath $ReportPath -Encoding UTF8
            Write-Log     "Analysis report written: $ReportPath" -Severity SUCCESS
            Write-Console "Analysis report written." -Severity SUCCESS -Indent 1
        }
        catch {
            Write-Log "Failed to write analysis report: $($_.Exception.Message)" -Severity ERROR
        }

        # ======================================================================
        # UPDATE XML
        # ======================================================================
        try {
            $AnalysisKey = if ($SkipMessageTraces) { "Immediate" } else { "Complete" }
            $Config.BECInvestigation.Analysis."${AnalysisKey}AnalysisCompleted" = "true"
            $Config.BECInvestigation.Analysis."${AnalysisKey}AnalysisDate"      = (Get-Date -Format "o")
            $Config.BECInvestigation.Analysis.CriticalFindingsCount             = [string]$CritCount
            $Config.BECInvestigation.Analysis.HighFindingsCount                 = [string]$HighCount
            $Config.Save($ConfigPath)
        }
        catch {
            Write-Log "Failed to update Investigation.xml: $($_.Exception.Message)" -Severity WARN
        }

        # ======================================================================
        # COMPLETION BANNER
        # ======================================================================
        $BannerColor = if ($CritCount -gt 0) { "Red" } elseif ($HighCount -gt 0) { "Yellow" } else { "Green" }
        Write-Banner -Title "ANALYSIS COMPLETE" -Color $BannerColor
        if ($script:AllFindings.Count -gt 0) {
            Write-Console "CRITICAL : $CritCount" -Severity $(if ($CritCount -gt 0) { "ERROR" } else { "SUCCESS" })
            Write-Console "HIGH     : $HighCount" -Severity $(if ($HighCount -gt 0) { "WARN" } else { "SUCCESS" })
            Write-Console "MEDIUM   : $MediumCount" -Severity WARN
            Write-Console "LOW      : $LowCount" -Severity INFO
            Write-Console "INFO     : $InfoCount" -Severity INFO
        }
        else {
            Write-Console "No suspicious activity detected." -Severity SUCCESS
        }
        Write-Console "" -Severity PLAIN
        Write-Console "Report   : $ReportPath" -Severity PLAIN
        Write-Console "Timeline : $TimelinePath" -Severity PLAIN
        Write-Console "" -Severity PLAIN

        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        try { Start-Process -FilePath "explorer.exe" -ArgumentList $AnalysisPath } catch { }
        exit 0

    }
    catch {
        Write-Log "Unhandled exception: $_" -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Banner -Title "ANALYSIS FAILED" -Color Red
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }

} # End function Invoke-BECLogAnalysis

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    SkipMessageTraces = $SkipMessageTraces
}

Invoke-BECLogAnalysis @ScriptParams
'@

        # ----------------------------------------------------------------------
        # Invoke-BECMessageTraceRetrieval.ps1 body
        # ----------------------------------------------------------------------
        $RetrievalScript = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Checks and downloads completed historical message trace jobs for a BEC investigation.

.DESCRIPTION
    Invoke-BECMessageTraceRetrieval reads the historical message trace job IDs stored in
    Investigation.xml, queries their status in Exchange Online, and downloads any completed
    traces to the investigation RawData folder. Dual-timestamp columns (UTC + Eastern) are
    added to downloaded traces, and each downloaded file is hashed and added to the
    evidence manifest.

    Historical trace jobs submitted by Invoke-BECDataCollection typically complete in
    15-30 minutes. This script is safe to run multiple times - it will download only
    completed jobs and report the status of any still-pending jobs.

    Once both traces are downloaded, Investigation.xml is updated with TracesCompleted=true
    and the technician should re-run Invoke-BECLogAnalysis.ps1 for full analysis.

.EXAMPLE
    .\Invoke-BECMessageTraceRetrieval.ps1
    Checks trace status and downloads any completed jobs.

.PARAMETER DisableWAM
    Optional switch. Force-disable WAM (Web Account Manager) when connecting
    to Exchange Online. Use when running PowerShell in a different user
    context than your Windows logon session. The script auto-detects WAM
    logon-session failure (error 0x80070520) and retries with -DisableWAM,
    so this switch is rarely needed up-front.

.NOTES
    File Name      : Invoke-BECMessageTraceRetrieval.ps1
    Version        : {SCRIPT_VERSION}
    Author         : Sam Kirsch
    Contributors   : Sam Kirsch
    Company        : Databranch
    Created        : {CREATED_DATE}
    Last Modified  : {CREATED_DATE}
    Modified By    : Sam Kirsch

    Investigation  : {INVESTIGATION_ID}
    Victim         : {VICTIM_EMAIL}

    Requires       : PowerShell 5.1+, ExchangeOnlineManagement 3.7.0+
    Run Context    : Interactive - Technician workstation
    DattoRMM       : Not applicable
    Client Scope   : Per-investigation (generated script)

    Exit Codes:
        0  - Completed (all ready traces downloaded, or traces still pending)
        1  - Runtime failure during retrieval
        2  - Fatal pre-flight failure (Exchange connection failed, XML not found)

.CHANGELOG
    v{SCRIPT_VERSION} - {CREATED_DATE} - Sam Kirsch
        - Generated by Start-BECInvestigation.ps1 v{SCRIPT_VERSION}
        - Auto-detects WAM logon-session failure (error 0x80070520) on
          Connect-ExchangeOnline and auto-retries with -DisableWAM
        - New -DisableWAM switch to force WAM-disabled connect from the start
        - TLS 1.2 block moved below param() - CmdletBinding must be first statement
        - Full template v1.4.1.0 compliance
        - Exit codes 0/1/2, dual-output Write-Log/Write-Console
        - Adds dual-timestamp columns (UTC + Eastern) to downloaded traces
        - Adds SHA-256 hash to Evidence-Manifest.csv for downloaded files
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch]$DisableWAM
)

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# Must be AFTER param() so CmdletBinding remains the first executable statement.
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

function Invoke-BECMessageTraceRetrieval {
    [CmdletBinding()]
    param (
        [switch]$DisableWAM
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Invoke-BECMessageTraceRetrieval"
    $ScriptVersion = "{SCRIPT_VERSION}"

    $EasternTZ = [System.TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time')

    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\Investigation.xml"
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Host "[ERROR] Investigation.xml not found at: $ConfigPath" -ForegroundColor Red
        exit 2
    }

    try {
        [xml]$Config = Get-Content -Path $ConfigPath -Encoding UTF8
    }
    catch {
        Write-Host "[ERROR] Failed to parse Investigation.xml: $($_.Exception.Message)" -ForegroundColor Red
        exit 2
    }

    $SentJobId       = $Config.BECInvestigation.MessageTraces.SentTraceJobId
    $ReceivedJobId   = $Config.BECInvestigation.MessageTraces.ReceivedTraceJobId
    $RawDataPath     = $Config.BECInvestigation.Paths.RawDataPath
    $AnalysisPath    = $Config.BECInvestigation.Paths.AnalysisPath
    $LogsPath        = $Config.BECInvestigation.Paths.LogsPath
    $UserAlias       = $Config.BECInvestigation.Victim.UserAlias
    $VictimEmail     = $Config.BECInvestigation.Victim.Email
    $InvestigationID = $Config.BECInvestigation.Investigation.InvestigationID

    $XmlErr = @()
    if (-not $RawDataPath) { $XmlErr += "Paths.RawDataPath" }
    if (-not $LogsPath)    { $XmlErr += "Paths.LogsPath" }
    if (-not $UserAlias)   { $XmlErr += "Victim.UserAlias" }
    if ($XmlErr.Count -gt 0) {
        Write-Host "[ERROR] Investigation.xml missing required fields: $($XmlErr -join ', ')" -ForegroundColor Red
        exit 2
    }

    # ==========================================================================
    # LOGGING
    # ==========================================================================
    $TranscriptTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $TranscriptPath      = Join-Path -Path $LogsPath -ChildPath "TraceRetrieval_${TranscriptTimestamp}.log"
    Start-Transcript -Path $TranscriptPath -ErrorAction SilentlyContinue | Out-Null

    function Write-Log {
        param (
            [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Message = "",
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
            [string]$Severity = "INFO"
        )
        $Ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Entry = "[$Ts] [$Severity] $Message"
        switch ($Severity) {
            "INFO"    { Write-Output  $Entry }
            "WARN"    { Write-Warning $Entry }
            "ERROR"   { Write-Error   $Entry -ErrorAction Continue }
            "SUCCESS" { Write-Output  $Entry }
            "DEBUG"   { Write-Output  $Entry }
        }
    }

    function Write-Console {
        param (
            [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Message = "",
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG","PLAIN")]
            [string]$Severity = "PLAIN",
            [Parameter(Mandatory = $false)] [int]$Indent = 0
        )
        $Prefix = "  " * $Indent
        $Colors = @{ INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; DEBUG="Magenta"; PLAIN="Gray" }
        $Color  = $Colors[$Severity]
        if ($Severity -eq "PLAIN") {
            Write-Host "$Prefix$Message" -ForegroundColor $Color
        }
        else {
            Write-Host "$Prefix" -NoNewline
            Write-Host "[$Severity]" -ForegroundColor $Color -NoNewline
            Write-Host " $Message" -ForegroundColor White
        }
    }

    function Write-Banner {
        param ([string]$Title, [string]$Color = "Cyan")
        $Line = "=" * 60
        Write-Host ""
        Write-Host $Line -ForegroundColor $Color
        Write-Host "  $Title" -ForegroundColor White
        Write-Host $Line -ForegroundColor $Color
        Write-Host ""
    }

    function Write-Section {
        param ([string]$Title, [string]$Color = "Cyan")
        $TitleStr = "---- $Title "
        $Padding  = "-" * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ""
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    function ConvertTo-EasternTime {
        param ($UtcDateTime)
        if (-not $UtcDateTime) { return "" }
        try {
            $Dt = if ($UtcDateTime -is [DateTime]) {
                $UtcDateTime
            }
            else {
                [DateTime]::Parse($UtcDateTime.ToString(), [System.Globalization.CultureInfo]::InvariantCulture,
                                  [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                                  [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            }
            if ($Dt.Kind -ne [DateTimeKind]::Utc) {
                $Dt = [DateTime]::SpecifyKind($Dt, [DateTimeKind]::Utc)
            }
            $Et = [System.TimeZoneInfo]::ConvertTimeFromUtc($Dt, $EasternTZ)
            $TzAbbr = if ($EasternTZ.IsDaylightSavingTime($Et)) { "EDT" } else { "EST" }
            return ("{0} {1}" -f $Et.ToString("yyyy-MM-dd HH:mm:ss"), $TzAbbr)
        }
        catch {
            return ""
        }
    }

    function Add-EasternTimeColumnsToCsv {
        param ([string]$CsvPath, [string[]]$TimeFields)
        try {
            $Rows = Import-Csv -Path $CsvPath
            if (-not $Rows) { return }
            $Result = foreach ($Row in $Rows) {
                $NewRow = [ordered]@{}
                foreach ($Prop in $Row.PSObject.Properties) {
                    $NewRow[$Prop.Name] = $Prop.Value
                    if ($TimeFields -contains $Prop.Name) {
                        $EtName = $Prop.Name + "_ET"
                        $NewRow[$EtName] = ConvertTo-EasternTime -UtcDateTime $Prop.Value
                    }
                }
                [PSCustomObject]$NewRow
            }
            $Result | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        }
        catch {
            Write-Log "Could not add ET columns to $CsvPath : $($_.Exception.Message)" -Severity WARN
        }
    }

    function Add-ManifestEntry {
        param (
            [string]$FilePath,
            [string]$Description,
            [string]$Source
        )
        $ManifestPath = Join-Path -Path $AnalysisPath -ChildPath "Evidence-Manifest.csv"
        if (-not (Test-Path -Path $FilePath)) { return }
        try {
            $Hash = (Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash
            $FileInfo = Get-Item -Path $FilePath
            $UtcNow   = (Get-Date).ToUniversalTime()
            $Entry = [PSCustomObject]@{
                FileName         = $FileInfo.Name
                RelativePath     = $FilePath.Replace($Config.BECInvestigation.Paths.RootPath, '').TrimStart('\')
                Description      = $Description
                Source           = $Source
                SizeBytes        = $FileInfo.Length
                CollectedUtc     = $UtcNow.ToString("yyyy-MM-dd HH:mm:ss") + " UTC"
                CollectedEastern = ConvertTo-EasternTime -UtcDateTime $UtcNow
                SHA256           = $Hash
            }

            # Append to existing manifest if present, else create new
            if (Test-Path -Path $ManifestPath) {
                $Existing = @(Import-Csv -Path $ManifestPath)
                # Remove any prior entry for the same file (replace with latest)
                $Existing = $Existing | Where-Object { $_.FileName -ne $FileInfo.Name }
                $Combined = @($Existing) + @($Entry)
                $Combined | Export-Csv -Path $ManifestPath -NoTypeInformation -Encoding UTF8
            }
            else {
                @($Entry) | Export-Csv -Path $ManifestPath -NoTypeInformation -Encoding UTF8
            }
        }
        catch {
            Write-Log "Could not update manifest for $FilePath : $($_.Exception.Message)" -Severity WARN
        }
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = "Continue"

    Write-Banner -Title "BEC MESSAGE TRACE RETRIEVAL v$ScriptVersion" -Color Cyan
    Write-Console "Investigation : $InvestigationID" -Severity PLAIN
    Write-Console "Victim        : $VictimEmail" -Severity PLAIN
    Write-Console "Transcript    : $TranscriptPath" -Severity PLAIN

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Investigation : $InvestigationID" -Severity INFO
    Write-Log "Sent Job ID   : $SentJobId" -Severity INFO
    Write-Log "Recv Job ID   : $ReceivedJobId" -Severity INFO

    if (-not $SentJobId -and -not $ReceivedJobId) {
        Write-Log     "No trace job IDs found in Investigation.xml. Run Invoke-BECDataCollection.ps1 first." -Severity WARN
        Write-Console "No trace job IDs found - run data collection first." -Severity WARN
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 0
    }

    try {
        # Module check
        Import-Module -Name ExchangeOnlineManagement -Force -ErrorAction Stop

        Write-Section -Title "Connecting to Exchange Online"
        # WAM auto-fallback: detect 0x80070520 (logon-session error from
        # mismatched PS user context) and retry with -DisableWAM. See
        # Invoke-BECDataCollection.ps1 for the full rationale.
        $RetrievalExoConnected = $false
        if ($DisableWAM) {
            Write-Console "Connecting without WAM (forced via -DisableWAM)..." -Severity INFO -Indent 1
            try {
                Connect-ExchangeOnline -ShowBanner:$false -DisableWAM -ErrorAction Stop
                $RetrievalExoConnected = $true
                Write-Log     "Connected to Exchange Online (WAM disabled)." -Severity SUCCESS
                Write-Console "Connected (WAM disabled)." -Severity SUCCESS -Indent 1
            }
            catch {
                Write-Log     "Failed to connect to Exchange Online: $($_.Exception.Message)" -Severity ERROR
                Write-Console "Failed to connect to Exchange Online." -Severity ERROR -Indent 1
                Write-Banner -Title "FATAL - EXCHANGE ONLINE CONNECT FAILED" -Color Red
                Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
                exit 2
            }
        }
        else {
            try {
                Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
                $RetrievalExoConnected = $true
                Write-Log     "Connected to Exchange Online." -Severity SUCCESS
                Write-Console "Connected." -Severity SUCCESS -Indent 1
            }
            catch {
                $ErrMsg = $_.Exception.Message
                $IsWamSessionError = ($ErrMsg -match '0x80070520') -or
                                     ($ErrMsg -match 'specified logon session does not exist') -or
                                     ($ErrMsg -match '0x21420087')
                if ($IsWamSessionError) {
                    Write-Log     "  WAM authentication failed - auto-retrying with -DisableWAM..." -Severity WARN
                    Write-Console "WAM error - auto-retrying with -DisableWAM..." -Severity WARN -Indent 1
                    try {
                        Connect-ExchangeOnline -ShowBanner:$false -DisableWAM -ErrorAction Stop
                        $RetrievalExoConnected = $true
                        Write-Log     "Connected to Exchange Online (WAM disabled, auto-fallback)." -Severity SUCCESS
                        Write-Console "Connected (WAM disabled)." -Severity SUCCESS -Indent 1
                    }
                    catch {
                        Write-Log     "Auto-fallback also failed: $($_.Exception.Message)" -Severity ERROR
                        Write-Console "Auto-fallback also failed: $($_.Exception.Message)" -Severity ERROR -Indent 1
                        Write-Banner -Title "FATAL - EXCHANGE ONLINE CONNECT FAILED" -Color Red
                        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
                        exit 2
                    }
                }
                else {
                    Write-Log     "Failed to connect to Exchange Online: $ErrMsg" -Severity ERROR
                    Write-Console "Failed to connect to Exchange Online." -Severity ERROR -Indent 1
                    Write-Banner -Title "FATAL - EXCHANGE ONLINE CONNECT FAILED" -Color Red
                    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
                    exit 2
                }
            }
        }

        $JobIds = @($SentJobId, $ReceivedJobId) | Where-Object { $_ -ne "" }
        $AllJobs = Get-HistoricalSearch | Where-Object { $_.JobId -in $JobIds }
        $DownloadCount = 0

        Write-Section -Title "Checking Trace Job Status"
        foreach ($Job in $AllJobs) {
            $Type = if ($Job.ReportTitle -match "Sent") { "Sent" } else { "Received" }
            $OutFile = Join-Path -Path $RawDataPath -ChildPath "MessageTrace-${Type}_${UserAlias}.csv"

            Write-Log     "Job: $($Job.ReportTitle)  Status: $($Job.Status)" -Severity INFO
            Write-Console "$Type trace : $($Job.Status)" -Severity INFO -Indent 1

            if ($Job.Status -eq "Done") {
                $Report = Get-HistoricalSearch -JobId $Job.JobId
                if ($Report.ReportUrl) {
                    try {
                        Invoke-WebRequest -Uri $Report.ReportUrl -OutFile $OutFile -ErrorAction Stop -UseBasicParsing
                        Write-Log     "$Type trace downloaded: $(Split-Path -Path $OutFile -Leaf)" -Severity SUCCESS
                        Write-Console "Downloaded $(Split-Path -Path $OutFile -Leaf)" -Severity SUCCESS -Indent 1

                        # Add ET columns to downloaded trace
                        # Historical trace CSVs typically use 'date_time_utc' or similar - try common fields
                        $CommonTimeFields = @('date_time_utc', 'DateTime', 'Received', 'received_utc', 'origin_timestamp_utc')
                        Add-EasternTimeColumnsToCsv -CsvPath $OutFile -TimeFields $CommonTimeFields

                        # Manifest entry
                        Add-ManifestEntry -FilePath $OutFile -Description "Historical Message Trace - $Type" `
                            -Source "Start-HistoricalSearch -> Invoke-WebRequest"
                        $DownloadCount++
                    }
                    catch {
                        Write-Log     "Download failed for $Type trace: $($_.Exception.Message)" -Severity ERROR
                        Write-Console "Download failed for $Type trace: $($_.Exception.Message)" -Severity ERROR -Indent 1
                    }
                }
                else {
                    Write-Log     "$Type trace completed but report URL not yet available. Wait and retry." -Severity WARN
                    Write-Console "$Type trace URL pending - retry in a few minutes." -Severity WARN -Indent 1
                }
            }
            else {
                Write-Log     "$Type trace not ready (Status: $($Job.Status)). Re-run this script later." -Severity INFO
                Write-Console "$Type trace not ready - re-run this script in a few minutes." -Severity INFO -Indent 1
            }
        }

        # Update XML if all traces downloaded
        if ($DownloadCount -ge $JobIds.Count) {
            try {
                $Config.BECInvestigation.MessageTraces.TracesCompleted = "true"
                $Config.Save($ConfigPath)
                Write-Log     "All traces downloaded. Investigation.xml updated." -Severity SUCCESS
                Write-Log     "Next: Run .\Invoke-BECLogAnalysis.ps1 for complete analysis." -Severity INFO
                Write-Console "" -Severity PLAIN
                Write-Console "Next: .\Invoke-BECLogAnalysis.ps1 (full analysis)" -Severity INFO
            }
            catch {
                Write-Log "Failed to update Investigation.xml: $($_.Exception.Message)" -Severity WARN
            }
        }
        elseif ($DownloadCount -gt 0) {
            Write-Log     "$DownloadCount of $($JobIds.Count) traces downloaded. Re-run when remaining complete." -Severity WARN
            Write-Console "$DownloadCount of $($JobIds.Count) traces downloaded." -Severity WARN
        }
        else {
            Write-Log "No traces downloaded this run." -Severity INFO
        }

        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

        Write-Banner -Title "TRACE RETRIEVAL COMPLETE" -Color Green
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 0
    }
    catch {
        Write-Log "Unhandled exception: $_" -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Banner -Title "TRACE RETRIEVAL FAILED" -Color Red
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }

} # End function Invoke-BECMessageTraceRetrieval

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    DisableWAM = $DisableWAM
}

Invoke-BECMessageTraceRetrieval @ScriptParams
'@

        # ----------------------------------------------------------------------
        # Token substitution + write scripts
        # ----------------------------------------------------------------------
        $CreatedDate = Get-Date -Format "yyyy-MM-dd"

        $Substitutions = @{
            '{INVESTIGATION_ID}' = $InvestigationName
            '{VICTIM_EMAIL}'     = $VictimEmail
            '{CREATED_DATE}'     = $CreatedDate
            '{SCRIPT_VERSION}'   = $ScriptVersion
        }

        $ScriptDefinitions = @(
            @{ Content = $DataCollectionScript;  FileName = "Invoke-BECDataCollection.ps1" }
            @{ Content = $GraphCollectionScript; FileName = "Invoke-BECGraphCollection.ps1" }
            @{ Content = $AnalysisScript;        FileName = "Invoke-BECLogAnalysis.ps1" }
            @{ Content = $RetrievalScript;       FileName = "Invoke-BECMessageTraceRetrieval.ps1" }
        )

        foreach ($Def in $ScriptDefinitions) {
            $Content = $Def.Content
            foreach ($Token in $Substitutions.Keys) {
                $Content = $Content -replace [regex]::Escape($Token), $Substitutions[$Token]
            }
            $OutPath = Join-Path -Path $ScriptsPath -ChildPath $Def.FileName
            $Content | Out-File -FilePath $OutPath -Encoding UTF8
            Write-Log     "  Generated: $($Def.FileName)" -Severity SUCCESS
            Write-Console "Generated: $($Def.FileName)" -Severity SUCCESS -Indent 1
        }

        Write-Log "All investigation scripts generated." -Severity SUCCESS

        # ======================================================================
        # STEP 4 - INVESTIGATION README (CIPP-FIRST WORKFLOW)
        # ======================================================================
        Write-Section -Title "Creating Investigation-README.txt"
        Write-Log "Creating Investigation-README.txt..." -Severity INFO

        $ScopeDesc = if ($LookbackHours -gt 0) {
            "$LookbackHours hours (custom override)"
        }
        else {
            "$Scope ($($ScopePresets[$Scope]) hours)"
        }

        $ReadmeContent = @"
============================================================================
BEC INVESTIGATION WORKSPACE
Start-BECInvestigation.ps1 v$ScriptVersion
============================================================================

Investigation ID : $InvestigationName
Victim           : $VictimEmail
Technician       : $Technician
$(if ($IncidentTicket) {"Ticket           : $IncidentTicket"})
Default Scope    : $ScopeDesc
Created          : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

============================================================================
WORKFLOW
============================================================================

------------------------------------------------------------
STEP 0 - CIPP COMPROMISE REMEDIATION (DO THIS FIRST)
------------------------------------------------------------
Before collecting evidence, CONTAIN THE THREAT in CIPP:

    CIPP > Identity > Administration > Users > [select victim]
         > Compromise Remediation

The "Execute Compromise Remediation" button performs these actions
in a single click:
    * Block user sign-in
    * Reset user password
    * Disconnect all active sessions
    * Remove all MFA methods (forces re-registration)
    * Disable all inbox rules

CIPP also surfaces an automated Indicators of Compromise (IoC) panel that
highlights mailbox rules, new users, and suspicious sign-ins for the tenant.

DO NOT USE MANUAL POWERSHELL FOR REMEDIATION. The containment workflow is
now centralized in CIPP.

The following actions are NOT part of CIPP's Compromise Remediation
and must be reviewed manually after analysis completes:
    * Tenant-level Transport Rules (EAC > Mail Flow > Rules)
    * OAuth consents granted to malicious apps (Entra > Enterprise Apps)
    * Conditional Access policy modifications
    * New service principals / app registrations created in the window
    * Directory role memberships

------------------------------------------------------------
STEP 1a - EXCHANGE ONLINE DATA COLLECTION (5-15 min)   [PowerShell 5.1]
------------------------------------------------------------
Open a Windows PowerShell 5.1 window (the default 'powershell.exe'):

    cd "$InvestigationPath\Scripts"
    .\Invoke-BECDataCollection.ps1

    Default lookback: $ScopeDesc.

    To override lookback:
      .\Invoke-BECDataCollection.ps1 -Scope Extended        # 30 days
      .\Invoke-BECDataCollection.ps1 -Scope Maximum         # 90 days
      .\Invoke-BECDataCollection.ps1 -LookbackHours 48      # 48 hours

    Optional: -SkipHistoricalTraces to skip async trace submission.

    This script collects Exchange Online artifacts only:
      - Inbox rules + suspicious rule flagging
      - Mail forwarding (mailbox-level)
      - Transport rules (tenant-level forwarding)
      - Mailbox permissions
      - Mobile devices
      - UAL ExchangeItem ops
      - UAL rule manipulation events
      - UAL send operations
      - UAL MailItemsAccessed (best-effort, Purview Audit Standard+)
      - UAL SharePoint/OneDrive file downloads
      - UAL login events
      - UAL MFA / password changes
      - UAL role membership changes
      - UAL Conditional Access policy changes
      - UAL OAuth consent events
      - Quick message traces (Get-MessageTraceV2, last 10 days)
      - Historical message traces (async, full window)

    Writes SHA-256 Evidence-Manifest.csv to Analysis folder.

    The script force-disconnects Exchange Online at the end so the Graph
    collection in Step 1b can authenticate cleanly.

------------------------------------------------------------
STEP 1b - MICROSOFT GRAPH COLLECTION (3-5 min)   [PowerShell 7]
------------------------------------------------------------
Leave your PowerShell 5.1 window OPEN (you'll return to it).
Open a NEW PowerShell 7 window (search 'pwsh' in Start Menu). Then:

    cd "$InvestigationPath\Scripts"
    .\Invoke-BECGraphCollection.ps1

    This script collects Entra ID / Graph artifacts:
      - Sign-in logs (IP, location, session, risk)
      - Risky users and risk detections (Entra ID Protection)
      - Current MFA / authentication methods
      - Directory role memberships
      - Enterprise apps / service principals (flags new-in-window)
      - OAuth permission grants
      - Conditional Access policies

    WHY POWERSHELL 7 FOR THIS STEP?
    Microsoft officially recommends PowerShell 7 for the Graph SDK. The
    Graph modules have known assembly-loading issues in Windows PowerShell
    5.1 (MSAL/WAM conflict, msgraph-sdk-powershell GitHub issue #3576).
    PS7 runs on .NET 8.0 with better assembly isolation and avoids these
    problems. The script detects the PS edition at startup and warns if
    you're in 5.1.

    If you do not have PowerShell 7 installed:
      winget install --id Microsoft.PowerShell --source winget
    Then close and reopen your terminal so 'pwsh' is on the PATH.

    When Step 1b finishes, CLOSE the PowerShell 7 window and return to
    your PowerShell 5.1 window for all remaining steps.

    POTENTIAL FUTURE FEATURE: A Run-All helper script that launches each
    collection step in its own PowerShell process automatically. Not
    generated today - let us know if it would be useful in the field.

------------------------------------------------------------
STEP 2 - IMMEDIATE ANALYSIS (1-2 min)   [back to PowerShell 5.1]
------------------------------------------------------------
    .\Invoke-BECLogAnalysis.ps1 -SkipMessageTraces

    Produces:
      Analysis\ANALYSIS-REPORT.txt   <- START HERE
      Analysis\All-Findings.csv
      Analysis\Timeline.csv           <- chronological event timeline
      Reports\SUSPICIOUS-Rules_$UserAlias.csv (if applicable)

------------------------------------------------------------
STEP 3 - RETRIEVE HISTORICAL TRACES (~30 min wait, then <1 min)
------------------------------------------------------------
    .\Invoke-BECMessageTraceRetrieval.ps1

    Downloads completed historical traces. Safe to re-run if traces
    are not ready yet.

------------------------------------------------------------
STEP 4 - COMPLETE ANALYSIS (2-3 min)
------------------------------------------------------------
    .\Invoke-BECLogAnalysis.ps1

    Re-runs analysis with full trace data. Updates ANALYSIS-REPORT.txt.

============================================================================
DETECTION CAPABILITIES (v$ScriptVersion)
============================================================================
The analyzer flags the following BEC indicators:

CRITICAL severity:
    - Entra ID Protection risky user flag
    - Entra ID Protection high-confidence risk detections
      (AiTM, anomalous token, leaked credentials, malicious IP)
    - Impossible travel (cross-country signins in short window)
    - Session ID reuse across IPs (AiTM / token theft)
    - New MFA device registered during window
    - OAuth consent granted by victim during window
    - Admin role assignments involving victim during window
    - MailItemsAccessed Sync events (full mailbox download)
    - MailItemsAccessed logging throttled (assume full access)
    - Email forwarding/redirect rules
    - SMTP forwarding enabled on mailbox

HIGH severity:
    - Inbox rule creation/deletion during window
    - Suspicious rule name patterns (single chars, financial keywords)
    - Tenant-level transport rules with forwarding
    - New service principals in window (OAuth phishing)
    - CA policy modifications in window
    - Admin/directory role memberships
    - Send volume spikes
    - File download volume spikes (SharePoint/OneDrive exfiltration)
    - Failed login volume (brute force / password spray)

MEDIUM severity:
    - Delegated mailbox permissions
    - Move-to-folder rules to non-standard locations
    - External recipient ratio anomalies
    - OAuth consent events in tenant (non-victim)

============================================================================
EVIDENCE MANIFEST
============================================================================
Analysis\Evidence-Manifest.csv contains a SHA-256 hash of every
collected artifact. This supports chain-of-custody documentation
and tamper detection (re-hash any file and compare to manifest).

See Analysis\Evidence-Manifest-README.txt for verification instructions.

============================================================================
INVESTIGATION CONFIGURATION
============================================================================
Config File  : Investigation.xml (do not edit manually - scripts update it)
Working Dir  : $InvestigationPath

Check status at any time:
  PS> [xml]`$c = Get-Content ..\Investigation.xml
  PS> `$c.BECInvestigation.DataCollection.Completed
  PS> `$c.BECInvestigation.GraphCollection.Completed
  PS> `$c.BECInvestigation.MessageTraces.TracesCompleted
  PS> `$c.BECInvestigation.Analysis.CriticalFindingsCount

============================================================================
TIMESTAMP CONVENTIONS
============================================================================
All CSV files with time fields have a sibling _ET column showing the same
time in US Eastern (EST/EDT, auto-handled). Reports show UTC first with
Eastern in parentheses. This supports easy correlation between Microsoft's
native UTC timestamps and the technician's local clock.

============================================================================
For assistance: Contact Databranch MSP Team Lead
============================================================================
"@

        $ReadmePath = Join-Path -Path $InvestigationPath -ChildPath "Investigation-README.txt"
        $ReadmeContent | Out-File -FilePath $ReadmePath -Encoding UTF8
        Write-Log     "Investigation-README.txt created." -Severity SUCCESS
        Write-Console "Investigation-README.txt created." -Severity SUCCESS -Indent 1

        # ======================================================================
        # COMPLETE
        # ======================================================================
        Write-Log "===== Workspace initialization complete =====" -Severity SUCCESS
        Write-Log "Investigation workspace: $InvestigationPath" -Severity INFO

        Write-Banner -Title "WORKSPACE CREATED SUCCESSFULLY" -Color Green
        Write-Console "Investigation ID : $InvestigationName" -Severity PLAIN
        Write-Console "Workspace        : $InvestigationPath" -Severity PLAIN
        Write-Console "" -Severity PLAIN
        Write-Console "Next Steps:" -Severity INFO
        Write-Console "0. CIPP > Identity > Administration > Users > [victim] > Compromise Remediation" -Severity WARN -Indent 1
        Write-Console "1. In PowerShell 5.1 window:" -Severity INFO -Indent 1
        Write-Console "     cd `"$ScriptsPath`"" -Severity PLAIN -Indent 1
        Write-Console "     .\Invoke-BECDataCollection.ps1          (Exchange Online data)" -Severity PLAIN -Indent 1
        Write-Console "2. Open a NEW PowerShell 7 (pwsh) window:" -Severity INFO -Indent 1
        Write-Console "     cd `"$ScriptsPath`"" -Severity PLAIN -Indent 1
        Write-Console "     .\Invoke-BECGraphCollection.ps1         (Entra/Graph data)" -Severity PLAIN -Indent 1
        Write-Console "3. Close PS7 window, return to your PowerShell 5.1 window:" -Severity INFO -Indent 1
        Write-Console "     .\Invoke-BECLogAnalysis.ps1 -SkipMessageTraces   (immediate triage)" -Severity PLAIN -Indent 1
        Write-Console "" -Severity PLAIN
        Write-Console "See Investigation-README.txt for complete step-by-step guide." -Severity PLAIN
        Write-Console "" -Severity PLAIN

        try { Start-Process -FilePath "explorer.exe" -ArgumentList $InvestigationPath } catch { }

        exit 0
    }
    catch {
        Write-Log "Unhandled exception: $_" -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Banner -Title "SCRIPT FAILED" -Color Red
        Write-Console "Error : $_" -Severity ERROR
        exit 1
    }

} # End function Start-BECInvestigation

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    VictimEmail      = $VictimEmail
    WorkingDirectory = $WorkingDirectory
    IncidentTicket   = $IncidentTicket
    Technician       = $Technician
    LookbackHours    = $LookbackHours
    Scope            = $Scope
}

Start-BECInvestigation @ScriptParams
