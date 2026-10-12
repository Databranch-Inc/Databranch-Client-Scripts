# =====================================================================
# SIMPLE RECYCLE BIN RECOVERY
# =====================================================================

$RecycleBin = 'D:\Data\Users\kmills\Restore March 2025\kmills\Desktop\$RECYCLE.BIN'
$RecoveryRoot = 'D:\Recovered_KMills'

New-Item -ItemType Directory -Path $RecoveryRoot -Force | Out-Null

$Recovered = 0
$Skipped = 0

Get-ChildItem $RecycleBin -Filter '$I*' -File | ForEach-Object {

    try {

        $IFile = $_

        Write-Host "Processing $($IFile.Name)..."

        # Read metadata
        $Bytes = [System.IO.File]::ReadAllBytes($IFile.FullName)

        $RawPath = [System.Text.Encoding]::Unicode.GetString(
            $Bytes[24..($Bytes.Length - 1)]
        )

        # Remove NULLs
        $RawPath = $RawPath -replace "`0", ""

        # Find first UNC path
        $UNCStart = $RawPath.IndexOf('\\')

        if ($UNCStart -lt 0) {
            Write-Warning "No UNC path found in $($IFile.Name)"
            $Skipped++
            return
        }

        $OriginalPath = $RawPath.Substring($UNCStart).Trim()

        # Example:
        # \\jme-fs1\users\kmills\Desktop\File.pdf

        $Parts = $OriginalPath -split '\\'

        # Need at least:
        # '', '', server, share, username, folder, file

        if ($Parts.Count -lt 6) {
            Write-Warning "Unexpected path format: $OriginalPath"
            $Skipped++
            return
        }

        # Build relative path beginning after server/share
        $RelativePath = ($Parts[4..($Parts.Count - 1)] -join '\')

        $DestinationFile = Join-Path $RecoveryRoot $RelativePath
        $DestinationFolder = Split-Path $DestinationFile -Parent

        # Locate matching R file
        $Suffix = $IFile.Name.Substring(2)

        $RFile = Get-ChildItem $RecycleBin -Force |
            Where-Object {
                -not $_.PSIsContainer -and
                $_.Name.StartsWith("`$R$Suffix")
            } |
            Select-Object -First 1

        if (-not $RFile) {

            Write-Warning "No matching R file found for $($IFile.Name)"
            $Skipped++
            return
        }

        # Create destination folder structure
        New-Item `
            -ItemType Directory `
            -Path $DestinationFolder `
            -Force | Out-Null

        # Copy recovered file
        Copy-Item `
            $RFile.FullName `
            $DestinationFile `
            -Force

        Write-Host "Recovered: $RelativePath" -ForegroundColor Green

        $Recovered++

    }
    catch {

        Write-Warning "$($IFile.Name): $($_.Exception.Message)"
        $Skipped++
    }
}

Write-Host ""
Write-Host "Recovery Complete" -ForegroundColor Green
Write-Host "Recovered: $Recovered"
Write-Host "Skipped:   $Skipped"