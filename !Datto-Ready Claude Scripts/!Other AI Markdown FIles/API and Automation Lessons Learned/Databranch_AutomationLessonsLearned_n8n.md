# n8n Lessons Learned -- Preferences, Patterns, and Pitfalls
**Databranch Internal | Sam Kirsch**
Last Updated: 2026-04-18

> **See also:** `cw-manage-lessons-learned.md` for all ConnectWise Manage API
> specific notes, field names, endpoint gotchas, and confirmed status strings.

---

## Design Philosophy

- **More nodes, less code -- but know the limit.** Prefer native n8n nodes over
  Code blocks. Every node is visible, debuggable, and reusable. But n8n item
  pairing has a hard limit: when you split items, make external calls per item,
  filter results, and need to carry context forward, native nodes run out of
  reliable solutions. That is the Code node's job.
- **Code nodes have one legitimate use case in this style:** handling per-item
  loops with external calls where item pairing would break down. Not for dense
  multi-purpose logic -- just for the specific section where native nodes fail.
- **Push complexity into SQL when possible.** A single Postgres CTE can dedup,
  insert, and return clean data in one atomic operation -- replacing three or
  four native nodes that would require item pairing gymnastics between them.
- **Complex ideas, not needless complexity.** Rich multi-step workflows are good.
  Clever code that does five things at once is not.
- **Name every node descriptively.** You reference nodes by name in expressions
  constantly. Vague names like Set1 make that painful fast.

---

## The Item Pairing Problem -- The Core n8n Limitation

This is the most important lesson from building this workflow.

n8n tracks which output item came from which input item -- called item linking
or item pairing. It allows expressions like `$('NodeName').item.json` to know
which item to return when there are multiple items in flight.

**Item pairing breaks when:**
- A node that produces multiple items is referenced downstream using `.item`
- An external call node (HTTP Request, Postgres) overwrites `$json` with its
  own response, and you try to reach back past it to a node that had multiple items
- You split items, make filtered external calls, and try to rejoin the context

**The error message:**
```
Multiple matching items for item [0]
An expression here won't work because it uses .item and n8n can't figure
out the matching item.
```

**What does NOT fix it:**
- Using `.first()` -- grabs item 0 for everyone, wrong for items 1+
- Using `.all()[index]` -- requires knowing the index, breaks dynamically
- Adding more Set nodes to pass data forward -- same pairing issue follows
- Merge node -- breaks when IF filters reduce item count before the merge
- Split Out with Include All Other Fields -- still breaks after filtered branches

**What DOES fix it:**
- A Code node for the loop section -- no item pairing concept, processes
  whatever it receives and returns whatever you tell it to
- Pushing logic into a Postgres CTE -- one query that handles filtering,
  inserting, and returning clean data with full context, no n8n item pairing
  involved at all
- Backreferences to nodes that output exactly ONE item per entity are safe --
  ambiguity only exists when the referenced node had multiple items

**The rule for safe backreferences:**
If the referenced node outputs exactly one item per tech/entity, `.item` works.
If it could output multiple items, you will hit the multiple matching items error.

---

## Grace Period Pattern -- Avoiding Premature Alerts

Some alerts should not fire the instant a condition is first detected. A tech
picking up a new ticket needs a few minutes to attach a configuration or start
a time entry before being yelled at about it.

**The pattern:** Store a `first_seen` timestamp in Postgres when a condition is
first detected. Only alert if `first_seen < NOW() - INTERVAL '5 minutes'`. On
the first detection run, the insert records `first_seen = NOW()` and the query
filters it out. On the next run (5 minutes later) the insert conflicts and does
nothing, but the existing row now passes the `first_seen` age check.

This is cleaner than checking CW Manage's audit trail or `lastUpdated` field
because it measures "how long has n8n known about this" rather than "how long
has CW known about this" -- which is actually the right question for your
use case.

Use this pattern any time:
- An alert might fire too soon after a tech first touches a ticket
- You want a buffer between a state change and the first notification
- The source system does not expose a reliable "state changed at" timestamp

The 5-minute interval pairs naturally with a 5-minute schedule trigger -- every
ticket gets exactly one missed run as a grace period before the alert fires.

---

## The Golden Rule -- $json Gets Overwritten

