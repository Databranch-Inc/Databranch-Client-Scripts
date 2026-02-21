# Databranch Script Library — Project Specification
### New Conversation Kickoff Reference
---

## About This Document
This spec is included at the start of every new script modernization conversation.
It establishes all standards, conventions, and context agreed upon during the initial
project setup so each conversation is immediately aligned without re-discussing fundamentals.

Reference project conversations are available in the **Databranch Script Library** Claude Project.

---

## Company & Context

| Field             | Value                                                                 |
|-------------------|-----------------------------------------------------------------------|
| Company           | Databranch                                                            |
| Industry          | IT MSP (Managed Service Provider)                                     |
| Author            | Sam Kirsch                                                            |
| Contributor Field | Original author credited if not Sam; Sam Kirsch listed as Contributor |
| RMM Platform      | Datto RMM (migrating from ConnectWise Automate)                       |
| Remote Access     | ConnectWise ScreenConnect (including Backstage = SYSTEM context)      |
| Ticketing/PSA     | ConnectWise Manage                                                     |
| Documentation     | ITGlue                                                                |
| Site Names        | Customer company names, synced from ConnectWise Manage into DattoRMM and ITGlue |

### Environment Scope
- Windows Domains (on-prem Active Directory)
- Microsoft 365 / Exchange Online
- Azure AD / Entra ID
- Windows Servers
- Windows Endpoints / Workstations

---

## PowerShell Standards

| Field                  | Value                                      |
|------------------------|--------------------------------------------|
| Target Version         | PowerShell 5.1 (universal compatibility)   |
| Execution Context      | Mixed — SYSTEM (DattoRMM/ScreenConnect) and Domain Admin (manual runs) |
| Error Handling         | `$ErrorActionPreference = 'Stop'` with `try/catch` throughout |
| Approved Verbs         | Always use `Get-Verb` approved verbs for function and file names |
| Master Function        | All code wrapped in a master function named to match the file |
| Entry Point            | Master function called at bottom using splatting (`@Params`) |
| File Naming            | Same name as the master function (e.g. `Invoke-ScriptName.ps1`) |

---

## DattoRMM Integration

- Scripts must support **both** DattoRMM automated runs (environment variable input) and manual runs (standard PowerShell parameters) without modification.
- Parameter fallback chain: **DattoRMM env var → PowerShell parameter → default value**
- DattoRMM built-in environment variables available automatically (no component config needed):

| Variable              | Description                        |
|-----------------------|------------------------------------|
| `$env:CS_PROFILE_NAME` | Site/customer name                |
| `$env:CS_HOSTNAME`     | Target machine hostname           |

- Exit codes must be explicit:
  - `0` = Success
  - `1` = General failure
  - Additional codes documented per script as needed
- stdout is the DattoRMM job output — `Write-Output` and `Write-Warning` both surface there.

---

## Logging Standards

| Field            | Value                                              |
|------------------|----------------------------------------------------|
| Log Root         | `C:\Databranch\ScriptLogs`                         |
| Log Path Pattern | `C:\Databranch\ScriptLogs\<ScriptName>\<ScriptName>_yyyy-MM-dd.log` |
| Log Rotation     | Keep last **10** log files per script, purge older on each run |
| Log Output       | Always to **both** stdout and log file             |
| Logging Level    | Always **verbose** — all severity levels always written, no filtering |

### Severity Levels

| Level     | Usage                                              |
|-----------|----------------------------------------------------|
| `INFO`    | General progress and status messages               |
| `WARN`    | Non-fatal issues, unexpected but recoverable state |
| `ERROR`   | Failures, caught exceptions                        |
| `SUCCESS` | Confirming a key operation completed successfully  |
| `DEBUG`   | Granular detail, variable states, diagnostic info  |

