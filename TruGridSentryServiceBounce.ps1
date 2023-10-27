<#
TruGridSentryServiceBounce

This script bounces the TruGridSentry Service on a server to avoid problems with re-connection.
Josh Britton
3/26/26
1.0
#>

Get-Service -name trugrid_sentry | Stop-Service
Start-sleep 10
Start-Service -Name Trugrid_sentry