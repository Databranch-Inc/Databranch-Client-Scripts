// =============================================================
// ArnotOnboarding — OnboardingRecord.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Central data model representing one complete onboarding
//              request. All wizard pages read/write to this object.
//              Serializes to JSON for draft storage, network export,
//              and future engineer automation tool consumption.
// =============================================================

using System;
using System.Collections.Generic;

namespace ArnotOnboarding.Models
{
    /// <summary>
    /// Represents the full data set for one new user onboarding request.
    /// All field names use camelCase JSON keys for machine readability.
    /// </summary>
    public class OnboardingRecord
    {
        // ── Meta ────────────────────────────────────────────────────
        public string RecordId        { get; set; } = Guid.NewGuid().ToString();
        public string SchemaVersion   { get; set; } = "1.0";
        public string Status          { get; set; } = "draft"; // "draft" | "finalized"
        public string CustomerProfile { get; set; } = "ArnotRealty";
        public DateTime CreatedAt     { get; set; } = DateTime.Now;
        public DateTime? FinalizedAt  { get; set; }
        public DateTime LastModified  { get; set; } = DateTime.Now;

        /// <summary>Full path to the exported PDF on the network share. Set on finalization.</summary>
        public string ExportedPdfPath  { get; set; }

        /// <summary>Full path to the exported JSON on the network share. Set on finalization.</summary>
        public string ExportedJsonPath { get; set; }

        // ── Page 01 — Employee Name (Wizard Entry) ─────────────────
        public string EmployeeFirstName { get; set; } = string.Empty;
        public string EmployeeLastName  { get; set; } = string.Empty;

        // ── Page 02 — Scheduling ───────────────────────────────────
        public DateTime? StartDate           { get; set; }
        public DateTime? AppointmentDate     { get; set; }
        public TimeSpan? AppointmentTime     { get; set; }
        public string   SchedulingNotes      { get; set; } = string.Empty;

        // ── Page 03 — User Information ─────────────────────────────
        // (First/Last also written here from page 01 for self-containment)
        public string Title          { get; set; } = string.Empty;
        public string Department     { get; set; } = string.Empty;
        public string DirectReportsTo { get; set; } = string.Empty;
        public string OfficeLocation { get; set; } = string.Empty;
        public string WorkPhone      { get; set; } = string.Empty;
        public string CellPhone      { get; set; } = string.Empty;

        /// <summary>Primary email. Auto-generated from name; synced with email page field.</summary>
        public string EmailAddress   { get; set; } = string.Empty;

        /// <summary>True if the auto-generated email was overridden manually.</summary>
        public bool EmailOverridden  { get; set; } = false;

        // ── Page 04 — Requestor Information ────────────────────────
        public string RequestorName   { get; set; } = string.Empty;
        public string RequestorTitle  { get; set; } = string.Empty;
        public string RequestorPhone  { get; set; } = string.Empty;
        public string RequestorEmail  { get; set; } = string.Empty;
        public DateTime? RequestDate  { get; set; }

        // ── Page 05 — Account Setup (Steps 4–7) ────────────────────
        public bool NewAccount            { get; set; } = false;
        public bool ModifyExistingAccount { get; set; } = false;
        public bool CopyPermissions       { get; set; } = false;  // Step 5 radio
        public string CopyFromUser        { get; set; } = string.Empty; // Step 6
        public string DomainUsername      { get; set; } = string.Empty; // Step 7a
        public string InitialPassword     { get; set; } = string.Empty; // Step 7b
        public bool ForcePasswordChange   { get; set; } = true;          // Step 7c radio

        // ── Page 06 — Email Setup (Step 8) ─────────────────────────
        // EmailAddress is shared with Page 03 — the same property is used.
        public string EmailPassword       { get; set; } = string.Empty; // Step 8b
        public string EmailLicenseType    { get; set; } = string.Empty; // Step 8c
        public bool   NewMailbox          { get; set; } = true;          // Step 8d (true=New, false=Existing)

        /// <summary>Step 21a — one email address per line.</summary>
        public string DistributionLists   { get; set; } = string.Empty;

