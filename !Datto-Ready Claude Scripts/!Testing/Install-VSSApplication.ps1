#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads, extracts, and silently installs VIVOTEK VAST Security Station (VSS).

.DESCRIPTION
    Downloads the VSS installer ZIP from the VIVOTEK download center, extracts it
    to C:\Databranch, and runs the setup executable silently. Supports both DattoRMM
    automated runs and manual interactive execution.

    If VSS is already detected in the Windows registry, the script exits with code 2
    (already installed) unless the -Force switch is provided, which bypasses the check
    and re-runs the installer regardless.

    The VSS NSIS installer requires a valid local admin account passed via installer
    arguments (/username and /password). When running as SYSTEM without these flags
    the installer returns exit code 2. Use -UseSetupAccount with -SetupAccountPassword
    to pass the local Setup account credentials directly to the installer. The script
    itself continues to run as SYSTEM — no token switching or Task Scheduler needed.

    Staging and extraction work in C:\Databranch, which is managed as a temp/working
    folder by monthly Databranch automation. No cleanup is performed by this script.

.PARAMETER Force
    Bypass the already-installed check and run the installer regardless of current
    install state. Equivalent to DattoRMM env var VSS_Force=true.

.PARAMETER UseSetupAccount
    Pass /username=Setup and /password=... as arguments to the VSS installer.
    Required when running via DattoRMM or any SYSTEM context, as the VSS NSIS
    installer requires a valid local admin account supplied via installer flags.
    Equivalent to DattoRMM env var VSS_UseSetupAccount=true.

.PARAMETER SetupAccountPassword
    Password for the local Setup account. Required when -UseSetupAccount is specified.
    Equivalent to DattoRMM env var VSS_SetupAccountPassword.
    Store as a password-type component variable in DattoRMM.

.PARAMETER SiteName
    Customer/site name. Auto-populated by DattoRMM via CS_PROFILE_NAME.
    Defaults to UnknownSite if not provided.

.PARAMETER Hostname
    Target machine hostname. Auto-populated by DattoRMM via CS_HOSTNAME.
    Defaults to COMPUTERNAME if not provided.

.EXAMPLE
    .\Install-VSSApplication.ps1 -UseSetupAccount -SetupAccountPassword "P@ssw0rd"
    Standard DattoRMM install via Task Scheduler under the local Setup account.

.EXAMPLE
    .\Install-VSSApplication.ps1 -UseSetupAccount -SetupAccountPassword "P@ssw0rd" -Force
    Force reinstall even if VSS is already detected.

.EXAMPLE
    .\Install-VSSApplication.ps1
    Manual run as an interactive admin. No Setup account needed in this context.

.NOTES
    File Name      : Install-VSSApplication.ps1
    Version        : 1.3.1.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-04-06
    Last Modified  : 2026-04-06
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM (DattoRMM) or interactive admin (manual)
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : All clients

    Staging Path   : C:\Databranch  (monthly automation manages cleanup)
    Log Path       : C:\Databranch\ScriptLogs\Install-VSSApplication\

    Why -UseSetupAccount is needed:
        The VSS NSIS installer requires a valid local admin account to be supplied
        via /username and /password installer arguments. When these are omitted and
        the installer runs as SYSTEM, it returns exit code 2 immediately. Passing
        /component=c /username=Setup /password="..." tells the installer which
        account to install under and satisfies its internal account validation.
        /component=c is always required for silent client installs.

    Exit Codes:
        0  - Success - VSS installed successfully
        1  - Failure - Unhandled exception or installer returned non-zero exit code
        2  - Skipped - VSS already installed (use -Force to override)
        3  - Failure - SetupAccountPassword not supplied when UseSetupAccount is set

    Output Design:
        Write-Log     - Structured [timestamp][SEVERITY] output to log file AND
                        DattoRMM stdout. Always verbose. No color.
        Write-Console - Human-friendly colored console output for manual/interactive
                        runs. Uses Write-Host (display stream only). Suppressed in
                        DattoRMM agent context automatically.

    DattoRMM Component Variables:
        VSS_Force                 - true/false  - Bypass already-installed check
        VSS_UseSetupAccount       - true/false  - Launch installer as Setup account
        VSS_SetupAccountPassword  - string      - Setup account password (use password type)

