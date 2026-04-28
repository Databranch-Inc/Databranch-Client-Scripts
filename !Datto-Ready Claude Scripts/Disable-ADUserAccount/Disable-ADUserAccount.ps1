#Requires -Version 5.1
<#
.SYNOPSIS
    Disables an Active Directory user account and performs full offboarding actions.

.DESCRIPTION
    Modernized AD user offboarding script. Performs a full, auditable disable
    sequence against a single user account: pre-state capture, disable,
    password scramble, optional GAL hide, OU move, group cleanup, direct
    report reassignment, account expiration, and tombstone description.

    REPORT-ONLY MODE IS ON BY DEFAULT. The script captures pre-state and
    evaluates every planned action but will not write anything to AD unless
    ReportOnly is explicitly set to the literal string 'false'. Any other
    value — including the default, a typo, or unexpected casing — stays
    safely in report-only mode. This is an all-or-nothing dry run: if
    ReportOnly is on, no changes are made anywhere.

    Mailbox conversion, license removal, and forwarding setup are M365
    territory and are intentionally out of scope. Use a companion M365
    offboarding script for those steps. Profile and home drive cleanup
    is also out of scope — see Remove-ADUserProfile.ps1.

.PARAMETER SamAccountName
    REQUIRED. The SamAccountName of the AD user to disable. Single user
    only — bulk operations are intentionally not supported.

.PARAMETER TicketNumber
    REQUIRED. The ticket number associated with this offboarding action.
    Folded into the AD description tombstone for future audit.

.PARAMETER Operator
    REQUIRED. The name of the technician performing the offboarding. This
    is the human accountable for the action and may differ from the user
    context the script runs under (e.g. NT AUTHORITY\SYSTEM in DattoRMM).
    Folded into the AD description tombstone.

.PARAMETER DisabledUsersOU
    Optional. The Distinguished Name of the target OU to move the disabled
    account into. If not provided or if the OU does not exist, the move
    step is skipped with a logged warning and the rest of the script
    continues normally.

    REQUIRED FORMAT — full Distinguished Name string:
        OU=Disabled Users,OU=Company,DC=contoso,DC=local

    Common mistakes that will fail validation:
        Disabled Users                              (not a DN)
        contoso.local/Company/Disabled Users        (canonical, not a DN)
        OU=Disabled Users                           (incomplete, no domain)

.PARAMETER RemoveGroupMemberships
    Optional. Set to 'true' to remove the user from all groups except
    Domain Users. Defaults to 'false'. Removed groups are logged so the
    action can be reversed if needed.

.PARAMETER HideFromGAL
    Optional. Set to 'true' to set msExchHideFromAddressLists = $true
    (hides the account from the Exchange Global Address List). Defaults
    to 'false'. Relevant in hybrid Exchange environments.

.PARAMETER ReassignReportsTo
    Optional. SamAccountName of the user to reassign any direct reports
    to. If the disabled user has direct reports and this parameter is
    not provided, the orphaned reports are logged as a warning (one
    SamAccountName per line) and left as-is for manual handling.

.PARAMETER ScramblePassword
    Optional. Set to 'false' to skip the password scramble step. Defaults
    to 'true' — the password is always scrambled by default. Generates
    a 32-character random complex password, sets it, and never logs it.

.PARAMETER SetAccountExpiration
    Optional. Set to 'false' to skip setting the account expiration date.
    Defaults to 'true' — the account is expired as of today as a
    belt-and-suspenders measure alongside the disable.

.PARAMETER ReportOnly
    Controls whether the script writes to Active Directory. DEFAULTS TO
    REPORT-ONLY. The script writes only if this parameter is the EXPLICIT
    literal string 'false' (case-insensitive, whitespace trimmed). Any
    other value — including the default, a typo, a blank string, or
    unexpected casing — falls safely into report-only mode.

.PARAMETER VerboseOutput
    Set to 'false' to suppress per-item detail lines. Section headers,
    summary totals, and all WARN/ERROR entries always emit regardless of
    this setting. Defaults to 'true'.

.EXAMPLE
    .\Disable-ADUserAccount.ps1 -SamAccountName 'jsmith' -TicketNumber '12345' -Operator 'M.Walters'
    Report-only run. Captures pre-state and shows what would happen. No changes made.

.EXAMPLE
    .\Disable-ADUserAccount.ps1 -SamAccountName 'jsmith' -TicketNumber '12345' -Operator 'M.Walters' -ReportOnly 'false'
    Performs the full default disable: scramble password, set expiration,
    apply tombstone description. No OU move, group removal, GAL hide, or report reassignment.

