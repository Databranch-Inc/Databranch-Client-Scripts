#Requires -Version 5.1
<#
.SYNOPSIS
    Lists the top N longest file full-paths under a given directory, sorted by
    character count descending, with count displayed first for quick visibility.

.DESCRIPTION
    Recursively scans a root directory and reports the files with the longest
    full paths by character count. Useful for identifying paths that may exceed
    the 260-character MAX_PATH limit on Windows, which can cause application
    failures, backup errors, or migration problems.

    Supports DattoRMM automated deployment via environment variable input, or
    standard interactive use via PowerShell parameters. Hidden and System files
    are excluded by default and can be included via switches or env vars.

    Output is written to both a structured log file (DattoRMM-visible via stdout)
    and a human-friendly colorized console display for interactive runs.

.PARAMETER Root
    The root directory to scan recursively. Required.
    DattoRMM env var: TopPaths_Root

.PARAMETER Top
    How many of the longest file paths to report. Default: 10.
    DattoRMM env var: TopPaths_Top

.PARAMETER IncludeHidden
    Include files with the Hidden attribute. Default: false.
    DattoRMM env var: TopPaths_IncludeHidden (set to "true" to enable)

.PARAMETER IncludeSystem
    Include files with the System attribute. Default: false.
    DattoRMM env var: TopPaths_IncludeSystem (set to "true" to enable)

.EXAMPLE
    .\Get-TopLongestPaths.ps1 -Root 'C:\ClientData'
    Reports the top 10 longest paths under C:\ClientData.

.EXAMPLE
    .\Get-TopLongestPaths.ps1 -Root 'C:\Data' -Top 25 -IncludeHidden -IncludeSystem
    Reports the top 25 longest paths including hidden and system files.

.EXAMPLE
    .\Get-TopLongestPaths.ps1 -Root 'C:\Shares\Department' -Top 50
    Reports the top 50 longest paths — useful pre-migration path audit.

.NOTES
    File Name      : Get-TopLongestPaths.ps1
    Version        : 1.0.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-03-06
    Last Modified  : 2026-03-06
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM or Domain Admin
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : All clients

    Exit Codes:
        0  - Success - results reported
        1  - General failure (unhandled exception)
        2  - Invalid or inaccessible root path
        3  - No files found under root path

    Output Design:
        Write-Log     - Structured [timestamp][SEVERITY] output to log file AND
                        DattoRMM stdout. Always verbose. No color.
        Write-Console - Human-friendly colored console output for manual/interactive
                        runs. Uses Write-Host (display stream only). Suppressed in
                        DattoRMM agent context automatically.

.CHANGELOG
    v1.0.0.0 - 2026-03-06 - Sam Kirsch
        - Initial release
        - DattoRMM env var support for all parameters
        - Dual-output logging pattern (Write-Log + Write-Console)
        - CharCount column output first for immediate visibility in DattoRMM job log
        - Per-entry structured log output ensures paths visible even in truncated consoles
        - Hidden and System file filtering with include switches
        - Log rotation (keeps last 10 log files)
        - Exit codes: 0 success, 1 general failure, 2 bad path, 3 no files found
#>

