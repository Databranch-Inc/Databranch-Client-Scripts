#Requires -Version 5.1
<#
.SYNOPSIS
    Initializes a BEC (Business Email Compromise) investigation workspace for a
    compromised Microsoft 365 user account.

.DESCRIPTION
    Start-BECInvestigation creates a complete, self-contained investigation workspace
    for a BEC incident. It generates a timestamped folder structure, an XML configuration
    file that tracks investigation state and all relevant paths, and three investigation
    scripts pre-configured with the victim's details:

        Invoke-BECDataCollection.ps1      - Collects mailbox forensic data from Exchange Online
        Invoke-BECLogAnalysis.ps1         - Analyzes collected data and produces findings reports
        Invoke-BECMessageTraceRetrieval.ps1 - Retrieves completed 30-day historical message traces

    This script is designed for interactive use by Databranch technicians on their
    local workstations. It does not connect to Exchange Online — all Exchange work
    is handled by the generated scripts. Once the workspace is created, the technician
    navigates to the Scripts subfolder and executes the generated scripts in sequence.

    Workspace folder structure:
        BEC-Investigation_<alias>_<timestamp>/
        ├── Investigation.xml                    (auto-managed config)
        ├── Investigation-README.txt             (per-investigation quick reference)
        ├── Scripts/
        │   ├── Invoke-BECDataCollection.ps1
        │   ├── Invoke-BECLogAnalysis.ps1
        │   └── Invoke-BECMessageTraceRetrieval.ps1
        ├── RawData/
        ├── Reports/
        ├── Analysis/
        └── Logs/

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

.EXAMPLE
    .\Start-BECInvestigation.ps1 -VictimEmail "john.doe@clientdomain.com"

    Minimal invocation. Creates the workspace under C:\Databranch_BEC using the
    current username as the technician name.

