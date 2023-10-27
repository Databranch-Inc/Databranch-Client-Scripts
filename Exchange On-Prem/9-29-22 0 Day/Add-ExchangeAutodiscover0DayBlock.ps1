Import-Module WebAdministration

Invoke-WebRequest -UseBasicParsing -Uri 'https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi' -OutFile "$env:windir\temp\rewrite.msi"

Start-Process -FilePath "$env:windir\system32\msiexec.exe" -ArgumentList '/i', "$env:windir\temp\rewrite.msi", '/qn'
Start-Sleep -Seconds 300

$name = 'Block AutoDiscover 0-Day'
$inbound = '.*autodiscover\.json.*\@.*Powershell.*'
$site = 'IIS:\Sites\Default Web Site'
$root = 'system.webServer/rewrite/rules'
$filter = "{0}/rule[@name='{1}']" -f $root, $name

Add-WebConfigurationProperty -PSPath $site -filter $root -name '.' -value @{name = $name; patterSyntax = 'Regular Expressions'; stopProcessing = 'False' }
Set-WebConfigurationProperty -PSPath $site -filter "$filter/match" -name 'url' -value $inbound
Set-WebConfigurationProperty -PSPath $site -filter "$filter/action" -name 'type' -value 'CustomResponse'
Set-WebConfigurationProperty -PSPath $site -filter "$filter/action" -name 'statusCode' -value 403
Set-WebConfigurationProperty -PSPath $site -filter "$filter/action" -name 'statusReason' -value 'Forbidden'