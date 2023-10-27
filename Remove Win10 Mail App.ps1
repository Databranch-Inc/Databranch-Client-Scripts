Write-Output "Removing Windows 10 Mail Appx Package"
Get-AppxPackage Microsoft.windowscommunicationsapps | Remove-AppxPackage
Get-AppxPackage Microsoft.windowscommunicationsapps | Remove-AppxPackage -Allusers
if(Get-AppxPackage -Name Microsoft.windowscommunicationsapps -AllUsers){
Get-AppxPackage -Name Microsoft.windowscommunicationsapps -AllUsers | Remove-AppxPackage -AllUsers - Verbose -ErrorAction Continue
}
else{
Write-Output "Mail app is not installed for any user"
}
if(Get-ProvisionedAppxPackage -Online | Where-Object {$_.Displayname -match "Microsoft.windowscommunicationsapps"}){
Get-ProvisionedAppxPackage -Online |Where-Object {$_.DisplayName -Match "Microsoft.windowscommunicationsapps"} | Remove-AppxProvisionedPackage -Online -AllUsers -Verbose -ErrorAction Continue
}
else {
Write-Output "Mail app is not installed for the system"
}

Exit