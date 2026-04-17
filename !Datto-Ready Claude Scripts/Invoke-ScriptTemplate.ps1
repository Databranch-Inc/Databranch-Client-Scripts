#Requires -Version 5.1
<#
.SYNOPSIS
    Brief one-line description of what this script does.

.DESCRIPTION
    Full description of the script's purpose, scope, and behavior.
    Include any important notes about how it works, what it touches,
    and any dependencies or prerequisites.

.PARAMETER ExampleParam
    Description of this parameter. Note if it is required or optional,
    what values are acceptable, and what the default is if any.

.PARAMETER AnotherParam
    Description of this parameter.

.EXAMPLE
    .\Invoke-ScriptTemplate.ps1 -ExampleParam "Value" -AnotherParam "Value"
    Description of what this example does.

.EXAMPLE
    .\Invoke-ScriptTemplate.ps1 -ExampleParam "Value"
    Description of what this example does using only required parameters.

.NOTES
    File Name      : Invoke-ScriptTemplate.ps1
    Version        : 1.4.0.0
    Author         : <Author Name>
    Contributors   :
    Company        : Databranch
    Created        : 2026-02-20
    Last Modified  : 2026-04-16
    Modified By    : <Name>

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
        Write-Log     - Structured [timestamp][SEVERITY] output to log file AND
                        DattoRMM stdout. Always verbose. No color.
        Write-Console - Human-friendly colored console output for manual/interactive
                        runs. Uses Write-Host (display stream only). Suppressed in
                        DattoRMM agent context automatically.

.CHANGELOG
    v1.4.0.0 - 2026-04-16 - Sam Kirsch
        - Added TLS 1.2 enforcement block between help block and parameters.
          PowerShell 5.1 defaults to TLS 1.0/1.1 on older Windows builds;
          IT Glue and Microsoft Graph/Azure AD both require TLS 1.2 minimum.

    v1.3.0.0 - 2026-04-16 - Sam Kirsch
        - Expanded DattoRMM built-in variable comments (full CS_ variable list)
        - Added Boolean input variable gotcha to parameter comments and script
          logic reference block (DattoRMM booleans arrive as strings "true"/"false";
          never cast to [bool] or evaluate as truthy — always use -eq 'true')
        - Added Set-UdfValue helper function for writing data back to DattoRMM UDFs
          via HKLM:\SOFTWARE\CentraStage registry path
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
        - Dual-output pattern: structured log/stdout via Write-Log,
          presentation layer via Write-Console (Write-Host, display stream only)
        - Updated main execution block to demonstrate dual-output usage
        - Added Output Design notes to .NOTES block

    v1.0.1.0 - 2026-02-20 - Sam Kirsch
        - Added DEBUG severity level to Write-Log
        - All log levels always written (verbose logging by default)
        - Updated company name to Databranch

    v1.0.0.0 - 2026-02-20 - Sam Kirsch
        - Initial release
