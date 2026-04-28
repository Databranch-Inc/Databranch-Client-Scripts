#Requires -Version 5.1
<#
.SYNOPSIS
    Pulls every device from DattoRMM and exports a comprehensive flat-CSV inventory.

.DESCRIPTION
    Authenticates against the DattoRMM v2 API, paginates through every device on the
    account, optionally enriches each device with audit data (manufacturer, serial,
    BIOS, MACs, RAM, processor, drives), and writes a single flattened CSV to disk.

    Key behaviors:
      - OAuth2 password-grant authentication; secrets nulled immediately after token issue.
      - Pagination follows pageDetails.nextPageUrl until null (never assumes single-page).
      - Sliding-window read throttling at 80% of the 600-reads-per-60-seconds limit.
      - Audit enrichment is per-device (one extra GET each) and adds manufacturer,
        serial, BIOS, MAC list, total RAM, processor, and disk summary.
      - Site name parsing handles "CompanyName - SiteName" with embedded dashes
        (e.g. "Dura-Bilt Products, Inc. - Main") via space-dash-space split.
      - Optional category filter (Desktop, Laptop, Server, etc.) when only a subset
        is wanted; default is all device types.
      - 'Deleted Devices' meta-site is skipped (DattoRMM internal).

    Designed for manual / scheduled execution from a management host (e.g. DB-RDP1).
    Not intended to run as a DattoRMM component on endpoints.

