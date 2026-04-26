# Power Automate -- Lessons Learned
**Databranch Internal | Sam Kirsch**
Last Updated: 2026-04-26

> **See also:** `Databranch_AutomationLessonsLearned_n8n.md` for n8n-specific
> automation patterns. `Databranch_APILessonsLearned_DattoRMM.md` and related
> files for API integration patterns used in flows.

---

## Flow Export / Import

**Power Automate can export flows as JSON packages but cannot import them.**
The export function produces a `.zip` containing `definition.json`,
`apisMap.json`, `connectionsMap.json`, and manifest files. These are useful
for documentation, version snapshots, and reading flow logic -- but there is
no native import path back into the designer. Flows must be rebuilt manually.

**Export JSON is valuable for auditing.** The `definition.json` contains the
full flow logic including all expressions, HTTP URIs, authentication settings,
and SharePoint column mappings. When debugging a broken flow or reviewing
logic, export and read the JSON directly rather than clicking through the
designer UI.

**Credential exposure risk in exported flows.** HTTP action credentials
(username/password for Basic Auth) are stored in plaintext in
`definition.json`. Treat exported flow packages as sensitive -- do not
commit to source control or share without scrubbing credentials first.

---

## Rebuilding Flows -- Designer Behavior

**The designer uses `Apply to each` for all loops, not `For each`.**
The UI presents all loop nodes as `Apply to each` regardless of how they
appear in documentation or AI-generated instructions. Do not waste time
searching for a `For each` node -- it does not exist as a separate action
in the current designer.

**Loop concurrency.** `Apply to each` runs sequentially by default.
Concurrency can be enabled per-loop via the `...` menu → Settings →
Concurrency Control. Use parallelism for independent operations (e.g.
SharePoint deletes). Do NOT enable concurrency on loops that contain
`Append to string variable` or `Set variable` actions -- concurrent
writes to the same variable produce race conditions and corrupted output.

**`runAfter` configuration for post-Condition nodes.** When a node must
run after a Condition regardless of which branch was taken, configure
its `runAfter` to include both `Succeeded` and `Skipped` for the
Condition action. Access via the node's `...` menu → Configure run after.
If only `Succeeded` is set, the node will not fire on the branch that
was skipped.

**Parse JSON schemas.** The designer sometimes refuses to accept a
pasted schema and requires using "Generate from sample" instead. To
get the sample: run the flow once, open the run history, find the HTTP
action output, copy the raw response body, and paste into Generate from
sample. The result is equivalent to a hand-written schema.

---

## Expressions and the Expression Editor

**Single quotes inside single quotes break OData filter queries.**
The SharePoint Get items `Filter Query` field uses OData syntax which
requires single quotes around string values. Power Automate expressions
also use single quotes for string literals. Nesting these conflicts.

**Wrong:**
```
DetectedOn ge '@{addHours(utcNow(),-16,'yyyy-MM-ddTHH:mm:ssZ')}'
```
The format string's single quotes terminate the outer OData string early.

**Correct -- drop the format parameter entirely:**
```
DetectedOn ge '@{addHours(utcNow(),-16)}'
```
`utcNow()` already returns ISO 8601 format. SharePoint OData accepts it
natively. The format parameter is unnecessary and causes silent failures
(zero rows returned, no error).

**`formatDateTime()` format specifiers bleed into URL-encoded strings.**
When building a URL-encoded date string using `formatDateTime()`, do not
embed the encoding directly in the format string. Use `encodeUriComponent()`
as a wrapper instead:

**Wrong:**
```
formatDateTime(utcNow(), 'yyyy%2DMM%2Ddd')
```
Produces `20262D042D25` -- the `%2D` is treated as literal format characters.

**Correct:**
```
encodeUriComponent(formatDateTime(utcNow(), 'yyyy-MM-dd'))
```
Produces `2026%2D04%2D25` as expected.

