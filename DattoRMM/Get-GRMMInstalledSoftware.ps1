function Get-DRMMInstalledSoftware {
    <#
    .SYNOPSIS
    Retrieve installed software (name + version) from Datto RMM for one or more devices.

    .DESCRIPTION
    Queries the Datto RMM API (audit endpoint) to return installed software inventory.
    Supports filtering by DeviceName, Site, or direct DeviceUid.

    .PARAMETER DeviceName
    One or more device hostnames to query.

    .PARAMETER DeviceUid
    One or more device UIDs (GUIDs).

    .PARAMETER SiteName
    Filter devices by site name.

    .PARAMETER ApiUrl
    Datto RMM API base URL (region-specific).

    .PARAMETER ApiKey
    Datto RMM API key.

    .PARAMETER ApiSecret
    Datto RMM API secret.

    .PARAMETER NameFilter
    Optional wildcard filter for software name.

    .PARAMETER Parallel
    Enable parallel processing (PowerShell 7+ recommended).

    .EXAMPLE
    Get-DRMMInstalledSoftware -DeviceName "SERVER01"

    .EXAMPLE
    Get-DRMMInstalledSoftware -SiteName "Client A" -NameFilter "*Microsoft*"

    .NOTES
    Requires Datto RMM API access enabled.
    #>

    [CmdletBinding()]
    param (
        [string[]]$DeviceName,
        [string[]]$DeviceUid,
        [string]$SiteName,

        [Parameter(Mandatory)]
        [string]$ApiUrl,

        [Parameter(Mandatory)]
        [string]$ApiKey,

        [Parameter(Mandatory)]
        [string]$ApiSecret,

        [string]$NameFilter,
        [switch]$Parallel
    )

    #region Get API Token
    Write-Verbose "Authenticating to Datto RMM API..."

    $tokenBody = @{
        grant_type    = "client_credentials"
        client_id     = $ApiKey
        client_secret = $ApiSecret
    }

    $tokenResponse = Invoke-RestMethod `
        -Uri "$ApiUrl/api/v2/oauth/token" `
        -Method POST `
        -Body $tokenBody `
        -ErrorAction Stop

    $headers = @{
        Authorization = "Bearer $($tokenResponse.access_token)"
    }
    #endregion

    #region Get Devices
    Write-Verbose "Retrieving device list..."

    $deviceList = Invoke-RestMethod `
        -Uri "$ApiUrl/api/v2/account/devices" `
        -Headers $headers `
        -Method GET

    $devices = $deviceList.data

    # Apply filters
    if ($DeviceName) {
        $devices = $devices | Where-Object { $DeviceName -contains $_.hostname }
    }

    if ($DeviceUid) {
        $devices = $devices | Where-Object { $DeviceUid -contains $_.uid }
    }

    if ($SiteName) {
        $devices = $devices | Where-Object { $_.siteName -eq $SiteName }
    }

    if (-not $devices) {
        Write-Warning "No devices matched filter criteria."
        return
    }
    #endregion

    #region Software Query ScriptBlock
    $scriptBlock = {
        param($device, $headers, $ApiUrl, $NameFilter)

        try {
            $audit = Invoke-RestMethod `
                -Uri "$ApiUrl/api/v2/audit/device/$($device.uid)" `
                -Headers $headers `
                -Method GET `
                -ErrorAction Stop

            foreach ($app in $audit.software) {

                if ($NameFilter -and ($app.name -notlike $NameFilter)) {
                    continue
                }

                [PSCustomObject]@{
                    DeviceName = $device.hostname
                    SiteName   = $device.siteName
                    Software   = $app.name
                    Version    = $app.version
                    Publisher  = $app.publisher
                    InstallDate= $app.installDate
                }
            }
        }
        catch {
            Write-Warning "Failed to query device [$($device.hostname)]: $_"
        }
    }
    #endregion

    #region Execute (Parallel or Sequential)
    if ($Parallel -and $PSVersionTable.PSVersion.Major -ge 7) {

        Write-Verbose "Running in parallel mode..."

        $results = $devices | ForEach-Object -Parallel {
            param($headers, $ApiUrl, $NameFilter)

            & $using:scriptBlock $_ $headers $ApiUrl $NameFilter

        } -ArgumentList $headers, $ApiUrl, $NameFilter -ThrottleLimit 10
    }
    else {
        Write-Verbose "Running in sequential mode..."

        $results = foreach ($device in $devices) {
            & $scriptBlock $device $headers $ApiUrl $NameFilter
        }
    }
    #endregion

    return $results
}
