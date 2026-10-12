#Requires -Version 5.1

<#
.SYNOPSIS
    Deploys a client-specific SonicWall NetExtender connection.json profile.

.DESCRIPTION
    Resolves the client name from the Datto RMM CS_PROFILE_NAME environment
    variable or the ClientName PowerShell parameter.

    The script looks for a JSON file in the Datto RMM component working
    directory using the following order:

        1. <ClientName>.json
        2. <SanitizedClientName>.json
        3. Explicit SourceFileName parameter, when supplied

    The selected file is validated as JSON and copied to the SonicWall
    NetExtender installation directory as:

        connection.json

    Existing connection.json files are compared before replacement. If the
    contents differ, the existing file is backed up before the new file is
    deployed.

    The script defaults to report-only mode. Set ReportOnly to false in the
    Datto RMM component to permit changes.

.PARAMETER ClientName
    Client/site name used to select the attached JSON file.

    Datto RMM fallback:
        $env:ClientName
        $env:CS_PROFILE_NAME
        PowerShell parameter

.PARAMETER SourceFileName
    Optional explicit attached-file name. When specified, this file takes
    precedence over the automatically generated client file names.

    Example:
        Contoso-NetExtender.json

.PARAMETER AttachmentDirectory
    Directory containing the Datto RMM component's attached files.

    The default is the current PowerShell working directory.

.PARAMETER DestinationDirectory
    Destination directory containing the SonicWall NetExtender profile.

.PARAMETER ReportOnly
    Controls whether changes are committed.

    true  = Report only. No files are copied or changed.
    false = Write mode. Deploy the selected profile.

    Defaults to true.

.PARAMETER RestartNetExtender
    Controls whether running NetExtender user-interface processes are stopped
    after the profile is deployed.

    true  = Stop detected NetExtender UI processes.
    false = Do not stop NetExtender UI processes.

    Defaults to false.

.PARAMETER VerboseOutput
    Controls detailed per-item logging.

    Defaults to true.

.EXAMPLE
    .\Install-NetExtenderConnectionProfile.ps1 `
        -ClientName "Contoso" `
        -ReportOnly "true"

    Searches for Contoso.json and reports what would be changed.