This includes HTTP Request, Postgres, and any other integration node. Whatever
was in $json before that node is gone after it unless you carry it forward.

**Fixes in order of preference:**
1. Push the logic into the external call itself (SQL CTE, query parameters)
   so you never need to reach back
2. Use a Code node that controls its own output shape completely
3. Use an Edit Fields (Set) node after the external call -- only safe when
   the node you are reaching back to outputs one item per entity

---

## Code Node -- Return Syntax

The return syntax differs between modes:

**Run Once for All Items** -- return an array:
```javascript
return [{ json: { field: value } }, { json: { field: value } }];
```

**Run Once for Each Item** -- return a single object:
```javascript
return { json: { field: value } };
```

Getting this wrong causes: `A 'json' property isn't an object [item 0]`

---

## Postgres CTE Pattern -- The Power Move

When you need to filter, insert, and return data based on the same dataset,
a single CTE does it atomically in one Postgres node -- no Code node filtering,
no Set nodes to restore context, no item pairing issues.

General pattern:

```sql
WITH input_data AS (
  -- Unpack JSON array from n8n expression
  SELECT (val->>'id')::int AS id, val->>'name' AS name
  FROM json_array_elements('{{ JSON.stringify($json.myArray) }}'::json) val
),
filtered AS (
  SELECT * FROM input_data
  WHERE NOT EXISTS (
    SELECT 1 FROM my_table
    WHERE some_id = input_data.id
    AND some_date = CURRENT_DATE
  )
),
inserted AS (
  INSERT INTO my_table (some_id, some_date)
  SELECT id, CURRENT_DATE FROM filtered
  ON CONFLICT DO NOTHING
)
SELECT
  '{{ $json.contextField }}' AS "contextField",
  COALESCE(json_agg(json_build_object('id', id, 'name', name)), '[]'::json) AS "results"
FROM filtered;
```

Key details:
- Use `COALESCE(..., '[]'::json)` to return empty array instead of null
- Quote column aliases with double quotes to preserve camelCase in n8n output
- `ON CONFLICT DO NOTHING` makes inserts safe to re-run
- The entire CTE is atomic -- no partial inserts if something fails

---

## Postgres CTE -- Apostrophe / Special Character Bug (CRITICAL)

**This will bite you.** Any ticket summary, company name, or other string
containing an apostrophe will break a Postgres CTE that injects a JSON array
via `JSON.stringify(...)` wrapped in single quotes.

**The error:** `Syntax error at line N near "s"` -- the `s` is the character
immediately after the apostrophe in the offending string.

**Real examples that triggered this:**
- `Install Manus on Peter's Desktop` -- apostrophe in ticket summary
- `The device's WMI may b...` -- apostrophe in summary
- Any O'Brien, O'Sullivan style company name will also hit this

**The fix -- apply to EVERY Postgres CTE node that injects a JSON array:**

```sql
-- BROKEN
FROM json_array_elements('{{ JSON.stringify($json.myArray) }}'::json) val

-- FIXED
FROM json_array_elements('{{ JSON.stringify($json.myArray).replace(/'/g, "''") }}'::json) val
```

The `.replace(/'/g, "''")` runs in the n8n expression evaluator before the
value is sent to Postgres. Doubling single quotes (`''`) is standard Postgres
string escaping.

**Apply this fix to ALL Postgres CTE nodes that inject string data from CW:**
- `Dedup Config` -- `JSON.stringify($json.missingConfigTickets)`
- `Dedup Time` -- `JSON.stringify($json.missingTimeTickets)`
- `Dedup Marked Done` -- `JSON.stringify($json.unmarkedEntries)`
- `Dedup Mismatch` -- `JSON.stringify($json.mismatches)`
- Any future CTE node that injects string data from external sources

**Do not wait for it to break in production.** Patch all of them now.

---

## HTTP Request Node -- Key Settings

### Always Output Data

When an API returns an empty array `[]`, n8n silently drops the item from the
pipeline. It never reaches the next node.

Fix: turn on **Always Output Data** in the HTTP Request node Options.
n8n passes through an empty object `{}` instead of dropping the item.

This was the root cause of the longest troubleshooting session in this workflow.

### Don't Fail on Error

Turn this on alongside Always Output Data for any call that might return
an unexpected response.

