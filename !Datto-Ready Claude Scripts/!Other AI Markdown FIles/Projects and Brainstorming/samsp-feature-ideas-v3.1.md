# SAMSP Bot -- Feature Ideas: Current Roadmap
**Databranch Internal | Sam Kirsch**
Last Updated: 2026-04-18 | v3.1

---

## Legend

| Tag | Meaning |
|---|---|
| `[SCHEDULED]` | Runs automatically on a timer |
| `[COMMAND]` | Tech or manager triggers via `!samsp` |
| `[BOTH]` | Has both a scheduled push and an on-demand pull variant |
| `[TECH]` | Primarily for individual techs |
| `[MGMT]` | Primarily for CTO / Service Coordinator |
| `[ALL]` | Useful for both audiences |

---

## v2 Ideas

These carried forward from v2.0. None have been built yet.

---

### 1. Morning Briefing Expansion
`[SCHEDULED]` `[TECH]`

The current 8 AM schedule push is the foundation -- expand it into a full
daily briefing card rather than just a schedule list. In addition to today's
schedule entries (already working), add:

- **Tickets currently In Progress** for this tech -- carry-overs from
  yesterday worth being aware of before the day starts
- **Tickets in Scheduled status assigned to this tech** that do not have a
  schedule resource entry for today -- orphaned scheduled tickets that may
  need SC attention or manual pickup
- **Total ticket count** in their queue by status (Scheduled, In Progress,
  Action Required if applicable)

Framing stays positive and informational -- this is orientation, not a
warning. All ticket numbers are clickable to CW Manage.

---

### 2. Short Note Reminder (Time Entry Quality Check)
`[SCHEDULED]` `[TECH]`

Rolls into the existing 5-minute combined alert as a new check branch. Looks
at schedule resources for today where the tech is listed, the resource entry
is marked Done, and the linked ticket is NOT in Scheduled or In Progress
status. For those tickets, checks the most recent time entry note. If the
note is under 45 characters, sends the tech a one-time-per-ticket-per-day
friendly reminder that their note looks short.

Postgres tracks per tech + ticket + date so it only fires once per ticket
per calendar day. No grace period needed -- the ticket is already done.

Add a new table `cw_shortnote_alerts` (tech_id, ticket_id, alerted_date).

---

### 4. `!samsp mytickets` -- Personal Ticket Queue
`[COMMAND]` `[TECH]`

Returns all open tickets where the requesting tech is the assigned owner,
grouped by status. Specifically useful for finding Scheduled-status tickets
not on today's schedule, or anything sitting in a non-standard state.

Status groups to show: In Progress, Scheduled, Action Required (if any),
other non-closed statuses. Show ticket number, company, summary, and last
updated date. Clickable links throughout. Filter out all terminal statuses.

---

### 7. Unassigned / Unscheduled Ticket Alert
`[SCHEDULED]` `[MGMT]`

Fires every 30 minutes during business hours. Checks for tickets in a
Scheduled status that have no schedule resource entry for any upcoming date
-- set to Scheduled by the SC workflow but no tech was ever dispatched.
Alerts SC with a list: ticket, company, age, current status.

Grace period: 15 minutes. Deferment: 30 minutes after alert.
Same Postgres fingerprint pattern as the 5-minute suite.

---

### 8. Overdue Ticket Report
`[SCHEDULED]` `[MGMT]`

Daily morning push to SC and CTO listing all tickets that have been open
beyond a priority-based age threshold. Thresholds stored in a Postgres
config table (Priority 1: 4 hours, Priority 2: 1 business day, Priority 3:
3 business days, Priority 4: 5 business days). Grouped by priority level,
sorted by age descending within each group. Excludes terminal and Waiting
statuses. Color-coded section headers by priority.

---

### 10. `!samsp whois [ticket]` -- Ticket Ownership and Touch History
`[COMMAND]` `[ALL]`

Returns a lightweight ownership summary card: created by, current owner,
current status, days open, and every tech who has logged time against it
with their hour totals. Useful for handoffs, audits, or when the SC needs
a quick picture of who has been involved without opening CW.

