<#
Microsoft Purview Parse Tool

This script extracts InternetMessageId values from the audit log for MailItemsAccessed operations,compares them with the Internet message IDs in specified log files, and generates a report of matched rows.

Required items:

eDiscovery Export Report (CSV) files from Microsoft Purview and the audit log during timeframe


Script Author: Sam Kirsch
Uploaded to Github: Josh Britton
Version 1.0
4-23-25

==================================================================================================
1.0 - 2025-04-13 - Sam Kirsch - Initial version. Josh Britton - Upload to Github.

=================================================================================================

#>


# Variables for file paths
$auditLogFile = "C:\Users\skirsch\Downloads\purview-time-scoped.csv"
$logFiles = @(
    "C:\Users\skirsch\Downloads\Reports-Test_Case-Full_PST_for_Michelle_Wolf-StartDirectExport-WolfPST-2025-04-13_04-31-09\Items_0_2025-04-13_04-31-09.csv",
    "C:\Users\skirsch\Downloads\Reports-Test_Case-Full_PST_for_Michelle_Wolf-StartDirectExport-WolfPST-2025-04-13_04-31-09\Items_1_2025-04-13_04-31-09.csv",
    "C:\Users\skirsch\Downloads\Reports-Test_Case-Full_PST_for_Michelle_Wolf-StartDirectExport-WolfPST-2025-04-13_04-31-09\Items_2_2025-04-13_04-31-09.csv"
    )
$outputReportFile = "C:\Users\skirsch\Downloads\matched_report6.csv"
$messageIdsFile = "C:\Users\skirsch\Downloads\captured_message_ids4.txt"

# Example syntax for logFiles variable:
# $logFiles = @("C:\path\to\logfile1.csv", "C:\path\to\logfile2.csv", "C:\path\to\logfile3.csv")

# Extract InternetMessageId from the audit log for MailItemsAccessed operation
$messageDetails = @()
Import-Csv -Path $auditLogFile | ForEach-Object {
    if ($_.Operation -eq "MailItemsAccessed") {
        $auditData = $_.AuditData
        # Extract all InternetMessageId values from the AuditData field
        $matches = [regex]::Matches($auditData, '"InternetMessageId":"([^"]+)"')
        foreach ($match in $matches) {
        $messageDetails += $match.Groups[1].Value
        }
    }
}

# Remove duplicates
$messageDetails = $messageDetails | Sort-Object -Unique

# Save the extracted message details to a file
$messageDetails | Out-File -FilePath $messageIdsFile

# Initialize a list to store the matched rows
$matchedRows = @()

# Iterate through the log files and compare for InternetMessageID
foreach ($logFile in $logFiles) {
    Import-Csv -Path $logFile | ForEach-Object {
        if ($messageDetails -contains $_.'Internet message ID') {
            $matchedRows += [PSCustomObject]@{
                'Internet message ID' = $_.'Internet message ID'
                'Subject/Title' = $_.'Subject/Title'
                'Path' = $_.'Path'
                'To' = $_.'To'
                'Email recipients' = $_.'Email recipients'
                'Sender' = $_.'Sender'
                'Participants' = $_.'Participants'
                'Participant expansion' = $_.'Participant expansion'
                'Received' = $_.'Received'
                'Date' = $_.'Date'
                'Email date sent' = $_.'Email date sent'
            }
        }
    }   
}
# Write the matched rows to the output report file
$matchedRows | Export-Csv -Path $outputReportFile -NoTypeInformation

Write-Output "Matched rows have been written to $outputReportFile"