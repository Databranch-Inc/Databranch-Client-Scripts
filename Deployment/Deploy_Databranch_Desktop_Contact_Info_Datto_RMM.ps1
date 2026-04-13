<#
Deploy Desktop Contact Info - Datto RMM

This new script is designed to be used with the Datto RMM platform to deploy the Desktop Info application to machines. The script will pull the site inforamtion from the Datto RMM platform and use that to determine which ZIP file to deploy.

Josh Britton

Orininal Write - 8-27-24s
Datto RMM Fork - 2-26-26
Last Update

Version 1.0.1
===========================================================================================================
1.0.1

Fork from Github CW Automate Script - Deploy_Desktop_Contact_Info.ps1 and modified for use with Datto RMM.

New Features - Pull of site variable from Datto RMM to determine which ZIP file to deploy.

Known Custom DeploymentS

    SCS
============================================================================================================
1.0 

Original Write
===========================================================================================================
#>

#Determine Site Code of Agent Running Script
$ClientName = $env:CS_PROFILE_NAME


$CustomInfoClients = @(
    "SCS",
    "Databranch"
)

#SetDate Variable for .ZIP File Versoning - this will be added the Zip files within the component.
$FileVersionDate = "2-26-26"


#All Client Tests
#Test for folder C:\Databranch
If (Test-Path C:\Databranch)
    {
    $DBFoldertest = "C:\Databranch exists"

    If (Test-path C:\Databranch\ScriptLogs){
        $DBLogFolderTest = "C:\Databranch\ScriptLogs exists"
    } 

    Else{
        $DBLogFolderTest = "C:\Databranch\ScriptLogs needs to be created"
        New-Item -ItemType Directory -Path C:\Databranch -Name ScriptLogs
    }
    }
Else
    {
    $DBFoldertest = "C:\Databranch needs to be created"
    $DBLogFolderTest = "C:\Databranch\ScriptLogs needs to be created"

    New-Item -ItemType Directory -Path C:\ -Name Databranch
    New-Item -ItemType Directory -Path C:\Databranch -Name ScriptLogs
    }

    
#Copy Zip file for deployment based on $ClientName Check

$ZipFile = $null

foreach ($Client in $CustomInfoClients) {
    if ($ClientName -eq $Client) {
        $SourceFile = "Desktop Info Databranch - $Client_$FileVersionDate.zip"
        Copy-Item -Path $SourceFile -Destination 'C:\Databranch\DesktopInfo\' -Force -ErrorAction Stop
        $ZipFile = "C:\Databranch\DesktopInfo\$SourceFile"
        break
    }
}

if ($null -eq $ZipFile) {
    $SourceFile = "Desktop Info Databranch - $FileVersionDate.zip"
    Copy-Item -Path $SourceFile -Destination "C:\Databranch\DesktopInfo\" -Force -ErrorAction Stop
    $ZipFile = "C:\Databranch\DesktopInfo\$SourceFile"
}

#Check for Zip File

If (Test-Path $ZipFile){

    $ZipFileTest = "Zip file copied to the agent. Starting extraction."

    #Extract Files
    Expand-Archive -LiteralPath $ZipFile -DestinationPath "C:\Program Files\Databranch\Desktop Info Databranch" -Force

    #Move shortcut to Startup folder
    Copy-Item -LiteralPath "C:\Program Files\Databranch\Desktop Info Databranch\DesktopInfo64.exe - Shortcut.lnk" -Destination 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp' -Force

}
Else{

    $ZipFileTest = "$Zipfile does not exist on agent. Exiting PS Script and noting RMM"
  
}

#Test file copies

$Shortcut = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\DesktopInfo64.exe - Shortcut.lnk'

If (Test-Path $Shortcut ){

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