Parallel Promise.all: GET `/service/tickets/{id}`, GET `/time/entries`
aggregated by member, GET `/service/tickets/{id}/notes` for the first note
date.

---

### 11. After-Hours Work Weekly Summary
`[SCHEDULED]` `[MGMT]`

Monday morning push to the CTO summarizing all time entries logged outside
business hours (before 8 AM or after 5 PM Eastern, or on weekends) from
the prior week. Shows tech name, ticket number, company, hours, and time
of entry. After-hours detection logic already proven in EOD report --
this extends the date window to a full week. Useful for overtime awareness
and payroll visibility. DST-safe with Luxon.

---

### 12. Escalation Alert -- Tickets In Progress Too Long
`[SCHEDULED]` `[MGMT]`

Monitors tickets currently In Progress against time thresholds, tiered
by tech seniority. Tech roles/tiers stored in a Postgres config table:

- Interns, Technicians, and Engineers In Progress for 2+ hours trigger
  an alert to senior staff
- Any tech In Progress for 4+ hours triggers an alert to CTO and senior
  engineers regardless of role

Alert fires once per ticket per threshold crossing. Postgres table:
`cw_escalation_alerts` (ticket_id, threshold_minutes, alerted_at).
Deferment: 60 minutes before re-alerting on the same ticket at the same
threshold.

---

### 13. Project Status Digest
`[BOTH]` `[MGMT]`

**Scheduled:** Weekly push (Monday 9 AM) to CTO and SC summarizing all
active projects: project name, percent complete, open project ticket count,
project manager, and a flag if any project ticket has had no activity in
7+ days.

**On-demand:** `!samsp projects` returns the same data on request.

Endpoints: GET `/project/projects` (active only), GET `/project/tickets`
filtered by project ID. Activity check uses most recent time entry date.

---

### 14. Daily Wrap-Up Prompt
`[SCHEDULED]` `[TECH]`

At 4:30 PM, each tech receives a short card with two action buttons:
"Still working" (suppresses the 4:45 EOD alert, extends by 30 min) and
"Run my EOD now" (triggers their EOD report immediately).

Requires Action.Submit card callbacks -- depends on the Teams bot app being
live rather than the Flow bot workaround. Post-Teams-app feature.

---

### 15. `!samsp schedule [date]` -- Schedule for Specific Date
`[COMMAND]` `[TECH]`

Extension of the existing `!samsp schedule` command. Accepts an optional
date argument: `!samsp schedule tomorrow`, `!samsp schedule monday`,
`!samsp schedule 4/21`. Without a date argument, behavior is identical to
current (today). Useful for planning ahead or reviewing what is on deck
after a day off. Luxon handles DST-safe Eastern boundary math.

---

### 16. `!samsp ticket [id]` Enhancements
`[COMMAND]` `[ALL]`

The existing ticket lookup is solid. Targeted additions:

- **Schedule resources** -- show all scheduled resources on the ticket
  (not just the owner), so you can tell who is dispatched at a glance
- **Waiting status age** -- if the ticket is in any Waiting status, show
  how many days it has been waiting and in which status
- **Project linkage** -- if the ticket belongs to a CW project, display
  the project name and a link

Additive sections that only render if the data exists.

---

### 17. Ticket Volume Spike Alert
`[SCHEDULED]` `[MGMT]`

Weekly report identifying companies with a notable spike in ticket volume
compared to their own historical baseline. Query the past 30 days of tickets
per company and compare to the 30-day average from the prior 3 months.
Companies where recent volume exceeds historical average by more than 50%
(configurable) are flagged.

Useful for catching DattoRMM-generated ticket floods, client infrastructure
problems generating repeat calls, or onboarding issues. Results stored in
Postgres to avoid re-alerting on the same company within a 7-day window.

---

### 18. Tech Performance Scorecard -- Scheduled Reports
`[SCHEDULED]` `[MGMT]`

The on-demand `!samsp stats 7` and `!samsp stats 30` commands are built.
This adds the scheduled variants:

