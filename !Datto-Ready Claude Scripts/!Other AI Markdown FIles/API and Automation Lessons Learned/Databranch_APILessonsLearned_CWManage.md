# ConnectWise Manage API -- Lessons Learned
**Databranch Internal | Sam Kirsch**
Last Updated: 2026-04-26

> **See also:** `Databranch_APILessonsLearned_DattoRMM.md`,
> `Databranch_APILessonsLearned_ITGlue.md`, and
> `Databranch_APILessonsLearned_Huntress.md` for related API notes.
> `n8n-lessons-learned-slim.md` for n8n-specific consumption patterns
> against this API.

---

## Base URL and Auth

- Base URL: `https://connectwise.databranch.com/v4_6_release/apis/3.0`
- Version confirmed: v2026.3.105333 self-hosted
- Auth: HTTP Basic Auth -- Username is `companyId+publicKey`, Password is `privateKey`
- Every request requires the `clientId` header -- without it you get a 403
- Use curl's `-u` flag for testing -- avoids manual Base64 encoding issues
- `system/info` is unauthenticated -- good for testing connectivity

**Auth troubleshooting:** The `+` character in `companyId+publicKey` is a
legitimate separator but can be mishandled when manually constructing Base64.
Use curl's `-u username:password` flag or decode the existing Base64 from a
working n8n node:

```bash
# Example string -- decodes to: COMPANY+PUBLICKEY:PRIVATEKEY
echo "Q09NUEFOWStQVUJMSUNLRVk6UFJJVkFURUtFWQ==" | base64 -d
```

Then use the `-H "Authorization: Basic ..."` header directly rather than `-u`
if the username contains special characters that `-u` mishandles.

**Recommended auth method:** API Member account with API Keys generated for
each integration (available CW Manage 2015.3+). Two other auth methods exist
(Impersonation and per-user username/password) but should not be used for
new integrations -- API Member accounts allow granular role-based access
without tying credentials to a human user.

---

## Endpoints Reference

| What | Endpoint | Notes |
|---|---|---|
| Tickets | `GET /service/tickets` | Filter by `owner/identifier`, `status/name` |
| Ticket configurations | `GET /service/tickets/{id}/configurations` | Returns `[]` when none attached |
| Time entries | `GET /time/entries` | Filter by `member/identifier`, `chargeToId`, `timeStart` |
| Schedule entries | `GET /schedule/entries` | Filter by `member/identifier`, `type/identifier`, `dateStart` |
| Service statuses | `GET /service/boards/{id}/statuses` | Requires board ID |
| System members | `GET /system/members` | Filter by `identifier` |
| Configurations | `GET /company/configurations` | Filter by `name`, `serialNumber`, `macAddress` |
| Configuration count | `GET /company/configurations/count` | Same `conditions` param, returns `{ "count": N }` |
| Tickets linked to config | `GET /service/tickets` | Use `configuration/id=N` (singular -- see below) |
| Company sites | `GET /company/companies/{id}/sites` | Limited fields -- see below |
| Company contacts | `GET /company/contacts` | Filter by `company/id`, `inactiveFlag` |

---

## Pagination

CW Manage uses page-number pagination via `?page=N&pageSize=M` query parameters.

**Defaults and limits (platform-enforced, cannot be changed):**
- `pageSize` defaults to **25** if not specified
- `pageSize` maximum is **1,000** -- any higher value is silently capped
- `page` defaults to **1**

**Two pagination styles are supported:**
- **Navigable** (default) -- the standard `page=N` style. Response includes
  a `Link` header with `rel="next"` and `rel="prev"` URLs following RFC 5988.
- **Forward-only** -- enabled by sending the header `pagination-type: forward-only`.
  Uses a `pageId` cursor instead of incrementing page numbers. More efficient
  for large result sets (10+ pages) because the server doesn't have to count
  prior records.

For everything Databranch currently does, the standard `page=N` pattern is
fine. Forward-only is worth knowing about if you ever paginate the full
configuration list or audit trail.

**Audit trail endpoints do NOT support forward-only pagination** -- use
navigable for those.

---

## Date Filter -- Critical Gotcha

**`>=` with today's date returns empty on self-hosted CW Manage instances
even when entries exist for today. Use `>` with yesterday's date instead.**

```
// BROKEN -- returns [] even with entries today
timeStart>=[2026-04-01]

// WORKS -- functionally identical, returns today's entries
timeStart>[2026-03-31]
```

Date format is `[YYYY-MM-DD]` with square brackets, no time component.
ISO datetime format (`2026-04-01T00:00:00Z`) also does not work.

