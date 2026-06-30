#Requires -Version 5.1
<#
.SYNOPSIS
    Enables or disables SMB settings required for Datto BCDR Samba share access.

.DESCRIPTION
    Configures three SMB settings on the local machine to allow or disallow
    unauthenticated guest logons and relaxes/restores security signature
    requirements — both client and server side — to support Datto BCDR
    Samba share connectivity.

    Supports both DattoRMM automated runs (via the EnableDisable environment
    variable) and manual PowerShell execution (via the -State parameter).

    Fallback chain: DattoRMM env var → -State parameter → pre-flight failure (exit 2)

.PARAMETER State
    'Enable'  — allows BCDR Samba access (insecure guest logons on, signing off).
    'Disable' — restores secure defaults (insecure guest logons off, signing on).

.EXAMPLE
    .\Set-BCDRSambaAccess.ps1 -State Enable
    .\Set-BCDRSambaAccess.ps1 -State Disable

.NOTES
    Author      : Josh Britton
    Company     : Databranch
    Version     : 1.0.0.0
    Created     : June 27, 2026
    Modified By :
    Contributors:

    .CHANGELOG
    v1.0.0.0 - June 27, 2025 - Josh
        - Initial release. Modernized from Enable_BCDR_Samba_Access.ps1 for
          DattoRMM deployment. Added standard logging, dual-output pattern,
          env var fallback, pre-flight validation, and exit codes.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Enable', 'Disable')]
    [string]$State
)

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Set-BCDRSambaAccess {
    [CmdletBinding()]
    param(
        [string]$State
    )

    $ErrorActionPreference = 'Stop'

    # --------------------------------------------------------------------------
    # CONSTANTS
    # --------------------------------------------------------------------------
    $ScriptName    = 'Set-BCDRSambaAccess'
    $ScriptVersion = '1.0.0.0'
    $LogRoot       = "C:\Databranch\ScriptLogs\$ScriptName"
    $LogFile       = Join-Path $LogRoot ("{0}_{1}.log" -f $ScriptName, (Get-Date -Format 'yyyy-MM-dd'))

    # --------------------------------------------------------------------------
    # LOGGING FUNCTIONS
    # --------------------------------------------------------------------------
    function Write-Log {
        param(
            [string]$Message  = '',
            [string]$Severity = 'INFO'
        )
        $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $line = "[$ts] [$Severity] $Message"
        switch ($Severity.ToUpper()) {
            'WARN'  { Write-Warning $line }
            'ERROR' { Write-Error   $line -ErrorAction Continue }
            default { Write-Output  $line }
        }
        Add-Content -Path $LogFile -Value $line -ErrorAction SilentlyContinue
    }

    function Write-Console {
        param(
            [string]$Message  = '',
            [string]$Severity = 'INFO',
            [int]$Indent      = 0
        )
        $colors = @{
            'INFO'    = 'Cyan'
            'SUCCESS' = 'Green'
            'WARN'    = 'Yellow'
            'ERROR'   = 'Red'
            'DEBUG'   = 'Magenta'
        }
        $color  = if ($colors.ContainsKey($Severity.ToUpper())) { $colors[$Severity.ToUpper()] } else { 'White' }
        $prefix = ' ' * $Indent
        Write-Host "$prefix[$Severity] $Message" -ForegroundColor $color
    }

    function Initialize-Logging {
        if (-not (Test-Path $LogRoot)) {
            New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
        }
        # Rotate: keep last 10 log files
        $logs = Get-ChildItem -Path $LogRoot -Filter '*.log' | Sort-Object LastWriteTime -Descending
        if ($logs.Count -ge 10) {
            $logs | Select-Object -Skip 9 | Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }

    # --------------------------------------------------------------------------
    # PRE-FLIGHT: RESOLVE STATE
    # --------------------------------------------------------------------------

    # DattoRMM env var takes priority. It may arrive as 'true'/'false' (Boolean
    # component variable) or as 'Enable'/'Disable' (Text component variable).
    if ($env:EnableDisable) {
        $raw = $env:EnableDisable.Trim().ToLower()
        switch ($raw) {
            'true'    { $State = 'Enable'  }
            'false'   { $State = 'Disable' }
            'enable'  { $State = 'Enable'  }
            'disable' { $State = 'Disable' }
            default   {
                Write-Output "[PREFLIGHT] [ERROR] Unrecognized EnableDisable value: '$($env:EnableDisable)'. Expected Enable/Disable or true/false."
                exit 2
            }
        }
    }

    if (-not $State) {
        Write-Output "[PREFLIGHT] [ERROR] State not provided. Set the EnableDisable component variable in DattoRMM or pass -State Enable/Disable manually."
        exit 2
    }

    # --------------------------------------------------------------------------
    # INITIALIZE LOGGING
    # --------------------------------------------------------------------------
    try { Initialize-Logging }
    catch {
        Write-Output "[PREFLIGHT] [ERROR] Failed to initialize log directory: $($_.Exception.Message)"
        exit 2
    }

    # --------------------------------------------------------------------------
    # LOG HEADER
    # --------------------------------------------------------------------------
    $site     = if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { 'UnknownSite' }
    $hostname = if ($env:CS_HOSTNAME)     { $env:CS_HOSTNAME }     else { $env:COMPUTERNAME }
    $runAs    = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log "===== $ScriptName v$ScriptVersion ====="
    Write-Log "Site     : $site"
    Write-Log "Hostname : $hostname"
    Write-Log "Run As   : $runAs"
    Write-Log "Mode     : $($State.ToUpper())"
    Write-Log "Log File : $LogFile"
    Write-Log "----------"

    Write-Console "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Console "Site: $site  |  Host: $hostname  |  Mode: $($State.ToUpper())" -Severity INFO

    # --------------------------------------------------------------------------
    # APPLY SMB SETTINGS
    # --------------------------------------------------------------------------
    try {
        switch ($State.ToLower()) {

            'enable' {
                Write-Log  "Enabling SMB settings for BCDR Samba access..." -Severity INFO
                Write-Console "Enabling SMB settings for BCDR Samba access..." -Severity INFO

                Write-Log  "Setting EnableInsecureGuestLogons = True" -Severity DEBUG
                Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force -ErrorAction Stop

                Write-Log  "Setting SmbClient RequireSecuritySignature = False" -Severity DEBUG
                Set-SmbClientConfiguration -RequireSecuritySignature $false -Force -ErrorAction Stop

                Write-Log  "Setting SmbServer RequireSecuritySignature = False" -Severity DEBUG
                Set-SmbServerConfiguration -RequireSecuritySignature $false -Force -ErrorAction Stop

                Write-Log  "SMB settings enabled successfully. BCDR Samba access is now permitted." -Severity SUCCESS
                Write-Console "SMB settings enabled. BCDR Samba access is now permitted." -Severity SUCCESS
            }

            'disable' {
                Write-Log  "Restoring secure SMB defaults..." -Severity INFO
                Write-Console "Restoring secure SMB defaults..." -Severity INFO

                Write-Log  "Setting EnableInsecureGuestLogons = False" -Severity DEBUG
                Set-SmbClientConfiguration -EnableInsecureGuestLogons $false -Force -ErrorAction Stop

                Write-Log  "Setting SmbClient RequireSecuritySignature = True" -Severity DEBUG
                Set-SmbClientConfiguration -RequireSecuritySignature $true -Force -ErrorAction Stop

                Write-Log  "Setting SmbServer RequireSecuritySignature = True" -Severity DEBUG
                Set-SmbServerConfiguration -RequireSecuritySignature $true -Force -ErrorAction Stop

                Write-Log  "Secure SMB defaults restored. BCDR Samba access is now blocked." -Severity SUCCESS
                Write-Console "Secure SMB defaults restored. BCDR Samba access is now blocked." -Severity SUCCESS
            }
        }
    }
    catch {
        Write-Log  "Failed to apply SMB settings ($State): $($_.Exception.Message)" -Severity ERROR
        Write-Console "Failed to apply SMB settings: $($_.Exception.Message)" -Severity ERROR
        exit 1
    }

    Write-Log  "$ScriptName completed successfully." -Severity SUCCESS
    exit 0
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$Params = @{
    State = $State
}

Set-BCDRSambaAccess @Params