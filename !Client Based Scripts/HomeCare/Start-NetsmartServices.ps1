#Requires -Version 5.1

<#
.SYNOPSIS
    Starts and verifies Netsmart Homecare services in the required dependency order.

.DESCRIPTION
    Starts the primary NHC_Homecareservices service first, waits for it to reach the
    Running state, then starts all remaining services matching the configured service
    name pattern. The script is designed for Datto RMM execution as Local SYSTEM and
    also supports manual PowerShell execution.

.PARAMETER PrimaryServiceName
    Service name that must be running before the remaining Netsmart services start.

.PARAMETER ServiceNamePattern
    Get-Service name pattern used to discover Netsmart services.

.PARAMETER MaxAttempts
    Maximum number of start and verification attempts for each phase.

.PARAMETER RetryDelaySeconds
    Delay, in seconds, between verification attempts.

.EXAMPLE
    .\Start-NetsmartServices.ps1

.EXAMPLE
    .\Start-NetsmartServices.ps1 -MaxAttempts 5 -RetryDelaySeconds 15

.NOTES
    Script Name : Start-NetsmartServices.ps1
    Version     : v2.0.0.001
    Author      : Josh Britton
    Contributors: Josh Britton
    Modified By : Josh Britton
    Company     : Databranch
    PS Minimum  : 5.1
    Run Context : Local SYSTEM or local administrator

    Exit Codes:
      0 = Success; all discovered Netsmart services are running
      1 = Runtime failure; one or more discovered services did not reach Running
      2 = Fatal pre-flight failure; invalid input, logging initialization failure,
          insufficient permissions, or primary service not found

.CHANGELOG
    v2.0.0.001 - October 19, 2026 - Josh Britton
      - Rebuilt for Datto RMM and PowerShell 5.1 compatibility.
      - Added parameter and Datto RMM environment-variable fallback support.
      - Added Databranch structured file/stdout logging and log rotation.
      - Added bounded retry loops to prevent indefinite component execution.
      - Added primary-service dependency enforcement and final service verification.
      - Added explicit success, runtime-failure, and pre-flight exit codes.

    v1.0.0.000 - July 24, 2025 - Josh Britton
      - Original script creation.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PrimaryServiceName = $(if ($env:PrimaryServiceName) { $env:PrimaryServiceName } else { 'NHC_Homecareservices' }),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ServiceNamePattern = $(if ($env:ServiceNamePattern) { $env:ServiceNamePattern } else { 'NHC_*' }),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 20)]
    [int]$MaxAttempts = $(if ($env:MaxAttempts) { [int]$env:MaxAttempts } else { 4 }),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 600)]
    [int]$RetryDelaySeconds = $(if ($env:RetryDelaySeconds) { [int]$env:RetryDelaySeconds } else { 30 })
)

