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
```css
--navy:           #0f1e35   /* Page background */
--navy-mid:       #1a3154   /* Sidebar, table headers, step headers */
--navy-light:     #1e4a7a   /* Active nav, h1 border, flow step numbers */
--accent:         #2e8bff   /* Primary blue — links, h2, code left border, h1 :: prefix */
--accent-dim:     #1a5fbd   /* Hover states */
--teal:           #00c9b1   /* Company label, h3, architecture tags */
--white:          #f4f7fb   /* Headings, strong text, cover title */
--text:           #d0dce8   /* Body text */
--text-muted:     #8a9bb5   /* Secondary text, table headers */
--text-dim:       #5a6f8a   /* Nav section labels, footer text */
--border:         #1e3a5a   /* Standard borders */
--border-mid:     #2a4f72   /* Table header bottom border */
--code-bg:        #0a1624   /* Code blocks, inline code background */
--row-alt:        #0d1e30   /* Alternating table rows */
--success-bg:     #0a2418   /* Tip callout background */
--success-border: #1a6640   /* Tip callout border */
--warn-bg:        #1e1a08   /* Warning callout background */
--warn-border:    #7a6010   /* Warning callout border */
--note-bg:        #0a1a2e   /* Note callout background */
--note-border:    #1a4a7a   /* Note callout border */
```

### Severity / Status Colors (used in-content, not as CSS variables)
```
INFO    : #60a5fa   (blue)
SUCCESS : #22c55e   (green)
DEBUG   : #a78bfa   (purple)
WARN    : #eab308   (amber)
ERROR   : #ef4444   (red)
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
- Fixed position, full height, scrollable, `#080f1a` background
- Logo block: `DATABRANCH` in teal uppercase small-caps, script name in white, doc type subtitle in muted
- Nav links: 13px, hover highlights, active state = accent left border + navy-light background
- Sub-links: `.nav-link.sub` — indented 24px, 12px font
- Nav section labels: 10px, uppercase, letter-spaced, `--text-dim`

### Cover Block
- Gradient: `linear-gradient(145deg, #0a1828 0%, #0f2544 40%, #0a1e3a 100%)`
- Two decorative radial gradients (pseudo-elements): blue glow top-right, teal glow bottom-left
- Eyebrow: `Databranch Script Library` — 11px, teal, uppercase, letter-spaced
- Title: Script's human-readable name — 42px, bold, white
- Script name: monospace, 16px, accent blue (e.g. `Start-EventLogCollection.ps1`)
- Doc type: italic, muted, 15px (e.g. `Operator How-To Guide` / `Technical Specification`)
- Meta row: flex row of labeled values — Version (mono/accent), Date, Author, Company, + doc-specific fields

### Content Typography
```
h1  : 26px bold white, border-bottom 2px navy-light, prefix: '//  ' in accent mono
h2  : 18px semibold accent blue
h3  : 12px bold teal, uppercase, letter-spaced
p   : var(--text), 14px line-height 1.7, margin-bottom 14px
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
.code-block  : dark background (#0a1624), border with 3px accent-blue left edge,
               IBM Plex Mono 13px, horizontal scrollable
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
- `td.mono`: monospace, accent blue, no-wrap
- `td.num`: large mono, centered (used for exit codes in TechSpec)

### Callout Boxes
Three variants, all use `.callout` base with emoji icon and labeled body:
```
.callout.note  — blue left border  — label: accent       — icon: ℹ️ or 🔧
.callout.tip   — green left border — label: green         — icon: 💡
.callout.warn  — amber left border — label: amber         — icon: ⚠️
```

### Badges
Inline chips in `.badge` with color variants:
```
.badge-blue   .badge-teal   .badge-green   .badge-amber   .badge-red
```

### Styled Lists
```
ul.styled  — custom bullet ▸ in accent blue
ol.styled  — numbered circles with navy-light background, accent number
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
| `logging`     | 8. Logging Architecture        | Severity grid (`.sev-grid`). Log file location and rotation. Summary file if applicable.       |
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
Tag color variants: `discovery` (teal), `collection` (blue), `infra` (muted), `output` (green).

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
    <div class="sev-level" style="color:#60a5fa;">INFO</div>
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