**`join()` requires a flat string array -- not an array of objects.**
The `join()` function concatenates array elements with a separator. It
only works correctly when the array contains primitive strings. If the
input is an array of objects (e.g. output of a Select action with a
key/value map), `join()` produces empty output or `[object Object]`
strings silently.

The Select action always outputs an array of objects even when the map
has a single key. Do not use Select + join() to build HTML row strings.
Use `Append to string variable` inside an `Apply to each` loop instead --
this is the reliable pattern for per-item HTML generation in Power Automate.

**`createObject()` with dynamic keys is unreliable.**
The `createObject(key, value)` function behaves unexpectedly when the key
is a dynamic expression rather than a string literal. Use `json(concat(...))`
to build single-entry objects with dynamic keys instead:

**Wrong:**
```
createObject(items('loop')?['id'], someValue)
```

**Correct:**
```
json(concat('{"', items('loop')?['id'], '":"', someValue, '"}'))
```

**Self-referencing variables in `Set variable` are blocked.**
Power Automate does not allow a `Set variable` action to reference the
same variable it is setting. The error is:
`Self reference is not supported when updating the value of variable 'X'`

This is a common pattern when merging new data into an accumulator object
(e.g. building a cache with `union()`). The workaround is a temp variable:

1. `Set variable` → `var_Temp` = `union(variables('myVar'), newEntry)`
2. `Set variable` → `myVar` = `variables('var_Temp')`

Initialize both variables at the top of the flow with `{}` (empty object,
entered in Expression mode).

**Variables initialized as blank/null fail on first use.**
`Initialize variable` with an empty Value field produces a `null` variable,
not an empty string or empty object. Functions like `contains()` and
`union()` throw on null input:
`'contains' expects its first argument to be a dictionary, array or string.
The provided value is of type 'Null'.`

Always initialize Object variables to `{}` and String variables to `''`
(empty string) in Expression mode, not Dynamic content mode. Entering `{}`
in Dynamic content mode stores the literal string `"{}"` rather than an
empty object.

---

## HTTP Actions

**TLS 1.2 enforcement.** Not applicable in Power Automate cloud flows --
TLS negotiation is handled by the platform. This is only a concern in
PowerShell scripts. No equivalent setting is needed in flow HTTP actions.

**308 Permanent Redirect is not followed automatically.**
Power Automate's HTTP action does not follow HTTP 308 redirects. A 308
response is treated as the final response, which is not a 2xx, causing
the action to fail. The fix is to correct the URL in the HTTP action to
point directly to the correct endpoint rather than relying on redirect
following.

**Auvik API region mismatch produces 308 errors.** Auvik's API is
region-specific. Databranch's tenant lives on `us2`. All Auvik HTTP
action URIs must use `auvikapi.us2.my.auvik.com`. Using `us1` produces
a 308 redirect to `us2` which Power Automate cannot follow, causing
the action to fail permanently.

**Add retry policies to all external HTTP actions.**
HTTP actions have no retry policy by default. Transient failures (timeouts,
momentary API unavailability) cause permanent flow failures. Configure
retry on every external HTTP action via `...` → Settings:

| Setting | Value |
|---|---|
| Type | Fixed interval |
| Count | 3 |
| Interval | PT1M (1 minute) |

---

## SharePoint Connector

**OData filter date format requires ISO 8601 with Z suffix.**
SharePoint OData filters on DateTime columns require the value to be in
ISO 8601 format with a UTC `Z` suffix. `addHours(utcNow(), -16)` produces
this format natively. Do not add a format parameter -- it causes quote
nesting issues. If zero rows return from a filtered Get items with no
error, the date format is the first thing to check.

**Get items returns `body/value`, not `body`.**
The output of a Get items action is accessed as
`outputs('Get_items')?['body/value']` for the array of items, not
`body('Get_items')`. Using the wrong path returns null silently.

**Delete loop should run with concurrency enabled.**
SharePoint delete operations are independent. Running them sequentially
when clearing a list wastes significant time. Set concurrency to 10 on
the delete `Apply to each` loop. This is safe because each delete
references its own item ID.

