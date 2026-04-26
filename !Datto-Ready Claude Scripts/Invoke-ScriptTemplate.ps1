#Requires -Version 5.1
<#
.SYNOPSIS
    Brief one-line description of what this script does.

.DESCRIPTION
    Full description of the script's purpose, scope, and behavior.
    Include any important notes about how it works, what it touches,
    and any dependencies or prerequisites.

    FOR WRITE-CAPABLE SCRIPTS: Add a REPORT-ONLY MODE paragraph here.
    Example:
        REPORT-ONLY MODE IS ON BY DEFAULT. The script performs all
        matching and logging but will not write anything unless
        ReportOnly is explicitly set to 'false'. Any other value —
        including the default, a typo, or unexpected casing — stays
        safely in report-only mode.

.PARAMETER ExampleParam
    Description of this parameter. Note if it is required or optional,
    what values are acceptable, and what the default is if any.

.PARAMETER AnotherParam
    Description of this parameter.

.PARAMETER ReportOnly
    FOR WRITE-CAPABLE SCRIPTS — include this parameter.
    Controls whether the script writes to external systems. DEFAULTS TO
    REPORT-ONLY. The script writes only if this parameter is the EXPLICIT
    literal string 'false' (case-insensitive, whitespace trimmed). Any
    other value — including the default, a typo, a blank string, or
    unexpected casing — falls safely into report-only mode. This is an
    intentionally asymmetric guard: report-only is the safe state, writes
    must be opted into explicitly and unambiguously.

.PARAMETER VerboseOutput
    FOR WRITE-CAPABLE SCRIPTS — include this parameter.
    Set to 'false' to suppress per-item detail lines. Section headers,
    summary totals, unmatched lists, and all WARN/ERROR entries always
    emit regardless of this setting. Defaults to 'true'. Named
    VerboseOutput rather than Verbose to avoid collision with
    PowerShell's built-in -Verbose common parameter.

.EXAMPLE
    .\Invoke-ScriptTemplate.ps1 -ExampleParam "Value" -AnotherParam "Value"
    Description of what this example does.

.EXAMPLE
    .\Invoke-ScriptTemplate.ps1 -ExampleParam "Value"
    Description of what this example does using only required parameters.

.NOTES
    File Name      : Invoke-ScriptTemplate.ps1
    Version        : 1.5.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-04-24
    Last Modified  : 2026-04-24
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM or Domain Admin (note which applies)
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : All clients / Client-specific (note which applies)

    Exit Codes:
        0  - Success
        1  - Runtime failure (script started, errors encountered during execution)
        2  - Fatal pre-flight failure (missing parameters, auth failure, cannot start)
        (Add additional script-specific codes as needed)

    Output Design:
        Write-Log        - Structured [timestamp][SEVERITY] output to log file AND
                           DattoRMM stdout. Always verbose. No color.
        Write-Console    - Human-friendly colored console output for manual/interactive
                           runs. Uses Write-Host (display stream only). Suppressed in
                           DattoRMM agent context automatically.
        Write-VerboseLog - Calls both Write-Log and Write-Console, gated by $IsVerbose.
                           Use for per-item detail lines in write-capable scripts.
                           Structural output (headers, summary, WARN/ERROR) should
                           always call Write-Log/Write-Console directly.

