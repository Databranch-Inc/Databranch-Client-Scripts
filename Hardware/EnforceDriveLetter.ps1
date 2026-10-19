#Requires -Version 5.1

<#
.SYNOPSIS
    Ensures a known removable disk is mounted as drive letter E:.

.DESCRIPTION
    Checks the Datto RMM DiskSerialNumber component variable first.
    If not provided, falls back to a maintained list of known serial numbers.

    When a matching disk is found, the first mounted partition is assigned
    drive letter E: if it is not already mounted as E:.

.NOTES
    Script Name : Invoke-EnforceDriveLetter.ps1
    Version     : v1.0.0.001
    Author      : Josh Britton
    Modified By : Josh Britton

    Exit Codes:
        0 = Success
        1 = Runtime failure
        2 = Fatal/pre-flight failure

.CHANGELOG
    v1.0.0.001
        - Initial release
#>

[CmdletBinding()]
param (
    [string]$DiskSerialNumber = $(if ($env:DiskSerialNumber) { $env:DiskSerialNumber } else { '' })
)

function Invoke-EnforceDriveLetter {

    $ErrorActionPreference = 'Stop'
    $ScriptVersion = 'v1.0.0.001'

    #==========================================================================
    # Maintained Serial Number List
    #==========================================================================

    $KnownSerials = @(
        'SERIALNUMBER1',
        'SERIALNUMBER2',
        'SERIALNUMBER3'
    ) | ForEach-Object {
        $_.Trim().ToUpper()
    }

    #==========================================================================
    # Logging Function
    #==========================================================================

    function Write-Log {
        param(
            [Parameter(Mandatory)]
            [string]$Message,

            [ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG')]
            [string]$Severity = 'INFO'
        )

        $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

        Write-Output ('[{0}] [{1}] {2}' -f $Timestamp, $Severity, $Message)
    }

    #==========================================================================
    # Serial Number Normalization
    #==========================================================================

    function Normalize-SerialNumber {
        param(
            [string]$SerialNumber
        )

        if ([string]::IsNullOrWhiteSpace($SerialNumber)) {
            return $null
        }

        return (($SerialNumber -replace '\s+', '').Trim().ToUpper())
    }

    try {

        Write-Log "======================================================"
        Write-Log "Invoke-EnforceDriveLetter $ScriptVersion"
        Write-Log "Site     : $($env:CS_PROFILE_NAME)"
        Write-Log "Hostname : $($env:CS_HOSTNAME)"
        Write-Log "======================================================"

        #======================================================================
        # Determine Target Mode
        #======================================================================

        $TargetSerial = $null

        if (-not [string]::IsNullOrWhiteSpace($DiskSerialNumber)) {

            $TargetSerial = Normalize-SerialNumber $DiskSerialNumber

            Write-Log "Using Datto RMM DiskSerialNumber variable."
            Write-Log "Target Serial: $TargetSerial" "DEBUG"
        }
        else {

            Write-Log "DiskSerialNumber not specified."
            Write-Log "Using maintained serial number list."
        }

        #======================================================================
        # Enumerate Disks
        #======================================================================

        $Disks = @(Get-Disk)

        if ($Disks.Count -eq 0) {
            throw "No disks were returned by Get-Disk."
        }

        Write-Log "Detected $($Disks.Count) disk(s)." "DEBUG"

        #======================================================================
        # Locate Matching Disk
        #======================================================================

        $MatchedDisk = $null

        foreach ($Disk in $Disks) {

            $CurrentSerial = Normalize-SerialNumber $Disk.SerialNumber

            if ([string]::IsNullOrWhiteSpace($CurrentSerial)) {
                continue
            }

            if ($TargetSerial) {

                if ($CurrentSerial -eq $TargetSerial) {
                    $MatchedDisk = $Disk
                    break
                }
            }
            else {

                if ($KnownSerials -contains $CurrentSerial) {
                    $MatchedDisk = $Disk
                    break
                }
            }
        }

        if (-not $MatchedDisk) {

            Write-Log "No matching disk detected." "WARN"
            return 0
        }

        Write-Log "Matched Disk Number : $($MatchedDisk.Number)"
        Write-Log "Matched Disk Model  : $($MatchedDisk.FriendlyName)"
        Write-Log "Matched Disk Serial : $($MatchedDisk.SerialNumber)"

        #======================================================================
        # Find Mounted Partition
        #======================================================================

        $Partition = Get-Partition -DiskNumber $MatchedDisk.Number |
            Where-Object { $_.DriveLetter } |
            Select-Object -First 1

        if (-not $Partition) {
            throw "No mounted partition found on matched disk."
        }

        Write-Log "Current Drive Letter: $($Partition.DriveLetter)"

        #======================================================================
        # Already E:
        #======================================================================

        if ($Partition.DriveLetter -eq 'E') {

            Write-Log "Disk is already mounted as E:" "SUCCESS"
            return 0
        }

        #======================================================================
        # Verify E: Availability
        #======================================================================

        $ExistingE = Get-Partition -DriveLetter E -ErrorAction SilentlyContinue

        if ($ExistingE) {

            Write-Log "Drive letter E: is already assigned to another volume." "WARN"

            $UsedDriveLetters = @(Get-Partition |
                Where-Object { $_.DriveLetter } |
                ForEach-Object { [string]$_.DriveLetter })

            $NewDriveLetter = [char[]](73..90) |
                Where-Object { $UsedDriveLetters -notcontains [string]$_ } |
                Select-Object -First 1

            if (-not $NewDriveLetter) {
                throw "No available drive letter was found to move the existing E: partition."
            }

            try {
                Set-Partition `
                    -DiskNumber $ExistingE.DiskNumber `
                    -PartitionNumber $ExistingE.PartitionNumber `
                    -NewDriveLetter ([string]$NewDriveLetter)
            }
            catch {
                if (Get-Partition -DriveLetter E -ErrorAction SilentlyContinue) {
                    Write-Log "No changes made." "WARN"
                }

                throw
            }

            Write-Log "Moved the existing E: partition to $NewDriveLetter`:" "SUCCESS"

        }

        #======================================================================
        # Assign E:
        #======================================================================

        Set-Partition `
            -DiskNumber $MatchedDisk.Number `
            -PartitionNumber $Partition.PartitionNumber `
            -NewDriveLetter 'E'

        Write-Log "Successfully assigned drive letter E:" "SUCCESS"

        return 0
    }
    catch {

        Write-Log $_.Exception.Message "ERROR"
        return 1
    }
}

$Result = Invoke-EnforceDriveLetter

switch ($Result) {
    0 { exit 0 }
    1 { exit 1 }
    default { exit 2 }
}