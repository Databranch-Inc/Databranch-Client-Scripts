# Script to verify ScreenConnect services match expected configuration IDs
# Used as a component for Datto RMM monitoring

param(
    [string[]]$ExpectedServiceIDs = @(1a5d6cc5d5f07e3e)
)

# Exit codes for Datto RMM
$EXIT_SUCCESS = 0
$EXIT_WARNING = 1
$EXIT_ERROR = 2

# Validate that expected IDs were provided
if ($ExpectedServiceIDs.Count -eq 0) {
    Write-Error "No expected ScreenConnect IDs provided."
    exit $EXIT_ERROR
}

# Get all ScreenConnect services
$ScreenConnectServices = Get-Service -Name "ScreenConnect*" -ErrorAction SilentlyContinue

# Check if any ScreenConnect services exist
if ($ScreenConnectServices.Count -eq 0) {
    Write-Error "No ScreenConnect services found."
    exit $EXIT_ERROR
}

# Extract service IDs and validate against expected values
$FoundServiceIDs = @()
foreach ($Service in $ScreenConnectServices) {
    # Extract ID from service name format "ScreenConnect (ID)"
    if ($Service.Name -match "ScreenConnect\s*\(([^)]+)\)") {
        $FoundServiceIDs += $matches[1]
    }
}

# Compare found IDs with expected IDs
$ValidatedIDs = $FoundServiceIDs | Where-Object { $_ -in $ExpectedServiceIDs }

if ($ValidatedIDs.Count -ne $FoundServiceIDs.Count) {
    $UnexpectedIDs = $FoundServiceIDs | Where-Object { $_ -notin $ExpectedServiceIDs }
    Write-Error "Unexpected ScreenConnect service IDs found: $($UnexpectedIDs -join ', ')"
    exit $EXIT_ERROR
}

Write-Output "All ScreenConnect services validated successfully. Found IDs: $($ValidatedIDs -join ', ')"
exit $EXIT_SUCCESS