#Requires -Version 5.1

<#
.SYNOPSIS
    Detects and optionally removes an MSI-based software package by product code.

.DESCRIPTION
    Designed for Datto RMM or manual execution. The MSI product code is resolved
    from the Datto RMM environment variable MSIProductID first, then the manual
    -MSIProductID parameter. The script validates the GUID, checks both 64-bit and
    32-bit uninstall registry locations, optionally runs a silent uninstall, and
    verifies the package is no longer registered.

.PARAMETER MSIProductID
    MSI product code in GUID format, including or excluding braces.

.PARAMETER ReportOnly
    Safe-by-default write gate. Only the literal value "false" permits uninstall.
    Datto RMM Boolean variables are received as strings.

.PARAMETER VerboseOutput
    Controls per-item detail messages. Defaults to true.

.EXAMPLE
    .\Remove-MsiSoftware.ps1 -MSIProductID '{12345678-1234-1234-1234-1234567890AB}'

.EXAMPLE
    .\Remove-MsiSoftware.ps1 -MSIProductID '{12345678-1234-1234-1234-1234567890AB}' -ReportOnly false

.NOTES
    Script Name : Remove-MsiSoftware.ps1
    Version     : v1.0.0.001
    Author      : Josh Britton
    Company     : Databranch
    PS Minimum  : 5.1
    Run Context : SYSTEM or local administrator

    Exit Codes:
      0 = Success, already absent, report-only detection, or uninstall completed
      1 = Runtime failure or MSI uninstall failure
      2 = Fatal pre-flight failure
      3 = Uninstall completed and reboot is required

.CHANGELOG
    v1.0.0.001 - 2026-10-13 - Josh Britton
      - Initial Datto RMM component script.
      - Added product-code validation, registry detection, report-only mode,
        silent MSI removal, log rotation, explicit exit codes, and verification.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$MSIProductID,

    [Parameter(Mandatory = $false)]
    [string]$ReportOnly,

    [Parameter(Mandatory = $false)]
    [string]$VerboseOutput
)