**SharePoint file Create action returns `body/ItemId` for the numeric ID.**
When creating a file via SharePoint → Create file, reference the created
file's ID for subsequent Update file properties calls as:
`outputs('Create_file')?['body/ItemId']`

**SharePoint Get files (properties only) returns `{Identifier}` for
file deletion.** When building a cleanup loop that deletes old files,
use `items('loop')?['{Identifier}']` as the File Identifier in the
Delete file action, not the numeric ID. The `{Identifier}` field is
the internal SP path reference required by the delete connector.

---

## HTML in Teams and Email

**Teams strips `<style>` blocks entirely.** All CSS must be inline on
every element. There is no way to use a shared stylesheet in a Teams
channel message. Every `<td>`, `<th>`, `<span>`, and `<a>` needs its
full style attribute.

**Teams does not support `div` elements reliably (as of late 2024).**
`div` rendering was removed or broken in a Teams update. Use `table`,
`tr`, `td`, `th`, `span`, and `p` elements only. `border-radius` is
stripped in Teams desktop but renders in Teams web and Outlook.
`display:block` on `span` elements is ignored -- use `<br>` instead.

**Teams has a character limit on message body length.** When the HTML
content exceeds this limit, Teams does not truncate cleanly -- it posts
a degraded/broken version and appends a "download" prompt. Design for
this by keeping inline Teams content concise (currently-down table only)
and delivering large tables (historic activity) via a separate mechanism.

**`Create HTML table` action produces unstyled, HTML-encoded output.**
The built-in Create HTML table action encodes angle brackets as `&lt;`
and `&gt;` and applies no styling. It cannot be used to produce styled
HTML for Teams or email. Replace it with `Append to string variable`
inside an `Apply to each` loop, building each `<tr>` as a raw HTML
string with full inline styles.

**The old `replace()` wrapper anti-pattern.** Flows that used
`Create HTML table` often wrap the output in nested `replace()` calls
to decode `&lt;` back to `<`. When replacing `Create HTML table` with
the `Append to string variable` pattern, remove all `replace()` wrappers
-- the output is already raw HTML and does not need decoding.

**Embedding HTML in JSON for email attachments is not viable.**
HTML content contains double quotes throughout (`style="..."`) which
conflicts with JSON string encoding. Attempting to build a JSON attachment
array containing raw HTML as a string value will fail with template
language errors regardless of escaping approach. The reliable alternative
is to write the HTML to a SharePoint file and reference it.

**`base64()` for email attachments encodes correctly but clients may
render the raw base64 string.** The Send email V2 action's attachment
`ContentBytes` field expects base64-encoded content. `base64(content)`
is the correct function. However, if the resulting `.html` attachment
opens as a raw base64 text file rather than rendered HTML, the issue is
the email client's file association handling, not the encoding. Test in
multiple clients before assuming the encoding is wrong.

**HTML files served from SharePoint open in a download dialog from
Teams links, not in-browser.** Teams does not have a native HTML
renderer for file previews. Clicking a SharePoint link to an `.html`
file from Teams bounces to the browser which then downloads the file
rather than rendering it inline. This only works cleanly for Office
formats (docx, xlsx, pptx) and PDF. Plan delivery mechanisms
accordingly -- HTML is best delivered as an email attachment or via a
direct link that the recipient opens in their own browser.

**MailProtector (and similar email security gateways) may flag HTML
file attachments as malicious.** Outbound flows sending `.html`
attachments through a security gateway may have those emails held for
manual review. The fix is to whitelist the sending address or destination
address (e.g. a `*.amer.teams.ms` Teams inbound address) in the gateway
configuration. Raise a support ticket with the gateway vendor specifying
the sender, recipient, and attachment type to get a targeted exemption.

---

## Auvik API -- Power Automate Specific

