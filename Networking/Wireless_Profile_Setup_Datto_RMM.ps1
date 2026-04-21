#Requires -Version 5.1

<#
.SYNOPSIS
    Deploys a wireless network profile to the local machine for all users.

.DESCRIPTION
    Generates a WLAN XML profile from the provided SSID, authentication type,
    encryption type, and pre-shared key, then installs it system-wide using
    netsh. Supports both DattoRMM automated runs (environment variable input)
    and manual execution (standard PowerShell parameters) without modification.

    Temporary XML files are written to the system temp directory and cleaned up
    after each run regardless of outcome.

.PARAMETER SSID
    Type     : String
    Required : Yes
    Default  : None
    The SSID (network name) of the wireless profile to deploy.
    Also sourced from DattoRMM environment variable $env:SSID.

.PARAMETER Authentication
    Type     : String
    Required : Yes
    Default  : None
    The authentication method for the wireless profile (e.g. WPA2PSK).
    Also sourced from DattoRMM environment variable $env:Authentication.

.PARAMETER Encryption
    Type     : String
    Required : Yes
    Default  : None
    The encryption type for the wireless profile (e.g. AES).
    Also sourced from DattoRMM environment variable $env:Encryption.

.PARAMETER Password
    Type     : String
    Required : Yes
    Default  : None
    The pre-shared key / passphrase for the wireless network.
    Also sourced from DattoRMM environment variable $env:WifiPassword.

.EXAMPLE
    .\Deploy-WirelessProfile.ps1 -SSID "CorpWiFi" -Authentication "WPA2PSK" -Encryption "AES" -Password "S3cur3P@ss"

.EXAMPLE
    # DattoRMM run — all parameters supplied via component environment variables.
    .\Deploy-WirelessProfile.ps1

.NOTES
    File Name      : Deploy-WirelessProfile.ps1
    Version        : 1.0.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2025-04-06
    Last Modified  : 2025-04-06
    Modified By    : Sam Kirsch
    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM or Domain Admin
    DattoRMM       : Compatible
    Client Scope   : All clients
    Exit Codes     :
        0 = Success — wireless profile deployed successfully
        1 = Failure — missing parameters or netsh deployment error

.CHANGELOG
    v1.0.0.0 - 2025-04-06 - Sam Kirsch
        - Initial release. Modernized from inline Deploy-WirelessProfile function.
        - Added DattoRMM environment variable fallback for all parameters.
        - Added Write-Log / Write-Console dual-output pattern.
        - Added log rotation (10 files), structured log header, exit codes.
        - Wrapped Convert-StringToHex as internal helper function.
#>

