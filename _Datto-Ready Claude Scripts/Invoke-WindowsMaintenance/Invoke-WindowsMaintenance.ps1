#Requires -Version 5.1
<#
.SYNOPSIS
    Comprehensive Windows system integrity and maintenance script covering SFC,
    DISM, CHKDSK, and drive optimization with full automation and RMM support.

.DESCRIPTION
    Performs a structured, multi-phase Windows maintenance pass on the local machine.
    Designed for both automated DattoRMM deployment and interactive technician use.

    Phases (in order):
      1. Pre-flight   — Elevation check, OS/volume/disk inventory, dirty-bit detection
      2. SFC Pass 1   — System File Checker initial scan
      3. DISM         — CheckHealth → ScanHealth → RestoreHealth (if needed)
      4. SFC Pass 2   — Re-verify after DISM repair (triple-pass strategy)
      5. CHKDSK       — Online scan per volume; schedules offline /F /R on errors/dirty
      6. Optimization — Defrag (HDD) or retrim (SSD) per volume; skipped in Server profile
                        unless explicitly unlocked
      7. Cleanup      — Optional WinSxS component cleanup (off by default)
      8. Summary      — Consolidated results, reboot recommendations, bitfield exit code

    Execution Profiles (set via -Profile):
      Workstation     — Full maintenance. All phases run by default.
      Server          — Conservative. Optimization and ComponentCleanup disabled
                        regardless of individual switches. Reboot recommendation is
                        extra-explicit. Intended for routine scheduled runs.
      ServerAggressive — Server context with optimization and cleanup unlocked.
                        Use during planned maintenance windows only.

    Individual override switches (-RunOptimization, -RunComponentCleanup,
    -SkipSFC, -SkipDISM, -SkipCHKDSK, -SkipOptimization) allow punching holes in
    or bolting onto profile defaults without changing the profile itself.

    Exit Code Design (bitfield — codes are additive):
        0   = Clean run, no issues, no reboot needed
        1   = General / unhandled script failure
        2   = Reboot recommended (CHKDSK queued, SFC/DISM repaired files, etc.)
        4   = SFC reported errors but could not repair
        8   = DISM RestoreHealth failed
        16  = CHKDSK scheduling failed for one or more volumes
        32  = Drive optimization failed for one or more volumes
        64  = Pre-flight warning (non-fatal — low disk space, dirty volume found, etc.)

    Multiple failure codes are summed. Example: DISM failed + CHKDSK scheduling
    failed + reboot recommended = 8 + 16 + 2 = 26.
    Code 1 is reserved for unhandled exceptions and is never combined.

    Reboot Behavior:
      The script NEVER triggers a reboot. When a reboot is recommended, it sets
      the reboot flag (exit code bit 2) and outputs a consolidated REBOOT RECOMMENDED
      block at the end of the run listing all reasons. The calling system (DattoRMM,
      technician) is responsible for acting on the recommendation.

    Prerequisites:
      - Must run as Administrator (or SYSTEM via DattoRMM)
      - Windows 10 / Server 2016 or newer recommended
      - No external modules required — uses only built-in Windows tools

.PARAMETER Profile
    Execution profile controlling default phase behavior.
    Valid values: Workstation | Server | ServerAggressive
    Default: Workstation

.PARAMETER SkipSFC
    [Switch] Skip both SFC passes entirely. Overrides profile.

.PARAMETER SkipDISM
    [Switch] Skip all DISM phases. Overrides profile.

.PARAMETER SkipCHKDSK
    [Switch] Skip CHKDSK scan and scheduling. Overrides profile.

.PARAMETER SkipOptimization
    [Switch] Skip drive optimization phase. Overrides profile.

.PARAMETER RunOptimization
    [Switch] Force-enable drive optimization even when profile would disable it
    (e.g., Server profile). Has no effect if -SkipOptimization is also set.

.PARAMETER RunComponentCleanup
    [Switch] Enable DISM WinSxS component cleanup (/StartComponentCleanup).
    Off by default in all profiles. Irreversible on Server — use with care.

.PARAMETER TargetVolumes
    Comma-separated list of drive letters to target for CHKDSK and optimization.
    Example: "C,D,E"
    Default: All fixed NTFS/ReFS volumes detected on the system.

.PARAMETER MinFreeSpacePct
    Minimum free space percentage required to allow defrag on an HDD volume.
    Volumes below this threshold are skipped with a warning.
    Default: 10

.PARAMETER SiteName
    Site/customer name. Auto-populated from DattoRMM env var CS_PROFILE_NAME.
    Falls back to manual parameter, then 'UnknownSite'.

.PARAMETER Hostname
    Target machine hostname. Auto-populated from DattoRMM env var CS_HOSTNAME.
    Falls back to $env:COMPUTERNAME.

.EXAMPLE
    .\Invoke-WindowsMaintenance.ps1
    Runs full workstation maintenance with all defaults. Suitable for DattoRMM
    deployment against endpoints.

.EXAMPLE
    .\Invoke-WindowsMaintenance.ps1 -Profile Server
    Runs conservative server maintenance — SFC/DISM/CHKDSK only, no optimization
    or component cleanup, extra-explicit reboot warnings.

.EXAMPLE
    .\Invoke-WindowsMaintenance.ps1 -Profile ServerAggressive -RunComponentCleanup
    Full server maintenance with optimization and WinSxS cleanup enabled.
    Use during a planned maintenance window.

.EXAMPLE
    .\Invoke-WindowsMaintenance.ps1 -Profile Workstation -SkipOptimization -TargetVolumes "C"
    Workstation profile, only target C: drive, skip optimization phase.

.EXAMPLE
    .\Invoke-WindowsMaintenance.ps1 -Profile Workstation -RunComponentCleanup -MinFreeSpacePct 15
    Workstation with WinSxS cleanup enabled and a 15% free space floor for defrag.

.NOTES
    File Name      : Invoke-WindowsMaintenance.ps1
    Version        : 1.0.0.2
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-02-21
    Last Modified  : 2026-02-21
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM (DattoRMM) or local/domain Administrator
    DattoRMM       : Compatible — supports environment variable input
    Client Scope   : All clients

    Exit Codes (bitfield — additive):
        0   = Success, no issues
        1   = General / unhandled failure (never combined)
        2   = Reboot recommended
        4   = SFC errors not repairable
        8   = DISM RestoreHealth failed
        16  = CHKDSK scheduling failed
        32  = Drive optimization failed
        64  = Pre-flight warning (non-fatal)

    Output Design:
        Write-Log     - Structured [timestamp][SEVERITY] output to log file AND
                        DattoRMM stdout. Always verbose. No color.
        Write-Console - Human-friendly colored console output for manual/interactive
                        runs. Uses Write-Host (display stream only). Suppressed in
                        DattoRMM agent context automatically.

.CHANGELOG
    v1.0.0.2 - 2026-02-21 - Sam Kirsch
        - Fixed remaining $PassLabel: variable-colon parser errors in Invoke-SFCScan
          (lines 719, 724, 730, 737). Same root cause as v1.0.0.1 fix — all
          $VarName: patterns in double-quoted strings now use $($VarName): form.

    v1.0.0.1 - 2026-02-21 - Sam Kirsch
        - Fixed parser error: $Letter: in double-quoted string on pre-flight
          volume-not-found warning. Wrapped in $($Letter) to prevent PowerShell
          from interpreting : as a variable scope modifier.

    v1.0.0.0 - 2026-02-21 - Sam Kirsch
        - Initial release
        - Triple-pass SFC/DISM/SFC strategy
        - Profile-based execution (Workstation / Server / ServerAggressive)
        - Per-volume CHKDSK with dirty-bit detection and offline scan scheduling
        - Media-type-aware optimization (defrag HDD, retrim SSD, skip VM/unknown)
        - Bitfield exit code system for granular DattoRMM alerting
        - Consolidated reboot recommendation block at end of run
        - Optional WinSxS component cleanup (off by default)
        - Individual phase skip/force switches for per-run override
        - Dual-output pattern (Write-Log + Write-Console)
        - Full DattoRMM env var / parameter / default fallback chain
