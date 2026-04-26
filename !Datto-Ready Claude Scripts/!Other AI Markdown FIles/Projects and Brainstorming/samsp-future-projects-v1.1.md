# SAMSP Bot -- Future Projects & Parking Lot
**Databranch Internal | Sam Kirsch**
Last Updated: 2026-04-18 | v1.1

This document captures two categories:

1. **Future Projects** -- Ideas that are valid and interesting but require
   significant architecture work, new platform integrations, or are
   intentionally deferred to a later phase.

2. **Parking Lot** -- Ideas that were evaluated and set aside for now,
   with notes on why, in case context changes later.

---

## Future Projects

---

### FP-1. Next Ticket System
`[COMMAND]` `[TECH]`

A dynamic ticket prioritization engine that recommends the best next ticket
for a tech to pick up when they have no scheduled work. Priority factors
would include ticket age, client priority tier, SLA proximity, agreement
type, and tech skill matching. `!samsp next` would return the top 1-3
recommended tickets with a reason for each recommendation. Ties into the
`!samsp mytickets` concept from the current roadmap but adds the intelligence
layer on top.

Requires a priority scoring formula defined in Postgres config, possibly
weighted differently by time of day or remaining capacity in the day.
Complex but extremely high value for reducing SC dispatch burden.

---

### FP-2. Tech Performance Scorecard -- Extended Historical Analytics
`[SCHEDULED]` `[MGMT]`

Extends the current `!samsp stats 7` and `!samsp stats 30` commands and the
scheduled scorecard reports into a full longitudinal analytics platform. Once
weekly and monthly aggregates are stored in Postgres, the following become
possible:

- **Year-to-date averages** as a rolling baseline for all metrics
- **Quarter-over-quarter comparison** cards
- **Team-level aggregates** alongside individual stats
- **On-demand `!samsp stats ytd`** for year-to-date at any time

The Postgres schema designed for Feature 18 should be forward-compatible with
these extensions. Build the aggregation layer right the first time and this
all becomes additive.

---

### FP-3. Multi-Turn Interactive Commands (Action.Submit Framework)
`[COMMAND]` `[BOTH]`

The Teams bot app (once live) enables Adaptive Card Action.Submit callbacks,
which unlock a family of interactive multi-step commands. This is an
infrastructure project before it is a feature project. Key building blocks:

- **Session state in Postgres** keyed by tech + Teams conversation ID
- **BangHandler extended** to receive and route Action.Submit payloads
  alongside text commands
- **Timeout/expiry logic** for abandoned sessions

Once this framework exists, the following commands become straightforward
to build on top of it:

- `!samsp log [ticket]` -- guided time entry with card inputs for hours,
  work type, and notes
- `!samsp close [ticket]` -- prompted resolution note before status change
- Daily Wrap-Up Prompt (Feature 14) -- yes/no card reply
- Any future command that needs confirmation or additional input from the tech

This is the reference architecture for interactive SAMSP commands. Build it
once, use it everywhere.

---

### FP-4. POST / PATCH Action Suite
`[COMMAND]` `[ALL]`

A deliberate phase of development focused on write operations back to CW
Manage. Deferred until the read-only (GET) feature set is mature and the
interactive command framework (FP-3) is established.

**Planned write commands:**

- `!samsp time [ticket] [hours] [note]` -- quick time entry. POST to
  `/time/entries`. Defaults `timeStart` to now, `billableOption` to
  `Billable`, `chargeToType` to `ServiceTicket`. Apostrophe-safe by
  construction since the note goes into the API body, not a SQL CTE.

- `!samsp log [ticket]` -- interactive guided time entry (depends on FP-3
  for the multi-turn card input flow)

- `!samsp status [ticket] [status]` -- quick status change. Shorthand map:
  `woc` → `Waiting on Client`, `wov` → `Waiting on vendor`, `ip` → `In
  Progress`, `done` → `Completed - No Email`, etc. Stored in a JavaScript
  object for easy expansion. PATCH to `/service/tickets/{id}`.

- `!samsp open [company] [summary]` -- open a new service ticket. POST to
  `/service/tickets`. Partial company match with disambiguation, tech as
  owner, board defaulted by company location. Confirmation step before
  submitting. Returns clickable confirmation card.

- `!samsp claim [ticket]` -- take ownership of a ticket. PATCH
  `/service/tickets/{id}` with `owner/identifier`. Returns confirmation card
  showing the ticket and previous owner. Useful during handoffs.

- `!samsp close [ticket]` -- set to Resolved with required resolution note

- `!samsp reassign [ticket] [tech]` -- SC reassignment from chat

- `!samsp vendor [ticket] [number]` -- set the Vendor Ticket Number custom
  field (id: 7) via PATCH with `customFields: [{ id: 7, value: "..." }]`.
  Removes the need to open CW Manage just to record a vendor case number
  after a support call. Custom fields PATCH pattern is new to the codebase
  but straightforward.

All write operations should include a confirmation card step before committing
to CW. All status changes should validate against an allowed-list stored in
Postgres to prevent invalid status names reaching the API.

