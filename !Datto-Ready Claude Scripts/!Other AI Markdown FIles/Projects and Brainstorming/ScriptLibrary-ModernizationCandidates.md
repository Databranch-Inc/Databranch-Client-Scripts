# Script Library — Modernization & Consolidation Candidates

> **Purpose:** Identifies legacy scripts that are strong candidates for consolidation and refactoring into the current Datto-Ready standard template.
> **Scope:** Based on full analysis of ScriptLibrary.zip — 350 files, ~213 PowerShell scripts.
> **Last Updated:** April 2026

---

## Executive Summary

The Databranch script library is in mid-transition between a large body of organically accumulated legacy scripts and a well-engineered production tier with a formal standard. The legacy tier contains significant functional duplication — multiple scripts doing overlapping jobs, dated variants that represent changelog entries rather than distinct tools, and one-offs that have since been superseded by production scripts.

This report identifies consolidation and modernization candidates organized by priority. The primary criteria for selection are: frequency of use in real support scenarios, degree of duplication across multiple files, existence of a clear canonical successor or consolidation target, and readiness to deploy as a DattoRMM component once modernized.

The recommended approach is **opportunistic modernization** — refactor a script when a support ticket would cause you to reach for it anyway — with a small number of proactive exceptions where the duplication is high-enough risk to warrant dedicated effort.

---

## Tier 1 — Proactive Modernization (Do These Now)

These are high-frequency, high-duplication clusters where the current state creates real operational risk — specifically, ambiguity about which file is the current one.

---

### 1.1 BitLocker Suite → `Invoke-BitlockerManagement.ps1`

**Current state — 8 scripts with overlapping scope:**

| File | Location | Function |
|---|---|---|
| `DB_Bitlocker_Setup_Automation.ps1` | `Bitlocker/` | Current setup automation |
| `DB_Bitlocker_Setup_Automation-3-22-23.ps1` | `Bitlocker/` | Dated variant |
| `DB_Bitlocker_Setup_Automation-6-7-21.ps1` | `Bitlocker/` | Dated variant |
| `DB_Bitlocker_Group Check.ps1` | `Bitlocker/` | Group membership check |
| `Bitlocker_GFS_Get_Key_AD_Sync.ps1` | `Bitlocker/` | Key retrieval, AD sync |
| `Bitlocker_Automate_Get_Key_EDF.ps1` | `Bitlocker/` | Key retrieval via CWA EDF |
| `Automate Bitlocker.ps1` | `Bitlocker/` | Legacy Automate-era setup |
| `Bitlocker One Liners.ps1` | `Bitlocker/` | Ad-hoc command reference |
| `Enable Bitlocker.ps1` | Root | Simple enable one-liner |

**The problem:** The dated variants (`-3-22-23`, `-6-7-21`) exist because the script changed over time — that is exactly what a changelog and version number are for. When a tech needs to enable or check BitLocker, it is not immediately obvious which of these eight files is authoritative.

**Consolidation target:** One `Invoke-BitlockerManagement.ps1` with switches controlling which operations run:

- `-Enable` — configure and enable BitLocker on the system drive
- `-GetKey` — retrieve recovery key (with output to UDF and/or log)
- `-CheckGroup` — verify the device is in the correct BitLocker AD group
- `-SyncToAD` — back up recovery key to Active Directory

All dated variants and the key retrieval scripts collapse into parameters. The one-liners become `.EXAMPLE` entries in the help block. The Automate-era script goes to `!Archive/`.

**DattoRMM value:** High. BitLocker enablement and key retrieval are among the most common DattoRMM component use cases. A single well-built component with UDF output for the recovery key would be immediately deployable at scale.

---

### 1.2 BreachSecureNow Whitelisting → `Invoke-BSNWhitelisting.ps1`

**Current state — 5 scripts, same function, different IP lists:**

| File | Date Tag |
|---|---|
| `BSN Allow IPs - O365.ps1` | Undated (original) |
| `BSN Allow IPs - O365 12-16-21.ps1` | December 2021 |
| `BSN Allow IPs - O365 10-21-22.ps1` | October 2022 |
| `BSN Allow IPs - O365 6-19-23.ps1` | June 2023 |
| `BSN_Whitelisting_7-10-25.ps1` | July 2025 (current) |

**The problem:** These are almost certainly the same script with an updated IP range on each BSN platform change. The naming convention makes `BSN_Whitelisting_7-10-25.ps1` look like the current one, but there is no documentation to confirm the others are retired. Any tech who opens the `BSN/` folder sees five files with no clear winner.

**Consolidation target:** One `Invoke-BSNWhitelisting.ps1` using the current IP ranges, versioned properly in the changelog when BSN updates their ranges. All prior dated versions go to `!Archive/`. When BSN changes IPs again, the response is a version bump and a changelog entry — not a new file.

**DattoRMM value:** Medium-high. BSN whitelisting is an onboarding step for every new client. A DattoRMM-ready component eliminates the current manual portal-based process.

---

## Tier 2 — Opportunistic Modernization (On Next Use)

