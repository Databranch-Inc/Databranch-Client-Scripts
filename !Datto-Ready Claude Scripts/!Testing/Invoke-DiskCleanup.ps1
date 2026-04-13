#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Targeted safe disk cleanup for Windows 11 domain workstations.

.DESCRIPTION
    Cleans known-safe locations including Windows Temp, user AppData Temp,
    SoftwareDistribution\Download, Edge cache, INetCache, and WinSxS reclaimable
    packages. Generates a before/after HTML report and a Roaming AppData size audit.
    Skips PST files, OneDrive, and user data.

.PARAMETER UserProfile
    Target user profile path. Defaults to $env:USERPROFILE.

.PARAMETER ReportPath
    Path to save the HTML report. Defaults to desktop.

.PARAMETER WhatIf
    Preview what would be deleted without making changes.

.EXAMPLE
    .\Invoke-DiskCleanup.ps1

.EXAMPLE
    .\Invoke-DiskCleanup.ps1 -WhatIf

.EXAMPLE
    .\Invoke-DiskCleanup.ps1 -ReportPath "C:\Temp\CleanupReport.html"

.NOTES
    Author:     Sam Kirsch / Databranch
    Version:    1.0.0.0
    Created:    2026-03-30
    
    Version History:
    v1.0.0.0 - 2026-03-30 - Initial release. Safe cleanup of Temp, SoftwareDistribution,
                             Edge cache, INetCache, WinSxS reclaimable packages.
                             Roaming AppData audit (report-only). HTML output report.
#>