### Checking for Empty Responses

When Always Output Data is on and the response was empty, $json becomes `{}`.

Check for it with:
```
={{ Object.keys($json).length === 0 }}
```

Do NOT use `$json.length` -- that only works on arrays, not empty objects.

---

## Scheduled Triggers -- Cron Expression Format

n8n uses a **6-field cron expression**, not the standard 5-field Unix format.
The extra leading field is seconds.

```
SECONDS  MINUTES  HOURS  DAY-OF-MONTH  MONTH  DAY-OF-WEEK
  0-59    0-59    0-23       1-31       1-12      0-7
```

**Always include the seconds field.** Omitting it causes silent misfires:

| Wrong (5-field) | Correct (6-field) |
|---|---|
| `45 16 * * 1-5` | `0 45 16 * * 1-5` |
| `*/5 * * * *` | `0 */5 * * * *` |

**Never use leading zeros on numeric values.**

| Inconsistent | Standardized |
|---|---|
| `0 */5 08-11 * * 1-5` | `0 */5 8-11 * * 1-5` |
| `0 00 09 * * 1-5` | `0 0 9 * * 1-5` |

**Do not mix trigger expression styles** across the same workflow.

**n8n does not reliably support comma-separated hours in a single trigger.**
If you need two specific times in a day, create two separate scheduled trigger nodes.

**Always set timezone in docker-compose.yml:**

```yaml
services:
  n8n:
    environment:
      - GENERIC_TIMEZONE=America/New_York
      - TZ=America/New_York
```

Use the full city-based TZ identifier -- not `EST` or `EST5EDT`.

**Validate expressions before saving:** https://crontab.guru (drop the seconds
field to test the 5-field portion, then mentally prepend `0` for n8n).

---

## Scheduled Triggers -- WSL2 Clock Drift and Sleep Resume

Scheduled triggers fail or fire late when running n8n in a Docker container
inside WSL2. The root cause is WSL2 kernel suspension -- WSL2 pauses its
kernel when Windows sleeps.

**Symptoms:**
- EOD reports firing 30-90 minutes late
- Triggers that never fire after the machine wakes from sleep
- `date` and `hwclock` show correct time by the time you check -- the drift
  already self-corrected before you looked

**The fix: Windows Service (WSL2TimeSyncWatcher)**

A PowerShell Windows Service listens for the Win32 `PowerModeChanged` Resume
kernel event and:

1. Waits 5 seconds for WSL2 to stabilize
2. Syncs WSL2 clock via `hwclock -s`
3. Runs `docker compose down` then `docker compose up -d`
4. Logs every event to `C:\ProgramData\WSL2TimeSyncWatcher\watcher.log`

**Install command (run as Administrator):**
```powershell
.\Install-WSL2TimeSyncWatcher.ps1 -Action Install -ComposeDirectory "C:\path\to\compose"
```

**Check status:**
```powershell
Get-Service WSL2TimeSyncWatcher
Get-Content "C:\ProgramData\WSL2TimeSyncWatcher\watcher.log" -Tail 50
```

**WSL2 cron daemon does not auto-start.** Add to `/etc/wsl.conf`:

```ini
[boot]
command = service cron start
```

---

## n8n Schedule Triggers -- UTC vs Local Time

n8n's `GENERIC_TIMEZONE` environment variable affects how times are DISPLAYED
in the UI but does NOT change the container's system clock. Cron expressions
always evaluate against the container clock.

If the container runs UTC (verify with `docker exec -it n8n date`), write all
cron expressions in UTC:

| Eastern time | UTC cron |
|---|---|
| 8:00 AM - 11:55 AM EDT | `*/5 12-15 * * 1-5` |
| 1:00 PM - 4:55 PM EDT | `*/5 17-20 * * 1-5` |
| 4:45 PM EDT | `45 20 * * 1-5` |

To fix properly, add to docker-compose.yml:

```yaml
environment:
  TZ: America/New_York
```

---

## Luxon -- DST-Safe Eastern Time in Code Nodes

Plain JavaScript `new Date()` and manual UTC offset math breaks twice a year
when Daylight Saving Time changes. Use Luxon instead.

Enable in docker-compose.yml:

```yaml
environment:
  NODE_FUNCTION_ALLOW_EXTERNAL: luxon
```

