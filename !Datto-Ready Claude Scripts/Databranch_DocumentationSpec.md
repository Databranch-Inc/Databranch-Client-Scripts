# Databranch Script Library — Documentation Standard
### HTML Document Specification
---

## Overview

Each script in the Databranch library may have up to two HTML documentation files:

| Document Type         | File Naming Convention                        | Audience                        |
|-----------------------|-----------------------------------------------|---------------------------------|
| Operator How-To Guide | `<ScriptName>-HowTo.html`                     | Engineers / Technicians         |
| Technical Specification | `<ScriptName>-TechSpec.html`                | Script authors / Senior engineers |

Documentation is **not auto-generated**. It is requested explicitly during a script conversation. Once created, all subsequent script iterations must include a documentation update to keep docs in sync with the script version.

---

## When Documentation Is Created

- Created **on request** during a script conversation — never automatically.
- Both documents are produced together when documentation is first requested.
- After initial creation, **every script version increment** that changes behavior, parameters, output, or error handling must produce updated versions of any existing documentation files.
- Version numbers in the document footer and cover block must always match the script version.

---

## Visual Design System

Both document types share an identical visual design. No deviations.

### Fonts
```
IBM Plex Sans  — body text, UI elements
IBM Plex Mono  — code, script names, version numbers, monospace values
Source: https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:ital,wght@0,300;0,400;0,500;0,600;0,700;1,400&display=swap
```

### Color Palette (CSS Variables)

All CSS variables must use the following tokens, derived from `Databranch_UIDesignSpec.html`.
No other color values should appear in documentation HTML files.

```css
/* Surface Layers */
--surface-void:       #080C14   /* Sidebar background */
--surface-base:       #0D1520   /* Page/window background */
--surface-raised:     #111C2E   /* Cover block dark base, alternating rows */
--surface-card:       #162238   /* Table headers, step headers, card backgrounds */
--surface-elevated:   #1D2E48   /* Active nav background, h1 border */

/* Brand Accents */
--brand-red-soft:     #C0404A   /* Active nav left border, cover eyebrow, h1 :: prefix */
--brand-red-pale:     #D07080   /* h3 headings, secondary accent labels */
--brand-blue-bright:  #2E8BFF   /* Links, h2, focus, accent buttons, meta value highlights */
--brand-blue-mid:     #1A6FD4   /* Hover states for blue elements */

/* Text */
--text-primary:       #F0F4FF   /* Headings, strong text, cover title */
--text-secondary:     #A8BDD8   /* Body text */
--text-muted:         #607090   /* Secondary text, table headers, field labels */
--text-dim:           #3A5070   /* Nav section labels, footer text, placeholder */

/* Borders */
--border-default:     #213A58   /* Standard borders */
--border-mid:         #2A4A70   /* Table header bottom border, emphasized borders */

/* Code */
--code-bg:            #060E1A   /* Code blocks, inline code background */

/* Rows */
--row-alt:            #111C2E   /* Alternating table rows (same as surface-raised) */

/* Status / Callouts */
--status-success:     #22C55E
--status-success-bg:  #0A2818
--status-success-bd:  #1A5030
--status-warn:        #E8A020
--status-warn-bg:     #1E1800
--status-warn-bd:     #6A4800
--status-error:       #C84040
--status-error-bg:    #200A0A
--status-error-bd:    #6A1818
--status-info:        #2E8BFF
--status-info-bg:     #091828
--status-info-bd:     #1A3A6A
```

### Severity / Status Colors (used in-content, not as CSS variables)
```
INFO    : #4AB4FF   (cyan-blue)
SUCCESS : #22C55E   (green)
DEBUG   : #C084FC   (magenta-purple)
WARN    : #E8A020   (amber)
ERROR   : #C84040   (red — matches brand red family)
```

---

## Page Layout

### Structure
```
.layout (flex row)
├── .sidebar (fixed, 260px wide)
│   ├── .sidebar-logo (company name, script name, doc type)
│   └── nav (hierarchical links)
└── .main (margin-left: 260px)
    ├── .cover (gradient hero block)
    ├── .content (max-width 860px HowTo / 900px TechSpec, padding 56px 80px 80px)
    │   └── .section[id] × N  (each major chapter)
    └── .doc-footer
```

### Sidebar
- Fixed position, full height, scrollable, `var(--surface-void)` (`#080C14`) background
- Logo block: `DATABRANCH` in `--brand-red-soft` uppercase small-caps, script name in `--text-primary`, doc type subtitle in `--text-muted`
- Nav links: 13px, hover: `--surface-card` background + `--text-primary`. Active state = **`--brand-red-soft` 2px left border** + `--surface-elevated` background (NOT blue — see UIDesignSpec §13)
- Sub-links: `.nav-link.sub` — indented 24px, 12px font
- Nav section labels: 10px, uppercase, letter-spaced, `--text-dim`

