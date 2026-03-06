// =============================================================
// ArnotOnboarding — OnboardingRecord.cs
// Version    : 1.3.0.0
// Author     : Sam Kirsch / Databranch
// Description: Central data model. All wizard page fields mapped
//              to typed properties. Mirrors the Arnot Realty
//              New User IT Request Form exactly (Steps 1-35).
// Schema     : 1.3
// =============================================================

using System;
using System.Collections.Generic;
using Newtonsoft.Json;

namespace ArnotOnboarding.Models
{
    // ── Nested model for Step 9 Other Accounts grid ──────────────
    public class OtherAccountState
    {
        public string Name            { get; set; } = string.Empty;
        public bool   AccountRequired { get; set; }
        public bool   AdminRights     { get; set; }
        public bool   InviteOnly      { get; set; }
        public bool   MatchDomain     { get; set; }
        public bool   MatchMS365      { get; set; }
    }

    public class OnboardingRecord
    {
        // ── Record metadata ───────────────────────────────────────
        [JsonProperty("recordId")]
        public string RecordId { get; set; } = Guid.NewGuid().ToString("N");

        [JsonProperty("schemaVersion")]
        public string SchemaVersion { get; set; } = "1.3";

        [JsonProperty("createdAt")]
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        [JsonProperty("lastModified")]
        public DateTime LastModified { get; set; } = DateTime.UtcNow;

        [JsonProperty("status")]
        public string Status { get; set; } = "draft";

        [JsonProperty("isExported")]
        public bool IsExported { get; set; } = false;

        [JsonProperty("exportedAt")]
        public DateTime? ExportedAt { get; set; }

        [JsonProperty("exportJsonPath")]
        public string ExportJsonPath { get; set; } = string.Empty;

        [JsonProperty("exportPdfPath")]
        public string ExportPdfPath  { get; set; } = string.Empty;

        /// <summary>
        /// If this record was restarted from a finalized record, stores the
        /// original record's ID. Blank for fresh onboardings.
        /// </summary>
        [JsonProperty("restartedFromRecordId")]
        public string RestartedFromRecordId { get; set; } = string.Empty;

        [JsonProperty("restartedAt")]
        public DateTime? RestartedAt { get; set; }

        // ── Section 1 — Request ───────────────────────────────────
        [JsonProperty("completedByDate")]
        public DateTime? CompletedByDate { get; set; }

        [JsonProperty("completedByTime")]
        public TimeSpan? CompletedByTime { get; set; }

        [JsonProperty("setupAppointmentDate")]
        public DateTime? SetupAppointmentDate { get; set; }

        [JsonProperty("setupAppointmentTime")]
        public TimeSpan? SetupAppointmentTime { get; set; }

        // ── Section 2 — User Information ─────────────────────────
        [JsonProperty("employeeFirstName")]
        public string EmployeeFirstName  { get; set; } = string.Empty;

        [JsonProperty("employeeLastName")]
        public string EmployeeLastName   { get; set; } = string.Empty;

        [JsonProperty("emailAddress")]
        public string EmailAddress       { get; set; } = string.Empty;

        [JsonProperty("emailOverridden")]
        public bool   EmailOverridden    { get; set; }

        [JsonProperty("workPhone")]
        public string WorkPhone          { get; set; } = string.Empty;

        [JsonProperty("extension")]
        public string Extension          { get; set; } = string.Empty;

        [JsonProperty("officeLocation")]
        public string OfficeLocation     { get; set; } = string.Empty;

        [JsonProperty("title")]
        public string Title              { get; set; } = string.Empty;

        [JsonProperty("department")]
        public string Department         { get; set; } = string.Empty;

        [JsonProperty("primaryComputerName")]
        public string PrimaryComputerName { get; set; } = string.Empty;

        // ── Section 3 — Requestor Information ────────────────────
        [JsonProperty("requestorName")]
        public string RequestorName      { get; set; } = string.Empty;

        [JsonProperty("requestorEmail")]
        public string RequestorEmail     { get; set; } = string.Empty;

        [JsonProperty("requestorPhone")]
        public string RequestorPhone     { get; set; } = string.Empty;

        [JsonProperty("requestorExtension")]
        public string RequestorExtension { get; set; } = string.Empty;

        // ── Steps 4-5 — Accounts & License ───────────────────────
        [JsonProperty("accountDomain")]
        public bool   AccountDomain           { get; set; }

        [JsonProperty("accountMS365")]
        public bool   AccountMS365            { get; set; }

        [JsonProperty("licenseBusinessStandard")]
        public bool   LicenseBusinessStandard { get; set; }

        [JsonProperty("licenseKiosk")]
        public bool   LicenseKiosk            { get; set; }

