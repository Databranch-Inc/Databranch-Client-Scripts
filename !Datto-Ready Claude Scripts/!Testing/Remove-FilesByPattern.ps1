#Requires -Version 5.1
<#
.SYNOPSIS
    Recursively removes files by name from specified root paths, with exclusion
    support and structured dual-output logging.

.DESCRIPTION
    Accepts a list of file names (or patterns) via the -FilePatterns parameter
    and recursively searches one or more root paths, deleting any matching files
    that do not fall under an excluded directory tree. Designed for automated
    deployment via DattoRMM (env var input) or interactive technician use
    (parameter input).

    File name matching is case-insensitive exact match on the file name only
    (not full path). Exclusion paths protect system directories from accidental
    deletion.

.PARAMETER FilePatterns
    One or more file names to remove (exact match, case-insensitive).
    Accepts a string array or a single comma-separated string (for DattoRMM
    single-line variable fields).
    Example: "thumbs.db,desktop.ini" or @("thumbs.db","desktop.ini")
    DattoRMM env var: $env:FilePatterns

.PARAMETER Roots
    One or more root paths to search recursively.
    Defaults to C:\ if not specified.
    DattoRMM env var: $env:Roots (comma-separated)

.PARAMETER ExcludePaths
    Directory paths that are off-limits. Files under these trees will never be
    deleted even if they match a pattern.
    Defaults to the standard Windows/system exclusion set.
    DattoRMM env var: $env:ExcludePaths (comma-separated)

.PARAMETER WhatIf
    Simulates the run without deleting anything. Logs what would have been
    removed. Useful for validation before a live run.

.EXAMPLE
    .\Remove-FilesByPattern.ps1 -FilePatterns "thumbs.db","desktop.ini"
    Removes all thumbs.db and desktop.ini files found under C:\ (excluding
    protected system paths).

.EXAMPLE
    .\Remove-FilesByPattern.ps1 -FilePatterns "thumbs.db" -Roots "C:\Users","D:\" -WhatIf
    Simulates removal under C:\Users and D:\ without deleting anything.

.EXAMPLE
    .\Remove-FilesByPattern.ps1 -FilePatterns "oldreport.pdf,tempfile.tmp" -Roots "C:\Users"
    Comma-separated string input (compatible with DattoRMM variable fields).

.NOTES
    File Name      : Remove-FilesByPattern.ps1
    Version        : 1.0.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch IT
    Created        : 2026-03-06
    Last Modified  : 2026-03-06
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM or Domain Admin
    DattoRMM       : Compatible - supports environment variable input
    Client Scope   : All clients

    Exit Codes:
        0  - Success (all matched files processed)
        1  - General / unexpected failure
        2  - No file patterns provided (required input missing)
        3  - No valid root paths found

.CHANGELOG
    v1.0.0.0 - 2026-03-06 - Sam Kirsch
        - Initial release
        - Converted from standalone script to master function with DattoRMM
          parameter standardization
        - FilePatterns accepted as string array or comma-separated string
        - Dual-output logging: Write-Log (structured) + Write-Console (colorized)
        - Added -WhatIf simulation mode
        - Added log rotation (keep last 10 logs)
        - Protected system path exclusions moved to parameter with safe defaults
#>

