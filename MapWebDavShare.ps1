<#Map WebDav Share

This script maps the User's L Drive to the CW Automate Server WebDAV Share

This script uses the Encrypted Password created in the Password Encryptor Script.

Josh Britton 7-31-23

1.0
#>

#Create PS Credentials
$User = "databranch2740"
$PasswordFile = "C:\Databranch\ENCPassword.txt"
$KeyFile = "C:\Databranch\AES.key"
$Key = Get-Content $KeyFile
$MyCredential = New-Object -TypeName System.Management.Automation.PSCredential `
 -ArgumentList $User, (Get-Content $PasswordFile | ConvertTo-SecureString -Key $key)

#Set WebDav Share Variable

[String]$WebDavShare = '\\databranch.hostedrmm.com@ssl\share'



 #Map Drive with PS Credentials

 if (Get-PSDrive L -ErrorAction SilentlyContinue) {
    Write-Host 'The L: drive is already mapped. Remapping'
    Get-PSDrive L | Remove-PSDrive -Force
    New-PSDrive -Name "L" -PSProvider FileSystem -Root $WebDavShare -Credential $MyCredential -Persist -Scope Global
} 
else {
    Write-Host 'The L: drive is not mapped. Mapping'
    New-PSDrive -Name "L" -PSProvider FileSystem -Root $WebDavShare -Credential $MyCredential -Persist -Scope Global
 }