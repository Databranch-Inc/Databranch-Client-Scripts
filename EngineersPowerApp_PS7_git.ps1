#Requires -Version 7.0
##ENGINEERSPOWERAPP#COMMENT#Engineers PowerApp is a WPF desktop tool for browsing, tagging, commenting on, and launching the PowerShell and batch scripts stored in your Git repository (or SharePoint). It gives every engineer on the team a consistent, searchable interface into the shared script library without needing to navigate Windows Explorer or remember folder structures.
##ENGINEERSPOWERAPP#TAGS#isApp,PowerShell 7,utility
<#
.SYNOPSIS
    Engineers PowerApp - PowerShell and Batch Script Browser & Manager (PowerShell 7)
.DESCRIPTION
    A WPF GUI application that connects to a SharePoint site, indexes all .ps1 and .bat
    files, and provides browsing, viewing, tagging, commenting, renaming, and VSCode
    integration. Comments and tags are stored directly in the script files using a
    structured comment syntax.
.NOTES
    Requires: PnP.PowerShell module (latest version)
    Install:  Install-Module PnP.PowerShell -Scope CurrentUser
    Auth:     Uses custom Entra ID app registration (interactive login)

    Comment syntax used in managed files:
#>

# ============================================================
# STATIC APP INTERNALS  (never user-configurable)
# ============================================================
$script:AppDataDir   = "$env:APPDATA\EngineersPowerApp"
$script:ConfigFile   = "$env:APPDATA\EngineersPowerApp\config.json"

$script:Config = @{
    CacheFile     = "$env:APPDATA\EngineersPowerApp\cache.json"
    GitCacheFile  = "$env:APPDATA\EngineersPowerApp\git-cache.json"
    LogFile       = "$env:APPDATA\EngineersPowerApp\app.log"
    AppDataDir    = "$env:APPDATA\EngineersPowerApp"
    AppVersion    = "2.0.0-PS7"
    # These three are overwritten by Load-AppConfig from config.json:
    SiteUrl       = ""
    CommentPrefix = "##ENGINEERSPOWERAPP#COMMENT#"
    TagPrefix     = "##ENGINEERSPOWERAPP#TAGS#"
    FileTypes     = @("*.ps1", "*.bat")
}
$script:AppConfig = @{ ClientId = ""; TenantDomain = "" }
$script:GitRepoPath = ""

# ============================================================
# BOOTSTRAP -- Ensure app data directory exists
# ============================================================
if (-not (Test-Path $script:AppDataDir)) {
    New-Item -ItemType Directory -Path $script:AppDataDir -Force | Out-Null
}

# ============================================================
# CONFIG FILE -- Load-AppConfig / Show-FirstRunWizard
# ============================================================
function Load-AppConfig {
    if (-not (Test-Path $script:ConfigFile)) { return $false }
    try {
        $json = Get-Content -Path $script:ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json

        $script:AppConfig.ClientId     = $json.ClientId
        $script:AppConfig.TenantDomain = $json.TenantDomain
        $script:GitRepoPath            = $json.GitRepoPath

        $script:Config.SiteUrl         = $json.SiteUrl
        $script:Config.CommentPrefix   = if ($json.CommentPrefix) { $json.CommentPrefix } else { "##ENGINEERSPOWERAPP#COMMENT#" }
        $script:Config.TagPrefix       = if ($json.TagPrefix)     { $json.TagPrefix     } else { "##ENGINEERSPOWERAPP#TAGS#"    }
        $script:Config.FileTypes       = if ($json.FileTypes)     { @($json.FileTypes)  } else { @("*.ps1", "*.bat")            }

        return $true
    } catch {
        [System.Windows.MessageBox]::Show(
            "Failed to read config.json:`n$_`n`nPath: $($script:ConfigFile)",
            "Config Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error
        )
        return $false
    }
}

function Save-AppConfig {
    param(
        [string]$ClientId, [string]$TenantDomain, [string]$GitRepoPath,
        [string]$SiteUrl,  [string]$CommentPrefix, [string]$TagPrefix,
        [string[]]$FileTypes
    )
    $obj = [ordered]@{
        "_comment"      = "Engineers PowerApp configuration — edit this file or delete it to re-run the setup wizard."
        "ClientId"      = $ClientId
        "TenantDomain"  = $TenantDomain
        "GitRepoPath"   = $GitRepoPath
        "SiteUrl"       = $SiteUrl
        "CommentPrefix" = $CommentPrefix
        "TagPrefix"     = $TagPrefix
        "FileTypes"     = $FileTypes
    }
    $obj | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigFile -Encoding UTF8
}

function Show-FirstRunWizard {
    # ── Build the dialog window ───────────────────────────────────────────
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $wizXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Engineers PowerApp — First Run Setup"
        Width="560" Height="580" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen"
        Background="#1E1E2E" Foreground="#F8F8F2" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <Style x:Key="Lbl" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#A0A0C0"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Margin" Value="0,10,0,3"/>
    </Style>
    <Style x:Key="Hint" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#44446A"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Margin" Value="0,2,0,0"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="TB" TargetType="TextBox">
      <Setter Property="Background" Value="#252537"/>
      <Setter Property="Foreground" Value="#F8F8F2"/>
      <Setter Property="BorderBrush" Value="#44446A"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="FontSize" Value="12"/>
    </Style>
  </Window.Resources>
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <StackPanel Grid.Row="0" Margin="0,0,0,16">
      <TextBlock Text="Welcome to Engineers PowerApp" FontSize="18" FontWeight="Bold"
                 Foreground="#7B9CFF"/>
      <TextBlock Margin="0,4,0,0" Foreground="#6272A4" TextWrapping="Wrap"
                 Text="No config.json was found. Fill in your settings below — this file will be saved to your AppData folder. Delete it at any time to re-run this wizard."/>
    </StackPanel>

    <!-- Fields -->
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel>

        <TextBlock Style="{StaticResource Lbl}" Text="Git Repository Path  *"/>
        <TextBox x:Name="TbGitRepo" Style="{StaticResource TB}"
                 Text="C:\GitHubRepos\YourRepoName"/>
        <TextBlock Style="{StaticResource Hint}"
                   Text="Full path to your local Git repository root. Used by Open Git Repo. Required for Git mode."/>

        <TextBlock Style="{StaticResource Lbl}" Text="SharePoint Site URL"/>
        <TextBox x:Name="TbSiteUrl" Style="{StaticResource TB}"
                 Text="https://YOURTENANT.sharepoint.com/sites/YOURSITE"/>
        <TextBlock Style="{StaticResource Hint}"
                   Text="Your SharePoint site URL. Only needed if you use SharePoint mode — leave as-is if using Git only."/>

        <TextBlock Style="{StaticResource Lbl}" Text="Entra ID Client ID"/>
        <TextBox x:Name="TbClientId" Style="{StaticResource TB}"
                 Text="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"/>
        <TextBlock Style="{StaticResource Hint}"
                   Text="App registration Client ID for PnP.PowerShell interactive login. Run: Register-PnPEntraIDAppForInteractiveLogin -ApplicationName 'PnP.PowerShell' -Tenant 'yourtenant.onmicrosoft.com' -Interactive"/>

        <TextBlock Style="{StaticResource Lbl}" Text="Tenant Domain"/>
        <TextBox x:Name="TbTenant" Style="{StaticResource TB}"
                 Text="yourtenant.onmicrosoft.com"/>
        <TextBlock Style="{StaticResource Hint}"
                   Text="Your Microsoft 365 tenant domain (e.g. contoso.onmicrosoft.com). Used with Entra ID auth."/>

        <TextBlock Style="{StaticResource Lbl}" Text="File Types  (comma-separated globs)"/>
        <TextBox x:Name="TbFileTypes" Style="{StaticResource TB}"
                 Text="*.ps1, *.bat"/>
        <TextBlock Style="{StaticResource Hint}"
                   Text="File extensions to index. Default: *.ps1, *.bat"/>

        <TextBlock Style="{StaticResource Lbl}" Text="Comment Prefix"/>
        <TextBox x:Name="TbCommentPrefix" Style="{StaticResource TB}"
                 Text="##ENGINEERSPOWERAPP#COMMENT#"/>
        <TextBlock Style="{StaticResource Hint}"
                   Text="Prefix used when writing comments into script files. Do not change unless you know what you're doing."/>

        <TextBlock Style="{StaticResource Lbl}" Text="Tag Prefix"/>
        <TextBox x:Name="TbTagPrefix" Style="{StaticResource TB}"
                 Text="##ENGINEERSPOWERAPP#TAGS#"/>
        <TextBlock Style="{StaticResource Hint}"
                   Text="Prefix used when writing tags into script files. Do not change unless you know what you're doing."/>

      </StackPanel>
    </ScrollViewer>

    <!-- Buttons -->
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="BtnWizardSkip" Content="Skip (use defaults)" Width="140" Height="34"
              Background="#3A3A55" Foreground="#A0A0C0" Margin="0,0,10,0"
              BorderBrush="#44446A" BorderThickness="1"/>
      <Button x:Name="BtnWizardSave" Content="Save and Continue" Width="150" Height="34"
              Background="#7B9CFF" Foreground="#1E1E2E" FontWeight="SemiBold"
              BorderThickness="0"/>
    </StackPanel>
  </Grid>
</Window>
'@

    $wiz = [System.Windows.Markup.XamlReader]::Parse($wizXaml)
    $tbGit    = $wiz.FindName("TbGitRepo")
    $tbSite   = $wiz.FindName("TbSiteUrl")
    $tbClient = $wiz.FindName("TbClientId")
    $tbTenant = $wiz.FindName("TbTenant")
    $tbTypes  = $wiz.FindName("TbFileTypes")
    $tbCmtPfx = $wiz.FindName("TbCommentPrefix")
    $tbTagPfx = $wiz.FindName("TbTagPrefix")
    $btnSave  = $wiz.FindName("BtnWizardSave")
    $btnSkip  = $wiz.FindName("BtnWizardSkip")

    $btnSave.Add_Click({
        $ftRaw = $tbTypes.Text -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        Save-AppConfig `
            -ClientId      $tbClient.Text.Trim() `
            -TenantDomain  $tbTenant.Text.Trim() `
            -GitRepoPath   $tbGit.Text.Trim() `
            -SiteUrl       $tbSite.Text.Trim() `
            -CommentPrefix $tbCmtPfx.Text.Trim() `
            -TagPrefix     $tbTagPfx.Text.Trim() `
            -FileTypes     $ftRaw
        $wiz.DialogResult = $true
        $wiz.Close()
    })
    $btnSkip.Add_Click({
        $wiz.DialogResult = $false
        $wiz.Close()
    })

    $result = $wiz.ShowDialog()

    if ($result -eq $true) {
        # Reload from the file we just wrote
        Load-AppConfig | Out-Null
    }
    # If skipped, defaults already set in $script:Config — app continues with blanks
}

# ============================================================
# LOGGING
# ============================================================
function Write-AppLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $script:Config.LogFile -Value $entry -ErrorAction SilentlyContinue
}

# ============================================================
# MODULE CHECK
# ============================================================
function Test-PnPModule {
    if (-not (Get-Module -ListAvailable -Name "PnP.PowerShell")) {
        $result = [System.Windows.MessageBox]::Show(
            "PnP.PowerShell module is required but not installed.`n`nWould you like to install it now? (Requires internet access)",
            "Missing Module",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            try {
                Install-Module PnP.PowerShell -Scope CurrentUser -Force -AllowClobber
                Import-Module PnP.PowerShell
                return $true
            } catch {
                [System.Windows.MessageBox]::Show(
                    "Failed to install PnP.PowerShell: $_`n`nPlease run manually:`nInstall-Module PnP.PowerShell -Scope CurrentUser",
                    "Install Failed", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error
                )
                return $false
            }
        }
        return $false
    }
    Import-Module PnP.PowerShell -ErrorAction SilentlyContinue
    return $true
}

