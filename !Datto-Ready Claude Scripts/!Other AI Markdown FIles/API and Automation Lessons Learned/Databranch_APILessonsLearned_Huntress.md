# Huntress API -- Lessons Learned
**Databranch Internal | Sam Kirsch**
Last Updated: 2026-04-26

> **See also:** `Databranch_APILessonsLearned_DattoRMM.md`,
> `Databranch_APILessonsLearned_ITGlue.md`, and
> `Databranch_APILessonsLearned_CWManage.md` for related API notes.

> **API status:** The Huntress REST API is currently in Public Beta. Endpoint
> shapes and field names may change between versions. Always verify the live
> response structure (see Swagger UI below) before writing consumer code.

---

## Base URL and Auth

- Base URL: `https://api.huntress.io/v1`
- Auth: HTTP Basic Auth -- Base64-encoded `apiKey:secretKey`
- The public key and secret key are separate credentials, not the same string

**Credential format:** Public keys are prefixed `hk_` and secret keys are
prefixed `hs_`. Both are visible only at creation time -- if the secret is
lost, delete the key and regenerate. The prefix makes it trivial to identify
Huntress credentials in code review or grep operations:

```
hk_XXXXXXXXXXXXXXXX     <- public key
hs_YYYYYYYYYYYYYYYY     <- secret key
```

**Auth headers (PowerShell):**
```powershell
$credBytes   = [System.Text.Encoding]::ASCII.GetBytes("${HuntressApiKey}:${HuntressApiSecret}")
$b64         = [Convert]::ToBase64String($credBytes)
$headers     = @{ Authorization = "Basic $b64"; 'Content-Type' = 'application/json' }

# Null raw credentials immediately after encoding
$HuntressApiKey    = $null
$HuntressApiSecret = $null
$credBytes         = $null
```

---

## Swagger UI / OpenAPI

Huntress publishes interactive API documentation:

| Resource | URL |
|---|---|
| API documentation landing | `https://api.huntress.io/docs` |
| Swagger UI (interactive) | `https://api.huntress.io/docs/preview` |
| OpenAPI JSON spec | `https://api.huntress.io/swagger_doc.json` |

**Live testing:** Paste `hk_XXXX:hs_YYYY` (key and secret colon-separated) into
the auth box at the top right of the Swagger UI to test against your own
account data.

**Importable spec:** The OpenAPI JSON can be imported into Insomnia or Postman
to scaffold an API client without hand-typing every endpoint.

---

## API Credential Types

Two distinct credential types exist and are NOT interchangeable:

| Type | Used for | Where to find |
|---|---|---|
| Account Key (`HUNTRESS_ACCOUNT_KEY`) | Agent installation | Huntress portal -> Download Agent page |
| API public key + secret | REST API calls | Huntress portal -> hamburger menu -> API Credentials |

**The `HUNTRESS_ACCOUNT_KEY` DattoRMM global variable is the agent installation
key, not the API key.** Do not attempt to use it for REST API authentication.

**Two API key types exist within the REST API:**
- Account-level key -- read-only, one per account
- User-level keys -- mirror the permissions of the associated user; required for
  write operations; multiple can be created per account

For the org list pull (read-only), either key type works. For future write
operations, a user-level key is required.

**Generating API credentials:** Huntress portal -> hamburger menu (upper right)
-> API Credentials -> Add. The secret is shown once at creation -- store it
immediately. If lost, delete and regenerate.

---

## Rate Limits

No hard rate limit values have been hit or documented at Databranch's scale
(67 organizations). Standard REST rate limits apply. For large accounts,
be mindful of rapid successive calls.

---

## Endpoints Reference

| What | Endpoint | Notes |
|---|---|---|
| All organizations | `GET /v1/organizations` | Paginated -- `limit` max 500 |
| Single organization | `GET /v1/organizations/{id}` | |
| All agents | `GET /v1/agents` | Paginated |
| Agents by org | `GET /v1/agents?organization_id={id}` | |
| Incidents | `GET /v1/reports/incidents` | |
| Account summary | `GET /v1/summary` | |

---

## Pagination

Huntress uses page-number pagination. Response includes a `pagination` object:

```json
{
  "organizations": [ ... ],
  "pagination": {
    "current_page": 1,
    "next_page": null,
    "total_pages": 1,
    "total_count": 67
  }
}
```

At Databranch's current scale (67 orgs, limit=500), all organizations fit on a
single page. **Always paginate anyway** -- org count will grow and the code must
not be the constraint.

