<#
Install_Taegis_Agent.ps1
This script is designed to install the Taegis Agent on a Windows machine. It checks for the existence of the C:\Databranch directory and its ScriptLogs subdirectory, creating them if they do not exist. The script then determines the type of Windows operating system (server or client) and uses the appropriate registration key to install the Taegis Agent silently, logging the installation process to a file in the ScriptLogs directory.

Original Author: Josh Britton
Date: 3-18-26

Version 1.0
==================================================================================================
1.0 - Initial script creation

==================================================================================================
#>

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


# Check Windows OS type and get the appropriate registration key for Taegis Agent installation
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$isServer = $osInfo.ProductType -eq 3

if ($isServer) {
    $registrationKey = "MTQ5NDc3fGZFdkM3c1JmQ2oteFFtYUhyNHZrZzVD"
} 
else {
    $registrationKey = "MTQ5NDc3fGctYWxVVGVRUDN6OE50eFZDbnVTM3Bt"
  
}

msiexec /i ".\Taegis.msi" REGISTRATIONKEY=$registrationKey REGISTRATIONSERVER=reg.d.taegiscloud.com /quiet /l*v "C:\Databranch\ScriptLogs\taegis_install.log"
