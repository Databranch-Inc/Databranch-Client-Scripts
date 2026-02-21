#Requires -Version 5.1
<#
.SYNOPSIS
    Collects a full Active Directory inventory including users, servers, desktops, and
    desktop hardware -- with smart caching, Wake-on-LAN, and parallel collection.

.DESCRIPTION
    Start-ADInventoryCollection performs a comprehensive inventory of an Active Directory
    environment. On each run it:

      - Queries AD for all user accounts, server computers, and desktop computers
      - Loads cached hardware data from the previous run (desktopsFINAL.csv)
      - Detects and logs computers that have been removed from AD since the last run
      - Discovers all Domain Controllers and collects MAC addresses from DHCP leases
        and ARP tables across all DCs
      - Sends Wake-on-LAN packets to all matched desktop MAC addresses (locally and
        remotely via each DC subnet), then waits a configurable number of minutes
      - Pings all desktops in parallel to identify online machines
      - Collects hardware inventory (Manufacturer, Model, Serial, RAM, OS, LastBootTime)
        from online desktops using parallel runspaces with WinRM -> DCOM fallback
      - Merges fresh hardware data with cached data for offline machines
      - Exports all results to CSV and produces a per-computer error/skip report

    Prerequisites:
      - RSAT / ActiveDirectory PowerShell module
      - DHCP Server PowerShell module (for DHCP MAC collection)
      - WinRM or DCOM access to target desktops
      - Domain Admin (or equivalent) permissions
      - Run from a domain-joined machine

    Output Files (all written to $DataFolder):
      usersAD.csv                 - All AD user accounts
      serversAD.csv               - All AD server computers
      desktopsAD.csv              - All AD desktop computers
      desktopsMODELS.csv          - Fresh hardware data (this run only)
      desktopsFINAL.csv           - Merged desktop inventory (fresh + cached)
      ADCollectionErrorReport.csv - Failed and skipped collection attempts
      RemovedFromAD.csv           - Computers in cache but no longer in AD

.PARAMETER DataFolder
    Path to the working directory where all CSV output files are written.
    Created automatically if it does not exist.
    DattoRMM env var: DataFolder
    Default: C:\Databranch_Inventory

.PARAMETER WaitTimeMinutes
    Number of minutes to wait after sending Wake-on-LAN packets before pinging.
    DattoRMM env var: WaitTimeMinutes
    Default: 3

.PARAMETER SiteName
    Customer/site name. Auto-populated by DattoRMM via CS_PROFILE_NAME.
    Default: UnknownSite

.PARAMETER Hostname
    Machine hostname. Auto-populated by DattoRMM via CS_HOSTNAME.
    Default: $env:COMPUTERNAME

.EXAMPLE
    .\Start-ADInventoryCollection.ps1
    Runs with all defaults. Uses C:\Databranch_Inventory as the output folder
    and waits 3 minutes after WOL before pinging.

.EXAMPLE
    .\Start-ADInventoryCollection.ps1 -DataFolder "D:\Inventory" -WaitTimeMinutes 5
    Writes output to D:\Inventory and waits 5 minutes after WOL.

.EXAMPLE
    .\Start-ADInventoryCollection.ps1 -WaitTimeMinutes 0
    Skips the WOL wait entirely -- useful when desktops are known to be online.

.NOTES
    File Name      : Start-ADInventoryCollection.ps1
    Version        : 1.0.0.0
    Author         : Josh Britton
    Contributors   : Sam Kirsch
    Company        : Databranch
    Created        : 2026-02-21
    Last Modified  : 2026-02-21
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
                     ActiveDirectory module (RSAT)
                     DhcpServer module (RSAT)
    Run Context    : Domain Admin
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : All clients with on-premises Active Directory

    Exit Codes:
        0  - Success -- all phases completed, CSVs exported
        1  - General failure -- unhandled exception, see log for details
        2  - AD module not available -- cannot continue without ActiveDirectory module

.CHANGELOG
    v1.0.0.0 - 2026-02-21 - Sam Kirsch
        - Modernized from legacy flat script (FINAL_2026Q1v1_0_InventoryScript.ps1)
        - Renamed to Start-ADInventoryCollection per project naming convention
        - Wrapped all logic in master function matching file name
        - Added full comment-based help block and .CHANGELOG section
        - Added DattoRMM/manual parameter fallback pattern for DataFolder and WaitTimeMinutes
        - Replaced all Write-Host logging with dual-output pattern:
            Write-Log     -- structured timestamped output to log file + DattoRMM stdout
            Write-Console -- colored terminal output via Write-Host (display stream only)
        - Added Write-Banner, Write-Section, Write-Separator console helpers
        - Added Initialize-Logging with log rotation (10-file max)
        - Log path: C:\Databranch\ScriptLogs\Start-ADInventoryCollection\
        - Added standard log header (Site, Hostname, Run As, Params, Log File)
        - Moved helper functions (Get-DhcpMacs, Get-ARPmacs, Match-ComputerName) inside
          the master function scope
        - Added AD module pre-check with exit code 2
        - Replaced silent catch blocks with Write-Log ERROR entries and error tracking
        - Added $ErrorActionPreference = 'Stop' with outer try/catch
        - Added explicit exit 0 / exit 1 / exit 2
        - Original logic (caching, WOL, parallel runspaces, hardware collection, merging,
          CSV export) preserved intact
        - Original author (Josh Britton) credited in .NOTES
#>

