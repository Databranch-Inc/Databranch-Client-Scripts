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