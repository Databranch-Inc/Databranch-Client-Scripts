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
| Authors           | (see Author Standards below)                                          |
| Author Format     | Use full name if known (First Last), otherwise first name or handle   |
| RMM Platform      | Datto RMM (migrating from ConnectWise Automate)                       |
| Remote Access     | ConnectWise ScreenConnect (including Backstage = SYSTEM context)      |
| Ticketing/PSA     | ConnectWise Manage                                                     |
| Documentation     | ITGlue                                                                |
| Site Names        | Customer company names, synced from ConnectWise Manage into DattoRMM and ITGlue |

### Author Standards

These rules govern how Claude fills in the `Author`, `Contributors`, and `Modified By` fields when writing or updating scripts. Claude must follow these automatically — do not leave these as blank placeholders.

**When creating a new script from the template:**
- Set `Author` to the name of the person Claude is currently talking to in this conversation.
- Use the fullest name available: full `First Last` if known, first name only if that's all that's been established, or their handle/display name if that's all Claude has.
- If a different author is explicitly specified in the conversation, use that.

**When modifying an existing script:**
- Leave `Author` as-is — it reflects who originally wrote it.
- Add the current user to `Contributors` if they are not already listed.
- Update `Modified By` to the current user's name.
- Add a new `.CHANGELOG` entry crediting the current user.

**Name resolution priority (for Claude to apply):**
1. Full name explicitly stated in the current conversation (`"I'm John Doe"`) → use `John Doe`
2. Full name known from prior project context or memory → use it
3. First name known from conversation or account → use first name only
4. Nothing known → use `<Author Name>` as a placeholder and ask

Claude should never leave `Author` as the literal string `<Author Name>` when it has enough context to fill it in.

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
| TLS                    | Force TLS 1.2 in any script making HTTPS REST calls (see below) |

### Mandatory Script-Level Declaration Order

Every script must follow this exact top-level structure. The order is non-negotiable and must not be altered during development or iteration.

```
1.  #Requires -Version 5.1
2.  Comment-based help block  (<# .SYNOPSIS ... #>)
3.  TLS 1.2 enforcement block  (if script makes HTTPS calls)
4.  Parameter block comment(s)  (BOOLEAN GOTCHA, DattoRMM notes, etc.)
5.  [CmdletBinding()]
6.  param ( ... )
7.  [Net.ServicePointManager] line  ← NEVER here — belongs at step 3
```

**The single most common ordering mistake:** placing `[Net.ServicePointManager]::SecurityProtocol` between `[CmdletBinding()]` and `param()`. This is wrong. The TLS line is an executable statement. `[CmdletBinding()]` must appear immediately above `param()` with zero executable statements between them. Violating this breaks the CmdletBinding contract and has caused real bugs.

> **Rule:** If you are writing or reviewing a script and see anything other than `param (` on the line immediately after `[CmdletBinding()]`, stop and fix it before continuing.

The template enforces this order. Do not change the ordering of top-level blocks when deriving a script from the template.

### TLS 1.2 Enforcement

PowerShell 5.1 on older Windows builds (Server 2012 R2, early Windows 10) defaults to TLS 1.0/1.1 for web requests. Both the ITGlue API and Microsoft Graph/Azure AD token endpoints require TLS 1.2 minimum and will reject older connections — typically with errors that look like generic network failures, making the root cause hard to diagnose.

Any script that makes HTTPS REST calls must include the following block after the comment-based help block and **before** `[CmdletBinding()]`:

```powershell
# ==============================================================================
# TLS 1.2 ENFORCEMENT
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
```

The value `3072` is the numeric equivalent of `[Net.SecurityProtocolType]::Tls12`. The `ToObject` cast is used instead of the enum name directly because on some older .NET/PS 5.1 environments the `Tls12` enum member is not guaranteed to be defined by name at parse time, whereas the integer value always works.

---

## DattoRMM Integration

- Scripts must support **both** DattoRMM automated runs (environment variable input) and manual runs (standard PowerShell parameters) without modification.
- Parameter fallback chain: **DattoRMM env var → PowerShell parameter → default value**

### Built-in Agent Environment Variables

All of the following are available automatically in every component — no configuration needed. **Do not add them all to every script.** Only wire up a variable as a script parameter if the script actually uses it.

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

> UDF variables reflect the value at the time the job runs. If UDF data changes after the job starts, the in-process variable will not update.

### Boolean Input Variables — Two-Layer Gotcha

DattoRMM Boolean component variables arrive as the **string** `"true"` or `"false"`, never as actual PowerShell booleans. There are two distinct failure modes:

**Layer 1 — Never cast or evaluate as bool:**
```powershell
# WRONG — any non-empty string (including "false") is truthy
if ($env:EnableFeature) { ... }
if ([bool]$env:EnableFeature) { ... }

# CORRECT
if ($env:EnableFeature -eq 'true') { ... }
```

