function Deploy-WirelessProfile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SSID,

        [Parameter(Mandatory = $true)]
        [string]$Authentication,

        [Parameter(Mandatory = $true)]
        [string]$Encryption,

        [Parameter(Mandatory = $true)]
        [string]$Password
    )

function Convert-StringToHex {
    param (
        [Parameter(Mandatory)]
        [string]$InputString
    )

    # Convert each character to its hex value
    $hex = ($InputString.ToCharArray() | ForEach-Object {
        [System.Text.Encoding]::UTF8.GetBytes($_) | ForEach-Object {
            '{0:X2}' -f $_
        }
    }) -join ''

    return $hex
}
$SSIDHEX = Convert-StringToHex -InputString $SSID

    # Create the XML configuration for the wireless profile
    $profileXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">    
    <SSIDConfig>
        <SSID>
            <hex>$SSIDHEX</hex>
            <name>$SSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>$Authentication</authentication>
                <encryption>$Encryption</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$Password</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

    # Save the profile XML to a temporary file
    $tempFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tempFile -Value $profileXml -Force

    # Add the wireless profile using netsh
    try {
        netsh wlan add profile filename="$tempFile" user=all | Out-Null
        Write-Host "Wireless profile '$SSID' deployed successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to deploy wireless profile '$SSID': $_" -ForegroundColor Red
    } finally {
        # Clean up the temporary file
        Remove-Item -Path $tempFile -Force
    }
}