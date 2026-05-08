#Requires -Version 5.1
<#
.SYNOPSIS
    Removes ThirdWall security policies from an endpoint using TWUndo.exe.

.DESCRIPTION
    Downloads TWUndo.exe and thirdwall.dll from the Third Wall license server,
    copies Interfaces.dll from the DattoRMM component working directory, stages
    all three files to %windir%\ltsvc (creating the directory if it does not
    exist), then executes TWUndo.exe with the specified policy IDs to remove
    ThirdWall policy enforcement from the machine.

    Designed for use in offboarding scenarios where ConnectWise Automate and
    ThirdWall are no longer installed on the endpoint. TWUndo.exe is a standalone
    utility provided by Third Wall that reverses policy enforcement without
    requiring a running Automate agent.

    COMPONENT FILE REQUIREMENT:
    Interfaces.dll must be added to the DattoRMM component Files tab before
    deployment. DattoRMM delivers component files to the agent working directory
    at runtime. The script locates Interfaces.dll in that working directory
    (the directory containing this script) and copies it to %windir%\ltsvc.
    The script will fail pre-flight if Interfaces.dll is not present.

    Policy IDs are passed as a comma-separated string (e.g. "19,20,21,22").
    TWUndo.exe is invoked with each ID as a separate slash argument
    (e.g. TWUndo.exe /19 /20 /21 /22).

    NOTE: Policies 19-22 (USB and Optical device restrictions) are machine-level
    policies and do not require a logged-on user. If you are removing user-context
    policies (see ThirdWall KB for which IDs are user policies), the affected user
    must be signed on at the time of execution.

.PARAMETER PolicyIds
    Comma-separated list of ThirdWall policy IDs to remove.
    Example: "19,20,21,22"
    Required. At least one valid integer ID must be provided.

.PARAMETER SiteName
    DattoRMM site/customer name. Populated automatically from CS_PROFILE_NAME
    environment variable when run via DattoRMM agent.

.PARAMETER Hostname
    Target machine hostname. Populated automatically from CS_HOSTNAME
    environment variable when run via DattoRMM agent.

.EXAMPLE
    .\Invoke-ThirdWallUndo.ps1 -PolicyIds "19,20,21,22"
    Removes the four USB/Optical device restriction policies.

.EXAMPLE
    .\Invoke-ThirdWallUndo.ps1 -PolicyIds "19,20,21,22" -SiteName "Acme Corp" -Hostname "DESKTOP-01"
    Same operation with explicit site and hostname metadata for log context.

.NOTES
    File Name      : Invoke-ThirdWallUndo.ps1
    Version        : v1.2.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-05-07
    Last Modified  : 2026-05-07
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM (DattoRMM agent context)
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : Client-specific (offboarding scenario)

    Exit Codes:
        0  - Success — all specified policies removed successfully
        1  - Runtime failure — TWUndo.exe ran but one or more policies failed,
             or an unhandled exception occurred during execution
        2  - Fatal pre-flight failure — missing/invalid parameters, download
             failed, or required files could not be staged

    Output Design:
        Write-Log     - Structured [timestamp][SEVERITY] output to log file AND
                        DattoRMM stdout. Always verbose. No color.
        Write-Console - Human-friendly colored console output for manual/interactive
                        runs. Uses Write-Host (display stream only). Suppressed in
                        DattoRMM agent context automatically.

    ThirdWall Download Sources:
        TWUndo.exe    : https://license.third-wall.com/dl/TWUndo.exe
        thirdwall.dll : https://license.third-wall.com/dl/thirdwall.dll

    Component File Requirements:
        Interfaces.dll - Must be added to the DattoRMM component Files tab.
                         Sourced from an existing Automate endpoint's
                         %windir%\ltsvc directory.

