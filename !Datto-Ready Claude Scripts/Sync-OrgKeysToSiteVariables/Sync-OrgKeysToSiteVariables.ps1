#Requires -Version 5.1
<#
.SYNOPSIS
    Syncs ITGlue organization IDs and Huntress organization keys to DattoRMM
    site-level variables for every matched site.

.DESCRIPTION
    Pulls all organizations from ITGlue and Huntress, then iterates every
    DattoRMM site and attempts to match each site's company-name prefix
    (parsed from the "CompanyName - SiteName" DattoRMM naming convention)
    against both sources. On a successful match, writes ITGOrgKey and/or
    HUNTRESS_ORG_KEY as site variables via the DattoRMM API.

    REPORT-ONLY MODE IS ON BY DEFAULT. The script matches and logs what it
    would write but will not touch any site variables unless you explicitly
    pass -ReportOnly 'false' (or set the DattoRMM ReportOnly component
    variable to 'false'). The resolution is default-safe: only the literal
    string 'false' enables writes; any other value (typo, blank, garbage,
    unexpected casing) falls back to report-only.

    Unmatched sites are logged but do not cause the script to fail. A
    summary is emitted at the end listing all unmatched sites for review.

    DEPLOYMENT CONTEXT
    This script is designed to run as a DattoRMM scheduled Script component
    targeted at a single management host. Secrets are delivered as DattoRMM
    component variables rather than being stored in a wrapper script on
    disk. The script also supports standard manual invocation for ad-hoc
    runs and initial testing.

    DattoRMM component variables (create these on the component):
        DattoApiUrl       - String    - DattoRMM base API URL
        DattoApiKey       - String    - DattoRMM OAuth2 API key
        DattoApiSecret    - Password  - DattoRMM OAuth2 API secret
        ITGlueAPIKey      - Password  - ITGlue account API key
        ITGlueUrl         - String    - (Optional) override base URL
        HuntressApiKey    - Password  - Huntress API public key
        HuntressApiSecret - Password  - Huntress API secret key
        ReportOnly        - String    - Defaults to report-only. Must be the
                                        EXPLICIT literal string 'false' to
                                        enable writes. Any other value
                                        (including typos or blank) stays
                                        safely in report-only mode.
        SkipITGlue        - String    - 'true' to skip ITGlue entirely
        SkipHuntress      - String    - 'true' to skip Huntress entirely
        VerboseOutput     - String    - 'true' (default) or 'false' for quiet

