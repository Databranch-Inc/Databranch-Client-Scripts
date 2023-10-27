<#
Fix Font Permisisons.PS1
Josh Britton
Origional Date 7-9-2019

Reference
https://answers.microsoft.com/en-us/msoffice/forum/all/there-is-insufficient-memory-or-disk-space-word/18c6b103-1ec6-46be-ba75-3cd0b845b283

Version 1.0

#>

<#Copy permissions from a base font and apply to all fonts installed on the PC

Get-acl C:\Windows\fonts\arial.ttf | Set-Acl -path c:\windows\fonts\*.*

Get-acl C:\Windows\fonts\arial.ttf | Set-Acl -path c:\windows\fonts

#>