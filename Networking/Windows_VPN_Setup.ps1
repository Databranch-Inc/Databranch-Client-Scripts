<#Windows_VPN_Setup
This script is designed to add the Windows VPN connection for clients that use the Windows VPN. 

A common use case is the Meraki VPN, currently in use by:

Aront Realty
Gas Field Specialists

Josh Britton

8/18/2025

Version: 1.0
==========================================================================
1.0

Fork from the original script to set up a VPN connection for Arnot Realty. Removing hard-coded variables and wrapping in a fucntion for pulls from CW Automate Variables

JB 8/18/2025
==========================================================================
#>

Function Enable-WindowsVPN {
    
    <#
    .SYNOPSIS
    This function sets up a Windows VPN connection with specified parameters.      
    .DESCRIPTION
    The function checks if a VPN connection with the specified name already exists. If it does not exist, it creates a new VPN connection with the provided server address, L2TP pre-shared key, and other parameters. The connection is set to allow all users and uses PAP authentication.
    .PARAMETER VPNName
    The name of the VPN connection to create or check.
    .PARAMETER Server_Address
    The server address for the VPN connection.
    .PARAMETER L2tpPsk
    The pre-shared key for the L2TP VPN connection.
    .EXAMPLE
    Enable-WindowsVPN -VPNName "MyVPN" -Server_Address "vpn.example.com - L2tpPsk "mysecretkey"
    This example creates a VPN connection named "MyVPN" with the specified server address and pre-shared key.  
    .NOTES
    #>

    param (
        
        [Parameter(Mandatory = $true)]  
        [string]$VPNName,

        [Parameter(Mandatory = $true)]
        [string]$ServerAddress,

        [Parameter(Mandatory = $true)]
        [string]$L2tpPsk
    )
           
    # Check if the VPN connection already exists
    $vpnConnection = Get-VpnConnection -Name $VPNName -AllUserConnection -ErrorAction SilentlyContinue
    if ($vpnConnection) {
        $VPNTEST = "VPN connection '$VPNName' already exists. Skipping creation."
    } else {
        # Create the VPN connection
        Add-VpnConnection -AllUserConnection -Name $VPNName -ServerAddress $ServerAddress -TunnelType L2tp -EncryptionLevel Optional -L2tpPsk $L2tpPsk -AuthenticationMethod Pap -Force
        $VPNTEST = "VPN connection '$VPNName' created successfully."
    }

#Create Array of variables that can be pulled into CW Automate

$obj = @{}
$obj.VPNTEST = $VPNTEST
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final
}