**Layer 2 — DattoRMM does not guarantee lowercase.** It may pass `'True'`, `'TRUE'`, or `' true '`. All boolean string comparisons must use `.Trim().ToLower() -eq 'true'`, not just `-eq 'true'`:

```powershell
# WRONG — breaks on 'True' or 'TRUE'
$IsEnabled = ($EnableFeature -eq 'true')

# CORRECT — handles any casing DattoRMM might produce
$IsEnabled = ($EnableFeature.Trim().ToLower() -eq 'true')
```

Apply `.Trim().ToLower()` to every boolean-style string parameter resolution. This is required for all parameters regardless of whether the value comes from DattoRMM or a manual invocation.

### Exit Codes

Exit codes must always be explicit. Standard conventions:

| Code | Meaning |
|------|---------|
| `0`  | Success |
| `1`  | Runtime failure — script started but encountered errors during execution |
| `2`  | Fatal pre-flight failure — missing parameters, auth failure, or any condition preventing execution from starting |

Additional script-specific codes must be documented in `.NOTES`.

### Post-Condition Warning Pattern

DattoRMM can scan stdout for a configured string and flag the job orange — independent of exit code. Use this for partial-success states where the script completed but something needs attention. Configure the match string in the component's Post-Condition field (case-sensitive).

```powershell
# In the script — emit the exact match string
Write-Log "WARNING: Some items could not be processed — review log." -Severity WARN

# In DattoRMM component Post-Condition field
# Match string: WARNING:
```

---

## Write-Capable Scripts — Safety Patterns

Any script that writes to external systems (APIs, Active Directory, DattoRMM, registry, etc.) must implement the following patterns. These are non-negotiable for all write-capable scripts in the library.

### Report-Only Mode — Safe by Default

Write-capable scripts must default to report-only mode. The script performs all matching, validation, and logging in report-only mode but gates all writes behind an explicit opt-in. This means the script can be run safely at any time without risk of unintended changes.

**Implementation:**

```powershell
# Parameter — defaults to report-only
[Parameter(Mandatory = $false)]
[string]$ReportOnly = $(if ($env:ReportOnly) { $env:ReportOnly } else { 'true' }),

# Resolution — safe by default
# The write gate uses an explicit 'false' check rather than 'not true'.
# This means any value other than the literal 'false' (typo, blank, garbage,
# unexpected casing) stays safely in report-only mode. Writes are opt-in,
# not opt-out.
$IsReportOnly = ($ReportOnly.Trim().ToLower() -ne 'false')
```

Note the asymmetry: `$IsReportOnly` uses `-ne 'false'` rather than `-eq 'true'`. This is intentional — report-only is the safe state. Any ambiguous value (blank, typo, unexpected casing) falls into report-only, never into write mode. Only the explicit literal string `'false'` enables writes.

**In the script body:**
```powershell
if ($IsReportOnly) {
    Write-VerboseLog "[SKIPPED-REPORT] Would write $varName = $varValue to '$target'"
}
else {
    # perform write
}
```

**In the summary output**, always emit the current mode so the log is unambiguous:
```powershell
$modeDisplay = if ($IsReportOnly) { 'REPORT-ONLY (no changes made)' } else { 'WRITE MODE (changes committed)' }
```

### Verbose Gating

Scripts that produce per-item detail logs (one line per record processed) must gate those lines behind a `[string]$VerboseOutput` parameter (default `'true'`).

**What is gated (suppressed when `VerboseOutput = 'false'`):**
- Per-item outcome lines (`[WROTE]`, `[SKIPPED-CURRENT]`, etc.)
- Per-item match/no-match lines

**What always emits regardless of VerboseOutput setting:**
- Section headers and banners
- Summary totals
- All WARN and ERROR lines
- Unmatched item lists

This lets you silence the per-item noise on daily scheduled runs once initial validation is complete without losing visibility into anomalies.

> **Naming note:** Use `VerboseOutput` (not `Verbose`) to avoid collision with PowerShell's built-in `-Verbose` common parameter, which is exposed automatically by `[CmdletBinding()]`.

### Full Accounting — Log Every Outcome

Scripts that process collections must log an explicit outcome for every item, not just the ones that changed. This produces a complete audit trail on every run and makes anomalies immediately visible without requiring a diff between runs.

**Standard four-outcome pattern:**

| Tag | Meaning |
|-----|---------|
| `[WROTE]` | Value was missing or different — write succeeded |
| `[SKIPPED-CURRENT]` | Value already correct — no write needed |
| `[SKIPPED-REPORT]` | Would have written, but report-only mode is on |
| `[SKIPPED-NO-MATCH]` | Item could not be matched to a source record |

