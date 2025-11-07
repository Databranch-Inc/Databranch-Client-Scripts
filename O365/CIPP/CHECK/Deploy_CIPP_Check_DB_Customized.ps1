<#
Deploy CIPP Check Browser Extension with DB Customized Settings

This script deploys the CIPP Check browser extension for Chrome and Edge with customized settings, including extension configuration, custom branding for Databranch, and installation options.

This script is also updated to wrap within a function to allow the CIPP Tenant ID to be passed as a parameter from a ConnectWise Automate Client EDF


Working elements of Script are forked from the CyberDrain GitHub repository

https://github.com/CyberDrain/Check

Forked for Datbranch use by Josh Britton

Original Load Date: 9-22-25
Version: 1.0

Version History
===========================================================================================================
1.0 - Initial version - 9-22-25 - Josh Britton

Original fork, Databranch Wrap into Overall function to call from CW Automate, addition of Paramater for CIPP Tenant ID
============================================================================================================

#>

Function Deploy-CIPPCheckExtension {
    Param (
        [Parameter(Mandatory=$true)]
        [string]$TenantId
    )


# Define extension details
# Chrome
$chromeExtensionId = "benimdeioplgkhanklclahllklceahbe"
$chromeUpdateUrl = "https://clients2.google.com/service/update2/crx"
$chromeManagedStorageKey = "HKLM:\SOFTWARE\Policies\Google\Chrome\3rdparty\extensions\$chromeExtensionId\policy"
$chromeExtensionSettingsKey = "HKLM:\SOFTWARE\Policies\Google\Chrome\ExtensionSettings\$chromeExtensionId"

#Edge
$edgeExtensionId = "knepjpocdagponkonnbggpcnhnaikajg"
$edgeUpdateUrl = "https://edge.microsoft.com/extensionwebstorebase/v1/crx"
$edgeManagedStorageKey = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\3rdparty\extensions\$edgeExtensionId\policy"
$edgeExtensionSettingsKey = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionSettings\$edgeExtensionId"

# Extension Configuration Settings
$showNotifications = 1 # 0 = Unchecked, 1 = Checked (Enabled); default is 1; This will set the "Show Notifications" option in the extension settings.
$enableValidPageBadge = 1 # 0 = Unchecked, 1 = Checked (Enabled); default is 0; This will set the "Show Valid Page Badge" option in the extension settings.
$enablePageBlocking = 1 # 0 = Unchecked, 1 = Checked (Enabled); default is 1; This will set the "Enable Page Blocking" option in the extension settings.
$forceToolbarPin = 1 # 0 = Not pinned, 1 = Force pinned to toolbar; default is 1
$enableCippReporting = 1 # 0 = Unchecked, 1 = Checked (Enabled); default is 1; This will set the "Enable CIPP Reporting" option in the extension settings.
$cippServerUrl = "https://cipp.databranch.com" # This will set the "CIPP Server URL" option in the extension settings; default is blank; if you set $enableCippReporting to 1, you must set this to a valid URL including the protocol (e.g., https://cipp.cyberdrain.com). Can be vanity URL or the default azurestaticapps.net domain.
$cippTenantId = "$TenantId" # This will set the "Tenant ID/Domain" option in the extension settings; default is blank; if you set $enableCippReporting to 1, you must set this to a valid Tenant ID.
$customRulesUrl = "" # This will set the "Config URL" option in the Detection Configuration settings; default is blank.
$updateInterval = 24 # This will set the "Update Interval" option in the Detection Configuration settings; default is 24 (hours). Range: 1-168 hours (1 hour to 1 week).
$urlWhitelist = @() # This will set the "URL Whitelist" option in the Detection Configuration settings; default is blank; if you want to add multiple URLs, add them as a comma-separated list within the brackets (e.g., @("https://example1.com", "https://example2.com")). Supports simple URLs with * wildcard (e.g., https://*.example.com) or advanced regex patterns (e.g., ^https:\/\/(www\.)?example\.com\/.*$).
$enableDebugLogging = 0 # 0 = Unchecked, 1 = Checked (Enabled); default is 0; This will set the "Enable Debug Logging" option in the Activity Log settings.

# Custom Branding Settings
$companyName = "Databranch" # This will set the "Company Name" option in the Custom Branding settings; default is "CyberDrain".
$companyURL = "https://www.databranch.com." # This will set the Company URL option in the Custom Branding settings; default is "https://cyberdrain.com"; Must include the protocol (e.g., https://).
$productName = "Check - Phishing Protection Powered by Databranch" # This will set the "Product Name" option in the Custom Branding settings; default is "Check - Phishing Protection".
$supportEmail = "support@databranch.com" # This will set the "Support Email" option in the Custom Branding settings; default is blank.
$primaryColor = "#54c3e5" # This will set the "Primary Color" option in the Custom Branding settings; default is "#F77F00"; must be a valid hex color code (e.g., #FFFFFF).
$logoUrl = "https://static.wixstatic.com/media/85fd0c_64287e1d1b5a4b639b60785525618ed9~mv2.png/v1/fill/w_77,h_73,al_c,q_85,usm_0.66_1.00_0.01,enc_avif,quality_auto/Databranch-Logo-Art-Circuitry.png" # This will set the "Logo URL" option in the Custom Branding settings; default is blank. Must be a valid URL including the protocol (e.g., https://example.com/logo.png); protocol must be https; recommended size is 48x48 pixels with a maximum of 128x128.

# Extension Settings
# These settings control how the extension is installed and what permissions it has. It is recommended to leave these at their default values unless you have a specific need to change them.
$installationMode = "force_installed"

# Function to check and install extension
function Configure-ExtensionSettings {
    param (
        [string]$ExtensionId,
        [string]$UpdateUrl,
        [string]$ManagedStorageKey,
        [string]$ExtensionSettingsKey
    )

    # Create and configure managed storage key
    if (!(Test-Path $ManagedStorageKey)) {
        New-Item -Path $ManagedStorageKey -Force | Out-Null
    }

    # Set extension configuration settings
    New-ItemProperty -Path $ManagedStorageKey -Name "showNotifications" -PropertyType DWord -Value $showNotifications -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "enableValidPageBadge" -PropertyType DWord -Value $enableValidPageBadge -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "enablePageBlocking" -PropertyType DWord -Value $enablePageBlocking -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "enableCippReporting" -PropertyType DWord -Value $enableCippReporting -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "cippServerUrl" -PropertyType String -Value $cippServerUrl -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "cippTenantId" -PropertyType String -Value $cippTenantId -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "customRulesUrl" -PropertyType String -Value $customRulesUrl -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "updateInterval" -PropertyType DWord -Value $updateInterval -Force | Out-Null
    New-ItemProperty -Path $ManagedStorageKey -Name "enableDebugLogging" -PropertyType DWord -Value $enableDebugLogging -Force | Out-Null

    # Create and configure custom branding
    $customBrandingKey = "$ManagedStorageKey\customBranding"
    if (!(Test-Path $customBrandingKey)) {
        New-Item -Path $customBrandingKey -Force | Out-Null
    }

    # Set custom branding settings
    New-ItemProperty -Path $customBrandingKey -Name "companyName" -PropertyType String -Value $companyName -Force | Out-Null
    New-ItemProperty -Path $customBrandingKey -Name "companyURL" -PropertyType String -Value $companyURL -Force | Out-Null
    New-ItemProperty -Path $customBrandingKey -Name "productName" -PropertyType String -Value $productName -Force | Out-Null
    New-ItemProperty -Path $customBrandingKey -Name "supportEmail" -PropertyType String -Value $supportEmail -Force | Out-Null
    New-ItemProperty -Path $customBrandingKey -Name "primaryColor" -PropertyType String -Value $primaryColor -Force | Out-Null
    New-ItemProperty -Path $customBrandingKey -Name "logoUrl" -PropertyType String -Value $logoUrl -Force | Out-Null

    # Create and configure extension settings
    if (!(Test-Path $ExtensionSettingsKey)) {
        New-Item -Path $ExtensionSettingsKey -Force | Out-Null
    }

    # Set extension settings
    New-ItemProperty -Path $ExtensionSettingsKey -Name "installation_mode" -PropertyType String -Value $installationMode -Force | Out-Null
    New-ItemProperty -Path $ExtensionSettingsKey -Name "update_url" -PropertyType String -Value $UpdateUrl -Force | Out-Null

    # Add toolbar pinning if enabled
    if ($forceToolbarPin -eq 1) {
        if ($ExtensionId -eq $edgeExtensionId) {
            New-ItemProperty -Path $ExtensionSettingsKey -Name "toolbar_state" -PropertyType String -Value "force_shown" -Force | Out-Null
        } elseif ($ExtensionId -eq $chromeExtensionId) {
            New-ItemProperty -Path $ExtensionSettingsKey -Name "toolbar_pin" -PropertyType String -Value "force_pinned" -Force | Out-Null
        }
    }
 
    Write-Output "Configured extension settings for $ExtensionId"
}

# Configure settings for Chrome and Edge
Configure-ExtensionSettings -ExtensionId $chromeExtensionId -UpdateUrl $chromeUpdateUrl -ManagedStorageKey $chromeManagedStorageKey -ExtensionSettingsKey $chromeExtensionSettingsKey
Configure-ExtensionSettings -ExtensionId $edgeExtensionId -UpdateUrl $edgeUpdateUrl -ManagedStorageKey $edgeManagedStorageKey -ExtensionSettingsKey $edgeExtensionSettingsKey


}