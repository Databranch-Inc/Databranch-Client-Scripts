<#
Talk to GitHub.ps1
Basic Script to write-host and allow the RMM to pull the result

Josh Britton

4-8-22

1.0
#>

#Create a Function to wrap the script. The line of the function is called in the CW Automate Script
function Talk-DatabranchGithub2 {

$wc = New-Object System.Net.WebClient
$wc.Headers.Add('Authorization','token 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')
$wc.Headers.Add('Accept','application/vnd.github.v3.raw')
$wc.DownloadString('https://raw.githubusercontent.com/Databranch-Inc/Databranch-Client-Scripts/main/Functions/Function_Set_Logging.ps1') | iex


$Date = Get-Date

Write-Log -logpath $logpath -message "Successfuly talked to GITHUB! on $Date"



Start-Sleep 10}
