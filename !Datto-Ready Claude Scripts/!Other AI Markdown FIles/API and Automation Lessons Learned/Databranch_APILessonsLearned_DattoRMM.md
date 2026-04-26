# DattoRMM API -- Lessons Learned
**Databranch Internal | Sam Kirsch**
Last Updated: 2026-04-26

> **See also:** `Databranch_APILessonsLearned_ITGlue.md`,
> `Databranch_APILessonsLearned_Huntress.md`, and
> `Databranch_APILessonsLearned_CWManage.md` for related API notes.
> `Databranch_ScriptLibrary_ProjectSpec.md` for PowerShell API integration patterns.

---

## Base URL and Auth

- Base URL (Databranch instance): `https://vidal-api.centrastage.net`
- Auth: OAuth2 password grant -- POST to `/auth/oauth/token`
- Client credentials are always `public-client:public` (Base64-encoded in the Authorization header)
- The API key and secret are passed in the POST body as `username` and `password`
- Returns a bearer token -- include as `Authorization: Bearer <token>` on all subsequent requests

**Auth request pattern (PowerShell):**
```powershell
$basicB64 = [Convert]::ToBase64String(
    [System.Text.Encoding]::ASCII.GetBytes('public-client:public')
)
$token = (Invoke-RestMethod -Uri 'https://vidal-api.centrastage.net/auth/oauth/token' `
    -Method POST `
    -Headers @{ Authorization = "Basic $basicB64" } `
    -Body @{
        grant_type = 'password'
        username   = $ApiKey
        password   = $ApiSecret
    }).access_token

$headers = @{ Authorization = "Bearer $token" }
```

**Null API key and secret immediately after obtaining the token.** They are no
longer needed and should not persist in memory.

**Token expiry:** Tokens expire. For long-running scripts (many sites, large
datasets), check for 401 responses and re-authenticate if needed. In practice,
a single daily sync of ~100 sites completes well within the token lifetime.

---

## Swagger UI

Every DattoRMM instance exposes its full API documentation at:
```
https://<your-api-url>/api/swagger-ui/index.html
```

Use this to confirm endpoint paths, request body shapes, and response schemas
before writing code. Field names in the UI match the actual API exactly.

**Always verify the site variable endpoint path against your Swagger UI.**
The variable write endpoint may be `/v2/site/{uid}/variable` (singular) or
`/v2/site/{uid}/variables` (plural) depending on instance version. The GET
(read all variables) uses the plural form. Confirm both before use.

---

## Rate Limits

| Operation | Limit |
|---|---|
| GET (reads) | 600 requests per 60 seconds |
| PUT / POST / PATCH / DELETE (writes) | 100 requests per 60 seconds |

**Never use a fixed `Start-Sleep` between writes.** Fixed sleeps are naive --
they don't account for burst patterns where some iterations produce more writes
than others. Use a sliding window queue instead. See
`Databranch_ScriptLibrary_ProjectSpec.md` for the full `Invoke-ThrottledWrite`
pattern.

**80% threshold:** Begin throttling at 80 writes per 60 seconds (80% of the
hard ceiling). This gives comfortable headroom and the script never approaches
the limit regardless of match patterns.

---

## Endpoints Reference

| What | Endpoint | Notes |
|---|---|---|
| All sites | `GET /api/v2/account/sites` | Paginated -- follow `pageDetails.nextPageUrl` |
| Site variables (read all) | `GET /api/v2/site/{uid}/variables` | Returns `variables` array |
| Site variable (write) | `PUT /api/v2/site/{uid}/variable` | Upsert -- creates or updates by name |
| Account devices | `GET /api/v2/account/devices` | Paginated |
| Site devices | `GET /api/v2/site/{uid}/devices` | Paginated |
| Device detail | `GET /api/v2/device/{uid}` | Full device object |
| Account alerts | `GET /api/v2/account/alerts` | Paginated |
| Site alerts | `GET /api/v2/site/{uid}/alerts` | Paginated |

---

## Pagination

All collection endpoints paginate. Response includes a `pageDetails` object:

```json
{
  "pageDetails": {
    "count": 25,
    "prevPageUrl": null,
    "nextPageUrl": "https://vidal-api.centrastage.net/api/v2/account/sites?page=2"
  },
  "sites": [ ... ]
}
```

Follow `nextPageUrl` until it is null. Never assume a single response is the
complete dataset -- at any scale this will silently miss records.

**Pagination loop pattern (PowerShell):**
```powershell
$allItems  = New-Object -TypeName 'System.Collections.Generic.List[object]'
$currentUrl = "$baseUrl/api/v2/account/sites"