function Deploy-WirelessProfile {

    param (
        # DattoRMM env var: $env:SSID
        [Parameter(Mandatory = $false)]
        [string]$SSID = $env:SSID,

        # DattoRMM env var: $env:Authentication
        [Parameter(Mandatory = $false)]
        [string]$Authentication = $env:Authentication,

        # DattoRMM env var: $env:Encryption
        [Parameter(Mandatory = $false)]
        [string]$Encryption = $env:Encryption,

        # DattoRMM env var: $env:WifiPassword
        [Parameter(Mandatory = $false)]
        [string]$Password = $env:Password
    )

    $ErrorActionPreference = 'Stop'
    $ScriptName    = 'Deploy-WirelessProfile'
    $ScriptVersion = '1.0.0.0'

    # -------------------------------------------------------------------------
    # region: Logging Infrastructure
    # -------------------------------------------------------------------------

    function Write-Log {
        param (
            [Parameter(Mandatory)]
            [string]$Message,

            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
            [string]$Severity = 'INFO'
        )

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $entry     = "[$timestamp][$Severity] $Message"

        # Always write to stdout (captured by DattoRMM)
        if ($Severity -eq 'ERROR' -or $Severity -eq 'WARN') {
            Write-Warning $entry
        } else {
            Write-Output $entry
        }

        # Always write to log file
        if ($script:LogFile) {
            Add-Content -Path $script:LogFile -Value $entry -Encoding UTF8
        }
    }

    function Initialize-Logging {
        $logRoot   = "C:\Databranch\ScriptLogs\$ScriptName"
        $logDate   = Get-Date -Format 'yyyy-MM-dd'
        $script:LogFile = Join-Path -Path $logRoot -ChildPath "${ScriptName}_${logDate}.log"

        if (-not (Test-Path -Path $logRoot)) {
            New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        }

        # Rotate — keep last 10 log files
        $existingLogs = Get-ChildItem -Path $logRoot -Filter "*.log" |
                        Sort-Object -Property LastWriteTime -Descending
        if ($existingLogs.Count -ge 10) {
            $existingLogs | Select-Object -Skip 9 | Remove-Item -Force
        }
    }

    # endregion

    # -------------------------------------------------------------------------
    # region: Console Output (display stream — suppressed in DattoRMM)
    # -------------------------------------------------------------------------

    function Write-Console {
        param (
            [string]$Message,
            [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'DEBUG', 'PLAIN')]
            [string]$Severity = 'INFO',
            [int]$Indent = 0
        )

        $colorMap = @{
            INFO    = 'Cyan'
            SUCCESS = 'Green'
            WARN    = 'Yellow'
            ERROR   = 'Red'
            DEBUG   = 'Magenta'
            PLAIN   = 'Gray'
        }

        $prefix = if ($Severity -ne 'PLAIN') { "[$Severity] " } else { '' }
        $pad    = if ($Indent -gt 0) { '  ' * $Indent } else { '' }

        Write-Host "$pad$prefix$Message" -ForegroundColor $colorMap[$Severity]
    }

    function Write-Banner {
        param ([string]$Text)
        Write-Host ''
        Write-Host ('=' * 60) -ForegroundColor DarkGray
        Write-Host "  $Text" -ForegroundColor White
        Write-Host ('=' * 60) -ForegroundColor DarkGray
        Write-Host ''
    }

    function Write-Section {
        param ([string]$Title)
        Write-Host ''
        Write-Host "---- $Title " -NoNewline -ForegroundColor DarkCyan
        Write-Host ('-' * (44 - $Title.Length)) -ForegroundColor DarkGray
    }

    function Write-Separator {
        Write-Host ('-' * 60) -ForegroundColor DarkGray
    }

    # endregion

    # -------------------------------------------------------------------------
    # region: Helper — Convert string to hex
    # -------------------------------------------------------------------------

    function Convert-StringToHex {
        param (
            [Parameter(Mandatory)]
            [string]$InputString
        )

        $hex = ($InputString.ToCharArray() | ForEach-Object {
            [System.Text.Encoding]::UTF8.GetBytes($_) | ForEach-Object {
                '{0:X2}' -f $_
            }
        }) -join ''

        return $hex
    }

    # endregion

    # =========================================================================
    # Script Entry
    # =========================================================================

    Initialize-Logging

    $site     = if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { 'UnknownSite' }
    $hostname = if ($env:CS_HOSTNAME)     { $env:CS_HOSTNAME }     else { $env:COMPUTERNAME }
    $runAs    = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Banner "$ScriptName v$ScriptVersion"

    Write-Console "Site     : $site"     -Severity PLAIN
    Write-Console "Hostname : $hostname" -Severity PLAIN
    Write-Console "Run As   : $runAs"    -Severity PLAIN
    Write-Console "Log File : $script:LogFile" -Severity PLAIN
    Write-Separator

    # Log header
    Add-Content -Path $script:LogFile -Encoding UTF8 -Value @"
