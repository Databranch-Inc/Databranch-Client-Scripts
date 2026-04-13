#Requires -Version 5.1
# ==============================================================================
# SCRIPT-LEVEL PARAMETERS
# Must appear before any other executable statements.
# DattoRMM env var fallback chain: env var -> parameter -> default value.
# ==============================================================================
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string]$ComputerName = $(if ($env:QA_ComputerName) { $env:QA_ComputerName } else { $env:COMPUTERNAME }),

    # Not Mandatory -- DattoRMM cannot prompt; use env var fallback instead
    [Parameter()]
    [string]$Username = $(if ($env:QA_Username) { $env:QA_Username } else { "" }),

    [Parameter()]
    [string]$BackupTimestamp = $(if ($env:QA_BackupTimestamp) { $env:QA_BackupTimestamp } else { "" }),

    [Parameter()]
    [string]$BackupRoot = $(if ($env:QA_BackupRoot) { $env:QA_BackupRoot } else { 'C:\ProgramData\Databranch\QABackups' }),

    [Parameter()]
    [switch]$RestartExplorer,

    [Parameter()]
    [switch]$ListOnly,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter()]
    [string]$LogPath = $(if ($env:QA_LogPath) { $env:QA_LogPath } else { "" }),

    # DattoRMM built-in variables (auto-populated, no component config needed)
    [Parameter()]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }),

    [Parameter()]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

<#
.SYNOPSIS
    Restores Quick Access pin data from a previous backup.

.DESCRIPTION
    Restore-QuickAccessPins restores AutomaticDestinations files from a backup created by
    Backup-QuickAccessPins. Supports listing available backups, restoring the latest or a
    specific timestamped backup, and optionally restarting Explorer to apply changes immediately.

    The restore process:
    1. Validates the backup exists and contains the expected files
    2. Creates a pre-restore snapshot (safety net)
    3. Stops Explorer.exe for the target user (if -RestartExplorer specified)
    4. Copies backup files to the AutomaticDestinations folder
    5. Restarts Explorer.exe

.PARAMETER ComputerName
    Target computer. Defaults to localhost. DattoRMM env var: QA_ComputerName.

.PARAMETER Username
    The username whose Quick Access data to restore. DattoRMM env var: QA_Username.

.PARAMETER BackupTimestamp
    Specific backup timestamp to restore (format: yyyyMMdd_HHmmss).
    If omitted, restores the most recent backup. DattoRMM env var: QA_BackupTimestamp.

.PARAMETER BackupRoot
    Root path where backups are stored. Must match the backup script's setting.
    DattoRMM env var: QA_BackupRoot.

.PARAMETER RestartExplorer
    If specified, stops and restarts Explorer.exe to apply the restored pins immediately.
    Without this, pins will appear after the next logon or Explorer restart.

.PARAMETER ListOnly
    Lists available backups for the specified user without restoring.

.PARAMETER Credential
    PSCredential for remote execution.

.PARAMETER LogPath
    Optional additional log file path. DattoRMM env var: QA_LogPath.

.EXAMPLE
    .\Restore-QuickAccessPins.ps1 -Username jclonch -ListOnly
    Lists all available backups for jclonch on the local machine.

.EXAMPLE
    .\Restore-QuickAccessPins.ps1 -Username jclonch
    Restores jclonch's most recent Quick Access backup.

.EXAMPLE
    .\Restore-QuickAccessPins.ps1 -ComputerName AAA2-23 -Username jclonch -BackupTimestamp '20260324_220000' -RestartExplorer -Credential (Get-Credential)
    Restores a specific backup on a remote machine and restarts Explorer.

.NOTES
    File Name      : Restore-QuickAccessPins.ps1
    Version        : 1.1.2.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-03-24
    Last Modified  : 2026-03-25
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM or Domain Admin
    DattoRMM       : Compatible -- supports QA_* environment variable input
    Client Scope   : All clients

    Exit Codes:
        0  - Success / list completed
        1  - General failure
        2  - Username not specified
        3  - Restore operation failed

    DattoRMM Environment Variables:
        QA_ComputerName    - Override target computer (default: local machine)
        QA_Username        - Username whose pins to restore (required)
        QA_BackupTimestamp - Specific backup to restore (default: latest)
        QA_BackupRoot      - Override backup root path
        QA_LogPath         - Optional additional log file path

