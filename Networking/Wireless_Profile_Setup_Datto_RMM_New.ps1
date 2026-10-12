#Requires -Version 5.1

<#
.SYNOPSIS
    Deploys a wireless network profile to the local machine for all users.

.DESCRIPTION
    Generates a WLAN XML profile from the provided wireless SSID, authentication type,
    encryption type, and pre-shared key, then installs it system-wide using netsh.

    Supports both DattoRMM automated runs using component environment variables and
    manual execution using standard PowerShell parameters without modification.

    Temporary XML files are written to the system temp directory and cleaned up after
    each run regardless of outcome.

.PARAMETER Wireless_SSID
    Type     : String
    Required : Yes
    Default  : None
    The SSID / network name of the wireless profile to deploy.
    Also sourced from DattoRMM environment variable $env:Wireless_SSID.

.PARAMETER Wireless_Authentication
    Type     : String
    Required : Yes
    Default  : None
    The authentication method for the wireless profile, such as WPA2PSK.
    Also sourced from DattoRMM environment variable $env:Wireless_Authentication.

.PARAMETER Wireless_Encryption
    Type     : String
    Required : Yes
    Default  : None
    The encryption type for the wireless profile, such as AES.
    Also sourced from DattoRMM environment variable $env:Wireless_Encryption.

.PARAMETER Wireless_Password
    Type     : String
    Required : Yes
    Default  : None
    The pre-shared key / passphrase for the wireless network.
    Also sourced from DattoRMM environment variable $env:Wireless_Password.

.EXAMPLE
    .\Deploy-WirelessProfile.ps1 -Wireless_SSID "CorpWiFi" -Wireless_Authentication "WPA2PSK" -Wireless_Encryption "AES" -Wireless_Password "S3cur3P@ss"

.EXAMPLE
    # DattoRMM run — all parameters supplied via component environment variables.
    .\Deploy-WirelessProfile.ps1

.NOTES
    File Name      : Deploy-WirelessProfile.ps1
    Version        : v1.0.1.0
    Author         : Josh Britton
    Contributors   : Sam Kirsch, Claude AI
    Company        : Databranch
    Created        : 2025-04-06
    Last Modified  : 2026-07-27
    Modified By    : Josh Britton
    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM or Domain Admin
    DattoRMM       : Compatible
    Client Scope   : All clients

    Exit Codes:
        0 = Success — wireless profile deployed successfully
        1 = Runtime failure — script started but encountered errors during execution
        2 = Fatal pre-flight failure — missing required parameters

.CHANGELOG
    v1.0.1.0 - 2026-07-27 - Josh Britton
        - Updated all component/manual input parameters to use the Wireless_ prefix.
        - Updated DattoRMM environment variable references to match component variable names.
        - Updated script metadata to align with Databranch Script Library standards.
        - Added top-level CmdletBinding and param block for manual PowerShell execution.
        - Updated missing-parameter handling to use exit code 2 for fatal pre-flight failure.

    v1.0.0.0 - 2025-04-06 - Josh Britton
        - Initial release. Modernized from inline Deploy-WirelessProfile function.
        - Added DattoRMM environment variable fallback for all parameters.
        - Added Write-Log / Write-Console dual-output pattern.
        - Added log rotation with 10-file retention, structured log header, and exit codes.
        - Wrapped Convert-StringToHex as internal helper function.
#>

[CmdletBinding()]
param (
    # DattoRMM env var: $env:Wireless_SSID
    [Parameter(Mandatory = $false)]
    [string]$Wireless_SSID = $env:Wireless_SSID,

    # DattoRMM env var: $env:Wireless_Authentication
    [Parameter(Mandatory = $false)]
    [string]$Wireless_Authentication = $env:Wireless_Authentication,

    # DattoRMM env var: $env:Wireless_Encryption
    [Parameter(Mandatory = $false)]
    [string]$Wireless_Encryption = $env:Wireless_Encryption,

    # DattoRMM env var: $env:Wireless_Password
    [Parameter(Mandatory = $false)]
    [string]$Wireless_Password = $env:Wireless_Password
)