.CHANGELOG
    v1.5.0.0 - 2026-04-24 - Sam Kirsch
        - Hardened [CmdletBinding()] placement: now enforced immediately above
          param() with explicit ordering comments. TLS block correctly positioned
          before [CmdletBinding()] — this ordering had caused a real production
          bug and is now non-negotiable per spec.
        - Updated all boolean string parameter resolutions to use
          .Trim().ToLower() -eq 'true' (was bare -eq 'true'). DattoRMM does not
          guarantee lowercase — 'True', 'TRUE', and ' true ' are all valid.
        - ReportOnly now uses asymmetric guard: -ne 'false' rather than -eq 'true'.
          Any value other than explicit 'false' stays safely in report-only mode.
        - Added Write-VerboseLog helper for gated per-item output in write-capable
          scripts. Structural output always calls Write-Log/Write-Console directly.
        - Added commented-out API scaffolding blocks: Invoke-PaginatedGet,
          Invoke-ThrottledWrite, sliding window rate limiter, and idempotency
          read-before-write pattern. Uncomment and configure for API scripts.
        - Added Write-VerboseLog, ReportOnly, and VerboseOutput to template key
          elements and parameter block examples.
        - Updated boolean example in parameter block comments to show
          .Trim().ToLower() pattern.
        - Added Mode to standard log header for write-capable scripts.

    v1.4.0.0 - 2026-04-16 - Sam Kirsch
        - Added TLS 1.2 enforcement block between help block and parameters.
          PowerShell 5.1 defaults to TLS 1.0/1.1 on older Windows builds;
          IT Glue and Microsoft Graph/Azure AD both require TLS 1.2 minimum.

    v1.3.0.0 - 2026-04-16 - Sam Kirsch
        - Expanded DattoRMM built-in variable comments (full CS_ variable list)
        - Added Boolean input variable gotcha to parameter comments and script
          logic reference block
        - Added Set-UdfValue helper function for writing data back to DattoRMM UDFs
        - Added UDF write pattern and post-condition guidance to script logic comments

    v1.2.0.0 - 2026-04-16 - Sam Kirsch
        - Updated exit codes to standard: 0=success, 1=runtime failure,
          2=fatal pre-flight failure
        - Added pre-flight parameter validation block with exit 2 pattern
        - Added PS 5.1 compatibility notes to template comments
        - Secret/credential nulling pattern added to template comments

    v1.1.0.0 - 2026-02-21 - Sam Kirsch
        - Added Write-Console function for human-friendly colored terminal output
        - Added Write-Banner, Write-Section, Write-Separator console helpers
        - Dual-output pattern established

    v1.0.1.0 - 2026-02-20 - Sam Kirsch
        - Added DEBUG severity level to Write-Log

    v1.0.0.0 - 2026-02-20 - Sam Kirsch
        - Initial release
#>

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# Required for any script making HTTPS REST calls.
# PowerShell 5.1 on older Windows (Server 2012 R2, early Win10) defaults to
# TLS 1.0/1.1. ITGlue, Microsoft Graph, and most modern REST APIs require
# TLS 1.2 minimum and reject older connections with errors that look like
# generic network failures.
#
# POSITION: This block must appear AFTER the help block and BEFORE
# [CmdletBinding()]. The TLS line is an executable statement — it must never
# appear between [CmdletBinding()] and param(). If you move this block during
# editing, the script will silently break. Leave it here.
#
# Remove this block only if the script makes no HTTPS calls whatsoever.
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