.CHANGELOG
    v1.2.0.0 - 2026-05-07 - Sam Kirsch
        - Fixed null $MyInvocation.MyCommand.Path when DattoRMM executes via
          agent pipe. Replaced with three-stage fallback chain:
          $PSScriptRoot -> $MyInvocation.ScriptName -> $PWD.Path
          $PWD is reliable because DattoRMM sets CWD to the package directory.

    v1.1.0.0 - 2026-05-07 - Sam Kirsch
        - Added Interfaces.dll staging from DattoRMM component working directory
        - Pre-flight now validates Interfaces.dll presence before proceeding
        - Interfaces.dll copied to %windir%\ltsvc alongside TWUndo.exe and thirdwall.dll
        - Updated .DESCRIPTION and .NOTES to document component file requirement
        - Updated file verification block to cover all three required files

    v1.0.0.0 - 2026-05-07 - Sam Kirsch
        - Initial release
        - Downloads TWUndo.exe and thirdwall.dll from Third Wall license server
        - Creates %windir%\ltsvc directory if not present
        - Parses comma-separated PolicyIds parameter into TWUndo slash arguments
        - Full pre-flight validation: parameter presence, integer parsing, file staging
        - Rich per-policy outcome logging with TWUndo stdout/stderr capture
        - TLS 1.2 enforcement for downloads
        - Log rotation: keeps last 10 log files per script
#>

# ==============================================================================
# ORDER IS NON-NEGOTIABLE: [CmdletBinding()] then TLS block then param()
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$PolicyIds = $(
        if ($env:PolicyIds) { $env:PolicyIds } else { "" }
    ),

    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(
        if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }
    ),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(
        if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME }
    )
)