.CHANGELOG
    v1.3.1.0 - 2026-04-07 - Sam Kirsch
        - Added retry loop to extract folder deletion in Expand-VSSZip
        - AV scanners briefly lock the installer EXE after download, causing
          Remove-Item to fail on the second run; retries up to 5 times with
          5-second waits before throwing

    v1.3.0.0 - 2026-04-07 - Sam Kirsch
        - Removed entire Task Scheduler launch mechanism (no longer needed)
        - Root cause identified: VSS installer requires /username and /password
          arguments to specify the account it installs under; it rejects SYSTEM
          unless a valid local admin account is supplied via installer flags
        - Installer now runs directly as SYSTEM via Start-Process -Wait -PassThru
        - When -UseSetupAccount is set, installer args include:
          /component=c /username=Setup /password="<password>"
        - When -UseSetupAccount is not set, args are /S /component=c only
        - /component=c required for all silent installs (client component)
        - Password masked in log output as [supplied] — never written in plain text
        - Removed Task Scheduler config vars: TaskBaseName, ExitCodeFile,
          TaskTimeoutMins, WrapperBat
        - Removed Phase 2 account existence/enabled validation (no longer launching
          as Setup account; password is passed to installer, not to a logon)
        - Simplified overall flow considerably

    v1.2.3.0 - 2026-04-06 - Sam Kirsch
        - Fixed Task Scheduler account resolution: changed -User from ".\AccountName"
          to "$env:COMPUTERNAME\AccountName" format
        - Task Scheduler CIM provider cannot resolve .\AccountName shorthand to a SID;
          explicit HOSTNAME\Username format resolves correctly
        - Updated log messages to reflect COMPUTERNAME\AccountName format

    v1.2.2.0 - 2026-04-06 - Sam Kirsch
        - Replaced inline cmd.exe chaining with a .bat wrapper file written to disk
        - Inline "& echo %ERRORLEVEL% > file" failed when installer path had spaces
          and quoting inside ScheduledTaskAction arguments was unreliable
        - Batch file (vss_install_wrapper.bat) runs installer and writes exit code
          cleanly with no escaping issues; cleaned up in finally block
        - Fixed polling loop infinite hang when task disappears from scheduler
        - Task state now treated as "Gone" when Get-ScheduledTask returns null
        - "Ready" and "Gone" both treated as completion signals; exit code file
          appearance also breaks the loop as an early completion signal
        - Added 2-second flush wait after loop exits before reading exit code file
        - Wrapper bat file added to finally block cleanup alongside exit code file

    v1.2.1.0 - 2026-04-06 - Sam Kirsch
        - Fixed Register-ScheduledTask parameter set conflict on PS 5.1
        - -Principal object and -Password cannot coexist in same parameter set
        - Replaced with -User, -Password, -RunLevel passed directly to
          Register-ScheduledTask (correct PS 5.1 parameter set for user+password)

    v1.2.0.0 - 2026-04-06 - Sam Kirsch
        - Replaced Start-Process -Credential with Task Scheduler launch mechanism
        - Start-Process -Credential requires "Log on as a batch job" right which is
          stripped from Setup account by domain GPO; Access Denied in SYSTEM context
        - Task Scheduler uses S4U logon internally, bypassing batch logon restriction
        - Installer launched via one-shot scheduled task running as .\Setup account
        - Exit code passed back to calling script via C:\Databranch\vss_exitcode.tmp
        - Task polled every 3 seconds until complete; 30-minute timeout safeguard
        - Task unregistered on completion regardless of outcome (try/finally)
        - Task name includes timestamp to avoid conflicts with concurrent runs
        - Updated .NOTES with Task Scheduler mechanism explanation

    v1.1.0.0 - 2026-04-06 - Sam Kirsch
        - Added -UseSetupAccount switch and -SetupAccountPassword parameter
        - VSS NSIS installer (v2.46) rejects SYSTEM token; Setup account provides
          valid interactive admin token required by requireAdministrator manifest
        - When -UseSetupAccount is set, installer launched via Start-Process -Credential
        - Validates Setup account exists, is enabled, and password is supplied
        - Exit code 3 for Setup account validation failures
        - DattoRMM env vars: VSS_UseSetupAccount, VSS_SetupAccountPassword
        - Password logged as [supplied]/[not supplied] only

    v1.0.0.0 - 2026-04-06 - Sam Kirsch
        - Initial release
        - Downloads VSS ZIP from VIVOTEK download center
        - Extracts to C:\Databranch staging area
        - Runs VSS_1_4_0_2300_x64_setup.exe /S silently
        - Registry-based install detection (HKLM Uninstall scan)
        - -Force parameter / VSS_Force env var to bypass detection
        - Exit code 2 when already installed without -Force
        - Dual-output pattern (Write-Log + Write-Console)
        - Full log rotation (10 files max)