# ============================================================
# SHAREPOINT FUNCTIONS
# ============================================================
function Connect-ToSharePoint {
    param([string]$SiteUrl)
    
    # Validate app config
    if ([string]::IsNullOrWhiteSpace($script:AppConfig.ClientId) -or $script:AppConfig.ClientId -eq "YOUR-CLIENT-ID-HERE") {
        [System.Windows.MessageBox]::Show(
            "Entra ID Client ID is not configured.`n`nEdit config.json in:`n$($script:AppDataDir)`n`nOr delete config.json to re-run the setup wizard.`n`nTo get a Client ID, run:`nRegister-PnPEntraIDAppForInteractiveLogin -ApplicationName 'PnP.PowerShell' -Tenant 'yourtenant.onmicrosoft.com' -Interactive",
            "Configuration Required",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return $false
    }
    
    try {
        Write-AppLog "Connecting to SharePoint: $SiteUrl with ClientId: $($script:AppConfig.ClientId)"
        
        Connect-PnPOnline -Url $SiteUrl `
                          -Interactive `
                          -ClientId $script:AppConfig.ClientId `
                          -ErrorAction Stop
        
        Write-AppLog "SharePoint connection successful"
        return $true
    } catch {
        Write-AppLog "SharePoint connection failed: $_" "ERROR"
        [System.Windows.MessageBox]::Show(
            "Failed to connect to SharePoint:`n`n$_`n`nMake sure:`n1. Your Client ID is correct`n2. The app has been granted admin consent`n3. You have permissions to access the site",
            "Connection Error",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return $false
    }
}

function Get-AllScriptFiles {
    <#
    .SYNOPSIS Retrieves all .ps1 and .bat files from all document libraries on the connected site.
    #>
    $allFiles = [System.Collections.Generic.List[PSObject]]::new()

    try {
        # Get all document libraries (excluding system lists)
        $lists = Get-PnPList | Where-Object {
            $_.BaseTemplate -eq 101 -and  # Document library template
            $_.Hidden -eq $false -and
            $_.Title -notin @("Site Assets", "Site Pages", "Style Library", "Form Templates")
        }

        Write-AppLog "Found $($lists.Count) document libraries to scan"

        foreach ($lib in $lists) {
            Write-AppLog "Scanning library: $($lib.Title)"
            try {
                # Use CAML query to get ps1 and bat files
                $camlQuery = @"
<View Scope="RecursiveAll">
    <Query>
        <Where>
            <Or>
                <Contains>
                    <FieldRef Name='FileLeafRef'/>
                    <Value Type='Text'>.ps1</Value>
                </Contains>
                <Contains>
                    <FieldRef Name='FileLeafRef'/>
                    <Value Type='Text'>.bat</Value>
                </Contains>
            </Or>
        </Where>
    </Query>
    <ViewFields>
        <FieldRef Name='FileLeafRef'/>
        <FieldRef Name='FileRef'/>
        <FieldRef Name='Created'/>
        <FieldRef Name='Modified'/>
        <FieldRef Name='Author'/>
        <FieldRef Name='Editor'/>
        <FieldRef Name='File_x0020_Size'/>
        <FieldRef Name='FileDirRef'/>
    </ViewFields>
</View>
"@
                $items = Get-PnPListItem -List $lib -Query $camlQuery -ErrorAction Stop

                foreach ($item in $items) {
                    $fileName = $item["FileLeafRef"]
                    # Double-check extension (CAML Contains can be loose)
                    $ext = [System.IO.Path]::GetExtension($fileName).ToLower()
                    if ($ext -notin @(".ps1", ".bat")) { continue }

                    $fileObj = [PSCustomObject]@{
                        Name          = $fileName
                        FileRef       = $item["FileRef"]        # Server-relative URL
                        Library       = $lib.Title
                        FolderPath    = $item["FileDirRef"]
                        Created       = $item["Created"]
                        Modified      = $item["Modified"]
                        Author        = $item["Author"].LookupValue
                        LastModifiedBy = $item["Editor"].LookupValue
                        SizeBytes     = $item["File_x0020_Size"]
                        Extension     = $ext
                        ItemId        = $item.Id
                        ListId        = $lib.Id
                        Comment       = ""
                        Tags          = @()
                        TagsRaw       = ""
                        ContentLoaded = $false
                    }
                    $allFiles.Add($fileObj)
                }
            } catch {
                Write-AppLog "Error scanning library '$($lib.Title)': $_" "WARN"
            }
        }
        Write-AppLog "Total script files found: $($allFiles.Count)"
    } catch {
        Write-AppLog "Critical error during file scan: $_" "ERROR"
        throw
    }

    return $allFiles
}

function Get-FileContent {
    param([PSCustomObject]$FileItem)
    try {
        $stream = Get-PnPFile -Url $FileItem.FileRef -AsMemoryStream -ErrorAction Stop
        $content = [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
        return $content
    } catch {
        Write-AppLog "Failed to read file content for $($FileItem.FileRef): $_" "ERROR"
        return $null
    }
}

function Parse-AppMetadata {
    param([string]$Content)
    $comment = ""
    $tags = @()

    if ([string]::IsNullOrEmpty($Content)) {
        return @{ Comment = $comment; Tags = $tags }
    }

    foreach ($line in $Content -split "`r?`n") {
        $line = $line.TrimEnd()
        if ($line.StartsWith($script:Config.CommentPrefix)) {
            # Decode the || newline token back to real newlines for the UI
            $raw = $line.Substring($script:Config.CommentPrefix.Length).Trim()
            $comment = $raw -replace '\|\|', "`n"
        } elseif ($line.StartsWith($script:Config.TagPrefix)) {
            $rawTags = $line.Substring($script:Config.TagPrefix.Length).Trim()
            $tags = $rawTags -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        }
    }

    return @{ Comment = $comment; Tags = $tags }
}

function Set-AppMetadata {
    <#
    .SYNOPSIS Writes comment and tag lines back into the file content string.
    Existing ENGINEERSPOWERAPP lines are replaced; new ones are added at the top.
    #>
    param(
        [string]$Content,
        [string]$Comment,
        [string[]]$Tags
    )

    # Remove any existing app metadata lines
    $lines = $Content -split "`r?`n" | Where-Object {
        -not $_.TrimStart().StartsWith($script:Config.CommentPrefix) -and
        -not $_.TrimStart().StartsWith($script:Config.TagPrefix)
    }

    # Build new metadata lines
    $newLines = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($Comment)) {
        # Encode any real newlines (from the multi-line TextBox) as || so the
        # comment stays on a single line in the file — decoded back by Parse-AppMetadata
        $encodedComment = $Comment -replace "`r`n", "||" -replace "`r", "||" -replace "`n", "||"
        $newLines.Add("$($script:Config.CommentPrefix)$encodedComment")
    }
    if ($Tags -and $Tags.Count -gt 0) {
        $tagString = ($Tags | Where-Object { $_ -ne "" }) -join ","
        if (-not [string]::IsNullOrWhiteSpace($tagString)) {
            $newLines.Add("$($script:Config.TagPrefix)$tagString")
        }
    }

    # Detect whether the original content already had metadata lines
    # (if not, we need to add a blank separator line after the new block)
    $hadMetadata = ($Content -match [regex]::Escape($script:Config.CommentPrefix)) -or
                   ($Content -match [regex]::Escape($script:Config.TagPrefix))

    # Prepend metadata to file (after shebang/requires line if present)
    $finalLines = [System.Collections.Generic.List[string]]::new()
    $insertedMeta = $false

    foreach ($line in $lines) {
        if (-not $insertedMeta -and -not $line.TrimStart().StartsWith("#!") -and
            -not $line.TrimStart().StartsWith("#Requires")) {
            foreach ($ml in $newLines) { $finalLines.Add($ml) }
            # Add a blank separator line when injecting metadata for the first time
            if (-not $hadMetadata -and $newLines.Count -gt 0) { $finalLines.Add("") }
            $insertedMeta = $true
        }
        $finalLines.Add($line)
    }

    if (-not $insertedMeta) {
        foreach ($ml in $newLines) { $finalLines.Add($ml) }
    }

    return ($finalLines -join "`n")
}

function Save-FileToSharePoint {
    param(
        [PSCustomObject]$FileItem,
        [string]$NewContent
    )
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($NewContent)
        $stream = [System.IO.MemoryStream]::new($bytes)
        Add-PnPFile -Stream $stream -Folder (Split-Path $FileItem.FileRef -Parent) `
                    -FileName $FileItem.Name -ErrorAction Stop | Out-Null
        Write-AppLog "Saved: $($FileItem.FileRef)"
        return $true
    } catch {
        Write-AppLog "Failed to save $($FileItem.FileRef): $_" "ERROR"
        return $false
    }
}

function Save-FileToLocal {
    param([PSCustomObject]$FileItem, [string]$NewContent)
    try {
        [System.IO.File]::WriteAllText($FileItem.FileRef, $NewContent, [System.Text.Encoding]::UTF8)
        Write-AppLog "Local save: $($FileItem.FileRef)"
        return $true
    } catch {
        Write-AppLog "Local save failed for $($FileItem.FileRef): $_" "ERROR"
        return $false
    }
}

function Rename-SharePointFile {
    param(
        [PSCustomObject]$FileItem,
        [string]$NewName
    )
    try {
        Rename-PnPFile -ServerRelativeUrl $FileItem.FileRef -TargetFileName $NewName `
                       -Force -ErrorAction Stop
        Write-AppLog "Renamed '$($FileItem.Name)' to '$NewName'"
        return $true
    } catch {
        Write-AppLog "Failed to rename '$($FileItem.Name)': $_" "ERROR"
        return $false
    }
}

