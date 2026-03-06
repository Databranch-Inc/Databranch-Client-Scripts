// =============================================================
// ArnotOnboardingUtility — Models/SessionIndex.cs
// Version    : 1.0.0.0
// Author     : Sam Kirsch / Databranch
// Created    : 2026-02-28
// Modified   : 2026-02-28
// Description: Lightweight session index persisted alongside
//              session files. Drives the LandingView "Continue"
//              recent sessions list without reading every full
//              session JSON on startup.
// =============================================================
using System;
using System.Collections.Generic;
using Newtonsoft.Json;

namespace ArnotOnboardingUtility.Models
{
    /// <summary>Summary row for one session, stored in the index file.</summary>
    public class SessionIndexEntry
    {
        [JsonProperty("recordId")]
        public string RecordId { get; set; } = "";

        [JsonProperty("employeeName")]
        public string EmployeeName { get; set; } = "";

        [JsonProperty("userType")]
        public string UserType { get; set; } = "Desktop";

        [JsonProperty("jsonSourcePath")]
        public string JsonSourcePath { get; set; } = "";

        [JsonProperty("currentStepIndex")]
        public int CurrentStepIndex { get; set; }

        [JsonProperty("totalSteps")]
        public int TotalSteps { get; set; }

        [JsonProperty("isComplete")]
        public bool IsComplete { get; set; }

        [JsonProperty("startedAt")]
        public DateTime StartedAt { get; set; }

        [JsonProperty("lastWorked")]
        public DateTime LastWorked { get; set; }

        // ── Computed Display Helpers ───────────────────────────────────

        [JsonIgnore]
        public string ProgressDisplay =>
            TotalSteps > 0
                ? $"Step {Math.Min(CurrentStepIndex + 1, TotalSteps)} of {TotalSteps}"
                : "Not started";

        [JsonIgnore]
        public string LastWorkedDisplay =>
            LastWorked == default
                ? "Never"
                : LastWorked.ToString("MMM d, yyyy h:mm tt");

        [JsonIgnore]
        public bool IsKiosk => UserType == "Kiosk";
    }

    /// <summary>Root object for the _index.json file.</summary>
    public class SessionIndex
    {
        [JsonProperty("entries")]
        public List<SessionIndexEntry> Entries { get; set; } = new List<SessionIndexEntry>();

        [JsonProperty("lastUpdated")]
        public DateTime LastUpdated { get; set; } = DateTime.Now;
    }
}
