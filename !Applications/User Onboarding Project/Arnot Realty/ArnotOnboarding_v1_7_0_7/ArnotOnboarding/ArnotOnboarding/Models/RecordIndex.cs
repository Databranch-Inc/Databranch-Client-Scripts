// =============================================================
// ArnotOnboarding — RecordIndex.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Index of all finalized and exported onboarding records.
//              Lives in %AppData% and is updated on every export.
//              Used by the Record Library view to browse past records.
//              Each entry stores the full path to the network JSON so
//              the app can open it even if the folder structure changes.
// =============================================================

using System;
using System.Collections.Generic;

namespace ArnotOnboarding.Models
{
    /// <summary>Lightweight summary of one finalized record for list display.</summary>
    public class RecordIndexEntry
    {
        public string   RecordId        { get; set; }
        public string   EmployeeName    { get; set; }  // "LastName, FirstName"
        public string   Department      { get; set; }
        public DateTime FinalizedAt     { get; set; }
        public DateTime? StartDate      { get; set; }

        /// <summary>Full path to the exported JSON on the network share.</summary>
        public string   JsonPath        { get; set; }

        /// <summary>Full path to the exported PDF on the network share.</summary>
        public string   PdfPath         { get; set; }

        /// <summary>True if this index entry has been confirmed to exist on disk recently.</summary>
        public bool     LastVerified    { get; set; } = false;
        public DateTime? LastVerifiedAt { get; set; }
    }

    /// <summary>Root container for the record index file.</summary>
    public class RecordIndex
    {
        public string SchemaVersion            { get; set; } = "1.0";
        public List<RecordIndexEntry> Entries  { get; set; } = new List<RecordIndexEntry>();
    }
}