These are strong candidates that do not carry the same urgency as Tier 1 but should be refactored the next time a support scenario causes you to reach for them. The refactor cost is low because the functional logic already exists — it just needs the template wrapper applied.

---

### 2.1 AD User Lifecycle Scripts → Coherent Named Set

**Current state — scattered across `AD/` with inconsistent naming:**

| File | Phase |
|---|---|
| `New AD Creation.ps1` / `Bulk AD User Creation.ps1` | Create |
| `Set_AD_Accounts.ps1` / `Bulk_Set_AD_Attribute.ps1` / `Bulk_Set_AD_Attribute_Entra_Sync.ps1` / `Bulk_Set_AD_Attribute_CHPC.ps1` | Modify |
| `Disable AD Accounts.ps1` / `AD_Account_Resets(Scrambled PW).ps1` | Disable / Reset |
| `RemoveProfile-HomeDrive.ps1` | Cleanup |
| `AD_User_Domain_Move.ps1` | Migration |

**The problem:** These represent the create → modify → disable → cleanup lifecycle of an AD user, but they are named and structured inconsistently. `Bulk_Set_AD_Attribute_CHPC.ps1` is almost certainly client-specific logic that crept into a generic-looking folder.

**Consolidation targets:**

- `New-ADUserAccount.ps1` — single and bulk creation, CSV-driven input
- `Set-ADUserAttributes.ps1` — bulk attribute setting with optional Entra sync trigger; absorbs the `_CHPC` variant as a parameter or moves it to `!Client Based Scripts/`
- `Disable-ADUserAccount.ps1` — disable with optional password scramble
- `Remove-ADUserProfile.ps1` — profile and home drive cleanup

Four scripts with clear ownership of their lifecycle phase, all DattoRMM-ready, all built from the template.

---

### 2.2 Bulk AD Attribute Scripts → `Set-ADUserAttributes.ps1`

**Current state:**

| File | Variation |
|---|---|
| `Bulk_Set_AD_Attribute.ps1` | Generic |
| `Bulk_Set_AD_Attribute_CHPC.ps1` | Client-specific variant |
| `Bulk_Set_AD_Attribute_Entra_Sync.ps1` | Adds Entra sync trigger |

These are the same script with two additive features tacked on in separate files. One `Set-ADUserAttributes.ps1` with `-TriggerEntraSync` as a switch and the CHPC-specific logic either parameterized or moved to `!Client Based Scripts/` eliminates the ambiguity entirely.

---

### 2.3 Wireless Profile Scripts → `Invoke-WirelessProfileDeployment.ps1`

**Current state:**

| File | Size | Notes |
|---|---|---|
| `Wireless_Profile_Setup.ps1` | 2.5KB | Base script |
| `Wireless_Profile_Setup_Datto_RMM.ps1` | 14KB | Partial DattoRMM modernization |
| `Wireless_Profile_Test.ps1` | 637B | Connectivity validation |

The 14KB DattoRMM variant shows that someone started modernizing this script but did not finish or consolidate. The base script and the RMM variant are now diverged, and the test script is a separate file rather than a switch. One `Invoke-WirelessProfileDeployment.ps1` with DattoRMM env var input and a `-ValidateOnly` switch covers all three use cases cleanly.

---

### 2.4 Folder and File Cleanup → Archive in Favor of `Remove-FilesByPattern.ps1`

**Current state:**

| File | Location |
|---|---|
| `Databranch_Folder_Cleanup.ps1` | `PC Maintenance/` |
| `Named_Folder_Cleanup.ps1` | `PC Maintenance/` |
| `Kiwi_Syslog_Folder_Cleanup.ps1` | `PC Maintenance/` |
| `DeleteOldFiles.ps1` | Root |
| `DeleteOldFiles_Allegany_County_ARC.ps1` | Root |

`Remove-FilesByPattern.ps1` is already in the `!Testing/` queue and is clearly the intended canonical replacement for all of these. The action here is not a refactor — it is promoting `Remove-FilesByPattern.ps1` to production and archiving the above five scripts with a pointer to the replacement.

---

### 2.5 MFA Reporting → `Get-MFAComplianceReport.ps1`

**Current state:**

| File | Location | Cut |
|---|---|---|
| `GetMFAReport.ps1` | `O365/` | Basic MFA status |
| `MFA Enrollment Counts.ps1` | `O365/` | Enrollment count summary |
| `MFA Enrollment Counts Enabled-Enforced-Disabled.ps1` | `O365/` | Enrollment by state breakdown |
| `Get-MFAStatus.ps1` | Root | MFA status (slightly different approach) |

Four scripts measuring the same thing with different levels of granularity. One `Get-MFAComplianceReport.ps1` with output mode parameters (`-Summary`, `-ByState`, `-PerUser`) covers all four cuts.

**Caveat:** Before refactoring, verify whether these have a genuine DattoRMM use case. CIPP now provides MFA reporting across all tenants natively. If these are only used for per-client interactive reporting, CIPP may have made them redundant entirely — in which case they go to `!Archive/` rather than getting refactored.

---

