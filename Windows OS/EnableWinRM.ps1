#Requires -Version 5.1

<#
.SYNOPSIS
    Enables and validates Remote WinRM and Windows PowerShell remoting.

.DESCRIPTION
    Configures the local Windows device to accept Windows PowerShell remoting
    connections through Windows Remote Management.

    The script validates and optionally configures:

    - Administrative execution context
    - WinRM service startup type and running state
    - Windows PowerShell remoting
    - WinRM HTTP listener
    - Built-in Windows Firewall rules for WinRM
    - Microsoft.PowerShell session configuration
    - Local WS-Management connectivity

    The script supports Datto RMM component variables and standard PowerShell
    parameters. It defaults to report-only mode.

.PARAMETER ReportOnly
    Controls whether changes are committed.

    true  = Report current configuration without making changes.
    false = Enable or repair Remote WinRM.

    Default: true

.PARAMETER AllowPublicProfile
    Controls WinRM behavior when an active network connection is categorized
    as Public.

    false = Preserve the default Public-profile restriction.
    true  = Use Enable-PSRemoting with SkipNetworkProfileCheck and expand the
            built-in Public WinRM firewall rule to RemoteAddress Any.

    Default: false

.PARAMETER ResetPowerShellEndpoint
    Controls whether the Microsoft.PowerShell session configuration is
    re-registered during write mode.

    Default: false

.PARAMETER VerboseOutput
    Controls detailed per-check and per-change logging.

    Default: true

.EXAMPLE
    .\Enable-RemoteWinRM.ps1

    Audits the current configuration without making changes.

.EXAMPLE
    .\Enable-RemoteWinRM.ps1 -ReportOnly 'false'

    Enables WinRM and Windows PowerShell remoting.

.EXAMPLE
    .\Enable-RemoteWinRM.ps1 `
        -ReportOnly 'false' `
        -AllowPublicProfile 'true'

    Enables remoting and allows the built-in Public-profile WinRM firewall
    rule from any remote address.

.NOTES
    Script Name : Enable-RemoteWinRM.ps1
    Version     : v1.0.0.002
    Author      : Josh Britton
    Company     : Databranch
    PowerShell  : 5.1 or later
    Run Context : Local Administrator or SYSTEM

    Datto RMM component variables:

        ReportOnly
        AllowPublicProfile
        ResetPowerShellEndpoint
        VerboseOutput

    Exit codes:

        0 = Script completed successfully.
        1 = Runtime or write-mode validation failure.
        2 = Fatal pre-flight failure.

    Security:

        This script configures the standard WinRM HTTP listener on TCP 5985.

        It does not:

        - Modify TrustedHosts
        - Enable Basic authentication
        - Enable unencrypted WinRM communication
        - Create an HTTPS listener
        - Generate or install certificates
        - Create local administrative accounts

.CHANGELOG
    v1.0.0.002 - 2026-08-10 - Josh Britton
        - Corrected Public-profile firewall address configuration.
        - Added distinct report-only validation handling.
        - Improved listener and firewall validation.
        - Reduced duplicate output and simplified configuration flow.

    v1.0.0.001 - 2026-08-10 - Josh Britton
        - Initial release.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ReportOnly = $(if ($env:ReportOnly) {
        $env:ReportOnly
    }
    else {
        'true'
    }),

    [Parameter(Mandatory = $false)]
    [string]$AllowPublicProfile = $(if ($env:AllowPublicProfile) {
        $env:AllowPublicProfile
    }
    else {
        'false'
    }),

    [Parameter(Mandatory = $false)]
    [string]$ResetPowerShellEndpoint = $(if ($env:ResetPowerShellEndpoint) {
        $env:ResetPowerShellEndpoint
    }
    else {
        'false'
    }),

    [Parameter(Mandatory = $false)]
    [string]$VerboseOutput = $(if ($env:VerboseOutput) {
        $env:VerboseOutput
    }
    else {
        'true'
    })
)