.EXAMPLE
    .\Start-BECInvestigation.ps1 -VictimEmail "john.doe@clientdomain.com" `
                                  -WorkingDirectory "D:\Investigations" `
                                  -IncidentTicket "INC-20458" `
                                  -Technician "Sam Kirsch"

    Full invocation with all optional parameters.

.NOTES
    File Name      : Start-BECInvestigation.ps1
    Version        : 3.0.1.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2024-02-15
    Last Modified  : 2026-02-20
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : Interactive - Technician workstation (local user context)
    DattoRMM       : Not applicable - interactive use only
    Client Scope   : All clients

    Exit Codes:
        0  - Workspace created successfully
        1  - General failure (folder creation, XML generation, or script generation failed)

.CHANGELOG
    v3.0.1.0 - 2026-02-20 - Sam Kirsch
        - Fixed Add-XmlElement type check: changed [hashtable] to [IDictionary]
          so [ordered]@{} sections (OrderedDictionary) are written as nested XML
          elements rather than collapsed to flat string values. This was causing
          all path variables and victim fields to read back as null from the XML.
        - Added null-guard validation in all three generated scripts after XML read;
          scripts now exit cleanly with a clear error if critical XML fields are missing
        - Fixed Get-ConnectionInformation call for NotifyAddress: now filters to
          State='Connected', sorts by ConnectedAt descending, takes first result
          to avoid picking up stale or unintended sessions
        - Made NotifyAddress optional in Start-HistoricalSearch calls using
          splatting so traces submit successfully even if UPN cannot be resolved
        - Moved Start-Transcript calls in all generated scripts to after XML
          validation so transcript failures don't mask the real root cause

    v3.0.0.0 - 2026-02-20 - Sam Kirsch
        - Renamed from Start-Investigation.ps1 to Start-BECInvestigation.ps1
        - Wrapped all logic in master function Start-BECInvestigation per project spec
        - Added #Requires -Version 5.1
        - Added full compliant .NOTES and .CHANGELOG header block
        - Added Write-Log + Initialize-Logging per project spec
        - Replaced all Write-Host with Write-Log throughout
        - Moved Add-XmlElement helper inside master function
        - Added $ScriptVersion variable; version surfaced in log header and README
        - Generated scripts renamed to Verb-Noun format:
            BEC-DataCollection.ps1         → Invoke-BECDataCollection.ps1
            BEC-LogAnalysis.ps1            → Invoke-BECLogAnalysis.ps1
            BEC-MessageTrace-Retrieval.ps1 → Invoke-BECMessageTraceRetrieval.ps1
        - Generated scripts updated with compliant headers, Write-Log, master functions
        - Investigation-README.txt updated to reflect new script names and version
        - Entry point converted to splatted parameter call

    v2.3.0.0 - 2024-02-15 - Sam Kirsch
        - O/D/S file conflict checks run BEFORE collection, not after
        - Improved mailbox permissions handling (empty result no longer treated as error)
        - Better error messages throughout data collection
        - Analysis script: detects MoveToFolder, DeleteMessage, MarkAsRead rules
        - Analysis script: improved severity classification (CRITICAL/HIGH/MEDIUM/LOW)
        - "No findings" report now explains what clean results mean

    v2.0.0.0 - 2024-02-01 - Sam Kirsch
        - Redesigned as single-script deployment model
        - XML-based configuration management replaces manual parameter passing
        - All three investigation scripts auto-generated per investigation
        - Standardized folder structure (RawData, Reports, Analysis, Scripts, Logs)
        - Investigation.xml tracks state across all stages

    v1.0.0.0 - 2024-01-10 - Sam Kirsch
        - Initial release (manual multi-script workflow)
#>

# ==============================================================================
# PARAMETERS
# This script is designed for interactive technician use only.
# No DattoRMM environment variable fallback is needed or implemented.
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
    [string]$Technician = $env:USERNAME
)

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
        [string]$Technician
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Start-BECInvestigation"
    $ScriptVersion = "3.0.1.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path -Path $LogRoot -ChildPath $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path -Path $LogFolder -ChildPath "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # ==========================================================================
    # LOGGING FUNCTION
    # Writes to both stdout and log file with timestamp and severity level.
    # Severity: INFO, WARN, ERROR, SUCCESS, DEBUG
    # All severity levels are always logged (verbose by default).
    # ==========================================================================
    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
            [string]$Severity = "INFO"
        )

        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $LogEntry  = "[$Timestamp] [$Severity] $Message"

        switch ($Severity) {
            "INFO"    { Write-Output  $LogEntry }
            "WARN"    { Write-Warning $LogEntry }
            "ERROR"   { Write-Error   $LogEntry -ErrorAction Continue }
            "SUCCESS" { Write-Output  $LogEntry }
            "DEBUG"   { Write-Output  $LogEntry }
        }

        try {
            Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8
        }
        catch {
            Write-Warning "Could not write to log file: $_"
        }
    }

    # ==========================================================================
    # LOG SETUP
    # Creates log folder if needed and rotates old log files.
    # ==========================================================================
    function Initialize-Logging {
        if (-not (Test-Path -Path $LogFolder)) {
            try {
                New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
            }
            catch {
                Write-Warning "Could not create log folder '$LogFolder': $_"
            }
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
        catch {
            Write-Warning "Log rotation failed: $_"
        }
    }

    # ==========================================================================
    # XML HELPER FUNCTION
    # Recursively builds XML elements from a dictionary.
    # Accepts both [hashtable] and [ordered]@{} (OrderedDictionary).
    # Uses IDictionary interface check so both types are handled correctly.
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

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Run As   : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -Severity INFO
    Write-Log "Params   : VictimEmail='$VictimEmail' | WorkingDirectory='$WorkingDirectory' | Technician='$Technician' | IncidentTicket='$IncidentTicket'" -Severity INFO
    Write-Log "Log File : $LogFile" -Severity INFO

    # Derive investigation identifiers
    $UserAlias         = $VictimEmail.Split("@")[0]
    $Domain            = $VictimEmail.Split("@")[1]
    $Timestamp         = Get-Date -Format "yyyyMMdd-HHmmss"
    $InvestigationName = "BEC-Investigation_${UserAlias}_${Timestamp}"
    $InvestigationPath = Join-Path -Path $WorkingDirectory -ChildPath $InvestigationName

    Write-Log "Starting BEC investigation workspace initialization..." -Severity INFO
    Write-Log "Victim       : $VictimEmail" -Severity INFO
    Write-Log "Investigation: $InvestigationName" -Severity INFO
    Write-Log "Workspace    : $InvestigationPath" -Severity INFO

    try {

        # ------------------------------------------------------------------
        # STEP 1: Create folder structure
        # ------------------------------------------------------------------
        Write-Log "Creating investigation folder structure..." -Severity INFO

        try {
            New-Item -Path $InvestigationPath -ItemType Directory -Force | Out-Null
            $SubFolders = @("Logs", "RawData", "Reports", "Analysis", "Scripts")
            foreach ($Folder in $SubFolders) {
                New-Item -Path (Join-Path -Path $InvestigationPath -ChildPath $Folder) -ItemType Directory -Force | Out-Null
                Write-Log "  Created subfolder: $Folder" -Severity DEBUG
            }
            Write-Log "Folder structure created successfully." -Severity SUCCESS
        }
        catch {
            Write-Log "Failed to create folder structure: $($_.Exception.Message)" -Severity ERROR
            exit 1
        }

        # ------------------------------------------------------------------
        # STEP 2: Create Investigation.xml configuration file
        # ------------------------------------------------------------------
        Write-Log "Creating Investigation.xml configuration file..." -Severity INFO

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
                DaysSearched   = "30"
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
            $XmlDoc     = New-Object System.Xml.XmlDocument
            $XmlDecl    = $XmlDoc.CreateXmlDeclaration("1.0", "UTF-8", $null)
            $XmlDoc.AppendChild($XmlDecl) | Out-Null

            $XmlRoot = $XmlDoc.CreateElement("BECInvestigation")
            $XmlDoc.AppendChild($XmlRoot) | Out-Null

            Add-XmlElement -Parent $XmlRoot -Data $ConfigData

            $XmlSettings            = New-Object System.Xml.XmlWriterSettings
            $XmlSettings.Indent     = $true
            $XmlSettings.IndentChars    = "  "
            $XmlSettings.NewLineChars   = "`r`n"
            $XmlSettings.Encoding       = [System.Text.Encoding]::UTF8

            $XmlWriter = [System.Xml.XmlWriter]::Create($ConfigPath, $XmlSettings)
            $XmlDoc.Save($XmlWriter)
            $XmlWriter.Close()

            Write-Log "Investigation.xml created: $ConfigPath" -Severity SUCCESS
        }
        catch {
            Write-Log "Failed to create Investigation.xml: $($_.Exception.Message)" -Severity ERROR
            exit 1
        }

        # ------------------------------------------------------------------
        # STEP 3: Generate investigation scripts
        # ------------------------------------------------------------------
        $ScriptsPath = Join-Path -Path $InvestigationPath -ChildPath "Scripts"
        Write-Log "Generating investigation scripts..." -Severity INFO

        # ---- Invoke-BECDataCollection.ps1 ----
        Write-Log "  Generating Invoke-BECDataCollection.ps1..." -Severity DEBUG
        $DataCollectionScript = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Collects forensic mailbox data from Exchange Online for a BEC investigation.

.DESCRIPTION
    Invoke-BECDataCollection connects to Exchange Online and collects all relevant
    forensic artifacts for a compromised M365 mailbox. All configuration (victim email,
    output paths, search period) is read from Investigation.xml in the parent folder.

    Data collected:
      - Inbox rules (with suspicious rule flagging to Reports folder)
      - Mail forwarding settings
      - Mailbox permissions (delegated, non-inherited)
      - Registered mobile devices
      - Unified audit logs (Exchange item operations, last N days)
      - Quick message traces (last 10 days, immediate results)
      - Historical message traces (last N days, async - 15-30 min to complete)

    When a data file already exists (re-run scenario), the technician is prompted
    to Overwrite, Duplicate (versioned _v2, _v3...), or Skip each collection.

    Execution is logged to the investigation Logs folder via Start-Transcript.
    All output is written to RawData and Reports subfolders defined in Investigation.xml.

.PARAMETER SkipHistoricalTraces
    Optional switch. If specified, the 30-day historical message trace submission
    is skipped. Useful when re-running data collection and traces are already in progress.

.EXAMPLE
    .\Invoke-BECDataCollection.ps1
    Standard run. Reads all config from Investigation.xml. Prompts if files exist.

.EXAMPLE
    .\Invoke-BECDataCollection.ps1 -SkipHistoricalTraces
    Collects all data but does not submit new historical message trace jobs.

.NOTES
    File Name      : Invoke-BECDataCollection.ps1
    Version        : {SCRIPT_VERSION}
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : {CREATED_DATE}
    Last Modified  : {CREATED_DATE}
    Modified By    : Sam Kirsch

    Investigation  : {INVESTIGATION_ID}
    Victim         : {VICTIM_EMAIL}

    Requires       : PowerShell 5.1+, ExchangeOnlineManagement module
    Run Context    : Interactive - Technician workstation (Exchange Administrator or Global Admin)
    DattoRMM       : Not applicable
    Client Scope   : Per-investigation (generated script)

    Exit Codes:
        0  - Data collection completed successfully
        1  - Fatal failure (Exchange connection failed, user not found, XML not found)

.CHANGELOG
    v{SCRIPT_VERSION} - {CREATED_DATE} - Sam Kirsch
        - Generated by Start-BECInvestigation.ps1 v{SCRIPT_VERSION}
        - Renamed from BEC-DataCollection.ps1 to Invoke-BECDataCollection.ps1
        - Added full compliant header block
        - Added Write-Log function (mirrors project standard)
        - Wrapped logic in master function Invoke-BECDataCollection
        - Entry point uses splatted call
        - Preserved all v2.3 collection logic and O/D/S file handling
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch]$SkipHistoricalTraces
)

function Invoke-BECDataCollection {
    [CmdletBinding()]
    param (
        [switch]$SkipHistoricalTraces
    )

    # ==========================================================================
    # CONFIGURATION FROM XML
    # ==========================================================================
    $ScriptName    = "Invoke-BECDataCollection"
    $ScriptVersion = "{SCRIPT_VERSION}"

    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\Investigation.xml"
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Host "[ERROR] Investigation.xml not found. Ensure you are running from the Scripts folder." -ForegroundColor Red
        exit 1
    }

    [xml]$Config      = Get-Content -Path $ConfigPath -Encoding UTF8
    $VictimEmail      = $Config.BECInvestigation.Victim.Email
    $UserAlias        = $Config.BECInvestigation.Victim.UserAlias
    $RawDataPath      = $Config.BECInvestigation.Paths.RawDataPath
    $LogsPath         = $Config.BECInvestigation.Paths.LogsPath
    $ReportsPath      = $Config.BECInvestigation.Paths.ReportsPath
    $DaysToSearch     = [int]$Config.BECInvestigation.DataCollection.DaysSearched

    # Validate critical values loaded from XML before proceeding.
    # If these are null/empty the XML structure is wrong (re-run Start-BECInvestigation.ps1).
    $XmlValidationErrors = @()
    if (-not $VictimEmail)  { $XmlValidationErrors += "Victim.Email" }
    if (-not $UserAlias)    { $XmlValidationErrors += "Victim.UserAlias" }
    if (-not $RawDataPath)  { $XmlValidationErrors += "Paths.RawDataPath" }
    if (-not $LogsPath)     { $XmlValidationErrors += "Paths.LogsPath" }
    if (-not $ReportsPath)  { $XmlValidationErrors += "Paths.ReportsPath" }
    if ($XmlValidationErrors.Count -gt 0) {
        Write-Host "[ERROR] Investigation.xml is missing required fields: $($XmlValidationErrors -join ', ')" -ForegroundColor Red
        Write-Host "[ERROR] The XML may be corrupted. Re-run Start-BECInvestigation.ps1 to regenerate the workspace." -ForegroundColor Red
        exit 1
    }

    # ==========================================================================
    # LOGGING
    # This generated script uses Start-Transcript for session capture, plus a
    # lightweight Write-Log for structured severity output within the transcript.
    # ==========================================================================
    $TranscriptTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $TranscriptPath      = Join-Path -Path $LogsPath -ChildPath "DataCollection_${TranscriptTimestamp}.log"
    Start-Transcript -Path $TranscriptPath

    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]  [string]$Message,
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
            [string]$Severity = "INFO"
        )
        $Ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Entry = "[$Ts] [$Severity] $Message"
        switch ($Severity) {
            "WARN"    { Write-Warning $Entry }
            "ERROR"   { Write-Error   $Entry -ErrorAction Continue }
            default   { Write-Output  $Entry }
        }
    }

    # ==========================================================================
    # FILE CONFLICT HELPER
    # Checks BEFORE collection runs. Returns action + resolved file path.
    # ==========================================================================
    function Get-OutputFileAction {
        param (
            [string]$BasePath,
            [string]$Description
        )

        if (Test-Path -Path $BasePath) {
            Write-Log "File already exists: $(Split-Path -Path $BasePath -Leaf)" -Severity WARN
            $Choice = Read-Host "  [O]verwrite, [D]uplicate, or [S]kip $Description? [O/D/S]"

            switch ($Choice.ToUpper()) {
                "O" {
                    Write-Log "  Will overwrite existing file." -Severity INFO
                    return @{ Action = "Collect"; Path = $BasePath }
                }
                "D" {
                    $Dir      = Split-Path -Path $BasePath -Parent
                    $FileName = [System.IO.Path]::GetFileNameWithoutExtension($BasePath)
                    $Ext      = [System.IO.Path]::GetExtension($BasePath)
                    $Version  = 2
                    while (Test-Path -Path (Join-Path -Path $Dir -ChildPath "${FileName}_v${Version}${Ext}")) {
                        $Version++
                    }
                    $NewPath = Join-Path -Path $Dir -ChildPath "${FileName}_v${Version}${Ext}"
                    Write-Log "  Will create duplicate: $(Split-Path -Path $NewPath -Leaf)" -Severity INFO
                    return @{ Action = "Collect"; Path = $NewPath }
                }
                default {
                    Write-Log "  Skipping $Description." -Severity INFO
                    return @{ Action = "Skip"; Path = $null }
                }
            }
        }

        return @{ Action = "Collect"; Path = $BasePath }
    }

    # ==========================================================================
    # CSV EXPORT HELPER
    # ==========================================================================
    function Export-DataWithLogging {
        param (
            $Data,
            [string]$FilePath,
            [string]$Description
        )
        try {
            if ($Data) {
                $Data | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
                $Count = ($Data | Measure-Object).Count
                Write-Log "$Description : $Count record(s) written to $(Split-Path -Path $FilePath -Leaf)" -Severity SUCCESS
                return $true
            }
            else {
                Write-Log "$Description : No data found." -Severity INFO
                return $false
            }
        }
        catch {
            Write-Log "$Description : Export failed - $($_.Exception.Message)" -Severity ERROR
            return $false
        }
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = "Continue"

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Investigation : $($Config.BECInvestigation.Investigation.InvestigationID)" -Severity INFO
    Write-Log "Victim        : $VictimEmail" -Severity INFO
    Write-Log "Search Period : Last $DaysToSearch days" -Severity INFO
    Write-Log "Transcript    : $TranscriptPath" -Severity INFO

    $StartDate = (Get-Date).AddDays(-$DaysToSearch)
    $EndDate   = Get-Date

    # ---- Verify ExchangeOnlineManagement module ----
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Log "ExchangeOnlineManagement module not found. Installing for current user..." -Severity WARN
        Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name ExchangeOnlineManagement -ErrorAction Stop

    # ---- Connect to Exchange Online ----
    Write-Log "Connecting to Exchange Online (REST API)..." -Severity INFO
    try {
        Connect-ExchangeOnline -ShowBanner:$false -UseRPSSession:$false -ErrorAction Stop
        Write-Log "Connected to Exchange Online." -Severity SUCCESS
    }
    catch {
        Write-Log "Failed to connect to Exchange Online: $($_.Exception.Message)" -Severity ERROR
        Stop-Transcript
        exit 1
    }

    # ---- Verify victim mailbox ----
    try {
        $UserMailbox = Get-Mailbox -Identity $VictimEmail -ErrorAction Stop
        Write-Log "User verified: $($UserMailbox.DisplayName) ($VictimEmail)" -Severity SUCCESS
    }
    catch {
        Write-Log "Victim mailbox not found: $VictimEmail - $($_.Exception.Message)" -Severity ERROR
        Disconnect-ExchangeOnline -Confirm:$false
        Stop-Transcript
        exit 1
    }

    # ==========================================================================
    # DATA COLLECTION
    # ==========================================================================

    # ---- Inbox Rules ----
    Write-Log "--- Collecting Inbox Rules ---" -Severity INFO
    $FileAction = Get-OutputFileAction -BasePath "$RawDataPath\InboxRules_${UserAlias}.csv" -Description "Inbox Rules"
    if ($FileAction.Action -eq "Collect") {
        try {
            $Rules = Get-InboxRule -Mailbox $VictimEmail -ErrorAction Stop
            if ($Rules) {
                $RuleDetails = $Rules | Select-Object -Property Name, Description, Enabled, Priority,
                    MoveToFolder, MarkAsRead, DeleteMessage, ForwardTo, ForwardAsAttachmentTo,
                    RedirectTo, MailboxOwnerId
                Export-DataWithLogging -Data $RuleDetails -FilePath $FileAction.Path -Description "Inbox Rules"

                # Flag suspicious rules to Reports folder
                $Suspicious = $RuleDetails | Where-Object {
                    $_.DeleteMessage -or $_.MoveToFolder -or $_.MarkAsRead -or $_.ForwardTo -or $_.RedirectTo
                }
                if ($Suspicious) {
                    $SuspiciousPath = "$ReportsPath\SUSPICIOUS-Rules_${UserAlias}.csv"
                    if ($FileAction.Path -match "_v(\d+)\.csv$") {
                        $SuspiciousPath = "$ReportsPath\SUSPICIOUS-Rules_${UserAlias}_v$($Matches[1]).csv"
                    }
                    Export-DataWithLogging -Data $Suspicious -FilePath $SuspiciousPath -Description "Suspicious Rules (flagged)"
                }
            }
            else {
                Write-Log "No inbox rules found." -Severity INFO
            }
        }
        catch {
            Write-Log "Inbox rules collection failed: $($_.Exception.Message)" -Severity ERROR
        }
    }

    # ---- Mail Forwarding ----
    Write-Log "--- Collecting Mail Forwarding Settings ---" -Severity INFO
    $FileAction = Get-OutputFileAction -BasePath "$RawDataPath\MailForwarding_${UserAlias}.csv" -Description "Mail Forwarding"
    if ($FileAction.Action -eq "Collect") {
        try {
            $Forwarding = Get-Mailbox -Identity $VictimEmail |
                Select-Object -Property UserPrincipalName, DisplayName,
                    ForwardingAddress, ForwardingSmtpAddress, DeliverToMailboxAndForward,
                    @{N='ForwardingEnabled'; E={ $null -ne $_.ForwardingAddress -or $null -ne $_.ForwardingSmtpAddress }}
            Export-DataWithLogging -Data $Forwarding -FilePath $FileAction.Path -Description "Mail Forwarding"
        }
        catch {
            Write-Log "Mail forwarding collection failed: $($_.Exception.Message)" -Severity ERROR
        }
    }

    # ---- Mailbox Permissions ----
    Write-Log "--- Collecting Mailbox Permissions ---" -Severity INFO
    $FileAction = Get-OutputFileAction -BasePath "$RawDataPath\MailboxPermissions_${UserAlias}.csv" -Description "Mailbox Permissions"
    if ($FileAction.Action -eq "Collect") {
        try {
            $Perms = Get-MailboxPermission -Identity $VictimEmail |
                Where-Object { $_.User -notlike "*SELF*" -and $_.IsInherited -eq $false }
            if ($Perms) {
                Export-DataWithLogging -Data $Perms -FilePath $FileAction.Path -Description "Mailbox Permissions"
            }
            else {
                Write-Log "No delegated mailbox permissions found (this is normal)." -Severity INFO
            }
        }
        catch {
            Write-Log "Mailbox permissions collection failed: $($_.Exception.Message)" -Severity ERROR
        }
    }

    # ---- Mobile Devices ----
    Write-Log "--- Collecting Mobile Devices ---" -Severity INFO
    $FileAction = Get-OutputFileAction -BasePath "$RawDataPath\MobileDevices_${UserAlias}.csv" -Description "Mobile Devices"
    if ($FileAction.Action -eq "Collect") {
        try {
            $Devices = Get-MobileDevice -Mailbox $VictimEmail -ErrorAction Stop
            if ($Devices) {
                Export-DataWithLogging -Data $Devices -FilePath $FileAction.Path -Description "Mobile Devices"
            }
            else {
                Write-Log "No mobile devices registered." -Severity INFO
            }
        }
        catch {
            Write-Log "Mobile devices collection failed: $($_.Exception.Message)" -Severity ERROR
        }
    }

    # ---- Unified Audit Logs ----
    Write-Log "--- Collecting Unified Audit Logs (this may take several minutes) ---" -Severity INFO
    $FileAction = Get-OutputFileAction -BasePath "$RawDataPath\UnifiedAuditLogs_${UserAlias}.csv" -Description "Unified Audit Logs"
    if ($FileAction.Action -eq "Collect") {
        try {
            $AuditLogs = Search-UnifiedAuditLog -StartDate $StartDate -EndDate $EndDate `
                -UserIds $VictimEmail -RecordType ExchangeItem -ResultSize 5000
            if ($AuditLogs) {
                Export-DataWithLogging -Data $AuditLogs -FilePath $FileAction.Path -Description "Unified Audit Logs"
            }
            else {
                Write-Log "No unified audit logs found." -Severity INFO
            }
        }
        catch {
            Write-Log "Unified audit log collection failed: $($_.Exception.Message)" -Severity ERROR
        }
    }
    else {
        Write-Log "Unified Audit Log collection skipped (can take 3-5 minutes)." -Severity INFO
    }

    # ---- Quick Message Traces (10 days) ----
    Write-Log "--- Running Quick Message Traces (last 10 days) ---" -Severity INFO
    $QuickStart         = (Get-Date).AddDays(-10)
    $WarningPreference  = "SilentlyContinue"

    # Detect API version
    $UseV2 = $false
    try {
        $null = Get-Command -Name Get-MessageTraceV2 -ErrorAction Stop
        $UseV2 = $true
        Write-Log "Using Get-MessageTraceV2 (REST API)." -Severity DEBUG
    }
    catch {
        Write-Log "Get-MessageTraceV2 not available. Using Get-MessageTrace V1 (deprecating Sept 2025)." -Severity WARN
    }

    # Sent messages
    $FileAction = Get-OutputFileAction -BasePath "$RawDataPath\QuickTrace-Sent_${UserAlias}.csv" -Description "Quick Trace - Sent"
    if ($FileAction.Action -eq "Collect") {
        try {
            $Sent = if ($UseV2) {
                Get-MessageTraceV2 -SenderAddress $VictimEmail -StartDate $QuickStart -EndDate $EndDate -ResultSize 5000
            } else {
                Get-MessageTrace -SenderAddress $VictimEmail -StartDate $QuickStart -EndDate $EndDate -PageSize 5000
            }
            if ($Sent) {
                Export-DataWithLogging -Data $Sent -FilePath $FileAction.Path -Description "Sent Messages (10 days)"
            }
            else {
                Write-Log "No sent messages found in last 10 days." -Severity INFO
            }
        }
        catch {
            Write-Log "Quick trace (sent) failed: $($_.Exception.Message)" -Severity ERROR
        }
    }

    # Received messages
    $FileAction = Get-OutputFileAction -BasePath "$RawDataPath\QuickTrace-Received_${UserAlias}.csv" -Description "Quick Trace - Received"
    if ($FileAction.Action -eq "Collect") {
        try {
            $Received = if ($UseV2) {
                Get-MessageTraceV2 -RecipientAddress $VictimEmail -StartDate $QuickStart -EndDate $EndDate -ResultSize 5000
            } else {
                Get-MessageTrace -RecipientAddress $VictimEmail -StartDate $QuickStart -EndDate $EndDate -PageSize 5000
            }
            if ($Received) {
                Export-DataWithLogging -Data $Received -FilePath $FileAction.Path -Description "Received Messages (10 days)"
            }
            else {
                Write-Log "No received messages found in last 10 days." -Severity INFO
            }
        }
        catch {
            Write-Log "Quick trace (received) failed: $($_.Exception.Message)" -Severity ERROR
        }
    }

    $WarningPreference = "Continue"

    # ---- Historical Message Traces (30 days, async) ----
    if (-not $SkipHistoricalTraces) {
        Write-Log "--- Initiating Historical Message Traces (last $DaysToSearch days) ---" -Severity INFO
        Write-Log "Historical searches complete in 15-30 minutes. Run Invoke-BECMessageTraceRetrieval.ps1 to download when done." -Severity INFO
        try {
            # Get the UPN of the currently authenticated technician to receive trace completion notifications.
            # Filter to the active connection and take the most recently established one.
            $ConnectionInfo = Get-ConnectionInformation |
                              Where-Object { $_.State -eq 'Connected' } |
                              Sort-Object -Property ConnectedAt -Descending |
                              Select-Object -First 1
            $NotifyAddress  = $ConnectionInfo.UserPrincipalName

            if (-not $NotifyAddress) {
                Write-Log "Could not determine technician UPN from connection info. Trace notifications will not be sent." -Severity WARN
                Write-Log "  Tip: Check Get-ConnectionInformation to see active sessions." -Severity DEBUG
            }
            else {
                Write-Log "Trace completion notifications will be sent to: $NotifyAddress" -Severity DEBUG
            }
            $SentTraceName   = "BEC-Sent-${UserAlias}-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            $SentSearchParams = @{
                ReportType   = "MessageTrace"
                StartDate    = $StartDate
                EndDate      = $EndDate
                ReportTitle  = $SentTraceName
                SenderAddress = $VictimEmail
            }
            if ($NotifyAddress) { $SentSearchParams['NotifyAddress'] = $NotifyAddress }
            $SentTrace = Start-HistoricalSearch @SentSearchParams

            $ReceivedTraceName = "BEC-Received-${UserAlias}-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            $ReceivedSearchParams = @{
                ReportType        = "MessageTrace"
                StartDate         = $StartDate
                EndDate           = $EndDate
                ReportTitle       = $ReceivedTraceName
                RecipientAddress  = $VictimEmail
            }
            if ($NotifyAddress) { $ReceivedSearchParams['NotifyAddress'] = $NotifyAddress }
            $ReceivedTrace = Start-HistoricalSearch @ReceivedSearchParams

            if ($SentTrace -and $ReceivedTrace) {
                Write-Log "Historical message traces submitted successfully." -Severity SUCCESS
                Write-Log "  Sent job     : $SentTraceName (ID: $($SentTrace.JobId))" -Severity DEBUG
                Write-Log "  Received job : $ReceivedTraceName (ID: $($ReceivedTrace.JobId))" -Severity DEBUG

                # Update XML with trace job IDs
                [xml]$ConfigUpdate = Get-Content -Path $ConfigPath -Encoding UTF8
                $ConfigUpdate.BECInvestigation.MessageTraces.SentTraceJobId     = $SentTrace.JobId.ToString()
                $ConfigUpdate.BECInvestigation.MessageTraces.SentTraceName      = $SentTraceName
                $ConfigUpdate.BECInvestigation.MessageTraces.ReceivedTraceJobId = $ReceivedTrace.JobId.ToString()
                $ConfigUpdate.BECInvestigation.MessageTraces.ReceivedTraceName  = $ReceivedTraceName
                $ConfigUpdate.BECInvestigation.MessageTraces.TracesInitiated    = "true"
                $ConfigUpdate.Save($ConfigPath)
            }
        }
        catch {
            Write-Log "Historical message trace submission failed: $($_.Exception.Message)" -Severity ERROR
        }
    }
    else {
        Write-Log "Historical message trace submission skipped (-SkipHistoricalTraces)." -Severity INFO
    }

    # ---- Mark collection complete in XML ----
    [xml]$ConfigFinal = Get-Content -Path $ConfigPath -Encoding UTF8
    $ConfigFinal.BECInvestigation.DataCollection.Completed     = "true"
    $ConfigFinal.BECInvestigation.DataCollection.CompletedDate = (Get-Date -Format "o")
    $ConfigFinal.Save($ConfigPath)

    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

    Write-Log "Data collection completed." -Severity SUCCESS
    Write-Log "Next steps:" -Severity INFO
    Write-Log "  1. Run .\Invoke-BECLogAnalysis.ps1 -SkipMessageTraces for immediate findings" -Severity INFO
    Write-Log "  2. Wait 30 minutes, then run .\Invoke-BECMessageTraceRetrieval.ps1" -Severity INFO
    Write-Log "  3. Re-run .\Invoke-BECLogAnalysis.ps1 for complete analysis" -Severity INFO

    Stop-Transcript
    exit 0

} # End function Invoke-BECDataCollection

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    SkipHistoricalTraces = $SkipHistoricalTraces
}