# ============================================================
# CACHE FUNCTIONS
# ============================================================
function Save-Cache {
    param([System.Collections.Generic.List[PSObject]]$Files)
    try {
        $cacheObj = @{
            Timestamp = (Get-Date).ToString("o")
            SiteUrl   = $script:Config.SiteUrl
            Files     = $Files | ForEach-Object {
                @{
                    Name           = $_.Name
                    FileRef        = $_.FileRef
                    Library        = $_.Library
                    FolderPath     = $_.FolderPath
                    Created        = if ($_.Created) { $_.Created.ToString("o") } else { $null }
                    Modified       = if ($_.Modified) { $_.Modified.ToString("o") } else { $null }
                    Author         = $_.Author
                    LastModifiedBy = $_.LastModifiedBy
                    SizeBytes      = $_.SizeBytes
                    Extension      = $_.Extension
                    ItemId         = $_.ItemId
                    Comment        = $_.Comment
                    Tags           = $_.Tags
                    TagsRaw        = $_.TagsRaw
                }
            }
        }
        $cacheObj | ConvertTo-Json -Depth 10 | Set-Content -Path $script:Config.CacheFile -Encoding UTF8
        Write-AppLog "Cache saved: $($Files.Count) files"
    } catch {
        Write-AppLog "Cache save failed: $_" "WARN"
    }
}

function Load-Cache {
    if (-not (Test-Path $script:Config.CacheFile)) { return $null }
    try {
        $raw = Get-Content -Path $script:Config.CacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $files = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($f in $raw.Files) {
            $obj = [PSCustomObject]@{
                Name           = $f.Name
                FileRef        = $f.FileRef
                Library        = $f.Library
                FolderPath     = $f.FolderPath
                Created        = if ($f.Created) { [datetime]$f.Created } else { $null }
                Modified       = if ($f.Modified) { [datetime]$f.Modified } else { $null }
                Author         = $f.Author
                LastModifiedBy = $f.LastModifiedBy
                SizeBytes      = $f.SizeBytes
                Extension      = $f.Extension
                ItemId         = $f.ItemId
                Comment        = if ($f.Comment) { $f.Comment } else { "" }
                Tags           = if ($f.Tags) { @($f.Tags) } else { @() }
                TagsRaw        = if ($f.TagsRaw) { $f.TagsRaw } else { "" }
                # Mark as loaded if we have cached metadata — no need to re-read the file
                ContentLoaded  = (-not [string]::IsNullOrEmpty($f.Comment) -or ($f.Tags -and @($f.Tags).Count -gt 0))
            }
            $files.Add($obj)
        }
        Write-AppLog "Cache loaded: $($files.Count) files (cached $(([datetime]$raw.Timestamp).ToString('g')))"
        return @{ Files = $files; Timestamp = [datetime]$raw.Timestamp; SiteUrl = $raw.SiteUrl }
    } catch {
        Write-AppLog "Cache load failed: $_" "WARN"
        return $null
    }
}

# ============================================================
# GIT CACHE FUNCTIONS
# ============================================================
function Save-GitCache {
    param([System.Collections.Generic.List[PSObject]]$Files)
    try {
        $cacheObj = @{
            Timestamp   = (Get-Date).ToString("o")
            RepoPath    = $script:GitRepoPath
            Files       = $Files | ForEach-Object {
                @{
                    Name           = $_.Name
                    FileRef        = $_.FileRef      # Full local path
                    Library        = $_.Library      # Relative folder from repo root
                    FolderPath     = $_.FolderPath
                    Created        = if ($_.Created)  { $_.Created.ToString("o")  } else { $null }
                    Modified       = if ($_.Modified) { $_.Modified.ToString("o") } else { $null }
                    Author         = $_.Author
                    LastModifiedBy = $_.LastModifiedBy
                    SizeBytes      = $_.SizeBytes
                    Extension      = $_.Extension
                    ItemId         = $_.ItemId
                    Comment        = $_.Comment
                    Tags           = $_.Tags
                    TagsRaw        = $_.TagsRaw
                }
            }
        }
        $cacheObj | ConvertTo-Json -Depth 10 | Set-Content -Path $script:Config.GitCacheFile -Encoding UTF8
        Write-AppLog "Git cache saved: $($Files.Count) files"
    } catch {
        Write-AppLog "Git cache save failed: $_" "WARN"
    }
}

function Load-GitCache {
    if (-not (Test-Path $script:Config.GitCacheFile)) { return $null }
    try {
        $raw   = Get-Content -Path $script:Config.GitCacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
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
                ItemId         = $f.ItemId
                Comment        = if ($f.Comment) { $f.Comment } else { "" }
                Tags           = if ($f.Tags) { @($f.Tags) } else { @() }
                TagsRaw        = if ($f.TagsRaw) { $f.TagsRaw } else { "" }
                ContentLoaded  = (-not [string]::IsNullOrEmpty($f.Comment) -or ($f.Tags -and @($f.Tags).Count -gt 0))
            })
        }
        Write-AppLog "Git cache loaded: $($files.Count) files (cached $(([datetime]$raw.Timestamp).ToString('g')))"
        return @{ Files = $files; Timestamp = [datetime]$raw.Timestamp; RepoPath = $raw.RepoPath }
    } catch {
        Write-AppLog "Git cache load failed: $_" "WARN"
        return $null
    }
}