function Invoke-DiskCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$UserProfile = $env:USERPROFILE,

        [Parameter()]
        [string]$ReportPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DiskCleanup_Report.html')
    )

    # SupportsShouldProcess provides -WhatIf automatically; map to a local bool for readability
    $IsWhatIf = [bool]$WhatIfPreference

    #region -- Helpers ----------------------------------------------------------

    function Get-FolderSize {
        param([string]$Path)
        if (-not (Test-Path $Path)) { return 0 }
        (Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    }

    function Format-Bytes {
        param([long]$Bytes)
        switch ($Bytes) {
            { $_ -ge 1GB } { return '{0:N2} GB' -f ($_ / 1GB) }
            { $_ -ge 1MB } { return '{0:N2} MB' -f ($_ / 1MB) }
            { $_ -ge 1KB } { return '{0:N2} KB' -f ($_ / 1KB) }
            default        { return '{0} B'     -f $_ }
        }
    }

    function Remove-SafeFolder {
        param([string]$Path, [string]$Label)
        if (-not (Test-Path $Path)) {
            Write-Host "  [SKIP] $Label -- path not found" -ForegroundColor DarkGray
            return 0
        }
        $before = Get-FolderSize $Path
        if ($IsWhatIf) {
            Write-Host "  [WHATIF] $Label -- would remove $(Format-Bytes $before)" -ForegroundColor Cyan
            return $before
        }
        Write-Host "  [CLEAN] $Label ($(Format-Bytes $before))..." -ForegroundColor Yellow
        Get-ChildItem $Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $after  = Get-FolderSize $Path
        $freed  = $before - $after
        Write-Host "         Freed: $(Format-Bytes $freed)" -ForegroundColor Green
        return $freed
    }

    #endregion

    #region -- Targets ----------------------------------------------------------

    $targets = @(
        @{
            Label = 'Windows Temp (C:\Windows\Temp)'
            Path  = 'C:\Windows\Temp'
        }
        @{
            Label = 'Windows SystemTemp (C:\Windows\SystemTemp)'
            Path  = 'C:\Windows\SystemTemp'
        }
        @{
            Label = 'SoftwareDistribution\Download'
            Path  = 'C:\Windows\SoftwareDistribution\Download'
        }
        @{
            Label = 'User AppData\Local\Temp'
            Path  = Join-Path $UserProfile 'AppData\Local\Temp'
        }
        @{
            Label = 'User INetCache'
            Path  = Join-Path $UserProfile 'AppData\Local\Microsoft\Windows\INetCache'
        }
        @{
            Label = 'User INetCookies'
            Path  = Join-Path $UserProfile 'AppData\Local\Microsoft\Windows\INetCookies'
        }
        @{
            Label = 'Edge Browser Cache'
            Path  = Join-Path $UserProfile 'AppData\Local\Microsoft\Edge\User Data\Default\Cache'
        }
        @{
            Label = 'Edge Browser Code Cache'
            Path  = Join-Path $UserProfile 'AppData\Local\Microsoft\Edge\User Data\Default\Code Cache'
        }
        @{
            Label = 'Edge GPU Cache'
            Path  = Join-Path $UserProfile 'AppData\Local\Microsoft\Edge\User Data\Default\GPUCache'
        }
        @{
            Label = 'Windows Error Reporting (User)'
            Path  = Join-Path $UserProfile 'AppData\Local\Microsoft\Windows\WER'
        }
        @{
            Label = 'Windows Error Reporting (System)'
            Path  = 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue'
        }
        @{
            Label = 'CrashDumps (User)'
            Path  = Join-Path $UserProfile 'AppData\Local\CrashDumps'
        }
        @{
            Label = 'Temporary Internet Files (Legacy IE/WebView)'
            Path  = Join-Path $UserProfile 'AppData\Local\Microsoft\Windows\Temporary Internet Files'
        }
        @{
            Label = 'Windows Logs\CBS'
            Path  = 'C:\Windows\Logs\CBS'
        }
    )

    #endregion

    #region -- Pre-flight snapshot ----------------------------------------------

    Write-Host "`n--------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Invoke-DiskCleanup v1.0.0.0" -ForegroundColor Cyan
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    if ($IsWhatIf) { Write-Host "  *** WHATIF MODE -- No files will be deleted ***" -ForegroundColor Magenta }
    Write-Host "--------------------------------------------`n" -ForegroundColor Cyan

    $drive         = Split-Path $UserProfile -Qualifier
    $diskBefore    = (Get-PSDrive ($drive.TrimEnd(':'))).Free
    $results       = [System.Collections.Generic.List[PSCustomObject]]::new()
    $totalFreed    = 0L

    #endregion

    #region -- Stop Windows Update service (needed for SoftwareDistribution) ---

    $wuWasRunning = $false
    if (-not $IsWhatIf) {
        $wuSvc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($wuSvc -and $wuSvc.Status -eq 'Running') {
            Write-Host "[INFO] Stopping Windows Update service temporarily..." -ForegroundColor DarkYellow
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            $wuWasRunning = $true
        }
    }

    #endregion

    #region -- Main cleanup loop ------------------------------------------------

    Write-Host "`n[PHASE 1] Cleaning safe cache and temp locations...`n" -ForegroundColor White

    foreach ($t in $targets) {
        $before = Get-FolderSize $t.Path
        $freed  = Remove-SafeFolder -Path $t.Path -Label $t.Label
        $totalFreed += $freed
        $results.Add([PSCustomObject]@{
            Label   = $t.Label
            Before  = $before
            Freed   = $freed
            Skipped = ($freed -eq 0 -and -not (Test-Path $t.Path))
        })
    }

    #endregion

    #region -- Restart Windows Update -------------------------------------------

    if ($wuWasRunning -and -not $IsWhatIf) {
        Write-Host "`n[INFO] Restarting Windows Update service..." -ForegroundColor DarkYellow
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    }

    #endregion

    #region -- WinSxS Component Cleanup -----------------------------------------

    Write-Host "`n[PHASE 2] Running DISM Component Store cleanup (reclaimable packages)...`n" -ForegroundColor White

    $dismResult = 'Skipped (WhatIf mode)'
    if (-not $IsWhatIf) {
        Write-Host "  [DISM] /StartComponentCleanup -- this may take several minutes..." -ForegroundColor Yellow
        $dismOutput = & dism /Online /Cleanup-Image /StartComponentCleanup 2>&1
        $dismResult = if ($LASTEXITCODE -eq 0) { 'Completed successfully' } else { "Exit code: $LASTEXITCODE" }
        Write-Host "  [DISM] $dismResult" -ForegroundColor Green
    } else {
        Write-Host "  [WHATIF] DISM /StartComponentCleanup would run here" -ForegroundColor Cyan
    }

    #endregion

    #region -- Roaming AppData Audit (report-only) ------------------------------

    Write-Host "`n[PHASE 3] Auditing AppData\Roaming (report only -- nothing deleted)...`n" -ForegroundColor White

    $roamingPath  = Join-Path $UserProfile 'AppData\Roaming'
    $roamingAudit = [System.Collections.Generic.List[PSCustomObject]]::new()

    if (Test-Path $roamingPath) {
        Get-ChildItem $roamingPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $sz = Get-FolderSize $_.FullName
            if ($sz -gt 1MB) {
                $roamingAudit.Add([PSCustomObject]@{
                    Folder  = $_.Name
                    'Size'  = $sz
                    'SizeFmt' = Format-Bytes $sz
                })
                Write-Host ("  {0,-45} {1}" -f $_.Name, (Format-Bytes $sz))
            }
        }
        $roamingAudit = $roamingAudit | Sort-Object Size -Descending
    }

    #endregion

    #region -- Summary -----------------------------------------------------------

    $diskAfter  = (Get-PSDrive ($drive.TrimEnd(':'))).Free
    $actualFreed = $diskAfter - $diskBefore

    Write-Host "`n--------------------------------------------" -ForegroundColor Green
    Write-Host "  CLEANUP COMPLETE" -ForegroundColor Green
    Write-Host "  Targeted freed : $(Format-Bytes $totalFreed)" -ForegroundColor Green
    Write-Host "  Actual disk freed : $(Format-Bytes $actualFreed)" -ForegroundColor Green
    Write-Host "  Drive free now : $(Format-Bytes $diskAfter)" -ForegroundColor Green
    Write-Host "--------------------------------------------`n" -ForegroundColor Green

    #endregion

    #region -- HTML Report -------------------------------------------------------

    $timestamp   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $hostname    = $env:COMPUTERNAME
    $modeLabel   = if ($IsWhatIf) { '<span style="color:#f59e0b">[!] WhatIf Mode</span>' } else { '<span style="color:#22c55e">[OK] Live Run</span>' }

    $cleanupRows = ($results | ForEach-Object {
        $status = if ($_.Skipped) { '<span class="badge skip">Skipped</span>' }
                  elseif ($_.Freed -gt 0) { '<span class="badge freed">Cleaned</span>' }
                  else { '<span class="badge empty">Empty</span>' }
        "<tr><td>$($_.Label)</td><td>$(Format-Bytes $_.Before)</td><td class='freed-cell'>$(Format-Bytes $_.Freed)</td><td>$status</td></tr>"
    }) -join "`n"

    $roamingRows = if ($roamingAudit.Count -gt 0) {
        ($roamingAudit | ForEach-Object {
            "<tr><td>$($_.Folder)</td><td>$($_.SizeFmt)</td></tr>"
        }) -join "`n"
    } else { '<tr><td colspan="2">No folders over 1MB found or path unavailable.</td></tr>' }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Disk Cleanup Report -- $hostname</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@300;400;600&display=swap');
  :root {
    --bg: #0d1117; --surface: #161b22; --border: #30363d;
    --text: #c9d1d9; --muted: #6e7681; --accent: #58a6ff;
    --green: #3fb950; --yellow: #d29922; --red: #f85149;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--text); font-family: 'IBM Plex Sans', sans-serif;
         font-size: 14px; line-height: 1.6; padding: 32px; }
  h1 { font-family: 'IBM Plex Mono', monospace; font-size: 22px; color: var(--accent);
       border-bottom: 1px solid var(--border); padding-bottom: 12px; margin-bottom: 24px; }
  h2 { font-family: 'IBM Plex Mono', monospace; font-size: 14px; color: var(--muted);
       text-transform: uppercase; letter-spacing: 0.1em; margin: 32px 0 12px; }
  .meta { display: flex; gap: 32px; margin-bottom: 28px; flex-wrap: wrap; }
  .meta-item { background: var(--surface); border: 1px solid var(--border); border-radius: 6px;
               padding: 12px 20px; }
  .meta-item .label { font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: .08em; }
  .meta-item .value { font-family: 'IBM Plex Mono', monospace; font-size: 18px; color: var(--accent); margin-top: 2px; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 32px; }
  th { background: var(--surface); color: var(--muted); font-size: 11px; text-transform: uppercase;
       letter-spacing: .08em; padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--border); }
  td { padding: 9px 14px; border-bottom: 1px solid var(--border); font-family: 'IBM Plex Mono', monospace; font-size: 13px; }
  tr:hover td { background: var(--surface); }
  .freed-cell { color: var(--green); font-weight: 600; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 11px;
           font-family: 'IBM Plex Sans', sans-serif; font-weight: 600; }
  .badge.freed { background: rgba(63,185,80,.15); color: var(--green); }
  .badge.skip  { background: rgba(110,118,129,.15); color: var(--muted); }
  .badge.empty { background: rgba(210,153,34,.1); color: var(--yellow); }
  .dism-result { background: var(--surface); border: 1px solid var(--border); border-radius: 6px;
                 padding: 12px 16px; font-family: 'IBM Plex Mono', monospace; font-size: 13px;
                 color: var(--green); margin-bottom: 32px; }
  .footer { color: var(--muted); font-size: 11px; margin-top: 48px; border-top: 1px solid var(--border); padding-top: 16px; }
