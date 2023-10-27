<#BSN Allow IPS - O365
This is the script from BSN to allow IP Address in O365, with modifications to ask for the admin to a client  O365 Tenant
Josh Britton
DB Version 1.0 
Created 10/23/20#>

#Variable Set
$Admin = read-host "What is the O365 Admin address for the tenant admin?"




$ips = "168.245.34.162/32",
"168.245.30.20/32",
"54.209.51.230/32",
"157.230.65.76/32",
"168.245.68.173/32",
"149.72.207.249/32",
"149.72.184.111/32",
"168.245.40.98/32",
"18.209.119.19/32",
"34.231.173.178/32"

$domainlist = "it-support.care",
"customer-portal.info",
"member-services.info",
"bankonlinesupport.com",
"secureaccess.biz",
"logineverification.com",
"Iogmein.com",
"mlcrosoft.live",
"cloud-service-care.com",
"packagetrackingportal.com"

$phishRuleName = "BSNPhishSimOverrideRule"

Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser
Connect-IPPSSession -UserPrincipalName $Admin

New-PhishSimOverridePolicy -Name "Databranch-PhishSimOverridePolicy"
New-PhishSimOverrideRule -Name $phishRuleName -Policy PhishSimOverridePolicy -SenderDomainIs $domainlist -SenderIpRanges $ips