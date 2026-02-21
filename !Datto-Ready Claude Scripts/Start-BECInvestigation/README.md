# BEC Investigation Automation Toolkit
## Databranch Script Library — BEC Incident Response

**Script:** `Start-BECInvestigation.ps1` | **Version:** `3.0.0.0` | **Author:** Sam Kirsch

---

## Overview

The BEC Investigation Toolkit automates the setup and execution of a Business Email Compromise investigation for a compromised Microsoft 365 mailbox. A single script creates a complete, self-contained investigation workspace — including folder structure, XML configuration, and three pre-configured investigation scripts — in under five seconds.

All investigation state is persisted in `Investigation.xml`, eliminating the need to pass parameters between scripts or track progress manually.

---

## Prerequisites

**PowerShell version:** 5.1 or later

**Permissions:** Exchange Administrator or Global Administrator on the target Microsoft 365 tenant

**Required module** (for generated data collection scripts):
```powershell
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser
```

**You only need one file to get started:** `Start-BECInvestigation.ps1`

---

## Quick Start

### Step 1 — Initialize the investigation workspace

```powershell
.\Start-BECInvestigation.ps1 -VictimEmail "john.doe@clientdomain.com"
```

Optional parameters:
```powershell
.\Start-BECInvestigation.ps1 -VictimEmail "john.doe@clientdomain.com" `
                              -WorkingDirectory "D:\Investigations" `
                              -IncidentTicket "INC-20458" `
                              -Technician "Sam Kirsch"
```

This creates the workspace folder, `Investigation.xml`, three investigation scripts, and a per-investigation README. It opens the folder in Explorer when complete. Expected time: under 5 seconds.

### Step 2 — Collect data

```powershell
cd BEC-Investigation_jdoe_TIMESTAMP\Scripts
.\Invoke-BECDataCollection.ps1
```

Connects to Exchange Online interactively, collects all forensic artifacts, and initiates 30-day historical message traces. Expected time: 2–5 minutes.

### Step 3 — Immediate analysis

```powershell
.\Invoke-BECLogAnalysis.ps1 -SkipMessageTraces
```

Analyzes collected data immediately without waiting for historical traces. Produces `ANALYSIS-REPORT.txt` and opens the Analysis folder. Address any CRITICAL or HIGH findings before continuing. Expected time: 1–2 minutes.

### Step 4 — Retrieve historical traces (after ~30 min wait)

```powershell
.\Invoke-BECMessageTraceRetrieval.ps1
```

Checks the status of the 30-day historical searches and downloads completed results. Safe to re-run if traces are not ready yet. Expected time: under 1 minute.

### Step 5 — Complete analysis

```powershell
.\Invoke-BECLogAnalysis.ps1
```

Re-runs analysis with full 30-day trace data. Updates `ANALYSIS-REPORT.txt`. Expected time: 2–3 minutes.

---

## Investigation Workspace Structure

```
BEC-Investigation_jdoe_20260220-143022/
│
├── Investigation.xml                          ← Auto-managed config (do not edit)
├── Investigation-README.txt                   ← Per-investigation quick reference
│
├── Scripts/
│   ├── Invoke-BECDataCollection.ps1          ← Step 2: Collect forensic data
│   ├── Invoke-BECLogAnalysis.ps1             ← Step 3 & 5: Analyze findings
│   └── Invoke-BECMessageTraceRetrieval.ps1   ← Step 4: Retrieve 30-day traces
│
├── RawData/                                   ← All collected CSV files
│   ├── InboxRules_jdoe.csv
│   ├── MailForwarding_jdoe.csv
│   ├── MailboxPermissions_jdoe.csv
│   ├── MobileDevices_jdoe.csv
│   ├── UnifiedAuditLogs_jdoe.csv
│   ├── QuickTrace-Sent_jdoe.csv
│   ├── QuickTrace-Received_jdoe.csv
│   ├── MessageTrace-Sent_jdoe.csv            ← After Step 4
│   └── MessageTrace-Received_jdoe.csv        ← After Step 4
│
├── Reports/                                   ← Flagged items for immediate review
│   └── SUSPICIOUS-Rules_jdoe.csv
│
├── Analysis/                                  ← Analysis output
│   ├── ANALYSIS-REPORT.txt                   ← Start here
│   └── All-Findings.csv
│
└── Logs/                                      ← Script execution logs (transcripts)
    ├── DataCollection_timestamp.log
    ├── Analysis_timestamp.log
    └── TraceRetrieval_timestamp.log