</style>
</head>
<body>
<h1>! Disk Cleanup Report</h1>

<div class="meta">
  <div class="meta-item"><div class="label">Host</div><div class="value">$hostname</div></div>
  <div class="meta-item"><div class="label">User Profile</div><div class="value">$($UserProfile | Split-Path -Leaf)</div></div>
  <div class="meta-item"><div class="label">Run Time</div><div class="value" style="font-size:14px">$timestamp</div></div>
  <div class="meta-item"><div class="label">Mode</div><div class="value" style="font-size:14px">$modeLabel</div></div>
  <div class="meta-item"><div class="label">Targeted Freed</div><div class="value">$(Format-Bytes $totalFreed)</div></div>
  <div class="meta-item"><div class="label">Actual Drive Freed</div><div class="value">$(Format-Bytes $actualFreed)</div></div>
  <div class="meta-item"><div class="label">Drive Free After</div><div class="value">$(Format-Bytes $diskAfter)</div></div>
</div>

<h2>Phase 1 -- Cache &amp; Temp Cleanup</h2>
<table>
  <thead><tr><th>Location</th><th>Before</th><th>Freed</th><th>Status</th></tr></thead>
  <tbody>$cleanupRows</tbody>
</table>

<h2>Phase 2 -- WinSxS Component Store (DISM)</h2>
<div class="dism-result">$dismResult</div>

<h2>Phase 3 -- AppData\Roaming Audit (Report Only -- Nothing Deleted)</h2>
<table>
  <thead><tr><th>Folder</th><th>Size</th></tr></thead>
  <tbody>$roamingRows</tbody>
</table>

<div class="footer">Invoke-DiskCleanup v1.0.0.0 -- Sam Kirsch / Databranch -- PST, OneDrive, and user data were not modified.</div>
</body>
</html>
"@

    $html | Out-File -FilePath $ReportPath -Encoding UTF8 -Force
    Write-Host "[REPORT] Saved to: $ReportPath" -ForegroundColor Cyan
    Start-Process $ReportPath

    #endregion
}

# -- Entry point ----------------------------------------------------------------
Invoke-DiskCleanup @PSBoundParameters