#>

# ==============================================================================
# PARAMETERS
# DattoRMM env vars take precedence; falls back to passed params or defaults.
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Workstation", "Server", "ServerAggressive")]
    [string]$Profile = $(if ($env:WM_Profile) { $env:WM_Profile } else { "Workstation" }),

    [Parameter(Mandatory = $false)]
    [switch]$SkipSFC = $(if ($env:WM_SkipSFC -eq "true") { $true } else { $false }),

    [Parameter(Mandatory = $false)]
    [switch]$SkipDISM = $(if ($env:WM_SkipDISM -eq "true") { $true } else { $false }),

    [Parameter(Mandatory = $false)]
    [switch]$SkipCHKDSK = $(if ($env:WM_SkipCHKDSK -eq "true") { $true } else { $false }),

    [Parameter(Mandatory = $false)]
    [switch]$SkipOptimization = $(if ($env:WM_SkipOptimization -eq "true") { $true } else { $false }),

    [Parameter(Mandatory = $false)]
    [switch]$RunOptimization = $(if ($env:WM_RunOptimization -eq "true") { $true } else { $false }),

    [Parameter(Mandatory = $false)]
    [switch]$RunComponentCleanup = $(if ($env:WM_RunComponentCleanup -eq "true") { $true } else { $false }),

    [Parameter(Mandatory = $false)]
    [string]$TargetVolumes = $(if ($env:WM_TargetVolumes) { $env:WM_TargetVolumes } else { "" }),

    [Parameter(Mandatory = $false)]
    [int]$MinFreeSpacePct = $(if ($env:WM_MinFreeSpacePct) { [int]$env:WM_MinFreeSpacePct } else { 10 }),

    # DattoRMM built-in variables — auto-populated, no component config needed
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Invoke-WindowsMaintenance {
    <#
    .SYNOPSIS
        Internal master function. See script-level help for full documentation.
    #>
    [CmdletBinding()]
    param (
        [string]$Profile,
        [switch]$SkipSFC,
        [switch]$SkipDISM,
        [switch]$SkipCHKDSK,
        [switch]$SkipOptimization,
        [switch]$RunOptimization,
        [switch]$RunComponentCleanup,
        [string]$TargetVolumes,
        [int]$MinFreeSpacePct,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Invoke-WindowsMaintenance"
    $ScriptVersion = "1.0.0.2"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path -Path $LogRoot -ChildPath $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path -Path $LogFolder -ChildPath "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # ==========================================================================
    # EXIT CODE CONSTANTS (bitfield)
    # ==========================================================================
    $EXIT_SUCCESS           = 0
    $EXIT_GENERAL_FAILURE   = 1
    $EXIT_REBOOT_RECOMMENDED = 2
    $EXIT_SFC_UNREPAIRABLE  = 4
    $EXIT_DISM_FAILED       = 8
    $EXIT_CHKDSK_SCHED_FAIL = 16
    $EXIT_OPTIM_FAILED      = 32
    $EXIT_PREFLIGHT_WARN    = 64

    # Accumulator — bits are OR'd in as phases complete
    $script:ExitCode = $EXIT_SUCCESS

    # ==========================================================================
    # REBOOT RECOMMENDATION ACCUMULATOR
    # Each phase appends a reason string here if a reboot is warranted.
    # Displayed as a consolidated block in the final summary.
    # ==========================================================================
    $script:RebootReasons = [System.Collections.Generic.List[string]]::new()

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
    # WRITE-CONSOLE  (Presentation Layer — display stream only)
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
            Write-Host " $Message" -ForegroundColor White
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
    # HELPER: Add-RebootReason
    # Records a reboot reason and sets the reboot exit code bit.
    # ==========================================================================
    function Add-RebootReason {
        param ([Parameter(Mandatory = $true)] [string]$Reason)
        $script:RebootReasons.Add($Reason)
        $script:ExitCode = $script:ExitCode -bor $EXIT_REBOOT_RECOMMENDED
    }

    # ==========================================================================
    # HELPER: Set-ExitCodeBit
    # OR's a failure bit into the accumulator.
    # ==========================================================================
    function Set-ExitCodeBit {
        param ([Parameter(Mandatory = $true)] [int]$Bit)
        $script:ExitCode = $script:ExitCode -bor $Bit
    }

    # ==========================================================================
    # PHASE: PRE-FLIGHT
    # Checks elevation, detects OS type, enumerates volumes and physical disks,
    # builds a volume→mediatype map, checks dirty bits.
    # Returns a hashtable of volume info used by downstream phases.
    # ==========================================================================
    function Invoke-PreFlight {
        Write-Section "Pre-Flight Checks"
        Write-Log "Starting pre-flight checks..." -Severity INFO
        Write-Console "Starting pre-flight checks..." -Severity INFO

        # --- Elevation check ---
        $IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)

        if (-not $IsAdmin) {
            Write-Log "Script is NOT running as Administrator. Elevation required." -Severity ERROR
            Write-Console "Script is NOT running as Administrator. Elevation required." -Severity ERROR
            # Fatal — cannot proceed
            Set-ExitCodeBit -Bit $EXIT_GENERAL_FAILURE
            return $null
        }
        Write-Log "Elevation: Running as Administrator." -Severity SUCCESS
        Write-Console "Elevation: Running as Administrator." -Severity SUCCESS

        # --- OS detection ---
        $OS = Get-CimInstance -ClassName Win32_OperatingSystem
        $OSCaption = $OS.Caption
        $OSBuild   = $OS.BuildNumber
        $IsServer  = $OSCaption -match "Server"

        Write-Log "OS: $OSCaption (Build $OSBuild)" -Severity INFO
        Write-Console "OS: $OSCaption (Build $OSBuild)" -Severity INFO

        if ($IsServer -and $Profile -eq "Workstation") {
            Write-Log "WARNING: Server OS detected but Profile is set to 'Workstation'. Consider using 'Server' or 'ServerAggressive'." -Severity WARN
            Write-Console "Server OS detected with Workstation profile — consider using Server or ServerAggressive." -Severity WARN
            Set-ExitCodeBit -Bit $EXIT_PREFLIGHT_WARN
        }

        # --- Volume and physical disk enumeration ---
        # Build a map: DriveLetter -> [FileSystem, Size, FreeSpace, MediaType, IsVirtual, IsDirty]
        $VolumeMap = @{}

        try {
            # Get all fixed volumes with a drive letter
            $Volumes = Get-Volume | Where-Object {
                $_.DriveType -eq 'Fixed' -and
                $_.DriveLetter -and
                $_.FileSystemType -in @('NTFS', 'ReFS', 'FAT32', 'exFAT')
            }

            # Get physical disk info for media type detection
            # Win32_DiskDrive → partition → logical disk mapping
            $DiskMap = @{}  # DriveLetter -> MediaType

            try {
                $DiskDrives = Get-CimInstance -ClassName Win32_DiskDrive
                foreach ($Disk in $DiskDrives) {
                    $Partitions = Get-CimAssociatedInstance -InputObject $Disk -ResultClassName Win32_DiskPartition
                    foreach ($Partition in $Partitions) {
                        $LogicalDisks = Get-CimAssociatedInstance -InputObject $Partition -ResultClassName Win32_LogicalDisk
                        foreach ($LD in $LogicalDisks) {
                            $Letter = $LD.DeviceID.TrimEnd(':')
                            # MediaType: 3 = HDD, 4 = SSD (for older Win32 classes)
                            # Prefer Get-PhysicalDisk if available for better accuracy
                            $DiskMap[$Letter] = @{
                                Model      = $Disk.Model
                                Size       = $Disk.Size
                                MediaType  = $Disk.MediaType   # may be empty on some hardware
                            }
                        }
                    }
                }
            }
            catch {
                Write-Log "Win32_DiskDrive mapping failed (non-fatal): $_" -Severity DEBUG
                Write-Console "Win32_DiskDrive mapping failed (non-fatal)." -Severity DEBUG -Indent 1
            }

            # Get-PhysicalDisk provides more reliable MediaType on modern systems
            $PhysicalDiskMap = @{}  # FriendlyName -> MediaType
            try {
                $PhysicalDisks = Get-PhysicalDisk
                foreach ($PD in $PhysicalDisks) {
                    $PhysicalDiskMap[$PD.FriendlyName] = $PD.MediaType
                }
            }
            catch {
                Write-Log "Get-PhysicalDisk failed (non-fatal — may be unavailable on this OS): $_" -Severity DEBUG
            }

            # Re-map drive letters to media type using Get-PhysicalDisk data where available
            # Cross-reference DiskMap model names against PhysicalDiskMap friendly names
            foreach ($Letter in $DiskMap.Keys) {
                $Model = $DiskMap[$Letter].Model
                if ($PhysicalDiskMap.ContainsKey($Model)) {
                    $DiskMap[$Letter].MediaType = $PhysicalDiskMap[$Model]
                }
            }

            # Detect VM / virtual disk environment
            $IsVM = $false
            try {
                $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
                $VMIndicators   = @("Virtual", "VMware", "Hyper-V", "VirtualBox", "QEMU", "Xen", "KVM")
                foreach ($Indicator in $VMIndicators) {
                    if ($ComputerSystem.Model -match $Indicator -or $ComputerSystem.Manufacturer -match $Indicator) {
                        $IsVM = $true
                        break
                    }
                }
                # Also check BIOS for hypervisor signatures
                $BIOS = Get-CimInstance -ClassName Win32_BIOS
                if ($BIOS.Version -match "VBOX|VMWARE|BOCHS|QEMU|HVRS") { $IsVM = $true }
            }
            catch {
                Write-Log "VM detection check failed (non-fatal): $_" -Severity DEBUG
            }

            if ($IsVM) {
                Write-Log "Virtual machine detected. Drive optimization will be skipped (hypervisor manages storage)." -Severity WARN
                Write-Console "Virtual machine detected — drive optimization will be skipped." -Severity WARN
                Set-ExitCodeBit -Bit $EXIT_PREFLIGHT_WARN
            }

            # Determine which volumes to target
            $TargetLetters = @()
            if ($TargetVolumes -and $TargetVolumes.Trim() -ne "") {
                # Parse comma-separated drive letters from parameter
                $TargetLetters = $TargetVolumes -split "," | ForEach-Object { $_.Trim().TrimEnd(':').ToUpper() }
                Write-Log "Target volumes (from parameter): $($TargetLetters -join ', ')" -Severity INFO
                Write-Console "Target volumes (from parameter): $($TargetLetters -join ', ')" -Severity INFO
            }
            else {
                # Default: all detected fixed volumes
                $TargetLetters = $Volumes | ForEach-Object { $_.DriveLetter }
                Write-Log "Target volumes (auto-detected): $($TargetLetters -join ', ')" -Severity INFO
                Write-Console "Target volumes (auto-detected): $($TargetLetters -join ', ')" -Severity INFO
            }

            # Build the VolumeMap for each target letter
            foreach ($Letter in $TargetLetters) {
                $Vol = $Volumes | Where-Object { $_.DriveLetter -eq $Letter }
                if (-not $Vol) {
                    Write-Log "Volume '$Letter' not found or not a fixed NTFS/ReFS volume — skipping." -Severity WARN
                    Write-Console "Volume '$($Letter):' not found or not a fixed volume — skipping." -Severity WARN -Indent 1
                    Set-ExitCodeBit -Bit $EXIT_PREFLIGHT_WARN
                    continue
                }

                # Determine media type string
                $MediaType = "Unknown"
                if ($IsVM) {
                    $MediaType = "VirtualDisk"
                }
                elseif ($DiskMap.ContainsKey($Letter)) {
                    $RawType = $DiskMap[$Letter].MediaType
                    switch -Wildcard ($RawType) {
                        "*SSD*"             { $MediaType = "SSD" }
                        "*Solid*"           { $MediaType = "SSD" }
                        "4"                 { $MediaType = "SSD" }
                        "*HDD*"             { $MediaType = "HDD" }
                        "*Hard Disk*"       { $MediaType = "HDD" }
                        "3"                 { $MediaType = "HDD" }
                        default             { $MediaType = "Unknown" }
                    }
                }

                # Dirty bit check via fsutil
                $IsDirty = $false
                try {
                    $FsutilOutput = & fsutil dirty query "$($Letter):" 2>&1
                    if ($FsutilOutput -match "is Dirty") {
                        $IsDirty = $true
                    }
                }
                catch {
                    Write-Log "fsutil dirty query failed for $($Letter): (non-fatal): $_" -Severity DEBUG
                }

                # Free space percentage
                $FreePct = 0
                if ($Vol.Size -gt 0) {
                    $FreePct = [Math]::Round(($Vol.SizeRemaining / $Vol.Size) * 100, 1)
                }

                $VolumeMap[$Letter] = @{
                    DriveLetter   = $Letter
                    FileSystem    = $Vol.FileSystemType
                    SizeGB        = [Math]::Round($Vol.Size / 1GB, 2)
                    FreeGB        = [Math]::Round($Vol.SizeRemaining / 1GB, 2)
                    FreePct       = $FreePct
                    MediaType     = $MediaType
                    IsDirty       = $IsDirty
                    IsVM          = $IsVM
                    CHKDSKQueued  = $false   # updated by CHKDSK phase
                }

                $DirtyFlag = if ($IsDirty) { " [DIRTY]" } else { "" }
                Write-Log "  Volume $($Letter): | $($Vol.FileSystemType) | $([Math]::Round($Vol.Size/1GB,1)) GB total | $($FreePct)% free | Media: $MediaType$DirtyFlag" -Severity INFO
                Write-Console "  $($Letter): $($Vol.FileSystemType) | $([Math]::Round($Vol.Size/1GB,1)) GB | $($FreePct)% free | $MediaType$DirtyFlag" -Severity PLAIN -Indent 1

                if ($IsDirty) {
                    Write-Log "  Volume $($Letter): has dirty bit set. CHKDSK will be scheduled." -Severity WARN
                    Write-Console "  $($Letter): dirty bit is SET — CHKDSK will be scheduled." -Severity WARN -Indent 1
                    Set-ExitCodeBit -Bit $EXIT_PREFLIGHT_WARN
                }

                if ($FreePct -lt $MinFreeSpacePct) {
                    Write-Log "  Volume $($Letter): free space is below $MinFreeSpacePct% threshold ($($FreePct)%). Defrag will be skipped." -Severity WARN
                    Write-Console "  $($Letter): low free space ($($FreePct)%) — defrag will be skipped." -Severity WARN -Indent 1
                    Set-ExitCodeBit -Bit $EXIT_PREFLIGHT_WARN
                }
            }

            Write-Log "Pre-flight checks completed. $($VolumeMap.Count) volume(s) targeted." -Severity SUCCESS
            Write-Console "Pre-flight checks completed. $($VolumeMap.Count) volume(s) targeted." -Severity SUCCESS
        }
        catch {
            Write-Log "Pre-flight volume enumeration failed: $_" -Severity ERROR
            Write-Console "Pre-flight volume enumeration failed: $_" -Severity ERROR
            Set-ExitCodeBit -Bit $EXIT_PREFLIGHT_WARN
        }

        return [PSCustomObject]@{
            IsAdmin  = $IsAdmin
            IsServer = $IsServer
            IsVM     = $IsVM
            OSCaption = $OSCaption
            OSBuild   = $OSBuild
            VolumeMap = $VolumeMap
        }
    }

    # ==========================================================================
    # PHASE: SFC
    # Runs sfc /scannow. Parses output for result indicators.
    # Returns: "Clean" | "Repaired" | "Unrepairable" | "Failed"
    # ==========================================================================
    function Invoke-SFCScan {
        param (
            [Parameter(Mandatory = $true)]  [int]$PassNumber,
            [Parameter(Mandatory = $false)] [bool]$IsAfterDISM = $false
        )

        $PassLabel = "SFC Pass $PassNumber"
        if ($IsAfterDISM) { $PassLabel += " (Post-DISM Re-Verify)" }

        Write-Section $PassLabel
        Write-Log "Starting $PassLabel..." -Severity INFO
        Write-Console "Starting $PassLabel..." -Severity INFO

        $SFCResult = "Unknown"

        try {
            Write-Log "Running: sfc /scannow" -Severity DEBUG
            Write-Console "Running sfc /scannow — this may take several minutes..." -Severity INFO

            # SFC writes to a Unicode CBS log rather than stdout; we capture what we can
            # and parse the CBS log for definitive results
            $SFCProcess = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" `
                          -Wait -PassThru -NoNewWindow

            $SFCExitCode = $SFCProcess.ExitCode
            Write-Log "$PassLabel exit code: $SFCExitCode" -Severity DEBUG

            # Parse CBS.log for result — most reliable source for SFC outcomes
            # CBS.log is Unicode (UTF-16); use StreamReader for PS 5.1 compatibility
            $CBSLog = "$env:SystemRoot\Logs\CBS\CBS.log"
            $SFCLines = @()
            if (Test-Path -Path $CBSLog) {
                try {
                    $Reader = [System.IO.StreamReader]::new($CBSLog, [System.Text.Encoding]::Unicode)
                    $AllLines = [System.Collections.Generic.List[string]]::new()
                    while (-not $Reader.EndOfStream) {
                        $AllLines.Add($Reader.ReadLine())
                    }
                    $Reader.Close()
                    $Reader.Dispose()

                    # Extract SFC-related lines from the tail of the log
                    $SFCLines = $AllLines | Where-Object { $_ -match "Windows Resource Protection" } |
                                Select-Object -Last 20
                }
                catch {
                    Write-Log "Could not read CBS.log: $_ (non-fatal — using exit code only)" -Severity DEBUG
                }
            }

            # Determine result from CBS content first, then fall back to exit code
            $ResultText = $SFCLines -join " "

            if ($ResultText -match "did not find any integrity violations" -or $SFCExitCode -eq 0) {
                $SFCResult = "Clean"
                Write-Log "$PassLabel result: No integrity violations found." -Severity SUCCESS
                Write-Console "$($PassLabel): No integrity violations found." -Severity SUCCESS
            }
            elseif ($ResultText -match "found and repaired" -or $ResultText -match "successfully repaired") {
                $SFCResult = "Repaired"
                Write-Log "$PassLabel result: Integrity violations found and REPAIRED." -Severity SUCCESS
                Write-Console "$($PassLabel): Integrity violations found and repaired." -Severity SUCCESS
                Add-RebootReason "$PassLabel repaired corrupted system files — reboot to finalize"
            }
            elseif ($ResultText -match "found integrity violations" -and $ResultText -notmatch "repaired") {
                $SFCResult = "Unrepairable"
                Write-Log "$PassLabel result: Integrity violations found but COULD NOT BE REPAIRED." -Severity ERROR
                Write-Console "$($PassLabel): Violations found but could not be repaired." -Severity ERROR
                Set-ExitCodeBit -Bit $EXIT_SFC_UNREPAIRABLE
            }
            else {
                # Ambiguous — log what we got and treat as unknown
                $SFCResult = "Unknown"
                Write-Log "$PassLabel result: Outcome unclear (ExitCode=$SFCExitCode). Review CBS.log manually." -Severity WARN
                Write-Console "$($PassLabel): Outcome unclear — review CBS.log manually." -Severity WARN
            }

            # Surface the last few relevant CBS lines to the log for DattoRMM visibility
            if ($SFCLines.Count -gt 0) {
                Write-Log "CBS.log tail (SFC-related lines):" -Severity DEBUG
                $SFCLines | Select-Object -Last 5 | ForEach-Object {
                    Write-Log "  $_" -Severity DEBUG
                }
            }
        }
        catch {
            $SFCResult = "Failed"
            Write-Log "$PassLabel threw an exception: $_" -Severity ERROR
            Write-Console "$PassLabel failed with an exception." -Severity ERROR -Indent 1
        }

        return $SFCResult
    }

    # ==========================================================================
    # PHASE: DISM
    # Runs CheckHealth → ScanHealth → RestoreHealth (if needed).
    # Returns: "Clean" | "Repaired" | "Failed"
    # ==========================================================================
    function Invoke-DISMRepair {
        Write-Section "DISM Component Store"
        Write-Log "Starting DISM component store health check..." -Severity INFO
        Write-Console "Starting DISM component store health check..." -Severity INFO

        $DISMResult = "Unknown"

        try {
            # --- Stage 1: CheckHealth (fast, no network) ---
            Write-Log "DISM Stage 1: /CheckHealth" -Severity INFO
            Write-Console "Stage 1/3: CheckHealth (fast scan)..." -Severity INFO

            $CheckHealthArgs = "/Online /Cleanup-Image /CheckHealth"
            $DismCheck = Start-Process -FilePath "dism.exe" -ArgumentList $CheckHealthArgs `
                         -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\dism_check.txt" `
                         -RedirectStandardError "$env:TEMP\dism_check_err.txt"

            $CheckOutput = if (Test-Path "$env:TEMP\dism_check.txt") {
                Get-Content -Path "$env:TEMP\dism_check.txt" -Raw
            } else { "" }

            Write-Log "DISM /CheckHealth exit code: $($DismCheck.ExitCode)" -Severity DEBUG
            if ($CheckOutput) {
                $CheckOutput.Split("`n") | Where-Object { $_.Trim() } | ForEach-Object {
                    Write-Log "  [DISM] $_" -Severity DEBUG
                }
            }

            $ComponentStoreCorrupt = $false

            if ($DismCheck.ExitCode -ne 0) {
                $ComponentStoreCorrupt = $true
                Write-Log "DISM /CheckHealth reported component store issues (exit code $($DismCheck.ExitCode))." -Severity WARN
                Write-Console "CheckHealth: Component store issues detected." -Severity WARN
            }
            elseif ($CheckOutput -match "No component store corruption detected") {
                Write-Log "DISM /CheckHealth: No component store corruption detected." -Severity SUCCESS
                Write-Console "CheckHealth: No component store corruption detected." -Severity SUCCESS
            }
            else {
                # Non-zero output but exit 0 — run ScanHealth to be thorough
                $ComponentStoreCorrupt = $true
                Write-Log "DISM /CheckHealth output ambiguous — proceeding to ScanHealth." -Severity WARN
                Write-Console "CheckHealth output ambiguous — proceeding to ScanHealth." -Severity WARN
            }

            # --- Stage 2: ScanHealth (thorough, slower) ---
            Write-Log "DISM Stage 2: /ScanHealth" -Severity INFO
            Write-Console "Stage 2/3: ScanHealth (thorough scan — may take a few minutes)..." -Severity INFO

            $ScanHealthArgs = "/Online /Cleanup-Image /ScanHealth"
            $DismScan = Start-Process -FilePath "dism.exe" -ArgumentList $ScanHealthArgs `
                        -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\dism_scan.txt" `
                        -RedirectStandardError "$env:TEMP\dism_scan_err.txt"

            $ScanOutput = if (Test-Path "$env:TEMP\dism_scan.txt") {
                Get-Content -Path "$env:TEMP\dism_scan.txt" -Raw
            } else { "" }

            Write-Log "DISM /ScanHealth exit code: $($DismScan.ExitCode)" -Severity DEBUG
            if ($ScanOutput) {
                $ScanOutput.Split("`n") | Where-Object { $_.Trim() } | ForEach-Object {
                    Write-Log "  [DISM] $_" -Severity DEBUG
                }
            }

            if ($ScanOutput -match "No component store corruption detected") {
                $ComponentStoreCorrupt = $false
                Write-Log "DISM /ScanHealth: No component store corruption detected." -Severity SUCCESS
                Write-Console "ScanHealth: No component store corruption." -Severity SUCCESS
            }
            elseif ($ScanOutput -match "component store is repairable" -or $DismScan.ExitCode -ne 0) {
                $ComponentStoreCorrupt = $true
                Write-Log "DISM /ScanHealth: Component store corruption detected — proceeding to RestoreHealth." -Severity WARN
                Write-Console "ScanHealth: Corruption detected — proceeding to RestoreHealth." -Severity WARN
            }

            # --- Stage 3: RestoreHealth (only if corruption detected) ---
            if ($ComponentStoreCorrupt) {
                Write-Log "DISM Stage 3: /RestoreHealth" -Severity INFO
                Write-Console "Stage 3/3: RestoreHealth (downloading/applying repairs — may take 10-30 min)..." -Severity INFO

                $RestoreArgs = "/Online /Cleanup-Image /RestoreHealth"
                $DismRestore = Start-Process -FilePath "dism.exe" -ArgumentList $RestoreArgs `
                               -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\dism_restore.txt" `
                               -RedirectStandardError "$env:TEMP\dism_restore_err.txt"

                $RestoreOutput = if (Test-Path "$env:TEMP\dism_restore.txt") {
                    Get-Content -Path "$env:TEMP\dism_restore.txt" -Raw
                } else { "" }

                Write-Log "DISM /RestoreHealth exit code: $($DismRestore.ExitCode)" -Severity DEBUG
                if ($RestoreOutput) {
                    $RestoreOutput.Split("`n") | Where-Object { $_.Trim() } | ForEach-Object {
                        Write-Log "  [DISM] $_" -Severity DEBUG
                    }
                }

                if ($DismRestore.ExitCode -eq 0 -or $RestoreOutput -match "The restore operation completed successfully") {
                    $DISMResult = "Repaired"
                    Write-Log "DISM /RestoreHealth: Component store repaired successfully." -Severity SUCCESS
                    Write-Console "RestoreHealth: Component store repaired successfully." -Severity SUCCESS
                    Add-RebootReason "DISM RestoreHealth repaired the component store — reboot recommended"
                }
                else {
                    $DISMResult = "Failed"
                    Write-Log "DISM /RestoreHealth failed (exit code $($DismRestore.ExitCode))." -Severity ERROR
                    Write-Console "RestoreHealth FAILED (exit code $($DismRestore.ExitCode))." -Severity ERROR
                    Set-ExitCodeBit -Bit $EXIT_DISM_FAILED
                }
            }
            else {
                $DISMResult = "Clean"
                Write-Log "DISM: Component store healthy — RestoreHealth not needed." -Severity SUCCESS
                Write-Console "DISM: Component store is healthy." -Severity SUCCESS
            }

            # --- Optional: Component Cleanup ---
            # Only runs if -RunComponentCleanup is set AND profile allows it
            $CleanupAllowed = $RunComponentCleanup -and (
                $Profile -eq "Workstation" -or $Profile -eq "ServerAggressive"
            )

            if ($CleanupAllowed) {
                Write-Log "Running DISM /StartComponentCleanup (WinSxS cleanup)..." -Severity INFO
                Write-Console "Running WinSxS component cleanup..." -Severity INFO

                $CleanupArgs = "/Online /Cleanup-Image /StartComponentCleanup"
                $DismCleanup = Start-Process -FilePath "dism.exe" -ArgumentList $CleanupArgs `
                               -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\dism_cleanup.txt" `
                               -RedirectStandardError "$env:TEMP\dism_cleanup_err.txt"

                Write-Log "DISM /StartComponentCleanup exit code: $($DismCleanup.ExitCode)" -Severity DEBUG

                if ($DismCleanup.ExitCode -eq 0) {
                    Write-Log "DISM /StartComponentCleanup completed successfully." -Severity SUCCESS
                    Write-Console "Component cleanup completed successfully." -Severity SUCCESS
                    Add-RebootReason "DISM component cleanup completed — reboot recommended to finalize"
                }
                else {
                    Write-Log "DISM /StartComponentCleanup failed (exit code $($DismCleanup.ExitCode)) — non-fatal." -Severity WARN
                    Write-Console "Component cleanup failed (non-fatal)." -Severity WARN
                }
            }
            elseif ($RunComponentCleanup -and $Profile -eq "Server") {
                Write-Log "Component cleanup requested but blocked by Server profile. Use ServerAggressive to allow." -Severity WARN
                Write-Console "Component cleanup skipped — blocked by Server profile." -Severity WARN -Indent 1
            }
        }
        catch {
            $DISMResult = "Failed"
            Write-Log "DISM phase threw an exception: $_" -Severity ERROR
            Write-Console "DISM phase failed with an exception." -Severity ERROR -Indent 1
            Set-ExitCodeBit -Bit $EXIT_DISM_FAILED
        }
        finally {
            # Clean up temp DISM output files
            @("dism_check.txt","dism_check_err.txt","dism_scan.txt","dism_scan_err.txt",
              "dism_restore.txt","dism_restore_err.txt","dism_cleanup.txt","dism_cleanup_err.txt") |
            ForEach-Object {
                $TmpFile = Join-Path -Path $env:TEMP -ChildPath $_
                if (Test-Path -Path $TmpFile) {
                    Remove-Item -Path $TmpFile -Force -ErrorAction SilentlyContinue
                }
            }
        }

        return $DISMResult
    }

    # ==========================================================================
    # PHASE: CHKDSK
    # Runs online scan per volume. Schedules offline /F /R if errors or dirty.
    # Updates VolumeMap.CHKDSKQueued for downstream phases.
    # ==========================================================================
    function Invoke-CHKDSKScan {
        param (
            [Parameter(Mandatory = $true)] [hashtable]$VolumeMap
        )

        Write-Section "CHKDSK Volume Scan"
        Write-Log "Starting CHKDSK phase for $($VolumeMap.Count) volume(s)..." -Severity INFO
        Write-Console "Starting CHKDSK phase for $($VolumeMap.Count) volume(s)..." -Severity INFO

        foreach ($Letter in ($VolumeMap.Keys | Sort-Object)) {
            $Vol = $VolumeMap[$Letter]

            Write-Log "CHKDSK: Scanning volume $($Letter):" -Severity INFO
            Write-Console "Scanning $($Letter):..." -Severity INFO -Indent 1

            $ShouldSchedule = $false
            $ScheduleReason = ""

            # If dirty bit is already set, we know we need to schedule — skip online scan
            if ($Vol.IsDirty) {
                $ShouldSchedule = $true
                $ScheduleReason = "dirty bit set before scan"
                Write-Log "  $($Letter): dirty bit already set — scheduling offline CHKDSK without online scan." -Severity WARN
                Write-Console "  $($Letter): dirty bit set — scheduling offline CHKDSK." -Severity WARN -Indent 2
            }
            else {
                # Online scan — non-destructive, no reboot required
                try {
                    Write-Log "  Running: chkdsk $($Letter): /scan" -Severity DEBUG

                    $ChkArgs    = "$($Letter): /scan"
                    $ChkProcess = Start-Process -FilePath "chkdsk.exe" -ArgumentList $ChkArgs `
                                  -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\chkdsk_$($Letter).txt" `
                                  -RedirectStandardError "$env:TEMP\chkdsk_$($Letter)_err.txt"

                    $ChkOutput = if (Test-Path "$env:TEMP\chkdsk_$($Letter).txt") {
                        Get-Content -Path "$env:TEMP\chkdsk_$($Letter).txt" -Raw
                    } else { "" }

                    Write-Log "  chkdsk $($Letter): /scan exit code: $($ChkProcess.ExitCode)" -Severity DEBUG

                    # Surface relevant chkdsk output lines
                    if ($ChkOutput) {
                        $ChkOutput.Split("`n") | Where-Object { $_.Trim() } | Select-Object -Last 10 | ForEach-Object {
                            Write-Log "  [CHKDSK] $_" -Severity DEBUG
                        }
                    }

                    # CHKDSK exit codes: 0=clean, 1=errors found+fixed online, 2=dirty, 3=unfixable
                    switch ($ChkProcess.ExitCode) {
                        0 {
                            Write-Log "  $($Letter): CHKDSK online scan: No errors found." -Severity SUCCESS
                            Write-Console "  $($Letter): No errors found." -Severity SUCCESS -Indent 2
                        }
                        1 {
                            # Errors found during online scan — schedule offline for full /F /R
                            $ShouldSchedule = $true
                            $ScheduleReason = "online scan found errors"
                            Write-Log "  $($Letter): CHKDSK online scan found errors — scheduling offline CHKDSK." -Severity WARN
                            Write-Console "  $($Letter): Errors found — scheduling offline CHKDSK." -Severity WARN -Indent 2
                        }
                        2 {
                            $ShouldSchedule = $true
                            $ScheduleReason = "volume flagged dirty by chkdsk"
                            Write-Log "  $($Letter): CHKDSK flagged volume as dirty — scheduling offline CHKDSK." -Severity WARN
                            Write-Console "  $($Letter): Volume flagged dirty — scheduling offline CHKDSK." -Severity WARN -Indent 2
                        }
                        3 {
                            $ShouldSchedule = $true
                            $ScheduleReason = "unfixable errors detected"
                            Write-Log "  $($Letter): CHKDSK found unfixable errors — scheduling offline CHKDSK /F /R." -Severity ERROR
                            Write-Console "  $($Letter): Unfixable errors — scheduling offline CHKDSK." -Severity ERROR -Indent 2
                        }
                        default {
                            Write-Log "  $($Letter): CHKDSK returned unexpected exit code $($ChkProcess.ExitCode)." -Severity WARN
                            Write-Console "  $($Letter): Unexpected CHKDSK exit code $($ChkProcess.ExitCode)." -Severity WARN -Indent 2
                        }
                    }
                }
                catch {
                    Write-Log "  $($Letter): CHKDSK online scan failed: $_" -Severity ERROR
                    Write-Console "  $($Letter): CHKDSK scan failed." -Severity ERROR -Indent 2
                    Set-ExitCodeBit -Bit $EXIT_CHKDSK_SCHED_FAIL
                }
                finally {
                    Remove-Item -Path "$env:TEMP\chkdsk_$($Letter).txt" -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "$env:TEMP\chkdsk_$($Letter)_err.txt" -Force -ErrorAction SilentlyContinue
                }
            }

            # Schedule offline CHKDSK if needed
            if ($ShouldSchedule) {
                try {
                    Write-Log "  Scheduling offline CHKDSK for $($Letter): ($ScheduleReason)..." -Severity INFO
                    Write-Console "  Scheduling offline CHKDSK for $($Letter): ($ScheduleReason)..." -Severity INFO -Indent 2

                    # For the OS volume (typically C:), use the registry method which is most reliable
                    # For data volumes, chkdsk /f schedules via volume dirty bit + autochk
                    $IsOSVolume = ($Letter -eq $env:SystemDrive.TrimEnd(':'))

                    if ($IsOSVolume) {
                        # Set BootExecute registry key to schedule autochk on next boot
                        $RegPath  = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
                        $RegValue = "BootExecute"
                        $ChkEntry = "autocheck autochk * /f"

                        $CurrentBE = (Get-ItemProperty -Path $RegPath -Name $RegValue).$RegValue

                        # Only add if not already scheduled
                        if ($CurrentBE -notcontains $ChkEntry) {
                            $NewBE = $CurrentBE + $ChkEntry
                            Set-ItemProperty -Path $RegPath -Name $RegValue -Value $NewBE
                            Write-Log "  $($Letter): Offline CHKDSK scheduled via BootExecute registry." -Severity SUCCESS
                            Write-Console "  $($Letter): Offline CHKDSK scheduled (BootExecute)." -Severity SUCCESS -Indent 2
                        }
                        else {
                            Write-Log "  $($Letter): CHKDSK was already scheduled in BootExecute." -Severity INFO
                            Write-Console "  $($Letter): CHKDSK was already scheduled." -Severity INFO -Indent 2
                        }
                    }
                    else {
                        # For non-OS volumes: use chkdsk /f to mark dirty and schedule autochk
                        # We also use fsutil to set dirty bit as a belt-and-suspenders approach
                        try {
                            & fsutil dirty set "$($Letter):" | Out-Null
                            Write-Log "  $($Letter): Dirty bit set via fsutil — autochk will run on next boot." -Severity SUCCESS
                            Write-Console "  $($Letter): Dirty bit set — autochk will run on next boot." -Severity SUCCESS -Indent 2
                        }
                        catch {
                            # fsutil may fail if volume is in use; try chkdsk /f scheduling instead
                            $ScheduleArgs = "$($Letter): /f"
                            $ScheduleResult = Start-Process -FilePath "chkdsk.exe" -ArgumentList $ScheduleArgs `
                                             -Wait -PassThru -NoNewWindow
                            Write-Log "  $($Letter): CHKDSK /f scheduled (exit code $($ScheduleResult.ExitCode))." -Severity INFO
                            Write-Console "  $($Letter): CHKDSK /f scheduled." -Severity INFO -Indent 2
                        }
                    }

                    $VolumeMap[$Letter].CHKDSKQueued = $true
                    Add-RebootReason "CHKDSK offline scan queued for $($Letter): ($ScheduleReason) — must reboot to run"
                }
                catch {
                    Write-Log "  $($Letter): Failed to schedule offline CHKDSK: $_" -Severity ERROR
                    Write-Console "  $($Letter): Failed to schedule offline CHKDSK." -Severity ERROR -Indent 2
                    Set-ExitCodeBit -Bit $EXIT_CHKDSK_SCHED_FAIL
                }
            }
        }

        Write-Log "CHKDSK phase complete." -Severity SUCCESS
        Write-Console "CHKDSK phase complete." -Severity SUCCESS
    }

    # ==========================================================================
    # PHASE: DRIVE OPTIMIZATION
    # HDD → Defrag (/O optimal, /U progress, /V verbose)
    # SSD → Retrim (/L) — no classic defrag
    # VirtualDisk/Unknown → Skip
    # Dirty volumes → Skip (CHKDSK must run first)
    # Low free space → Skip
    # ==========================================================================
    function Invoke-DriveOptimization {
        param (
            [Parameter(Mandatory = $true)] [hashtable]$VolumeMap
        )

        Write-Section "Drive Optimization"
        Write-Log "Starting drive optimization phase for $($VolumeMap.Count) volume(s)..." -Severity INFO
        Write-Console "Starting drive optimization for $($VolumeMap.Count) volume(s)..." -Severity INFO

        foreach ($Letter in ($VolumeMap.Keys | Sort-Object)) {
            $Vol = $VolumeMap[$Letter]

            Write-Log "Optimization: Processing volume $($Letter):" -Severity INFO
            Write-Console "Processing $($Letter):" -Severity INFO -Indent 1

            # --- Skip conditions ---

            # Dirty or CHKDSK queued — must run CHKDSK first
            if ($Vol.IsDirty -or $Vol.CHKDSKQueued) {
                Write-Log "  $($Letter): Skipping optimization — volume is dirty or CHKDSK queued. Run after next reboot." -Severity WARN
                Write-Console "  $($Letter): Skipped — dirty/CHKDSK pending." -Severity WARN -Indent 2
                continue
            }

            # Virtual disk — hypervisor manages storage
            if ($Vol.MediaType -eq "VirtualDisk") {
                Write-Log "  $($Letter): Skipping optimization — virtual disk (hypervisor-managed)." -Severity INFO
                Write-Console "  $($Letter): Skipped — virtual disk." -Severity INFO -Indent 2
                continue
            }

            # Unknown media type — conservative, skip with warning
            if ($Vol.MediaType -eq "Unknown") {
                Write-Log "  $($Letter): Skipping optimization — media type could not be determined. Manual review recommended." -Severity WARN
                Write-Console "  $($Letter): Skipped — media type unknown." -Severity WARN -Indent 2
                continue
            }

            # SSD — retrim only
            if ($Vol.MediaType -eq "SSD") {
                try {
                    Write-Log "  $($Letter): SSD detected — running retrim (defrag /L) instead of defrag." -Severity INFO
                    Write-Console "  $($Letter): SSD — running retrim..." -Severity INFO -Indent 2

                    $RetrimArgs = "$($Letter): /L /U"
                    $RetrimProc = Start-Process -FilePath "defrag.exe" -ArgumentList $RetrimArgs `
                                  -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\optim_$($Letter).txt"

                    Write-Log "  $($Letter): Retrim exit code: $($RetrimProc.ExitCode)" -Severity DEBUG

                    if ($RetrimProc.ExitCode -eq 0) {
                        Write-Log "  $($Letter): Retrim completed successfully." -Severity SUCCESS
                        Write-Console "  $($Letter): Retrim completed." -Severity SUCCESS -Indent 2
                    }
                    else {
                        Write-Log "  $($Letter): Retrim completed with warnings (exit code $($RetrimProc.ExitCode))." -Severity WARN
                        Write-Console "  $($Letter): Retrim completed with warnings." -Severity WARN -Indent 2
                    }
                }
                catch {
                    Write-Log "  $($Letter): Retrim failed: $_" -Severity ERROR
                    Write-Console "  $($Letter): Retrim failed." -Severity ERROR -Indent 2
                    Set-ExitCodeBit -Bit $EXIT_OPTIM_FAILED
                }
                finally {
                    Remove-Item -Path "$env:TEMP\optim_$($Letter).txt" -Force -ErrorAction SilentlyContinue
                }
                continue
            }

            # HDD — defrag with free space check
            if ($Vol.MediaType -eq "HDD") {
                # Free space threshold check
                if ($Vol.FreePct -lt $MinFreeSpacePct) {
                    Write-Log "  $($Letter): Skipping defrag — free space $($Vol.FreePct)% is below threshold $($MinFreeSpacePct)%." -Severity WARN
                    Write-Console "  $($Letter): Skipped — low free space ($($Vol.FreePct)%)." -Severity WARN -Indent 2
                    continue
                }

                try {
                    Write-Log "  $($Letter): HDD detected — running defrag /O /U /V" -Severity INFO
                    Write-Console "  $($Letter): HDD — defragmenting ($($Vol.FreePct)% free)..." -Severity INFO -Indent 2

                    $DefragArgs = "$($Letter): /O /U /V"
                    $DefragProc = Start-Process -FilePath "defrag.exe" -ArgumentList $DefragArgs `
                                  -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\defrag_$($Letter).txt"

                    Write-Log "  $($Letter): Defrag exit code: $($DefragProc.ExitCode)" -Severity DEBUG

                    # Surface defrag output summary to log
                    if (Test-Path "$env:TEMP\defrag_$($Letter).txt") {
                        $DefragOutput = Get-Content -Path "$env:TEMP\defrag_$($Letter).txt" -Raw
                        if ($DefragOutput) {
                            $DefragOutput.Split("`n") | Where-Object { $_.Trim() } | Select-Object -Last 8 | ForEach-Object {
                                Write-Log "  [DEFRAG] $_" -Severity DEBUG
                            }
                        }
                    }

                    if ($DefragProc.ExitCode -eq 0) {
                        Write-Log "  $($Letter): Defrag completed successfully." -Severity SUCCESS
                        Write-Console "  $($Letter): Defrag completed." -Severity SUCCESS -Indent 2
                    }
                    else {
                        Write-Log "  $($Letter): Defrag completed with warnings (exit code $($DefragProc.ExitCode))." -Severity WARN
                        Write-Console "  $($Letter): Defrag completed with warnings." -Severity WARN -Indent 2
                    }
                }
                catch {
                    Write-Log "  $($Letter): Defrag failed: $_" -Severity ERROR
                    Write-Console "  $($Letter): Defrag failed." -Severity ERROR -Indent 2
                    Set-ExitCodeBit -Bit $EXIT_OPTIM_FAILED
                }
                finally {
                    Remove-Item -Path "$env:TEMP\defrag_$($Letter).txt" -Force -ErrorAction SilentlyContinue
                }
            }
        }

        Write-Log "Drive optimization phase complete." -Severity SUCCESS
        Write-Console "Drive optimization phase complete." -Severity SUCCESS
    }

    # ==========================================================================
    # PHASE: SUMMARY
    # Outputs consolidated results for DattoRMM and the technician.
    # Emits the REBOOT RECOMMENDED block if any reboot reasons were collected.
    # ==========================================================================
    function Write-Summary {
        param (
            [Parameter(Mandatory = $true)] [hashtable]$Results
        )

        Write-Section "Run Summary" -Color "White"
        Write-Log ""
        Write-Log "===== MAINTENANCE RUN SUMMARY =====" -Severity INFO
        Write-Log "Profile       : $Profile" -Severity INFO
        Write-Log "SFC Pass 1    : $($Results.SFCPass1)" -Severity INFO
        Write-Log "DISM          : $($Results.DISM)" -Severity INFO
        Write-Log "SFC Pass 2    : $($Results.SFCPass2)" -Severity INFO
        Write-Log "CHKDSK        : $($Results.CHKDSK)" -Severity INFO
        Write-Log "Optimization  : $($Results.Optimization)" -Severity INFO
        if ($RunComponentCleanup) {
            Write-Log "Comp Cleanup  : $($Results.ComponentCleanup)" -Severity INFO
        }
        Write-Log "Exit Code     : $($script:ExitCode)" -Severity INFO

        Write-Console ""
        Write-Console "Profile       : $Profile"   -Severity PLAIN
        Write-Console "SFC Pass 1    : $($Results.SFCPass1)"   -Severity PLAIN
        Write-Console "DISM          : $($Results.DISM)"       -Severity PLAIN
        Write-Console "SFC Pass 2    : $($Results.SFCPass2)"   -Severity PLAIN
        Write-Console "CHKDSK        : $($Results.CHKDSK)"     -Severity PLAIN
        Write-Console "Optimization  : $($Results.Optimization)" -Severity PLAIN
        if ($RunComponentCleanup) {
            Write-Console "Comp Cleanup  : $($Results.ComponentCleanup)" -Severity PLAIN
        }

        # Reboot recommendation block
        if ($script:RebootReasons.Count -gt 0) {
            Write-Log "" -Severity INFO
            Write-Log "*** REBOOT RECOMMENDED ***" -Severity WARN
            Write-Log "The following conditions require a reboot:" -Severity WARN
            foreach ($Reason in $script:RebootReasons) {
                Write-Log "  - $Reason" -Severity WARN
            }
            Write-Log "No automatic reboot will be triggered. Schedule at your discretion." -Severity WARN

            Write-Console ""
            Write-Host ("!" * 60) -ForegroundColor Yellow
            Write-Host "  *** REBOOT RECOMMENDED ***" -ForegroundColor Yellow
            Write-Host ("!" * 60) -ForegroundColor Yellow
            foreach ($Reason in $script:RebootReasons) {
                Write-Console "  - $Reason" -Severity WARN -Indent 1
            }
            Write-Console "  No automatic reboot triggered." -Severity WARN -Indent 1
            Write-Host ("!" * 60) -ForegroundColor Yellow
            Write-Host ""
        }
        else {
            Write-Log "No reboot required." -Severity SUCCESS
            Write-Console "No reboot required." -Severity SUCCESS
        }

        Write-Log "Exit Code: $($script:ExitCode) (bitfield: see .NOTES for decode)" -Severity INFO
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    # Log header
    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName"         -Severity INFO
    Write-Log "Hostname : $Hostname"          -Severity INFO
    Write-Log "Run As   : $RunAs"             -Severity INFO
    Write-Log "Log File : $LogFile"           -Severity INFO
    Write-Log "Params   : Profile='$Profile' | SkipSFC=$SkipSFC | SkipDISM=$SkipDISM | SkipCHKDSK=$SkipCHKDSK | SkipOptimization=$SkipOptimization | RunOptimization=$RunOptimization | RunComponentCleanup=$RunComponentCleanup | TargetVolumes='$TargetVolumes' | MinFreeSpacePct=$MinFreeSpacePct" -Severity INFO

    # Console banner
    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site     : $SiteName"  -Severity PLAIN
    Write-Console "Hostname : $Hostname"  -Severity PLAIN
    Write-Console "Run As   : $RunAs"     -Severity PLAIN
    Write-Console "Profile  : $Profile"   -Severity PLAIN
    Write-Console "Log File : $LogFile"   -Severity PLAIN
    Write-Separator

    # Resolve effective phase flags based on profile + overrides
    # Server profile: optimization disabled unless RunOptimization or ServerAggressive
    $EffectiveRunOptimization = switch ($Profile) {
        "Workstation"      { -not $SkipOptimization }
        "Server"           { $RunOptimization -and -not $SkipOptimization }
        "ServerAggressive" { -not $SkipOptimization }
    }

    $EffectiveRunSFC    = -not $SkipSFC
    $EffectiveRunDISM   = -not $SkipDISM
    $EffectiveRunCHKDSK = -not $SkipCHKDSK

    Write-Log "Effective phases: SFC=$EffectiveRunSFC | DISM=$EffectiveRunDISM | CHKDSK=$EffectiveRunCHKDSK | Optimization=$EffectiveRunOptimization" -Severity DEBUG
    Write-Console "Effective phases: SFC=$EffectiveRunSFC | DISM=$EffectiveRunDISM | CHKDSK=$EffectiveRunCHKDSK | Optimize=$EffectiveRunOptimization" -Severity DEBUG

    # Result tracking for summary
    $Results = @{
        SFCPass1         = "Skipped"
        DISM             = "Skipped"
        SFCPass2         = "Skipped"
        CHKDSK           = "Skipped"
        Optimization     = "Skipped"
        ComponentCleanup = "Skipped"
    }

    try {
        # ------------------------------------------------------------------
        # PRE-FLIGHT
        # ------------------------------------------------------------------
        $PreFlight = Invoke-PreFlight

        if (-not $PreFlight -or -not $PreFlight.IsAdmin) {
            Write-Log "Pre-flight failed — insufficient privileges. Cannot continue." -Severity ERROR
            Write-Banner "SCRIPT FAILED — ELEVATION REQUIRED" -Color "Red"
            exit $EXIT_GENERAL_FAILURE
        }

        $VolumeMap = $PreFlight.VolumeMap

        # ------------------------------------------------------------------
        # SFC PASS 1
        # ------------------------------------------------------------------
        $SFCPass1Result = "Skipped"
        if ($EffectiveRunSFC) {
            $SFCPass1Result = Invoke-SFCScan -PassNumber 1
            $Results.SFCPass1 = $SFCPass1Result
        }
        else {
            Write-Log "SFC Pass 1: Skipped (-SkipSFC)." -Severity INFO
            Write-Console "SFC Pass 1: Skipped." -Severity INFO
        }

        # ------------------------------------------------------------------
        # DISM
        # ------------------------------------------------------------------
        $DISMResult = "Skipped"
        if ($EffectiveRunDISM) {
            $DISMResult = Invoke-DISMRepair
            $Results.DISM = $DISMResult
        }
        else {
            Write-Log "DISM: Skipped (-SkipDISM)." -Severity INFO
            Write-Console "DISM: Skipped." -Severity INFO
        }

        # ------------------------------------------------------------------
        # SFC PASS 2 (Post-DISM re-verify)
        # Always run if SFC is enabled and DISM ran — regardless of DISM outcome.
        # If DISM repaired something, this confirms SFC can now fix remaining issues.
        # If DISM was clean, this serves as a second SFC verification pass.
        # ------------------------------------------------------------------
        $SFCPass2Result = "Skipped"
        if ($EffectiveRunSFC -and $EffectiveRunDISM) {
            $SFCPass2Result = Invoke-SFCScan -PassNumber 2 -IsAfterDISM $true
            $Results.SFCPass2 = $SFCPass2Result
        }
        elseif ($EffectiveRunSFC -and -not $EffectiveRunDISM) {
            Write-Log "SFC Pass 2: Skipped (DISM was not run)." -Severity INFO
            Write-Console "SFC Pass 2: Skipped (DISM skipped)." -Severity INFO
        }

        # ------------------------------------------------------------------
        # CHKDSK
        # ------------------------------------------------------------------
        if ($EffectiveRunCHKDSK) {
            Invoke-CHKDSKScan -VolumeMap $VolumeMap
            $Results.CHKDSK = "Completed"
        }
        else {
            Write-Log "CHKDSK: Skipped (-SkipCHKDSK)." -Severity INFO
            Write-Console "CHKDSK: Skipped." -Severity INFO
        }

        # ------------------------------------------------------------------
        # DRIVE OPTIMIZATION
        # ------------------------------------------------------------------
        if ($EffectiveRunOptimization) {
            Invoke-DriveOptimization -VolumeMap $VolumeMap
            $Results.Optimization = "Completed"
        }
        else {
            $SkipMsg = if ($Profile -eq "Server") {
                "Skipped (Server profile — use RunOptimization switch or ServerAggressive profile to enable)"
            } else {
                "Skipped (-SkipOptimization)"
            }
            Write-Log "Drive Optimization: $SkipMsg" -Severity INFO
            Write-Console "Drive Optimization: $SkipMsg" -Severity INFO

            Write-Section "Drive Optimization"
            Write-Log "Drive optimization phase skipped per profile/parameter settings." -Severity INFO
            Write-Console "Drive optimization skipped per profile/parameter settings." -Severity INFO
        }

        # ------------------------------------------------------------------
        # SUMMARY
        # ------------------------------------------------------------------
        Write-Summary -Results $Results

        # Determine final banner color and message
        $HasFailures = ($script:ExitCode -band ($EXIT_SFC_UNREPAIRABLE -bor $EXIT_DISM_FAILED -bor $EXIT_CHKDSK_SCHED_FAIL -bor $EXIT_OPTIM_FAILED)) -gt 0
        $HasReboot   = ($script:ExitCode -band $EXIT_REBOOT_RECOMMENDED) -gt 0

        if ($HasFailures) {
            Write-Log "Maintenance run completed WITH FAILURES. Exit code: $($script:ExitCode)" -Severity ERROR
            Write-Banner "COMPLETED WITH FAILURES — Review Log" -Color "Red"
        }
        elseif ($HasReboot) {
            Write-Log "Maintenance run completed. Reboot recommended. Exit code: $($script:ExitCode)" -Severity WARN
            Write-Banner "COMPLETED — REBOOT RECOMMENDED" -Color "Yellow"
        }
        else {
            Write-Log "Maintenance run completed successfully. Exit code: $($script:ExitCode)" -Severity SUCCESS
            Write-Banner "COMPLETED SUCCESSFULLY" -Color "Green"
        }

        exit $script:ExitCode
    }
    catch {
        Write-Log "Unhandled exception in main execution: $_"             -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)"                   -Severity ERROR

        Write-Banner "SCRIPT FAILED" -Color "Red"
        Write-Console "Unhandled error: $_" -Severity ERROR

        exit $EXIT_GENERAL_FAILURE
    }

} # End function Invoke-WindowsMaintenance

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    Profile              = $Profile
    SkipSFC              = $SkipSFC
    SkipDISM             = $SkipDISM
    SkipCHKDSK           = $SkipCHKDSK
    SkipOptimization     = $SkipOptimization
    RunOptimization      = $RunOptimization
    RunComponentCleanup  = $RunComponentCleanup
    TargetVolumes        = $TargetVolumes
    MinFreeSpacePct      = $MinFreeSpacePct
    SiteName             = $SiteName
    Hostname             = $Hostname
}

Invoke-WindowsMaintenance @ScriptParams
