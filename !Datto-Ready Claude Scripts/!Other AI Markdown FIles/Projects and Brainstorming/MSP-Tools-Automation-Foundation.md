# MSP Tools & Automation Foundation

> **Purpose:** Reference document for brainstorming orchestration, automations, and middleware across our full toolstack.
> **Status:** Living document — update as tools evolve or new automations are built.
> **Last Updated:** April 2026

---

## How to Read This Document

Each tool entry covers four things: what the tool is, what API/automation surface is available, what we've already built, and unexploited opportunities worth pursuing. The final section maps the connective tissue and proposes an orchestration philosophy.

Tools with a **★** have the strongest automation surface and should be prioritized in any orchestration design.

---

## Table of Contents

1. [Microsoft 365 / Teams / SharePoint / OneDrive ★](#1-microsoft-365--teams--sharepoint--onedrive-)
2. [CIPP – CyberDrain Improved Partner Portal ★](#2-cipp--cyberdrain-improved-partner-portal-)
3. [ConnectWise Manage (PSA) ★](#3-connectwise-manage-psa-)
4. [DattoRMM ★](#4-dattormm-)
5. [ITGlue ★](#5-itglue-)
6. [DattoBCDR](#6-dattobcdr)
7. [Datto SaaSProtection & SaaSDefense](#7-datto-saasprotection--saasdefense)
8. [Auvik](#8-auvik)
9. [Huntress (EDR / ITDR / SIEM) ★](#9-huntress-edr--itdr--siem-)
10. [Liongard ★](#10-liongard-)
11. [MailProtector (Cloudfilter & Shield)](#11-mailprotector-cloudfilter--shield)
12. [BrightGauge (Reports & Dashboards)](#12-brightgauge-reports--dashboards)
13. [BreachSecureNow (Security Awareness Training)](#13-breachsecurenow-security-awareness-training)
14. [SonicWALL / MySonicWALL / NSM](#14-sonicwall--mysonicwall--nsm)
15. [DUO MFA](#15-duo-mfa)
16. [OpenText / Webroot (AV/DNS)](#16-opentext--webroot-avdns)
17. [HP GreenLake / Aruba InstantOn](#17-hp-greenlake--aruba-instanton)
18. [Meraki Dashboard](#18-meraki-dashboard)
19. [Ubiquiti / UniFi](#19-ubiquiti--unifi)
20. [Datto Networking](#20-datto-networking)
21. [VMware ESXi / HP Servers](#21-vmware-esxi--hp-servers)
22. [Scale Computing / Fleet Manager](#22-scale-computing--fleet-manager)
23. [Automation Platforms (n8n, Power Automate, Power Apps, CW Workflows, CIPP Scripting, Shield Workflows)](#23-automation-platforms)
24. [GitHub (Version Control)](#24-github-version-control)
25. [Cross-Tool Orchestration Map & Priority Targets](#25-cross-tool-orchestration-map--priority-targets)

---

## 1. Microsoft 365 / Teams / SharePoint / OneDrive ★

**What it is:** Core productivity and communication platform for us and most clients. Teams is our primary internal delivery channel for automated reports, alerts, and notifications. SharePoint and OneDrive provide file services; the broader M365 suite covers email, calendar, identity (Entra ID), Intune, and more.

**API / Automation Surface:**
- **Microsoft Graph API** — the single unified REST API for the entire M365 surface. Covers users, groups, mail, calendar, Teams channels/messages/tabs, SharePoint sites/lists, OneDrive, Conditional Access policies, Intune device compliance, licensing, audit logs, and more.
- Authentication via Azure AD app registration (OAuth 2.0); supports both delegated (user context) and application (service-to-service) permission scopes.
- **Graph Change Notifications (webhooks)** — subscribe to real-time events (new message, user change, sign-in event, policy change, etc.) via a registered endpoint.
- **Power Automate** has deep native M365 connectors; also callable via custom HTTP connector for Graph endpoints.
- **Adaptive Cards** — send rich interactive cards to Teams channels; users can click buttons that trigger Power Automate flows or n8n webhooks directly from Teams.
- CIPP wraps much of the multi-tenant Graph surface, so most M365 actions across clients should go through CIPP rather than direct Graph.

**What We've Built:**
- MSP-Bot style reporting bot shipping ConnectWise Manage data into Teams channels
- Power Automate flows surfacing Auvik alert summaries in Teams
- BreachSecureNow phishing campaign summaries delivered to a Teams chart via email parser
- DattoBCDR alert data delivered to a Teams chart via email parser

**Unexploited Opportunities:**
- Adaptive Cards as an in-Teams approval mechanism for ticket escalations, offboarding confirmations, or change management approvals — tech clicks approve/reject inside Teams and it triggers downstream action in CW Manage
- SharePoint Lists as lightweight middle-tier data stores for cross-system correlation (client metadata, onboarding state machine, agreement mapping)
- Graph webhook watching Entra for MFA policy changes, new Global Admin additions, or Conditional Access policy modifications → fire immediate alert to Teams + create CW ticket
- License delta automation: Graph pull of assigned licenses per tenant → compare against CW Manage agreement additions → flag over/under-provisioning as CW tickets
- Automated Teams channel provisioning on client onboarding (new CW company record → create Teams channel, SharePoint site, post onboarding runbook link)
- OneDrive/SharePoint as a scheduled report drop zone (PDFs, CSVs from scripts delivered directly to client-accessible folders)

**Orchestration Role:** The primary human-facing delivery layer for all automated output. Teams is our notification bus; SharePoint/Lists can serve as a shared data store when a full database is overkill. Also the identity and policy source of truth via Entra.

---

## 2. CIPP – CyberDrain Improved Partner Portal ★

**What it is:** Open-source, community-maintained multi-tenant M365 management portal built on PowerShell + Azure Functions + React. Eliminates the need to hop between individual tenant portals. Manages users, licensing, Conditional Access, Exchange, SharePoint, Intune, GDAP relationships, tenant standards, and security baselines across all clients from a single pane. Handled approximately 60% of all Microsoft partner-to-customer access migrations during the DAP → GDAP transition globally.

**API / Automation Surface:**
- Full REST API exposed via Azure Functions — since it's open-source, you can call any CIPP function directly or extend it.
- Authentication via Azure AD app registration tied to your CIPP deployment.
- Callable from n8n, Power Automate (custom connector), or PowerShell.
- Native CIPP scripting allows custom PowerShell execution across tenants triggered from the portal.
- CIPP Standards engine monitors and alerts on tenant configuration drift; alerts can trigger downstream webhooks.

**What We've Built:**
- Day-to-day M365 administration across client tenants
- GDAP relationship management during the Microsoft transition

**Unexploited Opportunities:**
- CIPP as a multi-tenant M365 data source: scheduled pull of MFA status, admin role assignments, Conditional Access policy state, guest accounts → push structured results into ITGlue Flexible Assets automatically
- License reconciliation pipeline: CIPP license data → compare against CW Manage agreement additions → auto-flag mismatches as CW tickets
- Offboarding automation trigger: CW Manage "user terminated" ticket type → call CIPP API to execute offboarding checklist (disable account, revoke sessions, remove licenses, set mail forward, OneDrive access delegation)
- CIPP Standards alert → n8n → CW Manage ticket creation with remediation steps pre-populated
- Weekly Conditional Access compliance scorecard: pull CA policy state via CIPP API → score against baseline → post summary to Teams with per-client status

**Orchestration Role:** The execution arm for all M365 multi-tenant operations. Any automation that needs to make M365 changes across clients should route through CIPP rather than direct Graph, to benefit from CIPP's existing GDAP credential management and audit trail.

---

## 3. ConnectWise Manage (PSA) ★

**What it is:** Our PSA and the operational system of record for tickets, time entries, agreements, contacts, companies, configurations, and billing. Everything we do as an MSP either originates from or should ultimately report back into CW Manage.

**API / Automation Surface:**
- Mature REST API with full Swagger/OpenAPI documentation at developer.connectwise.com.
- Authentication: company ID + public/private API key pair (Base64-encoded Basic auth).
- Full CRUD on: service tickets, companies, contacts, configurations, agreements, time entries, products, opportunities, projects, and more.
- **Callbacks (webhooks):** CW Manage can POST to any external URL when records are created or updated. This is the primary event-driven integration mechanism — new ticket, ticket updated, company created, agreement changed, etc. A callback fires the payload immediately on save.
- Built-in Workflows engine for rule-based internal actions (email, status changes, board routing); limited compared to external tools but useful for simple routing.
- Supports both on-prem and cloud-hosted instances; API endpoint is `api-na.myconnectwise.net` for cloud.
- Rate limits: default page size 25, max 1,000 records per request; pagination required for large datasets.

**What We've Built:**
- MSP-Bot: scheduled CW API pulls → Teams reports (ticket counts, open time, SLA metrics, technician utilization)
- Various PowerShell scripts for ad-hoc reporting against the API

**Unexploited Opportunities:**
- **ITGlue Article Suggestion Engine (the big idea):** CW Callback on new ticket → n8n listener → keyword extraction from ticket title/description → ITGlue API search → POST top matching articles/flexible assets as internal note back into CW ticket. Fully feasible with current APIs from both sides.
- CW Callback → DattoRMM API: new "Slow PC" ticket type → trigger a DattoRMM performance diagnostic component automatically on the affected device
- Agreement reconciliation: scheduled pull of agreement additions → cross-reference with Huntress, DattoRMM, and Webroot seat counts → flag seat mismatches as CW tickets or billing notes
- SLA pre-breach warning: scheduled API poll for tickets approaching SLA threshold → proactive Teams ping to assigned tech before the breach, not after
- Automated time entry anomaly detection: tickets open >N days with zero time logged → alert to service manager
- Configuration auto-population: DattoRMM device inventory + Auvik network scan → CW Configurations via API, with reconciliation to flag devices in RMM that have no CW config record
- New CW company creation → trigger full onboarding workflow in n8n (create ITGlue org, Teams channel, DattoRMM site, send welcome email)

**Orchestration Role:** The system of record and the primary event source. CW Callbacks are the most important triggering mechanism in our entire stack — they allow real-time event-driven automation without polling. Everything that results in work should record back into CW.

---

## 4. DattoRMM ★

**What it is:** Remote Monitoring and Management platform. Deploys lightweight agents to managed endpoints, executes scripts (Components), schedules Jobs, monitors device health, manages patch status, generates alerts, and triggers ticket creation in CW Manage. The hands on the keyboard for endpoint automation.

**API / Automation Surface:**
- Full REST API with Swagger UI documentation (rmm.datto.com/help/en/Content/2SETUP/APIv2.htm).
- Authentication: API URL + API Key + API Secret Key (per-user, generated in Global Settings).
- PowerShell module available on PowerShell Gallery (`DattoRMM` module) — wraps all major endpoints.
- Key objects accessible via API: account info, sites, devices (with full hardware/software inventory), alerts, jobs, audit data, patch status, components.
- **No native outbound webhook to arbitrary URLs** — alerts trigger CW tickets (via native integration) or emails, not direct HTTP POSTs to custom endpoints. Workaround: use the CW ticket creation as the trigger, then chain CW Callback to your automation platform.
- Components (scripts) can be triggered via API using Quick Jobs — this is the "run this script on this device right now" mechanism.

**What We've Built:**
- Large standardized Scripting Kit (DattoRMM component library) — foundational work for endpoint automation and standardization
- Scheduled maintenance components, health checks, and remediation scripts

**Unexploited Opportunities:**
- Device audit pipeline: scheduled API pull of all device data (patch status, disk health, warranty, AV status, software inventory) → normalize and push into ITGlue Flexible Assets and CW Configurations automatically
- Alert enrichment: when DattoRMM creates a CW ticket via native integration, the CW Callback fires → lookup the device in DattoRMM API for full context (last patch, disk health, event log snapshot) → append enriched note to the ticket within seconds of creation
- Billing reconciliation: DattoRMM site device counts → compare to CW agreement additions → auto-flag seat count mismatches monthly
- Component-on-demand trigger: specific CW ticket types (Slow PC, Can't Print, No Internet) → trigger corresponding DattoRMM Quick Job on the affected device automatically, before a tech even opens the ticket
- Patch compliance reporting: scheduled API pull → per-client patch status summary → Teams chart or BrightGauge gauge

**Orchestration Role:** The execution arm for endpoint actions. Data source for device inventory and health; execution target for on-demand script runs. Works best when chained after CW ticket events via Callbacks.

---

## 5. ITGlue ★

**What it is:** Our documentation platform. Stores client configurations (flexible assets), passwords, SOPs, runbooks, network diagrams, and contact information. The intended system of record for "how each client environment is configured." Under Kaseya's 2025 API-first initiative, the ITGlue API expanded significantly — six new endpoints launched in roughly six months, adding full CRUD on documents, document sections, flexible assets, groups, checklists, and password folders.

**API / Automation Surface:**
- REST API at `api.itglue.com` (EU: `api.eu.itglue.com`).
- Authentication: API key generated per admin user (Account > Settings > API Keys). Keys expire after 90 days of inactivity.
- Rate limit: 3,000 requests per 5-minute window.
- Full CRUD now available on: organizations, configurations, flexible assets, passwords and password folders, documents, document sections (individual content blocks within a doc), contacts, locations, groups, and checklists.
- **Incoming webhooks:** ITGlue can receive HTTP POST from external systems to trigger documentation events.
- PowerShell wrapper available on ITGlue's GitHub.
- Document Sections API (new in 2025/2026): allows reading and writing individual sections of a document — enabling granular automated updates without replacing entire documents.

**What We've Built:**
- Standard documentation structure across clients
- Some Liongard-driven Flexible Asset sync (Liongard creates/updates configs it knows about)

**Unexploited Opportunities:**
- **ITGlue Article Suggestion Engine (the big idea):** Retrieve articles/flexible assets matching keywords from CW ticket content → POST top results as internal ticket notes. The ITGlue API supports full-text search and filtering — this is the primary project on the table and is fully buildable today.
- Automated Flexible Asset population from DattoRMM: scripts that collect AD structure, firewall rules, backup configuration, or installed software → POST directly to ITGlue Flexible Assets on a schedule, keeping documentation current without manual effort
- Liongard Pro Sync gap analysis: Liongard's ITGlue Pro Sync (GA 2025) auto-creates configs for servers, workstations, firewalls, switches, WAPs — audit what it covers vs. what still requires custom scripts
- Document staleness alerting: scheduled script reads ITGlue `updated-at` timestamps → flag docs not touched in >90 days → CW ticket or Teams message to responsible tech
- Password expiration tracking: pull passwords with expiration dates → alert 30/7/1 day before expiry via Teams
- Onboarding automation: new CW company → create ITGlue organization, pre-populate document templates appropriate to that client tier, link to CW company record
- Checklist automation (new API): create and complete ITGlue checklists via API during onboarding/offboarding workflows — gives us a documented, auditable task trail

**Orchestration Role:** The knowledge base and documentation brain. Increasingly valuable as both a data target (write enriched data in automatically) and a retrieval source (keyword/search-based article lookup for the ticket suggestion engine). With the 2025 API expansion, ITGlue is now mature enough to treat as a real programmatic data store.

---

## 6. DattoBCDR

**What it is:** On-premises Backup and Continuity appliances deployed at clients running critical servers. Provides agent-based backup with screenshot verification and cloud replication to Datto's cloud for off-site retention and disaster recovery. Covers physical servers, VMware VMs, and Hyper-V VMs.

**API / Automation Surface:**
- Limited documented public API. The Datto partner portal (`portal.dattobackup.com`) has an API surface used by BrightGauge and other integrations, but it is not extensively documented for custom development.
- Primary alert mechanism is outbound email notifications — the current basis of our email parser automation.
- Some partners access backup data programmatically via the Datto XML API (older, unofficial), but reliability and support are limited.

**What We've Built:**
- Power Automate email parser bringing BCDR alert data into a Teams chart

**Unexploited Opportunities:**
- Alert enrichment and severity triage: parse the alert email more deeply — classify by alert type (screenshot verification failure, backup job failure, agent offline, storage warning) → route each type to a different CW ticket board/type/subtype rather than landing everything in one bucket
- Persistent failure trending: store parsed alert data in a SharePoint List → track recurring failures per device over time → flag devices with >N failures in 30 days for proactive engagement
- RPO compliance monitoring: if partner portal API is accessible, pull last-successful-backup timestamps per client → compare against agreed RPO per agreement → flag violations to CW ticket and Teams
- Automated weekly backup health digest: per-client success rate summary → formatted and posted to Teams or delivered to a SharePoint folder as a client-ready PDF

**Orchestration Role:** A monitoring source that currently outputs through email. The email parser is functional but brittle and has no severity differentiation. Priority should be adding structured routing and CW ticket enrichment to make BCDR alerts as actionable as possible.

---

## 7. Datto SaaSProtection & SaaSDefense

**What it is:** SaaSProtection backs up M365 and Google Workspace data (Exchange, SharePoint, OneDrive, Teams, contacts, calendar). SaaSDefense is an email security layer (advanced threat protection, anti-phishing, BEC detection) that sits inline with M365 mail flow.

**API / Automation Surface:**
- SaaSProtection has a REST API accessible via Kaseya/Datto partner credentials — covers backup job status, protected users, storage usage.
- SaaSDefense has limited documented automation surface; management is primarily portal-based with some email alerting.
- Both integrate with CW Manage for ticket creation on job failures.

**What We've Built:**
- Standard portal monitoring; failures go to email/CW tickets via native integration

**Unexploited Opportunities:**
- SaaSProtection API pull: scheduled backup job status per client → post failure/warning summary to Teams and auto-create CW ticket if failure count exceeds threshold
- Seat count reconciliation: SaaSProtection licensed user count → compare against CW agreement additions → monthly flag for billing accuracy
- SaaSDefense threat summary: if email alert output can be parsed, build a similar Power Automate parser to what we have for BreachSecureNow and BCDR — weekly threat summary chart delivered to Teams
- Onboarding checklist: when new CW company is created, validate that both SaaSProtection and SaaSDefense are provisioned before closing onboarding ticket

**Orchestration Role:** Managed as monitoring sources with CW ticket integration. Automation opportunity is primarily in richer alert routing and billing reconciliation.

---

## 8. Auvik

**What it is:** Cloud-based network monitoring and management platform. Provides automated network discovery, topology mapping, device configuration backup, traffic analysis, and alerting for all managed network devices (routers, switches, firewalls, WAPs). Integrates natively with CW Manage for bi-directional ticket sync and can push inventory to CW Configurations.

**API / Automation Surface:**
- REST API with API key + username authentication (API Access Only user role required).
- Multi-tenant architecture: single parent instance auto-discovers child tenants.
- API covers: tenants, networks, devices, interfaces, alerts, configurations, statistics, and more.
- Native integrations: CW Manage (bi-directional ticket sync, configuration sync), Liongard, ITGlue, Teams alert notifications.
- Alerting can POST to Teams channels natively (already in use).

**What We've Built:**
- Power Automate flow that collects and summarizes Auvik alerts → delivers to Teams

**Unexploited Opportunities:**
- Alert enrichment: when Auvik creates a CW ticket → CW Callback → look up the device in Auvik API → append network topology context, last config backup timestamp, and traffic stats to the ticket note
- Configuration drift detection: compare Auvik-stored device configs over time → alert when a device config changes unexpectedly (Auvik stores config backups — this is a built-in feature that could drive proactive CW tickets)
- Device warranty/EoL tracking: pull device model data from Auvik API → cross-reference manufacturer EoL databases → flag aging devices to CW ticket or Teams for client conversations
- Network inventory reconciliation: Auvik discovered devices → compare against CW Configurations and ITGlue → flag devices present in Auvik but missing from documentation
- Monthly network health digest per client: Auvik API pull → format summary of uptime, alert counts, bandwidth trends → deliver to Teams or SharePoint as client-facing report

**Orchestration Role:** The network visibility layer. Strong native integrations already handle basic ticket creation and Teams alerting. Automation value is in enrichment (adding Auvik data to CW tickets automatically) and cross-tool inventory reconciliation.

---

## 9. Huntress (EDR / ITDR / SIEM) ★

**What it is:** Managed security platform purpose-built for SMBs and MSPs. Includes Managed EDR (endpoint detection and response with 24/7 SOC), ITDR (Identity Threat Detection and Response — monitors M365/Entra for identity-based attacks), and Managed SIEM (log aggregation, correlation, and threat hunting). The SOC handles triage and provides remediation guidance; we execute.

**API / Automation Surface:**
- REST API at `api.huntress.io/v1/` with Basic auth (Base64 encoded API key + secret).
- Full API documentation: `api.huntress.io/docs`
- API covers: organizations, agents, incident reports, escalations, billing reports, summary reports, external recon data, user management, and subscription management.
- **Write APIs now available:** Can resolve escalations and approve/reject incident report remediations via API — not just read-only anymore.
- New (2025/2026): reseller subscription management endpoints, external recon port data endpoints, Azure Event Hub SIEM integration.
- Client-side agent health API: `http://localhost:24799/health` — callable from DattoRMM scripts to verify agent status per endpoint.
- PowerShell module available on GitHub (`PSHuntress`).
- Liongard Huntress Inspector auto-discovers all client orgs via a single parent API credential.

**What We've Built:**
- Standard portal monitoring; SOC handles incident triage and we respond to escalations

**Unexploited Opportunities:**
- Agent health monitoring via DattoRMM: schedule a DattoRMM component that calls the local Huntress agent health API → alert if unhealthy → create CW ticket automatically. Ensures agent coverage is verified, not assumed.
- Incident report API → CW ticket automation: when Huntress raises an incident report, automatically create or enrich a CW ticket with the full incident context (affected device, recommended remediation, severity)
- Billing reconciliation: Huntress API billing report → compare licensed agent count per organization against CW agreement additions → monthly mismatch report
- ITDR alert → CIPP action: Huntress ITDR detects suspicious M365 sign-in → trigger CIPP to revoke sessions and enforce MFA re-registration for the affected user automatically
- Weekly security posture summary: Huntress API pull (agents, incidents, ITDR alerts) per client → format as a Teams chart or BrightGauge gauge for internal operations visibility
- SIEM alert routing: Huntress SIEM events → webhook or API → CW ticket creation for high-severity findings that need ticket-tracked remediation

**Orchestration Role:** The security detection layer. With the expanded write API, Huntress can now be both a data source and an action target — this unlocks automated remediation workflows. The SOC is the human backstop; automation should handle ticket creation, agent health validation, and billing reconciliation.

---

## 10. Liongard ★

**What it is:** Configuration Change Detection and Response (CCDR) platform. "Inspectors" use API, SSH, and agent-based methods to continuously capture configuration snapshots of every system we manage — M365, Active Directory, firewalls, switches, servers, SaaS tools, and more. Detects when configurations change, surfaces timeline views, and can alert or create tickets when changes are detected. The 2025 LiongardIQ evolution added AI-powered asset summaries and natural-language asset search.

**API / Automation Surface:**
- Full REST API covering environments, inspectors, systems, metrics, alerts, and timelines.
- **Webhook support for alerts (new in 2025):** Liongard can POST signed JSON payloads to external URLs the moment a new alert is generated — currently API-managed only (no UI yet). This is a significant capability for event-driven automation.
- Integrates natively with: CW Manage (ticket creation on alerts), ITGlue (Flexible Asset creation/updates via Pro Sync, GA 2025), BrightGauge.
- ITGlue Pro Sync (GA 2025) automatically creates and updates ITGlue configuration records for servers, workstations, firewalls, switches, WAPs, storage, and printers.
- Liongard alert webhooks can trigger Rewst, n8n, Power Automate, or any SOAR/RPA platform.

**What We've Built:**
- Standard inspector deployment across client environments
- Liongard → ITGlue Flexible Asset sync (native integration)
- Liongard → CW Manage alert tickets (native integration)

**Unexploited Opportunities:**
- Alert webhook → n8n → enriched CW ticket: Liongard detects a firewall config change → webhook fires → n8n checks ITGlue for the device's last known config baseline → posts enriched note to the auto-created CW ticket (what changed, what it was before, what ITGlue says it should be)
- Change detection → CIPP remediation: Liongard detects a Conditional Access policy change in M365 → trigger CIPP to revert or flag it if it violates baseline
- Expiration tracking: Liongard tracks SSL certificate expiration, domain registration, and MFA app password expiration — wire these alerts to CW tickets with lead time appropriate for each (30/14/7 day warnings)
- ITGlue Pro Sync gap audit: periodically compare what Liongard has synced into ITGlue against our expected documentation standards — flag organizations with missing config types
- LiongardIQ natural-language queries as a future ticket enrichment source: "what is the firewall config for this client" → AI-powered Liongard response injected into a CW ticket note

**Orchestration Role:** The configuration intelligence layer. Liongard sees everything that changes across all client environments and has the API and webhook surface to act on it in real time. The new alert webhooks make it a first-class event source for our automation platform. Critically, it's the bridge between raw system state and documented state in ITGlue.

---

## 11. MailProtector (Cloudfilter & Shield)

**What it is:** MSP-exclusive email security platform. **Cloudfilter** is a gateway-based spam/virus/phishing filter that works with any email platform, including M365. **Shield** is a newer zero-trust email security product built exclusively for MSPs — it uses behavioral analysis and per-user communication patterns to build a dynamic "circle of trust," blocking threats before they reach the inbox. Shield was named MSP Today 2025 Product of the Year. Both products include Shield Workflows for rule-based email handling automation.

**API / Automation Surface:**
- MailProtector offers a partner API for provisioning and management (domain management, user sync, quarantine management).
- Shield Workflows: rule-based email traffic control within the product — useful for automating quarantine decisions, routing, and user notifications but scoped to email actions.
- Primary integration path for external systems is via email alerting (quarantine notifications, threat summaries) and the partner portal.
- Limited public webhook or REST API documentation for custom external automation compared to other tools in our stack.

**What We've Built:**
- Standard deployment and management via partner portal

**Unexploited Opportunities:**
- Quarantine summary automation: if MailProtector provides email digest data via API or structured email — build a Power Automate parser to surface high-volume quarantine events (potential attack indicators) to a Teams channel
- Domain provisioning automation: new client onboarding workflow → call MailProtector API to provision domain filtering, set MX records, configure DMARC — eliminate manual portal steps
- Threat event correlation: MailProtector detects phishing attempt targeting a client → cross-reference with Huntress ITDR to see if the same user had a suspicious M365 sign-in → combined alert to Teams
- User sync automation: keep MailProtector user directories in sync with M365 users via scheduled CIPP pull → MailProtector API update — prevents stale accounts and ensures accurate protection

**Orchestration Role:** A protection layer that is relatively self-contained. Automation opportunities are primarily in provisioning (onboarding) and alert correlation with the broader security stack (Huntress, CIPP). Shield Workflows handle internal email logic.

---

## 12. BrightGauge (Reports & Dashboards)

**What it is:** Business intelligence and reporting platform purpose-built for MSPs, now rebranded as ConnectWise Reports & Dashboards. Aggregates data from 60+ native integrations (CW Manage, DattoRMM, Auvik, ITGlue, Liongard, Huntress, and more) into real-time dashboards, automated client reports, and goal tracking. Key features: pre-built gauge library (4,200+ templates), Snapshots (lightweight data warehousing for historical trending), scheduled client report delivery, and a new AI-powered Sidekick chatbot for natural-language data queries via Teams.

**API / Automation Surface:**
- BrightGauge itself is primarily a data consumption platform — it pulls from connected data sources via their APIs.
- No significant inbound API for pushing custom data into BrightGauge from external sources (this is a limitation — it does not function well as a data target for custom scripts).
- Custom data sources can be added via direct database connections in some configurations.
- Native integration with CW Manage is the deepest connection — 202+ pre-built gauges for cloud CW.
- Sidekick (AI chatbot, early access): natural-language queries against BrightGauge data sources, delivered via Teams — a significant emerging capability for operations insights.

**What We've Built:**
- Internal operational dashboards (ticket counts, SLA performance, open time, technician utilization)
- Some client-facing report automation

**Unexploited Opportunities:**
- Expand native integrations: ensure Auvik, Huntress, Liongard, and DattoRMM are all connected — these exist as native integrations and provide out-of-the-box operational visibility without custom work
- Client-facing automated reports: schedule and automate monthly client reports (patch status, backup success rate, security incident count, ticket summary) — BrightGauge delivers these automatically via email on schedule
- Snapshots for trending: enable Snapshots on key metrics (daily open ticket count, patch compliance rate, backup failure count) to build historical trend charts — useful for QBRs
- Sidekick adoption: as the Teams-based AI query capability matures, position it as an internal ops tool where techs can ask "how many open P1 tickets does ClientX have this week" without opening BrightGauge
- SLA and goal tracking: configure BrightGauge Goals against SLA targets → automatic notification to service manager when approaching threshold

**Orchestration Role:** The metrics and visibility layer. Primarily a data consumer, not a trigger source or action target. Best used as the dashboard and reporting output for data that flows through our other automation. Its value multiplies when more of our tools are connected as data sources.

---

## 13. BreachSecureNow (Security Awareness Training)

**What it is:** Cybersecurity awareness training platform for end users. Delivers phishing simulations, video training modules, dark web monitoring reports, and security risk scoring for client organizations. Helps us demonstrate security value to clients and meet cyber insurance training requirements.

**API / Automation Surface:**
- BSN has a partner API for organizational management and reporting data.
- Primary data output mechanism is email-based reports and alerts — the basis of our current automation.
- Phishing campaign result data and training completion data are accessible via API and reports.

**What We've Built:**
- Power Automate email parser → Teams chart showing phishing campaign click rates and training completion summaries

**Unexploited Opportunities:**
- Expand Teams reporting: add training completion rates and dark web hit counts alongside phishing click rates — single consolidated BSN security posture card per client
- High-risk user alerting: BSN tracks users who repeatedly fail phishing simulations → when a user fails N times, auto-create a CW ticket for follow-up coaching conversation
- QBR data pull: BSN security risk score per client → pull via API → incorporate into BrightGauge client report or automated QBR document
- Onboarding trigger: new client onboarding → BSN org creation + initial phishing baseline campaign launch → automated

**Orchestration Role:** A compliance and security awareness data source. The email parser approach works; expanding it with API-driven data and high-risk user alerting would increase actionability.

---

## 14. SonicWALL / MySonicWALL / NSM

**What it is:** SonicWALL next-generation firewalls deployed at client sites for perimeter security, SSLVPN, and network segmentation. Managed via MySonicWALL (cloud licensing and registration portal) and NSM (Network Security Manager — centralized policy management and monitoring for multiple SonicWALL devices).

**API / Automation Surface:**
- **NSM REST API:** Available for programmatic access to device status, policy management, and reporting across managed SonicWALLs.
- **SonicOS API:** Individual SonicWALL devices expose a local REST API for configuration management (firmware 7.x and later) — useful for direct device queries.
- MySonicWALL has partner portal access but limited public API documentation.
- Liongard has a SonicWALL inspector that captures configuration snapshots and detects changes.

**What We've Built:**
- Standard management via NSM; Liongard inspector captures configs

**Unexploited Opportunities:**
- VPN usage reporting: NSM or SonicOS API pull of active/historical SSLVPN session data → Teams summary or BrightGauge gauge showing client VPN utilization
- Firmware compliance tracking: pull firmware versions via NSM API → compare against current recommended version → flag out-of-date devices to CW ticket or Teams
- Liongard change detection → NSM correlation: Liongard detects firewall rule change → query NSM API for the current ruleset → post diff to CW ticket note automatically
- SSLVPN DUO integration health: periodically verify that DUO is enforced on SSLVPN for all SonicWALL clients via SonicOS API → flag any device where DUO config has drifted

**Orchestration Role:** A security boundary device that benefits from configuration monitoring (Liongard) and change-driven alerting. The NSM API is underutilized and could drive firmware compliance and change detection workflows.

---

## 15. DUO MFA

**What it is:** Cisco DUO provides multi-factor authentication for Windows login, RDP, SSH/Unix, and SonicWALL SSLVPN across managed clients. Acts as a critical zero-trust enforcement layer — even if credentials are compromised, DUO blocks unauthorized access.

**API / Automation Surface:**
- **DUO Admin API:** Full REST API for user management, group management, authentication log retrieval, device enrollment status, and policy management.
- Authentication: Admin API integration key + secret key (per DUO account).
- Huntress SIEM can ingest DUO authentication logs via the API for correlation and threat detection.
- Liongard has a DUO inspector that captures enrollment status and configuration.

**What We've Built:**
- Standard deployment; Huntress SIEM ingests DUO logs for correlation

**Unexploited Opportunities:**
- Enrollment compliance reporting: DUO Admin API pull of user enrollment status per client → flag users without MFA enrolled → CW ticket or Teams alert with user list for remediation
- Failed authentication alerting: pull DUO auth logs for high failed-auth rates → alert to Teams + create CW ticket if threshold exceeded (potential credential stuffing indicator)
- Offboarding validation: during user offboarding workflow → call DUO Admin API to verify user is removed/disabled in DUO — add to offboarding checklist automation
- New user onboarding: when CIPP creates a new M365 user, trigger DUO Admin API to pre-enroll or send enrollment email automatically

**Orchestration Role:** A security enforcement layer with a strong API. Most valuable as a data source for compliance reporting (who has MFA, who doesn't) and a validation step in onboarding/offboarding workflows.

---

## 16. OpenText / Webroot (AV/DNS)

**What it is:** Endpoint antivirus and DNS protection used for a portion of the client base (some clients use Huntress Managed AV/EDR instead). Webroot provides lightweight cloud-managed AV and DNS filtering via the SecureAnywhere platform.

**API / Automation Surface:**
- Webroot Unity API: REST API for management — device status, site management, threat reports, license management.
- Authentication via API client credentials (OAuth 2.0 client credentials flow).
- Liongard has a Webroot inspector for configuration change detection.

**What We've Built:**
- Standard deployment and portal monitoring

**Unexploited Opportunities:**
- Seat count reconciliation: Webroot API pull of licensed/active agents per site → compare against CW agreement additions → monthly billing accuracy flag
- Threat detection reporting: pull threat event data via Unity API → weekly summary per client to Teams or BrightGauge
- Agent health monitoring: flag devices where Webroot agent is installed but not reporting → create CW ticket for remediation
- Stack rationalization tracking: as clients migrate to Huntress, track which clients still have Webroot agents active → maintain transition status in ITGlue or a SharePoint List

**Orchestration Role:** A protection and compliance data source. Billing reconciliation and agent health monitoring are the primary automation targets.

---

## 17. HP GreenLake / Aruba InstantOn

**What it is:** HP GreenLake is HP's cloud management portal; we use it specifically for managing Aruba InstantOn switches deployed at some client sites. InstantOn provides simple cloud-managed switching for smaller client environments.

**API / Automation Surface:**
- Aruba InstantOn has a cloud API for device management and status monitoring.
- HP GreenLake has broader API capabilities across HP infrastructure products.
- Generally lighter API surface compared to enterprise-grade Aruba or Meraki.

**What We've Built:**
- Standard management via GreenLake portal

**Unexploited Opportunities:**
- Device status monitoring: pull switch port status and alerts → route to CW ticket creation or Teams alert when a port goes down
- Firmware compliance: pull InstantOn firmware versions → flag devices below current recommended version
- Inventory reconciliation: GreenLake device list → compare against ITGlue configurations → flag undocumented devices

**Orchestration Role:** A lighter-weight managed network device tier. Monitoring and inventory reconciliation are the primary opportunities.

---

## 18. Meraki Dashboard

**What it is:** Cisco Meraki cloud-managed networking — used for clients with Meraki infrastructure (primarily MX security appliances, MS switches, MR access points). Managed via the Meraki Dashboard cloud portal.

**API / Automation Surface:**
- **Meraki Dashboard API:** Excellent REST API with full network management capabilities — organization management, device status, client data, network health, configuration, alerts, and more.
- Authentication: API key in request header (X-Cisco-Meraki-API-Key).
- **Webhooks:** Meraki can POST alert payloads to a configured HTTP server when network events occur — device down, configuration changes, security alerts, etc.
- Multi-org support: single API key with access to all managed organizations.

**What We've Built:**
- Standard management via Meraki Dashboard

**Unexploited Opportunities:**
- Meraki webhook → CW ticket: configure Meraki webhooks to POST to an n8n or Azure Function endpoint → create enriched CW tickets for network events (device offline, VPN down, high utilization)
- Device inventory sync: Meraki API device list → push to CW Configurations and ITGlue automatically for all Meraki orgs
- Client usage reporting: Meraki API client data → identify rogue devices, bandwidth hogs, or new unrecognized devices → alert to Teams
- Firmware compliance: pull Meraki device firmware versions via API → flag non-current firmware to CW ticket
- Configuration change detection: complement Liongard's Meraki inspector with a custom webhook that fires immediately on config changes (faster than Liongard's scheduled inspection cadence)

**Orchestration Role:** Meraki has one of the strongest network device APIs in our stack. Webhooks make it a real-time event source. Priority should be wiring Meraki webhooks into our automation platform for CW ticket creation and inventory sync.

---

## 19. Ubiquiti / UniFi

**What it is:** UniFi switches and access points deployed at some client sites for LAN/WiFi. Managed via UniFi Network Application (self-hosted or UniFi Cloud). We do not use UniFi for firewalls or SD-WAN — only switching and wireless.

**API / Automation Surface:**
- UniFi has an unofficial REST API (the UniFi Controller/Network Application API) that is widely used in the community but not officially documented by Ubiquiti.
- UniFi Cloud (unifi.ui.com) has a more formal API via the Site Manager API.
- Limited native webhook capability; most automation relies on polling.
- Auvik can monitor UniFi devices via SNMP.

**What We've Built:**
- Standard management via UniFi Network Application or UniFi Cloud

**Unexploited Opportunities:**
- Device health monitoring via Auvik: leverage Auvik's existing UniFi device monitoring to drive CW ticket creation on port/AP events rather than building custom UniFi API polling
- Inventory reconciliation: UniFi API device list → compare against CW Configurations and ITGlue → flag gaps
- Firmware reporting: pull device firmware via UniFi API → flag devices on older firmware → CW ticket or Teams alert

**Orchestration Role:** A lighter automation target given unofficial API status. Leverage Auvik as the monitoring layer for UniFi devices rather than building direct API integrations.

---

## 20. Datto Networking

**What it is:** Datto's cloud-managed networking appliances (routers/SD-WAN devices, switches, WAPs) deployed at some client sites. Managed via the Datto Networking portal (formerly Datto Networking DNX/DNA series).

**API / Automation Surface:**
- Datto Networking has a partner API accessible via the Datto partner portal.
- Auvik has a native Datto Networking integration for visibility.
- Alert notifications primarily via email and portal.

**What We've Built:**
- Standard management via Datto Networking portal; Auvik monitoring

**Unexploited Opportunities:**
- Alert routing: Datto Networking alerts → email parser or API poll → enriched CW ticket creation (similar to BCDR pattern)
- Firmware compliance: API pull of device firmware versions → flag out-of-date devices
- Inventory sync: device list → CW Configurations and ITGlue

**Orchestration Role:** Managed through Auvik for monitoring. Automation opportunities follow the same pattern as other network device tiers (inventory sync, firmware compliance, alert routing).

---

## 21. VMware ESXi / HP Servers

**What it is:** HP ProLiant servers running VMware ESXi hypervisor at client sites with on-premises server infrastructure. Hosts virtual machines for critical workloads. Managed via vCenter (where deployed) or direct ESXi host management.

**API / Automation Surface:**
- **VMware vSphere/ESXi API:** REST API (vSphere 7.0+) and SOAP API (legacy) for VM management, host health, datastore status, and snapshot management.
- **HP iLO (Integrated Lights-Out):** HP server management REST API for hardware health — CPU, memory, disk, power, temperature, firmware.
- Liongard has ESXi and VMware inspectors for configuration change detection.
- DattoBCDR protects VMs at the hypervisor level.

**What We've Built:**
- Standard monitoring; DattoBCDR backs up VMs; Liongard inspects ESXi configs

**Unexploited Opportunities:**
- VM snapshot monitoring: scheduled ESXi API query → flag VMs with snapshots older than N days → CW ticket (old snapshots degrade performance and consume storage)
- HP iLO health monitoring: scheduled iLO API query → surface hardware warnings (degraded RAID, failed HDD, high temps) → CW ticket creation before the server fails
- Datastore capacity alerting: ESXi API → flag datastores above 80% utilization → Teams alert and CW ticket
- ESXi host firmware tracking: pull ESXi build version and HP firmware via iLO → compare against recommended → flag to CW ticket

**Orchestration Role:** On-premises infrastructure that benefits from proactive health monitoring via direct API queries. iLO hardware health and ESXi snapshot/capacity monitoring are the highest-value automation targets.

---

## 22. Scale Computing / Fleet Manager

**What it is:** Scale Computing HyperCore (SC//HyperCore) is a hyperconverged infrastructure platform combining compute, storage, and virtualization on Scale Computing nodes. Fleet Manager is Scale's cloud-based multi-site management platform. An alternative to VMware ESXi for clients who want simpler hyperconverged infrastructure.

**API / Automation Surface:**
- Scale Computing HyperCore has a REST API for VM management, cluster health, storage status, and replication.
- Fleet Manager provides a centralized API surface for multi-site Scale environments.
- DattoBCDR can protect Scale VMs for backup continuity.

**What We've Built:**
- Standard management via Scale Fleet Manager portal

**Unexploited Opportunities:**
- Cluster health monitoring: Scale API poll → flag degraded nodes, storage warnings, or replication failures → CW ticket
- VM snapshot and capacity monitoring: same pattern as ESXi — old snapshots and near-full storage are common issues
- Fleet Manager multi-site status summary: scheduled API pull → Teams digest of all Scale cluster health across clients

**Orchestration Role:** Similar to ESXi — on-premises infrastructure where proactive health polling via API delivers the most value.

---

## 23. Automation Platforms

These are the execution environments where our workflows and integrations actually run.

### n8n
Self-hosted or cloud workflow automation with a visual node-based editor. Supports HTTP, webhooks, REST API calls, conditional logic, loops, data transformation, and 400+ built-in integrations. Our most flexible automation platform — use it for complex multi-step workflows that Power Automate can't handle cleanly or where licensing costs matter. Best choice for the CW Callback → ITGlue keyword lookup → CW note injection workflow.

### Power Automate (Flows)
Microsoft's workflow automation, deeply integrated with M365. Best for anything that touches Teams, SharePoint Lists, Outlook, or M365 services natively. We've already built several flows here. Good for email parsers, Teams notification delivery, and M365-native triggers. Licensing is part of M365.

### Power Apps
Low-code application builder within M365. Useful for building lightweight internal portals — tech-facing forms, onboarding dashboards, or client intake tools — that connect to SharePoint Lists or CW Manage via API. Has not been fully exploited yet.

### ConnectWise Manage Workflows
Built-in rule engine within CW Manage — handles ticket routing, status changes, automated email notifications, and SLA management internally. Good for simple CW-internal logic; CW Callbacks are needed for anything that needs to reach outside CW.

### CIPP Scripting
Native PowerShell execution within CIPP, running in the context of the CIPP service account with GDAP access to all client tenants. Uniquely powerful because it can perform multi-tenant M365 actions at scale without per-tenant credential management.

### Shield Workflows (MailProtector)
Rule-based email traffic control within Shield. Scoped to email actions — quarantine decisions, routing rules, notification triggers. Not a general-purpose automation tool.

**Platform Selection Guidance:**

| Trigger / Use Case | Best Platform |
|---|---|
| CW Callback → external action | n8n |
| M365 / Teams / SharePoint trigger | Power Automate |
| Email parser / parsing alerts | Power Automate |
| Multi-tenant M365 actions | CIPP Scripting |
| Internal tech-facing portal/form | Power Apps |
| Simple CW-internal routing | CW Workflows |
| Long-running or complex multi-step | n8n |
| Quick script execution on endpoints | DattoRMM Component |

---

## 24. GitHub (Version Control)

**What it is:** Version control for our PowerShell Scripting Kit, DattoRMM components, automation workflow definitions, and markdown documentation (including files like this one). Central repository for institutional scripting knowledge.

**API / Automation Surface:**
- GitHub REST API and webhooks — can trigger actions on push, PR merge, or release events.
- GitHub Actions for CI/CD — could automatically push updated DattoRMM components to the RMM on merge, or validate script syntax on commit.
- Stores AI instruction markdown files (system prompts, context docs) for consistent AI-assisted workflows.

**Unexploited Opportunities:**
- GitHub Actions → DattoRMM API: on merge to main for a component script, automatically push/update that component in DattoRMM via API — eliminates manual copy-paste deployment
- GitHub as a structured knowledge base: beyond scripts, use it to store standardized client runbooks that can be referenced by the ITGlue Article Suggestion engine or other automation
- Script version tracking: enforce versioning standards (already in our PS standards) with a GitHub Action lint/check on push

**Orchestration Role:** Source of truth for all automation code. The deployment pipeline from GitHub to DattoRMM is the most impactful near-term opportunity here.

---

## 25. Cross-Tool Orchestration Map & Priority Targets

### Data Flow Philosophy

Our stack can be organized into four functional layers:

```
DETECTION & MONITORING        EXECUTION & MANAGEMENT          KNOWLEDGE                  DELIVERY
─────────────────────────     ──────────────────────────      ──────────────────────     ──────────────────
Auvik (network)               DattoRMM (endpoint scripts)     ITGlue (docs)              Teams (alerts/reports)
Huntress (security)           CIPP (M365 multi-tenant)        BrightGauge (metrics)      CW Manage (tickets)
Liongard (config changes)     ConnectWise Manage (tickets)    GitHub (scripts)           SharePoint (files)
DattoBCDR (backup health)     n8n / Power Automate (glue)
SonicWALL / Meraki / Auvik
```

The key insight is that **CW Manage is the hub** — everything that matters should create, update, or close a ticket. CW Callbacks are the most important single mechanism in the stack because they let us react to ticket events in real time.

### Priority Automation Projects

**1. ITGlue Article Suggestion Engine (Highest Impact)**
- Trigger: CW Manage Callback on new ticket creation
- Processing: n8n extracts keywords from ticket title/description → queries ITGlue API for matching articles and flexible assets → selects top 3–5 results by relevance
- Output: POST matching articles as an internal note on the CW ticket within seconds of creation
- Impact: Reduces ticket resolution time; leverages existing ITGlue investment; completely API-driven with current capabilities

**2. DattoRMM Alert Enrichment Pipeline**
- Trigger: DattoRMM alert → creates CW ticket (native integration) → CW Callback fires
- Processing: n8n receives CW Callback → calls DattoRMM API to pull full device context (patch age, disk health, last seen, AV status) → calls ITGlue API to pull device documentation
- Output: Enriched internal note appended to the CW ticket with all device context before a tech opens it
- Impact: Techs start working with full context; eliminates the "look up the device" step

**3. Security Alert → CW Ticket Automation**
- Trigger: Huntress incident report / Liongard config change alert / Auvik device down
- Processing: Parse alert data → create structured CW ticket with appropriate board/type/subtype/priority
- Output: CW ticket created with full alert context and recommended remediation steps
- Impact: Security events get tracked and worked in the same system as everything else; nothing falls through the cracks

**4. Billing Reconciliation Engine**
- Trigger: Monthly schedule
- Processing: Pull seat counts from DattoRMM, Huntress, Webroot, SaaSProtection, CIPP (licenses) → compare against CW Manage agreement additions per client
- Output: Discrepancy report in Teams + CW ticket per client with mismatches flagged
- Impact: Revenue protection; eliminates manual monthly seat reconciliation

**5. Onboarding / Offboarding Automation**
- Trigger: CW Manage ticket type = "New Client Onboarding" or "User Offboarding"
- Processing: n8n state machine driving CIPP (M365 actions), ITGlue (create org/docs), DattoRMM (create site), MailProtector (provision domain), BSN (create org), Teams (create channel)
- Output: All provisioning steps completed automatically with CW ticket notes as the audit trail
- Impact: Consistent, documented, repeatable onboarding/offboarding with zero manual portal-hopping

### Key Integration Patterns

**CW Callback → n8n → [anything]** — The most powerful pattern in our stack. Wire this up for every automation that needs to react to ticket events.

**Scheduled API poll → Teams/CW** — For data that doesn't have webhooks (DattoBCDR, Webroot, some Datto products). Run on a schedule, normalize the data, deliver structured output.

**Liongard alert webhook → CW ticket enrichment** — Config change detected → ticket already created by Liongard → fire webhook to n8n → add context from ITGlue and other sources to the ticket.

**CIPP as the M365 action arm** — Any workflow that needs to make M365 changes across client tenants should route through CIPP, not direct Graph, to use CIPP's existing GDAP credential management.

**ITGlue as both source and target** — Write structured data into ITGlue automatically (from DattoRMM, Liongard, CIPP) and read from it for ticket enrichment and article suggestion. Stop treating it as a wiki that techs update manually.

---

*This document is a living reference. Add new tool discoveries, API capabilities, and completed automations as they emerge. Store in GitHub alongside the scripting kit.*
