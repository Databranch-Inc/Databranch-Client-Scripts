<#Databranch Bitlocker Group Check Automation

This script runs when the ThirdWall Machine not Encrypted Monitor triggers on a PC 
The script will check for the proper AD Group Membership to enable Bitlocker Encryption.

Josh Britton

v1.3.0.1

========================================================================================================
1.3.0.1 Update 8-20-24

Wrapping script as a function for CW Automate Script use. Cleaning up naming convention before Github Commit - JB

========================================================================================================
1.3 Update 6-9-23

Splitting Automation into multiple PowerShell Scripts - This will now be the First Script to Check for AD Group Membership and log the results in the Databranch Folder on the C Drive.

========================================================================================================
1.2 Update

Re-write of ADSI Call to verify Group Membership
========================================================================================================
1.1 Update

Updating script to cleanup un-needed test methods for script actions. Script as of this date is the PowerShell steps in the CW Automate Script
========================================================================================================
#>

Function Get-BitlockerADGroupInfo{

#Test for/create log file
$DatabranchPath = "C:\Databranch"
$LogFilePath =  "$DatabranchPath\Logs"
$LogFileName = "Bitlocker_Encryption_DB.csv"

if(Test-Path $DatabranchPath)
    {
    $DatabranchPathResult = "C:\Databranch Exists"
    }
else {
    $DatabranchPathResult = "C:\Databranch Does not exist. Creating Root folder, Log folder, and Log file"
    New-Item -Path "C:\" -Name "Databranch" -ItemType Directory
    New-Item -Path $DatabranchPath -Name "Logs" -ItemType Directory
    new-item -Path $LogFilePath -Name $LogFileName  -ItemType File
}

If(Test-Path $LogFilePath)
    {
    $LogFolderResult = "C:\Databranch\Logs Exists"
    }
else {
   $LogFolderResult = "C:\Databranch\Logs does not exist. Creating Log folder and Log file" 
   New-Item -Path $DatabranchPath -Name "Logs" -ItemType Directory
   new-item -Path $LogFilePath -Name $LogFileName  -ItemType File
}

if ( Test-Path $LogFilePath\$LogFileName) {
    $LogFileResult = "C:\Databranch\Logs\Bitlocker_Encryption_DB.csv Exists"
}
else {
    $LogFileResult = "C:\Databranch\Logs\Bitlocker_Encryption_DB.csv does not exist. Creating this logfile"
    new-item -Path $LogFilePath -Name $LogFileName  -ItemType File
}

#Function Import
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
 
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information','Warning','Error')]
        [string]$Severity = 'Information'
    )
 
    [pscustomobject]@{
        Time = (Get-Date -f g)
        Message = $Message
        Severity = $Severity
    } | Export-Csv -Path $LogFilePath\$LogFileName -Append -NoTypeInformation
}

Write-Log -Message $DatabranchPathResult -Severity Information
Write-Log -Message $LogFolderResult -Severity Information
Write-Log -Message $LogFileResult -Severity Information

#Use ADSI check for ADGroup Membership

 $groupName = "Bitlocker Encrypted Machines"
 $computerName = $env:COMPUTERNAME
 
 $searcher = [adsisearcher]"(&(objectCategory=computer)(name=$computerName))"
 $test = $searcher.PropertiesToLoad.Add("memberof")
 $result = $searcher.FindOne()
 
 if ($result.Properties["memberof"] -match "^CN=$groupName,") {
     $GroupCheckResult = "Computer is a member of $groupName"
 } else {
     $GroupCheckResult = "Computer is not a member of $groupName"
 }
 
Write-Log -Message $GroupCheckResult -Severity Information

#Create Array of varabiles that can be pulled into CW Automate

$obj = @{}
$obj.GroupCheckResult = $GroupCheckResult
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final
}