### Cover Block
- Gradient: `linear-gradient(145deg, #060E1A 0%, #0D1F3A 40%, #0A1828 100%)`
- Two decorative radial gradients (pseudo-elements): blue glow (`rgba(30,144,255,0.07)`) top-right, red glow (`rgba(176,16,32,0.06)`) bottom-left — **teal glow is retired**
- Eyebrow: `Databranch Script Library` — 11px, `--brand-red-soft`, uppercase, letter-spaced — **not teal**
- Title: Script's human-readable name — 42px, bold, `--text-primary`
- Script name: monospace, 16px, `--brand-blue-bright` (e.g. `Start-EventLogCollection.ps1`)
- Doc type: italic, `--text-muted`, 15px (e.g. `Operator How-To Guide` / `Technical Specification`)
- Meta row: flex row of labeled values — Version (`--brand-blue-bright` mono), Date, Author, Company, + doc-specific fields

### Content Typography
```
h1  : 26px bold --text-primary, border-bottom 2px --surface-elevated,
      prefix: '//  ' in --brand-red-soft mono  (NOT blue)
h2  : 18px semibold --brand-blue-bright
h3  : 12px bold --brand-red-pale, uppercase, letter-spaced  (NOT teal)
p   : var(--text-secondary), 14px line-height 1.7, margin-bottom 14px
```

### Footer
- `border-top: 1px solid var(--border)`
- Left: `Databranch — Confidential`
- Right: `<ScriptName>.ps1 | v<version> | <Month YYYY>` (monospace)

---

## Shared UI Components

All components below are used in both document types. CSS definitions are identical between HowTo and TechSpec files.

### Code Blocks
```
.code-block  : dark background (--code-bg / #060E1A), border with 3px --brand-red-soft left edge,
               IBM Plex Mono 13px, horizontal scrollable
               NOTE: Left-edge accent is RED, not blue. See UIDesignSpec §11 Design Decision Record.
code.inline  : same background, inline with border, 12.5px
```
Syntax highlighting classes (TechSpec only, used sparingly):
```
.comment  #4a7a5a   .keyword  #c084fc   .string   #86efac   .var   #fde68a
```

### Tables
- Wrapped in `.table-wrap` (overflow, rounded border)
- Alternating row colors, hover highlight
- `thead th`: uppercase, 10.5-11px, letter-spaced, muted
- `td.mono`: monospace, `--brand-blue-bright`, no-wrap
- `td.num`: large mono, centered (used for exit codes in TechSpec)

### Callout Boxes
Three variants, all use `.callout` base with emoji icon and labeled body:
```
.callout.note  — blue left border  — label: accent       — icon: ℹ️ or 🔧
.callout.tip   — green left border — label: green         — icon: 💡
.callout.warn  — amber left border — label: amber         — icon: ⚠️
```

### Badges
Inline chips in `.badge` with color variants. Teal variant is retired — use blue or muted instead:
```
.badge-blue    background: rgba(46,139,255,0.15)  text: #4AB4FF   border: rgba(46,139,255,0.3)
.badge-red     background: rgba(176,16,32,0.15)   text: #D07080   border: rgba(176,16,32,0.3)
.badge-green   background: rgba(34,197,94,0.12)   text: #22C55E   border: rgba(34,197,94,0.25)
.badge-amber   background: rgba(232,160,32,0.12)  text: #E8A020   border: rgba(232,160,32,0.25)
.badge-purple  background: rgba(192,132,252,0.12) text: #C084FC   border: rgba(192,132,252,0.25)
.badge-muted   background: rgba(96,112,144,0.15)  text: #607090   border: rgba(96,112,144,0.25)
```
All badges: IBM Plex Mono, 10.5–11px, weight 600, letter-spacing 0.05em, border-radius 4px, padding 2px 9px.

### Styled Lists
```
ul.styled  — custom bullet ▸ in --brand-red-soft (NOT blue)
ol.styled  — numbered circles with --surface-elevated background, --brand-blue-bright number
```

### Exit Code Pills (`.exit-codes` / `.exit-pill`)
Flex row of pill cards: large mono exit number (colored by severity), label, description.
Colors: green (0/success), amber (1/partial), red (2/failure).