# ============================================================
# WPF ASSEMBLY LOADING
# ============================================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# ============================================================
# WPF XAML DEFINITION
# ============================================================
# FIX: Store as a plain string — do NOT cast to [xml].
# Casting to [xml] strips x: namespace attributes, making the object unusable
# with XamlReader. Use XamlReader::Parse() on the raw string instead.
$XAMLString = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Engineers PowerApp - PowerShell and Batch Script Browser"
    Height="800" Width="1280" MinHeight="600" MinWidth="900"
    WindowStartupLocation="CenterScreen"
    Background="#1E1E2E">

    <Window.Resources>
        <!-- Color Palette -->
        <SolidColorBrush x:Key="BgDeep"      Color="#1E1E2E"/>
        <SolidColorBrush x:Key="BgPanel"     Color="#252537"/>
        <SolidColorBrush x:Key="BgCard"      Color="#2E2E45"/>
        <SolidColorBrush x:Key="BgHover"     Color="#3A3A55"/>
        <SolidColorBrush x:Key="BgSelected"  Color="#4B4B70"/>
        <SolidColorBrush x:Key="AccentBlue"  Color="#7B9CFF"/>
        <SolidColorBrush x:Key="AccentGreen" Color="#50FA7B"/>
        <SolidColorBrush x:Key="AccentOrange" Color="#FFB86C"/>
        <SolidColorBrush x:Key="AccentRed"   Color="#FF5555"/>
        <SolidColorBrush x:Key="TextPrimary" Color="#F8F8F2"/>
        <SolidColorBrush x:Key="TextSecond"  Color="#A0A0C0"/>
        <SolidColorBrush x:Key="TextMuted"   Color="#6272A4"/>
        <SolidColorBrush x:Key="Border"      Color="#44446A"/>
        <SolidColorBrush x:Key="PS1Color"    Color="#BD93F9"/>
        <SolidColorBrush x:Key="BatColor"    Color="#FFB86C"/>

        <!-- Button Style -->
        <Style x:Key="AppButton" TargetType="Button">
            <Setter Property="Background" Value="#3A3A55"/>
            <Setter Property="Foreground" Value="#F8F8F2"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#44446A"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
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

        <!-- Accent Button Style -->
        <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource AppButton}">
            <Setter Property="Background" Value="#7B9CFF"/>
            <Setter Property="Foreground" Value="#1E1E2E"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderBrush" Value="#7B9CFF"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#9BB4FF"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- TextBox Style -->
        <Style x:Key="AppTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#1E1E2E"/>
            <Setter Property="Foreground" Value="#F8F8F2"/>
            <Setter Property="BorderBrush" Value="#44446A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="#7B9CFF"/>
            <Setter Property="SelectionBrush" Value="#4B4B70"/>
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

        <!-- ListBox Item Style -->
        <Style x:Key="FileListItem" TargetType="ListBoxItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#F8F8F2"/>
            <Setter Property="Padding" Value="10,7"/>
            <Setter Property="Margin" Value="2,1"/>
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

        <!-- ScrollBar Style (minimal) -->
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Width" Value="8"/>
        </Style>

        <!-- ComboBox Style -->
        <Style x:Key="AppComboBox" TargetType="ComboBox">
            <Setter Property="Background" Value="#2E2E45"/>
            <Setter Property="Foreground" Value="#F8F8F2"/>
            <Setter Property="BorderBrush" Value="#44446A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="FontSize" Value="12"/>
        </Style>

        <!-- Label Style -->
        <Style x:Key="MetaLabel" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#6272A4"/>
            <Setter Property="FontSize" Value="10"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,0,0,2"/>
        </Style>

        <Style x:Key="MetaValue" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#A0A0C0"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
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
                    <TextBlock Text="Engineers PowerApp" FontSize="16" FontWeight="Bold"
                               Foreground="#F8F8F2" VerticalAlignment="Center"/>
                    <TextBlock Text=" - PowerShell and Batch Script Browser" FontSize="13"
                               Foreground="#6272A4" VerticalAlignment="Center"/>
                </StackPanel>

                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="BtnOpenGitRepo" Style="{StaticResource AppButton}"
                            Content="[G] Open Git Repo" ToolTip="Scan local Git repository folder" Margin="0,0,8,0"/>
                    <Button x:Name="BtnConnect" Style="{StaticResource AppButton}"
                            Content="[>] Connect" ToolTip="Connect to SharePoint" Margin="0,0,8,0"/>
                    <Button x:Name="BtnRefresh" Style="{StaticResource AppButton}"
                            Content="[R] Refresh" IsEnabled="False"
                            ToolTip="Re-scan SharePoint and refresh cache" Margin="0,0,8,0"/>
                    <Border Width="1" Background="#44446A" Margin="4,8"/>
                    <TextBlock x:Name="TxtConnectionStatus" Text="[X] Disconnected"
                               Foreground="#FF5555" VerticalAlignment="Center" FontSize="11" Margin="8,0,0,0"/>
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

                    <!-- Search bar -->
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
                                                                <TextBlock Text="Search files..." Foreground="#6272A4"
                                                                           FontSize="13" Padding="10,8"/>
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
                                        <Setter Property="Background" Value="Transparent"/>
                                        <Setter Property="Foreground" Value="#F8F8F2"/>
                                        <Setter Property="IsExpanded" Value="True"/>
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
                    <TextBlock Text="Select a file to view details" FontSize="16"
                               Foreground="#44446A" HorizontalAlignment="Center" Margin="0,16,0,8"/>
                    <TextBlock Text="Connect to SharePoint first if you haven't already"
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
                                        Background="#2E2E45" CornerRadius="8"
                                        Margin="0,0,16,0">
                                    <TextBlock x:Name="TxtFileIcon" Text="PS" FontSize="14"
                                               FontWeight="Bold" HorizontalAlignment="Center"
                                               VerticalAlignment="Center" Foreground="#BD93F9"/>
                                </Border>
                                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                    <TextBlock x:Name="TxtDetailName" Text="filename.ps1"
                                               FontSize="18" FontWeight="Bold" Foreground="#F8F8F2"
                                               TextTrimming="CharacterEllipsis"/>
                                    <TextBlock x:Name="TxtDetailPath" Text="/Library/Folder/file.ps1"
                                               FontSize="11" Foreground="#6272A4" Margin="0,4,0,0"
                                               TextTrimming="CharacterEllipsis"/>
                                </StackPanel>
                                <Button x:Name="BtnRename" Grid.Column="2"
                                        Style="{StaticResource AppButton}"
                                        Content="Rename" VerticalAlignment="Center"/>
                            </Grid>
                        </Border>

                        <!-- Metadata Cards Row -->
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
                                    <TextBlock Text="CREATED BY" Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaAuthor" Text="-" Style="{StaticResource MetaValue}"/>
                                    <TextBlock Text="CREATED" Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaCreated" Text="-" Style="{StaticResource MetaValue}"/>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="2" Background="#252537" CornerRadius="6"
                                    Padding="14,12" BorderBrush="#44446A" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="LAST MODIFIED BY" Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaModifiedBy" Text="-" Style="{StaticResource MetaValue}"/>
                                    <TextBlock Text="MODIFIED" Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaModified" Text="-" Style="{StaticResource MetaValue}"/>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="4" Background="#252537" CornerRadius="6"
                                    Padding="14,12" BorderBrush="#44446A" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="LIBRARY" Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaLibrary" Text="-" Style="{StaticResource MetaValue}"/>
                                    <TextBlock Text="SIZE" Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaSize" Text="-" Style="{StaticResource MetaValue}"/>
                                </StackPanel>
                            </Border>

                            <Border Grid.Column="6" Background="#252537" CornerRadius="6"
                                    Padding="14,12" BorderBrush="#44446A" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="TYPE" Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaType" Text="-" Style="{StaticResource MetaValue}"/>
                                    <TextBlock Text="FOLDER PATH" Style="{StaticResource MetaLabel}"/>
                                    <TextBlock x:Name="TxtMetaFolder" Text="-" Style="{StaticResource MetaValue}"
                                               TextTrimming="CharacterEllipsis"/>
                                </StackPanel>
                            </Border>
                        </Grid>

                        <!-- Action Buttons -->
                        <Border Grid.Row="2" Background="#252537" CornerRadius="8"
                                Padding="16,12" Margin="0,0,0,16"
                                BorderBrush="#44446A" BorderThickness="1">
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="BtnOpenVSCode" Style="{StaticResource AccentButton}"
                                        Content="[VS] Open in VSCode"
                                        ToolTip="Download file temporarily and open in VSCode" Margin="0,0,8,0"/>
                                <Button x:Name="BtnOpenWebDAV" Style="{StaticResource AppButton}"
                                        Content="[W] Open via WebDAV"
                                        ToolTip="Open file directly via SharePoint WebDAV mapping" Margin="0,0,8,0"/>
                                <Button x:Name="BtnLoadContent" Style="{StaticResource AppButton}"
                                        Content="[L] Load File Content"
                                        ToolTip="Load the full file content for preview and metadata editing" Margin="0,0,8,0"/>
                                <Border Width="1" Background="#44446A" Margin="4,4"/>
                                <Button x:Name="BtnCopyPath" Style="{StaticResource AppButton}"
                                        Content="Copy Path" Margin="8,0,8,0"/>
                                <Button x:Name="BtnCopyUrl" Style="{StaticResource AppButton}"
                                        Content="Copy URL"/>
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
                                    <TextBlock Text=" - stored as  ##ENGINEERSPOWERAPP#COMMENT#  in file"
                                               FontSize="10" Foreground="#44446A" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBox x:Name="TxtComment" Style="{StaticResource AppTextBox}"
                                         Height="80" TextWrapping="Wrap" AcceptsReturn="True"
                                         VerticalScrollBarVisibility="Auto"
                                         VerticalContentAlignment="Top"
                                         Text="" FontFamily="Consolas" FontSize="12"/>
                                <TextBlock Text="Multi-line supported (Enter for new line). Cached comments load automatically; click Load File Content to re-read from disk."
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
                                    <TextBlock Text=" - stored as  ##ENGINEERSPOWERAPP#TAGS#  in file"
                                               FontSize="10" Foreground="#44446A" VerticalAlignment="Center"/>
                                </StackPanel>
                                <TextBox x:Name="TxtTags" Style="{StaticResource AppTextBox}"
                                         Height="36" VerticalContentAlignment="Center"
                                         Text="" FontFamily="Consolas" FontSize="12"/>
                                <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                                    <TextBlock Text="Quick add:" FontSize="10" Foreground="#6272A4"
                                               VerticalAlignment="Center" Margin="0,0,4,0"/>
                                    <Button x:Name="BtnTagAutomation" Content="automation"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#BD93F9" BorderBrush="#BD93F9" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagMaintenance" Content="maintenance"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#50FA7B" BorderBrush="#50FA7B" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagDeploy" Content="deployment"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#FFB86C" BorderBrush="#FFB86C" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagMonitor" Content="monitoring"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#FF79C6" BorderBrush="#FF79C6" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagSecurity" Content="security"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#FF5555" BorderBrush="#FF5555" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagUtil" Content="utility"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#8BE9FD" BorderBrush="#8BE9FD" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagIsFunction" Content="isFunction"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#FFCF7A" BorderBrush="#FFCF7A" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagIsApp" Content="isApp"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#FFCF7A" BorderBrush="#FFCF7A" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnTagPS7" Content="PowerShell 7"
                                            Style="{StaticResource AppButton}" Padding="8,3" FontSize="10"
                                            Foreground="#BD93F9" BorderBrush="#BD93F9"/>
                                </StackPanel>
                                <TextBlock Text="Comma-separated. Cached tags load automatically; click Load File Content to re-read from disk."
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
                                    <TextBlock x:Name="TxtPreviewNote" Text=" - click 'Load File Content' above"
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
                <TextBlock x:Name="TxtStatus" Grid.Column="0"
                           Text="Ready. Connect to SharePoint to begin."
                           Foreground="#6272A4" VerticalAlignment="Center" FontSize="11"/>
                <TextBlock x:Name="TxtCacheInfo" Grid.Column="1"
                           Foreground="#44446A" VerticalAlignment="Center" FontSize="11"/>
            </Grid>
        </Border>

        <!-- Loading overlay -->
        <Border x:Name="LoadingOverlay" Grid.RowSpan="3"
                Background="#CC1E1E2E" Visibility="Collapsed">
            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                <TextBlock x:Name="TxtLoadingMsg" Text="Connecting to SharePoint..."
                           FontSize="18" Foreground="#F8F8F2" HorizontalAlignment="Center"/>
                <TextBlock Text="Please complete authentication in the popup window"
                           FontSize="12" Foreground="#A0A0C0" HorizontalAlignment="Center"
                           Margin="0,8,0,0"/>
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

# ============================================================
# WPF WINDOW SETUP
# FIX 1: Variable was mistyped as $XMAL in the previous version — now $XAMLString
# FIX 2: Use XamlReader::Parse() on the raw string. Never cast XAML to [xml] first —
#         doing so strips x: namespace attributes, leaving $null and causing the cascade
#         of "Value cannot be null" and "null-valued expression" errors seen at startup.
# ============================================================
$Window = [Windows.Markup.XamlReader]::Parse($XAMLString)

# Get control references — defined BEFORE the variable assignments that call it
function Get-Control { param($Name) $Window.FindName($Name) }

$BtnOpenGitRepo      = Get-Control "BtnOpenGitRepo"
$BtnConnect          = Get-Control "BtnConnect"
$BtnRefresh          = Get-Control "BtnRefresh"
$TxtConnectionStatus = Get-Control "TxtConnectionStatus"
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
$TxtDetailName       = Get-Control "TxtDetailName"
$TxtDetailPath       = Get-Control "TxtDetailPath"
$TxtFileIcon         = Get-Control "TxtFileIcon"
$TxtMetaAuthor       = Get-Control "TxtMetaAuthor"
$TxtMetaCreated      = Get-Control "TxtMetaCreated"
$TxtMetaModifiedBy   = Get-Control "TxtMetaModifiedBy"
$TxtMetaModified     = Get-Control "TxtMetaModified"
$TxtMetaLibrary      = Get-Control "TxtMetaLibrary"
$TxtMetaSize         = Get-Control "TxtMetaSize"
$TxtMetaType         = Get-Control "TxtMetaType"
$TxtMetaFolder       = Get-Control "TxtMetaFolder"
$BtnOpenVSCode       = Get-Control "BtnOpenVSCode"
$BtnOpenWebDAV       = Get-Control "BtnOpenWebDAV"
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
$BtnTagIsFunction    = Get-Control "BtnTagIsFunction"
$BtnTagIsApp         = Get-Control "BtnTagIsApp"
$BtnTagPS7           = Get-Control "BtnTagPS7"
$TxtFileContent      = Get-Control "TxtFileContent"
$TxtPreviewNote      = Get-Control "TxtPreviewNote"
$BtnSaveMetadata     = Get-Control "BtnSaveMetadata"
$TxtSaveStatus       = Get-Control "TxtSaveStatus"
$BtnRename           = Get-Control "BtnRename"
$TxtStatus           = Get-Control "TxtStatus"
$TxtCacheInfo        = Get-Control "TxtCacheInfo"
$LoadingOverlay      = Get-Control "LoadingOverlay"
$TxtLoadingMsg       = Get-Control "TxtLoadingMsg"

# ============================================================
# APPLICATION STATE
# ============================================================
$script:AllFiles      = [System.Collections.Generic.List[PSObject]]::new()
$script:FilteredFiles = [System.Collections.Generic.List[PSObject]]::new()
$script:SelectedFile  = $null
$script:IsConnected   = $false
$script:DataSource     = "none"      # "sharepoint" | "git" | "none"
$script:CurrentView   = "alpha"   # alpha | folder | tag
$script:FileContent   = $null