function Enable-RemoteWinRM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ReportOnly,

        [Parameter(Mandatory = $true)]
        [string]$AllowPublicProfile,

        [Parameter(Mandatory = $true)]
        [string]$ResetPowerShellEndpoint,

        [Parameter(Mandatory = $true)]
        [string]$VerboseOutput
    )

    # =========================================================================
    # SCRIPT CONFIGURATION
    # =========================================================================

    $ErrorActionPreference = 'Stop'

    $ScriptName     = 'Enable-RemoteWinRM'
    $ScriptVersion  = '1.0.0.002'
    $LogRoot        = 'C:\Databranch\ScriptLogs'
    $LogFolder      = Join-Path -Path $LogRoot -ChildPath $ScriptName
    $LogFile        = Join-Path -Path $LogFolder -ChildPath (
        '{0}_{1}.log' -f $ScriptName, (Get-Date -Format 'yyyy-MM-dd')
    )

    # Report-only is the safe state. Only the literal value "false" enables
    # configuration changes.
    $IsReportOnly = ($ReportOnly.Trim().ToLower() -ne 'false')
    $AllowPublic = (
        $AllowPublicProfile.Trim().ToLower() -eq 'true'
    )
    $ResetEndpoint = (
        $ResetPowerShellEndpoint.Trim().ToLower() -eq 'true'
    )
    $IsVerbose = (
        $VerboseOutput.Trim().ToLower() -eq 'true'
    )

    $ModeDisplay = if ($IsReportOnly) {
        'REPORT-ONLY (no changes made)'
    }
    else {
        'WRITE MODE (changes committed)'
    }

    $ExitCode           = 0
    $ChangesRequired    = 0
    $ChangesCompleted   = 0
    $ValidationFailures = 0

    # =========================================================================
    # LOGGING FUNCTIONS
    # =========================================================================

    function Initialize-Logging {
        [CmdletBinding()]
        param ()

        if (-not (Test-Path -LiteralPath $LogFolder)) {
            New-Item `
                -Path $LogFolder `
                -ItemType Directory `
                -Force `
                -ErrorAction Stop | Out-Null
        }

        $ExistingLogs = @(
            Get-ChildItem `
                -Path $LogFolder `
                -Filter "$ScriptName`_*.log" `
                -File `
                -ErrorAction SilentlyContinue |
                Sort-Object -Property LastWriteTime -Descending
        )

        if ($ExistingLogs.Count -gt 10) {
            $ExistingLogs |
                Select-Object -Skip 10 |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    function Write-Log {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
            [string]$Severity = 'INFO'
        )

        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $LogLine = '[{0}] [{1}] {2}' -f $Timestamp, $Severity, $Message

        try {
            Add-Content `
                -LiteralPath $LogFile `
                -Value $LogLine `
                -Encoding UTF8 `
                -ErrorAction Stop
        }
        catch {
            Write-Output (
                '[WARN] Unable to write to log file: {0}' -f
                $_.Exception.Message
            )
        }

        switch ($Severity) {
            'WARN' {
                Write-Warning -Message $LogLine
            }

            'ERROR' {
                Write-Error -Message $LogLine -ErrorAction Continue
            }

            default {
                Write-Output $LogLine
            }
        }
    }

    function Write-Console {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet(
                'INFO',
                'WARN',
                'ERROR',
                'SUCCESS',
                'DEBUG',
                'PLAIN'
            )]
            [string]$Severity = 'PLAIN',

            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )

        $Color = switch ($Severity) {
            'INFO'    { 'Cyan' }
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            'SUCCESS' { 'Green' }
            'DEBUG'   { 'Magenta' }
            default   { 'Gray' }
        }

        $Padding = ' ' * $Indent
        Write-Host "$Padding$Message" -ForegroundColor $Color
    }

    function Write-VerboseLog {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
            [string]$Severity = 'INFO',

            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )

        if (-not $IsVerbose) {
            return
        }

        Write-Log -Message $Message -Severity $Severity

        Write-Console `
            -Message $Message `
            -Severity $Severity `
            -Indent $Indent
    }

    function Write-Section {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Title
        )

        Write-Log -Message ('=' * 72)
        Write-Log -Message $Title
        Write-Log -Message ('=' * 72)

        Write-Console -Message ('=' * 72)
        Write-Console -Message $Title -Severity 'INFO'
        Write-Console -Message ('=' * 72)
    }

    # =========================================================================
    # VALIDATION FUNCTIONS
    # =========================================================================

    function Test-IsAdministrator {
        [CmdletBinding()]
        param ()

        $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

        $Principal = New-Object `
            -TypeName 'Security.Principal.WindowsPrincipal' `
            -ArgumentList $Identity

        return $Principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }

    function Get-WinRMListenerState {

    [CmdletBinding()]
    param ()

    $ListenerState = [ordered]@{
        HttpListenerPresent  = $false
        HttpsListenerPresent = $false
    }

    try {

        $Listeners = Get-ChildItem `
            -Path WSMan:\localhost\Listener `
            -ErrorAction Stop

        foreach ($Listener in $Listeners) {

            $Keys = ($Listener.Keys -join ';')

            if ($Keys -match 'Transport=HTTP') {
                $ListenerState.HttpListenerPresent = $true
            }

            if ($Keys -match 'Transport=HTTPS') {
                $ListenerState.HttpsListenerPresent = $true
            }
        }
    }
    catch {
    }
    
    return [PSCustomObject]$ListenerState

    }

    function Get-WinRMFirewallState {
        [CmdletBinding()]
        param ()

        $FirewallState = [ordered]@{
            RulesFound        = 0
            EnabledRules      = 0
            PublicRulesFound  = 0
            PublicRulesOpen   = 0
        }

        $Rules = @(
            Get-NetFirewallRule `
                -Name 'WINRM-HTTP-In-TCP*' `
                -ErrorAction SilentlyContinue
        )

        $FirewallState.RulesFound = $Rules.Count

        $EnabledRules = @(
            $Rules |
                Where-Object {
                    $_.Enabled -eq 'True'
                }
        )

        $FirewallState.EnabledRules = $EnabledRules.Count

        $PublicRules = @(
            $Rules |
                Where-Object {
                    $_.Name -eq 'WINRM-HTTP-In-TCP-PUBLIC'
                }
        )

        $FirewallState.PublicRulesFound = $PublicRules.Count

        foreach ($Rule in $PublicRules) {
            if ($Rule.Enabled -ne 'True') {
                continue
            }

            $AddressFilter = $Rule |
                Get-NetFirewallAddressFilter `
                    -ErrorAction SilentlyContinue

            if (
                $null -ne $AddressFilter -and
                $AddressFilter.RemoteAddress -contains 'Any'
            ) {
                $FirewallState.PublicRulesOpen++
            }
        }

        return [PSCustomObject]$FirewallState
    }

    function Get-WinRMState {
        [CmdletBinding()]
        param ()

        $State = [ordered]@{
            ServiceExists          = $false
            ServiceRunning         = $false
            ServiceStartMode       = $null
            HttpListenerPresent    = $false
            HttpsListenerPresent   = $false
            FirewallRulesFound     = 0
            FirewallRulesEnabled   = 0
            PublicFirewallOpen     = $false
            PowerShellEndpoint     = $false
            LocalWSManResponding   = $false
        }

        $Service = Get-Service `
            -Name 'WinRM' `
            -ErrorAction SilentlyContinue

        if ($null -ne $Service) {
            $State.ServiceExists = $true
            $State.ServiceRunning = ($Service.Status -eq 'Running')

            $ServiceData = Get-CimInstance `
                -ClassName Win32_Service `
                -Filter "Name='WinRM'" `
                -ErrorAction SilentlyContinue

            if ($null -ne $ServiceData) {
                $State.ServiceStartMode = $ServiceData.StartMode
            }
        }

        $ListenerState = Get-WinRMListenerState

        $State.HttpListenerPresent = (
            $ListenerState.HttpListenerPresent
        )

        $State.HttpsListenerPresent = (
            $ListenerState.HttpsListenerPresent
        )

        $FirewallState = Get-WinRMFirewallState

        $State.FirewallRulesFound = (
            $FirewallState.RulesFound
        )

        $State.FirewallRulesEnabled = (
            $FirewallState.EnabledRules
        )

        $State.PublicFirewallOpen = (
            $FirewallState.PublicRulesOpen -gt 0
        )

        $Endpoint = Get-PSSessionConfiguration `
            -Name 'Microsoft.PowerShell' `
            -ErrorAction SilentlyContinue

        $State.PowerShellEndpoint = ($null -ne $Endpoint)

        try {
            Test-WSMan `
                -ComputerName 'localhost' `
                -ErrorAction Stop | Out-Null

            $State.LocalWSManResponding = $true
        }
        catch {
            $State.LocalWSManResponding = $false
        }

        return [PSCustomObject]$State
    }

    function Write-WinRMState {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [PSCustomObject]$State,

            [Parameter(Mandatory = $true)]
            [string]$Label
        )

        Write-Log -Message $Label
        Write-Console -Message $Label -Severity 'INFO'

        Write-VerboseLog -Message (
            'WinRM service exists        : {0}' -f
            $State.ServiceExists
        )

        Write-VerboseLog -Message (
            'WinRM service running       : {0}' -f
            $State.ServiceRunning
        )

        Write-VerboseLog -Message (
            'WinRM service start mode    : {0}' -f
            $State.ServiceStartMode
        )

        Write-VerboseLog -Message (
            'HTTP listener present       : {0}' -f
            $State.HttpListenerPresent
        )

        Write-VerboseLog -Message (
            'HTTPS listener present      : {0}' -f
            $State.HttpsListenerPresent
        )

        Write-VerboseLog -Message (
            'WinRM firewall rules found  : {0}' -f
            $State.FirewallRulesFound
        )

        Write-VerboseLog -Message (
            'WinRM firewall rules enabled: {0}' -f
            $State.FirewallRulesEnabled
        )

        Write-VerboseLog -Message (
            'Public WinRM rule open      : {0}' -f
            $State.PublicFirewallOpen
        )

        Write-VerboseLog -Message (
            'PowerShell endpoint present : {0}' -f
            $State.PowerShellEndpoint
        )

        Write-VerboseLog -Message (
            'Local Test-WSMan succeeded  : {0}' -f
            $State.LocalWSManResponding
        )
    }

    function Write-ValidationResult {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [bool]$Passed,

            [Parameter(Mandatory = $true)]
            [string]$SuccessMessage,

            [Parameter(Mandatory = $true)]
            [string]$FailureMessage
        )

        if ($Passed) {
            Write-VerboseLog `
                -Message "[PASS] $SuccessMessage" `
                -Severity 'SUCCESS'

            return $true
        }

        if ($IsReportOnly) {
            Write-Log `
                -Message "[REQUIRES-CHANGE] $FailureMessage" `
                -Severity 'WARN'
        }
        else {
            Write-Log `
                -Message "[FAIL] $FailureMessage" `
                -Severity 'ERROR'
        }

        return $false
    }

    # =========================================================================
    # INITIALIZE LOGGING
    # =========================================================================

    try {
        Initialize-Logging
    }
    catch {
        Write-Output (
            '[ERROR] Fatal logging initialization failure: {0}' -f
            $_.Exception.Message
        )

        return 2
    }

    $SiteName = if ($env:CS_PROFILE_NAME) {
        $env:CS_PROFILE_NAME
    }
    else {
        'UnknownSite'
    }

    $HostName = if ($env:CS_HOSTNAME) {
        $env:CS_HOSTNAME
    }
    elseif ($env:COMPUTERNAME) {
        $env:COMPUTERNAME
    }
    else {
        'UnknownHost'
    }

    $RunAs = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log -Message "===== $ScriptName v$ScriptVersion ====="
    Write-Log -Message "Site     : $SiteName"
    Write-Log -Message "Hostname : $HostName"
    Write-Log -Message "Run As   : $RunAs"
    Write-Log -Message "Mode     : $ModeDisplay"
    Write-Log -Message "Log File : $LogFile"

    Write-Console `
        -Message "===== $ScriptName v$ScriptVersion =====" `
        -Severity 'INFO'

    Write-Console -Message "Site     : $SiteName"
    Write-Console -Message "Hostname : $HostName"
    Write-Console -Message "Run As   : $RunAs"
    Write-Console -Message "Mode     : $ModeDisplay"
    Write-Console -Message "Log File : $LogFile"

    try {
        # =====================================================================
        # PRE-FLIGHT
        # =====================================================================

        Write-Section -Title 'Pre-Flight Validation'

        if (-not (Test-IsAdministrator)) {
            Write-Log -Message (
                'Fatal pre-flight failure: administrative rights are ' +
                'required. Run the component as LocalSystem or an ' +
                'administrator.'
            ) -Severity 'ERROR'

            return 2
        }

        Write-VerboseLog `
            -Message '[PASS] Administrative execution context confirmed.' `
            -Severity 'SUCCESS'

        $RequiredCommands = @(
            'Enable-PSRemoting',
            'Get-NetConnectionProfile',
            'Get-NetFirewallRule',
            'Get-NetFirewallAddressFilter',
            'Set-NetFirewallAddressFilter',
            'Test-WSMan'
        )

        foreach ($CommandName in $RequiredCommands) {
            $Command = Get-Command `
                -Name $CommandName `
                -ErrorAction SilentlyContinue

            if ($null -eq $Command) {
                Write-Log -Message (
                    "Fatal pre-flight failure: required command " +
                    "'$CommandName' was not found."
                ) -Severity 'ERROR'

                return 2
            }

            Write-VerboseLog `
                -Message "[PASS] Required command found: $CommandName" `
                -Severity 'SUCCESS'
        }

        $ActiveProfiles = @(
            Get-NetConnectionProfile -ErrorAction Stop
        )

        $ActivePublicProfiles = @(
            $ActiveProfiles |
                Where-Object {
                    $_.NetworkCategory -eq 'Public'
                }
        )

        if ($ActivePublicProfiles.Count -gt 0) {
            $PublicProfileNames = @(
                $ActivePublicProfiles |
                        ForEach-Object {
                            if ([string]::IsNullOrEmpty($_.Name)) {
                                "InterfaceIndex $($_.InterfaceIndex)"
                            }
                            else {
                                $_.Name
                            }
                        }
            )

            Write-Log -Message (
                'Active Public network profile detected: {0}' -f
                ($PublicProfileNames -join ', ')
            ) -Severity 'WARN'

            if (-not $AllowPublic) {
                Write-Log -Message (
                    'AllowPublicProfile is false. The Public-profile WinRM ' +
                    'firewall rule will not be expanded.'
                ) -Severity 'WARN'
            }
        }
        else {
            Write-VerboseLog `
                -Message '[PASS] No active Public network profile detected.' `
                -Severity 'SUCCESS'
        }

        # =====================================================================
        # CURRENT STATE
        # =====================================================================

        Write-Section -Title 'Current WinRM Configuration'

        $BeforeState = Get-WinRMState

        Write-WinRMState `
            -State $BeforeState `
            -Label 'State before configuration:'

        if (-not $BeforeState.ServiceRunning) {
            $ChangesRequired++
        }

        if ($BeforeState.ServiceStartMode -ne 'Auto') {
            $ChangesRequired++
        }

        if (-not $BeforeState.HttpListenerPresent) {
            $ChangesRequired++
        }

        if ($BeforeState.FirewallRulesEnabled -lt 1) {
            $ChangesRequired++
        }

        if (-not $BeforeState.PowerShellEndpoint) {
            $ChangesRequired++
        }

        if (-not $BeforeState.LocalWSManResponding) {
            $ChangesRequired++
        }

        if (
            $AllowPublic -and
            $ActivePublicProfiles.Count -gt 0 -and
            -not $BeforeState.PublicFirewallOpen
        ) {
            $ChangesRequired++
        }

        if ($ResetEndpoint) {
            $ChangesRequired++
        }

        # =====================================================================
        # CONFIGURATION
        # =====================================================================

        Write-Section -Title 'WinRM Configuration'

        if ($IsReportOnly) {
            if ($ChangesRequired -eq 0) {
                Write-VerboseLog -Message (
                    '[SKIPPED-CURRENT] Remote WinRM is already configured.'
                ) -Severity 'SUCCESS'
            }
            else {
                Write-VerboseLog -Message (
                    '[SKIPPED-REPORT] Would enable or repair Windows ' +
                    'PowerShell remoting, the WinRM service, HTTP listener, ' +
                    'session configuration, and firewall rules.'
                )

                if ($ResetEndpoint) {
                    Write-VerboseLog -Message (
                        '[SKIPPED-REPORT] Would re-register the ' +
                        'Microsoft.PowerShell session configuration.'
                    )
                }

                if (
                    $AllowPublic -and
                    $ActivePublicProfiles.Count -gt 0
                ) {
                    Write-VerboseLog -Message (
                        '[SKIPPED-REPORT] Would expand the built-in Public ' +
                        'WinRM rule to RemoteAddress Any.'
                    )
                }
            }
        }
        else {
            Set-Service `
                -Name 'WinRM' `
                -StartupType Automatic `
                -ErrorAction Stop

            Write-VerboseLog `
                -Message '[WROTE] Set WinRM startup type to Automatic.' `
                -Severity 'SUCCESS'

            $ChangesCompleted++

            $WinRMService = Get-Service `
                -Name 'WinRM' `
                -ErrorAction Stop

            if ($WinRMService.Status -ne 'Running') {
                Start-Service `
                    -Name 'WinRM' `
                    -ErrorAction Stop

                Write-VerboseLog `
                    -Message '[WROTE] Started the WinRM service.' `
                    -Severity 'SUCCESS'

                $ChangesCompleted++
            }
            else {
                Write-VerboseLog -Message (
                    '[SKIPPED-CURRENT] WinRM service is already running.'
                )
            }

           Enable-PSRemoting -Force -Confirm:$false -ErrorAction Stop
         
            Write-VerboseLog -Message (
                '[WROTE] Enabled or repaired Windows PowerShell remoting.'
            ) -Severity 'SUCCESS'

            $ChangesCompleted++

            if ($ResetEndpoint) {
                Register-PSSessionConfiguration `
                    -Name 'Microsoft.PowerShell' `
                    -Force `
                    -ErrorAction Stop | Out-Null

                Write-VerboseLog -Message (
                    '[WROTE] Re-registered the Microsoft.PowerShell ' +
                    'session configuration.'
                ) -Severity 'SUCCESS'

                $ChangesCompleted++
            }

            if (
                $AllowPublic -and
                $ActivePublicProfiles.Count -gt 0
            ) {
                $PublicRule = Get-NetFirewallRule `
                    -Name 'WINRM-HTTP-In-TCP-PUBLIC' `
                    -ErrorAction SilentlyContinue

                if ($null -eq $PublicRule) {
                    Write-Log -Message (
                        'WARNING: The built-in Public WinRM firewall rule ' +
                        'WINRM-HTTP-In-TCP-PUBLIC was not found. No custom ' +
                        'firewall rule was created.'
                    ) -Severity 'WARN'
                }
                else {
                    $PublicRule |
                        Set-NetFirewallRule `
                            -Enabled True `
                            -ErrorAction Stop

                    $PublicRule |
                        Get-NetFirewallAddressFilter `
                            -ErrorAction Stop |
                        Set-NetFirewallAddressFilter `
                            -RemoteAddress Any `
                            -ErrorAction Stop

                    Write-VerboseLog -Message (
                        '[WROTE] Enabled the Public WinRM rule and set its ' +
                        'remote address scope to Any.'
                    ) -Severity 'SUCCESS'

                    $ChangesCompleted++
                }
            }
        }

        # =====================================================================
        # POST-CONDITION VALIDATION
        # =====================================================================

        Write-Section -Title 'Post-Condition Validation'

        $AfterState = Get-WinRMState

        Write-WinRMState `
            -State $AfterState `
            -Label 'State after configuration phase:'

        $Result = Write-ValidationResult `
            -Passed $AfterState.ServiceExists `
            -SuccessMessage 'WinRM service exists.' `
            -FailureMessage 'WinRM service was not found.'

        if (-not $Result) {
            $ValidationFailures++
        }

        $Result = Write-ValidationResult `
            -Passed $AfterState.ServiceRunning `
            -SuccessMessage 'WinRM service is running.' `
            -FailureMessage 'WinRM service is not running.'

        if (-not $Result) {
            $ValidationFailures++
        }

        $Result = Write-ValidationResult `
            -Passed ($AfterState.ServiceStartMode -eq 'Auto') `
            -SuccessMessage 'WinRM startup mode is Automatic.' `
            -FailureMessage (
                'WinRM startup mode is not Automatic. Detected: {0}' -f
                $AfterState.ServiceStartMode
            )

        if (-not $Result) {
            $ValidationFailures++
        }

     # If WSMan responds locally, we know an HTTP listener is functioning
        $ListenerValidated = (
            $AfterState.HttpListenerPresent -or
            $AfterState.LocalWSManResponding
        )

        $Result = Write-ValidationResult `
            -Passed $ListenerValidated `
            -SuccessMessage 'WinRM HTTP listener exists.' `
            -FailureMessage 'WinRM HTTP listener was not detected.'

        if (-not $Result) {
            $ValidationFailures++
        }

        $Result = Write-ValidationResult `
            -Passed ($AfterState.FirewallRulesEnabled -gt 0) `
            -SuccessMessage (
                'At least one built-in WinRM HTTP firewall rule is enabled.'
            ) `
            -FailureMessage (
                'No enabled built-in WinRM HTTP firewall rule was detected.'
            )

        if (-not $Result) {
            $ValidationFailures++
        }

        $Result = Write-ValidationResult `
            -Passed $AfterState.PowerShellEndpoint `
            -SuccessMessage (
                'Microsoft.PowerShell session configuration exists.'
            ) `
            -FailureMessage (
                'Microsoft.PowerShell session configuration was not detected.'
            )

        if (-not $Result) {
            $ValidationFailures++
        }

        $Result = Write-ValidationResult `
            -Passed $AfterState.LocalWSManResponding `
            -SuccessMessage 'Test-WSMan localhost succeeded.' `
            -FailureMessage 'Test-WSMan localhost did not succeed.'

        if (-not $Result) {
            $ValidationFailures++
        }

        if (
            $AllowPublic -and
            $ActivePublicProfiles.Count -gt 0
        ) {
            $Result = Write-ValidationResult `
                -Passed $AfterState.PublicFirewallOpen `
                -SuccessMessage (
                    'Public WinRM firewall rule allows RemoteAddress Any.'
                ) `
                -FailureMessage (
                    'Public WinRM firewall rule does not allow ' +
                    'RemoteAddress Any.'
                )

            if (-not $Result) {
                $ValidationFailures++
            }
        }

        # =====================================================================
        # SUMMARY
        # =====================================================================

        Write-Section -Title 'Summary'

        Write-Log -Message "Mode                : $ModeDisplay"
        Write-Log -Message "Changes required    : $ChangesRequired"
        Write-Log -Message "Changes completed   : $ChangesCompleted"
        Write-Log -Message "Validation failures : $ValidationFailures"

        Write-Log -Message (
            'WinRM service        : {0}' -f
            $(if ($AfterState.ServiceRunning) {
                'Running'
            }
            else {
                'Not Running'
            })
        )

        Write-Log -Message (
            'HTTP listener        : {0}' -f
            $(if ($AfterState.HttpListenerPresent) {
                'Present'
            }
            else {
                'Not Present'
            })
        )

        Write-Log -Message (
            'PowerShell endpoint  : {0}' -f
            $(if ($AfterState.PowerShellEndpoint) {
                'Present'
            }
            else {
                'Not Present'
            })
        )

        Write-Log -Message (
            'Local WSMan test     : {0}' -f
            $(if ($AfterState.LocalWSManResponding) {
                'Passed'
            }
            else {
                'Failed'
            })
        )

        if ($IsReportOnly -and $ValidationFailures -gt 0) {
            Write-Log -Message (
                'WARNING: WinRM configuration changes are required, but the ' +
                'script ran in report-only mode. Set ReportOnly to false to ' +
                'commit the changes.'
            ) -Severity 'WARN'

            # Report-only discovery is considered a successful script run.
            $ExitCode = 0
        }
        elseif ($ValidationFailures -gt 0) {
            Write-Log -Message (
                'Remote WinRM validation failed after the configuration ' +
                'phase. Review the ERROR entries above.'
            ) -Severity 'ERROR'

            $ExitCode = 1
        }
        else {
            Write-Log -Message (
                'Remote WinRM support is enabled and local validation passed.'
            ) -Severity 'SUCCESS'

            $ExitCode = 0
        }
    }
    catch {
        Write-Log -Message (
            'Runtime failure: {0}' -f
            $_.Exception.Message
        ) -Severity 'ERROR'

        Write-Log -Message (
            'Failure location: line {0}' -f
            $_.InvocationInfo.ScriptLineNumber
        ) -Severity 'ERROR'

        $ExitCode = 1
    }

    Write-Log `
        -Message "Script completed with exit code $ExitCode." `
        -Severity $(if ($ExitCode -eq 0) {
            'SUCCESS'
        }
        else {
            'ERROR'
        })

    return $ExitCode
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================

$Params = @{
    ReportOnly              = $ReportOnly
    AllowPublicProfile      = $AllowPublicProfile
    ResetPowerShellEndpoint = $ResetPowerShellEndpoint
    VerboseOutput           = $VerboseOutput
}

$Result = Enable-RemoteWinRM @Params
exit $Result