.PARAMETER DattoApiUrl
    Base API URL for your DattoRMM instance (e.g.
    https://merlot-api.centrastage.net). Reads $env:DattoApiUrl if not
    supplied.

.PARAMETER DattoApiKey
    DattoRMM OAuth2 API key. Reads $env:DattoApiKey if not supplied.

.PARAMETER DattoApiSecret
    DattoRMM OAuth2 API secret. Reads $env:DattoApiSecret if not supplied.
    Must be delivered as a Password-type component variable under DattoRMM.

.PARAMETER ITGlueUrl
    Base URL for the ITGlue API. Defaults to https://api.itglue.com. Reads
    $env:ITGlueUrl if not supplied. Override for EU/regional endpoints.

.PARAMETER ITGlueAPIKey
    ITGlue account API key. Reads $env:ITGlueAPIKey if not supplied.

.PARAMETER HuntressApiKey
    Huntress API public key. Reads $env:HuntressApiKey if not supplied.

.PARAMETER HuntressApiSecret
    Huntress API secret key. Reads $env:HuntressApiSecret if not supplied.

.PARAMETER ReportOnly
    Controls whether the script actually writes to DattoRMM. DEFAULTS TO
    REPORT-ONLY. The script writes only if this parameter is the EXPLICIT
    literal string 'false' (case-insensitive, whitespace trimmed). Any
    other value — including the default, a typo, a blank string, garbage,
    or an unexpected casing of 'true' — falls safely into report-only
    mode. This is an intentionally asymmetric guard: report-only is the
    safe state, writes must be opted into explicitly and unambiguously.
    DattoRMM Boolean component variables arrive as strings — this
    parameter accepts string input for that reason.

.PARAMETER SkipITGlue
    Set to 'true' to skip ITGlue entirely and only sync Huntress keys.

.PARAMETER SkipHuntress
    Set to 'true' to skip Huntress entirely and only sync ITGlue IDs.

.PARAMETER VerboseOutput
    Set to 'false' to suppress per-site detail lines. Section headers,
    summary, unmatched lists, and all WARN/ERROR entries always emit.
    Defaults to 'true'. Useful for quiet scheduled runs once the initial
    configuration is validated. Named VerboseOutput rather than Verbose
    to avoid collision with PowerShell's built-in -Verbose common
    parameter (exposed automatically by [CmdletBinding()]).

.EXAMPLE
    .\Sync-OrgKeysToSiteVariables.ps1 `
        -DattoApiUrl    'https://merlot-api.centrastage.net' `
        -DattoApiKey    'your-datto-key' `
        -DattoApiSecret 'your-datto-secret' `
        -ITGlueAPIKey   'your-itg-key' `
        -HuntressApiKey    'your-huntress-public-key' `
        -HuntressApiSecret 'your-huntress-secret'

    Report-only run (default). Shows every match and what would be written
    without modifying DattoRMM.

.EXAMPLE
    .\Sync-OrgKeysToSiteVariables.ps1 `
        -DattoApiUrl    'https://merlot-api.centrastage.net' `
        -DattoApiKey    'your-datto-key' `
        -DattoApiSecret 'your-datto-secret' `
        -ITGlueAPIKey   'your-itg-key' `
        -HuntressApiKey    'your-huntress-public-key' `
        -HuntressApiSecret 'your-huntress-secret' `
        -ReportOnly 'false'

    Commits writes. The parameter is [string], not [bool] — pass the
    literal string 'false' (quoted), not $false. Only run after review
    of a clean report-only pass.

.NOTES
    File Name      : Sync-OrgKeysToSiteVariables.ps1
    Version        : 1.4.1.005
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-04-23
    Last Modified  : 2026-04-23
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM (DattoRMM Script component on a designated
                     management host) or interactive Domain Admin for
                     manual/test runs
    DattoRMM       : Compatible - supports environment variable input for
                     all parameters including secrets
    Client Scope   : All clients (iterates every site in the Datto tenant)

    Exit Codes:
        0  - Success (partial matches and write errors are non-fatal)
        1  - Runtime failure (script started, errors during execution)
        2  - Fatal pre-flight failure (missing required parameters, auth
             failure, or any condition preventing execution from starting)

    Output Design:
        Write-Log       - Structured [timestamp][SEVERITY] output to log
                          file AND DattoRMM stdout. Always verbose. No color.
        Write-Console   - Human-friendly colored console output for manual
                          runs. Uses Write-Host (display stream only).
                          Suppressed automatically in DattoRMM agent context.
        VerboseOutput   - Controls per-site detail lines (wrote / skipped /
                          report-only / no-match). Section headers, summary,
                          unmatched lists, and WARN/ERROR always print.
                          Defaults to 'true'. Pass 'false' for quiet runs.

.CHANGELOG
    v1.4.1.005 - 2026-04-23 - Sam Kirsch
        - SAFETY: Inverted ReportOnly resolution to default-safe semantics.
          Previously resolved writes-enabled as "anything != 'true'", which
          meant a typo, whitespace issue, empty string, or garbage value in
          the DattoRMM component variable would enable writes. Now resolves
          report-only as "anything != 'false'" — only the explicit literal
          string 'false' enables writes. Any typo, blank, or unexpected
          value falls safely into report-only mode.
        - Renamed -Verbose parameter to -VerboseOutput to avoid collision
          with PowerShell's built-in [CmdletBinding()] -Verbose common
          parameter. Internal resolved variable renamed from $IsVerbose to
          $IsVerboseOutput and all call sites updated. DattoRMM component
          variable should be named 'VerboseOutput' to match.
        - ITGlue org ID idempotency comparison now forces both sides to
          trimmed strings via "$value".Trim() pattern. Guards against type
          drift (ITGlue's JSON id field can surface as string or int
          depending on deserializer) and incidental whitespace from the
          DattoRMM variables GET response. Prevents unnecessary churn
          writes on stable configurations.

    v1.4.0.004 - 2026-04-23 - Sam Kirsch
        - Hardened boolean string parsing: all three string-bool params
          (ReportOnly / SkipITGlue / SkipHuntress) now use
          .Trim().ToLower() -eq 'true' to prevent accidental write-mode
          entry if DattoRMM passes 'True', 'TRUE', or ' true '.
        - Added -Verbose parameter (string 'true'/'false', default 'true').
          Gates per-site detail lines in both Write-Log and Write-Console.
          Section headers, summary, unmatched lists, and all WARN/ERROR
          entries always emit regardless of Verbose setting.
        - Added Get-DattoSiteVariables helper: fetches all existing
          variables for a site in a single GET (/v2/site/{uid}/variables).
          Called once per site before the write phase; result passed into
          the variable decision logic to enable idempotency checks.
        - Added idempotency check: before writing each variable, compares
          the resolved value against the existing site variable value. Four
          outcomes per variable, all logged (gated by Verbose):
            [WROTE]             - new or changed value, write succeeded
            [SKIPPED-CURRENT]   - value already correct, no write needed
            [SKIPPED-REPORT]    - would write, but report-only mode is on
            [SKIPPED-NO-MATCH]  - site had no match in source system
          This produces a full per-org accounting on every run and
          eliminates unnecessary API writes on stable configurations.
        - Summary counters expanded: tracks skipped-current count
          separately from written count.
        - Added Verbose to startup log header.

    v1.2.0.0 - 2026-04-23 - Sam Kirsch
        - Full refactor to Databranch script standards
        - Wrapped all logic in master function Sync-OrgKeysToSiteVariables
        - Added standard Write-Log/Write-Console dual-output pattern with
          full severity support (INFO/WARN/ERROR/SUCCESS/DEBUG)
        - Added file logging to C:\Databranch\ScriptLogs\<ScriptName>\ with
          10-file rotation
        - Added standard startup log header (Site / Hostname / Run As /
          Params / Log File)
        - Added DattoRMM env-var fallback pattern for all parameters so the
          same script runs unchanged under DattoRMM component dispatch or
          via manual invocation
        - Added pre-flight parameter validation block that exits 2 with
          clear diagnostics on missing required inputs
        - Fixed exit codes: pre-flight/auth failures now exit 2, runtime
          exceptions exit 1 (was 1 for both)
        - Fixed DattoRMM OAuth2 token request: now includes required HTTP
          Basic auth header (public-client:public) in addition to the
          password grant body — prior version would fail token grant on
          current API gateway
        - Secrets now null out immediately after use in all three APIs
          (Datto secret was previously never nulled)
        - Replaced .Split on ' - ' with explicit StringSplitOptions to
          avoid regex surprises and handle normalized whitespace
        - Changed 'Deleted Devices' site filter from regex prefix match to
          exact-match equality for precision
        - Removed redundant parallel *NormLookup hashtables; lookup tables
          are queried with .ContainsKey directly
        - Verified Huntress pagination field name (pagination.next_page is
          a page number, not a URL — pagination branch now reconstructs
          the URL like the ITGlue branch does)
        - Added 600ms spacing between DattoRMM writes to stay comfortably
          under the 100-writes/60-seconds API ceiling
        - Replaced [System.Collections.Generic.List[T]]::new() with
          New-Object per PS 5.1 compatibility standard
        - Version format corrected to Major.Minor.Revision.Build

    v1.1.0.002 - 2026-04-23
        - Replaced -WhatIf/SupportsShouldProcess with explicit -ReportOnly
          parameter defaulting to $true

    v1.0.0.001 - 2026-04-23
        - Initial release
#>



# ==============================================================================
# PARAMETERS
# Supports both DattoRMM environment variable input (automated) and standard
# PowerShell parameter input (manual/interactive). DattoRMM env vars take
# precedence if present; otherwise falls back to passed parameters or defaults.
#
# BOOLEAN INPUT VARIABLES — CRITICAL GOTCHA:
#   DattoRMM Boolean component variables arrive as the STRING "true" or "false".
#   All boolean-ish params are typed as [string] and resolved with
#   .Trim().ToLower() against an explicit literal. Do NOT cast them to [bool] —
#   any non-empty string including "false" is truthy.
#
#   NOTE ON REPORTONLY — DEFAULT-SAFE ASYMMETRY:
#   ReportOnly resolves via -ne 'false' (NOT -eq 'true'). This means writes
#   are enabled ONLY when the value is the explicit literal 'false'. A typo,
#   blank string, garbage value, or unexpected casing all fall safely into
#   report-only. The other flags (SkipITGlue / SkipHuntress / VerboseOutput)
#   use the ordinary -eq 'true' pattern because their ambiguous case is lower
#   stakes. ReportOnly is the one flag that guards real blast radius.
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$DattoApiUrl = $(if ($env:DattoApiUrl) { $env:DattoApiUrl } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$DattoApiKey = $(if ($env:DattoApiKey) { $env:DattoApiKey } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$DattoApiSecret = $(if ($env:DattoApiSecret) { $env:DattoApiSecret } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$ITGlueUrl = $(if ($env:ITGlueUrl) { $env:ITGlueUrl } else { 'https://api.itglue.com' }),

    [Parameter(Mandatory = $false)]
    [string]$ITGlueAPIKey = $(if ($env:ITGlueAPIKey) { $env:ITGlueAPIKey } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$HuntressApiKey = $(if ($env:HuntressApiKey) { $env:HuntressApiKey } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$HuntressApiSecret = $(if ($env:HuntressApiSecret) { $env:HuntressApiSecret } else { "" }),

    # Boolean-style params — strings per DattoRMM convention.
    # All resolved with .Trim().ToLower() -eq 'true' to handle any casing.
    [Parameter(Mandatory = $false)]
    [string]$ReportOnly = $(if ($env:ReportOnly) { $env:ReportOnly } else { 'true' }),

    [Parameter(Mandatory = $false)]
    [string]$SkipITGlue = $(if ($env:SkipITGlue) { $env:SkipITGlue } else { 'false' }),

    [Parameter(Mandatory = $false)]
    [string]$SkipHuntress = $(if ($env:SkipHuntress) { $env:SkipHuntress } else { 'false' }),

    [Parameter(Mandatory = $false)]
    [string]$VerboseOutput = $(if ($env:VerboseOutput) { $env:VerboseOutput } else { 'true' }),

    # DattoRMM built-in variables — auto-populated by Datto, no component config needed
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "ManagementHost" }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# PowerShell 5.1 on older Windows (Server 2012 R2, early Win10 builds) defaults
# to TLS 1.0/1.1 for web requests. All three APIs this script calls (DattoRMM,
# ITGlue, Huntress) require TLS 1.2 minimum and will reject older connections
# with errors that look like generic network failures.
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Sync-OrgKeysToSiteVariables {
    [CmdletBinding()]
    param (
        [string]$DattoApiUrl,
        [string]$DattoApiKey,
        [string]$DattoApiSecret,
        [string]$ITGlueUrl,
        [string]$ITGlueAPIKey,
        [string]$HuntressApiKey,
        [string]$HuntressApiSecret,
        [string]$ReportOnly,
        [string]$SkipITGlue,
        [string]$SkipHuntress,
        [string]$VerboseOutput,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Sync-OrgKeysToSiteVariables"
    $ScriptVersion = "1.4.1.005"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # ---- Resolve boolean-style string params ----
    # .Trim().ToLower() guards against DattoRMM passing 'True', 'TRUE', ' true ', etc.
    #
    # SAFETY-CRITICAL ASYMMETRY:
    #   ReportOnly uses -ne 'false' (default-safe). Writes enable ONLY on the
    #   explicit literal 'false'. Any typo, blank, or garbage stays in report-only.
    #   The other three flags use the ordinary -eq 'true' pattern because their
    #   ambiguous case is not write-destructive.
    $IsReportOnly    = ($ReportOnly.Trim().ToLower()    -ne 'false')
    $IsSkipITGlue    = ($SkipITGlue.Trim().ToLower()    -eq 'true')
    $IsSkipHuntress  = ($SkipHuntress.Trim().ToLower()  -eq 'true')
    $IsVerboseOutput = ($VerboseOutput.Trim().ToLower() -eq 'true')

    # DattoRMM API write rate limit: 100 writes per 60 seconds.
    # Invoke-ThrottledWrite tracks timestamps in a sliding window and pauses
    # when 80 writes (80% of ceiling) have occurred in the last 60 seconds.
    $WriteRateLimit  = 100
    $WriteRateSafe   = 80
    $WriteWindowSecs = 60
    $WriteTimestamps = New-Object -TypeName 'System.Collections.Generic.Queue[datetime]'

    # ==========================================================================
    # WRITE-LOG  (Structured Output Layer)
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
    # CONSOLE PRESENTATION HELPERS
    # ==========================================================================

    # ==========================================================================
    # WRITE-VERBOSELOG  (Verbose-gated Output)
    # Calls both Write-Log and Write-Console only when $IsVerboseOutput is true.
    # Use for per-site detail lines. All WARN/ERROR/structural output should
    # call Write-Log/Write-Console directly so it always emits.
    # ==========================================================================
    function Write-VerboseLog {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = "",

            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
            [string]$Severity = "INFO",

            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )

        if (-not $IsVerboseOutput) { return }

        Write-Log     $Message -Severity $Severity
        Write-Console $Message -Severity $Severity -Indent $Indent
    }

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

    function Write-Separator {
        param (
            [Parameter(Mandatory = $false)]
            [string]$Color = "DarkGray"
        )

        Write-Host ("-" * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # INITIALIZE-LOGGING
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
    # GET-NORMALIZEDNAME
    # Lowercases and strips punctuation/extra whitespace for fuzzy matching.
    # ==========================================================================
    function Get-NormalizedName {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Name
        )

        if ([string]::IsNullOrWhiteSpace($Name)) { return "" }

        $result = $Name.ToLower()
        $result = $result -replace '[^a-z0-9\s]', ''
        $result = $result -replace '\s+', ' '
        return $result.Trim()
    }

    # ==========================================================================
    # RESOLVE-COMPANYNAME
    # Extracts the company name from a DattoRMM site name following the
    # "CompanyName - SiteName" convention. Handles company names that contain
    # " - " by trying progressively longer prefixes against the lookup table.
    # ==========================================================================
    function Resolve-CompanyName {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$SiteName,

            [Parameter(Mandatory = $false)]
            [hashtable]$NormalizedLookup = @{}
        )

        # Explicit literal split — avoid regex surprises and handle the
        # normalized whitespace case. StringSplitOptions::None preserves
        # empty tokens so we can detect mal-formed input.
        $tokens = $SiteName.Split([string[]]@(' - '), [System.StringSplitOptions]::None)

        if ($tokens.Count -eq 1) {
            return $SiteName
        }

        # Try longest prefix first that matches the lookup table, working
        # from all-but-last down to just-the-first.
        for ($i = ($tokens.Count - 1); $i -ge 1; $i--) {
            $slice      = @($tokens[0..($i - 1)])
            $candidate  = $slice -join ' - '
            $normalized = Get-NormalizedName -Name $candidate
            if ($NormalizedLookup.ContainsKey($normalized)) {
                return $candidate
            }
        }

        # No lookup match; return leftmost token as best guess
        return $tokens[0]
    }

    # ==========================================================================
    # INVOKE-PAGINATEDGET
    # Iterates paginated REST endpoints. Handles three pagination flavors:
    #   ITGlue   - meta.'next-page' returns a page number; URL reconstructed
    #   Huntress - pagination.current_page / .total_pages; URL reconstructed
    #   Datto    - pageDetails.nextPageUrl returns a full URL
    # ==========================================================================
    function Invoke-PaginatedGet {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [hashtable]$Headers,

            [Parameter(Mandatory = $true)]
            [string]$InitialUrl,

            [Parameter(Mandatory = $false)]
            [ValidateSet('ITGlue', 'Huntress', 'Datto')]
            [string]$PaginationStyle = 'Datto',

            [Parameter(Mandatory = $false)]
            [string]$ItemsProperty = 'data'
        )

        $allItems   = New-Object -TypeName 'System.Collections.Generic.List[object]'
        $currentUrl = $InitialUrl

        do {
            $restSplat = @{
                Uri     = $currentUrl
                Headers = $Headers
                Method  = 'GET'
            }
            $response = Invoke-RestMethod @restSplat
            $nextUrl  = $null
            $items    = $null

            switch ($PaginationStyle) {
                'ITGlue' {
                    $items = $response.data
                    if ($response.meta -and $response.meta.'next-page') {
                        $nextPage = $response.meta.'next-page'
                        if ($currentUrl -match 'page\[number\]=\d+') {
                            $nextUrl = $currentUrl -replace 'page\[number\]=\d+', "page[number]=$nextPage"
                        }
                        else {
                            $sep = if ($currentUrl -match '\?') { '&' } else { '?' }
                            $nextUrl = "$currentUrl${sep}page[number]=$nextPage"
                        }
                    }
                }
                'Huntress' {
                    $items = $response.$ItemsProperty
                    # Huntress exposes pagination.current_page and pagination.total_pages.
                    # There is no URL field — we must reconstruct by incrementing page.
                    if ($response.pagination -and
                        $response.pagination.current_page -and
                        $response.pagination.total_pages -and
                        ($response.pagination.current_page -lt $response.pagination.total_pages)) {

                        $nextPageNumber = [int]$response.pagination.current_page + 1
                        if ($currentUrl -match '[?&]page=\d+') {
                            $nextUrl = $currentUrl -replace 'page=\d+', "page=$nextPageNumber"
                        }
                        else {
                            $sep = if ($currentUrl -match '\?') { '&' } else { '?' }
                            $nextUrl = "$currentUrl${sep}page=$nextPageNumber"
                        }
                    }
                }
                'Datto' {
                    $items = $response.$ItemsProperty
                    if ($response.pageDetails -and $response.pageDetails.nextPageUrl) {
                        $nextUrl = $response.pageDetails.nextPageUrl
                    }
                }
            }

            if ($null -ne $items) {
                foreach ($item in $items) {
                    $allItems.Add($item)
                }
            }

            $currentUrl = $nextUrl
        } while ($null -ne $currentUrl)

        return $allItems
    }

    # ==========================================================================
    # GET-DATTOACCESSTOKEN
    # DattoRMM OAuth2: grant_type=password with HTTP Basic auth header using
    # the fixed public-client:public credentials, and the API key/secret as
    # the body username/password. Returns the access_token string on success.
    # ==========================================================================
    function Get-DattoAccessToken {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$ApiUrl,

            [Parameter(Mandatory = $true)]
            [string]$ApiKey,

            [Parameter(Mandatory = $true)]
            [string]$ApiSecret
        )

        $basicBytes = [System.Text.Encoding]::ASCII.GetBytes('public-client:public')
        $basicB64   = [Convert]::ToBase64String($basicBytes)

        $tokenSplat = @{
            Uri     = "$ApiUrl/auth/oauth/token"
            Method  = 'POST'
            Headers = @{ Authorization = "Basic $basicB64" }
            Body    = @{
                grant_type = 'password'
                username   = $ApiKey
                password   = $ApiSecret
            }
        }

        $tokenResponse = Invoke-RestMethod @tokenSplat
        return $tokenResponse.access_token
    }

    # ==========================================================================
    # WRITE-DATTOSITEVARIABLE
    # Writes a single site-scoped variable to DattoRMM. Returns $true on
    # success, $false on failure (with a warning log entry).
    # ==========================================================================
    function Write-DattoSiteVariable {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$BaseUrl,

            [Parameter(Mandatory = $true)]
            [hashtable]$Headers,

            [Parameter(Mandatory = $true)]
            [string]$SiteUid,

            [Parameter(Mandatory = $true)]
            [string]$VariableName,

            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$VariableValue,

            [Parameter(Mandatory = $true)]
            [string]$SiteLabel
        )

        try {
            $payload = @{ name = $VariableName; value = $VariableValue } | ConvertTo-Json -Compress
            $body    = [System.Text.Encoding]::UTF8.GetBytes($payload)

            $putSplat = @{
                Uri         = "$BaseUrl/api/v2/site/$SiteUid/variable"
                Method      = 'PUT'
                Headers     = $Headers
                Body        = $body
                ContentType = 'application/json'
            }
            Invoke-RestMethod @putSplat | Out-Null
            return $true
        }
        catch {
            Write-Log     "Failed to write $VariableName for site '$SiteLabel': $_" -Severity WARN
            Write-Console "Failed to write $VariableName for site '$SiteLabel': $_" -Severity WARN -Indent 1
            return $false
        }
    }

    # ==========================================================================
    # GET-DATTOSITEVARIABLES
    # Fetches all existing site-level variables for a site in a single GET.
    # Returns a hashtable of VariableName -> VariableValue, or an empty
    # hashtable on failure (treated as "no existing variables" so writes proceed).
    # ==========================================================================
    function Get-DattoSiteVariables {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$BaseUrl,

            [Parameter(Mandatory = $true)]
            [hashtable]$Headers,

            [Parameter(Mandatory = $true)]
            [string]$SiteUid,

            [Parameter(Mandatory = $true)]
            [string]$SiteLabel
        )

        $result = @{}
        try {
            $getSplat = @{
                Uri     = "$BaseUrl/api/v2/site/$SiteUid/variables"
                Method  = 'GET'
                Headers = $Headers
            }
            $response = Invoke-RestMethod @getSplat
            # Response is an array of objects with .name and .value properties
            if ($null -ne $response.variables) {
                foreach ($v in $response.variables) {
                    if (-not [string]::IsNullOrWhiteSpace($v.name)) {
                        $result[$v.name] = $v.value
                    }
                }
            }
        }
        catch {
            Write-Log "Could not fetch existing variables for '$SiteLabel' (will write unconditionally): $_" -Severity WARN
        }
        return $result
    }

    # ==========================================================================
    # INVOKE-THROTTLEDWRITE
    # Wraps Write-DattoSiteVariable with a sliding-window rate limiter.
    # Tracks write timestamps in a queue; if the last 60 seconds contain
    # $WriteRateSafe or more writes, sleeps until the oldest timestamp ages
    # out before issuing the next PUT.
    # Returns $true on success, $false on failure.
    # ==========================================================================
    function Invoke-ThrottledWrite {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$BaseUrl,

            [Parameter(Mandatory = $true)]
            [hashtable]$Headers,

            [Parameter(Mandatory = $true)]
            [string]$SiteUid,

            [Parameter(Mandatory = $true)]
            [string]$VariableName,

            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$VariableValue,

            [Parameter(Mandatory = $true)]
            [string]$SiteLabel
        )

        # Evict timestamps older than the window
        $cutoff = (Get-Date).AddSeconds(-$WriteWindowSecs)
        while ($WriteTimestamps.Count -gt 0 -and $WriteTimestamps.Peek() -lt $cutoff) {
            $WriteTimestamps.Dequeue() | Out-Null
        }

        # If at or above safe threshold, wait until oldest entry ages out
        if ($WriteTimestamps.Count -ge $WriteRateSafe) {
            $windowExpiry = $WriteTimestamps.Peek().AddSeconds($WriteWindowSecs)
            $waitMs       = [Math]::Max(0, ([int](($windowExpiry - (Get-Date)).TotalMilliseconds) + 100))
            Write-Log "Write throttle: $($WriteTimestamps.Count) writes in last ${WriteWindowSecs}s. Pausing ${waitMs}ms." -Severity INFO

            Start-Sleep -Milliseconds $waitMs

            # Re-evict after sleeping
            $cutoff = (Get-Date).AddSeconds(-$WriteWindowSecs)
            while ($WriteTimestamps.Count -gt 0 -and $WriteTimestamps.Peek() -lt $cutoff) {
                $WriteTimestamps.Dequeue() | Out-Null
            }
        }

        $ok = Write-DattoSiteVariable -BaseUrl $BaseUrl -Headers $Headers `
                                      -SiteUid $SiteUid -VariableName $VariableName `
                                      -VariableValue $VariableValue -SiteLabel $SiteLabel

        if ($ok) { $WriteTimestamps.Enqueue((Get-Date)) }

        return $ok
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $ModeLabel = if ($IsReportOnly) { 'REPORT-ONLY' } else { 'WRITE MODE' }

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName"                    -Severity INFO
    Write-Log "Hostname : $Hostname"                    -Severity INFO
    Write-Log "Run As   : $RunAs"                       -Severity INFO
    Write-Log "Mode     : $ModeLabel"                   -Severity INFO
    Write-Log "Verbose  : $IsVerboseOutput"             -Severity INFO
    Write-Log "DattoUrl : $DattoApiUrl"                 -Severity INFO
    Write-Log "ITGUrl   : $ITGlueUrl"                   -Severity INFO
    Write-Log "SkipITG  : $IsSkipITGlue"                -Severity INFO
    Write-Log "SkipHunt : $IsSkipHuntress"              -Severity INFO
    Write-Log "Log File : $LogFile"                     -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site     : $SiteName"         -Severity PLAIN
    Write-Console "Hostname : $Hostname"         -Severity PLAIN
    Write-Console "Run As   : $RunAs"            -Severity PLAIN
    Write-Console "Mode     : $ModeLabel"        -Severity PLAIN
    Write-Console "Verbose  : $IsVerboseOutput"  -Severity PLAIN
    Write-Console "Log File : $LogFile"          -Severity PLAIN
    Write-Separator

    try {

        # ------------------------------------------------------------------
        # PRE-FLIGHT VALIDATION
        # ------------------------------------------------------------------
        $MissingParams = @()

        if ([string]::IsNullOrWhiteSpace($DattoApiUrl))    { $MissingParams += 'DattoApiUrl' }
        if ([string]::IsNullOrWhiteSpace($DattoApiKey))    { $MissingParams += 'DattoApiKey' }
        if ([string]::IsNullOrWhiteSpace($DattoApiSecret)) { $MissingParams += 'DattoApiSecret' }

        if (-not $IsSkipITGlue -and [string]::IsNullOrWhiteSpace($ITGlueAPIKey)) {
            $MissingParams += 'ITGlueAPIKey (required unless SkipITGlue=true)'
        }

        if (-not $IsSkipHuntress) {
            if ([string]::IsNullOrWhiteSpace($HuntressApiKey))    { $MissingParams += 'HuntressApiKey (required unless SkipHuntress=true)' }
            if ([string]::IsNullOrWhiteSpace($HuntressApiSecret)) { $MissingParams += 'HuntressApiSecret (required unless SkipHuntress=true)' }
        }

        if ($IsSkipITGlue -and $IsSkipHuntress) {
            $MissingParams += 'Cannot set both SkipITGlue=true and SkipHuntress=true — script has nothing to sync'
        }

        if ($MissingParams.Count -gt 0) {
            foreach ($P in $MissingParams) {
                Write-Log     "Missing required parameter: $P" -Severity ERROR
                Write-Console "Missing required parameter: $P" -Severity ERROR
            }
            Write-Banner 'FATAL - MISSING PARAMETERS' -Color 'Red'
            exit 2
        }

        $dattoBaseUrl = $DattoApiUrl.TrimEnd('/')

        # ------------------------------------------------------------------
        # DATTORMM AUTHENTICATION
        # ------------------------------------------------------------------
        Write-Section 'DattoRMM Authentication'
        Write-Log     'Authenticating to DattoRMM API...' -Severity INFO
        Write-Console 'Authenticating to DattoRMM API...' -Severity INFO

        $dattoToken = $null
        try {
            $dattoToken = Get-DattoAccessToken -ApiUrl $dattoBaseUrl -ApiKey $DattoApiKey -ApiSecret $DattoApiSecret
            # Null the secret immediately after token acquisition
            $DattoApiSecret = $null

            if ([string]::IsNullOrWhiteSpace($dattoToken)) {
                throw 'Token response did not include access_token.'
            }

            Write-Log     'DattoRMM authentication successful.' -Severity SUCCESS
            Write-Console 'DattoRMM authentication successful.' -Severity SUCCESS
        }
        catch {
            Write-Log     "DattoRMM authentication failed: $_" -Severity ERROR
            Write-Console "DattoRMM authentication failed: $_" -Severity ERROR
            Write-Banner  'FATAL - DATTO AUTH FAILED' -Color 'Red'
            exit 2
        }

        $dattoHeaders = @{
            Authorization  = "Bearer $dattoToken"
            'Content-Type' = 'application/json'
        }

        # ------------------------------------------------------------------
        # PULL ITGLUE ORGANIZATIONS
        # ------------------------------------------------------------------
        $itglueLookup = @{}

        if (-not $IsSkipITGlue) {
            Write-Section 'ITGlue: Pull Organizations'
            Write-Log     'Pulling organizations from ITGlue...' -Severity INFO
            Write-Console 'Pulling organizations from ITGlue...' -Severity INFO

            $itgHeaders = @{
                'x-api-key'    = $ITGlueAPIKey
                'Content-Type' = 'application/vnd.api+json'
            }

            try {
                $itgUrl  = "$($ITGlueUrl.TrimEnd('/'))/organizations?page[size]=100&page[number]=1"
                $itgOrgs = Invoke-PaginatedGet -Headers $itgHeaders -InitialUrl $itgUrl -PaginationStyle 'ITGlue' -ItemsProperty 'data'

                foreach ($org in $itgOrgs) {
                    $name = $org.attributes.name
                    $id   = $org.id
                    $norm = Get-NormalizedName -Name $name
                    if (-not [string]::IsNullOrWhiteSpace($norm)) {
                        $itglueLookup[$norm] = $id
                    }
                }

                Write-Log     "ITGlue: loaded $($itgOrgs.Count) organizations, $($itglueLookup.Count) unique normalized names." -Severity SUCCESS
                Write-Console "ITGlue: loaded $($itgOrgs.Count) organizations, $($itglueLookup.Count) unique normalized names." -Severity SUCCESS
            }
            catch {
                Write-Log     "Failed to pull ITGlue organizations: $_" -Severity ERROR
                Write-Console "Failed to pull ITGlue organizations: $_" -Severity ERROR
                Write-Log     'Continuing without ITGlue data.'         -Severity WARN
                Write-Console 'Continuing without ITGlue data.'         -Severity WARN -Indent 1
                $IsSkipITGlue = $true
            }
            finally {
                $ITGlueAPIKey = $null
            }
        }
        else {
            Write-Log     'ITGlue sync skipped (SkipITGlue=true).' -Severity INFO
            Write-Console 'ITGlue sync skipped (SkipITGlue=true).' -Severity INFO
        }

        # ------------------------------------------------------------------
        # PULL HUNTRESS ORGANIZATIONS
        # ------------------------------------------------------------------
        $huntressLookup = @{}

        if (-not $IsSkipHuntress) {
            Write-Section 'Huntress: Pull Organizations'
            Write-Log     'Pulling organizations from Huntress...' -Severity INFO
            Write-Console 'Pulling organizations from Huntress...' -Severity INFO

            $huntressCredBytes = [System.Text.Encoding]::ASCII.GetBytes("${HuntressApiKey}:${HuntressApiSecret}")
            $huntressB64       = [Convert]::ToBase64String($huntressCredBytes)
            $huntressHeaders   = @{
                Authorization  = "Basic $huntressB64"
                'Content-Type' = 'application/json'
            }

            # Null secrets from memory immediately after encoding
            $HuntressApiKey    = $null
            $HuntressApiSecret = $null
            $huntressCredBytes = $null

            try {
                $huntressUrl  = 'https://api.huntress.io/v1/organizations?limit=500&page=1'
                $huntressOrgs = Invoke-PaginatedGet -Headers $huntressHeaders -InitialUrl $huntressUrl -PaginationStyle 'Huntress' -ItemsProperty 'organizations'

                foreach ($org in $huntressOrgs) {
                    $name   = $org.name
                    $orgKey = $org.key
                    $norm   = Get-NormalizedName -Name $name
                    if (-not [string]::IsNullOrWhiteSpace($norm)) {
                        $huntressLookup[$norm] = $orgKey
                    }
                }

                Write-Log     "Huntress: loaded $($huntressOrgs.Count) organizations, $($huntressLookup.Count) unique normalized names." -Severity SUCCESS
                Write-Console "Huntress: loaded $($huntressOrgs.Count) organizations, $($huntressLookup.Count) unique normalized names." -Severity SUCCESS
            }
            catch {
                Write-Log     "Failed to pull Huntress organizations: $_" -Severity ERROR
                Write-Console "Failed to pull Huntress organizations: $_" -Severity ERROR
                Write-Log     'Continuing without Huntress data.'         -Severity WARN
                Write-Console 'Continuing without Huntress data.'         -Severity WARN -Indent 1
                $IsSkipHuntress = $true
            }
        }
        else {
            Write-Log     'Huntress sync skipped (SkipHuntress=true).' -Severity INFO
            Write-Console 'Huntress sync skipped (SkipHuntress=true).' -Severity INFO
        }

        # Safety check: if both data sources died mid-pull, bail
        if ($IsSkipITGlue -and $IsSkipHuntress) {
            Write-Log     'Both ITGlue and Huntress are unavailable. Nothing to sync.' -Severity ERROR
            Write-Console 'Both ITGlue and Huntress are unavailable. Nothing to sync.' -Severity ERROR
            Write-Banner  'SCRIPT FAILED - NO DATA SOURCES' -Color 'Red'
            exit 1
        }

        # Build combined lookup for company-name prefix resolution
        $combinedNormLookup = @{}
        foreach ($k in $itglueLookup.Keys)   { $combinedNormLookup[$k] = $true }
        foreach ($k in $huntressLookup.Keys) { $combinedNormLookup[$k] = $true }

        # ------------------------------------------------------------------
        # PULL DATTORMM SITES
        # ------------------------------------------------------------------
        Write-Section 'DattoRMM: Pull Sites'
        Write-Log     'Pulling all sites from DattoRMM...' -Severity INFO
        Write-Console 'Pulling all sites from DattoRMM...' -Severity INFO

        $dattoSites = $null
        try {
            $dattoSites = Invoke-PaginatedGet -Headers $dattoHeaders -InitialUrl "$dattoBaseUrl/api/v2/account/sites" -PaginationStyle 'Datto' -ItemsProperty 'sites'
            Write-Log     "DattoRMM: loaded $($dattoSites.Count) sites." -Severity SUCCESS
            Write-Console "DattoRMM: loaded $($dattoSites.Count) sites." -Severity SUCCESS
        }
        catch {
            Write-Log     "Failed to pull DattoRMM sites: $_" -Severity ERROR
            Write-Console "Failed to pull DattoRMM sites: $_" -Severity ERROR
            Write-Banner  'SCRIPT FAILED - CANNOT LOAD SITES' -Color 'Red'
            exit 1
        }

        # ------------------------------------------------------------------
        # PROCESS EACH SITE
        # ------------------------------------------------------------------
        Write-Section 'Process Sites'

        $results        = New-Object -TypeName 'System.Collections.Generic.List[hashtable]'
        $writeErrors    = 0
        $skippedCurrent = 0

        foreach ($site in $dattoSites) {
            $currentSiteName = $site.name
            $siteUid         = $site.uid

            # Skip Datto's meta-site for deleted devices (exact match, not prefix)
            if ($currentSiteName -eq 'Deleted Devices') {
                continue
            }

            $companyName = Resolve-CompanyName -SiteName $currentSiteName -NormalizedLookup $combinedNormLookup
            $companyNorm = Get-NormalizedName -Name $companyName

            $itgOrgId        = $null
            $huntressOrgKey  = $null
            $itgMatched      = $false
            $huntressMatched = $false

            if (-not $IsSkipITGlue -and $itglueLookup.ContainsKey($companyNorm)) {
                $itgOrgId   = $itglueLookup[$companyNorm]
                $itgMatched = $true
            }

            if (-not $IsSkipHuntress -and $huntressLookup.ContainsKey($companyNorm)) {
                $huntressOrgKey  = $huntressLookup[$companyNorm]
                $huntressMatched = $true
            }

            $result = @{
                SiteName        = $currentSiteName
                SiteUid         = $siteUid
                CompanyName     = $companyName
                ITGMatched      = $itgMatched
                HuntressMatched = $huntressMatched
                ITGOrgId        = $itgOrgId
                HuntressOrgKey  = $huntressOrgKey
                ITGWritten      = $false
                HuntressWritten = $false
            }

            # Fetch existing site variables once per site (single GET).
            # Used for idempotency checks on both variables below.
            # On fetch failure, Get-DattoSiteVariables logs a WARN and returns
            # an empty hashtable, causing the script to write unconditionally.
            $existingVars = @{}
            if (-not $IsReportOnly) {
                $existingVars = Get-DattoSiteVariables -BaseUrl $dattoBaseUrl -Headers $dattoHeaders `
                                                       -SiteUid $siteUid -SiteLabel $currentSiteName
            }

            # ------------------------------------------------------------------
            # ITGlue variable — four outcomes, all logged via Write-VerboseLog
            # ------------------------------------------------------------------
            if (-not $IsSkipITGlue) {
                if ($itgMatched) {
                    if ($IsReportOnly) {
                        Write-VerboseLog "[SKIPPED-REPORT]   ITGOrgKey = $itgOrgId  |  '$currentSiteName'" -Severity INFO -Indent 1
                        $result['ITGWritten'] = $true
                    }
                    elseif (("$($existingVars['ITGOrgKey'])").Trim() -eq ("$itgOrgId").Trim()) {
                        # Type-safe comparison: coerce both sides to trimmed strings.
                        # Guards against ITGlue id surfacing as int vs string, and
                        # incidental whitespace in DattoRMM variable GET responses.
                        Write-VerboseLog "[SKIPPED-CURRENT]  ITGOrgKey = $itgOrgId  |  '$currentSiteName'" -Severity INFO -Indent 1
                        $skippedCurrent++
                        $result['ITGWritten'] = $true
                    }
                    else {
                        $ok = Invoke-ThrottledWrite -BaseUrl $dattoBaseUrl -Headers $dattoHeaders `
                                                    -SiteUid $siteUid -VariableName 'ITGOrgKey' `
                                                    -VariableValue $itgOrgId -SiteLabel $currentSiteName
                        if ($ok) {
                            Write-VerboseLog "[WROTE]            ITGOrgKey = $itgOrgId  |  '$currentSiteName'" -Severity SUCCESS -Indent 1
                            $result['ITGWritten'] = $true
                        }
                        else {
                            $writeErrors++
                        }
                    }
                }
                else {
                    Write-VerboseLog "[SKIPPED-NO-MATCH] ITGOrgKey              |  '$currentSiteName' (parsed: '$companyName')" -Severity INFO -Indent 1
                }
            }

            # ------------------------------------------------------------------
            # Huntress variable — four outcomes, all logged via Write-VerboseLog
            # ------------------------------------------------------------------
            if (-not $IsSkipHuntress) {
                if ($huntressMatched) {
                    if ($IsReportOnly) {
                        Write-VerboseLog "[SKIPPED-REPORT]   HUNTRESS_ORG_KEY = $huntressOrgKey  |  '$currentSiteName'" -Severity INFO -Indent 1
                        $result['HuntressWritten'] = $true
                    }
                    elseif (("$($existingVars['HUNTRESS_ORG_KEY'])").Trim() -eq ("$huntressOrgKey").Trim()) {
                        # Type-safe comparison: same pattern as ITGOrgKey above.
                        Write-VerboseLog "[SKIPPED-CURRENT]  HUNTRESS_ORG_KEY = $huntressOrgKey  |  '$currentSiteName'" -Severity INFO -Indent 1
                        $skippedCurrent++
                        $result['HuntressWritten'] = $true
                    }
                    else {
                        $ok = Invoke-ThrottledWrite -BaseUrl $dattoBaseUrl -Headers $dattoHeaders `
                                                    -SiteUid $siteUid -VariableName 'HUNTRESS_ORG_KEY' `
                                                    -VariableValue $huntressOrgKey -SiteLabel $currentSiteName
                        if ($ok) {
                            Write-VerboseLog "[WROTE]            HUNTRESS_ORG_KEY = $huntressOrgKey  |  '$currentSiteName'" -Severity SUCCESS -Indent 1
                            $result['HuntressWritten'] = $true
                        }
                        else {
                            $writeErrors++
                        }
                    }
                }
                else {
                    Write-VerboseLog "[SKIPPED-NO-MATCH] HUNTRESS_ORG_KEY       |  '$currentSiteName' (parsed: '$companyName')" -Severity INFO -Indent 1
                }
            }

            $results.Add($result)
        }

        # ------------------------------------------------------------------
        # SUMMARY
        # ------------------------------------------------------------------
        Write-Section 'Summary'

        $totalSites      = $results.Count
        $itgMatches      = ($results | Where-Object { $_.ITGMatched }).Count
        $huntressMatches = ($results | Where-Object { $_.HuntressMatched }).Count
        $itgWritten      = ($results | Where-Object { $_.ITGWritten }).Count
        $huntressWritten = ($results | Where-Object { $_.HuntressWritten }).Count
        $modeDisplay     = if ($IsReportOnly) { 'REPORT-ONLY (no changes made)' } else { 'WRITE MODE (changes committed)' }

        Write-Log     '------------------------------------------------------------' -Severity INFO
        Write-Log     "SUMMARY: $totalSites sites processed. Mode: $modeDisplay" -Severity INFO
        Write-Console "SUMMARY: $totalSites sites processed. Mode: $modeDisplay" -Severity INFO

        if (-not $IsSkipITGlue) {
            Write-Log     "  ITGlue:   $itgMatches matched, $itgWritten written/would-write." -Severity INFO
            Write-Console "ITGlue:   $itgMatches matched, $itgWritten written/would-write." -Severity INFO -Indent 1
        }
        if (-not $IsSkipHuntress) {
            Write-Log     "  Huntress: $huntressMatches matched, $huntressWritten written/would-write." -Severity INFO
            Write-Console "Huntress: $huntressMatches matched, $huntressWritten written/would-write." -Severity INFO -Indent 1
        }
        if (-not $IsReportOnly -and $skippedCurrent -gt 0) {
            Write-Log     "  Skipped (already current): $skippedCurrent variable(s)." -Severity INFO
            Write-Console "Skipped (already current): $skippedCurrent variable(s)." -Severity INFO -Indent 1
        }
        if ($writeErrors -gt 0) {
            Write-Log     "  Write errors: $writeErrors (see WARN entries above)." -Severity WARN
            Write-Console "Write errors: $writeErrors (see WARN entries above)." -Severity WARN -Indent 1
        }

        $itgUnmatched      = $results | Where-Object { (-not $IsSkipITGlue)   -and (-not $_.ITGMatched) }
        $huntressUnmatched = $results | Where-Object { (-not $IsSkipHuntress) -and (-not $_.HuntressMatched) }

        if ($itgUnmatched.Count -gt 0) {
            Write-Log     "ITGlue unmatched sites ($($itgUnmatched.Count)):" -Severity WARN
            Write-Console "ITGlue unmatched sites ($($itgUnmatched.Count)):" -Severity WARN
            foreach ($r in $itgUnmatched) {
                Write-Log     "  [ITG-UNMATCHED] '$($r.SiteName)' (parsed company: '$($r.CompanyName)')" -Severity WARN
                Write-Console "[ITG-UNMATCHED] '$($r.SiteName)' (parsed company: '$($r.CompanyName)')" -Severity WARN -Indent 1
            }
        }

        if ($huntressUnmatched.Count -gt 0) {
            Write-Log     "Huntress unmatched sites ($($huntressUnmatched.Count)):" -Severity WARN
            Write-Console "Huntress unmatched sites ($($huntressUnmatched.Count)):" -Severity WARN
            foreach ($r in $huntressUnmatched) {
                Write-Log     "  [HUNTRESS-UNMATCHED] '$($r.SiteName)' (parsed company: '$($r.CompanyName)')" -Severity WARN
                Write-Console "[HUNTRESS-UNMATCHED] '$($r.SiteName)' (parsed company: '$($r.CompanyName)')" -Severity WARN -Indent 1
            }
        }

        # Post-condition flag: if any unmatched sites OR any write errors, emit the
        # configured warning string so the DattoRMM job result can surface as orange.
        if ($itgUnmatched.Count -gt 0 -or $huntressUnmatched.Count -gt 0 -or $writeErrors -gt 0) {
            Write-Log "WARNING: Run completed with unmatched sites or write errors — review log for details." -Severity WARN
        }

        Write-Log "Script completed successfully." -Severity SUCCESS
        Write-Banner "COMPLETED SUCCESSFULLY" -Color "Green"

        exit 0

    }
    catch {
        Write-Log     "Unhandled exception: $_"             -Severity ERROR
        Write-Log     "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Console "Unhandled exception: $_"             -Severity ERROR
        Write-Banner  "SCRIPT FAILED" -Color "Red"

        exit 1
    }

} # End function Sync-OrgKeysToSiteVariables

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    DattoApiUrl       = $DattoApiUrl
    DattoApiKey       = $DattoApiKey
    DattoApiSecret    = $DattoApiSecret
    ITGlueUrl         = $ITGlueUrl
    ITGlueAPIKey      = $ITGlueAPIKey
    HuntressApiKey    = $HuntressApiKey
    HuntressApiSecret = $HuntressApiSecret
    ReportOnly        = $ReportOnly
    SkipITGlue        = $SkipITGlue
    SkipHuntress      = $SkipHuntress
    VerboseOutput     = $VerboseOutput
    SiteName          = $SiteName
    Hostname          = $Hostname
}

Sync-OrgKeysToSiteVariables @ScriptParams