# ============================================================
# VIEW MODEL HELPER
# ============================================================
function New-FileViewModel {
    param([PSCustomObject]$File)
    # Guard against corrupt/null cache entries
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

# ============================================================
# UI HELPERS
# ============================================================
function Set-Status {
    param([string]$Message, [string]$Color = "#6272A4")
    $TxtStatus.Dispatcher.Invoke({
        $TxtStatus.Text       = $Message
        $TxtStatus.Foreground = $Color
    })
}

function Show-Loading {
    param([string]$Message = "Working...")
    $Window.Dispatcher.Invoke({
        $TxtLoadingMsg.Text         = $Message
        $LoadingOverlay.Visibility  = "Visible"
    })
}

function Hide-Loading {
    $Window.Dispatcher.Invoke({ $LoadingOverlay.Visibility = "Collapsed" })
}

function Format-FileSize {
    param([long]$Bytes)
    if ($Bytes -lt 1024) { return "$Bytes B" }
    if ($Bytes -lt 1MB)  { return "{0:N1} KB" -f ($Bytes / 1KB) }
    return "{0:N1} MB" -f ($Bytes / 1MB)
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

# ============================================================
# FILE LIST POPULATION
# ============================================================
function Update-FileList {
    $search = $TxtSearch.Text.Trim().ToLower()

    $filtered = $script:AllFiles | Where-Object {
        if ([string]::IsNullOrEmpty($search)) { return $true }
        return (
            $_.Name.ToLower().Contains($search) -or
            $_.Library.ToLower().Contains($search) -or
            ($_.Comment -and $_.Comment.ToLower().Contains($search)) -or
            ($_.Tags -and ($_.Tags -join ",").ToLower().Contains($search))
        )
    }

    $script:FilteredFiles = [System.Collections.Generic.List[PSObject]]($filtered)

    switch ($script:CurrentView) {
        "alpha"  { Populate-AlphaView  $script:FilteredFiles }
        "folder" { Populate-FolderView $script:FilteredFiles }
        "tag"    { Populate-TagView    $script:FilteredFiles }
    }

    $count = $script:FilteredFiles.Count
    $total = $script:AllFiles.Count
    $TxtFileCount.Text = if ($search) { "$count of $total files match" } else { "$total files total" }
}

function Populate-AlphaView {
    param($Files)
    $FileTreeView.Visibility = "Collapsed"
    $FileListBox.Visibility  = "Visible"

    $sorted = $Files | Where-Object { -not [string]::IsNullOrEmpty($_.Name) -and -not [string]::IsNullOrEmpty($_.Extension) } | Sort-Object Name
    $FileListBox.Items.Clear()
    foreach ($f in $sorted) {
        $vm = New-FileViewModel $f
        if ($null -ne $vm) { $FileListBox.Items.Add($vm) }
    }
}

function Populate-FolderView {
    param($Files)
    $FileListBox.Visibility  = "Collapsed"
    $FileTreeView.Visibility = "Visible"
    $FileTreeView.Items.Clear()

    $grouped = $Files | Group-Object { "$($_.Library)/$($_.FolderPath -replace '^.*?/[^/]+/', '')" } |
               Sort-Object Name

    foreach ($group in $grouped) {
        $header            = New-Object System.Windows.Controls.TreeViewItem
        $header.Header     = "[/] $($group.Name)"
        $header.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xA0, 0xA0, 0xC0)
        $header.IsExpanded = $true

        foreach ($f in ($group.Group | Sort-Object Name)) {
            $item = New-Object System.Windows.Controls.TreeViewItem
            $vm   = New-FileViewModel $f

            $sp             = New-Object System.Windows.Controls.StackPanel
            $sp.Orientation = "Horizontal"

            $extLbl          = New-Object System.Windows.Controls.TextBlock
            $extLbl.Text     = $vm.ExtIcon
            $extLbl.Foreground = [System.Windows.Media.SolidColorBrush]([System.Windows.Media.ColorConverter]::ConvertFromString($vm.ExtColor))
            $extLbl.Margin   = [System.Windows.Thickness]::new(0,0,8,0)
            $extLbl.FontSize = 10

            $nameLbl           = New-Object System.Windows.Controls.TextBlock
            $nameLbl.Text      = $f.Name
            $nameLbl.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xF8, 0xF8, 0xF2)

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

function Populate-TagView {
    param($Files)
    $FileListBox.Visibility  = "Collapsed"
    $FileTreeView.Visibility = "Visible"
    $FileTreeView.Items.Clear()

    $tagged   = $Files | Where-Object { $_.Tags -and $_.Tags.Count -gt 0 }
    $untagged = $Files | Where-Object { -not $_.Tags -or $_.Tags.Count -eq 0 }

    $tagMap = @{}
    foreach ($f in $tagged) {
        foreach ($tag in $f.Tags) {
            if (-not $tagMap.ContainsKey($tag)) { $tagMap[$tag] = [System.Collections.Generic.List[PSObject]]::new() }
            $tagMap[$tag].Add($f)
        }
    }

    # Pinned tags always appear at the top in amber, even with 0 files
    $pinnedTags = @("isFunction", "isApp")
    $amberBrush = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xFF, 0xCF, 0x7A)
    $normalBrush = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xBD, 0x93, 0xF9)

    foreach ($tag in $pinnedTags) {
        $files = if ($tagMap.ContainsKey($tag)) { $tagMap[$tag] } else { @() }
        $header            = New-Object System.Windows.Controls.TreeViewItem
        $header.Header     = "[#] $tag ($($files.Count))"
        $header.Foreground = $amberBrush
        $header.IsExpanded = $true
        foreach ($f in ($files | Sort-Object Name)) {
            $item    = New-Object System.Windows.Controls.TreeViewItem
            $vm      = New-FileViewModel $f
            $nameLbl = New-Object System.Windows.Controls.TextBlock
            $nameLbl.Text       = "  $($vm.ExtIcon)  $($f.Name)"
            $nameLbl.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xF8, 0xF8, 0xF2)
            $item.Header = $nameLbl
            $item.Tag    = $f
            $item.Add_Selected({ param($s,$e) Select-File $s.Tag })
            $header.Items.Add($item)
        }
        $FileTreeView.Items.Add($header)
    }

    # Remaining tags sorted alphabetically, skipping the pinned ones
    foreach ($tag in ($tagMap.Keys | Where-Object { $pinnedTags -notcontains $_ } | Sort-Object)) {
        $header            = New-Object System.Windows.Controls.TreeViewItem
        $header.Header     = "[#] $tag ($($tagMap[$tag].Count))"
        $header.Foreground = $normalBrush
        $header.IsExpanded = $true

        foreach ($f in ($tagMap[$tag] | Sort-Object Name)) {
            $item    = New-Object System.Windows.Controls.TreeViewItem
            $vm      = New-FileViewModel $f
            $nameLbl = New-Object System.Windows.Controls.TextBlock
            $nameLbl.Text       = "  $($vm.ExtIcon)  $($f.Name)"
            $nameLbl.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xF8, 0xF8, 0xF2)
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
        $header.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0x62, 0x72, 0xA4)
        $header.IsExpanded = $false
        foreach ($f in ($untagged | Sort-Object Name)) {
            $item    = New-Object System.Windows.Controls.TreeViewItem
            $vm      = New-FileViewModel $f
            $nameLbl = New-Object System.Windows.Controls.TextBlock
            $nameLbl.Text      = "  $($vm.ExtIcon)  $($f.Name)"
            $nameLbl.Foreground = [System.Windows.Media.SolidColorBrush][System.Windows.Media.Color]::FromRgb(0xA0, 0xA0, 0xC0)
            $item.Header = $nameLbl
            $item.Tag    = $f
            $item.Add_Selected({ param($s,$e) Select-File $s.Tag })
            $header.Items.Add($item)
        }
        $FileTreeView.Items.Add($header)
    }
}

# ============================================================
# FILE SELECTION & DETAIL VIEW
# ============================================================
function Update-ModeButtons {
    # Grey out buttons that don't apply to the current data source
    if ($script:DataSource -eq "git") {
        $BtnCopyUrl.IsEnabled  = $false
        $BtnCopyUrl.Opacity    = 0.35
        $BtnCopyPath.IsEnabled = $true
        $BtnCopyPath.Opacity   = 1.0
    } elseif ($script:DataSource -eq "sharepoint") {
        $BtnCopyUrl.IsEnabled  = $true
        $BtnCopyUrl.Opacity    = 1.0
        $BtnCopyPath.IsEnabled = $false
        $BtnCopyPath.Opacity   = 0.35
    } else {
        $BtnCopyUrl.IsEnabled  = $false
        $BtnCopyUrl.Opacity    = 0.35
        $BtnCopyPath.IsEnabled = $false
        $BtnCopyPath.Opacity   = 0.35
    }
}

function Select-File {
    param([PSCustomObject]$File)
    $script:SelectedFile = $File
    $script:FileContent  = $null

    $PanelEmpty.Visibility  = "Collapsed"
    $PanelDetail.Visibility = "Visible"

    $ext = $File.Extension.ToLower()
    $TxtDetailName.Text = $File.Name
    $TxtDetailPath.Text = $File.FileRef

    if ($ext -eq ".ps1") {
        $TxtFileIcon.Text       = "PS1"
        $TxtFileIcon.Foreground = "#BD93F9"
    } else {
        $TxtFileIcon.Text       = "BAT"
        $TxtFileIcon.Foreground = "#FFB86C"
    }

    $TxtMetaAuthor.Text     = if ($File.Author)         { $File.Author }         else { "-" }
    $TxtMetaCreated.Text    = if ($File.Created)        { $File.Created.ToString("MMM dd, yyyy h:mmtt") }  else { "-" }
    $TxtMetaModifiedBy.Text = if ($File.LastModifiedBy) { $File.LastModifiedBy } else { "-" }
    $TxtMetaModified.Text   = if ($File.Modified)       { $File.Modified.ToString("MMM dd, yyyy h:mmtt") } else { "-" }
    $TxtMetaLibrary.Text    = if ($File.Library)        { $File.Library }        else { "-" }
    $TxtMetaSize.Text       = if ($File.SizeBytes)      { Format-FileSize([long]$File.SizeBytes) }         else { "-" }
    $TxtMetaType.Text       = $ext.ToUpper().TrimStart(".")
    $TxtMetaFolder.Text     = if ($File.FolderPath)     { $File.FolderPath }     else { "-" }

    $TxtComment.Text = $File.Comment
    $TxtTags.Text    = ($File.Tags -join ", ")

    $TxtFileContent.Text = "(Loading file content...)"
    $TxtPreviewNote.Text = ""
    $TxtSaveStatus.Text  = ""

    Set-Status "Selected: $($File.Name)"
    Write-AppLog "File selected: $($File.FileRef)"

    # Grey out buttons irrelevant to current mode
    Update-ModeButtons

    # Auto-load file content on every selection so metadata is always
    # in sync with disk and editing is immediately available.
    # The Load File Content button remains for manual re-reads after editing in VSCode.
    if ($script:DataSource -ne "none") {
        Load-SelectedFileContent
    }
}

