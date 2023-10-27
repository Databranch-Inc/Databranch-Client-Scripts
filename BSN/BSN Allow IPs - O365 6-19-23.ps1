
    #Requires -Module ExchangeOnlineManagement 
    Install-Module ExchangeOnlineManagement
    Connect-ExchangeOnline

    #IP addresses for phishing, welcome, micro-training, newsletter & reminder emails
    $IPAddresses = "149.72.207.249/32",
    "168.245.40.98/32",
    "149.72.184.111/32",
    "168.245.30.20/32",
    "54.209.51.230/32",
    "18.209.119.19/32",
    "34.231.173.178/32",
    "168.245.68.173/32",
    "168.245.34.162/32",
    "157.230.65.76/32"

    #Phishing Domains
    $domainList = "it-support.care",
    "customer-portal.info",
    "member-services.info",
    "bankonlinesupport.com",
    "secureaccess.biz",
    "logineverification.com",
    "Iogmein.com",
    "mlcrosoft.live",
    "cloud-service-care.com",
    "packagetrackingportal.com"

    #Phishing Simulation URLs
    $simURL = "~it-support.care~",
    "~customer-portal.info~",
    "~member-services.info~",
    "~bankonlinesupport.com~",
    "~Iogmein.com~",
    "~mlcrosoft.live~",
    "~packagetrackingportal.com~",
    "~secureaccess.biz~",
    "~logineverification.com~",
    "~cloud-service-care.com~"

    #Phishing Override Rule Name
    $phishRuleName = "BSNPhishSimOverrideRule"
    #Connector Name
    $connectorName = "BSN Connector"


    #Add URL's to Advanced Delivery Third Party Phishing Simulation
    New-TenantAllowBlockListItems -Allow -ListType Url -ListSubType AdvancedDelivery -Entries $simURL -NoExpiration

    #Create a connector for BSN IP addresses
    New-InboundConnector -Name $connectorName -SenderIPAddresses $IPAddresses -RequireTls $true -Enabled $true -SenderDomains *

    #Set Connection Filter Policy
    $listIPAllowList = New-Object System.Collections.Generic.HashSet[String]
    foreach ($ip in $IPAddresses){[void]$listIPAllowList.add($ip)}
    (Get-HostedConnectionFilterPolicy -Identity Default).IPAllowList | ForEach-Object {[void]$listIPAllowList.Add($_)}
    Set-HostedConnectionFilterPolicy -Identity Default -IPAllowList $listIPAllowList

    Connect-IPPSSession

    #Add domains and IP addresses to Advanced Delivery Third Party Phishing Simulation
    New-PhishSimOverridePolicy -Name PhishSimOverridePolicy
    New-PhishSimOverrideRule -Name $phishRuleName -Policy PhishSimOverridePolicy -SenderDomainIs $domainList -SenderIpRanges $IPAddresses
    