#Requires -Version 5.1

<#
.SYNOPSIS
    Collects connected monitor information from the local machine and publishes it to a
    DattoRMM User-Defined Field.

.DESCRIPTION
    Queries WmiMonitorID and WmiMonitorConnectionParams (root/wmi) to build a list of
    currently connected monitors, including manufacturer, model, and connection type
    (VGA, HDMI, DisplayPort, etc.). The resulting summary is written to the script log,
    the console (dual-output pattern), and published to the DattoRMM device via a
    registry-backed User-Defined Field (Custom<N> under HKLM:\SOFTWARE\CentraStage).

    The registry write is idempotent — the current UDF value is read first and only
    overwritten if it differs from the newly collected value, avoiding unnecessary writes
    on unchanged systems.

    DattoRMM UDF values have a 255-character limit. If the collected monitor summary
    exceeds this limit, it is truncated and a WARNING is logged so the condition is
    visible in the job log (and can be used as a DattoRMM Post-Condition match string).

.PARAMETER UDFNumber
    The DattoRMM User-Defined Field number (1-300) to publish the monitor summary to.
    Resolved via the standard fallback chain: DattoRMM environment variable ($env:UDFNumber)
    -> PowerShell parameter -> default value (50).

.EXAMPLE
    .\Get-MonitorInfo.ps1
    Runs with the default UDF number (50).

.EXAMPLE
    .\Get-MonitorInfo.ps1 -UDFNumber 12
    Publishes the monitor summary to UDF 12 instead of the default.

.NOTES
    Script Name  : Get-MonitorInfo.ps1
    Author       : Steven Peterson
    Contributors : Josh Britton
    Modified By  : John
    Version      : v2.0.0.000
    PS Minimum   : 5.1
    Run Context  : SYSTEM (DattoRMM agent) or interactive Domain Admin

    Exit Codes:
      0 = Success
      1 = Runtime failure  - script started but encountered an error during execution
      2 = Fatal pre-flight failure - invalid parameters, execution cannot proceed

    Registry mechanism:
      DattoRMM UDFs are populated by writing a string value named "Custom<N>" under
      HKLM:\SOFTWARE\CentraStage. The agent reads this value and syncs it to the
      platform on the next check-in/audit; the registry value is then cleared by the
      agent. This is expected behavior, not a bug.

    .CHANGELOG
    v2.0.0.000 - 2026-07-02 - Josh Britton
        - Modernized to Databranch Script Library standard (structure, logging, docs).
        - Added DattoRMM UDF publishing via Custom<N> registry write.
        - Added idempotent read-before-write for the UDF registry value.
        - Added 255-character UDF value truncation safeguard with WARN logging.
        - Added dual Write-Log / Write-Console output, Initialize-Logging with
          10-file rotation, and standard log header.
        - Replaced deprecated `gwmi` / `?` aliases with Get-CimInstance / Where-Object.
        - Added explicit exit codes (0/1/2) and pre-flight parameter validation.
    v1.0 - 2024-09-23 - Josh Britton
        - Moved script to Github folder and wrapped in function for use with CW Automate.
        - Added Get-Date field for last-run tracking.
    v1.0 (original) - Steven Peterson
        - Initial script.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$UDFNumber = $(if ($env:UDFNumber) { $env:UDFNumber } else { '50' })
)

