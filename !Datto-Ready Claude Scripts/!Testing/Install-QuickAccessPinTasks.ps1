#Requires -Version 5.1
# ==============================================================================
# SCRIPT-LEVEL PARAMETERS
# ==============================================================================
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$Username = $(if ($env:QA_Username) { $env:QA_Username } else { "" }),

    [Parameter()]
    [string]$ScriptRoot = $(if ($env:QA_ScriptRoot) { $env:QA_ScriptRoot } else { "C:\QAFix" }),

    [Parameter()]
    [string]$BackupRoot = $(if ($env:QA_BackupRoot) { $env:QA_BackupRoot } else { "C:\ProgramData\Databranch\QABackups" }),

    [Parameter()]
    [int]$RetentionDays = $(if ($env:QA_RetentionDays) { [int]$env:QA_RetentionDays } else { 30 }),

    # If set, removes tasks and shortcuts instead of creating them
    [Parameter()]
    [switch]$Uninstall,

    # DattoRMM built-in variables
    [Parameter()]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }),

    [Parameter()]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

<#
.SYNOPSIS
    Creates scheduled tasks and desktop shortcuts so a standard user can trigger
    Quick Access pin backup and restore without elevation.

.DESCRIPTION
    Install-QuickAccessPinTasks configures a machine so that a specified standard
    user account can reliably back up and restore their Explorer Quick Access pins
    on demand, without needing admin rights or UAC elevation at run time.

    Safe to run as SYSTEM via ScreenConnect Backstage. Resolves the target user's
    desktop path from the registry profile list rather than $env:USERPROFILE, so
    it works correctly regardless of the execution context.

    What this script creates:
      - Scheduled Task: "QA Backup - <Username>"
          Runs Backup-QuickAccessPins.ps1 as SYSTEM with highest privileges.
          Triggered on demand (shortcut) and daily at 5:00 PM automatically.

      - Scheduled Task: "QA Restore - <Username>"
          Runs Restore-QuickAccessPins.ps1 as SYSTEM with highest privileges.
          Includes -RestartExplorer so pins are live immediately.
          Triggered on demand (shortcut) only.

      - Desktop Shortcut: "Backup My Quick Access Pins.lnk"
          Placed on the target user's desktop. Runs the backup task silently.

      - Desktop Shortcut: "Restore My Quick Access Pins.lnk"
          Placed on the target user's desktop. Runs the restore task silently.

    Run with -Uninstall to remove all tasks and shortcuts cleanly.

.PARAMETER Username
    The standard user account to configure. Required.
    DattoRMM env var: QA_Username.

.PARAMETER ScriptRoot
    Path where Backup-QuickAccessPins.ps1 and Restore-QuickAccessPins.ps1 live.
    Default: C:\QAFix. DattoRMM env var: QA_ScriptRoot.

.PARAMETER BackupRoot
    Root path for backup storage, passed through to the backup script.
    Default: C:\ProgramData\Databranch\QABackups. DattoRMM env var: QA_BackupRoot.

.PARAMETER RetentionDays
    Backup retention in days, passed through to the backup script.
    Default: 30. DattoRMM env var: QA_RetentionDays.

.PARAMETER Uninstall
    Removes the two scheduled tasks and both desktop shortcuts.

.EXAMPLE
    .\Install-QuickAccessPinTasks.ps1 -Username jclonch
    Creates tasks and shortcuts for jclonch using default paths.

.EXAMPLE
    .\Install-QuickAccessPinTasks.ps1 -Username jclonch -ScriptRoot "C:\QAFix" -RetentionDays 60
    Creates tasks and shortcuts with a 60-day backup retention.

.EXAMPLE
    .\Install-QuickAccessPinTasks.ps1 -Username jclonch -Uninstall
    Removes all tasks and shortcuts created for jclonch.