# ============================================================
# LOAD FILE CONTENT (on demand)
# ============================================================
function Load-SelectedFileContent {
    if ($null -eq $script:SelectedFile) { return }
    if ($script:DataSource -eq "none") {
        Set-Status "Not connected to any source." "#FF5555"
        return
    }

    Set-Status "Loading file content..." "#FFB86C"
    $file = $script:SelectedFile

    try {
        $content = if ($script:DataSource -eq "git") {
            # Local file — read directly from disk
            if (Test-Path $file.FileRef) {
                Get-Content -Path $file.FileRef -Raw -Encoding UTF8
            } else {
                throw "Local file not found: $($file.FileRef)"
            }
        } else {
            Get-FileContent $file
        }
        if ($null -ne $content) {
            $script:FileContent = $content
            $meta = Parse-AppMetadata $content

            $script:SelectedFile.Comment      = $meta.Comment
            $script:SelectedFile.Tags         = $meta.Tags
            $script:SelectedFile.TagsRaw      = ($meta.Tags -join ",")
            $script:SelectedFile.ContentLoaded = $true

            $TxtComment.Text     = $meta.Comment
            $TxtTags.Text        = ($meta.Tags -join ", ")
            $TxtFileContent.Text = $content
            $TxtPreviewNote.Text = " - $([Math]::Round($content.Length/1KB,1)) KB, $($content.Split("`n").Count) lines"
            Set-Status "File loaded: $($file.Name)" "#50FA7B"
            Write-AppLog "Content loaded for: $($file.FileRef)"
        } else {
            Set-Status "Failed to load file content." "#FF5555"
        }
    } catch {
        Set-Status "Error loading content: $_" "#FF5555"
        Write-AppLog "Load content error: $_" "ERROR"
    }
}

# ============================================================
# SAVE METADATA BACK TO FILE
# ============================================================
function Save-SelectedFileMetadata {
    if ($null -eq $script:SelectedFile) { return }
    if ($script:DataSource -eq "none") {
        Set-Status "Not connected to any source." "#FF5555"
        return
    }
    # Content is auto-loaded on file selection, but guard in case somehow it's missing
    if ($null -eq $script:FileContent) {
        Load-SelectedFileContent
        if ($null -eq $script:FileContent) { return }
    }

    $comment = $TxtComment.Text.Trim()
    $tags    = $TxtTags.Text -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }

    $newContent = Set-AppMetadata -Content $script:FileContent -Comment $comment -Tags $tags

    try {
        $saveOk = if ($script:DataSource -eq "git") {
            Save-FileToLocal $script:SelectedFile $newContent
        } else {
            Save-FileToSharePoint $script:SelectedFile $newContent
        }
        if (-not $saveOk) { throw "Save returned false" }

        $script:FileContent           = $newContent
        $script:SelectedFile.Comment  = $comment
        $script:SelectedFile.Tags     = $tags
        $script:SelectedFile.TagsRaw  = ($tags -join ",")
        $TxtFileContent.Text          = $newContent
        $TxtSaveStatus.Text           = "[OK] Saved $(Get-Date -Format 'h:mmtt')"
        Set-Status "Saved metadata to: $($script:SelectedFile.Name)" "#50FA7B"
        Write-AppLog "Metadata saved: $($script:SelectedFile.FileRef)"

        if ($script:DataSource -eq "git") { Save-GitCache $script:AllFiles } else { Save-Cache $script:AllFiles }

        # Refresh the file list so the tag view updates immediately without needing a full refresh
        Update-FileList
    } catch {
        $TxtSaveStatus.Text           = "[X] Save failed"
        $TxtSaveStatus.Foreground     = "#FF5555"
        Set-Status "Save failed: $_" "#FF5555"
        Write-AppLog "Save metadata error: $_" "ERROR"
    }
}

# ============================================================
# RENAME
# ============================================================
function Rename-SelectedFile {
    if ($null -eq $script:SelectedFile) { return }

    $dialog                       = [System.Windows.Window]::new()
    $dialog.Title                 = "Rename File"
    $dialog.Width                 = 420
    $dialog.Height                = 180
    $dialog.WindowStartupLocation = "CenterOwner"
    $dialog.Owner                 = $Window
    $dialog.Background            = "#252537"
    $dialog.ResizeMode            = "NoResize"

    $lbl            = [System.Windows.Controls.TextBlock]::new()
    $lbl.Text       = "Enter new filename (include extension):"
    $lbl.Foreground = "#A0A0C0"
    $lbl.FontSize   = 12
    $lbl.Margin     = [System.Windows.Thickness]::new(0,0,0,8)

    $tb             = [System.Windows.Controls.TextBox]::new()
    $tb.Text        = $script:SelectedFile.Name
    $tb.Background  = "#1E1E2E"
    $tb.Foreground  = "#F8F8F2"
    $tb.FontSize    = 13
    $tb.Padding     = [System.Windows.Thickness]::new(8,6,8,6)
    $tb.BorderBrush = "#7B9CFF"
    $tb.Margin      = [System.Windows.Thickness]::new(0,0,0,16)
    $tb.SelectAll()

    $btnPanel                     = [System.Windows.Controls.StackPanel]::new()
    $btnPanel.Orientation         = "Horizontal"
    $btnPanel.HorizontalAlignment = "Right"

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

    $btnPanel.Children.Add($btnOk)
    $btnPanel.Children.Add($btnCancel)

    $sp = [System.Windows.Controls.StackPanel]::new()
    $sp.Margin = [System.Windows.Thickness]::new(20)
    $sp.Children.Add($lbl)
    $sp.Children.Add($tb)
    $sp.Children.Add($btnPanel)
    $dialog.Content = $sp

    # Store result via dialog.Tag to avoid PS7 closure scoping issues
    $dialog.Tag = $null
    $btnOk.Add_Click({
        $dialog.Tag = $tb.Text.Trim()
        $dialog.DialogResult = $true
        $dialog.Close()
    })
    $btnCancel.Add_Click({ $dialog.Close() })
    $tb.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq "Return") {
            $dialog.Tag = $tb.Text.Trim()
            $dialog.DialogResult = $true
            $dialog.Close()
        }
    })

    $result = $dialog.ShowDialog()
    $newName = $dialog.Tag

    if ($result -and -not [string]::IsNullOrWhiteSpace($newName) -and $newName -ne $script:SelectedFile.Name) {
        try {
            $oldName = $script:SelectedFile.Name

            if ($script:DataSource -eq "git") {
                $oldPath = $script:SelectedFile.FileRef
                $newPath = Join-Path (Split-Path $oldPath -Parent) $newName
                Rename-Item -Path $oldPath -NewName $newName -ErrorAction Stop
                $script:SelectedFile.FileRef = $newPath
            } else {
                Rename-PnPFile -ServerRelativeUrl $script:SelectedFile.FileRef `
                               -TargetFileName $newName -Force -ErrorAction Stop
                $script:SelectedFile.FileRef = ($script:SelectedFile.FileRef -replace [regex]::Escape($oldName), $newName)
            }

            $script:SelectedFile.Name      = $newName
            $script:SelectedFile.Extension = [System.IO.Path]::GetExtension($newName).ToLower()

            $TxtDetailName.Text = $newName
            $TxtDetailPath.Text = $script:SelectedFile.FileRef
            if ($script:DataSource -eq "git") { Save-GitCache $script:AllFiles } else { Save-Cache $script:AllFiles }
            Update-FileList
            # Re-select so detail panel and ItemId stay in sync
            Select-File $script:SelectedFile
            Set-Status "Renamed to: $newName" "#50FA7B"
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

# ============================================================
# OPEN IN VSCODE
# ============================================================
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
        $openPath = if ($script:DataSource -eq "git") {
            # Local file — open directly, no temp copy needed
            $script:SelectedFile.FileRef
        } else {
            # SharePoint — download to temp first
            $tempDir = "$env:TEMP\EngineersPowerApp"
            if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
            $tp = Join-Path $tempDir $script:SelectedFile.Name
            Get-PnPFile -Url $script:SelectedFile.FileRef -Path $tempDir `
                        -Filename $script:SelectedFile.Name -AsFile -Force -ErrorAction Stop
            $tp
        }

        if ($codeExe -is [System.Management.Automation.CommandInfo]) {
            & $codeExe.Source $openPath
        } else {
            & $codeExe $openPath
        }

        if ($script:DataSource -eq "git") {
            Set-Status "Opened in VSCode: $openPath" "#50FA7B"
        } else {
            Set-Status "Opened in VSCode (temp copy): $openPath" "#50FA7B"
            [System.Windows.MessageBox]::Show(
                "File opened in VSCode as a temporary copy.`n`nPath: $openPath`n`nNOTE: Changes made in VSCode will NOT sync back to SharePoint automatically.",
                "Opened in VSCode",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            )
        }
    } catch {
        Set-Status "Failed to open in VSCode: $_" "#FF5555"
        Write-AppLog "VSCode open error: $_" "ERROR"
    }
}

# ============================================================
# OPEN VIA WEBDAV
# ============================================================
function Open-ViaWebDAV {
    if ($null -eq $script:SelectedFile) { return }

    $fullUrl = "$($script:Config.SiteUrl)$($script:SelectedFile.FileRef)"

    try {
        Start-Process $fullUrl
        Set-Status "Opened WebDAV URL in browser/handler" "#50FA7B"
    } catch {
        [System.Windows.Clipboard]::SetText($fullUrl)
        Set-Status "URL copied to clipboard (couldn't auto-open)" "#FFB86C"
    }
}

# ============================================================
# QUICK TAG HELPERS
# ============================================================
function Add-QuickTag {
    param([string]$Tag)
    $existing = $TxtTags.Text.Trim()
    $tags = if ($existing) {
        $existing -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    } else { @() }

    if ($tags -notcontains $Tag) {
        $tags = @($tags) + $Tag
        $TxtTags.Text = ($tags -join ", ")
    }
}

# ============================================================
# OPEN GIT REPOSITORY (local folder mode)
# ============================================================
function Start-OpenGitRepo {
    $repoPath = $script:GitRepoPath

    if ([string]::IsNullOrWhiteSpace($repoPath) -or $repoPath -like "*YourRepoName*") {
        [System.Windows.MessageBox]::Show(
            "Git repository path is not configured.`n`nDelete config.json from:`n$($script:AppDataDir)`n`nto re-run the setup wizard, or edit config.json directly.",
            "Configuration Required",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return
    }

    if (-not (Test-Path $repoPath -PathType Container)) {
        [System.Windows.MessageBox]::Show(
            "Path not found or not a folder:`n$repoPath`n`nCheck GitRepoPath in config.json",
            "Folder Not Found",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        )
        return
    }

    Show-Loading "Scanning Git repository..."
    Write-AppLog "Scanning local repo: $repoPath"

    # Run synchronously — local FS scan is fast, no need for a runspace
    try {
        $found = Get-ChildItem -Path $repoPath -Recurse -Include "*.ps1","*.bat" -File -ErrorAction Stop

        $allFiles = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($f in $found) {
            $relFolder = $f.DirectoryName.Replace($repoPath, "").TrimStart("\/")
            $allFiles.Add([PSCustomObject]@{
                Name           = $f.Name
                FileRef        = $f.FullName               # Full local path
                Library        = if ($relFolder) { $relFolder.Split([IO.Path]::DirectorySeparatorChar)[0] } else { "(root)" }
                FolderPath     = $f.DirectoryName
                Created        = $f.CreationTime
                Modified       = $f.LastWriteTime
                Author         = ""
                LastModifiedBy = ""
                SizeBytes      = $f.Length
                Extension      = $f.Extension.ToLower()
                ItemId         = $f.FullName               # Use full path as stable ID
                Comment        = ""
                Tags           = @()
                TagsRaw        = ""
                ContentLoaded  = $false
            })
        }

        Write-AppLog "Git repo scan complete: $($allFiles.Count) script files"

        $script:AllFiles    = $allFiles
        $script:DataSource  = "git"
        $script:IsConnected = $true   # Reuse flag so rest of UI enables correctly

        # Merge existing git cache (preserves comments/tags between scans)
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
        Set-Status "Git repo loaded. $($allFiles.Count) script files found." "#50FA7B"
        Update-ModeButtons

        # Kick off background metadata scan to populate tags/comments for all files
        Start-MetadataScan
    } catch {
        Write-AppLog "Git repo scan error: $_" "ERROR"
        Set-Status "Error scanning repo: $_" "#FF5555"
    } finally {
        Hide-Loading
    }
}

# ============================================================
# BACKGROUND METADATA SCAN
# ============================================================
# Reads every file and parses ##ENGINEERSPOWERAPP tags/comments.
# Runs in a background runspace for SharePoint; a fast local loop for Git.
# Updates AllFiles in-place as results arrive, then saves cache.
function Start-MetadataScan {
    if ($script:AllFiles.Count -eq 0) { return }

    Write-AppLog "Starting metadata scan for $($script:AllFiles.Count) files (source=$($script:DataSource))"
    Set-Status "Scanning file metadata (0 / $($script:AllFiles.Count))..." "#FFB86C"

    if ($script:DataSource -eq "git") {
        # ── Git mode: read all files synchronously on the main thread.
        # Local disk reads for 200 files takes < 1 second — no threading needed,
        # and threading caused silent failures writing back to PSCustomObject properties.
        $total   = $script:AllFiles.Count
        $indexed = 0
        foreach ($f in $script:AllFiles) {
            try {
                if (Test-Path -LiteralPath $f.FileRef) {
                    $raw     = [System.IO.File]::ReadAllText($f.FileRef, [System.Text.Encoding]::UTF8)
                    $comment = ""
                    $tags    = @()
                    $tagsRaw = ""
                    foreach ($line in ($raw -split "`r?`n")) {
                        $line = $line.TrimEnd()
                        if ($line.StartsWith("##ENGINEERSPOWERAPP#COMMENT#")) {
                            $comment = $line.Substring(28).Trim() -replace [regex]::Escape("||"), "`n"
                        } elseif ($line.StartsWith("##ENGINEERSPOWERAPP#TAGS#")) {
                            $tagsRaw = $line.Substring(25).Trim()
                            $tags    = @($tagsRaw -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
                        }
                    }
                    # Always write what we found — if the file has markers, use them;
                    # if it genuinely has no markers the fields stay blank which is correct.
                    $f.Comment       = $comment
                    $f.Tags          = $tags
                    $f.TagsRaw       = $tagsRaw
                    $f.ContentLoaded = ($comment -ne "" -or $tags.Count -gt 0)
                    if ($comment -or $tags.Count -gt 0) {
                        $indexed++
                        Write-AppLog "  [META] $($f.Name): comment=$($comment -ne '') tags=$($tags -join ',')"
                    }
                }
            } catch {
                Write-AppLog "Metadata scan error on $($f.Name): $_" "WARN"
            }
        }
        Write-AppLog "Git metadata scan complete. $indexed / $total files had metadata."
        Save-GitCache $script:AllFiles
        Update-FileList
        Set-Status "Metadata scan complete. $indexed files with tags/comments." "#50FA7B"

    } else {
        # ── SharePoint mode: download each file via PnP in a runspace ───────
        $Config    = $script:Config
        $AppConfig = $script:AppConfig
        # Pass file refs as plain strings — PSObjects don't cross runspace cleanly
        $fileRefs  = $script:AllFiles | ForEach-Object { $_.FileRef }

        $runspace                = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $runspace.ApartmentState = "STA"
        $runspace.Open()
        $ps          = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $runspace

        $ps.AddScript({
            param($Config, $AppConfig, $FileRefs)

            function RS-Log {
                param([string]$Msg, [string]$Level = "INFO")
                $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Add-Content -Path $Config.LogFile -Value "[$ts] [$Level] [META] $Msg" -ErrorAction SilentlyContinue
            }

            try {
                Import-Module PnP.PowerShell -ErrorAction Stop
                Connect-PnPOnline -Url $Config.SiteUrl -Interactive `
                                  -ClientId $AppConfig.ClientId -ErrorAction Stop

                $results = [System.Collections.ArrayList]::new()
                $i = 0
                foreach ($ref in $FileRefs) {
                    $i++
                    try {
                        $stream  = Get-PnPFile -Url $ref -AsMemoryStream -ErrorAction Stop
                        $raw     = [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
                        $comment = ""; $tags = @(); $tagsRaw = ""
                        foreach ($line in $raw -split "`r?`n") {
                            $line = $line.TrimEnd()
                            if ($line.StartsWith("##ENGINEERSPOWERAPP#COMMENT#")) {
                                $comment = ($line.Substring(28).Trim()) -replace '\|\|', "`n"
                            } elseif ($line.StartsWith("##ENGINEERSPOWERAPP#TAGS#")) {
                                $tagsRaw = $line.Substring(25).Trim()
                                $tags    = $tagsRaw -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
                            }
                        }
                        [void]$results.Add(@{ FileRef = $ref; Comment = $comment; Tags = $tags; TagsRaw = $tagsRaw })
                    } catch {
                        RS-Log "Could not read $ref : $_" "WARN"
                    }
                }
                RS-Log "Metadata scan complete: $($results.Count) / $($FileRefs.Count) files read"
                return @{ Success = $true; Results = $results.ToArray(); Total = $FileRefs.Count }
            } catch {
                RS-Log "Metadata scan fatal error: $_" "ERROR"
                return @{ Success = $false; Error = $_.ToString() }
            }
        }).AddArgument($Config).AddArgument($AppConfig).AddArgument($fileRefs) | Out-Null

        $async = $ps.BeginInvoke()

        $scanTimer          = [System.Windows.Threading.DispatcherTimer]::new()
        $scanTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $scanTimer.Tag      = @{ Async = $async; PS = $ps; Runspace = $runspace }
        $scanTimer.Add_Tick({
            param($s, $e)
            $ctx = $s.Tag
            if ($ctx.Async.IsCompleted) {
                $s.Stop()
                try {
                    $result = $ctx.PS.EndInvoke($ctx.Async)
                    if ($result.Success) {
                        # Build a lookup and update AllFiles in place
                        $map = @{}
                        foreach ($r in $result.Results) { $map[$r.FileRef] = $r }
                        foreach ($f in $script:AllFiles) {
                            if ($map.ContainsKey($f.FileRef)) {
                                $r = $map[$f.FileRef]
                                # Only overwrite if scan actually found metadata in the file
                                if ($r.Comment -or @($r.Tags).Count -gt 0) {
                                    $f.Comment = $r.Comment
                                    $f.Tags    = $r.Tags
                                    $f.TagsRaw = $r.TagsRaw
                                }
                                $f.ContentLoaded = $true
                            }
                        }
                        Save-Cache $script:AllFiles
                        Update-FileList
                        Set-Status "Metadata scan complete. $($result.Total) files indexed." "#50FA7B"
                        Write-AppLog "SP metadata scan complete."
                    } else {
                        Set-Status "Metadata scan failed: $($result.Error)" "#FF5555"
                    }
                } catch {
                    Write-AppLog "Metadata scan callback error: $_" "ERROR"
                    Set-Status "Metadata scan error: $_" "#FF5555"
                } finally {
                    $ctx.PS.Dispose()
                    $ctx.Runspace.Close()
                }
            }
        })
        $scanTimer.Start()
    }
}