# ==============================================================================
# PARAMETERS
# Supports DattoRMM env var input (automated) and standard PS parameter input
# (manual/interactive). Env vars take precedence when present.
# ==============================================================================
[CmdletBinding(SupportsShouldProcess)]
param (
    # Primary input: file names to remove. Comma-separated string OR string array.
    [Parameter(Mandatory = $false)]
    [string[]]$FilePatterns = $(
        if ($env:FilePatterns) {
            $env:FilePatterns -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        } else {
            @()
        }
    ),

    # Root paths to search. Defaults to C:\.
    [Parameter(Mandatory = $false)]
    [string[]]$Roots = $(
        if ($env:Roots) {
            $env:Roots -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        } else {
            @('C:\')
        }
    ),

    # Paths to exclude from deletion — system/OS directories.
    [Parameter(Mandatory = $false)]
    [string[]]$ExcludePaths = $(
        if ($env:ExcludePaths) {
            $env:ExcludePaths -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        } else {
            @(
                'C:\Windows',
                'C:\Program Files',
                'C:\Program Files (x86)',
                'C:\ProgramData\Microsoft\Windows\Start Menu',
                'C:\Recovery',
                'C:\$Recycle.Bin',
                'C:\System Volume Information'
            )
        }
    ),

    # Simulate only — log what would be deleted without removing anything.
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf = $(
        if ($env:WhatIf -eq '1' -or $env:WhatIf -eq 'true') { $true } else { $false }
    ),

    # DattoRMM built-in variables (auto-populated by Datto)
    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { 'UnknownSite' }),

    [Parameter(Mandatory = $false)]
    [string]$HostName = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Remove-FilesByPattern {
    <#
    .SYNOPSIS
        Internal master function. See script-level help for full documentation.
    #>
    [CmdletBinding()]
    param (
        [string[]]$FilePatterns,
        [string[]]$Roots,
        [string[]]$ExcludePaths,
        [switch]$WhatIf,
        [string]$SiteName,
        [string]$HostName
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = 'Remove-FilesByPattern'
    $ScriptVersion = '1.0.0.0'
    $LogRoot       = 'C:\Databranch\ScriptLogs'
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format 'yyyy-MM-dd'
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # ==========================================================================
    # WRITE-LOG  (Structured output — file + stdout)
    # Uses Write-Output/Warning/Error so DattoRMM captures it.
    # ==========================================================================
    function Write-Log {
        param (
            [Parameter(Mandatory = $true)]  [string]$Message,
            [Parameter(Mandatory = $false)] [ValidateSet('INFO','WARN','ERROR','DEBUG')]
                                            [string]$Level = 'INFO'
        )
        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $Entry     = "[$Timestamp] [$Level] $Message"

        try { $Entry | Out-File -FilePath $LogFile -Append -Encoding utf8 } catch {}

        switch ($Level) {
            'WARN'  { Write-Warning $Entry }
            'ERROR' { Write-Error   $Entry }
            default { Write-Output  $Entry }
        }
    }

    # ==========================================================================
    # WRITE-CONSOLE  (Human-friendly display — interactive sessions only)
    # Write-Host is display-stream only; not captured by DattoRMM. That's fine.
    # ==========================================================================
    function Write-Console {
        param (
            [Parameter(Mandatory = $true)]  [string]$Message,
            [Parameter(Mandatory = $false)] [string]$Color = 'White',
            [Parameter(Mandatory = $false)] [string]$Prefix = ''
        )
        if ($Prefix) {
            Write-Host "[$Prefix] " -ForegroundColor DarkGray -NoNewline
        }
        Write-Host $Message -ForegroundColor $Color
    }

    function Write-Banner {
        param ([string]$Title, [string]$Version, [string]$Site)
        $Line = '=' * 60
        Write-Host ''
        Write-Host $Line                              -ForegroundColor DarkBlue
        Write-Host "  $Title"                         -ForegroundColor Cyan
        Write-Host "  Version : $Version"             -ForegroundColor DarkCyan
        Write-Host "  Site    : $Site"                -ForegroundColor DarkCyan
        Write-Host $Line                              -ForegroundColor DarkBlue
        Write-Host ''
    }

    function Write-Section {
        param ([string]$Title, [string]$Color = 'Cyan')
        $TitleStr = "---- $Title "
        $Padding  = '-' * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ''
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    function Write-Separator {
        param ([string]$Color = 'DarkGray')
        Write-Host ('-' * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # LOG SETUP & ROTATION
    # ==========================================================================
    function Initialize-Logging {
        if (-not (Test-Path $LogFolder)) {
            try   { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
            catch { Write-Warning "Could not create log folder '$LogFolder': $_" }
        }

        try {
            $Existing = Get-ChildItem -Path $LogFolder -Filter "$($ScriptName)_*.log" |
                        Sort-Object LastWriteTime -Descending
            if ($Existing.Count -ge $MaxLogFiles) {
                $Existing | Select-Object -Skip ($MaxLogFiles - 1) | ForEach-Object {
                    Remove-Item -Path $_.FullName -Force
                }
            }
        }
        catch { Write-Warning "Log rotation failed: $_" }
    }

    # ==========================================================================
    # HELPER: excluded path check
    # ==========================================================================
    function Test-IsExcludedPath {
        param ([string]$FullPath)
        foreach ($Prefix in $ExcludePrefixes) {
            if ($FullPath.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        return $false
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'
    Initialize-Logging

    Write-Banner -Title $ScriptName -Version $ScriptVersion -Site $SiteName
    Write-Log "===== $ScriptName v$ScriptVersion STARTED on $HostName (Site: $SiteName) ====="

    if ($WhatIf) {
        Write-Console '*** WHATIF MODE — No files will be deleted ***' -Color Yellow -Prefix 'SIMULATE'
        Write-Log 'WhatIf mode enabled — simulation only, no deletions will occur.' -Level 'WARN'
    }

    # ------------------------------------------------------------------
    # Validate inputs
    # ------------------------------------------------------------------
    Write-Section 'Validating Inputs'

    # Normalize FilePatterns — handle comma-separated string passed as single element
    if ($FilePatterns.Count -eq 1 -and $FilePatterns[0] -match ',') {
        $FilePatterns = $FilePatterns[0] -split ',' |
                        ForEach-Object { $_.Trim() } |
                        Where-Object { $_ }
    }

    $FilePatterns = $FilePatterns | Where-Object { $_ } | Select-Object -Unique

    if (-not $FilePatterns -or $FilePatterns.Count -eq 0) {
        Write-Log 'No file patterns provided. FilePatterns parameter is required.' -Level 'ERROR'
        Write-Console 'No file patterns provided. Use -FilePatterns or set $env:FilePatterns.' -Color Red -Prefix 'ERROR'
        exit 2
    }

    Write-Log "File patterns loaded: $($FilePatterns.Count) pattern(s)"
    Write-Console "File patterns : $($FilePatterns -join ', ')" -Color White -Prefix 'INFO'
    Write-Console "Search roots  : $($Roots -join ', ')"       -Color White -Prefix 'INFO'
    Write-Console "Excluded paths: $($ExcludePaths.Count) path(s) protected" -Color DarkGray -Prefix 'INFO'

    # Build exclusion prefix list (normalized with trailing backslash)
    $ExcludePrefixes = $ExcludePaths |
                       ForEach-Object { $_.TrimEnd('\') + '\' }

    # Validate that at least one root is accessible
    $ValidRoots = $Roots | Where-Object { Test-Path $_ }
    $SkippedRoots = $Roots | Where-Object { -not (Test-Path $_) }

    foreach ($Skip in $SkippedRoots) {
        Write-Log "Root path not found, skipping: $Skip" -Level 'WARN'
        Write-Console "Root not found, skipping: $Skip" -Color Yellow -Prefix 'WARN'
    }

    if (-not $ValidRoots) {
        Write-Log 'No valid root paths found. Exiting.' -Level 'ERROR'
        Write-Console 'No valid root paths found. Nothing to search.' -Color Red -Prefix 'ERROR'
        exit 3
    }

    # ------------------------------------------------------------------
    # File removal pass
    # ------------------------------------------------------------------
    Write-Section 'Scanning and Removing Files'

    $Deleted   = 0
    $Failed    = 0
    $Simulated = 0
    $Skipped   = 0

    foreach ($Root in $ValidRoots) {
        Write-Log "Scanning root: $Root"
        Write-Console "Scanning: $Root" -Color Cyan -Prefix 'SCAN'

        try {
            Get-ChildItem -Path $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-IsExcludedPath $_.FullName) } |
            Where-Object { $FilePatterns -icontains $_.Name } |
            ForEach-Object {
                $FilePath = $_.FullName

                if ($WhatIf) {
                    Write-Log   "[WHATIF] Would delete: $FilePath"
                    Write-Console "Would delete: $FilePath" -Color Yellow -Prefix 'WHATIF'
                    $Simulated++
                }
                else {
                    try {
                        Remove-Item -LiteralPath $FilePath -Force -ErrorAction Stop
                        Write-Log   "[DELETED] $FilePath"
                        Write-Console $FilePath -Color Green -Prefix 'DELETED'
                        $Deleted++
                    }
                    catch {
                        Write-Log   "[FAILED] $FilePath :: $($_.Exception.Message)" -Level 'ERROR'
                        Write-Console "$FilePath :: $($_.Exception.Message)" -Color Red -Prefix 'FAILED'
                        $Failed++
                    }
                }
            }
        }
        catch {
            Write-Log "Unexpected error scanning root '$Root': $_" -Level 'ERROR'
            Write-Console "Error scanning '$Root': $_" -Color Red -Prefix 'ERROR'
        }
    }

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    Write-Section 'Summary' -Color Green

    if ($WhatIf) {
        Write-Log   "SIMULATION COMPLETE | Would delete: $Simulated file(s)"
        Write-Console "Simulation complete. Would have deleted $Simulated file(s)." -Color Yellow -Prefix 'DONE'
    }
    else {
        Write-Log   "RUN COMPLETE | Deleted: $Deleted | Failed: $Failed | Skipped (excluded): $Skipped"
        Write-Console "Deleted : $Deleted"  -Color Green   -Prefix 'DONE'
        if ($Failed -gt 0) {
            Write-Console "Failed  : $Failed" -Color Red     -Prefix 'DONE'
        }
    }

    Write-Console "Log saved to: $LogFile" -Color DarkCyan -Prefix 'LOG'
    Write-Log "===== $ScriptName FINISHED ====="

    exit 0
}

# ==============================================================================
# ENTRY POINT — splat script-scope parameters into master function
# ==============================================================================
Remove-FilesByPattern @{
    FilePatterns = $FilePatterns
    Roots        = $Roots
    ExcludePaths = $ExcludePaths
    WhatIf       = $WhatIf
    SiteName     = $SiteName
    HostName     = $HostName
}
