<#
Check Cr2 Office Version and update channel
Checks current installed release of Office C2R versions (items that install via Office deployment tool, namely Office 365). Script then sets output for variable pickup in ConnectWise Automate

Source pages for scripts:

Version Check - https://www.cyberdrain.com/monitoring-with-powershell-monitoring-office-c2r-updates/

Prep Variables for Automate - https://www.gavsto.com/scripting-easily-convert-multiple-powershell-variables-into-automate-script-variables/

Josh Britton

1.0

3-15-23
#>

#Get Installed Outlook Version
$ReportedVersion = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -Name "VersionToReport"

#Get Update Channel GUID
$Channel = (Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -Name "CDNBaseUrl") -split "/" | Select-Object -Last 1

#Convert GUID to Channel Name
If (!$Channel) {
    $Channel = "Non-C2R version or No Channel selected."
}
else {
    switch ($Channel) {
        "492350f6-3a01-4f97-b9c0-c7c6ddf67d60" { $Channel = 'Current ("Monthly")' }
        "64256afe-f5d9-4f86-8936-8840a6a4f5be" { $Channel = "Current Preview (`"Monthly Targeted`"/`"Insiders`")" }
        "7ffbc6bf-bc32-4f92-8982-f9dd17fd3114" { $Channel = "Semi-Annual Enterprise(`"Broad`")" }
        "b8f9b850-328d-4355-9145-c59439a0c4cf" { $Channel = "Semi-Annual Enterprise Preview (`"Targeted`")" }
        "55336b82-a18d-4dd6-b5f6-9e5095c314a6" { $Channel = "Monthly Enterprise" }
        "5440fd1f-7ecb-4221-8110-145efaa6372f" { $Channel = "Beta" }
        "f2e724c1-748f-4b47-8fb8-8e0d210e9208" { $Channel = "LTSC" }
        "2e148de9-61c8-4051-b103-4af54baffbb4" { $Channel = "LTSC Preview" }
    }
}


#Create Array of varabiles that can be pulled into CW Automate

$obj = @{}
$obj.ReportedVersion = $ReportedVersion
$obj.Channel = $Channel
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final