<#
Enable_WinRM
This script sets the WinRM Quick Conifg on machines. It is meant to be enabled in a GPO so individual machines can be managed by WinRM for Powershell actions
Josh Britton
8-14-18
1.0
#>

Set-ExecutionPolicy Unrestricted
Set-WSManQuickConfig -Force -SkipNetworkProfileCheck