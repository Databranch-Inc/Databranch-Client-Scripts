#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnoses Quick Access pin loss on Windows 11 workstations with folder redirection.

.DESCRIPTION
    Collects targeted diagnostics to identify the root cause of Quick Access pins
    disappearing on a Sunday/Monday schedule. Checks:
      - Recent reboot/logon/logoff events (System + Security log)
      - AutomaticDestinations file timestamps and content
      - Offline Files / CSC configuration and sync status
      - Folder redirection GPO settings (effective)
      - Connectwise Automate / LabTech agent scheduled tasks and maintenance windows
      - Scheduled tasks that could touch the shell or profile
      - Shell bag and Explorer registry state
      - Network availability at logon (event 6005/Winlogon)

.PARAMETER OutputPath
    Path to write the HTML report. Defaults to Desktop.

.PARAMETER DaysBack
    How many days of event log history to pull. Default: 14.

.EXAMPLE
    .\Get-QuickAccessDiagnostics.ps1
    .\Get-QuickAccessDiagnostics.ps1 -OutputPath "C:\Temp\report.html" -DaysBack 30

.NOTES
    Version:    1.0.0.1
    Author:     DataBranch
    Created:    2025-01-01
    
    Run as the AFFECTED USER (not admin) to capture the correct AppData paths,
    then re-run as admin to capture the full event log and scheduled task data.
    Ideally run BOTH and compare.

    Version History:
    1.0.0.1 - Initial release
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "$env:USERPROFILE\Desktop\QuickAccess_Diagnostics_$(Get-Date -Format 'yyyyMMdd_HHmmss').html",
    [int]$DaysBack = 14
)