.PARAMETER ApiUrl
    Base URL of the DattoRMM API (e.g. https://vidal-api.centrastage.net).
    Defaults to environment variable DattoApiUrl.

.PARAMETER ApiKey
    DattoRMM API key. Defaults to environment variable DattoApiKey.

.PARAMETER ApiSecret
    DattoRMM API secret. Defaults to environment variable DattoApiSecret.

.PARAMETER OutputFolder
    Folder where the CSV will be written. Created if missing.
    Defaults to C:\Databranch\Reports.

.PARAMETER DeviceCategory
    Optional filter on the device category (deviceType.category).
    Common values: Desktop, Laptop, Server, Network Device, Printer, ESXi Host.
    Default '*' returns all categories.

.PARAMETER IncludeAudit
    When 'true' (default), enriches each device with /v2/audit/device data
    (manufacturer, serial, BIOS, MAC list, RAM, processor, disks).
    Set to 'false' for a much faster summary-only run.

.EXAMPLE
    .\Get-DattoDeviceInventory.ps1
    Full inventory of every device on the account, with audit enrichment.
    Reads credentials from DattoApi* environment variables.

.EXAMPLE
    .\Get-DattoDeviceInventory.ps1 -DeviceCategory 'Desktop' -IncludeAudit 'false'
    Workstation-only summary inventory, no audit enrichment (fast).

.EXAMPLE
    .\Get-DattoDeviceInventory.ps1 -ApiUrl 'https://vidal-api.centrastage.net' `
        -ApiKey 'xxxxxx' -ApiSecret 'yyyyyy' -OutputFolder 'C:\Temp'
    Explicit credential and path override (useful for ad-hoc testing).

.NOTES
    File Name      : Get-DattoDeviceInventory.ps1
    Version        : 1.0.0.0
    Author         : Sam Kirsch
    Contributors   :
    Company        : Databranch
    Created        : 2026-04-27
    Last Modified  : 2026-04-27
    Modified By    : Sam Kirsch

    Requires       : PowerShell 5.1+
    Run Context    : Domain Admin (manual or scheduled task on management host)
    DattoRMM       : Not applicable (calls the DattoRMM API; not a component)
    Client Scope   : All clients (account-wide pull)

    Exit Codes:
        0  - Success
        1  - Runtime failure (script started, errors encountered during execution)
        2  - Fatal pre-flight failure (missing parameters, auth failure, cannot start)

    Output Design:
        Write-Log     - Structured [timestamp][SEVERITY] output to log file AND
                        DattoRMM stdout. Always verbose. No color.
        Write-Console - Human-friendly colored console output for manual/interactive
                        runs. Uses Write-Host (display stream only). Suppressed in
                        DattoRMM agent context automatically.

    API Notes:
        - Token expiry is 100 hours (re-auth not needed for typical runs).
        - Read limit: 600 / 60s. Throttle at 80% (480 / 60s sliding window).
        - Audit endpoint paths vary by device class:
            agent / Desktop+Laptop+Server -> /v2/audit/device/{uid}
            ESXi  -> /v2/audit/esxi/{uid}
            Printer -> /v2/audit/printer/{uid}
        - Only the agent device-class audit is fetched (workstations/servers).
          Other classes export with summary fields only; audit fields blank.

.CHANGELOG
    v1.0.0.0 - 2026-04-27 - Sam Kirsch
        - Initial release
        - OAuth2 auth + secret nulling
        - Paginated /v2/account/devices fetch
        - Optional /v2/audit/device/{uid} enrichment
        - Sliding-window read throttle at 80% of 600/60s limit
        - 'Deleted Devices' meta-site skip
        - Embedded-dash company name parsing (' - ' split)
        - Flat CSV output with nested object flattening
#>

# ==============================================================================
# PARAMETERS
# Manual run: pass parameters directly. DattoRMM-style env var fallback included
# for consistency with the rest of the script library, even though this script
# is intended to run from a management host rather than as a component.
# ==============================================================================
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$ApiUrl = $(if ($env:DattoApiUrl) { $env:DattoApiUrl } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$ApiKey = $(if ($env:DattoApiKey) { $env:DattoApiKey } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$ApiSecret = $(if ($env:DattoApiSecret) { $env:DattoApiSecret } else { "" }),

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = $(if ($env:OutputFolder) { $env:OutputFolder } else { "C:\Databranch\Reports" }),

    [Parameter(Mandatory = $false)]
    [string]$DeviceCategory = $(if ($env:DeviceCategory) { $env:DeviceCategory } else { "*" }),

    # String-typed boolean (DattoRMM convention) - compare with -eq 'true' in logic
    [Parameter(Mandatory = $false)]
    [string]$IncludeAudit = $(if ($env:IncludeAudit) { $env:IncludeAudit } else { "true" }),

    [Parameter(Mandatory = $false)]
    [string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { "ManagementHost" }),

    [Parameter(Mandatory = $false)]
    [string]$Hostname = $(if ($env:CS_HOSTNAME) { $env:CS_HOSTNAME } else { $env:COMPUTERNAME })
)

# ==============================================================================
# TLS 1.2 ENFORCEMENT
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)

# ==============================================================================
# MASTER FUNCTION
# ==============================================================================
function Get-DattoDeviceInventory {
    [CmdletBinding()]
    param (
        [string]$ApiUrl,
        [string]$ApiKey,
        [string]$ApiSecret,
        [string]$OutputFolder,
        [string]$DeviceCategory,
        [string]$IncludeAudit,
        [string]$SiteName,
        [string]$Hostname
    )

    # ==========================================================================
    # CONFIGURATION
    # ==========================================================================
    $ScriptName    = "Get-DattoDeviceInventory"
    $ScriptVersion = "1.0.0.0"
    $LogRoot       = "C:\Databranch\ScriptLogs"
    $LogFolder     = Join-Path $LogRoot $ScriptName
    $LogDate       = Get-Date -Format "yyyy-MM-dd"
    $LogFile       = Join-Path $LogFolder "$($ScriptName)_$($LogDate).log"
    $MaxLogFiles   = 10

    # Sliding-window read throttling - 80% of the 600-reads-per-60s ceiling.
    $ReadWindowSeconds = 60
    $ReadLimit         = 480   # 80% of 600

    # ==========================================================================
    # WRITE-LOG
    # ==========================================================================
    function Write-Log {
        param (
            [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Message = "",
            [Parameter(Mandatory = $false)] [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG")] [string]$Severity = "INFO"
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
    # WRITE-CONSOLE
    # ==========================================================================
    function Write-Console {
        param (
            [Parameter(Mandatory = $false)] [AllowEmptyString()] [string]$Message = "",
            [Parameter(Mandatory = $false)] [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "DEBUG", "PLAIN")] [string]$Severity = "PLAIN",
            [Parameter(Mandatory = $false)] [int]$Indent = 0
        )

        $Prefix = "  " * $Indent
        $SeverityColors = @{
            INFO = "Cyan"; SUCCESS = "Green"; WARN = "Yellow"
            ERROR = "Red"; DEBUG = "Magenta"; PLAIN = "Gray"
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
        param ([Parameter(Mandatory = $true)] [string]$Title, [Parameter(Mandatory = $false)] [string]$Color = "Cyan")
        $Line = "=" * 60
        Write-Host ""
        Write-Host $Line       -ForegroundColor $Color
        Write-Host "  $Title"  -ForegroundColor White
        Write-Host $Line       -ForegroundColor $Color
        Write-Host ""
    }

    function Write-Section {
        param ([Parameter(Mandatory = $true)] [string]$Title, [Parameter(Mandatory = $false)] [string]$Color = "Cyan")
        $TitleStr = "---- $Title "
        $Padding  = "-" * [Math]::Max(0, (60 - $TitleStr.Length))
        Write-Host ""
        Write-Host "$TitleStr$Padding" -ForegroundColor $Color
    }

    function Write-Separator {
        param ([Parameter(Mandatory = $false)] [string]$Color = "DarkGray")
        Write-Host ("-" * 60) -ForegroundColor $Color
    }

    # ==========================================================================
    # LOGGING SETUP
    # ==========================================================================
    function Initialize-Logging {
        if (-not (Test-Path $LogFolder)) {
            try { New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null }
            catch { Write-Warning "Could not create log folder '$LogFolder': $_" }
        }
        try {
            $ExistingLogs = Get-ChildItem -Path $LogFolder -Filter "$($ScriptName)_*.log" | Sort-Object LastWriteTime -Descending
            if ($ExistingLogs.Count -ge $MaxLogFiles) {
                $ExistingLogs | Select-Object -Skip ($MaxLogFiles - 1) | ForEach-Object {
                    Remove-Item -Path $_.FullName -Force
                }
            }
        }
        catch { Write-Warning "Log rotation failed: $_" }
    }

    # ==========================================================================
    # HELPERS
    # ==========================================================================

    # Convert DattoRMM Unix epoch milliseconds -> ISO 8601 UTC string.
    # Returns empty string if value is null/zero/unparseable.
    function ConvertFrom-EpochMs {
        param ([Parameter(Mandatory = $false)] $EpochMs)

        if ($null -eq $EpochMs) { return "" }
        if ($EpochMs -isnot [long] -and $EpochMs -isnot [int] -and $EpochMs -isnot [double]) {
            $parsed = 0L
            if (-not [long]::TryParse("$EpochMs", [ref]$parsed)) { return "" }
            $EpochMs = $parsed
        }
        if ($EpochMs -le 0) { return "" }

        try {
            $dt = ([System.DateTimeOffset]::FromUnixTimeMilliseconds([long]$EpochMs)).UtcDateTime
            return $dt.ToString("yyyy-MM-dd HH:mm:ss") + "Z"
        }
        catch { return "" }
    }

    # Sliding-window read throttle. Maintains a queue of the timestamps of the
    # last N read calls; if the count within the trailing 60s window meets the
    # threshold, sleep until the oldest entry falls out of the window.
    $script:ReadTimestamps = New-Object -TypeName 'System.Collections.Generic.Queue[datetime]'

    function Wait-ReadWindow {
        $now = Get-Date
        $cutoff = $now.AddSeconds(-1 * $ReadWindowSeconds)

        # Discard timestamps outside the 60s window.
        while ($script:ReadTimestamps.Count -gt 0 -and $script:ReadTimestamps.Peek() -lt $cutoff) {
            [void]$script:ReadTimestamps.Dequeue()
        }

        if ($script:ReadTimestamps.Count -ge $ReadLimit) {
            $oldest = $script:ReadTimestamps.Peek()
            $sleep  = ($oldest.AddSeconds($ReadWindowSeconds) - $now).TotalSeconds
            if ($sleep -gt 0) {
                Write-Log "Read throttle: at $ReadLimit/$ReadWindowSeconds s - sleeping $([Math]::Round($sleep,2))s" -Severity DEBUG
                Start-Sleep -Seconds ([Math]::Ceiling($sleep))
            }
        }
        $script:ReadTimestamps.Enqueue((Get-Date))
    }

    # Wrapped Invoke-RestMethod with throttling, simple retry on transient errors,
    # and a single re-auth attempt on 401 (token expiry safety net for very long runs).
    function Invoke-DattoApi {
        param (
            [Parameter(Mandatory = $true)] [string]$Uri,
            [Parameter(Mandatory = $true)] [hashtable]$Headers,
            [Parameter(Mandatory = $false)] [int]$MaxRetries = 3
        )

        $attempt = 0
        while ($true) {
            $attempt++
            Wait-ReadWindow
            try {
                return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method GET -ErrorAction Stop
            }
            catch {
                $statusCode = $null
                if ($_.Exception.Response) {
                    try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
                }

                # 404 -> caller decides; surface immediately.
                if ($statusCode -eq 404) { throw }

                if ($attempt -ge $MaxRetries) {
                    Write-Log "API call failed after $MaxRetries attempts ($Uri): $_" -Severity ERROR
                    throw
                }

                $backoff = [Math]::Min(30, [Math]::Pow(2, $attempt))
                Write-Log "API call failed (attempt $attempt, status=$statusCode): $_ - retrying in ${backoff}s" -Severity WARN
                Start-Sleep -Seconds $backoff
            }
        }
    }

    # Parse "CompanyName - SiteName" with embedded-dash awareness.
    # Returns hashtable with CompanyName / Location keys.
    function Split-DattoSiteName {
        param ([Parameter(Mandatory = $true)] [string]$Name)

        if ([string]::IsNullOrWhiteSpace($Name)) {
            return @{ CompanyName = ""; Location = "" }
        }

        $tokens = $Name -split ' - '
        if ($tokens.Count -le 1) {
            return @{ CompanyName = $Name.Trim(); Location = "" }
        }

        # Default: company = everything except the last token; location = last token.
        $company  = ($tokens[0..($tokens.Count - 2)]) -join ' - '
        $location = $tokens[$tokens.Count - 1]

        return @{
            CompanyName = $company.Trim()
            Location    = $location.Trim()
        }
    }

    # Safely access a nested property without throwing if any segment is null.
    function Get-PropPath {
        param (
            [Parameter(Mandatory = $false)] $InputObject,
            [Parameter(Mandatory = $true)]  [string]$Path
        )
        if ($null -eq $InputObject) { return $null }
        $current = $InputObject
        foreach ($segment in ($Path -split '\.')) {
            if ($null -eq $current) { return $null }
            try { $current = $current.$segment } catch { return $null }
        }
        return $current
    }

    # ==========================================================================
    # MAIN EXECUTION
    # ==========================================================================
    $ErrorActionPreference = 'Stop'

    Initialize-Logging

    $RunAs = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    Write-Log "===== $ScriptName v$ScriptVersion =====" -Severity INFO
    Write-Log "Site     : $SiteName"                    -Severity INFO
    Write-Log "Hostname : $Hostname"                    -Severity INFO
    Write-Log "Run As   : $RunAs"                       -Severity INFO
    Write-Log "Params   : ApiUrl='$ApiUrl' | OutputFolder='$OutputFolder' | DeviceCategory='$DeviceCategory' | IncludeAudit='$IncludeAudit'" -Severity INFO
    Write-Log "Log File : $LogFile"                     -Severity INFO

    Write-Banner "$($ScriptName.ToUpper()) v$ScriptVersion"
    Write-Console "Site         : $SiteName"      -Severity PLAIN
    Write-Console "Hostname     : $Hostname"      -Severity PLAIN
    Write-Console "Run As       : $RunAs"         -Severity PLAIN
    Write-Console "API URL      : $ApiUrl"        -Severity PLAIN
    Write-Console "Output       : $OutputFolder"  -Severity PLAIN
    Write-Console "Category     : $DeviceCategory" -Severity PLAIN
    Write-Console "IncludeAudit : $IncludeAudit"  -Severity PLAIN
    Write-Console "Log File     : $LogFile"       -Severity PLAIN
    Write-Separator

    try {

        # ------------------------------------------------------------------
        # PRE-FLIGHT VALIDATION
        # ------------------------------------------------------------------
        $MissingParams = @()
        if ([string]::IsNullOrWhiteSpace($ApiUrl))    { $MissingParams += 'ApiUrl (DattoApiUrl)' }
        if ([string]::IsNullOrWhiteSpace($ApiKey))    { $MissingParams += 'ApiKey (DattoApiKey)' }
        if ([string]::IsNullOrWhiteSpace($ApiSecret)) { $MissingParams += 'ApiSecret (DattoApiSecret)' }

        if ($MissingParams.Count -gt 0) {
            foreach ($P in $MissingParams) {
                Write-Log "Missing required parameter: $P" -Severity ERROR
                Write-Console "Missing required parameter: $P" -Severity ERROR
            }
            Write-Banner 'FATAL - MISSING PARAMETERS' -Color 'Red'
            exit 2
        }

        # Strip any trailing slash off ApiUrl for clean URL composition.
        $ApiUrl = $ApiUrl.TrimEnd('/')

        # Ensure output folder exists.
        if (-not (Test-Path $OutputFolder)) {
            try {
                New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
                Write-Log "Created output folder: $OutputFolder" -Severity INFO
            }
            catch {
                Write-Log "Cannot create output folder '$OutputFolder': $_" -Severity ERROR
                Write-Console "Cannot create output folder '$OutputFolder': $_" -Severity ERROR
                Write-Banner 'FATAL - OUTPUT FOLDER UNAVAILABLE' -Color 'Red'
                exit 2
            }
        }

        # ------------------------------------------------------------------
        # AUTHENTICATION
        # OAuth2 password grant. Client credentials are always 'public-client:public'
        # (Base64-encoded). API key/secret pass in the body. Null secrets after.
        # ------------------------------------------------------------------
        Write-Section "Authentication"
        Write-Log     "Requesting OAuth2 access token..." -Severity INFO
        Write-Console "Requesting OAuth2 access token..." -Severity INFO

        $basicB64 = [Convert]::ToBase64String(
            [System.Text.Encoding]::ASCII.GetBytes('public-client:public')
        )

        $authParams = @{
            Uri         = "$ApiUrl/auth/oauth/token"
            Method      = 'POST'
            Headers     = @{ Authorization = "Basic $basicB64" }
            Body        = @{
                grant_type = 'password'
                username   = $ApiKey
                password   = $ApiSecret
            }
            ErrorAction = 'Stop'
        }

        $token = $null
        try {
            $token = (Invoke-RestMethod @authParams).access_token
        }
        catch {
            Write-Log "Authentication failed: $_" -Severity ERROR
            Write-Console "Authentication failed: $_" -Severity ERROR
            # Null secrets even on failure
            $ApiKey = $null
            $ApiSecret = $null
            Write-Banner 'FATAL - AUTH FAILURE' -Color 'Red'
            exit 2
        }

        # Null secrets immediately - token is sufficient from this point on.
        $ApiKey    = $null
        $ApiSecret = $null
        $authParams.Body.username = $null
        $authParams.Body.password = $null

        if ([string]::IsNullOrWhiteSpace($token)) {
            Write-Log "Auth response did not contain access_token." -Severity ERROR
            Write-Banner 'FATAL - AUTH FAILURE' -Color 'Red'
            exit 2
        }

        $headers = @{ Authorization = "Bearer $token" }
        Write-Log     "Authenticated successfully." -Severity SUCCESS
        Write-Console "Authenticated successfully." -Severity SUCCESS

        # ------------------------------------------------------------------
        # FETCH DEVICES (paginated)
        # ------------------------------------------------------------------
        Write-Section "Fetching Devices"
        Write-Log     "Fetching all account devices (paginated)..." -Severity INFO
        Write-Console "Fetching all account devices (paginated)..." -Severity INFO

        $allDevices = New-Object -TypeName 'System.Collections.Generic.List[object]'
        $currentUrl = "$ApiUrl/api/v2/account/devices"
        $pageNum    = 0

        do {
            $pageNum++
            $response = Invoke-DattoApi -Uri $currentUrl -Headers $headers
            $batch    = @($response.devices)
            foreach ($d in $batch) { $allDevices.Add($d) }

            Write-Log "  Page $pageNum : received $($batch.Count) devices (total so far: $($allDevices.Count))" -Severity DEBUG
            Write-Console "Page $pageNum : $($batch.Count) devices (total $($allDevices.Count))" -Severity DEBUG -Indent 1

            $currentUrl = $response.pageDetails.nextPageUrl
        } while (-not [string]::IsNullOrWhiteSpace($currentUrl))

        Write-Log     "Fetched $($allDevices.Count) total devices across $pageNum pages." -Severity SUCCESS
        Write-Console "Fetched $($allDevices.Count) total devices across $pageNum pages." -Severity SUCCESS

        # Skip the 'Deleted Devices' meta-site.
        $devices = @($allDevices | Where-Object { $_.siteName -ne 'Deleted Devices' })
        $skipped = $allDevices.Count - $devices.Count
        if ($skipped -gt 0) {
            Write-Log     "Skipped $skipped device(s) in 'Deleted Devices' meta-site." -Severity INFO
            Write-Console "Skipped $skipped device(s) in 'Deleted Devices' meta-site." -Severity INFO -Indent 1
        }

        # Apply optional category filter.
        if ($DeviceCategory -ne '*' -and -not [string]::IsNullOrWhiteSpace($DeviceCategory)) {
            $beforeFilter = $devices.Count
            $devices = @($devices | Where-Object {
                ($_.deviceType.category -eq $DeviceCategory)
            })
            Write-Log     "Filter '$DeviceCategory' : $($devices.Count) of $beforeFilter devices match." -Severity INFO
            Write-Console "Filter '$DeviceCategory' : $($devices.Count) of $beforeFilter devices match." -Severity INFO -Indent 1
        }

        if ($devices.Count -eq 0) {
            Write-Log     "No devices to export after filtering. Exiting cleanly." -Severity WARN
            Write-Console "No devices to export after filtering. Exiting cleanly." -Severity WARN
            Write-Banner "COMPLETED - NO DEVICES" -Color 'Yellow'
            exit 0
        }

        # ------------------------------------------------------------------
        # FETCH AUDIT DATA (optional, per-device)
        # ------------------------------------------------------------------
        $auditCache = @{}
        if ($IncludeAudit -eq 'true') {
            Write-Section "Fetching Audit Data"
            Write-Log     "Audit enrichment enabled - pulling /v2/audit/device for each agent device." -Severity INFO
            Write-Console "Audit enrichment enabled - pulling per-device audit data." -Severity INFO

            $i = 0
            $progressEvery = [Math]::Max(25, [int]($devices.Count / 20))

            foreach ($device in $devices) {
                $i++
                $uid      = $device.uid
                $devClass = "$($device.deviceClass)".ToLower()

                # Only the 'device' (agent) audit endpoint is fetched here.
                # ESXi/printer audits use different paths and aren't core to a
                # workstation/server inventory ask - left out by design for v1.
                if ([string]::IsNullOrWhiteSpace($uid)) { continue }
                if ($devClass -ne 'device') { continue }

                try {
                    $auditUri = "$ApiUrl/api/v2/audit/device/$uid"
                    $audit    = Invoke-DattoApi -Uri $auditUri -Headers $headers
                    $auditCache[$uid] = $audit
                }
                catch {
                    Write-Log "  Audit fetch failed for $($device.hostname) ($uid): $_" -Severity WARN
                }

                if (($i % $progressEvery) -eq 0) {
                    Write-Log     "  Audit progress: $i / $($devices.Count)" -Severity DEBUG
                    Write-Console "Audit progress: $i / $($devices.Count)" -Severity DEBUG -Indent 1
                }
            }

            Write-Log     "Audit enrichment complete: $($auditCache.Count) device(s) enriched." -Severity SUCCESS
            Write-Console "Audit enrichment complete: $($auditCache.Count) device(s) enriched." -Severity SUCCESS
        }
        else {
            Write-Log     "Audit enrichment disabled (IncludeAudit='false')." -Severity INFO
            Write-Console "Audit enrichment disabled." -Severity INFO
        }

        # ------------------------------------------------------------------
        # FLATTEN AND EXPORT
        # ------------------------------------------------------------------
        Write-Section "Building Inventory"
        Write-Log     "Flattening device records..." -Severity INFO
        Write-Console "Flattening device records..." -Severity INFO

        $rows = New-Object -TypeName 'System.Collections.Generic.List[object]'

        foreach ($d in $devices) {

            # Site name parsing - embedded-dash aware.
            $parsed = Split-DattoSiteName -Name $d.siteName

            # Audit blob (may be $null if not fetched or fetch failed).
            $audit = $null
            if ($auditCache.ContainsKey($d.uid)) { $audit = $auditCache[$d.uid] }

            # MAC list - audit.nics is an array of NIC objects with 'macAddress'.
            $macList = ""
            $nics = Get-PropPath -InputObject $audit -Path 'nics'
            if ($nics) {
                $macs = @($nics | Where-Object { $_.macAddress } | ForEach-Object { $_.macAddress })
                if ($macs.Count -gt 0) { $macList = ($macs -join ';') }
            }

            # Disks summary - audit.physicalDisks or audit.logicalDisks.
            $diskSummary = ""
            $logicalDisks = Get-PropPath -InputObject $audit -Path 'logicalDisks'
            if ($logicalDisks) {
                $parts = @()
                foreach ($ld in $logicalDisks) {
                    $name      = "$($ld.name)"
                    $sizeBytes = $ld.size
                    $freeBytes = $ld.freeSpace
                    if ($sizeBytes) {
                        $sizeGb = [Math]::Round(([double]$sizeBytes) / 1GB, 1)
                    } else { $sizeGb = "" }
                    if ($freeBytes) {
                        $freeGb = [Math]::Round(([double]$freeBytes) / 1GB, 1)
                    } else { $freeGb = "" }
                    $parts += "$name $sizeGb GB ($freeGb GB free)"
                }
                if ($parts.Count -gt 0) { $diskSummary = ($parts -join ' | ') }
            }

            # RAM (bytes -> GB rounded to 1 decimal).
            $ramBytes = Get-PropPath -InputObject $audit -Path 'systemInfo.totalPhysicalMemory'
            $ramGb = ""
            if ($ramBytes) {
                try { $ramGb = [Math]::Round(([double]$ramBytes) / 1GB, 1) } catch { $ramGb = "" }
            }

            # Processor (first one if multiple).
            $processor = ""
            $cpus = Get-PropPath -InputObject $audit -Path 'processors'
            if ($cpus -and @($cpus).Count -gt 0) {
                $processor = "$($cpus[0].name)".Trim()
            }

            # Build the row. Order is the CSV column order.
            $row = [ordered]@{

                # ----- Identity / company -----
                ClientName        = $parsed.CompanyName
                SiteLocation      = $parsed.Location
                SiteName_Raw      = "$($d.siteName)"
                SiteUid           = "$($d.siteUid)"

                # ----- Device basics -----
                Hostname          = "$($d.hostname)"
                Description       = "$($d.description)"
                DeviceUid         = "$($d.uid)"
                DeviceId          = "$($d.id)"
                DeviceClass       = "$($d.deviceClass)"
                DeviceCategory    = "$(Get-PropPath -InputObject $d -Path 'deviceType.category')"
                DeviceType        = "$(Get-PropPath -InputObject $d -Path 'deviceType.type')"

                # ----- Network -----
                InternalIp        = "$($d.intIpAddress)"
                ExternalIp        = "$($d.extIpAddress)"
                Domain            = "$($d.domain)"
                MacAddresses      = $macList

                # ----- User / OS -----
                LastLoggedInUser  = "$($d.lastLoggedInUser)"
                OperatingSystem   = "$($d.operatingSystem)"
                Is64Bit           = "$($d.a64Bit)"

                # ----- Status / timestamps -----
                Online            = "$($d.online)"
                Suspended         = "$($d.suspended)"
                Deleted           = "$($d.deleted)"
                RebootRequired    = "$($d.rebootRequired)"
                LastSeen          = (ConvertFrom-EpochMs -EpochMs $d.lastSeen)
                LastReboot        = (ConvertFrom-EpochMs -EpochMs $d.lastReboot)
                LastAuditDate     = (ConvertFrom-EpochMs -EpochMs $d.lastAuditDate)
                CreationDate      = (ConvertFrom-EpochMs -EpochMs $d.creationDate)

                # ----- Agent -----
                CagVersion        = "$($d.cagVersion)"
                DisplayVersion    = "$($d.displayVersion)"

                # ----- Patch management (nested) -----
                PatchStatus       = "$(Get-PropPath -InputObject $d -Path 'patchManagement.patchStatus')"
                PatchPolicy       = "$(Get-PropPath -InputObject $d -Path 'patchManagement.patchPolicy')"
                PatchesApproved   = "$(Get-PropPath -InputObject $d -Path 'patchManagement.patchesApprovedPending')"
                PatchesNotApproved = "$(Get-PropPath -InputObject $d -Path 'patchManagement.patchesNotApproved')"
                PatchesInstalled  = "$(Get-PropPath -InputObject $d -Path 'patchManagement.patchesInstalled')"

                # ----- Antivirus (nested) -----
                AntivirusProduct  = "$(Get-PropPath -InputObject $d -Path 'antivirus.antivirusProduct')"
                AntivirusStatus   = "$(Get-PropPath -InputObject $d -Path 'antivirus.antivirusStatus')"

                # ----- Alerts -----
                OpenAlerts        = "$(Get-PropPath -InputObject $d -Path 'numberOfOpenAlerts')"
                ResolvedAlerts    = "$(Get-PropPath -InputObject $d -Path 'numberOfResolvedAlerts')"

                # ----- Audit-only enrichment -----
                Manufacturer      = "$(Get-PropPath -InputObject $audit -Path 'systemInfo.manufacturer')"
                Model             = "$(Get-PropPath -InputObject $audit -Path 'systemInfo.model')"
                SerialNumber      = "$(Get-PropPath -InputObject $audit -Path 'bios.serialNumber')"
                BiosVersion       = "$(Get-PropPath -InputObject $audit -Path 'bios.version')"
                BiosReleaseDate   = "$(Get-PropPath -InputObject $audit -Path 'bios.releaseDate')"
                Processor         = $processor
                TotalRamGb        = "$ramGb"
                LogicalDisks      = $diskSummary

                # ----- UDFs (1-30) - exported as separate columns for analysis -----
                UDF1              = "$(Get-PropPath -InputObject $d -Path 'udf.udf1')"
                UDF2              = "$(Get-PropPath -InputObject $d -Path 'udf.udf2')"
                UDF3              = "$(Get-PropPath -InputObject $d -Path 'udf.udf3')"
                UDF4              = "$(Get-PropPath -InputObject $d -Path 'udf.udf4')"
                UDF5              = "$(Get-PropPath -InputObject $d -Path 'udf.udf5')"
                UDF6              = "$(Get-PropPath -InputObject $d -Path 'udf.udf6')"
                UDF7              = "$(Get-PropPath -InputObject $d -Path 'udf.udf7')"
                UDF8              = "$(Get-PropPath -InputObject $d -Path 'udf.udf8')"
                UDF9              = "$(Get-PropPath -InputObject $d -Path 'udf.udf9')"
                UDF10             = "$(Get-PropPath -InputObject $d -Path 'udf.udf10')"
                UDF11             = "$(Get-PropPath -InputObject $d -Path 'udf.udf11')"
                UDF12             = "$(Get-PropPath -InputObject $d -Path 'udf.udf12')"
                UDF13             = "$(Get-PropPath -InputObject $d -Path 'udf.udf13')"
                UDF14             = "$(Get-PropPath -InputObject $d -Path 'udf.udf14')"
                UDF15             = "$(Get-PropPath -InputObject $d -Path 'udf.udf15')"
                UDF16             = "$(Get-PropPath -InputObject $d -Path 'udf.udf16')"
                UDF17             = "$(Get-PropPath -InputObject $d -Path 'udf.udf17')"
                UDF18             = "$(Get-PropPath -InputObject $d -Path 'udf.udf18')"
                UDF19             = "$(Get-PropPath -InputObject $d -Path 'udf.udf19')"
                UDF20             = "$(Get-PropPath -InputObject $d -Path 'udf.udf20')"
                UDF21             = "$(Get-PropPath -InputObject $d -Path 'udf.udf21')"
                UDF22             = "$(Get-PropPath -InputObject $d -Path 'udf.udf22')"
                UDF23             = "$(Get-PropPath -InputObject $d -Path 'udf.udf23')"
                UDF24             = "$(Get-PropPath -InputObject $d -Path 'udf.udf24')"
                UDF25             = "$(Get-PropPath -InputObject $d -Path 'udf.udf25')"
                UDF26             = "$(Get-PropPath -InputObject $d -Path 'udf.udf26')"
                UDF27             = "$(Get-PropPath -InputObject $d -Path 'udf.udf27')"
                UDF28             = "$(Get-PropPath -InputObject $d -Path 'udf.udf28')"
                UDF29             = "$(Get-PropPath -InputObject $d -Path 'udf.udf29')"
                UDF30             = "$(Get-PropPath -InputObject $d -Path 'udf.udf30')"
            }

            $rows.Add([pscustomobject]$row)
        }

        # ------------------------------------------------------------------
        # WRITE CSV
        # ------------------------------------------------------------------
        $stamp    = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $csvName  = "DattoRMM-DeviceInventory_$stamp.csv"
        $csvPath  = Join-Path $OutputFolder $csvName

        Write-Section "Writing CSV"
        Write-Log     "Writing $($rows.Count) row(s) to: $csvPath" -Severity INFO
        Write-Console "Writing $($rows.Count) row(s) to: $csvPath" -Severity INFO

        # NoTypeInformation strips the PS-only #TYPE comment line; UTF8 for Excel sanity.
        $rows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

        Write-Log     "CSV written: $csvPath" -Severity SUCCESS
        Write-Console "CSV written: $csvPath" -Severity SUCCESS

        # ------------------------------------------------------------------
        # SUMMARY
        # ------------------------------------------------------------------
        Write-Section "Summary"

        $byCategory = $rows | Group-Object -Property DeviceCategory | Sort-Object Count -Descending
        Write-Log "Device counts by category:" -Severity INFO
        Write-Console "Device counts by category:" -Severity INFO
        foreach ($g in $byCategory) {
            $catName = if ([string]::IsNullOrWhiteSpace($g.Name)) { '(unknown)' } else { $g.Name }
            Write-Log     "  $catName : $($g.Count)" -Severity INFO
            Write-Console "$catName : $($g.Count)"   -Severity PLAIN -Indent 1
        }

        $clients = ($rows | Select-Object -ExpandProperty ClientName -Unique | Where-Object { $_ }).Count
        Write-Log     "Distinct clients : $clients" -Severity INFO
        Write-Console "Distinct clients : $clients" -Severity INFO

        Write-Log     "Total rows       : $($rows.Count)" -Severity INFO
        Write-Console "Total rows       : $($rows.Count)" -Severity INFO

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

} # End function Get-DattoDeviceInventory

# ==============================================================================
# ENTRY POINT
# ==============================================================================
$ScriptParams = @{
    ApiUrl         = $ApiUrl
    ApiKey         = $ApiKey
    ApiSecret      = $ApiSecret
    OutputFolder   = $OutputFolder
    DeviceCategory = $DeviceCategory
    IncludeAudit   = $IncludeAudit
    SiteName       = $SiteName
    Hostname       = $Hostname
}

Get-DattoDeviceInventory @ScriptParams
