#Requires -Version 5.1

<#
.SYNOPSIS
    Checks the Active Directory krbtgt account password age for Datto RMM monitoring.

.DESCRIPTION
    Locates the krbtgt account in the current Active Directory domain by using ADSI,
    converts pwdLastSet from Windows FILETIME, and compares it with a configurable
    maximum age. The monitor fails when the password was set before the calendar-based
    cutoff date.

.PARAMETER MaxPasswordAgeYears
    Maximum permitted password age in calendar years. Datto RMM environment variable
    MaxPasswordAgeYears takes precedence. Default: 1.

.EXAMPLE
    .\Test-KrbtgtPasswordAge.ps1

.EXAMPLE
    .\Test-KrbtgtPasswordAge.ps1 -MaxPasswordAgeYears '2'

.NOTES
    File Name    : Test-KrbtgtPasswordAge.ps1
    Author       : Josh Britton
    Company      : Databranch
    Version      : v1.0.0.001
    Requires     : Windows PowerShell 5.1, domain connectivity, and read access to AD
    Run Context  : Datto RMM SYSTEM or an authorized domain account

    Exit Codes:
      0 = Monitor passed; krbtgt password age is within the configured limit
      1 = Monitor failed; krbtgt password is older than the configured limit
      2 = Fatal/pre-flight failure; the script could not complete the check

.CHANGELOG
    v1.0.0.001 - 2026-09-22 - Josh Britton
      - Initial release.
      - Added ADSI-based krbtgt lookup with no ActiveDirectory module dependency.
      - Added Datto RMM/manual parameter fallback, structured logging, and log rotation.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$MaxPasswordAgeYears = $(
        if (-not [string]::IsNullOrWhiteSpace($env:MaxPasswordAgeYears)) {
            $env:MaxPasswordAgeYears
        }
        else {
            '1'
        }
    )
)