Invoke-BECDataCollection @ScriptParams
'@

        # ---- Invoke-BECLogAnalysis.ps1 ----
        Write-Log "  Generating Invoke-BECLogAnalysis.ps1..." -Severity DEBUG
        $AnalysisScript = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Analyzes collected BEC investigation data and produces a severity-ranked findings report.

.DESCRIPTION
    Invoke-BECLogAnalysis reads all CSV files from the investigation RawData folder and
    analyzes them for indicators of compromise. All configuration is read from
    Investigation.xml in the parent folder.

    Analysis performed:
      - Inbox rules: forwarding (CRITICAL), deletion (HIGH), move-to-folder (MEDIUM),
        mark-as-read (LOW)
      - Mail forwarding: SMTP forwarding enabled (CRITICAL)
      - Mailbox permissions: delegated access (MEDIUM)
      - Message traces: daily volume spikes >50 (HIGH), external send ratio >70% (MEDIUM)

    Output:
      - ANALYSIS-REPORT.txt    - Human-readable ranked findings with recommendations
      - All-Findings.csv       - Machine-readable findings (if any exist)

    Run with -SkipMessageTraces immediately after data collection for fast triage.
    Re-run without the switch after Invoke-BECMessageTraceRetrieval.ps1 for full analysis.

    Supports versioned CSV files (_v2, _v3...) created by re-runs of data collection.