All four outcomes are logged at INFO severity and gated behind `VerboseOutput`. WARN/ERROR outcomes (write failures, fetch failures) always emit.

### Idempotency — Read Before Write

Scripts that write to APIs on a recurring schedule must check the current value before writing. Never unconditionally overwrite a value that may already be correct.

**Pattern:** Before the write phase for a given target, fetch the current state in a single GET and build a name→value hashtable. Compare each resolved value against the existing value. Only issue a PUT/POST/PATCH if the value is actually different or missing.

Benefits: eliminates unnecessary API churn on stable configurations, keeps logs clean and meaningful (only `[WROTE]` entries indicate genuine changes), and reduces write rate limit consumption on daily runs once the initial population is complete.

---

## API Integration Patterns

For full pagination structure, rate limit values, and endpoint-specific details for DattoRMM, ITGlue, and Huntress, see `Databranch_APILessonsLearned.md`. The patterns below are the implementation standards that apply to all scripts.

### Pagination — Always Handle All Pages

Never assume the first API response is the complete dataset. Any script that pulls from a REST API must paginate through all pages. A single-page pull is a latent bug — it works until your dataset grows past the page size.

Wrap all paginated pulls in a reusable `Invoke-PaginatedGet` helper function rather than duplicating pagination loops per API call. The helper should accept a pagination style parameter and return a flat list of all items across all pages.

Common pagination styles used in this environment:

| API | Style | Next-page signal |
|-----|-------|-----------------|
| DattoRMM | URL-based | `$response.pageDetails.nextPageUrl` — null when done |
| ITGlue | Page number | `$response.meta.'next-page'` — null when done; reconstruct URL with `page[number]=N` |
| Huntress | Page number | `$response.pagination.total_pages` vs current page counter |

### Write Rate Limiting — Sliding Window

For APIs with write rate limits, never use a fixed `Start-Sleep` between writes. Fixed sleeps are naïve — they don't account for burst patterns where some iterations produce more writes than others, and they waste time sleeping when no throttling is actually needed.

Use a sliding window queue instead:

```powershell
# Setup — define limits and create timestamp queue
$WriteRateLimit  = 100   # API hard ceiling (writes per window)
$WriteRateSafe   = 80    # Threshold to start throttling (80% of ceiling)
$WriteWindowSecs = 60    # Rolling window duration in seconds
$WriteTimestamps = New-Object -TypeName 'System.Collections.Generic.Queue[datetime]'

# Before each write — check and throttle if needed
function Invoke-ThrottledWrite {
    # Evict timestamps older than the window
    $cutoff = (Get-Date).AddSeconds(-$WriteWindowSecs)
    while ($WriteTimestamps.Count -gt 0 -and $WriteTimestamps.Peek() -lt $cutoff) {
        $WriteTimestamps.Dequeue() | Out-Null
    }

    # If at or above safe threshold, sleep until oldest entry ages out
    if ($WriteTimestamps.Count -ge $WriteRateSafe) {
        $windowExpiry = $WriteTimestamps.Peek().AddSeconds($WriteWindowSecs)
        $waitMs       = [Math]::Max(0, ([int](($windowExpiry - (Get-Date)).TotalMilliseconds) + 100))
        Write-Log "Write throttle: $($WriteTimestamps.Count) writes in last ${WriteWindowSecs}s. Pausing ${waitMs}ms." -Severity INFO
        Start-Sleep -Milliseconds $waitMs
        # Re-evict after sleeping
        $cutoff = (Get-Date).AddSeconds(-$WriteWindowSecs)
        while ($WriteTimestamps.Count -gt 0 -and $WriteTimestamps.Peek() -lt $cutoff) {
            $WriteTimestamps.Dequeue() | Out-Null
        }
    }

    # Perform the write, then record the timestamp on success
    $ok = Invoke-YourWriteFunction ...
    if ($ok) { $WriteTimestamps.Enqueue((Get-Date)) }
    return $ok
}
```

The 80% threshold provides a comfortable buffer — the script will never get within 20 writes of the hard ceiling. The sleep duration is calculated exactly, so no time is wasted over-sleeping.

### API Response Field Verification

Before finalizing any script that consumes a third-party API, verify actual JSON field names against a live API response. Do not rely on documentation alone or infer field names from UI terminology — these frequently differ.

**Standard verification pattern:**
```powershell
# Inspect a single response object before writing the consumer code
$r = Invoke-RestMethod -Uri 'https://api.example.com/v1/resource?limit=1' -Headers $headers
$r.items[0] | ConvertTo-Json -Depth 3
```

The canonical lesson: Huntress documentation and UI refer to the "Organization Key" throughout, but the API response field is `key`, not `organization_key`. A one-line inspection call catches this before it becomes a production bug.

### Secret Handling in API Auth