function Deploy-WirelessProfile {

    param (
        # DattoRMM env var: $env:Wireless_SSID
        [Parameter(Mandatory = $false)]
        [string]$Wireless_SSID = $env:Wireless_SSID,

        # DattoRMM env var: $env:Wireless_Authentication
        [Parameter(Mandatory = $false)]
        [string]$Wireless_Authentication = $env:Wireless_Authentication,

        # DattoRMM env var: $env:Wireless_Encryption
        [Parameter(Mandatory = $false)]
        [string]$Wireless_Encryption = $env:Wireless_Encryption,

        # DattoRMM env var: $env:Wireless_Password
        [Parameter(Mandatory = $false)]
        [string]$Wireless_Password = $env:Wireless_Password
    )

    $ErrorActionPreference = 'Stop'
    $ScriptName    = 'Deploy-WirelessProfile'
    $ScriptVersion = 'v1.0.1.0'

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

        # Always write to stdout / warning stream for DattoRMM capture
        if ($Severity -eq 'ERROR' -or $Severity -eq 'WARN') {
            Write-Warning $entry
        }
        else {
            Write-Output $entry
        }

        # Always write to log file when initialized
        if ($script:LogFile) {
            Add-Content -Path $script:LogFile -Value $entry -Encoding UTF8
        }
    }

    function Initialize-Logging {
        $logRoot = "C:\Databranch\ScriptLogs\$ScriptName"
        $logDate = Get-Date -Format 'yyyy-MM-dd'
        $script:LogFile = Join-Path -Path $logRoot -ChildPath "${ScriptName}_${logDate}.log"

        if (-not (Test-Path -Path $logRoot)) {
            New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        }

        # Rotate logs — keep last 10 log files
        $existingLogs = Get-ChildItem -Path $logRoot -Filter "*.log" |
                        Sort-Object -Property LastWriteTime -Descending

        if ($existingLogs.Count -ge 10) {
            $existingLogs | Select-Object -Skip 9 | Remove-Item -Force
        }
    }

    # endregion

    # -------------------------------------------------------------------------
    # region: Console Output
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
        param (
            [Parameter(Mandatory)]
            [string]$Text
        )

        Write-Host ''
        Write-Host ('=' * 60) -ForegroundColor DarkGray
        Write-Host "  $Text" -ForegroundColor White
        Write-Host ('=' * 60) -ForegroundColor DarkGray
        Write-Host ''
    }

    function Write-Section {
        param (
            [Parameter(Mandatory)]
            [string]$Title
        )

        Write-Host ''
        Write-Host "---- $Title " -NoNewline -ForegroundColor DarkCyan

        $lineLength = 44 - $Title.Length
        if ($lineLength -lt 1) {
            $lineLength = 1
        }

        Write-Host ('-' * $lineLength) -ForegroundColor DarkGray
    }

    function Write-Separator {
        Write-Host ('-' * 60) -ForegroundColor DarkGray
    }

    # endregion

    # -------------------------------------------------------------------------
    # region: Helper Functions
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

    function Convert-ToXmlEscapedString {
        param (
            [Parameter(Mandatory)]
            [string]$InputString
        )

        return $InputString.Replace('&', '&amp;').
                            Replace('<', '&lt;').
                            Replace('>', '&gt;').
                            Replace('"', '&quot;').
                            Replace("'", '&apos;')
    }

    # endregion

    # =========================================================================
    # Script Entry
    # =========================================================================

    Initialize-Logging

    $site = if ($env:CS_PROFILE_NAME) {
        $env:CS_PROFILE_NAME
    }
    else {
        'UnknownSite'
    }

    $hostname = if ($env:CS_HOSTNAME) {
        $env:CS_HOSTNAME
    }
    else {
        $env:COMPUTERNAME
    }

    $runAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Banner "$ScriptName $ScriptVersion"

    Write-Console "Site     : $site" -Severity PLAIN
    Write-Console "Hostname : $hostname" -Severity PLAIN
    Write-Console "Run As   : $runAs" -Severity PLAIN
    Write-Console "Log File : $script:LogFile" -Severity PLAIN
    Write-Separator

    # Standard log header
    Add-Content -Path $script:LogFile -Encoding UTF8 -Value @"
