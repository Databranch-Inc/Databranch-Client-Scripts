

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


# Check Windows OS type
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$isServer = $osInfo.ProductType -eq 3

if ($isServer) {
    $registrationKey = "MTQ5NDc3fGZFdkM3c1JmQ2oteFFtYUhyNHZrZzVD"
} 
else {
    $registrationKey = "MTQ5NDc3fGctYWxVVGVRUDN6OE50eFZDbnVTM3Bt"
    
    # Workstation/Client OS
    $msiCommand = "msiexec.exe /i `"C:\path\to\Taegis_Agent.msi`" REGISTRATION_TYPE=CLIENT "
}

msiexec /i "C:\Databranch\Taegis.msi" REGISTRATIONKEY=$registrationKey REGISTRATIONSERVER=reg.d.taegiscloud.com /quiet /l*v "C:\Databranch\ScriptLogs\taegis_install.log"



Write-Host "Running: $msiCommand"
# Complete the MSI command with additional parameters as needed