- **End of Week** -- Friday at 5 PM, current week vs. prior week
- **End of Month** -- last business day of the month

Monthly and weekly reports also show a year-to-date average as a baseline.
Postgres stores weekly and monthly aggregates so comparisons do not require
re-querying CW for historical data on every run.

Schema: `tech_stats_weekly`, `tech_stats_monthly` with pre-aggregated values.

---

### 19. Board / Queue Health Dashboard
`[SCHEDULED]` `[MGMT]`

Mid-morning daily push (9:30 AM) to the SC giving a full-board operational
snapshot:

- Total open tickets by status
- Per-tech workload: how many tickets each tech has In Progress right now
- Any tickets with no owner assigned
- Any tech with zero In Progress and zero scheduled entries for today
  (availability signal for SC dispatch)

Color-codes techs with high In Progress counts (3+ = yellow, 5+ = red).
Complements the Waiting On commands with a capacity-focused view.

---

### 20. Inbound Email Ticket Monitor
`[SCHEDULED]` `[MGMT]`

Monitors support@databranch.com and service@databranch.com via Microsoft
Graph API. Polls every 10-15 minutes during business hours. For each email
received, queries CW for any tickets created in the past 30 minutes for the
same sender domain or contact. If no matching ticket is found, alerts the SC.
Does not create tickets -- purely observational.

Requires Microsoft Graph API credentials in n8n (app registration with
Mail.Read permission).

---

---

## v3 Ideas

New features identified during the April 2026 build session based on
hands-on API experience and workflow patterns proven in production.
All are read-only (GET) operations. Write operations are tracked separately
in `samsp-future-projects.md` under FP-4.

---

### 21. Stale In Progress Alert
`[SCHEDULED]` `[MGMT]`

