<#
Shield Trusted Site Registry Key Script
This script adds shield.security as a trusted site to the registry for all users on a machine.
This allows the Shield HUD to display the images for the email message witout turning on "Download Pictures" in Outlook.

Josh Britton

4-30-25

1.0
===========================================================
1.0

Initial release, created with Co-Pilot Assistance
===========================================================
#>


Function Add-TrustedSite {
   

    #Set the site URL to be added as a trusted site
    $siteUrl = "https://shield.security"

    # Define the registry path for trusted sites
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\Domains"

    # Extract the domain from the site URL
    $domain = ($siteUrl -replace "https://", "").Split('/')[0]

    # Create the registry key for the domain
    $domainKeyPath = Join-Path $regPath $domain
    if (-not (Test-Path $domainKeyPath)) {
        New-Item -Path $domainKeyPath -Force | Out-Null
    }

    # Set the value to mark the site as trusted (Zone 2)
    Set-ItemProperty -Path $domainKeyPath -Name "*" -Value 2

    Write-Host "Trusted site '$siteUrl' has been added for all users."
}