.CHANGELOG
    v1.1.2.0 - 2026-03-25 - Sam Kirsch
        - Fixed Explorer restart silently doing nothing when -RestartExplorer is set.
          Root cause: Get-CimInstance Win32_Process ownership query inside a
          Where-Object block under Invoke-Command local sessions can silently fail,
          returning no processes and skipping the stop/restart entirely.
          Replaced with taskkill /F /IM explorer.exe (terminates all instances
          regardless of ownership) followed by explicit Start-Process explorer
          to guarantee relaunch. Non-fatal: restore result is SUCCESS even if
          Explorer restart itself throws.

    v1.1.1.0 - 2026-03-25 - Sam Kirsch
        - Removed ParameterSetName declarations from all params and
          DefaultParameterSetName from both CmdletBinding attributes.
          PS throws AmbiguousParameterSet when RestartExplorer and ListOnly
          are both present in the splat (even as $false switches) because it
          cannot resolve which set applies. Mutual exclusivity of ListOnly vs
          RestartExplorer is enforced by logic in process block instead.

    v1.1.0.0 - 2026-03-25 - Sam Kirsch
        - Fixed parser error: moved script-level param() block to top of file
        - Removed [Mandatory] from Username -- replaced with env var fallback
          so DattoRMM unattended runs are supported
        - Added DattoRMM env var fallback chain (QA_* prefix) for all parameters
        - Added CS_PROFILE_NAME / CS_HOSTNAME DattoRMM built-in variable support
        - Replaced Write-Verbose with Write-Output/Write-Warning/Write-Error
          so log entries are captured by DattoRMM job stdout
        - Added Databranch structured log file (C:\Databranch\ScriptLogs\...)
          with 10-file rotation
        - Added standard log header (Site, Hostname, Run As, Params, Log File)
        - Added Write-Console / Write-Banner / Write-Section / Write-Separator
          helpers for interactive presentation (display stream only)
        - Replaced fragile InvocationName entry point with standard splatted pattern
        - Replaced em-dash in string literal (PS 5.1 encoding issue) with ASCII hyphen
        - Bumped version to 1.1.0.0
        - Added Username validation with exit 2 before invoking remote scriptblock

    v1.0.0.0 - 2026-03-24 - Sam Kirsch
        - Initial release. Supports list, latest/specific restore,
          pre-restore snapshot, Explorer restart, and structured logging.