        /// <summary>Step 22a — one shared mailbox per line.</summary>
        public string SharedMailboxes     { get; set; } = string.Empty;

        /// <summary>Step 25a — one delegate per line.</summary>
        public string CalendarDelegates   { get; set; } = string.Empty;

        // ── Page 07 — Applications (Step 9) ────────────────────────
        /// <summary>List of selected application names. Populated from CustomerProfile.ApplicationsList.</summary>
        public List<string> SelectedApplications { get; set; } = new List<string>();

        // ── Page 08 — Computer Setup (Steps 10–14) ─────────────────
        public bool   NewComputer          { get; set; } = true; // Step 10 radio (true=New, false=Existing)
        public string ExistingComputerName { get; set; } = string.Empty; // Step 12b
        public string Printers             { get; set; } = string.Empty; // Step 13a
        public int    MonitorCount         { get; set; } = 1;             // Step 14 radio (1 or 2)
        public string Monitor1Type         { get; set; } = string.Empty;
        public string Monitor2Type         { get; set; } = string.Empty;

        // ── Page 09 — Remote Access (Steps 15–16) ──────────────────
        public bool   VpnRequired     { get; set; } = false; // Step 15a radio
        public string VpnUsername     { get; set; } = string.Empty; // Step 15b
        public string VpnType         { get; set; } = string.Empty; // Step 15c radio
        public string Monitor1Config  { get; set; } = string.Empty; // Step 15d monitor 1
        public string Monitor2Config  { get; set; } = string.Empty; // Step 15d monitor 2

        /// <summary>Step 16 — selected remote desktop options.</summary>
        public List<string> RemoteDesktopOptions { get; set; } = new List<string>();

        // ── Page 10 — Software & Access Rights (Steps 17–18) ───────
        /// <summary>Step 17a selected items.</summary>
        public List<string> SoftwareAccess  { get; set; } = new List<string>();

        /// <summary>Step 18a selected items.</summary>
        public List<string> AccessRights    { get; set; } = new List<string>();

        // ── Page 11 — Additional Access & Security (Steps 19–20) ───
        /// <summary>Step 19 selected items.</summary>
        public List<string> AdditionalAccess  { get; set; } = new List<string>();

        /// <summary>Step 20 selected items.</summary>
        public List<string> SecurityOptions   { get; set; } = new List<string>();

        // ── Page 12 — Office Telephone ──────────────────────────────
        public bool   DeskPhoneRequired { get; set; } = false;
        public string Extension         { get; set; } = string.Empty;
        public string PhoneModel        { get; set; } = string.Empty;
        public List<string> VoicemailSetupOptions { get; set; } = new List<string>();

        // ── Page 12 (cont.) — Mobile Device ────────────────────────
        public string MobileDeviceType { get; set; } = string.Empty;
        public string MobileNumber     { get; set; } = string.Empty;
        public string MobileCarrier    { get; set; } = string.Empty;
        public bool   MdmEnrollment    { get; set; } = false; // Step 31 Yes/No
        public string MdmNotes         { get; set; } = string.Empty;

        // ── Page 13 — Miscellaneous Notes ──────────────────────────
        public string MiscNotes { get; set; } = string.Empty;

        // ── Computed Helpers (not serialized) ───────────────────────
        /// <summary>Returns the display name "LastName, FirstName" for list views and PDF headers.</summary>
        [Newtonsoft.Json.JsonIgnore]
        public string DisplayName =>
            string.IsNullOrWhiteSpace(EmployeeLastName)
                ? EmployeeFirstName
                : $"{EmployeeLastName}, {EmployeeFirstName}";

        /// <summary>Returns the full name "FirstName LastName".</summary>
        [Newtonsoft.Json.JsonIgnore]
        public string FullName =>
            $"{EmployeeFirstName} {EmployeeLastName}".Trim();

        /// <summary>True if this record has been exported to the network share.</summary>
        [Newtonsoft.Json.JsonIgnore]
        public bool IsExported => !string.IsNullOrEmpty(ExportedPdfPath);
    }
}