do {
    $response = Invoke-RestMethod -Uri $currentUrl -Headers $headers -Method GET
    foreach ($item in $response.sites) { $allItems.Add($item) }
    $currentUrl = $response.pageDetails.nextPageUrl
} while ($null -ne $currentUrl)
```

---

## Site Variables

**Site variables are upserted, not pre-seeded.** The `PUT /api/v2/site/{uid}/variable`
endpoint creates the variable if it doesn't exist and updates it if it does. No
placeholder variable needs to exist in the DattoRMM UI before writing.

**Request body:**
```json
{ "name": "MyVariableName", "value": "myvalue" }
```

**Response structure for GET `/api/v2/site/{uid}/variables`:**
```json
{
  "pageDetails": { "count": 5, "prevPageUrl": null, "nextPageUrl": null },
  "variables": [
    { "id": 570684, "name": "SSID",     "value": "DB-AP60 Secure", "masked": false },
    { "id": 571886, "name": "Password", "value": "*****",           "masked": true  }
  ]
}
```

Build a name->value hashtable from this for O(1) idempotency lookups:
```powershell
$existingVars = @{}
foreach ($v in $response.variables) {
    if (-not [string]::IsNullOrWhiteSpace($v.name)) {
        $existingVars[$v.name] = $v.value
    }
}
```

**Masked variables (Password type) always return `*****`** regardless of actual
value. Never attempt to read or compare Password-type variable values via the
API -- the comparison will always fail. Idempotency checks only work for
unmasked variable types.

**Site variable propagation delay.** Variables written via the API are not
immediately visible to agents running components on devices in that site. The
agent reads site variables from the platform on startup and on each check-in
cycle. If a script writes a variable and a component runs on that site
immediately afterward, the component may not see the new value. Restarting the
`CagService` on the target machine forces an immediate re-read.

---

## Idempotency -- Read Before Write

For scripts that write site variables on a recurring schedule, always fetch
existing variables first and skip the write if the value is already correct.
This eliminates unnecessary PUT calls on stable configurations and keeps logs
meaningful -- a `[WROTE]` entry indicates a genuine change.

**Fetch once per site, check both variables from the result.** Do not issue a
separate GET per variable -- one call returns all variables for the site.

**Type-safe comparison:** The GET response may return numeric IDs as strings
or with incidental whitespace. Coerce both sides before comparing:
```powershell
if (("$($existingVars['ITGOrgKey'])").Trim() -eq ("$itgOrgId").Trim()) {
    # already current -- skip write
}
```

---

## Site Naming Convention

DattoRMM site names at Databranch follow the pattern:
```
CompanyName - SiteName
```
Synced from ConnectWise Manage. The company name is the left portion (before
the first ` - `), the site/location name is the right portion.

**Parsing gotcha:** Company names can legitimately contain dashes
(e.g. `Dura-Bilt Products, Inc. - Main`). A naive split on `-` will truncate
the company name. Split on ` - ` (space-dash-space) and if a match fails, try
progressively longer prefixes from left to right until a lookup succeeds:

```powershell
$tokens = $SiteName -split ' - '
# Try longest prefix first against the lookup table, fall back to leftmost token
for ($i = ($tokens.Count - 1); $i -ge 1; $i--) {
    $candidate = ($tokens[0..($i - 1)]) -join ' - '
    $normalized = Get-NormalizedName -Name $candidate
    if ($lookupTable.ContainsKey($normalized)) { return $candidate }
}
return $tokens[0]  # fallback
```

**Name normalization for matching across systems.** Company names in DattoRMM,
ITGlue, and Huntress may differ in punctuation, casing, or whitespace. Normalize
before comparing:
```powershell
function Get-NormalizedName { param([string]$Name)
    return ($Name.ToLower() -replace '[^a-z0-9\s]', '' -replace '\s+', ' ').Trim()
}
```

**Internal meta-sites.** DattoRMM injects a `Deleted Devices` site into the
account. Skip it by name before processing:
```powershell
if ($site.name -eq 'Deleted Devices') { continue }
```

---

## DattoRMM Agent Environment Variables

Variables available in every component automatically. See
`Databranch_ScriptLibrary_ProjectSpec.md` for the full reference table.

**Site variable injection timing.** Site-level variables (`$env:MY_VAR_NAME`)
are injected into the agent process environment at startup, not dynamically.
A newly written site variable will not appear in `$env:` until the agent
restarts or the next check-in cycle. This is a known operational consideration
for workflows that write a variable and then immediately trigger a component
that reads it.

**DattoRMM boolean component variables arrive as strings.** Never cast to
`[bool]` or evaluate for truthiness. Always use `.Trim().ToLower() -eq 'true'`.
See `Databranch_ScriptLibrary_ProjectSpec.md` for the full two-layer gotcha.

---

## Confirmed Instance Details (Databranch)

| Field | Value |
|---|---|
| API URL | `https://vidal-api.centrastage.net` |
| Swagger UI | `https://vidal-api.centrastage.net/api/swagger-ui/index.html` |
| Site count | ~105 active sites (as of 2026-04-24) |
| Management host | DB-RDP1 |

---

*End of DattoRMM API Lessons Learned*