#>

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Restore-QuickAccessPins {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$ComputerName,

        [Parameter()]
        [string]$Username,

        [Parameter()]
        [string]$BackupTimestamp,

        [Parameter()]
        [string]$BackupRoot,

        [Parameter()]
        [switch]$RestartExplorer,

        [Parameter()]
        [switch]$ListOnly,

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [string]$LogPath,

        [Parameter()]
        [string]$SiteName,

        [Parameter()]
        [string]$Hostname
    )

    begin {
        # Apply defaults for any params not passed via splatting
        if (-not $ComputerName) { $ComputerName = $env:COMPUTERNAME }
        if (-not $BackupRoot)   { $BackupRoot   = 'C:\ProgramData\Databranch\QABackups' }
        if (-not $SiteName)     { $SiteName     = "UnknownSite" }
        if (-not $Hostname)     { $Hostname     = $env:COMPUTERNAME }

        $ScriptName    = "Restore-QuickAccessPins"
        $ScriptVersion = "1.1.2.0"
        $LogRoot       = "C:\Databranch\ScriptLogs"
        $LogFolder     = Join-Path $LogRoot $ScriptName
        $LogDate       = Get-Date -Format "yyyy-MM-dd"
        $StructuredLog = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
        $MaxLogFiles   = 10

        $isRemote = $ComputerName -ne $env:COMPUTERNAME

        # Initialize log folder and rotate old logs
        if (-not (Test-Path $LogFolder)) {
            New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
        }
        try {
            $existingLogs = Get-ChildItem -Path $LogFolder -Filter "$($ScriptName)_*.log" |
                            Sort-Object LastWriteTime -Descending
            if ($existingLogs.Count -ge $MaxLogFiles) {
                $existingLogs | Select-Object -Skip ($MaxLogFiles - 1) | ForEach-Object {
                    Remove-Item -Path $_.FullName -Force
                }
            }
        }
        catch { }

        # ==========================================================================
        # WRITE-LOG  (Structured Output Layer)
        # Writes to stdout (captured by DattoRMM) and log file. Never Write-Verbose.
        # ==========================================================================
        function Write-Log {
            param(
                [string]$Message,
                [string]$Level = 'INFO'
            )
            $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $entry = "[$ts] [$Level] $Message"

            switch ($Level) {
                "WARN"  { Write-Warning $entry }
                "ERROR" { Write-Error   $entry -ErrorAction Continue }
                default { Write-Output  $entry }
            }

            try { Add-Content -Path $StructuredLog -Value $entry -Encoding UTF8 } catch { }

            if ($LogPath) {
                try {
                    $logDir = Split-Path $LogPath -Parent
                    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
                    Add-Content -Path $LogPath -Value $entry -Encoding UTF8
                }
                catch { }
            }
        }

        # ==========================================================================
        # WRITE-CONSOLE  (Presentation Layer -- display stream only)
        # Uses Write-Host. NOT captured by DattoRMM stdout. Safe alongside Write-Log.
        # ==========================================================================
        function Write-Console {
            param(
                [string]$Message = "",
                [ValidateSet("INFO","WARN","ERROR","SUCCESS","DEBUG","PLAIN")]
                [string]$Severity = "PLAIN",
                [int]$Indent = 0
            )
            $Prefix = "  " * $Indent
            $Colors = @{ INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; DEBUG="Magenta"; PLAIN="Gray" }
            $Color  = $Colors[$Severity]
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
            param([string]$Title, [string]$Color = "Cyan")
            $Line = "=" * 60
            Write-Host ""
            Write-Host $Line       -ForegroundColor $Color
            Write-Host "  $Title"  -ForegroundColor White
            Write-Host $Line       -ForegroundColor $Color
            Write-Host ""
        }

        function Write-Section {
            param([string]$Title, [string]$Color = "Cyan")
            $TitleStr = "---- $Title "
            $Padding  = "-" * [Math]::Max(0, (60 - $TitleStr.Length))
            Write-Host ""
            Write-Host "$TitleStr$Padding" -ForegroundColor $Color
        }

        function Write-Separator {
            param([string]$Color = "DarkGray")
            Write-Host ("-" * 60) -ForegroundColor $Color
        }

        # Standard log header
        $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Write-Log "===== $ScriptName v$ScriptVersion ======"
        Write-Log "Site     : $SiteName"
        Write-Log "Hostname : $Hostname"
        Write-Log "Run As   : $RunAs"
        Write-Log "Params   : ComputerName='$ComputerName' | Username='$Username' | BackupTimestamp='$(if ($BackupTimestamp) { $BackupTimestamp } else { 'LATEST' })' | ListOnly=$($ListOnly.IsPresent)"
        Write-Log "Log File : $StructuredLog"

        Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
        Write-Console "Site     : $SiteName"  -Severity PLAIN
        Write-Console "Hostname : $Hostname"   -Severity PLAIN
        Write-Console "Run As   : $RunAs"      -Severity PLAIN
        Write-Console "Log File : $StructuredLog" -Severity PLAIN
        Write-Separator
    }

    process {
        $ErrorActionPreference = 'Stop'

        # Validate Username -- cannot proceed without it
        if (-not $Username) {
            Write-Log "Username is required but was not specified." -Level ERROR
            Write-Console "Username is required. Specify -Username or set the QA_Username environment variable." -Severity ERROR
            Write-Banner "SCRIPT FAILED" -Color Red
            exit 2
        }

        $scriptBlock = {
            param($BackupRoot, $Username, $BackupTimestamp, $RestartExplorer, $ListOnly)

            # Resolve user profile path
            $profileEntry = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
                Where-Object { $_.PSChildName -match '^S-1-5-21-' } |
                ForEach-Object {
                    $path = (Get-ItemProperty $_.PSPath).ProfileImagePath
                    [PSCustomObject]@{
                        SID         = $_.PSChildName
                        Username    = Split-Path $path -Leaf
                        ProfilePath = $path
                    }
                } |
                Where-Object { $_.Username -eq $Username } |
                Select-Object -First 1

            if (-not $profileEntry) {
                return [PSCustomObject]@{
                    Status  = 'ERROR'
                    Message = "No profile found for user: $Username"
                }
            }

            $qaTarget    = Join-Path $profileEntry.ProfilePath 'AppData\Roaming\Microsoft\Windows\Recent\AutomaticDestinations'
            $userBackups = Join-Path $BackupRoot $Username

            if (-not (Test-Path $userBackups)) {
                return [PSCustomObject]@{
                    Status  = 'ERROR'
                    Message = "No backup directory found at: $userBackups"
                }
            }

            # Get available backups sorted newest first
            $available = Get-ChildItem $userBackups -Directory |
                Where-Object { $_.Name -match '^\d{8}_\d{6}$' } |
                ForEach-Object {
                    $metaFile  = Join-Path $_.FullName '_backup_metadata.json'
                    $files     = Get-ChildItem $_.FullName -File | Where-Object { $_.Name -ne '_backup_metadata.json' }
                    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
                    $meta      = $null
                    if (Test-Path $metaFile) {
                        $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
                    }
                    [PSCustomObject]@{
                        Timestamp = $_.Name
                        Path      = $_.FullName
                        FileCount = $files.Count
                        TotalSize = $totalSize
                        SizeLabel = "$([math]::Round($totalSize / 1KB, 1)) KB"
                        Created   = $_.CreationTime
                        Computer  = if ($meta) { $meta.Computer } else { 'unknown' }
                    }
                } |
                Sort-Object Timestamp -Descending

            if ($available.Count -eq 0) {
                return [PSCustomObject]@{
                    Status  = 'ERROR'
                    Message = "No valid backups found in: $userBackups"
                }
            }

            # List mode
            if ($ListOnly) {
                return [PSCustomObject]@{
                    Status  = 'LIST'
                    Message = "Found $($available.Count) backup(s) for $Username"
                    Backups = $available
                }
            }

            # Select backup to restore
            if ($BackupTimestamp) {
                $selected = $available | Where-Object { $_.Timestamp -eq $BackupTimestamp }
                if (-not $selected) {
                    return [PSCustomObject]@{
                        Status  = 'ERROR'
                        Message = "Backup '$BackupTimestamp' not found. Available: $($available.Timestamp -join ', ')"
                    }
                }
            }
            else {
                $selected = $available | Select-Object -First 1
            }

            # Pre-restore safety snapshot
            $snapshotDir = Join-Path $userBackups "prerestore_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            if (Test-Path $qaTarget) {
                $currentFiles = Get-ChildItem $qaTarget -File -ErrorAction SilentlyContinue
                if ($currentFiles.Count -gt 0) {
                    New-Item -Path $snapshotDir -ItemType Directory -Force | Out-Null
                    Copy-Item -Path "$qaTarget\*" -Destination $snapshotDir -Force
                }
            }

            # Perform restore
            try {
                if (-not (Test-Path $qaTarget)) {
                    New-Item -Path $qaTarget -ItemType Directory -Force | Out-Null
                }

                # Clear current QA files
                Get-ChildItem $qaTarget -File | Remove-Item -Force

                # Copy backup files (exclude metadata)
                $backupFiles = Get-ChildItem $selected.Path -File |
                               Where-Object { $_.Name -ne '_backup_metadata.json' }
                foreach ($file in $backupFiles) {
                    Copy-Item -Path $file.FullName -Destination $qaTarget -Force
                }

                $restoredCount = (Get-ChildItem $qaTarget -File).Count

                # Restart Explorer if requested
                $explorerRestarted = $false
                if ($RestartExplorer) {
                    try {
                        # Stop all Explorer instances -- taskkill is more reliable than
                        # Stop-Process with CIM ownership filtering, especially under
                        # Invoke-Command local sessions where CIM queries can silently fail.
                        $explorerRunning = Get-Process explorer -ErrorAction SilentlyContinue
                        if ($explorerRunning) {
                            taskkill /F /IM explorer.exe 2>&1 | Out-Null
                            Start-Sleep -Seconds 2
                        }

                        # Relaunch Explorer -- Windows may auto-restart it via Winlogon,
                        # but explicitly starting it ensures it comes back in all cases.
                        $explorerPath = Join-Path $env:SystemRoot 'explorer.exe'
                        Start-Process -FilePath $explorerPath
                        Start-Sleep -Seconds 1

                        $explorerRestarted = $true
                    }
                    catch {
                        # Non-fatal -- restore succeeded even if Explorer restart failed
                        $explorerRestarted = $false
                    }
                }

                return [PSCustomObject]@{
                    Status            = 'SUCCESS'
                    Message           = "Restored $restoredCount files from backup $($selected.Timestamp)"
                    BackupUsed        = $selected.Timestamp
                    FilesRestored     = $restoredCount
                    SnapshotDir       = $snapshotDir
                    ExplorerRestarted = $explorerRestarted
                }
            }
            catch {
                return [PSCustomObject]@{
                    Status  = 'ERROR'
                    Message = "Restore failed: $($_.Exception.Message)"
                }
            }
        }

        $invokeParams = @{
            ScriptBlock  = $scriptBlock
            ArgumentList = @($BackupRoot, $Username, $BackupTimestamp, $RestartExplorer.IsPresent, $ListOnly.IsPresent)
        }

        if ($isRemote) {
            $invokeParams['ComputerName'] = $ComputerName
            if ($Credential) { $invokeParams['Credential'] = $Credential }
            Write-Log "Connecting to remote machine: $ComputerName"
            Write-Console "Connecting to remote machine: $ComputerName" -Severity INFO
        }

        if ($ListOnly) {
            Write-Log "Listing available backups for $Username on $ComputerName"
            Write-Section "Available Backups"
            Write-Console "User: $Username  |  Machine: $ComputerName" -Severity INFO
        }
        else {
            Write-Log "Starting Quick Access restore - Target: $ComputerName, User: $Username, Backup: $(if ($BackupTimestamp) { $BackupTimestamp } else { 'LATEST' })"
            Write-Section "Restore Operation"
            Write-Console "User: $Username  |  Machine: $ComputerName  |  Backup: $(if ($BackupTimestamp) { $BackupTimestamp } else { 'LATEST' })" -Severity INFO
        }

        if ($ListOnly -or $PSCmdlet.ShouldProcess($ComputerName, "Restore Quick Access pins for $Username")) {
            try {
                $result = Invoke-Command @invokeParams

                if ($result.Status -eq 'LIST') {
                    Write-Log $result.Message -Level INFO
                    Write-Console $result.Message -Severity INFO
                    Write-Host ""
                    # Per-entry output for DattoRMM log readability
                    foreach ($b in $result.Backups) {
                        Write-Log "  Backup: $($b.Timestamp)  Files: $($b.FileCount)  Size: $($b.SizeLabel)  Created: $($b.Created)  Computer: $($b.Computer)"
                        Write-Console "  $($b.Timestamp)  |  $($b.FileCount) files  |  $($b.SizeLabel)  |  $($b.Created)  |  $($b.Computer)" -Severity PLAIN
                    }
                }
                elseif ($result.Status -eq 'SUCCESS') {
                    Write-Log $result.Message -Level SUCCESS
                    Write-Console $result.Message -Severity SUCCESS
                    if ($result.SnapshotDir) {
                        Write-Log "Pre-restore snapshot: $($result.SnapshotDir)" -Level INFO
                        Write-Console "Pre-restore snapshot: $($result.SnapshotDir)" -Severity INFO -Indent 1
                    }
                    if ($result.ExplorerRestarted) {
                        Write-Log "Explorer restarted for $Username" -Level INFO
                        Write-Console "Explorer was restarted for $Username" -Severity INFO -Indent 1
                    }
                    else {
                        Write-Log "Pins will appear after next logon or Explorer restart" -Level INFO
                        Write-Console "Pins will appear after next logon or Explorer restart" -Severity WARN -Indent 1
                    }
                    Write-Banner "COMPLETED SUCCESSFULLY" -Color Green
                    exit 0
                }
                else {
                    Write-Log $result.Message -Level ERROR
                    Write-Console $result.Message -Severity ERROR
                    Write-Banner "SCRIPT FAILED" -Color Red
                    exit 3
                }
            }
            catch {
                Write-Log "Unhandled exception: $_" -Level ERROR
                Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
                Write-Console "Unhandled exception: $_" -Severity ERROR
                Write-Banner "SCRIPT FAILED" -Color Red
                exit 1
            }
        }
    }

    end {
        Write-Log "Restore operation complete."
    }
}

# ==============================================================================
# ENTRY POINT
# Splat all script-level parameters into the master function.
# ==============================================================================
$ScriptParams = @{
    ComputerName    = $ComputerName
    Username        = $Username
    BackupRoot      = $BackupRoot
    BackupTimestamp = $BackupTimestamp
    RestartExplorer = $RestartExplorer
    ListOnly        = $ListOnly
    LogPath         = $LogPath
    SiteName        = $SiteName
    Hostname        = $Hostname
}
if ($Credential) { $ScriptParams['Credential'] = $Credential }

Restore-QuickAccessPins @ScriptParams