.PARAMETER SkipMessageTraces
    Optional switch. If specified, message trace CSV analysis is skipped.
    Use for immediate triage while historical traces are still processing.

.EXAMPLE
    .\Invoke-BECLogAnalysis.ps1 -SkipMessageTraces
    Immediate triage - analyzes rules, forwarding, permissions only.

.EXAMPLE
    .\Invoke-BECLogAnalysis.ps1
    Full analysis - includes 30-day message trace data.

.NOTES
    File Name      : Invoke-BECLogAnalysis.ps1
    Version        : {SCRIPT_VERSION}
    Author         : Sam Kirsch
    Contributors   :
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
        1  - Fatal failure (XML not found)

.CHANGELOG
    v{SCRIPT_VERSION} - {CREATED_DATE} - Sam Kirsch
        - Generated by Start-BECInvestigation.ps1 v{SCRIPT_VERSION}
        - Renamed from BEC-LogAnalysis.ps1 to Invoke-BECLogAnalysis.ps1
        - Added full compliant header block
        - Added Write-Log function
        - Wrapped logic in master function Invoke-BECLogAnalysis
        - Entry point uses splatted call
        - Preserved all v2.3 detection logic (MoveToFolder, DeleteMessage, MarkAsRead)
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch]$SkipMessageTraces
)

