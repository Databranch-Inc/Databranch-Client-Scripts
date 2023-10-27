<#
=========================================================================================================
Office install (UNC Path)
Template Script that will run an Office 365/2019 install when the instller is located at a UNC Share

Josh Britton
12/18/19

1.0
=========================================================================================================
#>

#Variable Set
#Path to UNC Share - Update this based on client
$UNC = "\\HSWINSDC\Data\Deployment\Office_2019"

Start-Process -FilePath $UNC\setup.exe -ArgumentList "/configure $UNC\Head_Start_Office_2019.xml"