### Scroll-Spy Navigation (JavaScript)
Both documents use IntersectionObserver to highlight the active nav link as the user scrolls:
```javascript
const sections = document.querySelectorAll('.section[id]');
const navLinks = document.querySelectorAll('.nav-link');
const observer = new IntersectionObserver(entries => {
  entries.forEach(e => {
    if (e.isIntersecting) {
      navLinks.forEach(l => l.classList.remove('active'));
      const link = document.querySelector(`.nav-link[href="#${e.target.id}"]`);
      if (link) link.classList.add('active');
    }
  });
}, { rootMargin: '-20% 0px -70% 0px' });
sections.forEach(s => observer.observe(s));
```

### Console Output — Dual-Output Pattern Documentation
When documenting the logging architecture section of the TechSpec, the console output pattern must be explained alongside the structured log output. Include:

- A table showing the two output layers (`Write-Log` vs `Write-Console`/helpers), what stream each uses, what captures it, and its purpose
- The severity color table for `Write-Console` (INFO=Cyan, SUCCESS=Green, WARN=Yellow, ERROR=Red, DEBUG=Magenta, PLAIN=Gray)
- Description of `Write-Banner`, `Write-Section`, `Write-Separator` and when each is used
- A note explaining why `Write-Host` (display stream 6) is used — it is not captured by DattoRMM stdout, making it naturally suppressed in automated runs with no conditional logic needed
- A code example or prose description of the paired call pattern

In the HowTo, the Console Output section should show the severity prefix legend using the correct colors and explain that the formatted console output is only visible during interactive/manual runs, while DattoRMM job output shows the structured log format.

### Print Styles
Both documents include `@media print`:
- White background, dark text, 12px font
- Sidebar hidden, main margin removed
- Cover background forced with `-webkit-print-color-adjust: exact`

---

## Operator How-To Guide

**File:** `<ScriptName>-HowTo.html`
**Audience:** Engineers and technicians who will run the script. No assumed code knowledge.
**Tone:** Plain English. Imperative. Step-by-step where applicable.

### Cover Meta Fields
| Label    | Value                                 |
|----------|---------------------------------------|
| Version  | Script version (mono/accent)          |
| Date     | Month DD, YYYY                        |
| Author   | Original author / Contributor name(s) |
| Company  | Databranch                            |
| Audience | Engineers / Operators                 |

### Required Sections (in order)

| Section ID       | h1 Title              | Content                                                                                  |
|------------------|-----------------------|------------------------------------------------------------------------------------------|
| `overview`       | Overview              | One-paragraph plain-English description. Include a `.callout.note` for audience/context. |
| `what-it-does`   | What the Script Does  | `ul.styled` of concrete actions the script performs each run.                            |
| `prerequisites`  | Prerequisites         | Sub-sections for Permissions and Software Requirements (table).                          |
| `running`        | Running the Script    | Numbered `.step-block` elements for launch steps. Mode cards if applicable. Parameter table. Example commands. |
| `output`         | Reading the Output    | File path pattern (code block). Output file/column descriptions (table).                 |
| `console`        | Console Output        | Severity prefix legend in a styled bordered block using severity colors.                 |
| `troubleshooting`| Troubleshooting       | Common failure scenarios as h2 headings with plain-English resolution steps.             |
| `dattormm`       | Running via DattoRMM  | Environment variable table. Exit code pills. Any relevant callout notes.                 |

### How-To Exclusive Components

**Step Blocks** (`.step-block`):
```html
<div class="step-block">
  <div class="step-header">
    <div class="step-num">1</div>
    <div class="step-title">Step Title</div>
  </div>
  <div class="step-body"><!-- content --></div>
</div>
```

**Mode Cards** (`.mode-cards` grid, 2 columns):
```html
<div class="mode-cards">
  <div class="mode-card">
    <div class="mode-card-title"><span class="badge badge-blue">ModeName</span> Label</div>
    <div class="mode-card-desc">Description.</div>
  </div>
</div>
```

**Console Prefix Legend**:
Bordered block with alternating row backgrounds, `.prefix-tag` in severity color, description text.

---

## Technical Specification

**File:** `<ScriptName>-TechSpec.html`
**Audience:** Script authors and senior engineers. Assumes PowerShell familiarity.
**Tone:** Precise and technical. Implementation detail is expected.

### Cover Meta Fields
| Label      | Value                                 |
|------------|---------------------------------------|
| Version    | Script version (mono/accent)          |
| Date       | Month DD, YYYY                        |
| Author     | Original author / Contributor name(s) |
| PS Minimum | e.g. `5.1`                            |
| Run Context| e.g. `Domain Admin` / `SYSTEM`        |

### Required Sections (numbered, in order)