**Pagination loop pattern (PowerShell):**
```powershell
$allOrgs = New-Object -TypeName 'System.Collections.Generic.List[object]'
$page    = 1

do {
    $response = Invoke-RestMethod -Uri "https://api.huntress.io/v1/organizations?limit=500&page=$page" `
                    -Headers $headers
    foreach ($org in $response.organizations) { $allOrgs.Add($org) }
    $page++
} while ($page -le $response.pagination.total_pages)
```

---

## Organization Object Structure

**CRITICAL: The organization key field is `key`, NOT `organization_key`.**

The Huntress UI and support documentation refer to this value as the
"Organization Key" throughout. The REST API returns it as `key`. This is
the single most likely mistake when consuming this endpoint.

Full org object structure (confirmed against live API):
```json
{
  "id":                          625039,
  "name":                        "John Mills Electric",
  "key":                         "john-mills-electric",
  "account_id":                  440,
  "agents_count":                12,
  "created_at":                  "2023-01-15T14:22:00Z",
  "updated_at":                  "2026-04-23T19:34:23Z",
  "microsoft_365_tenant_id":     "...",
  "microsoft_365_users_count":   0,
  "notify_emails":               [],
  "report_recipients":           [],
  "sat_learner_count":           0,
  "incident_reports_count":      0,
  "logs_sources_count":          0,
  "billable_identity_count":     0,
  "identity_provider_tenant_id": null
}
```

**The `id` field is a numeric integer**, not a string. The `key` field is the
dashed string used for agent registration (e.g. `john-mills-electric`).

**Always inspect a live response before writing consumer code:**
```powershell
$creds = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("KEY:SECRET"))
$r = Invoke-RestMethod -Uri 'https://api.huntress.io/v1/organizations?limit=1' `
         -Headers @{ Authorization = "Basic $creds" }
$r.organizations[0] | ConvertTo-Json
```

---

## Organization Key Format

The `key` field is a lowercase dashed string derived from the organization
display name. Huntress generates it automatically when an org is created.

**Key generation rules (observed):**
- Lowercased
- Spaces replaced with hyphens
- Most punctuation stripped or replaced with hyphens
- Ampersands stripped (not replaced with `-and-`)
- Apostrophes stripped (e.g. `Ried's` -> `rieds`)
- Parenthetical suffixes included (e.g. `olean-food-barn-ried-s`)

**Keys for orgs created with garbage names** (e.g. from the DattoRMM site-name
format `Company-Main`) will have the garbage embedded in the key permanently.
The key cannot be changed without disrupting agent registration for all
devices in that org. Clean up org names in Huntress before running the
installer in write mode for the first time.

**Duplicate org detection.** If the same company has multiple Huntress orgs
(e.g. from being created twice, once with a clean name and once with a garbage
name from an old installer run), the lookup hashtable will contain both. The
last one wins during iteration. The normalized name load count will report
`N organizations, M unique normalized names` where `N > M` -- investigate
these. Choose the correct org (the one with active agents) and delete or
merge the garbage org in the Huntress portal.

**Example at Databranch:** Associated Radiologists has two orgs --
`associated-radiologists-of-the-finger-lakes-p-c` (clean) and
`associated-radiologists-of-the-finger-lakes-p-c-9d006912` (hash-suffixed
duplicate from an earlier install). The hash-suffixed one is the active one
with agents. Confirm which has agents before deleting.

---

## Org Matching Against DattoRMM Sites

Huntress org **names** are what get normalized for matching -- not the keys.
Match on normalized `$org.name`, store `$org.key` as the value to write to
DattoRMM. The key is what the installer needs; the name is what you have to
match against.

```powershell
$huntressLookup = @{}
foreach ($org in $huntressOrgs) {
    $norm = Get-NormalizedName -Name $org.name   # normalize the display name
    $huntressLookup[$norm] = $org.key            # store the key string
}
```

**Known mismatches at Databranch (as of 2026-04-24):**

| DattoRMM site (parsed company) | Huntress org name | Reason |
|---|---|---|
| `Cameron - Elk Behavioral and Development Program` | `Cameron Elk` | Huntress org was named differently |
| `Casella Recycling LLC (Formerly Central Recycling)` | `Central Recycling` | Huntress org predates the rename |
| `Beef and Barrel` | -- | Not in Huntress |
| `Bartlett Country Club` | -- | Not in Huntress |
| `KR Utilities` | -- | Not in Huntress |

Orgs not in Huntress are expected -- not every client needs endpoint protection.
`[SKIPPED-NO-MATCH]` for these is correct and non-fatal.

---

## Agent Installer -- org key Parameter

The Huntress agent installer accepts `/ORG_KEY="value"`. The value must be
the `key` string (dashed format), not the display name.

**The installer creates a new org in Huntress if the key does not match any
existing org.** This is the root cause of garbage org proliferation -- when the
DattoRMM site name (`Company - Location`) was passed as the org key directly,
Huntress created a new org for every unique site name string.

The fix: write `HUNTRESS_ORG_KEY` as a DattoRMM site variable (containing the
correct dashed key for that client), then pass `$env:HUNTRESS_ORG_KEY` to the
installer. All sites for the same client will resolve to the same key and the
same Huntress org.

---

## Confirmed Instance Details (Databranch)

| Field | Value |
|---|---|
| Base URL | `https://api.huntress.io/v1` |
| Account ID | `440` |
| Org count | 67 organizations (as of 2026-04-24) |
| Unique normalized org names | 65 (2 duplicate-name orgs present) |
| API key storage | DattoRMM global variables `HuntressApiKey` / `HuntressApiSecret` |
| Agent install key storage | DattoRMM global variable `HUNTRESS_ACCOUNT_KEY` |

---

*End of Huntress API Lessons Learned*