**Infrastructure requirement:** Write operations require a separate API
credential with PATCH/POST permissions. The current read-only credential
should remain unchanged. Add a second n8n credential for write operations.

---

### FP-5. CW Manage Webhook Receiver (Event-Driven Architecture)
`[BOTH]`

CW Manage supports outbound callbacks via `/system/callbacks`. Registering
n8n as a callback target for specific event types (ticket created, status
changed, priority changed) would replace or supplement the current polling
model with true real-time event handling.

Benefits: immediate alerts without waiting for the next 5-minute poll,
reduced CW API load, event-driven dispatch notifications possible. The
n8n Cloudflare tunnel endpoint is already set up to receive inbound
webhooks -- this is a CW configuration task more than an n8n one.

Deferring because current polling is working well and the CW callback
system has some quirks around reliability and authentication worth
researching before committing to it as a primary architecture dependency.

---

### FP-6. Agreement / Contract Expiry Tracker
`[SCHEDULED]` `[MGMT]`

Weekly digest to CTO of agreements approaching expiry (30/60/90 day windows),
already expired agreements with no renewal, and MRR at risk. This is
genuinely useful but belongs in a Sales/Admin module rather than the
Service Operations module being built now. Revisit when the sales and
account management feature list is developed.

Endpoints: GET `/finance/agreements` with `endDate` range conditions.

---

### FP-7. Inbound Email Intelligence -- Full Pipeline
`[BOTH]` `[MGMT]`

Expands on Feature 20 (Email Ticket Monitor) into a full email intelligence
pipeline:

- **Auto-categorization** of inbound support emails by keyword/sender
  patterns into suggested ticket types and boards
- **Client sentiment flagging** -- emails containing escalation language
  ("unacceptable," "cancel," "frustrated," "management") surface to CTO
  immediately
- **Vendor communication threading** -- service@databranch.com emails
  auto-linked to matching CW tickets by vendor name or ticket number
  referenced in subject lines

Build the basic monitor (Feature 20) first, extend later.

---

### FP-8. AI-Assisted Ticket Triage (`!samsp ask`)
`[COMMAND]` `[TECH]`

Accepts a natural-language issue description and returns: relevant IT Glue
KB articles, similar resolved CW tickets by keyword match, and a suggested
priority level and ticket type. Uses Anthropic API (Claude) or Azure OpenAI.

Deferred pending decision on AI integration strategy. The BangHandler routing
and card output patterns are already in place -- the AI call itself would be
a straightforward HTTP Request node once the go/no-go on AI is made.

---

### FP-9. Smart Duplicate Ticket Detector
`[SCHEDULED]` `[MGMT]`

Daily check for tickets from the same company that are currently open and
have similar summaries. Uses string similarity scoring (word overlap or
Levenshtein distance) computed in a Code node -- no AI needed. Sends a digest
to SC with potential duplicate pairs and links to both.

Deferred because similarity scoring logic adds meaningful code complexity and
the SC workflow already catches many duplicates manually. Worth building once
the core feature set is stable.

---

### FP-10. Datto BCDR Module
`[BOTH]` `[TECH]` `[MGMT]`

A self-contained module for monitoring client Datto backup and continuity
devices. Separate workflow group from the CW service board features.

Planned features:
- `!samsp bcdr [client]` -- last backup status, last successful backup
  timestamp, screenshot verification status for the client's devices
- **Scheduled daily alert** if any Datto device has not had a successful
  backup in 24 hours -- fires to on-call tech and SC
- **Weekly backup health digest** for CTO: all clients, pass/fail summary,
  any devices with recurring failures

Datto has a REST partner API available via the partner portal. Auth is
via API key. This entire module is independent of CW Manage and should
be designed as a parallel module that can share the PA/Teams delivery
infrastructure but runs its own data gathering separately.

---

### FP-11. Huntress Security Module
`[BOTH]` `[TECH]` `[MGMT]`

Integration with Huntress for security incident visibility in Teams.

Planned features:
- `!samsp huntress [client]` -- active incidents, agent count, last scan
- **Scheduled alert** (webhook or poll) when a new Huntress incident is
  created -- fires to SC and on-call tech with severity and affected host
- **Weekly summary** -- new incidents, resolved incidents, protected
  endpoint counts per client

Huntress has a well-documented REST API. High value for MSP security
posture -- incidents surfaced in Teams immediately rather than requiring
someone to check the Huntress portal.

---

### FP-12. CIPP / Microsoft 365 Tenant Module
`[BOTH]` `[MGMT]`

Integration with CIPP for multi-tenant M365 visibility.

Planned features:
- `!samsp m365 [client]` -- license counts, MFA status summary, flagged
  users (sign-in blocked, no MFA enrolled)
- **Scheduled weekly alert** for any tenant where MFA adoption drops below
  a defined threshold or a new unlicensed admin account appears
- CIPP is open-source with a documented API; auth is via Azure app
  registration pointed at the CIPP instance

Pairs naturally with the BCDR and Huntress modules as a "security posture"
channel in Teams for the SC and CTO.