| Section ID    | h1 Title                       | Content                                                                                        |
|---------------|--------------------------------|------------------------------------------------------------------------------------------------|
| `purpose`     | 1. Purpose and Scope           | What the script does, why it exists, what it replaces or consolidates.                         |
| `architecture`| 2. Script Architecture         | Structural pattern (ul.styled). Sub-function map as `.arch-grid` cards with tags.              |
| `parameters`  | 3. Parameters                  | Full parameter reference table (name, type, default, description). DattoRMM pattern with code example. |
| `modes`       | 4. Operating Modes             | One h2 per mode. Flow diagrams (`.flow`) where applicable. Callouts for important behaviors.   |
| `precheck`    | 5. Connectivity Pre-Check      | Multi-stage check table (stage, method, timeout, purpose). (Omit if not applicable.)           |
| `parallel`    | 6. Parallel Collection Engine  | PS version detection logic. One h2 per engine (5.1 runspaces, 7+ parallel). (Adapt to script.) |
| `collection`  | 7. [Core Logic Section]        | Implementation details of the script's primary work. Sub-sections as needed with code examples.|
| `logging`     | 8. Logging Architecture        | Severity grid (`.sev-grid`). Log file location and rotation. **Console output section**: dual-output pattern explanation, `Write-Console` color table, `Write-Banner`/`Write-Section`/`Write-Separator` descriptions. Summary file if applicable. |
| `errors`      | 9. Error Handling              | Global error policy. Per-target isolation if applicable. Exit codes table.                     |
| `limitations` | 10. Known Limitations          | Table of known constraints, edge cases, or design trade-offs.                                  |
| `changelog`   | 11. Version History            | `.version-entry` blocks (newest first). Each entry: version number, date, author, bullet list of changes. |

> Section numbers and titles should adapt to the script. Not every section applies to every script.
> For example, a simple utility script may not need a Parallel Collection Engine section.
> Renumber sections accordingly and update the nav links to match.

### TechSpec Exclusive Components

**Architecture Cards** (`.arch-grid`, 2-column grid):
```html
<div class="arch-grid">
  <div class="arch-card">
    <div class="arch-card-header">
      <div class="arch-fn">FunctionName</div>
      <div class="arch-tag discovery">Discovery</div>  <!-- or: infra, collection, output -->
    </div>
    <div class="arch-desc">Description of what this function does.</div>
  </div>
</div>
```
Tag color variants: `discovery` (blue-pale / #4A8FD4), `collection` (blue / #2E8BFF), `infra` (muted / #607090), `output` (green / #22C55E).
Note: The `discovery` tag previously used teal (#00c9b1). Teal is retired from the design system — use blue-pale instead.

**Flow Diagrams** (`.flow`, vertical):
```html
<div class="flow">
  <div class="flow-step">
    <div class="flow-num">1</div>
    <div class="flow-content">
      <div class="flow-title">Step Title <span class="flow-badge">Tag</span></div>
      <div class="flow-desc">Detail.</div>
    </div>
  </div>
</div>
```

**Severity Grid** (`.sev-grid`, 5-column):
```html
<div class="sev-grid">
  <div class="sev-cell">
    <div class="sev-level" style="color:#4AB4FF;">INFO</div>
    <div class="sev-stream">Write-Output</div>
    <div class="sev-desc">Description.</div>
  </div>
  <!-- repeat for SUCCESS, DEBUG, WARN, ERROR -->
</div>
```

**Version History Entries** (`.version-entry`, newest first):
```html
<div class="version-entry">
  <div class="version-header">
    <div class="version-num">v1.0.0.0</div>
    <div class="version-meta">Month DD, YYYY</div>
    <div class="version-author">Author Name</div>
  </div>
  <div class="version-body">
    <ul>
      <li>Change description.</li>
    </ul>
  </div>
</div>
```

---

## Documentation Update Rules

When a script iteration produces a new version:

1. Update the version number in the cover block meta and the footer of both documents.
2. Update the date in the cover block meta.
3. Add a new `.version-entry` block at the top of the Version History section in the TechSpec.
4. Update any section content that reflects changed behavior, parameters, output format, or error handling.
5. If a new parameter is added, add it to the parameter table in the TechSpec and the parameter table in the HowTo (if applicable).
6. If a new exit code is added, update the exit code pills in both documents.
7. The HowTo does not have a version history section — version is surfaced only in the cover and footer.

---

## File Naming Convention

```
<ScriptName>-HowTo.html
<ScriptName>-TechSpec.html
```

Examples:
```
Invoke-ADUserAudit-HowTo.html
Invoke-ADUserAudit-TechSpec.html
Get-DiskInventory-HowTo.html
Get-DiskInventory-TechSpec.html
```

Both files ship alongside the `.ps1` script file in the same library folder.
