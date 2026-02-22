#Requires -Version 7.0
<#
.SYNOPSIS
    Script Management Browser - Local Git repository script browser, metadata manager,
    and SharePoint sync tool for Databranch engineering teams.

.DESCRIPTION
    A WPF GUI application that indexes all .ps1 and .bat files from a local Git
    repository and provides browsing, viewing, tagging, commenting, renaming, and
    VSCode integration. Comments and tags are stored directly in script files using
    a structured comment syntax compatible with both the legacy EngineersPowerApp
    format and the new ScriptManagementBrowser format.

    SharePoint sync pushes the local Git repository to a dedicated SharePoint
    subfolder (one-way, Git is the master). Sync uses a timestamp-first, hash-as-
    tiebreaker delta strategy, uploading only new or changed files and optionally
    removing files from SharePoint that no longer exist in the local repository.

    Configuration is stored in:
        %APPDATA%\ScriptManagementBrowser\config.json

    Application log is stored in:
        %APPDATA%\ScriptManagementBrowser\app.log

    Comment/tag syntax written into managed script files:
        ##SCRIPTMGMT#COMMENT#<your comment here>
        ##SCRIPTMGMT#TAGS#<tag1,tag2,tag3>

    Legacy EngineersPowerApp syntax is read transparently and upgraded on next save:
        ##ENGINEERSPOWERAPP#COMMENT#<comment>
        ##ENGINEERSPOWERAPP#TAGS#<tags>