```

In addition, `Start-BECInvestigation.ps1` itself logs to `C:\Databranch\ScriptLogs\Start-BECInvestigation\` on the technician's workstation (last 10 log files retained).

---

## Parameters

### Start-BECInvestigation.ps1

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `VictimEmail` | String | Yes | — | Full email address (UPN) of the compromised user |
| `WorkingDirectory` | String | No | `C:\Databranch_BEC` | Root folder where investigation workspace is created |
| `IncidentTicket` | String | No | _(empty)_ | ConnectWise Manage ticket number for reference |
| `Technician` | String | No | `$env:USERNAME` | Name of the technician conducting the investigation |

### Generated script parameters

**Invoke-BECDataCollection.ps1**
| Parameter | Type | Required | Description |
|---|---|---|---|
| `SkipHistoricalTraces` | Switch | No | Skip submission of 30-day historical message trace jobs |

**Invoke-BECLogAnalysis.ps1**
| Parameter | Type | Required | Description |
|---|---|---|---|
| `SkipMessageTraces` | Switch | No | Skip message trace CSV analysis (use for immediate triage) |

**Invoke-BECMessageTraceRetrieval.ps1** — No parameters. All configuration read from `Investigation.xml`.

---

## Investigation.xml

The XML configuration file is the central state store for the investigation. All generated scripts read from and write to it automatically. Do not edit it manually.

```xml
<BECInvestigation>
  <Investigation>
    <InvestigationID>BEC-Investigation_jdoe_20260220-143022</InvestigationID>
    <ScriptVersion>3.0.0.0</ScriptVersion>
    <CreatedDate>2026-02-20T14:30:22</CreatedDate>
    <Technician>Sam Kirsch</Technician>
    <IncidentTicket>INC-20458</IncidentTicket>
  </Investigation>
  <Victim>
    <Email>john.doe@clientdomain.com</Email>
    <UserAlias>john.doe</UserAlias>
    <Domain>clientdomain.com</Domain>
  </Victim>
  <Paths>
    <RootPath>C:\Databranch_BEC\BEC-Investigation_jdoe_20260220-143022</RootPath>
    <RawDataPath>...\RawData</RawDataPath>
    <ReportsPath>...\Reports</ReportsPath>
    <AnalysisPath>...\Analysis</AnalysisPath>
    <ScriptsPath>...\Scripts</ScriptsPath>
    <LogsPath>...\Logs</LogsPath>
  </Paths>
  <DataCollection>
    <Completed>true</Completed>
    <CompletedDate>2026-02-20T14:35:11</CompletedDate>
    <DaysSearched>30</DaysSearched>
  </DataCollection>
  <MessageTraces>
    <SentTraceJobId>abc-123-def</SentTraceJobId>
    <TracesInitiated>true</TracesInitiated>
    <TracesCompleted>false</TracesCompleted>
  </MessageTraces>
  <Analysis>
    <ImmediateAnalysisCompleted>true</ImmediateAnalysisCompleted>
    <CriticalFindingsCount>2</CriticalFindingsCount>
    <HighFindingsCount>1</HighFindingsCount>
  </Analysis>
