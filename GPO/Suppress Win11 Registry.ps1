<#Suppress Windows 11 Update RegKey
Specifies registry keys to prevent Windows update to Windows 11

Josh Britton

0.1 

10/4/21
#>

$path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"


New-ItemProperty -Path $path -Name "TargetReleaseVersion" -Value 00000001 -PropertyType dword
New-ItemProperty -Path $path -Name "ProductVersion" -Value "Windows 10" -PropertyType string
New-ItemProperty -Path $path -Name "TargetReleaseVersionInfo" -Value "21H1" -PropertyType string