In code, generate date strings dynamically:

```javascript
const now       = new Date();
const yesterday = new Date(now); yesterday.setDate(now.getDate() - 1);
const tomorrow  = new Date(now); tomorrow.setDate(now.getDate() + 1);
const yStr = yesterday.toISOString().split('T')[0];
const tStr = tomorrow.toISOString().split('T')[0];

// Single-side bound (time entries):
// conditions: `timeStart>[${yStr}]`

// Double-side bound (schedule entries -- avoid returning future entries):
// conditions: `dateStart>[${yStr}] AND dateStart<[${tStr}]`
```

Confirmed on CW Manage v2026.3.105333 self-hosted.

---

## Schedule Entries

- `type/identifier="S"` filters to service ticket dispatches only
- `type/identifier="C"` is calendar/activity (meetings, etc) -- exclude these
- `objectId` is the linked ticket ID for type S entries
- `doneFlag` is the "Marked Done" boolean field
- All dates are UTC -- account for Eastern offset when filtering

**To get today's schedule entries only, bound BOTH sides:**
```
dateStart>[yesterday] AND dateStart<[tomorrow]
```
Using only `>[yesterday]` returns all future entries too.

**Schedule entry name format:**
```
Company Name / Ticket# 12345 - Ticket Summary
```
To extract the summary, split on ` - ` and take everything after:

```javascript
const dashIdx = name.indexOf(' - ');
const summary = dashIdx >= 0 ? name.slice(dashIdx + 3).trim() : name.trim();
```

**To-Do entries:** schedule entries where `dateStart === dateEnd` at midnight UTC.
These have no scheduled time block -- just a date. Detect with:

```javascript
const isToDoEntry = (e) => e.dateStart === e.dateEnd;
```

---

## Service Statuses

`GET /service/statuses` requires a board ID and returns empty without one.
Use the board-specific endpoint:

```
GET /service/boards/{boardId}/statuses?fields=id,name,closedFlag,inactiveFlag&pageSize=100
```

Multiple boards can have statuses with the same name but different IDs.
Querying tickets by `status/name` handles all boards automatically.

**Databranch board IDs:**
- Board 1: Databranch Olean/Olean Service (primary)
- Board 2: Internal Ops
- Board 4: Databranch Elmira/Elmira Service
- Board 14: Loaner/Leased
- Board 19: Sales

**Confirmed active status names on Databranch CW instance:**
- `In Progress`
- `Scheduled` (appears on multiple boards with different IDs -- name query handles both)
- `Action Required - Escalation`
- `Action Required - Inhouse`
- `Action Required - Onsite`
- `Waiting on Client`
- `Waiting on Client - No Auto Close`
- `Waiting on vendor` **(lowercase v -- not a typo)**
- `Waiting on Acc. Mgr`
- `Waiting parts/repair` **(no "on", confirmed exact string)**
- `Waiting on Parts/Licensing` (different board, different status)

**Confirmed closed/completed statuses for tech scorecard credit (boards 1, 2, 19):**

```javascript
const CLOSED_STATUSES = new Set([
  'Closed', 'Closed-Survey',
  'Completed', 'Completed - No Email', 'Completed - Send Email',
  'Completed - Customer has Updated (Karyn)',
  'Completed - Waiting on Client Confirmation (Karyn)',
  'Completed - Ready to Close Survey(Karyn)'
]);
```

**`closedFlag=true` does NOT reliably capture all completed statuses.** Some
completed statuses don't have `closedFlag` set at the board level but still
represent work completion for tech credit purposes. Always filter by status
name set, not by `closedFlag`.

---

## Ticket Fields -- dateEntered Is in _info, Not Top-Level

`dateEntered` is NOT a top-level field on ticket records. It lives inside
the `_info` object:

```json
"_info": {
    "dateEntered": "2026-04-07T05:00:09Z",
    "enteredBy": "template247",
    ...
}
```

**When using the `fields` parameter, `_info` is NOT returned by default.**
You must explicitly include it:

```
fields=id,status,closedDate,_info
```

Without `_info` in the fields list, `ticket._info` will be `undefined`.

**Confirmed top-level date fields on tickets:**
- `closedDate` -- date ticket entered a closed status (top-level, reliable)
- `dateResolved`, `dateResplan`, `dateResponded` -- SLA dates

For ticket age calculations: use `closedDate` (top-level) and
`ticket._info.dateEntered` (requires `_info` in fields).

---

## Ticket Custom Fields

Custom fields (like Vendor Ticket Number) are NOT top-level fields. They live
in a `customFields` array on the ticket response:

