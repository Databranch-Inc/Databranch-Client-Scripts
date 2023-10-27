$Token = "INSERT DEPLOYMENT TOKEN HERE";

$tls = "Tls";
[System.Net.ServicePointManager]::SecurityProtocol = $tls;

If ([string]::IsNullOrEmpty($Uninstall)) {
 $source = "http://static.zorustech.com.s3.amazonaws.com/downloads/ZorusInstaller.exe";
 $destination = "$env:TEMP\ZorusInstaller.exe";

$WebClient = New-Object System.Net.WebClient
 $WebClient.DownloadFile($source, $destination)

Write-Host "Downloading Zorus Archon Agent..."

If ([string]::IsNullOrEmpty($Password)) {
 Write-Host "Installing Zorus Archon Agent..."
 
 Start-Process -FilePath $destination -ArgumentList "/qn","ARCHON_TOKEN=$Token" -Wait
 } Else {
 Write-Host "Installing Zorus Archon Agent with password..."
 Start-Process -FilePath $destination -ArgumentList "/qn","ARCHON_TOKEN=$Token", "UNINSTALL_PASSWORD=$Password" -Wait
 }

Write-Host "Removing Installer..."
 Remove-Item -recurse $destination
 Write-Host "Job Complete!"
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