function Get-QuickAccessDiagnostics {

    $StartTime = (Get-Date).AddDays(-$DaysBack)
    $Results   = [ordered]@{}
    $IsAdmin   = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    Write-Host "[*] Starting Quick Access diagnostics (Running as $(if($IsAdmin){'ADMIN'}else{'USER'}))" -ForegroundColor Cyan
    Write-Host "[*] Collecting last $DaysBack days of data..." -ForegroundColor Cyan

    # -------------------------------------------------------------------------
    # 1. System Info
    # -------------------------------------------------------------------------
    Write-Host "[*] Gathering system info..." -ForegroundColor Yellow
    $Results['SystemInfo'] = [PSCustomObject]@{
        ComputerName    = $env:COMPUTERNAME
        CurrentUser     = $env:USERNAME
        OS              = (Get-CimInstance Win32_OperatingSystem).Caption
        Build           = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
        UBR             = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR
        LastBoot        = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        RunningAsAdmin  = $IsAdmin
        ReportGenerated = Get-Date
    }

    # -------------------------------------------------------------------------
    # 2. AutomaticDestinations - Quick Access pin database
    # -------------------------------------------------------------------------
    Write-Host "[*] Checking AutomaticDestinations (Quick Access database)..." -ForegroundColor Yellow
    $AutoDestPath = "$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations"
    $QAFile       = Join-Path $AutoDestPath "f01b4d95cf55d32a.automaticDestinations-ms"

    $Results['AutomaticDestinations'] = [PSCustomObject]@{
        FolderPath      = $AutoDestPath
        FolderExists    = Test-Path $AutoDestPath
        QAFileExists    = Test-Path $QAFile
        QAFileLastWrite = if (Test-Path $QAFile) { (Get-Item $QAFile).LastWriteTime } else { "NOT FOUND" }
        QAFileLastWriteDayOfWeek = if (Test-Path $QAFile) { (Get-Item $QAFile).LastWriteTime.DayOfWeek } else { "N/A" }
        QAFileSizeBytes = if (Test-Path $QAFile) { (Get-Item $QAFile).Length } else { 0 }
        AllFiles        = if (Test-Path $AutoDestPath) {
                            Get-ChildItem $AutoDestPath | Sort-Object LastWriteTime |
                                Select-Object Name, LastWriteTime, Length
                          } else { @() }
    }

    # -------------------------------------------------------------------------
    # 3. Folder Redirection - effective paths
    # -------------------------------------------------------------------------
    Write-Host "[*] Checking folder redirection paths..." -ForegroundColor Yellow
    $ShellFolders = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -ErrorAction SilentlyContinue
    $UserShellFolders = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue

    $RedirectKeys = @('Desktop','Personal','My Pictures','My Music','My Video','{374DE290-123F-4565-9164-39C4925E467B}')
    $RedirectionResults = foreach ($key in $RedirectKeys) {
        $actual  = $ShellFolders.$key
        $policy  = $UserShellFolders.$key
        [PSCustomObject]@{
            FolderName      = $key
            ActualPath      = $actual
            PolicyPath      = $policy
            IsRedirected    = ($actual -match '^[A-Z]:\\' -and $actual -notmatch [regex]::Escape($env:USERPROFILE)) -or ($actual -match '^\\\\')
            PathReachable   = if ($actual) { Test-Path $actual } else { $false }
        }
    }
    $Results['FolderRedirection'] = $RedirectionResults

    # -------------------------------------------------------------------------
    # 4. Offline Files / CSC Status
    # -------------------------------------------------------------------------
    Write-Host "[*] Checking Offline Files / CSC configuration..." -ForegroundColor Yellow
    $CSCPolicy = Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetCache" -ErrorAction SilentlyContinue
    $CSCUser   = Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\NetCache" -ErrorAction SilentlyContinue
    $CSCService = Get-Service -Name CscService -ErrorAction SilentlyContinue

    # Check if Offline Files is enabled via WMI
    $OfflineFilesEnabled = $false
    try {
        $cscConfig = Get-CimInstance -Namespace "root\cimv2" -ClassName "Win32_OfflineFilesCache" -ErrorAction SilentlyContinue
        $OfflineFilesEnabled = $cscConfig -ne $null
    } catch {}

    $Results['OfflineFiles'] = [PSCustomObject]@{
        ServiceStatus           = $CSCService.Status
        ServiceStartType        = $CSCService.StartType
        PolicyEnabled           = $CSCPolicy.Enabled
        PolicyNoCache           = $CSCPolicy.NoCacheViewer
        PolicySyncAtLogon       = $CSCPolicy.SyncAtLogon
        PolicySyncAtLogoff      = $CSCPolicy.SyncAtLogoff
        PolicyBackgroundSync    = $CSCPolicy.BackgroundSync
        UserCacheEnabled        = $CSCUser.Enabled
        OfflineFilesAPIEnabled  = $OfflineFilesEnabled
        RawPolicyKeys           = $CSCPolicy | Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSProvider,PSDrive
    }

    # -------------------------------------------------------------------------
    # 5. System Event Log - Reboots, shutdowns, power events
    # -------------------------------------------------------------------------
    Write-Host "[*] Pulling System event log (reboots/power events)..." -ForegroundColor Yellow
    $RebootEventIDs = @(1074, 6005, 6006, 6008, 41, 109)
    try {
        $RebootEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Id        = $RebootEventIDs
            StartTime = $StartTime
        } -ErrorAction SilentlyContinue |
        Select-Object TimeCreated,
                      @{N='DayOfWeek';E={$_.TimeCreated.DayOfWeek}},
                      Id,
                      @{N='EventType';E={
                          switch ($_.Id) {
                              1074  { "Shutdown/Restart Initiated" }
                              6005  { "Event Log Started (Boot)" }
                              6006  { "Event Log Stopped (Shutdown)" }
                              6008  { "Unexpected Shutdown" }
                              41    { "Kernel Power - Unexpected Reboot" }
                              109   { "Kernel Power - Reboot" }
                              default { "Unknown" }
                          }
                      }},
                      Message |
        Sort-Object TimeCreated
    } catch {
        $RebootEvents = @([PSCustomObject]@{ Error = $_.Exception.Message })
    }
    $Results['RebootEvents'] = $RebootEvents

    # -------------------------------------------------------------------------
    # 6. Security Event Log - Logon/Logoff events
    # -------------------------------------------------------------------------
    Write-Host "[*] Pulling Security event log (logon/logoff for affected user)..." -ForegroundColor Yellow
    if ($IsAdmin) {
        $LogonEventIDs = @(4624, 4634, 4647, 4800, 4801)
        try {
            $LogonEvents = Get-WinEvent -FilterHashtable @{
                LogName   = 'Security'
                Id        = $LogonEventIDs
                StartTime = $StartTime
            } -ErrorAction SilentlyContinue |
            Where-Object {
                $xml = [xml]$_.ToXml()
                $user = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
                $user -eq $env:USERNAME -or $user -match $env:USERNAME
            } |
            Select-Object TimeCreated,
                          @{N='DayOfWeek';E={$_.TimeCreated.DayOfWeek}},
                          Id,
                          @{N='EventType';E={
                              switch ($_.Id) {
                                  4624 { "Logon" }
                                  4634 { "Logoff" }
                                  4647 { "User Initiated Logoff" }
                                  4800 { "Workstation Locked" }
                                  4801 { "Workstation Unlocked" }
                                  default { "Unknown" }
                              }
                          }},
                          Message |
            Sort-Object TimeCreated
        } catch {
            $LogonEvents = @([PSCustomObject]@{ Error = $_.Exception.Message })
        }
    } else {
        $LogonEvents = @([PSCustomObject]@{ Note = "Re-run as Administrator to capture Security log events." })
    }
    $Results['LogonEvents'] = $LogonEvents

    # -------------------------------------------------------------------------
    # 7. Application Event Log - Explorer / Shell crashes
    # -------------------------------------------------------------------------
    Write-Host "[*] Checking Application log for Explorer/shell errors..." -ForegroundColor Yellow
    try {
        $AppEvents = Get-WinEvent -FilterHashtable @{
            LogName   = 'Application'
            StartTime = $StartTime
        } -ErrorAction SilentlyContinue |
        Where-Object { $_.ProviderName -match 'Explorer|Shell|Desktop Window Manager|dwm|Winlogon|userinit' -or
                       $_.Message -match 'explorer\.exe|shell32|AutomaticDestinations' } |
        Select-Object TimeCreated,
                      @{N='DayOfWeek';E={$_.TimeCreated.DayOfWeek}},
                      Id, ProviderName, LevelDisplayName, Message |
        Sort-Object TimeCreated
    } catch {
        $AppEvents = @([PSCustomObject]@{ Error = $_.Exception.Message })
    }
    $Results['AppEvents'] = $AppEvents

    # -------------------------------------------------------------------------
    # 8. Scheduled Tasks - anything touching the shell or running on weekend
    # -------------------------------------------------------------------------
    Write-Host "[*] Enumerating scheduled tasks (weekend triggers + shell-related)..." -ForegroundColor Yellow
    try {
        $AllTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
        $InterestingTasks = $AllTasks | Where-Object {
            $t = $_
            # Tasks with weekly/sunday triggers
            $hasSundayTrigger = $t.Triggers | Where-Object {
                ($_ -is [Microsoft.Management.Infrastructure.CimInstance]) -and
                ($_.CimClass.CimClassName -match 'Weekly|Daily|Boot|Logon') 
            }
            # Tasks related to known management agents or shell
            $isManagementTask = $t.TaskPath -match 'Automate|LabTech|Connectwise|CW|LT|Kaseya|Datto' -or
                                $t.TaskName -match 'Automate|LabTech|Connectwise|CW |LT |Maintenance|Patch|Update|Shell|Explorer|Profile'
            $hasSundayTrigger -or $isManagementTask
        } |
        Select-Object TaskName, TaskPath, State,
                      @{N='LastRunTime';E={$_.LastRunTime}},
                      @{N='NextRunTime';E={$_.NextRunTime}},
                      @{N='LastResult'; E={$_.LastTaskResult}},
                      @{N='Triggers';   E={($_.Triggers | ForEach-Object { $_.CimClass.CimClassName }) -join ', '}},
                      @{N='Actions';    E={($_.Actions  | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' | '}} |
        Sort-Object TaskPath, TaskName
    } catch {
        $InterestingTasks = @([PSCustomObject]@{ Error = $_.Exception.Message })
    }
    $Results['ScheduledTasks'] = $InterestingTasks

    # All CW Automate / LabTech tasks specifically
    try {
        $LTTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskPath -match 'Automate|LabTech|CW|LT' -or
                           $_.TaskName -match 'Automate|LabTech|CW|LT' } |
            Select-Object TaskName, TaskPath, State, LastRunTime, NextRunTime,
                          @{N='Actions';E={($_.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' | '}}
    } catch {
        $LTTasks = @()
    }
    $Results['LTTasks'] = $LTTasks

    # -------------------------------------------------------------------------
    # 9. Connectwise Automate Agent - maintenance window registry
    # -------------------------------------------------------------------------
    Write-Host "[*] Checking Connectwise Automate agent registry..." -ForegroundColor Yellow
    $LTRegPaths = @(
        "HKLM:\SOFTWARE\LabTech\Service",
        "HKLM:\SOFTWARE\WOW6432Node\LabTech\Service",
        "HKLM:\SOFTWARE\CWAutomate",
        "HKLM:\SOFTWARE\WOW6432Node\CWAutomate"
    )
    $LTRegData = foreach ($path in $LTRegPaths) {
        if (Test-Path $path) {
            $props = Get-ItemProperty $path -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                RegistryPath      = $path
                ServerAddress     = $props.ServerAddress
                LocationID        = $props.LocationID
                ClientID          = $props.ClientID
                LastContact       = $props.LastSuccessStatus
                MaintenanceMode   = $props.MaintenanceMode
                MaintenanceStart  = $props.MaintenanceStart
                MaintenanceEnd    = $props.MaintenanceEnd
                PatchWindow       = $props.PatchWindow
                PatchEnabled      = $props.PatchEnabled
                AllValues         = $props | Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSProvider,PSDrive
            }
        }
    }
    $Results['AutomateAgent'] = $LTRegData

    # -------------------------------------------------------------------------
    # 10. Network / K: drive availability at logon - Winlogon events
    # -------------------------------------------------------------------------
    Write-Host "[*] Checking Winlogon/network-at-logon events..." -ForegroundColor Yellow
    try {
        $WinlogonEvents = Get-WinEvent -FilterHashtable @{
            LogName      = 'Microsoft-Windows-Winlogon/Operational'
            StartTime    = $StartTime
        } -ErrorAction SilentlyContinue |
        Select-Object TimeCreated,
                      @{N='DayOfWeek';E={$_.TimeCreated.DayOfWeek}},
                      Id, Message |
        Sort-Object TimeCreated
    } catch {
        $WinlogonEvents = @([PSCustomObject]@{ Note = "Winlogon/Operational log not available or empty." })
    }
    $Results['WinlogonEvents'] = $WinlogonEvents

    # -------------------------------------------------------------------------
    # 11. Group Policy - Folder Redirection and Shell policies
    # -------------------------------------------------------------------------
    Write-Host "[*] Checking GPO/registry shell policies..." -ForegroundColor Yellow
    $PolicyChecks = [ordered]@{}

    # Folder redirection GPO flags
    $FRPolicy = Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\System" -ErrorAction SilentlyContinue
    $PolicyChecks['FolderRedirectionGPO'] = [PSCustomObject]@{
        DisableFROnInternetOpen = $FRPolicy.DisableFROnInternetOpen
        RestoreShellFolders     = $FRPolicy.RestoreShellFolders
    }

    # Logon network wait
    $WinlogonPolicy = Get-ItemProperty "HKLM:\Software\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon" -ErrorAction SilentlyContinue
    $PolicyChecks['WinlogonPolicy'] = [PSCustomObject]@{
        SyncForegroundPolicy     = $WinlogonPolicy.SyncForegroundPolicy
        AlwaysWaitForNetwork     = $WinlogonPolicy.AlwaysWaitForNetwork
        GpNetworkStartTimeoutPolicyValue = $WinlogonPolicy.GpNetworkStartTimeoutPolicyValue
    }

    # User Winlogon
    $WinlogonUser = Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows NT\CurrentVersion\Winlogon" -ErrorAction SilentlyContinue
    $PolicyChecks['WinlogonUserPolicy'] = $WinlogonUser | Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSProvider,PSDrive

    # Explorer policies
    $ExplorerPolicy = Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -ErrorAction SilentlyContinue
    $PolicyChecks['ExplorerPolicy'] = $ExplorerPolicy | Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSProvider,PSDrive

    $Results['PolicyChecks'] = $PolicyChecks

    # -------------------------------------------------------------------------
    # 12. K: drive mapping details
    # -------------------------------------------------------------------------
    Write-Host "[*] Checking K: drive mapping..." -ForegroundColor Yellow
    $KDrive = Get-PSDrive -Name K -ErrorAction SilentlyContinue
    $KNet   = Get-WmiObject -Class Win32_NetworkConnection -ErrorAction SilentlyContinue | Where-Object { $_.LocalName -eq 'K:' }
    $Results['KDrive'] = [PSCustomObject]@{
        Mapped          = $null -ne $KDrive
        Root            = $KDrive.Root
        RemoteName      = $KNet.RemoteName
        Status          = $KNet.Status
        Persistent      = $KNet.Persistent
        UserName        = $KNet.UserName
        Reachable       = if ($KDrive) { Test-Path $KDrive.Root } else { $false }
    }

    # -------------------------------------------------------------------------
    # Build HTML Report
    # -------------------------------------------------------------------------
    Write-Host "[*] Building HTML report..." -ForegroundColor Yellow

    function ConvertTo-HtmlTable {
        param($Data, [string]$Title)
        if (-not $Data) { return "<p><em>No data collected.</em></p>" }
        $html  = "<h3>$Title</h3>"
        $items = @($Data)
        if ($items[0] -is [PSCustomObject] -or $items[0] -is [hashtable]) {
            $html += $items | ConvertTo-Html -Fragment -As Table | Out-String
        } else {
            $html += "<pre>$($Data | Out-String)</pre>"
        }
        $html
    }

    $ReportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $AdminNote  = if (-not $IsAdmin) { 
        "<div class='warn'>⚠️ <strong>Script ran as standard user.</strong> Re-run as Administrator for full Security log and scheduled task data.</div>" 
    } else { "" }

    $Html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Quick Access Diagnostics - $($env:COMPUTERNAME)</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; font-size: 13px; background: #f4f6f9; color: #222; margin: 0; padding: 0; }
  .header { background: #1a3a5c; color: white; padding: 18px 28px; }
  .header h1 { margin: 0; font-size: 20px; }
  .header p  { margin: 4px 0 0; font-size: 12px; opacity: 0.8; }
  .container { padding: 20px 28px; }
  .section   { background: white; border-radius: 6px; padding: 16px 20px; margin-bottom: 18px; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
  h2 { font-size: 15px; color: #1a3a5c; border-bottom: 2px solid #1a3a5c; padding-bottom: 6px; margin-top: 0; }
  h3 { font-size: 13px; color: #444; margin: 12px 0 6px; }
  table { border-collapse: collapse; width: 100%; font-size: 12px; margin-bottom: 10px; }
  th { background: #1a3a5c; color: white; padding: 6px 10px; text-align: left; }
  td { padding: 5px 10px; border-bottom: 1px solid #e8e8e8; vertical-align: top; }
  tr:nth-child(even) td { background: #f8f9fb; }
  .warn { background: #fff3cd; border: 1px solid #ffc107; border-radius: 4px; padding: 10px 14px; margin-bottom: 14px; }
  .ok   { color: #2e7d32; font-weight: bold; }
  .bad  { color: #c62828; font-weight: bold; }
  .note { color: #888; font-style: italic; }
  pre   { background: #f4f4f4; padding: 10px; border-radius: 4px; overflow-x: auto; font-size: 11px; }
  .highlight-sunday td { background: #fff3e0 !important; }
  .highlight-monday  td { background: #fce4ec !important; }
</style>
</head>
<body>
<div class="header">
  <h1>Quick Access Pin Loss — Diagnostics Report</h1>
  <p>Computer: <strong>$($env:COMPUTERNAME)</strong> &nbsp;|&nbsp; User: <strong>$($env:USERNAME)</strong> &nbsp;|&nbsp; Generated: $ReportDate</p>
</div>
<div class="container">
$AdminNote

<div class="section">
  <h2>&#128196; System Information</h2>
  $(ConvertTo-HtmlTable -Data $Results.SystemInfo -Title "")
</div>

<div class="section">
  <h2>&#128204; Quick Access Database (AutomaticDestinations)</h2>
  $(ConvertTo-HtmlTable -Data $Results.AutomaticDestinations -Title "File Status")
  <h3>All Files in AutomaticDestinations</h3>
  $($Results.AutomaticDestinations.AllFiles | ConvertTo-Html -Fragment | Out-String)
  <p class="note">⭐ Key file: <strong>f01b4d95cf55d32a.automaticDestinations-ms</strong> — if its LastWriteTime matches a Sunday night or Monday morning after an incident, this confirms when the reset occurred.</p>
</div>

<div class="section">
  <h2>&#128193; Folder Redirection (Effective Paths)</h2>
  $($Results.FolderRedirection | ConvertTo-Html -Fragment | Out-String)
</div>

<div class="section">
  <h2>&#127760; K: Drive Mapping</h2>
  $(ConvertTo-HtmlTable -Data $Results.KDrive -Title "")
</div>

<div class="section">
  <h2>&#128274; Offline Files / CSC Configuration</h2>
  $(ConvertTo-HtmlTable -Data $Results.OfflineFiles -Title "")
  <p class="note">If CSC/Offline Files is enabled and syncing redirected folders, a sync conflict on Monday can overwrite shell data.</p>
</div>

<div class="section">
  <h2>&#128260; Reboot / Power Events (Last $DaysBack Days)</h2>
  $($Results.RebootEvents | ConvertTo-Html -Fragment | Out-String)
  <p class="note">Look for events on Sunday night or Monday morning. Event 6008 = unexpected shutdown. Event 1074 = managed reboot (check Message for initiator).</p>
</div>

<div class="section">
  <h2>&#128274; Logon / Logoff Events (Last $DaysBack Days)</h2>
  $($Results.LogonEvents | ConvertTo-Html -Fragment | Out-String)
</div>

<div class="section">
  <h2>&#128680; Application Log — Explorer / Shell Errors</h2>
  $($Results.AppEvents | ConvertTo-Html -Fragment | Out-String)
</div>

<div class="section">
  <h2>&#128336; Scheduled Tasks (Weekend + Management Agents)</h2>
  $($Results.ScheduledTasks | ConvertTo-Html -Fragment | Out-String)
</div>

<div class="section">
  <h2>&#128295; Connectwise Automate Agent — Scheduled Tasks</h2>
  $($Results.LTTasks | ConvertTo-Html -Fragment | Out-String)
</div>

<div class="section">
  <h2>&#128295; Connectwise Automate Agent — Registry</h2>
  $(foreach ($item in $Results.AutomateAgent) { ConvertTo-HtmlTable -Data $item -Title $item.RegistryPath })
  $(if (-not $Results.AutomateAgent) { "<p class='note'>No Automate/LabTech registry keys found at standard paths.</p>" })
</div>

<div class="section">
  <h2>&#128196; Winlogon / Network-at-Logon Events</h2>
  $($Results.WinlogonEvents | ConvertTo-Html -Fragment | Out-String)
</div>

<div class="section">
  <h2>&#128196; Group Policy / Shell Policy Registry</h2>
  $(foreach ($key in $Results.PolicyChecks.Keys) { ConvertTo-HtmlTable -Data $Results.PolicyChecks[$key] -Title $key })
</div>

</div>
</body>
</html>
"@

    $Html | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "`n[+] Report saved to: $OutputPath" -ForegroundColor Green
    Write-Host "[+] Open in any browser to review." -ForegroundColor Green

    # Also print a quick console summary of the most important findings
    Write-Host "`n--- Quick Console Summary ---" -ForegroundColor Cyan

    $qa = $Results.AutomaticDestinations
    Write-Host "QA File LastWrite : $($qa.QAFileLastWrite) ($($qa.QAFileLastWriteDayOfWeek))" -ForegroundColor White
    Write-Host "QA File Size      : $($qa.QAFileSizeBytes) bytes" -ForegroundColor White

    Write-Host "`nFolder Redirection:" -ForegroundColor White
    $Results.FolderRedirection | Format-Table FolderName, ActualPath, IsRedirected, PathReachable -AutoSize

    Write-Host "K: Drive Reachable: $($Results.KDrive.Reachable)" -ForegroundColor White
    Write-Host "CSC Service Status: $($Results.OfflineFiles.ServiceStatus)" -ForegroundColor White

    Write-Host "`nReboot events found on Sunday/Monday:" -ForegroundColor White
    $Results.RebootEvents | Where-Object { $_.DayOfWeek -in @('Sunday','Monday') } | 
        Format-Table TimeCreated, DayOfWeek, Id, EventType -AutoSize

    Write-Host "`nAutomate Agent Registry Keys Found:" -ForegroundColor White
    if ($Results.AutomateAgent) {
        $Results.AutomateAgent | ForEach-Object { Write-Host "  $($_.RegistryPath)" -ForegroundColor Green }
    } else {
        Write-Host "  None found at standard paths." -ForegroundColor Yellow
    }

    # Return structured data for piping
    return $Results
}

# Entry point
Get-QuickAccessDiagnostics