#>

# ==============================================================================
# PARAMETERS
# DattoRMM env vars take precedence; fall back to passed parameters or defaults.
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [switch]$Force = $(
        if ($env:VSS_Force -and $env:VSS_Force -eq 'true') { $true } else { $false }
    ),

    [Parameter(Mandatory = $false)]
    [switch]$UseSetupAccount = $(
        if ($env:VSS_UseSetupAccount -and $env:VSS_UseSetupAccount -eq 'true') { $true } else { $false }
    ),

    [Parameter(Mandatory = $false)]
    [string]$SetupAccountPassword = $(
        if ($env:VSS_SetupAccountPassword) { $env:VSS_SetupAccountPassword } else { "" }
    ),

    # DattoRMM built-in variables (auto-populated, no component config needed)
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Install-VSSApplication {
    [CmdletBinding()]
    param (
        [switch]$Force,
        [switch]$UseSetupAccount,
        [string]$SetupAccountPassword,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Install-VSSApplication"
    $ScriptVersion = "1.3.1.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # VSS installer details
    $VSSDownloadUrl  = "https://www.vivotek.com/resource/download-center/software-app-vadp-package/download/55106"
    $VSSZipName      = "Software_VAST Security Station(VSS)_Installation_Win(x64)_V1.4.0.2300.zip"
    $VSSExeName      = "VSS_1_4_0_2300_x64_setup.exe"
    $VSSSilentArgs   = "/S"
    $StagingRoot     = "C:\Databranch"
    $VSSZipPath      = Join-Path $StagingRoot $VSSZipName
    $VSSExtractPath  = Join-Path $StagingRoot "VSS_1_4_0_2300"
    $VSSExePath      = Join-Path $VSSExtractPath $VSSExeName

    # Local Setup account name — passed to installer via /username flag
    $SetupAccountName = "Setup"

    # Registry paths to scan for existing VSS installation
    $UninstallPaths  = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    $VSSRegistryName = "VAST Security Station"

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
    # WRITE-CONSOLE  (Presentation Layer — display stream only)
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
    # HELPER: Get-VSSInstallEntry
    # Scans both 32-bit and 64-bit Uninstall registry hives for VSS.
    # Returns the matching registry entry object, or $null if not found.
    # ==========================================================================
    function Get-VSSInstallEntry {
        foreach ($RegistryPath in $UninstallPaths) {
            if (-not (Test-Path $RegistryPath)) { continue }

            $Entry = Get-ChildItem -Path $RegistryPath -ErrorAction SilentlyContinue |
                     ForEach-Object { Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue } |
                     Where-Object {
                         $_.DisplayName -and
                         $_.DisplayName -like "*$VSSRegistryName*"
                     } |
                     Select-Object -First 1

            if ($Entry) { return $Entry }
        }
        return $null
    }

    # ==========================================================================
    # HELPER: Invoke-VSSDownload
    # Downloads the VSS ZIP using BITS with WebClient fallback.
    # ==========================================================================
    function Invoke-VSSDownload {
        if (-not (Test-Path $StagingRoot)) {
            New-Item -ItemType Directory -Path $StagingRoot -Force | Out-Null
            Write-Log  "Created staging folder: $StagingRoot" -Severity DEBUG
            Write-Console "Created staging folder: $StagingRoot" -Severity DEBUG -Indent 1
        }

        if (Test-Path $VSSZipPath) {
            Write-Log  "Removing stale ZIP from prior run: $VSSZipPath" -Severity DEBUG
            Write-Console "Removing stale ZIP from prior run." -Severity DEBUG -Indent 1
            Remove-Item -Path $VSSZipPath -Force
        }

        Write-Log  "Downloading VSS installer ZIP..." -Severity INFO
        Write-Console "Downloading VSS installer ZIP..." -Severity INFO

        $BITSAvailable = $false
        try {
            Import-Module BitsTransfer -ErrorAction Stop
            $BITSAvailable = $true
        }
        catch {
            Write-Log  "BITS not available, will use WebClient fallback." -Severity DEBUG
            Write-Console "BITS unavailable, using WebClient fallback." -Severity DEBUG -Indent 1
        }

        if ($BITSAvailable) {
            try {
                Start-BitsTransfer -Source $VSSDownloadUrl -Destination $VSSZipPath -ErrorAction Stop
                Write-Log  "Download complete via BITS: $VSSZipPath" -Severity SUCCESS
                Write-Console "Download complete via BITS." -Severity SUCCESS -Indent 1
                return
            }
            catch {
                Write-Log  "BITS transfer failed: $_. Falling back to WebClient." -Severity WARN
                Write-Console "BITS transfer failed, retrying with WebClient." -Severity WARN -Indent 1
            }
        }

        $WebClient = New-Object System.Net.WebClient
        try {
            $WebClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $WebClient.DownloadFile($VSSDownloadUrl, $VSSZipPath)
            Write-Log  "Download complete via WebClient: $VSSZipPath" -Severity SUCCESS
            Write-Console "Download complete via WebClient." -Severity SUCCESS -Indent 1
        }
        finally {
            $WebClient.Dispose()
        }
    }

    # ==========================================================================
    # HELPER: Expand-VSSZip
    # Extracts the ZIP to the staging extract path.
    # ==========================================================================
    function Expand-VSSZip {
        if (Test-Path $VSSExtractPath) {
            Write-Log  "Removing existing extract folder: $VSSExtractPath" -Severity DEBUG
            Write-Console "Clearing existing extract folder." -Severity DEBUG -Indent 1

            # Retry loop handles brief file locks from AV scanning the EXE after
            # a prior run. Retries up to 5 times with a 5-second wait between attempts.
            $MaxRetries    = 10
            $RetryDelaySec = 6

            for ($i = 1; $i -le $MaxRetries; $i++) {
                try {
                    Remove-Item -Path $VSSExtractPath -Recurse -Force -ErrorAction Stop
                    break
                }
                catch {
                    if ($i -lt $MaxRetries) {
                        Write-Log  "Folder locked (attempt $i/$MaxRetries), retrying in ${RetryDelaySec}s: $_" -Severity WARN
                        Write-Console "Folder locked, retrying in ${RetryDelaySec}s... ($i/$MaxRetries)" -Severity WARN -Indent 1
                        Start-Sleep -Seconds $RetryDelaySec
                    }
                    else {
                        throw "Could not remove extract folder after $MaxRetries attempts. Last error: $_"
                    }
                }
            }
        }

        New-Item -ItemType Directory -Path $VSSExtractPath -Force | Out-Null

        Write-Log  "Extracting ZIP to: $VSSExtractPath" -Severity INFO
        Write-Console "Extracting installer ZIP..." -Severity INFO

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($VSSZipPath, $VSSExtractPath)

        Write-Log  "Extraction complete." -Severity SUCCESS
        Write-Console "Extraction complete." -Severity SUCCESS -Indent 1
    }

    # ==========================================================================
    # HELPER: Invoke-VSSInstaller
    # Runs the setup executable silently via Start-Process as SYSTEM.
    #
    # The VSS installer requires a valid local admin account passed via its own
    # /username and /password flags. Without these it returns exit code 2
    # regardless of what user launches it. /component=c is always required for
    # silent client installs.
    #
    # When -UseSetupAccount is set:
    #   Arguments: /S /component=c /username=Setup /password="<password>"
    # When not set (manual interactive runs as admin):
    #   Arguments: /S /component=c
    #
    # Exit code 3010 = success + reboot required, treated as success.
    # ==========================================================================
    function Invoke-VSSInstaller {
        param (
            [string]$AccountName     = "",
            [string]$AccountPassword = ""
        )

        if (-not (Test-Path $VSSExePath)) {
            throw "Installer executable not found after extraction: $VSSExePath"
        }

        # Build argument string — always include /S /component=c
        # Add /username and /password when Setup account credentials are supplied
        if ($AccountName -and $AccountPassword) {
            $InstallerArgs    = "/S /component=c /username=$AccountName /password=`"$AccountPassword`""
            $InstallerArgsSafe = "/S /component=c /username=$AccountName /password=[supplied]"
        }
        else {
            $InstallerArgs    = "/S /component=c"
            $InstallerArgsSafe = "/S /component=c"
        }

        Write-Log  "Launching installer: $VSSExeName $InstallerArgsSafe" -Severity INFO
        Write-Console "Running silent installer..." -Severity INFO

        $Process = Start-Process `
            -FilePath        $VSSExePath `
            -ArgumentList    $InstallerArgs `
            -Wait `
            -PassThru `
            -WorkingDirectory $VSSExtractPath

        $ExitCode = $Process.ExitCode

        Write-Log  "Installer exited with code: $ExitCode" -Severity DEBUG
        Write-Console "Installer exit code: $ExitCode" -Severity DEBUG -Indent 1

        if ($ExitCode -eq 0) {
            Write-Log  "Installation completed successfully." -Severity SUCCESS
            Write-Console "Installation completed successfully." -Severity SUCCESS
        }
        elseif ($ExitCode -eq 3010) {
            Write-Log  "Installation succeeded. A reboot is required to complete setup." -Severity WARN
            Write-Console "Installation succeeded. Reboot required." -Severity WARN
        }
        else {
            throw "Installer returned non-zero exit code: $ExitCode"
        }
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    $RunAs         = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $PasswordState = if ($SetupAccountPassword) { '[supplied]' } else { '[not supplied]' }

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName"  -Severity INFO
    Write-Log "Hostname : $Hostname"  -Severity INFO
    Write-Log "Run As   : $RunAs"     -Severity INFO
    Write-Log "Params   : Force=$Force | UseSetupAccount=$UseSetupAccount | SetupAccountPassword=$PasswordState" -Severity INFO
    Write-Log "Log File : $LogFile"   -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site     : $SiteName"  -Severity PLAIN
    Write-Console "Hostname : $Hostname"  -Severity PLAIN
    Write-Console "Run As   : $RunAs"     -Severity PLAIN
    Write-Console "Log File : $LogFile"   -Severity PLAIN
    Write-Separator

    try {

        # ------------------------------------------------------------------
        # PHASE 1 — Install Detection
        # ------------------------------------------------------------------
        Write-Section "Install Detection"
        Write-Log  "Checking for existing VSS installation..." -Severity INFO
        Write-Console "Checking for existing VSS installation..." -Severity INFO

        $ExistingEntry = Get-VSSInstallEntry

        if ($ExistingEntry) {
            $InstalledVersion = $ExistingEntry.DisplayVersion
            $InstalledName    = $ExistingEntry.DisplayName

            Write-Log  "VSS detected: '$InstalledName' v$InstalledVersion" -Severity INFO
            Write-Console "VSS detected: '$InstalledName' v$InstalledVersion" -Severity INFO -Indent 1

            if (-not $Force) {
                Write-Log  "VSS is already installed. Skipping. Use -Force or VSS_Force=true to override." -Severity WARN
                Write-Console "Already installed. Skipping. Use -Force to reinstall." -Severity WARN
                Write-Banner "SKIPPED - ALREADY INSTALLED" -Color "Yellow"
                exit 2
            }
            else {
                Write-Log  "-Force is set. Proceeding with installation over existing install." -Severity WARN
                Write-Console "-Force specified. Proceeding with install over existing version." -Severity WARN
            }
        }
        else {
            Write-Log  "No existing VSS installation detected. Proceeding." -Severity INFO
            Write-Console "No existing installation found. Proceeding." -Severity SUCCESS -Indent 1
        }

        # ------------------------------------------------------------------
        # PHASE 2 — Installer Credential Validation
        # When -UseSetupAccount is set, verify the password was supplied.
        # The credentials are passed directly to the installer as /username
        # and /password arguments — no account switching or token change needed.
        # ------------------------------------------------------------------
        $InstallerAccountName     = ""
        $InstallerAccountPassword = ""

        if ($UseSetupAccount) {
            Write-Section "Installer Credential Validation"
            Write-Log  "UseSetupAccount is set. Credentials will be passed to installer as /username/$SetupAccountName /password=..." -Severity INFO
            Write-Console "UseSetupAccount set. Validating password was supplied..." -Severity INFO

            if ([string]::IsNullOrWhiteSpace($SetupAccountPassword)) {
                Write-Log  "SetupAccountPassword was not supplied. Required when UseSetupAccount is set." -Severity ERROR
                Write-Console "No password supplied for installer /username/$SetupAccountName flag." -Severity ERROR
                Write-Banner "SCRIPT FAILED - NO PASSWORD SUPPLIED" -Color "Red"
                exit 3
            }

            $InstallerAccountName     = $SetupAccountName
            $InstallerAccountPassword = $SetupAccountPassword

            Write-Log  "Installer will run with /username=$SetupAccountName /password=[supplied] /component=c." -Severity SUCCESS
            Write-Console "Credentials ready. Installer args: /username=$SetupAccountName /password=[supplied]." -Severity SUCCESS -Indent 1
        }
        else {
            Write-Log  "UseSetupAccount not set. Installer will run with /S /component=c only." -Severity DEBUG
            Write-Console "No credentials. Installer will run with /S /component=c only." -Severity DEBUG -Indent 1
        }

        # ------------------------------------------------------------------
        # PHASE 3 — Download
        # ------------------------------------------------------------------
        Write-Section "Download"
        Write-Log  "Staging path : $StagingRoot"    -Severity INFO
        Write-Log  "Download URL : $VSSDownloadUrl" -Severity INFO
        Write-Log  "ZIP target   : $VSSZipPath"     -Severity INFO
        Write-Console "Staging path : $StagingRoot"    -Severity PLAIN
        Write-Console "Download URL : $VSSDownloadUrl" -Severity PLAIN

        Invoke-VSSDownload

        if (-not (Test-Path $VSSZipPath)) {
            throw "Download appeared to succeed but ZIP file not found at: $VSSZipPath"
        }

        $ZipSizeMB = [Math]::Round((Get-Item $VSSZipPath).Length / 1MB, 2)
        Write-Log  "ZIP size: $ZipSizeMB MB" -Severity DEBUG
        Write-Console "ZIP size: $ZipSizeMB MB" -Severity DEBUG -Indent 1

        if ($ZipSizeMB -lt 1) {
            throw "Downloaded ZIP is suspiciously small ($ZipSizeMB MB). Download may have failed or returned an error page."
        }

        # ------------------------------------------------------------------
        # PHASE 4 — Extract
        # ------------------------------------------------------------------
        Write-Section "Extract"
        Write-Log  "Extract path : $VSSExtractPath" -Severity INFO
        Write-Console "Extract path : $VSSExtractPath" -Severity PLAIN

        Expand-VSSZip

        if (-not (Test-Path $VSSExePath)) {
            Write-Log  "Installer not found at expected path. Searching staging area..." -Severity WARN
            Write-Console "Installer not at expected path. Searching..." -Severity WARN -Indent 1

            $FoundExe = Get-ChildItem -Path $StagingRoot -Filter $VSSExeName -Recurse -ErrorAction SilentlyContinue |
                        Select-Object -First 1

            if ($FoundExe) {
                Write-Log  "Found installer at alternate path: $($FoundExe.FullName)" -Severity INFO
                Write-Console "Found installer: $($FoundExe.FullName)" -Severity INFO -Indent 1
                Set-Variable -Name VSSExePath -Value $FoundExe.FullName -Scope Script
            }
            else {
                throw "Installer executable '$VSSExeName' not found anywhere under $StagingRoot after extraction."
            }
        }
        else {
            Write-Log  "Installer confirmed at: $VSSExePath" -Severity DEBUG
            Write-Console "Installer confirmed." -Severity SUCCESS -Indent 1
        }

        # ------------------------------------------------------------------
        # PHASE 5 — Install
        # ------------------------------------------------------------------
        Write-Section "Install"
        Write-Log  "Installer : $VSSExePath"    -Severity INFO
        Write-Log  "Arguments : $VSSSilentArgs" -Severity INFO
        Write-Console "Installer : $VSSExeName"    -Severity PLAIN
        Write-Console "Arguments : $VSSSilentArgs" -Severity PLAIN

        Invoke-VSSInstaller -AccountName $InstallerAccountName -AccountPassword $InstallerAccountPassword

        # ------------------------------------------------------------------
        # PHASE 6 — Post-Install Verification
        # ------------------------------------------------------------------
        Write-Section "Post-Install Verification"
        Write-Log  "Verifying VSS appears in installed software registry..." -Severity INFO
        Write-Console "Verifying installation registry entry..." -Severity INFO

        # Give the installer a moment to finalize registry writes
        Start-Sleep -Seconds 5

        $VerifyEntry = Get-VSSInstallEntry

        if ($VerifyEntry) {
            $VerVersion = $VerifyEntry.DisplayVersion
            Write-Log  "Verification passed: '$($VerifyEntry.DisplayName)' v$VerVersion found in registry." -Severity SUCCESS
            Write-Console "Verification passed: VSS v$VerVersion registered." -Severity SUCCESS
        }
        else {
            Write-Log  "VSS not found in registry after install. May require a reboot to finalize." -Severity WARN
            Write-Console "Registry entry not found post-install. May require a reboot." -Severity WARN
        }

        # ------------------------------------------------------------------
        # Done
        # ------------------------------------------------------------------
        Write-Log "Script completed successfully." -Severity SUCCESS
        Write-Banner "COMPLETED SUCCESSFULLY" -Color "Green"

        exit 0

    }
    catch {
        Write-Log "Unhandled exception: $_"             -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR

        Write-Banner "SCRIPT FAILED" -Color "Red"
        Write-Console "Error : $_"   -Severity ERROR

        exit 1
    }

} # End function Install-VSSApplication

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    Force                = $Force
    UseSetupAccount      = $UseSetupAccount
    SetupAccountPassword = $SetupAccountPassword
    SiteName             = $SiteName
    Hostname             = $Hostname
}

Install-VSSApplication @ScriptParams