Luxon is available as a global `DateTime` object in Code nodes -- no require needed:

```javascript
const tz         = 'America/New_York';
const todayStart = DateTime.now().setZone(tz).startOf('day');
const todayEnd   = DateTime.now().setZone(tz).endOf('day');
const workDayEnd = todayStart.set({ hour: 17 });  // 5 PM Eastern

const todayStartUTC = todayStart.toUTC().toISO();
const todayEndUTC   = todayEnd.toUTC().toISO();
```

`America/New_York` handles both EDT (UTC-4) and EST (UTC-5) automatically.
Never hardcode the offset.

---

## IF Node -- Common Mistakes

- `$json.length` works on arrays but NOT on empty objects `{}`
- After Always Output Data, empty responses become `{}` not `[]`
- Use `Object.keys($json).length` to check for empty objects
- Checking array length after CTE: `$json.newTickets.length > 0`
- Or use: `Array.isArray($json.newTickets) && $json.newTickets.length > 0`

---

## JavaScript -- Object Key Type Coercion Gotcha

When building a lookup map with numeric IDs as keys, JavaScript silently
coerces numeric keys to strings when storing them in an object. A lookup
with the original number can return `undefined` even though the data is there.

**Fix:** Always coerce to string explicitly on both sides:

```javascript
// When building the map
ticketMap[String(configId)] = tickets;

// When reading the map
const openTickets = ticketMap[String(cfg.id)] || [];
```

This pattern applies anywhere you build a map from API response IDs and then
look up by those IDs later.

---

## Postgres Node -- Notes

- Host inside Docker is `postgres` (the service name), NOT localhost
- Use `ON CONFLICT DO NOTHING` on inserts for safe idempotent writes
- Use `unnest(ARRAY[...])` to insert multiple rows in a simple insert
- Use a full CTE when you need to filter + insert + return in one operation
- The Postgres node always overwrites $json with its query result
- Postgres cannot be queried directly from a Code node -- use a Postgres node
- COALESCE null results to empty arrays to keep downstream nodes predictable

---

## JSON Body in HTTP Request -- Newline Problem

When sending a POST with a message body containing newlines, do NOT use
the raw JSON editor. When n8n evaluates expressions that produce strings with
real newline characters, the raw JSON becomes invalid.

Always use **Fields Below** mode. n8n serializes and escapes the values
correctly, including newlines, when you provide them as individual fields.

---

## Build Message -- Expression Tip

Always type the message expression manually. Drag and drop from the data
panel omits `.map()` and produces a broken expression like:

```
$json.newTickets(t => ...)   // WRONG -- missing .map
```

Correct:
```
={{ $json.newTickets.map(t => "- Ticket #" + t.id + ": " + t.summary).join("\n") }}
```

---

## Expression Syntax -- Quick Reference

| What you want | How to write it |
|---|---|
| Current node field | `={{ $json.fieldName }}` |
| Field from named node (safe -- 1 item) | `={{ $('Node Name').item.json.fieldName }}` |
| Array length | `={{ $json.myArray.length }}` |
| Map over array | `={{ $json.myArray.map(t => t.id).join(',') }}` |
| Check empty object | `={{ Object.keys($json).length === 0 }}` |
| Check array is non-empty | `={{ Array.isArray($json.arr) && $json.arr.length > 0 }}` |
| Nested array field | `={{ $json.tickets[0].email }}` |
| Stringify for SQL CTE | `={{ JSON.stringify($json.myArray) }}` |

---

## Power Automate Bridge -- Notes

- Use a single shared PA flow -- pass `recipient` as a dynamic payload field
- The PA HTTP trigger URL contains a SAS token -- no Authorization header needed
- The newer direct invoke PA URLs require AAD auth -- use the classic
  `logic.azure.com` style URL which has auth baked into the querystring
- `ChatMessage.Send` and `ChannelMessage.Send` are delegated-only Graph API
  permissions -- app-only auth cannot send Teams messages. PA is the correct
  bridge for sending DMs from automated workflows
- Update the trigger JSON schema whenever you add new payload fields
- Always use **Fields Below** in the HTTP Request node when posting to PA

---

## Power Automate Bridge -- RequestEntityTooLarge

