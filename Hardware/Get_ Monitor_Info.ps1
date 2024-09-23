<#
Get Monitor Info
This script is used to to gather the current connected montitors to a machine. This incudes the model of the monitor and the connector type.

Original scipt was developed by Steven Peterson. Modified by Josh Britton for use with ConnectWise Automate

Script load date 9-23-24

Version 1.0
================================================================================================================
Version 1.0 9-23-24
Moved script to Github folder and wrapped in function to be called by CW Automate.

Added Get-Date cmdlets for use as a field to determine last run
================================================================================================================

#>
function Get-MonitorInfoDB {

#Get Date for Logging

$Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"


$adapterTypes = @{ #https://www.magnumdb.com/search?q=parent:D3DKMDT_VIDEO_OUTPUT_TECHNOLOGY
    '-2' = 'Unknown'
    '-1' = 'Unknown'
    '0' = 'VGA'
    '1' = 'S-Video'
    '2' = 'Composite'
    '3' = 'Component'
    '4' = 'DVI'
    '5' = 'HDMI'
    '6' = 'LVDS'
    '8' = 'D-Jpn'
    '9' = 'SDI'
    '10' = 'DisplayPort (external)'
    '11' = 'DisplayPort (internal)'
    '12' = 'Unified Display Interface'
    '13' = 'Unified Display Interface (embedded)'
    '14' = 'SDTV dongle'
    '15' = 'Miracast'
    '16' = 'Internal'
    '2147483648' = 'Internal'
}

$arrMonitors = @()

$monitors = gwmi WmiMonitorID -Namespace root/wmi
$connections = gwmi WmiMonitorConnectionParams -Namespace root/wmi

foreach ($monitor in $monitors)
{
    $manufacturer = $monitor.ManufacturerName
    $name = $monitor.UserFriendlyName
    $connectionType = ($connections | ? {$_.InstanceName -eq $monitor.InstanceName}).VideoOutputTechnology

    if ($manufacturer -ne $null) {$manufacturer =[System.Text.Encoding]::ASCII.GetString($manufacturer -ne 0)}
	if ($name -ne $null) {$name =[System.Text.Encoding]::ASCII.GetString($name -ne 0)}
    $connectionType = $adapterTypes."$connectionType"
    if ($connectionType -eq $null){$connectionType = 'Unknown'}

    if(($manufacturer -ne $null) -or ($name -ne $null)){$arrMonitors += "$manufacturer $name ($connectionType)"}

}

$i = 0
$strMonitors = ''
if ($arrMonitors.Count -gt 0){
    foreach ($monitor in $arrMonitors){
        if ($i -eq 0){$strMonitors += $arrMonitors[$i]}
        else{$strMonitors += "`n"; $strMonitors += $arrMonitors[$i]}
        $i++
    }
}

if ($strMonitors -eq ''){$strMonitors = 'None Found'}
$strMonitors

$obj = @{}
$obj.strMonitors = $strMonitors
$obj.Date = $Date
$Final = [string]::Join("|",($obj.GetEnumerator() | %{$_.Name + "=" + $_.Value}))
Write-Output $Final

}