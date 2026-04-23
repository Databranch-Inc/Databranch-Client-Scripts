# Sync-OrgKeysToSiteVariables

**Version:** 1.4.0.004
**Script file:** `Sync-OrgKeysToSiteVariables.ps1`
**Requires:** PowerShell 5.1 · Windows · outbound HTTPS to three APIs
**Deployment:** DattoRMM scheduled Script component targeted at a single management host (manual invocation also supported)

---

## What This Script Does

### The Problem It Solves

DattoRMM sites are named using a `CompanyName - SiteName` convention synced from ConnectWise Manage. When the Huntress installer runs and uses the full DattoRMM site name as the org key, Huntress creates duplicate or garbage organizations (e.g. `John-Mills-Electric-Main` and `John-Mills-Electric-Ithaca` instead of one `John-Mills-Electric` org). Similarly, scripts that need to look up a client in ITGlue have no reliable way to do so without the ITGlue org ID being present on the site.

This script fixes that by stamping two site variables onto every DattoRMM site:

| Variable | Source | Value |
|---|---|---|
| `ITGOrgKey` | ITGlue API | Numeric ITGlue organization ID (e.g. `12345678`) |
| `HUNTRESS_ORG_KEY` | Huntress API | Dashed organization key string (e.g. `John-Mills-Electric`) |

Once these variables are present on a site, any DattoRMM component or monitor can reference them directly — most importantly, the Huntress installer component can pass `HUNTRESS_ORG_KEY` as the `-orgkey` argument to stop creating duplicate Huntress organizations.

---

### How It Works — Step by Step

1. **Authenticate to DattoRMM** using OAuth2. The token request sends HTTP Basic auth with fixed `public-client:public` credentials plus a `password` grant body carrying the API key and secret.
2. **Pull all ITGlue organizations** via the ITGlue REST API, paginating through all results. Builds an in-memory lookup table keyed by normalized organization name (lowercased, punctuation stripped).
3. **Pull all Huntress organizations** via the Huntress REST API, paginating by page number (Huntress returns `current_page` / `total_pages`, no URL). Builds a second in-memory lookup table the same way, storing the `organization_key` string.
4. **Pull all DattoRMM sites** via the DattoRMM REST API.
5. **For each site**, parse the company name out of the `CompanyName - SiteName` format. Splits on literal ` - ` (space-dash-space) using `StringSplitOptions::None`. To handle company names that legitimately contain dashes (e.g. `Smith-Jones Electric - Main`), it tries progressively longer prefixes from left to right, checking each candidate against the combined ITGlue/Huntress lookup tables before falling back to the leftmost token.
6. **For each site in write mode**, fetches all existing site variables in a single GET before touching anything. Compares each resolved value against what's already there. Four outcomes per variable, all logged (gated by `Verbose`):
   - `[WROTE]` — value was missing or different, write succeeded
   - `[SKIPPED-CURRENT]` — value already correct, no write issued
   - `[SKIPPED-REPORT]` — would write, but report-only mode is on
   - `[SKIPPED-NO-MATCH]` — site had no match in the source system

   This produces a full per-org accounting on every run and eliminates unnecessary API writes once variables stabilize. The write throttle tracks timestamps in a sliding 60-second queue; when 80 writes (80% of the 100/min ceiling) have occurred in the last 60 seconds, it sleeps until the oldest timestamp ages out before proceeding.
7. **Unmatched sites** are logged as warnings at the end of the run but do not cause the script to fail. The summary output lists them with their parsed company name so you can diagnose naming drift.

---

### What It Does NOT Do

- It does not create or delete organizations in Huntress or ITGlue.
- It does not modify existing Huntress agent registrations.
- It does not touch any device-level variables, only site-level variables.
- It does not write anything at all unless `ReportOnly` is explicitly set to `false` (via parameter or component variable).
- API secrets are never written to logs, stdout, or disk — they are nulled from memory immediately after use.

---

## Deployment: DattoRMM Scheduled Component

This script is designed to run as a DattoRMM **Script** component, scheduled on a single designated management host. Running it under DattoRMM rather than as a Windows Scheduled Task with a credential-bearing wrapper script gives you:

- All secrets delivered as DattoRMM component variables — no `.ps1` wrapper containing keys on disk.
- Central visibility of every run in the DattoRMM job history.
- Platform-native schedule management and post-condition alerting.
- One place to rotate credentials.

