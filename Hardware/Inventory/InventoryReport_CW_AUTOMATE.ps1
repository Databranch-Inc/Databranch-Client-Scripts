<#
Databranch inventory report
This script will gather the current Servers, Desktops, and Users from Active Directory, and will give general infomration about them. Then, the data will be combined to create .CSV files for Databranch inventory.

Josh Britton
Current Version 2.1

Last Update - 1-24-25
Original Created Date - 9-23-19
=======================================================================================================
2.1 Update

Removing Desktop model lookup and Function to attempt to re-organize the .csv files. This should have a massive performance boost on the script time and will save failures/overhead.

JB - 1-24-25

==============================================================================================================

2.0 Update

New Items:
Updated File checks to review for log folder locations and create if found
Created AD Check functions for user and computer objects - This will look for inactive items over 90 days, disabled items not in the proper OU, and disbled items to delete.
Checking for Disabled Items OU and Do not Disabel AD group, will exit script if group is not found after attempting to create.
Added a transaction log, will be pulled into CW Autoamte via Automate script at a later time

JB - 7-29-24

=======================================================================================================
1.5 Update

Cleaning process for end file creation. Adding check and notes to review PC Last Logon Dates and disable/move disabled items to Disabled OU at root of Directory - JB 9-5-23
========================================================================================================
1.4 Update

Adding logic to test for previous inventory files before attempting to delete. This should reduce false error messages. -JB 9/23/19

========================================================================================================
1.3.2 Update

Re-located if/else to test for C:\Databranch Folder to have it created before running AD Exports

========================================================================================================
1.3.1 Update - Added if/else to test for C:\Databranch Folder.
#>