# ==============================================================================
# PARAMETERS
# Supports both DattoRMM environment variable input (automated) and standard
# PowerShell parameter input (manual/interactive). DattoRMM env vars take
# precedence if present; otherwise falls back to passed parameters or defaults.
#
# DATTORMM BUILT-IN AGENT VARIABLES
# The following are available in every component automatically.
# CS_PROFILE_NAME and CS_HOSTNAME are always wired up (used in the log header).
# Add the others only if this specific script actually needs them.
#
#   Always include:
#     $env:CS_PROFILE_NAME       - Site/customer name
#     $env:CS_HOSTNAME           - Target machine hostname
#
#   Add only when needed:
#     $env:CS_PROFILE_UID        - Unique ID for the site
#     $env:CS_PROFILE_DESC       - Description of the site
#     $env:CS_ACCOUNT_UID        - Unique ID for the Datto RMM account
#     $env:CS_DOMAIN             - Device domain (if domain-joined)
#     $env:CS_CC_HOST            - Agent control channel URI
#     $env:CS_CSM_ADDRESS        - Web Portal address for this device
#     $env:CS_PROFILE_PROXY_TYPE - 0 or 1 (proxy configured for site)
#     $env:UDF_1 .. $env:UDF_30  - Device UDF values at job run time (read-only)
#
# BOOLEAN INPUT VARIABLES — TWO-LAYER GOTCHA:
#
#   Layer 1 — Never cast or evaluate as [bool]. DattoRMM Boolean component
#   variables arrive as the STRING "true" or "false". Any non-empty string
#   (including "false") evaluates to $true in PowerShell.
#
#   WRONG:  if ($env:EnableFeature) { ... }           # always true when set
#   WRONG:  if ([bool]$env:EnableFeature) { ... }     # always true even for "false"
#
#   Layer 2 — DattoRMM does not guarantee lowercase. It may pass 'True',
#   'TRUE', or ' true '. Always use .Trim().ToLower() before comparing.
#
#   WRONG:  if ($EnableFeature -eq 'true') { ... }    # breaks on 'True' or 'TRUE'
#   CORRECT: if ($EnableFeature.Trim().ToLower() -eq 'true') { ... }
#
#   For standard boolean features, resolve once at the top of the master
#   function:
#       $IsEnabled = ($EnableFeature.Trim().ToLower() -eq 'true')
#
#   For write gates (report-only mode), use the asymmetric form:
#       $IsReportOnly = ($ReportOnly.Trim().ToLower() -ne 'false')
#   This ensures any ambiguous value (blank, typo, unexpected casing) stays
#   safely in report-only mode. Only the explicit literal 'false' enables writes.
#
# NOTE: [CmdletBinding()] MUST appear immediately above param() with nothing
# between them. The TLS enforcement line above is an executable statement and
# belongs BEFORE this block, not between [CmdletBinding()] and param().
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ExampleParam = $(if ($env:ExampleParam) { $env:ExampleParam } else { "DefaultValue" }),

    [Parameter(Mandatory = $false)]
    [string]$AnotherParam = $(if ($env:AnotherParam) { $env:AnotherParam } else { "" }),

    # Standard boolean feature flag — resolved with .Trim().ToLower() inside master function
    # [Parameter(Mandatory = $false)]
    # [string]$EnableFeature = $(if ($env:EnableFeature) { $env:EnableFeature } else { 'false' }),

    # Write-capable script parameters — uncomment for scripts that write to external systems
    # [Parameter(Mandatory = $false)]
    # [string]$ReportOnly = $(if ($env:ReportOnly) { $env:ReportOnly } else { 'true' }),
    #
    # [Parameter(Mandatory = $false)]
    # [string]$VerboseOutput = $(if ($env:VerboseOutput) { $env:VerboseOutput } else { 'true' }),

    # DattoRMM built-in variables (auto-populated by Datto, no need to define in component)
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# MASTER FUNCTION
# Named to match the file. Uses an approved PowerShell verb.
# All executable code lives inside this function. Nothing runs at script scope
# except the entry point splat at the bottom of this file.
# ==============================================================================
function Invoke-ScriptTemplate {
    <#
    .SYNOPSIS
        Internal master function. See script-level help for full documentation.
    #>
    [CmdletBinding()]
    param (
        [string]$ExampleParam,
        [string]$AnotherParam,
        # [string]$EnableFeature,
        # [string]$ReportOnly,
        # [string]$VerboseOutput,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Invoke-ScriptTemplate"
    $ScriptVersion = "1.5.0.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # Boolean resolution — resolve all boolean-style string params once, here.
    # Use .Trim().ToLower() on every comparison — DattoRMM does not guarantee
    # lowercase and may pass 'True', 'TRUE', or ' true '.
    #
    # Standard feature flags:
    #   $IsEnabled    = ($EnableFeature.Trim().ToLower() -eq 'true')
    #
    # Write gate (asymmetric — safe default is report-only):
    #   $IsReportOnly = ($ReportOnly.Trim().ToLower() -ne 'false')
    #   # Only the explicit literal 'false' enables writes. Any other value
    #   # (blank, typo, unexpected casing) stays safely in report-only mode.
    #
    # Verbose gate:
    #   $IsVerbose    = ($VerboseOutput.Trim().ToLower() -ne 'false')

    # ==========================================================================
    # WRITE-LOG  (Structured Output Layer)
    # Writes timestamped, severity-tagged entries to BOTH the log file and
    # DattoRMM stdout. Always verbose — all levels always written.
    #
    # Uses Write-Output / Write-Warning / Write-Error (NOT Write-Host) so
    # output is captured by DattoRMM job stdout, pipeline, and transcripts.
    # Do NOT use Write-Host here — it would bypass DattoRMM capture.
    # ==========================================================================
    function Write-Log {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = "",

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
            Write-Warning "[$Timestamp] [WARN] Could not write to log file: $_"
        }
    }

    # ==========================================================================
    # WRITE-CONSOLE  (Presentation Layer)
    # Human-friendly colored output for interactive/manual terminal runs.
    # Uses Write-Host — writes to the PowerShell display stream ONLY.
    # NOT captured by DattoRMM stdout, pipeline redirection, or transcripts.
    # Safe to call alongside Write-Log — the two output streams are independent.
    #
    # Severity color scheme:
    #   INFO    = Cyan       WARN    = Yellow
    #   SUCCESS = Green      ERROR   = Red
    #   DEBUG   = Magenta    PLAIN   = Gray (no severity prefix)
    #
    # Use -Indent to create visual hierarchy for sub-items under a parent step.
    # Each indent level adds 2 spaces of leading whitespace.
    # ==========================================================================
    function Write-Console {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = "",

            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG", "PLAIN")]
            [string]$Severity = "PLAIN",

            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )

        $Prefix = "  " * $Indent

        $SeverityColors = @{
            INFO    = "Cyan"
            SUCCESS = "Green"
            WARN    = "Yellow"
            ERROR   = "Red"
            DEBUG   = "Magenta"
            PLAIN   = "Gray"
        }
        $Color = $SeverityColors[$Severity]

        if ($Severity -eq "PLAIN") {
            Write-Host "$Prefix$Message" -ForegroundColor $Color
        }
        else {
            Write-Host "$Prefix" -NoNewline
            Write-Host "[$Severity]" -ForegroundColor $Color -NoNewline
            Write-Host " $Message"   -ForegroundColor White
        }
    }

    # ==========================================================================
    # WRITE-VERBOSELOG  (Verbose-Gated Output)
    # Calls both Write-Log and Write-Console only when $IsVerbose is true.
    # Use for per-item detail lines in write-capable scripts (e.g. [WROTE],
    # [SKIPPED-CURRENT], [SKIPPED-REPORT], [SKIPPED-NO-MATCH]).
    #
    # Structural output — section headers, summary totals, unmatched item
    # lists, and all WARN/ERROR lines — must call Write-Log/Write-Console
    # directly so they always emit regardless of verbose setting.
    #
    # This function requires $IsVerbose to be resolved before it is defined.
    # Ensure boolean resolution (see CONFIGURATION block) runs first.
    #
    # FOR WRITE-CAPABLE SCRIPTS ONLY. Remove from scripts that do not use
    # report-only mode or per-item outcome logging.
    # ==========================================================================
    # function Write-VerboseLog {
    #     param (
    #         [Parameter(Mandatory = $false)]
    #         [AllowEmptyString()]
    #         [string]$Message = "",
    #
    #         [Parameter(Mandatory = $false)]
    #         [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
    #         [string]$Severity = "INFO",
    #
    #         [Parameter(Mandatory = $false)]
    #         [int]$Indent = 0
    #     )
    #
    #     if (-not $IsVerbose) { return }
    #     Write-Log     $Message -Severity $Severity
    #     Write-Console $Message -Severity $Severity -Indent $Indent
    # }

    # ==========================================================================
    # CONSOLE PRESENTATION HELPERS
    # Write-Banner, Write-Section, Write-Separator — for structured, readable
    # console output during interactive runs. All use Write-Host (display stream
    # only). Not captured by DattoRMM, pipeline, or transcripts.
    # ==========================================================================

    # Write-Banner — full-width start/end banner.
    # Use at script open/close and for major milestone announcements.
    # Output:
    #   ============================================================
    #     SCRIPT NAME v1.0.0.0
    #   ============================================================
    function Write-Banner {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Title,

            [Parameter(Mandatory = $false)]
            [string]$Color = "Cyan"
        )

        $Line = "=" * 60
        Write-Host ""
        Write-Host $Line       -ForegroundColor $Color
        Write-Host "  $Title"  -ForegroundColor White
        Write-Host $Line       -ForegroundColor $Color
        Write-Host ""
    }

    # Write-Section — lightweight section header within a script run.
    # Use to introduce each logical phase of execution.
    # Output:
    #   ---- Section Title -----------------------------------------
    function Write-Section {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Title,

            [Parameter(Mandatory = $false)]
            [string]$Color = "Cyan"
        )

        $TitleStr = "---- $Title "
        $Padding  = "-" * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ""
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    # Write-Separator — thin divider line between logical groups.
    # Output:
    #   ------------------------------------------------------------
    function Write-Separator {
        param (
            [Parameter(Mandatory = $false)]
            [string]$Color = "DarkGray"
        )

        Write-Host ("-" * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # SET-UDFVALUE  (DattoRMM User-Defined Field Write)
    # Writes a value to a DattoRMM UDF slot via the CentraStage registry path.
    # The Datto agent syncs the value to the platform and deletes the registry
    # entry automatically.
    #
    # Notes:
    #   - Max 255 characters. Do not store secrets in UDFs.
    #   - UDF 1 may be reserved by Ransomware Detection — avoid Slot 1 where
    #     that feature is enabled.
    #   - Logs a warning on failure but does not throw.
    # ==========================================================================
    function Set-UdfValue {
        param (
            [Parameter(Mandatory = $true)]
            [ValidateRange(1, 30)]
            [int]$Slot,

            [Parameter(Mandatory = $true)]
            [ValidateLength(0, 255)]
            [string]$Value
        )

        $RegPath = 'HKLM:\SOFTWARE\CentraStage'
        $RegName = "Custom$Slot"

        try {
            New-ItemProperty -Path $RegPath -Name $RegName -Value $Value -PropertyType String -Force | Out-Null
            Write-Log "UDF $Slot set: $Value" -Severity DEBUG
        }
        catch {
            Write-Log "Failed to write UDF $Slot : $_" -Severity WARN
        }
    }

    # ==========================================================================
    # LOG SETUP
    # Creates log folder if needed and rotates old log files.
    # ==========================================================================
    function Initialize-Logging {
        if (-not (Test-Path $LogFolder)) {
            try {
                New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
            }
            catch {
                Write-Warning "Could not create log folder '$LogFolder': $_"
            }
        }

        try {
            $ExistingLogs = Get-ChildItem -Path $LogFolder -Filter "$($ScriptName)_*.log" |
                            Sort-Object LastWriteTime -Descending

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
    # API HELPERS — SCAFFOLDING (uncomment and configure for API scripts)
    #
    # These patterns are established standards for all scripts that interact
    # with REST APIs. See Databranch_ScriptLibrary_ProjectSpec.md and
    # Databranch_APILessonsLearned.md for full documentation.
    # ==========================================================================

    # --------------------------------------------------------------------------
    # INVOKE-PAGINATEDGET
    # Iterates paginated REST GET endpoints, returning all items as a flat list.
    # Never assume a single response is the complete dataset — always paginate.
    #
    # PaginationStyle options:
    #   'Datto'    - follows $response.pageDetails.nextPageUrl
    #   'ITGlue'   - uses $response.meta.'next-page' page number
    #   'Huntress' - uses $response.pagination.total_pages counter
    #
    # Usage:
    #   $allSites = Invoke-PaginatedGet -Headers $headers `
    #                   -InitialUrl "$baseUrl/api/v2/account/sites" `
    #                   -PaginationStyle 'Datto' -ItemsProperty 'sites'
    # --------------------------------------------------------------------------
    # function Invoke-PaginatedGet {
    #     [CmdletBinding()]
    #     param (
    #         [Parameter(Mandatory = $true)]
    #         [hashtable]$Headers,
    #
    #         [Parameter(Mandatory = $true)]
    #         [string]$InitialUrl,
    #
    #         [Parameter(Mandatory = $false)]
    #         [ValidateSet('Datto', 'ITGlue', 'Huntress')]
    #         [string]$PaginationStyle = 'Datto',
    #
    #         [Parameter(Mandatory = $false)]
    #         [string]$ItemsProperty = 'data'
    #     )
    #
    #     $allItems   = New-Object -TypeName 'System.Collections.Generic.List[object]'
    #     $currentUrl = $InitialUrl
    #
    #     do {
    #         $splat = @{ Uri = $currentUrl; Headers = $Headers; Method = 'GET' }
    #         $response = Invoke-RestMethod @splat
    #         $nextUrl  = $null
    #
    #         switch ($PaginationStyle) {
    #             'ITGlue' {
    #                 $items = $response.data
    #                 if ($response.meta -and $response.meta.'next-page') {
    #                     $nextPage = $response.meta.'next-page'
    #                     if ($currentUrl -match '[?&]page\[number\]=\d+') {
    #                         $nextUrl = $currentUrl -replace 'page\[number\]=\d+', "page[number]=$nextPage"
    #                     } else {
    #                         $sep     = if ($currentUrl -match '\?') { '&' } else { '?' }
    #                         $nextUrl = "$currentUrl${sep}page[number]=$nextPage"
    #                     }
    #                 }
    #             }
    #             'Huntress' {
    #                 $items = $response.$ItemsProperty
    #                 if ($response.pagination -and $response.pagination.next_page) {
    #                     $nextUrl = $response.pagination.next_page
    #                 }
    #             }
    #             'Datto' {
    #                 $items = $response.$ItemsProperty
    #                 if ($response.pageDetails -and $response.pageDetails.nextPageUrl) {
    #                     $nextUrl = $response.pageDetails.nextPageUrl
    #                 }
    #             }
    #         }
    #
    #         if ($null -ne $items) {
    #             foreach ($item in $items) { $allItems.Add($item) }
    #         }
    #         $currentUrl = $nextUrl
    #     } while ($null -ne $currentUrl)
    #
    #     return $allItems
    # }

    # --------------------------------------------------------------------------
    # INVOKE-THROTTLEDWRITE — Sliding Window Rate Limiter
    # Wraps an API write call with a sliding-window rate limiter.
    # Tracks write timestamps in a Queue[datetime]. When the queue contains
    # $WriteRateSafe or more entries within the last $WriteWindowSecs seconds,
    # sleeps until the oldest entry ages out before proceeding.
    #
    # Configure these three variables in the CONFIGURATION block above:
    #   $WriteRateLimit  = 100   # API hard ceiling (writes per window)
    #   $WriteRateSafe   = 80    # Throttle threshold (80% of ceiling)
    #   $WriteWindowSecs = 60    # Rolling window in seconds
    #   $WriteTimestamps = New-Object -TypeName 'System.Collections.Generic.Queue[datetime]'
    #
    # Replace the inner Invoke-RestMethod call with your actual write operation.
    # Returns $true on success, $false on failure.
    #
    # Usage:
    #   $ok = Invoke-ThrottledWrite -SiteUid $uid -VariableName 'MyVar' `
    #                               -VariableValue 'value' -SiteLabel $name
    # --------------------------------------------------------------------------
    # function Invoke-ThrottledWrite {
    #     [CmdletBinding()]
    #     param (
    #         [Parameter(Mandatory = $true)] [string]$SiteUid,
    #         [Parameter(Mandatory = $true)] [string]$VariableName,
    #         [Parameter(Mandatory = $true)] [AllowEmptyString()] [string]$VariableValue,
    #         [Parameter(Mandatory = $true)] [string]$SiteLabel
    #     )
    #
    #     # Evict timestamps older than the window
    #     $cutoff = (Get-Date).AddSeconds(-$WriteWindowSecs)
    #     while ($WriteTimestamps.Count -gt 0 -and $WriteTimestamps.Peek() -lt $cutoff) {
    #         $WriteTimestamps.Dequeue() | Out-Null
    #     }
    #
    #     # Throttle if at or above safe threshold
    #     if ($WriteTimestamps.Count -ge $WriteRateSafe) {
    #         $windowExpiry = $WriteTimestamps.Peek().AddSeconds($WriteWindowSecs)
    #         $waitMs       = [Math]::Max(0, ([int](($windowExpiry - (Get-Date)).TotalMilliseconds) + 100))
    #         Write-Log "Write throttle: $($WriteTimestamps.Count) writes in last ${WriteWindowSecs}s. Pausing ${waitMs}ms." -Severity INFO
    #         Start-Sleep -Milliseconds $waitMs
    #         $cutoff = (Get-Date).AddSeconds(-$WriteWindowSecs)
    #         while ($WriteTimestamps.Count -gt 0 -and $WriteTimestamps.Peek() -lt $cutoff) {
    #             $WriteTimestamps.Dequeue() | Out-Null
    #         }
    #     }
    #
    #     # Perform the write
    #     try {
    #         $body   = [System.Text.Encoding]::UTF8.GetBytes(
    #                     (ConvertTo-Json -Compress -InputObject @{
    #                         name  = $VariableName
    #                         value = $VariableValue
    #                     })
    #                   )
    #         $splat  = @{
    #             Uri         = "$dattoBaseUrl/api/v2/site/$SiteUid/variable"
    #             Method      = 'PUT'
    #             Headers     = $dattoHeaders
    #             Body        = $body
    #             ContentType = 'application/json'
    #         }
    #         Invoke-RestMethod @splat | Out-Null
    #         $WriteTimestamps.Enqueue((Get-Date))
    #         return $true
    #     }
    #     catch {
    #         Write-Log "Failed to write $VariableName for '$SiteLabel': $_" -Severity WARN
    #         return $false
    #     }
    # }

    # --------------------------------------------------------------------------
    # IDEMPOTENCY PATTERN — Read Before Write
    # For scripts that write to APIs on a recurring schedule, fetch current
    # state before writing. Only issue a write if the value is actually
    # different or missing. This eliminates unnecessary API churn and keeps
    # logs clean once initial population is complete.
    #
    # Example for DattoRMM site variables:
    #   $existingVars = @{}
    #   if (-not $IsReportOnly) {
    #       try {
    #           $getSplat = @{
    #               Uri     = "$dattoBaseUrl/api/v2/site/$siteUid/variables"
    #               Method  = 'GET'
    #               Headers = $dattoHeaders
    #           }
    #           $response = Invoke-RestMethod @getSplat
    #           if ($null -ne $response.variables) {
    #               foreach ($v in $response.variables) {
    #                   if (-not [string]::IsNullOrWhiteSpace($v.name)) {
    #                       $existingVars[$v.name] = $v.value
    #                   }
    #               }
    #           }
    #       }
    #       catch {
    #           Write-Log "Could not fetch existing variables for '$siteLabel': $_" -Severity WARN
    #       }
    #   }
    #
    #   # Then compare before writing:
    #   if (("$($existingVars['MyVar'])").Trim() -eq ("$myValue").Trim()) {
    #       Write-VerboseLog "[SKIPPED-CURRENT]  MyVar = $myValue  |  '$siteName'" -Severity INFO -Indent 1
    #   } else {
    #       $ok = Invoke-ThrottledWrite ...
    #   }
    # --------------------------------------------------------------------------

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    # Resolve boolean-style string parameters here, after logging is ready.
    # Standard feature flag:
    #   $IsEnabled    = ($EnableFeature.Trim().ToLower() -eq 'true')
    #
    # Write gate (asymmetric — any value other than explicit 'false' = report-only):
    #   $IsReportOnly = ($ReportOnly.Trim().ToLower() -ne 'false')
    #
    # Verbose gate:
    #   $IsVerbose    = ($VerboseOutput.Trim().ToLower() -ne 'false')

    # ------------------------------------------------------------------
    # Script startup — structured log header + console banner.
    # FOR WRITE-CAPABLE SCRIPTS: Add Mode to both the log header and the
    # console output block so the operating mode is captured at the top
    # of every run.
    # ------------------------------------------------------------------
    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    # $ModeLabel = if ($IsReportOnly) { 'REPORT-ONLY' } else { 'WRITE MODE' }

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName"                    -Severity INFO
    Write-Log "Hostname : $Hostname"                    -Severity INFO
    Write-Log "Run As   : $RunAs"                       -Severity INFO
    # Write-Log "Mode     : $ModeLabel"                 -Severity INFO   # uncomment for write-capable scripts
    Write-Log "Log File : $LogFile"                     -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site     : $SiteName"  -Severity PLAIN
    Write-Console "Hostname : $Hostname"  -Severity PLAIN
    Write-Console "Run As   : $RunAs"     -Severity PLAIN
    # Write-Console "Mode     : $ModeLabel" -Severity PLAIN              # uncomment for write-capable scripts
    Write-Console "Log File : $LogFile"   -Severity PLAIN
    Write-Separator

    try {

        # ------------------------------------------------------------------
        # PRE-FLIGHT VALIDATION
        # Check all required parameters before doing any real work.
        # Use exit 2 for fatal startup failures so DattoRMM can distinguish
        # "script never ran" from "script ran but hit errors".
        # ------------------------------------------------------------------
        Write-Section 'Pre-Flight'

        $preFlightFailed = $false

        if ([string]::IsNullOrWhiteSpace($ExampleParam)) {
            Write-Log "ExampleParam is required but was not provided." -Severity ERROR
            Write-Console "ExampleParam is required but was not provided." -Severity ERROR
            $preFlightFailed = $true
        }

        # Add additional required parameter checks here following the same pattern.

        if ($preFlightFailed) {
            Write-Log "Pre-flight validation failed. Exiting." -Severity ERROR
            Write-Banner "SCRIPT FAILED — PRE-FLIGHT" -Color "Red"
            exit 2
        }

        Write-Log "Pre-flight validation passed." -Severity SUCCESS
        Write-Console "Pre-flight validation passed." -Severity SUCCESS

        # ------------------------------------------------------------------
        # SCRIPT LOGIC
        # Add your implementation here. Reference notes:
        #
        # SECRETS / CREDENTIALS:
        #   - Never log secrets, API keys, or passwords via Write-Log.
        #   - Null out credential variables immediately after use:
        #       $ApiSecret = $null
        #   - For Basic auth, null both raw credentials after base64 encoding:
        #       $credBytes  = [System.Text.Encoding]::ASCII.GetBytes("$key:$secret")
        #       $b64        = [Convert]::ToBase64String($credBytes)
        #       $key        = $null
        #       $secret     = $null
        #       $credBytes  = $null
        #
        # API FIELD VERIFICATION:
        #   Before finalizing any script consuming a third-party API, verify
        #   actual JSON field names against a live response. Documentation
        #   terminology frequently differs from API field names.
        #   Quick check:
        #       $r = Invoke-RestMethod -Uri 'https://api.example.com/v1/items?limit=1' -Headers $h
        #       $r.items[0] | ConvertTo-Json -Depth 3
        #
        # FOUR-OUTCOME LOGGING (write-capable scripts):
        #   Log an explicit outcome for every item processed:
        #       [WROTE]             - value was missing or different, write succeeded
        #       [SKIPPED-CURRENT]   - value already correct, no write needed
        #       [SKIPPED-REPORT]    - would have written, but report-only mode is on
        #       [SKIPPED-NO-MATCH]  - item could not be matched to a source record
        #   All four outcomes emit via Write-VerboseLog (gated by $IsVerbose).
        #   WARN/ERROR outcomes always emit via Write-Log directly.
        #
        # SUMMARY OUTPUT:
        #   Never use Format-Table / Format-List for DattoRMM output.
        #   Column-formatted output garbles in the DattoRMM job log viewer.
        #   Write summary data as individual Write-Log lines instead.
        #
        # POST-CONDITIONS (Warning Text):
        #   DattoRMM can scan stdout for a configured string and flag the job
        #   orange — independent of exit code. Configure the match string in
        #   the component Post-Condition field (case-sensitive):
        #       Write-Log "WARNING: Some items could not be processed." -Severity WARN
        #       # Post-Condition match string: WARNING:
        #
        # UDF WRITES:
        #   Set-UdfValue -Slot 5 -Value "Completed: 42 records processed"
        #   Max 255 characters. Never write secrets to UDFs.
        #
        # PS 5.1 COMPATIBILITY REMINDERS:
        #   New-Object -TypeName 'System.Collections.Generic.List[PSObject]'
        #   $list[$list.Count - 1]            (not $list[-1])
        #   $x = if ($a) { $b } else { $c }   (not $a ? $b : $c)
        # ------------------------------------------------------------------

        Write-Section 'Main'

        # --- Your implementation here ---

        # ------------------------------------------------------------------
        # SUMMARY
        # Emit a structured summary before exit. For write-capable scripts,
        # always include the mode display and outcome counts.
        # ------------------------------------------------------------------
        Write-Section 'Summary'

        Write-Log "Script completed successfully." -Severity SUCCESS
        Write-Banner "COMPLETED SUCCESSFULLY" -Color "Green"

        exit 0

    }
    catch {
        Write-Log "Unhandled exception: $_"             -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Console "Unhandled exception: $_"         -Severity ERROR
        Write-Banner "SCRIPT FAILED" -Color "Red"

        exit 1
    }

} # End function Invoke-ScriptTemplate

# ==============================================================================
# ENTRY POINT
# Splat parameters cleanly into the master function. Nothing else runs here.
# ==============================================================================
$ScriptParams = @{
    ExampleParam = $ExampleParam
    AnotherParam = $AnotherParam
    # EnableFeature  = $EnableFeature
    # ReportOnly     = $ReportOnly
    # VerboseOutput  = $VerboseOutput
    SiteName     = $SiteName
    Hostname     = $Hostname
}

Invoke-ScriptTemplate @ScriptParams