#>

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# PowerShell 5.1 on older Windows (Server 2012 R2, early Win10 builds) defaults
# to TLS 1.0/1.1 for web requests. Both the IT Glue API and Microsoft Graph/
# Azure AD token endpoints require TLS 1.2 and will reject older connections
# with errors that look like generic network failures. Force TLS 1.2 explicitly
# at the top of any script that makes HTTPS REST calls.
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
# BOOLEAN INPUT VARIABLES — CRITICAL GOTCHA:
#   DattoRMM Boolean component variables arrive as the STRING "true" or "false".
#   NEVER evaluate them as [bool] or test truthiness directly — any non-empty
#   string (including "false") evaluates to $true in PowerShell.
#
#   WRONG:  if ($env:EnableFeature) { ... }           # always true when set
#   WRONG:  if ([bool]$env:EnableFeature) { ... }     # always true even for "false"
#   CORRECT: if ($env:EnableFeature -eq 'true') { ... }
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ExampleParam = $(if ($env:ExampleParam) { $env:ExampleParam } else { "DefaultValue" }),

    [Parameter(Mandatory = $false)]
    [string]$AnotherParam = $(if ($env:AnotherParam) { $env:AnotherParam } else { "" }),

    # Example Boolean input variable — always compare as string, never cast to [bool]
    # [Parameter(Mandatory = $false)]
    # [string]$EnableFeature = $(if ($env:EnableFeature) { $env:EnableFeature } else { 'false' }),
    # Usage: if ($EnableFeature -eq 'true') { ... }

    # DattoRMM built-in variables (auto-populated by Datto, no need to define in component)
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# MASTER FUNCTION
# Named to match the file. Uses an approved PowerShell verb.
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
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Invoke-ScriptTemplate"
    $ScriptVersion = "1.4.0.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

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

        # Write to stdout — captured by DattoRMM, pipeline, and transcript
        switch ($Severity) {
            "INFO"    { Write-Output  $LogEntry }
            "WARN"    { Write-Warning $LogEntry }
            "ERROR"   { Write-Error   $LogEntry -ErrorAction Continue }
            "SUCCESS" { Write-Output  $LogEntry }
            "DEBUG"   { Write-Output  $LogEntry }
        }

        # Write to log file — always
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
    # CONSOLE PRESENTATION HELPERS
    # Write-Banner, Write-Section, Write-Separator — for structured, readable
    # console output during interactive runs. All use Write-Host (display stream
    # only). Not captured by DattoRMM, pipeline, or transcripts.
    # ==========================================================================

    # Write-Banner — full-width start/end banner. Use at script open/close
    # and for major milestone announcements.
    #
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
        Write-Host $Line          -ForegroundColor $Color
        Write-Host "  $Title"    -ForegroundColor White
        Write-Host $Line          -ForegroundColor $Color
        Write-Host ""
    }

    # Write-Section — lightweight section header within a script run.
    # Use to introduce each logical phase of execution.
    #
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
    # Use within sections to separate clusters of related output.
    #
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
    # Writes a value to a DattoRMM UDF slot by setting the corresponding
    # registry key. The Datto agent syncs the value to the platform and then
    # deletes the registry entry automatically.
    #
    # Parameters:
    #   -Slot  : UDF number 1-30 (maps to Custom1-Custom30 in registry)
    #   -Value : String value to write (max 255 characters)
    #
    # Notes:
    #   - Do NOT write credentials or sensitive data to UDFs — they are
    #     visible in plain text in the Datto RMM portal.
    #   - UDF 1 is reserved by Ransomware Detection if that feature is
    #     enabled on the account. Avoid Slot 1 on endpoints where it applies.
    #   - Runs silently; logs a warning if the write fails but does not throw.
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

        $RegPath  = 'HKLM:\SOFTWARE\CentraStage'
        $RegName  = "Custom$Slot"

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

        # Rotate — keep only the $MaxLogFiles most recent log files
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
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    # ------------------------------------------------------------------
    # Script startup — structured log header + console banner
    # Write-Log handles DattoRMM/file. Write-Banner/Console handles display.
    # ------------------------------------------------------------------
    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName"                    -Severity INFO
    Write-Log "Hostname : $Hostname"                    -Severity INFO
    Write-Log "Run As   : $RunAs"                       -Severity INFO
    Write-Log "Params   : ExampleParam='$ExampleParam' | AnotherParam='$AnotherParam'" -Severity INFO
    Write-Log "Log File : $LogFile"                     -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site     : $SiteName"  -Severity PLAIN
    Write-Console "Hostname : $Hostname"  -Severity PLAIN
    Write-Console "Run As   : $RunAs"     -Severity PLAIN
    Write-Console "Log File : $LogFile"   -Severity PLAIN
    Write-Separator

    try {

        # ------------------------------------------------------------------
        # PRE-FLIGHT VALIDATION
        # Check all required parameters before doing any real work.
        # Use exit 2 for fatal startup failures so DattoRMM can distinguish
        # "script never ran" from "script ran but hit errors".
        #
        # Pattern:
        #   $MissingParams = @()
        #   if (-not $RequiredParam) { $MissingParams += 'RequiredParam' }
        #   if ($MissingParams.Count -gt 0) {
        #       foreach ($P in $MissingParams) {
        #           Write-Log "Missing required parameter: $P" -Severity ERROR
        #           Write-Console "Missing required parameter: $P" -Severity ERROR
        #       }
        #       Write-Banner 'FATAL - MISSING PARAMETERS' -Color 'Red'
        #       exit 2
        #   }
        # ------------------------------------------------------------------

        # ------------------------------------------------------------------
        # YOUR SCRIPT LOGIC GOES HERE
        #
        # Dual-output pattern — pair Write-Log with Write-Console:
        #
        #   Write-Section "Phase Name"
        #   Write-Log     "Starting phase..."   -Severity INFO
        #   Write-Console "Starting phase..."   -Severity INFO
        #
        #   $result = Some-Command -Param $ExampleParam
        #
        #   Write-Log     "Result: $result"     -Severity SUCCESS
        #   Write-Console "Result: $result"     -Severity SUCCESS
        #
        #   # Sub-items use -Indent on the console side only:
        #   Write-Log     "  Detail: $detail"   -Severity DEBUG
        #   Write-Console "Detail: $detail"     -Severity DEBUG -Indent 1
        #
        # Write-Log  -> goes to log file + DattoRMM stdout (always)
        # Write-Console -> goes to terminal display only (interactive runs)
        #
        # DATTORMM BOOLEAN INPUT VARIABLES:
        #   Booleans from DattoRMM component vars arrive as strings "true"/"false".
        #   Any non-empty string is truthy in PowerShell — including the string "false".
        #   WRONG:   if ($EnableFeature) { ... }           # always true when set
        #   WRONG:   if ([bool]$EnableFeature) { ... }     # always true even for "false"
        #   CORRECT: if ($EnableFeature -eq 'true') { ... }
        #
        # WRITING TO DATTORMM UDFs:
        #   Use Set-UdfValue to push data back to the platform (e.g. audit results).
        #   The agent syncs the registry value automatically after the script exits.
        #   Values are limited to 255 characters. Do not store secrets in UDFs.
        #   Example:
        #       Set-UdfValue -Slot 5 -Value "Audit completed: 42 users found"
        #
        # POST-CONDITIONS (Warning Text):
        #   DattoRMM can scan stdout for a configured string and flag the job as
        #   orange "Warning" status — independent of exit code. This is useful for
        #   partial-success states. Configure the match string in the component's
        #   Post-Condition field (case-sensitive). To trigger it from a script,
        #   include the exact string in a Write-Log call:
        #       Write-Log "WARNING: Some mailboxes could not be reached." -Severity WARN
        #   Then configure "WARNING:" as the Post-Condition match string.
        #
        # PS 5.1 COMPATIBILITY REMINDERS:
        #   - Use New-Object instead of ::new()
        #       CORRECT:  New-Object -TypeName 'System.Collections.Generic.List[PSObject]'
        #       AVOID:    [System.Collections.Generic.List[PSObject]]::new()
        #   - Use explicit index instead of negative index
        #       CORRECT:  $list[$list.Count - 1]
        #       AVOID:    $list[-1]
        #   - No ternary operator — use if/else
        #       CORRECT:  $x = if ($a) { $b } else { $c }
        #       AVOID:    $x = $a ? $b : $c
        #
        # SECRETS / CREDENTIALS:
        #   - Never log secrets, API keys, or passwords via Write-Log
        #   - Null out credential variables immediately after use:
        #       $ClientSecret = $null
        #
        # SUMMARY OUTPUT:
        #   - Never use Format-Table / Format-List for DattoRMM output
        #   - Column-formatted output garbles in the DattoRMM job log viewer
        #   - Write summary data as individual Write-Log lines instead
        # ------------------------------------------------------------------

        # ------------------------------------------------------------------
        # END SCRIPT LOGIC
        # ------------------------------------------------------------------

        Write-Log "Script completed successfully." -Severity SUCCESS

        Write-Banner "COMPLETED SUCCESSFULLY" -Color "Green"

        exit 0

    }
    catch {
        Write-Log "Unhandled exception: $_"             -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR

        Write-Banner "SCRIPT FAILED" -Color "Red"
        Write-Console "Error : $_"   -Severity ERROR

        exit 1
    }

} # End function Invoke-ScriptTemplate

# ==============================================================================
# ENTRY POINT
# Splat parameters cleanly into the master function.
# ==============================================================================
$ScriptParams = @{
    ExampleParam = $ExampleParam
    AnotherParam = $AnotherParam
    SiteName     = $SiteName
    Hostname     = $Hostname
}

Invoke-ScriptTemplate @ScriptParams