```json
"customFields": [
  {
    "id": 7,
    "caption": "Vendor Ticket Number",
    "type": "Text",
    "value": "2604140040004895\u200e"
  }
]
```

**To read a custom field:**
```javascript
const vendorNum = (ticket.customFields || [])
  .find(f => f.caption === 'Vendor Ticket Number')?.value || null;
```

**Zero-width character stripping:** Custom field values may contain invisible
Unicode characters -- particularly `\u200e` (left-to-right mark) which appears
in vendor ticket numbers copied from external systems. Always strip:

```javascript
value.replace(/[\u200e\u200f\u200b\ufeff]/g, '').trim()
```

---

## Time Entry billableOption Values

Confirmed values on Databranch CW instance:

| Value | Meaning |
|---|---|
| `Billable` | Billable to client |
| `DoNotBill` | Non-billable (internal, admin, etc.) |
| `NoCharge` | Non-billable (goodwill, warranty, etc.) |

For scorecard billable/non-billable split:
- Billable = `billableOption === 'Billable'`
- Non-billable = `DoNotBill` + `NoCharge`

---

## Configurations API

`GET /company/configurations` supports partial match filtering:

```
name like "%search%"
serialNumber like "%search%"
macAddress like "%search%"
```

To search name OR serial in one query:
```
name like "%term%" OR serialNumber like "%term%"
```

`GET /company/configurations/count` accepts the same `conditions` parameter
and returns `{ "count": N }`. Use `Promise.all` to fetch results and count
in parallel so pagination math is available without a second sequential call.

**MAC address normalization before querying:** Strip colons, dashes, and spaces
from user input before building the filter:

```javascript
const macRaw = searchTerm.replace(/[:\-\s]/g, '').toUpperCase();
// Then: macAddress like "%macRaw%"
```

---

## Tickets Linked to a Configuration -- Critical Filter Gotcha

The correct filter field is `configuration/id=N` (**singular**, no `s`).

```
// BROKEN -- returns 400
configurations/id=123 OR configurations/id=456

// BROKEN -- also 400
configurations/id=123

// CORRECT
configuration/id=123
```

Batch queries across multiple config IDs via OR also return 400. The only
working pattern is one query per config ID. Run in parallel via `Promise.all`:

```javascript
const ticketFetches = configs.map(cfg =>
  this.helpers.httpRequest({
    method: "GET",
    url:    `${baseUrl}/service/tickets`,
    headers,
    qs: {
      conditions: `configuration/id=${cfg.id} AND closedFlag=false`,
      fields:     "id,summary,status",
      pageSize:   "10"
    }
  }).then(res => ({ configId: cfg.id, tickets: Array.isArray(res) ? res : [] }))
    .catch(()  => ({ configId: cfg.id, tickets: [] }))
);
const allResults = await Promise.all(ticketFetches);
```

Always add `.catch()` per fetch so a single bad config ID never crashes the
whole node.

---

## Company Sites Sub-endpoint

`GET /company/companies/{id}/sites` returns site records for a company.

**Valid fields on this endpoint:**
```
id, name, addressLine1, city, zip, phoneNumber
```

**Fields that return 400 if requested:**
- `addressLine2` -- NOT a valid field on the sites endpoint
- `stateIdentifier` -- NOT returned even if requested (silently omitted)
- `defaultFlag` -- NOT filterable as a conditions parameter

**Correct call:**
```javascript
this.helpers.httpRequest({
  method: "GET",
  url:    `${baseUrl}/company/companies/${companyId}/sites`,
  headers,
  qs: {
    fields:   "id,name,addressLine1,city,zip,phoneNumber",
    pageSize: "1"
  }
})
```

Since `defaultFlag` is not filterable, fetch with `pageSize: 1` and take the
first result. The company-level record does return `stateIdentifier` -- use it
as a fallback for full address formatting.

---

## Company Contacts -- defaultFlag

The `defaultFlag` field at the contact level (not inside `communicationItems`)
identifies the primary/billing contact for a company. This IS filterable.

```javascript
const primaryContact = contacts.find(c => c.defaultFlag === true)
  || contacts[0]  // fallback to first active contact
  || null;
```

The `defaultFlag` inside `communicationItems` is different -- it marks which
phone or email is that contact's own primary communication method. Do not
confuse the two levels.

To extract a contact's phone/email from `communicationItems`:

```javascript
function getComm(contact, type, preferDirect) {
  if (!contact || !Array.isArray(contact.communicationItems)) return null;
  const items = contact.communicationItems.filter(c => c.communicationType === type);
  if (items.length === 0) return null;
  if (preferDirect) {
    const direct = items.find(c => c.type && c.type.name === 'Direct' && c.defaultFlag);
    if (direct) return direct.value;
    const cell = items.find(c => c.type && c.type.name === 'Cell' && c.defaultFlag);
    if (cell) return cell.value;
  }
  const def = items.find(c => c.defaultFlag);
  return def ? def.value : items[0].value;
}
```

---

## Batch Ticket Status Lookup

When you have multiple ticket IDs and need their statuses, build a single
OR condition rather than looping:

```javascript
const ids       = [123, 456, 789];
const condition = ids.map(id => `id=${id}`).join(' OR ');
```

Then one `GET /service/tickets` call returns all tickets. Build a map for
O(1) lookup downstream:

```javascript
const statusMap = {};
for (const t of tickets) {
  statusMap[t.id] = { statusName: t.status.name, companyName: t.company.name };
}
```

For large sets (100+ IDs), batch in groups of 100 to avoid URL length limits:

```javascript
async function fetchTicketDetails(ticketIds) {
  if (ticketIds.length === 0) return [];
  const batchSize = 100;
  let allTickets  = [];
  for (let i = 0; i < ticketIds.length; i += batchSize) {
    const batch     = ticketIds.slice(i, i + batchSize);
    const condition = batch.map(id => `id=${id}`).join(' OR ');
    const result    = await this.helpers.httpRequest({
      method: "GET",
      url:    `${baseUrl}/service/tickets`,
      headers,
      qs: { conditions: condition, fields: "id,status,closedDate,_info", pageSize: String(batchSize) }
    });
    if (Array.isArray(result)) allTickets = allTickets.concat(result);
  }
  return allTickets;
}
```

---

## Time Entries -- Paginated Fetch Pattern

For reporting workflows that need all time entries across a date range,
always paginate. A single tech over 30 days can produce 200+ entries.

```javascript
async function fetchTimeEntries(cwIdentifier, windowStart, windowEnd) {
  const condition = `member/identifier="${cwIdentifier}" AND chargeToType="ServiceTicket" AND timeStart>[${yStr}] AND timeStart<[${tStr}]`;

  let allEntries = [];
  let page       = 1;
  const pageSize = 200;

  while (true) {
    const batch = await this.helpers.httpRequest({
      method: "GET",
      url:    `${baseUrl}/time/entries`,
      headers,
      qs: { conditions: condition, fields: "...", pageSize: String(pageSize), page: String(page) }
    });
    if (!Array.isArray(batch) || batch.length === 0) break;
    allEntries = allEntries.concat(batch);
    if (batch.length < pageSize) break;  // last page
    page++;
  }

  return allEntries;
}
```

The `if (batch.length < pageSize) break` is the correct exit condition.
CW returns empty arrays, not errors, when you request a page beyond the last.

---

## Notes Endpoint

`GET /service/tickets/{id}/notes` accepts `detailDescriptionFlag=true` as a
condition to filter to the initial description note only.

`noteType` is NOT a valid filter field -- returns ApiFindCondition error.

The description note text often contains:
- Email headers (From/Sent/To/Subject lines)
- Markdown image tags `![text](url)`
- SafeLinks URLs (long Microsoft URL wrappers)
- Bold/italic markdown `**text**`
- Non-breaking spaces `\u00a0`

Strip all of these before displaying in a card:

```javascript
function stripToPlain(text) {
  if (!text) return '';
  return text
    .replace(/!\[.*?\]\(.*?\)/g, '')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/<[^>]*>/g, '')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\*([^*]+)\*/g, '$1')
    .replace(/\\([()[\]\\])/g, '$1')
    .replace(/\u00a0/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
```

---

## Structured Note Templates -- Bold Markdown Parsing

CW time entry notes use `**bold text**` markdown (NOT HTML) for structured
note templates. The pattern:

```
**Section Title**
**- Field: value**
**- Field:** value outside closing stars
```

Two bold value patterns in the wild:
- `**- What: Call Meraki after morning meeting**` -- value inside closing `**`
- `**- What is needed from Client:** iViewer setup` -- value outside closing `**`

Regex patterns to handle both:

```javascript
const titlePattern        = /^\*\*([^\-*][^*]*)\*\*\s*$/;
const fieldPatternOutside = /^\*\*-\s*([^:*]+):\*\*\s*(.*)$/;
const fieldPatternInside  = /^\*\*-\s*([^:*]+):\s*(.*?)\*\*\s*$/;
const fieldPatternNoValue = /^\*\*-\s*([^:*]+)\*\*\s*$/;
```