PA's HTTP trigger has a payload size limit. When an Adaptive Card JSON is too
large, the POST from n8n to PA fails silently -- the n8n execution shows
success but no card arrives in Teams. PA flow run history shows the error.

**Fix -- cap ticket rows at a threshold:**
```javascript
const MAX_TICKET_ROWS = 20;

if (activeTickets.length <= MAX_TICKET_ROWS) {
  // render individual rows
} else {
  body.push({
    "type": "TextBlock",
    "text": activeTickets.length + " active tickets -- open ConnectWise for the full list.",
    "size": "Small", "isSubtle": true, "spacing": "Small", "wrap": true
  });
}
```

Always show the status count summary FactSet regardless of ticket count.
Only the individual ticket rows are the variable-length risk.

**Safe thresholds:** Individual ticket rows: cap at 20.

---

## Adaptive Cards -- Teams Compatibility Rules

- `{ "type": "Separator" }` as a standalone body element is NOT supported --
  use `"separator": true` as a property on the following element instead
- `"version": "1.2"` has the broadest Teams compatibility -- prefer over 1.4/1.5
- `Action.OpenUrl` on a `ColumnSet` `selectAction` works -- entire row is clickable
- Color values are semantic names: `Good`, `Attention`, `Warning`, `Accent`,
  `Light`, `Dark` -- not hex values
- Build cards imperatively using `body.push()` -- do not use the spread
  operator inside a JSON object literal passed to `JSON.stringify`
- Test incrementally -- add one section at a time until it breaks, not all at once
- Container `"style": "default"` and `"style": "emphasis"` give alternating
  backgrounds -- use on `i % 2` to visually separate repeated blocks

**Power Automate action:** use "Post your own adaptive card as the Flow bot to a
user" -- NOT "Post adaptive card and wait for a response".

---

## Adaptive Card -- Width Cannot Be Controlled

Teams Adaptive Card width is controlled entirely by Teams and the chat panel
width. There is no `width`, `maxWidth`, or sizing property on the card.

**What you CAN do:**
- Use `"wrap": true` on all TextBlocks to prevent truncation
- Keep FactSet label titles short to give the value column more room
- Use ColumnSet with `"width": "auto"` and `"width": "stretch"` to control
  relative column proportions

**What you CANNOT do:** Set a minimum or maximum card width.

---

## Adaptive Card Debugging -- Missing Cards vs. Failed Cards

**Card JSON too large (PA RequestEntityTooLarge):**
- n8n execution shows success
- PA flow run history shows the error
- Fix: reduce card payload size

**Card JSON invalid (Teams rejects):**
- PA flow run shows success
- Card simply doesn't render in Teams
- Fix: paste card JSON into https://adaptivecards.io/designer to validate

**PA flow not triggered:**
- n8n HTTP call shows a non-200 status
- Check PA flow is active and the trigger URL hasn't expired

---

## WSL / Docker -- Quick Reference

```bash
# Start the n8n stack
cd ~/n8n && docker compose up -d

# Stop the stack
docker compose down

# View live n8n logs
docker compose logs -f n8n

# Access Postgres directly
docker exec -it n8n_postgres psql -U n8n -d n8n

# Check Docker disk usage
docker system df

# Prune unused images and containers
docker system prune -f

# Compact WSL vhdx (run from PowerShell after wsl --shutdown)
Optimize-VHD -Path "$env:LOCALAPPDATA\Packages\CanonicalGroupLimited.Ubuntu_79rhkp1fndgsc\LocalState\ext4.vhdx" -Mode Full
```

---

## Workflow Testing Checklist

Before going live with a scheduled workflow:

1. Run manually with one tech -- confirm Code node returns correct data
2. Confirm Postgres CTE returns correct results
3. Check fingerprint table has rows after a successful run
4. Run again immediately -- confirm same items are suppressed
5. Clear today's fingerprints and run again -- confirm alerts fire again
6. Check Teams DM arrives with correct formatting and recipient
7. Add remaining techs and run -- confirm each gets their own DM
8. Switch Manual Trigger to Schedule Trigger

---

## Merge / Aggregate Architecture -- When and How

Use the Merge + Aggregate pattern when you have multiple parallel branches that
each produce one item per entity and you want to combine them into one item per
entity downstream.