### 2.6 Windows Services and Processes → `Manage-WindowsService.ps1`

**Current state:**

| File | Function |
|---|---|
| `CheckandSetServiceStartup.ps1` | Verify and set service startup type |
| `Temporary Process Start.ps1` | Start a process temporarily |
| `Stop-PendingService.ps1` | Stop a service stuck in pending state |
| `Process stop by service.ps1` | Stop process by associated service |
| `process step by servics.ps1` | Duplicate with typo in name |

The typo in `process step by servics.ps1` is a reliable indicator these accumulated without governance. The functional overlap is significant. One `Manage-WindowsService.ps1` with `-Operation` parameter (`Check`, `Set`, `Start`, `Stop`, `ForceStop`) and `-StartupType` handles the majority of these scenarios.

---

## Tier 3 — Archive Without Refactor

These scripts have been functionally superseded by production scripts already in the library. They do not need refactoring — they need to be retired with a clear pointer to their replacement so techs stop reaching for them.

| Legacy Script(s) | Superseded By | Action |
|---|---|---|
| `Gather Event Logs Remote Machine.ps1`, `Gather Event Logs_6-29-19.ps1`, `!Archive/Gather Event Logs.ps1` | `Start-EventLogCollection.ps1` | Archive — add README note |
| `InventoryReport_*.ps1` (all 5 dated versions in `Hardware/Inventory/`) | `Start-ADInventoryCollection.ps1` | Archive — review WIP first |
| `InventoryReport_WIP.ps1` (root) | `Start-ADInventoryCollection.ps1` | Compare features, then archive or merge |
| `DeltaSync.ps1` / `FullSync.ps1` (both in `AD/` and `O365/`) | CIPP Standards engine / manual CIPP actions | Archive — 4 files, all one-liners |
| `EngineersPowerApp_PS7_git.ps1` | `Start-ScriptManagementBrowser.ps1` | Archive — keep as historical reference |

**Note on `InventoryReport_WIP.ps1`:** Before archiving, do a feature comparison against `Start-ADInventoryCollection`. The WIP file is dated February 2026 — after the production script was built — which suggests someone may have been iterating on capabilities the production script does not have. If unique capabilities exist, fold them into `Start-ADInventoryCollection` as a version increment first.

---

## Modernization Approach

### Recommended Process (Per Script)

1. Pull the legacy script and the current `Invoke-ScriptTemplate.ps1`
2. Read the legacy logic and document what it actually does — not what the filename implies
3. Map parameters to the DattoRMM env var fallback pattern
4. Wrap logic in the master function, apply `Write-Log` / `Write-Console` dual-output
5. Add pre-flight validation with `exit 2` on failure
6. Set version at `1.0.0.0` for a full rewrite; carry forward if the script already had a version number
7. Move the legacy script to `!Archive/` — do not delete, in case the refactor misses something
8. Test via DattoRMM Quick Job against a dev/test device before promoting

### Opportunistic Trigger

When a support ticket would cause a tech to reach for one of the legacy scripts listed above, that ticket is the moment to modernize it. The script gets tested against a real scenario, the tech already has context, and the result is a production-ready component rather than another one-off run.

### Exceptions — Proactive Refactor

The **BitLocker suite** and **BSN whitelisting scripts** are the only cases where the duplication risk is high enough to warrant dedicated time outside of a ticket-driven trigger. The BitLocker suite in particular is touched frequently enough that the "which file is current" ambiguity is an active problem, not a hypothetical one.

---

## Summary Table

| Cluster | Legacy Count | Target Script | Tier | DattoRMM Value |
|---|---|---|---|---|
| BitLocker suite | 8–9 | `Invoke-BitlockerManagement.ps1` | 1 — Proactive | High |
| BSN whitelisting | 5 | `Invoke-BSNWhitelisting.ps1` | 1 — Proactive | Medium-High |
| AD user lifecycle | ~10 | 4 named scripts | 2 — Opportunistic | High |
| Bulk AD attributes | 3 | `Set-ADUserAttributes.ps1` | 2 — Opportunistic | Medium |
| Wireless profiles | 3 | `Invoke-WirelessProfileDeployment.ps1` | 2 — Opportunistic | Medium |
| Folder/file cleanup | 5 | `Remove-FilesByPattern.ps1` (promote) | 2 — Opportunistic | Medium |
| MFA reporting | 4 | `Get-MFAComplianceReport.ps1` | 2 — Opportunistic | Low-Medium |
| Windows services | 5 | `Manage-WindowsService.ps1` | 2 — Opportunistic | Medium |
| Event log collection | 3 | Archive → `Start-EventLogCollection` | 3 — Archive | N/A |
| Inventory reports | 6+ | Archive → `Start-ADInventoryCollection` | 3 — Archive | N/A |
| Entra sync triggers | 4 | Archive → CIPP | 3 — Archive | N/A |
| Engineers PowerApp | 1 | Archive → `Start-ScriptManagementBrowser` | 3 — Archive | N/A |

---

*Store in GitHub alongside `Databranch_ScriptLibrary_ProjectSpec.md` and the foundational reference documents.*