---

### FP-13. DattoRMM Alert Bridge
`[BOTH]` `[TECH]` `[MGMT]`

Foundational integration connecting DattoRMM alerting to the SAMSP Teams
delivery pipeline.

**Inbound:** Register n8n as a DattoRMM webhook target for specific alert
categories (device offline, disk health, patch failure, monitoring threshold
breach). n8n receives the alert, enriches it with the matching CW company
and any open tickets for that device, and delivers a formatted Adaptive
Card to the appropriate tech or SC.

**On-demand:** `!samsp rmm [device]` queries Datto's API for device status,
last check-in, patch status, and recent alerts.

This is probably the single highest-value external integration after CW
Manage itself. DattoRMM generates a significant volume of events and having
them enriched and routed through Teams rather than raw email is transformative
for a service desk workflow.

---

### FP-14. Auvik Network Module
`[BOTH]` `[MGMT]`

- `!samsp auvik [client]` -- network device count, offline devices, last
  topology change, firmware warning count
- **Scheduled alert** when Auvik detects a network device go offline,
  enriched with CW company name and any open network tickets
- **Weekly network health digest** -- devices per client, offline count,
  firmware warnings

Auvik has a REST API with good documentation. Pairs with the DattoRMM and
Huntress modules as part of a comprehensive infrastructure monitoring layer
inside Teams.

---

### FP-15. SonicWall NSM Module
`[BOTH]` `[MGMT]`

- **Scheduled daily alert** if any managed SonicWall reports a high-severity
  security event (IPS/ATP) in the past 24 hours
- `!samsp sonicwall [client]` -- VPN tunnel status, active connections,
  threat event count
- SonicWall NSM REST API accessible via partner portal credentials

---

### FP-16. MailProtector Module
`[SCHEDULED]` `[MGMT]`

- **Weekly email hygiene summary** per tenant: spam catch rate, blocked
  senders, quarantine queue size
- **Alert** if a client's quarantine queue spikes significantly above their
  14-day average -- possible spam campaign or compromised sending account
- CloudFilter API and Shield API accessible via MailProtector partner
  account credentials

---

### FP-17. Scale Computing FleetManager Module
`[BOTH]` `[MGMT]`

- **Scheduled daily check** for any HC3/HC4 cluster with degraded storage,
  failed VM, or offline node -- alert to SC and on-call tech
- `!samsp scale [client]` -- cluster health, VM count, storage utilization
- Scale Computing REST API accessible via FleetManager tenant credentials

---

### FP-18. On-Call Schedule and Escalation Manager
`[BOTH]` `[MGMT]`

Manages an on-call rotation in Postgres (tech ID, on-call start, on-call
end). `!samsp oncall` returns who is currently on-call and through when.
Scheduled after-hours check (every 30 min) looks for new high-priority
tickets and pings the on-call tech. SC updates the rotation via a command.
Eliminates the need for a separate on-call tool for a small team.

---

## Parking Lot (Set Aside)

These ideas were evaluated and deferred for specific reasons. Captured
here for reference if context changes.

---

### PL-1. Note Length / Time Entry Quality (Original Concept)
Replaced by the more targeted Marked Done + Short Note check (Features 2
and 2.5 in current roadmap).

---

### PL-2. Quick Status Change `!samsp status`
POST/PATCH operations consolidated into FP-4. See full write-op suite there.

---

### PL-3. Quick Time Entry `!samsp time`
Same as above -- consolidated into FP-4.

---

### PL-4. Interactive Time Logger `!samsp log`
Multi-turn command depends on Teams bot app (Action.Submit) -- deferred
to FP-3 and FP-4 as the reference implementation for interactive commands.

---

### PL-5. Ticket Reassignment `!samsp reassign`
Consolidated into FP-4.

---

### PL-6. Open/Close Shortcuts `!samsp open` / `!samsp close`
Consolidated into FP-4.

---

### PL-7. Weekly Tech Utilization (BrightGauge overlap)
CTO already has BrightGauge gauges for utilization metrics. The Performance
Scorecard (Feature 18) serves a different, more narrative purpose.

---

### PL-8. CW Manage Webhook Receiver
Moved to FP-5. Polling is working well enough for now.

---

### PL-9. Agreement / Contract Expiry
Moved to FP-6. Belongs in a sales/admin module.

---

### PL-10. AI Ticket Triage `!samsp ask`
Moved to FP-8. No AI integration in current phase.

---

### PL-11. Daily Ticket Age Digest
Low priority -- the team carries many tickets for extended periods by design.
Revisit if queue hygiene becomes a pain point.

---

### PL-12. Write Operations -- `!samsp vendor`, `!samsp claim`
Added in v1.1 from the April 2026 build session. These are new write-op
ideas (`!samsp vendor [ticket] [number]` for custom field updates and
`!samsp claim [ticket]` for quick ownership takeover) that were identified
during hands-on API work. Both consolidated into FP-4 with the full suite.

---

*End of Future Projects and Parking Lot -- v1.1*
