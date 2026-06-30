function Set-BCDRSambaAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('Enable','Disable')]
        [string]$State
    )

    # If no parameter, look for a variable named EnableDisable (script or global scope)
    if (-not $State) {
        $found = $false
        foreach ($scope in 'Script','Global') {
            $var = Get-Variable -Name 'EnableDisable' -Scope $scope -ErrorAction SilentlyContinue
            if ($null -ne $var) { $val = $var.Value; $found = $true; break }
        }
        if (-not $found) { throw "State not provided and variable 'EnableDisable' not found. Use 'Enable' or 'Disable'." }

        if ($val -is [bool]) { $State = if ($val) { 'Enable' } else { 'Disable' } }
        else { $State = $val.ToString() }
    }

    switch ($State.ToLower()) {
        'enable' {
            try {
                Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -Force -ErrorAction Stop
                Set-SmbClientConfiguration -RequireSecuritySignature $false -Force -ErrorAction Stop
                Set-SmbServerConfiguration -RequireSecuritySignature $false -Force -ErrorAction Stop
            } catch {
                throw "Failed to enable SMB settings: $($_.Exception.Message)"
            }
        }
        'disable' {
            try {
                Set-SmbClientConfiguration -EnableInsecureGuestLogons $false -Force -ErrorAction Stop
                Set-SmbClientConfiguration -RequireSecuritySignature $true -Force -ErrorAction Stop
                Set-SmbServerConfiguration -RequireSecuritySignature $true -Force -ErrorAction Stop
            } catch {
                throw "Failed to disable SMB settings: $($_.Exception.Message)"
            }
        }
        default { throw "Invalid state value: $State. Use 'Enable' or 'Disable'." }
    }
}
