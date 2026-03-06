// =============================================================
// ArnotOnboarding — DraftIndex.cs
// Version    : 1.1.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-28
// Description: Index of all local in-progress draft records.
//              Stored alongside the draft files in
//              %AppData%\Databranch\ArnotOnboarding\Drafts\.
//
// v1.1.0.0 — Added SourceJsonPath: the full UNC/mapped path to the
//             finalized network JSON that this draft was restarted
//             from. Populated only for drafts created via
//             Restart Onboarding; empty for brand-new drafts.
//             Used by LockManager to know which .lock file to
//             release when the draft is finalized or deleted.
//             Also used by the nav warning banner to count and
//             report how many completed records are locked by
//             this session.
// =============================================================

using System;
using System.Collections.Generic;

namespace ArnotOnboarding.Models
{
    /// <summary>Lightweight summary of one draft for display in the In Progress list.</summary>
    public class DraftIndexEntry
    {
        public string   RecordId      { get; set; }

        /// <summary>"LastName, FirstName" or just first name if last is missing.</summary>
        public string   EmployeeName  { get; set; }

        public DateTime CreatedAt     { get; set; }
        public DateTime LastModified  { get; set; }

        /// <summary>Full local path to the draft JSON in %AppData%\...\Drafts\.</summary>
        public string   DraftFilePath { get; set; }

        /// <summary>Which wizard page was active when the draft was last saved.</summary>
        public int      LastPageIndex { get; set; } = 0;

        /// <summary>
        /// Full path (UNC or mapped drive) to the original finalized network JSON
        /// that this draft was created from via Restart Onboarding.
        /// Empty string for brand-new drafts.
        /// When non-empty, a .lock sidecar exists at SourceJsonPath + ".lock"
        /// and must be released when this draft is finalized or deleted.
        /// </summary>
        public string   SourceJsonPath { get; set; } = string.Empty;

        /// <summary>True if this draft has an active lock on a network file.</summary>
        [Newtonsoft.Json.JsonIgnore]
        public bool HasNetworkLock => !string.IsNullOrEmpty(SourceJsonPath);
    }

    /// <summary>Root container for the draft index file.</summary>
    public class DraftIndex
    {
        public string SchemaVersion          { get; set; } = "1.1";
        public List<DraftIndexEntry> Entries { get; set; } = new List<DraftIndexEntry>();
    }
}
