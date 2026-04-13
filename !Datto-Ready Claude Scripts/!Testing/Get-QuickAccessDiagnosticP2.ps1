Invoke-Command -ComputerName AAA2-23 -Credential (Get-Credential) -ScriptBlock {
    $username = "jclonch"
    
    # Get profile path from registry
    $profilePath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*" | 
        Where-Object { $_.ProfileImagePath -match $username }).ProfileImagePath

    # QA file check
    $QAPath = "$profilePath\AppData\Roaming\Microsoft\Windows\Recent\AutomaticDestinations"
    $QAFile = Join-Path $QAPath "f01b4d95cf55d32a.automaticDestinations-ms"

    Write-Host "Profile Path : $profilePath"
    Write-Host "QA Folder    : $(Test-Path $QAPath)"
    Write-Host "QA File      : $(Test-Path $QAFile)"
    if (Test-Path $QAFile) {
        $f = Get-Item $QAFile
        Write-Host "Last Write   : $($f.LastWriteTime) ($($f.LastWriteTime.DayOfWeek))"
        Write-Host "Size (bytes) : $($f.Length)"
    }
    Write-Host "`nAll AutomaticDestinations files:"
    if (Test-Path $QAPath) { Get-ChildItem $QAPath | Sort-Object LastWriteTime | Format-Table Name, LastWriteTime, Length -AutoSize }

    # Load their registry hive if not already mounted
    $sid = (New-Object Security.Principal.NTAccount("JOHNMILLSELECT\$username")).Translate([Security.Principal.SecurityIdentifier]).Value
    $hiveLoaded = $false
    if (-not (Test-Path "HKU:\$sid")) {
        reg load "HKU\$sid" "$profilePath\NTUSER.DAT" | Out-Null
        $hiveLoaded = $true
    }

    Write-Host "`nShell Folders (effective):"
    Get-ItemProperty "HKU:\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -ErrorAction SilentlyContinue | 
        Select-Object Desktop, Personal, 'My Pictures', 'My Music', 'My Video' | Format-List

    Write-Host "User Shell Folders (policy):"
    Get-ItemProperty "HKU:\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue | 
        Select-Object Desktop, Personal, 'My Pictures', 'My Music', 'My Video' | Format-List

    if ($hiveLoaded) { reg unload "HKU\$sid" | Out-Null }
}