> See also the Auvik-specific lessons if a dedicated
> `Databranch_APILessonsLearned_Auvik.md` is created. The following
> apply specifically to consuming the Auvik API from Power Automate flows.

**Auvik alert status values are `created` and `resolved` -- not lifecycle
states.** The `filter[status]` parameter on `GET /v1/alert/history/info`
accepts `created` (trigger events) and `resolved` (clear events). These
are two separate record types, not a status field on a single record.
A device going offline produces a `created` record. The same device
coming back online produces a new `resolved` record with a `relatedAlert`
back-pointer to the original. They are never the same record.

**`dismissed=true` on a `created` record means Auvik auto-closed it,
not that a human dismissed it.** When a `resolved` record is created,
Auvik automatically sets `dismissed=true` on the corresponding `created`
record. All `created` records in the dismissed bulk export are the
trigger-side of already-resolved pairs. Manually dismissed alerts (no
clear condition) remain as `created` + `dismissed=true` with no
corresponding `resolved` record.

**`filter[dismissed]=false` on `created` status returns only genuinely
open alerts.** This is the correct filter for a currently-down list.
Using `filter[status]=created` without the dismissed filter returns
both open and auto-closed trigger records -- the already-resolved ones
are noise and inflate the result set significantly.

**Not all resolved alerts have an `entity` relationship.**
Collector-level alerts (e.g. "Auvik Collector Reconnected") produce
`resolved` records with only `tenant` and `relatedAlert` relationships --
no `entity`. Device-level alerts include `entity`. Any flow that calls
the device info endpoint using `relationships.entity.data.id` must
guard against this with a Condition that checks whether entity exists
before making the HTTP call. Failure to guard produces:
`property 'entity' doesn't exist, available properties are 'tenant, relatedAlert'`

**The Auvik tenant detail endpoint is region-specific and must use `us2`
for Databranch.** The tenant detail lookup URI is:
`https://auvikapi.us2.my.auvik.com/v1/tenants/detail/{tenantId}?tenantDomainPrefix=databranch`
Using `us1` produces a 308 redirect that Power Automate cannot follow.
This was the root cause of the original flow failure that prompted the
rebuild documented here.

**Tenant names repeat across many alert records -- cache the lookup.**
In a 63-hour window, ~250 alert records may span only 15-20 unique
tenants. Calling the tenant detail API once per record wastes 230+
API calls returning duplicate data. Use an object variable as a cache:
check if the tenant ID is already in the cache before calling the API,
store new results into the cache, reference the cache for SP writes.
This pattern collapses N tenant API calls to the number of unique tenants.

---

## Flow Architecture Patterns

**Wipe-and-rewrite SP lists leave a blank window during runs.**
The pattern of Get items → delete all → create all means the SP list
is empty between the delete loop completing and the create loop finishing.
Any downstream flow or report that reads the list during this window
sees zero rows. For hourly snapshot flows this is acceptable. For flows
where downstream consumers run concurrently, consider a delta/upsert
pattern instead.

**Separate data collection from reporting.**
Flows that both collect data and produce output (email, Teams post) are
harder to maintain and debug. The pattern that works well at Databranch:

- **Capture flows** (run hourly): query the source API, write enriched
  data to SharePoint lists
- **Report flows** (run on schedule): read from SharePoint, build output,
  post to Teams / send email

This separation means the report can be triggered, rerun, or modified
independently of the collection cadence.

**Use day-of-week recurrence for schedule splitting.**
Power Automate's recurrence trigger supports a `weekDays` schedule array
when frequency is set to `Week`. This allows a single flow to target
specific days without building date-check logic inside the flow itself.
Use this to split weekday and Monday reports with different lookback
windows without duplicating the entire flow -- only the recurrence node
and the SP filter query differ between the two.

**Initialize all variables at the top of the flow before any loops.**
Variables referenced inside loops must be initialized before the first
loop runs. Power Automate evaluates variable initialization in sequence --
if an `Initialize variable` node is placed after a `Get items` node that
it depends on, it may not be initialized when the loop first executes.
Place all `Initialize variable` nodes in a chain at the top of the main
sequence, before any data-fetching nodes.

