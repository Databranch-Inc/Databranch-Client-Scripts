Function Check-ClusterHealth {
    <#Param (
        [Parameter(Mandatory=$true)]
        [string]$ClusterIP,
        [Parameter(Mandatory=$true)]
        [string]$Username,
        [Parameter(Mandatory=$true)]
        [string]$Password
    )
    #>

# Define the API endpoint and credentials
$BaseUrl = "https://10.10.1.24/rest/v1"
$Username = "admin"
$Password = "o(D6t$_6T0LFg1o!"

# Ignore SSL certificate errors (if needed)
Add-Type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@

[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

# Authenticate and get the token
$AuthBody = @{
    username = $Username
    password = $Password
}
$AuthResponse = Invoke-RestMethod -Uri "$BaseUrl/auth/login" -Method Post -Body ($AuthBody | ConvertTo-Json -Depth 10) -ContentType "application/json"
$Token = $AuthResponse.token

# Set the authorization header
$Headers = @{
    Authorization = "Bearer $Token"
}

# Perform a health check on the cluster nodes
$HealthCheckResponse = Invoke-RestMethod -Uri "$BaseUrl/condition" -Method Get -Headers $Headers

# Filter nodes with errors
$NodesInError = $HealthCheckResponse.nodes | Where-Object { $_.value -ne "true" }

# Save nodes in error to a file for export
$ErrorFilePath = "ClusterNodesInError.json"
$NodesInError | ConvertTo-Json -Depth 10 | Set-Content -Path $ErrorFilePath

Write-Host "Health check completed. Nodes in error saved to $ErrorFilePath."

}