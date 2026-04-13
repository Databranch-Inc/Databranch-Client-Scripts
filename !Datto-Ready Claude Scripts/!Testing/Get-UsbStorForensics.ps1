# Get-UsbStorForensics.ps1
# Version: v1.1.0.002

function Get-UsbStorForensics {

    $Out = [System.Collections.Generic.List[string]]::new()

    function W { param([string]$L = '') ; $Out.Add($L) ; Write-Host $L }

    W "================================================================"
    W " USBSTOR FORENSIC DUMP - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    W " Host: $env:COMPUTERNAME"
    W "================================================================"
    W ""

    $UsbStorRoot = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR'

    W "=== SECTION 1: USBSTOR DEVICE ENTRIES ==="
    W ""

    foreach ($DevClass in (Get-ChildItem -Path $UsbStorRoot -ErrorAction SilentlyContinue)) {

        W "--------------------------------------------------------------"
        W "DEVICE CLASS : $($DevClass.PSChildName)"
        W "Full Key     : $($DevClass.Name)"
        W ""

        foreach ($Inst in (Get-ChildItem -Path $DevClass.PSPath -ErrorAction SilentlyContinue)) {

            W "  INSTANCE (Serial): $($Inst.PSChildName)"

            $Props = Get-ItemProperty -Path $Inst.PSPath -ErrorAction SilentlyContinue
            $Fields = @('DeviceDesc','FriendlyName','HardwareID','CompatibleIDs','Manufacturer',
                        'LocationInformation','ContainerID','Capabilities','ConfigFlags',
                        'ClassGUID','Service','Driver','Mfg')

            foreach ($F in $Fields) {
                if ($Props.$F) {
                    $V = $Props.$F
                    if ($V -is [array]) { $V = $V -join ' | ' }
                    W "    $($F.PadRight(18)): $V"
                }
            }

            # Registry key last write time via .NET
            $SubKeyPath = $Inst.Name -replace 'HKEY_LOCAL_MACHINE\\',''
            $RegBase = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine,
                [Microsoft.Win32.RegistryView]::Registry64
            )
            $OpenedKey = $RegBase.OpenSubKey($SubKeyPath)
            if ($OpenedKey) {
                $lwt = $OpenedKey.GetLastWriteTime()
                W "    LastWriteTime    : $lwt (local)"
                W "    LastWriteTimeUTC : $($lwt.ToUniversalTime()) UTC"
                $OpenedKey.Close()
            }
            $RegBase.Close()

            # Device Parameters subkey
            $DPPath = Join-Path $Inst.PSPath 'Device Parameters'
            if (Test-Path $DPPath) {
                W "    [Device Parameters]"
                $DP = Get-ItemProperty -Path $DPPath -ErrorAction SilentlyContinue
                if ($DP) {
                    $DP.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                        W "      $($_.Name.PadRight(18)): $($_.Value)"
                    }
                }
            }

            # Timestamps from Properties GUID {83da6326...}
            $PropGuid = '{83da6326-97a6-4088-9453-a1923f573b29}'
            $PropPath = Join-Path $Inst.PSPath "Properties\$PropGuid"
            if (Test-Path $PropPath) {
                W "    [Timestamps]"
                Get-ChildItem -Path $PropPath -ErrorAction SilentlyContinue | ForEach-Object {
                    $ID  = $_.PSChildName
                    $Raw = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).'(default)'
                    $Label = switch ($ID) {
                        '0064' { 'First Install Time' }
                        '0065' { 'Last Arrival Time ' }
                        '0066' { 'Last Removal Time ' }
                        default { "Property $ID      " }
                    }
                    if ($Raw -is [byte[]] -and $Raw.Length -ge 8) {
                        $FT = [System.BitConverter]::ToInt64($Raw, 0)
                        if ($FT -gt 0) {
                            $DT = [System.DateTime]::FromFileTimeUtc($FT)
                            W "      $Label : $DT UTC"
                        }
                    }
                }
            }
            W ""
        }
    }

    # Section 2 - MountedDevices
    W "=== SECTION 2: MOUNTED DEVICES ==="
    W ""
    $MD = Get-ItemProperty 'HKLM:\SYSTEM\MountedDevices' -ErrorAction SilentlyContinue
    if ($MD) {
        $MD.PSObject.Properties | Where-Object { $_.Name -match '\\DosDevices\\[A-Z]:' } | ForEach-Object {
            $Letter = $_.Name -replace '.*\\DosDevices\\',''
            $Hex    = ($_.Value | ForEach-Object { $_.ToString('X2') }) -join ''
            $Ascii  = [System.Text.Encoding]::Unicode.GetString($_.Value) -replace '[^\x20-\x7E]',''
            W "  Drive $Letter"
            W "    Hex    : $($Hex.Substring(0,[Math]::Min(80,$Hex.Length)))"
            if ($Ascii.Trim()) { W "    Decoded: $($Ascii.Trim())" }
            W ""
        }
    }

    # Section 3 - MountPoints2 for charleswinkler
    W "=== SECTION 3: charleswinkler MountPoints2 ==="
    W ""
    $SID = 'S-1-5-21-2443160825-2733388491-1898970253-3611'
    $MP2 = "Registry::HKEY_USERS\$SID\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2"
    if (Test-Path $MP2) {
        Get-ChildItem -Path $MP2 -ErrorAction SilentlyContinue | ForEach-Object { W "  $($_.PSChildName)" }
    } else {
        W "  Hive not loaded. Run first:"
        W "  reg load HKU\cwinkler C:\Users\charleswinkler\NTUSER.DAT"
        W "  Then re-run this script."
    }

    # Section 4 - SetupAPI log
    W ""
    W "=== SECTION 4: SetupAPI Log (USB entries) ==="
    W ""
    $SALog = 'C:\Windows\INF\setupapi.dev.log'
    if (Test-Path $SALog) {
        Select-String -Path $SALog -Pattern 'USBSTOR|VID_154B|VID_05E3|NORELSYS|SanDisk|Walgreen|USB.*Disk' |
            Select-Object -Last 300 |
            ForEach-Object { W "  [Line $($_.LineNumber)] $($_.Line.Trim())" }
    } else {
        W "  setupapi.dev.log not found."
    }

    # Save output
    $OutFile = "C:\Databranch\USBSTOR_Forensic_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $Out | Out-File -FilePath $OutFile -Encoding UTF8
    Write-Host ""
    Write-Host "Saved to: $OutFile" -ForegroundColor Cyan
}

Get-UsbStorForensics