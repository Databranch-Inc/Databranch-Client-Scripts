# Invoke-MailRemediation - Setup & Deployment Guide
**Version 1.0.0.001**

---

## Overview

This DattoRMM component pulls an Azure App Registration client secret from IT
Glue, authenticates to Microsoft Graph, enumerates every mailbox in a client
M365 tenant, and soft- or hard-deletes any messages matching your search
criteria (subject, sender, Message-ID, or any combination).

---

## Prerequisites

### 1. Azure App Registration (per client tenant)

Create one App Registration per client (or use a multi-tenant registration):

| Setting | Value |
|---|---|
| Type | Single-tenant (or multi-tenant for MSP use) |
| Auth | Client secret (no redirect URI needed) |

**Required API Permissions (Application, not Delegated):**

| Permission | Reason |
|---|---|
| `Mail.ReadWrite` | Search and delete messages |
| `User.Read.All` | Enumerate all mailboxes |

> Grant admin consent after adding both permissions.

Record:
- **Tenant ID** (Directory ID)
- **Client ID** (Application ID)
- **Client Secret** (value, not the secret ID)

---

### 2. IT Glue Password Asset (per client)

Create a Password asset in the client's IT Glue organization:

| Field | Value |
|---|---|
| Name | `M365 Graph App Registration` (or your chosen name) |
| Username | The **Client ID** (optional, for reference) |
| Password | The **Client Secret value** |
| Notes | Tenant ID, App Registration name, expiry date |

> The script uses the **Password** field for the client secret.
> You may store the Client ID as a separate asset or pass it as a DattoRMM variable.

---

### 3. IT Glue API Key

Generate a read-only API key in IT Glue:
- **Account > Settings > API Keys**
- Scope: Read (Passwords)
- Store securely as a DattoRMM Account Variable

---

## DattoRMM Component Setup

### Component Type
PowerShell Script

### Environment Variables

Configure these as DattoRMM Site or Account Variables, or as Component Input Variables:

| Variable Name | Description | Example |
|---|---|---|
| `ITGlueApiKey` | IT Glue API key | `abc123...` |
| `ITGlueBaseUrl` | IT Glue API base URL | `https://api.itglue.com` |
| `ITGlueOrgId` | IT Glue Organization ID for the client | `123456` |
| `ITGluePasswordAssetName` | Name of the IT Glue password asset | `M365 Graph App Registration` |
| `TenantId` | Azure AD Tenant (Directory) ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `ClientId` | Azure App Registration Client ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `SearchSubject` | Subject keyword to match | `Invoice Payment Required` |
| `SearchSender` | Sender address to match | `phisher@evil.com` |
| `SearchMessageId` | Internet Message-ID to match | `<abc123@mail.evil.com>` |
| `RemediationMode` | `SoftDelete`, `HardDelete`, or `ReportOnly` | `SoftDelete` |
| `MaxMailboxes` | Safety cap on mailbox count | `5000` |

> At least one of `SearchSubject`, `SearchSender`, or `SearchMessageId` must be set.
> You do not need all three - any combination works.

---

## Remediation Modes

| Mode | Behavior | Recoverable? |
|---|---|---|
| `ReportOnly` | Finds and logs matches, no deletion | N/A - no action taken |
| `SoftDelete` | Moves message to Deleted Items folder | Yes - recoverable for 30 days |
| `HardDelete` | Permanently deletes via Graph permanentDelete API | No |

**Recommended workflow:**
1. Run `ReportOnly` first to validate matches
2. Run `SoftDelete` for initial remediation
3. Escalate to `HardDelete` only if required

---

## Graph API Permissions Explained

```
Tenant Admin Center > Azure AD > App Registrations > [Your App]
  > API Permissions > Add Permission
    > Microsoft Graph > Application Permissions
      > Mail.ReadWrite      (check)
      > User.Read.All       (check)
  > Grant Admin Consent
```

> Without `Mail.ReadWrite` at Application level the script cannot access
> other users' mailboxes. Delegated permissions are insufficient for this
> use case.

---

## IT Glue API Region URLs

| Region | Base URL |
|---|---|
| US (default) | `https://api.itglue.com` |
| EU | `https://api.eu.itglue.com` |
| AU | `https://api.au.itglue.com` |

---

## Finding Your IT Glue Organization ID

```
IT Glue > [Client Org] > look at the URL:
https://[subdomain].itglue.com/[ORG_ID]/...
```

Or via the IT Glue API:
```
GET https://api.itglue.com/organizations?filter[name]=ClientName
```

---

## Credential-Based Auth (Legacy Fallback)

The current version uses Graph App Registration only (recommended). Legacy
credential-based auth (UPN + Password via ROPC flow) is not supported because
Microsoft has deprecated ROPC for tenants with MFA enabled, which is nearly
universal. Graph App Registration is the correct enterprise pattern.

---

## Security Notes

- The IT Glue API key and client secret are never written to disk
- Secrets exist only in memory during script execution
- DattoRMM variables are passed via environment, not command line (not visible in process list)
- Consider rotating the App Registration client secret on a schedule
- Use `ReportOnly` in production first - HardDelete is irreversible

---

## Troubleshooting

| Symptom | Likely Cause |
|---|---|
| `No IT Glue password asset found` | OrgId wrong, or asset name doesn't match |
| `Graph token acquisition failed` | ClientId, TenantId, or ClientSecret incorrect |
| `Failed to enumerate tenant users` | Missing `User.Read.All` application permission |
| `Failed to search mailbox` | Missing `Mail.ReadWrite` application permission or MFA on service account |
| `No matching messages found` | Search criteria too specific, or emails already deleted |
| Messages found but not deleted | Check `RemediationMode` is not `ReportOnly`; check `Mail.ReadWrite` consent |

---

## Version History

| Version | Date | Notes |
|---|---|---|
| 1.0.0.001 | 2026-04-16 | Initial release |
