<#Password Encryptor

This script is used to encrypt password inputs and save to a target location for future script calls.

Josh Britton

7-27-23

1.0
#>

#Generate AES Key and Export to File
$KeyFile = "C:\Databranch\AES.key"
$Key = New-Object Byte[] 16   # You can use 16, 24, or 32 for AES
[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Key)
$Key | out-file $KeyFile


#Gather the password to encrypt from a Read Host Prompt, save in C:\Databranch
$PasswordFile = "C:\Databranch\ENCPassword.txt"
$KeyFile = "C:\Databranch\AES.key"
$Key = Get-Content $KeyFile
$Password = Read-Host "Enter Password" -AsSecureString |  ConvertFrom-SecureString -key $Key | Out-File $PasswordFile