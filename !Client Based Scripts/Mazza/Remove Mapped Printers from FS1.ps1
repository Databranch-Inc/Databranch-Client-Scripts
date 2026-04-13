$PrintServer = "\\MAZZA-FS1"

$Printers = Get-WmiObject -Class Win32_Printer
ForEach ($Printer in $Printers) {
If ($Printer.SystemName -like "$PrintServer") {
(New-Object -ComObject WScript.Network).RemovePrinterConnection($($Printer.Name))
}
}