<#
Enable_WinRM
This script sets the WinRM Quick Conifg on machines. It is meant to be enabled in a GPO so individual machines can be managed by WinRM for Powershell actions
Created within CHA Enviornment
Josh Britton
8/22/18
1.0
#>

Set-WSManQuickConfig -Force