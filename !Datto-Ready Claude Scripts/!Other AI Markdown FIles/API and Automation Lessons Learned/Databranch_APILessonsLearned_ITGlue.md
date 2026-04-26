# ITGlue API -- Lessons Learned
**Databranch Internal | Sam Kirsch**
Last Updated: 2026-04-26

> **See also:** `Databranch_APILessonsLearned_DattoRMM.md`,
> `Databranch_APILessonsLearned_Huntress.md`, and
> `Databranch_APILessonsLearned_CWManage.md` for related API notes.

---

## Base URL and Auth

- Base URL: `https://api.itglue.com`
- EU/regional instances use a different base URL -- override if applicable
- Auth: API key in the `x-api-key` request header
- Content-Type: `application/vnd.api+json` (required on all requests)

**Auth headers (PowerShell):**
```powershell
$headers = @{
    'x-api-key'    = $ITGlueApiKey
    'Content-Type' = 'application/vnd.api+json'
}
```

**Null the API key immediately after building the headers hashtable.** The key
is now embedded in the headers and the raw variable is no longer needed.

**Two key types exist:**
- Legacy per-org keys -- scoped to a single organization
- Account-level keys -- access to all organizations; required for cross-org
  operations like pulling the full org list

For scripts that iterate all sites, an account-level key is required.

---

## API Key Auto-Revocation (Critical Operational Risk)

**Effective May 15, 2023, ITGlue automatically revokes unused API keys after
90 days of inactivity.** Account admins receive a 10-day warning email before
revocation occurs.

This is a real operational risk for scripts that run on long cadences:
- A quarterly cleanup script (every 90+ days) will silently fail when its
  key is revoked between runs
- A "break glass" key kept in cold storage for emergency use will be gone
  when needed
- An audit/compliance pull that runs annually will require generating a new
  key every year

**Mitigation options:**
- Exercise the key on a regular schedule (a daily noop GET against
  `/organizations?page[size]=1` is enough to keep it alive)
- Use the same key across multiple scripts so daily-running scripts keep
  it warm for less-frequent ones
- Add a calendar reminder (60-day cadence) to validate key health before
  the warning fires
- Watch for the 10-day warning email and rotate proactively

If a key is revoked, the symptom is a 401 on calls that worked yesterday
with no other configuration change.

---

## Rate Limits

ITGlue's official rate limit is **3,000 requests per 5-minute window**,
returning HTTP 429 with a `Retry-After` header when exceeded. At Databranch's
scale (~356 organizations, ~105 active DattoRMM sites), this is not a
practical concern -- the org list pull completes well within limits.

For heavy read workloads (pulling all flexible assets, configurations, etc.
across all orgs), honor the `Retry-After` header value if a 429 is received.
For the standard org pull use case, rate limits will not be hit.

---

## Endpoints Reference

| What | Endpoint | Notes |
|---|---|---|
| All organizations | `GET /organizations` | Paginated -- page size max 100 |
| Single organization | `GET /organizations/{id}` | |
| Flexible assets | `GET /flexible_assets` | Filter by `filter[flexible_asset_type_id]` |
| Configurations | `GET /configurations` | Filter by `filter[organization_id]` |
| Contacts | `GET /contacts` | Filter by `filter[organization_id]` |
| Passwords | `GET /passwords` | Filter by `filter[organization_id]` |
| Documents | `GET /documents` | Filter by `filter[organization_id]` |

---

## Pagination

ITGlue uses page-number pagination. Response includes a `meta` object:

```json
{
  "meta": {
    "total-count": 356,
    "total-pages": 4,
    "current-page": 1,
    "next-page": 2,
    "prev-page": null
  },
  "data": [ ... ]
}
```

**The initial URL must include `page[number]=1` explicitly** for the
next-page URL reconstruction to work correctly. Build it as:
```
/organizations?page[size]=100&page[number]=1
```

Reconstruct the next URL by replacing the page number:
```powershell
if ($response.meta.'next-page') {
    $nextPage = $response.meta.'next-page'
    if ($currentUrl -match '[?&]page\[number\]=\d+') {
        $nextUrl = $currentUrl -replace 'page\[number\]=\d+', "page[number]=$nextPage"
    } else {
        $sep     = if ($currentUrl -match '\?') { '&' } else { '?' }
        $nextUrl = "$currentUrl${sep}page[number]=$nextPage"
    }
}
```

**Page size maximum is 100.** At 356 organizations, Databranch's org list
spans 4 pages. Always paginate -- a single-page pull silently misses records.

---

## Organization Response Structure

Organizations are returned under a `data` array. Each object follows JSON:API
structure -- attributes are nested under `.attributes`, the numeric ID is at
the top level:

```json
{
  "data": [
    {
      "id": "8441223",
      "type": "organizations",
      "attributes": {
        "name": "John Mills Electric",
        "short-name": "JME",
        "organization-type-name": "Customer",
        "psa-id": "...",
        "organization-status-name": "Active"
      }
    }
  ]
}
```

The `id` field is a **string**, not an integer, even though it looks numeric.
When writing it to DattoRMM site variables (as `ITGOrgKey`) it is used as-is.
For idempotency comparison, coerce both sides to trimmed strings:
```powershell
("$($existingVars['ITGOrgKey'])").Trim() -eq ("$($org.id)").Trim()
```

**The org `name` is under `.attributes.name`**, not at the top level. A common
mistake when building lookup tables is referencing `$org.name` instead of
`$org.attributes.name`.

---

## Building an Org Lookup Table

The standard pattern for matching DattoRMM site names to ITGlue orgs:

```powershell
$itglueLookup = @{}
foreach ($org in $itgOrgs) {
    $name = $org.attributes.name
    $id   = $org.id
    $norm = Get-NormalizedName -Name $name   # lowercase, strip punctuation
    $itglueLookup[$norm] = $id
}
```

Normalized lookup enables matching despite minor naming differences (extra
punctuation, casing differences) between DattoRMM and ITGlue org names.

**Duplicate normalized names.** If two orgs normalize to the same string
(e.g. `Acme Inc` and `ACME, Inc.`), the second one silently overwrites the
first in the hashtable. The `loaded N organizations, M unique normalized names`
log line will report `N > M` when this occurs. Investigate and resolve naming
conflicts at the source.

---

## PSA Integration Field

ITGlue organizations have a `psa-id` field under `.attributes` when a PSA
integration is configured. For ConnectWise Manage integrations, this field
contains the CW company ID. This can be used as a reliable cross-system join
key when available -- more reliable than name matching.

Check whether your ITGlue instance has PSA IDs populated before building
name-based matching logic. If they're populated, prefer `psa-id` as the
join key.

---

## Confirmed Instance Details (Databranch)

| Field | Value |
|---|---|
| Base URL | `https://api.itglue.com` |
| Org count | 356 organizations, 4 pages at page[size]=100 |
| API key storage | DattoRMM global variable `ITGlueAPIKey` |
| Key type | Account-level (read access to all orgs) |

---

*End of ITGlue API Lessons Learned*
