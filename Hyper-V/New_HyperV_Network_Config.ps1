function New-HVNetworkConfig {
    <#
    .SYNOPSIS
    Deploys Hyper-V networking for a flat / no-VLAN environment.

    .DESCRIPTION
    Creates an External Hyper-V vSwitch using either:
      - Shared host management mode
      - Dedicated management vNIC mode
      - Auto mode (recommended)

    Auto mode behavior:
      - 1 physical NIC  => Shared mode (safer for remote deployment)
      - 2+ physical NIC => Dedicated management vNIC

    Supports:
      - Standard single-NIC vSwitch
      - Switch Embedded Teaming (SET) when multiple NICs are supplied
      - Static IP assignment
      - DNS assignment
      - Optional replacement of existing host IPv4 config

    .PARAMETER SwitchName
    Name of the Hyper-V virtual switch.

    .PARAMETER NetAdapterNames
    One or more physical NIC names to bind to the vSwitch.

    .PARAMETER ManagementMode
    Auto      = choose Shared for 1 NIC, Dedicated for 2+ NICs
    Shared    = AllowManagementOS $true
    Dedicated = AllowManagementOS $false + create ManagementOS vNIC

    .PARAMETER EnableSET
    If $true and more than one NIC is provided, creates a SET-backed switch.

    .PARAMETER MgmtVnicName
    Name of the host management vNIC when in Dedicated mode.

    .PARAMETER MgmtIP
    Static IPv4 address to assign to the host vNIC.

    .PARAMETER PrefixLength
    Prefix length for the static IP.

    .PARAMETER Gateway
    Default gateway for the host vNIC. Optional.

    .PARAMETER DnsServers
    One or more DNS server IP addresses.

    .PARAMETER ReplaceExistingIPv4
    If $true, removes any existing IPv4 addresses from the host vNIC before applying the new one.

    .EXAMPLE
    New-HVNetworkConfig `
        -SwitchName "vSwitch-External" `
        -NetAdapterNames "Ethernet1","Ethernet2" `
        -ManagementMode Auto `
        -EnableSET $true `
        -MgmtIP "192.168.1.50" `
        -PrefixLength 24 `
        -Gateway "192.168.1.1" `
        -DnsServers "192.168.1.10","8.8.8.8"

    .EXAMPLE
    New-HVNetworkConfig `
        -SwitchName "vSwitch-External" `
        -NetAdapterNames "Ethernet" `
        -ManagementMode Auto `
        -EnableSET $false `
        -MgmtIP "192.168.1.50" `
        -PrefixLength 24 `
        -Gateway "192.168.1.1" `
        -DnsServers "192.168.1.1"
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$SwitchName,

        [Parameter(Mandatory)]
        [string[]]$NetAdapterNames,

        [Parameter()]
        [ValidateSet("Auto","Shared","Dedicated")]
        [string]$ManagementMode = "Auto",

        [Parameter()]
        [bool]$EnableSET = $true,

        [Parameter()]
        [string]$MgmtVnicName = "Management",

        [Parameter()]
        [string]$MgmtIP,

        [Parameter()]
        [int]$PrefixLength = 24,

        [Parameter()]
        [string]$Gateway,

        [Parameter()]
        [string[]]$DnsServers,

        [Parameter()]
        [bool]$ReplaceExistingIPv4 = $true
    )

    function Write-Info {
        param([string]$Message)
        Write-Host "[INFO] $Message" -ForegroundColor Cyan
    }

    function Write-WarnMsg {
        param([string]$Message)
        Write-Host "[WARN] $Message" -ForegroundColor Yellow
    }

    function Wait-NetAdapterPresent {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter()]
            [int]$TimeoutSeconds = 30
        )

        $stopWatch = [System.Diagnostics.Stopwatch]::StartNew()
        do {
            $adapter = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
            if ($adapter) {
                return $adapter
            }
            Start-Sleep -Seconds 1
        } while ($stopWatch.Elapsed.TotalSeconds -lt $TimeoutSeconds)

        return $null
    }

    Write-Info "Starting Hyper-V network deployment..."

    # Validate physical NICs
    $foundAdapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Name -in $NetAdapterNames }
    if (($foundAdapters | Measure-Object).Count -ne $NetAdapterNames.Count) {
        $missing = $NetAdapterNames | Where-Object { $_ -notin $foundAdapters.Name }
        throw "[ERROR] One or more physical adapters were not found: $($missing -join ', ')"
    }

    # Prevent duplicate switch creation
    if (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue) {
        throw "[ERROR] A vSwitch named '$SwitchName' already exists."
    }

    # Resolve management mode
    $resolvedManagementMode = $ManagementMode
    if ($ManagementMode -eq "Auto") {
        if ($NetAdapterNames.Count -eq 1) {
            $resolvedManagementMode = "Shared"
            Write-Info "Auto mode selected Shared management mode because only 1 NIC was provided."
        }
        else {
            $resolvedManagementMode = "Dedicated"
            Write-Info "Auto mode selected Dedicated management mode because multiple NICs were provided."
        }
    }

    $allowManagementOS = $false
    switch ($resolvedManagementMode) {
        "Shared"    { $allowManagementOS = $true }
        "Dedicated" { $allowManagementOS = $false }
        default     { throw "[ERROR] Invalid management mode resolution." }
    }

    # Build vSwitch
    if ($EnableSET -and $NetAdapterNames.Count -gt 1) {
        Write-Info "Creating SET-enabled External vSwitch '$SwitchName' using NICs: $($NetAdapterNames -join ', ')"

        New-VMSwitch `
            -Name $SwitchName `
            -NetAdapterName $NetAdapterNames `
            -EnableEmbeddedTeaming $true `
            -AllowManagementOS $allowManagementOS `
            -ErrorAction Stop | Out-Null
    }
    else {
        if ($EnableSET -and $NetAdapterNames.Count -eq 1) {
            Write-WarnMsg "SET requested but only 1 NIC was supplied. Creating a standard External vSwitch instead."
        }

        Write-Info "Creating standard External vSwitch '$SwitchName' using NIC: $($NetAdapterNames[0])"

        New-VMSwitch `
            -Name $SwitchName `
            -NetAdapterName $NetAdapterNames[0] `
            -AllowManagementOS $allowManagementOS `
            -ErrorAction Stop | Out-Null
    }

    # Create / identify host management vNIC
    $vnicAlias = $null

    if ($resolvedManagementMode -eq "Dedicated") {
        Write-Info "Creating dedicated host management vNIC '$MgmtVnicName'..."

        Add-VMNetworkAdapter `
            -ManagementOS `
            -Name $MgmtVnicName `
            -SwitchName $SwitchName `
            -ErrorAction Stop | Out-Null

        $vnicAlias = "vEthernet ($MgmtVnicName)"
    }
    else {
        $vnicAlias = "vEthernet ($SwitchName)"
    }

    Write-Info "Waiting for host adapter '$vnicAlias' to become available..."
    $hostVnic = Wait-NetAdapterPresent -Name $vnicAlias -TimeoutSeconds 45
    if (-not $hostVnic) {
        $existingVnics = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "vEthernet*" } |
            Select-Object -ExpandProperty Name

        throw "[ERROR] Host vNIC '$vnicAlias' not found. Existing vEthernet adapters: $($existingVnics -join ', ')"
    }

    # Replace IPv4 if requested
    if ($ReplaceExistingIPv4) {
        Write-Info "Removing existing non-link-local IPv4 addresses from '$vnicAlias'..."

        $existingIPs = Get-NetIPAddress `
            -InterfaceAlias $vnicAlias `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "169.254.*" }

        foreach ($ip in $existingIPs) {
            Write-Info "Removing existing IP $($ip.IPAddress)"
            Remove-NetIPAddress `
                -InterfaceAlias $vnicAlias `
                -IPAddress $ip.IPAddress `
                -Confirm:$false `
                -ErrorAction SilentlyContinue
        }
    }

    # Apply IP config if provided
    if ($MgmtIP) {
        Write-Info "Assigning static IPv4 address '$MgmtIP/$PrefixLength' to '$vnicAlias'..."

        $ipParams = @{
            InterfaceAlias = $vnicAlias
            IPAddress      = $MgmtIP
            PrefixLength   = $PrefixLength
            ErrorAction    = 'Stop'
        }

        if ($Gateway) {
            $ipParams.DefaultGateway = $Gateway
        }

        New-NetIPAddress @ipParams | Out-Null
    }
    else {
        Write-WarnMsg "No MgmtIP supplied. Skipping static IP assignment."
    }

    # Apply DNS if supplied
    if ($DnsServers) {
        Write-Info "Setting DNS servers on '$vnicAlias' to: $($DnsServers -join ', ')"

        Set-DnsClientServerAddress `
            -InterfaceAlias $vnicAlias `
            -ServerAddresses $DnsServers `
            -ErrorAction Stop
    }
    else {
        Write-WarnMsg "No DNS servers supplied. Skipping DNS configuration."
    }

    # Output summary object
    [pscustomobject]@{
        SwitchName             = $SwitchName
        PhysicalNICs           = $NetAdapterNames -join ", "
        ManagementMode         = $resolvedManagementMode
        HostVnicAlias          = $vnicAlias
        EnableSET              = [bool]($EnableSET -and $NetAdapterNames.Count -gt 1)
        MgmtIP                 = $MgmtIP
        PrefixLength           = $PrefixLength
        Gateway                = $Gateway
        DnsServers             = if ($DnsServers) { $DnsServers -join ", " } else { $null }
        ReplaceExistingIPv4    = $ReplaceExistingIPv4
    }

    Write-Host "`n[SUCCESS] Hyper-V networking configuration completed successfully." -ForegroundColor Green
}