[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
function Invoke-ThirdWallUndo {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$PolicyIds,

        [Parameter(Mandatory = $false)]
        [string]$SiteName,

        [Parameter(Mandatory = $false)]
        [string]$Hostname
    )

    # ==========================================================================
    # SCRIPT METADATA
    # ==========================================================================
    $ScriptName    = 'Invoke-ThirdWallUndo'
    $ScriptVersion = 'v1.2.0.0'

    # ==========================================================================
    # CONSTANTS
    # ==========================================================================
    $LtSvcPath          = Join-Path $env:windir 'ltsvc'
    $TWUndoUrl          = 'https://license.third-wall.com/dl/TWUndo.exe'
    $ThirdWallDllUrl    = 'https://license.third-wall.com/dl/thirdwall.dll'
    $TWUndoPath         = Join-Path $LtSvcPath 'TWUndo.exe'
    $ThirdWallDllPath   = Join-Path $LtSvcPath 'thirdwall.dll'
    $InterfacesDllDest  = Join-Path $LtSvcPath 'Interfaces.dll'

    # DattoRMM delivers component files to the same directory as command.ps1.
    # $MyInvocation.MyCommand.Path is null when DattoRMM pipes the script through
    # its agent executor, so we use a fallback chain to reliably resolve the
    # component working directory:
    #   1. $PSScriptRoot           -- set when script is dot-sourced or run as file
    #   2. MyInvocation.ScriptName -- sometimes populated when Path is not
    #   3. $PWD                    -- DattoRMM sets CWD to the package directory
    $ComponentWorkDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $PSScriptRoot
    }
    elseif (-not [string]::IsNullOrWhiteSpace($MyInvocation.ScriptName)) {
        Split-Path -Parent $MyInvocation.ScriptName
    }
    else {
        $PWD.Path
    }
    $InterfacesDllSource = Join-Path $ComponentWorkDir 'Interfaces.dll'

    # Policy ID reference map for rich log output
    $PolicyMap = @{
        2  = 'Rename Local Administrator Account'
        3  = 'Set Local Administrator Password'
        4  = 'Disable Local Administrator Account'
        5  = 'Enable Minimum Password Length'
        6  = 'Enable Maximum Password Age'
        7  = 'Enable Password Protected Screen Saver'
        8  = 'Restrict Local Administrator Tools'
        9  = 'Enable UAC'
        10 = 'Disable Setup.exe and Install.exe'
        11 = 'Disable Windows Installer'
        12 = 'Disable Windows 10 Keylogger'
        13 = 'Enable Logon Message'
        15 = 'Enable Smart Screen'
        16 = 'Enable UPnP'
        17 = 'Disable AutoPlay (AutoRun)'
        18 = 'Disable Running Exe from APPDATA'
        19 = 'Disable Write to Optical Devices'
        20 = 'Disable Read and Write to Optical Devices'
        21 = 'Disable Write to USB Storage Devices'
        22 = 'Disable Read and Write to USB Storage Devices'
        23 = 'Disable Cloud Storage'
        24 = 'Schedule Free Space Delete'
        26 = 'Uninstall Blacklisted Software'
        27 = 'Enforce Complex Passwords'
        28 = 'Block Common Webmail'
        29 = 'Block Social Media'
        30 = 'Disable Windows Store'
        31 = 'Disable Google Play'
        32 = 'Disable Apple App Store'
        33 = 'Disable Office Macros Downloaded from the Internet'
        34 = 'Disable OLE in Office Documents'
        35 = 'Enable Windows Firewall - Workstations'
        36 = 'Enable Windows Firewall - Servers'
        37 = 'Disable Local LM Hash Storage'
        38 = 'Audit All NTLM Traffic'
        39 = 'Disable LM NTLM v1'
        40 = 'Disable NetBios'
        41 = 'Disable IPv6'
        42 = 'Disable IGMP'
        43 = 'Disable SMB v1'
        44 = 'Log All Logon Events'
        45 = 'Enhance Security Logging'
        46 = 'Monitor Event Log Clearing'
        47 = 'Alert on Excessive Logon Failures'
        48 = 'Monitor for Ransomware Attack'
        49 = 'Alert on Unencrypted Disk'
        50 = 'Enable User Logon Reporting'
        51 = 'Disable Guest Account'
        52 = 'Disable Microsoft Accounts'
        53 = 'Enable USB Wall'
        54 = 'Disable Terminal Server Services'
        55 = 'Enable USB Watch'
        56 = 'Enable TWAPS'
        57 = 'Clear Windows Pagefile on Reboot'
        58 = 'Enable Registry Backup'
    }

    # ==========================================================================
    # LOGGING INFRASTRUCTURE
    # ==========================================================================
    $LogRoot  = 'C:\Databranch\ScriptLogs'
    $LogDir   = Join-Path $LogRoot $ScriptName
    $LogDate  = Get-Date -Format 'yyyy-MM-dd'
    $LogFile  = Join-Path $LogDir "${ScriptName}_${LogDate}.log"

    function Initialize-Logging {
        if (-not (Test-Path -Path $LogDir)) {
            New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
        }

        # Log rotation — keep last 10
        $ExistingLogs = Get-ChildItem -Path $LogDir -Filter "*.log" -ErrorAction SilentlyContinue |
            Sort-Object -Property LastWriteTime -Descending
        if ($ExistingLogs.Count -ge 10) {
            $ExistingLogs | Select-Object -Skip 9 | ForEach-Object {
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

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

    function Write-Console {
        param (
            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string]$Message = "",

            [Parameter(Mandatory = $false)]
            [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG", "PLAIN")]
            [string]$Severity = "INFO",

            [Parameter(Mandatory = $false)]
            [int]$Indent = 0
        )

        $Colors = @{
            INFO    = 'Cyan'
            WARN    = 'Yellow'
            ERROR   = 'Red'
            SUCCESS = 'Green'
            DEBUG   = 'Magenta'
            PLAIN   = 'Gray'
        }

        $Prefix = switch ($Severity) {
            "INFO"    { "[INFO]    " }
            "WARN"    { "[WARN]    " }
            "ERROR"   { "[ERROR]   " }
            "SUCCESS" { "[SUCCESS] " }
            "DEBUG"   { "[DEBUG]   " }
            "PLAIN"   { "          " }
        }

        $Pad  = " " * ($Indent * 2)
        $Line = if ($Severity -eq "PLAIN") { "$Pad$Message" } else { "$Pad$Prefix$Message" }
        Write-Host $Line -ForegroundColor $Colors[$Severity]
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
        Write-Host $Line      -ForegroundColor $Color
        Write-Host "  $Title" -ForegroundColor White
        Write-Host $Line      -ForegroundColor $Color
        Write-Host ""
    }

    function Write-Section {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Title
        )
        Write-Host ""
        Write-Host "--- $Title ---" -ForegroundColor DarkCyan
        Write-Host ""
    }

    function Write-Separator {
        Write-Host ("-" * 60) -ForegroundColor DarkGray
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log "===== $ScriptName $ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName"                   -Severity INFO
    Write-Log "Hostname : $Hostname"                   -Severity INFO
    Write-Log "Run As   : $RunAs"                      -Severity INFO
    Write-Log "Log File : $LogFile"                    -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) $ScriptVersion"
    Write-Console "Site     : $SiteName"  -Severity PLAIN
    Write-Console "Hostname : $Hostname"  -Severity PLAIN
    Write-Console "Run As   : $RunAs"     -Severity PLAIN
    Write-Console "Log File : $LogFile"   -Severity PLAIN
    Write-Separator

    try {

        # ------------------------------------------------------------------
        # PRE-FLIGHT VALIDATION
        # ------------------------------------------------------------------
        Write-Section 'Pre-Flight Validation'
        Write-Log "Starting pre-flight validation." -Severity INFO
        Write-Console "Starting pre-flight validation." -Severity INFO

        $preFlightFailed = $false

        # Validate PolicyIds parameter
        if ([string]::IsNullOrWhiteSpace($PolicyIds)) {
            Write-Log "PolicyIds parameter is required but was not provided." -Severity ERROR
            Write-Console "PolicyIds parameter is required but was not provided." -Severity ERROR
            $preFlightFailed = $true
        }
        else {
            # Parse and validate each ID is a positive integer
            $ParsedIds = New-Object -TypeName 'System.Collections.Generic.List[int]'
            $RawIds = $PolicyIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

            foreach ($RawId in $RawIds) {
                $Parsed = 0
                if ([int]::TryParse($RawId, [ref]$Parsed) -and $Parsed -gt 0) {
                    $ParsedIds.Add($Parsed)
                }
                else {
                    Write-Log "PolicyIds contains invalid value: '$RawId' — must be a positive integer." -Severity ERROR
                    Write-Console "PolicyIds contains invalid value: '$RawId' — must be a positive integer." -Severity ERROR
                    $preFlightFailed = $true
                }
            }

            if (-not $preFlightFailed -and $ParsedIds.Count -eq 0) {
                Write-Log "PolicyIds resolved to zero valid entries after parsing." -Severity ERROR
                Write-Console "PolicyIds resolved to zero valid entries after parsing." -Severity ERROR
                $preFlightFailed = $true
            }
        }

        if ($preFlightFailed) {
            Write-Log "Pre-flight validation failed. Exiting." -Severity ERROR
            Write-Banner "SCRIPT FAILED — PRE-FLIGHT" -Color "Red"
            exit 2
        }

        Write-Log "PolicyIds parsed successfully. Policies to remove: $($ParsedIds -join ', ')" -Severity INFO
        Write-Console "PolicyIds parsed successfully. Policies to remove: $($ParsedIds -join ', ')" -Severity INFO

        # Log friendly names for each requested policy
        foreach ($Id in $ParsedIds) {
            $FriendlyName = if ($PolicyMap.ContainsKey($Id)) { $PolicyMap[$Id] } else { 'Unknown Policy' }
            Write-Log "  Policy $Id : $FriendlyName" -Severity DEBUG
            Write-Console "  Policy $Id : $FriendlyName" -Severity DEBUG -Indent 1
        }

        # Validate Interfaces.dll is present in the component working directory
        Write-Log "Checking for Interfaces.dll in component working directory: $ComponentWorkDir" -Severity INFO
        Write-Console "Checking for Interfaces.dll in component working directory..." -Severity INFO

        if (-not (Test-Path -Path $InterfacesDllSource)) {
            Write-Log "Interfaces.dll not found at expected path: $InterfacesDllSource" -Severity ERROR
            Write-Log "Interfaces.dll must be added to the DattoRMM component Files tab before deployment." -Severity ERROR
            Write-Console "Interfaces.dll not found. Add it to the DattoRMM component Files tab." -Severity ERROR
            Write-Banner "SCRIPT FAILED — PRE-FLIGHT" -Color "Red"
            exit 2
        }

        $InterfacesSizeKB = [math]::Round((Get-Item -Path $InterfacesDllSource).Length / 1KB, 1)
        Write-Log "Interfaces.dll found in component directory. Size: ${InterfacesSizeKB} KB" -Severity INFO
        Write-Console "Interfaces.dll found. (${InterfacesSizeKB} KB)" -Severity INFO

        Write-Log "Pre-flight validation passed." -Severity SUCCESS
        Write-Console "Pre-flight validation passed." -Severity SUCCESS

        # ------------------------------------------------------------------
        # STAGE WORKING DIRECTORY
        # ------------------------------------------------------------------
        Write-Section 'Staging Working Directory'
        Write-Log "Target staging directory: $LtSvcPath" -Severity INFO
        Write-Console "Target staging directory: $LtSvcPath" -Severity INFO

        if (-not (Test-Path -Path $LtSvcPath)) {
            Write-Log "Directory does not exist. Creating: $LtSvcPath" -Severity INFO
            Write-Console "Directory does not exist. Creating: $LtSvcPath" -Severity INFO
            New-Item -Path $LtSvcPath -ItemType Directory -Force | Out-Null
            Write-Log "Directory created successfully." -Severity SUCCESS
            Write-Console "Directory created successfully." -Severity SUCCESS
        }
        else {
            Write-Log "Directory already exists: $LtSvcPath" -Severity INFO
            Write-Console "Directory already exists: $LtSvcPath" -Severity INFO
        }

        # ------------------------------------------------------------------
        # DOWNLOAD REQUIRED FILES
        # ------------------------------------------------------------------
        Write-Section 'Downloading ThirdWall Files'

        $FilesToDownload = @(
            @{ Url = $TWUndoUrl;       Dest = $TWUndoPath;       Name = 'TWUndo.exe'    },
            @{ Url = $ThirdWallDllUrl; Dest = $ThirdWallDllPath; Name = 'thirdwall.dll' }
        )

        foreach ($FileEntry in $FilesToDownload) {
            Write-Log "Downloading $($FileEntry.Name) from $($FileEntry.Url)" -Severity INFO
            Write-Console "Downloading $($FileEntry.Name) ..." -Severity INFO

            try {
                $WebClient = New-Object -TypeName System.Net.WebClient
                $WebClient.DownloadFile($FileEntry.Url, $FileEntry.Dest)
                $WebClient.Dispose()

                if (Test-Path -Path $FileEntry.Dest) {
                    $FileSizeKB = [math]::Round((Get-Item -Path $FileEntry.Dest).Length / 1KB, 1)
                    Write-Log "$($FileEntry.Name) downloaded successfully. Size: ${FileSizeKB} KB. Path: $($FileEntry.Dest)" -Severity SUCCESS
                    Write-Console "$($FileEntry.Name) downloaded successfully. (${FileSizeKB} KB)" -Severity SUCCESS
                }
                else {
                    Write-Log "$($FileEntry.Name) download reported success but file not found at destination: $($FileEntry.Dest)" -Severity ERROR
                    Write-Console "$($FileEntry.Name) not found after download attempt." -Severity ERROR
                    Write-Banner "SCRIPT FAILED — DOWNLOAD" -Color "Red"
                    exit 2
                }
            }
            catch {
                Write-Log "Failed to download $($FileEntry.Name): $_" -Severity ERROR
                Write-Console "Failed to download $($FileEntry.Name): $_" -Severity ERROR
                Write-Banner "SCRIPT FAILED — DOWNLOAD" -Color "Red"
                exit 2
            }
        }

        # ------------------------------------------------------------------
        # VERIFY EXECUTABLE INTEGRITY (basic existence check)
        # ------------------------------------------------------------------
        Write-Section 'File Verification'

        foreach ($FileEntry in $FilesToDownload) {
            if (Test-Path -Path $FileEntry.Dest) {
                Write-Log "Verified present: $($FileEntry.Dest)" -Severity INFO
                Write-Console "Verified: $($FileEntry.Name)" -Severity INFO
            }
            else {
                Write-Log "Required file missing after staging: $($FileEntry.Dest)" -Severity ERROR
                Write-Console "Required file missing: $($FileEntry.Name)" -Severity ERROR
                Write-Banner "SCRIPT FAILED — FILE VERIFICATION" -Color "Red"
                exit 2
            }
        }

        Write-Log "All required files verified." -Severity SUCCESS
        Write-Console "All required files verified." -Severity SUCCESS

        # ------------------------------------------------------------------
        # COPY INTERFACES.DLL FROM COMPONENT WORKING DIRECTORY
        # ------------------------------------------------------------------
        Write-Section 'Staging Interfaces.dll'

        Write-Log "Copying Interfaces.dll from component directory to ltsvc..." -Severity INFO
        Write-Log "  Source : $InterfacesDllSource" -Severity INFO
        Write-Log "  Dest   : $InterfacesDllDest"   -Severity INFO
        Write-Console "Copying Interfaces.dll to $LtSvcPath ..." -Severity INFO

        try {
            Copy-Item -Path $InterfacesDllSource -Destination $InterfacesDllDest -Force
            $CopiedSizeKB = [math]::Round((Get-Item -Path $InterfacesDllDest).Length / 1KB, 1)
            Write-Log "Interfaces.dll staged successfully. Size: ${CopiedSizeKB} KB" -Severity SUCCESS
            Write-Console "Interfaces.dll staged successfully. (${CopiedSizeKB} KB)" -Severity SUCCESS
        }
        catch {
            Write-Log "Failed to copy Interfaces.dll to ltsvc: $_" -Severity ERROR
            Write-Console "Failed to copy Interfaces.dll: $_" -Severity ERROR
            Write-Banner "SCRIPT FAILED — INTERFACES.DLL STAGING" -Color "Red"
            exit 2
        }
        Write-Section 'Executing TWUndo'

        $TWUndoArgs = $ParsedIds | ForEach-Object { "/$_" }
        $TWUndoArgString = $TWUndoArgs -join ' '

        Write-Log "TWUndo.exe path   : $TWUndoPath"       -Severity INFO
        Write-Log "TWUndo.exe args   : $TWUndoArgString"  -Severity INFO
        Write-Log "Working directory : $LtSvcPath"        -Severity INFO
        Write-Console "Invoking: TWUndo.exe $TWUndoArgString" -Severity INFO

        # ------------------------------------------------------------------
        # LOG POLICY INTENT BEFORE EXECUTION
        # ------------------------------------------------------------------
        Write-Log "Policies targeted for removal:" -Severity INFO
        foreach ($Id in $ParsedIds) {
            $FriendlyName = if ($PolicyMap.ContainsKey($Id)) { $PolicyMap[$Id] } else { 'Unknown Policy' }
            Write-Log "  /$Id => $FriendlyName" -Severity INFO
            Write-Console "  /$Id => $FriendlyName" -Severity INFO -Indent 1
        }

        # ------------------------------------------------------------------
        # EXECUTE TWUNDO.EXE
        # Run from the ltsvc directory so thirdwall.dll resolves correctly
        # as a same-directory dependency.
        # ------------------------------------------------------------------
        $PriorLocation = Get-Location
        Set-Location -Path $LtSvcPath

        $StartInfo = New-Object -TypeName System.Diagnostics.ProcessStartInfo
        $StartInfo.FileName               = $TWUndoPath
        $StartInfo.Arguments              = $TWUndoArgString
        $StartInfo.WorkingDirectory       = $LtSvcPath
        $StartInfo.UseShellExecute        = $false
        $StartInfo.RedirectStandardOutput = $true
        $StartInfo.RedirectStandardError  = $true
        $StartInfo.CreateNoWindow         = $true

        $Process = New-Object -TypeName System.Diagnostics.Process
        $Process.StartInfo = $StartInfo

        Write-Log "Starting TWUndo.exe process..." -Severity INFO
        $null = $Process.Start()
        $Process.WaitForExit()

        $StdOut   = $Process.StandardOutput.ReadToEnd().Trim()
        $StdErr   = $Process.StandardError.ReadToEnd().Trim()
        $ExitCode = $Process.ExitCode

        Set-Location -Path $PriorLocation

        Write-Log "TWUndo.exe process completed. Exit code: $ExitCode" -Severity INFO

        # Emit stdout verbatim — each line individually so DattoRMM renders cleanly
        if (-not [string]::IsNullOrWhiteSpace($StdOut)) {
            Write-Log "--- TWUndo.exe STDOUT ---" -Severity INFO
            Write-Console "--- TWUndo.exe STDOUT ---" -Severity INFO
            foreach ($StdOutLine in ($StdOut -split "`n")) {
                $CleanLine = $StdOutLine.TrimEnd()
                if (-not [string]::IsNullOrWhiteSpace($CleanLine)) {
                    Write-Log "  $CleanLine" -Severity INFO
                    Write-Console "  $CleanLine" -Severity PLAIN -Indent 1
                }
            }
        }
        else {
            Write-Log "TWUndo.exe produced no stdout output." -Severity DEBUG
            Write-Console "TWUndo.exe produced no stdout output." -Severity DEBUG
        }

        # Emit stderr
        if (-not [string]::IsNullOrWhiteSpace($StdErr)) {
            Write-Log "--- TWUndo.exe STDERR ---" -Severity WARN
            Write-Console "--- TWUndo.exe STDERR ---" -Severity WARN
            foreach ($StdErrLine in ($StdErr -split "`n")) {
                $CleanLine = $StdErrLine.TrimEnd()
                if (-not [string]::IsNullOrWhiteSpace($CleanLine)) {
                    Write-Log "  $CleanLine" -Severity WARN
                    Write-Console "  $CleanLine" -Severity WARN -Indent 1
                }
            }
        }

        # ------------------------------------------------------------------
        # INTERPRET EXIT CODE
        # ------------------------------------------------------------------
        Write-Section 'Result'

        if ($ExitCode -eq 0) {
            Write-Log "TWUndo.exe exited with code 0 — policies removed successfully." -Severity SUCCESS
            Write-Console "TWUndo.exe exited with code 0 — policies removed successfully." -Severity SUCCESS
        }
        else {
            Write-Log "TWUndo.exe exited with non-zero code: $ExitCode — one or more policies may not have been removed. Review STDOUT/STDERR above." -Severity WARN
            Write-Console "TWUndo.exe exited with non-zero code: $ExitCode — review output above." -Severity WARN
        }

        # ------------------------------------------------------------------
        # SUMMARY
        # ------------------------------------------------------------------
        Write-Section 'Summary'

        Write-Log "Policies submitted to TWUndo.exe: $($ParsedIds.Count)" -Severity INFO
        Write-Log "Policy IDs processed: $($ParsedIds -join ', ')"        -Severity INFO
        Write-Log "TWUndo.exe exit code: $ExitCode"                       -Severity INFO

        foreach ($Id in $ParsedIds) {
            $FriendlyName = if ($PolicyMap.ContainsKey($Id)) { $PolicyMap[$Id] } else { 'Unknown Policy' }
            Write-Log "  Policy $Id ($FriendlyName) — submitted" -Severity INFO
            Write-Console "  Policy $Id ($FriendlyName)" -Severity INFO -Indent 1
        }

        if ($ExitCode -eq 0) {
            Write-Log "ThirdWall policy removal completed successfully." -Severity SUCCESS
            Write-Banner "COMPLETED SUCCESSFULLY" -Color "Green"
            exit 0
        }
        else {
            Write-Log "ThirdWall policy removal completed with warnings. Exit code from TWUndo.exe: $ExitCode" -Severity WARN
            Write-Banner "COMPLETED WITH WARNINGS" -Color "Yellow"
            exit 1
        }

    }
    catch {
        Write-Log "Unhandled exception: $_"             -Severity ERROR
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Console "Unhandled exception: $_"         -Severity ERROR
        Write-Banner "SCRIPT FAILED" -Color "Red"
        exit 1
    }

} # End function Invoke-ThirdWallUndo

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    PolicyIds = $PolicyIds
    SiteName  = $SiteName
    Hostname  = $Hostname
}

Invoke-ThirdWallUndo @ScriptParams