</BECInvestigation>
```

Check investigation status at any time:

```powershell
[xml]$c = Get-Content Investigation.xml
$c.BECInvestigation.DataCollection.Completed
$c.BECInvestigation.MessageTraces.TracesCompleted
$c.BECInvestigation.Analysis.CriticalFindingsCount
```

---

## File Conflict Handling

When `Invoke-BECDataCollection.ps1` is re-run on an existing investigation (e.g., to collect additional data or re-collect after an error), it detects existing output files before collecting. For each existing file, the technician is prompted to choose:

- **[O] Overwrite** — replaces the existing file
- **[D] Duplicate** — creates a versioned copy (`_v2.csv`, `_v3.csv`, etc.)
- **[S] Skip** — skips collection for that data type

`Invoke-BECLogAnalysis.ps1` automatically analyzes all versions (base + `_v2`, `_v3`...) and includes results from each in the report.

---

## Findings Severity Reference

| Severity | Indicators |
|---|---|
| **CRITICAL** | Mail forwarding to external domain; inbox forwarding/redirect rule to external address |
| **HIGH** | Inbox rules automatically deleting messages; outbound email volume spike (>50/day) |
| **MEDIUM** | Rules moving emails to non-standard folders; delegated mailbox permissions; high external send ratio (>70%) |
| **LOW** | Rules automatically marking emails as read |

---

## Complete Incident Response Timeline

**0–5 min — Lock & Initialize**
- Lock the account: Azure AD portal > Users > [User] > Block sign-in
- Run `Start-BECInvestigation.ps1` to create the workspace

**5–10 min — Collect**
- Run `Invoke-BECDataCollection.ps1`

**10–15 min — Immediate Triage**
- Run `Invoke-BECLogAnalysis.ps1 -SkipMessageTraces`
- Review `Analysis\ANALYSIS-REPORT.txt`
- Address CRITICAL findings immediately

**15–45 min — Remediation + Wait**
- Reset password and force MFA re-registration
- Revoke active sessions
- Collect Azure AD sign-in logs manually if Business Premium (Azure Portal > Users > Sign-in logs > export last 30 days to `RawData\`)
- Check trace status: `Get-HistoricalSearch | Where-Object {$_.ReportTitle -like "*jdoe*"} | Format-Table ReportTitle, Status`

**45–50 min — Retrieve Traces**
- Run `Invoke-BECMessageTraceRetrieval.ps1`

**50–55 min — Complete Analysis**
- Run `Invoke-BECLogAnalysis.ps1`
- Review updated `ANALYSIS-REPORT.txt`

**55–60 min — Reporting**
- Compile findings for ticket and management notification
- Notify internal users and external contacts as warranted

---

## Troubleshooting

**"Investigation.xml not found"**
Ensure you are running scripts from the `Scripts` subfolder of the investigation workspace.
```powershell
cd BEC-Investigation_jdoe_TIMESTAMP\Scripts
.\Invoke-BECDataCollection.ps1
```

**"Failed to connect to Exchange Online"**
Verify you have the Exchange Administrator or Global Administrator role on the tenant. Try connecting manually first: `Connect-ExchangeOnline`. Ensure your MFA device is available.

**Historical traces not ready**
Normal — traces take 15–30 minutes. Re-run `Invoke-BECMessageTraceRetrieval.ps1` after waiting. The script is safe to run multiple times.

**No findings in analysis report**
Check the `Logs\` folder for data collection errors. Confirm `RawData\` contains CSV files. The account may not have been compromised — this is a valid outcome.

**ExchangeOnlineManagement module not installed**
The data collection script will attempt automatic installation. If it fails, install manually:
```powershell
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser -Force
```

---

## Batch Investigations

If multiple accounts are compromised in the same incident:

```powershell
$Victims = @("user1@domain.com", "user2@domain.com", "user3@domain.com")
foreach ($Victim in $Victims) {
    .\Start-BECInvestigation.ps1 -VictimEmail $Victim -IncidentTicket "INC-MASS-BREACH"
}
```

Each victim gets an isolated workspace. Navigate to each `Scripts` folder and run the investigation scripts independently.

---

## Best Practices

- Lock the compromised account **before** running data collection
- Run `Invoke-BECLogAnalysis.ps1 -SkipMessageTraces` first — do not wait 30 minutes before triaging
- Archive the entire investigation workspace folder for a minimum of one year
- Document lessons learned in your runbook after each investigation

---

## Business Standard vs. Business Premium

Both license types are fully supported. Business Premium provides approximately 40% more forensic detail due to Azure AD sign-in log access. With Business Standard, the scripts fall back to mailbox audit logs for IP and session data. Detailed comparison: see `BUSINESS-STANDARD-NOTES.md`.

---

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Failure (see log for details) |

---

## Version History

**v3.0.0.0** — 2026-02-20 — Sam Kirsch
- Renamed to `Start-BECInvestigation.ps1`
- Full Databranch Script Library spec compliance (header, master function, Write-Log, splatted entry point)
- Generated scripts renamed to Verb-Noun convention (`Invoke-BECDataCollection`, `Invoke-BECLogAnalysis`, `Invoke-BECMessageTraceRetrieval`)
- Generated scripts updated with compliant headers, Write-Log, master function wrappers

**v2.3.0.0** — 2024-02-15 — Sam Kirsch
- O/D/S file conflict checks run before collection
- Improved mailbox permissions handling
- Analysis: detects MoveToFolder, DeleteMessage, MarkAsRead rules
- Improved severity classification

**v2.0.0.0** — 2024-02-01 — Sam Kirsch
- Single-script deployment model
- XML-based configuration management
- Auto-generated investigation scripts
- Standardized folder structure

**v1.0.0.0** — 2024-01-10 — Sam Kirsch
- Initial release

---

*Databranch — Internal Use Only*
*For support, contact your Databranch team lead*
