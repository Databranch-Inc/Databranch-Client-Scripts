<#
Radius Allow Windows Firewall

This script will create 4 Windows Firewall Rules

1. Inbound Radius TCP Allow
2. Inbound Radius UDP Allow
3. Outbound Radius TCP Allow
4. Outbound Radius UDP Allow.

This could be needed as part of the process to setup a radius authentication, normally to SonicWALL devices for SSLVPN

Josh Britton

8-5-24

1.0
==================================================================
1.0

Initial Write - creating as a function with default radius port (1812)
==================================================================
#>








New-NetFirewallRule -DisplayName "" -Direction  -Action  -LocalPort