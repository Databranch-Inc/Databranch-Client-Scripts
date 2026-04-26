# Project Blurbs v1.0.0 | April 2026
# One blurb per project -- paste into project instructions alongside foundational docs.

---

## Script Library

Foundational docs in this project (project spec, documentation spec, script template) are authoritative for all standards and conventions. Defer to them without re-deriving. Author field resolution: use fullest name available from conversation context (full name > first name > handle); never leave it as a literal placeholder. Do not auto-generate HTML documentation unless explicitly requested; once docs exist, update them with every script version increment. The dual-output Write-Log/Write-Console pattern and all DattoRMM-specific conventions are defined in the spec -- apply them as specified.

---

## SAMSP Bot / n8n

Architecture is 3-layer: PA trigger flows (per-tech, never change), BangHandler routing workflow (single webhook entry, Switch routes by command), command sub-workflows (one per command, return Adaptive Cards via PA). Foundational docs (n8n lessons learned, CW Manage lessons learned, feature roadmap) are authoritative for all patterns and confirmed API gotchas -- check them before proposing novel approaches to problems they already cover. New scheduled checks follow the suite checklist; new commands follow the BangHandler checklist. Both are defined in the docs.

---

## Onboarding App

Stack is C#/WinForms/.NET Framework 4.8. Project spec is authoritative for architecture, component patterns, and established design decisions. Critical dependency: use PDFsharp-MigraDoc-gdi (the GDI variant) -- the standard PDFsharp-MigraDoc variant throws GDI+ exceptions in .NET 4.8 WinForms and will not work. Maintain the multi-client CustomerProfile JSON pattern for all client-specific values. Apply full enterprise C# standards and proactively flag .NET 4.8 compatibility issues when suggesting patterns.

---

## Lectures / Talks

Deliverables are .pptx decks and Markdown speaker scripts/outlines. Audience is mixed technical/non-technical (SMB owners, MSP staff, non-developer IT roles) -- write slide content as concise talking points, not dense prose. All AI agent content must be grounded in the established frameworks present in the project source documents; do not introduce competing framings or architectures that conflict with them.
