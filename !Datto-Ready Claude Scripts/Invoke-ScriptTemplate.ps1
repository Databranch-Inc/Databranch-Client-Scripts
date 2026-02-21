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
    Version        : 1.1.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-02-20
    Last Modified  : 2026-02-21
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM or Domain Admin (note which applies)
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : All clients / Client-specific (note which applies)

    Exit Codes:
        0  - Success
        1  - General failure
        2  - (Add additional exit codes and meanings as needed)

    Output Design:
        Write-Log     - Structured [timestamp][SEVERITY] output to log file AND
                        DattoRMM stdout. Always verbose. No color.
        Write-Console - Human-friendly colored console output for manual/interactive
                        runs. Uses Write-Host (display stream only). Suppressed in
                        DattoRMM agent context automatically.

.CHANGELOG
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
# PARAMETERS
# Supports both DattoRMM environment variable input (automated) and standard
# PowerShell parameter input (manual/interactive). DattoRMM env vars take
# precedence if present; otherwise falls back to passed parameters or defaults.
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ExampleParam = $(if ($env:ExampleParam) { $env:ExampleParam } else { "DefaultValue" }),

    [Parameter(Mandatory = $false)]
    [string]$AnotherParam = $(if ($env:AnotherParam) { $env:AnotherParam } else { "" }),

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
    $ScriptVersion = "1.1.0.0"
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