function Invoke-BECLogAnalysis {
    [CmdletBinding()]
    param (
        [switch]$SkipMessageTraces
    )

    # ==========================================================================
    # CONFIGURATION FROM XML
    # ==========================================================================
    $ScriptName    = "Invoke-BECLogAnalysis"
    $ScriptVersion = "{SCRIPT_VERSION}"

    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\Investigation.xml"
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Host "[ERROR] Investigation.xml not found. Ensure you are running from the Scripts folder." -ForegroundColor Red
        exit 1
    }

    [xml]$Config    = Get-Content -Path $ConfigPath -Encoding UTF8
    $VictimEmail    = $Config.BECInvestigation.Victim.Email
    $UserAlias      = $Config.BECInvestigation.Victim.UserAlias
    $RawDataPath    = $Config.BECInvestigation.Paths.RawDataPath
    $AnalysisPath   = $Config.BECInvestigation.Paths.AnalysisPath
    $ReportsPath    = $Config.BECInvestigation.Paths.ReportsPath
    $LogsPath       = $Config.BECInvestigation.Paths.LogsPath

    # Validate critical values loaded from XML before proceeding.
    $XmlValidationErrors = @()
    if (-not $VictimEmail)  { $XmlValidationErrors += "Victim.Email" }
    if (-not $RawDataPath)  { $XmlValidationErrors += "Paths.RawDataPath" }
    if (-not $AnalysisPath) { $XmlValidationErrors += "Paths.AnalysisPath" }
    if (-not $LogsPath)     { $XmlValidationErrors += "Paths.LogsPath" }
    if ($XmlValidationErrors.Count -gt 0) {
        Write-Host "[ERROR] Investigation.xml is missing required fields: $($XmlValidationErrors -join ', ')" -ForegroundColor Red
        Write-Host "[ERROR] The XML may be corrupted. Re-run Start-BECInvestigation.ps1 to regenerate the workspace." -ForegroundColor Red
        exit 1
    }

    # ==========================================================================
    # LOGGING (transcript + structured Write-Log)
    # ==========================================================================
    $TranscriptTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $TranscriptPath      = Join-Path -Path $LogsPath -ChildPath "Analysis_${TranscriptTimestamp}.log"
    Start-Transcript -Path $TranscriptPath

    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]  [string]$Message,
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
            [string]$Severity = "INFO"
        )
        $Ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Entry = "[$Ts] [$Severity] $Message"
        switch ($Severity) {
            "WARN"  { Write-Warning $Entry }
            "ERROR" { Write-Error   $Entry -ErrorAction Continue }
            default { Write-Output  $Entry }
        }
    }

    # ==========================================================================
    # HELPERS
    # ==========================================================================

    # Builds a finding PSCustomObject and logs it to the console
    function New-Finding {
        param (
            [string]$Severity,
            [string]$Category,
            [string]$Finding,
            [string]$Evidence      = "",
            [string]$Recommendation = ""
        )
        Write-Log "[$Severity] $Category - $Finding" -Severity $(if ($Severity -match "CRITICAL|HIGH") { "WARN" } else { "INFO" })
        if ($Evidence)       { Write-Log "  Evidence       : $Evidence"       -Severity DEBUG }
        if ($Recommendation) { Write-Log "  Recommendation : $Recommendation" -Severity DEBUG }

        return [PSCustomObject]@{
            Timestamp      = Get-Date
            Severity       = $Severity
            Category       = $Category
            Finding        = $Finding
            Evidence       = $Evidence
            Recommendation = $Recommendation
        }
    }

    # Returns all CSV files matching a pattern (base + _v2, _v3... versions)
    function Get-AllVersionedFiles {
        param ([string]$Pattern)
        $Files       = @(Get-ChildItem -Path $RawDataPath -Filter $Pattern -ErrorAction SilentlyContinue)
        $BaseFile    = $Files | Where-Object { $_.Name -notmatch "_v\d+\.csv$" }
        $VersionFiles = $Files | Where-Object { $_.Name -match "_v\d+\.csv$" } | Sort-Object -Property Name
        $AllFiles    = @()
        if ($BaseFile)    { $AllFiles += $BaseFile }
        $AllFiles += $VersionFiles
        return $AllFiles
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = "Continue"
    $AllFindings = @()

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Investigation : $($Config.BECInvestigation.Investigation.InvestigationID)" -Severity INFO
    Write-Log "Victim        : $VictimEmail" -Severity INFO
    Write-Log "Mode          : $(if ($SkipMessageTraces) { 'Immediate triage (no message traces)' } else { 'Full analysis (includes message traces)' })" -Severity INFO

    # ---- Inbox Rules ----
    Write-Log "--- Analyzing Inbox Rules ---" -Severity INFO
    $RuleFiles = Get-AllVersionedFiles -Pattern "InboxRules_*.csv"
    if ($RuleFiles.Count -eq 0) {
        Write-Log "No inbox rules files found in RawData." -Severity WARN
    }
    else {
        foreach ($File in $RuleFiles) {
            Write-Log "  Reading: $($File.Name)" -Severity DEBUG
            $Rules = Import-Csv -Path $File.FullName

            if ($Rules) {
                # Forwarding / redirect (CRITICAL)
                $Forwarders = $Rules | Where-Object {
                    ($_.ForwardTo -and $_.ForwardTo -ne "") -or
                    ($_.RedirectTo -and $_.RedirectTo -ne "")
                }
                if ($Forwarders) {
                    $AllFindings += New-Finding -Severity "CRITICAL" -Category "Inbox Rules - Forwarding" `
                        -Finding "Email forwarding rules detected" `
                        -Evidence "$($Forwarders.Count) rule(s) forwarding to external addresses in $($File.Name)" `
                        -Recommendation "IMMEDIATE: Disable these forwarding rules and verify destination addresses"
                }

                # Deletion rules (HIGH)
                $Deleters = $Rules | Where-Object { $_.DeleteMessage -eq "True" }
                if ($Deleters) {
                    $AllFindings += New-Finding -Severity "HIGH" -Category "Inbox Rules - Deletion" `
                        -Finding "Email deletion rules detected" `
                        -Evidence "$($Deleters.Count) rule(s) automatically deleting messages in $($File.Name)" `
                        -Recommendation "Review these rules - attackers use deletion rules to hide breach evidence"
                }

                # Move-to-folder rules (MEDIUM)
                $Movers = $Rules | Where-Object {
                    $_.MoveToFolder -and $_.MoveToFolder -ne "" -and
                    $_.MoveToFolder -notmatch "^(Inbox|Junk Email|Archive)$"
                }
                if ($Movers) {
                    $Folders = ($Movers | Select-Object -ExpandProperty MoveToFolder -Unique) -join ", "
                    $AllFindings += New-Finding -Severity "MEDIUM" -Category "Inbox Rules - Move to Folder" `
                        -Finding "Rules moving emails to non-standard folders" `
                        -Evidence "$($Movers.Count) rule(s) moving to: $Folders in $($File.Name)" `
                        -Recommendation "Review these rules - may be legitimate filtering or malicious email hiding"
                }

                # Mark-as-read rules (LOW)
                $Readers = $Rules | Where-Object { $_.MarkAsRead -eq "True" }
                if ($Readers) {
                    $AllFindings += New-Finding -Severity "LOW" -Category "Inbox Rules - Mark As Read" `
                        -Finding "Rules automatically marking emails as read" `
                        -Evidence "$($Readers.Count) rule(s) in $($File.Name)" `
                        -Recommendation "Often combined with move/delete rules to hide attacker activity"
                }
            }
        }
    }

    # ---- Mail Forwarding ----
    Write-Log "--- Analyzing Mail Forwarding ---" -Severity INFO
    $FwdFiles = Get-AllVersionedFiles -Pattern "MailForwarding_*.csv"
    if ($FwdFiles.Count -eq 0) {
        Write-Log "No mail forwarding files found in RawData." -Severity WARN
    }
    else {
        foreach ($File in $FwdFiles) {
            Write-Log "  Reading: $($File.Name)" -Severity DEBUG
            $Fwd = Import-Csv -Path $File.FullName
            if ($Fwd.ForwardingEnabled -eq "True") {
                $AllFindings += New-Finding -Severity "CRITICAL" -Category "Mail Forwarding" `
                    -Finding "SMTP mail forwarding enabled to external address" `
                    -Evidence "Forwarding to: $($Fwd.ForwardingSmtpAddress) in $($File.Name)" `
                    -Recommendation "IMMEDIATE: Disable mail forwarding - this is a primary BEC indicator"
            }
        }
    }

    # ---- Mailbox Permissions ----
    Write-Log "--- Analyzing Mailbox Permissions ---" -Severity INFO
    $PermFiles = Get-AllVersionedFiles -Pattern "MailboxPermissions_*.csv"
    if ($PermFiles.Count -eq 0) {
        Write-Log "No mailbox permissions files found (none delegated, or collection skipped)." -Severity INFO
    }
    else {
        foreach ($File in $PermFiles) {
            Write-Log "  Reading: $($File.Name)" -Severity DEBUG
            $Perms = Import-Csv -Path $File.FullName
            if ($Perms) {
                $AllFindings += New-Finding -Severity "MEDIUM" -Category "Mailbox Permissions" `
                    -Finding "Delegated mailbox permissions detected" `
                    -Evidence "$($Perms.Count) permission(s) in $($File.Name). Users: $(($Perms.User | Select-Object -First 3) -join ', ')" `
                    -Recommendation "Verify these are legitimate business needs. Check if added during breach window."
            }
        }
    }

    # ---- Message Traces ----
    if (-not $SkipMessageTraces) {
        Write-Log "--- Analyzing Message Traces ---" -Severity INFO
        $SentFiles = Get-AllVersionedFiles -Pattern "QuickTrace-Sent_*.csv"
        if ($SentFiles.Count -eq 0) {
            Write-Log "No sent message trace files found in RawData." -Severity WARN
        }
        else {
            foreach ($File in $SentFiles) {
                Write-Log "  Reading: $($File.Name)" -Severity DEBUG
                $Sent = Import-Csv -Path $File.FullName
                if ($Sent) {
                    # Daily volume spike detection
                    $DailyCounts = $Sent | Group-Object -Property { ([DateTime]$_.Received).Date }
                    $Peak = $DailyCounts | Sort-Object -Property Count -Descending | Select-Object -First 1
                    if ($Peak.Count -gt 50) {
                        $AllFindings += New-Finding -Severity "HIGH" -Category "Email Volume Spike" `
                            -Finding "Unusually high outbound email volume on a single day" `
                            -Evidence "$($Peak.Count) emails sent on $($Peak.Name) in $($File.Name)" `
                            -Recommendation "Review recipients - may indicate phishing campaign from compromised account"
                    }

                    # External recipient concentration
                    $TotalSent     = $Sent.Count
                    $ExternalEmails = $Sent | Where-Object {
                        $_.RecipientAddress -notmatch "@$($VictimEmail.Split('@')[1])$"
                    }
                    if ($ExternalEmails -and ($TotalSent -gt 0) -and (($ExternalEmails.Count / $TotalSent) -gt 0.7)) {
                        $AllFindings += New-Finding -Severity "MEDIUM" -Category "External Email Ratio" `
                            -Finding "High proportion of outbound email sent to external domains" `
                            -Evidence "$($ExternalEmails.Count) of $TotalSent emails ($([math]::Round(($ExternalEmails.Count / $TotalSent) * 100))%) sent externally in $($File.Name)" `
                            -Recommendation "Review external recipients for signs of phishing or data exfiltration"
                    }
                }
            }
        }
    }
    else {
        Write-Log "Message trace analysis skipped (-SkipMessageTraces)." -Severity INFO
    }

    # ---- Generate report ----
    Write-Log "--- Generating Analysis Report ---" -Severity INFO
    $ReportPath = Join-Path -Path $AnalysisPath -ChildPath "ANALYSIS-REPORT.txt"

    $SeverityOrder = @{ 'CRITICAL' = 1; 'HIGH' = 2; 'MEDIUM' = 3; 'LOW' = 4 }
    $SortedFindings = $AllFindings | Sort-Object -Property { $SeverityOrder[$_.Severity] }

    $FindingsDetail = if ($SortedFindings) {
        ($SortedFindings | ForEach-Object {
            "`n[$($_.Severity)] $($_.Category)`n  Finding        : $($_.Finding)`n  Evidence       : $($_.Evidence)`n  Recommendation : $($_.Recommendation)`n"
        }) -join ""
    } else { "" }

    $NoFindingsNote = if ($AllFindings.Count -eq 0) {
@"

NO SUSPICIOUS ACTIVITY DETECTED
================================
All analyzed data appears normal. This may mean:
  - The account was not compromised (false alarm / precautionary check)
  - The compromise was minimal and left no obvious traces
  - Additional data sources are needed (Azure AD sign-in logs, etc.)
  - Data collection failed or was incomplete - check Logs folder
"@
    } else { "" }

    $ReportContent = @"
BEC INVESTIGATION ANALYSIS REPORT
==================================
Investigation : $($Config.BECInvestigation.Investigation.InvestigationID)
Victim        : $VictimEmail
Analysis Date : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Analysis Mode : $(if ($SkipMessageTraces) { "Immediate triage (message traces excluded)" } else { "Full analysis (message traces included)" })
Script Version: $ScriptVersion

FINDINGS SUMMARY
================
Total Findings : $($AllFindings.Count)
  CRITICAL     : $(($AllFindings | Where-Object {$_.Severity -eq 'CRITICAL'}).Count)
  HIGH         : $(($AllFindings | Where-Object {$_.Severity -eq 'HIGH'}).Count)
  MEDIUM       : $(($AllFindings | Where-Object {$_.Severity -eq 'MEDIUM'}).Count)
  LOW          : $(($AllFindings | Where-Object {$_.Severity -eq 'LOW'}).Count)

DETAILED FINDINGS (sorted by severity)
=======================================
$FindingsDetail$NoFindingsNote
"@

    $ReportContent | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-Log "Analysis report written: $ReportPath" -Severity SUCCESS

    if ($AllFindings.Count -gt 0) {
        $AllFindings | Export-Csv -Path (Join-Path -Path $AnalysisPath -ChildPath "All-Findings.csv") -NoTypeInformation -Encoding UTF8
        Write-Log "Findings CSV written: All-Findings.csv" -Severity SUCCESS
    }

    # ---- Update Investigation.xml ----
    $AnalysisKey = if ($SkipMessageTraces) { "Immediate" } else { "Complete" }
    $Config.BECInvestigation.Analysis."${AnalysisKey}AnalysisCompleted" = "true"
    $Config.BECInvestigation.Analysis."${AnalysisKey}AnalysisDate"      = (Get-Date -Format "o")
    $Config.BECInvestigation.Analysis.CriticalFindingsCount             = [string](($AllFindings | Where-Object {$_.Severity -eq 'CRITICAL'}).Count)
    $Config.BECInvestigation.Analysis.HighFindingsCount                 = [string](($AllFindings | Where-Object {$_.Severity -eq 'HIGH'}).Count)
    $Config.Save($ConfigPath)

    Write-Log "Investigation.xml updated with analysis results." -Severity SUCCESS
    Write-Log "CRITICAL findings: $(($AllFindings | Where-Object {$_.Severity -eq 'CRITICAL'}).Count)" -Severity $(if (($AllFindings | Where-Object {$_.Severity -eq 'CRITICAL'}).Count -gt 0) {"WARN"} else {"INFO"})
    Write-Log "HIGH findings    : $(($AllFindings | Where-Object {$_.Severity -eq 'HIGH'}).Count)" -Severity INFO
    Write-Log "Analysis complete. Review: $ReportPath" -Severity SUCCESS

    Stop-Transcript
    Start-Process -FilePath "explorer.exe" -ArgumentList $AnalysisPath
    exit 0

} # End function Invoke-BECLogAnalysis

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    SkipMessageTraces = $SkipMessageTraces
}

