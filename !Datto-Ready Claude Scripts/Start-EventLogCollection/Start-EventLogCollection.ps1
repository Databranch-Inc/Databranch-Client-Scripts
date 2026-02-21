#Requires -Version 5.1
<#
.SYNOPSIS
    Collects Windows Event Log entries from local and remote servers, saving output to CSV files.

.DESCRIPTION
    Combines local and remote Event Log collection into a single script with two operating modes:

    AUTOMATED mode: Discovers all Windows Server machines on the domain automatically using an
    AD query as the primary method, with a ping sweep + OS fingerprinting fallback if AD returns
    no results. Always includes the local machine. Parallel processing is used where available.

    CUSTOM mode: Targets a specific list of servers provided via the -ComputerName parameter.
    Accepts hostnames, FQDNs, and IP addresses in any combination.

    Both modes perform a connectivity pre-check (CIM first, WinRM fallback) before attempting
    collection on each target. Output is written to a timestamped subfolder under C:\Databranch.
    A run summary log is generated alongside the CSV output files.

    Compatible with PowerShell 5.1 (runspaces) and PowerShell 7+ (ForEach-Object -Parallel).
    PS version is detected at runtime; 5.1 compatibility is the primary target.

.PARAMETER Mode
    Operating mode. 'Automated' discovers servers via AD + ping sweep fallback.
    'Custom' targets servers specified in -ComputerName.
    Default: Automated

.PARAMETER ComputerName
    Custom mode only. One or more server names, FQDNs, or IP addresses to target.
    Accepts a PowerShell array or a single comma-separated string (DattoRMM compatible).
    Example: "Server01,Server02,192.168.1.10" or "Server01","Server02"

.PARAMETER Subnets
    Optional. One or more subnets in CIDR notation to use for the ping sweep fallback
    in Automated mode. If not provided, subnets are auto-detected from local network adapters.
    Example: "192.168.1.0/24","10.0.0.0/24"

.PARAMETER DaysBack
    Number of days back to collect Event Log entries. Default: 30

.PARAMETER OutputPath
    Root folder for output. A timestamped subfolder will be created here.
    Default: C:\Databranch

.PARAMETER LogNames
    Event log names to collect from. Default: Application, System

.EXAMPLE
    .\Start-EventLogCollection.ps1
    Runs in Automated mode with all defaults. Discovers all Windows Server machines via AD,
    collects Application and System logs for Critical and Error events over the past 30 days.

.EXAMPLE
    .\Start-EventLogCollection.ps1 -Mode Automated -DaysBack 14 -Subnets "192.168.1.0/24","10.0.5.0/24"
    Automated mode with a 14-day window and explicit subnet overrides for the ping sweep fallback.

.EXAMPLE
    .\Start-EventLogCollection.ps1 -Mode Custom -ComputerName "DC01","FileServer02","192.168.1.50"
    Custom mode targeting three specific servers by name and IP.

.EXAMPLE
    .\Start-EventLogCollection.ps1 -Mode Custom -ComputerName "DC01,FileServer02,AppServer03"
    Custom mode using a comma-separated string (DattoRMM site variable format).

.NOTES
    File Name      : Start-EventLogCollection.ps1
    Version        : 1.1.0.0
    Author         : Josh Britton / Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-02-20
    Last Modified  : 2026-02-21
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
                     ActiveDirectory module (for AD discovery in Automated mode)
                     Network access to target servers (WinRM / RPC / CIM)
    Run Context    : Domain Admin recommended; SYSTEM with delegated rights minimum
    DattoRMM       : Compatible - supports environment variable input for all parameters
    Client Scope   : All clients with Windows Server infrastructure

    Exit Codes:
        0  - Success (all targets collected successfully)
        1  - Partial success (one or more targets failed, but at least one succeeded)
        2  - Complete failure (no targets collected, or fatal error during execution)

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
        - Implemented dual-output pattern throughout: structured log/stdout via
          Write-Log, presentation layer via Write-Console (display stream only)
        - Added rich console output to all phases: startup, discovery, pre-checks,
          collection, and summary
        - Console shows per-server reachability and collection results with
          color-coded SUCCESS/WARN/ERROR severity on each line
        - Run summary console block shows colored tallies  -  green for success,
          amber for partial, red for failures
        - Skipped servers and error details echoed to console in colored output
        - Parallel result log lines now routed through correct severity on flush
        - Added Output Design notes to .NOTES block

    v1.0.1.0 - 2026-02-20 - Sam Kirsch
        - Fixed pipeline pollution in Get-ServersFromAD, Get-LocalSubnets, Get-ServersFromPingSweep
          Write-Log calls inside return-value functions were leaking log strings into $TargetList
          Resolved by redirecting Write-Log output with | Out-Null and using Generic List + unary comma return
        - Fixed Write-Log rejecting empty strings (summary block contains blank lines)
          Changed $Message from Mandatory=$true to Mandatory=$false with [AllowEmptyString()]

    v1.0.0.0 - 2026-02-20 - Sam Kirsch
        - Initial release
        - Merged local collection script (v1.2) and remote collection script (v1.0)
        - Added Automated and Custom modes
        - AD query discovery with ping sweep + CIM/WinRM OS fingerprinting fallback
        - Runtime PS version detection: runspaces (5.1) / ForEach-Object -Parallel (7+)
        - Connectivity pre-check before collection on each target
        - Timestamped output subfolder under C:\Databranch
        - Rich per-server logging with run summary
        - DattoRMM environment variable support for all parameters
        - Exit codes: 0 (success), 1 (partial), 2 (failure)
#>

