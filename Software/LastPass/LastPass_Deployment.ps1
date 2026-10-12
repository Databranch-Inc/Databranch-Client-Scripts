#Requires -Version 5.1

<#
.SYNOPSIS
Downloads and installs LastPass silently.

.DESCRIPTION
Downloads the latest LastPass MSI installer and performs a silent installation.
Designed for Datto RMM and manual execution.

.NOTES
Author      : Josh Britton
Script Name : Install-LastPass
Version     : v1.0.0.001
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$DownloadUrl = $(if ($env:DownloadUrl) { $env:DownloadUrl } else { 'https://download.cloud.lastpass.com/windows_installer/LastPassInstaller.msi' }),

    [Parameter(Mandatory = $false)]
    [string]$WorkingFolder = $(if ($env:WorkingFolder) { $env:WorkingFolder } else { 'C:\Databranch' })
)

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject(
    [Net.SecurityProtocolType],
    3072
)

function Install-LastPass {

    $ScriptVersion = 'v1.0.0.001'
    $ScriptName    = 'Install-LastPass'

    $ErrorActionPreference = 'Stop'

    # --------------------------------------------------------------------------
    # Logging
    # --------------------------------------------------------------------------

    function Initialize-Logging {
        $script:LogRoot = "C:\Databranch\ScriptLogs\$ScriptName"

        if (-not (Test-Path $script:LogRoot)) {
            New-Item -Path $script:LogRoot -ItemType Directory -Force | Out-Null
        }

        $script:LogFile = Join-Path `
            $script:LogRoot `
            "$ScriptName`_$(Get-Date -Format 'yyyy-MM-dd').log"

        Get-ChildItem `
            -Path $script:LogRoot `
            -Filter '*.log' `
            -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 10 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    function Write-Log {
        param(
            [string]$Message,
            [ValidateSet('INFO','SUCCESS','WARN','ERROR','DEBUG')]
            [string]$Severity = 'INFO'
        )

        $Line = '[{0}] [{1}] {2}' -f `
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
            $Severity,
            $Message

        Add-Content -Path $script:LogFile -Value $Line

        switch ($Severity) {
            'ERROR' { Write-Error $Line }
            'WARN'  { Write-Warning $Line }
            default { Write-Output $Line }
        }
    }

    function Write-Console {
        param(
            [string]$Message,
            [string]$Severity = 'INFO'
        )

        $Color = switch ($Severity) {
            'INFO'    { 'Cyan' }
            'SUCCESS' { 'Green' }
            'WARN'    { 'Yellow' }
            'ERROR'   { 'Red' }
            'DEBUG'   { 'Magenta' }
            default   { 'Gray' }
        }

        Write-Host $Message -ForegroundColor $Color
    }

    try {

        Initialize-Logging

        Write-Log "===== $ScriptName $ScriptVersion ====="
        Write-Log "Site     : $($env:CS_PROFILE_NAME)"
        Write-Log "Hostname : $($env:CS_HOSTNAME)"
        Write-Log "Run As   : $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
        Write-Log "Log File : $script:LogFile"

        Write-Log "Beginning LastPass installation." -Severity INFO

        # ----------------------------------------------------------------------
        # Create Working Directory
        # ----------------------------------------------------------------------

        if (-not (Test-Path $WorkingFolder)) {
            New-Item `
                -Path $WorkingFolder `
                -ItemType Directory `
                -Force | Out-Null

            Write-Log "Created working folder: $WorkingFolder"
        }

        $MsiPath = Join-Path $WorkingFolder 'LastPassInstaller.msi'

        # ----------------------------------------------------------------------
        # Download MSI
        # ----------------------------------------------------------------------

        Write-Log "Downloading MSI from: $DownloadUrl"

        Invoke-WebRequest `
            -Uri $DownloadUrl `
            -OutFile $MsiPath `
            -UseBasicParsing

        if (-not (Test-Path $MsiPath)) {
            throw "MSI download failed."
        }

        Write-Log "Download completed successfully." -Severity SUCCESS

        # ----------------------------------------------------------------------
        # Install MSI
        # ----------------------------------------------------------------------

        Write-Log "Launching silent MSI installation."

        $Arguments = "/i `"$MsiPath`" /qn /norestart"

        $Process = Start-Process `
            -FilePath 'msiexec.exe' `
            -ArgumentList $Arguments `
            -Wait `
            -PassThru

        Write-Log "MSI Exit Code: $($Process.ExitCode)"

        if ($Process.ExitCode -eq 0) {
            Write-Log "LastPass installed successfully." -Severity SUCCESS
            exit 0
        }
        else {
            Write-Log "Installation failed with exit code $($Process.ExitCode)." -Severity ERROR
            exit 1
        }
    }
    catch {
        Write-Log $_.Exception.Message -Severity ERROR
        exit 1
    }
}

$Params = @{
    DownloadUrl  = $DownloadUrl
    WorkingFolder = $WorkingFolder
}

Install-LastPass @Params