function Initialize-DatabranchADInventory{

#Import AD Module into shell
Import-Module ActiveDirectory

#Inital Variable Set
#Dates
$Date = Get-Date -Format "MM/dd/yyyy hh:mm:ss tt"
$90DaysAgo =(Get-Date).AddDays(-90)
$DisableDate = Get-Date -Date $90DaysAgo -Format "MM/dd/yyyy hh:mm:ss tt"
$TranscriptDate = Get-Date -Format "MM-dd-yyyy_hhmmsstt"
 

#Test for folder C:\Databranch
If (Test-Path C:\Databranch)
    {
    Write-Host "C:\Databranch exists" -ForegroundColor Green

    If (Test-path C:\Databranch\Logs){
        Write-Host "C:\Databranch\Logs exists" -ForegroundColor Green
    } 

    Else{
        New-Item -ItemType Directory -Path C:\Databranch -Name Logs
    }
    }
Else
    {
    New-Item -ItemType Directory -Path C:\ -Name Databranch
    New-Item -ItemType Directory -Path C:\Databranch -Name Logs
    }
     
#Start Transcript for AD Actions:
Start-Transcript -Path "C:\Databranch\Logs\DB_Inventory_Script_Logs_$TranscriptDate.txt" -NoClobber
$Transcript = "C:\Databranch\Logs\DB_Inventory_Script_Logs_$TranscriptDate.txt"

#Clear old files from C:\Databranch to avoid duplicate entries
Write-Host "Performing cleanup on old Desktop info files" -ForegroundColor Green

#Create Array of files to check
$FileNames = @("FINAL","MODELADDED","MODELS","SERIAL")

foreach ($FileName in $FileNames)
{
if  (Test-Path "C:\Databranch\desktops$FileName.csv")
    { 
    Write-Host "C:\Databranch\desktops$FileName.csv exists. Removing file." -ForegroundColor Green
    Remove-Item -path "C:\Databranch\desktops$FileName.csv"
    }
    
Else
    {
    Write-Host "C:\Databranch\desktops$FileName.csv does not exist. Moving to next file." -ForegroundColor Green
    }
}

#These commands generate files called desktopsAD.csv, usersAD.csv and serverAD.csv at the root of drive C. Updated 6/28/18 - Added aditional filter to the server pull to include the wildcard for the registerd symbol (®) in Windows® Small Business Server 2011 Standard - Josh Britton

Write-Host "Gathering AD Information" -ForegroundColor Green

#Get AD information for desktops and laptops
GET-ADCOMPUTER -filter {OperatingSystem -NotLike "*server*"} -properties * |select-object name,OperatingSystem,lastlogondate,enabled,ipv4address,description,DistinguishedName| Export-csv C:\Databranch\desktopsAD.csv -notypeinformation -encoding utf8

#Get AD information for users
GET-ADUSER -filter * -properties * |select-object name,lastlogondate,enabled,description,DistinguishedName | Export-csv C:\Databranch\usersAD.csv -notypeinformation -encoding utf8

#Get AD information for servers
GET-ADCOMPUTER -filter {OperatingSystem -Like "Windows* *server*"} -properties * |select-object name,OperatingSystem,lastlogondate,enabled,ipv4address,description,DistinguishedName| Export-csv C:\Databranch\serverAD.csv -notypeinformation -encoding utf8


<#======================================================================================================

AD Cleanups

========================================================================================================#>

#Check for Disabled Items OU
if (Get-ADOrganizationalUnit -Filter 'Name -eq "Disabled Items"' ){

    Write-Host "Disabled Items OU found." -ForegroundColor Green
    
    }
    
    else{
    #Create Disabled Items OU
    New-ADOrganizationalUnit -Name "Disabled Items"
    }
    

#Check for "Do Not Disable AD Group"
$group = "Do not Disable"

if (Get-ADGroup -Identity $group){

    Write-host "$Group AD Group found in Active Directory. Moving to disable and delete actions" -ForegroundColor Green
}
Else{

    Write-host "$group AD Group not found in in Active Directory. Creating this group and skipping disable and delete actions" -ForegroundColor Cyan
    New-Adgroup -Name $group -Description "Items in this group will not be disabled via the Databranch Inventory Script"
    if (Get-ADGroup -Identity $group){
        Write-Host "$Group AD Group successfully created in Active Directory. Since this is a new group, review is needed to add members to this group before additional run. Exiting Script" -ForegroundColor Yellow
        Exit-PSHostProcess
    }
    Else{
        Write-Host "$Group AD Group failed to create in Active Directory. Review and resolve erorrs before attempting to run script again. Exiting Script" -ForegroundColor Red
        Exit-PSHostProcess
    }
}

#Move Disabled items to OU

#Upload Items to review for last login, and move legacy items to Disabled Items 
$DisabledOU = Get-ADOrganizationalUnit -Filter 'Name -eq "Disabled Items"' | Select-Object * -ExpandProperty DistinguishedName

#Desktop Check
$DesktopExpChecks = Search-ADAccount -ComputersOnly -AccountInactive -TimeSpan (New-TimeSpan -Days 90) | Where-Object -Property enabled -EQ True | Select-Object name,lastlogondate,enabled
    
foreach ($DesktopExpCheck in $DesktopExpChecks){
    
    $Authorization = Get-ADGroupMember -Identity $group | Where-Object {$_.name -eq $DesktopExpCheck.Name}
    if ($Authorization){ 
        Write-Host ""$DesktopExpCheck.Name" is a member of the AD Group Do Not Disable. This object will not be disabled or moved in AD" -ForegroundColor Cyan
        
    }
    else{       
        Get-ADComputer -Identity $DesktopExpCheck.Name | Disable-ADAccount -PassThru 
        $DesktopDescription = Get-ADComputer -Identity $DesktopExpCheck.Name | Select-Object -ExpandProperty Description
        Move-ADObject  -Identity $DesktopExpCheck.Name -TargetPath $DisabledOU
        Set-ADComputer -Identity $DesktopExpCheck.Name -Description "$Desktopdescription | Disabled on $date by Databranch AD Inventory Script"
        Write-Host ""$DesktopExpCheck.Name" has been moved to Disabled Items" -ForegroundColor Yellow
    }
}            

#User Check
$UserExpChecks = Search-ADAccount -UsersOnly -AccountInactive -TimeSpan (New-TimeSpan -Days 90) | Where-Object -Property enabled -EQ True | Select-Object name,SamAccountName,ObjectGUID,lastlogondate,Description,enabled

foreach ($UserExpCheck in $UserExpChecks){
    $group = "Do not Disable"    
    $Authorization = Get-ADGroupMember -Identity $group | Where-Object {$_.name -eq $UserExpCheck.Name}
    if ($Authorization){ 
        Write-Host ""$UserExpCheck.Name" is a member of the AD Group Do Not Disable. This object will not be disabled or moved in AD" -ForegroundColor Cyan
        
    }
    else{       
        Get-ADUser -Identity $UserExpCheck.SamAccountName | Disable-ADAccount -PassThru
        $UserDescription =  Get-ADUser -Identity $UserExpCheck.SamAccountName -Properties Description | Select-Object -ExpandProperty Description
        Move-ADObject -Identity $UserExpCheck.ObjectGUID -TargetPath $DisabledOU
        Set-ADUser -Identity $UserExpCheck.SamAccountName -Description "$UserDescription | Disabled on $date by Databranch AD Inventory Script"
        Write-Host ""$UserExpCheck.SamAccountName" has been moved to Disabled Items" -ForegroundColor Yellow
    }
}    

#Move disabled users and computers from other OUs to Disabled Items OU
$DisabledObjectCleanups = Search-ADAccount -AccountDisabled | Where-Object {$_.DistinguishedName -NotLike "*OU=Disabled Items,*"} | Select-Object SamAccountName,ObjectGUID,objectclass

foreach ($DisabledObjectCleanup in $DisabledObjectCleanups){
    if ($DisabledObjectCleanup.objectclass -eq "user"){
        $UserDescription =  Get-ADUser -Identity $DisabledObjectCleanup.SamAccountName -Properties Description | Select-Object -ExpandProperty Description
        Move-ADObject -Identity $DisabledObjectCleanup.ObjectGUID -TargetPath $DisabledOU
        Set-ADUser -Identity $DisabledObjectCleanup.SamAccountName -Description "$UserDescription | Moved to Disabled Items on $date by Databranch AD Inventory Script"
        Write-Host ""$DisabledObjectCleanup.SamAccountName" was already disabled but not in the Disabled Items OU. "$DisabledObjectCleanup.SamAccountName" has been moved to Disabled Items" -ForegroundColor Yellow
    }
    elseif($DisabledObjectCleanup.objectclass -eq "computer"){
        Write-Host ""$DisabledObjectCleanup.SamAccountName" is not a user object" -ForegroundColor Cyan
        $ComputerDescription =  Get-ADComputer -Identity $DisabledObjectCleanup.SamAccountName -Properties Description | Select-Object -ExpandProperty Description
        Move-ADObject -Identity $DisabledObjectCleanup.ObjectGUID -TargetPath $DisabledOU
        Set-ADComputer -Identity $DisabledObjectCleanup.SamAccountName -Description "$ComputerDescription | Moved to Disabled Items on $date by Databranch AD Inventory Script"
        Write-Host ""$DisabledObjectCleanup.SamAccountName" was already disabled but not in the Disabled Items OU. "$DisabledObjectCleanup.SamAccountName" has been moved to Disabled Items" -ForegroundColor Yellow
    }
    else{
        Write-host ""$DisabledObjectCleanup.SamAccountName" is not a user or computer object" -ForegroundColor Cyan
    }
}

#Check Disabled Items OU for items to delete

#Desktop Check
$DisabledComputers = Get-ADComputer -Filter * -SearchBase $DisabledOU | Where-Object {$_.Enabled -eq $False} | Select-Object -ExpandProperty name

foreach ($DisabledComputer in $DisabledComputers){
    $ObjectDisabledDateAttribute = Get-ADComputer -Identity $DisabledComputer -Properties whenChanged | select-object -ExpandProperty whenChanged
    $ObjectDisabledDateConverted = ($ObjectDisabledDateAttribute).tostring("MM/dd/yyyy hh:mm:ss tt")

    if($ObjectDisabledDateConverted -lt $DisableDate){
        Write-Host "Computer object $DisabledComputer been disabled longer than 90 days. Deleting from AD" -ForegroundColor Yellow
        Remove-ADComputer -Identity $DisabledComputer -Confirm:$False
    }
    else{
        Write-Host "Comptuer object $DisabledComputer has NOT been disabled longer than 90 days. Moving to next object" -ForegroundColor Cyan
   }
}

#User Check
$DisabledUsers = Get-ADuser -Filter * -SearchBase $DisabledOU | Where-Object {$_.Enabled -eq $False} | Select-Object -ExpandProperty samaccountname

foreach ($DisabledUser in $DisabledUsers){
    $ObjectDisabledDateAttribute = Get-ADUser -Identity $DisabledUser -Properties whenChanged | select-object -ExpandProperty whenChanged
    $ObjectDisabledDateConverted = ($ObjectDisabledDateAttribute).tostring("MM/dd/yyyy hh:mm:ss tt")

    if($ObjectDisabledDateConverted -lt $DisableDate){
        Write-Host "User object $Disableduser has been disabled longer than 90 days. Deleting from AD" -ForegroundColor Yellow
        Remove-ADUser -Identity $DisabledUser -Confirm:$False
    }
    else{
        Write-Host "User object $Disableduser has NOT been disabled longer than 90 days. Moving to next object" -ForegroundColor Cyan
   }
}


#Stop Transcript of AD Actions
Stop-Transcript

#Create Array of variables that can be pulled into CW Automate

$obj = @{}
$obj.Transcript = $Transcript
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final

}