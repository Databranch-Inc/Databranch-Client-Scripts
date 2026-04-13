Invoke-Command -ComputerName AAA3-24 -Credential (Get-Credential) -ScriptBlock {
    $username = "kgullo"
    $sid = (New-Object Security.Principal.NTAccount("JOHNMILLSELECT\$username")).Translate([Security.Principal.SecurityIdentifier]).Value

    Write-Host "SID: $sid"
    Write-Host "HKU hive mounted: $(Test-Path Registry::HKEY_USERS\$sid)"

    # Use Registry:: provider directly — works whether hive is loaded or not
    Write-Host "`nShell Folders (effective):"
    Get-ItemProperty "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -ErrorAction SilentlyContinue | 
        Select-Object Desktop, Personal, 'My Pictures', 'My Music', 'My Video' | Format-List

    Write-Host "User Shell Folders (policy/redirects):"
    Get-ItemProperty "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" -ErrorAction SilentlyContinue | 
        Select-Object Desktop, Personal, 'My Pictures', 'My Music', 'My Video' | Format-List

    Write-Host "Folder Redirection GPO policy (HKCU equivalent):"
    Get-ItemProperty "Registry::HKEY_USERS\$sid\Software\Policies\Microsoft\Windows\System" -ErrorAction SilentlyContinue |
        Select-Object DisableFROnInternetOpen, RestoreShellFolders | Format-List
}