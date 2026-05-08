function New-HVNetworkConfig-NoVLAN {
    param (
        [Parameter(Mandatory)]
        [string]$SwitchName,

        [Parameter(Mandatory)]
        [string[]]$NetAdapterNames,

        [Parameter()]
        [bool]$EnableSET = $true,

        [Parameter()]
        [bool]$AllowManagementOS = $false,

        [Parameter()]
        [string]$MgmtVnicName = "Management",

        [Parameter()]
        [string]$MgmtIP,

        [Parameter()]
        [int]$PrefixLength = 24,

        [Parameter()]
        [string]$Gateway,

        [Parameter()]
        [string[]]$DnsServers
    )

    Write-Host "`n[INFO] Starting Hyper-V Network Deployment (No VLANs)..." -ForegroundColor Cyan

    # Validate adapters
    $adapters = Get-NetAdapter | Where-Object { $_.Name -in $NetAdapterNames }
    if ($adapters.Count -ne $NetAdapterNames.Count) {
        throw "[ERROR] One or more adapters not found: $NetAdapterNames"
    }

    # Check for existing vSwitch
    if (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue) {
        throw "[ERROR] vSwitch '$SwitchName' already exists. Aborting."
    }

    # Create vSwitch
    if ($EnableSET -and $NetAdapterNames.Count -gt 1) {
        Write-Host "[INFO] Creating SET-enabled vSwitch..." -ForegroundColor Yellow

        New-VMSwitch `
            -Name $SwitchName `
            -NetAdapterName $NetAdapterNames `
            -EnableEmbeddedTeaming $true `
            -AllowManagementOS $AllowManagementOS
    }
    else {
        Write-Host "[INFO] Creating standard vSwitch..." -ForegroundColor Yellow

        New-VMSwitch `
            -Name $SwitchName `
            -NetAdapterName $NetAdapterNames[0] `
            -AllowManagementOS $AllowManagementOS
    }

    Start-Sleep -Seconds 3

    # Create Management vNIC if not sharing OS
    if (-not $AllowManagementOS) {
        Write-Host "[INFO] Creating management vNIC..." -ForegroundColor Yellow

        Add-VMNetworkAdapter `
            -ManagementOS `
            -Name $MgmtVnicName `
            -SwitchName $SwitchName
    }

    $vnicAlias = "vEthernet ($MgmtVnicName)"

    # Assign IP
    if ($MgmtIP -and $Gateway) {
        Write-Host "[INFO] Configuring IP address..." -ForegroundColor Yellow

        New-NetIPAddress `
            -InterfaceAlias $vnicAlias `
            -IPAddress $MgmtIP `
            -PrefixLength $PrefixLength `
            -DefaultGateway $Gateway
    }

    # DNS
    if ($DnsServers) {
        Write-Host "[INFO] Setting DNS servers..." -ForegroundColor Yellow

        Set-DnsClientServerAddress `
            -InterfaceAlias $vnicAlias `
            -ServerAddresses $DnsServers
    }

    Write-Host "`n[SUCCESS] Hyper-V Networking (No VLANs) Configured Successfully!" -ForegroundColor Green
}