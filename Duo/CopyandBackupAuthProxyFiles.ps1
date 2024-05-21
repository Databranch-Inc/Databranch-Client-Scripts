<#Copy and Backup Proxy Files

Script is used to create a password protected .ZIP file of the Duo Auth Proxy Config and Log files.

This is used to backup the files on a Duo Auth Proxy server before the service is upgraded. This is used to follow best practice from Duo Documentaiton

https://help.duo.com/s/article/2937?language=en_US
https://duo.com/docs/authproxy-reference#upgrading-the-proxy

Josh Britton

1.0

2-7-24

#>

#Variable Set:
$date = get-date -Format "MM-dd-yyyy"
$ConfigFolder = "C:\Program Files\Duo Security Authentication Proxy\conf"

Compress-Archive -Path $ConfigFolder -DestinationPath "C:\databranch\DuoAuthBackup$date.zip" | Out-Null

if (Test-Path "C:\databranch\DuoAuthBackup$date.zip"){
Write-Host "Duo config backup saved at C:\databranch\DuoAuthBackup$date.zip"
}

else{
Write-Host "Duo config backup does not exist."
}