# ============================================================
# CONNECT & REFRESH
# ============================================================
function Start-ConnectAndLoad {
    if ([string]::IsNullOrWhiteSpace($script:Config.SiteUrl) -or
        $script:Config.SiteUrl -like "*YOURCOMPANY*" -or
        $script:Config.SiteUrl -like "*YOURSITE*" -or
        $script:Config.SiteUrl -eq "https://YOURTENANT.sharepoint.com/sites/YOURSITE") {
        [System.Windows.MessageBox]::Show(
            "Please edit the `$script:Config.SiteUrl value at the top of this script with your SharePoint site URL before connecting.",
            "Configuration Required",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        )
        return
    }

    Show-Loading "Connecting to SharePoint...`nPlease complete authentication in the popup window."

    $runspace                = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.Open()

    $ps          = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace
    $Config      = $script:Config
    $AppConfig   = $script:AppConfig

    $ps.AddScript({
        param($Config, $AppConfig)

        function RS-Log {
            param([string]$Msg, [string]$Level = "INFO")
            $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Add-Content -Path $Config.LogFile -Value "[$ts] [$Level] [RS] $Msg" -ErrorAction SilentlyContinue
        }

        try {
            RS-Log "Runspace started. Importing PnP.PowerShell..."
            Import-Module PnP.PowerShell -ErrorAction Stop
            RS-Log "Module imported. Connecting to $($Config.SiteUrl) with ClientId $($AppConfig.ClientId)..."

            Connect-PnPOnline -Url $Config.SiteUrl `
                              -Interactive `
                              -ClientId $AppConfig.ClientId `
                              -ErrorAction Stop
            RS-Log "Connected successfully."

            $lists = Get-PnPList -ErrorAction Stop | Where-Object {
                $_.BaseTemplate -eq 101 -and $_.Hidden -eq $false -and
                $_.Title -notin @("Site Assets","Site Pages","Style Library","Form Templates")
            }
            RS-Log "Found $($lists.Count) document libraries: $(($lists | Select-Object -ExpandProperty Title) -join ', ')"

            # Return as a plain array of hashtables.
            # PSCustomObjects inside a Generic List do not survive the runspace
            # boundary cleanly in PS7 — hashtables do.
            $allFiles = [System.Collections.ArrayList]::new()

            foreach ($lib in $lists) {
                RS-Log "Scanning library: $($lib.Title)"
                try {
                    # Fetch all items then filter client-side.
                    # CAML Contains on FileLeafRef is unreliable on some SPO tenants.
                    $items = Get-PnPListItem -List $lib -PageSize 500 `
                                             -Fields "FileLeafRef","FileRef","Created","Modified","Author","Editor","File_x0020_Size","FileDirRef","FSObjType" `
                                             -ErrorAction Stop

                    $scriptItems = @($items | Where-Object {
                        $_["FSObjType"] -eq 0 -and
                        (
                            $_["FileLeafRef"] -like "*.ps1" -or
                            $_["FileLeafRef"] -like "*.bat"
                        )
                    })

                    RS-Log "  $($lib.Title): $($items.Count) total items, $($scriptItems.Count) script files"

                    foreach ($item in $scriptItems) {
                        $name = $item["FileLeafRef"]
                        $ext  = [System.IO.Path]::GetExtension($name).ToLower()

                        $authorVal  = $item["Author"]
                        $editorVal  = $item["Editor"]
                        $authorName = if ($authorVal  -and $authorVal.LookupValue)  { $authorVal.LookupValue  } else { "" }
                        $editorName = if ($editorVal  -and $editorVal.LookupValue)  { $editorVal.LookupValue  } else { "" }

                        [void]$allFiles.Add(@{
                            Name           = $name
                            FileRef        = "$($item["FileRef"])"
                            Library        = $lib.Title
                            FolderPath     = "$($item["FileDirRef"])"
                            Created        = if ($item["Created"])  { $item["Created"].ToString("o")  } else { $null }
                            Modified       = if ($item["Modified"]) { $item["Modified"].ToString("o") } else { $null }
                            Author         = $authorName
                            LastModifiedBy = $editorName
                            SizeBytes      = $item["File_x0020_Size"]
                            Extension      = $ext
                            ItemId         = $item.Id
                            Comment        = ""
                            Tags           = @()
                            TagsRaw        = ""
                            ContentLoaded  = $false
                        })
                    }
                } catch {
                    RS-Log "Error scanning library '$($lib.Title)': $_" "WARN"
                }
            }

            RS-Log "Scan complete. Total script files found: $($allFiles.Count)"
            return @{ Success = $true; Files = $allFiles.ToArray(); Count = $allFiles.Count }
        } catch {
            RS-Log "Fatal runspace error: $_" "ERROR"
            return @{ Success = $false; Error = $_.ToString() }
        }
    }).AddArgument($Config).AddArgument($AppConfig) | Out-Null


    $async = $ps.BeginInvoke()

    # Bundle all references into the timer's Tag so the Add_Tick closure can
    # reliably reach them in PS7 — local variables are not captured by scriptblocks
    # attached to event handlers the same way as in regular closures.
    $timer          = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    $timer.Tag      = @{
        Async    = $async
        PS       = $ps
        Runspace = $runspace
    }
    $timer.Add_Tick({
        param($timerSender, $e)
        $ctx = $timerSender.Tag
        if ($ctx.Async.IsCompleted) {
            $timerSender.Stop()
            try {
                $result = $ctx.PS.EndInvoke($ctx.Async)
                Write-AppLog "Runspace returned. Success=$($result.Success) Count=$($result.Count)"

                if ($result.Success) {
                    # Runspace returns an array of hashtables. Convert each back to
                    # a PSCustomObject so the rest of the app can use dot-notation.
                    $script:AllFiles = [System.Collections.Generic.List[PSObject]]::new()
                    foreach ($ht in $result.Files) {
                        $script:AllFiles.Add([PSCustomObject]@{
                            Name           = $ht.Name
                            FileRef        = $ht.FileRef
                            Library        = $ht.Library
                            FolderPath     = $ht.FolderPath
                            Created        = if ($ht.Created)  { [datetime]$ht.Created  } else { $null }
                            Modified       = if ($ht.Modified) { [datetime]$ht.Modified } else { $null }
                            Author         = $ht.Author
                            LastModifiedBy = $ht.LastModifiedBy
                            SizeBytes      = $ht.SizeBytes
                            Extension      = $ht.Extension
                            ItemId         = $ht.ItemId
                            Comment        = ""
                            Tags           = @()
                            TagsRaw        = ""
                            ContentLoaded  = $false
                        })
                    }

                    Write-AppLog "Converted $($script:AllFiles.Count) file objects."
                    $script:IsConnected = $true

                    $cache = Load-Cache
                    if ($null -ne $cache) {
                        $cacheMap = @{}
                        # Skip any corrupt cache entries that have a null FileRef
                        foreach ($cf in $cache.Files) {
                            if (-not [string]::IsNullOrEmpty($cf.FileRef)) {
                                $cacheMap[$cf.FileRef] = $cf
                            }
                        }
                        foreach ($f in $script:AllFiles) {
                            if (-not [string]::IsNullOrEmpty($f.FileRef) -and $cacheMap.ContainsKey($f.FileRef)) {
                                $cached    = $cacheMap[$f.FileRef]
                                $f.Comment = if ($cached.Comment) { $cached.Comment } else { "" }
                                $f.Tags    = if ($cached.Tags)    { @($cached.Tags) } else { @() }
                                $f.TagsRaw = if ($cached.TagsRaw) { $cached.TagsRaw } else { "" }
                            }
                        }
                    }
                    Write-AppLog "Cache merge complete. Saving $($script:AllFiles.Count) files..."
                    Save-Cache $script:AllFiles

                    $TxtConnectionStatus.Text       = "[OK] Connected"
                    $TxtConnectionStatus.Foreground = "#50FA7B"
                    $BtnRefresh.IsEnabled           = $true
                    $TxtCacheInfo.Text              = "Last scan: $(Get-Date -Format 'h:mmtt')"

                    Update-FileList
                    Update-ModeButtons
                    Set-Status "Connected. $($script:AllFiles.Count) script files found." "#50FA7B"

                    # Kick off background metadata scan to populate tags/comments for all files
                    Start-MetadataScan
                } else {
                    Set-Status "Connection failed: $($result.Error)" "#FF5555"
                    [System.Windows.MessageBox]::Show(
                        "Failed to connect to SharePoint:`n$($result.Error)",
                        "Connection Error",
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error
                    )
                }
            } catch {
                Write-AppLog "Timer callback error: $_" "ERROR"
                Set-Status "Error: $_" "#FF5555"
            } finally {
                Hide-Loading
                $ctx.PS.Dispose()
                $ctx.Runspace.Close()
            }
        }
    })
    $timer.Start()
}

