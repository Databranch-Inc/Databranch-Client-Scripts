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

    [Parameter()]
    [string]$Username = $(if ($env:QA_Username) { $env:QA_Username } else { "" }),

    [Parameter()]
    [string]$BackupRoot = $(if ($env:QA_BackupRoot) { $env:QA_BackupRoot } else { 'C:\ProgramData\Databranch\QABackups' }),

    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$RetentionDays = $(if ($env:QA_RetentionDays) { [int]$env:QA_RetentionDays } else { 30 }),

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
    Backs up Quick Access pin data (AutomaticDestinations) for specified or all users on a machine.

.DESCRIPTION
    Backup-QuickAccessPins creates timestamped backups of the AutomaticDestinations folder
    which stores Explorer Quick Access pinned items. Supports local and remote execution,
    configurable retention, and produces structured log output for RMM integration.

    Designed for deployment via DattoRMM, ConnectWise Automate, Group Policy, or Task Scheduler.

.PARAMETER ComputerName
    Target computer. Defaults to localhost.

.PARAMETER Username
    Specific username to back up. If omitted, backs up all interactive user profiles.

.PARAMETER BackupRoot
    Root path for backup storage. Defaults to C:\ProgramData\Databranch\QABackups.

.PARAMETER RetentionDays
    Number of days to retain backups. Older backups are pruned. Default: 30.

.PARAMETER Credential
    PSCredential for remote execution.

.PARAMETER LogPath
    Optional path to write a structured log file.

.EXAMPLE
    Backup-QuickAccessPins
    Backs up all user profiles on the local machine.

.EXAMPLE
    Backup-QuickAccessPins -ComputerName AAA2-23 -Username jclonch -Credential (Get-Credential)
    Backs up jclonch's Quick Access data on AAA2-23 remotely.

.EXAMPLE
    Backup-QuickAccessPins -RetentionDays 14
    Backs up all profiles, pruning backups older than 14 days.

.NOTES
    File Name      : Backup-QuickAccessPins.ps1
    Version        : 1.1.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-03-24
    Last Modified  : 2026-03-25
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM or Domain Admin
    DattoRMM       : Compatible  -  supports QA_* environment variable input
    Client Scope   : All clients

    Exit Codes:
        0  - Success
        1  - General failure

    DattoRMM Environment Variables:
        QA_ComputerName  - Override target computer (default: local machine)
        QA_Username      - Specific username to back up (default: all users)
        QA_BackupRoot    - Override backup root path
        QA_RetentionDays - Override retention in days (default: 30)
        QA_LogPath       - Optional additional log file path

.CHANGELOG
    v1.1.0.0 - 2026-03-25 - Sam Kirsch
        - Fixed parser error: moved script-level param() block to top of file
          (before function definition, as PS requires)
        - Removed duplicate param() block and stale commented-out entry point
        - Added standard Databranch splatted entry point pattern
        - Added DattoRMM env var fallback chain (QA_* prefix) for all parameters
        - Added CS_PROFILE_NAME / CS_HOSTNAME DattoRMM built-in variable support
        - Replaced Write-Verbose with Write-Output/Write-Warning/Write-Error
          so log entries are captured by DattoRMM job stdout
        - Added Databranch structured log file (C:\Databranch\ScriptLogs\...)
          with 10-file rotation alongside optional caller-supplied LogPath
        - Added standard log header (Site, Hostname, Run As, Params, Log File)
        - Replaced Format-Table summary (truncates in DattoRMM) with per-entry
          Write-Log calls in the end block
        - Bumped version to 1.1.0.0

    v1.0.0.0 - 2026-03-24 - Sam Kirsch
        - Initial release. Supports local/remote backup, retention,
          multi-user discovery, and structured logging.