# ==============================================================================
# PARAMETERS
# DattoRMM env vars take precedence; falls back to passed parameters or defaults.
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$Root = $(if ($env:TopPaths_Root) { $env:TopPaths_Root } else { "" }),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1000)]
    [int]$Top = $(if ($env:TopPaths_Top) { [int]$env:TopPaths_Top } else { 10 }),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeHidden,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeSystem,

    # DattoRMM built-in variables
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "UnknownSite" }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# DattoRMM switch env var resolution (switches cannot use default expressions)
if ($env:TopPaths_IncludeHidden -eq "true") { $IncludeHidden = $true }
if ($env:TopPaths_IncludeSystem -eq "true") { $IncludeSystem = $true }

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Get-TopLongestPaths {
    <#
    .SYNOPSIS
        Internal master function. See script-level help for full documentation.
    #>
    [CmdletBinding()]
    param (
        [string]$Root,
        [int]$Top,
        [bool]$IncludeHidden,
        [bool]$IncludeSystem,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Get-TopLongestPaths"
    $ScriptVersion = "1.0.0.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # ==========================================================================
    # WRITE-LOG  (Structured Output Layer)
    # Writes to log file AND DattoRMM stdout. Never use Write-Host here.
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
    # WRITE-CONSOLE  (Presentation Layer — display stream only, not DattoRMM)
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
            [string]$Title,
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
            [string]$Title,
            [string]$Color = "Cyan"
        )
        $TitleStr = "---- $Title "
        $Padding  = "-" * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ""
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    function Write-Separator {
        param ([string]$Color = "DarkGray")
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
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    # Log header
    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site          : $SiteName"               -Severity INFO
    Write-Log "Hostname      : $Hostname"               -Severity INFO
    Write-Log "Run As        : $RunAs"                  -Severity INFO
    Write-Log "Params        : Root='$Root' | Top=$Top | IncludeHidden=$IncludeHidden | IncludeSystem=$IncludeSystem" -Severity INFO
    Write-Log "Log File      : $LogFile"                -Severity INFO

    # Console banner
    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site          : $SiteName"   -Severity PLAIN
    Write-Console "Hostname      : $Hostname"   -Severity PLAIN
    Write-Console "Run As        : $RunAs"      -Severity PLAIN
    Write-Console "Log File      : $LogFile"    -Severity PLAIN
    Write-Separator

    try {

        # ------------------------------------------------------------------
        # STEP 1 — Validate root path
        # ------------------------------------------------------------------
        Write-Section "Validating Root Path"
        Write-Log     "Validating root path: '$Root'" -Severity INFO
        Write-Console "Validating root path: '$Root'" -Severity INFO

        if ([string]::IsNullOrWhiteSpace($Root)) {
            Write-Log     "Root parameter is required but was not provided." -Severity ERROR
            Write-Console "Root parameter is required but was not provided." -Severity ERROR
            Write-Log     "Set the Root parameter or the TopPaths_Root environment variable in DattoRMM." -Severity ERROR
            Write-Banner  "SCRIPT FAILED" -Color "Red"
            exit 2
        }

        try {
            $resolvedRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
        }
        catch {
            Write-Log     "Root path not found or inaccessible: '$Root' — $_" -Severity ERROR
            Write-Console "Root path not found or inaccessible: '$Root'" -Severity ERROR
            Write-Banner  "SCRIPT FAILED" -Color "Red"
            exit 2
        }

        Write-Log     "Root path resolved: $resolvedRoot" -Severity SUCCESS
        Write-Console "Root path resolved: $resolvedRoot" -Severity SUCCESS

        # ------------------------------------------------------------------
        # STEP 2 — Collect files
        # ------------------------------------------------------------------
        Write-Section "Collecting Files"
        Write-Log     "Scanning recursively under: $resolvedRoot" -Severity INFO
        Write-Console "Scanning recursively under: $resolvedRoot" -Severity INFO

        $files = Get-ChildItem -LiteralPath $resolvedRoot -File -Recurse -ErrorAction SilentlyContinue

        $totalFound = ($files | Measure-Object).Count
        Write-Log     "Raw file count: $totalFound" -Severity DEBUG
        Write-Console "Raw file count: $totalFound" -Severity DEBUG

        # ------------------------------------------------------------------
        # STEP 3 — Apply attribute filters
        # ------------------------------------------------------------------
        if (-not $IncludeHidden) {
            $files = $files | Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::Hidden) }
        }
        if (-not $IncludeSystem) {
            $files = $files | Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::System) }
        }

        $filteredCount = ($files | Measure-Object).Count
        $hiddenMsg     = if ($IncludeHidden) { "included" } else { "excluded" }
        $systemMsg     = if ($IncludeSystem) { "included" } else { "excluded" }

        Write-Log     "After attribute filter: $filteredCount files (Hidden: $hiddenMsg | System: $systemMsg)" -Severity INFO
        Write-Console "After attribute filter: $filteredCount files (Hidden: $hiddenMsg | System: $systemMsg)" -Severity INFO

        if ($filteredCount -eq 0) {
            Write-Log     "No files found under: $resolvedRoot" -Severity WARN
            Write-Console "No files found under: $resolvedRoot" -Severity WARN
            Write-Banner  "NO FILES FOUND" -Color "Yellow"
            exit 3
        }

        # ------------------------------------------------------------------
        # STEP 4 — Sort and select top N
        # NOTE: CharCount is the FIRST column so it is immediately visible
        #       in the DattoRMM job log and in narrow console windows.
        # ------------------------------------------------------------------
        Write-Section "Analyzing Path Lengths"
        Write-Log     "Sorting by path length, selecting top $Top..." -Severity INFO
        Write-Console "Sorting by path length, selecting top $Top..." -Severity INFO

        $longest = $files |
            Select-Object @{
                Name       = 'CharCount'
                Expression = { $_.FullName.Length }
            }, @{
                Name       = 'Path'
                Expression = { $_.FullName }
            } |
            Sort-Object -Property CharCount -Descending |
            Select-Object -First $Top

        # ------------------------------------------------------------------
        # STEP 5 — Output results
        # Each entry is logged individually so full paths always appear in
        # the DattoRMM job log, regardless of console window width or
        # Format-Table column truncation.
        # ------------------------------------------------------------------
        Write-Section "Results"
        Write-Log     "Top $Top longest paths under: $resolvedRoot" -Severity INFO
        Write-Console ""

        # Console header line
        Write-Host ("  {0,-6}  {1}" -f "CHARS", "PATH") -ForegroundColor Cyan
        Write-Host ("  {0,-6}  {1}" -f "------", ("-" * 70)) -ForegroundColor DarkGray

        $rank = 1
        foreach ($entry in $longest) {
            # Structured log — always full path, always visible in DattoRMM
            Write-Log ("{0,3}. [{1,4} chars]  {2}" -f $rank, $entry.CharCount, $entry.Path) -Severity INFO

            # Console — color-coded by threshold proximity
            # Windows MAX_PATH = 260. Flag paths getting close.
            $countColor = if ($entry.CharCount -ge 250) { "Red" }
                          elseif ($entry.CharCount -ge 220) { "Yellow" }
                          else { "Green" }

            Write-Host ("  {0,-6}" -f $entry.CharCount) -ForegroundColor $countColor -NoNewline
            Write-Host "  $($entry.Path)" -ForegroundColor White

            $rank++
        }

        Write-Host ""

        # Summary log entry
        $maxLen = ($longest | Select-Object -First 1).CharCount
        Write-Log "Scan complete. Longest path: $maxLen chars. Results: $([Math]::Min($Top, $filteredCount)) of $filteredCount files shown." -Severity SUCCESS
        Write-Console "Longest path: $maxLen chars. $([Math]::Min($Top, $filteredCount)) of $filteredCount files shown." -Severity SUCCESS

        # MAX_PATH advisory
        if ($maxLen -ge 260) {
            Write-Log     "WARNING: One or more paths meet or exceed the 260-char Windows MAX_PATH limit." -Severity WARN
            Write-Console "One or more paths meet or exceed the 260-char MAX_PATH limit." -Severity WARN
        }
        elseif ($maxLen -ge 220) {
            Write-Log     "ADVISORY: Longest path is within 40 characters of the MAX_PATH limit (260)." -Severity WARN
            Write-Console "Longest path is within 40 chars of the MAX_PATH limit (260)." -Severity WARN
        }

        Write-Banner "COMPLETED SUCCESSFULLY" -Color "Green"
        exit 0

    }
    catch {
        Write-Log     "Unhandled exception: $_"             -Severity ERROR
        Write-Log     "Stack trace: $($_.ScriptStackTrace)" -Severity ERROR
        Write-Console "Unhandled exception: $_"             -Severity ERROR
        Write-Banner  "SCRIPT FAILED" -Color "Red"
        exit 1
    }

} # End function Get-TopLongestPaths

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    Root          = $Root
    Top           = $Top
    IncludeHidden = [bool]$IncludeHidden
    IncludeSystem = [bool]$IncludeSystem
    SiteName      = $SiteName
    Hostname      = $Hostname
}

Get-TopLongestPaths @ScriptParams