.NOTES
    File Name      : Start-ScriptManagementBrowser.ps1
    Version        : 1.0.7.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-02-21
    Last Modified  : 2026-02-21
    Modified By    : Sam Kirsch

    Requires       : PowerShell 7.0+
    Requires       : PnP.PowerShell (optional - required for SharePoint sync only)
                     Install: Install-Module PnP.PowerShell -Scope CurrentUser
    Run Context    : Interactive desktop - Senior Engineers only
    DattoRMM       : Not applicable
    Client Scope   : Internal Databranch tooling only

    SharePoint Sync requires an Entra ID app registration with interactive login.
    To register:
        Register-PnPEntraIDAppForInteractiveLogin `
            -ApplicationName "PnP.PowerShell" `
            -Tenant "databranch.onmicrosoft.com" `
            -Interactive

    SharePoint target path format:
        Site URL  : https://databranch.sharepoint.com/sites/YourSite
        Library   : IT Scripts          (document library display name)
        Subfolder : Published/Scripts   (path within that library, no leading slash)
        Full path : /sites/YourSite/IT Scripts/Published/Scripts

.CHANGELOG
    v1.0.7.0 - 2026-02-21 - Sam Kirsch
        - Added: Ancestor path diagnostic in folder pre-creation pass. Walks each
          segment of the root target path (e.g. Documents, Engineering Procedures,
          _GitScriptsRepo) and logs OK/MISS for each so the exact break point is
          visible in the log. Folder pass now aborts after 3 consecutive errors
          rather than hammering all 54 folders when the root itself is inaccessible.

    v1.0.6.0 - 2026-02-21 - Sam Kirsch
        - Added: SharePoint path sanitization. Leading ! and . characters on any
          folder or file name segment are replaced with - when constructing SP
          destination paths. Local Git repo paths are never modified. Sanitization
          is applied consistently across the folder pre-creation pass, expected SP
          path comparison, upload folder, and filename. Mapping is logged when a
          path differs (e.g. "!Archive -> -Archive").
        - Added: Sanitize-SpPath and Sanitize-SpSegment helper functions in runspace.

    v1.0.5.0 - 2026-02-21 - Sam Kirsch
        - Fixed: .Replace("\","/") calls inside the runspace script block were
          corrupted by Python string processing during patching — backslashes were
          eaten, producing .Replace("","/") which throws "value cannot be empty string".
          Replaced all path-normalization .Replace() calls in the runspace with
          PowerShell's -replace operator which is not subject to this escaping issue.
          Affected: folder pre-creation pass (lines 584-585) and delta sync relPath
          and fileRelDir calculations.

    v1.0.4.0 - 2026-02-21 - Sam Kirsch
        - Fixed: Add-PnPFile returns "Access denied" when the destination folder does
          not exist in SharePoint (SharePoint's misleading error for missing path).
          Added a folder pre-creation pass before the upload loop using
          Resolve-PnPFolder, which creates the full folder chain for every unique
          directory in the local repo. Handles arbitrarily deep nesting in one call
          per folder. Is a no-op if the folder already exists.
        - Added folder creation stats to sync log (Ensured=N, Errors=N).

    v1.0.3.0 - 2026-02-21 - Sam Kirsch
        - Fixed: Get-SharePointFileUrl still referenced SharePointLibrary and
          SharePointSubfolder (old schema). Updated to use SharePointFolderPath.
        - Note: Delete %APPDATA%\ScriptManagementBrowser\config.json if upgrading
          from v1.0.0/v1.0.1 to force first-run setup with the new field schema.

    v1.0.2.0 - 2026-02-21 - Sam Kirsch
        - Fixed: Show-SettingsDialog rebuilt entirely using XAML + XamlReader::Parse()
          + FindName(). Previous New-Object/::new() approaches for WPF controls both
          fail at the nesting depth of a function-inside-function-inside-master-function
          in PS7 when WPF assemblies are loaded. XAML parsing is the only reliable method.
        - Fixed: Get-DefaultConfig changed from [ordered]@{} to plain @{} hashtable.
          OrderedDictionary does not have a .Clone() method, causing Load-AppConfig to
          throw on every startup and fall back to empty defaults.
        - Fixed: Load-AppConfig now uses @($config.Keys) snapshot instead of
          $config.Clone().Keys to safely enumerate keys during merge.
        - Changed: SharePointLibrary + SharePointSubfolder fields replaced with a
          single SharePointFolderPath field (full path within site, no leading slash,
          e.g. Documents/Engineering Procedures/!GitScriptsRepo). Eliminates the
          display-name vs internal-name confusion for SharePoint document libraries.
        - Updated: Sync runspace path logic, Get-SharePointFileUrl, and
          Test-SharePointConfig updated to use SharePointFolderPath.

    v1.0.1.0 - 2026-02-21 - Sam Kirsch
        - Fixed: Add-Field nested function in Show-SettingsDialog used [Type]::new()
          for WPF controls, which resolves ambiguously inside nested PS7 function
          scopes when WPF assemblies are loaded. Replaced with New-Object throughout
          and used explicit [System.Windows.TextWrapping]::Wrap enum value.
        - Fixed: $Window.Show() was called before ShowDialog() during first-run,
          putting the window in a visible state and causing ShowDialog() to throw
          "ShowDialog can be called only on hidden windows." Removed Show() entirely;
          the settings dialog uses CenterScreen and needs no window owner.
        - Fixed: Cancelling the first-run wizard now exits cleanly without writing
          config.json and without attempting to call ShowDialog() on the main window.
        - Fixed: Added $script:Config reload after first-run save so the main app
          immediately has the correct values without requiring a restart.

    v1.0.0.0 - 2026-02-21 - Sam Kirsch
        - Initial release as Start-ScriptManagementBrowser
        - Replaces EngineersPowerApp (EngineersPowerApp_PS7_git.ps1)
        - Removed all SharePoint inbound browse/read functionality
        - Removed PnP.PowerShell as a startup hard dependency
        - Removed SharePoint cache (cache.json) - Git cache only
        - Added JSON-based config (config.json) replacing hardcoded script variables
        - Added first-run settings dialog (also accessible via toolbar Settings button)
        - Added one-way SharePoint sync (Git -> SharePoint delta push)
            - Timestamp-first, MD5 hash tiebreaker delta strategy
            - Errs toward uploading when uncertain
            - Pre-deletion confirmation dialog with file list
            - "Skip delete confirmation" config option (default: off)
            - "Reset delete confirmation" option in settings
        - BtnCopyUrl now constructs full SharePoint URL for the selected file
          (useful for sharing direct links with junior engineers via Teams)
        - BtnCopyPath copies full local filesystem path (unchanged)
        - Metadata prefix migrated from ##ENGINEERSPOWERAPP# to ##SCRIPTMGMT#
          Legacy prefixes are read transparently; files are upgraded on next save
        - AppData path changed from EngineersPowerApp\ to ScriptManagementBrowser\
        - Master function wrapper: Start-ScriptManagementBrowser
        - Window/title/status bar text updated throughout
#>

# ==============================================================================
# ENTRY POINT — calls master function at bottom of file
# ==============================================================================

function Start-ScriptManagementBrowser {
    <#
    .SYNOPSIS
        Master function. Launches the Script Management Browser WPF application.
    #>

    # ==========================================================================
    # APP CONSTANTS
    # ==========================================================================
    $script:AppName       = "ScriptManagementBrowser"
    $script:AppVersion    = "1.0.7.0"
    $script:AppDataDir    = "$env:APPDATA\ScriptManagementBrowser"
    $script:ConfigFile    = "$script:AppDataDir\config.json"
    $script:LogFile       = "$script:AppDataDir\app.log"
    $script:GitCacheFile  = "$script:AppDataDir\git-cache.json"
    $script:FileTypes     = @("*.ps1", "*.bat")

    # Metadata prefixes — new (written), legacy (read-only, upgraded on save)
    $script:CommentPrefix        = "##SCRIPTMGMT#COMMENT#"
    $script:TagPrefix            = "##SCRIPTMGMT#TAGS#"
    $script:LegacyCommentPrefix  = "##ENGINEERSPOWERAPP#COMMENT#"
    $script:LegacyTagPrefix      = "##ENGINEERSPOWERAPP#TAGS#"

    # ==========================================================================
    # BOOTSTRAP
    # ==========================================================================
    if (-not (Test-Path $script:AppDataDir)) {
        New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null
    }

    # ==========================================================================
    # LOGGING  (simple file log — no DattoRMM integration needed for desktop app)
    # ==========================================================================
    function Write-AppLog {
        param(
            [string]$Message,
            [string]$Level = "INFO"
        )
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $entry     = "[$timestamp] [$Level] $Message"
        try {
            Add-Content -Path $script:LogFile -Value $entry -ErrorAction SilentlyContinue
        } catch {}
    }

    # ==========================================================================
    # CONFIG  (JSON persistence)
    # ==========================================================================
    function Get-DefaultConfig {
        # Plain hashtable (not [ordered]@{}) — OrderedDictionary has no .Clone() method,
        # which caused a load failure in v1.0.0/v1.0.1. Keys iterated via @($config.Keys).
        return @{
            GitRepoPath          = ""
            SharePointSiteUrl    = ""   # e.g. https://databranch.sharepoint.com
            SharePointFolderPath = ""   # Full folder path within site, no leading slash
                                        # e.g. Documents/Engineering Procedures/!GitScriptsRepo
                                        # Get this from the SharePoint URL: decode the id= parameter,
                                        # then drop the leading slash. Library name is the first segment.
            EntraClientId        = ""
            SkipDeleteConfirm    = $false
        }
    }

    function Load-AppConfig {
        if (-not (Test-Path $script:ConfigFile)) {
            return Get-DefaultConfig
        }
        try {
            $raw    = Get-Content -Path $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $config = Get-DefaultConfig
            # Merge loaded values over defaults (handles missing keys in old configs).
            # Use @($config.Keys) copy — hashtable keys cannot be enumerated while mutating.
            foreach ($key in @($config.Keys)) {
                if ($null -ne $raw.$key) {
                    $config[$key] = $raw.$key
                }
            }
            Write-AppLog "Config loaded from $script:ConfigFile"
            return $config
        } catch {
            Write-AppLog "Config load failed: $_ — using defaults" "WARN"
            return Get-DefaultConfig
        }
    }

    function Save-AppConfig {
        param([hashtable]$Config)
        try {
            $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigFile -Encoding UTF8
            Write-AppLog "Config saved"
        } catch {
            Write-AppLog "Config save failed: $_" "ERROR"
        }
    }

    # ==========================================================================
    # GIT CACHE
    # ==========================================================================
    function Save-GitCache {
        param([System.Collections.Generic.List[PSObject]]$Files)
        try {
            $cacheObj = @{
                Timestamp = (Get-Date).ToString("o")
                RepoPath  = $script:Config.GitRepoPath
                Files     = $Files | ForEach-Object {
                    @{
                        Name           = $_.Name
                        FileRef        = $_.FileRef
                        Library        = $_.Library
                        FolderPath     = $_.FolderPath
                        Created        = if ($_.Created)  { $_.Created.ToString("o")  } else { $null }
                        Modified       = if ($_.Modified) { $_.Modified.ToString("o") } else { $null }
                        Author         = $_.Author
                        LastModifiedBy = $_.LastModifiedBy
                        SizeBytes      = $_.SizeBytes
                        Extension      = $_.Extension
                        Comment        = $_.Comment
                        Tags           = $_.Tags
                        TagsRaw        = $_.TagsRaw
                    }
                }
            }
            $cacheObj | ConvertTo-Json -Depth 10 | Set-Content -Path $script:GitCacheFile -Encoding UTF8
            Write-AppLog "Git cache saved: $($Files.Count) files"
        } catch {
            Write-AppLog "Git cache save failed: $_" "WARN"
        }
    }

    function Load-GitCache {
        if (-not (Test-Path $script:GitCacheFile)) { return $null }
        try {
            $raw   = Get-Content -Path $script:GitCacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $files = [System.Collections.Generic.List[PSObject]]::new()
            foreach ($f in $raw.Files) {
                if ([string]::IsNullOrEmpty($f.Name) -or [string]::IsNullOrEmpty($f.Extension)) { continue }
                $files.Add([PSCustomObject]@{
                    Name           = $f.Name
                    FileRef        = $f.FileRef
                    Library        = $f.Library
                    FolderPath     = $f.FolderPath
                    Created        = if ($f.Created)  { [datetime]$f.Created  } else { $null }
                    Modified       = if ($f.Modified) { [datetime]$f.Modified } else { $null }
                    Author         = $f.Author
                    LastModifiedBy = $f.LastModifiedBy
                    SizeBytes      = $f.SizeBytes
                    Extension      = $f.Extension
                    Comment        = $f.Comment
                    Tags           = @($f.Tags)
                    TagsRaw        = $f.TagsRaw
                    ContentLoaded  = $false
                })
            }
            Write-AppLog "Git cache loaded: $($files.Count) files (cached $(([datetime]$raw.Timestamp).ToString('g')))"
            return @{ Files = $files; Timestamp = [datetime]$raw.Timestamp; RepoPath = $raw.RepoPath }
        } catch {
            Write-AppLog "Git cache load failed: $_" "WARN"
            return $null
        }
    }

    # ==========================================================================
    # METADATA PARSE / WRITE  (supports legacy prefix read + upgrade on save)
    # ==========================================================================
    function Read-AppMetadata {
        param([string]$Content)
        $comment = ""
        $tags    = @()

        if ([string]::IsNullOrEmpty($Content)) {
            return @{ Comment = $comment; Tags = $tags }
        }

        foreach ($line in ($Content -split "`r?`n")) {
            $line = $line.TrimEnd()
            # New prefix
            if ($line.StartsWith($script:CommentPrefix)) {
                $raw     = $line.Substring($script:CommentPrefix.Length).Trim()
                $comment = $raw -replace '\|\|', "`n"
            } elseif ($line.StartsWith($script:TagPrefix)) {
                $rawTags = $line.Substring($script:TagPrefix.Length).Trim()
                $tags    = $rawTags -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }
            # Legacy prefix (only used if new prefix not already found)
            elseif ($line.StartsWith($script:LegacyCommentPrefix) -and [string]::IsNullOrEmpty($comment)) {
                $raw     = $line.Substring($script:LegacyCommentPrefix.Length).Trim()
                $comment = $raw -replace '\|\|', "`n"
            } elseif ($line.StartsWith($script:LegacyTagPrefix) -and $tags.Count -eq 0) {
                $rawTags = $line.Substring($script:LegacyTagPrefix.Length).Trim()
                $tags    = $rawTags -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
            }
        }

        return @{ Comment = $comment; Tags = $tags }
    }

    function Write-AppMetadata {
        <#
        .SYNOPSIS
            Injects/replaces SCRIPTMGMT comment and tag lines in file content.
            Both new (##SCRIPTMGMT#) and legacy (##ENGINEERSPOWERAPP#) lines are
            removed and replaced with new-format lines. This is the upgrade path.
            Metadata is inserted after any #! shebang or #Requires lines.
        #>
        param(
            [string]$Content,
            [string]$Comment,
            [string[]]$Tags
        )

        # Strip all existing app metadata lines (both new and legacy prefixes)
        $lines = ($Content -split "`r?`n") | Where-Object {
            $l = $_.TrimStart()
            -not $l.StartsWith($script:CommentPrefix)       -and
            -not $l.StartsWith($script:TagPrefix)           -and
            -not $l.StartsWith($script:LegacyCommentPrefix) -and
            -not $l.StartsWith($script:LegacyTagPrefix)
        }

        # Build new metadata lines
        $newLines = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($Comment)) {
            $encoded = $Comment -replace "`r`n","||" -replace "`r","||" -replace "`n","||"
            $newLines.Add("$($script:CommentPrefix)$encoded")
        }
        if ($Tags -and $Tags.Count -gt 0) {
            $tagString = ($Tags | Where-Object { $_ -ne "" }) -join ","
            if (-not [string]::IsNullOrWhiteSpace($tagString)) {
                $newLines.Add("$($script:TagPrefix)$tagString")
            }
        }

        # Re-insert metadata after any leading shebang/#Requires lines
        $finalLines    = [System.Collections.Generic.List[string]]::new()
        $insertedMeta  = $false
        foreach ($line in $lines) {
            if (-not $insertedMeta -and
                -not $line.TrimStart().StartsWith("#!") -and
                -not $line.TrimStart().StartsWith("#Requires")) {
                foreach ($ml in $newLines) { $finalLines.Add($ml) }
                $insertedMeta = $true
            }
            $finalLines.Add($line)
        }
        if (-not $insertedMeta) {
            foreach ($ml in $newLines) { $finalLines.Add($ml) }
        }

        return ($finalLines -join "`n")
    }

    # ==========================================================================
    # PNP MODULE CHECK  (only required for sync — not a startup hard dependency)
    # ==========================================================================
    function Test-PnPModule {
        if (-not (Get-Module -ListAvailable -Name "PnP.PowerShell")) {
            $result = [System.Windows.MessageBox]::Show(
                "PnP.PowerShell module is required for SharePoint sync but is not installed.`n`nWould you like to install it now?`n(Requires internet access — runs: Install-Module PnP.PowerShell -Scope CurrentUser)",
                "PnP.PowerShell Not Installed",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                try {
                    Show-Loading "Installing PnP.PowerShell module..."
                    Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber
                    Import-Module PnP.PowerShell -ErrorAction Stop
                    Hide-Loading
                    Write-AppLog "PnP.PowerShell installed successfully"
                    return $true
                } catch {
                    Hide-Loading
                    [System.Windows.MessageBox]::Show(
                        "Installation failed: $_`n`nPlease run manually in an elevated PowerShell 7 session:`nInstall-Module PnP.PowerShell -Scope CurrentUser",
                        "Install Failed",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                    return $false
                }
            }
            return $false
        }
        Import-Module PnP.PowerShell -ErrorAction SilentlyContinue
        return $true
    }

    function Test-SharePointConfig {
        $c = $script:Config
        return (
            -not [string]::IsNullOrWhiteSpace($c.SharePointSiteUrl)      -and
            -not [string]::IsNullOrWhiteSpace($c.SharePointFolderPath)   -and
            -not [string]::IsNullOrWhiteSpace($c.EntraClientId)
        )
    }

    # ==========================================================================
    # MD5 HASH HELPER
    # ==========================================================================
    function Get-FileMD5 {
        param([string]$FilePath)
        try {
            $md5    = [System.Security.Cryptography.MD5]::Create()
            $stream = [System.IO.File]::OpenRead($FilePath)
            $hash   = [System.BitConverter]::ToString($md5.ComputeHash($stream)).Replace("-","")
            $stream.Close()
            return $hash
        } catch {
            return $null
        }
    }

    # ==========================================================================
    # SHAREPOINT SYNC  (runs in a runspace — PnP interactive auth blocks UI)
    # ==========================================================================
    function Start-SharePointSync {
        if (-not (Test-PnPModule))      { return }
        if (-not (Test-SharePointConfig)) {
            [System.Windows.MessageBox]::Show(
                "SharePoint sync is not configured.`n`nPlease open Settings and fill in:`n  • SharePoint Site URL`n  • SharePoint Folder Path`n  • Entra Client ID",
                "Sync Not Configured",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $repoPath = $script:Config.GitRepoPath
        if ([string]::IsNullOrWhiteSpace($repoPath) -or -not (Test-Path $repoPath -PathType Container)) {
            [System.Windows.MessageBox]::Show(
                "Git repository path is not set or does not exist.`n`nCheck Settings.",
                "Repo Path Invalid",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }

        Show-Loading "Connecting to SharePoint...`nPlease complete authentication in the popup window."
        Write-AppLog "SharePoint sync started. Repo: $repoPath"

        $runspace                = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $runspace.ApartmentState = "STA"
        $runspace.Open()

        $ps          = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $runspace

        # Capture all config values we need inside the runspace
        $rsConfig = @{
            LogFile              = $script:LogFile
            GitRepoPath          = $script:Config.GitRepoPath
            SharePointSiteUrl    = $script:Config.SharePointSiteUrl
            SharePointFolderPath = $script:Config.SharePointFolderPath
            EntraClientId        = $script:Config.EntraClientId
            FileTypes            = $script:FileTypes
        }

        $ps.AddScript({
            param($rsConfig)

            function RS-Log {
                param([string]$Msg, [string]$Level = "INFO")
                $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Add-Content -Path $rsConfig.LogFile -Value "[$ts] [$Level] [SYNC] $Msg" -ErrorAction SilentlyContinue
            }

            function Get-MD5Hash {
                param([string]$FilePath)
                try {
                    $md5    = [System.Security.Cryptography.MD5]::Create()
                    $stream = [System.IO.File]::OpenRead($FilePath)
                    $hash   = [System.BitConverter]::ToString($md5.ComputeHash($stream)).Replace("-","")
                    $stream.Close()
                    return $hash
                } catch { return $null }
            }

            try {
                # ------------------------------------------------------------------
                # PATH SANITIZATION
                # SharePoint blocks folder/file names with leading ! or . characters.
                # Sanitize-SpPath converts each path segment: leading ! or . becomes -
                # Applied to all SP destination paths. Local repo paths are never modified.
                # ------------------------------------------------------------------
                function Sanitize-SpSegment {
                    param([string]$Segment)
                    # Replace leading ! or . with - (SharePoint rejects both as first char)
                    return $Segment -replace '^[!.]+', '-'
                }

                function Sanitize-SpPath {
                    param([string]$RelPath)
                    # Split on /, sanitize each segment, rejoin
                    $segments = $RelPath -split '/'
                    $sanitized = $segments | ForEach-Object { Sanitize-SpSegment $_ }
                    return $sanitized -join '/'
                }

                RS-Log "Importing PnP.PowerShell..."
                Import-Module PnP.PowerShell -ErrorAction Stop

                RS-Log "Connecting to $($rsConfig.SharePointSiteUrl)..."
                Connect-PnPOnline -Url $rsConfig.SharePointSiteUrl `
                                  -Interactive `
                                  -ClientId $rsConfig.EntraClientId `
                                  -ErrorAction Stop
                RS-Log "Connected successfully."

                # ------------------------------------------------------------------
                # Build server-relative folder path for the sync target.
                # SharePointFolderPath is the full path within the site, no leading slash.
                # e.g. "Documents/Engineering Procedures/!GitScriptsRepo"
                # We prepend the site-relative path prefix to get a server-relative URL
                # that PnP can use for Get-PnPFolderItem and Add-PnPFile.
                # ------------------------------------------------------------------
                $siteRelative = $rsConfig.SharePointSiteUrl -replace "https://[^/]+"
                $siteRelative = $siteRelative.TrimEnd("/")
                $folderPath   = $rsConfig.SharePointFolderPath.Trim("/")
                $targetFolder = "$siteRelative/$folderPath"
                RS-Log "Sync target folder (server-relative): $targetFolder"

                # ------------------------------------------------------------------
                # Enumerate local Git repo files
                # ------------------------------------------------------------------
                $localFiles = Get-ChildItem -Path $rsConfig.GitRepoPath `
                                            -Recurse -File `
                                            -Include $rsConfig.FileTypes `
                                            -ErrorAction Stop

                RS-Log "Local files found: $($localFiles.Count)"

                # ------------------------------------------------------------------
                # Enumerate SharePoint files in the target folder (recursive)
                # ------------------------------------------------------------------
                RS-Log "Enumerating SharePoint files in target folder..."
                $spFiles = @{}
                try {
                    $spItems = Get-PnPFolderItem -FolderSiteRelativeUrl $targetFolder `
                                                  -ItemType File `
                                                  -Recursive `
                                                  -ErrorAction Stop
                    foreach ($item in $spItems) {
                        # Key = server-relative path (normalized, lowercased for comparison)
                        $spFiles[$item.ServerRelativeUrl.ToLower()] = $item
                    }
                    RS-Log "SharePoint files found: $($spFiles.Count)"
                } catch {
                    # Folder may not exist yet — that's OK, we'll create via upload
                    RS-Log "Could not enumerate SP folder (may not exist yet): $_" "WARN"
                }

                # ------------------------------------------------------------------
                # FOLDER PRE-CREATION PASS
                # Add-PnPFile does NOT create missing folders — it returns "Access denied"
                # if the destination folder doesn't exist. We must ensure every unique
                # folder path in the local repo exists in SharePoint before uploading.
                #
                # Resolve-PnPFolder creates the full folder chain in one call, handles
                # deeply nested paths, and is a no-op if the folder already exists.
                # We use the folder's SITE-relative path (without leading slash) as
                # required by Resolve-PnPFolder's -SiteRelativePath parameter.
                # ------------------------------------------------------------------
                RS-Log "Building folder list from local repo..."
                $uniqueFolders = $localFiles |
                    ForEach-Object {
                        # Use -replace operator (not .Replace()) — avoids backslash escaping
                        # issues when this script block is marshalled into the runspace.
                        $rel = ($_.FullName.Substring($rsConfig.GitRepoPath.Length).TrimStart('/\') -replace '\\','/')
                        $dir = ([System.IO.Path]::GetDirectoryName($rel) -replace '\\','/')
                        $spDir = if ($dir) { Sanitize-SpPath $dir } else { "" }
                        if ($spDir) { "$folderPath/$spDir" } else { $folderPath }
                    } |
                    Sort-Object -Unique

                RS-Log "Unique folders to ensure exist: $($uniqueFolders.Count)"
                $foldersCreated = 0
                $folderErrors   = 0

                # ------------------------------------------------------------------
                # DIAGNOSTIC: verify each ancestor of the root target path exists
                # before attempting Resolve-PnPFolder. Logs each segment so we know
                # exactly where the chain breaks.
                # ------------------------------------------------------------------
                RS-Log "--- Diagnosing ancestor path accessibility ---"
                $rootSegments  = $folderPath -split '/'
                $ancestorPath  = ""
                foreach ($seg in $rootSegments) {
                    $ancestorPath = if ($ancestorPath) { "$ancestorPath/$seg" } else { $seg }
                    try {
                        $folderObj = Get-PnPFolder -Url $ancestorPath -ErrorAction Stop
                        RS-Log "  [OK]     EXISTS: $ancestorPath  (ItemCount=$($folderObj.ItemCount))"
                    } catch {
                        RS-Log "  [MISS]   NOT FOUND or NO ACCESS: $ancestorPath  Error: $_" "WARN"
                    }
                }
                RS-Log "--- End ancestor diagnostic ---"

                foreach ($spFolderRelPath in $uniqueFolders) {
                    try {
                        # Resolve-PnPFolder expects a site-relative path with NO leading slash
                        Resolve-PnPFolder -SiteRelativePath $spFolderRelPath -ErrorAction Stop | Out-Null
                        $foldersCreated++
                    } catch {
                        $folderErrors++
                        RS-Log "  ERROR ensuring folder '$spFolderRelPath': $_" "ERROR"
                        # Only log first 3 errors then break — if root fails, all will fail
                        if ($folderErrors -ge 3) {
                            RS-Log "  Too many folder errors — aborting folder pass. Check ancestor diagnostic above." "ERROR"
                            break
                        }
                    }
                }

                RS-Log "Folder pass complete. Ensured=$foldersCreated Errors=$folderErrors"

                # ------------------------------------------------------------------
                # DELTA SYNC — compare local vs SharePoint
                # ------------------------------------------------------------------
                $uploaded = 0
                $skipped  = 0
                $errors   = 0
                $toDelete = [System.Collections.ArrayList]::new()

                # Track which SP paths we've matched so we can find orphans
                $matchedSpPaths = [System.Collections.Generic.HashSet[string]]::new()

                foreach ($localFile in $localFiles) {
                    # Build the relative path from repo root, use forward slashes
                    $relPath = ($localFile.FullName.Substring($rsConfig.GitRepoPath.Length).TrimStart('/\') -replace '\\','/')

                    # Sanitize the local relative path for SP destination:
                    # leading ! or . on any path segment becomes - in SharePoint.
                    # relPath is used for local file reading; spRelPath is used for all SP ops.
                    $spRelPath       = Sanitize-SpPath $relPath

                    # Build expected SP server-relative path (sanitized)
                    $expectedSpPath      = "$targetFolder/$spRelPath"
                    $expectedSpPathLower = $expectedSpPath.ToLower()

                    # Determine SP target folder for this specific file.
                    $fileRelDir     = ([System.IO.Path]::GetDirectoryName($spRelPath) -replace '\\','/')
                    $spUploadFolder = if ($fileRelDir) {
                        "$targetFolder/$fileRelDir"
                    } else {
                        $targetFolder
                    }

                    # SP file name is also sanitized (e.g. .gitignore -> -gitignore)
                    $spFileName = Sanitize-SpSegment $localFile.Name

                    $needsUpload = $true

                    if ($spFiles.ContainsKey($expectedSpPathLower)) {
                        [void]$matchedSpPaths.Add($expectedSpPathLower)
                        $spItem = $spFiles[$expectedSpPathLower]

                        # --- Timestamp comparison (primary check) ---
                        $localMod = $localFile.LastWriteTimeUtc
                        $spMod    = $spItem.TimeLastModified.ToUniversalTime()
                        $timeDiff = [Math]::Abs(($localMod - $spMod).TotalSeconds)

                        if ($timeDiff -le 2) {
                            # Timestamps match — skip (same file)
                            $needsUpload = $false
                            $skipped++
                            RS-Log "  SKIP (timestamp match): $relPath"
                        } else {
                            # Timestamps differ — check hash as tiebreaker
                            RS-Log "  Timestamp diff $([Math]::Round($timeDiff,1))s for $relPath — checking hash..."
                            $localHash = Get-MD5Hash -FilePath $localFile.FullName

                            # Download SP file content to get its hash
                            try {
                                $spBytes  = Get-PnPFile -Url $spItem.ServerRelativeUrl `
                                                        -AsMemoryStream -ErrorAction Stop
                                $spHash   = [System.BitConverter]::ToString(
                                    [System.Security.Cryptography.MD5]::Create().ComputeHash($spBytes.ToArray())
                                ).Replace("-","")

                                if ($localHash -eq $spHash) {
                                    $needsUpload = $false
                                    $skipped++
                                    RS-Log "  SKIP (hash match): $relPath"
                                } else {
                                    RS-Log "  UPLOAD (hash differs): $relPath"
                                }
                            } catch {
                                # Can't get SP hash — err on side of uploading
                                RS-Log "  UPLOAD (hash check failed, erring toward upload): $relPath" "WARN"
                            }
                        }
                    } else {
                        RS-Log "  UPLOAD (new file): $relPath"
                    }

                    if ($needsUpload) {
                        try {
                            if ($spRelPath -ne $relPath) {
                                RS-Log "  Path mapped: $relPath -> $spRelPath"
                            }
                            $fileBytes = [System.IO.File]::ReadAllBytes($localFile.FullName)
                            $memStream = [System.IO.MemoryStream]::new($fileBytes)
                            Add-PnPFile -Stream $memStream `
                                        -Folder $spUploadFolder `
                                        -FileName $spFileName `
                                        -ErrorAction Stop | Out-Null
                            $memStream.Dispose()
                            $uploaded++
                            RS-Log "  Uploaded: $relPath"
                        } catch {
                            $errors++
                            RS-Log "  ERROR uploading $relPath : $_" "ERROR"
                        }
                    }
                }

                # ------------------------------------------------------------------
                # Identify SP orphans (files in SP not found locally)
                # ------------------------------------------------------------------
                foreach ($spPath in $spFiles.Keys) {
                    if (-not $matchedSpPaths.Contains($spPath)) {
                        [void]$toDelete.Add($spFiles[$spPath].ServerRelativeUrl)
                        RS-Log "  Orphan (candidate for delete): $spPath"
                    }
                }

                RS-Log "Sync scan complete. Uploaded=$uploaded Skipped=$skipped Errors=$errors ToDelete=$($toDelete.Count)"

                return @{
                    Success    = $true
                    Uploaded   = $uploaded
                    Skipped    = $skipped
                    Errors     = $errors
                    ToDelete   = $toDelete.ToArray()
                    SiteUrl    = $rsConfig.SharePointSiteUrl
                    TargetPath = $targetFolder
                }

            } catch {
                RS-Log "Fatal sync error: $_" "ERROR"
                return @{ Success = $false; Error = $_.ToString() }
            }

        }).AddArgument($rsConfig) | Out-Null

        $async = $ps.BeginInvoke()

        $timer          = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(500)
        $timer.Tag      = @{ Async = $async; PS = $ps; Runspace = $runspace }

        $timer.Add_Tick({
            param($timerSender, $e)
            $ctx = $timerSender.Tag
            if (-not $ctx.Async.IsCompleted) { return }
            $timerSender.Stop()

            try {
                $result = $ctx.PS.EndInvoke($ctx.Async)
                Write-AppLog "Sync runspace returned. Success=$($result.Success)"
                Hide-Loading

                if (-not $result.Success) {
                    Set-Status "Sync failed: $($result.Error)" "#FF5555"
                    [System.Windows.MessageBox]::Show(
                        "SharePoint sync failed:`n`n$($result.Error)",
                        "Sync Failed",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                    return
                }

                # ------------------------------------------------------------------
                # Handle deletions — confirm unless SkipDeleteConfirm is set
                # ------------------------------------------------------------------
                $deletedCount = 0

                if ($result.ToDelete -and $result.ToDelete.Count -gt 0) {
                    $proceedWithDelete = $false

                    if ($script:Config.SkipDeleteConfirm -eq $true) {
                        $proceedWithDelete = $true
                        Write-AppLog "SkipDeleteConfirm=true — proceeding with $($result.ToDelete.Count) deletions"
                    } else {
                        # Show confirmation dialog with file list
                        $proceedWithDelete = Show-DeleteConfirmationDialog -FilePaths $result.ToDelete
                    }

                    if ($proceedWithDelete) {
                        Show-Loading "Deleting $($result.ToDelete.Count) orphaned file(s) from SharePoint..."
                        foreach ($spPath in $result.ToDelete) {
                            try {
                                Remove-PnPFile -ServerRelativeUrl $spPath -Force -ErrorAction Stop
                                $deletedCount++
                                Write-AppLog "Deleted from SP: $spPath"
                            } catch {
                                Write-AppLog "Delete failed for $spPath : $_" "ERROR"
                            }
                        }
                        Hide-Loading
                    } else {
                        Write-AppLog "User skipped deletion of $($result.ToDelete.Count) orphan(s)"
                    }
                }

                # ------------------------------------------------------------------
                # Sync summary
                # ------------------------------------------------------------------
                $summary = @"
SharePoint sync complete.

  Uploaded : $($result.Uploaded)
  Skipped  : $($result.Skipped)  (no changes)
  Deleted  : $deletedCount
  Errors   : $($result.Errors)

Target : $($result.TargetPath)
"@
                [System.Windows.MessageBox]::Show(
                    $summary,
                    "Sync Complete",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )

                Set-Status "Sync complete — Uploaded: $($result.Uploaded)  Deleted: $deletedCount  Errors: $($result.Errors)" "#50FA7B"
                $TxtCacheInfo.Text = "Last sync: $(Get-Date -Format 'h:mmtt')"

            } catch {
                Hide-Loading
                Write-AppLog "Sync timer callback error: $_" "ERROR"
                Set-Status "Sync error: $_" "#FF5555"
            } finally {
                $ctx.PS.Dispose()
                $ctx.Runspace.Close()
            }
        })

        $timer.Start()
    }

    # ==========================================================================
    # DELETE CONFIRMATION DIALOG
    # Returns $true if user confirms deletion, $false to skip
    # ==========================================================================
    function Show-DeleteConfirmationDialog {
        param([string[]]$FilePaths)

        $dlg                       = [System.Windows.Window]::new()
        $dlg.Title                 = "Confirm SharePoint Deletions"
        $dlg.Width                 = 640
        $dlg.Height                = 480
        $dlg.MinWidth              = 480
        $dlg.MinHeight             = 320
        $dlg.WindowStartupLocation = "CenterOwner"
        $dlg.Owner                 = $Window
        $dlg.Background            = "#1E1E2E"
        $dlg.ResizeMode            = "CanResize"

        # Root layout
        $root         = [System.Windows.Controls.Grid]::new()
        $row0         = [System.Windows.Controls.RowDefinition]::new(); $row0.Height = [System.Windows.GridLength]::Auto
        $row1         = [System.Windows.Controls.RowDefinition]::new(); $row1.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $row2         = [System.Windows.Controls.RowDefinition]::new(); $row2.Height = [System.Windows.GridLength]::Auto
        $row3         = [System.Windows.Controls.RowDefinition]::new(); $row3.Height = [System.Windows.GridLength]::Auto
        $root.RowDefinitions.Add($row0)
        $root.RowDefinitions.Add($row1)
        $root.RowDefinitions.Add($row2)
        $root.RowDefinitions.Add($row3)
        $root.Margin  = [System.Windows.Thickness]::new(20)
        $dlg.Content  = $root

        # Header
        $header            = [System.Windows.Controls.TextBlock]::new()
        $header.Text       = "The following $($FilePaths.Count) file(s) exist in SharePoint but were NOT found in the local Git repository.`nThey will be permanently deleted from SharePoint if you proceed."
        $header.Foreground = "#FFB86C"
        $header.FontSize   = 12
        $header.TextWrapping = "Wrap"
        $header.Margin     = [System.Windows.Thickness]::new(0,0,0,12)
        [System.Windows.Controls.Grid]::SetRow($header, 0)
        $root.Children.Add($header)

        # Scrollable file list
        $scroll                             = [System.Windows.Controls.ScrollViewer]::new()
        $scroll.VerticalScrollBarVisibility = "Auto"
        $scroll.Background                  = "#252537"
        $scroll.Margin                      = [System.Windows.Thickness]::new(0,0,0,12)
        [System.Windows.Controls.Grid]::SetRow($scroll, 1)
        $root.Children.Add($scroll)

        $listPanel = [System.Windows.Controls.StackPanel]::new()
        $listPanel.Margin = [System.Windows.Thickness]::new(10)
        $scroll.Content   = $listPanel

        foreach ($path in ($FilePaths | Sort-Object)) {
            $tb              = [System.Windows.Controls.TextBlock]::new()
            $tb.Text         = $path
            $tb.Foreground   = "#FF5555"
            $tb.FontFamily   = [System.Windows.Media.FontFamily]::new("Consolas")
            $tb.FontSize     = 11
            $tb.Margin       = [System.Windows.Thickness]::new(0,2,0,2)
            $tb.TextWrapping = "Wrap"
            $listPanel.Children.Add($tb)
        }

        # Skip future confirmation checkbox
        $chkPanel        = [System.Windows.Controls.StackPanel]::new()
        $chkPanel.Orientation = "Horizontal"
        $chkPanel.Margin  = [System.Windows.Thickness]::new(0,0,0,16)
        [System.Windows.Controls.Grid]::SetRow($chkPanel, 2)
        $root.Children.Add($chkPanel)

        $chkSkip              = [System.Windows.Controls.CheckBox]::new()
        $chkSkip.IsChecked    = $false
        $chkSkip.VerticalAlignment = "Center"
        $chkSkip.Foreground   = "#A0A0C0"

        $chkLabel             = [System.Windows.Controls.TextBlock]::new()
        $chkLabel.Text        = "Skip this confirmation in future syncs (can be reset in Settings)"
        $chkLabel.Foreground  = "#A0A0C0"
        $chkLabel.FontSize    = 11
        $chkLabel.Margin      = [System.Windows.Thickness]::new(8,0,0,0)
        $chkLabel.VerticalAlignment = "Center"

        $chkPanel.Children.Add($chkSkip)
        $chkPanel.Children.Add($chkLabel)

        # Buttons
        $btnPanel                     = [System.Windows.Controls.StackPanel]::new()
        $btnPanel.Orientation         = "Horizontal"
        $btnPanel.HorizontalAlignment = "Right"
        [System.Windows.Controls.Grid]::SetRow($btnPanel, 3)
        $root.Children.Add($btnPanel)

        $btnDelete              = [System.Windows.Controls.Button]::new()
        $btnDelete.Content      = "Delete from SharePoint"
        $btnDelete.Width        = 180
        $btnDelete.Height       = 34
        $btnDelete.Background   = "#FF5555"
        $btnDelete.Foreground   = "#F8F8F2"
        $btnDelete.FontWeight   = "SemiBold"
        $btnDelete.Margin       = [System.Windows.Thickness]::new(0,0,8,0)

        $btnSkip                = [System.Windows.Controls.Button]::new()
        $btnSkip.Content        = "Skip Deletions"
        $btnSkip.Width          = 120
        $btnSkip.Height         = 34
        $btnSkip.Background     = "#3A3A55"
        $btnSkip.Foreground     = "#F8F8F2"

        $btnPanel.Children.Add($btnDelete)
        $btnPanel.Children.Add($btnSkip)

        $userConfirmed = $false

        $btnDelete.Add_Click({
            # Save skip preference if checked
            if ($chkSkip.IsChecked -eq $true) {
                $script:Config.SkipDeleteConfirm = $true
                Save-AppConfig -Config $script:Config
                Write-AppLog "SkipDeleteConfirm set to true by user"
            }
            $userConfirmed = $true
            $dlg.DialogResult = $true
            $dlg.Close()
        })

        $btnSkip.Add_Click({
            $dlg.DialogResult = $false
            $dlg.Close()
        })

        $dlg.ShowDialog() | Out-Null
        return ($dlg.DialogResult -eq $true)
    }

    # ==========================================================================
    # SETTINGS DIALOG  (first-run and on-demand)
    #
    # IMPORTANT ARCHITECTURE NOTE:
    # This dialog is built entirely from XAML + XamlReader::Parse() + FindName(),
    # identical to how the main window is built. This is the ONLY reliable approach
    # for creating WPF controls inside deeply-nested PS7 functions.
    #
    # Both ::new() and New-Object for WPF types fail unpredictably when called inside
    # a function that is itself inside another function inside the master function —
    # PS7 resolves the type constructor to a wrong overload, returning an object that
    # looks like the right type but has none of the expected WPF properties. The root
    # cause is PS7's type resolution order at deep nesting depth when multiple WPF
    # assemblies are loaded. XamlReader::Parse() bypasses this entirely.
    # ==========================================================================
    function Show-SettingsDialog {
        param([bool]$IsFirstRun = $false)

        $titleText    = if ($IsFirstRun) { "Welcome! Let's get you set up." } else { "Settings" }
        $subtitleText = if ($IsFirstRun) {
            "Configure your Git repository and optional SharePoint sync settings. SharePoint fields are only needed for the Sync to SharePoint feature."
        } else {
            "Git repo path is required. SharePoint fields are only needed for sync."
        }
        $saveLabel    = if ($IsFirstRun) { "Save &amp; Launch" } else { "Save" }
        $showCancel   = if ($IsFirstRun) { "Collapsed" } else { "Visible" }
        $showReset    = if ((-not $IsFirstRun) -and ($script:Config.SkipDeleteConfirm -eq $true)) { "Visible" } else { "Collapsed" }
        $winHeight    = if ($IsFirstRun) { "560" } else { "620" }

        $settingsXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Settings"
    Height="$winHeight" Width="600" MinWidth="480"
    WindowStartupLocation="CenterScreen"
    Background="#1E1E2E"
    ResizeMode="NoResize">
    <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="24,20,24,20">

            <TextBlock x:Name="TxtSettingsTitle"
                       Foreground="#F8F8F2" FontSize="18" FontWeight="Bold" Margin="0,0,0,4"/>
            <TextBlock x:Name="TxtSettingsSubtitle"
                       Foreground="#6272A4" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,24"/>

            <!-- GIT SECTION -->
            <TextBlock Text="&#x2014; GIT REPOSITORY"
                       Foreground="#7B9CFF" FontSize="11" FontWeight="SemiBold" Margin="0,0,0,12"/>

            <StackPanel Margin="0,0,0,14">
                <TextBlock Text="GIT REPO PATH" Foreground="#6272A4" FontSize="10"
                           FontWeight="SemiBold" Margin="0,0,0,4"/>
                <TextBox x:Name="TxtGitPath" Background="#2E2E45" Foreground="#F8F8F2"
                         BorderBrush="#44446A" BorderThickness="1" Padding="10,7"
                         FontSize="12" FontFamily="Consolas"/>
                <TextBlock Text="Full path to your local repository root.  e.g.  C:\GitHubRepos\Databranch-Client-Scripts"
                           Foreground="#44446A" FontSize="10" Margin="2,4,0,0" TextWrapping="Wrap"/>
            </StackPanel>

            <!-- SHAREPOINT SECTION -->
            <TextBlock Text="&#x2014; SHAREPOINT SYNC  (optional)"
                       Foreground="#7B9CFF" FontSize="11" FontWeight="SemiBold" Margin="0,8,0,12"/>

            <StackPanel Margin="0,0,0,14">
                <TextBlock Text="SHAREPOINT SITE URL  (optional)" Foreground="#6272A4"
                           FontSize="10" FontWeight="SemiBold" Margin="0,0,0,4"/>
                <TextBox x:Name="TxtSpSiteUrl" Background="#2E2E45" Foreground="#F8F8F2"
                         BorderBrush="#44446A" BorderThickness="1" Padding="10,7"
                         FontSize="12" FontFamily="Consolas"/>
                <TextBlock Text="Root URL of your SharePoint site.  e.g.  https://databranch.sharepoint.com  or  https://databranch.sharepoint.com/sites/IT"
                           Foreground="#44446A" FontSize="10" Margin="2,4,0,0" TextWrapping="Wrap"/>
            </StackPanel>

            <StackPanel Margin="0,0,0,14">
                <TextBlock Text="SHAREPOINT FOLDER PATH  (optional)" Foreground="#6272A4"
                           FontSize="10" FontWeight="SemiBold" Margin="0,0,0,4"/>
                <TextBox x:Name="TxtSpFolderPath" Background="#2E2E45" Foreground="#F8F8F2"
                         BorderBrush="#44446A" BorderThickness="1" Padding="10,7"
                         FontSize="12" FontFamily="Consolas"/>
                <TextBlock Foreground="#44446A" FontSize="10" Margin="2,4,0,0" TextWrapping="Wrap">
                    <Run Text="Full folder path within your site. No leading slash. Library name is the first segment."/>
                    <LineBreak/>
                    <Run Text="Find it: navigate to the folder in SharePoint, copy the URL, decode the id= parameter value, drop the leading slash."/>
                    <LineBreak/>
                    <Run Text="e.g.  Documents/Engineering Procedures/!GitScriptsRepo" FontFamily="Consolas"/>
                </TextBlock>
            </StackPanel>

            <StackPanel Margin="0,0,0,14">
                <TextBlock Text="ENTRA APP CLIENT ID  (optional)" Foreground="#6272A4"
                           FontSize="10" FontWeight="SemiBold" Margin="0,0,0,4"/>
                <TextBox x:Name="TxtClientId" Background="#2E2E45" Foreground="#F8F8F2"
                         BorderBrush="#44446A" BorderThickness="1" Padding="10,7"
                         FontSize="12" FontFamily="Consolas"/>
                <TextBlock Foreground="#44446A" FontSize="10" Margin="2,4,0,0" TextWrapping="Wrap">
                    <Run Text="Client ID from your PnP Entra app registration. To create:"/>
                    <LineBreak/>
                    <Run Text="Register-PnPEntraIDAppForInteractiveLogin -ApplicationName 'PnP.PowerShell' -Tenant 'databranch.onmicrosoft.com' -Interactive"
                         FontFamily="Consolas"/>
                </TextBlock>
            </StackPanel>

            <!-- Delete confirmation reset banner (only shown when SkipDeleteConfirm = true) -->
            <Border x:Name="PanelResetDeleteConfirm"
                    Visibility="$showReset"
                    Background="#252537" BorderBrush="#FF5555" BorderThickness="1"
                    CornerRadius="6" Padding="14,10" Margin="0,8,0,14">
                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="Delete confirmation is currently disabled.  "
                               Foreground="#FFB86C" FontSize="11" VerticalAlignment="Center"/>
                    <Button x:Name="BtnResetDeleteConfirm" Content="Re-enable"
                            Background="#3A3A55" Foreground="#F8F8F2"
                            Padding="10,4" FontSize="11" Cursor="Hand"
                            BorderThickness="1" BorderBrush="#44446A"/>
                </StackPanel>
            </Border>

            <!-- Buttons -->
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
                <Button x:Name="BtnSettingsCancel" Content="Cancel"
                        Width="80" Height="34" Margin="0,0,8,0"
                        Background="#3A3A55" Foreground="#F8F8F2"
                        BorderThickness="1" BorderBrush="#44446A"
                        Cursor="Hand" Visibility="$showCancel"/>
                <Button x:Name="BtnSettingsSave" Content="$saveLabel"
                        Width="130" Height="34"
                        Background="#7B9CFF" Foreground="#1E1E2E"
                        FontWeight="SemiBold" BorderThickness="0" Cursor="Hand"/>
            </StackPanel>

        </StackPanel>
    </ScrollViewer>
</Window>
"@

        $dlg = [Windows.Markup.XamlReader]::Parse($settingsXaml)

        # Populate dynamic text (can't embed PS variables directly in XAML heredoc safely)
        $dlg.FindName("TxtSettingsTitle").Text    = $titleText
        $dlg.FindName("TxtSettingsSubtitle").Text = $subtitleText

        # Pre-fill current config values
        $dlg.FindName("TxtGitPath").Text      = $script:Config.GitRepoPath
        $dlg.FindName("TxtSpSiteUrl").Text    = $script:Config.SharePointSiteUrl
        $dlg.FindName("TxtSpFolderPath").Text = $script:Config.SharePointFolderPath
        $dlg.FindName("TxtClientId").Text     = $script:Config.EntraClientId

        # Wire buttons
        $dlg.FindName("BtnSettingsCancel").Add_Click({ $dlg.Close() })

        $dlg.FindName("BtnResetDeleteConfirm").Add_Click({
            $script:Config.SkipDeleteConfirm = $false
            Save-AppConfig -Config $script:Config
            $dlg.FindName("PanelResetDeleteConfirm").Visibility = "Collapsed"
            Write-AppLog "SkipDeleteConfirm reset to false by user"
        })

        $dlg.FindName("BtnSettingsSave").Add_Click({
            $gitPath = $dlg.FindName("TxtGitPath").Text.Trim()
            if ([string]::IsNullOrWhiteSpace($gitPath)) {
                [System.Windows.MessageBox]::Show(
                    "Git Repo Path is required.",
                    "Validation Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                )
                return
            }
            $script:Config.GitRepoPath          = $gitPath
            $script:Config.SharePointSiteUrl    = $dlg.FindName("TxtSpSiteUrl").Text.Trim().TrimEnd("/")
            $script:Config.SharePointFolderPath = $dlg.FindName("TxtSpFolderPath").Text.Trim().Trim("/")
            $script:Config.EntraClientId        = $dlg.FindName("TxtClientId").Text.Trim()
            Save-AppConfig -Config $script:Config
            $dlg.DialogResult = $true
            $dlg.Close()
        })

        return ($dlg.ShowDialog() -eq $true)
    }

    # ==========================================================================
    # WPF ASSEMBLY LOADING
    # ==========================================================================
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Windows.Forms

    # ==========================================================================
    # WPF XAML
    # NOTE: Do NOT cast to [xml] — use XamlReader::Parse() on the raw string.
    # Casting strips x: namespace attributes causing null control references.
    # ==========================================================================
    $XAMLString = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Script Management Browser"
    Height="800" Width="1280" MinHeight="600" MinWidth="900"
    WindowStartupLocation="CenterScreen"
    Background="#1E1E2E">

    <Window.Resources>
        <SolidColorBrush x:Key="BgDeep"       Color="#1E1E2E"/>
        <SolidColorBrush x:Key="BgPanel"      Color="#252537"/>
        <SolidColorBrush x:Key="BgCard"       Color="#2E2E45"/>
        <SolidColorBrush x:Key="BgHover"      Color="#3A3A55"/>
        <SolidColorBrush x:Key="BgSelected"   Color="#4B4B70"/>
        <SolidColorBrush x:Key="AccentBlue"   Color="#7B9CFF"/>
        <SolidColorBrush x:Key="AccentGreen"  Color="#50FA7B"/>
        <SolidColorBrush x:Key="AccentOrange" Color="#FFB86C"/>
        <SolidColorBrush x:Key="AccentRed"    Color="#FF5555"/>
        <SolidColorBrush x:Key="TextPrimary"  Color="#F8F8F2"/>
        <SolidColorBrush x:Key="TextSecond"   Color="#A0A0C0"/>
        <SolidColorBrush x:Key="TextMuted"    Color="#6272A4"/>
        <SolidColorBrush x:Key="BorderColor"  Color="#44446A"/>
        <SolidColorBrush x:Key="PS1Color"     Color="#BD93F9"/>
        <SolidColorBrush x:Key="BatColor"     Color="#FFB86C"/>

        <Style x:Key="AppButton" TargetType="Button">
            <Setter Property="Background"       Value="#3A3A55"/>
            <Setter Property="Foreground"       Value="#F8F8F2"/>
            <Setter Property="BorderThickness"  Value="1"/>
            <Setter Property="BorderBrush"      Value="#44446A"/>
            <Setter Property="Padding"          Value="12,6"/>
            <Setter Property="FontSize"         Value="12"/>
            <Setter Property="Cursor"           Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#4B4B70"/>
                                <Setter Property="BorderBrush" Value="#7B9CFF"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#5C5C88"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource AppButton}">
            <Setter Property="Background"  Value="#7B9CFF"/>
            <Setter Property="Foreground"  Value="#1E1E2E"/>
            <Setter Property="FontWeight"  Value="SemiBold"/>
            <Setter Property="BorderBrush" Value="#7B9CFF"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#9BB4FF"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SyncButton" TargetType="Button" BasedOn="{StaticResource AppButton}">
            <Setter Property="Background"  Value="#44663A"/>
            <Setter Property="Foreground"  Value="#50FA7B"/>
            <Setter Property="BorderBrush" Value="#50FA7B"/>
            <Setter Property="FontWeight"  Value="SemiBold"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#557A49"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="AppTextBox" TargetType="TextBox">
            <Setter Property="Background"        Value="#1E1E2E"/>
            <Setter Property="Foreground"        Value="#F8F8F2"/>
            <Setter Property="BorderBrush"       Value="#44446A"/>
            <Setter Property="BorderThickness"   Value="1"/>
            <Setter Property="Padding"           Value="8,6"/>
            <Setter Property="FontSize"          Value="12"/>
            <Setter Property="CaretBrush"        Value="#7B9CFF"/>
            <Setter Property="SelectionBrush"    Value="#4B4B70"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4">
                            <ScrollViewer x:Name="PART_ContentHost" Padding="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter Property="BorderBrush" Value="#7B9CFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="FileListItem" TargetType="ListBoxItem">
            <Setter Property="Background"  Value="Transparent"/>
            <Setter Property="Foreground"  Value="#F8F8F2"/>
            <Setter Property="Padding"     Value="10,7"/>
            <Setter Property="Margin"      Value="2,1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="4" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#3A3A55"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Background" Value="#4B4B70"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Width"      Value="8"/>
        </Style>

        <Style x:Key="MetaLabel" TargetType="TextBlock">
            <Setter Property="Foreground"  Value="#6272A4"/>
            <Setter Property="FontSize"    Value="10"/>
            <Setter Property="FontWeight"  Value="SemiBold"/>
            <Setter Property="Margin"      Value="0,0,0,2"/>
        </Style>

        <Style x:Key="MetaValue" TargetType="TextBlock">
            <Setter Property="Foreground"    Value="#A0A0C0"/>
            <Setter Property="FontSize"      Value="12"/>
            <Setter Property="Margin"        Value="0,0,0,10"/>
            <Setter Property="TextWrapping"  Value="Wrap"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="50"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="28"/>
        </Grid.RowDefinitions>

        <!-- TITLE BAR -->
        <Border Grid.Row="0" Background="#252537" BorderBrush="#44446A" BorderThickness="0,0,0,1">
            <Grid Margin="16,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="[*]" FontSize="20" Foreground="#7B9CFF" Margin="0,0,10,0" VerticalAlignment="Center"/>
                    <TextBlock Text="Script Management Browser" FontSize="16" FontWeight="Bold"
                               Foreground="#F8F8F2" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TxtVersionBadge" Text=" v1.0.0.0"
                               FontSize="11" Foreground="#44446A" VerticalAlignment="Center"/>
                </StackPanel>

                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="BtnRefresh"  Style="{StaticResource AppButton}"
                            Content="[R] Refresh" IsEnabled="False"
                            ToolTip="Re-scan local Git repository" Margin="0,0,8,0"/>
                    <Button x:Name="BtnSync"     Style="{StaticResource SyncButton}"
                            Content="[^] Sync to SharePoint"
                            ToolTip="Push changes from Git repository to SharePoint (one-way)" Margin="0,0,8,0"/>
                    <Button x:Name="BtnSettings" Style="{StaticResource AppButton}"
                            Content="[=] Settings"
                            ToolTip="Configure repository path and SharePoint settings" Margin="0,0,8,0"/>
                    <Border Width="1" Background="#44446A" Margin="4,8"/>
                    <TextBlock x:Name="TxtConnectionStatus" Text="[G] Git Repo"
                               Foreground="#6272A4" VerticalAlignment="Center" FontSize="11" Margin="8,0,0,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- MAIN CONTENT -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="320" MinWidth="220" MaxWidth="500"/>
                <ColumnDefinition Width="5"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- LEFT PANEL -->
            <Border Grid.Column="0" Background="#252537" BorderBrush="#44446A" BorderThickness="0,0,1,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Search -->
                    <Border Grid.Row="0" Margin="10,10,10,6" Background="#1E1E2E"
                            BorderBrush="#44446A" BorderThickness="1" CornerRadius="6">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="TxtSearch" Grid.Column="0"
                                     Background="Transparent" Foreground="#F8F8F2"
                                     BorderThickness="0" Padding="10,8"
                                     FontSize="13" CaretBrush="#7B9CFF"
                                     VerticalAlignment="Center">
                                <TextBox.Style>
                                    <Style TargetType="TextBox">
                                        <Style.Triggers>
                                            <Trigger Property="Text" Value="">
                                                <Setter Property="Background">
                                                    <Setter.Value>
                                                        <VisualBrush Stretch="None" AlignmentX="Left">
                                                            <VisualBrush.Visual>
                                                                <TextBlock Text="Search files, tags, comments..."
                                                                           Foreground="#6272A4" FontSize="13" Padding="10,8"/>
                                                            </VisualBrush.Visual>
                                                        </VisualBrush>
                                                    </Setter.Value>
                                                </Setter>
                                            </Trigger>
                                        </Style.Triggers>
                                    </Style>
                                </TextBox.Style>
                            </TextBox>
                            <Button x:Name="BtnClearSearch" Grid.Column="1" Content="X"
                                    Background="Transparent" BorderThickness="0"
                                    Foreground="#6272A4" Padding="8,0" Cursor="Hand"
                                    VerticalAlignment="Center" FontSize="12"/>
                        </Grid>
                    </Border>

                    <!-- View mode toggle -->
                    <Border Grid.Row="1" Margin="10,0,10,8" Background="#1E1E2E"
                            BorderBrush="#44446A" BorderThickness="1" CornerRadius="6">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="BtnViewAlpha" Grid.Column="0" Content="A-Z"
                                    Background="#4B4B70" Foreground="#F8F8F2"
                                    BorderThickness="0" Padding="0,6"
                                    FontSize="11" Cursor="Hand" FontWeight="SemiBold">
                                <Button.Template>
                                    <ControlTemplate TargetType="Button">
                                        <Border Background="{TemplateBinding Background}"
                                                CornerRadius="5,0,0,5" Padding="{TemplateBinding Padding}">
                                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Border>
                                    </ControlTemplate>
                                </Button.Template>
                            </Button>
                            <Button x:Name="BtnViewFolder" Grid.Column="1" Content="[/] Folder"
                                    Background="Transparent" Foreground="#A0A0C0"
                                    BorderThickness="0" Padding="0,6"
                                    FontSize="11" Cursor="Hand">
                                <Button.Template>
                                    <ControlTemplate TargetType="Button">
                                        <Border Background="{TemplateBinding Background}"
                                                Padding="{TemplateBinding Padding}">
                                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter Property="Background" Value="#3A3A55"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </Button.Template>
                            </Button>
                            <Button x:Name="BtnViewTag" Grid.Column="2" Content="[#] Tags"
                                    Background="Transparent" Foreground="#A0A0C0"
                                    BorderThickness="0" Padding="0,6"
                                    FontSize="11" Cursor="Hand">
                                <Button.Template>
                                    <ControlTemplate TargetType="Button">
                                        <Border Background="{TemplateBinding Background}"
                                                CornerRadius="0,5,5,0" Padding="{TemplateBinding Padding}">
                                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter Property="Background" Value="#3A3A55"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </Button.Template>
                            </Button>
                        </Grid>
                    </Border>

                    <!-- File list -->
                    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto"
                                  HorizontalScrollBarVisibility="Disabled">
                        <StackPanel>
                            <ListBox x:Name="FileListBox" Background="Transparent"
                                     BorderThickness="0" Padding="5,0"
                                     ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                                     ItemContainerStyle="{StaticResource FileListItem}"
                                     VirtualizingPanel.IsVirtualizing="True"
                                     VirtualizingPanel.VirtualizationMode="Recycling">
                                <ListBox.ItemTemplate>
                                    <DataTemplate>
                                        <Grid>
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="Auto"/>
                                                <ColumnDefinition Width="*"/>
                                            </Grid.ColumnDefinitions>
                                            <TextBlock Grid.Column="0" Text="{Binding ExtIcon}"
                                                       FontSize="11" Margin="0,0,8,0"
                                                       Foreground="{Binding ExtColor}"
                                                       VerticalAlignment="Center"/>
                                            <StackPanel Grid.Column="1">
                                                <TextBlock Text="{Binding Name}" FontSize="12"
                                                           Foreground="#F8F8F2" TextTrimming="CharacterEllipsis"/>
                                                <TextBlock Text="{Binding SubInfo}" FontSize="10"
                                                           Foreground="#6272A4" TextTrimming="CharacterEllipsis"/>
                                            </StackPanel>
                                        </Grid>
                                    </DataTemplate>
                                </ListBox.ItemTemplate>
                            </ListBox>

                            <TreeView x:Name="FileTreeView" Background="Transparent"
                                      BorderThickness="0" Padding="5,0"
                                      Visibility="Collapsed">
                                <TreeView.Resources>
                                    <Style TargetType="TreeViewItem">
                                        <Setter Property="Background"  Value="Transparent"/>
                                        <Setter Property="Foreground"  Value="#F8F8F2"/>
                                        <Setter Property="IsExpanded"  Value="True"/>
                                    </Style>
                                </TreeView.Resources>
                            </TreeView>
                        </StackPanel>
                    </ScrollViewer>

                    <!-- File count footer -->
                    <Border Grid.Row="3" Background="#1E1E2E" BorderBrush="#44446A"
                            BorderThickness="0,1,0,0" Padding="10,6">
                        <TextBlock x:Name="TxtFileCount" Text="No files loaded"
                                   Foreground="#6272A4" FontSize="11"/>
                    </Border>
                </Grid>
            </Border>

            <!-- Grid Splitter -->
            <GridSplitter Grid.Column="1" Width="5" HorizontalAlignment="Stretch"
                          Background="#2E2E45" Cursor="SizeWE"/>

            <!-- RIGHT PANEL -->
            <Grid Grid.Column="2" Background="#1E1E2E">

                <!-- Empty state -->
                <StackPanel x:Name="PanelEmpty" VerticalAlignment="Center" HorizontalAlignment="Center">
                    <TextBlock Text="[*]" FontSize="64" HorizontalAlignment="Center"
                               Foreground="#3A3A55"/>
                    <TextBlock Text="Select a script to view details" FontSize="16"
                               Foreground="#44446A" HorizontalAlignment="Center" Margin="0,16,0,8"/>
                    <TextBlock x:Name="TxtEmptyHint"
                               Text="Open your Git repository to get started"
                               FontSize="12" Foreground="#3A3A55" HorizontalAlignment="Center"/>
                </StackPanel>

                <!-- Detail panel -->
                <ScrollViewer x:Name="PanelDetail" Visibility="Collapsed"
                              VerticalScrollBarVisibility="Auto">
                    <Grid Margin="24,20,24,20">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>

                        <!-- File Header -->
                        <Border Grid.Row="0" Background="#252537" CornerRadius="8"
                                Padding="20,16" Margin="0,0,0,16"
                                BorderBrush="#44446A" BorderThickness="1">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <Border Grid.Column="0" Width="50" Height="50"
                                        Background="#2E2E45" CornerRadius="8" Margin="0,0,16,0">
                                    <TextBlock x:Name="TxtFileIcon" Text="PS1" FontSize="14"
                                               FontWeight="Bold" HorizontalAlignment="Center"
                                               VerticalAlignment="Center" Foreground="#BD93F9"/>
                                </Border>
                                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                    <TextBlock x:Name="TxtDetailName" Text="filename.ps1"
                                               FontSize="18" FontWeight="Bold" Foreground="#F8F8F2"
                                               TextTrimming="CharacterEllipsis"/>
                                    <TextBlock x:Name="TxtDetailPath" Text="/path/to/file.ps1"
                                               FontSize="11" Foreground="#6272A4" Margin="0,4,0,0"
                                               TextTrimming="CharacterEllipsis"/>
                                </StackPanel>
                                <Button x:Name="BtnRename" Grid.Column="2"
                                        Style="{StaticResource AppButton}"
                                        Content="Rename" VerticalAlignment="Center"/>
                            </Grid>
                        </Border>

                        <!-- Metadata Cards -->
                        <Grid Grid.Row="1" Margin="0,0,0,16">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <Border Grid.Column="0" Background="#252537" CornerRadius="6"
                                    Padding="14,12" BorderBrush="#44446A" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="CREATED"      Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaCreated" Text="-" Style="{StaticResource MetaValue}"/>
                                    <TextBlock Text="MODIFIED"     Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaModified" Text="-" Style="{StaticResource MetaValue}"/>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="2" Background="#252537" CornerRadius="6"
                                    Padding="14,12" BorderBrush="#44446A" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="TYPE"         Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaType" Text="-" Style="{StaticResource MetaValue}"/>
                                    <TextBlock Text="SIZE"         Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaSize" Text="-" Style="{StaticResource MetaValue}"/>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="4" Background="#252537" CornerRadius="6"
                                    Padding="14,12" BorderBrush="#44446A" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="FOLDER"       Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaFolder" Text="-" Style="{StaticResource MetaValue}"
                                               TextTrimming="CharacterEllipsis"/>
                                    <TextBlock Text="LIBRARY"      Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaLibrary" Text="-" Style="{StaticResource MetaValue}"/>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="6" Background="#252537" CornerRadius="6"
                                    Padding="14,12" BorderBrush="#44446A" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="SHAREPOINT URL" Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaSpUrl" Text="-"
                                               Style="{StaticResource MetaValue}"
                                               TextTrimming="CharacterEllipsis"
                                               ToolTip="Use [Copy SP URL] button to copy this link"/>
                                </StackPanel>
                            </Border>
                        </Grid>

                        <!-- Action Buttons -->
                        <Border Grid.Row="2" Background="#252537" CornerRadius="8"
                                Padding="16,12" Margin="0,0,0,16"
                                BorderBrush="#44446A" BorderThickness="1">
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="BtnOpenVSCode"  Style="{StaticResource AccentButton}"
                                        Content="[VS] Open in VSCode" Margin="0,0,8,0"
                                        ToolTip="Open this file in Visual Studio Code"/>
                                <Button x:Name="BtnLoadContent" Style="{StaticResource AppButton}"
                                        Content="[L] Load Content" Margin="0,0,8,0"
                                        ToolTip="Load file content for preview and metadata editing"/>
                                <Border Width="1" Background="#44446A" Margin="4,4"/>
                                <Button x:Name="BtnCopyPath"    Style="{StaticResource AppButton}"
                                        Content="Copy Local Path" Margin="8,0,8,0"
                                        ToolTip="Copy full local filesystem path to clipboard"/>
                                <Button x:Name="BtnCopyUrl"     Style="{StaticResource AppButton}"
                                        Content="Copy SP URL" Margin="0,0,0,0"
                                        ToolTip="Copy SharePoint URL for this file (for sharing with junior engineers via Teams etc.)"/>
                            </StackPanel>
                        </Border>

                        <!-- Comment Section -->
                        <Border Grid.Row="3" Background="#252537" CornerRadius="8"
                                Padding="16,14" Margin="0,0,0,12"
                                BorderBrush="#44446A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <TextBlock Text="[C]" FontSize="14" Margin="0,0,8,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="COMMENT" FontSize="11" FontWeight="SemiBold"
                                               Foreground="#6272A4" VerticalAlignment="Center"/>
                                    <TextBlock Text=" — stored as  ##SCRIPTMGMT#COMMENT#  in file"
                                               FontSize="10" Foreground="#44446A" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBox x:Name="TxtComment" Style="{StaticResource AppTextBox}"
                                         Height="80" TextWrapping="Wrap" AcceptsReturn="True"
                                         VerticalScrollBarVisibility="Auto"
                                         VerticalContentAlignment="Top"
                                         Text="" FontFamily="Consolas" FontSize="12"/>
                                <TextBlock Text="Multi-line supported. Load file content first to see existing comments."
                                           FontSize="10" Foreground="#44446A" Margin="0,6,0,0"/>
                            </StackPanel>
                        </Border>

                        <!-- Tags Section -->
                        <Border Grid.Row="4" Background="#252537" CornerRadius="8"
                                Padding="16,14" Margin="0,0,0,12"
                                BorderBrush="#44446A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <TextBlock Text="[#]" FontSize="14" Margin="0,0,8,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="TAGS" FontSize="11" FontWeight="SemiBold"
                                               Foreground="#6272A4" VerticalAlignment="Center"/>
                                    <TextBlock Text=" — stored as  ##SCRIPTMGMT#TAGS#  in file"
                                               FontSize="10" Foreground="#44446A" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBox x:Name="TxtTags" Style="{StaticResource AppTextBox}"
                                         Height="36" VerticalContentAlignment="Center"
                                         Text="" FontFamily="Consolas" FontSize="12"/>
                                <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                                    <TextBlock Text="Quick add:" FontSize="10" Foreground="#6272A4"
                                               VerticalAlignment="Center" Margin="0,0,4,0"/>
                                    <Button x:Name="BtnTagAutomation"  Content="automation"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#BD93F9" BorderBrush="#BD93F9" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagMaintenance" Content="maintenance"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#50FA7B" BorderBrush="#50FA7B" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagDeploy"      Content="deployment"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#FFB86C" BorderBrush="#FFB86C" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagMonitor"     Content="monitoring"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#FF79C6" BorderBrush="#FF79C6" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagSecurity"    Content="security"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#FF5555" BorderBrush="#FF5555" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagUtil"        Content="utility"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#8BE9FD" BorderBrush="#8BE9FD"/>
                                </StackPanel>
                                <TextBlock Text="Comma-separated. Load file content first to see existing tags."
                                           FontSize="10" Foreground="#44446A" Margin="0,6,0,0"/>
                            </StackPanel>
                        </Border>

                        <!-- File Content Preview -->
                        <Border Grid.Row="5" Background="#252537" CornerRadius="8"
                                Padding="16,14" Margin="0,0,0,12"
                                BorderBrush="#44446A" BorderThickness="1">
                            <StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                    <TextBlock Text="[F]" FontSize="14" Margin="0,0,8,0" VerticalAlignment="Center"/>
                                    <TextBlock Text="FILE PREVIEW" FontSize="11" FontWeight="SemiBold"
                                               Foreground="#6272A4" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="TxtPreviewNote"
                                               Text=" — click 'Load Content' above"
                                               FontSize="10" Foreground="#44446A" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBox x:Name="TxtFileContent"
                                         Background="#1E1E2E" Foreground="#F8F8F2"
                                         BorderBrush="#44446A" BorderThickness="1"
                                         Padding="12,10" FontFamily="Consolas" FontSize="11"
                                         Height="250" TextWrapping="NoWrap" AcceptsReturn="True"
                                         IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                                         HorizontalScrollBarVisibility="Auto"
                                         Text="(Load file content to preview)"
                                         VerticalContentAlignment="Top"/>
                            </StackPanel>
                        </Border>

                        <!-- Save Button -->
                        <Border Grid.Row="6" Padding="0,4,0,16">
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="BtnSaveMetadata" Style="{StaticResource AccentButton}"
                                        Content="[Save] Save Comment &amp; Tags to File"
                                        Padding="16,10" FontSize="13" Margin="0,0,10,0"/>
                                <TextBlock x:Name="TxtSaveStatus" VerticalAlignment="Center"
                                           Foreground="#50FA7B" FontSize="12" Text=""/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </ScrollViewer>
            </Grid>
        </Grid>

        <!-- STATUS BAR -->
        <Border Grid.Row="2" Background="#252537" BorderBrush="#44446A" BorderThickness="0,1,0,0">
            <Grid Margin="16,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock x:Name="TxtStatus"    Grid.Column="0"
                           Text="Ready. Configure settings and open your Git repository."
                           Foreground="#6272A4" VerticalAlignment="Center" FontSize="11"/>
                <TextBlock x:Name="TxtCacheInfo" Grid.Column="1"
                           Foreground="#44446A" VerticalAlignment="Center" FontSize="11"/>
            </Grid>
        </Border>

        <!-- Loading Overlay -->
        <Border x:Name="LoadingOverlay" Grid.RowSpan="3"
                Background="#CC1E1E2E" Visibility="Collapsed">
            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                <TextBlock x:Name="TxtLoadingMsg" Text="Working..."
                           FontSize="18" Foreground="#F8F8F2" HorizontalAlignment="Center"/>
                <TextBlock x:Name="TxtLoadingSubMsg" Text=""
                           FontSize="12" Foreground="#A0A0C0" HorizontalAlignment="Center"
                           Margin="0,8,0,0" TextWrapping="Wrap" MaxWidth="400" TextAlignment="Center"/>
                <Border Width="200" Height="4" Background="#3A3A55" CornerRadius="2" Margin="0,20,0,0">
                    <Border x:Name="ProgressBar" Width="0" Height="4" Background="#7B9CFF"
                            CornerRadius="2" HorizontalAlignment="Left">
                        <Border.Triggers>
                            <EventTrigger RoutedEvent="Border.Loaded">
                                <BeginStoryboard>
                                    <Storyboard RepeatBehavior="Forever">
                                        <DoubleAnimation Storyboard.TargetProperty="Width"
                                                         From="0" To="200" Duration="0:0:1.5"
                                                         AutoReverse="True"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                        </Border.Triggers>
                    </Border>
                </Border>
            </StackPanel>
        </Border>
    </Grid>
</Window>
'@

    # ==========================================================================
    # WINDOW SETUP
    # ==========================================================================
    $Window = [Windows.Markup.XamlReader]::Parse($XAMLString)

    function Get-Control { param($Name) $Window.FindName($Name) }

    $BtnRefresh          = Get-Control "BtnRefresh"
    $BtnSync             = Get-Control "BtnSync"
    $BtnSettings         = Get-Control "BtnSettings"
    $TxtConnectionStatus = Get-Control "TxtConnectionStatus"
    $TxtVersionBadge     = Get-Control "TxtVersionBadge"
    $TxtSearch           = Get-Control "TxtSearch"
    $BtnClearSearch      = Get-Control "BtnClearSearch"
    $BtnViewAlpha        = Get-Control "BtnViewAlpha"
    $BtnViewFolder       = Get-Control "BtnViewFolder"
    $BtnViewTag          = Get-Control "BtnViewTag"
    $FileListBox         = Get-Control "FileListBox"
    $FileTreeView        = Get-Control "FileTreeView"
    $TxtFileCount        = Get-Control "TxtFileCount"
    $PanelEmpty          = Get-Control "PanelEmpty"
    $PanelDetail         = Get-Control "PanelDetail"
    $TxtEmptyHint        = Get-Control "TxtEmptyHint"
    $TxtDetailName       = Get-Control "TxtDetailName"
    $TxtDetailPath       = Get-Control "TxtDetailPath"
    $TxtFileIcon         = Get-Control "TxtFileIcon"
    $TxtMetaCreated      = Get-Control "TxtMetaCreated"
    $TxtMetaModified     = Get-Control "TxtMetaModified"
    $TxtMetaLibrary      = Get-Control "TxtMetaLibrary"
    $TxtMetaSize         = Get-Control "TxtMetaSize"
    $TxtMetaType         = Get-Control "TxtMetaType"
    $TxtMetaFolder       = Get-Control "TxtMetaFolder"
    $TxtMetaSpUrl        = Get-Control "TxtMetaSpUrl"
    $BtnOpenVSCode       = Get-Control "BtnOpenVSCode"
    $BtnLoadContent      = Get-Control "BtnLoadContent"
    $BtnCopyPath         = Get-Control "BtnCopyPath"
    $BtnCopyUrl          = Get-Control "BtnCopyUrl"
    $TxtComment          = Get-Control "TxtComment"
    $TxtTags             = Get-Control "TxtTags"
    $BtnTagAutomation    = Get-Control "BtnTagAutomation"
    $BtnTagMaintenance   = Get-Control "BtnTagMaintenance"
    $BtnTagDeploy        = Get-Control "BtnTagDeploy"
    $BtnTagMonitor       = Get-Control "BtnTagMonitor"
    $BtnTagSecurity      = Get-Control "BtnTagSecurity"
    $BtnTagUtil          = Get-Control "BtnTagUtil"
    $TxtFileContent      = Get-Control "TxtFileContent"
    $TxtPreviewNote      = Get-Control "TxtPreviewNote"
    $BtnSaveMetadata     = Get-Control "BtnSaveMetadata"
    $TxtSaveStatus       = Get-Control "TxtSaveStatus"
    $BtnRename           = Get-Control "BtnRename"
    $TxtStatus           = Get-Control "TxtStatus"
    $TxtCacheInfo        = Get-Control "TxtCacheInfo"
    $LoadingOverlay      = Get-Control "LoadingOverlay"
    $TxtLoadingMsg       = Get-Control "TxtLoadingMsg"
    $TxtLoadingSubMsg    = Get-Control "TxtLoadingSubMsg"

    $TxtVersionBadge.Text = " v$script:AppVersion"

    # ==========================================================================
    # APPLICATION STATE
    # ==========================================================================
    $script:AllFiles      = [System.Collections.Generic.List[PSObject]]::new()
    $script:FilteredFiles = [System.Collections.Generic.List[PSObject]]::new()
    $script:SelectedFile  = $null
    $script:CurrentView   = "alpha"
    $script:FileContent   = $null

    # ==========================================================================
    # UI HELPERS
    # ==========================================================================
    function Set-Status {
        param([string]$Message, [string]$Color = "#6272A4")
        $TxtStatus.Dispatcher.Invoke({
            $TxtStatus.Text       = $Message
            $TxtStatus.Foreground = $Color
        })
    }

    function Show-Loading {
        param([string]$Message = "Working...", [string]$SubMessage = "")
        $Window.Dispatcher.Invoke({
            $TxtLoadingMsg.Text    = $Message
            $TxtLoadingSubMsg.Text = $SubMessage
            $LoadingOverlay.Visibility = "Visible"
        })
    }

    function Hide-Loading {
        $Window.Dispatcher.Invoke({ $LoadingOverlay.Visibility = "Collapsed" })
    }

    function Format-FileSize {
        param([long]$Bytes)
        if ($Bytes -lt 1024)  { return "$Bytes B" }
        if ($Bytes -lt 1MB)   { return "{0:N1} KB" -f ($Bytes / 1KB) }
        return "{0:N1} MB" -f ($Bytes / 1MB)
    }

    function Get-SharePointFileUrl {
        param([PSCustomObject]$File)
        $c = $script:Config
        if ([string]::IsNullOrWhiteSpace($c.SharePointSiteUrl) -or
            [string]::IsNullOrWhiteSpace($c.SharePointFolderPath)) {
            return $null
        }
        # SharePointFolderPath = full path within site, no leading slash
        # e.g. Documents/Engineering Procedures/!GitScriptsRepo
        # Append the file's repo-relative path to build the full SharePoint URL.
        $repoPath   = $c.GitRepoPath.TrimEnd("\/")
        $relPath    = $File.FileRef.Substring($repoPath.Length).TrimStart("\/").Replace("\","/")
        $baseUrl    = $c.SharePointSiteUrl.TrimEnd("/")
        $folderPart = [Uri]::EscapeUriString($c.SharePointFolderPath.Trim("/"))
        return "$baseUrl/$folderPart/$relPath"
    }

    function Update-ViewToggleStyle {
        param([string]$Active)
        $map = @{ alpha = $BtnViewAlpha; folder = $BtnViewFolder; tag = $BtnViewTag }
        foreach ($key in $map.Keys) {
            $btn = $map[$key]
            if ($key -eq $Active) {
                $btn.Background = "#4B4B70"
                $btn.Foreground = "#F8F8F2"
            } else {
                $btn.Background = "Transparent"
                $btn.Foreground = "#A0A0C0"
            }
        }
    }

    # ==========================================================================
    # FILE LIST POPULATION
    # ==========================================================================
    function New-FileViewModel {
        param([PSCustomObject]$File)
        if ([string]::IsNullOrEmpty($File.Name) -or [string]::IsNullOrEmpty($File.Extension)) {
            return $null
        }
        $ext   = $File.Extension.ToLower()
        $icon  = if ($ext -eq ".ps1") { "PS1" } else { "BAT" }
        $color = if ($ext -eq ".ps1") { "#BD93F9" } else { "#FFB86C" }
        $sub   = "$($File.Library) | $(if($File.Modified){$File.Modified.ToString('MM/dd/yy')}else{'-'})"
        return [PSCustomObject]@{
            FileData = $File
            Name     = $File.Name
            SubInfo  = $sub
            ExtIcon  = $icon
            ExtColor = $color
        }
    }

    function Update-FileList {
        $search = $TxtSearch.Text.Trim().ToLower()

        $filtered = $script:AllFiles | Where-Object {
            if ([string]::IsNullOrEmpty($search)) { return $true }
            return (
                $_.Name.ToLower().Contains($search)    -or
                $_.Library.ToLower().Contains($search) -or
                ($_.Comment -and $_.Comment.ToLower().Contains($search)) -or
                ($_.Tags    -and ($_.Tags -join ",").ToLower().Contains($search))
            )
        }

        $script:FilteredFiles = [System.Collections.Generic.List[PSObject]]($filtered)

        switch ($script:CurrentView) {
            "alpha"  { Invoke-AlphaView  $script:FilteredFiles }
            "folder" { Invoke-FolderView $script:FilteredFiles }
            "tag"    { Invoke-TagView    $script:FilteredFiles }
        }

        $count = $script:FilteredFiles.Count
        $total = $script:AllFiles.Count
        $TxtFileCount.Text = if ($search) { "$count of $total files match" } else { "$total files total" }
    }

    function Invoke-AlphaView {
        param($Files)
        $FileTreeView.Visibility = "Collapsed"
        $FileListBox.Visibility  = "Visible"

        $sorted = $Files | Where-Object {
            -not [string]::IsNullOrEmpty($_.Name) -and -not [string]::IsNullOrEmpty($_.Extension)
        } | Sort-Object Name

        $FileListBox.Items.Clear()
        foreach ($f in $sorted) {
            $vm = New-FileViewModel $f
            if ($null -ne $vm) { $FileListBox.Items.Add($vm) }
        }
    }

    function Invoke-FolderView {
        param($Files)
        $FileListBox.Visibility  = "Collapsed"
        $FileTreeView.Visibility = "Visible"
        $FileTreeView.Items.Clear()

        $grouped = $Files | Group-Object { $_.Library } | Sort-Object Name

        foreach ($group in $grouped) {
            $header            = New-Object System.Windows.Controls.TreeViewItem
            $header.Header     = "[/] $($group.Name)"
            $header.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xA0,0xA0,0xC0)
            $header.IsExpanded = $true

            foreach ($f in ($group.Group | Sort-Object Name)) {
                $item = New-Object System.Windows.Controls.TreeViewItem
                $vm   = New-FileViewModel $f

                $sp             = New-Object System.Windows.Controls.StackPanel
                $sp.Orientation = "Horizontal"

                $extLbl            = New-Object System.Windows.Controls.TextBlock
                $extLbl.Text       = $vm.ExtIcon
                $extLbl.Foreground = [System.Windows.Media.SolidColorBrush](
                    [System.Windows.Media.ColorConverter]::ConvertFromString($vm.ExtColor))
                $extLbl.Margin     = [System.Windows.Thickness]::new(0,0,8,0)
                $extLbl.FontSize   = 10

                $nameLbl           = New-Object System.Windows.Controls.TextBlock
                $nameLbl.Text      = $f.Name
                $nameLbl.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xF8,0xF8,0xF2)

                $sp.Children.Add($extLbl)
                $sp.Children.Add($nameLbl)

                $item.Header = $sp
                $item.Tag    = $f
                $item.Add_Selected({ param($s,$e) Select-File $s.Tag })
                $header.Items.Add($item)
            }
            $FileTreeView.Items.Add($header)
        }
    }

    function Invoke-TagView {
        param($Files)
        $FileListBox.Visibility  = "Collapsed"
        $FileTreeView.Visibility = "Visible"
        $FileTreeView.Items.Clear()

        $tagged   = $Files | Where-Object { $_.Tags -and $_.Tags.Count -gt 0 }
        $untagged = $Files | Where-Object { -not $_.Tags -or $_.Tags.Count -eq 0 }

        $tagMap = @{}
        foreach ($f in $tagged) {
            foreach ($tag in $f.Tags) {
                if (-not $tagMap.ContainsKey($tag)) {
                    $tagMap[$tag] = [System.Collections.Generic.List[PSObject]]::new()
                }
                $tagMap[$tag].Add($f)
            }
        }

        foreach ($tag in ($tagMap.Keys | Sort-Object)) {
            $header            = New-Object System.Windows.Controls.TreeViewItem
            $header.Header     = "[#] $tag ($($tagMap[$tag].Count))"
            $header.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xBD,0x93,0xF9)
            $header.IsExpanded = $true

            foreach ($f in ($tagMap[$tag] | Sort-Object Name)) {
                $item    = New-Object System.Windows.Controls.TreeViewItem
                $vm      = New-FileViewModel $f
                $nameLbl = New-Object System.Windows.Controls.TextBlock
                $nameLbl.Text      = "  $($vm.ExtIcon)  $($f.Name)"
                $nameLbl.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xF8,0xF8,0xF2)
                $item.Header = $nameLbl
                $item.Tag    = $f
                $item.Add_Selected({ param($s,$e) Select-File $s.Tag })
                $header.Items.Add($item)
            }
            $FileTreeView.Items.Add($header)
        }

        if ($untagged.Count -gt 0) {
            $header            = New-Object System.Windows.Controls.TreeViewItem
            $header.Header     = "[ ] Untagged ($($untagged.Count))"
            $header.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0x62,0x72,0xA4)
            $header.IsExpanded = $false
            foreach ($f in ($untagged | Sort-Object Name)) {
                $item    = New-Object System.Windows.Controls.TreeViewItem
                $vm      = New-FileViewModel $f
                $nameLbl = New-Object System.Windows.Controls.TextBlock
                $nameLbl.Text      = "  $($vm.ExtIcon)  $($f.Name)"
                $nameLbl.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xA0,0xA0,0xC0)
                $item.Header = $nameLbl
                $item.Tag    = $f
                $item.Add_Selected({ param($s,$e) Select-File $s.Tag })
                $header.Items.Add($item)
            }
            $FileTreeView.Items.Add($header)
        }
    }

    # ==========================================================================
    # FILE SELECTION
    # ==========================================================================
    function Select-File {
        param([PSCustomObject]$File)
        $script:SelectedFile = $File
        $script:FileContent  = $null

        $PanelEmpty.Visibility  = "Collapsed"
        $PanelDetail.Visibility = "Visible"

        $ext = $File.Extension.ToLower()
        if ($ext -eq ".ps1") {
            $TxtFileIcon.Text       = "PS1"
            $TxtFileIcon.Foreground = "#BD93F9"
        } else {
            $TxtFileIcon.Text       = "BAT"
            $TxtFileIcon.Foreground = "#FFB86C"
        }

        $TxtDetailName.Text  = $File.Name
        $TxtDetailPath.Text  = $File.FileRef
        $TxtMetaCreated.Text = if ($File.Created)  { $File.Created.ToString("MMM dd, yyyy h:mmtt")  } else { "-" }
        $TxtMetaModified.Text= if ($File.Modified) { $File.Modified.ToString("MMM dd, yyyy h:mmtt") } else { "-" }
        $TxtMetaLibrary.Text = if ($File.Library)  { $File.Library }  else { "-" }
        $TxtMetaSize.Text    = if ($File.SizeBytes) { Format-FileSize([long]$File.SizeBytes) } else { "-" }
        $TxtMetaType.Text    = $ext.ToUpper().TrimStart(".")
        $TxtMetaFolder.Text  = if ($File.FolderPath) { $File.FolderPath } else { "-" }

        # SharePoint URL preview (if configured)
        $spUrl = Get-SharePointFileUrl -File $File
        $TxtMetaSpUrl.Text = if ($spUrl) { $spUrl } else { "(SharePoint sync not configured)" }

        $TxtComment.Text      = $File.Comment
        $TxtTags.Text         = ($File.Tags -join ", ")
        $TxtFileContent.Text  = "(Click 'Load Content' to preview and enable metadata editing)"
        $TxtPreviewNote.Text  = " — click 'Load Content' above"
        $TxtSaveStatus.Text   = ""

        Set-Status "Selected: $($File.Name)"
        Write-AppLog "File selected: $($File.FileRef)"
    }

    # ==========================================================================
    # LOAD FILE CONTENT
    # ==========================================================================
    function Invoke-LoadFileContent {
        if ($null -eq $script:SelectedFile) { return }
        Set-Status "Loading file content..." "#FFB86C"
        $file = $script:SelectedFile

        try {
            if (-not (Test-Path $file.FileRef)) {
                throw "Local file not found: $($file.FileRef)"
            }
            $content = Get-Content -Path $file.FileRef -Raw -Encoding UTF8

            if ($null -ne $content) {
                $script:FileContent = $content
                $meta = Read-AppMetadata $content

                $script:SelectedFile.Comment       = $meta.Comment
                $script:SelectedFile.Tags          = $meta.Tags
                $script:SelectedFile.TagsRaw       = ($meta.Tags -join ",")
                $script:SelectedFile.ContentLoaded = $true

                $TxtComment.Text     = $meta.Comment
                $TxtTags.Text        = ($meta.Tags -join ", ")
                $TxtFileContent.Text = $content
                $TxtPreviewNote.Text = " — $([Math]::Round($content.Length/1KB,1)) KB, $($content.Split("`n").Count) lines"
                Set-Status "File loaded: $($file.Name)" "#50FA7B"
                Write-AppLog "Content loaded: $($file.FileRef)"
            }
        } catch {
            Set-Status "Error loading content: $_" "#FF5555"
            Write-AppLog "Load content error: $_" "ERROR"
        }
    }

    # ==========================================================================
    # SAVE METADATA
    # ==========================================================================
    function Save-FileMetadata {
        if ($null -eq $script:SelectedFile) { return }

        if ($null -eq $script:FileContent) {
            $r = [System.Windows.MessageBox]::Show(
                "File content hasn't been loaded yet.`nLoad the file first so existing content is preserved.",
                "Load Required",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Question
            )
            if ($r -eq [System.Windows.MessageBoxResult]::Yes) { Invoke-LoadFileContent }
            if ($null -eq $script:FileContent) { return }
        }

        $comment = $TxtComment.Text.Trim()
        $tags    = $TxtTags.Text -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

        $newContent = Write-AppMetadata -Content $script:FileContent -Comment $comment -Tags $tags

        try {
            [System.IO.File]::WriteAllText($script:SelectedFile.FileRef, $newContent, [System.Text.Encoding]::UTF8)

            $script:FileContent              = $newContent
            $script:SelectedFile.Comment     = $comment
            $script:SelectedFile.Tags        = $tags
            $script:SelectedFile.TagsRaw     = ($tags -join ",")
            $TxtFileContent.Text             = $newContent
            $TxtSaveStatus.Text              = "[OK] Saved $(Get-Date -Format 'h:mmtt')"
            $TxtSaveStatus.Foreground        = "#50FA7B"
            Set-Status "Saved metadata to: $($script:SelectedFile.Name)" "#50FA7B"
            Write-AppLog "Metadata saved: $($script:SelectedFile.FileRef)"
            Save-GitCache $script:AllFiles
        } catch {
            $TxtSaveStatus.Text      = "[X] Save failed"
            $TxtSaveStatus.Foreground = "#FF5555"
            Set-Status "Save failed: $_" "#FF5555"
            Write-AppLog "Save metadata error: $_" "ERROR"
        }
    }

    # ==========================================================================
    # RENAME
    # ==========================================================================
    function Invoke-RenameFile {
        if ($null -eq $script:SelectedFile) { return }

        $dlg                       = [System.Windows.Window]::new()
        $dlg.Title                 = "Rename File"
        $dlg.Width                 = 420
        $dlg.Height                = 175
        $dlg.WindowStartupLocation = "CenterOwner"
        $dlg.Owner                 = $Window
        $dlg.Background            = "#252537"
        $dlg.ResizeMode            = "NoResize"

        $sp         = [System.Windows.Controls.StackPanel]::new()
        $sp.Margin  = [System.Windows.Thickness]::new(20)
        $dlg.Content = $sp

        $lbl            = [System.Windows.Controls.TextBlock]::new()
        $lbl.Text       = "Enter new filename (include extension):"
        $lbl.Foreground = "#A0A0C0"
        $lbl.FontSize   = 12
        $lbl.Margin     = [System.Windows.Thickness]::new(0,0,0,8)
        $sp.Children.Add($lbl)

        $tb             = [System.Windows.Controls.TextBox]::new()
        $tb.Text        = $script:SelectedFile.Name
        $tb.Background  = "#1E1E2E"
        $tb.Foreground  = "#F8F8F2"
        $tb.FontSize    = 13
        $tb.Padding     = [System.Windows.Thickness]::new(8,6,8,6)
        $tb.BorderBrush = "#7B9CFF"
        $tb.Margin      = [System.Windows.Thickness]::new(0,0,0,16)
        $sp.Children.Add($tb)
        $tb.SelectAll()

        $btnRow                     = [System.Windows.Controls.StackPanel]::new()
        $btnRow.Orientation         = "Horizontal"
        $btnRow.HorizontalAlignment = "Right"
        $sp.Children.Add($btnRow)

        $btnOk            = [System.Windows.Controls.Button]::new()
        $btnOk.Content    = "Rename"
        $btnOk.Width      = 80
        $btnOk.Height     = 32
        $btnOk.Margin     = [System.Windows.Thickness]::new(0,0,8,0)
        $btnOk.Background = "#7B9CFF"
        $btnOk.Foreground = "#1E1E2E"
        $btnOk.FontWeight = "SemiBold"

        $btnCancel            = [System.Windows.Controls.Button]::new()
        $btnCancel.Content    = "Cancel"
        $btnCancel.Width      = 80
        $btnCancel.Height     = 32
        $btnCancel.Background = "#3A3A55"
        $btnCancel.Foreground = "#F8F8F2"

        $btnRow.Children.Add($btnOk)
        $btnRow.Children.Add($btnCancel)

        $btnOk.Add_Click({
            $dlg.DialogResult = $true
            $dlg.Close()
        })
        $btnCancel.Add_Click({ $dlg.Close() })
        $tb.Add_KeyDown({
            param($s, $e)
            if ($e.Key -eq "Return") { $dlg.DialogResult = $true; $dlg.Close() }
        })

        $dlgResult = $dlg.ShowDialog()
        $newName   = $tb.Text.Trim()

        if ($dlgResult -and -not [string]::IsNullOrWhiteSpace($newName) -and $newName -ne $script:SelectedFile.Name) {
            try {
                $oldName = $script:SelectedFile.Name
                $oldPath = $script:SelectedFile.FileRef
                $newPath = Join-Path (Split-Path $oldPath -Parent) $newName
                Rename-Item -Path $oldPath -NewName $newName -ErrorAction Stop

                $script:SelectedFile.Name      = $newName
                $script:SelectedFile.FileRef   = $newPath
                $script:SelectedFile.Extension = [System.IO.Path]::GetExtension($newName).ToLower()

                $TxtDetailName.Text = $newName
                $TxtDetailPath.Text = $newPath

                Update-FileList
                Save-GitCache $script:AllFiles
                Set-Status "Renamed: $oldName → $newName" "#50FA7B"
                Write-AppLog "Renamed '$oldName' -> '$newName'"
            } catch {
                [System.Windows.MessageBox]::Show(
                    "Rename failed: $_", "Error",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
                Write-AppLog "Rename error: $_" "ERROR"
            }
        }
    }

    # ==========================================================================
    # OPEN IN VSCODE
    # ==========================================================================
    function Open-InVSCode {
        if ($null -eq $script:SelectedFile) { return }

        $codeExe = Get-Command "code" -ErrorAction SilentlyContinue
        if ($null -eq $codeExe) {
            $paths = @(
                "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
                "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
                "C:\Program Files\Microsoft VS Code\bin\code.cmd"
            )
            $codeExe = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
        }

        if ($null -eq $codeExe) {
            [System.Windows.MessageBox]::Show(
                "VSCode ('code' command) not found.`n`nEnsure VSCode is installed and 'code' is in your PATH.",
                "VSCode Not Found",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        try {
            if ($codeExe -is [System.Management.Automation.CommandInfo]) {
                & $codeExe.Source $script:SelectedFile.FileRef
            } else {
                & $codeExe $script:SelectedFile.FileRef
            }
            Set-Status "Opened in VSCode: $($script:SelectedFile.Name)" "#50FA7B"
            Write-AppLog "Opened in VSCode: $($script:SelectedFile.FileRef)"
        } catch {
            Set-Status "Failed to open in VSCode: $_" "#FF5555"
            Write-AppLog "VSCode open error: $_" "ERROR"
        }
    }

    # ==========================================================================
    # QUICK TAG
    # ==========================================================================
    function Add-QuickTag {
        param([string]$Tag)
        $existing = $TxtTags.Text.Trim()
        $tags = if ($existing) {
            $existing -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        } else { @() }
        if ($tags -notcontains $Tag) {
            $tags      = @($tags) + $Tag
            $TxtTags.Text = ($tags -join ", ")
        }
    }

    # ==========================================================================
    # GIT REPO SCAN
    # ==========================================================================
    function Start-GitScan {
        $repoPath = $script:Config.GitRepoPath

        if ([string]::IsNullOrWhiteSpace($repoPath)) {
            $r = [System.Windows.MessageBox]::Show(
                "Git repository path is not configured.`nWould you like to open Settings now?",
                "Not Configured",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning
            )
            if ($r -eq [System.Windows.MessageBoxResult]::Yes) {
                if (Show-SettingsDialog) { Start-GitScan }
            }
            return
        }

        if (-not (Test-Path $repoPath -PathType Container)) {
            [System.Windows.MessageBox]::Show(
                "Git repository path not found or not a folder:`n$repoPath`n`nCheck Settings.",
                "Folder Not Found",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Error
            )
            return
        }

        Show-Loading "Scanning Git repository..." "This may take a moment for large repositories"
        Write-AppLog "Scanning local repo: $repoPath"

        try {
            $found = Get-ChildItem -Path $repoPath -Recurse -Include $script:FileTypes -File -ErrorAction Stop

            $allFiles = [System.Collections.Generic.List[PSObject]]::new()
            foreach ($f in $found) {
                $relFolder = $f.DirectoryName.Replace($repoPath,"").TrimStart("\/")
                $allFiles.Add([PSCustomObject]@{
                    Name           = $f.Name
                    FileRef        = $f.FullName
                    Library        = if ($relFolder) { $relFolder.Split([IO.Path]::DirectorySeparatorChar)[0] } else { "(root)" }
                    FolderPath     = $f.DirectoryName
                    Created        = $f.CreationTime
                    Modified       = $f.LastWriteTime
                    Author         = ""
                    LastModifiedBy = ""
                    SizeBytes      = $f.Length
                    Extension      = $f.Extension.ToLower()
                    Comment        = ""
                    Tags           = @()
                    TagsRaw        = ""
                    ContentLoaded  = $false
                })
            }

            Write-AppLog "Repo scan complete: $($allFiles.Count) script files found"

            $script:AllFiles = $allFiles

            # Merge existing cache (preserves comments/tags between scans)
            $cache = Load-GitCache
            if ($null -ne $cache) {
                $cacheMap = @{}
                foreach ($cf in $cache.Files) {
                    if (-not [string]::IsNullOrEmpty($cf.FileRef)) { $cacheMap[$cf.FileRef] = $cf }
                }
                foreach ($f in $script:AllFiles) {
                    if ($cacheMap.ContainsKey($f.FileRef)) {
                        $cached    = $cacheMap[$f.FileRef]
                        $f.Comment = if ($cached.Comment) { $cached.Comment } else { "" }
                        $f.Tags    = if ($cached.Tags)    { @($cached.Tags) } else { @() }
                        $f.TagsRaw = if ($cached.TagsRaw) { $cached.TagsRaw } else { "" }
                    }
                }
            }

            Save-GitCache $script:AllFiles

            $TxtConnectionStatus.Text       = "[G] Git Repo"
            $TxtConnectionStatus.Foreground = "#50FA7B"
            $BtnRefresh.IsEnabled           = $true
            $TxtCacheInfo.Text              = "Last scan: $(Get-Date -Format 'h:mmtt')"

            Update-FileList
            Set-Status "Repository loaded — $($allFiles.Count) script files found." "#50FA7B"

        } catch {
            Write-AppLog "Git repo scan error: $_" "ERROR"
            Set-Status "Error scanning repository: $_" "#FF5555"
        } finally {
            Hide-Loading
        }
    }

    # ==========================================================================
    # STARTUP — load from cache for fast start, then offer rescan
    # ==========================================================================
    function Start-AppLoad {
        $cache = Load-GitCache
        if ($null -ne $cache -and $cache.Files.Count -gt 0) {
            $script:AllFiles = $cache.Files

            $TxtConnectionStatus.Text       = "[G] Git Repo (cached)"
            $TxtConnectionStatus.Foreground = "#FFB86C"
            $BtnRefresh.IsEnabled           = $true

            $age    = [datetime]::Now - $cache.Timestamp
            $ageStr = if ($age.TotalMinutes -lt 60)  { "$([int]$age.TotalMinutes)m ago" }
                      elseif ($age.TotalHours -lt 24) { "$([int]$age.TotalHours)h ago"   }
                      else                            { "$([int]$age.TotalDays)d ago"     }

            $TxtCacheInfo.Text = "Cached: $ageStr"

            Update-FileList
            Set-Status "Loaded $($cache.Files.Count) files from cache ($ageStr). Click Refresh to rescan." "#FFB86C"
            Write-AppLog "Startup: loaded git cache ($($cache.Files.Count) files, $ageStr)"
        } else {
            # No cache — prompt to scan if repo is configured
            if (-not [string]::IsNullOrWhiteSpace($script:Config.GitRepoPath)) {
                Start-GitScan
            } else {
                Set-Status "No repository configured. Click Settings to get started." "#6272A4"
            }
        }
    }

    # ==========================================================================
    # EVENT HANDLERS
    # ==========================================================================
    $BtnRefresh.Add_Click({ Start-GitScan })
    $BtnSync.Add_Click({ Start-SharePointSync })
    $BtnSettings.Add_Click({
        if (Show-SettingsDialog -IsFirstRun $false) {
            # Rescan if repo path was changed
            Start-GitScan
        }
    })

    $TxtSearch.Add_TextChanged({ Update-FileList })
    $BtnClearSearch.Add_Click({ $TxtSearch.Text = "" })

    $BtnViewAlpha.Add_Click({
        $script:CurrentView = "alpha"
        Update-ViewToggleStyle "alpha"
        Update-FileList
    })
    $BtnViewFolder.Add_Click({
        $script:CurrentView = "folder"
        Update-ViewToggleStyle "folder"
        Update-FileList
    })
    $BtnViewTag.Add_Click({
        $script:CurrentView = "tag"
        Update-ViewToggleStyle "tag"
        Update-FileList
    })

    $FileListBox.Add_SelectionChanged({
        $vm = $FileListBox.SelectedItem
        if ($null -ne $vm -and $vm.PSObject.Properties["FileData"]) {
            Select-File $vm.FileData
        }
    })

    $BtnLoadContent.Add_Click({ Invoke-LoadFileContent })
    $BtnOpenVSCode.Add_Click({ Open-InVSCode })

    $BtnCopyPath.Add_Click({
        if ($null -ne $script:SelectedFile) {
            [System.Windows.Clipboard]::SetText($script:SelectedFile.FileRef)
            Set-Status "Local path copied to clipboard" "#50FA7B"
        }
    })

    $BtnCopyUrl.Add_Click({
        if ($null -ne $script:SelectedFile) {
            $spUrl = Get-SharePointFileUrl -File $script:SelectedFile
            if ($spUrl) {
                [System.Windows.Clipboard]::SetText($spUrl)
                Set-Status "SharePoint URL copied to clipboard" "#50FA7B"
            } else {
                [System.Windows.MessageBox]::Show(
                    "SharePoint sync is not configured.`n`nOpen Settings and fill in the SharePoint fields to enable URL copying.",
                    "Not Configured",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
        }
    })

    $BtnRename.Add_Click({ Invoke-RenameFile })
    $BtnSaveMetadata.Add_Click({ Save-FileMetadata })

    $BtnTagAutomation.Add_Click({  Add-QuickTag "automation"  })
    $BtnTagMaintenance.Add_Click({ Add-QuickTag "maintenance" })
    $BtnTagDeploy.Add_Click({      Add-QuickTag "deployment"  })
    $BtnTagMonitor.Add_Click({     Add-QuickTag "monitoring"  })
    $BtnTagSecurity.Add_Click({    Add-QuickTag "security"    })
    $BtnTagUtil.Add_Click({        Add-QuickTag "utility"     })

    $TxtComment.Add_TextChanged({ $TxtSaveStatus.Text = "" })
    $TxtTags.Add_TextChanged({    $TxtSaveStatus.Text = "" })

    $Window.Add_Closing({
        Write-AppLog "Application closed"
    })

    # ==========================================================================
    # LAUNCH SEQUENCE
    # ==========================================================================
    Write-AppLog "=== $script:AppName v$script:AppVersion starting ==="

    # Load config
    $script:Config = Load-AppConfig

    # First-run check — if no git repo path is configured, show setup dialog
    # First-run check — if no git repo path is configured, show setup dialog.
    # IMPORTANT: Do NOT call $Window.Show() before ShowDialog() — doing so puts
    # the window in a visible state and causes ShowDialog() to throw
    # "ShowDialog can be called only on hidden windows."
    # The settings dialog uses CenterScreen so it does not need a window owner.
    if ([string]::IsNullOrWhiteSpace($script:Config.GitRepoPath)) {
        Write-AppLog "No config found — showing first-run setup dialog"
        $configured = Show-SettingsDialog -IsFirstRun $true
        if (-not $configured) {
            # User closed/cancelled first-run wizard — exit cleanly, no config written
            Write-AppLog "First-run setup cancelled by user — exiting without saving config"
            return
        }
        # Reload config now that first-run save has written it
        $script:Config = Load-AppConfig
    }

    # Load from cache or trigger initial scan
    Start-AppLoad

    # Show the main window — ShowDialog() blocks until the window is closed
    $Window.ShowDialog() | Out-Null

} # End function Start-ScriptManagementBrowser

# ==============================================================================
# ENTRY POINT
# ==============================================================================
Start-ScriptManagementBrowser
