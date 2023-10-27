$tls = "Tls";
[System.Net.ServicePointManager]::SecurityProtocol = $tls;

$source = "http://static.zorustech.com.s3.amazonaws.com/downloads/ZorusInstaller.exe";
$destination = "$env:TEMP\ZorusInstaller.exe";


#Invoke-WebRequest -Uri $source -OutFile $destination


$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile($source, $destination)

Write-Host "Downloading Zorus Archon Agent..."