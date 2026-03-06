# ArnotOnboarding — Changelog

All notable changes to this project are documented here.  
Format: `vMajor.Minor.Revision.Build — YYYY-MM-DD`

---

## v1.7.0.0 — 2026-02-28

### New Features
- **AboutDialog** — themed About / version dialog with full changelog.  
  Opened by clicking the logo/version area in the nav rail, or pressing **F1** anywhere in the shell.
- **LockManager** — network `.lock` sidecar file system for Restart Onboarding.  
  Prevents two staff members from editing the same finalized record simultaneously.
- **Restart Onboarding lock negotiation** in `RecordLibraryView`:
  - Fresh lock by another user → hard block with name/machine/account/time shown
  - Stale lock (> 2 hours) → override prompt, defaults to No for safety
  - Lock write failure → offer to proceed without lock protection
- **Nav warning banner** in `MainShell` — amber banner above the footer when one or more In Progress drafts hold an active network lock (i.e. were created via Restart Onboarding)
- **Lock icon column** in Past Records grid shows 🔒 + owner name; locked rows tinted amber; Restart button disabled with tooltip when locked by another user

### Bug Fixes
- **Lock not released on Finalize** — `ExportManager.Finalize` was calling a private `RemoveFromDraftIndex` helper that bypassed `DraftManager.DeleteDraft`, so the `.lock` sidecar on the network share was never deleted after export. Fixed by routing through `DraftManager.DeleteDraft` which calls `ReleaseLockForDraft` before removing the draft index entry.
- **Restart allowed on own stale lock** — after export, the `.lock` file remained on disk. `TryAcquire` saw it was owned by the same machine/user and re-used it instead of blocking. Root cause was the lock not being released (see above). Now resolved.
- **`RequeryNetworkShare` did not prune missing records** — Refresh updated PDF ✓/— indicators but kept deleted entries in the index. Fixed: Step 1 of requery now calls `RemoveAll` on entries whose `JsonPath` no longer exists on disk before scanning for new files.
- **PDF path derivation broken for new filename format** — `Path.ChangeExtension` on `"...IT Onboarding Data.json"` produced `"...IT Onboarding Data.pdf"` instead of `"...IT Onboard.pdf"`. Fixed with a dedicated `DerivePdfPath()` helper that detects the format and strips the correct suffix.
- **`LockManager.cs` missing from `.csproj`** — file was on disk but not registered, causing CS0103 build errors on all references to `LockManager` and `LockAcquireStatus`. Added `<Compile Include="Managers\LockManager.cs" />`.
- **`AboutDialog.cs` missing from `.csproj`** — registered in this release.

### Version / Naming
- App version bumped to **v1.7.0.0** in `AssemblyInfo.cs`, nav rail display string, and `AboutDialog`
- Nav version hint now reads: `v1.7.0.0  —  click to learn more`
- `MainShell.cs` → v1.5.0.0

---

## v1.6.1.0 — 2026-02-27

- `LockFile` model: added `LockedByUser` (Windows account name, separate from display name), `FriendlyDescription`, `DisplayName` computed properties
- `RecordLibraryView`: Lock column in grid; locked rows tinted amber; Restart button shows tooltip with owner name when disabled

---

## v1.6.0.0 — 2026-02-26

- **Restart Onboarding** — Past Records can be re-opened into a new editable draft
- `Page06_Computer`, `Page08_Email`: UI refinements and field corrections

---

## v1.5.9.0 — 2026-02-25

- `Page01_Request`: scheduling fields (completed-by date, setup appointment date + time) finalized

---

## v1.5.8.0 — 2026-02-24

- `DraftListView`: full resume, rename, delete, and import-from-zip workflow
- `Page04_AccountsAndCredentials`: conditional fields, domain username auto-suggest, initial password field
- `Page06b_MonitorsApps`: dual-monitor radio button sets, application checkbox grid loaded from `CustomerProfile`
- `Page07_PrintScanAccess`: printer field, scan-to-folder toggle, shared folder access grid

---

## v1.5.6.0 — 2026-02-28  *(patch, included in v1.7.0.0)*

- `ExportManager.Finalize` routes through `DraftManager.DeleteDraft` to release network locks on export

---

## v1.5.5.0 — 2026-02-28  *(patch, included in v1.7.0.0)*

- `RequeryNetworkShare` prunes index entries whose JSON no longer exists on disk (true Refresh behavior)
- `DerivePdfPath()` helper correctly maps JSON path → PDF path for both old and new filename formats

---

## v1.5.4.0 — 2026-02-28  *(patch, included in v1.7.0.0)*

- **New file naming convention:**
  - PDF:  `YYYYMMDD J Doe IT Onboard.pdf`
  - JSON: `YYYYMMDD J Doe IT Onboarding Data.json`
- Date in filename always uses `record.CreatedAt` (original request date), not today's date — re-exports and Restart exports on a later day preserve the original date
- `RequeryNetworkShare` glob updated to match both old (`*_Onboarding_*.json`) and new (`* IT Onboarding Data.json`) filename formats for backwards compatibility

---

## v1.5.0.0 — 2026-02-23

- `AppSettings`: `HrBasePath` / `HrSubPath` network share path configuration
- `SettingsView`: network path browse/edit, requestor profile management, index management (rebuild, open in Explorer)
- `ExportManager`: PDF generation via MigraDoc/PdfSharp, JSON export, Outlook MIME email compose with PDF + JSON attachments
- `RecordLibraryView`: indexed past records list with PDF ✓/— and JSON ✓/— column indicators, date filter, search
- `RequeryNetworkShare`: scans HR share for records created on other machines and adds them to the local index

---

## v1.4.0.0 — 2026-02-23

- `MainShell`: locked-record warning banner in nav footer — amber box counting active network locks on in-progress drafts
- `MainShell.FormClosing`: safety-net release of all session-owned network locks on app close

---

## v1.3.0.0 — 2026-02-22

- `WizardView`: 10-page wizard with Back/Next navigation, step indicator progress bar, auto-save on every field change
- `OnboardingRecord`: full data model with all wizard fields, `schemaVersion`, JSON serialization via Newtonsoft
- `DraftManager`: local `%AppData%` draft system; crash recovery prompt on launch if unsaved draft detected
- All wizard pages (01–10) fully implemented and wired to auto-save

---

## v1.0.0.0 — 2026-02-22

- Initial project: Visual Studio solution, `MainShell` nav rail, Databranch dark theme
- `AppColors`, `AppFonts`, `ThemeHelper` — full design token system matching the Databranch UI spec
- `CustomerProfile`, `RequestorProfile` model classes
- NuGet packages: `PDFsharp-MigraDoc-gdi 1.50.5147`, `Newtonsoft.Json 13.0.3`
