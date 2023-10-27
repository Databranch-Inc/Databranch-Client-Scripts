param(
  [Parameter(Mandatory=$true)]
  [String]$organizationKey
)

$ErrorActionPreference = "Stop"

####################################################################################
####################################################################################
###
### SkyKick Outlook Assistant Install Helper Script
###
### This script will determine which version of the SkyKick Outlook Assistant
### should be installed based on the configuration of the desktop that this is 
### run on.
###
### An organization key $organizationKey must be specified as a parameter to this
### script
### usage:
###      .\GroupPolicyDeployScript <your organization key without quotes>
###
####################################################################################
####################################################################################

$OACS_x86_PC = "SkyKick Outlook Assistant Client Service (x86)"
$OACS_x64_PC = "SkyKick Outlook Assistant Client Service (x64)"
$OADA_PC = "SkyKick Outlook Assistant Desktop"
$VNOW_PC = "Outlook Assistant"
$VNOW_MAPI64 = "Outlook Assistant MAPI64 Helper"
$DB_Install_Path = "C:\Databranch\skoa\skoa"

Write-Host "Loading WMI Product Database ... " -NoNewline
$installer_db = get-wmiobject Win32_Product
Write-Host "Done"

function CheckForProductName ([String] $productName) {
    $prod_obj = $installer_db | Where-Object -Property "Name" -eq $productName
    if ($prod_obj -ne $null) {
        return $true
    }
    return $false
}

function GetOutlook2016Bitness {
    try
    {
        return (Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Office\16.0\Outlook -Name Bitness).Bitness
    }
    catch 
    {
        Write-Host "Outlook 2016 not found. Checking in WOW6432Node."
        try
        {
            return (Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Outlook -Name Bitness).Bitness
        }
        catch 
        {
            Write-Host "Outlook 2016 not found."            
        }
    }
    return $null
}

function HasOutlook2016 {
    return (GetOutlook2016Bitness -ne $null)
}

function GetWindowsVersion {
    $rv = New-Object -TypeName PSObject
    $rv | Add-Member -MemberType NoteProperty -Name Major -Value $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion' CurrentMajorVersionNumber).CurrentMajorVersionNumber
    $rv | Add-Member -MemberType NoteProperty -Name Minor -Value $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion' CurrentMinorVersionNumber).CurrentMinorVersionNumber
    $rv | Add-Member -MemberType NoteProperty -Name Build -Value $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion' CurrentBuild).CurrentBuild
    $rv | Add-Member -MemberType NoteProperty -Name Revision -Value $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion' UBR).UBR
    $rv | Add-Member -MemberType NoteProperty -Name Bitness -Value $(Get-WmiObject -Class Win32_Processor | Select-Object AddressWidth).AddressWidth
    return $rv
}

function DoMSIExec ([String] $msiPath) {
    Write-Host -NoNewline "Installing MSI @ $DB_Install_Path\$msiPath ... "
    $installer_rv = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $DB_Install_Path\$msiPath /qn ORGANIZATIONKEY=$organizationKey" -Wait -Passthru).ExitCode
    Write-Host $installer_rv
    return $installer_rv
}

$windows_version = GetWindowsVersion
Write-Host "Windows Version : $windows_version"

$has_win10 = ($windows_version.Major -ge 10)
Write-Host "Has Windows 10 : $has_win10"

$has_outlook_2016_x64 =  ((HasOutlook2016) -and (GetOutlook2016Bitness) -eq "x64" )
$has_outlook_2016_x86 =  ((HasOutlook2016) -and (GetOutlook2016Bitness) -eq "x86" )
Write-Host "Has Outlook 2016 (x64) : $has_outlook_2016_x64"
Write-Host "Has Outlook 2016 (x86) : $has_outlook_2016_x86"

$has_oada = CheckForProductName $OADA_PC
Write-Host "Has OADA : $has_oada"

$has_oacs_x64 = CheckForProductName $OACS_x64_PC
Write-Host "Has OACS (x64) : $has_oacs_x64"

$has_oacs_x86 = CheckForProductName $OACS_x86_PC
Write-Host "Has OACS (x86) : $has_oacs_x86"

$has_vnow = CheckForProductName $VNOW_PC
Write-Host "Has SKOA VNOW : $has_vnow"

$has_vnow_mapi64 = CheckForProductName $VNOW_MAPI64
Write-Host "Has SKOA VNOW MAPI64 : $has_vnow_mapi64"

if ($has_oada -or $has_oacs_x64 -or $has_oacs_x86) {
    Write-Error "An existing installation of SKOA v.Next already exists on this machine. Cannot continue."
    return
}

if ($has_vnow -or $has_vnow_mapi64) {
    Write-Error "An existing installation of SKOA v.Now already exists on this machine. Cannot continue."
    return
}

if ($has_win10 -and (HasOutlook2016)) {

    if ($has_outlook_2016_x64) {
        $oacs_install_status = DoMSIExec "SkyKickOutlookAssistant-ClientService-x64.msi"
    } 
    elseif ($has_outlook_2016_x86) {
        $oacs_install_status = DoMSIExec "SkyKickOutlookAssistant-ClientService-x86.msi"
    }
    
    if ($oacs_install_status -eq 0) {
        Write-Host "OACS Installed Successfully" -ForegroundColor Green
    }
    else {
        Write-Error "OACS Failed to install with error code $oacs_install_status"
    }

    $oada_install_status = DoMSIExec "SkyKickOutlookAssistant-Desktop.msi"
    if ($oada_install_status -eq 0) {
        Write-Host "OADA Installed Successfully" -ForegroundColor Green
    }
    else {
        Write-Error "OADA Failed to install with error code $oada_install_status"
    }
}
else 
{
    Write-Host "Unsupported v.Next device configuration - Installing SKOA v.Now" -ForegroundColor Yellow
    $vnow_install_status = DoMSIExec "OutlookAssistant.msi"
    if ($vnow_install_status -eq 0) {
        Write-Host "SKOA v.Now Service Installed Successfully" -ForegroundColor Green
    }
    else {
        Write-Error "SKOA v.Now service Failed to install with error code $vnow_install_status"
    }
    
    if ($windows_version.Bitness -eq 64) {
        $vnow_mapi64Helper_install_status = DoMSIExec "mapi64helper.msi"
        if ($vnow_mapi64Helper_install_status -eq 0) {
            Write-Host "SKOA v.Now Mapi 64 Helper Installed Successfully" -ForegroundColor Green
        }
        else {
            Write-Error "SKOA v.Now Mapi 64 Helper Failed to install with error code $vnow_install_status"
        }
    }
}
