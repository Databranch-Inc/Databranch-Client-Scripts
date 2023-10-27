#$Token = "gdhshjqbjlvlvxrsdidrwlxmuhpjwmjgaxsiz4h2ff5glawwfiia";
$Token = "bibfiszwzl7ulybquq2e67bun2ysqkuvug3z7qamfyapz3xivyqa";
$tls = "Tls";
$Uninstall =""
$Password = "jjhhh7$$tg!hTd90"
[System.Net.ServicePointManager]::SecurityProtocol = $tls;
If ([string]::IsNullOrEmpty($Uninstall)) {
# Determine wether or not Archon is currently installed
$IsInstalled = $false
$InstalledSoftware = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
foreach($obj in $InstalledSoftware){
if ($obj.GetValue('DisplayName') -match "Archon") {
	Write-Host $obj.GetValue('DisplayName')
$IsInstalled = $true
}
}

# If it is installed
if ($IsInstalled) {
# We skip the install routine
Write-Host "Archon already installed. Skipping"
} else {
# If it is not installed, we do the routine we had previously in place 
Write-Host "Archon not installed. Installing now"
$source = "http://static.zorustech.com.s3.amazonaws.com/downloads/ZorusInstaller.exe";
$destination = "$env:TEMP\ZorusInstaller.exe";
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile($source, $destination)
Write-Host "Downloading Zorus Archon Agent..."
If ([string]::IsNullOrEmpty($Password)) {
Write-Host "Installing Zorus Archon Agent..."
Start-Process -FilePath $destination -ArgumentList "/qn","ARCHON_TOKEN=$Token", "HIDE_TRAY_ICON=1", "HIDE_ADD_REMOVE=1" -Wait
} Else {
Write-Host "Installing Zorus Archon Agent with password..."
Start-Process -FilePath $destination -ArgumentList "/qn","ARCHON_TOKEN=$Token", "HIDE_TRAY_ICON=1", "HIDE_ADD_REMOVE=1" -Wait
} 
Write-Host "Removing Installer..."
Remove-Item -recurse $destination
Write-Host "Job Complete!"
}
} Else {
$source = "http://static.zorustech.com.s3.amazonaws.com/downloads/ZorusAgentRemovalTool.exe";
$destination = "$env:TEMP\ZorusAgentRemovalTool.exe";
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile($source, $destination)
Write-Host "Downloading Zorus Agent Removal Tool..."
If ([string]::IsNullOrEmpty($Password)) {
Write-Host "Uninstalling Zorus Archon Agent..."
Start-Process -FilePath $destination -ArgumentList "-s" -Wait
} Else {
Write-Host "Uninstalling Zorus Archon Agent with password..."
Start-Process -FilePath $destination -ArgumentList "-s", "-p $Password" -Wait
}
Write-Host "Removing Uninstaller..."
Remove-Item -recurse $destination
Write-Host "Job Complete!"
}