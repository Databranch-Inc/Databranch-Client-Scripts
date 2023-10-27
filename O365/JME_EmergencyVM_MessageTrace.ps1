<#
JME Emergency VM Message Trace Report
This script is designed to connect to Exhagne onling and run a trace report of messages sent to the JME Emergency CM over the last 30 days. 
#>

#Variable Set
$EndDate = Get-Date -UFormat %D
$TempStartDate = (Get-Date).AddDays(-30)
$FormatStartDate = Get-Date $TempStartDate -UFormat %D
$ReportTitle = "JME Emergency VM TraceLog Report - $FormatStartDate through $EndDate"

#ModuleImport
Import-Module ExchangeOnlineManagement

#Connect to EOL


#Run Historical Search
Start-HistoricalSearch -ReportTitle $ReportTitle -StartDate $FormatStartDate -EndDate $EndDate -RecipientAddress "emergencyvm@johnmilselectric.com" -ReportType MessageTraceDetail
