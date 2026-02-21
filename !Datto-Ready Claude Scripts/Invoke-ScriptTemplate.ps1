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
    Version        : 1.0.1.0
    Author         : Sam Kirsch
    Contributors   : 
    Company        : Databranch
    Created        : 2026-02-20
    Last Modified  : 2026-02-20
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM or Domain Admin (note which applies)
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : All clients / Client-specific (note which applies)

    Exit Codes:
        0  - Success
        1  - General failure
        2  - (Add additional exit codes and meanings as needed)

.CHANGELOG
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
    $ScriptVersion = "1.0.1.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
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

        # Write to stdout - all levels always output
        switch ($Severity) {
            "INFO"    { Write-Output  $LogEntry }
            "WARN"    { Write-Warning $LogEntry }
            "ERROR"   { Write-Error   $LogEntry -ErrorAction Continue }
            "SUCCESS" { Write-Output  $LogEntry }
            "DEBUG"   { Write-Output  $LogEntry }
        }

        # Write to log file - all levels always logged
        try {
            Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8
        }
        catch {
            Write-Warning "[$Timestamp] [WARN] Could not write to log file: $_"
        }
    }

    # ==========================================================================
    # LOG SETUP
    # Creates log folder if needed and rotates old log files.
    # ==========================================================================
    function Initialize-Logging {
        # Create log folder if it doesn't exist
        if (-not (Test-Path $LogFolder)) {
            try {
                New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
            }
            catch {
                Write-Warning "Could not create log folder '$LogFolder': $_"
            }
        }

        # Rotate logs - keep only the most recent $MaxLogFiles
        try {
            $ExistingLogs = Get-ChildItem -Path $LogFolder -Filter "$($ScriptName)_*.log" |
                            Sort-Object LastWriteTime -Descending

            if ($ExistingLogs.Count -ge $MaxLogFiles) {
                $ExistingLogs | Select-Object -Skip ($MaxLogFiles - 1) | ForEach-Object {
                    Remove-Item $_.FullName -Force
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

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName" -Severity INFO
    Write-Log "Hostname : $Hostname" -Severity INFO
    Write-Log "Run As   : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)" -Severity INFO
    Write-Log "Params   : ExampleParam='$ExampleParam' | AnotherParam='$AnotherParam'" -Severity INFO
    Write-Log "Log File : $LogFile" -Severity INFO
    Write-Log "Starting execution..." -Severity INFO

    try {

        # ------------------------------------------------------------------
        # YOUR SCRIPT LOGIC GOES HERE
        # ------------------------------------------------------------------

        # Example:
        # Write-Log "Doing something..." -Severity INFO
        # $result = Some-Command -Param $ExampleParam
        # Write-Log "Result: $result" -Severity SUCCESS

        # ------------------------------------------------------------------
        # END SCRIPT LOGIC
        # ------------------------------------------------------------------

        Write-Log "Script completed successfully." -Severity SUCCESS
        exit 0

    }
    catch {
        Write-Log "Unhandled exception: $_" -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
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
