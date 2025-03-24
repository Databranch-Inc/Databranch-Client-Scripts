<#
This script will stop the print spooler service, clear the files from C:\Windows\System32\spool\PRINTERS, and restart the service.
Josh Britton
1/8/19
1.0#>

function Restart-PrintSpooler {
    # Stop the print spooler service
    Stop-Service -Name Spooler

    # Remove all items from the Spooler Folder
    Remove-Item C:\Windows\System32\spool\PRINTERS\*.* -ErrorAction SilentlyContinue

    # Restart the Print Spooler Service
    Start-Service -Name Spooler
}

# Call the function to restart the print spooler
Restart-PrintSpooler