// =============================================================
// ArnotOnboarding — DraftIndex.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Index of all local in-progress draft records.
//              Stored alongside the draft files in %AppData%\Drafts\.
// =============================================================

using System;
using System.Collections.Generic;

namespace ArnotOnboarding.Models
{
    /// <summary>Lightweight summary of one draft for display in the In Progress list.</summary>
    public class DraftIndexEntry
    {
        public string   RecordId      { get; set; }
        public string   EmployeeName  { get; set; }  // "LastName, FirstName" or just first if last missing
        public DateTime CreatedAt     { get; set; }
        public DateTime LastModified  { get; set; }
        public string   DraftFilePath { get; set; }  // Full path to the draft JSON
        public int      LastPageIndex { get; set; } = 0; // Which wizard page was active on last save
    }

    /// <summary>Root container for the draft index file.</summary>
    public class DraftIndex
    {
        public string SchemaVersion     { get; set; } = "1.0";
        public List<DraftIndexEntry> Entries { get; set; } = new List<DraftIndexEntry>();
    }
}
