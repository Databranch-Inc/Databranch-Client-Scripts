<##>

#Variable Set
# File Location
$FilePath = "C:\users\jbritton\downloads\MediaCreationTool22H2.exe"
  
# Get file size in bytes
$FileSize = (Get-Item -Path $FilePath).Length

#Convert to different scale (KB, MB, GB, update as needed)
$FileSizeMB = ($FileSize/1MB)
$FileSizeMB = "{0:n2}" -f $FileSizeMB

$MonitorSize = 15
$Runtime = Get-Date
$hostname = 


#See if filesize is over threshold, send email if it is over monitor


if($FileSizeMB -gt $MonitorSize){

    #Set Email Server
    $PSEmailServer = "databranch-com.mail.protection.outlook.com"

    #Send email to DBHelp about this error
    Send-MailMessage -From 'alerts@databranch.com' -To 'help@databranch.com' -Subject "PowerShell Monitor - File Size Failed on $env:COMPUTERNAME" -Body "The File located at $FilePath is currently $FileSizeMB MB. This size has exceeded the monitor threshold of $MonitorSize MB. Please review this file and take necessary action. This Monitor ran at $Runtime"
    }

else {
    exit
}

exit