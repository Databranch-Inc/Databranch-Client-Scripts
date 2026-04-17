# CIPP-MailRemediation - Deployment Guide (v10.3.0+)
**Script Version: 1.0.0.001 | CIPP Target: v10.3.0 "The Fishbowl"**

---

## What Changed in v10.3.0 (Why This Guide Matters)

v10.3.0 shipped **Custom Scripts as a first-class native feature** —
full scheduler support, enable/disable toggle, manual runs, and UI-based
authoring. This script is built specifically for that system and requires
**no file deployment, no repo commits, and no Azure Portal access**.

The previous approach (deploying into the Function App file system) is now
unnecessary for this use case.

---

## Deployment — 3 Steps

### Step 1: Add the Script in CIPP

```
CIPP UI > Tools > Custom Scripts > Add Script
```

- Paste the entire `.ps1` contents into the script editor
- Give it a name: `Mail Remediation` (or similar)
- Save

### Step 2: Enable It

Use the **Enable/Disable toggle** next to the script to activate it.
Disabled scripts will not appear in Scheduler command dropdowns.

### Step 3: Run It

**Option A — Manual / Immediate Run:**
- Click **Run Now** on the script row
- Select tenant (specific or All Tenants)
- Set parameters (see below)
- Execute

**Option B — Scheduled Run via CIPP Scheduler:**
```
CIPP UI > Tools > Scheduler > Add Task
  Tenant     : All Tenants  (or specific tenant domain)
  Command    : [Your script name]
  Parameters : (enable Advanced JSON Input toggle)
```

---

## Parameters

```json
{
  "SearchSubject":   "Urgent Invoice",
  "SearchSender":    "phisher@evil.com",
  "SearchMessageId": "",
  "RemediationMode": "ReportOnly",
  "MaxMailboxes":    5000
}
```

> `TenantFilter` is **injected automatically by CIPP** — do not set it
> manually in the parameters JSON. Select the tenant in the Run/Scheduler UI.

| Parameter | Description | Default |
|---|---|---|
| `SearchSubject` | Partial subject keyword (contains match) | *(empty)* |
| `SearchSender` | Exact sender email address | *(empty)* |
| `SearchMessageId` | Internet Message-ID header value | *(empty)* |
| `RemediationMode` | `ReportOnly`, `SoftDelete`, or `HardDelete` | `ReportOnly` |
| `MaxMailboxes` | Safety cap on mailboxes per tenant | `5000` |

At least one of `SearchSubject`, `SearchSender`, or `SearchMessageId` must be set.
You can combine any or all three — they are joined with OR logic.

---

## Remediation Modes

| Mode | Behavior | Recoverable? |
|---|---|---|
| `ReportOnly` | Logs matches only, zero mailbox changes | N/A |
| `SoftDelete` | Moves message to Deleted Items | Yes — ~30 days |
| `HardDelete` | Calls Graph `permanentDelete` | No — permanent |

### Recommended Incident Response Workflow

```
1. ReportOnly  →  review matches in CIPP script results
2. SoftDelete  →  recoverable removal, verify correct messages gone
3. HardDelete  →  only if compliance or legal requires permanent removal
```

---

## Viewing Results

Results appear in two places:

**Custom Scripts panel:**
- `Tools > Custom Scripts` > script row > results column

**Scheduler panel (if triggered via Scheduler):**
- `Tools > Scheduler` > task row > eye icon (Results)
- Or click **More Info** > **View Logs** for full per-mailbox output

All `Write-LogMessage` calls feed into CIPP's standard logbook and are
visible in the tenant logbook under `CIPP-MailRemediation`.

---

## SAM App Permission Check

CIPP's SAM app needs these Graph **Application** permissions with admin consent:

| Permission | Why Needed |
|---|---|
| `User.Read.All` | Enumerate all mailbox users in tenant |
| `Mail.ReadWrite` | Search and delete messages cross-mailbox |

To verify:
```
Azure Portal > Entra ID > App Registrations > All Applications
> Search: CIPP SAM (or your app name)
> API Permissions
  Mail.ReadWrite   Application   Granted ✓
  User.Read.All    Application   Granted ✓
```

If `Mail.ReadWrite` is missing: Add permission > Microsoft Graph >
Application permissions > `Mail.ReadWrite` > Grant admin consent.

---

## Multi-Tenant Behavior

When run against **All Tenants**, CIPP's Custom Scripts engine calls the
script once **per tenant**, injecting each tenant's `$TenantFilter`
automatically. The script does not need to loop through tenants itself —
CIPP handles the fanout.

When run against a **specific tenant**, it runs once for that tenant only.

---

## How Auth Works (No Credentials Needed)

`New-GraphGetRequest` and `New-GraphPostRequest` are CIPP's internal Graph
helper functions. They automatically:

1. Look up the SAM refresh token from CIPP's Key Vault / environment
2. Exchange it for a per-tenant Graph access token
3. Execute the Graph call with the correct token
4. Handle token expiry and retry

You write zero auth code. `$TenantFilter` is all they need.

---

## v10.3.0 Feature Notes

This script takes advantage of new v10.3.0 capabilities:

| Feature | How Used |
|---|---|
| Custom Scripts UI | Primary deployment mechanism |
| Scheduler support | Run on schedule via Task Scheduler |
| Enable/Disable toggle | Safe activation control |
| Manual runs | Immediate incident response |
| `Write-LogMessage` | Results visible in CIPP logbook and Scheduler results |
| Structured return object | Displays in Custom Scripts results panel |

---

## Version History

| Version | Date | Notes |
|---|---|---|
| 1.0.0.001 | 2026-04-16 | Initial release, CIPP v10.3.0 Custom Scripts native |