function Start-NetsmartServices {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PrimaryServiceName,

        [Parameter(Mandatory = $true)]
        [string]$ServiceNamePattern,

        [Parameter(Mandatory = $true)]
        [int]$MaxAttempts,

        [Parameter(Mandatory = $true)]
        [int]$RetryDelaySeconds
    )

    $ErrorActionPreference = 'Stop'
    $ScriptName = 'Start-NetsmartServices'
    $ScriptVersion = 'v2.0.0.001'
    $LogRoot = 'C:\Databranch\ScriptLogs'
    $LogDirectory = Join-Path -Path $LogRoot -ChildPath $ScriptName
    $LogFile = Join-Path -Path $LogDirectory -ChildPath ('{0}_{1}.log' -f $ScriptName, (Get-Date -Format 'yyyy-MM-dd'))
    $script:LoggingReady = $false

    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
            [string]$Severity = 'INFO'
        )

        $logLine = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Severity, $Message

        switch ($Severity) {
            'WARN'  { Write-Warning -Message $logLine }
            'ERROR' { Write-Output -InputObject $logLine }
            default { Write-Output -InputObject $logLine }
        }

        if ($script:LoggingReady) {
            try {
                Add-Content -LiteralPath $LogFile -Value $logLine -Encoding UTF8 -ErrorAction Stop
            }
            catch {
                Write-Warning -Message ('Unable to write to log file: {0}' -f $_.Exception.Message)
            }
        }
    }

    function Write-Console {
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG', 'PLAIN')]
            [string]$Severity = 'INFO',

            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )

        $color = switch ($Severity) {
            'INFO'    { 'Cyan' }
            'SUCCESS' { 'Green' }
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            'DEBUG'   { 'Magenta' }
            default   { 'Gray' }
        }

        $prefix = if ($Severity -eq 'PLAIN') { '' } else { '[{0}] ' -f $Severity }
        $padding = ' ' * [Math]::Max(0, $Indent)
        Write-Host ('{0}{1}{2}' -f $padding, $prefix, $Message) -ForegroundColor $color
    }

    function Initialize-Logging {
        try {
            if (-not (Test-Path -LiteralPath $LogDirectory)) {
                New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }

            $oldLogs = @(Get-ChildItem -LiteralPath $LogDirectory -Filter ('{0}_*.log' -f $ScriptName) -File -ErrorAction Stop |
                Sort-Object -Property LastWriteTime -Descending |
                Select-Object -Skip 10)

            foreach ($oldLog in $oldLogs) {
                Remove-Item -LiteralPath $oldLog.FullName -Force -ErrorAction Stop
            }

            $script:LoggingReady = $true
            return $true
        }
        catch {
            Write-Output ('{0} [ERROR] Logging initialization failed: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message)
            return $false
        }
    }

    function Test-IsAdministrator {
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity
            return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch {
            return $false
        }
    }

    function Get-ServiceCurrent {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Name
        )

        return Get-Service -Name $Name -ErrorAction Stop
    }

    function Start-ServiceWithVerification {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Name,

            [Parameter(Mandatory = $true)]
            [int]$Attempts,

            [Parameter(Mandatory = $true)]
            [int]$DelaySeconds
        )

        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            try {
                $service = Get-ServiceCurrent -Name $Name

                if ($service.Status -eq 'Running') {
                    Write-Log -Message ("[SKIPPED-CURRENT] Service '{0}' is already running." -f $Name) -Severity 'INFO'
                    Write-Console -Message ("Service '{0}' is already running." -f $Name) -Severity 'SUCCESS' -Indent 2
                    return $true
                }

                Write-Log -Message ("Attempt {0}/{1}: Starting service '{2}' from state '{3}'." -f $attempt, $Attempts, $Name, $service.Status) -Severity 'INFO'
                Write-Console -Message ("Attempt {0}/{1}: Starting '{2}'." -f $attempt, $Attempts, $Name) -Severity 'INFO' -Indent 2

                Start-Service -Name $Name -ErrorAction Stop

                $waitMilliseconds = [Math]::Max(1000, ($DelaySeconds * 1000))
                $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromMilliseconds($waitMilliseconds))
                $service.Refresh()

                if ($service.Status -eq 'Running') {
                    Write-Log -Message ("[WROTE] Service '{0}' is running." -f $Name) -Severity 'SUCCESS'
                    Write-Console -Message ("Service '{0}' started successfully." -f $Name) -Severity 'SUCCESS' -Indent 2
                    return $true
                }
            }
            catch {
                Write-Log -Message ("Attempt {0}/{1} failed for service '{2}': {3}" -f $attempt, $Attempts, $Name, $_.Exception.Message) -Severity 'WARN'
                Write-Console -Message ("Attempt {0}/{1} failed for '{2}'." -f $attempt, $Attempts, $Name) -Severity 'WARN' -Indent 2
            }

            if ($attempt -lt $Attempts) {
                Start-Sleep -Seconds $DelaySeconds
            }
        }

        Write-Log -Message ("Service '{0}' did not reach the Running state after {1} attempts." -f $Name, $Attempts) -Severity 'ERROR'
        Write-Console -Message ("Service '{0}' failed to reach Running." -f $Name) -Severity 'ERROR' -Indent 2
        return $false
    }

    if (-not (Initialize-Logging)) {
        return 2
    }

    $siteName = if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { 'UnknownSite' }
    $hostName = if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME }
    $runAs = [Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log -Message ("===== {0} {1} =====" -f $ScriptName, $ScriptVersion) -Severity 'INFO'
    Write-Log -Message ("Site     : {0}" -f $siteName) -Severity 'INFO'
    Write-Log -Message ("Hostname : {0}" -f $hostName) -Severity 'INFO'
    Write-Log -Message ("Run As   : {0}" -f $runAs) -Severity 'INFO'
    Write-Log -Message 'Mode     : SERVICE REMEDIATION' -Severity 'INFO'
    Write-Log -Message ("Log File : {0}" -f $LogFile) -Severity 'INFO'
    Write-Log -Message ("Primary Service : {0}" -f $PrimaryServiceName) -Severity 'DEBUG'
    Write-Log -Message ("Service Pattern : {0}" -f $ServiceNamePattern) -Severity 'DEBUG'
    Write-Log -Message ("Max Attempts    : {0}" -f $MaxAttempts) -Severity 'DEBUG'
    Write-Log -Message ("Retry Delay     : {0} seconds" -f $RetryDelaySeconds) -Severity 'DEBUG'

    try {
        if (-not (Test-IsAdministrator)) {
            Write-Log -Message 'Administrative rights are required to start Windows services.' -Severity 'ERROR'
            return 2
        }

        $primaryService = Get-Service -Name $PrimaryServiceName -ErrorAction SilentlyContinue
        if ($null -eq $primaryService) {
            Write-Log -Message ("Required primary service '{0}' was not found." -f $PrimaryServiceName) -Severity 'ERROR'
            return 2
        }

        $allServices = @(Get-Service -Name $ServiceNamePattern -ErrorAction SilentlyContinue)
        if ($allServices.Count -eq 0) {
            Write-Log -Message ("No services matched pattern '{0}'." -f $ServiceNamePattern) -Severity 'ERROR'
            return 2
        }

        Write-Log -Message ("Discovered {0} service(s) matching '{1}'." -f $allServices.Count, $ServiceNamePattern) -Severity 'INFO'

        Write-Log -Message ("Starting dependency service '{0}'." -f $PrimaryServiceName) -Severity 'INFO'
        if (-not (Start-ServiceWithVerification -Name $PrimaryServiceName -Attempts $MaxAttempts -DelaySeconds $RetryDelaySeconds)) {
            Write-Log -Message 'The primary service failed to start; dependent Netsmart services will not be started.' -Severity 'ERROR'
            return 1
        }

        $dependentServices = @($allServices | Where-Object { $_.Name -ne $PrimaryServiceName } | Sort-Object -Property Name)
        foreach ($service in $dependentServices) {
            [void](Start-ServiceWithVerification -Name $service.Name -Attempts $MaxAttempts -DelaySeconds $RetryDelaySeconds)
        }

        $finalServices = @(Get-Service -Name $ServiceNamePattern -ErrorAction SilentlyContinue)
        $runningServices = @($finalServices | Where-Object { $_.Status -eq 'Running' })
        $failedServices = @($finalServices | Where-Object { $_.Status -ne 'Running' })

        Write-Log -Message '===== Remediation Summary =====' -Severity 'INFO'
        Write-Log -Message ("Services discovered : {0}" -f $finalServices.Count) -Severity 'INFO'
        Write-Log -Message ("Services running    : {0}" -f $runningServices.Count) -Severity 'INFO'
        Write-Log -Message ("Services not running: {0}" -f $failedServices.Count) -Severity 'INFO'

        if ($failedServices.Count -gt 0) {
            foreach ($failedService in $failedServices) {
                Write-Log -Message ("WARNING: Service '{0}' remains in state '{1}'." -f $failedService.Name, $failedService.Status) -Severity 'WARN'
            }

            Write-Log -Message 'Netsmart service remediation completed with failures.' -Severity 'ERROR'
            return 1
        }

        Write-Log -Message 'All discovered Netsmart services are running.' -Severity 'SUCCESS'
        return 0
    }
    catch {
        Write-Log -Message ("Unhandled runtime failure: {0}" -f $_.Exception.Message) -Severity 'ERROR'
        return 1
    }
}

$invokeParams = @{
    PrimaryServiceName = $PrimaryServiceName
    ServiceNamePattern = $ServiceNamePattern
    MaxAttempts = $MaxAttempts
    RetryDelaySeconds = $RetryDelaySeconds
}

$exitCode = Start-NetsmartServices @invokeParams
exit $exitCode
