function New-ClusterShutdownBatch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Password,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Node
    )

    try {
        # Build Base64 auth string
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("$Username`:$Password")
        $auth  = [Convert]::ToBase64String($bytes)

        # Output file (same directory as script)
        $outFile = Join-Path $PSScriptRoot "cluster_shutdown.bat"

        # Batch file content
        $batContent = @"
@echo off
curl.exe -k -X GET "https://$Node/rest/v1/Cluster/shutdown" -H "accept: application/json" -H "Authorization: Basic $auth"
"@

        # Write the file
        Set-Content -Path $outFile -Value $batContent -Encoding ASCII

        if (Test-Path $outFile) {
            Write-Host "✅ Batch file created: $outFile"
        }
        else {
            throw "Failed to create batch file"
        }
    }
    catch {
        Write-Error "Error creating cluster shutdown batch file: $_"
    }
}