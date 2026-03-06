// =============================================================
// ArnotOnboardingUtility — Models/OnboardingRecord.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Read-only deserialization target for the
//              ArnotOnboarding schemaVersion 1.3 JSON export.
//              All properties are set by Newtonsoft.Json only.
//              This tool never writes to this model.
// =============================================================
using System;
using System.Collections.Generic;
using Newtonsoft.Json;

namespace ArnotOnboardingUtility.Models
{
    /// <summary>
    /// Represents a single other-account entry within the otherAccounts dictionary.
    /// </summary>
    public class OtherAccountEntry
    {
        [JsonProperty("Name")]
        public string Name { get; set; } = "";

        [JsonProperty("AccountRequired")]
        public bool AccountRequired { get; set; }

        [JsonProperty("AdminRights")]
        public bool AdminRights { get; set; }

        [JsonProperty("InviteOnly")]
        public bool InviteOnly { get; set; }

        [JsonProperty("MatchDomain")]
        public bool MatchDomain { get; set; }

        [JsonProperty("MatchMS365")]
        public bool MatchMS365 { get; set; }
    }

    /// <summary>
    /// Full deserialization model for schemaVersion 1.3 onboarding JSON records
    /// produced by the ArnotOnboarding HR application. Read-only in this tool.
    /// </summary>
    public class OnboardingRecord
    {
        // ── Meta ──────────────────────────────────────────────────────
        [JsonProperty("recordId")]
        public string RecordId { get; set; } = "";

        [JsonProperty("schemaVersion")]
        public string SchemaVersion { get; set; } = "";

        [JsonProperty("status")]
        public string Status { get; set; } = "";

        [JsonProperty("createdAt")]
        public DateTime CreatedAt { get; set; }

        [JsonProperty("lastModified")]
        public DateTime LastModified { get; set; }

        [JsonProperty("isExported")]
        public bool IsExported { get; set; }

        [JsonProperty("exportedAt")]
        public DateTime? ExportedAt { get; set; }

        [JsonProperty("exportJsonPath")]
        public string ExportJsonPath { get; set; } = "";

        [JsonProperty("exportPdfPath")]
        public string ExportPdfPath { get; set; } = "";

        // ── Scheduling ────────────────────────────────────────────────
        [JsonProperty("completedByDate")]
        public DateTime? CompletedByDate { get; set; }

        [JsonProperty("completedByTime")]
        public string CompletedByTime { get; set; } = "";

        [JsonProperty("setupAppointmentDate")]
        public DateTime? SetupAppointmentDate { get; set; }

        [JsonProperty("setupAppointmentTime")]
        public string SetupAppointmentTime { get; set; } = "";

        // ── Employee ──────────────────────────────────────────────────
        [JsonProperty("employeeFirstName")]
        public string EmployeeFirstName { get; set; } = "";

        [JsonProperty("employeeLastName")]
        public string EmployeeLastName { get; set; } = "";

        [JsonProperty("emailAddress")]
        public string EmailAddress { get; set; } = "";

        [JsonProperty("emailOverridden")]
        public bool EmailOverridden { get; set; }

        [JsonProperty("workPhone")]
        public string WorkPhone { get; set; } = "";

        [JsonProperty("extension")]
        public string Extension { get; set; } = "";

        [JsonProperty("officeLocation")]
        public string OfficeLocation { get; set; } = "";

        [JsonProperty("title")]
        public string Title { get; set; } = "";

        [JsonProperty("department")]
        public string Department { get; set; } = "";

        [JsonProperty("primaryComputerName")]
        public string PrimaryComputerName { get; set; } = "";

        // ── Requestor ─────────────────────────────────────────────────
        [JsonProperty("requestorName")]
        public string RequestorName { get; set; } = "";

        [JsonProperty("requestorEmail")]
        public string RequestorEmail { get; set; } = "";

        [JsonProperty("requestorPhone")]
        public string RequestorPhone { get; set; } = "";

        [JsonProperty("requestorExtension")]
        public string RequestorExtension { get; set; } = "";

        // ── Account Setup ─────────────────────────────────────────────
        [JsonProperty("accountDomain")]
        public bool AccountDomain { get; set; }

        [JsonProperty("accountMS365")]
        public bool AccountMS365 { get; set; }

        [JsonProperty("licenseBusinessStandard")]
        public bool LicenseBusinessStandard { get; set; }