        // ── Step 6 — Local Admin ──────────────────────────────────
        [JsonProperty("localAdminRights")]
        public bool LocalAdminRights { get; set; }

        // ── Step 7 — Domain Credentials ──────────────────────────
        [JsonProperty("domainUsername")]
        public string DomainUsername          { get; set; } = string.Empty;

        [JsonProperty("domainUsernameCustomized")]
        public bool   DomainUsernameCustomized { get; set; } = false;
        public bool   EmailCustomized          { get; set; } = false;

        [JsonProperty("recordIsNew")]
        public bool   RecordIsNew { get; set; } = true;   // True until first SaveData on Page4

        [JsonProperty("domainTempPassword")]
        public string DomainTempPassword      { get; set; } = string.Empty;

        [JsonProperty("domainForcePasswordChange")]
        public bool   DomainForcePasswordChange { get; set; } = true;

        // ── Step 8 — MS365 Credentials ───────────────────────────
        [JsonProperty("ms365Username")]
        public string MS365Username           { get; set; } = string.Empty;

        [JsonProperty("ms365TempPassword")]
        public string MS365TempPassword       { get; set; } = string.Empty;

        [JsonProperty("ms365ForcePasswordChange")]
        public bool   MS365ForcePasswordChange { get; set; } = true;

        [JsonProperty("runCalendarScript")]
        public bool   RunCalendarScript       { get; set; }

        // ── Step 9 — Other Accounts ───────────────────────────────
        [JsonProperty("otherAccounts")]
        public Dictionary<string, OtherAccountState> OtherAccounts { get; set; }
            = new Dictionary<string, OtherAccountState>();

        [JsonProperty("otherAccount1")]
        public OtherAccountState OtherAccount1 { get; set; } = new OtherAccountState();

        [JsonProperty("otherAccount2")]
        public OtherAccountState OtherAccount2 { get; set; } = new OtherAccountState();

        [JsonProperty("otherAccount3")]
        public OtherAccountState OtherAccount3 { get; set; } = new OtherAccountState();

        public OtherAccountState GetOtherAccountState(string name)
        {
            OtherAccountState st;
            if (OtherAccounts.TryGetValue(name, out st)) return st;
            return new OtherAccountState { Name = name };
        }

        public void SetOtherAccountState(string name, OtherAccountState state)
        {
            OtherAccounts[name] = state;
        }

        // ── Steps 10-15 — Computer ────────────────────────────────
        [JsonProperty("computerExisting")]
        public bool   ComputerExisting        { get; set; }

        [JsonProperty("resetToFactory")]
        public bool   ResetToFactory          { get; set; }

        [JsonProperty("existingComputerName")]
        public string ExistingComputerName    { get; set; } = string.Empty;

        [JsonProperty("renameComputer")]
        public bool   RenameComputer          { get; set; }

        [JsonProperty("computerNewName")]
        public string ComputerNewName         { get; set; } = string.Empty;

        [JsonProperty("relocateComputer")]
        public bool   RelocateComputer        { get; set; }

        [JsonProperty("computerCurrentLocation")]
        public string ComputerCurrentLocation { get; set; }
        public string ComputerNewLocation     { get; set; } = string.Empty;

        [JsonProperty("dockingStationRequired")]
        public bool   DockingStationRequired  { get; set; }

        [JsonProperty("dockingCompatible")]
        public bool   DockingCompatible       { get; set; }

        [JsonProperty("dockTypeUSBC")]
        public bool   DockTypeUSBC            { get; set; }

        [JsonProperty("additionalMonitors")]
        public bool   AdditionalMonitors      { get; set; }

        [JsonProperty("monitorCount")]
        public int    MonitorCount            { get; set; } = 1;

        [JsonProperty("monitorSizes")]
        public string MonitorSizes            { get; set; } = string.Empty;

        [JsonProperty("monitor1New")]      public bool Monitor1New      { get; set; }
        [JsonProperty("monitor1Existing")] public bool Monitor1Existing { get; set; }
        [JsonProperty("monitor2New")]      public bool Monitor2New      { get; set; }
        [JsonProperty("monitor2Existing")] public bool Monitor2Existing { get; set; }
        [JsonProperty("monitor1Connector")] public string Monitor1Connector { get; set; } = "VGA";
        [JsonProperty("monitor2Connector")] public string Monitor2Connector { get; set; } = "VGA";

        // ── Step 16 — Applications ────────────────────────────────
        [JsonProperty("applications")]
        public List<string> Applications { get; set; } = new List<string>();

        [JsonProperty("applicationOther1")]
        public string ApplicationOther1 { get; set; } = string.Empty;