function Remove-MsiSoftware {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$MSIProductID,

        [Parameter(Mandatory = $false)]
        [string]$ReportOnly,

        [Parameter(Mandatory = $false)]
        [string]$VerboseOutput
    )

    $ErrorActionPreference = 'Stop'
    $ScriptName = 'Remove-MsiSoftware'
    $ScriptVersion = 'v1.0.0.001'
    $LogRoot = 'C:\Databranch\ScriptLogs'
    $LogDirectory = Join-Path -Path $LogRoot -ChildPath $ScriptName
    $LogFile = Join-Path -Path $LogDirectory -ChildPath ('{0}_{1}.log' -f $ScriptName, (Get-Date -Format 'yyyy-MM-dd'))

    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
            [string]$Severity = 'INFO'
        )

        $Line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Severity, $Message
        try { Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8 -ErrorAction Stop } catch { }

        switch ($Severity) {
            'WARN'  { Write-Warning $Line }
            'ERROR' { Write-Output $Line }
            default { Write-Output $Line }
        }
    }

    function Write-Console {
        param (
            [string]$Message = '',
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG', 'PLAIN')]
            [string]$Severity = 'INFO',
            [int]$Indent = 0
        )

        $Color = switch ($Severity) {
            'INFO'    { 'Cyan' }
            'SUCCESS' { 'Green' }
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            'DEBUG'   { 'Magenta' }
            default   { 'Gray' }
        }
        Write-Host (('{0}{1}' -f (' ' * $Indent), $Message)) -ForegroundColor $Color
    }

    function Initialize-Logging {
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }

        Get-ChildItem -LiteralPath $LogDirectory -Filter ($ScriptName + '_*.log') -File -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -Skip 10 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    function Get-MsiRegistryEntry {
        param (
            [Parameter(Mandatory = $true)]
            [string]$ProductCode
        )

        $RegistryPaths = @(
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )

        foreach ($RegistryPath in $RegistryPaths) {
            $ProductPath = Join-Path -Path $RegistryPath -ChildPath $ProductCode
            if (Test-Path -LiteralPath $ProductPath) {
                return Get-ItemProperty -LiteralPath $ProductPath -ErrorAction Stop
            }
        }

        return $null
    }

    $ResolvedProductID = if (-not [string]::IsNullOrWhiteSpace($env:MSIProductID)) {
        $env:MSIProductID
    }
    elseif (-not [string]::IsNullOrWhiteSpace($MSIProductID)) {
        $MSIProductID
    }
    else {
        $null
    }

    $ResolvedReportOnly = if (-not [string]::IsNullOrWhiteSpace($env:ReportOnly)) {
        $env:ReportOnly
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ReportOnly)) {
        $ReportOnly
    }
    else {
        'true'
    }

    $ResolvedVerboseOutput = if (-not [string]::IsNullOrWhiteSpace($env:VerboseOutput)) {
        $env:VerboseOutput
    }
    elseif (-not [string]::IsNullOrWhiteSpace($VerboseOutput)) {
        $VerboseOutput
    }
    else {
        'true'
    }

    $IsReportOnly = ($ResolvedReportOnly.Trim().ToLower() -ne 'false')
    $IsVerbose = ($ResolvedVerboseOutput.Trim().ToLower() -eq 'true')
    $ModeDisplay = if ($IsReportOnly) { 'REPORT-ONLY (no changes made)' } else { 'WRITE MODE (changes committed)' }

    function Write-VerboseLog {
        param (
            [string]$Message = '',
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
            [string]$Severity = 'INFO',
            [int]$Indent = 0
        )
        if (-not $IsVerbose) { return }
        Write-Log -Message $Message -Severity $Severity
        Write-Console -Message $Message -Severity $Severity -Indent $Indent
    }

    try {
        Initialize-Logging
    }
    catch {
        Write-Output "Fatal pre-flight failure: unable to initialize logging. $($_.Exception.Message)"
        return 2
    }

    $SiteName = if ([string]::IsNullOrWhiteSpace($env:CS_PROFILE_NAME)) { 'UnknownSite' } else { $env:CS_PROFILE_NAME }
    $HostName = if ([string]::IsNullOrWhiteSpace($env:CS_HOSTNAME)) { $env:COMPUTERNAME } else { $env:CS_HOSTNAME }
    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log -Message ('===== {0} {1} =====' -f $ScriptName, $ScriptVersion) -Severity INFO
    Write-Log -Message ('Site     : {0}' -f $SiteName) -Severity INFO
    Write-Log -Message ('Hostname : {0}' -f $HostName) -Severity INFO
    Write-Log -Message ('Run As   : {0}' -f $RunAs) -Severity INFO
    Write-Log -Message ('Mode     : {0}' -f $ModeDisplay) -Severity INFO
    Write-Log -Message ('Log File : {0}' -f $LogFile) -Severity INFO

    if ([string]::IsNullOrWhiteSpace($ResolvedProductID)) {
        Write-Log -Message 'MSIProductID was not supplied by Datto RMM or as a PowerShell parameter.' -Severity ERROR
        return 2
    }

    $GuidValue = [guid]::Empty
    $TrimmedProductID = $ResolvedProductID.Trim().Trim('{', '}')
    if (-not [guid]::TryParse($TrimmedProductID, [ref]$GuidValue)) {
        Write-Log -Message ('MSIProductID is not a valid GUID: {0}' -f $ResolvedProductID) -Severity ERROR
        return 2
    }

    $ProductCode = '{{{0}}}' -f $GuidValue.ToString().ToUpperInvariant()
    Write-VerboseLog -Message ('Normalized MSI product code: {0}' -f $ProductCode) -Severity DEBUG

    try {
        $InstalledApp = Get-MsiRegistryEntry -ProductCode $ProductCode
        if ($null -eq $InstalledApp) {
            Write-Log -Message ('[SKIPPED-CURRENT] MSI package {0} is already absent.' -f $ProductCode) -Severity SUCCESS
            return 0
        }

        $DisplayName = if ([string]::IsNullOrWhiteSpace($InstalledApp.DisplayName)) { 'Unknown MSI package' } else { $InstalledApp.DisplayName }
        $DisplayVersion = if ([string]::IsNullOrWhiteSpace($InstalledApp.DisplayVersion)) { 'Unknown' } else { $InstalledApp.DisplayVersion }
        Write-Log -Message ('Detected: {0} | Version: {1} | Product Code: {2}' -f $DisplayName, $DisplayVersion, $ProductCode) -Severity INFO

        if ($IsReportOnly) {
            Write-Log -Message ('[SKIPPED-REPORT] Would silently uninstall {0} ({1}).' -f $DisplayName, $ProductCode) -Severity INFO
            return 0
        }

        $MsiArguments = @(
            '/x'
            $ProductCode
            '/qn'
            '/norestart'
            '/L*v'
            ('"{0}"' -f (Join-Path -Path $LogDirectory -ChildPath ($ScriptName + '_MSI.log')))
        )

        Write-Log -Message ('Starting silent uninstall of {0}.' -f $DisplayName) -Severity INFO
        $ProcessParams = @{
            FilePath     = "$env:SystemRoot\System32\msiexec.exe"
            ArgumentList = $MsiArguments
            Wait         = $true
            PassThru     = $true
            WindowStyle  = 'Hidden'
            ErrorAction  = 'Stop'
        }
        $Process = Start-Process @ProcessParams
        $MsiExitCode = $Process.ExitCode
        Write-Log -Message ('msiexec returned exit code {0}.' -f $MsiExitCode) -Severity INFO

        if ($MsiExitCode -notin @(0, 1605, 1614, 1641, 3010)) {
            Write-Log -Message ('MSI uninstall failed with exit code {0}. Review the MSI log: {1}' -f $MsiExitCode, (Join-Path -Path $LogDirectory -ChildPath ($ScriptName + '_MSI.log'))) -Severity ERROR
            return 1
        }

        $RemainingApp = Get-MsiRegistryEntry -ProductCode $ProductCode
        if ($null -ne $RemainingApp -and $MsiExitCode -notin @(1641, 3010)) {
            Write-Log -Message ('Uninstall command completed, but {0} remains registered.' -f $DisplayName) -Severity ERROR
            return 1
        }

        if ($MsiExitCode -in @(1641, 3010)) {
            Write-Log -Message ('[WROTE] Uninstall completed for {0}; a reboot is required.' -f $DisplayName) -Severity WARN
            Write-Log -Message 'WARNING: Reboot required to complete MSI removal.' -Severity WARN
            return 3
        }

        Write-Log -Message ('[WROTE] Successfully removed {0} ({1}).' -f $DisplayName, $ProductCode) -Severity SUCCESS
        return 0
    }
    catch {
        Write-Log -Message ('Runtime failure: {0}' -f $_.Exception.Message) -Severity ERROR
        return 1
    }
}

$Params = @{
    MSIProductID = $MSIProductID
    ReportOnly = $ReportOnly
    VerboseOutput = $VerboseOutput
}

$ExitCode = Remove-MsiSoftware @Params
exit $ExitCode