Invoke-BECLogAnalysis @ScriptParams
'@

        # ---- Invoke-BECMessageTraceRetrieval.ps1 ----
        Write-Log "  Generating Invoke-BECMessageTraceRetrieval.ps1..." -Severity DEBUG
        $RetrievalScript = @'
#Requires -Version 5.1
<#
.SYNOPSIS
    Checks and downloads completed 30-day historical message trace jobs for a BEC investigation.

.DESCRIPTION
    Invoke-BECMessageTraceRetrieval reads the historical message trace job IDs stored in
    Investigation.xml, queries their status in Exchange Online, and downloads any completed
    traces to the investigation RawData folder.

    Historical trace jobs submitted by Invoke-BECDataCollection typically complete in
    15-30 minutes. This script is safe to run multiple times - it will download only
    completed jobs and report the status of any still-pending jobs.

    Once both traces are downloaded, Investigation.xml is updated with TracesCompleted=true
    and the technician should re-run Invoke-BECLogAnalysis.ps1 for full analysis.

.EXAMPLE
    .\Invoke-BECMessageTraceRetrieval.ps1
    Checks trace status and downloads any completed jobs.

.NOTES
    File Name      : Invoke-BECMessageTraceRetrieval.ps1
    Version        : {SCRIPT_VERSION}
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : {CREATED_DATE}
    Last Modified  : {CREATED_DATE}
    Modified By    : Sam Kirsch

    Investigation  : {INVESTIGATION_ID}
    Victim         : {VICTIM_EMAIL}

    Requires       : PowerShell 5.1+, ExchangeOnlineManagement module
    Run Context    : Interactive - Technician workstation (Exchange Administrator or Global Admin)
    DattoRMM       : Not applicable
    Client Scope   : Per-investigation (generated script)

    Exit Codes:
        0  - Completed (all ready traces downloaded, or traces still pending)
        1  - Fatal failure (Exchange connection failed, XML not found)

