
#Replace PRINTSERVER with name of the Print Server
$PrintServer = "\\db-fs2012"
$Printers = Get-WmiObject -Class Win32_Printer
ForEach ($Printer in $Printers)
    {If ($Printer.SystemName -like "$PrintServer") 
        {Write-Host $printer.name "is installed on" $printserver
         Remove-Printer -Name $printer.name -ComputerName $env:COMPUTERNAME
            #(New-Object -ComObject WScript.Network).RemovePrinterConnection($($Printer.Name))
        }
    }