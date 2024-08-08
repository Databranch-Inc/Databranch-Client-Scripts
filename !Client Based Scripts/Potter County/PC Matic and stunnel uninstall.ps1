<#
This PC will check an array of GUIDs based on different versions of PC Matic. Once found, it will update 2 registry keys to allow for a silent MSI Uninstall. Once complete, the uninstall command specific to the MSI GUID will run.

The script will then look for the STUNNEL applicaiton, and run a silent uninstall if found


Script is called in the Following RMM Script:
*** JB - Potter County - Remove PC Matic and STunnel applications

Josh Britton
5-3-24
========================================================================================================
1.0

Initial Build

========================================================================================================
#>
function Uninstall-PCMatic {

#Variable Set
$Keys = @(
    '00E93EF4-4518-40FB-B7DA-9DB725CD03EE'
    '63F0B41F-2500-41EE-86BC-50F4B141E24E'   
    '21B39C1C-C758-484F-9253-3FDA8244F2E5'
    '610AFFC6-EC4D-43D5-AD46-E7F6B082B044'
    '96A780A4-19E1-489B-9F17-6F5A757E1786'
    'CBFE412A-73C7-4137-9A00-12C618BBC143'
    'AD606E62-1755-440B-A6C5-9963B838C5D7'
    '91FCB869-B65C-43CF-80E7-474A2F1A4FC2'
    '94421269-1F8F-4CFE-9CC5-9FD9E1693644'
    '82BAC19B-77DE-4F84-964C-B9F17540711C'
)

#Test for version via Regkey and GUID path, update keys when proper version found.

foreach ($key in $keys){

    $Regpath = Test-Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{$key}"

    if ($Regpath -eq $true){

        #Adjust Registry keys to allow for uninstall
        Set-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{$key}" -name  NoRemove -value 0
        Set-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{$key}" -name SystemComponent -value 0
        Write-host "Registry Keys for GUID $key have been found and updated. Attempting uninstall" -ForegroundColor Green

        #Set variables for uninstall
        $uninstall = "msiexec.exe"
        $arguments = "/X{$key} /quiet /norestart"

        #Run Uninstall
        Start-Process $uninstall -Wait -ArgumentList $arguments

    }
    else {
        Write-host "Guid $key does not exist on this machine. Checking next version" -ForegroundColor Yellow
    }
    
}

#Check for remaining PCMatic PitStop uninstall, and run if found.

$PCPitStopPath = Test-Path -Path "C:\Program Files (x86)\PCPitstop\Super Shield\unins000.exe" 

if($PCPitStopPath -eq $true){

    #Stunnel uninstall variable set
    $PCPitStopUninstall = "C:\Program Files (x86)\PCPitstop\Super Shield\unins000.exe" 
    $PCPitStopArguments = "/Silent"

    #Run Stunnel uninstall
    Start-Process $PCPitStopUninstall $PCPitStopArguments
}

else{

    Write-host "No Additonal PC Pit Stop files found on this machine. Moving to STunnel check"
}


#Check for Stunnel.exe - if found, attempt to remove

$stunnelpath = test-path -Path "C:\Program Files (x86)\stunnel\uninstall.exe" 

if($stunnelpath -eq $true){

    #Stunnel uninstall variable set
    $stunneluninstall = "C:\Program Files (x86)\stunnel\uninstall.exe" 
    $stunnelaruments = "/S /AllUsers"

    #Run Stunnel uninstall
    Start-Process $stunneluninstall $stunnelaruments
}

else{

    Write-host "Stunnel not found on this machine. Ending script"
}

#Allow time for uninstall actions to complete before refreshing software list in Automate
Start-Sleep 300

}