### Prerequisites

#### 1. DattoRMM API Access

The script authenticates to the DattoRMM API with an OAuth2 key and secret tied to a specific user account.

**To generate API credentials:**

1. In DattoRMM, go to **Setup → Global Settings → Access Control** and confirm API access is enabled.
2. Go to **Setup → Users**, open the user you want to run the script as (a dedicated service account is recommended).
3. Click **Generate API Keys**.
4. Note the **API URL**, **API Key**, and **API Secret Key** — the secret is only shown once.

The account needs at minimum **Administrator** privileges to read all sites and write site variables.

You will need:
- `DattoApiUrl` — the API URL from the user page (e.g. `https://merlot-api.centrastage.net`)
- `DattoApiKey` — the API key
- `DattoApiSecret` — the API secret

> **Confirm the variable endpoint path in your Swagger UI** before the first live write run. Navigate to `[DattoApiUrl]/api/swagger-ui/index.html`, find the `/v2/site` tag, and confirm the PUT variables endpoint is `/v2/site/{uid}/variable` (singular) or `/v2/site/{uid}/variables` (plural). The script uses singular — adjust the `Write-DattoSiteVariable` function if yours differs.

#### 2. ITGlue API Key

You need an account-level API key with read access to organizations.

1. In ITGlue, go to **Account → API Keys**.
2. Create a new key or use an existing one — read-only access to Organizations is sufficient.
3. Note the key value.

For non-US ITGlue instances (EU, etc.), set the `ITGlueUrl` component variable to your regional endpoint (e.g. `https://api.eu.itglue.com`).

#### 3. Huntress API Credentials

1. In the Huntress portal, click your account name in the upper left.
2. Go to **API Credentials**.
3. Generate a new credential pair — you will get a **public key** and a **secret key**.
4. Store both securely — the secret is only shown at creation time.

> The `HUNTRESS_ACCOUNT_KEY` global variable already in DattoRMM is the agent installation account key, which is different from the API credentials used here.

---

### Setting Up the DattoRMM Component

**1. Create the component.**

Navigate to **Automation → Components** and create a new **Script** component:

| Field | Value |
|---|---|
| Category | Scripts |
| Component Type | Applications *or* Scripts (Scripts is fine) |
| Script Type | PowerShell |
| Script | Paste `Sync-OrgKeysToSiteVariables.ps1` |

**2. Define component variables.**

Under the component's **Variables** tab, add the following. Set secrets to **Password** type so they are masked in the UI and the job log.

| Variable Name | Type | Required | Notes |
|---|---|---|---|
| `DattoApiUrl` | String (Value) | Yes | e.g. `https://merlot-api.centrastage.net` |
| `DattoApiKey` | String (Value) | Yes | DattoRMM OAuth2 API key |
| `DattoApiSecret` | Password | Yes | DattoRMM OAuth2 API secret |
| `ITGlueApiKey` | Password | Conditional | Required unless `SkipITGlue=true` |
| `ITGlueUrl` | String (Value) | No | Override base URL for EU/regional endpoints |
| `HuntressApiKey` | Password | Conditional | Required unless `SkipHuntress=true` |
| `HuntressApiSecret` | Password | Conditional | Required unless `SkipHuntress=true` |
| `ReportOnly` | Selection | Yes | `true` (default) / `false` — must be `false` to commit writes |
| `SkipITGlue` | Selection | No | `true` / `false` — default `false` |
| `SkipHuntress` | Selection | No | `true` / `false` — default `false` |
| `Verbose` | Selection | No | `true` (default) / `false` — set `false` for quiet scheduled runs |

> DattoRMM Boolean-type variables arrive as string `"true"` / `"false"`. The script expects this and compares with `-eq 'true'`. You can use either a **Selection** variable with true/false options or a plain **String (Value)** variable — both produce a string in the environment.

**3. Post-Condition (optional but recommended).**

Under the component's **Post-Condition** field, enter the case-sensitive string:

```
WARNING:
```

The script emits `WARNING: Run completed with unmatched sites or write errors — review log for details.` whenever there are unmatched sites or failed writes. DattoRMM will then flag those runs as orange **Warning** status in the job log — visible at a glance without opening the output.

**4. Target and schedule the component.**

Do **not** schedule this at the account or site level. Target **one specific management host** (a utility server or admin workstation, domain-joined, always on). Two reasons:

- The script iterates every site in your tenant — you only want it running once per schedule interval.
- Running it as SYSTEM on a management box keeps all three sets of API secrets off end-user endpoints.

Recommended schedule: **daily, off-hours** (e.g. 2:00 AM). Use a **Scheduled Job** policy applied to the single target device, or push a **Quick Job** manually until you're comfortable with the output, then convert to scheduled.

---

### Manual / Interactive Runs

The parameter-based invocation pattern still works unchanged. Useful for:
- Initial rollout testing (before committing to a scheduled component).
- Ad-hoc reruns after correcting naming drift in ITGlue or Huntress.
- Troubleshooting on your own workstation.

---

## Parameters Reference

| Parameter | DattoRMM Env Var | Default | Description |
|---|---|---|---|
| `-DattoApiUrl` | `DattoApiUrl` | _(none — required)_ | DattoRMM instance API URL |
| `-DattoApiKey` | `DattoApiKey` | _(none — required)_ | DattoRMM OAuth2 API key |
| `-DattoApiSecret` | `DattoApiSecret` | _(none — required)_ | DattoRMM OAuth2 API secret |
| `-ITGlueUrl` | `ITGlueUrl` | `https://api.itglue.com` | Override for EU/regional ITGlue endpoints |
| `-ITGlueApiKey` | `ITGlueApiKey` | _(empty)_ | ITGlue API key. Required unless `SkipITGlue=true` |
| `-HuntressApiKey` | `HuntressApiKey` | _(empty)_ | Huntress API public key. Required unless `SkipHuntress=true` |
| `-HuntressApiSecret` | `HuntressApiSecret` | _(empty)_ | Huntress API secret key. Required unless `SkipHuntress=true` |
| `-ReportOnly` | `ReportOnly` | `'true'` | Safety gate. Must be `'false'` to commit writes |
| `-SkipITGlue` | `SkipITGlue` | `'false'` | Skip ITGlue entirely, only sync Huntress |
| `-SkipHuntress` | `SkipHuntress` | `'false'` | Skip Huntress entirely, only sync ITGlue |

All parameters accept either direct PowerShell invocation or DattoRMM component variables — the script checks the env var first and falls back to the passed parameter, then to the default.

Boolean-style parameters (`ReportOnly`, `SkipITGlue`, `SkipHuntress`) are **strings** by design, per DattoRMM convention. The literal string `'true'` is the only truthy value; anything else is treated as false.

---

## Usage Examples (Manual Invocation)

### Report-only run (default — safe to run anytime)

```powershell
.\Sync-OrgKeysToSiteVariables.ps1 `
    -DattoApiUrl    'https://merlot-api.centrastage.net' `
    -DattoApiKey    'your-datto-key' `
    -DattoApiSecret 'your-datto-secret' `
    -ITGlueApiKey   'your-itg-key' `
    -HuntressApiKey    'your-huntress-public-key' `
    -HuntressApiSecret 'your-huntress-secret'
```

This matches and logs but writes nothing. Review the output — especially any `[ITG-UNMATCHED]` or `[HUNTRESS-UNMATCHED]` lines — before proceeding.

### Commit writes

```powershell
.\Sync-OrgKeysToSiteVariables.ps1 `
    -DattoApiUrl    'https://merlot-api.centrastage.net' `
    -DattoApiKey    'your-datto-key' `
    -DattoApiSecret 'your-datto-secret' `
    -ITGlueApiKey   'your-itg-key' `
    -HuntressApiKey    'your-huntress-public-key' `
    -HuntressApiSecret 'your-huntress-secret' `
    -ReportOnly 'false'
```

### ITGlue only (skip Huntress)

```powershell
.\Sync-OrgKeysToSiteVariables.ps1 `
    -DattoApiUrl    'https://merlot-api.centrastage.net' `
    -DattoApiKey    'your-datto-key' `
    -DattoApiSecret 'your-datto-secret' `
    -ITGlueApiKey   'your-itg-key' `
    -SkipHuntress 'true' `
    -ReportOnly   'false'