function Test-KrbtgtPasswordAge {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MaxPasswordAgeYears
    )

    $ErrorActionPreference = 'Stop'

    $ScriptName    = 'Test-KrbtgtPasswordAge'
    $ScriptVersion = 'v1.0.0.001'
    $LogRoot       = 'C:\Databranch\ScriptLogs'
    $LogDirectory  = Join-Path -Path $LogRoot -ChildPath $ScriptName
    $LogFile       = Join-Path -Path $LogDirectory -ChildPath ('{0}_{1}.log' -f $ScriptName, (Get-Date -Format 'yyyy-MM-dd'))

    function Initialize-Logging {
        [CmdletBinding()]
        param ()

        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }

        $OldLogs = Get-ChildItem -LiteralPath $LogDirectory -Filter '*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -Skip 10

        foreach ($OldLog in $OldLogs) {
            Remove-Item -LiteralPath $OldLog.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    function Write-Log {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'SUCCESS', 'DEBUG', 'WARN', 'ERROR')]
            [string]$Severity = 'INFO'
        )

        $LogLine = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Severity, $Message
        Add-Content -LiteralPath $LogFile -Value $LogLine -Encoding UTF8

        switch ($Severity) {
            'WARN'  { Write-Warning -Message $LogLine }
            'ERROR' { Write-Output -InputObject $LogLine }
            default { Write-Output -InputObject $LogLine }
        }
    }

    function Write-Console {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'SUCCESS', 'DEBUG', 'WARN', 'ERROR', 'PLAIN')]
            [string]$Severity = 'INFO'
        )

        $Color = switch ($Severity) {
            'INFO'    { 'Cyan' }
            'SUCCESS' { 'Green' }
            'DEBUG'   { 'Magenta' }
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            default   { 'Gray' }
        }

        Write-Host ('[{0}] {1}' -f $Severity, $Message) -ForegroundColor $Color
    }

    function Write-Status {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'SUCCESS', 'DEBUG', 'WARN', 'ERROR')]
            [string]$Severity = 'INFO'
        )

        Write-Log -Message $Message -Severity $Severity
        Write-Console -Message $Message -Severity $Severity
    }

    function ConvertFrom-LargeInteger {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [object]$Value
        )

        if ($Value -is [long] -or $Value -is [int64]) {
            return [int64]$Value
        }

        if ($null -ne $Value.PSObject.Properties['HighPart'] -and
            $null -ne $Value.PSObject.Properties['LowPart']) {
            $HighPart = [int64]$Value.HighPart
            $LowPart  = [uint32]$Value.LowPart
            return (($HighPart -shl 32) -bor $LowPart)
        }

        return [int64]$Value
    }

    $Searcher = $null
    $SearchRoot = $null

    try {
        Initialize-Logging

        $SiteName = if ([string]::IsNullOrWhiteSpace($env:CS_PROFILE_NAME)) { 'UnknownSite' } else { $env:CS_PROFILE_NAME }
        $HostName = if ([string]::IsNullOrWhiteSpace($env:CS_HOSTNAME)) { $env:COMPUTERNAME } else { $env:CS_HOSTNAME }
        $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

        Write-Status -Message ('===== {0} {1} =====' -f $ScriptName, $ScriptVersion) -Severity INFO
        Write-Status -Message ('Site     : {0}' -f $SiteName) -Severity INFO
        Write-Status -Message ('Hostname : {0}' -f $HostName) -Severity INFO
        Write-Status -Message ('Run As   : {0}' -f $RunAs) -Severity INFO
        Write-Status -Message 'Mode     : MONITOR' -Severity INFO
        Write-Status -Message ('Log File : {0}' -f $LogFile) -Severity INFO

        $ParsedMaxYears = 0
        if (-not [int]::TryParse($MaxPasswordAgeYears.Trim(), [ref]$ParsedMaxYears) -or $ParsedMaxYears -lt 1) {
            Write-Status -Message ("Fatal pre-flight failure: MaxPasswordAgeYears must be a whole number greater than zero. Received '{0}'." -f $MaxPasswordAgeYears) -Severity ERROR
            return 2
        }

        Write-Status -Message ('Configured maximum password age: {0} calendar year(s).' -f $ParsedMaxYears) -Severity DEBUG

        $RootDse = [ADSI]'LDAP://RootDSE'
        $DefaultNamingContext = [string]$RootDse.defaultNamingContext

        if ([string]::IsNullOrWhiteSpace($DefaultNamingContext)) {
            throw 'The default Active Directory naming context could not be determined.'
        }

        $SearchRoot = New-Object -TypeName System.DirectoryServices.DirectoryEntry -ArgumentList ('LDAP://{0}' -f $DefaultNamingContext)
        $Searcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher -ArgumentList $SearchRoot
        $Searcher.Filter = '(&(objectCategory=person)(objectClass=user)(sAMAccountName=krbtgt))'
        $Searcher.SearchScope = [System.DirectoryServices.SearchScope]::Subtree
        $Searcher.PageSize = 100
        [void]$Searcher.PropertiesToLoad.Add('distinguishedName')
        [void]$Searcher.PropertiesToLoad.Add('sAMAccountName')
        [void]$Searcher.PropertiesToLoad.Add('pwdLastSet')

        $Result = $Searcher.FindOne()
        if ($null -eq $Result) {
            throw "The krbtgt account was not found in '$DefaultNamingContext'."
        }

        if ($Result.Properties['pwdlastset'].Count -eq 0) {
            throw 'The krbtgt account does not contain a readable pwdLastSet value.'
        }

        $PwdLastSetRaw = ConvertFrom-LargeInteger -Value $Result.Properties['pwdlastset'][0]
        if ($PwdLastSetRaw -le 0) {
            throw "The krbtgt pwdLastSet value is invalid or zero: '$PwdLastSetRaw'."
        }

        $PasswordLastSetUtc = [datetime]::FromFileTimeUtc($PwdLastSetRaw)
        $NowUtc             = (Get-Date).ToUniversalTime()
        $CutoffUtc          = $NowUtc.AddYears(-$ParsedMaxYears)
        $PasswordAge        = $NowUtc - $PasswordLastSetUtc
        $PasswordAgeDays    = [math]::Floor($PasswordAge.TotalDays)
        $DistinguishedName  = [string]$Result.Properties['distinguishedname'][0]

        Write-Status -Message ('Domain naming context : {0}' -f $DefaultNamingContext) -Severity INFO
        Write-Status -Message ('Account DN            : {0}' -f $DistinguishedName) -Severity DEBUG
        Write-Status -Message ('Password last set UTC : {0:yyyy-MM-dd HH:mm:ss}Z' -f $PasswordLastSetUtc) -Severity INFO
        Write-Status -Message ('Password age          : {0} day(s)' -f $PasswordAgeDays) -Severity INFO
        Write-Status -Message ('Failure cutoff UTC    : {0:yyyy-MM-dd HH:mm:ss}Z' -f $CutoffUtc) -Severity INFO

        if ($PasswordLastSetUtc -lt $CutoffUtc) {
            Write-Status -Message ('MONITOR FAILED: The krbtgt password was last set {0} day(s) ago, which is older than the configured {1} calendar-year limit.' -f $PasswordAgeDays, $ParsedMaxYears) -Severity ERROR
            return 1
        }

        Write-Status -Message ('MONITOR PASSED: The krbtgt password was last set {0} day(s) ago and is within the configured {1} calendar-year limit.' -f $PasswordAgeDays, $ParsedMaxYears) -Severity SUCCESS
        return 0
    }
    catch {
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $FailureMessage = 'Fatal monitor error: {0}' -f $_.Exception.Message
        try {
            Write-Status -Message $FailureMessage -Severity ERROR
        }
        catch {
            Write-Output -InputObject $FailureMessage
        }
        return 2
    }
    finally {
        if ($null -ne $Searcher) {
            $Searcher.Dispose()
        }
        if ($null -ne $SearchRoot) {
            $SearchRoot.Dispose()
        }
    }
}

$Params = @{
    MaxPasswordAgeYears = $MaxPasswordAgeYears
}

$ExitCode = Test-KrbtgtPasswordAge @Params
exit $ExitCode
