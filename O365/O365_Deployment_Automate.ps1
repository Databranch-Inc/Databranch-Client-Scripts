<#

#>

Expand-Archive \\CM-FS01\data\deployments\O365.zip -destinationpath C:\Databranch\O365\O365

Start-Process -FilePath "C:\databranch\o365\o365\setup.exe" -ArgumentList "/configure C:\databranch\o365\o365\Cameron_MFG_O365_Config.xml" -Wait -Passthru

C:\databranch\o365\o365\setup.exe /configure C:\databranch\o365\o365\Cameron_MFG_O365_Config.xml