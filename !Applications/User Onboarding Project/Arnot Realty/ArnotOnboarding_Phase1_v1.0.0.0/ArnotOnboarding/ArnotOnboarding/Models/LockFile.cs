// =============================================================
// ArnotOnboarding — LockFile.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-22
// Description: Represents the data written to a .lock sidecar file
//              next to a finalized network record being edited.
//              Prevents concurrent edits by multiple users.
// =============================================================

using System;

namespace ArnotOnboarding.Models
{
    public class LockFile
    {
        public string   RecordId    { get; set; }
        public string   LockedBy    { get; set; }   // Requestor name from profile
        public string   LockedByMachine { get; set; } // Environment.MachineName
        public string   LockedByUser    { get; set; } // Environment.UserName
        public DateTime LockedAt    { get; set; } = DateTime.UtcNow;

        /// <summary>Stale threshold — locks older than this are considered abandoned.</summary>
        public static readonly TimeSpan StaleThreshold = TimeSpan.FromHours(2);

        [Newtonsoft.Json.JsonIgnore]
        public bool IsStale => DateTime.UtcNow - LockedAt > StaleThreshold;

        [Newtonsoft.Json.JsonIgnore]
        public string AgeDescription
        {
            get
            {
                var age = DateTime.UtcNow - LockedAt;
                if (age.TotalMinutes < 2)  return "just now";
                if (age.TotalMinutes < 60) return $"{(int)age.TotalMinutes} minutes ago";
                if (age.TotalHours   < 24) return $"{(int)age.TotalHours} hours ago";
                return $"{(int)age.TotalDays} days ago";
            }
        }
    }
}