        [JsonProperty("applicationOther2")]
        public string ApplicationOther2 { get; set; } = string.Empty;

        [JsonProperty("applicationOther3")]
        public string ApplicationOther3 { get; set; } = string.Empty;

        // ── Steps 17-18 — Print & Scan ───────────────────────────
        [JsonProperty("printersRequired")]
        public bool PrintersRequired     { get; set; }

        [JsonProperty("printer17Main")]      public bool Printer17Main      { get; set; }
        [JsonProperty("printer17Stillwater")] public bool Printer17Stillwater { get; set; }
        [JsonProperty("printer17Other")]     public bool Printer17Other     { get; set; }
        [JsonProperty("printer17Ironworks")] public bool Printer17Ironworks { get; set; }

        [JsonProperty("scanToFolder")]
        public bool ScanToFolder         { get; set; }

        [JsonProperty("scanner18Main")]      public bool Scanner18Main      { get; set; }
        [JsonProperty("scanner18Stillwater")] public bool Scanner18Stillwater { get; set; }
        [JsonProperty("scanner18Other")]     public bool Scanner18Other     { get; set; }
        [JsonProperty("scanner18Ironworks")] public bool Scanner18Ironworks { get; set; }

        // ── Step 19 — Mapped Drives ───────────────────────────────
        [JsonProperty("driveR")] public bool DriveR { get; set; }
        [JsonProperty("driveQ")] public bool DriveQ { get; set; }
        [JsonProperty("driveK")] public bool DriveK { get; set; }
        [JsonProperty("driveS")] public bool DriveS { get; set; }

        // ── Step 20 — Shared Folders ──────────────────────────────
        [JsonProperty("sharedFolderR")]
        public List<string> SharedFolderR { get; set; } = new List<string>();

        [JsonProperty("sharedFolderQ")]
        public List<string> SharedFolderQ { get; set; } = new List<string>();

        // ── Steps 21-25 — Email ───────────────────────────────────
        [JsonProperty("sharedMailboxes21")]
        public bool   SharedMailboxes21   { get; set; }

        [JsonProperty("sharedMailboxList")]
        public string SharedMailboxList   { get; set; } = string.Empty;

        [JsonProperty("distributionLists22")]
        public bool   DistributionLists22 { get; set; }

        [JsonProperty("distributionListText")]
        public string DistributionListText { get; set; } = string.Empty;

        [JsonProperty("emailAliases25")]
        public bool   EmailAliases25      { get; set; }

        [JsonProperty("emailAliasesList")]
        public string EmailAliasesList    { get; set; } = string.Empty;

        // ── Steps 26-29 — Office Telephone ───────────────────────
        [JsonProperty("phoneExisting")]
        public bool   PhoneExisting        { get; set; }

        [JsonProperty("phoneRelocate")]
        public bool   PhoneRelocate        { get; set; }

        [JsonProperty("phoneCurrentLocation")]
        public string PhoneCurrentLocation { get; set; } = string.Empty;

        [JsonProperty("extensionChange")]
        public bool   ExtensionChange      { get; set; }

        [JsonProperty("vmPin")]
        public string VmPin               { get; set; } = string.Empty;

        // ── Step 30 — Mobile — Phone ──────────────────────────────
        [JsonProperty("phoneIssued")]
        public bool   PhoneIssued         { get; set; }

        [JsonProperty("phoneModel")]
        public string PhoneModel          { get; set; } = string.Empty;

        [JsonProperty("phoneNumber")]
        public string PhoneNumber         { get; set; } = string.Empty;

        [JsonProperty("phoneDeviceExisting")]
        public bool   PhoneDeviceExisting { get; set; }

        // ── Step 30 — Mobile — iPad ───────────────────────────────
        [JsonProperty("iPadIssued")]
        public bool   iPadIssued         { get; set; }

        [JsonProperty("iPadModel")]
        public string iPadModel          { get; set; } = string.Empty;

        [JsonProperty("iPadNumber")]
        public string iPadNumber         { get; set; } = string.Empty;

        [JsonProperty("iPadDeviceExisting")]
        public bool   iPadDeviceExisting { get; set; }

        // ── Notes ─────────────────────────────────────────────────
        [JsonProperty("miscNotes")]
        public string MiscNotes { get; set; } = string.Empty;

        // ── Computed helpers ──────────────────────────────────────
        [JsonIgnore]
        public string FullName => string.IsNullOrEmpty(EmployeeLastName)
            ? EmployeeFirstName
            : EmployeeFirstName + " " + EmployeeLastName;

        [JsonIgnore]
        public string DisplayName => string.IsNullOrWhiteSpace(FullName) ? "(No Name)" : FullName;
    }
}
