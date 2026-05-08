#Requires -Version 5.1
<#
.SYNOPSIS
    Assesses the active ThirdWall policy footprint on an endpoint and reports
    findings to stdout and the Databranch script log.

.DESCRIPTION
    Performs a passive read-only assessment of all known ThirdWall policy
    enforcement mechanisms on a Windows endpoint. For each of the 40+ ThirdWall
    policy IDs, the script checks the known registry keys, service states, and
    HKCU hives that ThirdWall writes to when a policy is applied.

    For every policy assessed, the report includes:
      - Policy ID and friendly name
      - Whether it is active (ACTIVE / NOT DETECTED)
      - How it is enforced (registry path, key, value)
      - The TWUndo.exe slash command to remove it
      - The manual registry remediation command

    USER-CONTEXT POLICIES:
    ThirdWall user policies write to HKCU rather than HKLM. When running as
    SYSTEM, the script enumerates all loaded user hives under HKU and assesses
    each one individually. Each assessed user is identified by SID and resolved
    to a username where possible. Users whose hives are not loaded (not currently
    logged on) cannot be assessed and are flagged explicitly.

    THIS SCRIPT IS PASSIVE. It makes no changes to the system.

.PARAMETER SiteName
    DattoRMM site/customer name. Populated automatically from CS_PROFILE_NAME
    environment variable when run via DattoRMM agent.

.PARAMETER Hostname
    Target machine hostname. Populated automatically from CS_HOSTNAME
    environment variable when run via DattoRMM agent.

.EXAMPLE
    .\Get-ThirdWallPolicyAssessment.ps1
    Runs full assessment against the local machine in DattoRMM context.

.EXAMPLE
    .\Get-ThirdWallPolicyAssessment.ps1 -SiteName "Acme Corp" -Hostname "DESKTOP-01"
    Runs full assessment with explicit site and hostname metadata.

.NOTES
    File Name      : Get-ThirdWallPolicyAssessment.ps1
    Version        : v1.2.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-05-07
    Last Modified  : 2026-05-07
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM (DattoRMM agent context)
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : All clients

    Exit Codes:
        0  - Assessment completed successfully
        1  - Assessment completed with errors (some policies could not be checked)
        2  - Fatal pre-flight failure

    Output Design:
        Write-Log     - Structured [timestamp][SEVERITY] output to log file AND
                        DattoRMM stdout. Always verbose. No color.
        Write-Console - Human-friendly colored console output for manual/interactive
                        runs. Uses Write-Host (display stream only).

    Assessment Coverage:
        Machine policies  : HKLM registry keys (all policies)
        User policies     : HKU hives for all currently loaded user profiles
        Service states    : USBSTOR, cdrom driver start values
        Filter drivers    : USB and CD-ROM device class upper/lower filters
        SRP               : Software Restriction Policy CodeIdentifiers key
        GPO overlap       : RemovableStorageDevices and DeviceInstall policy paths

.CHANGELOG
    v1.2.0.0 - 2026-05-07 - Sam Kirsch
        - Fixed $script: scope prefix on ActiveFindings/RemoveList/LeaveList .Add() calls
          inside Write-PolicyFinding nested function. $script: was resolving to the root
          script scope rather than the master function scope, causing null-ref errors on
          every active policy and leaving all tracking lists empty (summary showed 1 active
          when 9 were actually detected).
        - Fixed .DEFAULT hive being assessed as a user. Added SkipPatterns array alongside
          SkippedSIDs to filter non-SID entries like .DEFAULT from HKU enumeration.

    v1.1.0.0 - 2026-05-07 - Sam Kirsch
        - Added RemoveRecommended and RemoveReason fields to all policy definitions
        - Updated Write-PolicyFinding to display recommendation and reason per active finding
        - Added three-list tracking: ActiveFindings, RemoveList, LeaveList
        - Overhauled summary section: all active findings, remove-recommended list with
          copy-paste TWUndo PolicyIds string, leave-in-place list — all as separate sections

    v1.0.0.0 - 2026-05-07 - Sam Kirsch
        - Initial release
        - Full passive assessment of all known ThirdWall policy IDs (2-58)
        - Machine-context HKLM checks for all policies
        - User-context HKU enumeration for user-scoped policies
        - SID-to-username resolution for all loaded user hives
        - Service state checks (USBSTOR, cdrom)
        - Filter driver checks (USB class, CD-ROM class)
        - Per-policy TWUndo command and manual remediation command in output
        - Summary: active count, not-detected count, user hives assessed
#>

# ==============================================================================
# ORDER IS NON-NEGOTIABLE: [CmdletBinding()] then TLS block then param()
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(
        if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { 'UnknownSite' }
    ),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(
        if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME }
    )
)