**The pattern:**

```
Set Tech List
  |--> Branch 1 (Code --> Postgres --> Set)
  |--> Branch 2 (Code --> Postgres --> Set)    --> Merge (Append)
  |--> Branch 3 (Code --> Postgres --> Set)          --> Aggregate
                                                           --> Group by Tech (Code)
                                                                 --> Build Card (Code)
```

**Standardize the output shape of every branch:**

```json
{
  "cwIdentifier": "skirsch",
  "displayName":  "Sam Kirsch",
  "email":        "skirsch@databranch.com",
  "sectionKey":   "config",
  "tickets":      []
}
```

**Aggregate does NOT group by field natively.** It collapses ALL items into one
list. Always follow Aggregate with a Code node that groups by your key field.

**Aggregate output shape:** the nested array field name matches whatever you set
in the "Put Output in Field" setting. Access it with `$input.item.json.sections`
-- NOT `$input.all()`.

---

## Postgres JSON Columns -- Parse After Aggregate

When a Postgres CTE returns a JSON column (e.g. `json_agg(...) AS "tickets"`),
n8n receives it as a parsed array. However after passing through Aggregate and
a grouping Code node, the value may become a JSON string again.

Always defensively parse in the consuming Code node:

```javascript
const get = (key) => {
  const s = d.sections.find(s => s.sectionKey === key);
  if (!s) return [];
  let tickets = s.tickets;
  if (typeof tickets === 'string') {
    try { tickets = JSON.parse(tickets); } catch(e) { return []; }
  }
  return Array.isArray(tickets) ? tickets : [];
};
```

---

## Suppression Cheat Codes -- Testing

When you need to force-fire suppressed alerts immediately during testing:

```bash
# Reset time entry alerts (30-min suppression)
docker exec -it n8n_postgres psql -U n8n -d n8n -c \
  "UPDATE cw_timeentry_alerts SET alerted_at = NOW() - INTERVAL '31 minutes';"

# Reset config alerts
docker exec -it n8n_postgres psql -U n8n -d n8n -c \
  "UPDATE cw_config_alerts SET alerted_at = NOW() - INTERVAL '31 minutes' WHERE alerted_on = CURRENT_DATE;"

# Reset idle alerts
docker exec -it n8n_postgres psql -U n8n -d n8n -c \
  "UPDATE cw_idle_alerts SET alerted_at = NOW() - INTERVAL '31 minutes';"

# Reset grace period (first_seen) for time entries
docker exec -it n8n_postgres psql -U n8n -d n8n -c \
  "UPDATE cw_timeentry_alerts SET first_seen = NOW() - INTERVAL '6 minutes';"

# Nuclear option -- wipe everything and start fresh
docker exec -it n8n_postgres psql -U n8n -d n8n -c \
  "DELETE FROM cw_config_alerts WHERE alerted_on = CURRENT_DATE;
   TRUNCATE TABLE cw_timeentry_alerts;
   TRUNCATE TABLE cw_idle_alerts;"
```

---

## SAMSP Bot Architecture -- Command Routing Pattern

SAMSP Bot architecture separates concerns across three layers:

**Layer 1 -- Teams / Power Automate**
One PA flow per tech chat. Watches for `!samsp` keyword. Passes raw message and
tech identity to the BangHandler webhook. Never changes.

**Layer 2 -- BangHandler workflow (n8n)**
Single webhook entry point. Parse Command Code node strips HTML and `!samsp`
prefix, splits command from args. Switch node routes by command name. Each
command wires to an Execute Sub-workflow node.

**Layer 3 -- Sub-workflows (n8n)**
Each command is its own workflow. Receives tech identity and args. Does API
work. Returns Adaptive Card via PA.

**Adding a new command checklist:**
1. Add Switch case in BangHandler
2. Create new sub-workflow with Execute Sub-workflow Trigger
3. Wire Switch output to Execute Sub-workflow node
4. Update help card FactSet
5. No PA flow changes needed

---

## SAMSP Bot -- Workflow Architecture Rule

**Scheduled alert checks belong in the existing 5-minute suite, not as
standalone workflows**, unless there is a genuine structural reason to separate.

**A check belongs in the suite if:**
- It is per-tech (fans out from `Set Tech List`)
- Its result belongs in the same combined card as other alerts
- It follows the Check --> Dedup --> Format Section --> Merge pattern