Different from the escalation alert (#12). Fires once daily (morning) for
tickets that have been In Progress for more than 2 business days with zero
time entries logged in the past 24 hours. These are tickets that look active
but nobody is actually working -- a tech moved the ticket to In Progress,
got pulled onto something else, and forgot it.

Card shows: ticket number, company, summary, owner, days In Progress, last
time entry date. Sorted by last activity ascending (most neglected first).
No Postgres needed -- pure CW query using `_info.lastUpdated` and status
filter. SC and CTO recipients.

---

### 22. Daily No-Time-Entry Summary (SC View)
`[SCHEDULED]` `[MGMT]`

End-of-day push to SC at 4:45 PM listing any tech who has logged zero hours
for the day. Distinct from the 5-minute idle alert (which fires in real-time
during the day) -- this is a day-end summary for the record. Includes total
hours logged per tech for context so the SC can see the full picture at once.

Simple time entry aggregate query filtered to today's date. No Postgres
tracking needed -- stateless daily snapshot.

---

### 23. `!samsp recent` -- My Recent Tickets
`[COMMAND]` `[TECH]`

Returns the last 10 tickets the requesting tech has logged time against,
regardless of current status, sorted by most recent time entry descending.
Shows ticket number, company, summary, current status, and the date of their
last entry on it. Useful for jumping back to something worked on recently
without searching CW Manage.

Different from `!samsp mytickets` which shows current queue by ownership --
this shows recent activity history regardless of who owns the ticket now.
Single time entries query + batch ticket detail fetch. All patterns proven
in the stats scorecard build.

---

### 24. Agreement Coverage Alert
`[SCHEDULED]` `[MGMT]`

Weekly Monday morning check for tickets in the past 7 days where
`billableOption` is `DoNotBill` or `NoCharge` but the ticket has no agreement
attached (`agreementType` is null or empty). These are tickets being given
away for free without any agreement coverage on record -- worth the SC's
attention for billing hygiene.

Groups by company, shows ticket count and total hours given away. Sorted by
total hours descending. Uses the time entry `billableOption` field confirmed
during the stats scorecard build. No Postgres needed -- pure CW query.

---

### 25. `!samsp away [date]` -- Out of Office Flag
`[COMMAND]` `[TECH]`

Lets a tech flag themselves as out of office for a specific date or date
range. Stores the entry in a Postgres table `tech_away` (tech_id, away_date).
The 5-minute suite checks this table before sending idle alerts -- if a tech
is flagged away for today, suppress all 5-minute alerts for that tech for the
day. Usage: `!samsp away tomorrow`, `!samsp away 4/25`,
`!samsp away 4/25-4/28`.

The SC can also flag a tech on their behalf: `!samsp away lwyant 4/25`.
`!samsp away list` shows all upcoming flagged dates for the team.

Solves the real problem of the idle alert firing all day when a tech is on
PTO, at a client site with no internet, or in an all-day meeting.

---

### 26. `!samsp contacts [company]` -- Company Contact List
`[COMMAND]` `[ALL]`

Returns all active contacts for a company as a scrollable card. Shows name,
title, email, and phone for each contact. Partial company name match with
disambiguation. Useful before a client call when you need to find the right
person to reach but don't want to open CW Manage.

Different from `!samsp company` which gives the ticket/site snapshot with
only the primary/billing contact. This command is specifically for when you
need the full contact directory. GET `/company/contacts` filtered by
`company/id` and `inactiveFlag=false`. All patterns proven in the company
lookup build.

---

### 27. `!samsp configs [company]` -- Configuration List for a Company
`[COMMAND]` `[ALL]`

Returns all active configurations for a company: device name, type,
manufacturer, model, serial number, and status. Partial company name match
with disambiguation. Useful before a site visit or when troubleshooting to
get a quick inventory of what's managed at the client.

Cap results at 20 with a count footer if more exist. Clickable config rows
open the CW configuration record. GET `/company/configurations` filtered by
`company/id` -- the same endpoint proven in the config lookup build (`!samsp
config`), just inverted from asset-first to company-first.

---

### 28. First Response SLA Alert
`[SCHEDULED]` `[MGMT]`

Fires every 15 minutes during business hours. Checks for New or unacknowledged
tickets (any status in `New`, `New (Portal)`, `New - RMM`, `New (RMM)`)
where the ticket was created more than 30 minutes ago and has zero time
entries. These are tickets sitting in a new queue that nobody has touched.

Alert fires to SC with ticket number, company, summary, time since creation,
and priority. Deduplicates via `cw_firstresponse_alerts` (ticket_id,
alerted_at) with a 30-minute re-alert window. Grace period: 30 minutes from
ticket creation so fresh tickets aren't immediately flagged.

Distinct from the idle alert (which is about In Progress techs) and the
unscheduled ticket alert (#7, which is about Scheduled-status tickets).
This catches tickets that haven't even been picked up yet.

---

### 29. `!samsp sla [ticket]` -- SLA Status Check
`[COMMAND]` `[ALL]`

Returns the current SLA status for a ticket: responded time, resplan time,
resolved time, whether each was met or breached, and time remaining until
the next SLA threshold. Uses the `isInSla`, `slaStatus`, `dateResponded`,
`dateResplan`, `resolveMinutes`, `respondMinutes`, and `resPlanMinutes`
fields already present on the ticket record -- no additional API calls needed
beyond the standard ticket fetch.

Useful when a tech or SC needs a quick read on where a ticket stands against
SLA before making prioritization decisions. All data already fetched in the
existing ticket lookup (`!samsp ticket`) -- this is a focused lightweight
variant.

---

### 30. Loaner / Leased Equipment Tracker
`[SCHEDULED]` `[MGMT]`

Weekly Monday digest to SC of all tickets currently in `Loaner` or `Leased`
status, sorted by ticket age descending. Shows ticket number, company,
summary, assigned tech, and days open. Loaner tickets are often opened when
equipment goes out and forgotten until the client returns the item -- this
keeps them visible.

Uses the `Loaner` and `Leased` status names confirmed from the board status
query. GET `/service/tickets` with `status/name="Loaner" OR
status/name="Leased"` and `closedFlag=false`. No Postgres needed -- pure
weekly query. Simple and high value for avoiding lost loaner equipment.

---

*End of Current Feature Roadmap -- v3.1*