[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

function Get-ThirdWallPolicyAssessment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$SiteName,

        [Parameter(Mandatory = $false)]
        [string]$Hostname
    )

    # ==========================================================================
    # SCRIPT METADATA
    # ==========================================================================
    $ScriptName    = 'Get-ThirdWallPolicyAssessment'
    $ScriptVersion = 'v1.2.0.0'

    # ==========================================================================
    # LOGGING INFRASTRUCTURE
    # ==========================================================================
    $LogRoot = 'C:\Databranch\ScriptLogs'
    $LogDir  = Join-Path $LogRoot $ScriptName
    $LogDate = Get-Date -Format 'yyyy-MM-dd'
    $LogFile = Join-Path $LogDir "${ScriptName}_${LogDate}.log"

    function Initialize-Logging {
        if (-not (Test-Path -Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }
        $ExistingLogs = Get-ChildItem -Path $LogDir -Filter '*.log' -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending
        if ($ExistingLogs.Count -ge 10) {
            $ExistingLogs | Select-Object -Skip 9 | ForEach-Object {
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    function Write-Log {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = '',

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG')]
            [string]$Severity = 'INFO'
        )
        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $LogEntry  = "[$Timestamp] [$Severity] $Message"
        switch ($Severity) {
            'INFO'    { Write-Output  $LogEntry }
            'WARN'    { Write-Warning $LogEntry }
            'ERROR'   { Write-Error   $LogEntry -ErrorAction Continue }
            'SUCCESS' { Write-Output  $LogEntry }
            'DEBUG'   { Write-Output  $LogEntry }
        }
        try {
            Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8
        }
        catch {
            Write-Warning "[$Timestamp] [WARN] Could not write to log file: $_"
        }
    }

    function Write-Console {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = '',

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG','PLAIN')]
            [string]$Severity = 'INFO',

            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )
        $Colors = @{
            INFO    = 'Cyan'
            WARN    = 'Yellow'
            ERROR   = 'Red'
            SUCCESS = 'Green'
            DEBUG   = 'Magenta'
            PLAIN   = 'Gray'
        }
        $Prefix = switch ($Severity) {
            'INFO'    { '[INFO]    ' }
            'WARN'    { '[WARN]    ' }
            'ERROR'   { '[ERROR]   ' }
            'SUCCESS' { '[SUCCESS] ' }
            'DEBUG'   { '[DEBUG]   ' }
            'PLAIN'   { '          ' }
        }
        $Pad  = ' ' * ($Indent * 2)
        $Line = if ($Severity -eq 'PLAIN') { "$Pad$Message" } else { "$Pad$Prefix$Message" }
        Write-Host $Line -ForegroundColor $Colors[$Severity]
    }

    function Write-Banner {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Title,
            [Parameter(Mandatory = $false)]
            [string]$Color = 'Cyan'
        )
        $Line = '=' * 60
        Write-Host ''
        Write-Host $Line      -ForegroundColor $Color
        Write-Host "  $Title" -ForegroundColor White
        Write-Host $Line      -ForegroundColor $Color
        Write-Host ''
    }

    function Write-Section {
        param ([Parameter(Mandatory = $true)][string]$Title)
        Write-Host ''
        Write-Host "--- $Title ---" -ForegroundColor DarkCyan
        Write-Host ''
    }

    function Write-Separator {
        Write-Host ('-' * 60) -ForegroundColor DarkGray
    }

    # ==========================================================================
    # POLICY DEFINITION TABLE
    # Each entry defines how ThirdWall enforces the policy and how to detect it.
    #
    # CheckType values:
    #   HKLM_KEY_EXISTS   - policy active if registry key exists
    #   HKLM_VALUE        - policy active if registry value matches expected data
    #   HKLM_VALUE_EXISTS - policy active if registry value exists (any data)
    #   SERVICE_START     - policy active if service Start value equals Expected
    #   FILTER_DRIVER     - policy active if value contains driver name
    #   HKCU_VALUE        - user policy, checked per loaded HKU hive
    #   HKCU_KEY_EXISTS   - user policy key presence, checked per loaded HKU hive
    #   MULTI             - multiple sub-checks (handled inline)
    # ==========================================================================
    $PolicyDefinitions = @(

        # ----------------------------------------------------------------------
        # POLICY 2 - Rename Local Administrator Account
        # Detection: SAM account name of the built-in admin differs from default
        # This one requires WMI, handled as SPECIAL type
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 2
            Name        = 'Rename Local Administrator Account'
            CheckType   = 'SPECIAL_ADMIN_RENAME'
            RegPath     = ''
            RegValue    = ''
            Expected    = ''
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /2'
            ManualFix          = 'Rename the local Administrator account back to "Administrator" via: Rename-LocalUser -Name "<CurrentName>" -NewName "Administrator"'
            Notes              = 'Detection requires resolving built-in admin SID S-1-5-21-*-500 and checking current name.'
            RemoveRecommended  = $false
            RemoveReason       = 'Account rename may be intentional baseline hardening. Verify with customer before reverting.'
        },

        # ----------------------------------------------------------------------
        # POLICY 4 - Disable Local Administrator Account
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 4
            Name        = 'Disable Local Administrator Account'
            CheckType   = 'SPECIAL_ADMIN_DISABLED'
            RegPath     = ''
            RegValue    = ''
            Expected    = ''
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /4'
            ManualFix          = 'Enable-LocalUser -SID "S-1-5-21-*-500"  (or net user Administrator /active:yes)'
            Notes              = 'Checks if built-in Administrator account (RID 500) is disabled.'
            RemoveRecommended  = $false
            RemoveReason       = 'Disabling the built-in admin is a baseline security practice. Leave unless access is needed.'
        },

        # ----------------------------------------------------------------------
        # POLICY 7 - Enable Password Protected Screen Saver
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 7
            Name        = 'Enable Password Protected Screen Saver'
            CheckType   = 'HKCU_VALUE'
            RegPath     = 'Control Panel\Desktop'
            RegValue    = 'ScreenSaverIsSecure'
            Expected    = '1'
            UserScoped  = $true
            TWUndoCmd          = 'TWUndo.exe /7'
            ManualFix          = 'reg delete "HKCU\Control Panel\Desktop" /v ScreenSaverIsSecure /f'
            Notes              = 'User policy — must be assessed per loaded user hive.'
            RemoveRecommended  = $false
            RemoveReason       = 'Password-protected screen saver is a reasonable baseline security setting. Leave unless customer objects.'
        },

        # ----------------------------------------------------------------------
        # POLICY 8 - Restrict Local Administrator Tools
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 8
            Name        = 'Restrict Local Administrator Tools'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
            RegValue    = 'RestrictRun'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /8'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v RestrictRun /f'
            Notes              = 'Also check RestrictRun subkey for blocked executable list.'
            RemoveRecommended  = $true
            RemoveReason       = 'ThirdWall-specific restriction that blocks admin tooling. Remove to restore normal administrative access.'
        },

        # ----------------------------------------------------------------------
        # POLICY 9 - Enable UAC
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 9
            Name        = 'Enable UAC'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
            RegValue    = 'EnableLUA'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /9'
            ManualFix          = 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 0 /f'
            Notes              = 'Active means UAC is ON (value=1). TWUndo disables it — only undo if intentional.'
            RemoveRecommended  = $false
            RemoveReason       = 'UAC should remain enabled. Do not remove unless there is a specific documented reason.'
        },

        # ----------------------------------------------------------------------
        # POLICY 10 - Disable Setup.exe and Install.exe (SRP)
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 10
            Name        = 'Disable Setup.exe and Install.exe'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers'
            RegValue    = 'DefaultLevel'
            Expected    = 262144
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /10'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers" /f'
            Notes              = 'DefaultLevel 262144 = Disallowed (SRP active). 0 = Unrestricted. Full key delete is cleanest.'
            RemoveRecommended  = $true
            RemoveReason       = 'SRP enforcement blocks legitimate software installation. Remove to restore normal installer execution.'
        },

        # ----------------------------------------------------------------------
        # POLICY 11 - Disable Windows Installer
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 11
            Name        = 'Disable Windows Installer'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer'
            RegValue    = 'DisableMSI'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /11'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer" /v DisableMSI /f'
            Notes              = ''
            RemoveRecommended  = $true
            RemoveReason       = 'Disabling Windows Installer blocks MSI-based software deployment. Remove to restore normal software management.'
        },

        # ----------------------------------------------------------------------
        # POLICY 12 - Disable Windows 10 Keylogger
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 12
            Name        = 'Disable Windows 10 Keylogger'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            RegValue    = 'AllowTelemetry'
            Expected    = 0
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /12'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /f'
            Notes              = 'AllowTelemetry=0 disables telemetry/data collection.'
            RemoveRecommended  = $false
            RemoveReason       = 'Disabling telemetry is a reasonable privacy setting. Leave unless customer wants diagnostics data restored.'
        },

        # ----------------------------------------------------------------------
        # POLICY 13 - Enable Logon Message
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 13
            Name        = 'Enable Logon Message'
            CheckType   = 'HKLM_VALUE_EXISTS'
            RegPath     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
            RegValue    = 'LegalNoticeText'
            Expected    = ''
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /13'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LegalNoticeText /f && reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v LegalNoticeCaption /f'
            Notes              = 'Active if LegalNoticeText value exists and is non-empty.'
            RemoveRecommended  = $true
            RemoveReason       = 'ThirdWall logon banner is a remnant of the old deployment. Remove to clean up the logon experience.'
        },

        # ----------------------------------------------------------------------
        # POLICY 15 - Enable Smart Screen
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 15
            Name        = 'Enable Smart Screen'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
            RegValue    = 'EnableSmartScreen'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /15'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v EnableSmartScreen /f'
            Notes              = ''
            RemoveRecommended  = $false
            RemoveReason       = 'SmartScreen should remain enabled. It is an active Windows security feature independent of ThirdWall.'
        },

        # ----------------------------------------------------------------------
        # POLICY 17 - Disable AutoPlay (AutoRun)
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 17
            Name        = 'Disable AutoPlay (AutoRun)'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
            RegValue    = 'NoDriveTypeAutoRun'
            Expected    = 255
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /17'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDriveTypeAutoRun /f'
            Notes              = 'NoDriveTypeAutoRun=255 disables autorun on all drive types.'
            RemoveRecommended  = $false
            RemoveReason       = 'Disabling AutoRun is a standard Windows security baseline. Leave unless customer has a specific need.'
        },

        # ----------------------------------------------------------------------
        # POLICY 18 - Disable Running Exe from %APPDATA%
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 18
            Name        = 'Disable Running Exe from APPDATA'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers'
            RegValue    = 'DefaultLevel'
            Expected    = 262144
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /18'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers" /f'
            Notes              = 'Shares SRP key with policy 10. If both applied, single key delete clears both.'
            RemoveRecommended  = $true
            RemoveReason       = 'SRP enforcement is a ThirdWall remnant. Remove to restore normal application execution from user profile paths.'
        },

        # ----------------------------------------------------------------------
        # POLICY 19 - Disable Write to Optical Devices
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 19
            Name        = 'Disable Write to Optical Devices'
            CheckType   = 'HKLM_KEY_EXISTS'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{F33FDC04-D1AC-4E8E-9A30-19BBD4B108AE}'
            RegValue    = ''
            Expected    = ''
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /19'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{F33FDC04-D1AC-4E8E-9A30-19BBD4B108AE}" /f'
            Notes              = 'GUID {F33FDC04...} = CD-ROM/optical device class.'
            RemoveRecommended  = $true
            RemoveReason       = 'Customer-reported issue. Optical device restriction is a ThirdWall remnant and should be removed.'
        },

        # ----------------------------------------------------------------------
        # POLICY 20 - Disable Read & Write to Optical Devices
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 20
            Name        = 'Disable Read and Write to Optical Devices'
            CheckType   = 'HKLM_KEY_EXISTS'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{F33FDC04-D1AC-4E8E-9A30-19BBD4B108AE}'
            RegValue    = ''
            Expected    = ''
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /20'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{F33FDC04-D1AC-4E8E-9A30-19BBD4B108AE}" /f'
            Notes              = 'Shares GUID key with policy 19. Key delete clears both read and write deny.'
            RemoveRecommended  = $true
            RemoveReason       = 'Customer-reported issue. Optical device restriction is a ThirdWall remnant and should be removed.'
        },

        # ----------------------------------------------------------------------
        # POLICY 21 - Disable Write to USB Storage Devices
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 21
            Name        = 'Disable Write to USB Storage Devices'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies'
            RegValue    = 'WriteProtect'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /21'
            ManualFix          = 'reg delete "HKLM\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies" /v WriteProtect /f'
            Notes              = 'WriteProtect=1 enables write blocking on all removable storage.'
            RemoveRecommended  = $true
            RemoveReason       = 'USB write restriction is a ThirdWall remnant from the offboarding concern. Remove.'
        },

        # ----------------------------------------------------------------------
        # POLICY 22 - Disable Read & Write to USB Storage Devices
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 22
            Name        = 'Disable Read and Write to USB Storage Devices'
            CheckType   = 'HKLM_KEY_EXISTS'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53F5630D-B6BF-11D0-94F2-00A0C91EFB8B}'
            RegValue    = ''
            Expected    = ''
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /22'
            ManualFix          = 'reg add "HKLM\SYSTEM\CurrentControlSet\Services\usbstor" /t REG_DWORD /v start /d 3 /f && reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53F5630D-B6BF-11D0-94F2-00A0C91EFB8B}" /f'
            Notes              = 'GUID {53F5630D...} = USB mass storage device class. Also checks USBSTOR Start value.'
            RemoveRecommended  = $true
            RemoveReason       = 'USB read/write restriction is a ThirdWall remnant from the offboarding concern. Remove.'
        },

        # ----------------------------------------------------------------------
        # POLICY 23 - Disable Cloud Storage
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 23
            Name        = 'Disable Cloud Storage'
            CheckType   = 'HKCU_VALUE'
            RegPath     = 'SOFTWARE\Policies\Microsoft\Windows\OneDrive'
            RegValue    = 'DisableFileSyncNGSC'
            Expected    = '1'
            UserScoped  = $true
            TWUndoCmd          = 'TWUndo.exe /23'
            ManualFix          = 'reg delete "HKCU\SOFTWARE\Policies\Microsoft\Windows\OneDrive" /v DisableFileSyncNGSC /f'
            Notes              = 'User policy. Also check HKLM path for machine-wide enforcement.'
            RemoveRecommended  = $true
            RemoveReason       = 'Cloud storage restriction is a ThirdWall remnant. Remove to restore OneDrive/cloud sync access.'
        },

        # ----------------------------------------------------------------------
        # POLICY 27 - Enforce Complex Passwords
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 27
            Name        = 'Enforce Complex Passwords'
            CheckType   = 'SPECIAL_SECPOL'
            RegPath     = ''
            RegValue    = ''
            Expected    = ''
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /27'
            ManualFix          = 'secedit /configure /cfg %windir%\inf\defltbase.inf /db defltbase.sdb /verbose'
            Notes              = 'Enforced via local security policy (secedit). Cannot reliably detect via registry alone.'
            RemoveRecommended  = $false
            RemoveReason       = 'Complex password enforcement is a baseline security requirement. Leave in place.'
        },

        # ----------------------------------------------------------------------
        # POLICY 28 - Block Common Webmail
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 28
            Name        = 'Block Common Webmail'
            CheckType   = 'HKCU_KEY_EXISTS'
            RegPath     = 'SOFTWARE\Policies\Microsoft\Windows\IPSec\Policy\Local'
            RegValue    = ''
            Expected    = ''
            UserScoped  = $true
            TWUndoCmd          = 'TWUndo.exe /28'
            ManualFix          = 'Check hosts file at %windir%\System32\drivers\etc\hosts for webmail domain entries and remove manually.'
            Notes              = 'ThirdWall may use hosts file blocking or IPSec policy. Check hosts file as well.'
            RemoveRecommended  = $true
            RemoveReason       = 'Webmail blocking is a ThirdWall remnant. Remove to restore normal web access post-offboarding.'
        },

        # ----------------------------------------------------------------------
        # POLICY 30 - Disable Windows Store
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 30
            Name        = 'Disable Windows Store'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'
            RegValue    = 'RemoveWindowsStore'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /30'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\WindowsStore" /v RemoveWindowsStore /f'
            Notes              = ''
            RemoveRecommended  = $true
            RemoveReason       = 'Windows Store restriction is a ThirdWall remnant. Remove to restore default Windows behavior.'
        },

        # ----------------------------------------------------------------------
        # POLICY 33 - Disable Office Macros Downloaded from Internet
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 33
            Name        = 'Disable Office Macros Downloaded from Internet'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Excel\Security'
            RegValue    = 'blockcontentexecutionfrominternet'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /33'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\Excel\Security" /v blockcontentexecutionfrominternet /f'
            Notes              = 'Check Word, PowerPoint, and Excel subkeys under Office\16.0 and Office\15.0.'
            RemoveRecommended  = $false
            RemoveReason       = 'Blocking Office macros downloaded from the internet is a strong security control. Leave unless customer has a documented need.'
        },

        # ----------------------------------------------------------------------
        # POLICY 34 - Disable OLE in Office Documents
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 34
            Name        = 'Disable OLE in Office Documents'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Excel\Security'
            RegValue    = 'PackagerPrompt'
            Expected    = 2
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /34'
            ManualFix          = 'reg delete "HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\Excel\Security" /v PackagerPrompt /f'
            Notes              = 'PackagerPrompt=2 blocks OLE object activation.'
            RemoveRecommended  = $false
            RemoveReason       = 'OLE blocking in Office documents is a meaningful ransomware mitigation. Leave in place.'
        },

        # ----------------------------------------------------------------------
        # POLICY 37 - Disable Local LM Hash Storage
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 37
            Name        = 'Disable Local LM Hash Storage'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
            RegValue    = 'NoLMHash'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /37'
            ManualFix          = 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v NoLMHash /t REG_DWORD /d 0 /f'
            Notes              = 'NoLMHash=1 prevents storing LM hashes. Generally safe to leave.'
            RemoveRecommended  = $false
            RemoveReason       = 'Preventing LM hash storage is a security baseline. Leave in place.'
        },

        # ----------------------------------------------------------------------
        # POLICY 38 - Audit All NTLM Traffic
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 38
            Name        = 'Audit All NTLM Traffic'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'
            RegValue    = 'AuditReceivingNTLMTraffic'
            Expected    = 2
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /38'
            ManualFix          = 'reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" /v AuditReceivingNTLMTraffic /f'
            Notes              = ''
            RemoveRecommended  = $false
            RemoveReason       = 'NTLM auditing is a useful security diagnostic. Leave unless it is causing log noise issues.'
        },

        # ----------------------------------------------------------------------
        # POLICY 39 - Disable LM / NTLMv1
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 39
            Name        = 'Disable LM NTLMv1'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
            RegValue    = 'LmCompatibilityLevel'
            Expected    = 5
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /39'
            ManualFix          = 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LmCompatibilityLevel /t REG_DWORD /d 3 /f'
            Notes              = 'LmCompatibilityLevel=5 = NTLMv2 only. Generally safe to leave enabled.'
            RemoveRecommended  = $false
            RemoveReason       = 'Requiring NTLMv2 is a security baseline. Leave in place.'
        },

        # ----------------------------------------------------------------------
        # POLICY 40 - Disable NetBios
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 40
            Name        = 'Disable NetBios'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters'
            RegValue    = 'NodeType'
            Expected    = 2
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /40'
            ManualFix          = 'reg delete "HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters" /v NodeType /f'
            Notes              = 'NodeType=2 sets P-node (no NetBIOS broadcasts).'
            RemoveRecommended  = $false
            RemoveReason       = 'Disabling NetBIOS broadcasts reduces attack surface. Leave unless a legacy application requires it.'
        },

        # ----------------------------------------------------------------------
        # POLICY 41 - Disable IPv6
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 41
            Name        = 'Disable IPv6'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
            RegValue    = 'DisabledComponents'
            Expected    = 255
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /41'
            ManualFix          = 'reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" /v DisabledComponents /f'
            Notes              = 'DisabledComponents=255 disables all IPv6. Can break AAD join and WindowsApps. Caution.'
            RemoveRecommended  = $false
            RemoveReason       = 'IPv6 disable can break AAD join, Windows Store apps, and modern Windows features. Verify customer environment before removing.'
        },

        # ----------------------------------------------------------------------
        # POLICY 43 - Disable SMB v1
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 43
            Name        = 'Disable SMB v1'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
            RegValue    = 'SMB1'
            Expected    = 0
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /43'
            ManualFix          = 'reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v SMB1 /t REG_DWORD /d 1 /f'
            Notes              = 'SMB1=0 disables SMBv1. Generally safe and recommended to leave disabled.'
            RemoveRecommended  = $false
            RemoveReason       = 'SMBv1 should remain disabled. It is a known ransomware vector (WannaCry, NotPetya).'
        },

        # ----------------------------------------------------------------------
        # POLICY 51 - Disable Guest Account
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 51
            Name        = 'Disable Guest Account'
            CheckType   = 'SPECIAL_GUEST_DISABLED'
            RegPath     = ''
            RegValue    = ''
            Expected    = ''
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /51'
            ManualFix          = 'net user Guest /active:yes'
            Notes              = 'Checks if built-in Guest account is disabled. Generally safe to leave disabled.'
            RemoveRecommended  = $false
            RemoveReason       = 'Guest account should remain disabled. Re-enabling it is a security risk.'
        },

        # ----------------------------------------------------------------------
        # POLICY 53 - Enable USB Wall
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 53
            Name        = 'Enable USB Wall'
            CheckType   = 'SERVICE_START'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR'
            RegValue    = 'Start'
            Expected    = 4
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /53'
            ManualFix          = 'reg add "HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR" /v Start /t REG_DWORD /d 3 /f'
            Notes              = 'USBSTOR Start=4 disables the USB mass storage driver entirely.'
            RemoveRecommended  = $true
            RemoveReason       = 'USB Wall is a ThirdWall-specific feature. Remove to restore USB storage access post-offboarding.'
        },

        # ----------------------------------------------------------------------
        # POLICY 54 - Disable Terminal Server Services
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 54
            Name        = 'Disable Terminal Server Services'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
            RegValue    = 'fDenyTSConnections'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /54'
            ManualFix          = 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f'
            Notes              = 'fDenyTSConnections=1 disables RDP.'
            RemoveRecommended  = $true
            RemoveReason       = 'RDP may be needed for remote management post-offboarding. Remove if remote access is required.'
        },

        # ----------------------------------------------------------------------
        # POLICY 57 - Clear Windows Pagefile on Reboot
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 57
            Name        = 'Clear Windows Pagefile on Reboot'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
            RegValue    = 'ClearPageFileAtShutdown'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /57'
            ManualFix          = 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v ClearPageFileAtShutdown /t REG_DWORD /d 0 /f'
            Notes              = ''
            RemoveRecommended  = $true
            RemoveReason       = 'Pagefile clearing extends shutdown time significantly. Remove to restore normal shutdown behavior.'
        },

        # ----------------------------------------------------------------------
        # POLICY 58 - Enable Registry Backup
        # ----------------------------------------------------------------------
        [PSCustomObject]@{
            Id          = 58
            Name        = 'Enable Registry Backup'
            CheckType   = 'HKLM_VALUE'
            RegPath     = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'
            RegValue    = 'EnablePeriodicBackup'
            Expected    = 1
            UserScoped  = $false
            TWUndoCmd          = 'TWUndo.exe /58'
            ManualFix          = 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager" /v EnablePeriodicBackup /t REG_DWORD /d 0 /f'
            Notes              = ''
            RemoveRecommended  = $false
            RemoveReason       = 'Registry backup is harmless and useful for recovery. Leave in place.'
        }
    )

    # ==========================================================================
    # HELPER: Resolve SID to username
    # ==========================================================================
    function Resolve-SidToUsername {
        param ([Parameter(Mandatory = $true)][string]$Sid)
        try {
            $SidObj   = New-Object -TypeName System.Security.Principal.SecurityIdentifier -ArgumentList $Sid
            $NTAccount = $SidObj.Translate([System.Security.Principal.NTAccount])
            return $NTAccount.Value
        }
        catch {
            return $Sid
        }
    }

    # ==========================================================================
    # HELPER: Check a single policy against a registry path
    # Returns [PSCustomObject] with IsActive, Evidence
    # ==========================================================================
    function Test-PolicyRegistry {
        param (
            [Parameter(Mandatory = $true)]
            [PSCustomObject]$Policy,

            [Parameter(Mandatory = $false)]
            [string]$HivePath = ''  # For HKCU checks, pass the mapped HKU path
        )

        $IsActive = $false
        $Evidence = 'Not detected'

        try {
            $RegPath = if ($HivePath -ne '') { $HivePath } else { $Policy.RegPath }

            switch ($Policy.CheckType) {

                'HKLM_KEY_EXISTS' {
                    if (Test-Path -Path $RegPath) {
                        $IsActive = $true
                        $Evidence = "Registry key present: $RegPath"
                    }
                }

                'HKLM_VALUE' {
                    if (Test-Path -Path $RegPath) {
                        $Props = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
                        if ($null -ne $Props -and $null -ne $Props.($Policy.RegValue)) {
                            $ActualValue = $Props.($Policy.RegValue)
                            if ($ActualValue -eq $Policy.Expected) {
                                $IsActive = $true
                                $Evidence = "[$RegPath] $($Policy.RegValue) = $ActualValue (expected $($Policy.Expected))"
                            }
                            else {
                                $Evidence = "[$RegPath] $($Policy.RegValue) = $ActualValue (expected $($Policy.Expected) — value present but differs)"
                            }
                        }
                    }
                }

                'HKLM_VALUE_EXISTS' {
                    if (Test-Path -Path $RegPath) {
                        $Props = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
                        if ($null -ne $Props -and $null -ne $Props.($Policy.RegValue)) {
                            $ActualValue = $Props.($Policy.RegValue)
                            if (-not [string]::IsNullOrWhiteSpace([string]$ActualValue)) {
                                $IsActive = $true
                                $Evidence = "[$RegPath] $($Policy.RegValue) exists: '$ActualValue'"
                            }
                        }
                    }
                }

                'SERVICE_START' {
                    if (Test-Path -Path $RegPath) {
                        $Props = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
                        if ($null -ne $Props -and $null -ne $Props.($Policy.RegValue)) {
                            $ActualValue = $Props.($Policy.RegValue)
                            if ($ActualValue -eq $Policy.Expected) {
                                $IsActive = $true
                                $Evidence = "[$RegPath] $($Policy.RegValue) = $ActualValue (service disabled)"
                            }
                            else {
                                $Evidence = "[$RegPath] $($Policy.RegValue) = $ActualValue (service running normally)"
                            }
                        }
                    }
                }

                'HKCU_VALUE' {
                    if (Test-Path -Path $RegPath) {
                        $Props = Get-ItemProperty -Path $RegPath -ErrorAction SilentlyContinue
                        if ($null -ne $Props -and $null -ne $Props.($Policy.RegValue)) {
                            $ActualValue = [string]$Props.($Policy.RegValue)
                            if ($ActualValue -eq [string]$Policy.Expected) {
                                $IsActive = $true
                                $Evidence = "[$RegPath] $($Policy.RegValue) = $ActualValue"
                            }
                        }
                    }
                }

                'HKCU_KEY_EXISTS' {
                    if (Test-Path -Path $RegPath) {
                        $IsActive = $true
                        $Evidence = "Registry key present: $RegPath"
                    }
                }
            }
        }
        catch {
            $Evidence = "CHECK ERROR: $_"
        }

        return [PSCustomObject]@{
            IsActive = $IsActive
            Evidence = $Evidence
        }
    }

    # ==========================================================================
    # HELPER: Emit a formatted policy finding to log and console
    # ==========================================================================
    function Write-PolicyFinding {
        param (
            [Parameter(Mandatory = $true)]
            [PSCustomObject]$Policy,

            [Parameter(Mandatory = $true)]
            [bool]$IsActive,

            [Parameter(Mandatory = $true)]
            [string]$Evidence,

            [Parameter(Mandatory = $false)]
            [string]$UserContext = ''
        )

        $UserLabel   = if ($UserContext -ne '') { " [User: $UserContext]" } else { '' }
        $Recommended = if ($null -ne $Policy.RemoveRecommended) { $Policy.RemoveRecommended } else { $false }
        $Reason      = if ($null -ne $Policy.RemoveReason -and $Policy.RemoveReason -ne '') { $Policy.RemoveReason } else { '' }

        if ($IsActive) {
            $RemoveLabel = if ($Recommended) { 'REMOVE RECOMMENDED' } else { 'LEAVE IN PLACE' }

            Write-Log  "  [ACTIVE]       Policy $($Policy.Id): $($Policy.Name)$UserLabel"    -Severity WARN
            Write-Log  "                 Evidence      : $Evidence"                           -Severity WARN
            Write-Log  "                 Recommendation: $RemoveLabel"                        -Severity WARN
            if ($Reason -ne '') {
                Write-Log "                 Reason        : $Reason"                          -Severity WARN
            }
            Write-Log  "                 TWUndo Cmd    : $($Policy.TWUndoCmd)"                -Severity WARN
            Write-Log  "                 Manual Fix    : $($Policy.ManualFix)"                -Severity WARN
            if ($Policy.Notes -ne '') {
                Write-Log "                 Notes         : $($Policy.Notes)"                 -Severity WARN
            }
            Write-Console "  [ACTIVE] Policy $($Policy.Id): $($Policy.Name)$UserLabel"       -Severity WARN
            Write-Console "           Evidence      : $Evidence"                              -Severity PLAIN -Indent 3
            Write-Console "           Recommendation: $RemoveLabel"                           -Severity $(if ($Recommended) { 'WARN' } else { 'INFO' }) -Indent 3
            if ($Reason -ne '') {
                Write-Console "           Reason        : $Reason"                            -Severity PLAIN -Indent 3
            }
            Write-Console "           TWUndo Cmd    : $($Policy.TWUndoCmd)"                   -Severity PLAIN -Indent 3
            Write-Console "           Manual Fix    : $($Policy.ManualFix)"                   -Severity PLAIN -Indent 3

            $FindingRecord = [PSCustomObject]@{
                Id          = $Policy.Id
                Name        = $Policy.Name
                UserContext = $UserContext
                Recommended = $Recommended
                Reason      = $Reason
                TWUndoCmd   = $Policy.TWUndoCmd
            }
            $ActiveFindings.Add($FindingRecord)
            if ($Recommended) {
                $RemoveList.Add($FindingRecord)
            } else {
                $LeaveList.Add($FindingRecord)
            }
        }
        else {
            Write-Log  "  [NOT DETECTED] Policy $($Policy.Id): $($Policy.Name)$UserLabel" -Severity INFO
            Write-Log  "                 Evidence   : $Evidence"                           -Severity DEBUG
            Write-Console "  [NOT DETECTED] Policy $($Policy.Id): $($Policy.Name)$UserLabel" -Severity INFO
        }
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log "===== $ScriptName $ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName"                   -Severity INFO
    Write-Log "Hostname : $Hostname"                   -Severity INFO
    Write-Log "Run As   : $RunAs"                      -Severity INFO
    Write-Log "Log File : $LogFile"                    -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) $ScriptVersion"
    Write-Console "Site     : $SiteName"  -Severity PLAIN
    Write-Console "Hostname : $Hostname"  -Severity PLAIN
    Write-Console "Run As   : $RunAs"     -Severity PLAIN
    Write-Console "Log File : $LogFile"   -Severity PLAIN
    Write-Separator

    $ActiveCount         = 0
    $NotDetectedCount    = 0
    $ErrorCount          = 0
    $ScriptExitCode      = 0

    # Tracking lists for final summary
    $ActiveFindings    = New-Object -TypeName 'System.Collections.Generic.List[PSObject]'
    $RemoveList        = New-Object -TypeName 'System.Collections.Generic.List[PSObject]'
    $LeaveList         = New-Object -TypeName 'System.Collections.Generic.List[PSObject]'

    try {

        # ------------------------------------------------------------------
        # ENUMERATE LOADED USER HIVES
        # ------------------------------------------------------------------
        Write-Section 'User Hive Enumeration'
        Write-Log "Enumerating loaded user hives under HKU..." -Severity INFO
        Write-Console "Enumerating loaded user hives under HKU..." -Severity INFO

        $LoadedHives = New-Object -TypeName 'System.Collections.Generic.List[PSObject]'
        $SkippedSIDs = @(
            'S-1-5-18',   # SYSTEM
            'S-1-5-19',   # LOCAL SERVICE
            'S-1-5-20'    # NETWORK SERVICE
        )
        # Also skip .DEFAULT (system default profile, not a real user)
        $SkipPatterns = @('.DEFAULT')

        try {
            $HKUSubKeys = Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction Stop |
                Where-Object { $_.PSChildName -notmatch '_Classes$' }

            foreach ($Hive in $HKUSubKeys) {
                $Sid = $Hive.PSChildName

                # Skip well-known system SIDs and non-user profiles
                $IsSystem = $false
                foreach ($Skip in $SkippedSIDs) {
                    if ($Sid -eq $Skip) { $IsSystem = $true; break }
                }
                foreach ($Pattern in $SkipPatterns) {
                    if ($Sid -eq $Pattern) { $IsSystem = $true; break }
                }
                if ($IsSystem) { continue }

                $Username = Resolve-SidToUsername -Sid $Sid
                $HivePath = "Registry::HKEY_USERS\$Sid"

                $LoadedHives.Add([PSCustomObject]@{
                    Sid      = $Sid
                    Username = $Username
                    HivePath = $HivePath
                })

                Write-Log "  Found user hive: $Sid ($Username)" -Severity INFO
                Write-Console "  Found user hive: $Sid ($Username)" -Severity INFO
            }
        }
        catch {
            Write-Log "Error enumerating HKU hives: $_" -Severity WARN
            Write-Console "Error enumerating HKU hives: $_" -Severity WARN
            $ErrorCount++
        }

        if ($LoadedHives.Count -eq 0) {
            Write-Log "No user hives found. User-scoped policies cannot be assessed." -Severity WARN
            Write-Console "No user hives found. User-scoped policies cannot be assessed." -Severity WARN
        }
        else {
            Write-Log "$($LoadedHives.Count) user hive(s) will be assessed for user-scoped policies." -Severity INFO
            Write-Console "$($LoadedHives.Count) user hive(s) will be assessed for user-scoped policies." -Severity INFO
        }

        # ------------------------------------------------------------------
        # MACHINE-LEVEL POLICY ASSESSMENT (HKLM)
        # ------------------------------------------------------------------
        Write-Section 'Machine Policy Assessment (HKLM)'
        Write-Log "Assessing machine-level ThirdWall policies..." -Severity INFO
        Write-Console "Assessing machine-level ThirdWall policies..." -Severity INFO

        $MachinePolicies = $PolicyDefinitions | Where-Object { -not $_.UserScoped }

        foreach ($Policy in $MachinePolicies) {

            try {
                $Result = $null

                switch ($Policy.CheckType) {

                    'SPECIAL_ADMIN_RENAME' {
                        $AdminUser = Get-LocalUser | Where-Object {
                            $_.SID.Value -match '-500$'
                        } | Select-Object -First 1
                        if ($null -ne $AdminUser -and $AdminUser.Name -ne 'Administrator') {
                            $Result = [PSCustomObject]@{
                                IsActive = $true
                                Evidence = "Built-in Administrator account renamed to: '$($AdminUser.Name)'"
                            }
                        }
                        else {
                            $Result = [PSCustomObject]@{
                                IsActive = $false
                                Evidence = "Built-in Administrator account name is 'Administrator' (default)"
                            }
                        }
                    }

                    'SPECIAL_ADMIN_DISABLED' {
                        $AdminUser = Get-LocalUser | Where-Object {
                            $_.SID.Value -match '-500$'
                        } | Select-Object -First 1
                        if ($null -ne $AdminUser -and -not $AdminUser.Enabled) {
                            $Result = [PSCustomObject]@{
                                IsActive = $true
                                Evidence = "Built-in Administrator account (RID 500) is disabled."
                            }
                        }
                        else {
                            $Result = [PSCustomObject]@{
                                IsActive = $false
                                Evidence = "Built-in Administrator account is enabled."
                            }
                        }
                    }

                    'SPECIAL_GUEST_DISABLED' {
                        $GuestUser = Get-LocalUser | Where-Object {
                            $_.SID.Value -match '-501$'
                        } | Select-Object -First 1
                        if ($null -ne $GuestUser -and -not $GuestUser.Enabled) {
                            $Result = [PSCustomObject]@{
                                IsActive = $true
                                Evidence = "Built-in Guest account (RID 501) is disabled."
                            }
                        }
                        else {
                            $Result = [PSCustomObject]@{
                                IsActive = $false
                                Evidence = "Built-in Guest account is enabled."
                            }
                        }
                    }

                    'SPECIAL_SECPOL' {
                        # Cannot reliably detect via registry; flag for manual check
                        $Result = [PSCustomObject]@{
                            IsActive = $false
                            Evidence = "Cannot assess via registry. Run: secedit /export /cfg C:\temp\secpol.cfg and inspect PasswordComplexity value."
                        }
                    }

                    default {
                        $Result = Test-PolicyRegistry -Policy $Policy
                    }
                }

                Write-PolicyFinding -Policy $Policy -IsActive $Result.IsActive -Evidence $Result.Evidence

                if ($Result.IsActive) { $ActiveCount++ } else { $NotDetectedCount++ }
            }
            catch {
                Write-Log "  [ERROR] Policy $($Policy.Id): $($Policy.Name) — check failed: $_" -Severity ERROR
                Write-Console "  [ERROR] Policy $($Policy.Id): $($Policy.Name) — check failed: $_" -Severity ERROR
                $ErrorCount++
                $ScriptExitCode = 1
            }
        }

        # ------------------------------------------------------------------
        # ADDITIONAL MACHINE-LEVEL CHECKS
        # Items not tied to a single policy ID but relevant to ThirdWall footprint
        # ------------------------------------------------------------------
        Write-Section 'Additional Machine Checks'

        # USBSTOR driver state
        Write-Log "Checking USBSTOR driver start value..." -Severity INFO
        try {
            $UsbStorStart = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR' -Name Start -ErrorAction Stop).Start
            if ($UsbStorStart -eq 4) {
                Write-Log "  [ACTIVE]       USBSTOR driver: Start=4 (disabled) — USB mass storage blocked" -Severity WARN
                Write-Log "                 Manual Fix: reg add `"HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR`" /v Start /t REG_DWORD /d 3 /f" -Severity WARN
                Write-Console "  [ACTIVE]       USBSTOR driver: Start=4 (disabled)" -Severity WARN
                $ActiveCount++
            }
            else {
                Write-Log "  [NOT DETECTED] USBSTOR driver: Start=$UsbStorStart (normal)" -Severity INFO
                Write-Console "  [NOT DETECTED] USBSTOR driver: Start=$UsbStorStart (normal)" -Severity INFO
                $NotDetectedCount++
            }
        }
        catch {
            Write-Log "  [ERROR] Could not read USBSTOR Start value: $_" -Severity WARN
            $ErrorCount++
        }

        # CD-ROM driver state
        Write-Log "Checking cdrom driver start value..." -Severity INFO
        try {
            $CdRomStart = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\cdrom' -Name Start -ErrorAction Stop).Start
            if ($CdRomStart -eq 4) {
                Write-Log "  [ACTIVE]       cdrom driver: Start=4 (disabled) — optical drive access blocked" -Severity WARN
                Write-Log "                 Manual Fix: reg add `"HKLM\SYSTEM\CurrentControlSet\Services\cdrom`" /v Start /t REG_DWORD /d 1 /f" -Severity WARN
                Write-Console "  [ACTIVE]       cdrom driver: Start=4 (disabled)" -Severity WARN
                $ActiveCount++
            }
            else {
                Write-Log "  [NOT DETECTED] cdrom driver: Start=$CdRomStart (normal)" -Severity INFO
                Write-Console "  [NOT DETECTED] cdrom driver: Start=$CdRomStart (normal)" -Severity INFO
                $NotDetectedCount++
            }
        }
        catch {
            Write-Log "  [ERROR] Could not read cdrom Start value: $_" -Severity WARN
            $ErrorCount++
        }

        # Filter drivers — USB class
        Write-Log "Checking USB device class filter drivers..." -Severity INFO
        try {
            $UsbClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{36FC9E60-C465-11CF-8056-444553540000}'
            $UsbFilters = Get-ItemProperty -Path $UsbClass -ErrorAction SilentlyContinue
            $UsbUpper = if ($null -ne $UsbFilters) { $UsbFilters.UpperFilters } else { $null }
            $UsbLower = if ($null -ne $UsbFilters) { $UsbFilters.LowerFilters } else { $null }
            if ($UsbUpper -or $UsbLower) {
                Write-Log "  [ACTIVE]       USB class filter drivers present — UpperFilters: $UsbUpper | LowerFilters: $UsbLower" -Severity WARN
                Write-Log "                 Manual Fix: Remove ThirdWall entries from UpperFilters/LowerFilters at $UsbClass" -Severity WARN
                Write-Console "  [ACTIVE]       USB class filter drivers present" -Severity WARN
                Write-Console "                 Upper: $UsbUpper | Lower: $UsbLower" -Severity PLAIN -Indent 3
                $ActiveCount++
            }
            else {
                Write-Log "  [NOT DETECTED] USB class: no filter drivers" -Severity INFO
                Write-Console "  [NOT DETECTED] USB class: no filter drivers" -Severity INFO
                $NotDetectedCount++
            }
        }
        catch {
            Write-Log "  [ERROR] Could not check USB class filter drivers: $_" -Severity WARN
            $ErrorCount++
        }

        # Filter drivers — CD-ROM class
        Write-Log "Checking CD-ROM device class filter drivers..." -Severity INFO
        try {
            $CdClass = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E965-E325-11CE-BFC1-08002BE10318}'
            $CdFilters = Get-ItemProperty -Path $CdClass -ErrorAction SilentlyContinue
            $CdUpper = if ($null -ne $CdFilters) { $CdFilters.UpperFilters } else { $null }
            $CdLower = if ($null -ne $CdFilters) { $CdFilters.LowerFilters } else { $null }
            if ($CdUpper -or $CdLower) {
                Write-Log "  [ACTIVE]       CD-ROM class filter drivers present — UpperFilters: $CdUpper | LowerFilters: $CdLower" -Severity WARN
                Write-Log "                 Manual Fix: Remove ThirdWall entries from UpperFilters/LowerFilters at $CdClass" -Severity WARN
                Write-Console "  [ACTIVE]       CD-ROM class filter drivers present" -Severity WARN
                Write-Console "                 Upper: $CdUpper | Lower: $CdLower" -Severity PLAIN -Indent 3
                $ActiveCount++
            }
            else {
                Write-Log "  [NOT DETECTED] CD-ROM class: no filter drivers" -Severity INFO
                Write-Console "  [NOT DETECTED] CD-ROM class: no filter drivers" -Severity INFO
                $NotDetectedCount++
            }
        }
        catch {
            Write-Log "  [ERROR] Could not check CD-ROM class filter drivers: $_" -Severity WARN
            $ErrorCount++
        }

        # Hosts file check for webmail/social blocking (policies 28, 29)
        Write-Log "Checking hosts file for ThirdWall domain blocks..." -Severity INFO
        try {
            $HostsPath = Join-Path $env:windir 'System32\drivers\etc\hosts'
            $HostsContent = Get-Content -Path $HostsPath -ErrorAction SilentlyContinue
            $BlockedDomains = $HostsContent | Where-Object {
                $_ -match '^\s*0\.0\.0\.0|^\s*127\.0\.0\.1' -and
                $_ -notmatch 'localhost' -and
                $_ -match '\S'
            }
            if ($BlockedDomains -and $BlockedDomains.Count -gt 0) {
                Write-Log "  [ACTIVE]       Hosts file contains $($BlockedDomains.Count) blocking entries (policies 28/29 possible)" -Severity WARN
                foreach ($Entry in $BlockedDomains) {
                    Write-Log "                 $($Entry.Trim())" -Severity WARN
                }
                Write-Log "                 Manual Fix: Edit $HostsPath and remove ThirdWall block entries" -Severity WARN
                Write-Console "  [ACTIVE]       Hosts file blocking entries detected ($($BlockedDomains.Count) entries)" -Severity WARN
                $ActiveCount++
            }
            else {
                Write-Log "  [NOT DETECTED] Hosts file: no suspicious blocking entries" -Severity INFO
                Write-Console "  [NOT DETECTED] Hosts file: no suspicious blocking entries" -Severity INFO
                $NotDetectedCount++
            }
        }
        catch {
            Write-Log "  [ERROR] Could not read hosts file: $_" -Severity WARN
            $ErrorCount++
        }

        # ------------------------------------------------------------------
        # USER-CONTEXT POLICY ASSESSMENT (HKCU via HKU)
        # ------------------------------------------------------------------
        Write-Section 'User Policy Assessment (HKCU)'

        $UserScopedPolicies = $PolicyDefinitions | Where-Object { $_.UserScoped }

        if ($LoadedHives.Count -eq 0) {
            Write-Log "No user hives loaded — skipping user policy assessment." -Severity WARN
            Write-Console "No user hives loaded — skipping user policy assessment." -Severity WARN
        }
        else {
            foreach ($Hive in $LoadedHives) {
                Write-Log "Assessing user policies for: $($Hive.Username) ($($Hive.Sid))" -Severity INFO
                Write-Console "Assessing user: $($Hive.Username) ($($Hive.Sid))" -Severity INFO

                foreach ($Policy in $UserScopedPolicies) {
                    try {
                        # Build the HKU path by replacing HKCU: with the loaded hive path
                        $HkuPath = "$($Hive.HivePath)\$($Policy.RegPath)"

                        $CheckPolicy = [PSCustomObject]@{
                            Id        = $Policy.Id
                            Name      = $Policy.Name
                            CheckType = $Policy.CheckType
                            RegPath   = $HkuPath
                            RegValue  = $Policy.RegValue
                            Expected  = $Policy.Expected
                            TWUndoCmd = $Policy.TWUndoCmd
                            ManualFix = $Policy.ManualFix
                            Notes     = $Policy.Notes
                        }

                        $Result = Test-PolicyRegistry -Policy $CheckPolicy -HivePath $HkuPath

                        Write-PolicyFinding -Policy $Policy -IsActive $Result.IsActive -Evidence $Result.Evidence -UserContext "$($Hive.Username) ($($Hive.Sid))"

                        if ($Result.IsActive) { $ActiveCount++ } else { $NotDetectedCount++ }
                    }
                    catch {
                        Write-Log "  [ERROR] Policy $($Policy.Id) for user $($Hive.Username): $_" -Severity ERROR
                        $ErrorCount++
                        $ScriptExitCode = 1
                    }
                }
            }
        }

        # ------------------------------------------------------------------
        # SUMMARY
        # ------------------------------------------------------------------
        Write-Section 'Assessment Summary'

        Write-Log '============================================================' -Severity INFO
        Write-Log 'THIRDWALL POLICY ASSESSMENT — FINAL REPORT'                   -Severity INFO
        Write-Log '============================================================' -Severity INFO
        Write-Log ''                                                              -Severity INFO
        Write-Log "Site     : $SiteName"   -Severity INFO
        Write-Log "Hostname : $Hostname"   -Severity INFO
        Write-Log "Run As   : $RunAs"      -Severity INFO
        Write-Log ''                        -Severity INFO

        # --- Counts ---
        Write-Log "Total policies assessed  : $($ActiveCount + $NotDetectedCount)" -Severity INFO
        Write-Log "Active (ACTIVE)          : $ActiveCount"                        -Severity INFO
        Write-Log "Not detected             : $NotDetectedCount"                   -Severity INFO
        Write-Log "Check errors             : $ErrorCount"                         -Severity INFO
        Write-Log "User hives assessed      : $($LoadedHives.Count)"               -Severity INFO
        foreach ($Hive in $LoadedHives) {
            Write-Log "  - $($Hive.Username) ($($Hive.Sid))" -Severity INFO
        }
        Write-Log '' -Severity INFO

        # --- All Active Findings ---
        Write-Log '------------------------------------------------------------' -Severity INFO
        Write-Log 'ALL ACTIVE POLICY FINDINGS'                                   -Severity INFO
        Write-Log '------------------------------------------------------------' -Severity INFO
        if ($ActiveFindings.Count -eq 0) {
            Write-Log '  None — no active ThirdWall policy enforcement detected.' -Severity SUCCESS
        }
        else {
            foreach ($F in $ActiveFindings) {
                $ULabel = if ($F.UserContext -ne '') { " [User: $($F.UserContext)]" } else { '' }
                $RLabel = if ($F.Recommended) { ' — REMOVE RECOMMENDED' } else { ' — LEAVE IN PLACE' }
                Write-Log "  Policy $($F.Id): $($F.Name)$ULabel$RLabel" -Severity WARN
            }
            $AllActiveIds = ($ActiveFindings | Sort-Object Id | ForEach-Object { $_.Id }) -join ', '
            Write-Log '' -Severity INFO
            Write-Log "  Policy IDs (all active): $AllActiveIds" -Severity INFO
        }
        Write-Log '' -Severity INFO

        # --- Remove Recommended ---
        Write-Log '------------------------------------------------------------' -Severity WARN
        Write-Log 'POLICIES RECOMMENDED FOR REMOVAL'                             -Severity WARN
        Write-Log '------------------------------------------------------------' -Severity WARN
        if ($RemoveList.Count -eq 0) {
            Write-Log '  None.' -Severity INFO
        }
        else {
            foreach ($F in $RemoveList) {
                $ULabel = if ($F.UserContext -ne '') { " [User: $($F.UserContext)]" } else { '' }
                Write-Log "  Policy $($F.Id): $($F.Name)$ULabel" -Severity WARN
                Write-Log "    Reason    : $($F.Reason)"         -Severity WARN
                Write-Log "    TWUndo Cmd: $($F.TWUndoCmd)"      -Severity WARN
            }
            $RemoveIds = ($RemoveList | Sort-Object Id | ForEach-Object { $_.Id }) -join ','
            Write-Log '' -Severity INFO
            Write-Log "  TWUndo Policy ID string (copy/paste into Invoke-ThirdWallUndo PolicyIds): $RemoveIds" -Severity WARN
        }
        Write-Log '' -Severity INFO

        # --- Leave In Place ---
        Write-Log '------------------------------------------------------------' -Severity INFO
        Write-Log 'ACTIVE POLICIES — LEAVE IN PLACE'                             -Severity INFO
        Write-Log '------------------------------------------------------------' -Severity INFO
        if ($LeaveList.Count -eq 0) {
            Write-Log '  None.' -Severity INFO
        }
        else {
            foreach ($F in $LeaveList) {
                $ULabel = if ($F.UserContext -ne '') { " [User: $($F.UserContext)]" } else { '' }
                Write-Log "  Policy $($F.Id): $($F.Name)$ULabel" -Severity INFO
                Write-Log "    Reason: $($F.Reason)"             -Severity INFO
            }
            $LeaveIds = ($LeaveList | Sort-Object Id | ForEach-Object { $_.Id }) -join ', '
            Write-Log '' -Severity INFO
            Write-Log "  Policy IDs (leave in place): $LeaveIds" -Severity INFO
        }
        Write-Log '' -Severity INFO
        Write-Log '============================================================' -Severity INFO

        Write-Console ''
        Write-Console '============================================================' -Severity PLAIN
        Write-Console 'THIRDWALL POLICY ASSESSMENT — FINAL REPORT'                  -Severity INFO
        Write-Console '============================================================' -Severity PLAIN
        Write-Console '' -Severity PLAIN
        Write-Console "Policies Active       : $ActiveCount"      -Severity $(if ($ActiveCount -gt 0) { 'WARN' } else { 'SUCCESS' })
        Write-Console "Policies Not Detected : $NotDetectedCount" -Severity INFO
        Write-Console "Check Errors          : $ErrorCount"       -Severity $(if ($ErrorCount -gt 0) { 'WARN' } else { 'INFO' })
        Write-Console "User Hives Assessed   : $($LoadedHives.Count)" -Severity INFO
        Write-Console '' -Severity PLAIN

        if ($ActiveFindings.Count -gt 0) {
            Write-Console '--- ALL ACTIVE FINDINGS ---' -Severity WARN
            foreach ($F in $ActiveFindings) {
                $ULabel = if ($F.UserContext -ne '') { " [User: $($F.UserContext)]" } else { '' }
                $RLabel = if ($F.Recommended) { 'REMOVE' } else { 'LEAVE' }
                Write-Console "  [$RLabel] Policy $($F.Id): $($F.Name)$ULabel" -Severity $(if ($F.Recommended) { 'WARN' } else { 'INFO' })
            }
            Write-Console '' -Severity PLAIN
        }

        if ($RemoveList.Count -gt 0) {
            $RemoveIds = ($RemoveList | Sort-Object Id | ForEach-Object { $_.Id }) -join ','
            Write-Console '--- RECOMMENDED FOR REMOVAL ---' -Severity WARN
            foreach ($F in $RemoveList) {
                Write-Console "  Policy $($F.Id): $($F.Name)" -Severity WARN
            }
            Write-Console '' -Severity PLAIN
            Write-Console "  PolicyIds string: $RemoveIds" -Severity WARN
            Write-Console '' -Severity PLAIN
        }

        if ($LeaveList.Count -gt 0) {
            Write-Console '--- LEAVE IN PLACE ---' -Severity INFO
            foreach ($F in $LeaveList) {
                Write-Console "  Policy $($F.Id): $($F.Name)" -Severity INFO
            }
            Write-Console '' -Severity PLAIN
        }

        if ($ActiveCount -gt 0) {
            Write-Banner 'ASSESSMENT COMPLETE — ACTIVE POLICIES FOUND' -Color 'Yellow'
        }
        else {
            Write-Banner 'ASSESSMENT COMPLETE — CLEAN' -Color 'Green'
        }

        exit $ScriptExitCode

    }
    catch {
        Write-Log "Unhandled exception: $_"             -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Console "Unhandled exception: $_"         -Severity ERROR
        Write-Banner "SCRIPT FAILED" -Color "Red"
        exit 1
    }

} # End function Get-ThirdWallPolicyAssessment

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    SiteName = $SiteName
    Hostname = $Hostname
}

Get-ThirdWallPolicyAssessment @ScriptParams