        [JsonProperty("licenseKiosk")]
        public bool LicenseKiosk { get; set; }

        [JsonProperty("localAdminRights")]
        public bool LocalAdminRights { get; set; }

        [JsonProperty("domainUsername")]
        public string DomainUsername { get; set; } = "";

        [JsonProperty("domainTempPassword")]
        public string DomainTempPassword { get; set; } = "";

        [JsonProperty("domainForcePasswordChange")]
        public bool DomainForcePasswordChange { get; set; }

        [JsonProperty("ms365Username")]
        public string Ms365Username { get; set; } = "";

        [JsonProperty("ms365TempPassword")]
        public string Ms365TempPassword { get; set; } = "";

        [JsonProperty("ms365ForcePasswordChange")]
        public bool Ms365ForcePasswordChange { get; set; }

        [JsonProperty("runCalendarScript")]
        public bool RunCalendarScript { get; set; }

        // ── Other Accounts ────────────────────────────────────────────
        [JsonProperty("otherAccounts")]
        public Dictionary<string, OtherAccountEntry> OtherAccounts { get; set; }
            = new Dictionary<string, OtherAccountEntry>();

        [JsonProperty("otherAccount1")]
        public OtherAccountEntry OtherAccount1 { get; set; } = new OtherAccountEntry();

        [JsonProperty("otherAccount2")]
        public OtherAccountEntry OtherAccount2 { get; set; } = new OtherAccountEntry();

        [JsonProperty("otherAccount3")]
        public OtherAccountEntry OtherAccount3 { get; set; } = new OtherAccountEntry();

        // ── Computer Setup ────────────────────────────────────────────
        [JsonProperty("computerExisting")]
        public bool ComputerExisting { get; set; }

        [JsonProperty("resetToFactory")]
        public bool ResetToFactory { get; set; }

        [JsonProperty("existingComputerName")]
        public string ExistingComputerName { get; set; } = "";

        [JsonProperty("renameComputer")]
        public bool RenameComputer { get; set; }

        [JsonProperty("computerNewName")]
        public string ComputerNewName { get; set; } = "";

        [JsonProperty("relocateComputer")]
        public bool RelocateComputer { get; set; }

        [JsonProperty("computerCurrentLocation")]
        public string ComputerCurrentLocation { get; set; } = "";

        [JsonProperty("ComputerNewLocation")]
        public string ComputerNewLocation { get; set; } = "";

        [JsonProperty("dockingStationRequired")]
        public bool DockingStationRequired { get; set; }

        [JsonProperty("dockingCompatible")]
        public bool DockingCompatible { get; set; }

        [JsonProperty("dockTypeUSBC")]
        public bool DockTypeUSBC { get; set; }

        [JsonProperty("additionalMonitors")]
        public bool AdditionalMonitors { get; set; }

        [JsonProperty("monitorCount")]
        public int MonitorCount { get; set; }

        [JsonProperty("monitorSizes")]
        public string MonitorSizes { get; set; } = "";

        [JsonProperty("monitor1New")]
        public bool Monitor1New { get; set; }

        [JsonProperty("monitor1Existing")]
        public bool Monitor1Existing { get; set; }

        [JsonProperty("monitor2New")]
        public bool Monitor2New { get; set; }

        [JsonProperty("monitor2Existing")]
        public bool Monitor2Existing { get; set; }

        [JsonProperty("monitor1Connector")]
        public string Monitor1Connector { get; set; } = "";

        [JsonProperty("monitor2Connector")]
        public string Monitor2Connector { get; set; } = "";

        // ── Applications ──────────────────────────────────────────────
        [JsonProperty("applications")]
        public List<string> Applications { get; set; } = new List<string>();

        [JsonProperty("applicationOther1")]
        public string ApplicationOther1 { get; set; } = "";

        [JsonProperty("applicationOther2")]
        public string ApplicationOther2 { get; set; } = "";

        [JsonProperty("applicationOther3")]
        public string ApplicationOther3 { get; set; } = "";

        // ── Printing & Scanning ───────────────────────────────────────
        [JsonProperty("printersRequired")]
        public bool PrintersRequired { get; set; }

        [JsonProperty("printer17Main")]
        public bool Printer17Main { get; set; }

        [JsonProperty("printer17Stillwater")]
        public bool Printer17Stillwater { get; set; }

        [JsonProperty("printer17Other")]
        public bool Printer17Other { get; set; }