.CHANGELOG
    v{SCRIPT_VERSION} - {CREATED_DATE} - Sam Kirsch
        - Generated by Start-BECInvestigation.ps1 v{SCRIPT_VERSION}
        - Renamed from BEC-MessageTrace-Retrieval.ps1 to Invoke-BECMessageTraceRetrieval.ps1
        - Added full compliant header block
        - Added Write-Log function
        - Wrapped logic in master function Invoke-BECMessageTraceRetrieval
        - Entry point uses splatted call
        - Preserved all v2.3 retrieval logic
#>

[CmdletBinding()]
param ()

function Invoke-BECMessageTraceRetrieval {
    [CmdletBinding()]
    param ()

    # ==========================================================================
    # CONFIGURATION FROM XML
    # ==========================================================================
    $ScriptName    = "Invoke-BECMessageTraceRetrieval"
    $ScriptVersion = "{SCRIPT_VERSION}"

    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "..\Investigation.xml"
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Host "[ERROR] Investigation.xml not found. Ensure you are running from the Scripts folder." -ForegroundColor Red
        exit 1
    }

    [xml]$Config    = Get-Content -Path $ConfigPath -Encoding UTF8
    $SentJobId      = $Config.BECInvestigation.MessageTraces.SentTraceJobId
    $ReceivedJobId  = $Config.BECInvestigation.MessageTraces.ReceivedTraceJobId
    $RawDataPath    = $Config.BECInvestigation.Paths.RawDataPath
    $LogsPath       = $Config.BECInvestigation.Paths.LogsPath
    $UserAlias      = $Config.BECInvestigation.Victim.UserAlias

    # Validate critical values loaded from XML before proceeding.
    $XmlValidationErrors = @()
    if (-not $RawDataPath) { $XmlValidationErrors += "Paths.RawDataPath" }
    if (-not $LogsPath)    { $XmlValidationErrors += "Paths.LogsPath" }
    if (-not $UserAlias)   { $XmlValidationErrors += "Victim.UserAlias" }
    if ($XmlValidationErrors.Count -gt 0) {
        Write-Host "[ERROR] Investigation.xml is missing required fields: $($XmlValidationErrors -join ', ')" -ForegroundColor Red
        Write-Host "[ERROR] The XML may be corrupted. Re-run Start-BECInvestigation.ps1 to regenerate the workspace." -ForegroundColor Red
        exit 1
    }

    # ==========================================================================
    # LOGGING (transcript + structured Write-Log)
    # ==========================================================================
    $TranscriptTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $TranscriptPath      = Join-Path -Path $LogsPath -ChildPath "TraceRetrieval_${TranscriptTimestamp}.log"
    Start-Transcript -Path $TranscriptPath

    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]  [string]$Message,
            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG")]
            [string]$Severity = "INFO"
        )
        $Ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $Entry = "[$Ts] [$Severity] $Message"
        switch ($Severity) {
            "WARN"  { Write-Warning $Entry }
            "ERROR" { Write-Error   $Entry -ErrorAction Continue }
            default { Write-Output  $Entry }
        }
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = "Continue"

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Investigation : $($Config.BECInvestigation.Investigation.InvestigationID)" -Severity INFO
    Write-Log "Sent Job ID   : $SentJobId" -Severity INFO
    Write-Log "Received Job ID : $ReceivedJobId" -Severity INFO

    if (-not $SentJobId -and -not $ReceivedJobId) {
        Write-Log "No trace job IDs found in Investigation.xml. Run Invoke-BECDataCollection.ps1 first." -Severity WARN
        Stop-Transcript
        exit 0
    }

    Import-Module -Name ExchangeOnlineManagement -ErrorAction Stop

    Write-Log "Connecting to Exchange Online..." -Severity INFO
    try {
        Connect-ExchangeOnline -ShowBanner:$false -UseRPSSession:$false -ErrorAction Stop
        Write-Log "Connected to Exchange Online." -Severity SUCCESS
    }
    catch {
        Write-Log "Failed to connect to Exchange Online: $($_.Exception.Message)" -Severity ERROR
        Stop-Transcript
        exit 1
    }

    $JobIds      = @($SentJobId, $ReceivedJobId) | Where-Object { $_ -ne "" }
    $AllJobs     = Get-HistoricalSearch | Where-Object { $_.JobId -in $JobIds }
    $DownloadCount = 0

    foreach ($Job in $AllJobs) {
        $Type    = if ($Job.ReportTitle -match "Sent") { "Sent" } else { "Received" }
        $OutFile = Join-Path -Path $RawDataPath -ChildPath "MessageTrace-${Type}_${UserAlias}.csv"

        Write-Log "Job: $($Job.ReportTitle) - Status: $($Job.Status)" -Severity INFO

        if ($Job.Status -eq "Done") {
            $Report = Get-HistoricalSearch -JobId $Job.JobId
            if ($Report.ReportUrl) {
                try {
                    Invoke-WebRequest -Uri $Report.ReportUrl -OutFile $OutFile -ErrorAction Stop
                    Write-Log "$Type trace downloaded: $(Split-Path -Path $OutFile -Leaf)" -Severity SUCCESS
                    $DownloadCount++
                }
                catch {
                    Write-Log "Download failed for $Type trace: $($_.Exception.Message)" -Severity ERROR
                }
            }
            else {
                Write-Log "$Type trace completed but report URL not yet available. Wait a few minutes and retry." -Severity WARN
            }
        }
        else {
            Write-Log "$Type trace not yet ready (Status: $($Job.Status)). Wait and re-run this script." -Severity INFO
        }
    }

    # Update XML if both traces are now downloaded
    if ($DownloadCount -ge $JobIds.Count) {
        $Config.BECInvestigation.MessageTraces.TracesCompleted = "true"
        $Config.Save($ConfigPath)
        Write-Log "All traces downloaded. Investigation.xml updated (TracesCompleted=true)." -Severity SUCCESS
        Write-Log "Next step: Run .\Invoke-BECLogAnalysis.ps1 for complete analysis." -Severity INFO
    }
    elseif ($DownloadCount -gt 0) {
        Write-Log "$DownloadCount of $($JobIds.Count) traces downloaded. Re-run this script when remaining traces complete." -Severity WARN
    }
    else {
        Write-Log "No traces downloaded this run. Check status above and re-run when ready." -Severity INFO
    }

    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    Stop-Transcript
    exit 0

} # End function Invoke-BECMessageTraceRetrieval

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{}