.EXAMPLE
    .\Install-NetExtenderConnectionProfile.ps1 `
        -ClientName "Contoso" `
        -ReportOnly "false" `
        -RestartNetExtender "true"

    Deploys Contoso.json as connection.json and stops the NetExtender UI
    process so the profile can be reloaded when NetExtender is reopened.

.EXAMPLE
    .\Install-NetExtenderConnectionProfile.ps1 `
        -SourceFileName "Contoso-NetExtender.json" `
        -ReportOnly "false"

    Deploys an explicitly named attached JSON file.

.NOTES
    Script Name : Install-NetExtenderConnectionProfile.ps1
    Version     : v1.0.0.001
    Author      : Josh Britton
    Company     : Databranch
    PowerShell  : 5.1
    Run Context : SYSTEM through Datto RMM or elevated administrator
    Log Path    : C:\Databranch\ScriptLogs\Install-NetExtenderConnectionProfile

    Datto RMM component variables:

        ClientName          String    Optional
        SourceFileName      String    Optional
        AttachmentDirectory String    Optional
        DestinationDirectory String   Optional
        ReportOnly          Boolean   Default: true
        RestartNetExtender  Boolean   Default: false
        VerboseOutput       Boolean   Default: true

    Required attached-file naming convention:

        <Datto Site Name>.json

    Example:

        Datto site/client:
            Contoso Manufacturing

        Attached file:
            Contoso Manufacturing.json

        Deployed file:
            connection.json

    Exit codes:

        0 = Success
        1 = Runtime failure
        2 = Fatal pre-flight failure

.CHANGELOG
    v1.0.0.001 - 2026-08-11 - Josh Britton
        - Initial release.
        - Added Datto RMM and manual parameter fallback support.
        - Added client-specific attached-file selection.
        - Added filename sanitization fallback.
        - Added JSON syntax validation.
        - Added report-only mode, safe by default.
        - Added idempotent SHA-256 file comparison.
        - Added existing-profile backup.
        - Added atomic profile replacement.
        - Added optional NetExtender UI process restart handling.
        - Added Databranch-standard logging and explicit exit codes.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ClientName = $(if ($env:ClientName) {
            $env:ClientName
        }
        elseif ($env:CS_PROFILE_NAME) {
            $env:CS_PROFILE_NAME
        }
        else {
            ''
        }),

    [Parameter(Mandatory = $false)]
    [string]$SourceFileName = $(if ($env:SourceFileName) {
            $env:SourceFileName
        }
        else {
            ''
        }),

    [Parameter(Mandatory = $false)]
    [string]$AttachmentDirectory = $(if ($env:AttachmentDirectory) {
            $env:AttachmentDirectory
        }
        else {
            (Get-Location).Path
        }),

    [Parameter(Mandatory = $false)]
    [string]$DestinationDirectory = $(if ($env:DestinationDirectory) {
            $env:DestinationDirectory
        }
        else {
            'C:\Program Files (x86)\SonicWall\SSL-VPN\NetExtender'
        }),

    [Parameter(Mandatory = $false)]
    [string]$ReportOnly = $(if ($env:ReportOnly) {
            $env:ReportOnly
        }
        else {
            'true'
        }),

    [Parameter(Mandatory = $false)]
    [string]$RestartNetExtender = $(if ($env:RestartNetExtender) {
            $env:RestartNetExtender
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

function Install-NetExtenderConnectionProfile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ClientName,

        [Parameter(Mandatory = $false)]
        [string]$SourceFileName,

        [Parameter(Mandatory = $true)]
        [string]$AttachmentDirectory,

        [Parameter(Mandatory = $true)]
        [string]$DestinationDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ReportOnly,

        [Parameter(Mandatory = $true)]
        [string]$RestartNetExtender,

        [Parameter(Mandatory = $true)]
        [string]$VerboseOutput
    )

    # ==========================================================================
    # SCRIPT CONFIGURATION
    # ==========================================================================

    $ScriptName    = 'Install-NetExtenderConnectionProfile'
    $ScriptVersion = 'v1.0.0.001'
    $LogRoot       = 'C:\Databranch\ScriptLogs'
    $LogDirectory  = Join-Path -Path $LogRoot -ChildPath $ScriptName
    $LogFile       = Join-Path -Path $LogDirectory -ChildPath (
        '{0}_{1}.log' -f $ScriptName, (Get-Date -Format 'yyyy-MM-dd')
    )

    $ErrorActionPreference = 'Stop'

    # Report-only stays enabled for every value except the explicit string false.
    $IsReportOnly = (
        $ReportOnly.Trim().ToLower() -ne 'false'
    )

    $ShouldRestartNetExtender = (
        $RestartNetExtender.Trim().ToLower() -eq 'true'
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

    # ==========================================================================
    # INTERNAL FUNCTIONS
    # ==========================================================================

    function Initialize-Logging {
        try {
            if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
                New-Item -Path $LogDirectory -ItemType Directory -Force |
                    Out-Null
            }

            $LogFiles = Get-ChildItem -LiteralPath $LogDirectory `
                -Filter "$ScriptName`_*.log" `
                -File |
                Sort-Object -Property LastWriteTime -Descending

            if ($LogFiles.Count -gt 10) {
                $LogFiles |
                    Select-Object -Skip 10 |
                    Remove-Item -Force
            }
        }
        catch {
            Write-Output (
                '[ERROR] Failed to initialize logging: {0}' -f
                $_.Exception.Message
            )

            exit 2
        }
    }

    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Message,

            [Parameter(Mandatory = $false)]
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS', 'DEBUG')]
            [string]$Severity = 'INFO'
        )

        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $LogLine = '{0} [{1}] {2}' -f $Timestamp, $Severity, $Message

        try {
            Add-Content -LiteralPath $LogFile -Value $LogLine `
                -Encoding UTF8
        }
        catch {
            Write-Output (
                '[ERROR] Unable to write to log file: {0}' -f
                $_.Exception.Message
            )
        }

        switch ($Severity) {
            'WARN' {
                Write-Warning $LogLine
            }

            'ERROR' {
                # Write-Error would become terminating under the script-wide
                # Stop policy. Write-Output preserves logging control here.
                Write-Output $LogLine
            }

            default {
                Write-Output $LogLine
            }
        }
    }

    function Write-Console {
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

        $Prefix = if ($Indent -gt 0) {
            ' ' * $Indent
        }
        else {
            ''
        }

        $Color = switch ($Severity) {
            'INFO'    { 'Cyan' }
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            'SUCCESS' { 'Green' }
            'DEBUG'   { 'Magenta' }
            default   { 'Gray' }
        }

        Write-Host "$Prefix$Message" -ForegroundColor $Color
    }

    function Write-VerboseLog {
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
        Write-Console -Message $Message -Severity $Severity -Indent $Indent
    }

    function ConvertTo-SafeFileName {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Name
        )

        $SafeName = $Name.Trim()

        foreach ($InvalidCharacter in [System.IO.Path]::GetInvalidFileNameChars()) {
            $SafeName = $SafeName.Replace(
                [string]$InvalidCharacter,
                '_'
            )
        }

        return $SafeName.Trim().TrimEnd('.')
    }

    function Get-ProfileSourceFile {
        param (
            [Parameter(Mandatory = $false)]
            [string]$RequestedFileName,

            [Parameter(Mandatory = $false)]
            [string]$ResolvedClientName,

            [Parameter(Mandatory = $true)]
            [string]$WorkingDirectory
        )

        $CandidateNames = New-Object -TypeName `
            'System.Collections.Generic.List[string]'

        if (-not [string]::IsNullOrWhiteSpace($RequestedFileName)) {
            $CandidateNames.Add($RequestedFileName.Trim())
        }
        else {
            if ([string]::IsNullOrWhiteSpace($ResolvedClientName)) {
                throw (
                    'ClientName is empty and SourceFileName was not supplied.'
                )
            }

            $ExactName = '{0}.json' -f $ResolvedClientName.Trim()
            $CandidateNames.Add($ExactName)

            $SafeClientName = ConvertTo-SafeFileName `
                -Name $ResolvedClientName

            $SafeName = '{0}.json' -f $SafeClientName

            if ($SafeName -ne $ExactName) {
                $CandidateNames.Add($SafeName)
            }
        }

        foreach ($CandidateName in $CandidateNames) {
            if ([System.IO.Path]::IsPathRooted($CandidateName)) {
                $CandidatePath = $CandidateName
            }
            else {
                $CandidatePath = Join-Path `
                    -Path $WorkingDirectory `
                    -ChildPath $CandidateName
            }

            Write-VerboseLog `
                -Message "[CHECK] Looking for attached file '$CandidatePath'." `
                -Severity 'DEBUG'

            if (Test-Path -LiteralPath $CandidatePath -PathType Leaf) {
                return Get-Item -LiteralPath $CandidatePath
            }
        }

        throw (
            "No matching JSON attachment was found. Checked: {0}" -f
            ($CandidateNames -join ', ')
        )
    }

    function Test-JsonProfile {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        try {
            $RawJson = Get-Content -LiteralPath $Path -Raw -Encoding UTF8

            if ([string]::IsNullOrWhiteSpace($RawJson)) {
                throw 'The JSON file is empty.'
            }

            $JsonObject = $RawJson | ConvertFrom-Json

            if ($null -eq $JsonObject) {
                throw 'ConvertFrom-Json returned a null object.'
            }

            return $true
        }
        catch {
            throw (
                "JSON validation failed for '$Path': {0}" -f
                $_.Exception.Message
            )
        }
    }

    function Get-FileSha256 {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        return (
            Get-FileHash -LiteralPath $Path -Algorithm SHA256
        ).Hash
    }

    function Stop-NetExtenderInterface {
        $ProcessNames = @(
            'NEGui',
            'NetExtender'
        )

        $StoppedCount = 0

        foreach ($ProcessName in $ProcessNames) {
            $Processes = @(
                Get-Process -Name $ProcessName `
                    -ErrorAction SilentlyContinue
            )

            foreach ($Process in $Processes) {
                try {
                    Stop-Process -Id $Process.Id -Force
                    $StoppedCount++

                    Write-VerboseLog `
                        -Message (
                            "[WROTE] Stopped process '{0}' with PID {1}." -f
                            $Process.ProcessName,
                            $Process.Id
                        ) `
                        -Severity 'INFO'
                }
                catch {
                    Write-Log `
                        -Message (
                            "WARNING: Unable to stop process '{0}' with " +
                            "PID {1}: {2}"
                        ) -f @(
                            $Process.ProcessName
                            $Process.Id
                            $_.Exception.Message
                        ) `
                        -Severity 'WARN'
                }
            }
        }

        return $StoppedCount
    }

    # ==========================================================================
    # INITIALIZE LOGGING
    # ==========================================================================

    Initialize-Logging

    $SiteName = if ($env:CS_PROFILE_NAME) {
        $env:CS_PROFILE_NAME
    }
    else {
        'UnknownSite'
    }

    $Hostname = if ($env:CS_HOSTNAME) {
        $env:CS_HOSTNAME
    }
    elseif ($env:COMPUTERNAME) {
        $env:COMPUTERNAME
    }
    else {
        'UnknownHost'
    }

    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log -Message "===== $ScriptName $ScriptVersion ====="
    Write-Log -Message "Site     : $SiteName"
    Write-Log -Message "Hostname : $Hostname"
    Write-Log -Message "Run As   : $RunAs"
    Write-Log -Message "Mode     : $ModeDisplay"
    Write-Log -Message "Log File : $LogFile"
    Write-Log -Message ''

    Write-Console `
        -Message "$ScriptName $ScriptVersion" `
        -Severity 'INFO'

    Write-Console `
        -Message "Mode: $ModeDisplay" `
        -Severity 'INFO'

    # ==========================================================================
    # PRE-FLIGHT VALIDATION
    # ==========================================================================

    try {
        Write-Log -Message 'Starting pre-flight validation.'

        if ([string]::IsNullOrWhiteSpace($AttachmentDirectory)) {
            throw 'AttachmentDirectory cannot be empty.'
        }

        if (-not (
            Test-Path -LiteralPath $AttachmentDirectory -PathType Container
        )) {
            throw (
                "Attachment directory does not exist: " +
                "'$AttachmentDirectory'."
            )
        }

        if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
            throw 'DestinationDirectory cannot be empty.'
        }

        if (
            [string]::IsNullOrWhiteSpace($ClientName) -and
            [string]::IsNullOrWhiteSpace($SourceFileName)
        ) {
            throw (
                'ClientName could not be resolved from ClientName, ' +
                'CS_PROFILE_NAME, or SourceFileName.'
            )
        }

        Write-VerboseLog `
            -Message "Resolved client name: '$ClientName'." `
            -Severity 'DEBUG'

        Write-VerboseLog `
            -Message "Attachment directory: '$AttachmentDirectory'." `
            -Severity 'DEBUG'

        Write-VerboseLog `
            -Message "Destination directory: '$DestinationDirectory'." `
            -Severity 'DEBUG'

        $SourceFile = Get-ProfileSourceFile `
            -RequestedFileName $SourceFileName `
            -ResolvedClientName $ClientName `
            -WorkingDirectory $AttachmentDirectory

        Write-Log `
            -Message "Selected source file: '$($SourceFile.FullName)'."

        Test-JsonProfile -Path $SourceFile.FullName | Out-Null

        Write-Log `
            -Message 'Source profile passed JSON syntax validation.' `
            -Severity 'SUCCESS'
    }
    catch {
        Write-Log `
            -Message "Fatal pre-flight failure: $($_.Exception.Message)" `
            -Severity 'ERROR'

        return 2
    }

    # ==========================================================================
    # PROFILE COMPARISON AND DEPLOYMENT
    # ==========================================================================

    try {
        $DestinationFile = Join-Path `
            -Path $DestinationDirectory `
            -ChildPath 'connection.json'

        $SourceHash = Get-FileSha256 -Path $SourceFile.FullName

        $DestinationExists = Test-Path `
            -LiteralPath $DestinationFile `
            -PathType Leaf

        $ProfileIsCurrent = $false

        if ($DestinationExists) {
            $DestinationHash = Get-FileSha256 -Path $DestinationFile
            $ProfileIsCurrent = ($SourceHash -eq $DestinationHash)

            Write-VerboseLog `
                -Message "Source SHA-256:      $SourceHash" `
                -Severity 'DEBUG'

            Write-VerboseLog `
                -Message "Destination SHA-256: $DestinationHash" `
                -Severity 'DEBUG'
        }

        if ($ProfileIsCurrent) {
            Write-VerboseLog `
                -Message (
                    "[SKIPPED-CURRENT] '$DestinationFile' already matches " +
                    "the selected client profile."
                ) `
                -Severity 'INFO'

            Write-Log `
                -Message 'NetExtender connection profile is already current.' `
                -Severity 'SUCCESS'

            return 0
        }

        if ($IsReportOnly) {
            $ActionDescription = if ($DestinationExists) {
                "replace the existing '$DestinationFile'"
            }
            else {
                "create '$DestinationFile'"
            }

            Write-VerboseLog `
                -Message (
                    "[SKIPPED-REPORT] Would $ActionDescription using " +
                    "'$($SourceFile.Name)'."
                ) `
                -Severity 'INFO'

            Write-Log `
                -Message (
                    'Report-only validation completed successfully. ' +
                    'No changes were made.'
                ) `
                -Severity 'SUCCESS'

            return 0
        }

        if (-not (
            Test-Path -LiteralPath $DestinationDirectory -PathType Container
        )) {
            New-Item `
                -Path $DestinationDirectory `
                -ItemType Directory `
                -Force |
                Out-Null

            Write-VerboseLog `
                -Message (
                    "[WROTE] Created destination directory " +
                    "'$DestinationDirectory'."
                ) `
                -Severity 'INFO'
        }

        if ($DestinationExists) {
            $BackupTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $BackupFileName = 'connection.json.{0}.bak' -f $BackupTimestamp
            $BackupPath = Join-Path `
                -Path $DestinationDirectory `
                -ChildPath $BackupFileName

            Copy-Item `
                -LiteralPath $DestinationFile `
                -Destination $BackupPath `
                -Force

            Write-VerboseLog `
                -Message (
                    "[WROTE] Backed up the existing profile to " +
                    "'$BackupPath'."
                ) `
                -Severity 'INFO'
        }

        # Copy to a temporary file in the destination directory first. This
        # prevents an interrupted copy from leaving a partial connection.json.
        $TemporaryPath = Join-Path `
            -Path $DestinationDirectory `
            -ChildPath (
                'connection.{0}.tmp' -f
                [System.Guid]::NewGuid().ToString('N')
            )

        try {
            Copy-Item `
                -LiteralPath $SourceFile.FullName `
                -Destination $TemporaryPath `
                -Force

            Test-JsonProfile -Path $TemporaryPath | Out-Null

            $TemporaryHash = Get-FileSha256 -Path $TemporaryPath

            if ($TemporaryHash -ne $SourceHash) {
                throw (
                    'The copied temporary file does not match the source ' +
                    'file SHA-256 hash.'
                )
            }

            Move-Item `
                -LiteralPath $TemporaryPath `
                -Destination $DestinationFile `
                -Force
        }
        finally {
            if (Test-Path -LiteralPath $TemporaryPath -PathType Leaf) {
                Remove-Item -LiteralPath $TemporaryPath -Force
            }
        }

        $DeployedHash = Get-FileSha256 -Path $DestinationFile

        if ($DeployedHash -ne $SourceHash) {
            throw (
                'Post-deployment SHA-256 validation failed. The deployed ' +
                'file does not match the selected source profile.'
            )
        }

        Write-VerboseLog `
            -Message (
                "[WROTE] Deployed '$($SourceFile.Name)' as " +
                "'$DestinationFile'."
            ) `
            -Severity 'INFO'

        if ($ShouldRestartNetExtender) {
            $StoppedProcessCount = Stop-NetExtenderInterface

            if ($StoppedProcessCount -eq 0) {
                Write-VerboseLog `
                    -Message (
                        '[SKIPPED-CURRENT] No running NetExtender UI ' +
                        'processes were detected.'
                    ) `
                    -Severity 'INFO'
            }
        }
        else {
            Write-VerboseLog `
                -Message (
                    '[SKIPPED-CURRENT] NetExtender UI restart was not ' +
                    'requested.'
                ) `
                -Severity 'INFO'
        }

        Write-Log `
            -Message (
                "NetExtender connection profile deployed successfully for " +
                "client '$ClientName'."
            ) `
            -Severity 'SUCCESS'

        Write-Log -Message "Destination: '$DestinationFile'."
        Write-Log -Message "SHA-256   : $DeployedHash"

        return 0
    }
    catch {
        Write-Log `
            -Message "Profile deployment failed: $($_.Exception.Message)" `
            -Severity 'ERROR'

        return 1
    }
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

$Params = @{
    ClientName           = $ClientName
    SourceFileName       = $SourceFileName
    AttachmentDirectory  = $AttachmentDirectory
    DestinationDirectory = $DestinationDirectory
    ReportOnly           = $ReportOnly
    RestartNetExtender   = $RestartNetExtender
    VerboseOutput        = $VerboseOutput
}

$ExitCode = Install-NetExtenderConnectionProfile @Params
exit $ExitCode