.NOTES
    File Name      : Install-QuickAccessPinTasks.ps1
    Version        : 1.0.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-03-25
    Last Modified  : 2026-03-25
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM (ScreenConnect Backstage) or Domain Admin
    DattoRMM       : Compatible -- supports QA_* environment variable input
    Client Scope   : All clients

    Exit Codes:
        0  - Success
        1  - General failure
        2  - Username not specified
        3  - Script files not found at ScriptRoot
        4  - User profile not found on this machine

    Notes:
        - Must run as SYSTEM or a local/domain admin account.
        - The target user does NOT need admin rights -- that is the entire point.
        - Desktop path is resolved from the registry profile list so this works
          correctly when running as SYSTEM (where $env:USERPROFILE is wrong).
        - Shortcuts use schtasks.exe /Run so the user triggers the task with a
          double-click and never sees a UAC prompt.
        - The backup task also runs automatically at 5:00 PM daily as a safety net.
          The shortcut lets her trigger an immediate backup whenever she wants.

.CHANGELOG
    v1.0.0.0 - 2026-03-25 - Sam Kirsch
        - Initial release.
#>

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Install-QuickAccessPinTasks {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Username,
        [string]$ScriptRoot,
        [string]$BackupRoot,
        [int]$RetentionDays,
        [switch]$Uninstall,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Install-QuickAccessPinTasks"
    $ScriptVersion = "1.0.0.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    $TaskNameBackup  = "QA Backup - $Username"
    $TaskNameRestore = "QA Restore - $Username"

    $BackupScript  = Join-Path $ScriptRoot "Backup-QuickAccessPins.ps1"
    $RestoreScript = Join-Path $ScriptRoot "Restore-QuickAccessPins.ps1"

    # ==========================================================================
    # LOGGING
    # ==========================================================================
    if (-not (Test-Path $LogFolder)) {
        New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
    }
    try {
        $existing = Get-ChildItem -Path $LogFolder -Filter "$($ScriptName)_*.log" |
                    Sort-Object LastWriteTime -Descending
        if ($existing.Count -ge $MaxLogFiles) {
            $existing | Select-Object -Skip ($MaxLogFiles - 1) | ForEach-Object {
                Remove-Item -Path $_.FullName -Force
            }
        }
    }
    catch { }

    function Write-Log {
        param([string]$Message, [string]$Level = "INFO")
        $ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $entry = "[$ts] [$Level] $Message"
        switch ($Level) {
            "WARN"  { Write-Warning $entry }
            "ERROR" { Write-Error   $entry -ErrorAction Continue }
            default { Write-Output  $entry }
        }
        try { Add-Content -Path $LogFile -Value $entry -Encoding UTF8 } catch { }
    }

    function Write-Console {
        param([string]$Message = "", [string]$Severity = "PLAIN", [int]$Indent = 0)
        $Prefix = "  " * $Indent
        $Colors = @{ INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; DEBUG="Magenta"; PLAIN="Gray" }
        $Color  = $Colors[$Severity]
        if ($Severity -eq "PLAIN") { Write-Host "$Prefix$Message" -ForegroundColor $Color }
        else {
            Write-Host "$Prefix" -NoNewline
            Write-Host "[$Severity]" -ForegroundColor $Color -NoNewline
            Write-Host " $Message" -ForegroundColor White
        }
    }

    function Write-Banner {
        param([string]$Title, [string]$Color = "Cyan")
        $Line = "=" * 60
        Write-Host ""; Write-Host $Line -ForegroundColor $Color
        Write-Host "  $Title" -ForegroundColor White
        Write-Host $Line -ForegroundColor $Color; Write-Host ""
    }

    function Write-Section {
        param([string]$Title, [string]$Color = "Cyan")
        $s = "---- $Title "
        $p = "-" * [Math]::Max(0, 60 - $s.Length)
        Write-Host ""; Write-Host "$s$p" -ForegroundColor $Color
    }

    function Write-Separator {
        Write-Host ("-" * 60) -ForegroundColor DarkGray
    }

    # ==========================================================================
    # STARTUP
    # ==========================================================================
    $ErrorActionPreference = "Stop"
    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log "===== $ScriptName v$ScriptVersion ======"
    Write-Log "Site     : $SiteName"
    Write-Log "Hostname : $Hostname"
    Write-Log "Run As   : $RunAs"
    Write-Log "Params   : Username='$Username' | ScriptRoot='$ScriptRoot' | BackupRoot='$BackupRoot' | RetentionDays=$RetentionDays | Uninstall=$($Uninstall.IsPresent)"
    Write-Log "Log File : $LogFile"

    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site     : $SiteName"   -Severity PLAIN
    Write-Console "Hostname : $Hostname"   -Severity PLAIN
    Write-Console "Run As   : $RunAs"      -Severity PLAIN
    Write-Console "Log File : $LogFile"    -Severity PLAIN
    Write-Separator

    try {

        # ======================================================================
        # VALIDATE USERNAME
        # ======================================================================
        if (-not $Username) {
            Write-Log "Username is required but was not specified." -Level ERROR
            Write-Console "Username is required. Use -Username or set QA_Username." -Severity ERROR
            Write-Banner "SCRIPT FAILED" -Color Red
            exit 2
        }

        # ======================================================================
        # RESOLVE USER PROFILE PATH FROM REGISTRY
        # Cannot use $env:USERPROFILE -- when running as SYSTEM that points to
        # C:\Windows\System32\config\systemprofile, not the target user's profile.
        # ======================================================================
        Write-Section "Resolving User Profile"

        $profileEntry = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
            Where-Object { $_.PSChildName -match '^S-1-5-21-' } |
            ForEach-Object {
                $path = (Get-ItemProperty $_.PSPath).ProfileImagePath
                [PSCustomObject]@{
                    Username    = Split-Path $path -Leaf
                    ProfilePath = $path
                }
            } |
            Where-Object { $_.Username -eq $Username } |
            Select-Object -First 1

        if (-not $profileEntry) {
            Write-Log "No profile found for user '$Username' on this machine." -Level ERROR
            Write-Console "No profile found for '$Username'. Has this user logged in at least once?" -Severity ERROR
            Write-Banner "SCRIPT FAILED" -Color Red
            exit 4
        }

        $userDesktop = Join-Path $profileEntry.ProfilePath "Desktop"

        Write-Log "Profile  : $($profileEntry.ProfilePath)"
        Write-Log "Desktop  : $userDesktop"
        Write-Console "User     : $Username" -Severity INFO
        Write-Console "Profile  : $($profileEntry.ProfilePath)" -Severity INFO
        Write-Console "Desktop  : $userDesktop" -Severity INFO

        # ======================================================================
        # UNINSTALL MODE
        # ======================================================================
        if ($Uninstall) {
            Write-Section "Uninstalling Tasks and Shortcuts" -Color Yellow

            # Remove scheduled tasks
            foreach ($taskName in @($TaskNameBackup, $TaskNameRestore)) {
                if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
                    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                    Write-Log "Removed scheduled task: $taskName" -Level SUCCESS
                    Write-Console "Removed task: $taskName" -Severity SUCCESS
                }
                else {
                    Write-Log "Task not found (skipping): $taskName" -Level WARN
                    Write-Console "Task not found (skipping): $taskName" -Severity WARN
                }
            }

            # Remove desktop shortcuts
            $shortcuts = @(
                (Join-Path $userDesktop "Backup My Quick Access Pins.lnk"),
                (Join-Path $userDesktop "Restore My Quick Access Pins.lnk")
            )
            foreach ($lnk in $shortcuts) {
                if (Test-Path $lnk) {
                    Remove-Item -Path $lnk -Force
                    Write-Log "Removed shortcut: $lnk" -Level SUCCESS
                    Write-Console "Removed shortcut: $(Split-Path $lnk -Leaf)" -Severity SUCCESS
                }
                else {
                    Write-Log "Shortcut not found (skipping): $lnk" -Level WARN
                    Write-Console "Shortcut not found (skipping): $(Split-Path $lnk -Leaf)" -Severity WARN
                }
            }

            Write-Log "Uninstall complete." -Level SUCCESS
            Write-Banner "UNINSTALL COMPLETE" -Color Green
            exit 0
        }

        # ======================================================================
        # VALIDATE SCRIPT FILES EXIST
        # ======================================================================
        Write-Section "Validating Script Files"

        $missing = @()
        if (-not (Test-Path $BackupScript))  { $missing += $BackupScript }
        if (-not (Test-Path $RestoreScript)) { $missing += $RestoreScript }

        if ($missing.Count -gt 0) {
            foreach ($m in $missing) {
                Write-Log "Script file not found: $m" -Level ERROR
                Write-Console "Missing: $m" -Severity ERROR
            }
            Write-Log "Place Backup-QuickAccessPins.ps1 and Restore-QuickAccessPins.ps1 in '$ScriptRoot' and re-run." -Level ERROR
            Write-Banner "SCRIPT FAILED" -Color Red
            exit 3
        }

        Write-Log "Found: $BackupScript"  -Level SUCCESS
        Write-Log "Found: $RestoreScript" -Level SUCCESS
        Write-Console "Found: $BackupScript"  -Severity SUCCESS
        Write-Console "Found: $RestoreScript" -Severity SUCCESS

        # ======================================================================
        # CREATE SCHEDULED TASKS
        # Both run as SYSTEM with highest privileges so the standard user never
        # needs to elevate. The user triggers them via schtasks /Run from a
        # desktop shortcut -- no UAC prompt, no admin rights required.
        # ======================================================================
        Write-Section "Creating Scheduled Tasks"

        $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

        # --- Backup Task ---
        # Runs on demand AND daily at 5 PM as an automatic safety-net backup.
        $backupArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass " +
                      "-File `"$BackupScript`" " +
                      "-Username `"$Username`" " +
                      "-BackupRoot `"$BackupRoot`" " +
                      "-RetentionDays $RetentionDays"

        $backupAction  = New-ScheduledTaskAction  -Execute $psExe -Argument $backupArgs
        $backupTrigger = New-ScheduledTaskTrigger -Daily -At "5:00PM"
        $backupSettings = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
            -MultipleInstances IgnoreNew `
            -StartWhenAvailable

        # SYSTEM principal, highest privileges -- standard user can still /Run it
        $backupPrincipal = New-ScheduledTaskPrincipal `
            -UserId    "SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel  Highest

        $backupTask = New-ScheduledTask `
            -Action    $backupAction `
            -Trigger   $backupTrigger `
            -Principal $backupPrincipal `
            -Settings  $backupSettings `
            -Description "Backs up Quick Access pins for $Username. Created by $ScriptName v$ScriptVersion."

        Register-ScheduledTask `
            -TaskName   $TaskNameBackup `
            -InputObject $backupTask `
            -Force | Out-Null

        Write-Log "Created scheduled task: $TaskNameBackup" -Level SUCCESS
        Write-Console "Created task: $TaskNameBackup" -Severity SUCCESS
        Write-Console "  Daily at 5:00 PM + on-demand via shortcut" -Severity PLAIN -Indent 1

        # --- Restore Task ---
        # On-demand only (no automatic trigger). RestartExplorer baked in so
        # pins are live immediately after she double-clicks the shortcut.
        $restoreArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass " +
                       "-File `"$RestoreScript`" " +
                       "-Username `"$Username`" " +
                       "-BackupRoot `"$BackupRoot`" " +
                       "-RestartExplorer"

        $restoreAction   = New-ScheduledTaskAction -Execute $psExe -Argument $restoreArgs
        $restoreSettings = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
            -MultipleInstances IgnoreNew `
            -StartWhenAvailable

        $restorePrincipal = New-ScheduledTaskPrincipal `
            -UserId    "SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel  Highest

        # No trigger -- on-demand only via shortcut
        $restoreTask = New-ScheduledTask `
            -Action    $restoreAction `
            -Principal $restorePrincipal `
            -Settings  $restoreSettings `
            -Description "Restores Quick Access pins for $Username and restarts Explorer. Created by $ScriptName v$ScriptVersion."

        Register-ScheduledTask `
            -TaskName    $TaskNameRestore `
            -InputObject $restoreTask `
            -Force | Out-Null

        Write-Log "Created scheduled task: $TaskNameRestore" -Level SUCCESS
        Write-Console "Created task: $TaskNameRestore" -Severity SUCCESS
        Write-Console "  On-demand via shortcut only, Explorer restarts automatically" -Severity PLAIN -Indent 1

        # ======================================================================
        # CREATE DESKTOP SHORTCUTS
        # Uses WScript.Shell COM object -- available to SYSTEM on all Windows
        # versions without any additional dependencies.
        #
        # The shortcut runs:
        #   schtasks.exe /Run /TN "<TaskName>"
        # Any standard user can issue schtasks /Run against a pre-existing task.
        # No elevation prompt. The task itself runs as SYSTEM.
        # ======================================================================
        Write-Section "Creating Desktop Shortcuts"

        if (-not (Test-Path $userDesktop)) {
            New-Item -ItemType Directory -Path $userDesktop -Force | Out-Null
            Write-Log "Created desktop folder: $userDesktop" -Level INFO
        }

        $shell = New-Object -ComObject WScript.Shell

        # Helper -- creates a .lnk shortcut
        function New-Shortcut {
            param(
                [string]$LnkPath,
                [string]$TargetPath,
                [string]$Arguments,
                [string]$Description,
                [string]$IconPath,
                [int]$IconIndex = 0,
                [int]$WindowStyle = 7   # 7 = minimized (no console flash)
            )
            $lnk                  = $shell.CreateShortcut($LnkPath)
            $lnk.TargetPath       = $TargetPath
            $lnk.Arguments        = $Arguments
            $lnk.Description      = $Description
            $lnk.IconLocation     = "$($IconPath),$IconIndex"
            $lnk.WindowStyle      = $WindowStyle
            $lnk.WorkingDirectory = $env:SystemRoot
            $lnk.Save()
        }

        $schtasksExe = Join-Path $env:SystemRoot "System32\schtasks.exe"

        # Backup shortcut -- briefcase icon from shell32.dll
        $backupLnk = Join-Path $userDesktop "Backup My Quick Access Pins.lnk"
        New-Shortcut `
            -LnkPath     $backupLnk `
            -TargetPath  $schtasksExe `
            -Arguments   "/Run /TN `"$TaskNameBackup`"" `
            -Description "Backs up your Quick Access pins to a safe location." `
            -IconPath    "$env:SystemRoot\System32\shell32.dll" `
            -IconIndex   166    # briefcase / save icon

        Write-Log "Created shortcut: $backupLnk" -Level SUCCESS
        Write-Console "Created: Backup My Quick Access Pins.lnk" -Severity SUCCESS

        # Restore shortcut -- undo/restore icon from shell32.dll
        $restoreLnk = Join-Path $userDesktop "Restore My Quick Access Pins.lnk"
        New-Shortcut `
            -LnkPath     $restoreLnk `
            -TargetPath  $schtasksExe `
            -Arguments   "/Run /TN `"$TaskNameRestore`"" `
            -Description "Restores your Quick Access pins from the most recent backup." `
            -IconPath    "$env:SystemRoot\System32\shell32.dll" `
            -IconIndex   238    # circular arrow / restore icon

        Write-Log "Created shortcut: $restoreLnk" -Level SUCCESS
        Write-Console "Created: Restore My Quick Access Pins.lnk" -Severity SUCCESS

        # ======================================================================
        # SUMMARY
        # ======================================================================
        Write-Section "Summary"

        Write-Log "Setup complete for user '$Username'." -Level SUCCESS
        Write-Log "  Backup task  : $TaskNameBackup (daily 5 PM + on-demand)"
        Write-Log "  Restore task : $TaskNameRestore (on-demand, Explorer restarts automatically)"
        Write-Log "  Backup LNK   : $backupLnk"
        Write-Log "  Restore LNK  : $restoreLnk"
        Write-Log "  Scripts from : $ScriptRoot"
        Write-Log "  Backups to   : $BackupRoot"
        Write-Log "  Retention    : $RetentionDays days"

        Write-Console "Setup complete for: $Username" -Severity SUCCESS
        Write-Console "Backup task  : $TaskNameBackup" -Severity PLAIN -Indent 1
        Write-Console "Restore task : $TaskNameRestore" -Severity PLAIN -Indent 1
        Write-Console "Shortcuts on : $userDesktop" -Severity PLAIN -Indent 1
        Write-Console "" -Severity PLAIN
        Write-Console "She can now double-click either shortcut without any admin rights." -Severity INFO

        Write-Banner "SETUP COMPLETE" -Color Green
        exit 0

    }
    catch {
        Write-Log "Unhandled exception: $_" -Level ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level ERROR
        Write-Console "Unhandled exception: $_" -Severity ERROR
        Write-Banner "SCRIPT FAILED" -Color Red
        exit 1
    }

} # End function Install-QuickAccessPinTasks

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    Username      = $Username
    ScriptRoot    = $ScriptRoot
    BackupRoot    = $BackupRoot
    RetentionDays = $RetentionDays
    Uninstall     = $Uninstall
    SiteName      = $SiteName
    Hostname      = $Hostname
}

Install-QuickAccessPinTasks @ScriptParams