### Standard Log Header (written at start of every run)
```
===== <ScriptName> v<Version> =====
Site     : <CS_PROFILE_NAME or 'UnknownSite'>
Hostname : <CS_HOSTNAME or $env:COMPUTERNAME>
Run As   : <WindowsIdentity current user>
Params   : <key parameter values>
Log File : <full log file path>
```

---

## Script Header Block Standard

Every script must include a full comment-based help block containing:

```
.SYNOPSIS        One-line description
.DESCRIPTION     Full description, scope, dependencies, prerequisites
.PARAMETER       One entry per parameter with type, required/optional, default
.EXAMPLE         At least one full usage example
.NOTES
    File Name      : <FileName.ps1>
    Version        : <Major.Minor.Revision.Build>  e.g. 1.0.0.0
    Author         : <Original Author>
    Contributors   : <Sam Kirsch, others>
    Company        : Databranch
    Created        : <yyyy-MM-dd>
    Last Modified  : <yyyy-MM-dd>
    Modified By    : <Name>
    Requires       : PowerShell 5.1+
    Run Context    : SYSTEM or Domain Admin (specify which)
    DattoRMM       : Compatible / Not applicable
    Client Scope   : All clients / Client-specific (specify)
    Exit Codes     : Listed with meanings
.CHANGELOG
    v1.0.0.0 - yyyy-MM-dd - Author Name
        - Initial release
```

---

## Version Numbering

Format: `Major.Minor.Revision.Build` — e.g. `1.0.0.0`, `1.2.3.456`

| Segment    | When to increment                                              |
|------------|----------------------------------------------------------------|
| Major      | Breaking changes, complete rewrites, fundamental behavior change |
| Minor      | New features, significant enhancements                         |
| Revision   | Bug fixes, small improvements, refactoring                     |
| Build      | Internal iterations, work-in-progress increments               |

- Every code change must produce a new version number and a changelog entry.
- Version must appear in **both** the `.NOTES` block and the `$ScriptVersion` variable inside the master function.
- Full version must be included in every chat response that delivers a complete updated script.

---

## Code Quality & Style

- Prefer **simple and straightforward** approaches; suggest more sophisticated solutions only when complexity is genuinely warranted.
- When scripts have common feature sets, **proactively suggest or add** reasonable improvements (efficiency, robustness, additional utility).
- Use publicly available best practices and patterns for enterprise PowerShell.
- Use **splatting** for cmdlets with multiple parameters.
- Avoid positional parameters — always use named parameters.
- Use full cmdlet names — avoid aliases (e.g. `Where-Object` not `?`, `ForEach-Object` not `%`).
- Comment generously — sections, logic decisions, and anything non-obvious.
- Keep scripts **self-contained** — no external module dependencies unless absolutely necessary and clearly documented.

---

## Script Template

The standard template file `Invoke-ScriptTemplate.ps1` is the baseline for all scripts.
It is included alongside this spec document. Every new or refactored script should be
built from or validated against this template.

Key template elements:
- `#Requires -Version 5.1`
- Full `.NOTES` and `.CHANGELOG` comment block
- DattoRMM/manual parameter fallback pattern
- `Write-Log` internal function (all 5 severity levels, always verbose)
- `Initialize-Logging` function (folder creation + log rotation)
- `$ErrorActionPreference = 'Stop'` with `try/catch`
- Standard log header written at startup
- Master function wrapper with splatted entry point call at bottom
- Explicit `exit 0` / `exit 1` (or other documented codes)

---

## How to Use This Document in a New Conversation

Paste the following at the start of each new script chat:

---
> **Project:** Databranch Script Library Modernization
>
> **Instructions:** Please review the attached project spec (`Databranch_ScriptLibrary_ProjectSpec.md`) and the standard script template (`Invoke-ScriptTemplate.ps1`) before we begin. All standards defined in the spec apply to this script. You can also reference prior conversations in the Databranch Script Library Claude Project for additional context.
>
> Here is the script we will be working on today:
>
> `[paste script here]`
---

