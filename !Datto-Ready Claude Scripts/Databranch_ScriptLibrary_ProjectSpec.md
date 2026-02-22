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

## Console Output Standards (Dual-Output Pattern)

Scripts use a **two-layer output model** that separates structured logging from human-friendly presentation. Both layers always run — they write to completely independent streams and do not interfere with each other.

| Function          | Stream          | Captured By                      | Purpose                                          |
|-------------------|-----------------|----------------------------------|--------------------------------------------------|
| `Write-Log`       | stdout / stderr | DattoRMM, pipeline, log file     | Structured `[timestamp][SEVERITY]` entries       |
| `Write-Console`   | Display stream  | Terminal only                    | Colored, formatted output for interactive runs   |
| `Write-Banner`    | Display stream  | Terminal only                    | Script start/end banners                         |
| `Write-Section`   | Display stream  | Terminal only                    | Section headers within a run                     |
| `Write-Separator` | Display stream  | Terminal only                    | Divider lines between logical groups             |

### Why `Write-Host` for console output?
`Write-Host` writes to PowerShell's display stream (stream 6), which is separate from stdout (stream 1). DattoRMM agents capture stdout — not the display stream — so `Write-Host` output is automatically suppressed in automated runs. No conditional logic or environment detection needed.

### Severity Color Scheme (`Write-Console`)
| Severity  | Color    | Notes                                      |
|-----------|----------|--------------------------------------------|
| `INFO`    | Cyan     |                                            |
| `SUCCESS` | Green    |                                            |
| `WARN`    | Yellow   |                                            |
| `ERROR`   | Red      |                                            |
| `DEBUG`   | Magenta  |                                            |
| `PLAIN`   | Gray     | No severity prefix — use for labels/metadata |

### Console Structure Convention
```
============================================================   <- Write-Banner (script open)
  SCRIPT-NAME v1.0.0.0
============================================================

Site     : ClientName
Hostname : MACHINENAME
Run As   : DOMAIN\user
Log File : C:\Databranch\ScriptLogs\...
------------------------------------------------------------   <- Write-Separator

---- Section Name ------------------------------------------   <- Write-Section
[INFO] Starting phase...
[SUCCESS] Step completed.
  [DEBUG] Sub-detail here                                       <- Write-Console -Indent 1

---- Next Section ------------------------------------------
...

============================================================   <- Write-Banner (script end)
  COMPLETED SUCCESSFULLY  -or-  SCRIPT FAILED
============================================================
```

### Usage Pattern
Every significant log entry should have a paired console call:
```powershell
Write-Section "Collecting User Data"
Write-Log     "Collecting user data..."  -Severity INFO
Write-Console "Collecting user data..."  -Severity INFO

Write-Log     "Found 42 users."          -Severity SUCCESS
Write-Console "Found 42 users."          -Severity SUCCESS

# Sub-items use -Indent on console side only
Write-Log     "  Skipped: $user"         -Severity WARN
Write-Console "Skipped: $user"           -Severity WARN   -Indent 1
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

## Documentation Standards

Each script may have up to two companion HTML documentation files. Full design and content specifications are defined in `Databranch_DocumentationSpec.md`, which is included alongside this spec and the script template.

### Key Rules

**Do not auto-generate documentation.** Documentation is produced only when explicitly requested during a script conversation.

**Once documentation exists, keep it in sync.** Every script version increment that changes behavior, parameters, output, or error handling must include updated documentation files.

**Two document types:**

| Type                    | File Naming                      | Audience                          |
|-------------------------|----------------------------------|-----------------------------------|
| Operator How-To Guide   | `<ScriptName>-HowTo.html`        | Engineers / Technicians           |
| Technical Specification | `<ScriptName>-TechSpec.html`     | Script authors / Senior engineers |

**Design system:** IBM Plex Sans + IBM Plex Mono fonts. Dark navy color scheme. Fixed left sidebar with scroll-spy navigation. Shared CSS variables, components, and print styles across both document types. Full design token and component reference is in `Databranch_DocumentationSpec.md`.

**Versioning in docs:** Version number and date in both the cover block meta and the document footer must always match the current script version. The TechSpec contains a Version History section with `.version-entry` blocks (newest first). The HowTo surfaces version only in the cover and footer.

**To request documentation** during a script conversation, say something like:
> *"Please generate documentation for this script."*

Both files will be produced together. From that point forward, doc updates accompany every code iteration automatically.

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
> **Instructions:** Please review the attached project spec (`Databranch_ScriptLibrary_ProjectSpec.md`), the documentation standard (`Databranch_DocumentationSpec.md`), and the standard script template (`Invoke-ScriptTemplate.ps1`) before we begin. All standards defined in these files apply to this script. You can also reference prior conversations in the Databranch Script Library Claude Project for additional context.
>
> Here is the script we will be working on today:
>
> `[paste script here]`
---

