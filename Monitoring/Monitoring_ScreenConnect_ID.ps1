# Script to verify ScreenConnect services match expected configuration IDs
# Used as a component for Datto RMM monitoring

param(
    [string[]]$ExpectedServiceIDs = @("1a5d6cc5d5f07e3e", "595fd337e1c95b7c")
)

# Exit codes for Datto RMM
$EXIT_SUCCESS = 0
$EXIT_ERROR = 1

# Validate that expected IDs were provided
if ($ExpectedServiceIDs.Count -eq 0) {
    write-host '<-Start Result->'
    "RESULT=No expected ScreenConnect IDs provided."
    write-host '<-End Result->'
    exit $EXIT_ERROR
}

# Get all ScreenConnect services
$ScreenConnectServices = Get-Service -Name "ScreenConnect*" -ErrorAction SilentlyContinue

# Check if any ScreenConnect services exist
if ($ScreenConnectServices.Count -eq 0) {
    write-host '<-Start Result->'
    "RESULT=No ScreenConnect services found."
    write-host '<-End Result->'
    exit $EXIT_ERROR
}

# Extract service IDs and validate against expected values
$FoundServiceIDs = @()
foreach ($Service in $ScreenConnectServices) {
    # Extract ID from service name format "ScreenConnect (ID)"
    if ($Service.Name -match "ScreenConnect Client\s*\(([^)]+)\)") {
        $FoundServiceIDs += $matches[1]
    }
}

# Compare found IDs with expected IDs
$ValidatedIDs = $FoundServiceIDs | Where-Object { $_ -in $ExpectedServiceIDs }

if ($ValidatedIDs.Count -ne $FoundServiceIDs.Count) {
    $UnexpectedIDs = $FoundServiceIDs | Where-Object { $_ -notin $ExpectedServiceIDs }
    write-host '<-Start Result->'
    "RESULT=Unexpected ScreenConnect service IDs found: $($UnexpectedIDs -join ', ')"
    write-host '<-End Result->'
    exit $EXIT_ERROR
}

write-host '<-Start Result->'
"RESULT=All ScreenConnect services validated successfully. Found IDs: $($ValidatedIDs -join ', ')"
write-host '<-End Result->'
exit $EXIT_SUCCESS