function Get-MonitorInfo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$UDFNumber = '50'
    )

    # ==============================================================================
    # SCRIPT METADATA
    # ==============================================================================
    $ScriptName    = 'Get-MonitorInfo'
    $ScriptVersion = 'v2.0.0.000'

    # ==============================================================================
    # LOGGING - INTERNAL FUNCTIONS
    # ==============================================================================
    function Initialize-Logging {
        param (
            [Parameter(Mandatory = $true)]
            [string]$ScriptName
        )

        $logRoot = "C:\Databranch\ScriptLogs\$ScriptName"

        if (-not (Test-Path -Path $logRoot)) {
            New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
        }

        $logFile = Join-Path -Path $logRoot -ChildPath "${ScriptName}_$(Get-Date -Format 'yyyy-MM-dd').log"

        # Rotate - keep the 10 most recent log files, purge anything older
        $existingLogs = Get-ChildItem -Path $logRoot -Filter "${ScriptName}_*.log" -File -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending

        if ($existingLogs.Count -gt 10) {
            $existingLogs | Select-Object -Skip 10 | ForEach-Object {
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }

        return $logFile
    }

    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'SUCCESS', 'DEBUG', 'WARN', 'ERROR')]
            [string]$Severity = 'INFO'
        )

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line      = "[$timestamp] [$Severity] $Message"

        # Structured log - captured by DattoRMM via stdout/stderr, and written to the log file
        switch ($Severity) {
            'ERROR' { Write-Error   -Message $line -ErrorAction Continue }
            'WARN'  { Write-Warning -Message $line }
            default { Write-Output  $line }
        }

        Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue
    }

    function Write-Console {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'SUCCESS', 'DEBUG', 'WARN', 'ERROR')]
            [string]$Severity = 'INFO',

            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )

        $color = switch ($Severity) {
            'INFO'    { 'Cyan' }
            'SUCCESS' { 'Green' }
            'DEBUG'   { 'Magenta' }
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            default   { 'White' }
        }

        $prefix = ' ' * ($Indent * 2) + "[$Severity]"

        # Presentation layer only - Write-Host is suppressed automatically in the
        # DattoRMM agent context and never interferes with the structured log above.
        Write-Host "$prefix $Message" -ForegroundColor $color
    }

    # ==============================================================================
    # INITIALIZE LOGGING
    # ==============================================================================
    $script:LogFile = Initialize-Logging -ScriptName $ScriptName

    # ==============================================================================
    # PRE-FLIGHT PARAMETER VALIDATION
    # ==============================================================================
    $udfNumberInt = 0
    $isValidUdf   = [int]::TryParse($UDFNumber.Trim(), [ref]$udfNumberInt)

    if (-not $isValidUdf -or $udfNumberInt -lt 1 -or $udfNumberInt -gt 300) {
        Write-Log     "Fatal pre-flight failure: UDFNumber '$UDFNumber' is not a valid integer between 1 and 300." -Severity ERROR
        Write-Console "Fatal pre-flight failure: UDFNumber '$UDFNumber' is not a valid integer between 1 and 300." -Severity ERROR
        exit 2
    }

    # ==============================================================================
    # STANDARD LOG HEADER
    # ==============================================================================
    $siteName = if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { 'UnknownSite' }
    $hostName = if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME }
    $runAs    = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $mode     = "COLLECT & PUBLISH (UDF $udfNumberInt)"

    Write-Log "===== $ScriptName $ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $siteName"    -Severity INFO
    Write-Log "Hostname : $hostName"    -Severity INFO
    Write-Log "Run As   : $runAs"       -Severity INFO
    Write-Log "Mode     : $mode"        -Severity INFO
    Write-Log "Log File : $script:LogFile" -Severity INFO

    Write-Console "===== $ScriptName $ScriptVersion =====" -Severity INFO
    Write-Console "Site     : $siteName" -Severity INFO
    Write-Console "Hostname : $hostName" -Severity INFO
    Write-Console "Mode     : $mode"     -Severity INFO

    # ==============================================================================
    # MONITOR OUTPUT-TECHNOLOGY LOOKUP TABLE
    # Reference: https://www.magnumdb.com/search?q=parent:D3DKMDT_VIDEO_OUTPUT_TECHNOLOGY
    # ==============================================================================
    $adapterTypes = @{
        '-2'          = 'Unknown'
        '-1'          = 'Unknown'
        '0'           = 'VGA'
        '1'           = 'S-Video'
        '2'           = 'Composite'
        '3'           = 'Component'
        '4'           = 'DVI'
        '5'           = 'HDMI'
        '6'           = 'LVDS'
        '8'           = 'D-Jpn'
        '9'           = 'SDI'
        '10'          = 'DisplayPort (external)'
        '11'          = 'DisplayPort (internal)'
        '12'          = 'Unified Display Interface'
        '13'          = 'Unified Display Interface (embedded)'
        '14'          = 'SDTV dongle'
        '15'          = 'Miracast'
        '16'          = 'Internal'
        '2147483648'  = 'Internal'
    }

    try {
        # ==========================================================================
        # COLLECT MONITOR DATA
        # ==========================================================================
        Write-Log "Querying WmiMonitorID and WmiMonitorConnectionParams (root/wmi)." -Severity DEBUG

        $monitors    = Get-CimInstance -ClassName WmiMonitorID -Namespace root/wmi -ErrorAction Stop
        $connections = Get-CimInstance -ClassName WmiMonitorConnectionParams -Namespace root/wmi -ErrorAction Stop

        Write-Log "Found $($monitors.Count) monitor instance(s)." -Severity DEBUG

        $monitorEntries = New-Object -TypeName 'System.Collections.Generic.List[string]'

        foreach ($monitor in $monitors) {
            $manufacturer = $monitor.ManufacturerName
            $friendlyName = $monitor.UserFriendlyName

            $connection = $connections | Where-Object { $_.InstanceName -eq $monitor.InstanceName }
            $connectionTypeCode = $connection.VideoOutputTechnology

            # Preserve the proven filtering approach from the original script: filtering a
            # WMI byte array with -ne 0 strips trailing null padding while keeping the
            # array in a form GetString() accepts. Piping through Where-Object here would
            # coerce the array to Object[] and break the GetString(Byte[]) overload.
            if ($null -ne $manufacturer) {
                $manufacturer = [System.Text.Encoding]::ASCII.GetString($manufacturer -ne 0)
            }
            if ($null -ne $friendlyName) {
                $friendlyName = [System.Text.Encoding]::ASCII.GetString($friendlyName -ne 0)
            }

            $connectionType = $adapterTypes["$connectionTypeCode"]
            if ($null -eq $connectionType) { $connectionType = 'Unknown' }

            if (($null -ne $manufacturer) -or ($null -ne $friendlyName)) {
                $entry = "$manufacturer $friendlyName ($connectionType)".Trim()
                $monitorEntries.Add($entry)
                Write-Log     "Detected monitor: $entry" -Severity DEBUG
                Write-Console "Detected monitor: $entry" -Severity INFO -Indent 1
            }
        }

        #Get Date for last run tracking that can be appended to the UDF value if desired. This is not required for the UDF write, but can be useful for tracking when the script was last run.

        $Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        $monitorSummary = if ($monitorEntries.Count -gt 0) {
            [string]::Join(' | ', $monitorEntries) + " -- $Date"
        }
        else {
            "'None Found' -- $Date"
        }

        Write-Log     "Monitor summary: $monitorSummary" -Severity INFO
        Write-Console "Monitor summary: $monitorSummary" -Severity SUCCESS

        # ==========================================================================
        # ENFORCE 255-CHARACTER UDF LIMIT
        # ==========================================================================
        if ($monitorSummary.Length -gt 255) {
            $originalLength = $monitorSummary.Length
            $monitorSummary = $monitorSummary.Substring(0, 255)
            Write-Log     "WARNING: Monitor summary was $originalLength characters and exceeded the 255-character DattoRMM UDF limit. Value truncated to 255 characters." -Severity WARN
            Write-Console "Monitor summary truncated from $originalLength to 255 characters (UDF limit)." -Severity WARN
        }

        # ==========================================================================
        # PUBLISH TO DATTORMM UDF (IDEMPOTENT REGISTRY WRITE)
        # ==========================================================================
        $regPath  = 'HKLM:\SOFTWARE\CentraStage'
        $regName  = "Custom$udfNumberInt"

        Write-Log "Reading current value of $regName under $regPath before write." -Severity DEBUG

        $currentValue = $null
        if (Test-Path -Path $regPath) {
            $existingProperty = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
            if ($existingProperty) {
                $currentValue = $existingProperty.$regName
            }
        }
        else {
            Write-Log "Registry path $regPath does not exist. Creating it." -Severity DEBUG
            New-Item -Path $regPath -Force | Out-Null
        }

        if ($currentValue -eq $monitorSummary) {
            Write-Log     "[SKIPPED-CURRENT] UDF $udfNumberInt ($regName) already matches the current monitor summary. No write performed." -Severity INFO
            Write-Console "[SKIPPED-CURRENT] UDF $udfNumberInt already up to date." -Severity INFO
        }
        else {
            Write-Log "Writing $regName to $regPath." -Severity DEBUG
            New-ItemProperty -Path $regPath -Name $regName -PropertyType String -Value $monitorSummary -Force | Out-Null
            Write-Log     "[WROTE] UDF $udfNumberInt ($regName) updated." -Severity SUCCESS
            Write-Console "[WROTE] UDF $udfNumberInt updated." -Severity SUCCESS
        }

        Write-Log     "$ScriptName completed successfully." -Severity SUCCESS
        Write-Console "$ScriptName completed successfully." -Severity SUCCESS

        exit 0
    }
    catch {
        Write-Log     "Runtime failure: $($_.Exception.Message)" -Severity ERROR
        Write-Console "Runtime failure: $($_.Exception.Message)" -Severity ERROR
        exit 1
    }
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$Params = @{
    UDFNumber = $UDFNumber
}
Get-MonitorInfo @Params