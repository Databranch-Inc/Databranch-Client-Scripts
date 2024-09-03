<#
Deploy Desktop Contact Info

This Script will check for the Desktop Info.Zip file downloaded from the ConnectWise Automate Server on a machine, extract it to C:\Program Files\Desktop Info and copy the shortcut to the login folder.

Josh Britton

Orininal Write - 8-27-24
Last Update

Version 1.0
===========================================================================================================
1.0 

Original Write
===========================================================================================================
#>

function Install-DatabranchDesktopInfo{

#Test for folder C:\Databranch
If (Test-Path C:\Databranch)
    {
    $DBFoldertest = "C:\Databranch exists"

    If (Test-path C:\Databranch\Logs){
        $DBLogFolderTest = "C:\Databranch\Logs exists"
    } 

    Else{
        $DBLogFolderTest = "C:\Databranch\Logs needs to be created"
        New-Item -ItemType Directory -Path C:\Databranch -Name Logs
    }
    }
Else
    {
    $DBFoldertest = "C:\Databranch needs to be created"
    $DBLogFolderTest = "C:\Databranch\Logs needs to be created"

    New-Item -ItemType Directory -Path C:\ -Name Databranch
    New-Item -ItemType Directory -Path C:\Databranch -Name Logs
    }
     
#Check for Zip File
$ZipFile = "C:\Databranch\DesktopInfo\Desktop Info Databranch.Zip"

If (Test-Path $ZipFile){

    $ZipFileTest = "C:\Databranch\DesktopInfo\Desktop Info Databranch.Zip exists"

    #Extract Files
    Expand-Archive -LiteralPath $ZipFile -DestinationPath "C:\Program Files\Databranch"

    #Move shortcut to Startup folder
    Copy-Item -LiteralPath "C:\Program Files\Databranch\Desktop Info Databranch\DesktopInfo64.exe - Shortcut.lnk" -Destination “C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp” -Force

}
Else{

    $ZipFileTest = "C:\Databranch\DesktopInfo\DesktopInfo Databranch.Zip does not exist. Exiting PS Script and noting Autoamte"
  
}

#Test file copies
If (Test-Path “C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp”){

    $DeploymentStatus = "Deployment Complete"

}
Else{
    $DeploymentStatus = "Deployment Failed"

}

#Create Array of variables that can be pulled into CW Automate
$obj = @{}
$obj.DBFoldertest = $DBFoldertest
$obj.DBLogFolderTest = $DBLogFolderTest
$obj.ZipFileTest = $ZipFileTest
$obj.$DeploymentStatus = $DeploymentStatus
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final

}