```

---

## Recommended Rollout Sequence

**Step 1 — Manual report-only run and review output.**

Run the script once manually on your admin workstation with `ReportOnly` at its default (`'true'`). Examine the summary at the bottom. For every `[ITG-UNMATCHED]` or `[HUNTRESS-UNMATCHED]` line, the script shows you what company name it parsed — this tells you whether there is naming drift between DattoRMM, ITGlue, or Huntress that needs to be corrected at the source.

**Step 2 — Resolve unmatched sites.**

For each unmatched site, the fix is almost always one of:
- A company name in Huntress or ITGlue doesn't match ConnectWise exactly — correct it at the source.
- A DattoRMM site name was manually renamed away from the CW convention — correct it in DattoRMM.

**Step 3 — Re-run report-only until unmatched count is acceptable.**

Unmatched sites are non-fatal. A handful of legacy or special-purpose sites may never match — that is fine. Once satisfied with the match rate, proceed.

**Step 4 — Run manually with `-ReportOnly 'false'`.**

This commits the first pass of writes. The log will show `WRITE MODE (changes committed)` in the summary line. Spot-check a few sites in DattoRMM to confirm the variables appear under **Site Settings → Variables**.

**Step 5 — Build and target the DattoRMM component.**

Create the Script component as described in the **Setting Up the DattoRMM Component** section above, targeting your designated management host. Set `ReportOnly` to `'false'` on the component once you're committing writes.

**Step 6 — Schedule.**

Apply a daily Scheduled Job policy to the management host targeting the component. Daily off-hours (e.g. 2:00 AM) is the recommended cadence.

---

## Reading the Log Output

Two output streams are produced on every run:

- **Structured log** — file at `C:\Databranch\ScriptLogs\Sync-OrgKeysToSiteVariables\Sync-OrgKeysToSiteVariables_yyyy-MM-dd.log` AND DattoRMM stdout. Rotates to keep the last 10 files.
- **Colored console output** — only visible in manual interactive runs. Suppressed automatically under DattoRMM.

Structured log format:

```
[2026-04-23 02:00:01] [INFO] ===== Sync-OrgKeysToSiteVariables v1.4.0.004 =====
[2026-04-23 02:00:01] [INFO] Site     : ManagementHost
[2026-04-23 02:00:01] [INFO] Hostname : MGMT-SRV-01
[2026-04-23 02:00:01] [INFO] Run As   : NT AUTHORITY\SYSTEM
[2026-04-23 02:00:01] [INFO] Mode     : WRITE MODE
[2026-04-23 02:00:01] [INFO] Verbose  : True
[2026-04-23 02:00:02] [SUCCESS] DattoRMM authentication successful.
[2026-04-23 02:00:03] [SUCCESS] ITGlue: loaded 104 organizations, 104 unique normalized names.
[2026-04-23 02:00:04] [SUCCESS] Huntress: loaded 98 organizations, 98 unique normalized names.
[2026-04-23 02:00:05] [SUCCESS] DattoRMM: loaded 112 sites.
[2026-04-23 02:00:05] [INFO]   [WROTE]            ITGOrgKey = 12345678  |  'John Mills Electric - Main'
[2026-04-23 02:00:05] [INFO]   [WROTE]            HUNTRESS_ORG_KEY = John-Mills-Electric  |  'John Mills Electric - Main'
[2026-04-23 02:00:06] [INFO]   [SKIPPED-CURRENT]  ITGOrgKey = 87654321  |  'Acme Corp - Buffalo'
[2026-04-23 02:00:06] [INFO]   [SKIPPED-CURRENT]  HUNTRESS_ORG_KEY = Acme-Corp  |  'Acme Corp - Buffalo'
[2026-04-23 02:00:06] [INFO]   [SKIPPED-NO-MATCH] ITGOrgKey              |  'Legacy Site - Old' (parsed: 'Legacy Site')
...
[2026-04-23 02:01:10] [WARN]  [ITG-UNMATCHED] 'Legacy Site - Old' (parsed company: 'Legacy Site')
[2026-04-23 02:01:10] [INFO]  SUMMARY: 112 sites processed. Mode: WRITE MODE (changes committed)
[2026-04-23 02:01:10] [INFO]    ITGlue:   109 matched, 109 written/would-write.
[2026-04-23 02:01:10] [INFO]    Huntress: 106 matched, 106 written/would-write.
[2026-04-23 02:01:10] [INFO]    Skipped (already current): 198 variable(s).
[2026-04-23 02:01:10] [SUCCESS] Script completed successfully.
```

Key things to look for:

- `[WROTE]` — variable was created or updated this run
- `[SKIPPED-CURRENT]` — variable already had the correct value, no write needed
- `[SKIPPED-REPORT]` — report-only mode, would have written this value
- `[SKIPPED-NO-MATCH]` — site could not be matched to a company in the source system
- `[ERROR]` lines indicate a fatal or near-fatal condition (auth failure, API unreachable)
- `[WARN]` lines with `UNMATCHED` list sites that need attention at the source
- `[WARN]` lines with `Failed to write` indicate a specific write failed — script continued
- The `SUMMARY` line confirms mode, totals, and skipped-current count
- A trailing `WARNING:` line appears when there are unmatched sites or write errors — this is what the post-condition matches on to flag the job orange
- All per-site detail lines are suppressed when `Verbose = false` — only the summary and warnings emit

---

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Success (partial matches and individual write failures are non-fatal) |
| `1` | Runtime failure — script started but an unhandled exception occurred, or both data sources failed mid-run |
| `2` | Fatal pre-flight failure — missing required parameters or DattoRMM auth failure before any sites were processed |

---

## API Rate Limits

| API | Limit | Script Behavior |
|---|---|---|
| DattoRMM reads | 600 requests / 60 seconds | GETs are spaced by network latency; well under limit |
| DattoRMM writes | 100 requests / 60 seconds | 600ms spacing between writes = ~100/min with headroom |
| ITGlue | 429 throttle with Retry-After header | Will surface as an error on the read pull if hit |
| Huntress | Standard REST rate limits | Reads only; limits not typically approached |

For environments with hundreds of sites and both data sources matching, the write phase is the pacing constraint. A 200-site run with ITGlue + Huntress both matching = ~400 writes = ~4 minutes of writes. That is the designed operating range.

---

## Version History

### v1.4.0.004 — 2026-04-23
- **Boolean hardening:** all string-bool parameters (`ReportOnly`, `SkipITGlue`, `SkipHuntress`, `Verbose`) now resolved with `.Trim().ToLower() -eq 'true'`. Prevents accidental write-mode entry if DattoRMM passes `'True'`, `'TRUE'`, or `' true '`.
- **`-Verbose` parameter** (string `'true'`/`'false'`, default `'true'`): gates per-site detail lines in both `Write-Log` and `Write-Console`. Section headers, summary, unmatched lists, and all WARN/ERROR entries always emit regardless of setting. Add as a Selection component variable to silence daily scheduled runs once initial configuration is validated.
- **Idempotency check:** before writing each variable, fetches all existing site variables in a single GET (`/v2/site/{uid}/variables`). Compares the resolved value against the current value and skips the write if already correct. Four outcomes per variable per site: `[WROTE]`, `[SKIPPED-CURRENT]`, `[SKIPPED-REPORT]`, `[SKIPPED-NO-MATCH]` — all logged via the verbose gate for full per-org accounting on every run.
- **Summary expanded:** tracks and reports `Skipped (already current)` count separately from written count.

### v1.2.0.0 — 2026-04-23
- Full refactor to Databranch script standards: master-function wrap, Write-Log / Write-Console dual-output, file logging with rotation, standard log header, pre-flight validation, standard exit codes (0/1/2).
- Converted to DattoRMM Script component deployment. All parameters (including secrets) now delivered as component variables with env-var fallback.
- Fixed DattoRMM OAuth2 token request: now includes the required `public-client:public` HTTP Basic auth header. The prior version's token request would fail on the current API gateway.
- Fixed Huntress pagination: prior version looked for a non-existent `pagination.next_page` URL field. Now uses `pagination.current_page` / `pagination.total_pages` and reconstructs the page-number URL.
- Secrets now null out immediately after use across all three APIs.
- Hardened site-name split: literal `StringSplitOptions::None` split instead of regex split.
- `Deleted Devices` site filter is now an exact-match equality check rather than a regex prefix match.
- 600ms pause between writes to stay under DattoRMM's write rate ceiling.
- Post-condition `WARNING:` line emitted when there are unmatched sites or write errors.

### v1.1.0.002 — 2026-04-23
- Replaced `-WhatIf` / `SupportsShouldProcess` with explicit `-ReportOnly` parameter defaulting to `$true`. Safe-by-default — must pass `-ReportOnly $false` (now `'false'`) to commit.

### v1.0.0.001 — 2026-04-23
- Initial release.
