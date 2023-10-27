<#VPN_Setup
This script is designed to add the Windows VPN connection for Arnot Realty Corp. It is set to use thier Meraki system for VPN

Josh Britton

10/29/20

1.0#>

#Variable Set

$VPNName = "Arnot-VPN"
$Server_Address = "arnot-realty-network-wired-czmqnrgkrp.dynamic-m.com"
$L2tpPsk = "tKD8tK8QT"

Add-VpnConnection -AllUserConnection -Name $VPNName -ServerAddress $Server_Address -TunnelType L2tp -EncryptionLevel Optional -L2tpPsk  -AuthenticationMethod Pap -Force