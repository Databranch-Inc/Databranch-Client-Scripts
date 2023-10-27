<#
******************************************************************************************** 
 # BareMetalADDisasterBackupScript.ps1 
 # Version 1.0 
 # Date: 8/03/2013 
 # Author: Cengiz KUSKAYA (www.Kuskaya.Info) 
 # Description: A PowerShell script to make a full server backup of a Domain Controller, 
 # all group policies, all group policy links, 
 # all Distinguished Name of objects and AD integrated DNS. 
 #********************************************************************************************* 
 # Requirements: 
 # Create a folder named “C:\Script” prior executing the Script and a BATCH file  
 # named C:\Script\DNSBackup.bat . Copy and paste the following commands  
 # into the BATCH file. 
 # dnscmd /enumzones > C:\Script\AllZones.txt 
 # for /f %%a in (C:\Script\AllZones.txt) do dnscmd /ZoneExport %%a Export\%%a.dns 
 # Additionaly, create a Text file named C:\Script\Script.txt. 
 # Paste the following command into the text file “delete shadows all”. 
 # It will delete all full server backup shadow copies for efficient disk space management. 
 #********************************************************************************************* 
#>


#Import required PowerShell Modules 
 Import-Module ActiveDirectory 
 Import-Module GroupPolicy 
 
#Backup baremetal and delete all backups except last 4 copies.START 
 wbadmin start backup -backuptarget:D: -allCritical -vssfull -quiet 
 diskshadow.exe /s C:\Script\Script.txt 
#Backup baremetal and delete all backups except last 4 copies.END 
 
#Backup all Group Policies.START 
 $Computer = gc env:computername 
 $date = Get-Date -format H.m.d.M.yyyy 
 $GPOPath = “D:\WindowsImageBackup\GPOAll” 
$DestGPO = “D:\WindowsImageBackup\GPOAll\” + $Computer + “-” + $date 
 $DestDelGPO = “D:\WindowsImageBackup\GPOAll\*” 
Test-Path -Path $GPOPath -PathType Container 
 if ( -Not (Test-Path $GPOPath)) 
 { 
 $null = New-Item -Path $GPOPath -ItemType Directory 
 } 
 else 
 { 
#Do Nothing 
 } 
 New-Item -Path $DestGPO -ItemType Directory 
 Get-GPO -all | Backup-GPO -path $DestGPO 
 Get-ChildItem $DestDelGPO | where {$_.Lastwritetime -lt (date).adddays(-2)} | Remove-Item -force -recurse -Confirm:$false 
#Backup all Group Policies.END 
 
#Backup all Group Policy Links.START 
 $GPLinkAllPath = “D:\WindowsImageBackup\GPLinkAll” 
$DestGPLinkAllPath = “D:\WindowsImageBackup\GPLinkAll\” + $Computer + “-” + $date 
 $DestGPLinkAllDelPath = “D:\WindowsImageBackup\GPLinkAll\*” 
Test-Path -Path $GPLinkAllPath -PathType Container 
 if ( -Not (Test-Path $GPLinkAllPath)) 
 { 
 $null = New-Item -Path $GPLinkAllPath -ItemType Directory 
 } 
 else 
 { 
#Do Nothing 
 } 
 New-Item -Path $DestGPLinkAllPath -ItemType Directory 
 Get-ADOrganizationalUnit -Filter ‘Name -like “*”‘ | 
foreach-object {(Get-GPInheritance -Target $_.DistinguishedName).GpoLinks} | 
 export-csv $DestGPLinkAllPath\GPLinkBackup.csv -notypeinformation -delimiter ‘;’ 
Get-ChildItem $DestGPLinkAllDelPath | where {$_.Lastwritetime -lt (date).adddays(-5)} | Remove-Item -force -recurse -Confirm:$false 
 #Backup all Group Policy Links.END 
 
#Backup all Distinguished Name of Objects in the Root Domain.START 
 $DNFolderPath = “D:\WindowsImageBackup\DNAll” 
$DNFolderDelPath = “D:\WindowsImageBackup\DNAll\*” 
Test-Path -Path $DNFolderPath -PathType Container 
 if ( -Not (Test-Path $DNFolderPath)) 
 { 
 $null = New-Item -Path $DNFolderPath -ItemType Directory 
 } 
 else 
 { 
#Do Nothing 
 } 
 $DNFileName = “DNBackup_$(get-date -Uformat “%Y%m%d-%H%M%S”).txt” 
$DNFilePath = “D:\WindowsImageBackup\DNAll\$DNFileName” 
$DNList_command = “dsquery * domainroot -scope subtree -attr modifytimestamp distinguishedname -limit 0 > $DNFilePath” 
Invoke-expression $DNList_command 
 Get-ChildItem $DNFolderDelPath | where {$_.Lastwritetime -lt (date).adddays(-10)} | Remove-Item -force -recurse -Confirm:$false 
#Backup all Distinguished Name of Objects in the Root Domain.END 
 
#Backup DNS.START 
 $DNSBackupFolderPath = “D:\WindowsImageBackup\DNSBackup” 
$DNSDestFolderPath = “D:\WindowsImageBackup\DNSBackup\” + $Computer + “-” + $date 
 $DNSOldLogDelPath = “D:\WindowsImageBackup\DNSBackup\*” 
$TempFolderPath = “C:\Script” 
$DNSExportFolderPath = “C:\Windows\System32\DNS\Export” 
Test-Path -Path $DNSBackupFolderPath -PathType Container 
 if ( -Not (Test-Path $DNSBackupFolderPath)) 
 { 
 $null = New-Item -Path $DNSBackupFolderPath -ItemType Directory 
 } 
 else 
 { 
#Do Nothing 
 } 
 Test-Path -Path $DNSExportFolderPath -PathType Container 
 if ( -Not (Test-Path $DNSExportFolderPath)) 
 { 
 $null = New-Item -Path $DNSExportFolderPath -ItemType Directory 
 } 
 else 
 { 
#Do Nothing 
 } 
 C:\Script\DNSBackup.bat 
 New-Item -Path $DNSDestFolderPath -ItemType Directory 
 Copy-Item “C:\Windows\System32\DNS\Export\*” $DNSDestFolderPath 
 Get-ChildItem $DNSOldLogDelPath | where {$_.Lastwritetime -lt (date).adddays(-5)} | Remove-Item -force -recurse -Confirm:$false 
#Backup DNS.END 
 
#Send an e-mail message after the backup operation 
 $smtp = “smtpserver.com” 
$from = “FROM <from@example.com>” 
$to = “TO <to@example.com>” 
$body = “Your message inside the body of your mail. Date: $date Server Name: $server” 
$subject = “Backup at $date on $Computer” 
#Send eMail 
 send-MailMessage -SmtpServer $smtp -From $from -To $to -Subject $subject -Body $body -BodyAsHtml 