// =============================================================
// ArnotOnboarding — LockFile.cs
// Version    : 1.1.0.0
// Author     : Sam Kirsch
// Company    : Databranch
// Created    : 2026-02-22
// Modified   : 2026-02-28
// Description: Represents the data written to a .lock sidecar file
//              next to a finalized network record being edited.
//              Prevents concurrent edits by multiple users.
//
// v1.1.0.0 — Added LockedByUser (Windows account name, separate from
//             the display name in LockedBy) so the lock banner can
//             report both the friendly name and the Windows login.
//             Added FriendlyDescription computed property for UI display.
// =============================================================

using System;
using Newtonsoft.Json;

namespace ArnotOnboarding.Models
{
    public class LockFile
    {
        /// <summary>The OnboardingRecord.RecordId this lock applies to.</summary>
        public string RecordId { get; set; }

        /// <summary>
        /// The requestor profile display name of the person who locked the record
        /// (from AppSettings.Requestor.Name). This is the human-readable name shown
        /// to other users: "Sam Kirsch is currently editing this record."
        /// </summary>
        public string LockedBy { get; set; }

        /// <summary>
        /// The Windows machine name (Environment.MachineName).
        /// Used with LockedByUser to identify ownership for same-session re-use.
        /// </summary>
        public string LockedByMachine { get; set; }

        /// <summary>
        /// The Windows account name (Environment.UserName) of the locking session.
        /// Shown alongside LockedBy so admins can identify the exact workstation login.
        /// </summary>
        public string LockedByUser { get; set; }

        /// <summary>UTC timestamp when the lock was created or last refreshed.</summary>
        public DateTime LockedAt { get; set; } = DateTime.UtcNow;

        // ── Computed (not serialized) ─────────────────────────────────

        /// <summary>Locks older than this are considered abandoned and overridable.</summary>
        public static readonly TimeSpan StaleThreshold = TimeSpan.FromHours(2);

        [JsonIgnore]
        public bool IsStale => DateTime.UtcNow - LockedAt > StaleThreshold;

        /// <summary>
        /// Human-readable age string for display in the override confirmation dialog.
        /// </summary>
        [JsonIgnore]
        public string AgeDescription
        {
            get
            {
                var age = DateTime.UtcNow - LockedAt;
                if (age.TotalSeconds < 90) return "just now";
                if (age.TotalMinutes < 60) return $"{(int)age.TotalMinutes} minutes ago";
                if (age.TotalHours   < 24) return $"{(int)age.TotalHours} hours ago";
                return $"{(int)age.TotalDays} days ago";
            }
        }

        /// <summary>
        /// One-line description for tooltips and dialogs:
        /// "Sam Kirsch (DATABRANCH-SAM · samk) — locked 12 minutes ago"
        /// </summary>
        [JsonIgnore]
        public string FriendlyDescription
        {
            get
            {
                string who  = !string.IsNullOrWhiteSpace(LockedBy) ? LockedBy : LockedByUser ?? "Unknown";
                string acct = !string.IsNullOrWhiteSpace(LockedByUser)    ? LockedByUser    : string.Empty;
                string mach = !string.IsNullOrWhiteSpace(LockedByMachine) ? LockedByMachine : string.Empty;

                string detail = string.Empty;
                if (!string.IsNullOrEmpty(mach) && !string.IsNullOrEmpty(acct))
                    detail = $" ({mach} · {acct})";
                else if (!string.IsNullOrEmpty(mach))
                    detail = $" ({mach})";

                return $"{who}{detail} — locked {AgeDescription}";
            }
        }

        /// <summary>
        /// Short name shown in the nav warning banner:
        /// "Sam Kirsch" or falls back to Windows user.
        /// </summary>
        [JsonIgnore]
        public string DisplayName
            => !string.IsNullOrWhiteSpace(LockedBy) ? LockedBy : LockedByUser ?? "Unknown";
    }
}