Invoke-BECMessageTraceRetrieval @ScriptParams
'@

        # ---- Perform token substitution and write all three scripts ----
        $CreatedDate = Get-Date -Format "yyyy-MM-dd"

        $Substitutions = @{
            '{INVESTIGATION_ID}' = $InvestigationName
            '{VICTIM_EMAIL}'     = $VictimEmail
            '{CREATED_DATE}'     = $CreatedDate
            '{SCRIPT_VERSION}'   = $ScriptVersion
        }

        $ScriptDefinitions = @(
            @{ Content = $DataCollectionScript;  FileName = "Invoke-BECDataCollection.ps1" }
            @{ Content = $AnalysisScript;         FileName = "Invoke-BECLogAnalysis.ps1" }
            @{ Content = $RetrievalScript;        FileName = "Invoke-BECMessageTraceRetrieval.ps1" }
        )

        foreach ($ScriptDef in $ScriptDefinitions) {
            $Content = $ScriptDef.Content
            foreach ($Token in $Substitutions.Keys) {
                $Content = $Content -replace [regex]::Escape($Token), $Substitutions[$Token]
            }
            $OutPath = Join-Path -Path $ScriptsPath -ChildPath $ScriptDef.FileName
            $Content | Out-File -FilePath $OutPath -Encoding UTF8
            Write-Log "  Generated: $($ScriptDef.FileName)" -Severity SUCCESS
        }

        Write-Log "All investigation scripts generated." -Severity SUCCESS

        # ------------------------------------------------------------------
        # STEP 4: Create Investigation-README.txt
        # ------------------------------------------------------------------
        Write-Log "Creating Investigation-README.txt..." -Severity INFO

        $ReadmeContent = @"
============================================================================
BEC INVESTIGATION WORKSPACE
Start-BECInvestigation.ps1 v$ScriptVersion
============================================================================

Investigation ID : $InvestigationName
Victim           : $VictimEmail
Technician       : $Technician
$(if ($IncidentTicket) {"Ticket           : $IncidentTicket"})
Created          : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

============================================================================
WORKFLOW - RUN SCRIPTS IN THIS ORDER
============================================================================

STEP 1 - COLLECT DATA (2-5 min)
  cd Scripts
  .\Invoke-BECDataCollection.ps1

  Connects to Exchange Online and collects:
    - Inbox rules                 -> RawData\InboxRules_$UserAlias.csv
    - Mail forwarding settings    -> RawData\MailForwarding_$UserAlias.csv
    - Mailbox permissions         -> RawData\MailboxPermissions_$UserAlias.csv
    - Registered mobile devices   -> RawData\MobileDevices_$UserAlias.csv
    - Unified audit logs          -> RawData\UnifiedAuditLogs_$UserAlias.csv
    - Quick message traces        -> RawData\QuickTrace-Sent/Received_$UserAlias.csv
    - Initiates 30-day historical traces (async, takes 15-30 min to complete)

STEP 2 - IMMEDIATE ANALYSIS (1-2 min)
  .\Invoke-BECLogAnalysis.ps1 -SkipMessageTraces

  Analyzes all collected data immediately. Produces:
    - Analysis\ANALYSIS-REPORT.txt   <- START HERE
    - Analysis\All-Findings.csv
    - Reports\SUSPICIOUS-Rules_$UserAlias.csv (if applicable)

  Address any CRITICAL or HIGH findings before continuing.

STEP 3 - RETRIEVE TRACES (~30 min wait, then <1 min)
  .\Invoke-BECMessageTraceRetrieval.ps1

  Downloads completed historical traces to RawData folder.
  Safe to re-run if traces are not ready yet.

STEP 4 - COMPLETE ANALYSIS (2-3 min)
  .\Invoke-BECLogAnalysis.ps1

  Re-runs analysis with full 30-day trace data.
  Updates ANALYSIS-REPORT.txt with complete findings.

============================================================================
IMMEDIATE ACTIONS (CRITICAL findings)
============================================================================

If CRITICAL findings are identified:
  [ ] Remove malicious inbox rules immediately
  [ ] Disable mail forwarding if enabled
  [ ] Reset user password + force MFA re-registration
  [ ] Revoke all active sessions (Azure AD > Users > Revoke Sessions)
  [ ] Remove unrecognized mobile devices

============================================================================
INVESTIGATION CONFIGURATION
============================================================================

Config File  : Investigation.xml (do not edit manually - scripts update it)
Working Dir  : $InvestigationPath

Check status at any time:
  PS> [xml]`$c = Get-Content ..\Investigation.xml
  PS> `$c.BECInvestigation.DataCollection.Completed
  PS> `$c.BECInvestigation.MessageTraces.TracesCompleted
  PS> `$c.BECInvestigation.Analysis.CriticalFindingsCount

============================================================================
For assistance: Contact Databranch MSP Team Lead
============================================================================
"@

        $ReadmePath = Join-Path -Path $InvestigationPath -ChildPath "Investigation-README.txt"
        $ReadmeContent | Out-File -FilePath $ReadmePath -Encoding UTF8
        Write-Log "Investigation-README.txt created." -Severity SUCCESS

        # ------------------------------------------------------------------
        # COMPLETE
        # ------------------------------------------------------------------
        Write-Log "===== Workspace initialization complete =====" -Severity SUCCESS
        Write-Log "Investigation workspace: $InvestigationPath" -Severity INFO
        Write-Log "Next step: cd `"$ScriptsPath`" and run .\Invoke-BECDataCollection.ps1" -Severity INFO

        Start-Process -FilePath "explorer.exe" -ArgumentList $InvestigationPath

        exit 0

    } # End try
    catch {
        Write-Log "Unhandled exception: $_" -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
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
}

Start-BECInvestigation @ScriptParams