When constructing Basic auth credentials (public key + secret concatenated and base64-encoded), null both the raw key and secret from memory immediately after the base64 string is built — before any API calls are issued:

```powershell
$huntressCredBytes = [System.Text.Encoding]::ASCII.GetBytes("${HuntressApiKey}:${HuntressApiSecret}")
$huntressB64       = [Convert]::ToBase64String($huntressCredBytes)

# Null immediately after encoding
$HuntressApiKey    = $null
$HuntressApiSecret = $null
$huntressCredBytes = $null

$headers = @{ Authorization = "Basic $huntressB64" }
```

The base64 string is transmitted in every request header and is not itself a secret in the same sense, but the raw key and secret should not persist in memory longer than necessary.

### Retry Logic — Defer Until Observed

Retry/backoff on transient API failures adds meaningful complexity. For daily scheduled sync operations that are inherently self-healing on the next run, defer retry logic until there is observed evidence of transient failures in production. Log failed writes as WARN and let the next scheduled run resolve them. Do not pre-emptively add complexity for a failure mode that may never occur at your scale.

---

## Versioning

- Format: `vMajor.Minor.Revision.Build` (e.g. `v1.4.0.004`)
- Increment on every iteration — no exceptions.
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
| DattoRMM Boolean env var | `if ($env:Flag)` or `if ([bool]$env:Flag)` | `($env:Flag.Trim().ToLower() -eq 'true')` |

> When in doubt about 5.1 compatibility, test explicitly. Do not assume PS 7+ syntax works in 5.1 just because it is cleaner.

---

## Security Standards

- Secrets (API keys, client secrets, passwords) must never be written to disk, log files, or stdout.
- DattoRMM environment variables are the correct delivery mechanism for secrets — they are passed via the process environment, not the command line, and are not visible in process listings.
- Once a secret has been used to acquire a token or session, **null it out immediately**: `$ClientSecret = $null`
- Secrets must never appear in `Write-Log` output, log headers, or parameter dumps.
- When base64-encoding credentials for Basic auth, null the raw credential variables immediately after encoding (see API Secret Handling above).

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

### Standard Log Header

Written at the start of every run:
```
===== <ScriptName> v<Version> =====
Site     : <CS_PROFILE_NAME or 'UnknownSite'>
Hostname : <CS_HOSTNAME or $env:COMPUTERNAME>
Run As   : <WindowsIdentity current user>
Mode     : <operational mode, e.g. REPORT-ONLY or WRITE MODE>
Log File : <full log file path>
```

For write-capable scripts, `Mode` must always be present in the log header so the operating mode is captured at the top of every run.

---

## Console Output Standards (Dual-Output Pattern)

Scripts use a **two-layer output model** that separates structured logging from human-friendly presentation. Both layers always run — they write to completely independent streams and do not interfere with each other.

| Layer | Function | Stream | Captured by DattoRMM |
|---|---|---|---|
| Structured log | `Write-Log` | `Write-Output` / `Write-Warning` / `Write-Error` | Yes |
| Presentation | `Write-Console` | `Write-Host` (display stream) | No |

`Write-Log` is what DattoRMM captures and what goes to the log file. `Write-Console` is for human-friendly colored output during interactive/manual runs — it is automatically suppressed in the DattoRMM agent context because `Write-Host` writes to the host display stream, not stdout.

**Never use `Format-Table`, `Format-List`, or `Format-Wide`** for any output that will be captured by DattoRMM. Column-formatted output garbles in the DattoRMM job log viewer. Write summary data as individual `Write-Log` lines instead.

### Write-VerboseLog Helper

For write-capable scripts with per-item outcome logging, add a `Write-VerboseLog` helper that calls both `Write-Log` and `Write-Console` only when `$IsVerbose` is true. Structural output always calls `Write-Log`/`Write-Console` directly so it always emits.

```powershell
function Write-VerboseLog {
    param (
        [string]$Message = "",
        [string]$Severity = "INFO",
        [int]$Indent = 0
    )
    if (-not $IsVerbose) { return }
    Write-Log     $Message -Severity $Severity
    Write-Console $Message -Severity $Severity -Indent $Indent
}
```

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

**To request documentation** during a script conversation, say:
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
- TLS 1.2 enforcement block (positioned correctly — before `[CmdletBinding()]`)
- DattoRMM/manual parameter fallback pattern
- Boolean parameter resolution with `.Trim().ToLower()`
- `Write-Log` internal function (all 5 severity levels, always verbose)
- `Write-Console` internal function (colored presentation layer)
- `Write-VerboseLog` helper (gated detail output for write-capable scripts)
- `Initialize-Logging` function (folder creation + log rotation)
- `$ErrorActionPreference = 'Stop'` with `try/catch`
- Standard log header written at startup (includes Mode for write-capable scripts)
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