===== $ScriptName v$ScriptVersion =====
Site     : $site
Hostname : $hostname
Run As   : $runAs
Params   : SSID=$SSID | Authentication=$Authentication | Encryption=$Encryption
Log File : $($script:LogFile)
"@

    # -------------------------------------------------------------------------
    # region: Parameter Validation
    # -------------------------------------------------------------------------

    Write-Section "Parameter Validation"

    $missingParams = @()
    if ([string]::IsNullOrWhiteSpace($SSID))           { $missingParams += 'SSID' }
    if ([string]::IsNullOrWhiteSpace($Authentication)) { $missingParams += 'Authentication' }
    if ([string]::IsNullOrWhiteSpace($Encryption))     { $missingParams += 'Encryption' }
    if ([string]::IsNullOrWhiteSpace($Password))       { $missingParams += 'Password' }

    if ($missingParams.Count -gt 0) {
        $missingList = $missingParams -join ', '

        Write-Log     "Missing required parameters: $missingList" -Severity ERROR
        Write-Console "Missing required parameters: $missingList" -Severity ERROR
        Write-Console "Provide values via PowerShell parameters or DattoRMM environment variables." -Severity WARN

        Write-Banner "SCRIPT FAILED"
        exit 1
    }

    Write-Log     "All required parameters present." -Severity INFO
    Write-Console "All required parameters present." -Severity INFO
    Write-Log     "SSID=$SSID | Authentication=$Authentication | Encryption=$Encryption" -Severity DEBUG
    Write-Console "SSID=$SSID | Auth=$Authentication | Enc=$Encryption" -Severity DEBUG -Indent 1

    # endregion

    # -------------------------------------------------------------------------
    # region: Build Wireless Profile XML
    # -------------------------------------------------------------------------

    Write-Section "Building Wireless Profile"

    try {
        $SSIDHEX         = Convert-StringToHex -InputString $SSID
        $encodedPassword = $Password.Replace('&',  '&amp;').Replace('<',  '&lt;').Replace('>',  '&gt;').Replace('"',  '&quot;').Replace("'",  '&apos;')

        Write-Log     "SSID hex encoded: $SSIDHEX" -Severity DEBUG
        Write-Console "SSID hex encoded: $SSIDHEX"  -Severity DEBUG -Indent 1

        $profileXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$SSID</name>
    <SSIDConfig>
        <SSID>
            <hex>$SSIDHEX</hex>
            <name>$SSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>$Authentication</authentication>
                <encryption>$Encryption</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$encodedPassword</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

        Write-Log     "Wireless profile XML built successfully." -Severity SUCCESS
        Write-Console "Wireless profile XML built successfully." -Severity SUCCESS

    } catch {
        Write-Log     "Failed to build profile XML: $_" -Severity ERROR
        Write-Console "Failed to build profile XML: $_" -Severity ERROR

        Write-Banner "SCRIPT FAILED"
        exit 1
    }

    # endregion

    # -------------------------------------------------------------------------
    # region: Deploy Wireless Profile
    # -------------------------------------------------------------------------

    Write-Section "Deploying Wireless Profile"

    $tempFile = [System.IO.Path]::GetTempFileName().Replace('.tmp', '.xml')

    try {
        # Write XML to temp file
        $profileXml | Out-File -FilePath $tempFile -Encoding UTF8

        Write-Log     "Temp profile file written: $tempFile" -Severity DEBUG
        Write-Console "Temp profile file written: $tempFile" -Severity DEBUG -Indent 1

        # Deploy via netsh
        $netshOutput = netsh wlan add profile filename="$tempFile" user=all 2>&1

        Write-Log     "netsh output: $netshOutput" -Severity DEBUG
        Write-Console "netsh: $netshOutput"         -Severity DEBUG -Indent 1

        Write-Log     "Wireless profile '$SSID' deployed successfully." -Severity SUCCESS
        Write-Console "Wireless profile '$SSID' deployed successfully." -Severity SUCCESS

    } catch {
        Write-Log     "Failed to deploy wireless profile '$SSID': $_" -Severity ERROR
        Write-Console "Failed to deploy wireless profile '$SSID': $_" -Severity ERROR

        Write-Banner "SCRIPT FAILED"
        exit 1

    } finally {
        # Always clean up the temp file
        if (Test-Path -Path $tempFile) {
            Remove-Item -Path $tempFile -Force
            Write-Log     "Temp file removed: $tempFile" -Severity DEBUG
            Write-Console "Temp file cleaned up."         -Severity DEBUG -Indent 1
        }
    }

    # endregion

    Write-Banner "COMPLETED SUCCESSFULLY"
    exit 0
}

# =============================================================================
# Entry Point
# =============================================================================

$Params = @{}

# Only pass parameters explicitly if they were provided on the command line.
# DattoRMM env var fallback is handled inside the function via param defaults.
if ($SSID)           { $Params['SSID']           = $SSID }
if ($Authentication) { $Params['Authentication'] = $Authentication }
if ($Encryption)     { $Params['Encryption']     = $Encryption }
if ($Password)       { $Params['Password']       = $Password }

Deploy-WirelessProfile @Params