**A check warrants a standalone workflow only if:**
- It has a fundamentally different schedule
- It targets a different audience entirely
- It requires a different aggregation pattern

**Adding a new check to the suite checklist:**
1. Add Check Code node (parallel from `Set Tech List`)
2. Add Dedup Postgres node
3. Add Format Section Set node (shape: `cwIdentifier`, `displayName`, `email`, `sectionKey`, `tickets`)
4. Bump Merge node input count by 1
5. Wire new Format Section node to the new Merge input
6. Add section renderer to `Build Alert Card`
7. Add sectionKey to `hasIssues` check in `Build Alert Card`

---

## Teams / Power Automate -- HTML in Message Body

When PA's "When keywords are mentioned" trigger fires, the message body content
comes through as HTML, not plain text:

```
<p>!samsp eod</p>
```

Strip HTML tags before parsing in any Code node that receives PA message body:

```javascript
const raw = (body.rawMessage || "").trim().replace(/<[^>]*>/g, '').trim();
```

---

## Teams Bot -- Flow Bot Default Message Problem

The PA Flow bot sends a default "Hi there! I'm here to keep you posted..."
message whenever someone types in the Flow bot chat and there is no matching
flow. This cannot be suppressed without building a proper Teams app bot.

Workaround options in order of quality:
1. Use a dedicated private Teams channel for commands (no DM, shared visibility)
2. Build a proper Azure Bot resource + Teams app (eliminates the problem entirely)

The Azure Bot approach requires:
- Azure subscription (free tier sufficient)
- Azure Bot resource (F0 tier = 10,000 messages/month free)
- Microsoft Entra app registration (free, single-tenant)
- Node.js bot app (thin wrapper -- forwards to n8n BangHandler)
- Teams app manifest + package zip
- Upload to Teams tenant app catalog via Teams Admin Center

Cost for SAMSP Bot use case (5 techs, slash commands only, no AI): $0/month.

---

## Teams Bot -- Infinite Loop from Card Content

If an Adaptive Card sent to a tech's chat contains the trigger keyword (e.g.
`!samsp`) PA will detect it, trigger the flow again, send another card, loop
forever.

**Fix:** Remove the trigger keyword from all card text. Replace `!samsp` in
help cards with a visual substitute like `[ samsp ]`.

---

## Cloudflare Tunnel -- WSL2 Setup

Cloudflare Tunnel exposes n8n to the internet with no inbound firewall ports.

Key files:
- Config: `~/.cloudflared/config.yml`
- Credentials: `/etc/cloudflared/{tunnel-id}.json`
- Service config: `/etc/cloudflared/config.yml` (systemd reads this location)

The service installer requires config at `/etc/cloudflared/config.yml` not
`~/.cloudflared/`. Copy both files there before running `cloudflared service install`.

Tunnel config with path-based routing (bot on 3978, n8n on 5678):

```yaml
tunnel: YOUR_TUNNEL_ID
credentials-file: /etc/cloudflared/YOUR_TUNNEL_ID.json

ingress:
  - hostname: n8n.fragilecaveman.com
    path: /api/messages
    service: http://localhost:3978
  - hostname: n8n.fragilecaveman.com
    service: http://localhost:5678
  - service: http_status:404
```

Order matters -- cloudflared matches top to bottom.

---

## Cloudflare Access -- Zero Trust for n8n

**Browser access:** Cloudflare sends a one-time email code. No passwords.

**API/webhook access:** Use a Service Token. PA flows send two headers:
```
CF-Access-Client-Id:     your-client-id
CF-Access-Client-Secret: your-client-secret
```

**Bot Framework bypass:** Microsoft Bot Framework servers cannot send custom
headers. The `/api/messages` path must bypass Access entirely. Add a Bypass
policy in Zero Trust scoped to URI Path `/api/messages`.

**Policy order matters:** Bypass policy must be above Allow policy in priority.

---

## Promise.all -- Parallel CW API Calls

When a Code node needs multiple independent API calls, use Promise.all to
fire them simultaneously instead of awaiting sequentially:

```javascript
const [notesRaw, configsRaw, timeRaw] = await Promise.all([
  this.helpers.httpRequest({ ... }),
  this.helpers.httpRequest({ ... }),
  this.helpers.httpRequest({ ... })
]);
```

Only use this when calls are truly independent -- if call B depends on call
A's result, keep them sequential.

---

## Debugging in n8n Code Nodes -- No Log Tab on Task Runner

When n8n is configured with the external task runner (v2.14+), `console.log`
output does NOT appear anywhere visible. There is no log tab.

**Workaround: surface debug info in the card itself.**

```javascript
// Inside the function being debugged, build a debug string:
const debugInfo = 'worked:' + ticketsWorked.size
  + ' | mapkeys:' + Object.keys(ticketMap).length
  + ' | sample_type:' + typeof [...ticketsWorked][0]
  + ' | direct:' + JSON.stringify(ticketMap[[...ticketsWorked][0]])
  + ' | ticket_keys:' + JSON.stringify(Object.keys(ticketMap[[...ticketsWorked][0]] || {}));

// Return it alongside other fields:
return { ..., debugInfo };

// Render it in the card:
{ label: "DEBUG", value: curr.debugInfo },
// Comment out the real metric while debugging
```

Remove the debug field and swap back to the production metric once confirmed.

---

## n8n Workflow JSON -- Importable Workflow Generation

Key structural requirements for valid importable JSON:

- Every node needs a unique `id` (UUID format)
- `connections` must use exact node `name` values as keys
- `typeVersion` must match the installed n8n node version
- `credentials` block requires the credential `id` from your specific instance
- `meta.instanceId` should match your instance but n8n tolerates mismatches on import
- `versionId` is a workflow version GUID -- generate any valid UUID for new workflows
- `active: true` activates on import; use `false` for workflows needing review

**Always validate JSON before importing:**
```bash
python3 -m json.tool workflow.json > /dev/null && echo "VALID" || echo "INVALID"
```

---

## SAMSP Stats Scorecard -- Architecture Notes

The `!samsp stats 7` and `!samsp stats 30` commands query CW directly with no
Postgres storage -- all data is live.

**Window math:**
- Current window: today back N days
- Prior window: N days before the current window start
- Both windows query independently so deltas are always apples-to-apples

**Ticket close date approach:**
- Use `ticket.closedDate` (top-level CW field) as the close date
- Use `ticket._info.dateEntered` as the open date (requires `_info` in fields)

**Tickets closed definition:**
- A ticket counts as closed if it appears in the tech's time entries for the
  window AND its current status is in `CLOSED_STATUSES`

**Performance:** For 5 techs over 7 days, approximately 15-20 API calls total.
Runs in 5-8 seconds. Paginated to handle future team growth.

---

## Proxmox / TacticalRMM / phpIPAM -- Notes

*(These sections are retained from earlier work on the cherry.home automation stack.)*

### Proxmox API Error Handling

Always wrap Proxmox API responses in an error check before proceeding:

```javascript
const response = $input.item.json;
if (response.error) {
  return { json: { callError: true, message: response.error.message || JSON.stringify(response.error) } };
}
const data = response.data;
```

### phpIPAM -- Description Column Length

The `description` field on addresses has a limited column length (~64 chars).
Always truncate: `spec.purpose.substring(0, 50)`

### Proxmox Guest-Agent Exec

`POST /api2/json/nodes/{node}/qemu/{vmid}/agent/exec` runs commands inside a
VM through the guest agent. Returns immediately with a `pid` -- poll
`/agent/exec-status?pid={pid}` until `exited: true`.

### TacticalRMM API -- runscript Required Fields

The `runscript` endpoint requires ALL of: `script`, `args`, `timeout`,
`output`, `run_as_user`, `env_vars`. Missing any field causes a 500 with an
HTML Django KeyError response (not a useful API error message).

### TacticalRMM -- Installer Auth Token Expiry

The `--auth` token used by the LinuxRMM installer script expires. When it
expires: `FATA[0000] Installer token has expired.`
Get a fresh token: TacticalRMM UI > Agents > Install Agent > Manual.

### TacticalRMM -- /tmp noexec Blocks Agent Install

Ubuntu cloud images mount `/tmp` with `noexec`. Run the install script from
`/opt` instead to avoid `Permission denied` failures on the meshagent binary.