**Bake cleanup into operational flows rather than creating separate
maintenance flows.** A cleanup loop at the top of a report flow (e.g.
delete SharePoint files older than 365 days) adds negligible runtime
and eliminates the need to manage a separate scheduled maintenance flow.
At low file volumes (one file per daily run), the cleanup loop iterates
over one or zero files per execution.

---

## Recurrence Trigger Notes

**`Eastern Standard Time` does not observe DST -- use `Eastern Standard Time`
deliberately or `Eastern Time (US & Canada)` if DST adjustment is needed.**
Power Automate's time zone list includes both. `Eastern Standard Time` is
always UTC-5. `Eastern Time (US & Canada)` shifts to UTC-4 in summer.
Choose based on whether you want the flow to fire at wall-clock 8 AM
year-round or at a fixed UTC offset.

**Set `startTime` to a past date when configuring weekly recurrence.**
The `startTime` field anchors which day-of-week the recurrence considers
"week 1." Set it to a past occurrence of the desired start day to ensure
the schedule fires immediately on the next correct day rather than waiting
for the first future anchor.

---

## Flow Design Anti-Patterns

**Nested if/else chains are the wrong pattern for multi-type email or record
classification.** A deeply nested Condition tree (Critical → Warning → Hardware
→ Device Not Seen → Screenshot → Unknown) works when first built but becomes
unmaintainable past three types. Adding a new type requires navigating to the
deepest else branch and inserting another level of nesting. Debugging requires
mentally walking the entire tree. The correct pattern is to classify first
(determine the type from the subject/content into a variable) and then branch
once on that variable, keeping each branch's logic flat and independent. If
Power Automate's expression limitations make a single classification step
impractical, use parallel top-level conditions that each terminate early on a
match rather than a cascading else chain.

**Duplicated Compose chains per classification branch signal a structural
problem.** In the DattoParser flow, a 9-node Agent/Device/Serial extraction
sequence (three Compose nodes each for agent name, device name, and serial
number) appears independently in each classification branch. When the same
sequence of nodes repeats verbatim across multiple branches, the classification
is happening after the parsing when it should happen before it. The correct
order is: classify the email type first, then parse based on that type. This
collapses N copies of the same parsing logic into one.

**`nthIndexOf` with hardcoded line numbers is the most fragile parsing
approach available in Power Automate.** It silently produces garbage output
when the source message format changes its line count by even one line. Prefer
`indexOf` with landmark strings (e.g. find `'Campaign Name: '` and extract
from there to the next newline) over absolute line-number offsets. Any
text-parsing approach in Power Automate is inherently fragile against format
changes -- when a flow depends on parsing a specific message format, document
the dependency and notify the owner of the source system that the message
template is being consumed programmatically.

**The SP item trigger (`When an item is created`) is the correct pattern for
real-time alerting on new SP data.** Use it when the requirement is "react
immediately when a new record appears." Use scheduled recurrence when the
requirement is "summarize what accumulated over a time window." These are
different patterns for different purposes and should not be substituted for
each other. The DattoChannelAlert flow correctly uses the item trigger for
instant per-alert Teams notifications; the Datto8AMReport correctly uses
recurrence for a periodic summary.

**`runAfter` with all four states (Succeeded, Skipped, Failed, TimedOut) is
the correct pattern for guaranteed post-loop cleanup.** When a node must
execute regardless of whether the preceding loop succeeded or failed -- for
example, a reporting step that should always run even if the data collection
loop had errors -- configure its `runAfter` to include all four states. The
default `Succeeded`-only setting means the node is silently skipped on any
upstream failure. Example from the PhishingCampaign flow: the final
`Get_items_1` and report post use this pattern to ensure the report fires
even if the message-parsing loop encountered errors on some items.

---

*End of Power Automate Lessons Learned*