# ============================================================
# LOAD FROM CACHE (offline / fast startup)
# ============================================================
function Load-FromCache {
    $cache = Load-Cache
    if ($null -eq $cache) {
        Set-Status "No cache found. Connect to SharePoint to load files." "#6272A4"
        return
    }

    $script:AllFiles   = $cache.Files
    $script:DataSource = "sharepoint"
    $cacheAge = [datetime]::Now - $cache.Timestamp
    $ageStr   = if ($cacheAge.TotalHours -lt 1) {
        "$([int]$cacheAge.TotalMinutes)m ago"
    } elseif ($cacheAge.TotalDays -lt 1) {
        "$([int]$cacheAge.TotalHours)h ago"
    } else {
        "$([int]$cacheAge.TotalDays)d ago"
    }

    $TxtCacheInfo.Text = "Cached: $ageStr"
    Update-FileList
    Set-Status "Loaded $($cache.Files.Count) files from cache ($ageStr). Connect to refresh." "#FFB86C"
}

# ============================================================
# EVENT HANDLERS
# ============================================================

$BtnOpenGitRepo.Add_Click({ Start-OpenGitRepo })
$BtnConnect.Add_Click({ Start-ConnectAndLoad })

$BtnRefresh.Add_Click({
    if ($script:DataSource -eq "git") { Start-OpenGitRepo }
    else { Start-ConnectAndLoad }
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

$BtnLoadContent.Add_Click({ Load-SelectedFileContent })
$BtnOpenVSCode.Add_Click({ Open-InVSCode })
$BtnOpenWebDAV.Add_Click({ Open-ViaWebDAV })

$BtnCopyPath.Add_Click({
    if ($null -ne $script:SelectedFile) {
        [System.Windows.Clipboard]::SetText($script:SelectedFile.FileRef)
        Set-Status "Path copied to clipboard" "#50FA7B"
    }
})
$BtnCopyUrl.Add_Click({
    if ($null -ne $script:SelectedFile) {
        [System.Windows.Clipboard]::SetText("$($script:Config.SiteUrl)$($script:SelectedFile.FileRef)")
        Set-Status "Full URL copied to clipboard" "#50FA7B"
    }
})

$BtnRename.Add_Click({ Rename-SelectedFile })
$BtnSaveMetadata.Add_Click({ Save-SelectedFileMetadata })

$BtnTagAutomation.Add_Click({ Add-QuickTag "automation" })
$BtnTagMaintenance.Add_Click({ Add-QuickTag "maintenance" })
$BtnTagDeploy.Add_Click({ Add-QuickTag "deployment" })
$BtnTagMonitor.Add_Click({ Add-QuickTag "monitoring" })
$BtnTagIsFunction.Add_Click({ Add-QuickTag "isFunction" })
$BtnTagIsApp.Add_Click({ Add-QuickTag "isApp" })
$BtnTagPS7.Add_Click({ Add-QuickTag "PowerShell 7" })
$BtnTagSecurity.Add_Click({ Add-QuickTag "security" })
$BtnTagUtil.Add_Click({ Add-QuickTag "utility" })

$TxtComment.Add_TextChanged({ $TxtSaveStatus.Text = "" })
$TxtTags.Add_TextChanged({ $TxtSaveStatus.Text = "" })

$Window.Add_Closing({
    try { Disconnect-PnPOnline -ErrorAction SilentlyContinue } catch {}
    Write-AppLog "Application closed"
})

# ============================================================
# STARTUP
# ============================================================
Write-AppLog "Engineers PowerApp v$($script:Config.AppVersion) starting"

# Config file check — show first-run wizard if config.json is missing
if (-not (Load-AppConfig)) {
    Write-AppLog "No config.json found — launching first-run wizard."
    Show-FirstRunWizard
}

if (-not (Test-PnPModule)) {
    Write-AppLog "PnP.PowerShell module not available. Exiting." "ERROR"
    exit 1
}

# Load whichever cache exists — git takes priority if both are present.
# The user can switch modes manually via the Connect / Open Git Repo buttons.
if (Test-Path $script:Config.GitCacheFile) {
    $gitCache = Load-GitCache
    if ($null -ne $gitCache -and $gitCache.Files.Count -gt 0) {
        $script:AllFiles   = $gitCache.Files
        $script:DataSource = "git"
        $TxtConnectionStatus.Text       = "[G] Git Repo (cached)"
        $TxtConnectionStatus.Foreground = "#FFB86C"
        $BtnRefresh.IsEnabled           = $true
        $TxtCacheInfo.Text              = "Cached: $($gitCache.Timestamp.ToString('g'))"
        Update-FileList
        Write-AppLog "Startup: loaded git cache ($($gitCache.Files.Count) files)"
    } else {
        Load-FromCache
    }
} else {
    Load-FromCache
}

# ============================================================
# SHOW WINDOW
# ============================================================
$Window.ShowDialog() | Out-Null
