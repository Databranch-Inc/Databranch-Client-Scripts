# Databranch Script Library — Foundational Reference

> **Purpose:** Summarizes the structure, standards, and inventory of the Databranch PowerShell Script Library for use as AI context and team reference.
> **Source:** ScriptLibrary.zip — 350 files, ~213 .ps1 scripts across 40+ categories
> **Last Updated:** April 2026

---

## Table of Contents

1. [Library Architecture Overview](#1-library-architecture-overview)
2. [Coding & Formatting Standards](#2-coding--formatting-standards)
3. [The Standard Script Template](#3-the-standard-script-template)
4. [Production Scripts — Datto-Ready](#4-production-scripts--datto-ready)
5. [In-Development Scripts — Testing Queue](#5-in-development-scripts--testing-queue)
6. [CIPP-Ready Scripts](#6-cipp-ready-scripts)
7. [Legacy Library — Categorized Inventory](#7-legacy-library--categorized-inventory)
8. [Internal Tooling](#8-internal-tooling)
9. [Documentation Standards](#9-documentation-standards)
10. [Key Patterns & Conventions for AI Collaboration](#10-key-patterns--conventions-for-ai-collaboration)

---

## 1. Library Architecture Overview

The library is organized into a tiered folder structure that reflects both production readiness and functional domain.

### Folder Tier Structure

```
ScriptLibrary/
│
├── !Datto-Ready Claude Scripts/        ← PRODUCTION TIER — Full standard, DattoRMM-ready
│   ├── Invoke-ScriptTemplate.ps1       ← Master template (baseline for all scripts)
│   ├── Databranch_ScriptLibrary_ProjectSpec.md  ← Authoritative standards doc
│   ├── Databranch_DocumentationSpec.md ← HTML doc design standards
│   ├── Invoke-MailRemediation/         ← Production script (with docs)
│   ├── Invoke-WindowsMaintenance/      ← Production script (with docs)
│   ├── Start-ADInventoryCollection/    ← Production script (with docs)
│   ├── Start-BECInvestigation/         ← Production script (with docs)
│   ├── Start-EventLogCollection/       ← Production script (with docs)
│   ├── Start-ScriptManagementBrowser/  ← Production script (with docs)
│   ├── Sync-OrgKeysToSiteVariables/    ← Production script (with markdown doc)
│   └── !Testing/                       ← In-development, standard-compliant scripts
│
├── !CIPP-Ready Claude Scripts/         ← CIPP-targeted scripts (PowerShell via CIPP)
│
├── !Client Based Scripts/              ← Client-specific one-offs (Arnot, Cameron, JIT, JME, Mazza, Potter County)
│
├── !Archive/                           ← Retired/superseded scripts
│
├── !Testing/                           ← Root-level scratch/prototype scripts
│
├── AD/                                 ← Active Directory management scripts (legacy tier)
├── O365/                               ← Microsoft 365 / Exchange Online scripts (legacy tier)
├── Networking/                         ← Network configuration scripts
├── Hardware/Inventory/                 ← Hardware inventory reporting
├── Bitlocker/                          ← BitLocker management and reporting
├── BSN/                                ← BreachSecureNow IP whitelisting
├── ConnectWise/                        ← ConnectWise Manage integration
├── DattoRMM/                           ← DattoRMM-specific integrations
├── Deployment/                         ← Endpoint deployment scripts
├── Duo/                                ← DUO Auth Proxy management
├── Exchange Online/                    ← Exchange Online specific
├── Exchange On-Prem/                   ← Legacy on-prem Exchange
├── File Server/                        ← File share and permissions
├── Functions/                          ← Reusable function templates
├── GPO/                                ← Group Policy tooling
├── Hardware/                           ← Hardware inventory
├── Log4j/                              ← Log4j incident response (Dec 2021)
├── MailProtector/                      ← MailProtector configuration
├── Monitoring/                         ← Endpoint monitoring helpers
├── PC Maintenance/                     ← Workstation cleanup/maintenance
├── Printing/                           ← Print spooler and printer management
├── Registry/                           ← Registry check/set utilities
├── Scale HCI/                          ← Scale Computing cluster management
├── SkyKick/                            ← SkyKick migration tooling
├── SMB/                                ← SMB share enumeration
├── Software/                           ← Software install/uninstall (Huntress, Webroot, etc.)
├── Windows Services and Processes/     ← Service and process management
├── Zorus/                              ← Zorus agent install/uninstall
├── ACL/                                ← ACL and permissions management
├── Ansible/                            ← Ansible inventory/config (limited use)
├── AutoIT/                             ← AutoIT scripts (minimal)
├── Automate/                           ← Legacy ConnectWise Automate scripts
├── Offline File Sync/                  ← Offline files cleanup
└── EngineersPowerApp_PS7_git.ps1       ← Legacy predecessor to Start-ScriptManagementBrowser
```

### Tiering Summary

| Tier | Folder Prefix | Standard Compliance | DattoRMM Ready | Has HTML Docs |
|---|---|---|---|---|
| Production | `!Datto-Ready Claude Scripts/` (root) | Full | Yes | Most |
| Testing/WIP | `!Datto-Ready Claude Scripts/!Testing/` | Full | Yes | No |
| CIPP Platform | `!CIPP-Ready Claude Scripts/` | Partial | Via CIPP | Markdown |
| Client-Specific | `!Client Based Scripts/` | Varies | Varies | No |
| Legacy | All other folders | Pre-standard | Varies | No |
| Retired | `!Archive/` | Pre-standard | No | No |

---

## 2. Coding & Formatting Standards

These standards are defined in `Databranch_ScriptLibrary_ProjectSpec.md` and apply to all scripts in the Production and Testing tiers. They are the ground truth for AI-assisted script work.

### Core Requirements

| Field | Standard |
|---|---|
| PowerShell Target | **PS 5.1** — never use PS 7+ syntax (no ternary `?:`, no `??`, no negative indexes, no `ForEach-Object -Parallel`) |
| Error Handling | `$ErrorActionPreference = 'Stop'` with `try/catch` throughout |
| Naming | `CmdletBinding`, named parameters only (no positional), full cmdlet names (no aliases) |
| Master Function | All code wrapped in a master function named identically to the `.ps1` file |
| Entry Point | Master function called at bottom via splatting (`@Params`) |
| Multi-param Calls | Always use splatting |
| Self-Contained | No external module dependencies unless clearly documented |
| No Format-* Output | Never use `Format-Table`, `Format-List`, or `Format-Wide` in DattoRMM-facing output |

### DattoRMM Integration Pattern

Every production script supports both DattoRMM automated runs and manual interactive runs without modification.

**Parameter fallback chain:** `DattoRMM env var → PowerShell parameter → default value`

```powershell
[Parameter(Mandatory = $false)]
[string]$SiteName = $(if ($env:CS_PROFILE_NAME) { $env:CS_PROFILE_NAME } else { 'UnknownSite' })
```

**Always-wired DattoRMM variables** (used in log header):
- `$env:CS_PROFILE_NAME` — Site/customer name
- `$env:CS_HOSTNAME` — Target machine hostname

**Critical Boolean gotcha:** DattoRMM boolean component variables arrive as strings `"true"` / `"false"` — never as `$true`/`$false`. Always compare with `-eq 'true'`.

```powershell
# WRONG:  if ($env:EnableFeature) { ... }        ← always true (non-empty string)
# CORRECT: if ($env:EnableFeature -eq 'true') { ... }
```

**UDF Write Pattern:**
```powershell
New-ItemProperty -Path 'HKLM:\SOFTWARE\CentraStage' -Name 'Custom5' -Value 'Value' -PropertyType String -Force | Out-Null
```

**Post-Condition (orange warning status):** Configure `WARNING:` in DattoRMM component post-condition field; include that literal prefix in relevant `Write-Log` lines.

### Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Runtime failure — script started but encountered errors during execution |
| `2` | Fatal pre-flight failure — missing parameters, auth failure, or any condition preventing execution from starting |

`Invoke-WindowsMaintenance` uses an additive bitfield exit code scheme (0, 2, 4, 8, 16, 32, 64) to represent multiple simultaneous outcomes — a pattern available for complex multi-phase scripts.

### TLS 1.2 Enforcement

Any script making HTTPS/REST calls must include this line **after** `param()` (not before — placing it before `param()` causes a parse-time crash):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
```

### Security Standards

- Secrets (API keys, client secrets, passwords) **never** appear in logs, stdout, or on disk
- DattoRMM environment variables are the correct delivery mechanism for secrets
- Null secrets immediately after use: `$ClientSecret = $null`
- Never log secrets in the log header or parameter dumps

### Version Format

`Major.Minor.Revision.Build` (e.g. `1.2.3.004`)

| Segment | Trigger |
|---|---|
| Major | Breaking changes, complete rewrites |
| Minor | New features, significant enhancements |
| Revision | Bug fixes, small improvements |
| Build | Internal iterations, WIP increments |

Every code change requires a new version number AND a changelog entry.

---

## 3. The Standard Script Template

**File:** `!Datto-Ready Claude Scripts/Invoke-ScriptTemplate.ps1` — v1.4.1.0
**Author:** Sam Kirsch

This is the baseline for all new or refactored scripts. Key structural elements:

### Script Structure (in order)

```
1. #Requires -Version 5.1
2. Comment-based help block (.SYNOPSIS, .DESCRIPTION, .PARAMETER, .EXAMPLE, .NOTES, .CHANGELOG)
3. [CmdletBinding()] param() block  ← MUST be first executable statement
4. TLS 1.2 enforcement line         ← MUST be after param()
5. Master function definition (named to match file)
   a. $ScriptName, $ScriptVersion, log path config
   b. Write-Log function (structured output → stdout + log file)
   c. Write-Console function (colored display → terminal only via Write-Host)
   d. Write-Banner, Write-Section, Write-Separator (display helpers)
   e. Initialize-Logging (folder creation + log rotation, keeps last 10 files)
   f. Set-UdfValue (write to DattoRMM UDF via registry)
   g. Standard log header (site, hostname, run-as, params, log path)
   h. Pre-flight parameter validation block (exit 2 on failure)
   i. Main execution logic in try/catch
   j. Exit 0 (success) or Exit 1 (runtime failure)
6. Splatted entry point call at bottom
```

### Dual-Output Pattern

Scripts use two completely independent output layers:

| Function | Stream | Captured By | Purpose |
|---|---|---|---|
| `Write-Log` | stdout / log file | DattoRMM, pipeline | Structured `[timestamp][SEVERITY]` entries |
| `Write-Console` | Display stream (Write-Host) | Terminal only | Colored, formatted output for interactive runs |
| `Write-Banner` | Display stream | Terminal only | Script start/end banners |
| `Write-Section` | Display stream | Terminal only | Section headers |
| `Write-Separator` | Display stream | Terminal only | Divider lines |

`Write-Host` writes to PS stream 6 (display only) — DattoRMM captures stdout (stream 1) and never sees `Write-Host` output. No conditional logic needed.

### Severity Levels

| Level | Color | Usage |
|---|---|---|
| `INFO` | Cyan | General progress |
| `SUCCESS` | Green | Key operation confirmed complete |
| `WARN` | Yellow | Non-fatal, unexpected but recoverable |
| `ERROR` | Red | Failures, caught exceptions |
| `DEBUG` | Magenta | Granular detail, variable states |
| `PLAIN` | Gray | Labels/metadata, no severity prefix |

### Log Root

`C:\Databranch\ScriptLogs\<ScriptName>\<ScriptName>_yyyy-MM-dd.log`
Log rotation: keep last **10** log files per script.

---

## 4. Production Scripts — Datto-Ready

These are fully standard-compliant scripts with HTML documentation. Each lives in its own named subfolder within `!Datto-Ready Claude Scripts/`.

---

### Invoke-MailRemediation
**Version:** 1.2.1.0 | **Author:** Sam Kirsch | **Context:** SYSTEM (DattoRMM) or Domain Admin

Searches and remediates malicious emails across all mailboxes in an M365 tenant via Microsoft Graph API. Retrieves client App Registration credentials from ITGlue, authenticates via OAuth2 client_credentials, enumerates all licensed mailboxes, and performs a collect-then-act workflow with multiple safety gates before any deletions occur.

**Key capabilities:**
- ITGlue password lookup via REST API to retrieve the per-client App Registration secret
- Full mailbox enumeration (paged) before any action is taken
- Safety gates: multiple-matches-per-mailbox hard stop, internal sender domain check, configurable `MaxDeletions` cap
- Modes: `ReportOnly` (default), `SoftDelete`, `HardDelete`
- `AllowDelete` must be explicitly `'true'` — two-step workflow forces confirmation before deletion
- No external modules — all API calls via `Invoke-RestMethod`

**DattoRMM inputs:** `ITGlueApiKey`, `ITGlueBaseUrl`, `ITGlueOrgId`, `Subject`, `SenderAddress`, `MessageId`, `RemediationMode`, `AllowDelete`, `MaxDeletions`, `AllowOverrideSafeguards`

**Companion docs:** `Invoke-MailRemediation-Setup.md`

---

### Invoke-WindowsMaintenance
**Version:** 1.0.0.2 | **Author:** Sam Kirsch | **Context:** SYSTEM (DattoRMM) or local/domain Administrator

Comprehensive Windows system integrity and maintenance script covering SFC, DISM, CHKDSK, and drive optimization. Structured as a multi-phase pipeline with configurable execution profiles for workstations vs. servers. Uses an additive bitfield exit code to represent multiple simultaneous outcomes.

**Execution phases (in order):**
1. Pre-flight — elevation check, OS/volume/disk inventory, dirty-bit detection
2. SFC Pass 1 — System File Checker initial scan
3. DISM — CheckHealth → ScanHealth → RestoreHealth (if needed)
4. SFC Pass 2 — re-verify after DISM repair (triple-pass strategy)
5. CHKDSK — online scan per volume; schedules offline `/F /R` on errors or dirty volumes
6. Optimization — defrag (HDD) or retrim (SSD) per volume; skipped in Server profile
7. Cleanup — optional WinSxS component cleanup (off by default)
8. Summary — consolidated results, reboot recommendations, bitfield exit code

**Profiles:** `Workstation` (full), `Server` (conservative — no optimization), `ServerAggressive` (server + optimization unlocked for maintenance windows)

**Exit codes (additive bitfield):** 0=clean, 2=reboot recommended, 4=SFC errors not repaired, 8=DISM failed, 16=CHKDSK scheduling failed, 32=optimization failed, 64=pre-flight warning. The script **never triggers a reboot** — it only flags recommendations.

**Companion docs:** `Invoke-WindowsMaintenance-HowTo.html`, `Invoke-WindowsMaintenance-TechSpec.html`

---

### Start-ADInventoryCollection
**Version:** 1.0.0.0 | **Author:** Josh Britton | **Context:** Domain Admin

Comprehensive Active Directory environment inventory. Queries AD for all users, servers, and desktop computers; collects hardware data from online desktops in parallel (WinRM with DCOM fallback); sends Wake-on-LAN packets to power on offline machines; merges fresh data with cached data from the previous run.

**Key capabilities:**
- Parallel hardware collection via runspaces (PS 5.1 compatible)
- WoL sent locally and via all DC subnets for cross-subnet reach
- Smart caching: only re-collects machines that were online; offline machines carry forward cached hardware
- Detects computers removed from AD since last run
- MAC address discovery from DHCP leases and ARP tables across all DCs
- Outputs: `usersAD.csv`, `serversAD.csv`, `desktopsAD.csv`, `desktopsFINAL.csv`, `ADCollectionErrorReport.csv`, `RemovedFromAD.csv`

**Prerequisites:** RSAT/ActiveDirectory module, DHCP Server module, WinRM or DCOM access to desktops

**Companion docs:** `Start-ADInventoryCollection-HowTo.html`, `Start-ADInventoryCollection-TechSpec.html`

---

### Start-BECInvestigation
**Version:** 4.0.2.0 | **Author:** Sam Kirsch | **Context:** Interactive technician workstation

Initializes a complete, self-contained Business Email Compromise (BEC) investigation workspace. Does not connect to Exchange Online or Graph directly — generates three pre-configured investigation scripts and a structured workspace folder, then the technician runs those scripts in sequence. Remediation (account lockdown) is performed separately via CIPP Compromise Remediation.

**Generated workspace structure:**
```
BEC-Investigation_<alias>_<timestamp>/
    Investigation.xml                 (auto-managed config tracking state)
    Investigation-README.txt          (per-investigation quick reference)
    Scripts/
        Invoke-BECDataCollection.ps1
        Invoke-BECLogAnalysis.ps1
        Invoke-BECMessageTraceRetrieval.ps1
    RawData/   (collected CSVs)
    Reports/   (flagged suspicious artifacts)
    Analysis/  (reports, timeline, evidence manifest)
    Logs/      (per-run transcripts)
```

A `BEC-QUICK-REFERENCE.txt` guide (27KB) is included alongside the script as a standalone tech reference.

**Inputs:** `VictimEmail` (required), `WorkingDirectory`, `IncidentTicket`, `Technician`

**Companion docs:** `Start-BECInvestigation-HowTo.html`, `Start-BECInvestigation-TechSpec.html`

---

### Start-EventLogCollection
**Version:** 1.1.0.0 | **Author:** Josh Britton / Sam Kirsch | **Context:** Domain Admin or SYSTEM with delegated rights

Collects Windows Event Log entries from local and remote servers in two modes:

- **Automated mode:** Discovers all Windows Server machines on the domain via AD query (with ping sweep + OS fingerprinting fallback). Always includes the local machine. Parallel processing via runspaces.
- **Custom mode:** Targets a specific list of servers via `-ComputerName` (accepts hostnames, FQDNs, IPs in any combination, including a comma-separated single string for DattoRMM compatibility).

Performs a connectivity pre-check (CIM first, WinRM fallback) before attempting collection on each target. Output written to a timestamped subfolder under `C:\Databranch`.

**DattoRMM inputs:** `Mode`, `ComputerName`, `DaysBack` (default 30), `OutputPath`, `LogNames` (default: Application, System), `Subnets`

**Companion docs:** `Start-EventLogCollection-HowTo.html`, `Start-EventLogCollection-TechSpec.html`

---

### Start-ScriptManagementBrowser
**Version:** 1.0.12.0 | **Author:** Sam Kirsch | **Context:** Interactive desktop — Senior Engineers only | **Requires:** PS 7.0+

WPF GUI application that indexes all `.ps1` and `.bat` files from a local Git repository. Provides browsing, viewing, tagging, commenting, renaming, and VSCode integration. Stores comments and tags directly in managed script files using a structured comment syntax. Includes SharePoint sync that pushes the local Git repo to a designated SharePoint subfolder (one-way, Git is master) using a timestamp-first, hash-as-tiebreaker delta strategy.

**Note:** This is the successor to `EngineersPowerApp_PS7_git.ps1`. It reads and upgrades the legacy `##ENGINEERSPOWERAPP#` comment syntax transparently on next save. Requires PS 7 (WPF threading model); `DattoRMM: Not applicable`.

**Config stored:** `%APPDATA%\ScriptManagementBrowser\config.json`

**Companion docs:** `Start-ScriptManagementBrowser-HowTo.html`, `Start-ScriptManagementBrowser-TechSpec.html`

---

### Sync-OrgKeysToSiteVariables
**Version:** 1.4.1.006 | **Author:** Sam Kirsch | **Context:** SYSTEM (DattoRMM scheduled component on designated management host)

Solves a specific naming-mismatch problem: DattoRMM sites use a `CompanyName - SiteName` convention, which causes the Huntress installer to create duplicate organizations. This script stamps two site-level variables onto every DattoRMM site by cross-referencing all three APIs:

| Variable | Source | Value |
|---|---|---|
| `ITGOrgKey` | ITGlue API | Numeric ITGlue organization ID |
| `HUNTRESS_ORG_KEY` | Huntress API | Dashed organization key string |

**Key design decisions:**
- **Default-safe:** Report-only mode is on by default. Writes only occur if `ReportOnly` is the **explicit literal string `'false'`** — any other value (typo, blank, garbage) stays safely in report-only
- Fuzzy company name matching: handles names with embedded dashes by trying progressively longer prefixes left-to-right
- Write throttle: sliding 60-second queue tracking API writes, sleeps when approaching Datto's 100/min ceiling
- Secrets nulled immediately after use; never appear in logs
- Per-org outcome logged: `[WROTE]`, `[SKIPPED-CURRENT]`, `[SKIPPED-REPORT]`, `[SKIPPED-NO-MATCH]`

**API integrations:** DattoRMM REST API (OAuth2), ITGlue REST API, Huntress REST API

**Companion docs:** `Sync-OrgKeysToSiteVariables.md`

---

## 5. In-Development Scripts — Testing Queue

Located in `!Datto-Ready Claude Scripts/!Testing/`. All are standard-compliant but not yet promoted to production. Most have DattoRMM compatibility.

| Script | Version | Synopsis | DattoRMM |
|---|---|---|---|
| `Backup-QuickAccessPins.ps1` | 1.1.0.0 | Backs up Quick Access pin data (AutomaticDestinations) for specified or all users | Yes |
| `Restore-QuickAccessPins.ps1` | 1.1.2.0 | Restores Quick Access pin data from a previous Backup-QuickAccessPins backup | Yes |
| `Install-QuickAccessPinTasks.ps1` | 1.0.0.0 | Installs scheduled tasks to automate Quick Access backup/restore without elevation | Yes |
| `Get-QuickAccessDiagnostics.ps1` | 1.0.0.1 | Diagnoses Quick Access pin issues; outputs HTML report | Yes |
| `Invoke-DiskCleanup.ps1` | 1.0.0.0 | Targeted safe disk cleanup for Windows 11 domain workstations (Temp, AppData Temp, etc.) | Yes |
| `Remove-FilesByPattern.ps1` | 1.0.0.0 | Recursively removes files by name pattern from specified root paths with exclusion support | Yes |
| `Get-TopLongestPaths.ps1` | 1.0.0.0 | Lists top N longest file paths under a directory (sorted by character count) | Yes |
| `Invoke-PenTestRemediation.ps1` | 1.0.0.0 | Applies local security hardening from Databranch PenTest Remediation process (idempotent) | Yes |
| `Invoke-SingleUserAirgap.ps1` | 1.0.0.1 | Blocks all outbound internet traffic for a specific domain user SID via Windows Firewall | Yes |
| `Install-VSSApplication.ps1` | 1.3.1.0 | Downloads and silently installs VIVOTEK VAST Security Station | Yes |
| `Get-UsbStorForensics.ps1` | 1.1.0.002 | USB storage forensics — registry analysis of connected USB devices | — |
| `Get-CalendarEventCreator.ps1` | WIP | Retrieves calendar event details including organizer, creator, and metadata | — |
| `Search-CalendarEventAudit.ps1` | WIP | Audits calendar events on shared mailbox calendars | — |
| `test-huntress.ps1` | WIP | Huntress integration testing/validation script | — |

**Notable pattern — Quick Access suite:** `Backup-`, `Restore-`, `Install-QuickAccessPinTasks`, and `Get-QuickAccessDiagnostics` form a related four-script suite addressing a specific Windows 11 issue with Quick Access pins being lost. The diagnostics script produces an HTML output report (sample: `QuickAccess_Diagnostics_20260309_152113.html` included in the folder).

**Notable pattern — Invoke-PenTestRemediation:** Idempotent security hardening script deployable as a recurring DattoRMM job. Applies: FTP/Telnet firewall blocks, IPv6 disable (registry + firewall), LLMNR disable, mDNS disable, NetBIOS disable, SMBv1 disable, and additional controls derived from Databranch's PenTest Remediation process. Each control independently switchable via parameter.

---

## 6. CIPP-Ready Scripts

Located in `!CIPP-Ready Claude Scripts/`. These run in the CIPP platform context via CIPP scripting (PowerShell executing with CIPP's GDAP service account against M365 tenants).

### CIPP-MailRemediation
**Versions:** v10.3 (current), v2.0 (prior iteration)
**Files:** `CIPP-MailRemediation-v10.3.ps1`, `CIPP-MailRemediation-Guide-v10.3.md`

M365 mail remediation script designed to run within the CIPP scripting engine rather than as a standalone DattoRMM component. The CIPP context provides GDAP-based multi-tenant Graph API access without needing to manage per-client App Registrations. Companion guide is a markdown document with deployment instructions.

**Relationship to Invoke-MailRemediation:** The DattoRMM version (`Invoke-MailRemediation.ps1`) uses ITGlue to retrieve per-client App Registration credentials. The CIPP version leverages CIPP's existing credential management instead — two delivery paths for the same core remediation capability.

---

## 7. Legacy Library — Categorized Inventory

These scripts predate the current standards. Functionality is sound but they vary significantly in structure, header completeness, and DattoRMM compatibility. Good candidates for modernization when functionality is needed.

### Active Directory (`AD/` — 24 scripts)

The most script-dense legacy category. Covers the full AD lifecycle:

| Script | Function |
|---|---|
| `Bulk AD User Creation.ps1` | Creates AD users in bulk from CSV input |
| `Bulk_Create_AD_Share_Groups.ps1` | Creates AD groups for file share access |
| `Bulk_Set_AD_Attribute.ps1` | Sets an attribute on multiple AD accounts in bulk |
| `Bulk_Set_AD_Attribute_Entra_Sync.ps1` | Sets attributes with Entra ID sync considerations |
| `AD_Account_Resets(Scrambled PW).ps1` | Resets AD accounts with randomized passwords |
| `AD_Gather_Enabled_Users.ps1` | Exports all enabled AD users |
| `AD_User_Domain_Move.ps1` | Moves user accounts between domains |
| `CreateADGroup.ps1` | Creates a single AD group |
| `Add PC to AD group.ps1` | Adds a computer account to an AD group |
| `Set_AD_Accounts.ps1` | Sets properties on AD accounts |
| `Set_AD_Accounts_Remove_Login_Script_Home_Folder.ps1` | Removes login script and home folder from AD accounts |
| `Disable AD Accounts.ps1` | Disables AD accounts |
| `New AD Creation.ps1` | Creates a new AD user account |
| `Login Audit.ps1` | Audits AD login events |
| `DC Backup.ps1` | Domain Controller backup operations |
| `SingleDCVerifer.ps1` | Verifies DC health (large script, 10KB) |
| `DeltaSync.ps1` / `FullSync.ps1` | Entra ID delta / full sync triggers |
| `RemoveProfile-HomeDrive.ps1` | Removes user profiles and home drives |
| `Test and Set AD RecycleBin.ps1` | Enables/verifies AD Recycle Bin feature |
| `AD Test.ps1` | AD connectivity and configuration testing |

### Microsoft 365 / Exchange Online (`O365/` — 23 scripts)

Covers M365 administration, MFA reporting, and Exchange Online management:

| Script | Function |
|---|---|
| `GetMFAReport.ps1` | Generates MFA status report across tenant |
| `MFA Enrollment Counts.ps1` / `MFA Enrollment Counts Enabled-Enforced-Disabled.ps1` | MFA enrollment statistics |
| `Smtp_auth_disabled.ps1` | Disables SMTP AUTH on mailboxes |
| `O365_Set_StrongPassword_Required.ps1` | Enforces strong password policy in M365 |
| `Force_O365_Signout.ps1` | Forces sign-out of all active sessions |
| `Bulk_Shared_Mailbox_Create.ps1` | Creates shared mailboxes in bulk |
| `get_basicAuth_settings.ps1` | Reports on Basic Authentication status |
| `O365_Delegated_Trusted_Sender*.ps1` | Manages trusted sender lists (3 variants) |
| `MS_Purview_Parse_Tool.ps1` | Parses Microsoft Purview compliance data |
| `Create-SecureAppModel.ps1` | Creates Secure App Model registration for CIPP/automation |
| `SecureAppTest.ps1` | Tests Secure App Model authentication |
| `Check C2R Office Version.ps1` | Checks Click-to-Run Office version |
| `Update_Safe_Sender_Tenant.ps1` | Updates safe sender list at tenant level |
| `OneDriveSites.ps1` | Enumerates OneDrive sites |
| `JME_EmergencyVM_MessageTrace.ps1` | Emergency message trace for specific client (JME) |
| **CIPP subfolder:** `Deploy_CIPP_Check_DB_Customized.ps1` | Deploys CIPP Check browser extension with Databranch branding for Chrome and Edge; accepts CIPP Tenant ID as parameter; forked from CyberDrain GitHub |

### Networking (`Networking/` — 10 scripts)

| Script | Function |
|---|---|
| `Wireless_Profile_Setup_Datto_RMM.ps1` | Deploys wireless profiles via DattoRMM (14KB, full-featured) |
| `Wireless_Profile_Setup.ps1` | Standalone wireless profile deployment |
| `Wireless_Profile_Test.ps1` | Tests wireless profile configuration |
| `Windows_VPN_Setup.ps1` | Configures Windows VPN connections |
| `IP Config Release Renew.ps1` | Releases and renews IP configuration |
| `Monitor_Network_Profiles.ps1` | Monitors network profile state |
| `Radius_Allow_Windows_Firewall.ps1` | Opens Windows Firewall for RADIUS |

### Hardware Inventory (`Hardware/Inventory/` — 10 scripts)

Multiple generations of inventory reporting scripts showing the evolution toward `Start-ADInventoryCollection`:

| Script | Notes |
|---|---|
| `WIP_InventoryReport_2-10-26.ps1` | Most recent WIP iteration |
| `InventoryReport_9-23-20.ps1` / `_9-23-19.ps1` / `_1-8-21.ps1` | Dated versions |
| `InventoryReport_1-26-22 - FOR CW AUTOMATE.ps1` | CW Automate-specific variant |
| `Get-SMBShare.ps1` / `Get-SMBSharePerms.ps1` | SMB share enumeration |
| `Get_Monitor_Info.ps1` | Monitor hardware detection |
| `Bulk_username_change.ps1` | Bulk username rename utility |

### BitLocker (`Bitlocker/` — 10 scripts)

Covers the full BitLocker management lifecycle including setup automation, key retrieval, and group checks. Multiple dated versions reflect ongoing refinement:
`DB_Bitlocker_Setup_Automation.ps1` (current), `DB_Bitlocker_Setup_Automation-3-22-23.ps1`, `_6-7-21.ps1` | `DB_Bitlocker_Group Check.ps1` | `Bitlocker_GFS_Get_Key_AD_Sync.ps1` | `Bitlocker_Automate_Get_Key_EDF.ps1` | `Automate Bitlocker.ps1`

### BreachSecureNow (`BSN/` — 5 scripts)

All variations of the same core task: adding BreachSecureNow IP addresses to M365 allowed senders list. Multiple dated versions (`6-19-23`, `12-16-21`, `10-21-22`, `7-10-25`) reflect updated BSN IP ranges over time. The most current is `BSN_Whitelisting_7-10-25.ps1`.

### Software Deployment (`Software/`)

| Script | Function |
|---|---|
| `Huntress/Install_Huntress_Agent.ps1` | Full-featured Huntress agent installer (28KB) |
| `HP Programs/HP_Wolf_Security_Remove.ps1` | Removes HP Wolf Security bloatware |
| `Zorus(1)/Zorus Agent Install.ps1` | Zorus DNS agent installer |

### PC Maintenance (`PC Maintenance/`)

| Script | Function |
|---|---|
| `Databranch_Folder_Cleanup.ps1` | Cleans Databranch-specific temp folders |
| `Named_Folder_Cleanup.ps1` | Parameterized folder cleanup |
| `Kiwi_Syslog_Folder_Cleanup.ps1` | Kiwi Syslog log rotation |
| `ScreenConnect_File_Delete_Hash.ps1` | Cleans ScreenConnect temp files by hash |

### Key Integration Scripts

| Script | Location | Function |
|---|---|---|
| `BWM Update ProtectedAccount Password and Update ITGlue config and password.ps1` | `DattoRMM/` | Rotates local ProtectedAccount password and syncs to ITGlue via REST API. Matches device by BIOS serial number, handles duplicate password record deduplication in ITGlue. |
| `Update-ManageContactOnConfiguration.ps1` | `ConnectWise/` | CW Manage + CW Automate API integration — updates Configuration contact fields based on EDF data. Uses community `ConnectWiseManageAPI` and `AutomateAPI` modules. |
| `Deploy_CIPP_Check_DB_Customized.ps1` | `O365/CIPP/CHECK/` | Deploys CIPP Check browser extension with Databranch branding to Chrome and Edge via registry policy. Accepts CIPP Tenant ID parameter. Forked from CyberDrain GitHub. |
| `Shield_Trusted_Site_Regkey.ps1` | `MailProtector/` | Sets MailProtector Shield trusted site registry keys |

### Other Legacy Categories (smaller)

| Category | Scripts | Notes |
|---|---|---|
| `ACL/` | 2 | ACL copy loop, AD home drive ACL fix |
| `Exchange On-Prem/` | 3 | 0-day block script (Sep 2022), mailbox export, offline address book |
| `File Server/` | 2 | NTFS permissions reporter, legacy CWA share permissions script |
| `GPO/` | 5 | Group policy deployment scripts (including SkyKick migration GPO) |
| `Duo/` | 1 | DUO Auth Proxy config backup |
| `Log4j/` | 1 | Log4j detection script (Dec 2021 incident response) |
| `Printing/` | 2 | Print spooler bounce, remove printer server mappings |
| `Registry/` | 1 | Registry key check and set utility |
| `Scale HCI/` | 2 | Scale Computing cluster health check (REST API), encrypted shutdown batch |
| `SMB/` | 1 | SMB share enumeration |
| `Windows Services and Processes/` | 2 | Service startup check/set, temporary process start |
| `Zorus/` | 2 | Zorus install/uninstall for specific client (OHA) |
| `Offline File Sync/` | 2 | Remove offline file sync partnerships |
| `Monitoring/` | 1 | ScreenConnect connection ID monitoring |

### Root-Level Miscellaneous Scripts

A collection of standalone scripts at the repo root, mostly utilities and one-offs predating folder organization:

| Script | Function |
|---|---|
| `EngineersPowerApp_PS7_git.ps1` | Legacy predecessor to `Start-ScriptManagementBrowser`; full WPF GUI, PS 7 only, SharePoint-based |
| `InventoryReport_WIP.ps1` | Inventory report work-in-progress (24KB) |
| `Get-MFAStatus.ps1` | MFA status reporting across M365 |
| `Invoke-RemoveBuiltinApps.ps1` | Removes Windows built-in/bloatware apps |
| `Enable-WOLWindowsNICSettings.ps1` | Enables Wake-on-LAN NIC settings |
| `Teams Cache Clear and Delete.ps1` | Clears Teams cache |
| `PasswordGenerator.ps1` / `PasswordEncryptor.ps1` | Password generation and encryption utilities |
| `Get-installedprogram.ps1` | Installed program enumeration |
| `DeleteOldFiles.ps1` / `DeleteOldFiles_Allegany_County_ARC.ps1` | Old file cleanup (one generic, one client-specific) |
| `BATCH-RUN_PS_FROM_SAME_FOLDER.bat` | Utility batch wrapper to run PS from same directory |
| `autologonTEMPLATE.reg` | Auto-logon registry template |
| `MapWebDavShare.ps1` | Maps a WebDAV share as a drive |
| `LocalAdminUpdate.ps1` | Updates local admin account |

---

## 8. Internal Tooling

### Engineers PowerApp (Legacy)
`EngineersPowerApp_PS7_git.ps1` — PS 7.0+, WPF GUI, SharePoint-backed script browser. Tags and comments stored in managed files using `##ENGINEERSPOWERAPP#COMMENT#` and `##ENGINEERSPOWERAPP#TAGS#` syntax. Active but being superseded.

### Start-ScriptManagementBrowser (Current)
`!Datto-Ready Claude Scripts/Start-ScriptManagementBrowser/Start-ScriptManagementBrowser.ps1` — The current generation script manager. Reads legacy EngineersPowerApp syntax and upgrades on save. Git-native (local repo) with optional SharePoint push sync.

### GitHub Integration (`!Testing/` root)
Three scripts for GitHub API integration from DattoRMM context:
- `Connect to Github - DattoRMM.ps1` — GitHub API connection for DattoRMM
- `Connect to Github.ps1` — GitHub API connection (interactive)
- `Talk to GitHub.ps1` — Prototype GitHub API communication

---

## 9. Documentation Standards

Full design spec: `Databranch_DocumentationSpec.md` and `Databranch_UIDesignSpec.html` (in `!Datto-Ready Claude Scripts/`).

### Two Document Types

| Type | File Name Pattern | Audience |
|---|---|---|
| Operator How-To Guide | `<ScriptName>-HowTo.html` | Engineers / Technicians |
| Technical Specification | `<ScriptName>-TechSpec.html` | Script authors / Senior engineers |

### Design System
- **Fonts:** IBM Plex Sans (body) + IBM Plex Mono (code)
- **Theme:** Dark navy color scheme
- **Layout:** Fixed left sidebar with scroll-spy navigation
- **CSS variables** shared across both document types for consistency

### Rules
- Documentation is produced **only when explicitly requested** — not auto-generated
- Once docs exist, every version increment that changes behavior/parameters/output requires updated docs
- Version number and date in both cover block and document footer must match the current script version
- TechSpec includes a Version History section with `.version-entry` blocks (newest first)

---

## 10. Key Patterns & Conventions for AI Collaboration

When continuing work on this script library in any new conversation, these rules govern all behavior:

### Context Setup
Paste `Databranch_ScriptLibrary_ProjectSpec.md`, `Databranch_DocumentationSpec.md`, and `Invoke-ScriptTemplate.ps1` at the start of any new script conversation. All standards in those files apply without re-negotiation.

### Script Delivery Rules
- State the full version number in every chat response that delivers a complete updated script
- Every code change = new version number + changelog entry
- Never deliver a partial script — always the complete file

### Author Fields
- New scripts: set `Author` to the current conversation user (fullest name available)
- Modifying existing scripts: leave `Author` as-is, add current user to `Contributors` and `Modified By`
- Never leave `Author` as `<Author Name>` if context provides a name

### What NOT to Use in PS 5.1

| Avoid | Use Instead |
|---|---|
| `?:` ternary | `if ($a) { $b } else { $c }` |
| `??` null coalescing | `if ($a) { $a } else { $b }` |
| `$list[-1]` | `$list[$list.Count - 1]` |
| `ForEach-Object -Parallel` | Runspaces |
| `[bool]$env:Flag` or `if ($env:Flag)` | `if ($env:Flag -eq 'true')` |
| `New-Object` for generic list | `New-Object -TypeName 'System.Collections.Generic.List[PSObject]'` |
| Format-Table/List/Wide in RMM output | `Write-Log` lines |

### Security Non-Negotiables
- Secrets never in logs, stdout, or on disk
- Null secrets immediately after use
- DattoRMM env vars for all secret delivery
- TLS 1.2 enforcement on all HTTPS scripts (after `param()`)

### DattoRMM Component Design Checklist
- [ ] `param()` with DattoRMM env var fallback for every parameter
- [ ] `CS_PROFILE_NAME` and `CS_HOSTNAME` always wired up
- [ ] Boolean env vars compared with `-eq 'true'` — never cast to `[bool]`
- [ ] Exit 0 / 1 / 2 explicit (and any script-specific codes documented in `.NOTES`)
- [ ] No `Format-Table/List/Wide` anywhere in output
- [ ] TLS 1.2 line after `param()` if making HTTPS calls
- [ ] Secrets nulled immediately after use
- [ ] Log rotation via `Initialize-Logging` (keep last 10)
- [ ] Standard log header written at startup
- [ ] Pre-flight validation block with `exit 2` on failure

---

*This document is part of the Databranch Script Library reference set. Store alongside `Databranch_ScriptLibrary_ProjectSpec.md`, `Databranch_DocumentationSpec.md`, and `Invoke-ScriptTemplate.ps1` in GitHub.*