# ==============================================================================
# PARAMETERS
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$DataFolder = $(if ($env:DataFolder) { $env:DataFolder } else { "C:\Databranch_Inventory" }),

    [Parameter(Mandatory = $false)]
    [int]$WaitTimeMinutes = $(if ($env:WaitTimeMinutes) { [int]$env:WaitTimeMinutes } else { 3 }),

    # DattoRMM built-in variables (auto-populated by Datto, no config needed)
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Start-ADInventoryCollection {
    <#
    .SYNOPSIS
        Internal master function. See script-level help for full documentation.
    #>
    [CmdletBinding()]
    param (
        [string]$DataFolder,
        [int]$WaitTimeMinutes,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Start-ADInventoryCollection"
    $ScriptVersion = "1.0.0.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

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
    # WRITE-CONSOLE  (Presentation Layer -- Write-Host display stream only)
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

    function Write-Banner {
        param (
            [Parameter(Mandatory = $true)]  [string]$Title,
            [Parameter(Mandatory = $false)] [string]$Color = "Cyan"
        )
        $Line = "=" * 60
        Write-Host ""
        Write-Host $Line       -ForegroundColor $Color
        Write-Host "  $Title" -ForegroundColor White
        Write-Host $Line       -ForegroundColor $Color
        Write-Host ""
    }

    function Write-Section {
        param (
            [Parameter(Mandatory = $true)]  [string]$Title,
            [Parameter(Mandatory = $false)] [string]$Color = "Cyan"
        )
        $TitleStr = "---- $Title "
        $Padding  = "-" * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ""
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    function Write-Separator {
        param ([Parameter(Mandatory = $false)] [string]$Color = "DarkGray")
        Write-Host ("-" * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # LOG SETUP
    # ==========================================================================
    function Initialize-Logging {
        if (-not (Test-Path $LogFolder)) {
            try { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
            catch { Write-Warning "Could not create log folder '$LogFolder': $_" }
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
        catch { Write-Warning "Log rotation failed: $_" }
    }

    # ==========================================================================
    # HELPER: DHCP MAC COLLECTION
    # Queries DHCP leases from a specified Domain Controller.
    # Returns array of [Name, MAC, IP] objects. Silent on failure (reported upstream).
    # ==========================================================================
    function Get-DhcpMacs {
        param ([string]$DC)
        $AllMACs = @()
        try {
            $Scopes = Get-DhcpServerv4Scope -ComputerName $DC -ErrorAction Stop
            foreach ($Scope in $Scopes) {
                $Leases = Get-DhcpServerv4Lease -ScopeId $Scope.ScopeId -ComputerName $DC -ErrorAction Stop |
                          Where-Object { $_.ClientId -match '^[0-9A-Fa-f-]+$' }

                foreach ($Lease in $Leases) {
                    if ($Lease.HostName -and $Lease.ClientId) {
                        $AllMACs += [PSCustomObject]@{
                            Name = $Lease.HostName
                            MAC  = $Lease.ClientId.Replace("-", "").ToUpper()
                            IP   = $Lease.IPAddress.IPAddressToString
                        }
                    }
                }
            }
        }
        catch {
            # Caller handles failure reporting
        }
        return $AllMACs
    }

    # ==========================================================================
    # HELPER: ARP MAC COLLECTION
    # Collects ARP table from a DC via WinRM, then does parallel reverse-DNS
    # lookups via runspaces to resolve IPs to hostnames.
    # Returns array of [Name, MAC, IP] objects. Silent on failure (reported upstream).
    # ==========================================================================
    function Get-ARPmacs {
        param ([string]$DC)
        $AllMACs = @()
        try {
            $ARP = Invoke-Command -ComputerName $DC -ScriptBlock { arp -a } -ErrorAction Stop

            # Parse all IP/MAC pairs from ARP output
            $ARPEntries = @()
            foreach ($Line in $ARP) {
                if ($Line -match '\s+([0-9\.]+)\s+([0-9A-Fa-f-]+)\s+') {
                    $ARPEntries += [PSCustomObject]@{
                        IP  = $Matches[1]
                        MAC = $Matches[2].Replace("-", "").ToUpper()
                    }
                }
            }

            # Parallel reverse-DNS using runspaces (much faster than sequential)
            $RunspacePool = [runspacefactory]::CreateRunspacePool(1, 20)
            $RunspacePool.Open()
            $Jobs = @()

            foreach ($Entry in $ARPEntries) {
                $PS = [powershell]::Create()
                $PS.RunspacePool = $RunspacePool

                [void]$PS.AddScript({
                    param($IP, $MAC)
                    $Name = $IP
                    try {
                        $HostEntry = [System.Net.Dns]::GetHostEntry($IP)
                        $Name = $HostEntry.HostName
                    }
                    catch { }
                    return [PSCustomObject]@{ Name = $Name; MAC = $MAC; IP = $IP }
                }).AddArgument($Entry.IP).AddArgument($Entry.MAC)

                $Jobs += [PSCustomObject]@{ Pipe = $PS; Status = $PS.BeginInvoke() }
            }

            foreach ($Job in $Jobs) {
                try {
                    $Result = $Job.Pipe.EndInvoke($Job.Status)
                    if ($Result) { $AllMACs += $Result }
                }
                catch { }
                $Job.Pipe.Dispose()
            }

            $RunspacePool.Close()
            $RunspacePool.Dispose()
        }
        catch {
            # Caller handles failure reporting
        }
        return $AllMACs
    }

    # ==========================================================================
    # HELPER: COMPUTER NAME MATCHING
    # Matches a DHCP/ARP hostname to an AD computer object.
    # Strips domain suffix, tries exact match, then prefix match.
    # ==========================================================================
    function Resolve-ComputerMatch {
        param (
            [string]$SearchName,
            [object[]]$ADComputers
        )

        if ([string]::IsNullOrWhiteSpace($SearchName)) { return $null }

        # Strip any domain suffix
        $CleanName = $SearchName.Split('.')[0].ToUpper()

        # Exact match
        $Match = $ADComputers | Where-Object { $_.Name.ToUpper() -eq $CleanName } | Select-Object -First 1
        if ($Match) { return $Match }

        # Prefix match (first segment before dash)
        if ($CleanName -match '^([^-]+)') {
            $Prefix = $Matches[1]
            $Match = $ADComputers | Where-Object { $_.Name.ToUpper().StartsWith($Prefix) } | Select-Object -First 1
            if ($Match) { return $Match }
        }

        return $null
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'
    $ScriptStart = Get-Date

    Initialize-Logging

    # ------------------------------------------------------------------
    # Startup banner and log header
    # ------------------------------------------------------------------
    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName"                    -Severity INFO
    Write-Log "Hostname : $Hostname"                    -Severity INFO
    Write-Log "Run As   : $RunAs"                       -Severity INFO
    Write-Log "Params   : DataFolder='$DataFolder' | WaitTimeMinutes='$WaitTimeMinutes'" -Severity INFO
    Write-Log "Log File : $LogFile"                     -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site     : $SiteName"    -Severity PLAIN
    Write-Console "Hostname : $Hostname"    -Severity PLAIN
    Write-Console "Run As   : $RunAs"       -Severity PLAIN
    Write-Console "Log File : $LogFile"     -Severity PLAIN
    Write-Separator

    try {

        # ------------------------------------------------------------------
        # PRE-CHECK: ActiveDirectory module
        # ------------------------------------------------------------------
        Write-Section "Prerequisites"
        Write-Log  "Checking for ActiveDirectory PowerShell module..." -Severity INFO
        Write-Console "Checking for ActiveDirectory PowerShell module..." -Severity INFO

        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Write-Log  "ActiveDirectory module not found. Install RSAT to continue." -Severity ERROR
            Write-Console "ActiveDirectory module not found. Install RSAT to continue." -Severity ERROR
            Write-Banner "SCRIPT FAILED -- MISSING MODULE" -Color "Red"
            exit 2
        }

        Write-Log  "ActiveDirectory module found." -Severity SUCCESS
        Write-Console "ActiveDirectory module found." -Severity SUCCESS

        Import-Module -Name ActiveDirectory -ErrorAction Stop

        # ------------------------------------------------------------------
        # WORKING DIRECTORY
        # ------------------------------------------------------------------
        Write-Section "Working Directory"
        Write-Log  "Data folder: $DataFolder" -Severity INFO
        Write-Console "Data folder: $DataFolder" -Severity INFO

        if (-not (Test-Path $DataFolder)) {
            New-Item -Path $DataFolder -ItemType Directory -Force | Out-Null
            Write-Log  "Created working directory: $DataFolder" -Severity SUCCESS
            Write-Console "Created working directory: $DataFolder" -Severity SUCCESS
        }
        else {
            Write-Log  "Working directory ready." -Severity INFO
            Write-Console "Working directory ready." -Severity INFO
        }

        # ------------------------------------------------------------------
        # LOAD CACHED HARDWARE DATA
        # Reads desktopsFINAL.csv from the previous run to preserve hardware
        # data for machines that are offline during the current run.
        # ------------------------------------------------------------------
        Write-Section "Loading Cache"
        Write-Log  "Loading cached hardware data from previous run..." -Severity INFO
        Write-Console "Loading cached hardware data from previous run..." -Severity INFO

        $CachedHardware  = @{}
        $CacheLoadedCount = 0
        $CacheFile = Join-Path $DataFolder "desktopsFINAL.csv"

        if (Test-Path $CacheFile) {
            try {
                $OldData = Import-Csv -Path $CacheFile
                foreach ($Row in $OldData) {
                    if ($Row.Name -and $Row.Manufacturer) {
                        $CachedHardware[$Row.Name.ToUpper()] = [PSCustomObject]@{
                            Name            = $Row.Name
                            Manufacturer    = $Row.Manufacturer
                            Model           = $Row.Model
                            SerialNumber    = $Row.SerialNumber
                            TotalRAM_GB     = $Row.TotalRAM_GB
                            OS              = $Row.OS
                            LastBootTime    = $Row.LastBootTime
                            Domain          = $Row.Domain
                            LastInventoried = $Row.LastInventoried
                        }
                        $CacheLoadedCount++
                    }
                }
                Write-Log  "Loaded $CacheLoadedCount cached hardware records." -Severity SUCCESS
                Write-Console "Loaded $CacheLoadedCount cached hardware records." -Severity SUCCESS
            }
            catch {
                Write-Log  "Could not load cache file (may be corrupt): $_" -Severity WARN
                Write-Console "Could not load cache file -- starting fresh." -Severity WARN
            }
        }
        else {
            Write-Log  "No cache file found -- first run." -Severity INFO
            Write-Console "No cache file found -- this appears to be the first run." -Severity INFO
        }

        # ------------------------------------------------------------------
        # ACTIVE DIRECTORY COLLECTION
        # ------------------------------------------------------------------
        Write-Section "Active Directory Collection"
        Write-Log  "Querying Active Directory..." -Severity INFO
        Write-Console "Querying Active Directory..." -Severity INFO

        # Desktops (non-server OS)
        Write-Log  "Collecting desktop computers..." -Severity INFO
        Write-Console "Collecting desktop computers..." -Severity INFO
        $DesktopsAD = Get-ADComputer -Filter { OperatingSystem -NotLike "*server*" } `
                        -Properties OperatingSystem, LastLogonDate, Enabled, IPv4Address, Description |
                      Select-Object -Property Name, OperatingSystem, LastLogonDate, Enabled, IPv4Address,
                                              Description, DistinguishedName
        Write-Log  "Found $($DesktopsAD.Count) desktop computers." -Severity SUCCESS
        Write-Console "Found $($DesktopsAD.Count) desktop computers." -Severity SUCCESS

        # Users
        Write-Log  "Collecting user accounts..." -Severity INFO
        Write-Console "Collecting user accounts..." -Severity INFO
        $UsersAD = Get-ADUser -Filter * -Properties LastLogonDate, Enabled, Description |
                   Select-Object -Property Name, LastLogonDate, Enabled, Description, DistinguishedName
        Write-Log  "Found $($UsersAD.Count) user accounts." -Severity SUCCESS
        Write-Console "Found $($UsersAD.Count) user accounts." -Severity SUCCESS

        # Servers
        Write-Log  "Collecting server computers..." -Severity INFO
        Write-Console "Collecting server computers..." -Severity INFO
        $ServersAD = Get-ADComputer -Filter { OperatingSystem -Like "Windows* *server*" } `
                        -Properties OperatingSystem, LastLogonDate, Enabled, IPv4Address, Description |
                     Select-Object -Property Name, OperatingSystem, LastLogonDate, Enabled, IPv4Address,
                                             Description, DistinguishedName
        Write-Log  "Found $($ServersAD.Count) server computers." -Severity SUCCESS
        Write-Console "Found $($ServersAD.Count) server computers." -Severity SUCCESS

        # ------------------------------------------------------------------
        # DETECT REMOVED COMPUTERS
        # Compare current AD desktop names against the cache to find machines
        # that no longer exist in AD (decommissioned, renamed, etc.)
        # ------------------------------------------------------------------
        Write-Section "Removed Computer Detection"
        $RemovedComputers   = @()
        $CurrentADNames     = $DesktopsAD | ForEach-Object { $_.Name.ToUpper() }

        foreach ($CachedName in $CachedHardware.Keys) {
            if ($CachedName -notin $CurrentADNames) {
                $RemovedComputers += $CachedHardware[$CachedName]
            }
        }

        if ($RemovedComputers.Count -gt 0) {
            Write-Log  "$($RemovedComputers.Count) computer(s) in cache but no longer in AD -- will log to RemovedFromAD.csv." -Severity WARN
            Write-Console "$($RemovedComputers.Count) computer(s) removed from AD since last run." -Severity WARN
        }
        else {
            Write-Log  "No removed computers detected." -Severity SUCCESS
            Write-Console "No removed computers detected." -Severity SUCCESS
        }

        # ------------------------------------------------------------------
        # CLEAN PREVIOUS CSV FILES
        # Remove stale CSVs before writing fresh data so old data never merges
        # accidentally with the new run's output.
        # ------------------------------------------------------------------
        Write-Section "CSV Cleanup"
        Write-Log  "Removing previous CSV files..." -Severity INFO
        Write-Console "Removing previous CSV files..." -Severity INFO

        $CSVFiles = @(
            "desktopsFINAL.csv",
            "desktopsMODELADDED.csv",
            "desktopsMODELS.csv",
            "desktopsSERIAL.csv",
            "desktopsAD.csv",
            "usersAD.csv",
            "serversAD.csv",
            "ADCollectionErrorReport.csv"
        )

        foreach ($FileName in $CSVFiles) {
            $FilePath = Join-Path $DataFolder $FileName
            if (Test-Path $FilePath) {
                try {
                    Remove-Item -Path $FilePath -Force
                    Write-Log  "Removed: $FileName" -Severity DEBUG
                    Write-Console "Removed: $FileName" -Severity DEBUG -Indent 1
                }
                catch {
                    Write-Log  "Could not remove $FileName : $_" -Severity WARN
                    Write-Console "Could not remove $FileName" -Severity WARN -Indent 1
                }
            }
        }

        # ------------------------------------------------------------------
        # DISCOVER DOMAIN CONTROLLERS
        # ------------------------------------------------------------------
        Write-Section "Domain Controller Discovery"
        Write-Log  "Discovering Domain Controllers..." -Severity INFO
        Write-Console "Discovering Domain Controllers..." -Severity INFO

        $DCs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty Name

        Write-Log  "Found $($DCs.Count) DC(s): $($DCs -join ', ')" -Severity SUCCESS
        Write-Console "Found $($DCs.Count) DC(s): $($DCs -join ', ')" -Severity SUCCESS

        # ------------------------------------------------------------------
        # MAC ADDRESS COLLECTION
        # Queries DHCP and ARP tables from each DC. Deduplicates results.
        # ------------------------------------------------------------------
        Write-Section "MAC Address Collection"
        Write-Log  "Collecting MAC addresses from all Domain Controllers..." -Severity INFO
        Write-Console "Collecting MAC addresses from all Domain Controllers..." -Severity INFO

        $AllMACs        = @()
        $UnreachableDCs = @()
        $DHCPFailures   = @()
        $ARPFailures    = @()

        foreach ($DC in $DCs) {
            Write-Log  "Processing DC: $DC" -Severity INFO
            Write-Console "Processing DC: $DC" -Severity INFO -Indent 1

            # Ping check
            if (-not (Test-Connection -ComputerName $DC -Count 1 -Quiet)) {
                Write-Log  "DC not reachable: $DC" -Severity WARN
                Write-Console "DC not reachable -- skipping." -Severity WARN -Indent 2
                $UnreachableDCs += $DC
                continue
            }

            # DHCP
            Write-Log  "  Collecting DHCP leases from $DC..." -Severity DEBUG
            Write-Console "Collecting DHCP leases..." -Severity DEBUG -Indent 2

            $MACsDHCP = Get-DhcpMacs -DC $DC
            if ($MACsDHCP.Count -eq 0) {
                Write-Log  "No DHCP data from $DC (no DHCP role, or access denied)." -Severity WARN
                Write-Console "No DHCP data retrieved." -Severity WARN -Indent 2
                $DHCPFailures += $DC
            }
            else {
                Write-Log  "Retrieved $($MACsDHCP.Count) DHCP leases from $DC." -Severity SUCCESS
                Write-Console "Retrieved $($MACsDHCP.Count) DHCP leases." -Severity SUCCESS -Indent 2
                $AllMACs += $MACsDHCP
            }

            # ARP
            Write-Log  "  Collecting ARP table from $DC..." -Severity DEBUG
            Write-Console "Collecting ARP table..." -Severity DEBUG -Indent 2

            $MACsARP = Get-ARPmacs -DC $DC
            if ($MACsARP.Count -eq 0) {
                Write-Log  "No ARP data from $DC (WinRM issue?)." -Severity WARN
                Write-Console "No ARP data retrieved (WinRM issue?)." -Severity WARN -Indent 2
                $ARPFailures += $DC
            }
            else {
                Write-Log  "Retrieved $($MACsARP.Count) ARP entries from $DC." -Severity SUCCESS
                Write-Console "Retrieved $($MACsARP.Count) ARP entries." -Severity SUCCESS -Indent 2
                $AllMACs += $MACsARP
            }
        }

        # Deduplicate
        $OriginalMACCount = $AllMACs.Count
        $AllMACs          = $AllMACs | Sort-Object -Property MAC -Unique
        Write-Log  "MAC deduplication: $OriginalMACCount -> $($AllMACs.Count) unique entries." -Severity INFO
        Write-Console "MAC deduplication: $OriginalMACCount -> $($AllMACs.Count) unique entries." -Severity INFO

        # ------------------------------------------------------------------
        # WAKE-ON-LAN
        # Matches each MAC to an AD desktop and sends a WOL magic packet
        # locally, then via each reachable DC for cross-subnet coverage.
        # ------------------------------------------------------------------
        Write-Section "Wake-on-LAN"
        Write-Log  "Building WOL target list and sending magic packets..." -Severity INFO
        Write-Console "Building WOL target list and sending magic packets..." -Severity INFO

        $WOLTargets  = @()
        $WOLSkipped  = 0

        foreach ($M in $AllMACs) {
            if ([string]::IsNullOrWhiteSpace($M.Name) -or [string]::IsNullOrWhiteSpace($M.MAC)) {
                $WOLSkipped++
                continue
            }

            $ADMatch = Resolve-ComputerMatch -SearchName $M.Name -ADComputers $DesktopsAD
            if (-not $ADMatch) {
                $WOLSkipped++
                continue
            }

            $TargetIP = if ($ADMatch.IPv4Address) { $ADMatch.IPv4Address } else { $M.IP }
            if ([string]::IsNullOrWhiteSpace($TargetIP)) {
                $WOLSkipped++
                continue
            }

            $WOLTargets += [PSCustomObject]@{ MAC = $M.MAC; IP = $TargetIP }
        }

        Write-Log  "$($WOLTargets.Count) WOL targets identified. $WOLSkipped skipped (no AD match or no IP)." -Severity INFO
        Write-Console "$($WOLTargets.Count) WOL targets identified. $WOLSkipped skipped." -Severity INFO

        $ReachableDCs = $DCs | Where-Object { $_ -notin $UnreachableDCs }
        $WOLSuccesses = 0
        $WOLFailures  = 0

        # Parallel WOL transmission via runspaces
        $RunspacePool = [runspacefactory]::CreateRunspacePool(1, 30)
        $RunspacePool.Open()
        $WOLJobs = @()

        foreach ($Target in $WOLTargets) {
            $PS = [powershell]::Create()
            $PS.RunspacePool = $RunspacePool

            [void]$PS.AddScript({
                param($MAC, $IP, $ReachableDCs)

                $Success = $false

                # Local send
                try {
                    $MACBytes = $MAC -split '(?<=\G..)' | Where-Object { $_ } |
                                ForEach-Object { [convert]::ToByte($_, 16) }
                    $Packet   = [byte[]](, 0xFF * 6) + ($MACBytes * 16)
                    $UDP      = New-Object System.Net.Sockets.UdpClient
                    $UDP.Connect($IP, 9)
                    [void]$UDP.Send($Packet, $Packet.Length)
                    $UDP.Close()
                    $Success = $true
                }
                catch { }

                # Remote send from DCs (cross-subnet coverage)
                if (-not $Success -and $ReachableDCs.Count -gt 0) {
                    foreach ($DCName in $ReachableDCs) {
                        try {
                            $Result = Invoke-Command -ComputerName $DCName -ArgumentList $MAC, $IP -ScriptBlock {
                                param($MAC, $IP)
                                try {
                                    $MACBytes = $MAC -split '(?<=\G..)' | Where-Object { $_ } |
                                                ForEach-Object { [convert]::ToByte($_, 16) }
                                    $Packet   = [byte[]](, 0xFF * 6) + ($MACBytes * 16)
                                    $UDP      = New-Object System.Net.Sockets.UdpClient
                                    $UDP.Connect($IP, 9)
                                    [void]$UDP.Send($Packet, $Packet.Length)
                                    $UDP.Close()
                                    return $true
                                }
                                catch { return $false }
                            } -ErrorAction Stop
                            if ($Result) { $Success = $true; break }
                        }
                        catch { }
                    }
                }

                return $Success
            }).AddArgument($Target.MAC).AddArgument($Target.IP).AddArgument($ReachableDCs)

            $WOLJobs += [PSCustomObject]@{ Pipe = $PS; Status = $PS.BeginInvoke() }
        }

        foreach ($Job in $WOLJobs) {
            try {
                $Result = $Job.Pipe.EndInvoke($Job.Status)
                if ($Result) { $WOLSuccesses++ } else { $WOLFailures++ }
            }
            catch { $WOLFailures++ }
            $Job.Pipe.Dispose()
        }

        $RunspacePool.Close()
        $RunspacePool.Dispose()

        Write-Log  "WOL complete -- Sent: $WOLSuccesses | Failed: $WOLFailures | Skipped: $WOLSkipped" -Severity INFO
        Write-Console "Sent: $WOLSuccesses" -Severity SUCCESS -Indent 1
        if ($WOLFailures -gt 0) {
            Write-Console "Failed: $WOLFailures" -Severity WARN -Indent 1
        }
        Write-Console "Skipped (no match): $WOLSkipped" -Severity INFO -Indent 1

        # ------------------------------------------------------------------
        # WOL WAIT
        # ------------------------------------------------------------------
        if ($WaitTimeMinutes -gt 0) {
            Write-Section "WOL Wake Wait"
            Write-Log  "Waiting $WaitTimeMinutes minute(s) for computers to wake..." -Severity INFO
            Write-Console "Waiting $WaitTimeMinutes minute(s) for computers to wake..." -Severity INFO
            Start-Sleep -Seconds ($WaitTimeMinutes * 60)
        }
        else {
            Write-Log  "WaitTimeMinutes is 0 -- skipping wake wait." -Severity DEBUG
            Write-Console "WaitTimeMinutes = 0 -- skipping wake wait." -Severity DEBUG
        }

        # ------------------------------------------------------------------
        # PARALLEL PING -- VERIFY ONLINE MACHINES
        # ------------------------------------------------------------------
        Write-Section "Online Verification"
        Write-Log  "Pinging all desktop computers in parallel..." -Severity INFO
        Write-Console "Pinging all desktop computers in parallel..." -Severity INFO

        $Pingable    = @()
        $PingResults = @{}   # Name -> "Online" | "Offline" | "No IP"

        $RunspacePool = [runspacefactory]::CreateRunspacePool(1, 50)
        $RunspacePool.Open()
        $PingJobs = @()

        foreach ($PC in $DesktopsAD) {
            if (-not $PC.IPv4Address) {
                $PingResults[$PC.Name] = "No IP"
                continue
            }

            $PS = [powershell]::Create()
            $PS.RunspacePool = $RunspacePool

            [void]$PS.AddScript({
                param($Computer)
                if (Test-Connection -ComputerName $Computer.IPv4Address -Count 1 -Quiet) {
                    return $Computer
                }
                return $null
            }).AddArgument($PC)

            $PingJobs += [PSCustomObject]@{ Pipe = $PS; Status = $PS.BeginInvoke(); PCName = $PC.Name }
        }

        foreach ($Job in $PingJobs) {
            try {
                $Result = $Job.Pipe.EndInvoke($Job.Status)
                if ($Result) {
                    $Pingable += $Result
                    $PingResults[$Job.PCName] = "Online"
                }
                else {
                    $PingResults[$Job.PCName] = "Offline"
                }
            }
            catch {
                $PingResults[$Job.PCName] = "Offline"
            }
            $Job.Pipe.Dispose()
        }

        $RunspacePool.Close()
        $RunspacePool.Dispose()

        Write-Log  "$($Pingable.Count) desktop(s) responding to ping." -Severity SUCCESS
        Write-Console "$($Pingable.Count) desktop(s) responding to ping." -Severity SUCCESS

        # ------------------------------------------------------------------
        # PARALLEL HARDWARE INVENTORY COLLECTION
        # WinRM-first with DCOM fallback. Partial data is logged and retained.
        # ------------------------------------------------------------------
        Write-Section "Hardware Inventory Collection"
        Write-Log  "Collecting hardware inventory from $($Pingable.Count) online desktop(s)..." -Severity INFO
        Write-Console "Collecting hardware inventory from $($Pingable.Count) online desktop(s)..." -Severity INFO

        $AllHardware      = @()
        $CollectionErrors = @()

        $RunspacePool = [runspacefactory]::CreateRunspacePool(1, 30)
        $RunspacePool.Open()
        $HWJobs = @()

        foreach ($PC in $Pingable) {
            $PS = [powershell]::Create()
            $PS.RunspacePool = $RunspacePool

            [void]$PS.AddScript({
                param($PCName)

                $HWInfo      = $null
                $ErrorDetail = ""
                $Method      = ""

                # WinRM attempt
                try {
                    $HWInfo = Invoke-Command -ComputerName $PCName -ScriptBlock {
                        $CS   = Get-WmiObject -Class Win32_ComputerSystem
                        $OS   = Get-WmiObject -Class Win32_OperatingSystem
                        $BIOS = Get-WmiObject -Class Win32_BIOS
                        [PSCustomObject]@{
                            Name         = $CS.Name
                            Manufacturer = $CS.Manufacturer
                            Model        = $CS.Model
                            SerialNumber = $BIOS.SerialNumber
                            TotalRAM_GB  = [math]::Round($CS.TotalPhysicalMemory / 1GB, 2)
                            OS           = $OS.Caption
                            LastBootTime = $OS.ConvertToDateTime($OS.LastBootUpTime)
                            Domain       = $CS.Domain
                        }
                    } -ErrorAction Stop
                    $Method = "WinRM"
                }
                catch {
                    $ErrorDetail = "WinRM: $($_.Exception.Message)"

                    # DCOM fallback
                    try {
                        $CS   = Get-WmiObject -Class Win32_ComputerSystem   -ComputerName $PCName -ErrorAction Stop
                        $OS   = Get-WmiObject -Class Win32_OperatingSystem   -ComputerName $PCName -ErrorAction Stop
                        $BIOS = Get-WmiObject -Class Win32_BIOS              -ComputerName $PCName -ErrorAction Stop

                        $HWInfo = [PSCustomObject]@{
                            Name         = $CS.Name
                            Manufacturer = $CS.Manufacturer
                            Model        = $CS.Model
                            SerialNumber = $BIOS.SerialNumber
                            TotalRAM_GB  = [math]::Round($CS.TotalPhysicalMemory / 1GB, 2)
                            OS           = $OS.Caption
                            LastBootTime = $OS.ConvertToDateTime($OS.LastBootUpTime)
                            Domain       = $CS.Domain
                        }
                        $Method      = "DCOM"
                        $ErrorDetail = ""
                    }
                    catch {
                        $ErrorDetail += "; DCOM: $($_.Exception.Message)"
                    }
                }

                return [PSCustomObject]@{
                    Hardware = $HWInfo
                    Error    = $ErrorDetail
                    Method   = $Method
                }
            }).AddArgument($PC.Name)

            $HWJobs += [PSCustomObject]@{
                Pipe   = $PS
                Status = $PS.BeginInvoke()
                PCName = $PC.Name
                PC     = $PC
            }
        }

        # Collect hardware results
        foreach ($Job in $HWJobs) {
            try {
                $Result = $Job.Pipe.EndInvoke($Job.Status)

                if ($Result.Hardware) {
                    # Check for missing/null fields -- still keep partial data
                    $MissingFields = @()
                    if ([string]::IsNullOrWhiteSpace($Result.Hardware.Manufacturer))                                  { $MissingFields += "Manufacturer" }
                    if ([string]::IsNullOrWhiteSpace($Result.Hardware.Model))                                         { $MissingFields += "Model"        }
                    if ([string]::IsNullOrWhiteSpace($Result.Hardware.SerialNumber))                                  { $MissingFields += "SerialNumber" }
                    if ([string]::IsNullOrWhiteSpace($Result.Hardware.TotalRAM_GB) -or
                        $Result.Hardware.TotalRAM_GB -eq 0)                                                           { $MissingFields += "RAM"          }

                    $AllHardware += $Result.Hardware

                    if ($MissingFields.Count -gt 0) {
                        Write-Log  "Partial data for $($Job.PCName): missing $($MissingFields -join ', ')" -Severity WARN

                        $CollectionErrors += [PSCustomObject]@{
                            ComputerName     = $Job.PCName
                            IPv4Address      = $Job.PC.IPv4Address
                            LastLogonDate    = $Job.PC.LastLogonDate
                            PingStatus       = "Online"
                            CollectionStatus = "Partial Data"
                            FailureReason    = "Some fields returned null/empty"
                            MissingFields    = ($MissingFields -join ", ")
                            AttemptDateTime  = $ScriptStart
                            HasCachedData    = if ($CachedHardware.ContainsKey($Job.PCName.ToUpper())) {
                                "Yes (from $($CachedHardware[$Job.PCName.ToUpper()].LastInventoried))" } else { "No" }
                        }
                    }
                }
                else {
                    # Total failure -- no hardware data returned at all
                    Write-Log  "Hardware collection failed for $($Job.PCName): $($Result.Error)" -Severity WARN

                    $CollectionErrors += [PSCustomObject]@{
                        ComputerName     = $Job.PCName
                        IPv4Address      = $Job.PC.IPv4Address
                        LastLogonDate    = $Job.PC.LastLogonDate
                        PingStatus       = "Online"
                        CollectionStatus = "Failed - WinRM/DCOM"
                        FailureReason    = $Result.Error
                        MissingFields    = "(n/a)"
                        AttemptDateTime  = $ScriptStart
                        HasCachedData    = if ($CachedHardware.ContainsKey($Job.PCName.ToUpper())) {
                            "Yes (from $($CachedHardware[$Job.PCName.ToUpper()].LastInventoried))" } else { "No" }
                    }
                }
            }
            catch {
                Write-Log  "Runspace job exception for $($Job.PCName): $_" -Severity ERROR

                $CollectionErrors += [PSCustomObject]@{
                    ComputerName     = $Job.PCName
                    IPv4Address      = $Job.PC.IPv4Address
                    LastLogonDate    = $Job.PC.LastLogonDate
                    PingStatus       = "Online"
                    CollectionStatus = "Failed - Job Exception"
                    FailureReason    = $_.Exception.Message
                    MissingFields    = "(n/a)"
                    AttemptDateTime  = $ScriptStart
                    HasCachedData    = if ($CachedHardware.ContainsKey($Job.PCName.ToUpper())) {
                        "Yes (from $($CachedHardware[$Job.PCName.ToUpper()].LastInventoried))" } else { "No" }
                }
            }
            $Job.Pipe.Dispose()
        }

        $RunspacePool.Close()
        $RunspacePool.Dispose()

        Write-Log  "Hardware collected from $($AllHardware.Count) computer(s)." -Severity SUCCESS
        Write-Console "Hardware collected from $($AllHardware.Count) computer(s)." -Severity SUCCESS

        # Log offline/no-IP machines to the error report
        foreach ($PC in $DesktopsAD) {
            $PingStatus = $PingResults[$PC.Name]

            if ($PingStatus -eq "Offline") {
                $CollectionErrors += [PSCustomObject]@{
                    ComputerName     = $PC.Name
                    IPv4Address      = if ($PC.IPv4Address) { $PC.IPv4Address } else { "(none)" }
                    LastLogonDate    = $PC.LastLogonDate
                    PingStatus       = "Offline"
                    CollectionStatus = "Skipped - Offline"
                    FailureReason    = "No response to ping after WOL"
                    MissingFields    = "(n/a)"
                    AttemptDateTime  = $ScriptStart
                    HasCachedData    = if ($CachedHardware.ContainsKey($PC.Name.ToUpper())) {
                        "Yes (from $($CachedHardware[$PC.Name.ToUpper()].LastInventoried))" } else { "No" }
                }
            }
            elseif ($PingStatus -eq "No IP") {
                $CollectionErrors += [PSCustomObject]@{
                    ComputerName     = $PC.Name
                    IPv4Address      = "(none)"
                    LastLogonDate    = $PC.LastLogonDate
                    PingStatus       = "Unknown"
                    CollectionStatus = "Skipped - No IP"
                    FailureReason    = "No IPv4 address in Active Directory"
                    MissingFields    = "(n/a)"
                    AttemptDateTime  = $ScriptStart
                    HasCachedData    = if ($CachedHardware.ContainsKey($PC.Name.ToUpper())) {
                        "Yes (from $($CachedHardware[$PC.Name.ToUpper()].LastInventoried))" } else { "No" }
                }
            }
        }

        # ------------------------------------------------------------------
        # MERGE: FRESH + CACHED HARDWARE
        # Priority: fresh data > cached data > empty record
        # ------------------------------------------------------------------
        Write-Section "Merging Inventory Data"
        Write-Log  "Merging fresh hardware data with cache..." -Severity INFO
        Write-Console "Merging fresh hardware data with cache..." -Severity INFO

        $FinalInventory = @()
        $FreshDataCount = 0
        $UsedCacheCount = 0

        foreach ($Desktop in $DesktopsAD) {
            $FreshHW = $AllHardware | Where-Object { $_.Name -eq $Desktop.Name } | Select-Object -First 1

            if ($FreshHW) {
                $FinalInventory += [PSCustomObject]@{
                    Name            = $Desktop.Name
                    OperatingSystem = $Desktop.OperatingSystem
                    LastLogonDate   = $Desktop.LastLogonDate
                    Enabled         = $Desktop.Enabled
                    IPv4Address     = $Desktop.IPv4Address
                    Description     = $Desktop.Description
                    Manufacturer    = $FreshHW.Manufacturer
                    Model           = $FreshHW.Model
                    SerialNumber    = $FreshHW.SerialNumber
                    TotalRAM_GB     = $FreshHW.TotalRAM_GB
                    OS              = $FreshHW.OS
                    LastBootTime    = $FreshHW.LastBootTime
                    Domain          = $FreshHW.Domain
                    LastInventoried = $ScriptStart.ToString("yyyy-MM-dd HH:mm:ss")
                }
                $FreshDataCount++
            }
            elseif ($CachedHardware.ContainsKey($Desktop.Name.ToUpper())) {
                $CachedHW = $CachedHardware[$Desktop.Name.ToUpper()]
                $FinalInventory += [PSCustomObject]@{
                    Name            = $Desktop.Name
                    OperatingSystem = $Desktop.OperatingSystem
                    LastLogonDate   = $Desktop.LastLogonDate
                    Enabled         = $Desktop.Enabled
                    IPv4Address     = $Desktop.IPv4Address
                    Description     = $Desktop.Description
                    Manufacturer    = $CachedHW.Manufacturer
                    Model           = $CachedHW.Model
                    SerialNumber    = $CachedHW.SerialNumber
                    TotalRAM_GB     = $CachedHW.TotalRAM_GB
                    OS              = $CachedHW.OS
                    LastBootTime    = $CachedHW.LastBootTime
                    Domain          = $CachedHW.Domain
                    LastInventoried = $CachedHW.LastInventoried    # Preserved -- keep original date
                }
                $UsedCacheCount++
            }
            else {
                # No data available (new machine or never collected)
                $FinalInventory += [PSCustomObject]@{
                    Name            = $Desktop.Name
                    OperatingSystem = $Desktop.OperatingSystem
                    LastLogonDate   = $Desktop.LastLogonDate
                    Enabled         = $Desktop.Enabled
                    IPv4Address     = $Desktop.IPv4Address
                    Description     = $Desktop.Description
                    Manufacturer    = ""
                    Model           = ""
                    SerialNumber    = ""
                    TotalRAM_GB     = ""
                    OS              = ""
                    LastBootTime    = ""
                    Domain          = ""
                    LastInventoried = ""
                }
            }
        }

        $NoDataCount = $DesktopsAD.Count - $FreshDataCount - $UsedCacheCount
        Write-Log  "Merge complete -- Fresh: $FreshDataCount | Cached: $UsedCacheCount | No data: $NoDataCount" -Severity SUCCESS
        Write-Console "Fresh: $FreshDataCount" -Severity SUCCESS -Indent 1
        Write-Console "Cached: $UsedCacheCount" -Severity INFO -Indent 1
        if ($NoDataCount -gt 0) {
            Write-Console "No data: $NoDataCount" -Severity WARN -Indent 1
        }
        else {
            Write-Console "No data: $NoDataCount" -Severity INFO -Indent 1
        }

        # ------------------------------------------------------------------
        # EXPORT CSV FILES
        # ------------------------------------------------------------------
        Write-Section "CSV Export"
        Write-Log  "Exporting data to CSV files..." -Severity INFO
        Write-Console "Exporting data to CSV files..." -Severity INFO

        # AD data exports
        $UsersAD | Export-Csv -Path (Join-Path $DataFolder "usersAD.csv") -NoTypeInformation -Encoding UTF8
        Write-Log  "Exported usersAD.csv ($($UsersAD.Count) users)" -Severity SUCCESS
        Write-Console "usersAD.csv ($($UsersAD.Count) users)" -Severity SUCCESS -Indent 1

        $ServersAD | Export-Csv -Path (Join-Path $DataFolder "serversAD.csv") -NoTypeInformation -Encoding UTF8
        Write-Log  "Exported serversAD.csv ($($ServersAD.Count) servers)" -Severity SUCCESS
        Write-Console "serversAD.csv ($($ServersAD.Count) servers)" -Severity SUCCESS -Indent 1

        $DesktopsAD | Export-Csv -Path (Join-Path $DataFolder "desktopsAD.csv") -NoTypeInformation -Encoding UTF8
        Write-Log  "Exported desktopsAD.csv ($($DesktopsAD.Count) desktops)" -Severity SUCCESS
        Write-Console "desktopsAD.csv ($($DesktopsAD.Count) desktops)" -Severity SUCCESS -Indent 1

        # Fresh hardware only (raw, this run)
        if ($AllHardware.Count -gt 0) {
            $AllHardware | Export-Csv -Path (Join-Path $DataFolder "desktopsMODELS.csv") -NoTypeInformation -Encoding UTF8
            Write-Log  "Exported desktopsMODELS.csv ($($AllHardware.Count) fresh collections)" -Severity SUCCESS
            Write-Console "desktopsMODELS.csv ($($AllHardware.Count) fresh)" -Severity SUCCESS -Indent 1
        }

        # Merged final inventory
        $FinalInventory | Export-Csv -Path (Join-Path $DataFolder "desktopsFINAL.csv") -NoTypeInformation -Encoding UTF8
        Write-Log  "Exported desktopsFINAL.csv ($($FinalInventory.Count) desktops, fresh + cached)" -Severity SUCCESS
        Write-Console "desktopsFINAL.csv ($($FinalInventory.Count) desktops, fresh + cached)" -Severity SUCCESS -Indent 1

        # Error/skip report
        if ($CollectionErrors.Count -gt 0) {
            $CollectionErrors | Export-Csv -Path (Join-Path $DataFolder "ADCollectionErrorReport.csv") -NoTypeInformation -Encoding UTF8
            Write-Log  "Exported ADCollectionErrorReport.csv ($($CollectionErrors.Count) entries)" -Severity WARN
            Write-Console "ADCollectionErrorReport.csv ($($CollectionErrors.Count) entries)" -Severity WARN -Indent 1
        }
        else {
            Write-Log  "No collection errors to report." -Severity SUCCESS
            Write-Console "No collection errors to report." -Severity SUCCESS -Indent 1
        }

        # Removed computers log
        if ($RemovedComputers.Count -gt 0) {
            $RemovedComputers | Export-Csv -Path (Join-Path $DataFolder "RemovedFromAD.csv") -NoTypeInformation -Encoding UTF8
            Write-Log  "Exported RemovedFromAD.csv ($($RemovedComputers.Count) computers)" -Severity WARN
            Write-Console "RemovedFromAD.csv ($($RemovedComputers.Count) removed)" -Severity WARN -Indent 1
        }

        # Legacy compatibility export
        $DesktopsAD | Export-Csv -Path (Join-Path $DataFolder "desktopsSERIAL.csv") -NoTypeInformation -Encoding UTF8
        Write-Log  "Exported desktopsSERIAL.csv (legacy format)" -Severity DEBUG
        Write-Console "desktopsSERIAL.csv (legacy format)" -Severity DEBUG -Indent 1

        # ------------------------------------------------------------------
        # FINAL SUMMARY
        # ------------------------------------------------------------------
        $ScriptEnd = Get-Date
        $Runtime   = $ScriptEnd - $ScriptStart

        $SuccessRate = if ($Pingable.Count -gt 0) {
            [math]::Round(($FreshDataCount / $Pingable.Count) * 100, 1)
        } else { 0 }

        Write-Log "" -Severity INFO
        Write-Log "===== RUN SUMMARY =====" -Severity INFO
        Write-Log "AD Users             : $($UsersAD.Count)"     -Severity INFO
        Write-Log "AD Servers           : $($ServersAD.Count)"   -Severity INFO
        Write-Log "AD Desktops          : $($DesktopsAD.Count)"  -Severity INFO
        Write-Log "Desktops Online      : $($Pingable.Count)"    -Severity INFO
        Write-Log "Fresh HW Collected   : $FreshDataCount"       -Severity INFO
        Write-Log "Using Cached HW      : $UsedCacheCount"       -Severity INFO
        Write-Log "No HW Data           : $NoDataCount"          -Severity INFO
        Write-Log "Collection Rate      : $SuccessRate% (of online)" -Severity INFO
        if ($UnreachableDCs.Count -gt 0) {
            Write-Log "Unreachable DCs      : $($UnreachableDCs -join ', ')" -Severity WARN
        }
        if ($CollectionErrors.Count -gt 0) {
            Write-Log "Collection Errors    : $($CollectionErrors.Count)" -Severity WARN
        }
        if ($RemovedComputers.Count -gt 0) {
            Write-Log "Removed from AD      : $($RemovedComputers.Count)" -Severity WARN
        }
        Write-Log "Runtime              : $($Runtime.ToString('hh\:mm\:ss'))" -Severity INFO
        Write-Log "Output               : $DataFolder" -Severity INFO
        Write-Log "Script completed successfully." -Severity SUCCESS

        Write-Banner "ACTIVE DIRECTORY SUMMARY" -Color "White"
        Write-Console "User Accounts   : $($UsersAD.Count)"                                       -Severity PLAIN
        Write-Console "Servers         : $($ServersAD.Count)"                                     -Severity PLAIN
        Write-Console "Desktops        : $($DesktopsAD.Count)"                                    -Severity PLAIN
        Write-Separator

        Write-Console "Desktops Online : $($Pingable.Count)"                                      -Severity PLAIN
        Write-Console "Fresh HW        : $FreshDataCount"                                         -Severity SUCCESS
        Write-Console "Cached HW       : $UsedCacheCount"                                         -Severity INFO
        Write-Console "No Data         : $NoDataCount"                                            -Severity $(if ($NoDataCount -gt 0) { "WARN" } else { "INFO" })
        Write-Console "Success Rate    : $SuccessRate% (of online PCs)"                           -Severity $(if ($SuccessRate -ge 90) { "SUCCESS" } elseif ($SuccessRate -ge 70) { "WARN" } else { "ERROR" })
        Write-Separator

        if ($UnreachableDCs.Count -gt 0) {
            Write-Console "Unreachable DCs : $($UnreachableDCs -join ', ')"                       -Severity WARN
        }
        if ($CollectionErrors.Count -gt 0) {
            Write-Console "Errors/Skips    : $($CollectionErrors.Count) -- see ADCollectionErrorReport.csv" -Severity WARN
        }
        if ($RemovedComputers.Count -gt 0) {
            Write-Console "Removed from AD : $($RemovedComputers.Count) -- see RemovedFromAD.csv"  -Severity WARN
        }
        Write-Separator

        Write-Console "Runtime  : $($Runtime.ToString('hh\:mm\:ss'))" -Severity PLAIN
        Write-Console "Output   : $DataFolder"                         -Severity PLAIN

        Write-Banner "INVENTORY COLLECTION COMPLETE" -Color "Green"

        exit 0

    }
    catch {
        Write-Log "Unhandled exception: $_"             -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR

        Write-Banner "SCRIPT FAILED" -Color "Red"
        Write-Console "Error: $_"    -Severity ERROR

        exit 1
    }

} # End function Start-ADInventoryCollection

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    DataFolder      = $DataFolder
    WaitTimeMinutes = $WaitTimeMinutes
    SiteName        = $SiteName
    Hostname        = $Hostname
}

Start-ADInventoryCollection @ScriptParams
