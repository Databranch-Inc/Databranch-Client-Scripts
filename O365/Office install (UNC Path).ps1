<#
=========================================================================================================
Office install (Local Path)
Template Script that will run an Office 365/2019 install when the instller is located at a UNC Share

Josh Britton
3-26-25
=========================================================================================================
1.0

Initial Script - JB
=========================================================================================================
#>

function Install-Office {
    
Expand-Archive -Path %TempDir%\O365\O365.zip -DestinationPath %TempDir%\O365\O365 -force

Write-Output "Files Extracted"

start-process -FilePath %TempDir%\o365\o365\setup.exe -ArgumentList "/configure %TempDir%\o365\o365\remove_office.xml"

Start-Process -FilePath %TempDir%\o365\o365\setup.exe -ArgumentList "/configure %TempDir%\o365\o365\@XML_FILE@"

Write-Output "O365 installed"

}