===== $ScriptName $ScriptVersion =====
Site     : $site
Hostname : $hostname
Run As   : $runAs
Mode     : WRITE MODE
Params   : Wireless_SSID=$Wireless_SSID | Wireless_Authentication=$Wireless_Authentication | Wireless_Encryption=$Wireless_Encryption
Log File : $($script:LogFile)
"@

    # -------------------------------------------------------------------------
    # region: Parameter Validation
    # -------------------------------------------------------------------------

    Write-Section "Parameter Validation"

    $missingParams = @()

    if ([string]::IsNullOrWhiteSpace($Wireless_SSID)) {
        $missingParams += 'Wireless_SSID'
    }

    if ([string]::IsNullOrWhiteSpace($Wireless_Authentication)) {
        $missingParams += 'Wireless_Authentication'
    }

    if ([string]::IsNullOrWhiteSpace($Wireless_Encryption)) {
        $missingParams += 'Wireless_Encryption'
    }

    if ([string]::IsNullOrWhiteSpace($Wireless_Password)) {
        $missingParams += 'Wireless_Password'
    }

    if ($missingParams.Count -gt 0) {
        $missingList = $missingParams -join ', '

        Write-Log     "Missing required parameters: $missingList" -Severity ERROR
        Write-Console "Missing required parameters: $missingList" -Severity ERROR
        Write-Console "Provide values via PowerShell parameters or DattoRMM environment variables." -Severity WARN

        Write-Banner "SCRIPT FAILED"
        exit 2
    }

    Write-Log     "All required parameters present." -Severity INFO
    Write-Console "All required parameters present." -Severity INFO

    # Do not log Wireless_Password.
    Write-Log     "Wireless_SSID=$Wireless_SSID | Wireless_Authentication=$Wireless_Authentication | Wireless_Encryption=$Wireless_Encryption" -Severity DEBUG
    Write-Console "SSID=$Wireless_SSID | Auth=$Wireless_Authentication | Enc=$Wireless_Encryption" -Severity DEBUG -Indent 1

    # endregion

    # -------------------------------------------------------------------------
    # region: Build Wireless Profile XML
    # -------------------------------------------------------------------------

    Write-Section "Building Wireless Profile"

    try {
        $SSIDHEX         = Convert-StringToHex -InputString $Wireless_SSID
        $encodedPassword = Convert-ToXmlEscapedString -InputString $Wireless_Password
        $encodedSSID     = Convert-ToXmlEscapedString -InputString $Wireless_SSID

        Write-Log     "SSID hex encoded: $SSIDHEX" -Severity DEBUG
        Write-Console "SSID hex encoded: $SSIDHEX" -Severity DEBUG -Indent 1

        $profileXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$encodedSSID</name>
    <SSIDConfig>
        <SSID>
            <hex>$SSIDHEX</hex>
            <name>$encodedSSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>$Wireless_Authentication</authentication>
                <encryption>$Wireless_Encryption</encryption>
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
    }
    catch {
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
        $netshExitCode = $LASTEXITCODE

        Write-Log     "netsh output: $netshOutput" -Severity DEBUG
        Write-Console "netsh: $netshOutput" -Severity DEBUG -Indent 1

        if ($netshExitCode -ne 0) {
            throw "netsh wlan add profile failed with exit code $netshExitCode. Output: $netshOutput"
        }

        Write-Log     "Wireless profile '$Wireless_SSID' deployed successfully." -Severity SUCCESS
        Write-Console "Wireless profile '$Wireless_SSID' deployed successfully." -Severity SUCCESS
    }
    catch {
        Write-Log     "Failed to deploy wireless profile '$Wireless_SSID': $_" -Severity ERROR
        Write-Console "Failed to deploy wireless profile '$Wireless_SSID': $_" -Severity ERROR

        Write-Banner "SCRIPT FAILED"
        exit 1
    }
    finally {
        # Always clean up the temp file
        if (Test-Path -Path $tempFile) {
            Remove-Item -Path $tempFile -Force

            Write-Log     "Temp file removed: $tempFile" -Severity DEBUG
            Write-Console "Temp file cleaned up." -Severity DEBUG -Indent 1
        }

        # Clear secret value from script variable after use.
        $Wireless_Password = $null
        $encodedPassword   = $null
    }

    # endregion

    Write-Banner "COMPLETED SUCCESSFULLY"
    exit 0
}

# =============================================================================
# Entry Point
# =============================================================================

$Params = @{}

# Only pass parameters explicitly if they were provided or resolved from DattoRMM
# environment variables. Function-level fallback remains available as a safeguard.
if ($Wireless_SSID) {
    $Params['Wireless_SSID'] = $Wireless_SSID
}

if ($Wireless_Authentication) {
    $Params['Wireless_Authentication'] = $Wireless_Authentication
}

if ($Wireless_Encryption) {
    $Params['Wireless_Encryption'] = $Wireless_Encryption
}

if ($Wireless_Password) {
    $Params['Wireless_Password'] = $Wireless_Password
}

Deploy-WirelessProfile @Params