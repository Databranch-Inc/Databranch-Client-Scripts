param(
    [Parameter(Mandatory=$true)]
    [string]$FolderPath
)

function Test-UserHasReadWritePermission {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$SamAccountName
    )

    try {
        $acl = Get-Acl -Path $Path -ErrorAction Stop
    }
    catch {
        return $false
    }

    $requiredRights = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [System.Security.AccessControl.FileSystemRights]::Write

    foreach ($rule in $acl.Access) {
        $ruleAccount = $rule.IdentityReference.Value.Split('\\')[-1]
        if ($ruleAccount -ieq $SamAccountName -and $rule.AccessControlType -eq 'Allow') {
            if (($rule.FileSystemRights -band $requiredRights) -eq $requiredRights) {
                return $true
            }
        }
    }

    return $false
}

if (-not (Test-Path -Path $FolderPath -PathType Container)) {
    Write-Error "Folder path '$FolderPath' does not exist or is not a directory."
    exit 1
}

$directoryNames = Get-ChildItem -Path $FolderPath -Directory | Select-Object -ExpandProperty Name

foreach ($directoryName in $directoryNames) {
    try {
        $adUser = Get-ADUser -Identity $directoryName
        Write-Output "Match found for '$directoryName': $($adUser.SamAccountName)"

        $userFolder = Join-Path -Path $FolderPath -ChildPath $directoryName
        $pathsToCheck = @($userFolder)
        $pathsToCheck += Get-ChildItem -Path $userFolder -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName

        $failures = @()
        foreach ($path in $pathsToCheck) {
            if (-not (Test-UserHasReadWritePermission -Path $path -SamAccountName $adUser.SamAccountName)) {
                $failures += $path
            }
        }

        if ($failures.Count -eq 0) {
            Write-Output "User '$($adUser.SamAccountName)' has Read/Write permissions on '$userFolder' and all subitems."
        }
        else {
            Write-Output "User '$($adUser.SamAccountName)' is missing Read/Write permissions on the following paths:"
            $failures | ForEach-Object { Write-Output "  $_" }
        }
    }
    catch {
        Write-Output "No AD match found for '$directoryName'"
    }
}