.EXAMPLE
    .\Disable-ADUserAccount.ps1 -SamAccountName 'jsmith' -TicketNumber '12345' -Operator 'M.Walters' `
        -DisabledUsersOU 'OU=Disabled Users,OU=Company,DC=contoso,DC=local' `
        -RemoveGroupMemberships 'true' -HideFromGAL 'true' `
        -ReassignReportsTo 'msmith' -ReportOnly 'false'
    Full offboarding: disable, scramble, expire, move to Disabled Users OU,
    strip group memberships, hide from GAL, reassign direct reports.

.NOTES
    File Name      : Disable-ADUserAccount.ps1
    Version        : 1.0.0.0
    Author         : Josh Britton
    Contributors   : Sam Kirsch
    Company        : Databranch
    Created        : 2018-10-01
    Last Modified  : 2026-04-28
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+, ActiveDirectory module (RSAT)
    Run Context    : Domain Admin (or delegated user/group management rights)
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : All clients (DisabledUsersOU is per-client)

    Exit Codes:
        0  - Success - all planned actions completed (or report-only run completed)
        1  - Runtime failure - script started, some actions failed during execution
        2  - Fatal pre-flight failure - missing parameters, AD module unavailable,
             cannot reach a domain controller, or target user not found

    Companion Scripts (separate offboarding lifecycle steps):
        Remove-ADUserProfile.ps1     - Profile and home drive cleanup
        Disable-M365User.ps1         - Mailbox conversion, license removal, forwarding (planned)

    Output Design:
        Write-Log        - Structured [timestamp][SEVERITY] output to log file AND
                           DattoRMM stdout. Always verbose. No color.
        Write-Console    - Human-friendly colored console output for manual/interactive
                           runs. Uses Write-Host (display stream only). Suppressed in
                           DattoRMM agent context automatically.
        Write-VerboseLog - Calls both Write-Log and Write-Console, gated by $IsVerbose.
                           Used for per-action detail lines.

.CHANGELOG
    v1.0.0.0 - 2026-04-28 - Sam Kirsch
        - Full rewrite to current Databranch script template (v1.5.0.0).
        - Replaced legacy bulk-from-text-file pattern with single-user
          parameter-driven design (SamAccountName + DattoRMM env var fallback).
        - Added required Operator and TicketNumber parameters (mandatory).
        - Added pre-state capture: enabled status, last logon, OU, group
          memberships, manager, direct reports, description, account
          expiration. Logged before any change for audit/reversal.
        - Added password scramble (default on) using 32-char complex random.
        - Added optional move to Disabled Users OU (DN format, validated).
        - Added optional group membership removal (preserves Domain Users).
        - Added optional GAL hide (msExchHideFromAddressLists).
        - Added optional direct report reassignment with warning-on-orphan
          fallback when no reassignment target is provided.
        - Added belt-and-suspenders account expiration set to today.
        - Added tombstone description: "Disabled YYYY-MM-DD by <Operator>
          (Ticket #<Number>) via DattoRMM".
        - Implemented all-or-nothing ReportOnly mode (asymmetric guard:
          any value other than explicit 'false' stays safely in report-only).
        - Standard dual Write-Log / Write-Console output, structured summary,
          standard exit codes (0/1/2).

    Pre-rewrite history (legacy script: Disable_AD_Accounts.ps1):
        v1.0     - 2018-10-01 - Josh Britton
            - Original 6-line bulk disable from C:\Databranch\Accounts_to_Disable.txt.
              Superseded entirely by this rewrite. Archive original script.
#>

# ==============================================================================
# PARAMETERS
# Supports both DattoRMM environment variable input (automated) and standard
# PowerShell parameter input (manual/interactive). DattoRMM env vars take
# precedence if present; otherwise falls back to passed parameters or defaults.
#
# DATTORMM COMPONENT VARIABLE NAMES expected (configure in component):
#   SamAccountName, TicketNumber, Operator, DisabledUsersOU,
#   RemoveGroupMemberships (bool), HideFromGAL (bool),
#   ReassignReportsTo, ScramblePassword (bool),
#   SetAccountExpiration (bool), ReportOnly (bool), VerboseOutput (bool)
#
# BOOLEAN INPUT VARIABLES — TWO-LAYER GOTCHA:
#   Always use .Trim().ToLower() before comparing. DattoRMM Boolean component
#   variables arrive as STRING "true" or "false", and casing is not
#   guaranteed (may be 'True', 'TRUE', or ' true ').
#
# NOTE: This [CmdletBinding()] and param() MUST appear immediately first in the 
# script after comments. This MUST be the first 'active' element of the script
# otherwise it breaks PowerShell compliance.  Do NOT place the TLS block before 
# this one.
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$SamAccountName = $(if ($env:SamAccountName) { $env:SamAccountName } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$TicketNumber = $(if ($env:TicketNumber) { $env:TicketNumber } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$Operator = $(if ($env:Operator) { $env:Operator } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$DisabledUsersOU = $(if ($env:DisabledUsersOU) { $env:DisabledUsersOU } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$RemoveGroupMemberships = $(if ($env:RemoveGroupMemberships) { $env:RemoveGroupMemberships } else { 'false' }),

    [Parameter(Mandatory = $false)]
    [string]$HideFromGAL = $(if ($env:HideFromGAL) { $env:HideFromGAL } else { 'false' }),

    [Parameter(Mandatory = $false)]
    [string]$ReassignReportsTo = $(if ($env:ReassignReportsTo) { $env:ReassignReportsTo } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$ScramblePassword = $(if ($env:ScramblePassword) { $env:ScramblePassword } else { 'true' }),

    [Parameter(Mandatory = $false)]
    [string]$SetAccountExpiration = $(if ($env:SetAccountExpiration) { $env:SetAccountExpiration } else { 'true' }),

    [Parameter(Mandatory = $false)]
    [string]$ReportOnly = $(if ($env:ReportOnly) { $env:ReportOnly } else { 'true' }),

    [Parameter(Mandatory = $false)]
    [string]$VerboseOutput = $(if ($env:VerboseOutput) { $env:VerboseOutput } else { 'true' }),

    # DattoRMM built-in variables (auto-populated by the agent)
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# Required for any script making HTTPS REST calls. This script does not call
# HTTPS REST APIs directly, but the AD module and Exchange attribute writes can
# trigger schema lookups against domain services. Keeping the line is harmless
# and aligns with the standard template top-of-file order.
#
# POSITION: This block must appear AFTER [CmdletBinding()] and param(). The TLS 
# line is an executable statement — it must never before [CmdletBinding()] nor 
# appear between [CmdletBinding()] and param(). Place it right before the master
# function. 
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

# ==============================================================================
# MASTER FUNCTION
# Named to match the file. Uses an approved PowerShell verb.
# All executable code lives inside this function. Nothing runs at script scope
# except the entry point splat at the bottom of this file.
# ==============================================================================
function Disable-ADUserAccount {
    <#
    .SYNOPSIS
        Internal master function. See script-level help for full documentation.
    #>
    [CmdletBinding()]
    param (
        [string]$SamAccountName,
        [string]$TicketNumber,
        [string]$Operator,
        [string]$DisabledUsersOU,
        [string]$RemoveGroupMemberships,
        [string]$HideFromGAL,
        [string]$ReassignReportsTo,
        [string]$ScramblePassword,
        [string]$SetAccountExpiration,
        [string]$ReportOnly,
        [string]$VerboseOutput,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Disable-ADUserAccount"
    $ScriptVersion = "1.0.0.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # Boolean resolution — resolved once, used everywhere.
    # ReportOnly uses asymmetric guard: any value other than explicit 'false'
    # stays safely in report-only mode.
    $IsReportOnly             = ($ReportOnly.Trim().ToLower() -ne 'false')
    $IsVerbose                = ($VerboseOutput.Trim().ToLower() -ne 'false')
    $DoRemoveGroups           = ($RemoveGroupMemberships.Trim().ToLower() -eq 'true')
    $DoHideFromGAL            = ($HideFromGAL.Trim().ToLower() -eq 'true')
    $DoScramblePassword       = ($ScramblePassword.Trim().ToLower() -ne 'false')   # default true
    $DoSetAccountExpiration   = ($SetAccountExpiration.Trim().ToLower() -ne 'false') # default true

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
    # WRITE-CONSOLE  (Presentation Layer)
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
    # WRITE-VERBOSELOG  (Verbose-Gated Output)
    # ==========================================================================
    function Write-VerboseLog {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = "",

            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")]
            [string]$Severity = "INFO",

            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )

        if (-not $IsVerbose) { return }
        Write-Log     $Message -Severity $Severity
        Write-Console $Message -Severity $Severity -Indent $Indent
    }

    # ==========================================================================
    # CONSOLE PRESENTATION HELPERS
    # ==========================================================================
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

    function Write-Separator {
        param (
            [Parameter(Mandatory = $false)]
            [string]$Color = "DarkGray"
        )
        Write-Host ("-" * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # LOG SETUP
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
    # NEW-SCRAMBLEDPASSWORD
    # Generates a 32-character cryptographically random complex password.
    # The password is never logged. Caller must null the returned secure string
    # immediately after use.
    # ==========================================================================
    function New-ScrambledPassword {
        $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
        $lower   = 'abcdefghjkmnpqrstuvwxyz'.ToCharArray()
        $digits  = '23456789'.ToCharArray()
        $symbols = '!@#$%^&*()-_=+[]{}<>?'.ToCharArray()
        $allSets = @($upper, $lower, $digits, $symbols)

        $rng     = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes   = New-Object byte[] 32
        $rng.GetBytes($bytes)
        $rng.Dispose()

        $charsOut = New-Object 'System.Collections.Generic.List[char]'

        # Guarantee one of each set
        for ($i = 0; $i -lt 4; $i++) {
            $set = $allSets[$i]
            $charsOut.Add($set[ $bytes[$i] % $set.Length ]) | Out-Null
        }

        # Fill to 32 chars from the union
        $allChars = $upper + $lower + $digits + $symbols
        for ($i = 4; $i -lt 32; $i++) {
            $charsOut.Add($allChars[ $bytes[$i] % $allChars.Length ]) | Out-Null
        }

        # Shuffle (Fisher-Yates with crypto bytes)
        $shuffleRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $shuffleBytes = New-Object byte[] $charsOut.Count
        $shuffleRng.GetBytes($shuffleBytes)
        $shuffleRng.Dispose()
        for ($i = $charsOut.Count - 1; $i -gt 0; $i--) {
            $j = $shuffleBytes[$i] % ($i + 1)
            $tmp = $charsOut[$i]
            $charsOut[$i] = $charsOut[$j]
            $charsOut[$j] = $tmp
        }

        $plain  = -join $charsOut
        $secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
        $plain  = $null
        return $secure
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    $RunAs     = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $ModeLabel = if ($IsReportOnly) { 'REPORT-ONLY' } else { 'WRITE MODE' }

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName"                    -Severity INFO
    Write-Log "Hostname : $Hostname"                    -Severity INFO
    Write-Log "Run As   : $RunAs"                       -Severity INFO
    Write-Log "Mode     : $ModeLabel"                   -Severity INFO
    Write-Log "Operator : $Operator"                    -Severity INFO
    Write-Log "Ticket   : $TicketNumber"                -Severity INFO
    Write-Log "Target   : $SamAccountName"              -Severity INFO
    Write-Log "Log File : $LogFile"                     -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site     : $SiteName"      -Severity PLAIN
    Write-Console "Hostname : $Hostname"      -Severity PLAIN
    Write-Console "Run As   : $RunAs"         -Severity PLAIN
    Write-Console "Mode     : $ModeLabel"     -Severity PLAIN
    Write-Console "Operator : $Operator"      -Severity PLAIN
    Write-Console "Ticket   : $TicketNumber"  -Severity PLAIN
    Write-Console "Target   : $SamAccountName" -Severity PLAIN
    Write-Console "Log File : $LogFile"       -Severity PLAIN
    Write-Separator

    # Outcome counters for summary
    $actionsAttempted = 0
    $actionsSucceeded = 0
    $actionsSkipped   = 0
    $actionsFailed    = 0

    try {

        # ------------------------------------------------------------------
        # PRE-FLIGHT VALIDATION
        # ------------------------------------------------------------------
        Write-Section 'Pre-Flight'

        $preFlightFailed = $false

        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
            Write-Log "SamAccountName is required but was not provided." -Severity ERROR
            Write-Console "SamAccountName is required but was not provided." -Severity ERROR
            $preFlightFailed = $true
        }

        if ([string]::IsNullOrWhiteSpace($TicketNumber)) {
            Write-Log "TicketNumber is required but was not provided." -Severity ERROR
            Write-Console "TicketNumber is required but was not provided." -Severity ERROR
            $preFlightFailed = $true
        }

        if ([string]::IsNullOrWhiteSpace($Operator)) {
            Write-Log "Operator is required but was not provided." -Severity ERROR
            Write-Console "Operator is required but was not provided." -Severity ERROR
            $preFlightFailed = $true
        }

        # Validate DisabledUsersOU format if provided (must look like a DN)
        $ouProvided    = -not [string]::IsNullOrWhiteSpace($DisabledUsersOU)
        $ouLooksValid  = $false
        if ($ouProvided) {
            if ($DisabledUsersOU -match '^(OU|CN)=.+,DC=.+') {
                $ouLooksValid = $true
            }
            else {
                Write-Log "DisabledUsersOU does not look like a valid Distinguished Name. Expected format: OU=Disabled Users,OU=Company,DC=contoso,DC=local" -Severity ERROR
                Write-Console "DisabledUsersOU is not a valid Distinguished Name. See help for required format." -Severity ERROR
                $preFlightFailed = $true
            }
        }

        # AD module availability
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Write-Log "ActiveDirectory PowerShell module is not available on this host. Install RSAT-AD-PowerShell." -Severity ERROR
            Write-Console "ActiveDirectory module not available. Install RSAT-AD-PowerShell." -Severity ERROR
            $preFlightFailed = $true
        }
        else {
            try {
                Import-Module ActiveDirectory -ErrorAction Stop
            }
            catch {
                Write-Log "Failed to import ActiveDirectory module: $_" -Severity ERROR
                Write-Console "Failed to import ActiveDirectory module." -Severity ERROR
                $preFlightFailed = $true
            }
        }

        # Domain controller reachability
        if (-not $preFlightFailed) {
            try {
                $dc = Get-ADDomainController -Discover -ErrorAction Stop
                Write-Log "Discovered domain controller: $($dc.HostName)" -Severity INFO
            }
            catch {
                Write-Log "Could not locate a writable domain controller: $_" -Severity ERROR
                Write-Console "Could not locate a writable domain controller." -Severity ERROR
                $preFlightFailed = $true
            }
        }

        # Target user must exist
        $targetUser = $null
        if (-not $preFlightFailed) {
            try {
                $targetUser = Get-ADUser -Identity $SamAccountName -Properties `
                    Enabled, DistinguishedName, LastLogonDate, MemberOf, Manager, `
                    DirectReports, Description, AccountExpirationDate, `
                    msExchHideFromAddressLists, GivenName, Surname, EmailAddress `
                    -ErrorAction Stop
            }
            catch {
                Write-Log "Target user '$SamAccountName' not found in Active Directory: $_" -Severity ERROR
                Write-Console "Target user '$SamAccountName' not found in Active Directory." -Severity ERROR
                $preFlightFailed = $true
            }
        }

        # Validate ReassignReportsTo target if specified
        $reassignTargetUser = $null
        if (-not $preFlightFailed -and -not [string]::IsNullOrWhiteSpace($ReassignReportsTo)) {
            try {
                $reassignTargetUser = Get-ADUser -Identity $ReassignReportsTo -ErrorAction Stop
                Write-Log "Reassignment target user found: $($reassignTargetUser.DistinguishedName)" -Severity INFO
            }
            catch {
                Write-Log "ReassignReportsTo target '$ReassignReportsTo' not found in Active Directory: $_" -Severity ERROR
                Write-Console "ReassignReportsTo target '$ReassignReportsTo' not found." -Severity ERROR
                $preFlightFailed = $true
            }
        }

        # Validate Disabled Users OU exists if specified
        $ouExists = $false
        if (-not $preFlightFailed -and $ouProvided -and $ouLooksValid) {
            try {
                $null = Get-ADOrganizationalUnit -Identity $DisabledUsersOU -ErrorAction Stop
                $ouExists = $true
                Write-Log "Target Disabled Users OU verified: $DisabledUsersOU" -Severity INFO
            }
            catch {
                Write-Log "DisabledUsersOU '$DisabledUsersOU' was provided but does not exist. OU move step will be skipped." -Severity WARN
                Write-Console "DisabledUsersOU does not exist. OU move will be skipped." -Severity WARN
                $ouExists = $false
            }
        }

        if ($preFlightFailed) {
            Write-Log "Pre-flight validation failed. Exiting." -Severity ERROR
            Write-Banner "SCRIPT FAILED -- PRE-FLIGHT" -Color "Red"
            exit 2
        }

        Write-Log "Pre-flight validation passed." -Severity SUCCESS
        Write-Console "Pre-flight validation passed." -Severity SUCCESS

        # ------------------------------------------------------------------
        # PRE-STATE CAPTURE
        # Logged before any change for audit and reversal.
        # ------------------------------------------------------------------
        Write-Section 'Pre-State Capture'

        $preDN          = $targetUser.DistinguishedName
        $preEnabled     = $targetUser.Enabled
        $preLastLogon   = if ($targetUser.LastLogonDate) { $targetUser.LastLogonDate.ToString('yyyy-MM-dd HH:mm:ss') } else { '<never>' }
        $preDescription = if ($targetUser.Description) { $targetUser.Description } else { '<none>' }
        $preExpiration  = if ($targetUser.AccountExpirationDate) { $targetUser.AccountExpirationDate.ToString('yyyy-MM-dd') } else { '<none>' }
        $preGalHidden   = if ($null -eq $targetUser.msExchHideFromAddressLists) { '<unset>' } else { [string]$targetUser.msExchHideFromAddressLists }
        $preManager     = if ($targetUser.Manager) { $targetUser.Manager } else { '<none>' }

        Write-Log "[PRE-STATE] $SamAccountName | DistinguishedName : $preDN"           -Severity INFO
        Write-Log "[PRE-STATE] $SamAccountName | Enabled           : $preEnabled"      -Severity INFO
        Write-Log "[PRE-STATE] $SamAccountName | LastLogonDate     : $preLastLogon"    -Severity INFO
        Write-Log "[PRE-STATE] $SamAccountName | Description       : $preDescription"  -Severity INFO
        Write-Log "[PRE-STATE] $SamAccountName | AccountExpiration : $preExpiration"   -Severity INFO
        Write-Log "[PRE-STATE] $SamAccountName | GAL Hidden        : $preGalHidden"    -Severity INFO
        Write-Log "[PRE-STATE] $SamAccountName | Manager           : $preManager"      -Severity INFO

        # Group memberships — log each on its own line for grep-ability
        $preGroups = @()
        if ($targetUser.MemberOf) {
            foreach ($groupDN in $targetUser.MemberOf) {
                try {
                    $g = Get-ADGroup -Identity $groupDN -ErrorAction Stop
                    $preGroups += $g
                    Write-Log "[PRE-STATE] $SamAccountName | Group             : $($g.SamAccountName) ($groupDN)" -Severity INFO
                }
                catch {
                    Write-Log "[PRE-STATE] $SamAccountName | Group (unresolved): $groupDN" -Severity WARN
                }
            }
        }
        else {
            Write-Log "[PRE-STATE] $SamAccountName | Group             : <none beyond primary>" -Severity INFO
        }

        # Direct reports — log each on its own line
        $preDirectReports = @()
        if ($targetUser.DirectReports) {
            foreach ($reportDN in $targetUser.DirectReports) {
                try {
                    $r = Get-ADUser -Identity $reportDN -ErrorAction Stop
                    $preDirectReports += $r
                    Write-Log "[PRE-STATE] $SamAccountName | DirectReport      : $($r.SamAccountName) ($reportDN)" -Severity INFO
                }
                catch {
                    Write-Log "[PRE-STATE] $SamAccountName | DirectReport (unresolved): $reportDN" -Severity WARN
                }
            }
        }
        else {
            Write-Log "[PRE-STATE] $SamAccountName | DirectReports     : <none>" -Severity INFO
        }

        Write-Console "Pre-state captured. See log for full detail." -Severity INFO

        # ------------------------------------------------------------------
        # PLANNED ACTIONS
        # Build a list of what will happen, then execute it.
        # ------------------------------------------------------------------
        Write-Section 'Planned Actions'

        $tombstoneDate    = Get-Date -Format 'yyyy-MM-dd'
        $tombstoneText    = "Disabled $tombstoneDate by $Operator (Ticket #$TicketNumber) via DattoRMM"
        $tombstonePreview = $tombstoneText

        Write-Log "Planned: Disable account."                                                   -Severity INFO
        Write-Console "Plan: Disable account" -Severity INFO -Indent 1

        if ($DoScramblePassword) {
            Write-Log "Planned: Scramble password (32-char random complex)."                    -Severity INFO
            Write-Console "Plan: Scramble password" -Severity INFO -Indent 1
        }
        else {
            Write-Log "Planned: SKIP password scramble (ScramblePassword=false)."               -Severity INFO
            Write-Console "Plan: Skip password scramble" -Severity INFO -Indent 1
        }

        if ($DoSetAccountExpiration) {
            Write-Log "Planned: Set AccountExpirationDate to today."                            -Severity INFO
            Write-Console "Plan: Set AccountExpirationDate to today" -Severity INFO -Indent 1
        }

        Write-Log "Planned: Set Description to: $tombstonePreview"                              -Severity INFO
        Write-Console "Plan: Set Description tombstone" -Severity INFO -Indent 1

        if ($DoHideFromGAL) {
            Write-Log "Planned: Hide from GAL (msExchHideFromAddressLists = TRUE)."             -Severity INFO
            Write-Console "Plan: Hide from GAL" -Severity INFO -Indent 1
        }

        if ($DoRemoveGroups) {
            $groupRemovalCount = ($preGroups | Measure-Object).Count
            Write-Log "Planned: Remove from $groupRemovalCount group(s) (Domain Users preserved)." -Severity INFO
            Write-Console "Plan: Remove from $groupRemovalCount groups" -Severity INFO -Indent 1
        }

        $directReportCount = ($preDirectReports | Measure-Object).Count
        if ($directReportCount -gt 0) {
            if ($null -ne $reassignTargetUser) {
                Write-Log "Planned: Reassign $directReportCount direct report(s) to $($reassignTargetUser.SamAccountName)." -Severity INFO
                Write-Console "Plan: Reassign $directReportCount direct reports to $($reassignTargetUser.SamAccountName)" -Severity INFO -Indent 1
            }
            else {
                Write-Log "WARNING: User has $directReportCount direct report(s) and no ReassignReportsTo target was provided. Reports will be left orphaned." -Severity WARN
                Write-Console "WARN: $directReportCount direct reports will be ORPHANED (no reassign target)" -Severity WARN -Indent 1
            }
        }

        if ($ouProvided -and $ouExists) {
            Write-Log "Planned: Move account to $DisabledUsersOU."                              -Severity INFO
            Write-Console "Plan: Move to Disabled Users OU" -Severity INFO -Indent 1
        }
        elseif ($ouProvided -and -not $ouExists) {
            Write-Log "Planned: SKIP OU move (target OU does not exist)."                       -Severity WARN
            Write-Console "Plan: Skip OU move (OU not found)" -Severity WARN -Indent 1
        }
        else {
            Write-Log "Planned: SKIP OU move (no DisabledUsersOU provided)."                    -Severity INFO
            Write-Console "Plan: Skip OU move (not specified)" -Severity INFO -Indent 1
        }

        # ------------------------------------------------------------------
        # ACTION EXECUTION
        # All-or-nothing: report-only mode skips every write.
        # ------------------------------------------------------------------
        Write-Section 'Action Execution'

        if ($IsReportOnly) {
            Write-Log "REPORT-ONLY MODE: No changes will be made to Active Directory." -Severity WARN
            Write-Console "REPORT-ONLY MODE -- skipping all writes" -Severity WARN
        }

        # ----- Disable account -----
        $actionsAttempted++
        if ($IsReportOnly) {
            Write-VerboseLog "[SKIPPED-REPORT] Disable-ADAccount $SamAccountName" -Severity INFO -Indent 1
            $actionsSkipped++
        }
        elseif (-not $preEnabled) {
            Write-VerboseLog "[SKIPPED-CURRENT] Account already disabled." -Severity INFO -Indent 1
            $actionsSkipped++
        }
        else {
            try {
                Disable-ADAccount -Identity $SamAccountName -ErrorAction Stop
                Write-Log "[WROTE] Disabled $SamAccountName" -Severity SUCCESS
                Write-Console "Disabled account" -Severity SUCCESS -Indent 1
                $actionsSucceeded++
            }
            catch {
                Write-Log "[FAILED] Disable-ADAccount $SamAccountName : $_" -Severity ERROR
                Write-Console "Failed to disable account" -Severity ERROR -Indent 1
                $actionsFailed++
            }
        }

        # ----- Scramble password -----
        if ($DoScramblePassword) {
            $actionsAttempted++
            if ($IsReportOnly) {
                Write-VerboseLog "[SKIPPED-REPORT] Set-ADAccountPassword (scramble)" -Severity INFO -Indent 1
                $actionsSkipped++
            }
            else {
                $secure = $null
                try {
                    $secure = New-ScrambledPassword
                    Set-ADAccountPassword -Identity $SamAccountName -NewPassword $secure -Reset -ErrorAction Stop
                    Write-Log "[WROTE] Password scrambled (32-char random complex)" -Severity SUCCESS
                    Write-Console "Password scrambled" -Severity SUCCESS -Indent 1
                    $actionsSucceeded++
                }
                catch {
                    Write-Log "[FAILED] Set-ADAccountPassword $SamAccountName : $_" -Severity ERROR
                    Write-Console "Failed to scramble password" -Severity ERROR -Indent 1
                    $actionsFailed++
                }
                finally {
                    # Null the secure string immediately after use
                    if ($null -ne $secure) {
                        $secure.Dispose()
                        $secure = $null
                    }
                }
            }
        }

        # ----- Set account expiration to today -----
        if ($DoSetAccountExpiration) {
            $actionsAttempted++
            if ($IsReportOnly) {
                Write-VerboseLog "[SKIPPED-REPORT] Set AccountExpirationDate" -Severity INFO -Indent 1
                $actionsSkipped++
            }
            else {
                try {
                    Set-ADUser -Identity $SamAccountName -AccountExpirationDate (Get-Date) -ErrorAction Stop
                    Write-Log "[WROTE] AccountExpirationDate set to $(Get-Date -Format 'yyyy-MM-dd')" -Severity SUCCESS
                    Write-Console "Account expiration set" -Severity SUCCESS -Indent 1
                    $actionsSucceeded++
                }
                catch {
                    Write-Log "[FAILED] Set AccountExpirationDate $SamAccountName : $_" -Severity ERROR
                    Write-Console "Failed to set account expiration" -Severity ERROR -Indent 1
                    $actionsFailed++
                }
            }
        }

        # ----- Set tombstone description -----
        $actionsAttempted++
        if ($IsReportOnly) {
            Write-VerboseLog "[SKIPPED-REPORT] Set Description tombstone" -Severity INFO -Indent 1
            $actionsSkipped++
        }
        else {
            try {
                Set-ADUser -Identity $SamAccountName -Description $tombstoneText -ErrorAction Stop
                Write-Log "[WROTE] Description set to: $tombstoneText" -Severity SUCCESS
                Write-Console "Description tombstone applied" -Severity SUCCESS -Indent 1
                $actionsSucceeded++
            }
            catch {
                Write-Log "[FAILED] Set Description $SamAccountName : $_" -Severity ERROR
                Write-Console "Failed to set description" -Severity ERROR -Indent 1
                $actionsFailed++
            }
        }

        # ----- Hide from GAL -----
        if ($DoHideFromGAL) {
            $actionsAttempted++
            if ($IsReportOnly) {
                Write-VerboseLog "[SKIPPED-REPORT] Set msExchHideFromAddressLists = TRUE" -Severity INFO -Indent 1
                $actionsSkipped++
            }
            else {
                try {
                    Set-ADUser -Identity $SamAccountName -Replace @{msExchHideFromAddressLists = $true} -ErrorAction Stop
                    Write-Log "[WROTE] msExchHideFromAddressLists = TRUE" -Severity SUCCESS
                    Write-Console "Hidden from GAL" -Severity SUCCESS -Indent 1
                    $actionsSucceeded++
                }
                catch {
                    Write-Log "[FAILED] Set msExchHideFromAddressLists $SamAccountName : $_" -Severity ERROR
                    Write-Console "Failed to hide from GAL" -Severity ERROR -Indent 1
                    $actionsFailed++
                }
            }
        }

        # ----- Reassign or warn on direct reports -----
        if ($directReportCount -gt 0) {
            if ($null -ne $reassignTargetUser) {
                foreach ($report in $preDirectReports) {
                    $actionsAttempted++
                    if ($IsReportOnly) {
                        Write-VerboseLog "[SKIPPED-REPORT] Reassign $($report.SamAccountName) -> $($reassignTargetUser.SamAccountName)" -Severity INFO -Indent 1
                        $actionsSkipped++
                    }
                    else {
                        try {
                            Set-ADUser -Identity $report.DistinguishedName -Manager $reassignTargetUser.DistinguishedName -ErrorAction Stop
                            Write-Log "[WROTE] Reassigned $($report.SamAccountName) -> $($reassignTargetUser.SamAccountName)" -Severity SUCCESS
                            Write-Console "Reassigned $($report.SamAccountName)" -Severity SUCCESS -Indent 1
                            $actionsSucceeded++
                        }
                        catch {
                            Write-Log "[FAILED] Reassign $($report.SamAccountName) : $_" -Severity ERROR
                            Write-Console "Failed to reassign $($report.SamAccountName)" -Severity ERROR -Indent 1
                            $actionsFailed++
                        }
                    }
                }
            }
            else {
                Write-Log "WARNING: $directReportCount direct report(s) orphaned (no ReassignReportsTo target):" -Severity WARN
                Write-Console "WARN: $directReportCount direct reports orphaned" -Severity WARN -Indent 1
                foreach ($report in $preDirectReports) {
                    Write-Log "[ORPHANED-REPORT] $($report.SamAccountName)" -Severity WARN
                    Write-Console "$($report.SamAccountName)" -Severity WARN -Indent 2
                }
            }
        }

        # ----- Remove group memberships -----
        if ($DoRemoveGroups -and $preGroups.Count -gt 0) {
            foreach ($group in $preGroups) {
                # Skip Domain Users (it's a primary group anyway and Remove-ADGroupMember would fail)
                if ($group.SamAccountName -eq 'Domain Users') {
                    Write-VerboseLog "[SKIPPED-CURRENT] Domain Users (primary group, preserved)" -Severity INFO -Indent 1
                    continue
                }

                $actionsAttempted++
                if ($IsReportOnly) {
                    Write-VerboseLog "[SKIPPED-REPORT] Remove from $($group.SamAccountName)" -Severity INFO -Indent 1
                    $actionsSkipped++
                }
                else {
                    try {
                        Remove-ADGroupMember -Identity $group.DistinguishedName -Members $SamAccountName -Confirm:$false -ErrorAction Stop
                        Write-Log "[WROTE] Removed from group: $($group.SamAccountName)" -Severity SUCCESS
                        Write-Console "Removed from $($group.SamAccountName)" -Severity SUCCESS -Indent 1
                        $actionsSucceeded++
                    }
                    catch {
                        Write-Log "[FAILED] Remove from group $($group.SamAccountName) : $_" -Severity ERROR
                        Write-Console "Failed to remove from $($group.SamAccountName)" -Severity ERROR -Indent 1
                        $actionsFailed++
                    }
                }
            }
        }

        # ----- Move to Disabled Users OU (last, so other operations target the
        # known-good DN we captured up front) -----
        if ($ouProvided -and $ouExists) {
            $actionsAttempted++
            if ($IsReportOnly) {
                Write-VerboseLog "[SKIPPED-REPORT] Move-ADObject -> $DisabledUsersOU" -Severity INFO -Indent 1
                $actionsSkipped++
            }
            else {
                try {
                    Move-ADObject -Identity $preDN -TargetPath $DisabledUsersOU -ErrorAction Stop
                    Write-Log "[WROTE] Moved to $DisabledUsersOU" -Severity SUCCESS
                    Write-Console "Moved to Disabled Users OU" -Severity SUCCESS -Indent 1
                    $actionsSucceeded++
                }
                catch {
                    Write-Log "[FAILED] Move-ADObject $SamAccountName : $_" -Severity ERROR
                    Write-Console "Failed to move to Disabled Users OU" -Severity ERROR -Indent 1
                    $actionsFailed++
                }
            }
        }

        # ------------------------------------------------------------------
        # SUMMARY
        # ------------------------------------------------------------------
        Write-Section 'Summary'

        Write-Log "Mode              : $ModeLabel"          -Severity INFO
        Write-Log "Target            : $SamAccountName"     -Severity INFO
        Write-Log "Operator          : $Operator"           -Severity INFO
        Write-Log "Ticket            : $TicketNumber"       -Severity INFO
        Write-Log "Actions Attempted : $actionsAttempted"   -Severity INFO
        Write-Log "Actions Succeeded : $actionsSucceeded"   -Severity INFO
        Write-Log "Actions Skipped   : $actionsSkipped"     -Severity INFO
        Write-Log "Actions Failed    : $actionsFailed"      -Severity INFO

        Write-Console "Mode              : $ModeLabel"        -Severity PLAIN
        Write-Console "Actions Attempted : $actionsAttempted" -Severity PLAIN
        Write-Console "Actions Succeeded : $actionsSucceeded" -Severity PLAIN
        Write-Console "Actions Skipped   : $actionsSkipped"   -Severity PLAIN
        Write-Console "Actions Failed    : $actionsFailed"    -Severity PLAIN

        if ($actionsFailed -gt 0) {
            Write-Log "WARNING: One or more actions failed. Review log for details." -Severity WARN
            Write-Banner "COMPLETED WITH ERRORS" -Color "Yellow"
            exit 1
        }

        Write-Log "Script completed successfully." -Severity SUCCESS
        Write-Banner "COMPLETED SUCCESSFULLY" -Color "Green"

        exit 0

    }
    catch {
        Write-Log "Unhandled exception: $_"             -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Console "Unhandled exception: $_"         -Severity ERROR
        Write-Banner "SCRIPT FAILED" -Color "Red"

        exit 1
    }

} # End function Disable-ADUserAccount

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    SamAccountName         = $SamAccountName
    TicketNumber           = $TicketNumber
    Operator               = $Operator
    DisabledUsersOU        = $DisabledUsersOU
    RemoveGroupMemberships = $RemoveGroupMemberships
    HideFromGAL            = $HideFromGAL
    ReassignReportsTo      = $ReassignReportsTo
    ScramblePassword       = $ScramblePassword
    SetAccountExpiration   = $SetAccountExpiration
    ReportOnly             = $ReportOnly
    VerboseOutput          = $VerboseOutput
    SiteName               = $SiteName
    Hostname               = $Hostname
}

Disable-ADUserAccount @ScriptParams