# ==============================================================================
# PARAMETERS
# Supports DattoRMM environment variable input and standard PowerShell parameters.
# DattoRMM env vars take precedence if present.
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Automated", "Custom")]
    [string]$Mode = $(if ($env:Mode) { $env:Mode } else { "Automated" }),

    [Parameter(Mandatory = $false)]
    [string[]]$ComputerName = $(if ($env:ComputerName) { $env:ComputerName } else { @() }),

    [Parameter(Mandatory = $false)]
    [string[]]$Subnets = $(if ($env:Subnets) { $env:Subnets } else { @() }),

    [Parameter(Mandatory = $false)]
    [int]$DaysBack = $(if ($env:DaysBack) { [int]$env:DaysBack } else { 30 }),

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = $(if ($env:OutputPath) { $env:OutputPath } else { "C:\Databranch" }),

    [Parameter(Mandatory = $false)]
    [string[]]$LogNames = $(if ($env:LogNames) { $env:LogNames -split "," } else { @("Application", "System") }),

    # DattoRMM built-in variables
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Start-EventLogCollection {
    [CmdletBinding()]
    param (
        [string]$Mode,
        [string[]]$ComputerName,
        [string[]]$Subnets,
        [int]$DaysBack,
        [string]$OutputPath,
        [string[]]$LogNames,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName     = "Start-EventLogCollection"
    $ScriptVersion  = "1.1.0.0"
    $RunTimestamp   = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $RunDate        = Get-Date -Format "yyyy-MM-dd"
    $LogRoot        = "C:\Databranch\ScriptLogs"
    $LogFolder      = Join-Path $LogRoot $ScriptName
    $LogFile        = Join-Path $LogFolder "$($ScriptName)_$($RunDate).log"
    $MaxLogFiles    = 10
    $OutputFolder   = Join-Path $OutputPath $RunTimestamp
    $SummaryFile    = Join-Path $OutputFolder "EventLog-Collection-Summary-$RunTimestamp.txt"
    $EventLevels    = @("Critical", "Error")   # Hardcoded per design spec
    $MaxParallel    = 10                        # Max concurrent runspace threads (PS 5.1)

    # ==========================================================================
    # WRITE-LOG  (Structured Output Layer)
    # Writes timestamped, severity-tagged entries to BOTH the log file and
    # DattoRMM stdout. Always verbose  -  all levels always written.
    #
    # Uses Write-Output / Write-Warning / Write-Error (NOT Write-Host) so
    # output is captured by DattoRMM job stdout, pipeline, and transcripts.
    # Do NOT use Write-Host here  -  it would bypass DattoRMM capture.
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

        # Write to stdout  -  captured by DattoRMM, pipeline, and transcript
        switch ($Severity) {
            "INFO"    { Write-Output  $LogEntry }
            "WARN"    { Write-Warning $LogEntry }
            "ERROR"   { Write-Error   $LogEntry -ErrorAction Continue }
            "SUCCESS" { Write-Output  $LogEntry }
            "DEBUG"   { Write-Output  $LogEntry }
        }

        # Write to log file  -  always
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
    # Uses Write-Host  -  writes to the PowerShell display stream ONLY.
    # NOT captured by DattoRMM stdout, pipeline redirection, or transcripts.
    # Safe to call alongside Write-Log  -  the two output streams are independent.
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
    # Write-Banner, Write-Section, Write-Separator  -  for structured, readable
    # console output during interactive runs. All use Write-Host (display stream
    # only). Not captured by DattoRMM, pipeline, or transcripts.
    # ==========================================================================

    # Write-Banner  -  full-width start/end banner. Use at script open/close.
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
        Write-Host $Line       -ForegroundColor $Color
        Write-Host "  $Title"  -ForegroundColor White
        Write-Host $Line       -ForegroundColor $Color
        Write-Host ""
    }

    # Write-Section  -  lightweight section header within a script run.
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

    # Write-Separator  -  thin divider line between logical groups.
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

        # Rotate  -  keep only the $MaxLogFiles most recent log files
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
    # OUTPUT FOLDER SETUP
    # ==========================================================================
    function Initialize-OutputFolder {
        if (-not (Test-Path $OutputFolder)) {
            try {
                New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
                Write-Log     "Output folder created: $OutputFolder" -Severity DEBUG
                Write-Console "Output folder: $OutputFolder"         -Severity DEBUG -Indent 1
            }
            catch {
                Write-Log     "Failed to create output folder '$OutputFolder': $_" -Severity ERROR
                Write-Console "Failed to create output folder: $_"                 -Severity ERROR
                throw
            }
        }
    }

    # ==========================================================================
    # SUBNET HELPERS
    # ==========================================================================
    function Get-LocalSubnets {
        <# Returns list of subnets in CIDR notation from active local adapters #>
        $subnets = [System.Collections.Generic.List[string]]::new()
        try {
            $adapters = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                        Where-Object { $_.IPAddress -notmatch "^(127\.|169\.254\.)" -and $_.PrefixLength -lt 32 }
            foreach ($adapter in $adapters) {
                $subnets.Add("$($adapter.IPAddress)/$($adapter.PrefixLength)")
                Write-Log "Auto-detected subnet: $($adapter.IPAddress)/$($adapter.PrefixLength)" -Severity DEBUG | Out-Null
            }
        }
        catch {
            Write-Log "Could not auto-detect subnets: $_" -Severity WARN | Out-Null
        }
        return ,$subnets
    }

    function Get-SubnetIPs {
        <# Expands a CIDR subnet string to an array of host IP strings #>
        param ([string]$CIDR)
        try {
            $parts      = $CIDR -split "/"
            $baseIP     = $parts[0]
            $prefix     = [int]$parts[1]
            $ipBytes    = [System.Net.IPAddress]::Parse($baseIP).GetAddressBytes()
            [Array]::Reverse($ipBytes)
            $ipInt      = [System.BitConverter]::ToUInt32($ipBytes, 0)
            $mask       = [uint32](0xFFFFFFFF -shl (32 - $prefix))
            $network    = $ipInt -band $mask
            $broadcast  = $network -bor (-bnot $mask -band 0xFFFFFFFF)
            $hostIPs    = @()
            for ($i = $network + 1; $i -lt $broadcast; $i++) {
                $b = [System.BitConverter]::GetBytes([uint32]$i)
                [Array]::Reverse($b)
                $hostIPs += ([System.Net.IPAddress]$b).ToString()
            }
            return $hostIPs
        }
        catch {
            Write-Log "Failed to expand subnet '$CIDR': $_" -Severity WARN
            return @()
        }
    }

    # ==========================================================================
    # SERVER DISCOVERY
    # ==========================================================================
    function Get-ServersFromAD {
        <# Queries AD for computers running Windows Server OS #>
        $servers = [System.Collections.Generic.List[string]]::new()
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            Write-Log     "Querying Active Directory for Windows Server machines..." -Severity INFO | Out-Null
            Write-Console "Querying Active Directory..." -Severity INFO -Indent 1
            $adComputers = Get-ADComputer -Filter { OperatingSystem -like "*Windows Server*" } `
                           -Properties Name, OperatingSystem, Enabled |
                           Where-Object { $_.Enabled -eq $true }
            foreach ($c in $adComputers) { $servers.Add($c.Name) }
            Write-Log     "AD query returned $($servers.Count) Windows Server machine(s)." -Severity INFO | Out-Null
            Write-Console "$($servers.Count) Windows Server machine(s) found in AD." -Severity SUCCESS -Indent 1
        }
        catch {
            Write-Log     "AD query failed: $_" -Severity WARN | Out-Null
            Write-Console "AD query failed: $_" -Severity WARN -Indent 1
        }
        return ,$servers
    }

    function Get-ServersFromPingSweep {
        <# Pings all IPs in provided subnets, then fingerprints responders for Windows Server OS #>
        param ([string[]]$SubnetList)

        Write-Log     "Starting ping sweep across $($SubnetList.Count) subnet(s)..." -Severity INFO | Out-Null
        Write-Console "Sweeping $($SubnetList.Count) subnet(s)  -  this may take a moment..." -Severity INFO -Indent 1

        $allIPs = [System.Collections.Generic.List[string]]::new()
        foreach ($subnet in $SubnetList) {
            $expanded = Get-SubnetIPs -CIDR $subnet
            Write-Log     "Subnet $subnet expanded to $($expanded.Count) host addresses." -Severity DEBUG | Out-Null
            Write-Console "$subnet  -  $($expanded.Count) host addresses" -Severity DEBUG -Indent 2
            foreach ($ip in $expanded) { $allIPs.Add($ip) }
        }

        Write-Log     "Pinging $($allIPs.Count) addresses..." -Severity INFO | Out-Null
        Write-Console "Pinging $($allIPs.Count) addresses..." -Severity INFO -Indent 1

        $liveHosts = [System.Collections.Generic.List[string]]::new()

        $pingJobs = @()
        foreach ($ip in $allIPs) {
            $pingJobs += Start-Job -ScriptBlock {
                param($addr)
                if (Test-Connection -ComputerName $addr -Count 1 -Quiet -ErrorAction SilentlyContinue) {
                    return $addr
                }
            } -ArgumentList $ip
        }
        $pingResults = $pingJobs | Wait-Job | Receive-Job
        $pingJobs    | Remove-Job -Force

        foreach ($r in ($pingResults | Where-Object { $_ })) { $liveHosts.Add($r) }

        Write-Log     "$($liveHosts.Count) host(s) responded to ping." -Severity INFO | Out-Null
        Write-Console "$($liveHosts.Count) host(s) responded to ping." -Severity INFO -Indent 1

        $confirmedServers = [System.Collections.Generic.List[string]]::new()
        foreach ($h in $liveHosts) {
            $osName = $null

            try {
                $cimResult = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $h `
                             -OperationTimeoutSec 10 -ErrorAction Stop
                $osName = $cimResult.Caption
            }
            catch {
                Write-Log "CIM failed for $h, trying WinRM..." -Severity DEBUG | Out-Null
                try {
                    $osName = Invoke-Command -ComputerName $h -ScriptBlock {
                        (Get-CimInstance Win32_OperatingSystem).Caption
                    } -ErrorAction Stop
                }
                catch {
                    Write-Log "WinRM also failed for $h - skipping OS check." -Severity DEBUG | Out-Null
                }
            }

            if ($osName -like "*Windows Server*") {
                Write-Log     "Confirmed Windows Server: $h ($osName)" -Severity DEBUG | Out-Null
                Write-Console "$h  -  $osName" -Severity DEBUG -Indent 2
                $confirmedServers.Add($h)
            }
            elseif ($osName) {
                Write-Log "Skipping $h - not a Windows Server OS ($osName)." -Severity DEBUG | Out-Null
            }
            else {
                Write-Log "Skipping $h - could not determine OS." -Severity DEBUG | Out-Null
            }
        }

        Write-Log     "Ping sweep confirmed $($confirmedServers.Count) Windows Server machine(s)." -Severity INFO | Out-Null
        Write-Console "$($confirmedServers.Count) Windows Server(s) confirmed." -Severity SUCCESS -Indent 1
        return ,$confirmedServers
    }

    # ==========================================================================
    # CONNECTIVITY PRE-CHECK
    # ==========================================================================
    function Test-ServerConnectivity {
        <# Returns $true if server is reachable via CIM or WinRM. Sets $OSName by ref. #>
        param (
            [string]$Server,
            [ref]$OSName
        )

        # Ping first  -  fast fail
        if (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Log     "[$Server] Pre-check FAILED - no ping response." -Severity WARN
            Write-Console "[$Server] No ping response" -Severity WARN -Indent 1
            return $false
        }

        # CIM check
        try {
            $cim = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $Server `
                   -OperationTimeoutSec 15 -ErrorAction Stop
            $OSName.Value = $cim.Caption
            Write-Log     "[$Server] Pre-check OK via CIM ($($cim.Caption))." -Severity DEBUG
            return $true
        }
        catch {
            Write-Log "[$Server] CIM pre-check failed, trying WinRM: $_" -Severity DEBUG
        }

        # WinRM fallback
        try {
            $os = Invoke-Command -ComputerName $Server -ScriptBlock {
                (Get-CimInstance Win32_OperatingSystem).Caption
            } -ErrorAction Stop
            $OSName.Value = $os
            Write-Log     "[$Server] Pre-check OK via WinRM ($os)." -Severity DEBUG
            return $true
        }
        catch {
            Write-Log     "[$Server] Pre-check FAILED - CIM and WinRM both unreachable: $_" -Severity WARN
            Write-Console "[$Server] Unreachable  -  CIM and WinRM both failed" -Severity WARN -Indent 1
            return $false
        }
    }

    # ==========================================================================
    # EVENT LOG COLLECTION - SINGLE SERVER
    # Called per-server from both serial and parallel paths
    # ==========================================================================
    function Invoke-EventLogCollection {
        param (
            [string]$Server,
            [string[]]$LogNames,
            [datetime]$StartDate,
            [string]$OutputFolder,
            [string[]]$EventLevels,
            [bool]$IsLocal = $false
        )

        $results = @{
            Server  = $Server
            Success = @()
            Failed  = @()
            Skipped = @()
            Errors  = @()
        }

        foreach ($LogName in $LogNames) {
            $SafeServer = $Server -replace '[\\/:*?"<>|]', '_'
            $OutFile    = Join-Path $OutputFolder "$SafeServer $LogName Event Log.csv"

            # Remove old file if present
            if (Test-Path $OutFile) {
                try {
                    Remove-Item -Path $OutFile -Force -ErrorAction Stop
                    Write-Log "[$Server] Removed existing: $OutFile" -Severity DEBUG
                }
                catch {
                    Write-Log "[$Server] Could not remove old file '$OutFile': $_" -Severity WARN
                }
            }

            try {
                $filterHash = @{
                    LogName   = $LogName
                    StartTime = $StartDate
                    Level     = @(1, 2)   # 1=Critical, 2=Error
                }

                $events = if ($IsLocal) {
                    Get-WinEvent -FilterHashtable $filterHash -ErrorAction Stop
                }
                else {
                    Get-WinEvent -ComputerName $Server -FilterHashtable $filterHash -ErrorAction Stop
                }

                if ($events) {
                    $events | Select-Object -Property @(
                        @{N='Server';       E={ $Server }},
                        @{N='LogName';      E={ $_.LogName }},
                        @{N='Level';        E={ $_.LevelDisplayName }},
                        @{N='EventId';      E={ $_.Id }},
                        @{N='Source';       E={ $_.ProviderName }},
                        @{N='TimeCreated';  E={ $_.TimeCreated }},
                        @{N='Message';      E={ $_.Message }}
                    ) | Export-Csv -Path $OutFile -Force -NoTypeInformation -Encoding UTF8

                    Write-Log     "[$Server] $LogName - $($events.Count) event(s) written to $OutFile" -Severity SUCCESS
                    $results.Success += $LogName
                }
                else {
                    Write-Log     "[$Server] $LogName - No Critical/Error events found in window." -Severity INFO
                    $results.Skipped += $LogName
                }
            }
            catch [System.Exception] {
                if ($_.Exception.Message -like "*No events were found*") {
                    Write-Log "[$Server] $LogName - No events found (log may be empty)." -Severity INFO
                    $results.Skipped += $LogName
                }
                else {
                    Write-Log "[$Server] $LogName - Collection FAILED: $_" -Severity ERROR
                    $results.Failed  += $LogName
                    $results.Errors  += "$LogName : $_"
                }
            }
        }

        return $results
    }

    # ==========================================================================
    # PARALLEL COLLECTION - PS 5.1 RUNSPACES
    # ==========================================================================
    function Invoke-ParallelCollection51 {
        param (
            [string[]]$Servers,
            [string[]]$LogNames,
            [datetime]$StartDate,
            [string]$OutputFolder,
            [string[]]$EventLevels,
            [int]$MaxThreads
        )

        Write-Log     "Using PS 5.1 runspace pool (max $MaxThreads threads)..." -Severity INFO
        Write-Console "Engine: PS 5.1 runspace pool ($MaxThreads threads)" -Severity DEBUG -Indent 1

        $RunspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxThreads)
        $RunspacePool.Open()

        $CollectionScript = {
            param ($Server, $LogNames, $StartDate, $OutputFolder, $EventLevels, $IsLocal)

            $results = @{
                Server  = $Server
                Success = @()
                Failed  = @()
                Skipped = @()
                Errors  = @()
                Log     = @()
            }

            foreach ($LogName in $LogNames) {
                $SafeServer = $Server -replace '[\\/:*?"<>|]', '_'
                $OutFile    = Join-Path $OutputFolder "$SafeServer $LogName Event Log.csv"

                if (Test-Path $OutFile) {
                    try { Remove-Item -Path $OutFile -Force -ErrorAction Stop } catch {}
                }

                try {
                    $filterHash = @{
                        LogName   = $LogName
                        StartTime = $StartDate
                        Level     = @(1, 2)
                    }

                    $events = if ($IsLocal) {
                        Get-WinEvent -FilterHashtable $filterHash -ErrorAction Stop
                    }
                    else {
                        Get-WinEvent -ComputerName $Server -FilterHashtable $filterHash -ErrorAction Stop
                    }

                    if ($events) {
                        $events | Select-Object -Property @(
                            @{N='Server';      E={ $Server }},
                            @{N='LogName';     E={ $_.LogName }},
                            @{N='Level';       E={ $_.LevelDisplayName }},
                            @{N='EventId';     E={ $_.Id }},
                            @{N='Source';      E={ $_.ProviderName }},
                            @{N='TimeCreated'; E={ $_.TimeCreated }},
                            @{N='Message';     E={ $_.Message }}
                        ) | Export-Csv -Path $OutFile -Force -NoTypeInformation -Encoding UTF8

                        $results.Log    += "[SUCCESS] [$Server] $LogName - $($events.Count) event(s) written."
                        $results.Success += $LogName
                    }
                    else {
                        $results.Log    += "[INFO]    [$Server] $LogName - No Critical/Error events found."
                        $results.Skipped += $LogName
                    }
                }
                catch {
                    if ($_.Exception.Message -like "*No events were found*") {
                        $results.Log    += "[INFO]    [$Server] $LogName - No events found."
                        $results.Skipped += $LogName
                    }
                    else {
                        $results.Log    += "[ERROR]   [$Server] $LogName - FAILED: $_"
                        $results.Failed  += $LogName
                        $results.Errors  += "$LogName : $_"
                    }
                }
            }
            return $results
        }

        $Jobs         = @()
        $LocalMachine = $env:COMPUTERNAME

        foreach ($Server in $Servers) {
            $IsLocal         = ($Server -eq $LocalMachine -or $Server -eq "localhost" -or $Server -eq "127.0.0.1")
            $PS              = [System.Management.Automation.PowerShell]::Create()
            $PS.RunspacePool = $RunspacePool
            [void]$PS.AddScript($CollectionScript)
            [void]$PS.AddArgument($Server)
            [void]$PS.AddArgument($LogNames)
            [void]$PS.AddArgument($StartDate)
            [void]$PS.AddArgument($OutputFolder)
            [void]$PS.AddArgument($EventLevels)
            [void]$PS.AddArgument($IsLocal)
            $Jobs += [PSCustomObject]@{ PS = $PS; Handle = $PS.BeginInvoke(); Server = $Server }
        }

        $AllResults = @()
        foreach ($Job in $Jobs) {
            try {
                $result = $Job.PS.EndInvoke($Job.Handle)
                if ($result) {
                    # Flush buffered log lines  -  route each through the correct severity
                    foreach ($line in $result.Log) {
                        if     ($line -like "*[SUCCESS]*") { Write-Log $line -Severity SUCCESS }
                        elseif ($line -like "*[ERROR]*")   { Write-Log $line -Severity ERROR   }
                        elseif ($line -like "*[WARN]*")    { Write-Log $line -Severity WARN    }
                        else                               { Write-Log $line -Severity INFO    }
                    }
                    $AllResults += $result
                }
            }
            catch {
                Write-Log "Runspace result error for $($Job.Server): $_" -Severity ERROR
            }
            finally {
                $Job.PS.Dispose()
            }
        }

        $RunspacePool.Close()
        $RunspacePool.Dispose()
        return $AllResults
    }

    # ==========================================================================
    # PARALLEL COLLECTION - PS 7+
    # ==========================================================================
    function Invoke-ParallelCollection7 {
        param (
            [string[]]$Servers,
            [string[]]$LogNames,
            [datetime]$StartDate,
            [string]$OutputFolder,
            [string[]]$EventLevels,
            [int]$MaxThreads
        )

        Write-Log     "Using PowerShell 7+ ForEach-Object -Parallel (max $MaxThreads threads)..." -Severity INFO
        Write-Console "Engine: PS 7+ ForEach-Object -Parallel ($MaxThreads threads)" -Severity DEBUG -Indent 1

        $LocalMachine = $env:COMPUTERNAME

        $AllResults = $Servers | ForEach-Object -Parallel {
            $Server    = $_
            $IsLocal   = ($Server -eq $using:LocalMachine -or $Server -eq "localhost")
            $LogNames  = $using:LogNames
            $StartDate = $using:StartDate
            $OutFolder = $using:OutputFolder

            $results = @{
                Server  = $Server
                Success = [System.Collections.Generic.List[string]]::new()
                Failed  = [System.Collections.Generic.List[string]]::new()
                Skipped = [System.Collections.Generic.List[string]]::new()
                Errors  = [System.Collections.Generic.List[string]]::new()
                Log     = [System.Collections.Generic.List[string]]::new()
            }

            foreach ($LogName in $LogNames) {
                $SafeServer = $Server -replace '[\\/:*?"<>|]', '_'
                $OutFile    = Join-Path $OutFolder "$SafeServer $LogName Event Log.csv"

                if (Test-Path $OutFile) {
                    try { Remove-Item -Path $OutFile -Force -ErrorAction Stop } catch {}
                }

                try {
                    $filterHash = @{
                        LogName   = $LogName
                        StartTime = $StartDate
                        Level     = @(1, 2)
                    }

                    $events = if ($IsLocal) {
                        Get-WinEvent -FilterHashtable $filterHash -ErrorAction Stop
                    }
                    else {
                        Get-WinEvent -ComputerName $Server -FilterHashtable $filterHash -ErrorAction Stop
                    }

                    if ($events) {
                        $events | Select-Object -Property @(
                            @{N='Server';      E={ $Server }},
                            @{N='LogName';     E={ $_.LogName }},
                            @{N='Level';       E={ $_.LevelDisplayName }},
                            @{N='EventId';     E={ $_.Id }},
                            @{N='Source';      E={ $_.ProviderName }},
                            @{N='TimeCreated'; E={ $_.TimeCreated }},
                            @{N='Message';     E={ $_.Message }}
                        ) | Export-Csv -Path $OutFile -Force -NoTypeInformation -Encoding UTF8

                        $results.Log.Add("[SUCCESS] [$Server] $LogName - $($events.Count) event(s) written.")
                        $results.Success.Add($LogName)
                    }
                    else {
                        $results.Log.Add("[INFO]    [$Server] $LogName - No Critical/Error events found.")
                        $results.Skipped.Add($LogName)
                    }
                }
                catch {
                    if ($_.Exception.Message -like "*No events were found*") {
                        $results.Log.Add("[INFO]    [$Server] $LogName - No events found.")
                        $results.Skipped.Add($LogName)
                    }
                    else {
                        $results.Log.Add("[ERROR]   [$Server] $LogName - FAILED: $_")
                        $results.Failed.Add($LogName)
                        $results.Errors.Add("$LogName : $_")
                    }
                }
            }
            return $results

        } -ThrottleLimit $MaxThreads

        foreach ($result in $AllResults) {
            foreach ($line in $result.Log) {
                if     ($line -like "*[SUCCESS]*") { Write-Log $line -Severity SUCCESS }
                elseif ($line -like "*[ERROR]*")   { Write-Log $line -Severity ERROR   }
                elseif ($line -like "*[WARN]*")    { Write-Log $line -Severity WARN    }
                else                               { Write-Log $line -Severity INFO    }
            }
        }

        return $AllResults
    }

    # ==========================================================================
    # RUN SUMMARY
    # Writes structured text file + log entries via Write-Log, and a rich
    # colored display via Write-Console for interactive terminal runs.
    # ==========================================================================
    function Write-RunSummary {
        param (
            [object[]]$Results,
            [string[]]$Skipped,
            [datetime]$StartTime,
            [string]$SummaryFile,
            [string]$Mode,
            [int]$TotalDiscovered
        )

        $EndTime     = Get-Date
        $Duration    = $EndTime - $StartTime
        $Succeeded   = ($Results | Where-Object { $_.Failed.Count -eq 0 -and $_.Success.Count -gt 0 }).Count
        $PartialFail = ($Results | Where-Object { $_.Failed.Count -gt 0 -and $_.Success.Count -gt 0 }).Count
        $FullFail    = ($Results | Where-Object { $_.Failed.Count -gt 0 -and $_.Success.Count -eq 0 }).Count
        $NoEvents    = ($Results | Where-Object { $_.Failed.Count -eq 0 -and $_.Success.Count -eq 0 }).Count
        $RunAs       = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

        $summary = @"
================================================================================
  EVENT LOG COLLECTION SUMMARY
  $ScriptName v$ScriptVersion
================================================================================
  Run Date      : $RunDate
  Run Timestamp : $RunTimestamp
  Mode          : $Mode
  Duration      : $($Duration.ToString("hh\:mm\:ss"))
  Site          : $SiteName
  Run As        : $RunAs

  DISCOVERY
  ---------
  Servers Discovered    : $TotalDiscovered
  Servers Attempted     : $($Results.Count)
  Servers Skipped (pre-check failed) : $($Skipped.Count)

  COLLECTION RESULTS
  ------------------
  Fully Successful      : $Succeeded
  Partial Success       : $PartialFail
  Fully Failed          : $FullFail
  No Events Found       : $NoEvents

  OUTPUT LOCATION
  ---------------
  $OutputFolder

"@

        if ($Skipped.Count -gt 0) {
            $summary += "  SKIPPED SERVERS (connectivity pre-check failed)`n"
            $summary += "  " + ("-" * 50) + "`n"
            foreach ($s in $Skipped) { $summary += "    - $s`n" }
            $summary += "`n"
        }

        if ($PartialFail -gt 0 -or $FullFail -gt 0) {
            $summary += "  ERRORS`n"
            $summary += "  " + ("-" * 50) + "`n"
            foreach ($r in ($Results | Where-Object { $_.Errors.Count -gt 0 })) {
                $summary += "  [$($r.Server)]`n"
                foreach ($e in $r.Errors) { $summary += "    $e`n" }
            }
            $summary += "`n"
        }

        $summary += "=" * 80

        # Write to summary file
        try {
            $summary | Out-File -FilePath $SummaryFile -Encoding UTF8 -Force
        }
        catch {
            Write-Log "Could not write summary file: $_" -Severity WARN
        }

        # Write to structured log
        Write-Log "" -Severity INFO
        $summary -split "`n" | ForEach-Object { Write-Log $_ -Severity INFO }

        # -----------------------------------------------------------------------
        # Console summary  -  colored, human-readable, display stream only
        # -----------------------------------------------------------------------
        Write-Section "Run Summary"
        Write-Console "Duration   : $($Duration.ToString("hh\:mm\:ss"))"  -Severity PLAIN
        Write-Console "Mode       : $Mode"                                   -Severity PLAIN
        Write-Console "Site       : $SiteName"                              -Severity PLAIN
        Write-Console "Output     : $OutputFolder"                          -Severity PLAIN
        Write-Separator

        Write-Console "DISCOVERY" -Severity PLAIN
        Write-Console "Servers discovered : $TotalDiscovered"   -Severity PLAIN   -Indent 1
        Write-Console "Servers attempted  : $($Results.Count)"  -Severity PLAIN   -Indent 1
        if ($Skipped.Count -gt 0) {
            Write-Console "Servers skipped    : $($Skipped.Count)" -Severity WARN -Indent 1
        }
        else {
            Write-Console "Servers skipped    : 0"                 -Severity PLAIN -Indent 1
        }

        Write-Separator
        Write-Console "COLLECTION RESULTS" -Severity PLAIN
        Write-Console "Fully successful   : $Succeeded"   -Severity $(if ($Succeeded -gt 0)   { "SUCCESS" } else { "PLAIN" }) -Indent 1
        Write-Console "Partial success    : $PartialFail" -Severity $(if ($PartialFail -gt 0) { "WARN"    } else { "PLAIN" }) -Indent 1
        Write-Console "Fully failed       : $FullFail"    -Severity $(if ($FullFail -gt 0)    { "ERROR"   } else { "PLAIN" }) -Indent 1
        Write-Console "No events found    : $NoEvents"    -Severity PLAIN -Indent 1

        if ($Skipped.Count -gt 0) {
            Write-Separator
            Write-Console "SKIPPED SERVERS" -Severity WARN
            foreach ($s in $Skipped) {
                Write-Console $s -Severity WARN -Indent 1
            }
        }

        if ($PartialFail -gt 0 -or $FullFail -gt 0) {
            Write-Separator
            Write-Console "ERRORS" -Severity ERROR
            foreach ($r in ($Results | Where-Object { $_.Errors.Count -gt 0 })) {
                Write-Console "[$($r.Server)]" -Severity ERROR -Indent 1
                foreach ($e in $r.Errors) {
                    Write-Console $e -Severity ERROR -Indent 2
                }
            }
        }

        return @{
            Succeeded   = $Succeeded
            PartialFail = $PartialFail
            FullFail    = $FullFail
        }
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'
    $ScriptStartTime = Get-Date
    $RunAs           = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Initialize-Logging

    # --------------------------------------------------------------------------
    # Startup  -  structured log header (DattoRMM/file) + console banner (display)
    # --------------------------------------------------------------------------
    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site        : $SiteName"                   -Severity INFO
    Write-Log "Hostname    : $Hostname"                   -Severity INFO
    Write-Log "Run As      : $RunAs"                      -Severity INFO
    Write-Log "Mode        : $Mode"                       -Severity INFO
    Write-Log "DaysBack    : $DaysBack"                   -Severity INFO
    Write-Log "Log Names   : $($LogNames -join ', ')"     -Severity INFO
    Write-Log "Levels      : Critical, Error"             -Severity INFO
    Write-Log "Output Path : $OutputPath"                 -Severity INFO
    Write-Log "Log File    : $LogFile"                    -Severity INFO
    Write-Log "PS Version  : $($PSVersionTable.PSVersion)" -Severity INFO
    Write-Log "Starting execution..." -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site        : $SiteName"                            -Severity PLAIN
    Write-Console "Hostname    : $Hostname"                            -Severity PLAIN
    Write-Console "Run As      : $RunAs"                               -Severity PLAIN
    Write-Console "Mode        : $Mode"                                -Severity PLAIN
    Write-Console "Days Back   : $DaysBack"                            -Severity PLAIN
    Write-Console "Logs        : $($LogNames -join ', ')"              -Severity PLAIN
    Write-Console "PS Version  : $($PSVersionTable.PSVersion)"        -Severity PLAIN
    Write-Console "Log File    : $LogFile"                             -Severity PLAIN
    Write-Separator

    try {
        $StartDate    = (Get-Date).AddDays(-$DaysBack)
        $TargetList   = @()
        $LocalMachine = $env:COMPUTERNAME

        Initialize-OutputFolder

        # -----------------------------------------------------------------------
        # SERVER DISCOVERY
        # -----------------------------------------------------------------------
        Write-Section "Server Discovery"
        Write-Log "--- SERVER DISCOVERY ---" -Severity INFO

        if ($Mode -eq "Automated") {

            # Always include local machine first
            $TargetList += $LocalMachine
            Write-Log     "Local machine added: $LocalMachine" -Severity INFO
            Write-Console "Local machine added: $LocalMachine" -Severity INFO -Indent 1

            # AD Query
            $adServers = Get-ServersFromAD
            if ($adServers.Count -gt 0) {
                $TargetList += $adServers
                Write-Log     "AD discovery complete. $($adServers.Count) server(s) added." -Severity SUCCESS
                Write-Console "AD discovery complete  -  $($adServers.Count) server(s) added." -Severity SUCCESS
            }
            else {
                # Fallback: ping sweep
                Write-Log     "AD returned no results. Falling back to ping sweep..." -Severity WARN
                Write-Console "AD returned no results  -  falling back to ping sweep..." -Severity WARN

                $subnetList = if ($Subnets -and $Subnets.Count -gt 0) {
                    Write-Log     "Using user-provided subnet list." -Severity INFO
                    Write-Console "Using provided subnets: $($Subnets -join ', ')" -Severity INFO -Indent 1
                    $Subnets
                }
                else {
                    Write-Log     "Auto-detecting local subnets..." -Severity INFO
                    Write-Console "Auto-detecting local subnets..." -Severity INFO -Indent 1
                    Get-LocalSubnets
                }

                if ($subnetList.Count -eq 0) {
                    Write-Log     "No subnets available for ping sweep. Cannot proceed with discovery." -Severity ERROR
                    Write-Console "No subnets available for ping sweep  -  cannot continue." -Severity ERROR
                    throw "No servers discovered and no subnets available for fallback sweep."
                }

                $sweepServers = Get-ServersFromPingSweep -SubnetList $subnetList
                $TargetList  += $sweepServers
                Write-Log     "Ping sweep complete. $($sweepServers.Count) Windows Server(s) added." -Severity SUCCESS
                Write-Console "Ping sweep complete  -  $($sweepServers.Count) server(s) added." -Severity SUCCESS
            }

        }
        elseif ($Mode -eq "Custom") {

            Write-Log "--- CUSTOM MODE ---" -Severity INFO

            # Handle comma-separated string input (DattoRMM compatibility)
            if ($ComputerName.Count -eq 1 -and $ComputerName[0] -like "*,*") {
                $ComputerName = $ComputerName[0] -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }

            if (-not $ComputerName -or $ComputerName.Count -eq 0) {
                Write-Log     "Custom mode selected but no -ComputerName targets provided." -Severity ERROR
                Write-Console "No -ComputerName targets provided for Custom mode." -Severity ERROR
                throw "No ComputerName targets specified for Custom mode."
            }

            $TargetList = $ComputerName
            Write-Log     "$($TargetList.Count) custom target(s) specified." -Severity INFO
            Write-Console "$($TargetList.Count) custom target(s):" -Severity INFO
            foreach ($t in $TargetList) {
                Write-Console $t -Severity PLAIN -Indent 1
            }
        }

        # Deduplicate
        $TargetList = $TargetList | Sort-Object -Unique
        Write-Log     "Total unique targets after deduplication: $($TargetList.Count)" -Severity INFO
        Write-Console "Total unique targets: $($TargetList.Count)" -Severity INFO

        $TotalDiscovered = $TargetList.Count

        # -----------------------------------------------------------------------
        # CONNECTIVITY PRE-CHECKS
        # -----------------------------------------------------------------------
        Write-Section "Connectivity Pre-Checks"
        Write-Log "--- CONNECTIVITY PRE-CHECKS ---" -Severity INFO

        $ReachableServers = @()
        $SkippedServers   = @()

        foreach ($Server in $TargetList) {
            $IsLocal = ($Server -eq $LocalMachine -or $Server -eq "localhost" -or $Server -eq "127.0.0.1")
            if ($IsLocal) {
                Write-Log     "[$Server] Local machine - skipping remote pre-check." -Severity DEBUG
                Write-Console "[$Server] Local  -  skipping pre-check" -Severity DEBUG -Indent 1
                $ReachableServers += $Server
                continue
            }

            $osRef = [ref]""
            if (Test-ServerConnectivity -Server $Server -OSName $osRef) {
                Write-Log     "[$Server] Reachable  -  $($osRef.Value)" -Severity INFO
                Write-Console "[$Server] $($osRef.Value)" -Severity SUCCESS -Indent 1
                $ReachableServers += $Server
            }
            else {
                Write-Log     "[$Server] UNREACHABLE  -  skipping." -Severity WARN
                $SkippedServers += $Server
            }
        }

        Write-Log     "$($ReachableServers.Count) server(s) passed pre-check. $($SkippedServers.Count) skipped." -Severity INFO
        Write-Console "$($ReachableServers.Count) reachable, $($SkippedServers.Count) skipped." -Severity INFO

        if ($ReachableServers.Count -eq 0) {
            Write-Log     "No reachable servers to collect from. Exiting." -Severity ERROR
            Write-Console "No reachable servers found  -  nothing to collect." -Severity ERROR
            throw "All discovered servers failed the connectivity pre-check."
        }

        # -----------------------------------------------------------------------
        # COLLECTION  -  RUNTIME PS VERSION DETECTION
        # -----------------------------------------------------------------------
        Write-Section "Event Log Collection"
        Write-Log "--- EVENT LOG COLLECTION ---" -Severity INFO

        $AllResults = @()
        $PSMajor    = $PSVersionTable.PSVersion.Major

        if ($PSMajor -ge 7) {
            $AllResults = Invoke-ParallelCollection7 `
                -Servers      $ReachableServers `
                -LogNames     $LogNames `
                -StartDate    $StartDate `
                -OutputFolder $OutputFolder `
                -EventLevels  $EventLevels `
                -MaxThreads   $MaxParallel
        }
        else {
            $AllResults = Invoke-ParallelCollection51 `
                -Servers      $ReachableServers `
                -LogNames     $LogNames `
                -StartDate    $StartDate `
                -OutputFolder $OutputFolder `
                -EventLevels  $EventLevels `
                -MaxThreads   $MaxParallel
        }

        # Display per-server collection results to console
        foreach ($r in $AllResults) {
            if ($r.Failed.Count -eq 0 -and $r.Success.Count -gt 0) {
                Write-Console "[$($r.Server)] $($r.Success.Count) log(s) written successfully" -Severity SUCCESS -Indent 1
            }
            elseif ($r.Failed.Count -gt 0 -and $r.Success.Count -gt 0) {
                Write-Console "[$($r.Server)] Partial  -  $($r.Success.Count) OK, $($r.Failed.Count) failed" -Severity WARN -Indent 1
            }
            elseif ($r.Failed.Count -gt 0) {
                Write-Console "[$($r.Server)] FAILED  -  $($r.Failed.Count) log(s) could not be collected" -Severity ERROR -Indent 1
            }
            else {
                Write-Console "[$($r.Server)] No Critical/Error events in collection window" -Severity INFO -Indent 1
            }
        }

        # -----------------------------------------------------------------------
        # SUMMARY AND EXIT
        # -----------------------------------------------------------------------
        $summaryStats = Write-RunSummary `
            -Results         $AllResults `
            -Skipped         $SkippedServers `
            -StartTime       $ScriptStartTime `
            -SummaryFile     $SummaryFile `
            -Mode            $Mode `
            -TotalDiscovered $TotalDiscovered

        # Determine exit code and show closing banner
        if ($summaryStats.FullFail -gt 0 -and $summaryStats.Succeeded -eq 0 -and $summaryStats.PartialFail -eq 0) {
            Write-Log "Collection complete with full failures. Exit 2." -Severity ERROR
            Write-Banner "COLLECTION FAILED" -Color "Red"
            exit 2
        }
        elseif ($summaryStats.FullFail -gt 0 -or $summaryStats.PartialFail -gt 0) {
            Write-Log "Collection complete with partial failures. Exit 1." -Severity WARN
            Write-Banner "COMPLETED WITH WARNINGS" -Color "Yellow"
            exit 1
        }
        else {
            Write-Log "Collection complete. All targets successful. Exit 0." -Severity SUCCESS
            Write-Banner "COMPLETED SUCCESSFULLY" -Color "Green"
            exit 0
        }

    }
    catch {
        Write-Log "FATAL: Unhandled exception: $_"            -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)"       -Severity ERROR

        Write-Banner "SCRIPT FAILED" -Color "Red"
        Write-Console "Error : $_"  -Severity ERROR

        exit 2
    }

} # End function Start-EventLogCollection

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    Mode         = $Mode
    ComputerName = $ComputerName
    Subnets      = $Subnets
    DaysBack     = $DaysBack
    OutputPath   = $OutputPath
    LogNames     = $LogNames
    SiteName     = $SiteName
    Hostname     = $Hostname
}

Start-EventLogCollection @ScriptParams
