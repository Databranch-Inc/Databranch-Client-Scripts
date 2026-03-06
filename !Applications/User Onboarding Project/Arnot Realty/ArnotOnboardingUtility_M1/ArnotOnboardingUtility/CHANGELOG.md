# ArnotOnboardingUtility — Changelog

All notable changes to this project, newest first.

---

## v1.0.0.0 — 2026-02-28

**Milestone 1 — Shell, Landing & Session Infrastructure**

### Added
- New Visual Studio solution: `ArnotOnboardingUtility.sln` (.NET 4.8 WinForms)
- `Theme/AppColors.cs` — Full Databranch unified dark theme color tokens (matches ArnotOnboarding v1.7)
- `Theme/AppFonts.cs` — Pre-instantiated font instances (Segoe UI + Consolas). No inline `new Font()`.
- `Theme/ThemeHelper.cs` — Recursive theme applicator + primary / secondary / ghost button style helpers
- `Models/OnboardingRecord.cs` — Full read-only deserialization target for schemaVersion 1.3 JSON. All 60+ fields from actual JSON file, computed helpers: `FullName`, `IsFinalized`, `IsKioskUser`, `OtherAccountRequired()`
- `Models/EngineerSession.cs` — Progress state model. `MarkStepComplete()`, `SetNote()`, `GetNote()`, `ProgressDisplay`
- `Models/SessionIndex.cs` — Lightweight index for recent sessions list. `SessionIndexEntry` with display helpers
- `Models/StepDefinition.cs` — `StepType` enum (Automated / Manual / Hybrid), `ParameterFactory` delegate for M4/5
- `Models/StepCatalog.cs` — Full step catalog factory for Desktop (16 steps) and Kiosk (5-6 steps). All conditional step logic resolved against `OnboardingRecord`. Guidance text for all steps populated
- `Managers/SessionManager.cs` — Load, save, create, delete session files in AppData. Session index maintenance. `LoadOnboardingRecord()` with full validation. `SchemaMismatchException` for non-blocking schema warnings
- `Views/MainShell.cs` — Borderless form with custom-painted nav rail (260px). Logo image caching. State-gated `Invalidate()` for hover (anti-flicker). Hit-rect tracking. Drag-to-move. Close/minimize chrome. About dialog (F1 shortcut). Session state forwarding to nav
- `Views/LandingView.cs` — New Onboarding (file picker + validation) and Continue (recent sessions ListView + file picker). Schema mismatch warning dialog. Existing-session resume-or-restart prompt. Full error handling
- `Views/StepRunnerView.cs` — M1 stub: renders all steps as summary cards with phase headers, step label, title, type badge, status badge. Full StepCard UserControls in M2
- `Views/LogViewerView.cs` — Read-only log display. Refresh and Open in Notepad buttons
- `Views/SettingsView.cs` — M1 stub: shows AppData paths with exist indicators. Full settings in M6
