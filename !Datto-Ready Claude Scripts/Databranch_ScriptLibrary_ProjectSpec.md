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

### Built-in Agent Environment Variables

All of the following are available automatically in every component — no configuration needed. **Do not add them all to every script.** Only wire up a variable as a script parameter if the script actually uses it. The full list is here for reference so you know what exists.

**Always include in every script** (used in the standard log header):

| Variable               | Description             |
|------------------------|-------------------------|
| `$env:CS_PROFILE_NAME` | Site/customer name      |
| `$env:CS_HOSTNAME`     | Target machine hostname |

**Add only when the script needs them:**

| Variable                     | Description                                                        |
|------------------------------|--------------------------------------------------------------------|
| `$env:CS_ACCOUNT_UID`        | Unique identifier for the Datto RMM account managing this device   |
| `$env:CS_PROFILE_UID`        | Unique identifier for the site where this device is located        |
| `$env:CS_PROFILE_DESC`       | Description of the site where this device is located               |
| `$env:CS_DOMAIN`             | Local device domain (if domain-joined)                             |
| `$env:CS_CC_HOST`            | Control channel URI used by the Agent                              |
| `$env:CS_CSM_ADDRESS`        | Web Portal address this device connects to                         |
| `$env:CS_PROFILE_PROXY_TYPE` | `0` or `1` — whether a proxy is configured for the site            |
| `$env:UDF_1` … `$env:UDF_30` | Current values of the device's User-Defined Fields at job run time |

> UDF variables reflect the value at the time the job runs. If UDF data changes after the job starts, the in-process variable will not update. For monitoring components, UDF data is only valid at the time the policy is pushed.

### Exit Codes

Exit codes must always be explicit. Standard conventions:

| Code | Meaning |
|------|---------|
| `0`  | Success |
| `1`  | Runtime failure — script started but encountered errors during execution |
| `2`  | Fatal pre-flight failure — missing parameters, auth failure, or any condition preventing execution from starting |

Additional script-specific codes must be documented in `.NOTES`.

### stdout and Job Output

- `Write-Output` and `Write-Warning` both surface in the DattoRMM job log (stdout/stderr).
- **Never use `Format-Table`, `Format-List`, or `Format-Wide` for DattoRMM output.** These cmdlets produce fixed-width column output that renders as garbled text in the job log viewer. Write all job log data as individual `Write-Log` lines.

### Post-Conditions (Warning Text)

DattoRMM components support a **Post-Condition** field that scans stdout/stderr for a configured string. If the string is found, the job result is flagged as orange "Warning" status — independent of exit code. This is useful for surfacing partial-success states. The match is **case-sensitive**. Example: configure `WARNING:` in the post-condition field and include that literal prefix in relevant `Write-Log` output lines.

### SYSTEM Context Limitations

All DattoRMM scripts run as `NT AUTHORITY\SYSTEM` by default. Key limitations to design around:

| Limitation | Impact | Workaround |
|---|---|---|
| No desktop / no window | GUI installers with Next buttons hang silently | Always use silent/unattended install flags (`/qn`, `/S`, etc.) |
| No network authentication | Cannot authenticate to remote resources using the machine account | Use explicit credentials or machine-based certs |
| No mapped drives | User-mapped drives are not visible | Use UNC paths (`\\server\share`) directly |
| No user profile | User-specific paths (`%APPDATA%`, `%USERPROFILE%`) resolve to system paths | Use machine-scoped paths (`$env:ProgramData`, `$env:SystemRoot`) |

> Scheduled jobs can optionally run in the context of the logged-on user via advanced execution settings. Quick jobs always run as SYSTEM.

### Script Delivery

DattoRMM wraps `.ps1` scripts in a `.bat` file for delivery. The script runs from the component package directory. **Attached files** (images, installers, supplemental scripts) are extracted to the same directory and can be referenced with `.\filename` — no hardcoded paths needed.

### Writing to User-Defined Fields (UDFs) from Scripts

Scripts can write data back to DattoRMM by setting registry values. The agent syncs them to the platform automatically:

```powershell
# Write a value to UDF slot 5 (CustomX where X = UDF number)
New-ItemProperty -Path 'HKLM:\SOFTWARE\CentraStage' `
                 -Name 'Custom5' `
                 -Value 'YourValueHere' `
                 -PropertyType String `
                 -Force | Out-Null
```

- UDF values are limited to **255 characters**
- Once synced, the registry value is deleted by the agent — it won't persist on the device
- **Do not store credentials or sensitive data in UDFs** — they are visible in plain text in the portal
- UDF 1 is reserved by Ransomware Detection if that feature is enabled — avoid writing to Custom1 on endpoints with ransomware detection active

### Boolean Input Variables

DattoRMM Boolean-type component variables arrive as the **string** `"true"` or `"false"` — not PowerShell `$true`/`$false`. This is a critical gotcha:

```powershell
# WRONG - [bool]"false" evaluates to $true because any non-empty string is truthy
if ($env:EnableFeature) { ... }           # always true if var is set
if ([bool]$env:EnableFeature) { ... }     # always true even when value is "false"

# CORRECT - always compare DattoRMM boolean vars as strings
if ($env:EnableFeature -eq 'true') { ... }
```

Always use `-eq 'true'` string comparison for DattoRMM Boolean input variables. Never cast them to `[bool]` or evaluate them directly as truthiness.

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

## PowerShell 5.1 Compatibility Notes

The target runtime is PowerShell 5.1. Several modern PS patterns that work in PS 7+ silently fail or behave differently in 5.1. Always use the 5.1-safe equivalents listed below.

| Pattern | PS 7+ (avoid) | PS 5.1-safe (use this) |
|---|---|---|
| Generic list construction | `[System.Collections.Generic.List[PSObject]]::new()` | `New-Object -TypeName 'System.Collections.Generic.List[PSObject]'` |
| Negative array index | `$list[-1]` | `$list[$list.Count - 1]` |
| Ternary operator | `$x = $a ? $b : $c` | `$x = if ($a) { $b } else { $c }` |
| Null coalescing | `$x = $a ?? $b` | `$x = if ($a) { $a } else { $b }` |
| `ForEach-Object -Parallel` | `ForEach-Object -Parallel { }` | Runspaces (see parallel pattern in template) |
| DattoRMM Boolean env var | `if ($env:Flag)` or `if ([bool]$env:Flag)` | `if ($env:Flag -eq 'true')` — env vars are always strings |

> When in doubt about 5.1 compatibility, test explicitly. Do not assume PS 7+ syntax works in 5.1 just because it is cleaner.

---

## Security Standards

- Secrets (API keys, client secrets, passwords) must never be written to disk, log files, or stdout.
- DattoRMM environment variables are the correct delivery mechanism for secrets — they are passed via the process environment, not the command line, and are not visible in process listings.
- Once a secret has been used to acquire a token or session, **null it out immediately**: `$ClientSecret = $null`
- Secrets must never appear in `Write-Log` output, log headers, or parameter dumps.

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
- Explicit `exit 0` (success), `exit 1` (runtime errors), `exit 2` (fatal pre-flight failure)
- Pre-flight parameter validation block with `exit 2` on failure
- Secret/credential variables nulled out immediately after use

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