        [JsonProperty("printer17Ironworks")]
        public bool Printer17Ironworks { get; set; }

        [JsonProperty("scanToFolder")]
        public bool ScanToFolder { get; set; }

        [JsonProperty("scanner18Main")]
        public bool Scanner18Main { get; set; }

        [JsonProperty("scanner18Stillwater")]
        public bool Scanner18Stillwater { get; set; }

        [JsonProperty("scanner18Other")]
        public bool Scanner18Other { get; set; }

        [JsonProperty("scanner18Ironworks")]
        public bool Scanner18Ironworks { get; set; }

        // ── Drive / File Access ───────────────────────────────────────
        [JsonProperty("driveR")]
        public bool DriveR { get; set; }

        [JsonProperty("driveQ")]
        public bool DriveQ { get; set; }

        [JsonProperty("driveK")]
        public bool DriveK { get; set; }

        [JsonProperty("driveS")]
        public bool DriveS { get; set; }

        [JsonProperty("sharedFolderR")]
        public List<string> SharedFolderR { get; set; } = new List<string>();

        [JsonProperty("sharedFolderQ")]
        public List<string> SharedFolderQ { get; set; } = new List<string>();

        // ── Mailboxes / Distribution ──────────────────────────────────
        [JsonProperty("sharedMailboxes21")]
        public bool SharedMailboxes21 { get; set; }

        [JsonProperty("sharedMailboxList")]
        public string SharedMailboxList { get; set; } = "";

        [JsonProperty("distributionLists22")]
        public bool DistributionLists22 { get; set; }

        [JsonProperty("distributionListText")]
        public string DistributionListText { get; set; } = "";

        [JsonProperty("emailAliases25")]
        public bool EmailAliases25 { get; set; }

        [JsonProperty("emailAliasesList")]
        public string EmailAliasesList { get; set; } = "";

        // ── Phone ─────────────────────────────────────────────────────
        [JsonProperty("phoneExisting")]
        public bool PhoneExisting { get; set; }

        [JsonProperty("phoneRelocate")]
        public bool PhoneRelocate { get; set; }

        [JsonProperty("phoneCurrentLocation")]
        public string PhoneCurrentLocation { get; set; } = "";

        [JsonProperty("extensionChange")]
        public bool ExtensionChange { get; set; }

        [JsonProperty("vmPin")]
        public string VmPin { get; set; } = "";

        [JsonProperty("phoneIssued")]
        public bool PhoneIssued { get; set; }

        [JsonProperty("phoneModel")]
        public string PhoneModel { get; set; } = "";

        [JsonProperty("phoneNumber")]
        public string PhoneNumber { get; set; } = "";

        [JsonProperty("phoneDeviceExisting")]
        public bool PhoneDeviceExisting { get; set; }

        // ── iPad / Mobile ─────────────────────────────────────────────
        [JsonProperty("iPadIssued")]
        public bool IPadIssued { get; set; }

        [JsonProperty("iPadModel")]
        public string IPadModel { get; set; } = "";

        [JsonProperty("iPadNumber")]
        public string IPadNumber { get; set; } = "";

        [JsonProperty("iPadDeviceExisting")]
        public bool IPadDeviceExisting { get; set; }

        // ── Misc ──────────────────────────────────────────────────────
        [JsonProperty("miscNotes")]
        public string MiscNotes { get; set; } = "";

        // ── Computed Helpers ──────────────────────────────────────────

        /// <summary>Full name for display throughout the UI.</summary>
        [JsonIgnore]
        public string FullName => $"{EmployeeFirstName} {EmployeeLastName}".Trim();

        /// <summary>
        /// True when the record was marked finalized by HR.
        /// Only finalized records may be loaded by this utility.
        /// </summary>
        [JsonIgnore]
        public bool IsFinalized => Status?.Equals("finalized", StringComparison.OrdinalIgnoreCase) == true;

        /// <summary>
        /// True when this is a Kiosk/iPad user (no AD account, no PC setup).
        /// </summary>
        [JsonIgnore]
        public bool IsKioskUser => LicenseKiosk && !AccountDomain;

        /// <summary>
        /// Returns the AccountRequired flag for a named other-account entry.
        /// Safe — returns false if the key is not present.
        /// </summary>
        public bool OtherAccountRequired(string name)
        {
            return OtherAccounts != null
                && OtherAccounts.TryGetValue(name, out var entry)
                && entry.AccountRequired;
        }
    }
}