The structured block always appears at the **bottom** of the note after a
blank line. Everything above it is plain narrative text. Parse by finding the
first line matching `titlePattern` and treating everything from there as the
structured block.

---

## Deep Links Reference (Confirmed Working)

Only three reliable deep link patterns exist for self-hosted CW Manage:

| Destination | URL Pattern |
|---|---|
| Service ticket | `ConnectWise.aspx?routeTo=ServiceFV&recid={ticketId}` |
| Company record | `ConnectWise.aspx?routeTo=AccountFV&recid={companyId}` |
| Configuration record | `ConnectWise.aspx?routeTo=ConfigFV&recid={configId}` |

**Does NOT work:**
- `routeTo=ServiceTicketFV&recid={companyId}` -- spins forever
- `routeTo=AccountFV&recid={companyId}??CompanyServiceList` -- spins forever
- `routeTo=ServiceFV&companyRecId={companyId}` -- opens a new ticket form

**Why:** CW Manage is a legacy WebForms single-page app. The company Service
tab and filtered board views are driven by authenticated POST requests to
internal `.rails` endpoints with session tokens. These cannot be reproduced
as a static URL. There is no public deep link to a company's service ticket
list.

**Best practice:** Link to `AccountFV` (company record) for company context.
The tech can click the Service tab from there -- it is one click.

---

## Terminal / Non-Actionable Ticket Statuses

When building company snapshots or board views, filter out terminal statuses
to avoid inflating counts and blowing payload size limits:

```javascript
const TERMINAL_STATUSES = new Set([
  'Closed', 'Cancelled', 'Completed', 'Completed - Internal Email Only',
  'Resolved', 'Loaner', 'Assigned'
]);

const activeTickets = allTickets.filter(
  t => !TERMINAL_STATUSES.has(t.status ? t.status.name : '')
);
```

Note: `closedFlag=false` on the API query does NOT exclude tickets in a
"Closed" named status if that status doesn't have the closed flag set at the
board level. Always apply the status name exclusion list in JavaScript after
fetching.

---

## Parallel vs Sequential API Calls for Debugging

When a `Promise.all` fails with a 400, you cannot tell which call caused it.
Split into sequential awaits temporarily to isolate the problem:

```javascript
// Instead of:
const [a, b, c] = await Promise.all([callA(), callB(), callC()]);

// Use temporarily:
const a = await callA();  // if this fails, you know it's callA
const b = await callB();
const c = await callC();
```

Once identified and fixed, re-combine into `Promise.all` if performance
matters -- though sequential is fine for command-triggered workflows.

**Known 400-causing field names:**
- `addressLine2` on `/company/companies/{id}/sites`
- `dateEntered` as a top-level field on tickets (it's in `_info`)
- Any field name not supported by that specific sub-endpoint

---

## After-Hours Detection

Consistent definition used across EOD report, stats scorecard, and any
workflow that needs to flag after-hours time entries:

```javascript
function isAfterHours(timeStartISO) {
  const dt   = DateTime.fromISO(timeStartISO, { zone: 'utc' }).setZone('America/New_York');
  const dow  = dt.weekday; // 1=Mon, 7=Sun in Luxon
  const hour = dt.hour;
  if (dow >= 6) return true;     // Saturday or Sunday
  return hour < 8 || hour >= 17; // before 8 AM or at/after 5 PM
}
```

Requires Luxon. See n8n-lessons-learned for Luxon setup.

---

## Filtering to Today's Eastern Date

CW schedule entries use UTC timestamps. The `>[yesterday] AND <[tomorrow]`
CW filter leaks in entries from adjacent days because UTC midnight does not
align with Eastern midnight. Always apply a second filter in JavaScript using
Luxon boundaries after fetching from CW:

```javascript
const tz         = 'America/New_York';
const todayStart = DateTime.now().setZone(tz).startOf('day');
const todayEnd   = todayStart.endOf('day');

// Filter fetched entries to true Eastern today
const todayEntries = entries.filter(e => {
  const s = new Date(e.dateStart);
  return s >= new Date(todayStart.toMillis()) && s < new Date(todayEnd.toMillis());
});
```

---

## Confirmed Instance Details (Databranch)

| Field | Value |
|---|---|
| Base URL | `https://connectwise.databranch.com/v4_6_release/apis/3.0` |
| Version | v2026.3.105333 (self-hosted) |
| Auth | API Member account with API Keys |

---

*End of ConnectWise Manage API Lessons Learned*