#>
function Backup-QuickAccessPins {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$ComputerName,

        [Parameter()]
        [string]$Username,

        [Parameter()]
        [string]$BackupRoot,

        [Parameter()]
        [ValidateRange(1, 365)]
        [int]$RetentionDays,

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
        # Apply defaults for any params not passed (supports splatting from script level)
        if (-not $ComputerName)  { $ComputerName  = $env:COMPUTERNAME }
        if (-not $BackupRoot)    { $BackupRoot     = 'C:\ProgramData\Databranch\QABackups' }
        if ($RetentionDays -lt 1){ $RetentionDays  = 30 }
        if (-not $SiteName)      { $SiteName       = "UnknownSite" }
        if (-not $Hostname)      { $Hostname        = $env:COMPUTERNAME }

        $ScriptName    = "Backup-QuickAccessPins"
        $ScriptVersion = "1.1.0.0"
        $LogRoot       = "C:\Databranch\ScriptLogs"
        $LogFolder     = Join-Path $LogRoot $ScriptName
        $LogDate       = Get-Date -Format "yyyy-MM-dd"
        $StructuredLog = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
        $MaxLogFiles   = 10

        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $isRemote  = $ComputerName -ne $env:COMPUTERNAME
        $results   = [System.Collections.Generic.List[PSCustomObject]]::new()

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

        function Write-Log {
            param(
                [string]$Message,
                [string]$Level = 'INFO'
            )
            $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $entry = "[$ts] [$Level] $Message"

            # Write to stdout  -  captured by DattoRMM job output
            switch ($Level) {
                "WARN"  { Write-Warning $entry }
                "ERROR" { Write-Error   $entry -ErrorAction Continue }
                default { Write-Output  $entry }
            }

            # Write to structured log file
            try {
                Add-Content -Path $StructuredLog -Value $entry -Encoding UTF8
            }
            catch { }

            # Also honour the optional caller-supplied LogPath
            if ($LogPath) {
                try {
                    $logDir = Split-Path $LogPath -Parent
                    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
                    Add-Content -Path $LogPath -Value $entry -Encoding UTF8
                }
                catch { }
            }
        }

        # Standard log header
        $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Write-Log "===== $ScriptName v$ScriptVersion ======"
        Write-Log "Site     : $SiteName"
        Write-Log "Hostname : $Hostname"
        Write-Log "Run As   : $RunAs"
        Write-Log "Params   : ComputerName='$ComputerName' | Username='$(if ($Username) { $Username } else { 'ALL' })' | RetentionDays=$RetentionDays"
        Write-Log "Log File : $StructuredLog"
    }

    process {
        $scriptBlock = {
            param($BackupRoot, $Username, $RetentionDays, $Timestamp)

            $output = [System.Collections.Generic.List[PSCustomObject]]::new()

            # Discover user profiles
            $profiles = @(
                Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
                Where-Object { $_.PSChildName -match '^S-1-5-21-' } |
                ForEach-Object {
                    $profilePath = (Get-ItemProperty $_.PSPath).ProfileImagePath
                    $user = Split-Path $profilePath -Leaf
                    [PSCustomObject]@{
                        SID         = $_.PSChildName
                        Username    = $user
                        ProfilePath = $profilePath
                    }
                } |
                Where-Object { $_.ProfilePath -notmatch '(defaultuser|systemprofile|NetworkService|LocalService)' }
            )

            if ($Username) {
                $profiles = $profiles | Where-Object { $_.Username -eq $Username }
                if (-not $profiles) {
                    $output.Add([PSCustomObject]@{
                        Computer  = $env:COMPUTERNAME
                        Username  = $Username
                        Status    = 'ERROR'
                        Message   = "Profile not found for user: $Username"
                        Timestamp = $Timestamp
                        BackupDir = $null
                        FileCount = 0
                        TotalSize = 0
                    })
                    return $output
                }
            }

            foreach ($profile in $profiles) {
                $qaSource = Join-Path $profile.ProfilePath 'AppData\Roaming\Microsoft\Windows\Recent\AutomaticDestinations'
                $userBackupDir = Join-Path $BackupRoot "$($profile.Username)\$Timestamp"

                if (-not (Test-Path $qaSource)) {
                    $output.Add([PSCustomObject]@{
                        Computer  = $env:COMPUTERNAME
                        Username  = $profile.Username
                        Status    = 'SKIPPED'
                        Message   = "AutomaticDestinations folder not found at: $qaSource"
                        Timestamp = $Timestamp
                        BackupDir = $null
                        FileCount = 0
                        TotalSize = 0
                    })
                    continue
                }

                $sourceFiles = Get-ChildItem $qaSource -File -ErrorAction SilentlyContinue
                if (-not $sourceFiles -or $sourceFiles.Count -eq 0) {
                    $output.Add([PSCustomObject]@{
                        Computer  = $env:COMPUTERNAME
                        Username  = $profile.Username
                        Status    = 'SKIPPED'
                        Message   = "AutomaticDestinations folder is empty"
                        Timestamp = $Timestamp
                        BackupDir = $qaSource
                        FileCount = 0
                        TotalSize = 0
                    })
                    continue
                }

                try {
                    if (-not (Test-Path $userBackupDir)) {
                        New-Item -Path $userBackupDir -ItemType Directory -Force | Out-Null
                    }

                    Copy-Item -Path "$qaSource\*" -Destination $userBackupDir -Force -ErrorAction Stop
                    $copiedFiles = Get-ChildItem $userBackupDir -File
                    $totalSize   = ($copiedFiles | Measure-Object -Property Length -Sum).Sum

                    # Write a metadata file for restore context
                    $meta = [PSCustomObject]@{
                        BackupTimestamp = $Timestamp
                        Computer        = $env:COMPUTERNAME
                        Username        = $profile.Username
                        SID             = $profile.SID
                        ProfilePath     = $profile.ProfilePath
                        SourcePath      = $qaSource
                        FileCount       = $copiedFiles.Count
                        TotalSizeBytes  = $totalSize
                        OSVersion       = [System.Environment]::OSVersion.VersionString
                    }
                    $meta | ConvertTo-Json -Depth 3 | Out-File (Join-Path $userBackupDir '_backup_metadata.json') -Encoding UTF8

                    $output.Add([PSCustomObject]@{
                        Computer  = $env:COMPUTERNAME
                        Username  = $profile.Username
                        Status    = 'SUCCESS'
                        Message   = "Backed up $($copiedFiles.Count) files ($([math]::Round($totalSize / 1KB, 1)) KB)"
                        Timestamp = $Timestamp
                        BackupDir = $userBackupDir
                        FileCount = $copiedFiles.Count
                        TotalSize = $totalSize
                    })
                }
                catch {
                    $output.Add([PSCustomObject]@{
                        Computer  = $env:COMPUTERNAME
                        Username  = $profile.Username
                        Status    = 'ERROR'
                        Message   = "Backup failed: $($_.Exception.Message)"
                        Timestamp = $Timestamp
                        BackupDir = $userBackupDir
                        FileCount = 0
                        TotalSize = 0
                    })
                }
            }

            # Retention cleanup
            $userDirs = Get-ChildItem $BackupRoot -Directory -ErrorAction SilentlyContinue
            foreach ($userDir in $userDirs) {
                $cutoff = (Get-Date).AddDays(-$RetentionDays)
                Get-ChildItem $userDir.FullName -Directory | ForEach-Object {
                    $dirDate = $null
                    if ($_.Name -match '^\d{8}_\d{6}$') {
                        try {
                            $dirDate = [DateTime]::ParseExact($_.Name, 'yyyyMMdd_HHmmss', $null)
                        }
                        catch { }
                    }
                    if ($dirDate -and $dirDate -lt $cutoff) {
                        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            return $output
        }

        $invokeParams = @{
            ScriptBlock  = $scriptBlock
            ArgumentList = @($BackupRoot, $Username, $RetentionDays, $timestamp)
        }

        if ($isRemote) {
            $invokeParams['ComputerName'] = $ComputerName
            if ($Credential) { $invokeParams['Credential'] = $Credential }
            Write-Log "Connecting to remote machine: $ComputerName"
        }

        Write-Log "Starting Quick Access backup  -  Target: $ComputerName, User: $(if ($Username) { $Username } else { 'ALL' }), Retention: $RetentionDays days"

        if ($PSCmdlet.ShouldProcess($ComputerName, "Backup Quick Access pins")) {
            $invokeResults = Invoke-Command @invokeParams

            foreach ($r in $invokeResults) {
                $results.Add($r)
                Write-Log "$($r.Username): $($r.Status)  -  $($r.Message)" -Level $r.Status
            }
        }
    }

    end {
        Write-Log "Backup complete. $($results.Count) profile(s) processed."

        # Per-entry summary to log (Format-Table truncates in narrow consoles/DattoRMM)
        foreach ($r in $results) {
            Write-Log "  [$($r.Status)] $($r.Computer) \ $($r.Username)  -  $($r.Message)"
        }
    }
}

# ==============================================================================
# ENTRY POINT
# Splat all script-level parameters into the master function.
# ==============================================================================
$ScriptParams = @{
    ComputerName  = $ComputerName
    Username      = $Username
    BackupRoot    = $BackupRoot
    RetentionDays = $RetentionDays
    LogPath       = $LogPath
    SiteName      = $SiteName
    Hostname      = $Hostname
}
if ($Credential) { $ScriptParams['Credential'] = $Credential }

Backup-QuickAccessPins @ScriptParams
