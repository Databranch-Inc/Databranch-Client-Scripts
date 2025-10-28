function Get-WirelessProfileBySSID {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SSID
    )

    # Get all wireless profiles on the machine
    $profiles = netsh wlan show profiles | Select-String -Pattern "All User Profile\s*:\s*(.+)" | ForEach-Object {
        ($_ -match "All User Profile\s*:\s*(.+)") | Out-Null
        $matches[1].Trim()
    }

    # Check if the provided SSID exists in the profiles
    if ($profiles -contains $SSID) {
        Write-Output "Wireless profile found."
    } else {
        Write-Warning "Wireless profile for SSID '$SSID' not found on this machine."
    }
}